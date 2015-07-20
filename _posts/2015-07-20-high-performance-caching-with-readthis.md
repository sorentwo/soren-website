---
layout: default
author: Parker Selbert
summary: Strategies behind building the fastest ActiveSupport compliant cache with Redis and Ruby.
tags: readthis redis ruby
---

<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/1.0.2/Chart.js"></script>

[Redis][redis] is blazingly fast, amazingly versatile and its use is virtually
ubiquitous among Rails apps. Typically it's being leveraged for background job
processing, pub/sub, request rate limiting, and all manner of other ad-hoc tasks
that require persistence and speed. Unfortunately, its adoption as a cache has
lagged in the shadow of [Memcached][memcached], the longstanding in-memory
caching alternative. That may be due to lingering views on what Redis's
strengths are, but I believe it comes down to a lack of great libraries. That's
precisely what led to writing [Readthis][readthis], an extremely fast caching
library for Ruby and backed by Redis.

Before diving into project goals and implementation details let's look at a
chart comparing the performance of `multi` cache operations across varying cache
libraries. Multi, or pipelined, read/write operations are particularly valuable
for caching with API requests, and an excellent example of where Readthis's
performance excels:

<canvas id="multi-chart" width="800" height="400"></canvas>

<script>
  var data = {
    labels: ["MemoryStore 4.2.0", "Readthis 0.6.2", "Dalli 2.7.2", "RedisActiveSupport 4.0.0"],
    datasets: [
      {
        label: "read-multi",
        fillColor: "rgba(220,220,220,0.5)",
        strokeColor: "rgba(220,220,220,0.8)",
        highlightFill: "rgba(220,220,220,0.75)",
        highlightStroke: "rgba(220,220,220,1)",
        data: [4692.7, 3750.2, 1006.7, 996.7]
      },
      {
        label: "fetch-multi",
        fillColor: "rgba(151,187,205,0.5)",
        strokeColor: "rgba(151,187,205,0.8)",
        highlightFill: "rgba(151,187,205,0.75)",
        highlightStroke: "rgba(151,187,205,1)",
        data: [3915.1, 3290.6, 969.8, 889.0]
      }
    ]
  };
  var ctx = document.getElementById('multi-chart').getContext('2d');
  var perfChart = new Chart(ctx).Bar(data, { responsive: true });
</script>

The [multi benchmark][multi-bench] can be found in the Readthis repository.

The only store faster than Readthis is ActiveSupport's in memory storage, which
isn't persisted to a database at all. Throughout the rest of this post we'll
look at the high level goals that made this performance possible, and examine
some of the specific steps taken to achieve it.

## High Level Goals

Writing a new implementation of existing software begins with setting high level
goals. These goals establish how the library will be differentiated from the
alternatives and provide some metrics of success. As there was already a Redis
backed cache available in [redis-store][redis-store], and an extremely popular
Memcached library in [dalli][dalli], setting the initial goals was quite
straight forward.

* **Lightweight** - Aside from Redis there is no need for external dependencies.
  Keep the gem as portable as possible and avoid requiring the `ActiveSupport`
  beast while still supporting integration points with Rails apps.
* **Speedy** - Raw speed with a low impact on memory is the ultimate focus.
  Start benchmarking and profiling right from the beginning so that the impact
  of each change can be measured.
* **Pooled** - Many apps use a single global connection to Redis, which is a
  cause for contention in multi-threaded systems. Follow Dalli's lead and
  leverage connection pooling to increase throughput.
* **Well Tested** - Caching is a critical component in production systems. Each
  code path needs to be exercised so that changes and optimizations can be made
  with confidence. This is a case where 100% test coverage is necessary.
* **Maintained** - Project maintenance isn't a concrete feature, but it is
  paramount to the trust and adoption of a library. I submitted numerous patches
  to `redis-activesupport` but the pull requests languished for months while
  compatibility drifted away from releases of Rails.

## Identifying Performance Bottlenecks

Once the initial library structure was in place a small suite of benchmark
scripts were created to measure performance and memory usage. As features were
added or enhanced the scripts were used to identify performance bottlenecks,
while also ensuring there weren't any performance regressions.

