%{
  author: "Parker Selbert",
  summary: "Learn how to effectively layer caching around an API endpoint to yield massive performance gains.",
  title: "Layering API Defenses with Caching"
}

---

This is the story a woefully slow API endpoint. It starts out unprotected and
naive; recalculating the world on every request and vulnerable to floods of
traffic. Like a [castle][castle], defenses must be layered on for degrees of
protection and resiliency. Some layers make the endpoint faster, while other
layers harden it against change. In the end, the endpoint will be well defended
and wickedly fast.

## Starting From the Outside

We'll start with a vanilla Rails app, with simple authentication and a single
endpoint defined for posts. Posts are top level objects that also have an author
and associated comments. The `published` scope limits the response to only
include published posts, and it also pre-loads the associated records. The
endpoint naively generates a brand new JSON payload for every request:

```ruby
class PostsController < ApplicationController
  def index
    posts = current_user.posts.published

    render json: posts.to_json(include: %i[author comments])
  end
end
```

Now we benchmark the results of assaulting this endpoint with [siege][siege].
Siege saturates the endpoint with repeated concurrent requests and measures
performance statistics. The same requests will be used to benchmark all
subsequent modifications, with slight modifications to headers where necessary.
All tests are run in production mode to mimic a real production environment.

```bash
siege -c 10 -r 10 -b 127.0.0.1:3000/posts
```

### Impact

```
Transactions:                    100 hits
Availability:                 100.00 %
Elapsed time:                  10.89 secs
Data transferred:              14.54 MB
Response time:                  1.05 secs
Transaction rate:               9.18 trans/sec
Throughput:                     1.34 MB/sec
Concurrency:                    9.60
Successful transactions:         100
Failed transactions:               0
Longest transaction:            1.43
Shortest transaction:           0.34
```

With the initial benchmark in hand our endpoint is ready for layering on some
defenses.

## The Outer Curtain Wall (HTTP Caching)

The outer layer of defense is [HTTP Caching][httpc]. HTTP caching is the outer
wall, catching hints about what clients have seen and responds intelligently.
If a client has already seen a resource and has retained a reference to the
`Etag` or `Last-Modified` header, then our application can quickly respond with a
`304 Not Modified`. The response won't contain the resource, allowing the
application to do less work overall.

Support for `If-Match` and `If-Modified-Since`, the reciprocals to `Etag` and
`Last-Modified`, respectively, are built into Rails. Controllers have
`fresh_when`, `fresh?`, and `stale?` methods to make HTTP caching simple. Here
we're adding a `stale?` check to the index action:

```ruby
class PostsController < ApplicationController
  def index
    posts = current_user.posts.published

    if stale?(last_modified: posts.latest.updated_at)
      render json: posts.to_json(include: %i[author comments])
    end
  end
end
```

Now we can re-run siege with the `If-Modified-Since` header using the latest
post's timestamp.

```bash
siege -c 10 -r 10 -b -H 'If-Modified-Since: Mon, 19 Oct 2015 14:13:50 GMT' 127.0.0.1:3000/posts
```

### Impact

```
Transactions:                    100 hits
Availability:                 100.00 %
Elapsed time:                   2.82 secs
Data transferred:               0.00 MB
Response time:                  0.27 secs
Transaction rate:              35.46 trans/sec
Throughput:                     0.00 MB/sec
Concurrency:                    9.65
Successful transactions:         100
Failed transactions:               0
Longest transaction:            0.33
Shortest transaction:           0.06
```

The data transfer has plummeted to `0.00 MB` and the elapsed time is `2.82
secs`. This is only possible if the client has already cached the data though.
What if the client doesn't have anything cached locally?

## Turrets & Towers (Document Caching)

When the endpoint is a shared resource that the current client hasn't seen yet
it is still possible to return an entire cached payload. This is action caching
in Rails. Unlike HTTP caching, where the resource is cached by the client,
action caching requires the server to cache the full payload. This is where a
cache like Redis or Memcached comes into play.

