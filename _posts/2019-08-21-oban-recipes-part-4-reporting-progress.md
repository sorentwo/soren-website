---
layout: default
author: Parker Selbert
title: "Oban Recipes Part 4: Reporting Progress"
summary: >
  Keep applications feeling responsive by reporting progress from long running
  background jobs.
tags: elixir oban
---

The [first post][part1] details what [Oban][oban] is, what you may use it for, and what inspired this series—it may be helpful to read that before jumping into the recipe here!

## Reporting Job Progress

Most applications provide some way to generate an artifact—something that may take the server a long time to accomplish.
If it takes several minutes to render a video, crunch some numbers or generate an export, users may be left wondering whether your application is working.
Providing periodic updates to end users assures them that the work is being done and keeps the application feeling responsive.

Reporting progress is something that any background job processor with _unlimited execution time_ can do!
Naturally, we'll look at an example built on Oban.

### Use Case: Exporting a Large Zip File

Users of our site can export a zip of all the files they have uploaded.
A _zip_ file (no, not a tar, our users don't have neck-beards) is generated on the fly, when the user requests it.
Lazily generating archives is great for our server's utilization, but it means that users may wait a while when there are many files.
Fortunately, we know how many files will be included in the zip and we can use that information to send progress reports!
We will compute the archive's percent complete as each file is added and push a message to the user.

#### Before We Start...

In the [forum question that prompted this post][post] the work was done externally by a port process.
Working with ports is well outside the scope of this post, so I've modified it for the sake of simplicity.
The result is slightly contrived as it puts both processes within the same module, which isn't necessary if the only goal is to broadcast progress.
This post is ultimately about coordinating processes to report progress from a background job, so that's what we'll focus on (everything else will be rather [hand-wavy][wavy]).

### Coordinating Processes

Our worker, the creatively titled `ZippingWorker`, handles both building the archive and reporting progress to the client.
Showing the entire module at once felt distracting, so we'll start with only the module definition and the `perform/2` function:

```elixir
defmodule MyApp.ZippingWorker do
  use Oban.Worker, queue: :exports, max_attempts: 1

  def perform(%{"channel" => channel, "paths" => paths}, _job) do
    build_zip(paths)
    await_zip(channel)
  end
end
```

The function accepts a channel name and a list of file paths, which it immediately passes on to the private `build_zip/1`:

```elixir
defp build_zip(paths) do
  job_pid = self()

  Task.async(fn ->
    zip_path = MyApp.Zipper.new()

    paths
    |> Enum.with_index(1)
    |> Enum.each(fn {path, index} ->
      :ok = MyApp.Ziper.add_file(zip_path, path)

      send(job_pid, {:progress, trunc(index / length(paths) * 100)})
    end)

    send(job_pid, {:complete, zip_path})
  end)
end
```

The function grabs the current pid, which belongs to the job, and kicks off an async task to handle the zipping.
With a few calls to a fictional `Zipper` module the task works through each file path, adding it to the zip.
After adding a file the task sends a `:progress` message with the percent complete back to the job.
Finally, when the zip finishes, the task sends a `:complete` message with a path to the archive.

The async call spawns a separate process and returns immediately.
In order for the task to finish building the zip we need to wait on it.
Typically we'd use `Task.await/2`, but we'll use a custom receive loop to track the task's progress:


```elixir
defp await_zip(channel) do
  receive do
    {:progress, percent} ->
      MyApp.Endpoint.broadcast(channel, "zip:progress", percent)

      await_zip()

    {:complete, zip_path} ->
      MyApp.Endpoint.broadcast(channel, "zip:complete", zip_path)
  after
    30_000 ->
      MyApp.Endpoint.broadcast(channel, "zip:failed", "zipping failed")

      raise RuntimeError, "no progress after 30s"
  end
end
```

The receive loop blocks execution while it waits for `:progress` or `:complete` messages.
When a message comes in it broadcasts to the provided channel and the client receives an update (this example uses Phoenix channels, but any other pubsub type mechanism would work).
As a safety mechanism we have an `after` clause that will timeout after 30 seconds of inactivity.
If the receive block times out we notify the client and raise an error, failing the job.

### Made Possible by Unlimited Execution

Reporting progress asynchronously works in Oban because anything that blocks a worker's `perform/2` function will keep the job executing.
Jobs aren't executed inside of a transaction, which alleviates any limitations on how long a job can run.

This technique is suitable for any _single_ long running job where an end user is waiting on the results.
Next time we'll look at combining _multiple_ jobs into a single output by creating **batch jobs**.

#### More Oban Recipes

* [Oban Recipes Part 1: Unique Jobs][part1]
* [Oban Recipes Part 2: Recursive Jobs][part2]
* [Oban Recipes Part 3: Reliable Scheduling][part3]
* [Oban Recipes Part 5: Batch Jobs][part5]
* [Oban Recipes Part 6: Expected Failures][part6]

[oban]: https://github.com/sorentwo/oban
[post]: https://elixirforum.com/t/oban-reliable-and-observable-job-processing/22449/52?u=sorentwo
[chan]: https://hexdocs.pm/phoenix/channels.html#content
[wavy]: https://www.quora.com/When-someone-says-this-explanation-was-hand-wavy-what-does-that-mean
[endp]: https://hexdocs.pm/phoenix/endpoint.html#content
[part1]: /2019/07/18/oban-recipes-part-1-unique-jobs.html
[part2]: /2019/07/22/oban-recipes-part-2-recursive-jobs.html
[part3]: /2019/08/02/oban-recipes-part-3-reliable-scheduling.html
[part5]: /2019/09/17/oban-recipes-part-5-batch-jobs.html
[part6]: /2019/10/17/oban-recipes-part-6-expected-failures.html
