---
title: HTTP State Tokens
docname: draft-west-http-state-tokens
date: {DATE}
category: std
ipr: trust200902
area: Applications and Real-Time
keyword: Internet-Draft

stand_alone: yes
pi:
  toc: yes
  tocindent: yes
  sortrefs: yes
  symrefs: yes
  strict: yes
  compact: yes
  comments: yes
  inline: yes
  tocdepth: 2


author:
 -
    ins: M. West
    name: Mike West
    organization: Google
    email: mkwst@google.com
    uri: https://www.mikewest.org/

normative:
  I-D.ietf-httpbis-header-structure:
  I-D.yasskin-http-origin-signed-responses:
  RFC2104:
  RFC2119:
  RFC4648:
  Fetch:
    target: https://fetch.spec.whatwg.org/
    title: Fetch
    author:
    -
      ins: A. van Kesteren
      name: Anne van Kesteren
      organization: Mozilla

informative:
  RFC6265:
  I-D.ietf-httpbis-rfc6265bis:
  I-D.abarth-cake:
  I-D.ietf-cbor-cddl:

--- abstract

This document describes a mechanism which allows HTTP servers to maintain stateful sessions with
HTTP user agents. It aims to address some of the security and privacy considerations which have
been identified in existing state management mechanisms, providing developers with a well-lit path
towards our current understanding of best practice.

--- middle

# Introduction

Cookies {{RFC6265}} allow the nominally stateless HTTP protocol to support stateful sessions,
enabling practically everything interesting on the web today. That said, cookies have some issues:
they're hard to use securely, they add substantial weight to users' outgoing requests, and they
enable tracking users' activity across the web in potentially surprising ways.

This document proposes an alternative state management mechanism that aims to provide the bare
minimum required for state management: each user agent generates a single token per origin,
and delivers it as a header in requests to that origin. A few notable features distinguish this
token from the cookie it aims to replace:

1.  The client controls the token's value, not the server.

2.  The token will only be available to the network layer, not to JavaScript (including network-like
    JavaScript, such as Service Workers).

3.  The user agent will generate only one token per origin, and will only expose the token to the
    origin for which it was generated.

4.  Tokens will not be generated for, or delivered to, non-secure origins.

5.  Tokens will be delivered along with same-site requests by default.

6.  The token persists until it's reset by the server, user, or user agent.

These distinctions might not be appropriate for all use cases, but seem like a reasonable set of
defaults. For folks for whom these defaults aren't good enough, we'll provide developers with a few
control points that can be triggered via a `Sec-HTTP-State-Options` HTTP response header, described in 

TODO(mkwst): Flesh out an introduction.

## Examples

User agents can deliver HTTP state tokens to a server in a `Sec-Http-State` header. For example,
if a user agent has generated a token bound to `https://example.com/` whose base64 encoding is
`hB2RfWaGyNk60sjHze5DzGYjSnL7tRF2HWSBx6J1o4k=` ({{RFC4648}}, Section 4), then it would generate the
following header when delivering the token along with requests to `https://example.com/`:

~~~
Sec-Http-State: token=*hB2RfWa...GyNko4k=*
~~~
{: artwork-align="center"}

The server can control certain aspects of the token's delivery by responding to requests with a
`Sec-Http-State-Options` header.

~~~
Sec-Http-State-Options: ttl=3600, key=*b7kuUkp...lkRioC2=*
~~~
{: artwork-align="center"}

# Conventions

## Conformance

{::boilerplate bcp14}

## Syntax

This document defines two Structured Headers {{!I-D.ietf-httpbis-header-structure}}. In doing so it
relies upon the Augmented Backus-Naur Form (ABNF) notation of {{!RFC5234}} and the OWS rule from
{{!RFC7230}}.

# HTTP State Management

## Infrastructure

### HTTP State Tokens

An HTTP State Token holds information which allows a user agent to maintain a stateful session with
a specific origin. HTTP State Tokens have a number of associated properties:

*   `scope` controls the scopes from which the token can be delivered. It is an enum of either
    `same-origin`, `same-site`, or `cross-site`. Unless otherwise specified, its value is
    `same-site`.

*   `expiration` is a timestamp representing the point at which the token will be reset. Unless
    otherwise specified, its value is the maximum date the user agent can represent.

