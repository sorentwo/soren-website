---
layout: default
author: Parker Selbert & Shannon Selbert
summary: >
  Peek behind the scenes to see how we use Oban to demo, license, and actively
  verify Oban Web+Pro.
excerpt: >
  Where's the fun in building a background job runner if you aren't running it
  yourself? Oban is a reliable way to implement business-critical functionality
  like payment processing, license management, and communicating with customers.
  Naturally, that's what we want to use for the licensing app that runs
  [getoban.pro][pro].
tags: elixir oban
---

![Mirrors with a View](/assets/posts/using-oban-to-license-oban/drmakete-lab-hsg538WrP0Y-unsplash.jpg){:loading="lazy"}

_Photo by [drmakete lab on Unsplash](https://unsplash.com/photos/hsg538WrP0Y)_

Where's the fun in building a background job runner if you aren't running it
yourself? Oban is a reliable way to implement business-critical functionality
like payment processing, license management, and communicating with customers.
Naturally, that's what we want to use for the licensing app that runs
[getoban.pro][pro].

Today we'd like to give you a tour of how we use Oban in that app to run the
dashboard demo, dogfood new features, asynchronously process customer payments,
and handle critical webhooks.

As a brief aside, before we get into the fun stuff, the application itself is
named "Lysmore." "Lys" is Norwegian for "light" and is an intentional
misspelling of "Lismore," the island across the bay from Oban in Scotland. If
you notice the `Lysmore` module in some code samples, that's why.

[pro]: https://getoban.pro

## Running the Web Dashboard Demo

Undoubtedly, our most entertaining use of Oban is for the live [Web dashboard
demo][demo]. A playful combination of randomly generated workers using fake data
and random failures makes the demo a chaotic simulation of a production
workload. A typical generated worker looks something like this (with hardcoded
values and inlined functions for simplicity):

```elixir
defmodule Oban.Workers.WelcomeMailer do
  use Oban.Worker, queue: :mailers

  alias Faker.Internet

  def gen(opts \\ []) do
    args = %{
      email: Internet.email(),
      homepage: Internet.url(),
      username: Internet.user_name()
    }

    new(args, opts)
  end

  @impl Worker
  def perform(_job) do
    if :rand.uniform(100) < 15, do: raise(RuntimeError, "Something went wrong!")

    100..60_000
    |> Enum.random()
    |> Process.sleep()
  end
end
```

That worker will randomly error 15% of the time and take anywhere from 100ms to
60s to run, plenty of time for people to track progress, click into the details
and possibly cancel the job.

Anybody on the internet can get a taste of the dashboard and possibly cause
some harmless chaos of their own in the meantime—some miscreants love to pause
queues or scale the concurrency down to one.

The demo is a beautiful canary because it uses the latest OSS, Web, and Pro
releases, utilizing all the plugins and most available features. With error
monitoring, we receive notifications that help us diagnose and fix issues from a
constantly running production instance, often (but not _always_) before any
customers report a problem! It's crowdsourcing _and_ dogfooding rolled into one,
leading us to...

## Dogfooding Web and Pro Features

During development, we use Lysmore to mount the web dashboard in an actual
Phoenix project. That is essential for complete integration tests and getting a
sense of how well everything plays together. Through that integration, proven
out and refined new features before they're released. Let's look at a few
examples.

#### CSP (Content Security Policy)

Using a nonce for [CSP (Content Security Policy)][csp] was a customer's security
requirement that we verified locally. Fun fact, Phoenix's live reload iframe
doesn't like CSP. Now the public demo loads a different nonce for every
dashboard request in production, using this config in `router.ex`:

```elixir
scope "/" do
  pipe_through :live_browser

  oban_dashboard "/oban",
    resolver: LysmoreWeb.Resolver,
    csp_nonce_assign_key: %{
      img: :img_csp_nonce,
      style: :style_csp_nonce,
      script: :script_csp_nonce
    }
end
```

#### Access Controls and Auditing

Access controls for [authorization][user], [authentication][auth], and
[auditing][aud] landed in Web a little while ago. Obviously, we don't restrict
access to the public demo, and all of the actions (deleting, pausing, scaling,
etc.) are allowed. Regardless, we use a simple resolver module that is easily
modified to restrict access while
testing:

```elixir
defmodule LysmoreWeb.Resolver do
  defmodule User do
    defstruct [:id, guest?: true, admin?: false]
  end

  @behaviour Oban.Web.Resolver

  @impl Oban.Web.Resolver
  def resolve_user(_conn), do: %User{id: 0, guest?: true}

  @impl Oban.Web.Resolver
  def resolve_access(_user), do: :all

  @impl Oban.Web.Resolver
  def resolve_refresh(_user), do: 1
end
```

In the future, if the dashboard supports more invasive operations, e.g., editing
crontabs, we're prepared to disable some features.

#### Smart Engine

Pro's [SmartEngine][se] introduced oft-requested global concurrency and rate
limiting, which are built on lightweight locks and required multiple nodes to
exercise queue producer interaction. The public demo uses rate-limiting and
global limiting for a couple of queues:

```elixir
queues: [
  analysis: 20,
  default: 30,
  events: 15,
  exports: 8,
  mailers: [local_limit: 10, rate_limit: [allowed: 20, period: 30]],
  media: [global_limit: 10]
],
```

If you've ever noticed that the `mailers` queue has a lot of available jobs,
that aggressive rate-limit is the reason.

When we deployed the `SmartEngine`, we briefly scaled our cluster up to 5 nodes
to identify any bottlenecks. That proved fruitful because we identified a global
concurrency deadlock and quickly [shipped an improved algorithm][p71] that used
some jitter.

[demo]: https://getoban.pro/oban
[csp]: https://hexdocs.pm/oban/web_installation.html#content-security-policy
[user]: https://hexdocs.pm/oban/web_customizing.html#current-user
[auth]: https://hexdocs.pm/oban/web_customizing.html#action-controls
[aud]: https://hexdocs.pm/oban/web_customizing.html#current-user
[se]: https://hexdocs.pm/oban/smart_engine.html#content
[p71]: https://hexdocs.pm/oban/pro-changelog.html#v0-7-0-2021-04-02

## Handling License Payments

In addition to the public Oban instance that powers the demo, we also run a
[separate private instance][iso] using a `private` prefix in PostgreSQL. That
instance is entirely isolated and only runs a few queues where we integrate with
Stripe to manage customers, attach payment methods, and create or update
subscriptions.

Here is the full config for that instance, living right alongside the public
config:

```elixir
config :lysmore, ObanPrivate,
  engine: Oban.Pro.Queue.SmartEngine,
  repo: Lysmore.Repo,
  name: ObanPrivate,
  prefix: "private",
  queues: [default: 3],
  plugins: [
    Oban.Plugins.Gossip,
    Oban.Pro.Plugins.Lifeline,
    Oban.Web.Plugins.Stats
  ]
```

Note that there isn't any pruning involved. There are relatively few private
jobs that run, and the data is vital for troubleshooting, so we hold on to
it.

All of the Stripe interactions are essential for setting up payments. They're
also possible failure points—anything can happen when we make an HTTP call to a
third-party service, even one as reliable as Stripe. What happens if, as a
customer signs up, we send invalid data, make an invalid API call, or we get
rate-limited for too much activity (yeah, we wish)? We can't have that affect
our customers.

Our solution for ensuring that we are resilient to failures is to wrap each
operation in an idempotent job. As an example, let's look at the worker that
handles updating customer details, upgrading their payment details, or changing
their subscription:

```elixir
defmodule Lysmore.Accounts.UpdateWorker do
  use Oban.Worker, unique: [period: 120]

  alias Lysmore.Accounts

  @impl Oban.Worker
  def perform(%{args: %{"id" => id, "plan" => plan}}) do
    {:ok, user} = Accounts.fetch_user(id)

    user =
      user
      |> attach_payment()
      |> update_customer()
      |> create_or_update_subscription(plan)

    {:ok, user}
  end

  def perform(%{args: %{"id" => id, "info" => info}}) do
    {:ok, user} = Accounts.fetch_user(id)

    update_customer(user, info)
  end
```

We handle either a plan change or a generic customer info change through the
beauty of pattern matching. Each of the `attach_payment/1` type functions is
built to be idempotent—if a change already happened, then the function is a
no-op. That way, if one step fails, the job can try again without duplicating
changes. If you're looking at that and thinking, "that sure looks a lot like a
workflow," keep reading!

Managing customers and taking payments is where Stripe integration starts. After
that we rely on webhooks to manage licenses.

[iso]: https://hexdocs.pm/oban/Oban.html#module-isolation

## Handling Webhooks

After a subscription is created or canceled, Stripe sends a webhook to notify
us. Much like payment processing, it is critical that we are resilient to
failures and _eventually_ grant or revoke a license. Granting a license sounds
simple enough, but it involves four separate steps that either touch the
database or make external calls.

Like payment processing, the steps must be idempotent—we don't want to create
multiple licenses or deliver the same email repeatedly if something fails.
However, unlike payment processing, we model webhook handling [as a
workflow][wf].

Here you can see how the webhook controller's `create/2` function matches on the
webhook type and inserts a corresponding workflow:

```elixir
def create(conn, %{"data" => %{"object" => data}, "type" => type}) do
  insert_workflow(type, data)

  send_resp(conn, 200, "")
end

defp insert_workflow("customer.subscription.created", data) do
  args = %{data: data}

  workflow =
    WorkflowWorker.new_workflow()
    |> WorkflowWorker.add(:hex, HexWorker.new(args))
    |> WorkflowWorker.add(:license, LicenseWorker.new(args))
    |> WorkflowWorker.add(:welcome, WelcomeWorker.new(args), deps: [:hex, :license])
    |> WorkflowWorker.add(:notify, NotifyWorker.new(args), deps: [:hex, :license])

  Oban.insert_all(ObanPrivate, workflow)
end
```

The workflow coordinates generating a legacy hex license, building a
self-hosting license, delivering a welcome email with the new information, and
notifying us that we have a new subscriber. There are similar workflows for
cancellation and deletion, each of which is decomposed and simple to test in
isolation.

[wf]: https://hexdocs.pm/oban/workflow.html#content

## Where the Magic Happens

Using Oban to build the licensing site is essential to walking in the shoes of
our customers. We're running the same software that our customers are. That
means we run into the same rough spots that they do, and when something goes
wrong, we're plagued by the same bugs they are—with a rich incentive to expedite
a fix. It's a fortunate situation; how many products can go all-in on
themselves?

Thanks to everybody that hammers on the demo or signs up for a subscription.
You're helping us refine Oban!
