---
layout: default
author: Parker Selbert
summary: >
  Learn lessons of stability and reliability through an exploration of
  how the Ruby Redis client manages reconnection.
tags: ruby, redis
---

Recently a new user of the [Readthis][rdt] caching library inquired about where
to force Redis to reconnect after the application booted:

> When restarting unicorn with the USR2 signal, a new master is created and
> workers are forked off. In my config/unicorn.rb, before switching to readthis,
> I had `Rails.cache.reconnect` to reconnect to redis after forking. I believe
> this was an implementation of the redis-store gem, which you aren't using
> here.
>
> How would you suggest I reconnect the unicorn worker to the redis-based cache
> with readthis? Thanks!
>
> <cite>&mdash;[Justin Downing][jdi]</cite>

The [good news][i414] is, after `redis-rb 3.1.0` you [don't need to][rcl]
manually reconnect your redis clients. In fact, it isn't desirable to do so! It
was common, historically, to force a Redis reconnect after a Unicorn or Puma
cluster forked off child workers. That was in order to avoid sharing the same
socket between multiple processes, a recipe for unpredictable behavior and
general mayhem. The alternative to manually reconnecting was an error from Redis
warning you about the insanity that would ensue:

> Tried to use a connection from a child process without reconnecting. You need
> to reconnect to Redis after forking or set :inherit_socket to true.

Reconnecting after a child forks is just one of the errors that the Redis client
will automatically recover from. This post aims to provide some more context and
a whiff of exploration into how the redis client heals itself.

## Stealing the Fork Safety Test

For proof of the reconnection claim and a concrete point of reference we'll
co-opt an example from the `redis-rb` [test suite][rts]. Borrowing from the
`fork_safety_test`:

```ruby
require "redis"

redis = Redis.new
redis.set("foo", 1)

child_pid = fork do
  begin
    redis.set("foo", 2)
  rescue Redis::InheritedError
    exit 127
  end
end

_, status = Process.wait2(child_pid)

puts status.exitstatus #=> 0
puts redis.get("foo")  #=> "2"
```

The code snippet starts out by instantiating a client in the parent process. It
then forces a connection to be established by calling `set`. The Redis client is
lazy, so it will only establish a connection the first time a command is sent—
without this initial connection before the fork there wouldn't be any socket
inheritance to test. Immediately after setting the value `1` a child process is
forked, inheriting the parent's Redis instance, connection and all.

After waiting for the process to return we can see that it exited without a
problem, returning a happy `0` status. Additionally, the child's `set` command
was successful in overwriting `foo` with the value `2`, so we know everything
worked as expected.

## Accomplishing Resiliency

How does the client know to reconnect after a fork? It's relatively simple. All
commands executed by the client are centralized, passing through a chain of base
methods. It is within this method chain that common behavior such as logging and
connection management are guaranteed. The abbreviated flow of methods looks
like:

```
call -> process -> ensure_connected
```

The `redis-rb` source is idiomatic, straight forward, and an excellent place to
learn about connections and the Redis command protocol. It is, however, too
verbose to include verbatim in this post, so the code sample has been modified
from its original context for clarity.

The `ensure_connected` method is, predictably, where the reconnection magic
happens:

```ruby
# lib/redis/client.rb#334

def ensure_connected
  attempts = 0

  begin
    attempts += 1

    if connected?
      unless inherit_socket? || Process.pid == @pid
        raise InheritedError, INHERITED_MESSAGE
      end
    else
      connect
    end

    yield
  rescue BaseConnectionError
    disconnect

    if attempts <= @options[:reconnect_attempts] && @reconnect
      retry
    else
      raise
    end
  rescue Exception
    disconnect
    raise
  end
end
```

Within a `begin/retry` block the connection is verified and the current PID is
compared to the PID from when the connection was established. If the PID is
different then the process has since forked and an `InheritedError` is raised.
`InheritedError` is one of numerous specific connection errors that inherit from
`BaseConnectionError`:

```ruby
# lib/redis/errors.rb#37

# Raised when the connection was inherited by a child process.
class InheritedError < BaseConnectionError
end
```

When `BaseConnectionError` is rescued there is an immediate disconnect, dropping
the connection and clearing the old PID. Provided the reconnect attempt is lower
than the reconnect limit, the block is retried and a new connection is
established. The reconnection mechanism is guarded by tracking the number of
attempts. It is guaranteed not to reconnect infinitely when faced with
persistent connection errors.

By centralizing the execution of commands, the client keeps connection
management simple and understandable.

## Forget About It

Stop worrying about managing your application's connections to Redis. Problems
with a network outage, unexpectedly closed connection, or an inherited socket
error? Not a problem, the Ruby client for Redis has you covered.

[rdt]:  https://github.com/sorentwo/readthis
[jdi]:  https://github.com/sorentwo/readthis/issues/10
[rcl]:  https://github.com/redis/redis-rb/blob/master/CHANGELOG.md#310
[rts]:  https://github.com/redis/redis-rb/tree/master/test
[i414]: https://github.com/redis/redis-rb/pull/414
