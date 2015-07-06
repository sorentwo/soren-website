---
layout: default
author: Parker Selbert
summary: Applications are services, they need monitoring too.
tags: devops rails inspeqtor
---

Every process that is available when a server boots was brought up by the init
system (or systems). That is all the init system does, just what it is good at.
It's certainly better at managing processes than an ad-hoc deployment script is.

Each production server should only have one job, be it running a load balancer,
serving up static pages or working as a database. Realistically that isn't
always the case, staging servers are a notable exemption, but it is an
attainable goal. Every component in the stack should rely on the init system to
maintain a steady state. Chances are the load balancer, reverse proxy cache,
NoSQL server, SQL server or configuration registry is already being managed by
an init system.  The application should too.

## Service Configurations

This post assumes you are deploying to Ubuntu, though the same principles apply
to *nearly* any other \*nix system. The current service management system for
Ubuntu is [Upstart][upstart], though it is being phased out in favor of the
[controversial][boycott] RedHat driven [systemd][systemd]. Regardless, Upstart
is included in Ubuntu 14.04 LTS, so it will be around for at least another four
years.

The [Upstart Cookbook][cookbook] is your best friend when crafting upstart
configuration files. Don't be intimidated by the cookbook's massive length.
While searching around for specific details you'll learn of other useful
features that you didn't even know existed.

The least common denominator for any web application is the server, so that is
what we will look at setting up as a service. Below is a configuration file for
running the [Puma][puma] web server as a service. Most of the details are common
to any upstart script, and in fact much of this configuration is straight out of
the example from the Puma repository:

```sh
#!upstart
description "Puma Server"

setuid deploy
setgid deploy
env HOME=/home/deploy

reload signal USR1
normal exit 0 TERM

respawn
respawn limit 3 30

start on runlevel [2345]
stop on runlevel [06]

script
  cd /var/www/app/current
  exec bin/puma -C config/puma.rb -b 'unix:///var/run/puma.sock?umask=0111'
end script

post_script exec rm -f /var/run/puma.sock
```

There are a couple of important changes and additions to the configuration that
I'll point out, as they are crucial for service maintainability.

```sh
setuid deploy
setgid deploy
```

First, drop down to a less priveleged user for the sake of security. This is a
very helpful feature built into more recent versions of Upstart. Your service
simply should not need to run as root. Some `sudo` level commands are necessary
for service control, but they should be enabled within `sudoers`, as we'll look
at later.

```sh
reload signal USR1
normal exit 0 TERM
```

Use an alternate reload signal. The standard signal emitted to the process is
`HUP`, which tells a process to reload its configuration file. Puma, like some
of the other web servers, can perform a full code reload and hot restart when
sent a particular signal. Here we are hijacking the upstart `reload` event to
send Puma the `USR1` signal, triggering a [phased restart][phased-restart]. Part
of the phased restart process involves sending the `TERM` signal, which we tell
upstart to ignore. Without the `normal exit` directive Upstart would consider
the Puma process down after one reload.

```sh
respawn
respawn limit 3 30
```

Add a respawning directive. It will try to restart the job up to 3 times within
a 30 second window if it fails for some reason. More often than not, the service
simply isn't coming back. It's nice to have a backup.

```sh
start on runlevel [2345]
```

Automatic start is one of the strongest selling points for using an init system
for an application. If the VM is mysteriously rebooted by your hosting provider,
which is guaranteed to happen at some point, it will be brought right back up
when the VM boots.

```sh
exec bin/puma -C config/puma.rb -b 'unix:///var/run/puma.sock?umask=0111'
```

The final line of the `script` block determines which process will be tracked by
upstart. While that may seem obvious, there are some gotchas to be aware of. By
default upstart pipes `STDOUT` and `STDERR` to `/var/log/upstart/puma.log`,
which is convenient. If you decide that you'd prefer to log directly to `syslog`
you may be tempted to add a pipe:

```sh
exec bin/puma ... | logger -t puma
```

However, that causes upstart to track the logger process's PID instead of
Puma's, preventing any further control of the Puma process by upstart. As you
would soon discover, attempts to `sudo stop puma` would only stop the logger
process and leave a zombie Puma process running in the background. Tracking the
proper PID is also crucial for the next stage of managing applications as
services, service monitoring.

