# Explainer: Tightening HTTP State Management

forked from

[Mike West](https://github.com/mikewest/http-state-tokens), August 2018 to provide a pull request.

_Copyright statements are so nineties_

(_Note: This isn't a proposal that's well thought out, and stamped solidly with the Google Seal of
Approval. It's a collection of interesting ideas for discussion, nothing more, nothing less._)

(_Note: This is a pull request after fruitful discussions in Dagstuhl)

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
    decade ago, only ~8.31% of `Sec-Cookie` operations use it today.
    
*   Cookies are sent to non-secure origins by default, which enables trivial credential theft when
    you visit your local Evil But Delicious Coffee Shoppe™. The `Secure` attribute locks the cookie
    to secure origins, which is good! Still, only ~7.85% of `Set-Cookie` operations use it today.

*   Cookies are often delivered without any indication of the request's initiator, meaning that a
    server's own requests look identical to requests initiated by your good friends at
    `https://evil.com`. The `SameSite` attribute aims to mitigate the CSRF risk, but the fact that
    ~0.06% of `Set-Cookie` operations use it today is not inspiring.
    
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
median (uncompressed) `Cookie` request header is 409 bytes, while the 90th percentile is 1,589
bytes, the 95th 2,549 bytes, and the 99th 4,601 bytes (~0.1% of `Cookie` headers are over 10kB,
which is a lot of kB).

**Privacy**: Cookies enable pervasive monitoring on the one hand (which I'm hopeful we can
address to some extent by deprecating them over HTTP via mechanisms like those sketched out in
[cookies-over-http-bad](https://github.com/mikewest/cookies-over-http-bad)), and
not-entirely-pervasive tracking by entities that users might not know about on the other.

**Unkown Semantics**: One of the issues of the cookie identifiers is that their purpose is 
opaque to users. Many attempts were made to remedy the situation or to distinguish between 
good cookies and bad cookies. Namely, [P3P](https://www.w3.org/TR/P3P) tried to add 
semantics to data collection. In this case, the server side was creating the identifier 
to maintain state and explained the meaning in a P3P policy. P3P did not find wide adoption 
in practice, but influenced research quite significantly. 

_Note: All the metrics noted above come from Chrome's telemetry data for July, 2018. I'd welcome
similar measurements from other vendors, but I'm assuming they'll be within the same order of
magnitude._


## A Proposal


Let's address the above concerns by giving developers a well-lit path towards security boundaries we
can defend. The browser can take control of the HTTP state it represents on the users' behalf by
generating a unique 64-bit value for each secure origin the user visits. This token can be delivered
to the origin as a [structured](https://tools.ietf.org/html/draft-ietf-httpbis-header-structure) HTTP
request header:

```http
Sec-HTTP-State: token=*AeQYkQ4Touk* purpose=*authentication*
```

This identifier acts more or less like a client-controlled cookie, with a few notable distinctions:

1.  The client controls the token's value, not the server. 

2.  The token will only be available to the network layer, not to JavaScript (including network-like
    JavaScript, such as Service Workers).

3.  The user agent will generate only one 64-bit token per origin, and will only expose the token to
    the origin for which it was generated.

4.  Tokens will not be generated for, or delivered to, non-secure origins.

5.  Tokens will be delivered along with same-site requests by default.

6.  The token persists until it's reset by the server, user, or browser.

7.  The token will have fixed semantics attached to it and identified in purpose-field. 
    A browser can generate a new token for a new purpose. This may include permission
    or prohibition of cross-origin sharing via backend channels.

These distinctions might not be appropriate for all use cases, but seem like a reasonable set of
defaults. The major difference to classic cookies is that the browser mints the identifiers and controls
the purpose of the identifier with an additional field. This way, a browser may distinguish between 
desirable and undesirable uses of the identifier it provides. 

In unregulated environments, there is no difference. In regulated environments, 
data protection rules may help to enforce the purpose limitation set with the identifier. 
This may sound restrictive, but it would be a way to avoid the browser-generated identifier 
running into the same issues and bad reputation we see for cookies.

For folks for whom these defaults aren't good enough, we'll provide developers with a few
control points that can be triggered via a `Sec-HTTP-State-Options` HTTP response header. The
following options come to mind:

1.  Some servers will require cross-site access to their token. Other servers may wish to narrow the
    delivery scope to same-origin requests. Either option could be specified by the server:

    ```http
    Sec-HTTP-State-Options: ..., delivery=cross-site, ...
    ```

    or 

    ```http
    Sec-HTTP-State-Options: ..., delivery=same-origin, ...
    

2.  Some servers will wish to limit the token's lifetime. We can allow them to set a TTL (in seconds):

    ```http
    Sec-HTTP-State-Options: ..., ttl=3600, ...
    ```

    After the time expires, the token's value will be automatically reset. Servers may also wish to
    explicitly trigger the token's reset (upon signout, for example). Setting a TTL of 0 will do the
    trick:

    ```http
    Sec-HTTP-State-Options: ..., ttl=0, ...
    ```

    In either case, currently-running pages can be notified of the user's state change in order to
    perform cleanup actions. When a reset happens, the browser can post a message to the origin's
    `BroadcastChannel` named `http-state-reset` (and perhaps wake up the origin's Service Worker
    to respond to user-driven resets):

    ```js
    let resetChannel = new BroadcastChannel('http-state-reset'));
    resetChannel.onmessage = e => { /* Do exciting cleanup here. */ };
    ```

3.  For some servers, the client-generated token will be enough to maintain state. They can treat
    it as an opaque session identifier, and bind the user's state to it server-side. Other servers
    will require additional assurance that they can trust the token's provenance. To that end,
    servers can generate a unique key, associate it with the session identifier on the server, and
    deliver it to the client via an HTTP response header:

    ```http
    Sec-HTTP-State-Options: ..., key=*ZH0GxtBMWA...nJudhZ8dtz*, ...
    ```

    Clients will store that key, and use it to generate a signature over some set of data that
    mitigates the risk of token capture:

    ```http
    Sec-HTTP-State: token=*AeQYkQ4Touk*, sig=*(HMAC-SHA265(key, token+metadata))*
    ```

    For instance, signing the entire request using the format that [Signed Exchanges](https://tools.ietf.org/html/draft-yasskin-http-origin-signed-responses) have defined
    could make it difficult indeed to use stolen tokens for anything but replay attacks. Including a
    timestamp in the request might reduce that capability even further by reducing the window for
    pure replay attacks.

    _Note: This bit in particular is not baked. We need to review the work folks have done on things
    like Token Binding to determine what the right threat model ought to be. Look at it as an area
    to explore, not a solidly thought-out solution._

4.  A token may be limited not only in its delivery scope (cross-site vs origin only), but may also be 
    limited in the purpose it is used for in a stateful system. This should be limited to the options 
    given by a specification with an extension mechanism. 
    
    ```http
    Sec-HTTP-State-Options: ..., purpose=authentication, measurement, ...
    ```
    Given the fact that the number of potential purposes is infinite, an extension mechanism is needed to 
    allow for quick evolution between standardization efforts. The initiative for such an extension 
    should come from the server side. Wanting state after a first stateless interaction, the server 
    would request a number with an extended purpose string. The browser could present such a new purpose to 
    the user in a notification and send the string below once the user agrees.
    
    ```http
    Sec-HTTP-State-Options: ..., purpex=delivery, backgroundsync, cloudsync, ...
    ```

Coming back to the three prongs above, this proposal aims to create a state token whose
configuration is hardened, maps to the same security primitive as the rest of the platform, reduces
the client-side cost of transport, and isn't useful for cross-site tracking by default.

## Pivot Points

The proposal described above seems pretty reasonable to me, but I see it as the start of a
conversation. There are many variations that I hope we can explore together. In the hopes of kicking
that off, here are some I've considered:

### Server-controlled values?

An earlier version of this proposal put the server in charge of the token's value, allowing
developers to come up with a storage and verification scheme that makes sense for their application.
While I've since come around to the idea that baking this mechanism more deeply into the platform is
probably a good direction to explore, there's real value in allowing the server to map their
existing authentication cookies onto a new transport mechanism in a reasonably straightforward way,
and to design a signing/verification scheme that meets their needs. For example, the server could
set the token directly via an HTTP response header:

```http
Sec-HTTP-State-Options: token=*ZH0GxtBMWAnJudhZ8dtz*
```

That still might be a reasonable option to allow, but I'm less enthusiastic about it than I was
previously.

### A new world of browser controlled tokens does not replace cookies, but makes things that matter reliable

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

One counterpoint, however, is that it could be very valuable to distinguish tokens for specific
purposes. Users and browsers would likely treat an "authentication" token differently from an
"advertising and measurement" token, giving them different lifetimes and etc. Perhaps it
would make sense to specify a small set of use cases that we'd like user agents to explicitly
support. The important thing to remember is that adding semantics to the token should start 
with very easy and consistent use cases like `purpose=authentication` to avoid a large scope 
that would renew the known deficiencies and abuses of cookies as generic opaque identifiers.


### Mere reflection?

The current proposal follows in the footsteps of cookies, delivering the identifier unmodified to
the server on every request. This seems like the most straightforward story to tell developers,
and fits well with how folks think things work today.

That said, it might be interesting to explore more complicated relationships between the token's
value, and the value that's delivered to servers in the HTTP request. You could imagine, for
instance, incorporating some [Cake](https://tools.ietf.org/html/draft-abarth-cake-00)- or
[Macaroon](https://ai.google/research/pubs/pub41892)-like HMACing to indicate provenance or
capability. Or shifting more radically to an OAuth style model where the server sets a long-lived
token which the browser exchanges on a regular basis for short-lived tokens.


### Opt-in?

The current proposal suggests that the browser generate a token for newly visited origins by
default, delivering it along with the initial request. It might be reasonable instead to send
something like `Sec-HTTP-State: ?` to advertise the feature's presence, and allow the server to
ask for a token by sending an appropriate options header (`Sec-HTTP-State-Options: generate`, or
something similar).

For privacy preservation, the browser would do a stateless default in private browsing mode and 
send an authentication identifier in normal browsing with the option of the server to ask for 
more tokens and different purposes after the first roundtrip. 


## FAQ

### Wait. What? Are you saying we should deprecate cookies?

No! Of course not! That would be silly! Ha! Who would propose such a thing?


### You would, Mike. You would.

Ok, you got me. Cookies are bad and we should find a path towards deprecation. But that's going to
take some time. This proposal aims to be an addition to the platform that will provide value even
in the presence of cookies, giving us the ability to shift developers from one to the other
incrementally.

The proposal has the potential to kill cookies, but it should be very specific in the first 
place to make reliable, resilient tokens that are harder to abuse than cookies. Over time, cookies 
will be mostly used in edge cases where the browser token would be too complex to obtain. 


### Is this new thing fundamentally different than a cookie?

Definitely! It changes the relations between the service and the user using the user agent. 
It allows the user agent to change the token, maintain state and be aware of the token used. 
Cookies are opaque to the user agent. Tokens may be abused, but remain under the control 
of the user agent. It doesn't change developing fundamentally though.

Developers can get almost all of the above properties by setting a cookie like
`__Host-token=value1; Secure; HttpOnly; SameSite=Lax; path=/`. That isn't a perfect analog (it
continues to ignore ports, for instance), but it's pretty good. My concern with the status quo is
that developers need to understand the impact of the various flags and naming convention in order to
choose it over `Set-Cookie: token=value`. Defaults matter, deeply, and this seems like the simplest
thing that could possibly work. It solidifies best practice into a thing-in-itself, rather than
attempting to guide developers through the four attributes they must use, the one attribute they
must not use, and the weird naming convention they need to adopt.

We also have the opportunity to reset the foundational assumption that server-side state is best
maintained on the client. I'll blithly assert that it is both more elegant and more respectful of
users' resources to migrate towards browser-controlled session identifiers, rather than oodles of
key-value pairs set by the server (though I expect healthy debate on that topic).


### How do you expect folks to migrate to this from cookies?

Slowly and gradually. User agents could begin by advertising support for the new hotness by
appending a `Sec-HTTP-State` header to outgoing requests (either setting the value by default, or
allowing developers to opt-in, as per the pivot point discussion above). 

If tokens are introduced for a specific purpose only and targeted to a specific audience and if 
legal sanctions are possible when abusing the token, chances are not neglectable that a resilient 
identifier for a more comfortable browsing experience will emerge. Additionally, the fact that the 
browser controls the token makes it easier for the user agent to be more privacy protective.

Developers could begin using the new mechanism for pieces of their authentication infrastructure
that would most benefit from origin-scoping, side-by-side with the existing cookie infrastructure.
Over time, they could build up a list of the client-side state they're relying on, and begin to
construct a server-side mapping between session identifiers and state. Once that mechanism was in
place, state could migrate to it in a piecemeal fashion.

Eventually, you could imagine giving developers the ability to migrate completely, turning cookies
off for their sites entirely (via Origin Manifests, for instance). Even more eventually, we could
ask developers to opt-into cookies rather than opting out.

At any point along that timeline, browsers can begin to encourage migration by placing restrictions
on subsets of cookies, along the lines of proposals like
[cookies-over-http-bad](https://github.com/mikewest/cookies-over-http-bad).


### Won't this migration be difficult for origins that host multiple apps?

Yes, it will. That seems like both a bug and a feature. It would be better for origins and
applications to have more of a 1:1 relationship than they have today. There is no security boundary
between applications on the same origin, and there doesn't seem to me to be much value in pretending
that one exists (though perhaps we'll get there someday with a good story around
[Suborigins](https://w3c.github.io/webappsec-suborigins/)). It is good to encourage different
applications to run on different origins, creating actual segregation between their capabilities.


### Does this proposal constitute a material change in privacy properties?

Yes and no. Mostly yes. That is, folks can still use these tokens to track users across origins, just
as they can with cookies today. There's a trivial hurdle insofar as folks would need to declare that
intent by setting the token's `delivery` member, and it's reasonable to expect user agents to react
to that declaration in some interesting ways, but in itself, there's little change in technical
capability. 

Still, it has some advantages over the status quo. For example, these tokens can never be sent in
plaintext, which mitigates some risk of pervasive monitoring. Also, reasonable length and character
limitations restrict the amount of data which can be contained directly in the token, tilting the
field towards opaque identifiers linked to server-side state, as opposed to caching sensitive
information locally and exposing on the local disk, as well as to all the TLS-terminating endpoints
between you and the service you care about. Additionally, in regulated environments, control by 
the user and appropriate semantics will allow rogue services to be pursued. The reduced semantics 
of specific tokens avoid scope creep by cloudy privacy statements. The services using cloudy 
statements are forced to continue to use cookies.
