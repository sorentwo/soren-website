%{
  author: "Parker Selbert",
  summary: "Maximizing cache performance when serializing large collections for API endpoints.",
  title: "Journey into Perforated Caching"
}

---

About a year ago it became clear that nearly all of the content Rails was
rendering for me was JSON and not HTML, and it was being regenerated on every
request. Sure, we have wonderful HTTP based caching with [Etags and
Last-Modified][1], but those only work for GET requests that return a single
resource, not a collection of resources.

If you are serving up complex resources with customizable or user specific
attributes you need something more flexible. One solution is composable
per-resource caching, this is my experience implementing and enhancing
performance.

## Cache the JSON

Even with the current breed of native extension backed serializers the process
of serializing from native objects to a string of JSON can take a hefty
percentage of the server's response time. Caches such as in-memory, Memcached,
or Redis readily store a serialized JSON string or a [marshalled object][2].
Always cache the serialized output of `to_json` rather than the native
serialization produced by `as_json`. We can see the performance difference with
an isolated benchmark:

```ruby
require 'active_support/json'
require 'benchmark/ips'
require 'dalli'

client = Dalli::Client.new('localhost', namespace: 'json-bm', compress: true)

object = {
  id: 1000,
  published: false,
  posts: [
    { id: 2000, body: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec a diam lectus. Sed sit amet ipsum mauris. Maecenas congue ligula ac quam viverra nec consectetur ante hendrerit. Donec et mollis dolor. Praesent et diam eget libero egestas mattis sit amet vitae augue. Nam tincidunt congue enim, ut porta lorem lacinia consectetur. Donec ut libero sed arcu vehicula ultricies a non tortor. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aenean ut gravida lorem. Ut turpis felis, pulvinar a semper sed, adipiscing id dolor. Pellentesque auctor nisi id magna consequat sagittis. Curabitur dapibus enim sit amet elit pharetra tincidunt feugiat nisl imperdiet. Ut convallis libero in urna ultrices accumsan. Donec sed odio eros. Donec viverra mi quis quam pulvinar at malesuada arcu rhoncus. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. In rutrum accumsan ultricies. Mauris vitae nisi at sem facilisis semper ac in est.' }
  ]
}

client.set("object-to-json", object.to_json)
client.set("object-as-json", object.as_json)

GC.disable

Benchmark.ips do |x|
  x.report('to_json') { client.get('object-to-json') }
  x.report('as_json') { client.get('object-as-json').to_json }
end
```

```
Calculating -------------------------------------
             to_json      1069 i/100ms
             as_json       507 i/100ms
-------------------------------------------------
             to_json    10581.7 (±12.0%) i/s -     50243 in   5.039299s
             as_json     5089.4 (±0.9%) i/s -      25857 in   5.080955s
```

Storing and retrieving the string is, unsurprisingly, 2.1x faster than
retrieving the marshalled object and stringifying it every time it is
retrieved.

This works wonderfully when caching an individual resource, but caching a
collection makes this approach tricky. When an entire collection is cached as a
single string it locks any cached objects inside where they can't be displayed
individually or shared with other collections. To work around this we need a
collection caching mechanism that is bit more intelligent.

## Pipelining

Typically cached content is retrieved one key at a time. That quickly adds up
to a lot of round trips when you are displaying a lot of cached resources.
Fortunately the caching strategies built into Rails support the ability to read
multiple items from the cache at once using the `read_multi` method.

```ruby
Rails.cache.read_multi 'first-key', 'second-key'
#=> { 'first-key' => '...', 'second-key' => '...' }
```

If `read_multi` doesn't get a hit for a particular key it will eliminate it
from the results hash, leaving a hole in the results:

```ruby
Rails.cache.read_multi 'first-key', 'unknown-key'
#=> { 'first-key' => '...' }
```

The missing key/value pairs leave an indication of what content is missing so
that we can patch in the content that we need. [Prior to rails 4.1.X][3] you would
need to do this manually, but now Rails provides the very clean `fetch_multi`
that handles both reading existing keys and writing whatever is missing.