The initial benchmark results can be broken down into three distinct
bottlenecks: round trips to Redis, marshaling cached data and cache entry
creation. Though there were also other micro-optimizations that presented
themselves, these three areas provided the most obvious gains.

## Mitigating the Redis Round-trip

Redis is extremely fast, but no amount of speed can compensate for wasting time
with repeated calls back and forth between an application and the database. The
round-trip back and forth wastes a lot of CPU time and instantiates additional
objects that will need to be garbage collected eventually. Redis provides
pipelining via the `MULTI` command for exactly this situation.

Readthis uses `MULTI` to complete data setting and retrieval with as few
transactions as possible. Primarily this benefits "bulk" operations such as
`read_multi`, `fetch_multi`, or the Readthis specific `write_multi`. For `fetch`
operations where values are written only when they can't be retrieved, reading
and writing of all values is always performed with two commands, no matter how
many entries are being retrieved.

The most significant gains to pipelining and round-trip performance came through
the use of [hiredis][hiredis]. Hiredis is a Redis adapter written in C that
drastically speeds up the parsing of bulk replies.

```ruby
require 'bundler'

Bundler.setup

require 'benchmark/ips'
require 'readthis'

REDIS_URL = 'redis://localhost:6379/11'
native  = Readthis::Cache.new(REDIS_URL, driver: :ruby,  expires_in: 60)
hiredis = Readthis::Cache.new(REDIS_URL, driver: :hiredis, expires_in: 60)

('a'..'z').each { |key| native.write(key, key * 1024) }

Benchmark.ips do |x|
  x.report('native:read-multi')  { native.read_multi(*('a'..'z')) }
  x.report('hiredis:read-multi') { hiredis.read_multi(*('a'..'z')) }

  x.compare!
end
```

<canvas id="driver-chart" width="800" height="400"></canvas>

<script>
  var data = {
    labels: ["Native Ruby", "Hiredis"],
    datasets: [
      {
        label: "read-multi",
        fillColor: "rgba(220,220,220,0.5)",
        strokeColor: "rgba(220,220,220,0.8)",
        highlightFill: "rgba(220,220,220,0.75)",
        highlightStroke: "rgba(220,220,220,1)",
        data: [1139.0, 3930.4]
      }
    ]
  };
  var ctx = document.getElementById('driver-chart').getContext('2d');
  var perfChart = new Chart(ctx).Bar(data, { responsive: true });
</script>

## Faster Marshalling

Once you eliminate time spent retrieving data over the wire it becomes clear
that most of the wall time is spent marshaling data back and forth between
strings and native Ruby objects. Even when a value being cached is already a
string it is still marshaled as a Ruby string:

```ruby
Marshal.dump('ruby') #=> "\x04\bI\"\truby\x06:\x06ET"
```

For some caching use cases, such as storing JSON payloads, it simply isn't
necessary to load stored strings back into Ruby objects. This insight provided
an opportunity to make the marshaller plug-able, and even bypass serialization
entirely, yielding a significant performance boost. In some implementations,
such as Dalli's, a `raw` option may be set to bypass entry serialization as
well, but the option is checked on every read or write and doesn't provide any
additional flexibility.

Let's look at the script used to measure marshal performance. It illustrates
that configuring the marshaller is as simple as passing an option during
construction. Any object that responds to both `dump` and `load` may be used.

