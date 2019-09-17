---
layout: default
author: Parker Selbert
title: "Oban Recipes Part 5: Batch Jobs"
summary: >
  Monitor jobs as a group with the power of pattern matching and queue introspection.
tags: elixir oban
---

The [first post][part1] details what [Oban][oban] is, what you may use it for, and what inspired this series—it may be helpful to read that before jumping into the recipe here!

## Batching Jobs for Monitoring

In the [previous post][part4] we looked at tracking the progress of _a single job_ as it executes.
What about tracking the progress of tens, hundreds or thousands of jobs as they execute?
In that situation we want to monitor the jobs as a group—execute a set of jobs in parallel and then enqueue a callback when all the jobs are finished.
At lease one [popular background job processor][sqp] calls these groups "batches", and so we'll adopt that term here as we build it out with Oban.

### Use Case: Notifying Admins When an Email Delivery is Complete

Admins on our site send weekly batch emails to a large mailing list to let users know new content is available.
Naturally the system sends emails in parallel in the background.
Delivery can take many hours and we want to notify our admins when the batch is complete.
This is an admittedly simple use case, but it is just complex enough to benefit from a batching flow.

At a high level, the worker flow looks like this:

1. Generate a unique id for the batch, it can be entirely random or something structured like "my-batch-1"; any string will due, provided it is unique for the forseable future.
2. Count the total number of jobs to execute.
   This is the `batch_size`, which we'll use later to decide whether all jobs have completed.
3. Create a worker that has a `perform/2` clause matching a `batch_id` key.
   This clause will handle the real work that the job is meant to do, and afterwards it will check whether the batch is complete.
   Since executed jobs are stored in the database with a `completed` state we can evaluate whether this was the final job in the batch.
4. When we detect that the current job is the last one we enqueue one final job with different arguments to indicate that it is the "completed" callback.
   Through the magic of pattern matching this "callback" job can live within the same worker.

Here is the worker module with both the primary and callback clauses of `perform/2`:

```elixir
defmodule MyApp.BatchEmailWorker do
  use Oban.Worker, queue: :batch

  @impl true
  def perform(%{"email" => email, "batch_id" => batch_id, "batch_size" => batch_size}, _job) do
    MyApp.Mailer.weekly_update(email)

    if final_batch_job?(batch_id, batch_size) do
      %{"status" => "complete", "batch_id" => batch_id}
      |> new()
      |> Oban.insert()
    end
  end

  def perform(%{"status" => "complete", "batch_id" => batch_id}, _job) do
    MyApp.Mailer.notify_admin("Batch #{batch_id} is complete!")
  end
end
```

Within the first `perform/2` clause we deliver a weekly update email and then check whether this is the final job using `final_batch_job?/2`:

```elixir
defp final_batch_job?(batch_id, batch_size) do
  # The current job isn't completed, we can't count it!
  finished_size = batch_size - 1

  Oban.Job
  |> where([j], j.state not in ["avaialable", "scheduled"])
  |> where([j], fragment("?->>'batch_id' = ?", j.args, ^batch_id))
  |> select([j], count(j.id) >= ^finished_size)
  |> MyApp.Repo.one()
end
```

This private predicate function uses the [Oban.Job struct][obj] to query the `oban_jobs` table for other completed jobs in the batch.
Within the query we use a fragment containing the indecipherable `->>` operator, a [native PostgreSQL jsonb operator][json] that keys into the `args` column and filters down to jobs in the same batch.
When the number of completed or discarded jobs matches our expected batch size we know that the batch is complete!
(It's worth mentioning at this point that by default there aren't any indexes on the `args` column, so this query won't be super snappy with a lot of completed jobs laying around).

To kick off our batch job we generate a `batch_id` and a iterate through a list of emails:

```elixir
batch_id = "email-blast-#{DateTime.to_unix(DateTime.utc_now())}"
batch_size = length(emails)

for email <- emails do
  %{email: email, batch_id: batch_id, batch_size: batch_size}
  |> MyApp.BatchEmailWorker.new()
  |> Oban.insert!()
end
```

### Historic Observation

This batching technique is possible without any other tables or tracking mechanisms because Oban's jobs are **retained in the database after execution**.
They're stored right along with your other production data, which opens them up to querying and manipulating as needed.
Batching isn't built into Oban because between queries and pattern matching you have everything you need to build complex batch pipelines.

One final note: querying for completed batches all hinges on how aggressive your pruning configuration is.
If you're pruning completed jobs after a few minutes or a few hours then there is a good chance that your batch won't ever complete.
Be sure that you **tune your pruning** so that there is enough headroom for batches to finish.

#### More Oban Recipes

* [Oban Recipes Part 1: Unique Jobs][part1]
* [Oban Recipes Part 2: Recursive Jobs][part2]
* [Oban Recipes Part 3: Reliable Scheduling][part3]
* [Oban Recipes Part 4: Reporting Progress][part4]

[oban]: https://github.com/sorentwo/oban
[sqp]: https://github.com/mperham/sidekiq/wiki/Batches
[obj]: https://hexdocs.pm/oban/Oban.Job.html#t:t/0
[json]: https://www.postgresql.org/docs/11/functions-json.html#FUNCTIONS-JSON-OP-TABLE
[part1]: /2019/07/18/oban-recipes-part-1-unique-jobs.html
[part2]: /2019/07/22/oban-recipes-part-2-recursive-jobs.html
[part3]: /2019/08/02/oban-recipes-part-3-reliable-scheduling.html
[part4]: /2019/08/21/oban-recipes-part-4-reporting-progress.html
