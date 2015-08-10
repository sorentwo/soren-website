---
layout: default
author: Parker Selbert
summary: Boost cache performance and memory consumption in Redis through cache sharding, an intelligent way to utilize the Hash type.
tags: redis
---

<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/1.0.2/Chart.js"></script>

If you spend some time browsing through Redis documentation you'll quickly
stumble upon references to "intelligent caching." Within the context of Redis,
intelligent caching refers to leveraging the [native data types][types] rather
than storing all values as strings. There are numerous examples of this out in
the wild, some using ordered lists, some using sets, and a notable example using
hashes.

## Using Hashes

The inspiration for this post came from the [memory optimization][mo]
documentation for Redis itself:

> Small hashes are encoded in a very small space, so you should try representing
> your data using hashes every time it is possible. For instance if you have
> objects representing users in a web application, instead of using different
> keys for name, surname, email, password, use a single hash with all the
> required fields.
>
> <cite>&mdash;[Redis Documentation][mo]</cite>

Typically Redis string storage costs more memory than Memcached, but it doesn't
have to be that way. Memory consumption, write and read performance can be
boosted by using the optimized storage of the hash data type. Wrapping data in
hashes can be semantically cleaner, much more memory efficient, faster to write,
and faster to retrieve.

Smaller and faster always sound great in theory, let's see if it proves to be true.

## Proving the Concept

Before delving into specific use cases we'll set up some benchmarking and
measurement scripts to verify the hypothesis: bundling values into hashes is
more memory efficient and performant than discrete string storage.

The benchmark, written in Ruby only for the sake of simplicity, performs the
following steps:

1. Flush the database.
2. Generates 1001 structures with 101 randomized string values.
3. Measure the speed of writing each value and each structure.

```ruby
require 'redis'
require 'benchmark'
require 'securerandom'

REDIS = Redis.new(url: 'redis://localhost:6379/11')
REDIS.flushdb

def write_string(obj, index)
  obj.each do |key, data|
    REDIS.set("string-#{key}-#{index}", data)
  end
end

def write_hash(obj, index)
  fields = obj.flat_map { |field, value| [field, value] }
  REDIS.hmset("hash-#{index}", *fields)
end

values = (0..1_000).to_a.map do |n|
  data = SecureRandom.hex(100)

  (0..100).to_a.each_with_object({}) do |i, memo|
    memo["field-#{i}"] = data
  end
end

Benchmark.bm do |x|
  x.report('write_string') do
    REDIS.multi do
      values.each_with_index { |value, index| write_string(value, index) }
    end
  end

  x.report('write_hash') do
    REDIS.multi do
      values.each_with_index { |value, index| write_hash(value, index) }
    end
  end
end
```

The results for one iteration, in seconds, lower is better:

<canvas id="speed-chart" width="800" height="400"></canvas>

<script>
  var data = {
    labels: ["String", "Hash", "Tuned Hash"],
    datasets: [
      {
        label: "write speed",
        fillColor: "rgba(151,187,205,0.5)",
        strokeColor: "rgba(151,187,205,0.8)",
        highlightFill: "rgba(151,187,205,0.75)",
        highlightStroke: "rgba(151,187,205,1)",
        data: [2.10, 0.33, 0.46]
      }
    ]
  };
  var ctx = document.getElementById('speed-chart').getContext('2d');
  var perfChart = new Chart(ctx).Bar(data, { responsive: true });
</script>

With some slight modifications the same script can be used to measure memory
consumption, simply by checking `REDIS.info(:memory)` for each strategy. The
results are consistent across multiple iterations, in megabytes, lower is
better:

<canvas id="mem-chart" width="800" height="400"></canvas>

<script>
  var data = {
    labels: ["String", "Hash", "Tuned Hash"],
    datasets: [
      {
        label: "size",
        fillColor: "rgba(151,187,205,0.5)",
        strokeColor: "rgba(151,187,205,0.8)",
        highlightFill: "rgba(151,187,205,0.75)",
        highlightStroke: "rgba(151,187,205,1)",
        data: [31.27, 33.32, 22.08]
      }
    ]
  };
  var ctx = document.getElementById('mem-chart').getContext('2d');
  var perfChart = new Chart(ctx).Bar(data, { responsive: true });
</script>

This demonstrates a sizable difference between string storage, hash based
storage, and tuned hash based storage (more on that later). With this sample
data the memory savings are nearly 30%. Those are pretty huge savings! Note that
there is a slight trade off between tuned hash entry size and insertion time.