```ruby
object = { 'first-key' => 123, 'second-key' => 456 }
Rails.cache.fetch_multi('first-key', 'second-key') do |key|
  object[key]
end
```

With a caching strategy like [Dalli][4] reading and writing can each be
pipelined into a single request. This is hugely efficient and gives us a highly
performant way to store and retrieve the elements of a collection we are
caching.

Note: Unfortunately at this time the `dalli` adapter does not support
`fetch_multi`, but I have [submitted a pull request][5] which will hopefully
get it included in future versions. The benchmark presented here uses the branch
which implements `fetch_multi`:

```ruby
require 'dalli'
require 'active_support/json'
require 'active_support/cache'
require 'active_support/cache/dalli_store'
require 'benchmark/ips'

client  = ActiveSupport::Cache::DalliStore.new('localhost', namespace: 'pipelining-bm')
objects = 30.times.inject({}) do |hash, i|
  hash[i.to_s] = { id: i, value: 'abcdefg' }
  hash
end

GC.disable

Benchmark.ips do |x|
  x.report('fetch') do
    objects.each do |key, object|
      client.fetch(key) { object[:value] }
    end

    client.clear
  end

  x.report('fetch_multi') do
    client.fetch_multi(*objects.keys) do |key|
      objects[key][:value]
    end

    client.clear
  end
end
```

```
Calculating -------------------------------------
               fetch        19 i/100ms
         fetch_multi        64 i/100ms
-------------------------------------------------
               fetch      197.7 (±2.0%) i/s -       1007 in   5.094973s
         fetch_multi      638.4 (±1.9%) i/s -       3200 in   5.014111s
```

Pipelining yields over a 3x performance increase, easily the difference between
a 10ms and a 35ms cache retrieval.

## Perforated Caching

The [perforated gem][6] implements the storage and pipelining strategies
outlined above. It provides a small wrapper around a collection that will
automatically pipeline reading and writing when the JSON serialization methods
(`to_json`, `as_json`) are called. There are no constraints on the caching
strategy or serialization libraries you work with, both of these aspects are
configurable (and a fallback `fetch_multi` is provided if the current cache
strategy doesn't support it).

```ruby
require 'perforated'

Perforated.configure do |config|
  config.cache = Rails.cache
end

# Custom key construction strategy takes the current_user (scope)'s role in the
# system as an element of the final key.
class KeyStrategy
  attr_reader :scope

  def initialize(scope)
    @scope = scope
  end

  def expand_cache_key(object, suffix)
    args = [object, scope.role, suffix]
    ActiveSupport::Cache.expand_cache_key(args)
  end
end
```

Wrap the resource collection when returning the response and caching is used
automatically. In this example posts are scoped to what a user has "liked".
There would be potential overlap between posts that different users have liked,
but they could be composed using what has previously been cached.

```ruby
class PostsController < ApplicationController
  def index
    render json: Perforated::Cache.new(posts, strategy).to_json
  end

  private

  def posts
    current_user.liked_posts.limit(30)
  end

  def strategy
    KeyStrategy.new(current_user)
  end
end
```

## The Future of Serialized Caching

Many apps use [ActiveModelSerializers][7] to serialize resources
programmatically rather than declaratively. An essentialy part of the
serialization strategy is how to handle relationships with other resources. The
strategies themself are [extremely well defined][8], but there is only partial
support for properly caching and expiring the serialized resources. This is an
area I'm actively exploring and I hope to hybridize the "perforated" approach
and Rails' "russian doll" caching into a single robust strategy.

In the meantime I hope you'll look into leveraging perforated caching.

[1]: http://edgeguides.rubyonrails.org/caching_with_rails.html#conditional-get-support
[2]: http://ruby-doc.org/core-2.0/doc/marshal_rdoc.html
[3]: https://github.com/rails/rails/commit/36d41a15c35e6f4b698931987b2115e221d0fcfa
[4]: https://github.com/mperham/dalli
[5]: https://github.com/mperham/dalli/pull/380
[6]: https://github.com/sorentwo/perforated
[7]: https://github.com/rails-api/active_model_serializers
[8]: http://jsonapi.org/
