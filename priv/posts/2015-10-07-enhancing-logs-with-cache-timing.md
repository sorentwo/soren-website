%{
  author: "Parker Selbert",
  summary: "Enhancing logs with custom timings illuminates where request time is really being spent.",
  title: "Enhanced Logs with Cache Timing"
}

---

Supplemental and ad-hoc logs are helpful for debugging problematic responses,
but they aren't ideal for production logging. For production you need
per-request timing ingrained with standard logging output. These enhanced logs
help effectively analyze trends over time and diagnose production performance.
In this post we'll look at how to measure the performance of caching during a
request and how to shim that into production logging.

All of the examples in this post are written with [Readthis][rd] in mind, but
the technique will work for any instrumented library. In fact, because the event
names are standardized as `cache_{{operation}}.active_support`, these techniques
will work for any `ActiveSupport` cache.

## Case of the Missing Render Times

With standard Rails production logging your request timing is comprised of three
values: `duration`, `view`, and `db`. For basic applications without any
external services or caching the combined `view` and `db` timing is sufficient.
Once your application integrates additional databases such as Memcached,
ElasticSearch, or Redis the standard log output won't tell the whole story.

Below is sample output of a log without any additional timing information. Note
that it is formatted using [Lograge][lr] and has been edited for clarity.

```
method=GET path=/api/posts status=200 duration=55.73 view=27.06 db=21.51
```

All of the render timing is bundled into the view. Any external requests,
including cache or search, are included in the timing. That simply won't do!
Let's get started unpacking those timings.

## Recording Aggregate Cache Runtimes

The linchpin of Rails instrumentation is `Notifications`. If you recall from
[Instrumenting Your Cache With Notifications][iy], it is the module that enables
hooking into any instrumented block to receive timing information. Here is an
how you would write out the timing of every cache event:

```ruby
ActiveSupport::Notifications.subscribe(/cache_/) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  puts "Cache Event Duration: #{event.duration}"
end
```

That example merely writes out the duration to `STDOUT`. Instead, we want to
forward that event to a module that will aggregate the timing for multiple
events.

Remember, the `subscribe` block will be called for every cache event, many of
which can trigger during a single request. Aggregated timings can be recorded
with a small purpose-built module, so long as you're mindful of thread safety.
For multi-threaded servers such as Puma it is crucial that the recording events
is limited to the thread handling the request. Modules are constants, and
constants are global, so we need to use `Thread.current` to store timing values.

```ruby
# config/initializers/readthis.rb

module Readthis
  module Instrumentation
    module Runtime
      extend self

      def runtime=(value)
        Thread.current['readthis_runtime'] = value
      end

      def runtime
        Thread.current['readthis_runtime'] ||= 0
      end

      def reset_runtime
        new_runtime, self.runtime = runtime, 0
        new_runtime
      end

      def append_runtime(event)
        self.runtime += event.duration
      end
    end
  end
end
```

With this module available it is trivial to append new runtimes for cache
events. Instead of writing out the event duration within the subscribe block,
the `append_runtime` method is called with the event.

```ruby
ActiveSupport::Notifications.subscribe(/cache_/) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  Readthis::Instrumentation::Runtime.append_runtime(event)
end
```

## Hooking Into the ActionController Rendering Lifecycle

Augmenting the controller rendering lifecycle isn't at all invasive.
`ActionController` provides a method explicitly for the purpose of fixing
erroneous view runtimes. The [`cleanup_view_runtime`][cvr] hook is called around
rendering, offering a place to remove cache runtime from the full view runtime.

```ruby
# config/initializers/readthis.rb

module Readthis
  module Instrumentation
    module ControllerRuntime
      attr_internal :readthis_runtime

      def cleanup_view_runtime
        before_render = reset_runtime
        runtime       = super
        after_render  = reset_runtime

        self.readthis_runtime = before_render + after_render

        runtime - after_render
      end

      def append_info_to_payload(payload)
        super

        payload[:readthis_runtime] = (readthis_runtime || 0) + reset_runtime
      end

      def reset_runtime
        Readthis::Instrumentation::Runtime.reset_runtime
      end
    end
  end
end
```

Another hook, [`append_info_to_payload`][aip], provides a way to inject
additional runtime information into the event payload. Above we do just that,
append the `readthis_runtime` and reset it for the next request.

The `on_load` hook from `ActiveSupport` is the final piece in gluing everything
together. We can pass a block that will be executed within `ActionController`
after it has finished loading. It is within that block that we include our
`ControllerRuntime` module and subscribe to cache notifications.

```ruby
ActiveSupport.on_load(:action_controller) do
  include Readthis::Instrumentation::ControllerRuntime

  ActiveSupport::Notifications.subscribe(/cache_/) do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)

    Readthis::Instrumentation::Runtime.append_runtime(event)
  end
end
```

## Display Values With Lograge

While it is possible to format Rails' built in logger, we'll use the compact
formatting provided by Lograge. Not only is it compact and easy to read, but it
is simple to modify at configuration time through `custom_options`. Lograge
uses the same instrumentation subscribers as Rails' own logging internals.  The
logging event is passed through with accumulated timings in the payload, which
can be accessed directly.

```ruby
MyApp.Application.configure do |config|
  config.lograge.custom_options = lambda do |event|
    { cache: event.payload[:readthis_runtime] }
  end
end
```

With this addition the log output will look like this now:

```
method=GET path=/api/posts status=200 duration=55.73 view=15.06 db=21.51 cache=11.92
```

## When Enhanced Logging is Available

I initially underestimated the effort involved in piping instrumentation data
into logs. The classes are well documented, cleanly abstracted, and compose
well—but it takes a while to understand how to glue everything together.
Understanding the tools available is the hard part, once you get past that the
effort involved is minimal.

Custom instrumentation and logging should be provided for mature libraries. If
it isn't available, ask for it, or better yet, submit a pull request. Enhanced
logging tools will be rolled into Readthis soon, so augmenting logs with cache
timings is as simple as requiring a module.

[iy]: http://sorentwo.com/2015/09/30/instrumenting-your-cache-with-notifications.html
[lr]: https://github.com/roidrage/lograge
[rd]: https://github.com/sorentwo/readthis
[cvr]: https://github.com/rails/rails/blob/d47438745e34d75e03347b54b604b71b7a92c3ac/actionpack/lib/action_controller/metal/instrumentation.rb#L85
[aip]: https://github.com/rails/rails/blob/d47438745e34d75e03347b54b604b71b7a92c3ac/actionpack/lib/action_controller/metal/instrumentation.rb#L92
