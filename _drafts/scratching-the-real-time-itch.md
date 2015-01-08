---
layout: default
author: Parker Selbert
summary: Sometimes you do need to reinvent the wheel
---

- The story of real-time communications
  - Building efflux, the nature of collaboration
- Where an existing platform let us down
  - Reliability - Pushing events would often timeout after 5 seconds
  - Inflexibility - Any payload over a seemingly arbitrary threshhold of 10k
    could not be delivered. It was quite common that the payload included a lot
    of text or numerous URLs.
- The tribulations of rolling your own
  - Websockets and Ruby simply don't play well together. Support for Rack Hijack
    is spotty and only works with certain servers. Even with hijack support
    working you won't scale a threaded server like Puma up to thousands of
    concurrent connections. The Faye project and related libraries provide
    excellent tooling around websockets, but it won't work with Unicorn and
    provides no abstractions at all.
  - Jumping to another stack, such as Node.js or Erlang, is tricky enough by
    itself. On top of the issues with building out a relay you need to support
    additional servers, additional deployments, some sort of pub/sub or message
    broker.
  - Websockets enforce security policies. Not only would it be a bad idea to
    send insecure data from a secure client, it isn't even possible. That means
    the real-time server needs to handle SSL connections, adding another layer
    of complexity. Node isn't natively able to handle secure connections. That
    leaves a solution like stunnel or nginx to terminate SSL, making
    configuration even more complex.
  - Cross domain policies mandate a wildcard certificate or additional CORS
    setup.
  - All messages within the system are acting within a black box without
    instrumentation on connections and performance.
  - This is unquestionably the most expensive way to tackle the issue. The cost
    of even a single developer, who has worked on this exact problem before,
    greatly exceeds subscription fees to an outside service.  Unfortunately no
    such service existed when I went through all of these steps myself.
