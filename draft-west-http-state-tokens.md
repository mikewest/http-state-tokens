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
  RFC2109:
  RFC6265:
  I-D.ietf-httpbis-rfc6265bis:
  I-D.abarth-cake:
  StateTokenExplainer:
    target: https://github.com/mikewest/http-state-tokens
    title: "Explainer: Tightening HTTP State Management"
    author:
    -
      ins: M. West
      name: Mike West
    date: 2018

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
minimum required for state management: each user agent generates a single token, bound to a single
origin, and delivers it as a header in requests to that origin.

TODO(mkwst): Flesh out an introduction.

## Examples

User agents can deliver HTTP state tokens to a server in a `Sec-Http-State` header. For example,
if a user agent has generated a token bound to `https://example.com/` whose base64 encoding is
`hB2RfWaGyNk60sjHze5DzGYjSnL7tRF2HWSBx6J1o4k=` ({{RFC4648}}, Section 4), then it would generate the
following header when delivering the token along with requests to `https://example.com/`:

~~~
Sec-Http-State: token=*hB2RfWaGyNk60sjHze5DzGYjSnL7tRF2HWSBx6J1o4k=*
~~~

The server can control certain aspects of the token's delivery by responding to requests with a
`Sec-Http-State-Options` header.

# Conventions

## Conformance

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
described in BCP 14 {{!RFC2119}} {{!RFC8174}} when, and only when, they appear in all capitals, as
shown here.

## Syntax

This document defines two Structured Headers {{!I-D.ietf-httpbis-header-structure}}. In doing so it
relies upon the Augmented Backus-Naur Form (ABNF) notation of {{!RFC5234}} and the OWS rule from
{{!RFC7230}}.

# HTTP State Management

## Infrastructure

### HTTP State Tokens

An HTTP State Token is a set of information maintained by a user agent to represent a stateful
session with a specific origin.

HTTP State Tokens have an associated `value`, which contains up to 256-bits of binary data.

HTTP State Tokens have an associated `key`, which is either empty, or contains up to 256-bits of
binary data.

### Token Storage

User agents store HTTP State Tokens in an internal Token Store, which maps origins to HTTP State
Tokens in a 1:1 relationship.

The Token Store can store, retrieve, and remove a given origin's HTTP State Token.

## Syntax

### The 'Sec-Http-State' HTTP Header Field

The `Sec-Http-State` HTTP header field allows user agents to deliver HTTP state tokens to servers
as part of an HTTP request.

`Sec-Http-State` is a Structured Header {{!I-D.ietf-httpbis-header-structure}}. Its value MUST be
a dictionary ({{!I-D.ietf-httpbis-header-structure}}, Section 3.1). Its ABNF is:

~~~ abnf
Sec-Http-State = sh-dictionary
~~~

The dictionary MUST contain:

*   Exactly one member whose key is `token`, and whose value is binary content
    ({{!I-D.ietf-httpbis-header-structure}}, Section 3.9) that encodes the HTTP state token's
    value for the origin to which the header is delivered.

The dictionary MAY contain:

*   Exactly one member whose key is `sig`, and whose value is binary content
    ({{!I-D.ietf-httpbis-header-structure}}, Section 3.9) that encodes a signature over the token
    and the request which contains it, using a key previously delivered by the server. This
    mechanism is described in {{sign}}.

### The 'Sec-Http-State-Options' HTTP Header Field

TODO

# Delivering HTTP State Tokens

User agents deliver HTTP state tokens to servers by appending a `Sec-Http-State` header field to
outgoing requests. 

This specification provides algorithms which are called at the appropriate points in {{Fetch}} in
order to attach `Sec-Http-State` headers to outgoing requests, and to ensure that
`Sec-Http-State-Options` headers are correctly processed.

## Attach HTTP State Tokens to a request

The user agent can attach HTTP State Tokens to a request using an algorithm equivalent to the
following:

1.  If the user agent is configured to block cookies for the request, skip the remaining steps in
    this algorithm, and return without modifying the request.

2.  Let `request-origin` be the origin of `request`'s current URL.

3.  Let `request-token` be the result of retrieving origin's token from the user agent's token
    store, or `null` if no such token exists.

4.  Let `serialized-token` be the empty string.

5.  Let `serialized-signature` be the empty string.

6.  If `request-token` is not `null`:

    1.  Set `serialized-token` to the base64 encoding ({{!RFC4648}}, Section 4) of
        `request-token`'s value.

    2.  If `request-token`'s `key` is present:

        1.  Set serialized-signature to the result of executing {{sign}} on request.

7.  Let `header-value` be a Structured Header whose value is a dictionary.

8.  Insert a member into `header-value` whose key is `token`, and whose value is `serialized-token`.

9.  If `serialized-signature` is not empty, then insert a member into `header-value` whose key is
    `sig`, and whose value is `serialized-signature`.

10. Append a header to `request`'s header list whose name is `Sec-Http-State`, and whose value is
    the result of serializing `header-value` ({{I-D.ietf-httpbis-header-structure}}, Section 4.1).
  
## Generate a request's signature {#sign}

TODO.


# IANA Considerations

## Header Field Registry

This document registers the `Sec-Http-State` and `Sec-Http-State-Options` header fields in the
"Permanent Message Header Field Names" registry located at
<https://www.iana.org/assignments/message-headers>.

### Sec-Http-State

Header field name:

: Sec-Http-State

Applicable protocol:

: http

Status:

: experimental

Author/Change controller:

: IETF

Specification document(s):

: This document

Related information:

: (empty)

### Sec-Http-State-Options

Header field name:

: Sec-Http-State-Options

Applicable protocol:

: http

Status:

: experimental

Author/Change controller:

: IETF

Specification document(s):

: This document

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
