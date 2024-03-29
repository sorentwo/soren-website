%{
  author: "Parker Selbert",
  summary: "Learn about finite recursive background jobs through the lense of Oban.",
  title: "Oban Recipes Part 2: Recursive Jobs"
}

---

This is the second in a series of "recipes", showing what you can accomplish with background jobs using [Oban][oban].
The [first post][fp] details what Oban is, what you may use it for, and what inspired this series—it may be helpful to read that before jumping into the recipe here!

## When to Reach for Recursive Jobs

Recursive jobs, like recursive functions, call themselves after they have have executed.
Except unlike recursive functions, where recursion happens in a tight loop, a recursive job enqueues a new version of itself and may add a slight delay to alleviate pressure on the queue.

Recursive jobs are a great way to backfill large amounts of data where a database migration or a mix task may not be suitable.
Here are a few reasons that a recursive job may be better suited for backfilling data:

* Data can't be backfilled with a database migration, it may require talking to an external service
* A task may fail partway through execution; resuming the task would mean starting over again, or tracking progress manually to resume where the failure occurred
* A task may be computationally intensive or put heavy pressure on the database
* A task may run for too long and would be interrupted by code releases or other node restarts
* A task may interface with an external service and require some rate limiting
* A job can be used directly for new records _and_ to backfill existing records

Let's explore recursive jobs with a use case that builds on several of those reasons.

### Use Case: Backfilling Timezone Data

Consider a worker that queries an external service to determine what timezone a user resides in.
The external service has a rate limit and the response time is unpredictable.
We have a lot of users in our database missing timezone information, and we need to backfill.

Our application has an existing `TimezoneWorker` that accepts a user's `id`, makes an external request and then updates the user's timezone.
We can modify the worker to handle backfilling by adding a new clause to `perform/1`.
The new clause explicitly checks for a `backfill` argument and will enqueue the next job after it executes:

```elixir
defmodule MyApp.TimezoneWorker do
  use Oban.Worker

  import Ecto.Query

  @backfill_delay 1

  def perform(%{id: id, backfill: true}) do
    with :ok <- perform(%{id: id}),
         next_id when is_integer(next_id) <- fetch_next(id) do
      %{id: next_id, backfill: true}
      |> new(schedule_in: @backfill_delay)
      |> MyApp.Repo.insert!()
    end
  end

  def perform(%{id: id}) do
    update_timezone(id)
  end

  defp fetch_next(current_id) do
    MyApp.User
    |> where([u], is_nil(u.timezone))
    |> order_by(asc: :id)
    |> limit(1)
    |> select([u], u.id)
    |> MyApp.Repo.one()
  end
end
```

There is a lot happening in the worker module, so let's unpack it a little bit.

1. There are two clauses for `perform/1`, the first only matches when a job is marked as `backfill: true`, the second does the actual work of updating the timezone.
2. The backfill clause checks that the timezone update succeeds and then uses `fetch_next/1` to look for the id of the next user without a timezone.
3. When another user needing a backfill is available it enqueues a new backfill job with a one second delay.

With the new `perform/1` clause in place and our code deployed we can kick off the recursive backfill.
Assuming the `id` of the first user is `1`, you can start the job from an `iex` console:

```elixir
iex> %{id: 1, backfill: true} |> MyApp.TimezoneWorker.new() |> MyApp.Repo.insert()
```

Now the jobs will chug along at a steady rate of one per second until the backfill is complete (or something fails).
If there are any errors the backfill will pause until the failing job completes: especially useful for jobs relying on flaky external services.
Finally, when there aren't any more user's without a timezone, the backfill is complete and recursion will stop.

## Building On Recursive Jobs

This was a relatively simple example, and hopefully it illustrates the power and flexibility of recursive jobs.
Recursive jobs are a general pattern and aren't specific to Oban.
In fact, aside from the `use Oban.Worker` directive there isn't anything specific to Oban in the recipe!

In the next recipe we'll look at a specialized use case for recursive jobs: [infinite recursion for scheduled jobs][part3].

#### More Oban Recipes

* [Oban Recipes Part 1: Unique Jobs][part1]
* [Oban Recipes Part 3: Reliable Scheduling][part3]
* [Oban Recipes Part 4: Reporting Progress][part4]
* [Oban Recipes Part 5: Batch Jobs][part5]
* [Oban Recipes Part 6: Expected Failures][part6]
* [Oban Recipes Part 7: Splitting Queues][part7]

[oban]: https://github.com/sorentwo/oban
[part1]: /2019/07/18/oban-recipes-part-1-unique-jobs.html
[part3]: /2019/08/02/oban-recipes-part-3-reliable-scheduling.html
[part4]: /2019/08/21/oban-recipes-part-4-reporting-progress.html
[part5]: /2019/09/17/oban-recipes-part-5-batch-jobs.html
[part6]: /2019/10/17/oban-recipes-part-6-expected-failures.html
[part7]: /2019/11/05/oban-recipes-part-7-splitting-queues.html
