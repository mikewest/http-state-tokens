# Explainer: Tightening HTTP State Management

## A Problem

Cookies allow the nominally stateless HTTP protocol to support stateful sessions, enabling practically
everything interesting on the web today. That said, cookies have some issues: they're hard to use
securely, they waste users' resources, and they enable tracking users' activity across the web in
potentially surprising ways.

**Security**: we've introduced a number of features over the years with the intent of providing
reasonable security properties to developers who care, but adoption is low to non-existent:

*   Cookies are available to JavaScript by default (via `document.cookie`), which enables a smooth
    upgrade from one-time XSS to theft of persistent credentials (and also makes cookies available
    to Spectre-like attacks on memory). Though the `HttpOnly` attribute was introduced well over a
    decade ago, only ~8.65% of cookies use it today.
    
*   Cookies are sent to non-secure origins by default, which enables trivial credential theft when
    you visit your local Evil But Delicious Coffee Shoppe™. The `Secure` attribute locks the cookie
    to secure origins, which is good! Still, only ~7.37% of cookies set in Chrome use it today.

*   Cookies are often delivered without any indication of the request's initiator, meaning that a
    server's own requests look identical to requests initiated by your good friends at
    `https://evil.com`. The `SameSite` attribute aims to mitigate the CSRF risk, but ~0.03% adoption
    is not inspiring.
    