```ruby
require 'bundler'

Bundler.setup

require 'benchmark/ips'
require 'json'
require 'oj'
require 'readthis'
require 'readthis/passthrough'

REDIS_URL = 'redis://localhost:6379/11'
OPTIONS   = { compressed: false }

readthis_pass = Readthis::Cache.new(REDIS_URL, OPTIONS.merge(marshal: Readthis::Passthrough))
readthis_oj   = Readthis::Cache.new(REDIS_URL, OPTIONS.merge(marshal: Oj))
readthis_json = Readthis::Cache.new(REDIS_URL, OPTIONS.merge(marshal: JSON))
readthis_ruby = Readthis::Cache.new(REDIS_URL, OPTIONS.merge(marshal: Marshal))

HASH = ('a'..'z').each_with_object({}) { |key, memo| memo[key] = key }

Benchmark.ips do |x|
  x.report('pass:hash:dump') { readthis_pass.write('pass', HASH) }
  x.report('oj:hash:dump')   { readthis_oj.write('oj',     HASH) }
  x.report('json:hash:dump') { readthis_json.write('json', HASH) }
  x.report('ruby:hash:dump') { readthis_ruby.write('ruby', HASH) }

  x.compare!
end

Benchmark.ips do |x|
  x.report('pass:hash:load') { readthis_pass.read('pass') }
  x.report('oj:hash:load')   { readthis_oj.read('oj') }
  x.report('json:hash:load') { readthis_json.read('json') }
  x.report('ruby:hash:load') { readthis_ruby.read('ruby') }

  x.compare!
end
```

The results, in prettified chart form:

<canvas id="marshal-chart" width="800" height="400"></canvas>

<script>
  var data = {
    labels: ["Passthrough", "Oj", "JSON", "Marshal"],
    datasets: [
      {
        label: "load",
        fillColor: "rgba(220,220,220,0.5)",
        strokeColor: "rgba(220,220,220,0.8)",
        highlightFill: "rgba(220,220,220,0.75)",
        highlightStroke: "rgba(220,220,220,1)",
        data: [11347.3, 9033.5, 7646.7, 7873.1]
      },
      {
        label: "dump",
        fillColor: "rgba(151,187,205,0.5)",
        strokeColor: "rgba(151,187,205,0.8)",
        highlightFill: "rgba(151,187,205,0.75)",
        highlightStroke: "rgba(151,187,205,1)",
        data: [7771.4, 10413.1, 8456.5, 7695.7]
      }
    ]
  };
  var ctx = document.getElementById('marshal-chart').getContext('2d');
  var perfChart = new Chart(ctx).Bar(data, { responsive: true });
</script>

This benchmark demonstrates the relative difference between serialization
modules when working with a small hash. Performance varies for other primitives,
such as strings, but the pass-through module is always fastest for load
operations. This makes sense as there aren't any additional allocations being
made, the string that is read back from Redis is returned directly.

When you can get away with it, which is any time you're only working with
strings, the pass-through module provides an enormous boost in load performance.
Otherwise, if you are only working with basic types (strings, arrays, numbers,
booleans, hashes) then there are gains to be made with [Oj][oj], particularly
during `dump` operations.

# Entity Storage

All of the caches built off of `ActiveSupport::Cache` rely on the `Entry` class
for wrapping values. The `Entry` class provides a base for serialization,
compression, and expiration tracking. Every time a new value is read or written
to the store a new entry is initialized for the value.

When working with Redis not all of the entry class's functionality is necessary.
For instance, some stores, such as `FileStore` or `MemoryStore` require
per-entry expirations to evict stale cache entries. Redis has built in support
for expiration and can avoid wrapping individual entries. By not wrapping each
cache entry Readthis can use pure methods and avoid instantiating additional
objects.

In synthetic benchmarks the performance gains are negligible (and it makes for a
very boring chart), but there is a direct reduction in the number of objects
allocated. That savings adds up across thousands of requests, aiding in fewer GC
pauses.

# Lessons to be Learned

Ignoring the implementation details between Redis and Memcached there isn't
anything preventing other caches from benefiting from these techniques.
Everybody benefits from healthy competition. There is always room for
improvement and I hope to see Readthis pushed further.

Use Redis for your next project and give [Readthis][readthis] a try!

[readthis]: https://github.com/sorentwo/readthis
[redis]: http://redis.io
[hiredis]: https://github.com/redis/hiredis
[memcached]: http://www.memcached.org/
[redis-store]: https://github.com/redis-store/redis-activesupport
[dalli]: https://github.com/mperham/dalli
[oj]: https://github.com/ohler55/oj
[multi-bench]: https://github.com/sorentwo/readthis/blob/master/benchmarks/multi.rb