Action caching is applicable to any resource that is shared between multiple
users without any customization applied. A `cache` convenience method is
available within every controller, providing a shortcut to the `cache#fetch`
method and automatically scoped to the controller.

```ruby
class PostsController < ApplicationController
  def index
    posts = current_user.posts.published

    if stale?(last_modified: posts.latest.updated_at)
      render json: serialized_posts(posts)
    end
  end

  private

  def serialized_posts(posts)
    cache(posts) do
      posts.to_json(include: %i[author comments])
    end
  end
end
```

Now the test can be re-run, this time without any HTTP cache headers.

```bash
siege -c 10 -r 10 -b 127.0.0.1:3000/posts
```

### Impact

```
Transactions:                    100 hits
Availability:                 100.00 %
Elapsed time:                   0.61 secs
Data transferred:              14.54 MB
Response time:                  0.06 secs
Transaction rate:             163.93 trans/sec
Throughput:                    23.84 MB/sec
Concurrency:                    9.69
Successful transactions:         100
Failed transactions:               0
Longest transaction:            0.09
Shortest transaction:           0.03
```

Believe it or not the response times are even faster. Total elapsed time is down
to `0.61 secs`, but we are back to `14.54 MB` of data transfer. For a high speed
connection the data transfer isn't a problem, but what about mobile devices?

## The Drawbridge (Size Reduction)

Reducing the size of an application's responses isn't quite caching, but a door
on a chain doesn't exactly sound like defense either. Computing responses can be
slow, and the effect of sending large data sets over the wire (particularly to a
mobile device) can have a more pronounced effect on speed.

Summary representations as can be used to broadly represent resources instead of
more detailed representations. Listing a collection only includes a *subset* of
the attributes for that resource. Some attributes or sub-resources are
computationally expensive to provide, and not needed at a high level. To obtain
those attributes the client must fetch a separate *detailed* representation.
Each of these representations can be cached individually, or you may opt to
cache the summary representation and layer on the less frequently accessed
detailed representation.

In our example the posts are being sent along with the author and all of the
comments. Chances are that the client doesn't need all of the comments up front,
so let's eliminate those from the index payload. Note, using a serializer
library like [ActiveModelSerializers][ams] is recommended over passing options
to `to_json`, but we're aiming for clarity.

```ruby
class PostsController < ApplicationController
  def index
    posts = current_user.posts.published

    if stale?(last_modified: posts.latest.updated_at)
      render json: serialized_posts(posts)
    end
  end

  private

  def serialized_posts(posts)
    cache(posts) do
      posts.to_json(include: %i[author])
    end
  end
end
```

Only the `include` block has been changed to omit comments.

### Impact

```
Transactions:                    100 hits
Availability:                 100.00 %
Elapsed time:                   0.62 secs
Data transferred:               4.17 MB
Response time:                  0.06 secs
Transaction rate:             161.29 trans/sec
Throughput:                     6.72 MB/sec
Concurrency:                    9.74
Successful transactions:         100
Failed transactions:               0
Longest transaction:            0.08
Shortest transaction:           0.03
```

The elapsed time is slightly lower, at `0.62 secs`, but the real win is that the
data transfered is down from `14.52 MB` to `4.17 MB`. Over a non-local
connection that will have a significant impact.

## The Gatehouse (Perforated Caching)

So far our endpoint has been considered unchanging. All of a user's posts are
cached together in a giant blob of JSON. Typically, resources that are part of a
collection don't expire all at once. It is probable that most cached posts are
fresh, with only a few stale entries. Perforated caching is the technique of
fetching all fresh records from the cache and only generating stale records. Not
only does this reduce the time our application spends serializing JSON, it also
reduces the stale blobs laying around in the cache waiting to expire.

This behavior is built into `ActiveModelSerializers`, provided caching has been
enabled. We'll simulate it with a private method inside the controller for now.

