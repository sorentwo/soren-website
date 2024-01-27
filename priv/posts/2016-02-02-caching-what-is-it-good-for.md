%{
  author: "Parker Selbert",
  summary: "Reaching for an alternative runtime rather than eeking out performance through caching",
  title: "Caching, What is it Good For?"
}

---

<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/1.0.2/Chart.js"></script>

The fact is, caching makes systems more complicated.
Expiration and eviction strategies require planning, foresight, and maintenance.
Caching adds additional dependencies in the form of database(s) that store all the cached data.
It adds more libraries dedicated to caching and communication with said external cache.
Finally, it makes personalizing content unwieldy, rarely worth the extra effort.
All this extra effort is only necessary when a language can't do the heavy lifting for you.

## Look at the Language

Performance without any caching at all has always been possible.
Even for a high traffic site serving dynamic content with sizable payloads, it is entirely attainable.
All that is required is a language that is powerful enough to make it possible.
That language needs to be inherently fast, concurrent, absent of stop-the-world garbage collection pauses, and tolerant in the face of errors.
That language is also likely to be compiled, and not an interpreted scripting language.
Sadly, none of those attributes describe Ruby (MRI), and as a result every production fortified Ruby application must resort to a menagerie of caching for any hope of performance.

Ruby isn't alone in the caching conundrum, it is a common pitfall of all the dynamic languages commonly used on the web.
However, the majority of my caching experience has been focused on fortifying Rails applications, so I'm calling Ruby out.

## Looking Elsewhere

For years I've been following the development of Elixir and using it for hobby projects.
Only recently have I gotten the opportunity to build production systems with it.
Now I'm completely spoiled.
While I can espouse praise for the language, functional programming, the beauty of pattern matching, and the brilliance of the BEAM all day...that probably won't be convincing.
Instead, I'll share a few benchmarks that emphasize the performance gulf between Ruby systems and an Elixir system.

## Comparing Performance

Synthetic benchmarks are a poor measure of anything in the real world.
So, let's not pretend this is a scientific comparison.
Instead, I'll compare the performance of two systems in production serving up equivalent content.
To be fair, the content isn't identical, but that's because the Elixir/Phoenix version can be customized without fear of breaking caching.
The true configuration of each application is non-trivial, and the code is confidential, so I can only share an overview of each.

We will be testing is a typical API endpoint that uses token based authentication and returns JSON side-loaded associations.
Both applications are using Postgres 9.4, and both are hosted on Heroku, but there is a difference in the servers they run on.
The Rails application is running on two Performance-M dynos while the Phoenix application is running on a single 1x Production dyno.

**Ruby/Rails**

* Ruby 2.3 / Rails 4.2.5.1 with ActiveRecord
* Fronted by a Redis cache that combines [Perforated][perf] and [Readthis][read]
* Content serialized with [ActiveModelSerializers][ams], unused with a warm cache
* Tuned to fetch as little data as possible from the database
* All associations are preloaded
* All content is cached as strings, no marshalling or serialization is performed
* All data is generic, not customized to the current user
* The request is paginated to **100** primary records, without a limit on side loads
* The payload is a hefty 160k, un-gzipped

**Elixir/Phoenix**

* Elixir 1.2.1 / Phoenix 1.1
* No entity cache
* All fields are fetched from the database, `SELECT *`
* All JSON responses are serialized on the fly, directly in views
* Includes customized data based on the current user
* The request isn't paginated at all, there are **250** primary records
* The payload is a massive 724k, un-gzipped

The following chart plots the response time in milliseconds when hitting the API endpoint five times.
Be warned, these requests were made to production instances with abnormally large data-sets, so the values are fairly noisy.
The gray line is Rails, the blue is Phoenix.

<canvas id="perf-chart" width="800" height="400"></canvas>

<script>
  var data = {
    labels: ["First", "Second", "Third", "Fourth", "Fifth"],
    datasets: [
      {
        label: "rails",
        fillColor: "rgba(220,220,220,0.2)",
        strokeColor: "rgba(220,220,220,1)",
        pointColor: "rgba(220,220,220,1)",
        pointStrokeColor: "#fff",
        pointHighlightFill: "#fff",
        pointHighlightStroke: "rgba(220,220,220,1)",
        data: [208, 244, 338, 261, 313]
      },
      {
        label: "phoenix",
        fillColor: "rgba(151,187,205,0.2)",
        strokeColor: "rgba(151,187,205,1)",
        pointColor: "rgba(151,187,205,1)",
        pointStrokeColor: "#fff",
        pointHighlightFill: "#fff",
        pointHighlightStroke: "rgba(151,187,205,1)",
        data: [149, 160, 138, 145, 174]
      }
    ]
  };
  var ctx = document.getElementById('perf-chart').getContext('2d');
  var perfChart = new Chart(ctx).Line(data, { responsive: true });
</script>

These response times are *not characteristic* of either system, they are at the extreme upper limit.
Even so, serving up **2.5x** the records with **4.5x** the data, without any caching, the Phoenix API response times are **1.5x-2.5x faster**.

## Stop Squeezing Stones

For several years I focused my effort on squeezing performance out of caching and serialization in the Ruby world.
The libraries I've built have been benchmarked and micro-tuned to attain what felt like blazing fast response times.
On top of the work put into the libraries there was substantial overhead in constructing APIs to work within the confines of caching.
As it turns out, those response times weren't so blazing fast after all.

[perf]: https://github.com/sorentwo/perforated
[read]: https://github.com/sorentwo/readthis
[ams]: https://github.com/rails-api/active-model-serializers
