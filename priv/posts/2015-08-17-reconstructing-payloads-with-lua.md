%{
  author: "Parker Selbert",
  summary: "Reconstructing cached data into API responses quickly directly from Redis using Lua scripting.",
  title: "Reconstructing Payloads with Lua"
}

---

<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/1.0.2/Chart.js"></script>

Pipelining commands to minimize I/O, optimizing storage on in the database and
minimizing persistence overhead can get you pretty far toward caching bliss.
However, there are still some more speed improvements we can squeeze out. It's
time to look at applying [Lua][lua] scripting to caching operations.

Redis has provided [Lua for scripting][ls] since version `2.6.0`. Typically it
is used for transactional semantics and more advanced queuing behavior. Today we
are going to look at a data driven use-case for executing Lua scripts in Redis.
The possibility to manipulate large volumes of data on the server opens up
avenues of performance that are normally prevented by the I/O heavy nature of
Redis:

> Most Redis work-flows tend to be I/O bound and not CPU bound. Even when you
> see the CPU at 100% it is likely to be all about protocol handling. This is
> almost impossible to avoid as Redis commands are much faster than dealing with
> I/O.  With scripting we can put at much better use our bandwidth and CPU
> power.
>
> <cite>&mdash;[Antirez][ls]</cite>

Wouldn't it be awesome to construct fully prepared API responses directly from
the server? Doing so means fewer commands to execute, fewer I/O operations, less
bytes transfered, fewer objects allocated and less work done on the client.
Let's see how it can be done.

## Only the Very Basics

There are other [primers][rl] on Lua integration, so we'll stay focused on *why*
offloading work to Lua is desirable, and *how* it can be used to speed up data
heavy tasks, rather than the semantics of the language or its integration into
Redis. However, as an extremely specific introduction to Lua scripting for our
use case, here is a high level overview of scripting with Lua in Redis.

* Scripts are written client side and can be sent to the server for immediate
  execution, or stored for later and executed like [prepared statements][ps].
* Scripts have immediate *synchronous* access to data and run extremely fast.
* Scripts dynamically reference keys that are passed in when the script is
  executed, allowing for script re-use without hard coded key values.
* There are limited data constructs available in Lua, so there isn't a Hash
  type. Instead nested data is manipulated with the [table][lt] data type, a
  sort of dense multi-dimensional Array.
* Tables have an index base of `1`. For example, the first key passed can be
  accessed as `KEYS[1]`, instead of `KEYS[0]`.
* A limited number of Lua modules are loaded in Redis, but thankfully json and
  messagepack libraries are included for working with serialized values.

Executing scripts on the server is as simple as using the `EVAL` command, which
can be used from the command line like so:

```bash
redis-cli EVAL 'return redis.call("KEYS", "*")' 0
```

Throughout the rest of this post the examples will all be in Ruby; partially
because we're directly comparing Ruby client performance against Lua on the
server, but also because it's much easier to send dynamic keys.

## Build Something That Really Cooks

Continuing from the post on [hashed caching][hc], we'll investigate the process
of reconstructing a blog post and all of its associated records. For this
example it is assumed that all of the serialized records are stored within
fields where the names are `posts/1`, `authors/1`, etc. The goal is to
efficiently reconstruct the data from multiple hashes into a single payload
where all of the posts, authors, and comments are grouped under common keys,
like so:

```json
{ "authors": [], "comments": [], "posts": [] }
```

The sample data we're working with and the output format are greatly simplified
from actual application data. The purpose of this exercise is to explore the
performance possibilities of using Lua, so the reconstruction process is what
truly matters. Building up [json-api][ja] compliant payloads would be a great
exercise, maybe some other time.

The starting point is a ruby script that performs the following high level
steps:

1. Within a `MULTI` block, fetch the full contents of each hash for each post
   via `HGETALL`.
2. Iterate over the hashes, normalizing the field names and translating the data
   into a Hash of Arrays.

```ruby
# Boilerplate, configuration and data seeding has been left out to emphasize
# the relevant bits of code.

hashes = REDIS.multi do
  ('posts/0'..'posts/30').map { |key| REDIS.hgetall(key) }
end

array_backed_hash = Hash.new { |hash, key| hash[key] = [] }

payload = hashes.each_with_object(array_backed_hash) do |hash, memo|
  hash.each do |key, val|
    root, _ = key.split('/')
    memo[root] << val
  end
end

puts payload.length          #=> 3
puts payload.keys.sort       #=> ['authors', 'comments', 'posts']
puts payload['posts'].length #=> 30
```

Now, with a working reference in place, we can start translating to Lua and
offloading the work. The first step is simply testing that we can pass keys
along to the server and execute the commands we expect:

