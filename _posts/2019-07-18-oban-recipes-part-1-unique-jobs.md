---
layout: default
author: Parker Selbert
title: "Oban Recipes Part 1: Unique Jobs"
summary: >
  Examine techniques for enforcing unique background jobs with Oban
tags: elixir oban
---

This is the first in a series of "recipes" (use-cases), showing what you can accomplish using [Oban][oban].
Oban is an Elixir based background job processing library with a focus on reliability and historical observability.
Background job is a rather general term that has a broad definition—they are suitable for everything from sending an email after account sign-up to transcoding videos.

On the [Oban issue tracker][oit] and in the [Elixir forum][ef] I'm frequently asked how to accomplish certain tasks.
While some tasks, like the aforementioned after-sign-up email delivery are straight forward, other jobs are tricky to coordinate and may require knowledge of how Oban composes.
This recipe, and the others to follow, apply to background job processing in general, but this post will look at accomplishing a task using Oban.

Enough preamble, on to the recipe!

## Enforcing Unique Jobs

Preventing duplicate jobs ensures that the same background work isn't done multiple times.
For instance, perhaps you have a job that emails a link whenever a form is submitted.
If the form is submitted twice you don't want to insert a second job while the first is still pending.
Note that "pending" means jobs that are `scheduled` or `available` to execute, it does not apply to jobs that have already completed.
It is certainly possible to enforce uniqueness within a window of time, but we won't focus on that for this example.

With Oban, unlike most background job libraries, you have complete control over how jobs are inserted into the database.
That control gives us a few options where the trade-off is between strong guarantees and convenience.

### Using a Partial Index

The first solution is the most robust, as it leverages PostgreSQL's uniqueness guarantees.
Namely, we can use [partial indexes](https://www.postgresql.org/docs/11/indexes-partial.html) to scope the uniqueness to a particular worker.

We start by adding an index for the worker that we want to enforce uniqueness for.
Add the following declaration to a new Ecto migration, where `MyApp.Worker` is the name of the worker you want to enforce uniqueness for:

```elixir
create index(
  :oban_jobs,
  [:worker, :args],
  unique: true,
  where: "worker = 'MyApp.Worker' AND state IN ('available', 'scheduled')"
)
```

The composite index is unique, but the `where` clause ensures that the index only applies to _new_ jobs.
With the index defined we can make use of [Ecto's ON CONFLICT support](https://hexdocs.pm/ecto/3.1.7/Ecto.Repo.html#c:insert/2) when inserting a job.
Using `ON CONFLICT DO NOTHING` tells PostgreSQL to try and insert the new row, but that it's alright if insertion fails:

```elixir
%{email: "somebody@example.com"}
|> MyApp.Worker.new()
|> MyApp.Repo.insert(on_conflict: :nothing)
```

This solution is efficient and has transactional guarantees, but it isn't particularly convenient.
Every time we want to add a unique constraint, or modify an existing constraint to take other fields into account, we need to run a database migration.
There is an application based alternative that doesn't have such strong guarantees, but is far more flexible.

### Using an Insert Helper

The second solution is to define a helper function within your application's `Repo` module.
The helper checks the database for jobs before trying to insert, and aborts insertion if anything is found:

```elixir
def insert_unique(changeset, opts \\ []) do
  worker = Ecto.Changeset.get_change(changeset, :worker)
  args = Ecto.Changeset.get_change(changeset, :args)

  Oban.Job
  |> where([j], j.state in ~w(available scheduled))
  |> get_by(worker: worker, args: args)
  |> case do
    nil -> insert(changeset, opts)
    _job -> {:ignored, changeset}
  end
end
```

Now, where you would have used `Repo.insert/1` before you can use `Repo.insert_unique/2` instead:

```elixir
%{email: "somebody@example.com"}
|> MyApp.Worker.new()
|> MyApp.Repo.insert_unique()
```

The helper can be used freely for any worker without the need to deploy new indexes to your database.
Unlike the previous solution, this one has no transactional guarantees and doesn't have any indexes to work off of, so it may be slower.

## Integrating Into Oban

Supporting unique jobs purely within your own application shows how much direct control you have over queueing behavior.
The forum [post this recipe is based on][post] is over a month old now, and subsequent [discussion on the issue tracker][dit] proved that this is a generally desirable feature.
The use case for unique jobs is broad enough that it makes a great candidate for inclusion directly within Oban.
When unique job support makes its way into Oban I'll update this post with a third *official* technique.

#### More Oban Recipes

[Oban Recipes Part 2: Recursive Jobs](/2019/07/22/oban-recipes-part-2-recursive-jobs.html)

[oban]: https://github.com/sorentwo/oban
[oit]: https://github.com/sorentwo/oban/issues
[ef]: https://elixirforum.com/t/oban-reliable-and-observable-job-processing/22449
[post]: https://elixirforum.com/t/oban-reliable-and-observable-job-processing/22449/44
[dit]: https://github.com/sorentwo/oban/issues/27#issuecomment-510827928
