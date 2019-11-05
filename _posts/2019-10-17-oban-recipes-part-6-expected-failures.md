---
layout: default
author: Parker Selbert
title: "Oban Recipes Part 6: Expected Failures"
summary: >
  Using protocols to control notifications for expected Oban job failures.
tags: elixir oban
---

The [first post][part1] details what [Oban][oban] is, what you may use it for, and what inspired this series—it may be helpful to read that before jumping into the recipe here!

## Handling Expected Failures

Reporting job errors by sending notifications to an external service is essential to maintaining application health.
While reporting is essential, noisy reports for flaky jobs can become a distraction that gets ignored.
Sometimes we _expect_ that a job will error a few times.
That could be because the job relies on an external service that is flaky, because it is prone to race conditions, or because the world is a crazy place.
Regardless of _why_ a job fails, reporting every failure may be undesirable.

### Use Case: Silencing Initial Notifications for Flaky Services

One solution for reducing noisy error notifications is to start reporting only after a job has failed several times.
Oban uses [Telemetry][tele] to make reporting errors and exceptions a simple matter of attaching a handler function.
In this example we will extend [Honeybadger][hb] reporting from the [Oban.Telemetry documentation][obt], but account for the number of processing attempts.

To start, we'll define a `Reportable` [protocol][pro] with a single `reportable?/2` function:

```elixir
defprotocol MyApp.Reportable do
  @fallback_to_any true
  def reportable?(worker, attempt)
end

defimpl MyApp.Reportable, for: Any do
  def reportable?(_worker, _attempt), do: true
end
```

The `Reportable` protocol has a default implementation which always returns `true`, meaning it reports all errors.
Our application has a `FlakyWorker` that's known to fail a few times before succeeding.
We don't want to see a report until after a job has failed three times, so we'll add an implementation of `Reportable` within the worker module:

```elixir
defmodule MyApp.FlakyWorker do
  use Oban.Worker

  defimpl MyApp.Reportable do
    @threshold 3

    def reportable?(_worker, attempt), do: attempt > @threshold
  end

  @impl true
  def perform(%{email: email}) do
    MyApp.ExternalService.deliver(email)
  end
end
```

The final step is to call `reportable?/2` from our application's error reporter, passing in the worker module and the attempt number:

```elixir
defmodule MyApp.ErrorReporter do
  alias MyApp.Reportable

  def handle_event(_, _, %{attempt: attempt, worker: worker} = meta, _) do
    if Reportable.reportable?(worker, attempt)
      context = Map.take(meta, [:id, :args, :queue, :worker])

      Honeybadger.notify(meta.error, context, meta.stack)
    end
  end
end
```

Attach the failure handler somewhere in your `application.ex` module:

```elixir
:telemetry.attach("oban-errors", [:oban, :failure], &ErrorReporter.handle_event/4, nil)
```

With the failure handler attached you will start getting error reports **only after the third error**.

### Giving Time to Recover

If a service is especially flaky you may find that Oban's default backoff strategy is too fast.
By defining a custom `backoff` function on the `FlakyWorker` we can set a linear delay before retries:

```elixir
# inside of MyApp.FlakyWorker

@impl true
def backoff(attempt, base_amount \\ 60) do
  attempt * base_amount
end
```

Now the first retry is scheduled `60s` later, the second `120s` later, and so on.

### Building Blocks

Elixir's powerful primitives of behaviours, protocols and event handling make flexible error reporting seamless and extendible.
While our `Reportable` protocol only considered the number of attempts, this same mechanism is suitable for filtering by any other `meta` value.

Explore the [event metadata][meta] that Oban provides for job failures to see how you can configure reporting by by worker, queue, or even specific arguments.

#### More Oban Recipes

* [Oban Recipes Part 1: Unique Jobs][part1]
* [Oban Recipes Part 2: Recursive Jobs][part2]
* [Oban Recipes Part 3: Reliable Scheduling][part3]
* [Oban Recipes Part 4: Reporting Progress][part4]
* [Oban Recipes Part 5: Batch Jobs][part5]
* [Oban Recipes Part 7: Splitting Queues][part7]

[oban]: https://github.com/sorentwo/oban
[tele]: https://github.com/beam-telemetry/telemetry
[hb]: https://www.honeybadger.io/
[obt]: https://hexdocs.pm/oban/Oban.Telemetry.html#module-examples
[pro]: https://hexdocs.pm/elixir/Protocol.html
[meta]: https://hexdocs.pm/oban/Oban.Telemetry.html#content
[part1]: /2019/07/18/oban-recipes-part-1-unique-jobs.html
[part2]: /2019/07/22/oban-recipes-part-2-recursive-jobs.html
[part3]: /2019/08/02/oban-recipes-part-3-reliable-scheduling.html
[part4]: /2019/08/21/oban-recipes-part-4-reporting-progress.html
[part5]: /2019/09/17/oban-recipes-part-5-batch-jobs.html
[part7]: /2019/11/05/oban-recipes-part-7-splitting-queues.html