```ruby
keys = ('posts/1'..'posts/30').to_a

REDIS.eval('return KEYS[1], KEYS[2]', keys) #=> ['posts/1', 'posts/2']
```

That did it, keys were passed in and are available in the `KEYS` table. Next
we'll iterate over all of the keys, fetching the contents of each hash. There
are a few syntactical jumps here, for example usage of `local`, `for`, and
`ipairs`, but nothing tricky is going on. It is all variable declaration and
looping over the `KEYS` table:

```ruby
script = <<-LUA
  local payload = {}

  for _, key in ipairs(KEYS) do
    payload[key] = key
  end

  return cjson.encode(payload)
LUA

REDIS.eval(script, keys) #=> {"posts\/1":"posts\/1",...
```

Note the call to `cjson.encode` for the return value. Without encoding the
return value as a string the table will be returned as `nil`, rather
unintuitively. The `cjson` module is indispensable for client/script interop.

Commands can be executed within scripts through `redis.call`. Using `call` the
script can use the `HGETALL` command for each key to build up the payload.

```lua
local payload = {}

for _, key in ipairs(KEYS) do
  local hash = redis.call('HGETALL', key)
end

return cjson.encode(payload)
```

The final step is to loop over each field/value pair in the hash in order to
construct our desired payload. This is largely a mechanical translation of the
Ruby enumeration we saw earlier. Only the Lua script is being shown here—it's
much more readable with some syntax highlighting.

```lua
local payload = {}

for _, key in ipairs(KEYS) do
  local hash = redis.call('HGETALL', key)

  for index = 1, #hash, 2 do
    local field = hash[index]
    local data  = hash[index + 1]
    local root  = string.gsub(field, '(%a)([/\]%d*)', '%1')

    if type(payload[root]) == "table" then
      table.insert(payload[root], data)
    else
      payload[root] = {data}
    end
  end
end

return cjson.encode(payload)
```

There you have it, the fully translated construction script moved to Lua! The
entire purpose of this exercise is to squeeze out more performance from our
Redis cache. Naturally, it's time to do some benchmarking!

Here the script is being loaded once from an external file through `SCRIPT LOAD`
and then referenced with `EVALSHA` to avoid the overhead of repeatedly sending
the same script to the server.

```ruby
SHA = REDIS.script(:load, IO.read('payload.lua'))

def construct_ruby
  # see above
end

def construct_lua
  REDIS.evalsha(SHA, ('posts/1'..'posts/30').to_a)
end

Benchmark.ips do |x|
  x.report('ruby') { construct_ruby }
  x.report('lua')  { construct_lua }
end
```

The results are impressive, checking iterations per second for pipelined Ruby
and scripted Lua:

<canvas id="speed-chart" width="800" height="400"></canvas>

<script>
  var data = {
    labels: ["Ruby", "Lua"],
    datasets: [
      {
        label: "write speed",
        fillColor: "rgba(151,187,205,0.5)",
        strokeColor: "rgba(151,187,205,0.8)",
        highlightFill: "rgba(151,187,205,0.75)",
        highlightStroke: "rgba(151,187,205,1)",
        data: [2.496, 12.699]
      }
    ]
  };
  var ctx = document.getElementById('speed-chart').getContext('2d');
  var perfChart = new Chart(ctx).Bar(data, { responsive: true });
</script>

## When to Reach for Lua

Lua is your performance go-to whenever you want to minimize round trips,
guarantee atomicity, or process large swaths of data without slurping it into
memory. It is a perfect fit for [reliable queues][rq], [atomic scheduling][as],
and [custom analytics][ca]. It can also be indispensable for processing large
data sets without slurping all of the data back to the client.

A few parting words of caution. Scripts are evaluated atomically, which in the
world of Redis means that no other script or Redis command will be executed in
parallel. It's guaranteed by the single threaded "stop the world" approach.
Consequently, `EVAL` has one major limitation—scripts must be small and fast to
prevent blocking other clients.

[ls]: http://oldblog.antirez.com/post/redis-and-scripting.html
[rl]: http://www.redisgreen.net/blog/intro-to-lua-for-redis-programmers/
[rq]: http://oldblog.antirez.com/post/250
[as]: http://www.mikeperham.com/2015/02/18/sidekiq-pro-2.0/
[ca]: https://tech.bellycard.com/blog/light-speed-analytics-with-redis-bitmaps-and-lua/
[lt]: http://www.lua.org/pil/3.6.html
[hc]: /2015/08/10/efficient-redis-caching-through-hashing.html
[ja]: http://json-api.org
[ps]: https://en.wikipedia.org/wiki/Prepared_statement
[lua]: http://www.lua.org/start.html