Poorly-adopted mitigation attributes to the side, cookies simply don't match the security boundaries
we've decided to enforce for other kinds of web-accessible data. They flow across origins within a
given registrable domain (`domain=example.com`), they ignore ports and schemes (which means they can
be trivially forged by network attackers), and they can be narrowed to specific paths
(`path=/a/specific/subdirectory`). These characteristics make them difficult to reason about, and
create incentives to weaken the same-origin policy for other pieces of the platform ("Cookies get
away with being site-scoped! Why can't my feature?").

**Inefficiency**: Servers can (and do) store many cookies for a given registrable domain, and
many of those cookies may be sent along with any given HTTP request. Different vendors have different
limits, but they're all fairly high. Chrome, for example, allows ~180 cookies to be stored for each
registrable domain, which equates to ~724kB on disk. Happily(?), servers
[generally explode](http://homakov.blogspot.de/2014/01/cookie-bomb-or-lets-break-internet.html) if
that much data is sent in a request header. Abuse to the side, the practical overhead is huge: the
median `Cookie` request header is 444 bytes (unzipped), while the 90th percentile is ~1kB, the 95th
~2kB, and the 99th ~4kB (~0.1% are over 10kB, which is a lot).

**Privacy**: Cookies enable pervasive monitoring on the one hand (which I'm hopeful we can
address to some extent via mechanisms like those sketched out in
[cookies-over-http-bad](https://github.com/mikewest/cookies-over-http-bad)), and
not-entirely-pervasive tracking by entities that users might not know about on the other.

_Note: All the metrics noted above come from Chrome's telemetry data for March, 2018. I'd welcome
similar measurements from other vendors, but I'm assuming they'll be within the same order of
magnitude._


## A Proposal

Let's address the above concerns by giving developers a well-lit path towards security boundaries we
can defend. Developers can set a single token in an HTTP response header, perhaps:

<pre><code>Sec-HTTP-State: token=*<i>base64-encoded-value-goes-here</i>*, delivery="same-site"</code></pre>

The user agent will deliver this token back to the server as an HTTP request header, perhaps:

<pre><code>Sec-HTTP-State: token=*<i>base64-encoded-value-goes-here</i>*</code></pre>

At a glance, this looks a lot like a cookie. The differences are almost entirely in the constraints
applied. The token will:

*   The token will be available only to the network layer, not to JavaScript (though Service Workers
    might be a special case worth thinking about more deeply).

*   The user agent will store only one token per origin, and will limit the token's size to
    something reasonable (perhaps 128 bytes, which covers the status quo's ~20th percentile, and
    would be more than enough to hold a signed session identifier, plus a bit of metadata like a
    timestamp).

*   The user agent will not store tokens at all for non-secure origins. 

*   The token will be delivered only to same-site requests by default, with the option for
    developers to explicitly tighten that scope to same-origin requests, or loosen it to
    cross-site requests.

Coming back to the three prongs above, this proposal aims to create a state token whose
configuration is hardened, maps to the same security primitive as the rest of the platform, reduces
the client-side cost of transport, and isn't useful for cross-site tracking by default.

## Pivot Points

The proposal described above seems pretty reasonable to me, but I see it as the start of a
conversation. There are many variations that I hope we can explore together. In the hopes of kicking
that off, here are some I've considered:

### Just one token? Really?

An early variant of the proposal was built around setting two tokens: one sent with all requests,
and one which behaved like a cookie set with `SameSite=Strict`. Clever folks suggested adding
another, which would be sent only for same-origin requests. More clever folks had more ideas about
additional tokens which might be valuable to distinguish certain characteristics which might be
useful for CSRF mitigation and other purposes.

At the moment, I believe that something like the separate
[`Sec-Metadata`](https://github.com/mikewest/sec-metadata) proposal will give developers enough
granularity in the HTTP request to deal with these kinds of attacks without adding the complexity
of additional tokens. It also allows us to avoid the slippery slope from "Just one more token!" to
"Just ten more tokens!" that seems somehow inevietable. One token is simple to explain, simple to
use, and simple (theoretically, though I recognize not practically) to deploy.

### Server-controlled values?

This proposal puts the server in charge of the token's value, allowing developers to come up with
a storage and verification scheme that makes sense for their application. My intuition is that this
is the right place to start, giving developers the flexibility to map their existing authentication
cookies onto a new transport in a reasonably straightforward way, and to construct a
signing/verification mechanism that meets their needs.

That said, it might be interesting to explore an alternative in which the browser controls the value
entirely, generating a random identifier when visiting an origin for the first time, or in response
to something like `Sec-HTTP-State: token=0`. That concept has some interesting properties that are
probably worth looking into more deeply. We might, for instance, be able to push more developers
towards verifying signed values if we allowed them to set a key that browser would use to sign a
random value rather than setting the value itself.

### Mere reflection?

The current proposal follows in the footsteps of cookies, reflecting the server-set value back to
the server on each request exactly as it was set. This seems like the most straightforward story
to tell developers, and fits well with how folks think things work today.

That said, it might be interesting to explore more complicated relationships between the token's
value, and the value that's delivered to servers in the HTTP request. You could imagine, for
instance, sending a signed value including a timestamp and salt, padded out to a uniform length. Or
incorporating some [Cake](https://tools.ietf.org/html/draft-abarth-cake-00)- or
[Macaroon](https://ai.google/research/pubs/pub41892)-like HMACing to prove provenance. Or shifting
more radically to an OAuth style model where the server sets a long-lived token which the browser
exchanges on a regular basis for short-lived tokens.


## FAQ

### Wait. What? Are you saying we should deprecate cookies?

No! Of course not! That would be silly! Ha! Who would propose such a thing?


### You would, Mike. You would.

Ok, you got me. Cookies are bad and we should find a path towards deprecation. But that's going to
take some time.


### Is this new thing fundamentally different than a cookie?

TL;DR: No. But yes!

Developers can get almost all of the above properties by setting a cookie like
`__Host-token=value1; Secure; HttpOnly; SameSite=Lax; path=/`. That isn't a perfect analog (it
continues to ignore ports, for instance), but it's pretty good. My concern with the status is that
developers need to understand the impact of the various flags and naming convention in order to
choose it over `Set-Cookie: token=value`. Defaults matter, deeply, and this seems like the simplest
thing that could possibly work. It solidifies best practice into a thing-in-itself, rather than
attempting to guide developers through the four attributes they must use, the one attribute they
must not use, and the weird naming convention they need to adopt.

We also have the opportunity to reset the foundational assumption that server-side state is best
maintained on the client. I'll blithly assert that it is both more elegant and more respectful of
users' resources to migrate away towards small session identifiers, rather than oodles of key-value
pairs (though I expect healthy debate on that topic).


### How do you expect folks to migrate to this from cookies?

Slowly and gradually. User agents could begin by advertising support for the new hotness, perhaps
adding a `Sec-HTTP-State: ?` header to outgoing requests. Developers could begin using the new
mechanism for pieces of their authentication infrastructure that would most benefit from
origin-scoping, probably side-by-side with the existing cookie infrastructure. Over time, they
could build up a list of the client-side state they're relying on, and begin to construct a
server-side mapping between session identifiers and state. Once that mechanism was in place, state
could migrate to it in a piecemeal fashion.

Eventually, you could imagine giving developers the ability to migrate completely, turning cookies
off for their sites entirely (via Origin Manifests, for instance). Even more eventually, we could
ask developers to opt-into cookies rather than opting out.


### Won't this migration be difficult for origins that host multiple apps?

Yes, it will. That seems like both a bug and a feature. It would be better for origins and
applications to have more of a 1:1 relationship than they are today. There is no security boundary
between applications on the same origin, and there doesn't seem to me to be much value in pretending
that there is. Different applications ought to run on different origins, creating actual segregation
between their capabilities.

### Does this proposal constitute a material change in privacy properties?

Yes and no. Mostly no. That is, folks can still use these tokens to track users across origins, just
as they can with cookies today. There's a trivial hurdle insofar as folks would need to declare that
intent by setting the token's `delivery` member, and it's reasonable to expect user agents to react
to that declaration in some interesting ways, but in itself, there's little change in technical
capability.

Still, it has some advantages over the status quo. For example, these tokens can never be sent in
plaintext, which mitigates some risk of pervasive monitoring. Also, reasonable length and character
limitations restrict the amount of data which can be contained directly in the token, tilting the
field towards opaque identifiers linked to server-side state, as opposed to caching sensitive
information locally and exposing on the local disk, as well as to all the TLS-terminating endpoints
between you and the service you care about.
