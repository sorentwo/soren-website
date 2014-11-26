---
layout: default
author: Parker Selbert
summary: Applications are services, they need monitoring too
---

Every process that is available when a server boots was brought up by the init
system (or systems). That's all the init system does, that's what it is good at.
It's certainly better at managing processes than an ad-hoc Capistrano or Mina
script is. Each production server should only have one job, be it running a
load balancer, serving up pages or working as a database. That isn't always the
case, staging servers are a notable exemption, but it is an easily achievable goal.
Every component in the stack should rely on the init system to maintain a steady
state. Chances are the load balancer, reverse proxy cache, NoSQL server, SQL
server or configuration registry is already being managed by an init system.
The application should too.

## Service Configurations

This post assumes you are deploying on Ubuntu, though the same principles apply
to *nearly* any other \*nix system. The current service management system for
Ubuntu is [Upstart][upstart], though it is being phased out in favor of the
[controversial][boycott] [systemd][systemd]. Regardless, Upstart is included in
Ubuntu 14.04 LTS, so it will be around for at least another four years.

The [Upstart Cookbook][cookbook] is your best friend when crafting upstart
configuration files. Don't be intimidated by the cookbook's massive length. As
you search around to find what you need and you'll absorb useful bits that you
didn't even know existed.

Walk through the configuration for running the puma web server as a service.
Most of the details are entirely vanilla, and in fact straight out of the puma
example configuration.

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
I'll point out as they are crucial for service maintainability.

```sh
setuid deploy
setgid deploy
```

First, drop down to a less priveleged user for the sake of security. This is a very
helpful feature built into more recent versions of Upstart. Your service simply
should not need to run as root. Some `sudo` level commands are necessary for
service control, but they should be enabled ad-hoc as we'll look at later.

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
upstart to ignore.

```sh
respawn
respawn limit 3 30
```

Add a respawning directive. It will try to restart the job up to 3 times if it
fails for some reason. More often than not the service simply isn't coming back,
but it's nice to have a backup.

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
puma's, preventing any further control of the puma process by upstart.

## Monitoring Services

* Use services for managing your server
* Understand what the configuration is doing
* Craft configuration that can be monitored and healed
  * The last `exec` yields the PID that will be tracked
* Have a monitor watch your services
  * It lets you know when something goes down
  * It can reload or restart when a process gets out of hand

[upstart]: http://upstart.ubuntu.com/
[systemd]: http://freedesktop.org/wiki/Software/systemd/
[boycott]: http://boycottsystemd.org/
[cookbook]: http://upstart.ubuntu.com/cookbook/
[phased-restart]: https://github.com/puma/puma/blob/master/DEPLOYMENT.md#restarting
