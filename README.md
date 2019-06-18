# Explainer: Tightening HTTP State Management

**WIP specification**: https://mikewest.github.io/http-state-tokens/draft-west-http-state-tokens.html (_or on the IETF's servers at https://tools.ietf.org/html/draft-west-http-state-tokens-00, if you like pretending that web pages are paginated!_)

-----

Mike West, August 2018

_©2018, Google, Inc. All rights reserved._

(_Note: This isn't a proposal that's well thought out, and stamped solidly with the Google Seal of
Approval. It's a collection of interesting ideas for discussion, nothing more, nothing less._)

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
    decade ago, only ~8.31% of `Set-Cookie` operations use it today.
    
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

_Note: All the metrics noted above come from Chrome's telemetry data for July, 2018. I'd welcome
similar measurements from other vendors, but I'm assuming they'll be within the same order of
magnitude._


## A Proposal

Let's address the above concerns by giving developers a well-lit path towards security boundaries we
can defend. The user agent can take control of the HTTP state it represents on the users' behalf by
generating a unique 256-bit value for each secure origin the user visits. This token can be delivered
to the origin as a [structured](https://tools.ietf.org/html/draft-ietf-httpbis-header-structure) HTTP
request header:

```http
Sec-HTTP-State: token=*J6BRKagRIECKdpbDLxtlNzmjKo8MXTjyMomIwMFMonM*
```

This identifier acts more or less like a client-controlled cookie, with a few notable distinctions:

1.  The client controls the token's value, not the server.

2.  The token will only be available to the network layer, not to JavaScript (including network-like
    JavaScript, such as Service Workers).

3.  The user agent will generate only one token per origin, and will only expose the token to the
    origin for which it was generated.

4.  Tokens will not be generated for, or delivered to, non-secure origins.

5.  Tokens will be delivered only along with same-site requests by default, and can only be created
    from same-site contexts.

6.  Each token persists for one hour after generation by default. This default expiration time can
    be overwritten by servers, and tokens can be reset at any time by servers, users, or user
    agents.

These distinctions might not be appropriate for all use cases, but seem like a reasonable set of
defaults. For folks for whom these defaults aren't good enough, we'll provide developers with a few
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
    ```

2.  Some servers will wish to limit the token's lifetime. We can allow them to set a `max-age` (in seconds):

    ```http
    Sec-HTTP-State-Options: ..., max-age=3600, ...
    ```

    After the time expires, the token's value will be automatically reset. Servers may also wish to
    explicitly trigger the token's reset (upon signout, for example). Setting a `max-age` of 0 will do the
    trick:

    ```http
    Sec-HTTP-State-Options: ..., max-age=0, ...
    ```

    In either case, currently-running pages can be notified of the user's state change in order to
    perform cleanup actions. When a reset happens, the user agent can post a message to the origin's
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
    Sec-HTTP-State: token=*J6BRKa...MonM*, sig=*(HMAC-SHA256(key, token+metadata))*
    ```

    For instance, signing the entire request using the format that [Signed Exchanges](https://tools.ietf.org/html/draft-yasskin-http-origin-signed-responses) have defined
    could make it difficult indeed to use stolen tokens for anything but replay attacks. Including a
    timestamp in the request might reduce that capability even further by reducing the window for
    pure replay attacks.

    _Note: This bit in particular is not baked. We need to review the work folks have done on things
    like Token Binding to determine what the right threat model ought to be. Look at it as an area
    to explore, not a solidly thought-out solution._

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
Sec-HTTP-State-Options: token=*h3PkR1BwTyfAq6UOr...n6LlOPGSWGT3iBEF5CKes*
```

That still might be a reasonable option to allow, but I'm less enthusiastic about it than I was
previously.

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

One counterpoint, however, is that it could be very valuable to distinguish tokens for specific
purposes. Users and user agents would likely treat an "authentication" token differently from an
"advertising and measurement" token, giving them different lifetimes and etc. Perhaps it
would make sense to specify a small set of use cases that we'd like user agents to explicitly
support.


### Mere reflection?

The current proposal follows in the footsteps of cookies, delivering the identifier unmodified to
the server on every request. This seems like the most straightforward story to tell developers,
and fits well with how folks think things work today.

That said, it might be interesting to explore more complicated relationships between the token's
value, and the value that's delivered to servers in the HTTP request. You could imagine, for
instance, incorporating some [Cake](https://tools.ietf.org/html/draft-abarth-cake-00)- or
[Macaroon](https://ai.google/research/pubs/pub41892)-like HMACing to indicate provenance or
capability. Or shifting more radically to an OAuth style model where the server sets a long-lived
token which the user agent exchanges on a regular basis for short-lived tokens.


### Opt-in?

The current proposal suggests that the user agent generate a token for newly visited origins by
default, delivering it along with the initial request. It might be reasonable instead to send
something like `Sec-HTTP-State: ?` to advertise the feature's presence, and allow the server to
ask for a token by sending an appropriate options header (`Sec-HTTP-State-Options: generate`, or
something similar).


## FAQ

### Wait. What? Are you saying we should deprecate cookies?

No! Of course not! That would be silly! Ha! Who would propose such a thing?


### You would, Mike. You would.

Ok, you got me. Cookies are bad and we should find a path towards deprecation. But that's going to
take some time. This proposal aims to be an addition to the platform that will provide value even
in the presence of cookies, giving us the ability to shift developers from one to the other
incrementally.


### Is this new thing fundamentally different than a cookie?

TL;DR: No. But yes!

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
users' resources to migrate towards user-agent-controlled session identifiers, rather than oodles of
key-value pairs set by the server (though I expect healthy debate on that topic).


### How do you expect folks to migrate to this from cookies?

Slowly and gradually. User agents could begin by advertising support for the new hotness by
appending a `Sec-HTTP-State` header to outgoing requests (either setting the value by default, or
allowing developers to opt-in, as per the pivot point discussion above).

Developers could begin using the new mechanism for pieces of their authentication infrastructure
that would most benefit from origin-scoping, side-by-side with the existing cookie infrastructure.
Over time, they could build up a list of the client-side state they're relying on, and begin to
construct a server-side mapping between session identifiers and state. Once that mechanism was in
place, state could migrate to it in a piecemeal fashion.

Eventually, you could imagine giving developers the ability to migrate completely, turning cookies
off for their sites entirely (via Origin Manifests, for instance). Even more eventually, we could
ask developers to opt-into cookies rather than opting out.

At any point along that timeline, user agents can begin to encourage migration by placing restrictions
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

Yes and no. Mostly no. That is, folks can still use these tokens to track users across origins, just
as they can with cookies today. There's a trivial hurdle insofar as folks would need to declare that
intent by setting the token's `delivery` member, and it's reasonable to expect user agents to react
to that declaration in some interesting ways, but in itself, there's little change in technical
capability.

Still, it has some advantages over the status quo. For example:

1.  These tokens can never be sent in plaintext, which mitigates some risk of pervasive monitoring.
2.  The user agent controls the token's value, which reduces the risk that the server could store
    sensitive information on the user's machine in a way that would be continually exposed on the
    local disk, as well as to all the TLS-terminating endpoints between you and the service you
    care about.
3.  The default `delivery` option would restrict tokens to same-site requests. Assuming we follow
    the `SameSite` cookie precedent by only accepting options to be changed on requests that would
    send the token, cross-site tokens would only be available to a given origin after the user
    visited that origin in a same-site context, and it explicitly declared its token as being
    deliverable cross-site (at which point the user agent could make some decisions about how to
    handle that declaration).


### What kinds of user control would user agents provide?

Users must always have the ability to opt-out of sending this token to any entity, just as they do
with cookies today. User agents should likely aim above that bar, but an opt-out seems like the bare
minimum we could reasonably accept.

----------

# Contributing

## Building the Draft

Formatted text and HTML versions of the draft can be built using `make`.

```sh
$ make
```

This requires that you have the necessary software installed.  See
[the instructions](https://github.com/martinthomson/i-d-template/blob/master/doc/SETUP.md).


## Contributing

See the
[guidelines for contributions](https://github.com/mikewest/http-state-tokens/blob/master/CONTRIBUTING.md).
