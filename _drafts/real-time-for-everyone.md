---
layout: default
author: Parker Selbert
summary: Sometimes you do need to build a new wheel
---

Many modern web and mobile apps rely heavily on real-time communication to
provide a fast and consistent experience to users. Entire categories of
applications would limp along without the ability to broadcast new data out to
everybody connected. Imagine collaboration tools, live editors, sports scores,
and stock tickers all stuck polling for changes.

Recently I led a team that overhauled a client side experience to handle a
continuous flow of data from everybody participating in the project. Speed,
consistency and reliability were critical for the new implementation's success.
Naturally we turned to Pusher, but we didn't get what we were looking for.

## Where an Existing Platform Let Us Down

Of course we tried the existing industry standard solution first. Configuration
and setup was simple enough, but it quickly fell over with even a modest
workload. What follows are only a few of the problem areas that we encountered.

### Reliability

Broadcasting events would *often* timeout after 5 seconds. More accurately,
"often" means up to 30% of the time. To combat unpredictability and latency,
events were broadcast in the background and automatically retried. Automatic
retries may assuage timeouts over time, but they introduce rampant race
conditions. Imagine a scenario where an event that added some data fails to send
but the subsequent event that removes that data sends immediately?

### Inflexibility

Any payload over a seemingly arbitrary threshold of 10 kilobytes could not be
delivered. It was quite common that a JSON payload included a lot of text,
lengthy URLs, or numerous associations for sideloading. Engineering solutions
to this problem such as compressing data or only sending a delta are possible,
but neither are foolproof and introduce more complexity.

## The Tribulations of Rolling Your Own

All developers are prone to bouts of [NIH Syndrome][nih]. Surely our team can
implement a websocket solution ourselves?

### Why Not Stick With Ruby?

Websockets and [MRI][mri] simply don't play well together. Support for [Rack
Hijack][hijack] is spotty and only works with certain servers. Even with hijack
support working you won't scale a threaded server like Puma up to thousands of
concurrent connections. The [Faye][faye] project and related libraries provide
excellent tooling around websockets, but it won't work with Unicorn and provides
no abstractions or instrumentation at all.

### Use Another Stack Instead?

Jumping to another stack, such as Node.js or Erlang, is tricky enough by itself.
On top of the issues with building out a relay you need to support additional
servers, additional deployments, some sort of pub/sub or message broker. That is
a lot of added complexity to distract your team from building your primary
product.

Websockets enforce [security policies][wssec]. Yes, it is a bad idea to send
insecure data from a secure client, fortunately it isn't even possible. That
means the real-time server needs to handle SSL connections, adding another layer
of complexity. Node isn't natively able to handle secure connections. That
leaves a solution like [stunnel][stunnel] or [nginx][nginxssl] to terminate SSL,
making configuration even more complex. Additionally cross domain policies
mandate a wildcard certificate or additional [CORS][cors] setup.

### What's Going on in There?

Without additional engineering effort all messages within the system are zipping
around within a black box. There isn't any instrumentation on connections or
performance. Tracking connection activity and messaging is just as important as
monitoring HTTP traffic. Now it's time to get [statsd][statsd] involved too!

## Introducing Snö

Building and maintaining your own solution is unquestionably the most expensive
way to tackle the issue. The cost of a single developer (one who has worked on
this exact problem before and knows precisely what to build) greatly exceeds
subscription fees to an outside service for years. No suitable service or stack
existed when I went through all of these steps.

That is why we're introducing [Snö][sno], a reliable platform for websites and
apps that need real time messaging. Please take a look. If you like what you see
sign up for the waitlist, we'll let you know how it progresses.

[mri]: https://en.wikipedia.org/wiki/Ruby_MRI
[hijack]: https://github.com/rack/rack/pull/481
[faye]: http://faye.jcoglan.com/ruby/websockets.html
[wssec]: http://blog.kaazing.com/2012/02/28/html5-websocket-security-is-strong/
[stunnel]: https://www.stunnel.org/index.html
[nginxssl]: http://nginx.com/resources/admin-guide/nginx-ssl-termination/
[cors]: https://en.wikipedia.org/wiki/Cross-origin_resource_sharing
[statsd]: https://github.com/etsy/statsd
[sno]: http://snoapp.io
[nih]: https://en.wikipedia.org/wiki/Not_invented_here
