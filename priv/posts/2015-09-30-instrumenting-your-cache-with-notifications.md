%{
  author: "Parker Selbert",
  summary: "Instrumentation with ActiveSupport::Notifications is a powerful tool, useful for much more than raw performance benchmarking.",
  title: "Instrumenting Your Cache with Notifications"
}

---

ActiveSupport, the utility belt portion of Rails, ships with
[Notifications][an], a module for instrumenting libraries and applications. It
has a simple and highly flexible API that makes it a suitable tool for more than
instrumenting performance.

Many of the gems intended to work with Rails come with built in support for
hooking into Notifications. [Readthis][rd], a Redis based caching library, is
among the gems that have support built in. Provided ActiveSupport is available
Readthis will use Notifications to instrument every cache operation as a
separate event. Because instrumentation is so flexible, Readthis doesn't have
any additional hooks for debugging or configuration for a logger. Here we'll at
a few powerful ways to utilize instrumentation in your app.

## The Basics of Notifications

The Notifications module has [excellent documentation][doc] that is recommended
reading for any Rails developer. However, as a precursor to the use cases we're
about to explore, here are the most important parts:

* Notifications are publish and subscribe operations around a queue.
* Notifications can be subscribed to by name or as a pattern with regular
  expressions. Similarly named notifications can be grouped.
* Notifications are lazy, making them a no-op unless something has registered to
  listen. There is minimal overhead in dispatching events without any
  subscribers.
* Notifications are designed for measuring performance, as such they include
  timing raw timing information through `start` and `finish` times.

To instrument a bit of code all that's required is wrapping it in an
`instrument` block:

```ruby
ActiveSupport::Notifications.instrument('event.namespace', payload) do
  do_something_worth_measuring
end
```

By itself the `instrument` block won't emit any events. However, once some other
part of your application has subscribed to the `event.namespace` event then
metrics will start to be reported. The most straight forward use of
instrumentation is tracking metrics, so let's start there.

## Collecting Cache Performance Metrics

Measuring performance is the primary use case for instrumenting with
notifications, making it a natural starting point. Any service that aggregates
metrics over time, such as [statsd][sd], is perfect for collecting remotely. All
that is required is to subscribe to a pattern that matches any cache operation
and forward the timing measurements to the statsd instance:

```ruby
require 'statsd'

ActiveSupport::Notifications.subscribe(/cache_.*\.active_support/) do |name, start, finish, _, _|
  Statsd.measure(name, finish - start)
end
```

Every time a cache operation is called a new measurement will be emitted. The
service aggregating the metrics will collapse them within the resolution window,
typically a matter of seconds. Using a visualization tool such as [Librato][lb]
or [Graphite][gr] the measurements can then be averaged, have standard deviation
tracked, etc.

## Enhancing Logs With Cache Metrics

There are echelons of logging and log integration within a production
application. Logging can range from robust production level logging to simple
debug statements stuffed into development. Hooking into Rails for production
metrics logging is too complex a topic for this post, instead we'll look at
outputting simpler debugging logs.

There are a wide assortment of loggers in the Rails space, but we'll work with
the vanilla Rails logger here. It makes use of `ActiveSupport::LogSubscriber` to
register and measure runtimes for database and view performance. The APIs used
for logging are wide open, and can be used to include custom values.

```ruby
module Readthis
  class LogSubscriber < ActiveSupport::LogSubscriber

    # LogSubscriber wraps payloads in an Event object, which has convenience
    # methods like `#duration`
    def cache_read(event)
      payload = event.payload

      debug "Readthis: #{payload[:name]} (#{event.duration}) #{payload[:key]}"
    end

    alias_method :cache_write, :cache_read
  end
end

Readthis::LogSubscriber.attach_to :active_support
```

The log subscriber must be "attached" to a particular namespace. With
notifications the namespace is appended to the end of the event name, for
example the `cache_read` event is namespaced as `cache_read.active_support`.

When a `read` or `write` event is emitted you'll have entries like this output
to the logs:

```
Readthis: read (1.74) model/1/12345678
```

## Tracking Cache Hit Rates

Within applications it is common to use `fetch` to retrieve values. Any direct
call to `cache` within a template is really calling `Rails.cache.fetch`. The
benefit of using `fetch` over `read` is that it accepts a block and will use the
result of the block to write a value to the cache if the read is a "cache miss".
Here is a simple example of using `fetch`:

```ruby
cache.fetch('special-info') do
  'Expensive info to be cached'
end
```

If the key `'special-info'` has been cached it will be returned immediately from
a cache `read`, if it is missing it will be written with a `write`. It is
desirable to have a warm cache with a majority of fetches resulting in reads
rather than writes. Notifications can be used to track the hit rate of fetch
operations by comparing raw reads to raw writes. Here is a simplistic class that
uses sets to maintain a list of all keys for read and write operations:

```ruby
require 'set'

module Readthis
  class HitRateInstrumenter
    attr_reader :reads, :writes

    def initialize
      @reads  = Set.new
      @writes = Set.new

      subscribe('cache_read.active_support', @reads)
      subscribe('cache_write.active_support', @writes)
    end

    def hit_rate
      1 - (reads.intersection(writes).length.to_f / reads.length)
    end

    def reset
      @reads.clear
      @writes.clear
    end

    private

    def subscribe(pattern, set)
      ActiveSupport::Notifications.subscribe(pattern) do |_, _, _, _, payload|
        set.add(payload[:key])
      end
    end
  end
end
```

When the class is initialized it subscribes to the events that it cares about
and simply stores the cache key in each set. Later we can compute the hit rate
percentage by comparing the number of keys that are read to the number that are
written.

```ruby
cache = Readthis::Cache.new
instrumenter = Readthis::HitRateInstrumenter.new

cache.fetch('a') { true }
cache.fetch('b') { true }
cache.fetch('a') { true }

instrumenter.hit_rate #=> 0.5
```

## Add Notifications to Your Toolbelt

Notifications are integral to the modularity and re-usability of Rails internals,
and a powerful abstraction to have at your disposal. Reach for them whenever you
need to measure, log, or track events within an application.

[an]: https://github.com/rails/rails
[doc]: http://api.rubyonrails.org/classes/ActiveSupport/Notifications.html
[sd]: https://github.com/etsy/statsd
[lb]: http://librato.com/
[gr]: https://www.hostedgraphite.com/
[rd]: https://github.com/sorentwo/readthis
