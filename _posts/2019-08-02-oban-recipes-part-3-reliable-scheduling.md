---
layout: default
author: Parker Selbert
title: "Oban Recipes Part 3: Reliable Scheduling"
summary: >
  Patterns for recursively scheduled jobs without any duplication and the
  mechanisms that make it possible.
tags: elixir oban
---

The [first post][part1] details what [Oban][oban] is, what you may use it for, and what inspired this series—it may be helpful to read that before jumping into the recipe here!
This recipe also picks up where we left off with [recursive jobs in the second post][part2], so be sure to check that out as well.

## Reliable Scheduled Jobs

A common variant of recursive jobs are "scheduled jobs", where the goal is for a job to repeat indefinitely with a fixed amount of time between executions.
The part that makes it "reliable" is the guarantee that we'll keep retrying the job's business logic when the job retries, but we'll **only schedule the next occurrence once**.
In order to achieve this guarantee we'll make use of a [recent change in Oban][pr] that allows the `perform` function to receive a complete `Oban.Job` struct.

Time for illustrative example!

### Use Case: Delivering Daily Digest Emails

When a new user signs up to use our site we need to start sending them daily digest emails.
We want to deliver the emails around the same time a user signed up every, repeating every 24 hours.
It is important that we don't spam them with duplicate emails, so we ensure that the next email is only scheduled on our first attempt.

```elixir
defmodule MyApp.ScheduledWorker do
  use Oban.Worker, queue: :scheduled, max_attempts: 10

  @one_day 60 * 60 * 24

  @impl true
  def perform(%Oban.Job{attempt: 1, args: args}) do
    args
    |> new(schedule_in: @one_day)
    |> Oban.insert!()

    perform(args)
  end

  def perform(%{"email" => email}) do
    MyApp.Mailer.deliver_email(email)
  end
end
```

You'll notice that the first `perform/1` clause only matches a job struct on the first attempt.
When it matches, the first clause schedules the next iteration immediately, _before_ attempting to delver the email.
Any subsequent retries fall through to the second `perform/1` clause, which only attempts to deliver the email again.
Combined, the clauses get us close to **at-most-once semantics for scheduling**, and **at-least-once semantics for delivery**.

### Made Possible With Module Hooks

The interesting thing that is happening here is that `perform/1` can handle either an `Oban.Job` struct, or the args map directly.
This is possible because of a "before compile" module hook in the `Oban.Worker` module.
Below is a simplified version of the [worker module][wm] with extraneous code removed to emphasize the `@before_compile` hook:

```elixir
defmacro __before_compile__(_env) do
  quote do
    def perform(%Job{args: args}), do: perform(args)
  end
end

defmacro __using__(opts) do
  quote location: :keep do
    @before_compile Oban.Worker
  end
end
```

When your module uses `Oban.Worker` it includes the args extraction clause in the compiled module _before_ your definition of `perform/1`.
For example, if your worker defines a `perform` clause to work with an email address there would be two compiled clauses:

```elixir
def perform(%{email: email}), do: work_with_email(email)
def perform(%Job{args: args}), do: perform(args)
```

The additional clause ensures that your perform can accept either a struct or the args map interchangeably.

### More Flexible Than CRON Scheduling

Delivering around the same time using cron-style scheduling would need extra book-keeping to check when a user signed up, and then only deliver to those users that signed up within that window of time.
The recursive scheduling approach is more accurate and entirely self contained—when and if the digest interval changes the scheduling will pick it up automatically once our code deploys.

Next time, for [something completely different][scd], we'll see how to [report progress back to our users as a slow job executes][part4].

_An [extensive discussion][oi27] on the Oban issue tracker prompted this example along with the underlying feature that made it possible._

## Update

This recipe is now a pack of white lies!
The gist of the recipe is still intact, but the examples and the `before_compile` details aren't accurate.
This post [prompted an issue][oi45] on the tracker that suggested replacing the args dance in `perform/1` with a consistent `perform/2` function instead.
The new `perform/2` _always_ accepts an args map as the first argument and the complete job struct as the second.

Here is the worker example from above, slightly modified to use `perform/2`:

```elixir
defmodule MyApp.ScheduledWorker do
  use Oban.Worker, queue: :scheduled, max_attempts: 10

  @one_day 60 * 60 * 24

  @impl true
  def perform(%{"email" => email}, %{attempt: 1} = job) do
    args
    |> new(schedule_in: @one_day)
    |> Oban.insert!()

    MyApp.Mailer.deliver_email(email)
  end

  def perform(%{"email" => email}, _job) do
    MyApp.Mailer.deliver_email(email)
  end
end
```

The upcoming `0.7.0` release will include the `perform/2` changes.

#### More Oban Recipes

* [Oban Recipes Part 1: Unique Jobs][part1]
* [Oban Recipes Part 2: Recursive Jobs][part2]
* [Oban Recipes Part 4: Reporting Progress][part4]

[oban]: https://github.com/sorentwo/oban
[oi27]: https://github.com/sorentwo/oban/issues/27
[oi45]: https://github.com/sorentwo/oban/issues/45
[wm]: https://github.com/sorentwo/oban/blob/master/lib/oban/worker.ex
[pr]: https://github.com/sorentwo/oban/pull/32
[scd]: https://en.wikipedia.org/wiki/And_Now_for_Something_Completely_Different
[part1]: /2019/07/18/oban-recipes-part-1-unique-jobs.html
[part2]: /2019/07/22/oban-recipes-part-2-recursive-jobs.html
[part4]: /2019/08/21/oban-recipes-part-4-reporting-progress.html