## Controlling Services

By placing the configuration file in the proper location we can use service
commands to control the server process. Write the file to `/etc/init/puma.conf`.
All configuration files go into `etc/init/`, and the service becomes available
as whatever the file is named.

With the configuration in place the server can start up:

```sh
sudo service puma start
```

Even though the process will be ran as the `deploy` user the service must be
controlled with `sudo`. This can be problematic when using a deployment tool
like Capistrano, which doesn't officially support running commands as `sudo`. In
order for all of the necessary job control to be available during deployment you
will need to configure the `deploy` user with proper `sudoer` permissions.
Playing with passwordless `sudo` can be dangerous, so only add an exemption for
controlling the puma process directly:

```bash
sudo echo "deploy ALL = (root) NOPASSWD: /sbin/start puma, /sbin/stop puma, /sbin/restart puma, /sbin/reload puma" >> /etc/sudoers
```

The various service commands (start, stop, restart, and reload) are all aliased
into `/sbin`. This makes the passwordless commands slightly more readable, but
is functionally equivalent to the `service {name} {action}` version.

Now the service is up and the init system will ensure it comes back up if the
system crashes, or even if the process itself crashes. But what happens if the
process itself misbehaves or starts syphoning too many resources? There are
tools for just that situation, of course.

## Monitoring Services

Utilities for monitoring a server and the services on that server are essential
to maintaining the health of a system.  Many systems in the Ruby world have
relied on tools like [God][god] or [Bluepill][bluepill] to monitor and control
application state. Those particular tools have a couple of large drawbacks
though. Notably they require a Ruby runtime, which reduces portability and
sacrifices stability when version management is involved. More importantly,
instead of working with an existing init system they duplicate the
functionality.

A recently released monitoring tool called [Inspeqtor][inspeqtor] addresses both
of the aforementioned issues. It is distributed as a small self-contained binary
that itself is managed by an init system. However, it doesn't get into the
business of trying to control services directly. Instead, it leverages the init
system and very concise configuration files to help the system manage services
directly. [Installation is simple][inspeqtor-install] and works with the
existing package manager.

Continuing on with the goal of keeping the system up, self-healing, and allowing
the init system to do our work for us here is an example configuration file for
Puma. It is targeting the Puma service specifically, and would be placed in
`/etc/inspeqtor/services.d/puma.inq`:

```
check service puma
  if cpu:total_user > 90% then alert
  if memory:total_rss > 2g then alert, reload
```

That outlines, in very plain language, how Inspeqtor will monitor the service.
It will find the init system that is managing the process and periodically
perform some analysis on it. It performs simple status checks, such as whether
the service is even up currently, and can alert you if the service goes down.
Deeper introspection into resource usage is also possible, as shown in the
example above. Experience tells us that a Ruby web server will suffer memory
bloat over time and we'll want to track it. When the memory passes a threshold
Inspeqtor will take action. In this case it will tell Upstart to reload puma
(the same as running `service puma reload`) and it will send an alert to any of
the configured channels such as email or [Slack][slack].

Some services, such as [Sidekiq][sidekiq] workers for example, may not have such
strident requirements on uptime or may not have any notion of "phased restart".
In that case the config can use `restart` in place of `reload`.

## Keep Deployment Simple

Make the most of the tools that are available to you. Some of them, such as
Upstart, can be leveraged to great effect with a tiny bit of configuration and
some outside monitoring. Converting a system from a set of custom deployment
recipies that manage logs, sockets and pid files to one that manages and
maintains itself *will* be vastly more stable and predictable.

[upstart]: http://upstart.ubuntu.com/
[systemd]: http://freedesktop.org/wiki/Software/systemd/
[boycott]: http://boycottsystemd.org/
[cookbook]: http://upstart.ubuntu.com/cookbook/
[puma]: https://github.com/puma/puma
[phased-restart]: https://github.com/puma/puma/blob/master/DEPLOYMENT.md#restarting
[bluepill]: https://github.com/bluepill-rb/bluepill
[god]: http://godrb.com/
[inspeqtor]: http://contribsys.com/inspeqtor
[inspeqtor-install]: https://github.com/mperham/inspeqtor/wiki/Installation
[slack]: https://slack.com/
[sidekiq]: http://contribsys.com/sidekiq
