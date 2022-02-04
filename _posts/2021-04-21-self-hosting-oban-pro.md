---
layout: redirect
sitemap: false
redirect_to:  https://getoban.pro/articles/self-hosting-oban-pro
author: Parker Selbert & Shannon Selbert
summary: >
  Our journey to self-hosting the Oban Web and Oban Pro hex packages.
tags: elixir oban
---

Oban [Web and Pro][gpro] are now available through a self-hosted package
repository. If you'd just like to see how to switch to the new self-hosted
endpoint you can [skip ahead](#using-the-self-hosted-oban-repository).
Otherwise, keep reading for some background on why we're self hosting and how
we've implemented it securely and efficiently.

## How and Why We're Self-Hosting

Self-hosting hex packages is now possible thanks efforts by the Hex team, and
[Wojtek Mach][twit] in particular. After [dashbit][dash] [shut down the
bytepack project][byte], a platform for delivering software products to
developers, the team open sourced most of the underlying tech. The last project
that they open sourced was [mix hex.registry][here], which made self-hosting a
package repository practical.

Oban Web and Oban Pro are paid products that require a license to access.
Currently (or historically, depending on when you read this), they are hosted as
[private packages][priv] served directly through the official [Hex][hexp]
servers. The Hex servers are fast, stable, fronted by a CDN, and relied on by
the entire Elixir ecosystem. That sounds great, right? Why would we want to
switch to our own servers?

Well, hosting our own packages is desirable for a few key reasons:

* Primarily, it enables us fine grained control over managing licenses and the
  ability to differentiate between products. Limiting access to one product or
  another isn't possible through Hex's private packages since that really isn't
  what they are meant for.
* As a consideration, it doesn't violate the Hex team's [terms of use][term],
  which stipulates that user accounts may only be one person. Until now, the
  team has graciously allowed us to use private hex for distribution, and we
  don't want to overstay our welcome.

## Our Schmancy Implementation

Along with the `mix hex.registry` [introduction post][here] on the Dashbit blog
there is an [official guide][self] on how to self-host a package repository. We
used that as a starting point and then modified it to suit our needs.

The `hex.registry` mix task generates a set of static files that can be hosted
anywhere and fetched by the hex client. The official guide walks through serving
them using [Plug.Static][stat] with authentication via [Plug.BasicAuth][basi].
That solution is simple and worked wonderfully for us initially, but there were
a couple of downsides:

* Providing repository files directly from the server would require us to store
  everything in our application's `priv` directory, which would bloat the git
  repository over time and didn't seem like an elegant solution.
* We have Pro customers all over the globe, from Hong Kong to Australia, Brazil
  and Norway. Serving packages from a data center in middle of the United States
  isn't ideal—and a significant step backwards from private hex hosting.

That lead us to a slightly more complex, yet ultimately more robust
solution—instead of serving files from our server, or even streaming them back
from external storage, we redirect requests to a signed, temporary URL on
CloudFront.  While developing this redirect flow we discovered and fixed a
[small bug in hex][hexb], so be sure to run `mix hex.local` for the latest
hex release before attempting a redirect based flow.

Once we worked out which files hex requests and how to securely sign redirect
URLs, the overall flow was rather simple:

1. Publish new packages to a local copy of the package repository and then sync
   it to a private S3 bucket.
2. As package requests come in we route them to a plug that checks the auth-key
   against active licenses and records some light tracking information about the
   version and client.
3. Authenticated requests are then redirected to a short-lived CloudFront URL
   that expires after a few minutes.

If you hand-wave over license fetching, package authorization, and URL signing,
the entire process fits into a single Plug's `call/2` function:

```elixir
def call(conn, _opts) do
  with [license_key] <- get_req_header(conn, "authorization"),
       {:ok, license} <- Accounts.fetch_license_by_key(license_key) do
    if package_allowed?(conn.path_info, license.product) do
      signed_url =
        ["registry" | conn.path_info]
        |> Path.join()
        |> Signer.sign()

      Controller.redirect(conn, external: signed_url)
    else
      conn
      |> send_resp(403, "package not allowed")
      |> halt()
    end
  else
    _ ->
      conn
      |> send_resp(401, "unknown or incorrect license key")
      |> halt()
  end
end
```

That's all there is to it behind the scenes! It's easily maintained with a
couple of mix tasks and extremely lightweight. For the security minded, license
fetching has optimizations to prevent timing attacks or brute force discovery of
license keys.

## Using the Self-Hosted Oban Repository

Adding a self-hosted repo is negligibly more complex than authenticating a
private hex organization. The `mix hex.repo` command takes care of adding the
registry, verifying the public/private key pair, and verifying the auth-key
(license) all in a single command:

```bash
mix hex.repo add oban https://getoban.pro/repo \
  --fetch-public-key ${OBAN_KEY_SHA} \
  --auth-key ${OBAN_API_KEY}
```

With a proper public key fingerprint (`OBAN_KEY_SHA`) and auth-key
(`OBAN_API_KEY`) set in the environment, that command will add a new local
package repo. You can verify the name and settings with `mix hex.repo list`:


```
$ mix hex.repo list

Name   URL                       Public key         Auth key
hexpm  https://repo.hex.pm       SHA256:O1LOYhHFW4  6d37f61cc0
oban   https://getoban.pro/repo  SHA256:/BIMLnK8NH  12e3671cc1
```

_Note: This example is modified for space, and to obfuscate actual keys_

Now you specify the `oban` repo for the `:oban_web` and `:oban_pro` packages,
where previously you'd use `organization: "oban"`.

```elixir
  {:oban_web, "~> 2.6", repo: "oban"},
  {:oban_pro, "~> 0.7", repo: "oban"},
```

If you're an existing license holder, don't worry: the old hosting will stay
active for a while so that you can transition when you're ready. We'll give
plenty of warning before we stop supporting private hex hosting.

## Recursive (Not Redundant)

Since [getoban.pro][gpro] both _uses_ Web/Pro and _serves_ Web/Pro, we actually
fetch the private packages from our running server instance while deploying a
new instance. There's a beautiful recursion to it!

There's more recursion to come in a future post when we share how we use Oban to
handle payments, coordinate licenses and run the Web demo.

---

Many thanks to the Hex Team, Dashbit, and Wojtek for all the groundwork they
laid to make self-hosting possible. This enables a new era for indie developers
in Elixir—now we have all the tools necessary to maintain, prepare and serve our
own hex packages securely.

[twit]: https://twitter.com/wojtekmach
[dash]: https://dashbit.co/
[byte]: https://github.com/dashbitco/bytepack_archive
[here]: https://dashbit.co/blog/mix-hex-registry-build
[self]: https://hex.pm/docs/self_hosting
[priv]: https://hex.pm/docs/private
[hexp]: https://hex.pm/
[term]: https://hex.pm/policies/termsofservice
[gpro]: https://getoban.pro/
[stat]: https://hexdocs.pm/plug/Plug.Static.html#content
[basi]: https://hexdocs.pm/plug/Plug.BasicAuth.html#content
[hexb]: https://github.com/hexpm/hex/pull/874
