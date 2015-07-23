---
layout: default
author: Parker Selbert
summary: Strategies and configuration tips for making the most value out of Redis as a cache
tags: redis devops
---

You're convinced that Redis is the right tool for caching. I whole heartedly
agree, it's amazing! Here are four essential optimizations for leveraging
Redis as a cache in your infrastructure.

## Use a Dedicated Cache Instance

Unlike Memcached, which is multi-threaded, Redis only runs a single thread per
process. Considering the brute speed of Redis a single process seems like plenty
for many workloads. That's until your platform traffic starts rising, background
jobs are firing continuously, pub/sub channels are relaying thousands of
payloads over the network and the cache is being hit continuously. Each request
to Redis is blocking, which can throw off the timing of background jobs or
be an outright bottleneck for a set of load balanced servers.

Configure multiple separate instances of Redis to alleviate pressure on a single
process. Separate instances by workload: one for background jobs, another for
pub/sub and another dedicated to caching. Don't rely on partitioning data into
multiple Redis databases! Each of those databases is still backed by a single
process so all of the same caveats apply.

### To summarize:

* Do use dedicated Redis instances for distinct workloads.
* Do not use databases (`/0`, `/1`, `/2`) to partition workloads.

## Loosen Persistence

> You should care about persistence and replication, two features only available
> in Redis. Even if your goal is to build a cache it helps that after an upgrade
> or a reboot your data are [sic] still there.
>
> <cite>—[Antirez][dinosaur]</cite>

Each Redis instance has its own configuration file and can be tuned according to
the use-case. Caching servers, for example, can be configured to use [RDB
persistence][persistence] to periodically save a single backup instead of AOF
persistence logs. By only taking periodic snapshots of the database RDB
maximizes performance at the expense of up-to-the-second consistency.  For a
hybrid Redis instance that may be storing business critical background jobs data
consistency is paramount. With a cache it is alright to lose some data in the
event of a disaster, after reboot *most* of the cache will be warm and intact.

### To summarize:

* Do optimize cache persistence for speed by favoring RDB over AOF.
* Do not disable persistence entirely, it is valuable for warming the cache
  after an upgrade or restart.

## Manage Memory Effectively

Once you have a Redis instance dedicated to caching you can start to optimize
memory management in ways that don't make sense for a hybrid database. When
ephemeral and long-lived data is co-mingled it is imperative that ephemeral
keys have a TTL and Redis is free to clean up expired keys.

Redis can manage memory in a [variety of ways][lru-cache]. The management
policies vary from never evicting keys (`noeviction`) to randomly evicting a key
when memory is full (`allkeys-random`). Hybridized databases typically use
`volatile-*` policies, which require the presence of expiration values or they
behave identically to `noeviction`. There is another policy that works better
for cache data, `allkeys-lru`. The `allkeys-lru` policy attempts to remove the
less recently used (LRU) keys first in order to make space for the new data
added.

> It is also worth to note that setting an expire to a key costs memory, so
> using a policy like `allkeys-lru` is more memory efficient since there is no
> need to set an expire for the key to be evicted under memory pressure.
>
> <cite>—[Redis Documentation][lru-cache]</cite>

Redis uses an approximated LRU algorithm instead of an exact algorithm. What
this means is that you can conserve memory in favor of inaccuracy by tuning the
number of samples to check with each eviction. Set `maxmemory-samples` to a
low level, say around 5, for "good enough" eviction with a low memory footprint.

### To summarize:

* Do use `allkeys-lru` policies for dedicated cache instances. Let Redis manage
  key eviction by itself.
* Do not set `expire` for keys, it adds additional memory overhead per key.
* Do tune the precision of the LRU algorithm to favor speed over accuracy. Redis
  does not pick the best candidate for eviction, it samples a small number of
  keys and chooses the entry with the oldest access time.

## Utilize Intelligent Caching

> Because of Redis data structures, the usual pattern used with memcached of
> destroying objects when the cache is invalidated, to recreate it from the DB
> later, is a primitive way of using Redis.
>
> <cite>—[Antirez][stack]</cite>

Only storing serialized HTML or JSON as strings, the standard way of caching for
web applications, doesn't fully utilize Redis as a cache. One of the great
strengths of Redis over Memcached is the rich set of data structures available.
Ordered lists, structured hashes, and sorted sets are particularly useful
caching tools only available through Redis. Caching is more than stuffing
everything into strings.

Let's look at the Hash type for a specific example. Instead of storing objects
as a serialized string you can store the object as fields and values available
through a single key. Using a Hash saves web servers the work of fetching an
entire serialized value, de-serializing it, updating it, re-serializing it, and
finally writing it back to the cache. Eliminating that flow for every minor
update pushes the work into Redis and out of your applications, where it is
supposed to be.

### To Summarize:

* Do use the native Redis types wherever possible (`list`, `set`, `zset`,
  `hash`).
* Do not use the `string` type for structured data, reach for a `hash`.

Happy optimizing. Go forth and cache!

[stack]: http://stackoverflow.com/questions/23601622/if-redis-is-already-a-part-of-the-stack-why-is-memcached-still-used-alongside-r
[dinosaur]: http://stackoverflow.com/questions/2873249/is-memcached-a-dinosaur-in-comparison-to-redis
[lru-cache]: http://redis.io/topics/lru-cache
[persistence]: http://redis.io/topics/persistence
