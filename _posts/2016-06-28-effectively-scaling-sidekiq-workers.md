---
layout: default
author: Parker Selbert
summary: >
  A case study on organizing Sidekiq queues, workers, and throttles for
  stability and higher concurrent throughput.
tags: sidekiq concurrency
---

Recently we helped a client overcome widespread errors in Sidekiq. Between all
of the deadlocks, threading errors and the need for widespread rate limiting,
they were crippled and unable to scale. Some background jobs could only run one
at a time but would take 30 seconds or more each. Other jobs ran quickly, but
subsequently heaped *more* jobs onto the slow queues. The queues kept on
growing, but dialing up the concurrency simply caused more problems.

On most days they could only let Sidekiq run for a few hours at a time before
the system would break down into constant errors. Some of errors compounded so
badly it ground the web server to a halt, taking down the entire site. In an
attempt at exerting control, all onboarding jobs were started manually rather
than automatically. There was no trust in the system, and no obvious way to
scale their way out of the situation.

After brief investigation it was clear that there were fundamental problems with
the way jobs were enqueued, distributed, and limited. What follows are the high
level changes that were implemented, each presented as an observation and a
solution.

## Entangle Jobs Between Queues

#### Observation

Various categories of jobs were bucketed into different queues, but the queues
weren't weighted. This forced each queue to drain completely before jobs in the
next queue were started. Queues are processed in the order they are listed, so
piling thousands of slow running jobs onto a queue in the middle guarantees
inefficient processing. A mass of the same slow job running simultaneously just
exacerbates resource contention and prevents jobs in the subsequent queues from
ever starting.

#### Solution

Declare equal weights for each of the queues so that jobs are plucked randomly
between them. That forces fast jobs from the default queue to run alongside slow
jobs. Spreading busy jobs between queues becomes even more important when there
are limits on how many of each job type can run concurrently.

#### Example

Force random queue priorities:

~~~bash
sidekiq -q google,1 -q facebook,1 -q linkedin,1 -q twitter,1 -q default,1
~~~

Learn more about [advanced queuing][adv-opt] in the Sidekiq Wiki.

## Scale With Processes and Threads

#### Observation

The application's database drivers for [Neo4j][neo4j] used HTTPS as a transport.
Instead of connection pooling, it executed every request across a single
long-standing `NetHTTPPersistent` connection. When concurrent jobs deadlocked or
threw errors the thread stopped waiting for a response but kept holding the
connection. With one or two errors in quick succession the connection would
recover, but with rapid fire errors the connection problems quickly choked out
the database.

#### Solution

The ultimate solution would be to use a more efficient transport than HTTP, and
to institute connection pooling. However, that would require upstream library
changes and would take far longer than the client had. The temporary fix was to
lean on processes for concurrency rather than threads. With fewer threads per
process there was less of a drain on the single connection and it was easy to
keep it healthy.

#### Example

On a platform like Heroku it is simply a matter of scaling the number of worker
instances. On a host that uses Upstart to manage Sidekiq workers it is as simple
as bumping `NUM_WORKERS` within the [workers][workers] conf. Even better, with
[Enterprise][ent] you can make use of managed multi process using [swarm][swarm].

~~~conf
env COUNT=4

exec bundle exec sidekiqswarm -e production
~~~

## Use Concurrency Throttling

#### Observation

Many of the same type of job ran concurrently and contended for the same
database or network resources. In an attempt to prevent clobbering the output of
each job all of the records were being pessimistically locked, leading to
database deadlocks. Some deadlocks would resolve themselves, but any that didn't
slowed the queue to a crawl, caused unpredictable errors, and put an extra
burden on the throttling constructs.

#### Solution

Impose limits on the number of concurrent jobs that can run at once. With a
single process and strictly segregated jobs it is trivial to control the
concurrency by limiting a queue. But what happens when there is more work than a
single process can handle (or a poorly behaving database driver forces you to
parallelize with processes)? Now there are as many queues as there are
processes, and any limits that were being enforced has scaled right along with
them.

The proper solution is to use a distributed concurrency construct like the
throttling available from [Sidekiq Enterprise][ent]. The throttle enforces job
concurrency limits across all threads, processes, and hosts; ensuring that at
most N jobs can run at a time. Be aware that throttling operates at the job
level, not at the queue level. For example, with a throttle that limits one job
at a time and concurrency set to 25 Sidekiq will still start 25 of the same job
type, but each job will wait for the lock to release and they will run
sequentially. That makes it crucial to balance queues evenly so that multiple
job types are enqueued simultaneously.

#### Example

Configure a concurrent rate limiter that only permits 2 concurrent jobs, with
generous timeouts:

~~~ruby
LINKEDIN_THROTTLE = Sidekiq::Limiter.concurrent(
  'linkedin',
  2,
  wait_timeout: 10,
  lock_timeout: 60
)

def perform
  LINKEDIN_THROTTLE.within_limit do
    # Talk to LinkedIn
  end
end
~~~

See the details of [concurrent][conc] rate limiting at the Wiki.

## Nothing is a Silver Bullet

Happily the workers are now plowing through `300,000+` jobs a day without any
downtime or hiccups.

None of these changes by themselves were enough to get the system running
smoothly. It required a healthy amount of defensive coding, bug fixes, and
configuration tuning to smooth out the platform. It may have been possible
without the industrial strength features offered by Enterprise, but it would
have required a lot of plugins and some hand rolled throttling. I didn't even
mention using batches, unique jobs or time based rate limiting—used properly,
Pro/Enterprise save tremendous amounts of developer time.

*No, I don't receive kickbacks on Enterprise sales!*

[ent]: http://sidekiq.org/enterprise
[neo4j]: https://github.com/neo4jrb/neo4j-core
[adv-opt]: https://github.com/mperham/sidekiq/wiki/Advanced-Options
[workers]: https://github.com/mperham/sidekiq/blob/master/examples/upstart/workers.conf
[swarm]: https://github.com/mperham/sidekiq/wiki/Ent-Multi-Process
[conc]: https://github.com/mperham/sidekiq/wiki/Ent-Rate-Limiting#concurrent
