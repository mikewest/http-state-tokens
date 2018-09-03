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
  RFC2119:
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
  I-D.ietf-httpbis-header-structure:
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
been identified in existing state management mechanims, providing developers with a well-lit path
towards our current understanding of best practice.

--- middle

# Introduction

Cookies {{RFC6265}} allow the nominally stateless HTTP protocol to support stateful sessions,
enabling practically everything interesting on the web today. That said, cookies have some issues:
they're hard to use securely, they waste users' resources, and they enable tracking users' activity
across the web in potentially surprising ways.

TODO(mkwst): Add an introduction.

## Requirements Language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in RFC 2119 {{!RFC2119}}.

## Notational Conventions

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
described in BCP 14 {{!RFC2119}} {{!RFC8174}} when, and only when, they appear in all capitals, as
shown here.

This document defines two Structured Headers {{!I-D.ietf-httpbis-header-structure}}. In doing so it
relies upon the Augmented Backus-Naur Form (ABNF) notation of {{!RFC5234}} and the OWS rule from
{{!RFC7230}}.

# HTTP State Management

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

This specification provides algorithms which are called at the appropriate points
in {{Fetch}} in order to 

In order to deliver an HTTP state token to a server, it 

## Attach an HTTP state token 

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

The size of most types defined by Structured Headers is not limited; as a result, extremely large header fields could be an attack vector (e.g., for resource consumption). Most HTTP implementations limit the sizes of size of individual header fields as well as the overall header block size to mitigate such attacks.

It is possible for parties with the ability to inject new HTTP header fields to change the meaning
of a Structured Header. In some circumstances, this will cause parsing to fail, but it is not possible to reliably fail in all such circumstances.

--- back


# Frequently Asked Questions {#faq}

## Why not JSON?

Earlier proposals for structured headers were based upon JSON {{?RFC8259}}. However, constraining its use to make it suitable for HTTP header fields required senders and recipients to implement specific additional handling.

For example, JSON has specification issues around large numbers and objects with duplicate members. Although advice for avoiding these issues is available (e.g., {{?RFC7493}}), it cannot be relied upon.

Likewise, JSON strings are by default Unicode strings, which have a number of potential interoperability issues (e.g., in comparison). Although implementers can be advised to avoid non-ASCII content where unnecessary, this is difficult to enforce.

Another example is JSON's ability to nest content to arbitrary depths. Since the resulting memory commitment might be unsuitable (e.g., in embedded and other limited server deployments), it's necessary to limit it in some fashion; however, existing JSON implementations have no such limits, and even if a limit is specified, it's likely that some header field definition will find a need to violate it.

Because of JSON's broad adoption and implementation, it is difficult to impose such additional constraints across all implementations; some deployments would fail to enforce them, thereby harming interoperability.

Since a major goal for Structured Headers is to improve interoperability and simplify implementation, these concerns led to a format that requires a dedicated parser and serialiser.

Additionally, there were widely shared feelings that JSON doesn't "look right" in HTTP headers.

## Structured Headers don't "fit" my data.

Structured headers intentionally limits the complexity of data structures, to assure that it can be processed in a performant manner with little overhead. This means that work is necessary to fit some data types into them.

Sometimes, this can be achieved by creating limited substructures in values, and/or using more than one header. For example, consider:

~~~
Example-Thing: name="Widget", cost=89.2, descriptions="foo bar"
Example-Description: foo; url="https://example.net"; context=123,
                     bar; url="https://example.org"; context=456
~~~

Since the description contains a list of key/value pairs, we use a Parameterised List to represent them, with the identifier for each item in the list used to identify it in the "descriptions" member of the Example-Thing header.

When specifying more than one header, it's important to remember to describe what a processor's behaviour should be when one of the headers is missing.

If you need to fit arbitrarily complex data into a header, Structured Headers is probably a poor fit for your use case.


# Changes

_RFC Editor: Please remove this section before publication._

## Since the beginning of time

*   This document was created.