*   `key` is a server-provided key which can be used to sign requests with which the token is
    delivered. It is either empty, or contains up to 256-bits of binary data. Unless otherwise
    specified, its value is empty.

*   `value` is the token's value (surprising, right?). It contains up to 256-bits of binary data.

### Token Storage

User agents MUST keep a list of all the unexpired HTTP State Tokens which have been created. For the
purposes of this document, we'll assume that user agents keep this list in the form of a map whose
keys are origins, and whose values are HTTP State Tokens. 

This map exposes three functions:

*   An HTTP State Token can be stored for a given origin. If the origin already exists in the map,
    the entry's value will be overwritten with the new HTTP State Token.

*   An origin's HTTP State Token can be retrieved. If the origin does not exist in the map, `null`
    will be returned instead.

*   An origin (along with its HTTP State Token) can be deleted from the map.

The map is initially empty.

## Syntax

### The 'Sec-Http-State' HTTP Header Field {#sec-http-state}

The `Sec-Http-State` HTTP header field allows user agents to deliver HTTP state tokens to servers
as part of an HTTP request.

`Sec-Http-State` is a Structured Header {{!I-D.ietf-httpbis-header-structure}}. Its value MUST be
a dictionary ({{!I-D.ietf-httpbis-header-structure}}, Section 3.1). Its ABNF is:

~~~ abnf
Sec-Http-State = sh-dictionary
~~~
{: artwork-align="center"}

The dictionary MUST contain:

*   Exactly one member whose key is `token`, and whose value is binary content
    ({{!I-D.ietf-httpbis-header-structure}}, Section 3.9) that encodes the HTTP state token's
    value for the origin to which the header is delivered.

    If the `token` member contains more than 256 bits of binary content, the member MUST be ignored.

The dictionary MAY contain:

*   Exactly one member whose key is `sig`, and whose value is binary content
    ({{!I-D.ietf-httpbis-header-structure}}, Section 3.9) that encodes a signature over the token
    and the request which contains it, using a key previously delivered by the server. This
    mechanism is described in {{sign}}.

    If the `sig` member contains more than 256 bits of binary content, the member MUST be ignored.

The `Sec-Http-State` header is parsed per the algorithm in Section 4.2 of
{{I-D.ietf-httpbis-header-structure}}. Servers MUST ignore the header if parsing fails, or if the
parsed header does not contain a member whose key is `token`.

User agents will attach a `Sec-Http-State` header to outgoing requests according to the processing
rules described in {{delivery}}.

### The 'Sec-Http-State-Options' HTTP Header Field {#sec-http-state-options}

The `Sec-Http-State-Options` HTTP header field allows servers to deliver configuration information
to user agents as part of an HTTP response.

`Sec-Http-State-Options` is a Structured Header {{!I-D.ietf-httpbis-header-structure}}. Its value
MUST be a dictionary ({{!I-D.ietf-httpbis-header-structure}}, Section 3.1). Its ABNF is:

~~~ abnf
Sec-Http-State-Options = sh-dictionary
~~~
{: artwork-align="center"}

The dictionary MAY contain:

*   Exactly one member whose key is `key`, and whose value is binary content
    ({{!I-D.ietf-httpbis-header-structure}}, Section 3.9) that encodes an key which can be used to
    generate a signature over outgoing requests.

    If the `key` member contains an unknown identifier, the member MUST be ignored.

*   Exactly one member whose key is `scope`, and whose value is one of the following identifiers
    ({{!I-D.ietf-httpbis-header-structure}}, Section 3.8): `same-origin`, `same-site`, or
    `cross-site`.

    If the `scope` member contains an unknown identifier, the member MUST be ignored.

*   Exactly one member whose key is `ttl`, and whose value is an integer
    ({{!I-D.ietf-httpbis-header-structure}}, Section 3.5) representing the server's desires for its
    HTTP State Token's lifetime.

    If the `ttl` member contains a negative number, the member MUST be ignored.

# Delivering HTTP State Tokens {#delivery}

User agents deliver HTTP state tokens to servers by appending a `Sec-Http-State` header field to
outgoing requests. 

This specification provides algorithms which are called at the appropriate points in {{Fetch}} in
order to attach `Sec-Http-State` headers to outgoing requests, and to ensure that
`Sec-Http-State-Options` headers are correctly processed.

