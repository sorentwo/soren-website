---
layout: default
author: Parker Selbert
summary: >
  Selectively expiring cached records is essential to maintaining the health of
  large production caches.
tags: rails caching
---

Production applications quickly rack up gigabytes of cached data spanning
hundreds of thousands of cache keys. Most of that data is fresh, but every once
in a while you'll find a particular family of entries is holding stale data.
Databases that large are holding a humongous amount of cached data, which is
being cached for a reason—it is expensive to compute. It would be wasteful to
blow away the entire cache just to recompute a fraction of the data.

There are at least three discrete strategies to solve the issue of expiring
targeted data. Which one to use depends on how the keys have been composed, how
the data was generated, and exactly what has become stale.

### Expiration via Touching

When the cached data is referencing a database record, and has a key that is
based on the timestamp of a record, you can `touch` it to bust the cache. The
next time the data is fetched the key will have expired and you'll get fresh
data. For more in depth information on key composition see [essentials of cache
expiration][ece].

With a narrow collection of records touching is easy and targeted. Large
collections, hybrid caches of multiple models or unbounded range (like every
record in the database) are *not* well suited to purging via touching. When the
situation is right you can use methods like `touch` or `update_all` in Rails to
bump the timestamp on one or more records:

```ruby
child.touch # touch a single record

parent.children.update_all(updated_at: Time.now) # touch all records
```

### Expiration via Targeted Versioning

Occasionally the data in the cache is fresh, but you need a different view of
it. Maybe an API client requires a new field, fewer fields, or more associated
records. In this case there isn't any point in touching the records. Views and
serializers need to be updated, which is your opportunity to bundle the
expiration. This is a job for targeted versioning.

Note the word *targeted* is being used. It is possible to *uniformly* version
the entire cache by updating the namespace. Much like changing an API from `v1`
to `v2`, you prepend the cache with a version. Targeted versioning is similar,
but the version change is scoped to the view or serializer in question. For
caching within a Rails view this is as simple as composing the key from an array
rather than just the model. For example:

```ruby
cache [model, 'v2'] do
  # fragment to cache
end

cache [model, 'v3'] do
  # new fragment to cache
end
```

## Expiration via Selective Purging

Recently, on a client project, a situation arose where a large section of the
cache had to be purged, but neither touching nor versioning would work.

Their application caches large trees of API data, many parts of which contain
embedded user data. The embedded user data includes a few avatar URLs, all of
which were securely checked out from Amazon S3 and have an expiration. A
background job keeps the URLs refreshed, but that hadn't been accounted for in
the cache. The end result was a lot of `403 Forbidden` requests when the browser
tried to load the embedded expired avatars.

Touching won't help here, because the user record isn't cached directly, and
they aren't part of the cache key for the parent record. Versioning isn't well
suited either, as the fields don't need to change, the underlying data is out of
sync. That's a lot of wind up for what I'm about to suggest: delete the exact
keys that have expired.

Avoid purging the entire cache by using a targeted tool like
[delete_matched][dm], as provided by `ActiveSupport::Cache`. Most of the
available caches support matching using regular expressions, though some only
support globbing.

```ruby
Rails.cache.delete_matched("posts/9[0-1]*")
```

_Note: Until [very recently][rdm] my [readthis][rdt] cache for Redis didn't
support `delete_matched` due to concerns about performance and the [evil keys
command][ekc]. The eventual implementation uses `SCAN` and is entirely safe to
use with gigantic databases. The aforementioned client was using Readthis for
caching, driving the need for `delete_matched` to be implemented._

## The Right Expiration Strategy for the Job

Caching is key to a highly performant application, but stale data can be
insidious. Without targeted expiration we start to reach for blunt tools and
expire too broadly. All of the expiration strategies presented here are simple,
and they come up often in a production system. Recognize the situation and
choose the right strategy for the job.

[ece]: https://sorentwo.com/2016-07-11-essentials-of-cache-expiration-in-rails
[dm]: http://api.rubyonrails.org/classes/ActiveSupport/Cache/Store.html#method-i-delete_matched
[rdm]: https://github.com/sorentwo/readthis/blob/master/CHANGELOG.md#v150-2016-07-18
[rdt]: https://github.com/sorentwo/readthis
[ekc]: https://redislabs.com/blog/5-key-takeaways-for-developing-with-redis#.V59KpbVB4qk