```ruby
class PostsController < ApplicationController
  def index
    posts = current_user.posts.published

    if stale?(etag: posts, last_modified: posts.latest.updated_at)
      render json: serialized_posts(posts)
    end
  end

  private

  def serialized_posts(posts)
    posts.map do |post|
      cache(post) { post.to_json(include: %i[author]) }
    end.join(',')
  end
end
```

Without sporadically expiring requested objects, you'll see a 100% hit rate for
every request after the first. That makes testing the endpoint a little
misleading, as it will appear slower than action caching and you can't see the
benefit of fine grained caching.

### Impact

```
Transactions:                    100 hits
Availability:                 100.00 %
Elapsed time:                   1.84 secs
Data transferred:               4.17 MB
Response time:                  0.18 secs
Transaction rate:              54.35 trans/sec
Throughput:                     2.26 MB/sec
Concurrency:                    9.71
Successful transactions:         100
Failed transactions:               0
Longest transaction:            0.25
Shortest transaction:           0.08
```

As expected the results are slower, down to `1.84 secs` for the full run. That
is still nearly `10x` faster than the original time of `10.89secs` though, and
it comes with added resiliency against complete cache invalidation.

## The Barbican (Fragment Caching)

Personalized payloads can't be cached in their entirety. Usually some, if not
most, of the payload can be cached and the personalized data is generated during
the request. This situation arises when a cache key would be so specific that
you're generating a cache entry for every user. That's useless and wasteful, not
clever at all!

This is a variant of fragment caching, with a twist. Typically fragment caching
sees each record serialized and fetches a portion of the results to avoid
expensive computations. Well, serializing the record **is** the expensive
computation!

We want to pull the post out of the cache and inject a personalized attribute
directly. In this case, want to indicate whether the client has ever "read" this
post before. The client could be anybody, but the rest of the response is the
same for everybody.

```ruby
class PostsController < ApplicationController
  def index
    posts = current_user.posts.published

    if stale?(last_modified: posts.latest.updated_at)
      render json: serialized_posts(posts)
    end
  end

  private

  def serialized_posts(posts)
    posts.map do |post|
      cached = cache(post) { post.as_json(include: %i[author]) }

      cached[:read_before] = current_user.read_before?(post)
    end.to_json
  end
end
```

### Impact

```
Transactions:                    100 hits
Availability:                 100.00 %
Elapsed time:                   4.08 secs
Data transferred:               0.03 MB
Response time:                  0.40 secs
Transaction rate:              24.51 trans/sec
Throughput:                     0.01 MB/sec
Concurrency:                    9.73
Successful transactions:         100
Failed transactions:               0
Longest transaction:            0.45
Shortest transaction:           0.20
```

Now the post had to be cached with `as_json` instead of `to_json`, so that we
could modify it as a hash and avoid re-serializing it during the request. Even
so, the total runtime only grew to `4.08 secs`, merely 38% of the original naive
runtime. Still, avoid personalizing cached endpoints whenever possible. It is
drastically slower, and introduces a lot of additional complexity.

## Mounting Defenses

Strategic caching can get you a long way, but be sure to employ additional
defenses against ballooning payloads and malicious requests. Practices like rate
limiting and resource pagination are invaluable for maintaining predictable
response times. Relying on a single layer of defense is a performance headache
waiting to happen. Each layer of caching takes a little more effort than the
previous layer, but a couple of layers working together will get you started.

Note: External layers like a [reverse-proxy cache][rpc] can check the contents
of the `Cache-Control` header to fully respond to requests for public resources,
without even touching your application layer. However, this post focused on what
your *application* can do itself, so there weren't any details about that.

[castle]: http://www.exploring-castles.com/medieval_castle_defence.html
[httpc]: http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html
[siege]: https://www.joedog.org/siege-home/
[rpc]: https://www.varnish-cache.org/
[ams]: https://github.com/rails-api/active_model_serializers
