%{
  author: "Parker Selbert",
  summary: "Learn the essentials of cache expiration in Rails, and see how fundamental cache key composition is to a performant cache.",
  title: "Essentials of Cache Expiration in Rails"
}

---

The old adage goes "there are only two hard things in software: naming things
and cache expiration." We can all agree, naming things is a doozy. Cache
expiration isn't nearly so difficult. Considering how important caching is to a
performant Rails application, it's well worth learning. With a few fundamental
concepts under your belt there's nothing to it.

Rails comes with caching built in. It is available anywhere you can reference
`Rails`, and as the `cache` method within every controller and view. You don't
have to look far to access the cache. The real work is deciding what to put in
the cache, and how to keep it fresh. A stale cache gives users the sense that
the system is slow or broken, and we don't want that. This is where expiration
comes in. How do we ensure old data is expired?

## Expiring Cached Data

Broadly, there are only three approaches to cache expiration. Each has
overlapping use cases and varying granularity:

1. **Key Based** — Everything that is cached is referenced by a unique name,
   this is the key. The key is composed of parts that uniquely identify a value.
   Often one of those parts is a timestamp or a counter, some value that will
   change when the data that the key represents changes. This is the finest
   level of cache expiration.
2. **Time Based** — When values are cached an expiration time is set as well.
   When the expiration time comes around the value is dropped, and it's time to
   cache a new value. Expirations can be on the order of milliseconds (system
   level), or years (HTTP asset level).
3. **Purging** — This is the nuclear option. Everything is cached using the same
   key, forever, until all of the values are dropped. This isn't as useless as
   it may sound. For example, the `MemoryStore` only retains values as long as
   the parent process is alive. Once the process stops the memory holding cached
   values is released. For applications with data that changes less frequently
   than the application restarts this is a viable option.

Regardless of how values are expired they are always referenced by a key. It all
comes down to keys. The fundamental cache operation is [fetch][fetch], which
checks the cache store for the existence of a key and returns the value it
finds. If the key isn't found it then generates the value, writes it to the
store, and then returns the new value.

The way cache keys are composed is critical to how effectively values are
expired. Compose a key too broadly and the cache is busted more often than it
should be, making it inefficient. A well composed key, or set of keys, smoothes
everything out. Let's look at some recipes for cache key composition, and which
situations they work for.

## Composing Cache Keys

Cache keys are built from unique segments which change when the data they
reference changes. Be aware that the precise structure of the key isn't
important. The order of segments and how they are separated is inconsequential,
so long as they combine into a unique value.

#### Simple

`:class/:id -> Post/1`

The most basic cache key structure possible, only a model name and the `id`. The
parts represent the bare information needed to retrieve a cached value. This
type of key can only be expired by time or a full purge, making it of limited
value in production systems.

#### Timestamped

`:class/:id-:timestamp -> Post/1-1468239686`

A timestamped key appends a model's `updated_at` timestamp in milliseconds. When
the model is updated or [touched][touch], the cache is expired. This is what is
generated for `ActiveRecord` models out of the box. How records are touched, and
whether they [touch associated records][btt], is critical to proper cache
expiration. In the world of `ActiveRecord` it's alright to touch yourself, touch
your friends, and touch your friend's friends.

#### Collection

`:class_plural/:last_updated/:count -> Posts/1468239686/8`

When all of the values in a collection can be cached together you have to
consider more than the ids. Instead, a collection's cache key combines the
timestamp of the most recently updated model in the collection along with the
collection length. If any model within the collection is updated or one is
deleted the cache is expired.

#### Checksummed

`:class/:id/:view/:checksum -> Posts/1/SomeView/a8b56bb`

This includes the name of a view that generated the value and a checksum of the
view at the time the value was created. This guarantees that when new fields or
markup is added to the view that the cache will be expired.

#### Scoped

`:class/:id/:role -> Post/1/staff`

The role of the current user, or "scope", is appended. In this example, staff
see different values than regular users. Appending the scope prevents sensitive
data from leaking to regular users. It also guarantees that both values can be
cached and served up independently.

#### Stapled

`:class/:id/:user_id -> Post/1/123`

Appending the `user_id` generates a new cache entry for each user. Generally
this is undesirable—the cache can't be shared at all, defeating most of the
reason you are trying to cache things. However, in a system with a limited
number of users where data is extremely expensive to generate, this is a viable
option.

## Cache Expiration is Crucial to Performance

Caching is critical to high performance Rails applications. The most fundamental
part of effective caching is expiration, and that hinges almost exclusively on
cache keys. Understanding how to compose keys for different use cases, manage
key based expirations, and keep keys finely scoped is all it takes to master
caching. Expiration is often maligned as being hard, but there isn't much to it.
A sliver of knowledge will get you a long way.

[fetch]: http://www.rubydoc.info/github/sorentwo/readthis/master/Readthis/Cache#fetch-instance_method
[touch]: http://api.rubyonrails.org/classes/ActiveRecord/Persistence.html#method-i-touch
[btt]: http://api.rubyonrails.org/classes/ActiveRecord/Associations/ClassMethods.html#method-i-belongs_to
