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

The current service management system for Ubuntu is [Upstart][upstart], though
it is being phased out in favor of the [controversial][boycott]
[systemd][systemd]. Irregardless Upstart is included in Ubuntu 14.04 LTS, so it
will be around for at least another four years.

The [Upstart Cookbook][cookbook] is your best friend when crafting upstart
configuration files. Don't be intimidated by the cookbook's massive length. As
you search around to find what you need and you'll absorb useful bits that you
didn't even know existed.

```sh
#!upstart
description "Puma Server"
```

Drop down to a less priveleged user for the sake of security. This is a very
helpful feature built into more recent versions of Upstart.

```sh
setuid deploy
setgid deploy
env HOME=/home/deploy
```

Add a respawning directive. It will try to restart the job up to 3 times if it
fails for some reason. More often than not it simply isn't coming back, but it's
nice to have a backup.

```sh
respawn
respawn limit 3 30
```

Flexible reload signal, defaults to HUP.

```sh
reload signal USR1
normal exit 0 TERM
```

```
start on runlevel [2345]
stop on runlevel [06]

script
  cd /var/www/app/current
  exec bin/puma -C config/puma.rb -b 'unix:///var/run/puma.sock?umask=0111' 2> /dev/null
end script
```

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
