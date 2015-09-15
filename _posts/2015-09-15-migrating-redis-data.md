---
layout: default
author: Parker Selbert
summary: >
  Sometimes migrating data from between Redis instances is necessary and not
  all of the tools are available.
tags: redis
---

Long lived applications invariably change up their infrastructure at some point.
Perhaps the team has decided that it doesn't want the devops overhead or worry
of maintaining their own infrastructure. For some services, it is as simple as
spinning up new hosts or pushing to a managed service. Other services have more
blockers to migration, blockers like migrating a large set of important data.

This isn't such a hypothetical situation. It happens with Redis servers often
enough. Redis has a broad set of tools specifically to enable backing up,
restoring, and migrating data. In most situations that set of tools is perfectly
adequate. However, sometimes there are constraints imposed by various providers
that make migration much trickier.

Think of this post as a verbose migration constraint solver. We'll start with
the ideal means of migration and gradually add constraints. Eventually, we'll
arrive at the last resort and see how to work with it.

## Master/Slave Replication

The most reliable and preferred way to handle a migration is with master/slave
replication using [`SLAVEOF`][so]. All that is required is configuring the
destination instance as a slave of your current production instance. Once the
new database has caught up to production your application's Redis clients can be
directed to the new database and the server can be promoted to master.

### Process

1. Set the destination instance to be a slave of the source instance with
   `SLAVEOF {SOURCE_HOST} {SOURCE_PORT}`
2. Verify replication is current with `INFO replication`, it will say that the
   link is up and the last sync was 0 or more milliseconds ago
3. Change client URLs to point to the new server, reconnect clients
4. Promote the destination server to master with `SLAVEOF NO ONE`

### Constraint

Use of `SLAVEOF` isn't allowed.

Lacking access to `SLAVEOF` eliminates replication outright. Any managed Redis
provider worth their salt supplies replication with failover, making it
impossible for you to control the master/slave status of your instance. Master
servers can't be put into slave mode without killing the [sentinels][sent] or
other [HA][ha] system controlling them, which certainly isn't possible with a
cloud service.

## RDB Snapshot

When replication isn't an option you can fall back to transferring the database
dump persisted to disk. Even databases that aren't configured for periodic
[RDB][rdb] persistence can trigger a dump to disk with either `SAVE` or
[`BGSAVE`][bg], the asynchronous version. With the database dumped to disk it
can be transfered to the new server or uploaded with a data migration tool.

One major caveat around snapshot loading is the exact timing that is used.
Snapshots must be loaded when the Redis server is shut down. On reboot the Redis
instance will load data from the dump. Any server that is configured to perform
RDB persistence will automatically save to disk on shutdown. That means you must
shut down the destination instance *before overwriting the snapshot* or it will
be overwritten automatically during shutdown.

### Process

1. Save the source database to disk with `BGSAVE`
2. Transfer the database to the target host with `scp` or `rsync`
3. Stop the destination Redis process
4. Overwrite the RDB dump, typically found at `/var/lib/redis/dump.rdb`
5. Start the process back up

### Constraint

No access or mechanism to upload a RDB snapshot.

They don't have any way to upload a RDB dump file. Understandable, any cloud
service provider doesn't want to grant you access to the underlying file-system.
Still, [some providers][rc] have interfaces that allow you to load a dump into
the new instance.

## Key by Key Migration

When bulk loading and replication aren't available you can try to migrate one
key at a time with [`MIGRATE`][mg]. The `MIGRATE` command atomically transfers a key
from a source database to a destination database. By default this is a
destructive action unless the `COPY` option is passed, it must be handled with
care when pointed at a production instance.

Migration isn't automatic, it requires a script to iterate over all of the keys
and call `MIGRATE` for every individual key.

### Process

1. Connect to the source instance
2. Iterate over all keys with `SCAN`, or `KEYS` for smaller data sets
3. Run `MIGRATE host port key destination-db timeout COPY` for each key

### Constraint

Authorization is enabled (thankfully), preventing `MIGRATE`.

`MIGRATE` can't be used if the target server requires authorization. There have
been [pull requests][mpr] to allow authorization for `MIGRATE` commands, but it
hasn't been merged in.

## What Does That Leave?

> Maybe one could use DUMP/RESTORE - why would one want to do that though?
>
> <cite>&mdash; HippieLogLog ([@itamarhaber][its])</cite>

When you eliminate all of the traditional, supported, recommended means of
performing data migration what are you left with? The answer is [`DUMP`][du] and
[`RESTORE`][re]. Internally `MIGRATE` uses `DUMP` on the source database and
`RESTORE` on the target database. Those commands are available to any Redis
client, no special privileges are necessary.

### Process

1. Connect to the source instance
2. Connect to the destination instance
3. Iterate over all source keys with `SCAN`, or `KEYS` for smaller data sets
4. Call `DUMP` for each source key, which returns a serialized representation of
   the value
5. Call `TTL` for each source key to record the expiration
6. Call `RESTORE key ttl value` on the destination for each key

All of the same scripting work necessary to use `MIGRATE` is needed for dumping
and restoring, along with the additional work of setting the TTL for each key
that is restored. This should be your absolute last resort, let's hope you're
never in the situation to actually use it.

[so]: http://redis.io/commands/slaveof
[ha]: https://en.wikipedia.org/wiki/High_availability
[bg]: http://redis.io/commands/bgsave
[rdb]: https://github.com/sripathikrishnan/redis-rdb-tools/wiki/Redis-RDB-Dump-File-Format
[its]: https://twitter.com/itamarhaber/status/642598734497378304
[mg]: http://redis.io/commands/migrate
[du]: http://redis.io/commands/dump
[re]: http://redis.io/commands/restore
[rc]: https://redislabs.com/redis-cloud
[sent]: http://redis.io/topics/sentinel
[mpr]: https://github.com/antirez/redis/pull/2507
