---
layout: default
author: Parker Selbert
summary: Protecting distributed systems with stability patterns
---

> View other enterprise systems with suspicion and distrust—any of them can stab
> you in the back.
> <cite>Michael T. Nygard—"Release It!"</cite>

Invariably modern web applications will use some number of external services,
even when the team doesn't set out to employ service oriented architecture.
There is no denying the ease and reliability of sending email through a
dedicated platform, having all of your videos transcoded by a dedicated system,
or storing masses of data within buckets in the cloud. However, as much as an
external service can simply your infrastructure and ease the burden on your
operations they are outside of your control. Even a database hosted on another
of your own dedicated servers may periodically be beyond the reach of your
application servers. One of the few certainties in computing is that [something
will go wrong][wrong]—you need to be prepared when it does.

## Patterns of Stability

Michael Nygard's [Release It][release-it] is an excellent resource entirely
dedicated to preparing yourself for "when things go wrong". Within the book he
outlines a collection of stability patterns and anti-patterns. All of the
examples target enterprise Java systems, but almost every pattern can be adapted
and applied to other languages, frameworks, or polyglot systems. In this post
we'll focus on applying a few of the stability patterns together within a
distributed Ruby application. Specifically we'll look at what are dubbed the
"circuit breaker", "timeout", and "test harness" patterns—all in an effort to
create an extremely robust circuit breaker.

### Circuit Breaker

> The circuit breaker exists to allow one subsystem to fail without destroying
> the entire system. Furthermore, once the danger has passed, the circuit
> breaker can be reset to restore full function to the system.
>
> ...circuit breakers exist to prevent operations rather than reexecute them.

The concept of circuit breaking hinges on the idea of a stateful breaker, such
as a fuse. In the original metaphor the breaker is a solid state piece of metal
that will either conduct electricity when present, or stop any conduction when
absent. The fuse is a physical artifact that can be inspected and interacted
with. The same premise applies when we port the concept to the world of
software: the system must retain an artifact for further inspection and
interaction.

Let's use a two server system for example. One server acts as a CMS and manages
the data for a business. The other server needs to read from that server and
expose some information publicly.

![some-chart.png]

Ideally the public facing server will cache data coming from the CMS server to
reduce load. What happens if the CMS server goes down or starts serving up
errors instead? That's where our error mitigating circuit breaker will come in.

## A Test Harness

In order to properly test error mitigation we need some chaos—a testing setup
[designed to break unexpectedly][chaos-monkey]. By no coincidence a "devious
test harness" built to break your system is another of the stability patterns
recommended in "Release It!":

> ...create [a] test harnesses to emulate the remote system on the other end of
> each integration point. Hardware and mechanical engineers have used test
> harnesses for a long time. Software engineers have used test harnesses, but
> not as maliciously as they should. A good test harness should be devious. It
> should be as nasty and vicious as real-world systems will be. The test harness
> should leave scars on the system under test. Its job is to make the system
> under test cynical.

So, with the notion of unpredictable behavior firmly in mind let's write some
tests that we can implement our circuit breaker against. We'll start off simple
with some predictable specs to identify expected behavior before getting
chaotic.

```ruby
require 'rack/test'

describe CircuitBreaker do
  include Rack::Test

  class App
    def call(env)
      sleep rand(10)

      status = case rand(2)
        when 0 then 200
        when 1 then 422
        when 2 then 500

      [status, {}, '{}']
    end
  end

  let(:app) { App.new }

  describe 'Deterministic Responses' do
    it 'returns a 200 OK response' do
      get '/'

      expect(last_response).to be_ok
    end
  end
end
```

This may not look like a distributed system, but it does replicate the client
server relationship we need. The spec uses an extremely simple rack app that
sleeps indiscriminately and returns a random response code. We're expecting the
response to be `200 OK`, which will only pass 1/3 of the time. Now let's update
the spec to wrap the `GET` request in a circuit breaker.

```ruby
circuit breaker
```

## Timeout

> If you cannot complete an operation because of some timeout, it is better for
> you to return a result. It can be a failure, a success, or a note that you’ve
> queued the work for later execution.

```ruby
class CacheCircuit
  attr_reader :cache

  def initialize(cache)
    @cache = cache
  end

  # cache with a far-future expiration key
  # mark the corresponding circuit with a shorter cache key
  # check the circuit-key for freshness, respond accordingly
  # use an error to trip the breaker
  # use a timeout to trip the breaker
  def fetch(key, &block)
    breaker = Breaker.new(cache, key)

    if breaker.tripped?
      # try to return a cached value
    else
      if breaker.fresh?
        # return the cached value
      else
        # fetch and re-cache
      end
    end
  end
end
```

```ruby
class Breaker
  attr_reader :cache, :key

  def initialize(cache, key)
    @cache = cache
    @key = key
  end

  def tripped?
  end

  def fresh?
  end
end
```

## Cache States

```
| circuit | cache | result |
| ------- | ----- | ------ |
| closed  | none  | ✓      |
| closed  | fresh | ✓      |
| closed  | stale | ✓      |
| open    | none  | ⨯      |
| open    | fresh | ✓      |
| open    | stale | ✓      |
```

* Existing gems out there?
* Usage of Circuit Breakers at Netflix

---

* Describe the approach to circuit breaking we'll take, implement a simple example
  against the specs
* Add more complexity with the notion of caching
* Add more complexity to the example with sleep & timeout
* Expose the amount branching possible with a decision table (possibly
  implemented as code for testing?)
* Add chaos to the testing regime (sleep, status, cache miss, expiration)
* Point to additional resources (netflix)
* Summary

[wrong]: /wrong
[release-it]: /release-it
[chaos-monkey]: http://techblog.netflix.com/2012/07/chaos-monkey-released-into-wild.html
[netflix-blog]: http://techblog.netflix.com/2011/12/making-netflix-api-more-resilient.html
