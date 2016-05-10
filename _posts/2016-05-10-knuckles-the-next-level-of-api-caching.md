---
layout: default
author: Parker Selbert
title: Knuckles, The Next Level of API Caching
summary: >
  An introduction into the motiviation and methods behind Knuckles, an extremely
  fast API caching library.
tags: rails caching knuckles
---

<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/2.0.0/Chart.js"></script>

For months I'd been watching [Skylight][skylight] performance metrics for a
couple of critical API endpoints. The response times weren't great, moreover
they were highly unpredictable. The endpoint had some intensive caching, but it
fell flat whenever the cache wasn't warm. When the cache was warm it was still
plagued by massive object allocations and frequent GC pauses. These are
essential API endpoints, serving hundreds of thousands of requests a day. It had
to get better.

## Figuring Out How To Get Better

I've been down this road before with a library called [Perforated][perforated].
The idea behind Perforated is simple, only cache the parts of a collection that
need to be recomputed and stitch the serialized values back together. To that
end, Perforated worked very well. What Perforated lacked were some crucial
optimizations to reduce initial object allocation and provide flexibility. The
architecture of Perforated wasn't composable enough for optimizations to be
added on. It was simply too hard to isolate and instrument each part of the
serialization process. It begged for a rewrite.

The successor to Perforated is called [Knuckles][knuckles]. If that name is
confusing, just know that "Sonic" was already taken. It extends the
functionality of Perforated by adding crucial features like cache customization,
full instrumentation, and an integrated view module. Thanks to rigorous
profiling and benchmarking it also crushes on performance.

## Critical Project Goals

Setting a few goals from the outset helped make design decisions and kept the
project focused. The library is meant to be as fast and lightweight as possible,
which pushed back on feature creep. Here are some of the highest impact
decisions along with the results they yielded.

#### Emphasis on Caching as a Composable Operation

Personalization is a caching roadblock. In a typical system you can't cache a
payload when the content is customized for the current requester. That results
in an untenable one-cache-entry-per-user situation, which isn't useful.

Knuckles breaks the cache process down into discrete stages of a functional
pipeline. Each stage aids in reducing down to a final serialized payload. Stages
can be removed from the pipeline, or new ones can be added. For example, to
handle the personalization conundrum you simply insert an `enhancer` stage that
augments the payload with the current user's information. If a resource is being
served to users with differing privileges then the customizer step can prune
sensitive information before it is served up.

As an example, imagine rendering content for staff and regular users. The only
difference is that staff can see more fields. In this situation, you would cache
everything and then prune the final payload when the request isn't from staff:

~~~ruby
module Knuckles
  module Enhancers
    module StaffEnhancer
      STAFF_ONLY = %w[bookmarks notes tags].freeze

      def self.call(rendered, options)
        scope = options[:scope]

        unless scope.staff?
          rendered.delete_if { |key, _| STAFF_ONLY.include?(key.to_s) }
        end

        rendered
      end
    end
  end
end
~~~

Now the endpoint can be fully cached and serve multiple roles efficiently. Using
this technique, or the opposite wherein personal content is appended to the
payload, there are no limitations on how personalized cached content can be.

#### Reduced Object Instantiation

Rampant object allocations are a massive performance killer for any application.
Unrestricted object creation puts a strain on the garbage collector, hurting
random unrelated requests. A key to the design of Knuckles was promoting
patterns where fewer objects were allocated. Just how many fewer objects? Take a
look at the chart below. These numbers are for the same sizable endpoint running
in production, fully cached.

<canvas id="alloc-chart" width="800" height="400"></canvas>

<script>
  var data = {
    labels: ["Allocated", "Retained"],
    datasets: [
      {
        label: "ams/perforated",
        backgroundColor: "rgba(255,99,132,0.5)",
        borderWidth: 0,
        hoverBackgroundColor: "rgba(255,99,132,0.7)",
        data: [148735, 18203]
      },
      {
        label: "ams/knuckles",
        backgroundColor: "rgba(99,255,132,0.5)",
        borderWidth: 0,
        hoverBackgroundColor: "rgba(99,255,132,0.7)",
        data: [19603, 136]
      }
    ]
  };

  new Chart(document.getElementById('alloc-chart').getContext('2d'), {
    type: 'bar',
    data: data,
    options: { responsive: true }
  });
</script>

The retained value for Knuckles is **136** objects, so low that it isn't even on
the chart. These drastic reductions in object allocation stem from three places:

* **Avoid full model instantiation**—fetch only the exact fields needed to construct
  cache keys. Full model instances are only instantiated after a cache miss
  during a stage called "hydration."
* **Prevent repeated serialization**—combining payloads requires a native data
  structure, minimize the number of string/hash/array transformations while
  constructing the final payload.
* **Mutate whenever possible**—contrary to the overall functional design, each stage
  of the pipeline mutates objects whenever possible. This isn't the functional
  way, but it saves gobs of object allocation. Note that this mutation only
  happens while the payload is being computed, and never effects the original
  data.

#### Custom Serializer with Compatibility

Having spent the past half a year writing Elixir I've come to strongly favor
explicit code over DSLs. That's why the serializer that comes with Knuckles,
called a `view` only uses three methods to construct serialized data.

~~~ruby
PostView = Module.new do
  extend Knuckles::View

  def self.root
    :posts
  end

  def self.data(post, _)
    {id: post.id, title: post.title, tag_ids: post.tags.map(&:id)}
  end

  def self.relations(post, _)
    {tags: has_many(post.tags, TagView)}
  end
end
~~~

All of the data structures, keys, and values must be stated explicitly. There
isn't any surprising pluralization, or obscure incantations to sideload an
association rather than embed it. Views are very simple and designed to stay out
of your way.

There is a built in stage for `ActiveModelSerializers` compatibility, if you're
coming to Knuckles from an existing system. In fact, that's how it was rolled
out to production initially.

## How Are Those Endpoints Now?

It's been several months since Knuckles hit production. I can proudly say that
the 95th percentile response times jumped **4-5x**, with warm requests coming
back in **~31ms** or less. Undoubtedly there were stumbling points while folding
Knuckles in, but the final transition was seamless.

If you're running an app with lagging API endpoints, or endpoints you wish you
could cache, give [Knuckles][knuckles] a try.

[transcon]: drkp.net/papers/txcache-osdi10.pdf
[skylight]: http://skylight.io
[perforated]: https://github.com/sorentwo/perforated
[knuckles]: https://github.com/sorentwo/knuckles
