%{
  author: "Parker Selbert",
  summary: "A zero-downtime technique for reloading the environment within long running processes.",
  title: "Environment Reloading"
}

---

One of the core principals of [The Twelve-Factor App][12-factor], and a
highlight of deploying applications on Heroku, is storing configuration in the
environment:

> Apps sometimes store config as constants in the code. This is a violation of
> twelve-factor, which requires strict separation of config from code. Config
> varies substantially across deploys, code does not.

In the Ruby world the [Dotenv][dotenv] library makes it simple to dynamically
load configuration from values stored in local `.env` files. Early in the
loading process the file is read and each key value pair is loaded into Ruby's
hash-like `ENV` object. A common, and simple, example of using environment
variables is storing the URL, credentials, and configuration for a database
connection:

```bash
DATABASE_URL=postgres://username:password@localhost:port/database?pool=16
```

The details of the connection are confidential and shouldn't be checked into
source control. An `.env` file can be managed independently of the source code
and transferred to the web server securely, even as part of the deploy process.
This method of providing database configuration is so common that Rails will
check the `ENV` for a `DATABASE_URL` when it boots. This built in usage of
environment variables is great, but there are some caveats.

### Forking

Those familiar with Heroku know that when you change an environment variable on
Heroku, no matter how small, the application will be restarted. In the land of
Heroku a restart means creating all new containers for your application,
starting them up, and finally routing traffic to them once they have loaded.
Complete shutdown and startup is consistent, but has noticeable lag when
compared to the hot reloading available in [Unicorn][unicorn] or [Puma][puma].

Unicorn servers achieve concurrency by running one or more workers, each
controlled from a single master process. The master process listens for Unix
[signals][signals] such as `TERM`, `QUIT`, or `USR2` and manages the pool of
workers accordingly. For example, when the master receives a `USR2` signal it
forks new worker instances with the most recent version of the code and begins
directing connections to the new instances. This is called a phased restart.

Starting a new Unicorn master forks it from the current process, typically a
shell of some kind. During the forking process it inherits the shell's
environment variables. After the process is forked it loses any reference to the
shell's environment, so any further changes to the environment will be ignored.
This separation prevents chaos between different processes, but it also creates
a hiccup when we want to update the configuration for a long running process
like Unicorn.

### Updating Configuration

Updating environment variables from a configuration file can be performed at any
time with `ENV.update`. Calling update will add or replace any existing keys
with the new values, but only within the current process. In order to have the
updated `ENV` cascade down to the workers actually handling requests we have to
call `update` before the workers are forked. It is very common to perform some
setup around the exec/fork life cycle, so servers provide life cycle hooks. Here
is an example of how to update within a Unicorn config:

```ruby
require 'dotenv'

before_exec do
  ENV.update Dotenv::Environment.new('.env')
end
```

Or, alternately, within a Puma config:

```ruby
require 'dotenv'

on_worker_boot do
  ENV.update Dotenv::Environment.new('.env')
end
```

With the configuration hooks in place you can safely update a `.env` file at any
time, issue a restart, and change configuration on the fly.

[12-factor]: http://12factor.net/config
[dotenv]: https://github.com/bkeepers/dotenv
[unicorn]: http://unicorn.bogomips.org/SIGNALS.html
[puma]: https://github.com/puma/puma/#restart
[signals]: http://www.ruby-doc.org/core-2.1.0/Signal.html
