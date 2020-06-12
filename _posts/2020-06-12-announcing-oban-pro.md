---
layout: default
author: Parker Selbert & Shannon Selbert
title: "Oban 2.0 and the Introduction of Oban Web+Pro"
summary: >
  Announcing Oban 2.0 and the future of sustaining Oban with Web+Pro.
tags: elixir oban
---

Oban 2.0 is the biggest release yet—not in an exaggerated Apple WWDC kind of way either, it genuinely has the most bug fixes, feature additions, and breaking changes of any release so far.
Admittedly, breaking changes aren't typically something to celebrate, but this is a major version bump and it enables some fantastic new features.

Let's start with some highlights plucked from [the CHANGELOG][cl]:

- **Unified Worker Callbacks** — We've replaced the `perform/2` callback with `perform/1`, where the only argument is an `Oban.Job` struct.
  Along with the `backoff/1` callback also accepting a job struct, this unifies the interface for all `Oban.Worker` callbacks and helps to eliminate confusion around pattern matching on arguments.

- **Snooze** — You can return `{:snooze, seconds}` from a workers's `perform/1` callback to reschedule a job some number of seconds in the future.
  This is useful for recycling jobs that aren't ready to run yet, e.g. due to rate limiting or temporary errors that might resolve with time.

- **Discard** — Rather than snoozing you can return `:discard` from `perform/1` to drop the job.
  This is useful when a job encounters an error that won't resolve with time, e.g. invalid arguments or a missing record.

- **Test Helper** — The new `perform_job/2,3` helper automates validating, normalizing and performing jobs while unit testing.
  It bore from catching the same mistakes and "gotchas" in code reviews.
  This is the preferred way to unit test workers now.

- **Local Only Queues** — The updated `Oban.start_queue/2` function accepts a list of options, including the new `local_only` flag, which allows you to dynamically start and stop queues only for the local node.

- **Crontab Improvements** — New support for non-standard expressions such as `@daily`, step values with ranges, and fixes for scheduling in a system running multiple Oban instances.

- **Standard Telemetry** — Oban adopted Telemetry from the outset, before some standards had solidified.
  Now that conventions have standardized we've switched to the `span` convention and enhanced Telemetry events throughout the codebase.

- **Reliability Fixes** — We've eliminated race conditions that allowed duplicate dispatch of new jobs and false positives when enqueuing unique jobs through improvements to the use of transactions and namespacing locks.

The [CHANGELOG][cl] includes an upgrade guide for breaking changes and examples for select new features.

One other important addition to note is the new plugin system.
As more companies use Oban, there is an increasing need for behaviour tailored to certain use cases.
Those features require significant development time and can add a lot complexity to the codebase.

The plugin system helps us tackle those problems by moving those time-intensive and complex features to the Oban Pro package, which we will explore in depth soon.
In particular, we've made the following changes:

- The pruning system housed a lot of complexity to support all of the different use cases.
  Therefore, it we've simplified it so that it *keeps jobs for 60 seconds*, making sure Oban by default leaves a small footprint after execution.
  For those who want flexibility and/or historical data, Oban UI+Pro offers a functional UI to explore all past and on-going jobs alongside a fully featured pruning system

- Producer activity is no longer recorded via heartbeats—this functionality largely powers Oban UI and now, with the plugin system, we were able to move it out

- Stop rescuing of orphaned jobs.
  The rules around restarting jobs can be complex and domain dependent.
  For instance, automatically retrying a job could accidentally invoice a client twice.
  Therefore, manual intervention is the safest default.
  You can do so via the command line or via Oban UI's web interface.
  Once you see a pattern in your orphaned jobs, you can use Oban Pro's new Lifeline system or automate some of those restarts on your own

We've extracted, rewritten and dramatically improved all of the removed functionality to make it available through the new Oban Pro package.

## Introducing Oban Pro

When we started Oban, we believed it would fill a valuable gap in the Elixir community.
We also knew that it would be important to find a sustainable model that would allow us to continue working and improving Oban throughout the years.

Oban adoption has gone well and it is widely used by Elixir powered businesses across an array of industries.
Initially we launched Oban UI, which was our first experiment into finding a viable business model for Oban.

Ideally Oban UI would have been enough to sustain Oban's growth, but the feedback we got made it clear that we needed more.
While Oban UI helped companies identify trends and act on their queues, their teams also wanted to be able to convert those trends back into complex business rules which are deeply integrated into their queuing system.

Given the effort required to implement and revamp those features, we've decided to give them a new home as Oban Pro.
Oban Pro brings all of the missing pieces to Oban UI, now renamed to Oban Web, **for the same price as before**.
Existing customers are upgraded to Oban Web+Pro for free.
Oban Pro complements Oban Web with the following plugin powered features:

