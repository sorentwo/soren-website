---
layout: default
author: Parker Selbert
summary: Manage applications as services, and monitor those services
---

Every process that is available when a server boots was brought up by the init
system (or systems). That's all the init system does, that's what it is good at.
It's certainly better at managing processes than an ad-hoc Capistrano or Mina
script is. Each production server should also only have one job, be it running a
load balancer, serving up pages or working as a database. That isn't always the
case, take staging servers for example, but it is an easily achievable goal.
Every component in the stack should rely on the init system to maintain a steady
state. Chances are the load balancer, reverse proxy cache, nosql server, sql
server or configuration registry is already being managed by the init system.
The application should too.

[Don't daemonize yourself](mperham.com)

## Service Configurations

The example services I'm about to discuss both ship with example Upstart
configurations. Those are an excellent place to start.

The [Upstart Cookbook][cookbook] is your best friend when crafting upstart
configuration files. Don't be intimidated by its massive length. As you search
around to find what you need and you'll absorb useful bits that you didn't even
know existed.

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

start on runlevel [2345]
stop on runlevel [06]

script
  mkfifo /tmp/puma-log-fifo
  (logger -t puma < /tmp/puma-log-fifo &)
  exec > /tmp/puma-log-fifo
  rm /tmp/puma-log-fifo

  cd /var/www/app/current
  . /etc/environment
  exec bin/puma -C config/puma.rb -b 'unix:///var/run/puma.sock?umask=0111' 2> /dev/null
end script

post-stop exec rm -f /var/run/puma.sock
```

[cookbook]: http://upstart.ubuntu.com/cookbook/
