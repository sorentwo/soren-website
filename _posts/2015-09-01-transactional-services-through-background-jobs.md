---
layout: default
author: Parker Selbert
summary: >
  Mitigate the lack of transactional safety by leaning on discrete background
  jobs when interfacing with external systems.
tags: ruby sidekiq
---

> View other enterprise systems with suspicion and distrust—any of them can stab
> you in the back.
>
> <cite>Michael T. Nygard—[Release It!][ri]</cite>

Inevitably applications need to do actual time consuming, highly coordinated
work. As engineers we know not to handle such hard work during a request, it
needs to be pushed into the background. Often that work can be performed locally
inside of application code, or purely within the database; but eventually
external systems will come into play. When our applications start coordinating
work with external services we can really start to lean on our background
processor for isolation from others systems outside of our control.

## Transactional Services at Work

Let's set up a scenario, something common and digestible, and work through how
to break it up at the boundaries. This (relatively) concrete example will
demonstrate when and how to make services transactional through isolation.

Our application accepts multimedia uploads, including videos. Perhaps we've
found that handling uploads is fraught with [timeouts][hr] and connection
issues, so instead the mobile apps upload videos directly to [S3][s3].  The
mobile app then alerts the server that a video is ready and the server sets off
to start processing the video. We spare no expense processing the video, and so
numerous external services are utilized. Processing is comprised of several
steps:

* Copy the video from a temporary location specified by the mobile app
  and into a permanent location specified by the server
* Transcoded the video into multiple formats for portability
* Go the extra mile for your users and automatically transcribe it

Each one of those tasks require interfacing with an external service, and the
failure of one task shouldn't have any effect on the others.  Each task must be
wrapped in an independent unit of work, a background job. The job manager will
make sure the work is done in a transactional manner, handling retries in the
event of errors.

## Packaging Up the Work

> A transaction is an abstract unit of work processed by the system. This is not
> the same as a database transaction. A single unit of work might encompass many
> database transactions.
>
> <cite>Michael T. Nygard—[Release It!][ri]</cite>

If the video processing was a series of interactions with an [ACID][acid]
compliant [database][pg], all of the operations could be wrapped in a
transaction, or set of transactions. If any of the processing steps were to fail
all of the changes could be rolled back and retried again later. This behavior
is fundamental to eliminating duplicate entries and orphaned data.

Here is a paraphrased example illustrating how the steps in our video processing
task would operate if we could wrap them in a *database* transaction:

```ruby
def process_video(video_id)
  video = Video.find(video_id)

  Video.transaction do
    perform_cloud_copy!(video)
    perform_transcoding!(video)
    perform_transcription!(video)
  end
end
```

Sadly, services over the internet don't provide any such transactional behavior,
so we need to approximate it ourselves. We can compensate for a lack of
transactional safety by breaking tasks into discrete background jobs.

## Translating to Background Jobs

Because it is amazingly fast and utterly reliable, we'll use Sidekiq for our
examples. However, the same principles hold true for any background processing
library that automatically retries failing jobs—most [ActiveJob][aj] compliant
queues will do the trick.

The processing sequence starts with a worker that copies the remote file and
then kicks off the other jobs.

```ruby
class VideoCopyWorker
  include Sidekiq::Worker

  def perform(video_id, object_path)
    video = Video.find(video_id)

    perform_copy!(video, object_path)
    enqueue_processing(video)
  end

  private

  def perform_copy!(video, object_path)
    CloudCopier.new(video).copy!(object_path)
  end

  def enqueue_processing(video)
    VideoTranscodeWorker.perform_async(video.id)
    VideoTranscribeWorker.perform_async(video.id)
  end
end
```

After the object is successfully copied, the transcode and transcription workers
are enqueued to process the video. If the `cloud_copy!` fails it will raise an
exception, aborting the job and triggering a retry a little bit later. A failed
cloud copy also prevents the other workers from being enqueued. At a later
point, when the `cloud_copy!` is successful the secondary jobs will be enqueued.

The workers are wrapped safely in *individual* jobs. This encapsulation is
essential to prevent duplicate work and prevent unwanted side effects. To paint
a clearer picture here are pseudo examples of the transaction and transcription
workers:

```ruby
class VideoTranscodeWorker
  include Sidekiq::Worker

  def perform(video_id)
    video = Video.find(video_id)

    Transcoder.new(video).create!
  end
end

class VideoTranscribeWorker
  include Sidekiq::Worker

  def perform(video_id)
    video = Video.find(video_id)

    Transcriber.new(video).create!
  end
end
```

The implementation of `Transcoder` and `Transcriber` are intentionally vague to
keep the focus on job encapsulation rather than actual service integration.

## Idempotent Jobs are Critical

It is important to keep each job idempotent, meaning the job can be called
repeatedly but will only perform the actual work once. In order to keep the
`VideoCopyWorker` job idempotent there needs to be a check for whether the video
has been copied yet:

```ruby
def perform(video_id, object_path)
  video = Video.find(video_id)

  unless video.copied?
    perform_copy!(video, object_path)
    enqueue_processing(video)
  end
end
```

Each of the workers needs a similar guard to ensure it is idempotent.

## Enforce Boundaries

Splitting work that coordinates with external systems into independent jobs is
simple, straight forward, and a reliable way to give your system more
resiliency. Just as you split classes up by responsibility and minimize
communication between objects, break work apart around integration points with
other systems. Isolate external integrations like it is going out of style
(which it's not). Don't trust other systems with your sites reliability.
External may mean another process, a different host, or a service provided by
another company, it's all the same to your system.

[ri]: https://pragprog.com/book/mnee/release-it
[acid]: https://en.wikipedia.org/wiki/ACID
[pg]: http://www.postgresql.org/docs/current/static/tutorial-transactions.html
[hr]: https://devcenter.heroku.com/articles/s3#file-uploads
[s3]: https://aws.amazon.com/s3/
[aj]: https://github.com/rails/rails/tree/master/activejob