- **Flexible Historical Data** — The new `DynamicPruner` in Oban Pro allows you to specify either a maximum age or a maximum length and provide custom rules for specific queues, workers and job states.
  This works great with unique jobs and Oban Web, allowing you to explore and introspect active and historic jobs from your browser

- **Lifeline** — Rules for rescuing orphaned jobs.
  While you can tell Oban how much time your jobs have to shutdown; misconfiguration, bugs and system crashes may leave some jobs stuck on the “executing” state.
  With Oban Web+Pro, you can visualize those jobs and restart them from the Web and define rules to periodically restart them

- **Auto-Reprioritization** — Companies that make extensive use of Oban's priority system may find themselves in a position where low priority jobs are not executed, especially during high-traffic and spikes.
  This feature prevents queue starvation by automatically adjusting priorities to ensure all jobs are eventually processed

In addition we're launching with an official `Batch` worker.
The worker links the execution of many jobs as a group and runs optional callbacks after the group of jobs execute.
This allows your application to coordinate the execution of tens, hundreds or thousands of jobs in parallel.
It is an abstraction on top of the standard `Oban.Worker` and a _dramatic_ improvement over the old batch recipe.
Learn more about how you can put it to work for you in the [official batch worker guide][bwg].

To sum up, Oban Pro is a collection of plugins, workers and extensions that improve Oban's reliability even further and make difficult workflows easier.
Everything provided by Oban Pro builds on Oban OSS.
There isn't anything hidden or any monkey-patching because Elixir keeps us honest.
I hope you will give Oban Web+Pro a try and join other companies investing in Oban's future!

## Overhauling Oban Web

Going well beyond a simple renaming, Oban Web is an overhaul of the former UI.
The product is entirely redesigned and rebuilt for extensibility, flexibility, clarity and speed.
A few of the highlights:

- **No More Configuration** — Oban Web piggybacks on the Oban configuration

- **No More Migrations** — The update and search functionality no longer requires any database migrations

- **Router Integration** — A new `oban_dashboard` macro simplifies Phoenix router integration and makes it possible to mount multiple dashboards in the same application

- **Customizable Refresh** — Change how frequently the dashboard refreshes, or pause updates entirely

- **Bulk Actions** — Select multiple jobs and act on them in bulk to cancel, retry, discard or delete them all together

- **Queue Pausing** — Pause and resume queues globally directly from the queue side panel

- **Queue Scaling** — Scale queues up or down globally from the queue side panel

It's still early days, but we've released an alpha of Oban Web 2.0.0 which is compatible with Oban 2.0+ and bundles with Oban Pro.
The upgrade process is minimal and mostly involves deleting code, so give it a try!
This leads us to the next topic: where to find documentation on all of these changes.

## Centralized Documentation

Oban has thorough module documentation and an extensive README, but it lacked guides and walkthroughs beyond the posts of this blog.
As of 2.0 there are a few initial guides and with thanks to [support from the community][og], the recipes published on this blog are now available as guides (and updated for 2.0).

What's more, both Oban Web+Pro hook into the new guides structure to present docs side-by-side with [Oban on hexdocs][oh].
There are docs on installation, troubleshooting, full product changelogs, and extensive guides for each feature.

Check out the [Oban Pro docs][opd] and [Oban Web docs][owd].

## What About Licenses?

As hinted earlier, **Oban Web+Pro is available through a single license**.
If you already have an Oban Web license you now get Oban Pro as well!

Not only are the products available through a [single license][li], there aren't any changes to the [pricing tiers][pr] either.
The only thing that is changing around license subscriptions is the **removal of a trial period**.
Due to abuse by a few unsavory individuals we can no longer offer a seven day trial.
Oban Web+Pro is a monthly subscription rather than an annual fee, so there is minimal financial risk to trying it out for a month.

## Sincere Thanks

The interest and adoption of Oban has been truly overwhelming.
The feedback has been amazingly positive, which is a testament to how respectful and supportive the Elixir community is.
Thank you for providing the drive to keep maintaining and improving Oban.
There is so much more to do; our future is wide open!

_Special thanks to Jesse Cooke, Milton Mazzarri and José Valim for reviewing this post._

[og]: https://github.com/sorentwo/oban/pull/247
[cl]: https://github.com/sorentwo/oban/blob/master/CHANGELOG.md
[oh]: https://hexdocs.pm/oban/2.0.0-rc.1/Oban.html
[li]: https://getoban.pro/
[pr]: https://getoban.pro/pricing
[opd]: https://hexdocs.pm/oban/2.0.0-rc.1/pro_overview.html#content
[owd]: https://hexdocs.pm/oban/2.0.0-rc.1/web_overview.html#content
[bwg]: https://hexdocs.pm/oban/2.0.0-rc.1/batch.html#content