## Attach HTTP State Tokens to a request

The user agent can attach HTTP State Tokens to a given request using an algorithm equivalent to the
following:

1.  If the user agent is configured to block cookies for the request, skip the remaining steps in
    this algorithm, and return without modifying the request.

2.  Let `target-origin` be the origin of `request`'s current URL.

3.  Let `request-token` be the result of retrieving origin's token from the user agent's token
    store, or `null` if no such token exists.

4.  Let `serialized-token` be the empty string.

5.  Let `serialized-signature` be the empty string.

6.  Let `header-value` be a Structured Header whose value is a dictionary.

7.  If `request-token` is not `null`:

    1.  If `request-token`'s `scope` is `same-origin` and `target-origin` is not same origin with
        `request`'s origin, or if `request-token`'s `scope` is `same-site` and `target-origin`'s
        registrable domain is not the same as `request`'s origin's registrable domain, then skip
        the remaining substeps.

        ISSUE: Perhaps we should add some sort of `out-of-scope` token to the header in this case?
        Or note that folks should look at `Sec-Metadata`?

    2.  Set `serialized-token` to the base64 encoding ({{!RFC4648}}, Section 4) of
        `request-token`'s value.

    3.  If `request-token`'s `key` is present:

        1.  Set `serialized-signature` to the result of executing {{sign}} on request,
            `serialized-token`, and `request-token`'s `key`.

8.  Insert a member into `header-value` whose key is `token`, and whose value is `serialized-token`.

9.  If `serialized-signature` is not empty, then insert a member into `header-value` whose key is
    `sig`, and whose value is `serialized-signature`.

10. Append a header to `request`'s header list whose name is `Sec-Http-State`, and whose value is
    the result of serializing `header-value` ({{I-D.ietf-httpbis-header-structure}}, Section 4.1).
  
## Generate a request's signature {#sign}

If the origin server provides a `key`, the user agent will use it to sign any outgoing requests
which target that origin and include an HTTP State Token. Note that the signature is produced
before adding the `Sec-Http-State` header to the request.

Given a request, a base64-encoded token value, and a key:

1.  Let `cbor-request` be the result of building a CBOR representation {{!RFC7409}} of the given
    request, as specified in the first element of the array described in Section 3.2 of
    {{I-D.yasskin-http-origin-signed-responses}}.

2.  Add an item to `cbor-request` which maps the byte string ':token' to the byte string containing
    the given base64-encoded token value.
   
3.  Return the result of computing HMAC-SHA256 {{!RFC2104}} over the canonical CBOR serialization of
    `cbor-request` (Section 3.4 of {{I-D.yasskin-http-origin-signed-responses}}), using the given
    `key`.

### Example

The following request:

~~~
GET / HTTP/1.1
Host: example.com
Accept: */*
~~~

results in the following CBOR representation (represented using the extended diagnostic notation
from Appendix G of {{I-D.ietf-cbor-cddl}}):

~~~
{
  ':method': 'GET',
  ':token': 'hB2RfWaGyNk60sjHze5DzGYjSnL7tRF2HWSBx6J1o4k='
  ':url': 'https://example.com/',
  'accept': '*/*',
}
~~~

# IANA Considerations

## Header Field Registry

This document registers the `Sec-Http-State` and `Sec-Http-State-Options` header fields in the
"Permanent Message Header Field Names" registry located at
<https://www.iana.org/assignments/message-headers>.

### Sec-Http-State Header Field

Header field name:

: Sec-Http-State

Applicable protocol:

: http

Status:

: experimental

Author/Change controller:

: IETF

Specification document(s):

: This document (see {{sec-http-state}})

Related information:

: (empty)

### Sec-Http-State-Options Header Field

Header field name:

: Sec-Http-State-Options

Applicable protocol:

: http

Status:

: experimental

Author/Change controller:

: IETF

Specification document(s):

: This document (see {{sec-http-state-options}})

Related information:

: (empty)

# Security Considerations

TODO

# Privacy Considerations

TODO

--- back

# Acknowledgements

This document owes much to Adam Barth's {{I-D.abarth-cake}}.

# Changes

_RFC Editor: Please remove this section before publication._

## Since the beginning of time

*   This document was created.