With some slight modification the writing and memory benchmark can also be used
to measure read speed. There isn't any appreciable performance difference for
`HGETALL` between hash entry size, so only one data-point is included.

```ruby
string_keys = (0..1_000).to_a.flat_map do |n|
  (0..100).to_a.map { |i| "string-#{n}-#{i}" }
end

hash_keys = (0..1_000).to_a.map do |n|
  "hash-#{n}"
end

Benchmark.bm do |x|
  x.report('read_string') do
    REDIS.multi do
      string_keys.map { |key| REDIS.get(key) }
    end
  end

  x.report('read_hash') do
    REDIS.multi do
      hash_keys.map { |key| REDIS.hgetall(key) }
    end
  end
end
```

The results for one iteration, in seconds, lower is better:

<canvas id="read-chart" width="800" height="400"></canvas>

<script>
  var data = {
    labels: ["String", "Hash"],
    datasets: [
      {
        label: "size",
        fillColor: "rgba(151,187,205,0.5)",
        strokeColor: "rgba(151,187,205,0.8)",
        highlightFill: "rgba(151,187,205,0.75)",
        highlightStroke: "rgba(151,187,205,1)",
        data: [2.52, 1.87]
      }
    ]
  };
  var ctx = document.getElementById('read-chart').getContext('2d');
  var perfChart = new Chart(ctx).Bar(data, { responsive: true });
</script>

Ignoring the fact that reading over 10,000 items in a single `MULTI` command is
pretty slow, you can see that _relatively_ hash fetching is 26% faster. This is
intuitive, fetching one hundredth as many keys should be faster.

As expected the documentation was right, with a little tuning the hash based
approach can be smaller and faster. There are some caveats though, let's explore
them with a practical example.

## A Practical Example

The original idea as demonstrated uses a [sharding][shard] scheme to bucket
models into hashes based on a model's unique key. This has a wonderful sense of
symmetry and predictability, but doesn't do anything to ensure that the models
are related to each other. The cache only has a finite amount of space and we
want old values to be evicted, so it is desirable to keep all fields within a
hash related. Additionally, there are performance benefits to naively fetching
each hash in its entirety.

For example, imagine an API endpoint that serves up JSON data for blog posts.
Each post would include the author, some comments, and tags. Naturally the
serialized JSON would be cached in order to boost response times. Typically each
post and the associated data would be stored separately, as strings, available
at keys such as `posts/:id/:timestamp`. Instead, with hash based caching, all of
the serialized values are stored inside of a single hash referenced by the
post's key at the top level.

![Cache Hashing](/assets/cache-hashing.png)

When requests come in a post is retrieved from the database, the cache
key generated in the format of `posts/:id/:children/:timestamp`, and if the
cache is fresh there is only a single fetch necessary. Field invalidation for
associated children (authors, comments, etc.), field additions (new comments,
new tags), or field removal (deleted comments) are simply dealt with by using
the number of children and a timestamp within the cache key.

## Logistics & Tuning

Previously I mentioned that there was a significant difference in storage that
was achieved by "tuning." Through the Redis config file, or with the `CONFIG`
command, the storage semantics of most data structures can be configured. In
this case the `hash-max-zipmap-*` values are most important.

> Hashes, Lists, Sets composed of just integers, and Sorted Sets, when smaller
> than a given number of elements, and up to a maximum element size, are encoded
> in a very memory efficient way that uses up to 10 times less memory.
>
> <cite>&mdash;[Redis Documentation][mo]</cite>

As long as the `hash-max-zipmap-value` size is larger than the maximum value
being stored in a hash then storage will be optimized. For caching it is
recommended that you use a particularly aggressive value, at least 2048-4096b.

Fields within a hash can't have individual expiration, only the hash key itself.
Bundling related fields together allows the entire hash to be treated as a
single unit, eventually falling out of memory entirely when it is no longer
needed—this means that it is preferable to use Redis as an LRU cache. We're
[already doing that though][optimizing], right?

Bundling serialized data for associated models is just one way to utilize the
native hash type for intelligent caching. Custom caching schemes require more
explicit and purposeful schemes for organizing data, but can be far more
rewarding than naive key/value storage.

[types]: http://redis.io/topics/data-types-intro
[mo]: http://redis.io/topics/memory-optimization
[shard]: https://en.wikipedia.org/wiki/Shard_%28database_architecture%29
[optimizing]: /2015/07/27/optimizing-redis-usage-for-caching.html
[br]: https://digitalserb.me/writing-a-redis-client-in-pure-bash/
