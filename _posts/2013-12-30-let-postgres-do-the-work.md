---
layout: default
summary: Efficient social ranking within Postgres
author: Parker Selbert
---

You are developing an application that serves up social content, perhaps it is a
clone of Instragram. The application's users can view posts by others and then
like and comment on their favorites, typical social behavior. As it is a
community site you'll naturally want to show a selection of the most recent
popular posts. However, if you were to continuously show only the most popular
posts the site would get stale very quickly. The same popular posts would linger
at the top, and fresh posts would be difficult to promote. What you need is a
way to calculate which posts are trending!

As this is a common problem for social websites there are a number of existing
examples for how to calculate the [hotness][reddit-ranking] or
[ranking][hn-ranking] of posts. We're going to evaluate a hybrid version of some
of these algorithms, and see how they need to be modified to get the most out of
our database.

## Calculating Trending

The popularity of a post can be calculated rather simply. In our example it is
the sum of the comments and likes counts. Expressed in Ruby:

```ruby
def popularity(post)
  post.comments_count + post.likes_count
end
```

That will get you a raw score, which is useful if you are sorting items by
popularity alone. If you are combining popularity with another measurement, such
as recentness, you will want a means of weighting the output. By weighting the
output with a multiplier, we can compose multiple values more evenly. Here is
the `popularity` method rewritten to accept a pure number and apply the weight:

```ruby
def popularity(count, weight: 3)
  count * weight
end

popularity(1)  # 3
popularity(25) # 75
```

The new `popularity` method is simplistic, but documents the code better than a
group of magic numbers. The need for weighting will become more apparent after
we look at the other important factor in computing a post's trending arc,
recentness.

Recentness is a measure of how old something is, relative to an absolute point
in time. There are two opposing methods for tracking recentness: decreasing the
value over time or increasing the value over time. In the ranking algorithm used
on Hacker News posts *decrease* their "recentness" value over time. Reddit, on
the other hand, perpetually *increases* the score for new posts. Decreasing
recentness over time seems intuitive, but we'll favor the perpetual increase
approach for reasons that will be apparent later.

Here is a basic recentness method in Ruby:

```ruby
SYSTEM_EPOCH   = 1.day.ago.to_i
SECOND_DIVISOR = 3600

def recentness(timestamp, epoch: SYSTEM_EPOCH, divisor: SECOND_DIVISOR)
  seconds = timestamp.to_i - epoch

  (seconds / divisor).to_i
end

recentness(1.hour.ago)   # 23
recentness(12.hours.ago) # 12
recentness(1.day.ago)    # 0
```

Using an absolute `epoch` of just a day ago makes the increments very clear.
Each new post will have a higher score than an older post, staggered by one hour
windows.

Combining the recentness and the popularity yields a composite trending score
Let's try it out purely in Ruby land, ignoring any pesky database details:

```ruby
Post = Struct.new(:id, :created_at, :likes_count, :comments_count)

posts = [
  Post.new(1, 1.hour.ago,  1, 1),
  Post.new(2, 2.days.ago,  7, 1),
  Post.new(3, 9.hours.ago, 2, 5),
  Post.new(4, 6.days.ago,  11, 3),
  Post.new(5, 2.weeks.ago, 58, 92),
  Post.new(6, 1.week.ago,  12, 7)
]

sorted = posts.map do |post|
  pop = popularity(post.likes_count + post.comments_count)
  rec = recentness(post.created_at, epoch: 1.month.ago.to_i)
  [pop + rec, post.id]
end.sort_by(&:first)

sorted.reverse # [[608, 6], [617, 4], [695, 2], [724, 1], [731, 3], [833, 5]]
```

That looks about right. The really popular post from two weeks ago is hanging
around at the top, but newer and less popular posts are up there as well. This
example demonstrates how the ranking should work, but it glosses over one
crucial aspect of how applications really operate. The entire history of posts
aren't sitting around the server in memory. They are stored in a database where
our Ruby methods won't be of any use. Loading thousands, or millions, of posts
into memory to sort them is ludicrous. So, how can we move our ranking to the
database?

## Moving it to Postgres

All of the mainstream SQL databases (MySQL, SQL Server, Oracle, Postgres) have
the notion of custom procedures, or functions. Postgres, what we'll be focusing
on here, has particularly great support for defining custom functions. It allows
custom functions to be written in `SQL`, `C`, an internal representation, or any
number of user-defined procedural languages such as `JavaScript`.

[Postgres functions](pg-functions) can be defined in isolation and labeled with
a hint for the query optimizer about the behavior of the function. The behaviors
range from `VOLATILE`, in which there may be side-effects and no optimizations
can be made, to `IMMUTABLE` where the function will always return the same
output given the same input. Beyond an academic love of "functional purity"
there is one killer benefit to using `IMMUTABLE` functions: they can be used for
indexing. That feature can also be a constraint when dealing with notions of
time, as we'll see shortly.

First, let's translate the popularity method from Ruby. Connect to a database
with the `psql` client execute the following:

```psql
CREATE FUNCTION popularity(count integer, weight integer default 3) RETURNS integer AS $$
  SELECT count * weight
$$ LANGUAGE SQL IMMUTABLE;
```

The declaration is a bit more verbose than the Ruby version.  It requires that
you specify the input types, but it even allows default values. We can easily
verify the output matches the Ruby version:

```sql
SELECT popularity(1);  -- 3
SELECT popularity(25); -- 75
```

The recentness function proves to be a little trickier. Postgres has a lot of
[facilities for manipulating timestamps][pg-datetime] and it can take a while to
find the invocation that gets the exact value you need. In this case we are
trying to mimic Ruby's `Time#to_i` method. The `EXTRACT` function, when combined
with `EPOCH`, does just that. It converts the timestamp into an integer. Here is
the translated recentness function:

```psql
CREATE FUNCTION recentness(stamp timestamp, sys_epoch integer default 1388380757) RETURNS integer AS $$
  SELECT ((EXTRACT(EPOCH FROM stamp) - sys_epoch) / 3600)::integer
$$ LANGUAGE SQL IMMUTABLE;
```

Plugging in the same output shows that it matches:

```sql
SELECT recentness((now() - interval '1 hour')::timestamp);   -- 23
SELECT recentness((now() - interval '12 hours')::timestamp); -- 12
```

All that is left is to combine the two scores into a single value:

```psql
CREATE FUNCTION ranking(counts integer, stamp timestamp, weight integer) RETURNS integer AS $$
  SELECT popularity(counts, weight) + recentness(stamp)
$$ LANGUAGE SQL IMMUTABLE;
```

Imagine a `posts` table that is similar to the Ruby Struct that was used above:

```
| Column         | Type      |
+----------------+-----------+
| id             | integer   |
| title          | text      |
| comments_count | timestamp |
| likes_count    | timestamp |
| created_at     | timestamp |
| updated_at     | timestamp |
```

We can rank the trending posts easily with an `ORDER BY` clause that uses the
trending function:

```sql
SELECT * FROM posts
  ORDER BY ranking(
    comments_count + likes_count,
    created_at::timestamp
  ) DESC LIMIT 30;
```

As expected the ordering works! Trending ranking has been successfully moved to
the database. There is a little matter of performance, however. On my local
machine with a table of roughly 210,000 posts this query takes ~289.049 ms—not
speedy by any measure. For comparison, running a similar query that orders only
by `id` takes ~0.428 ms. That is over 390x; faster. We can still do better.

## Tuning the Performance

The first step to improving any query is understanding what the query planner is
doing with it. All it takes is prepending an `EXPLAIN` clause to our original
query:

```psql
EXPLAIN SELECT * FROM posts -- ...
```

The output clearly identifies an insurmountable cost in the sorting phase:

```
->  Sort  (cost=69179.55..69689.03 rows=203790 width=229)
```

This is where indexes come to the rescue. There are three separate columns from
each row used to compute the trending score. Adding an index to any column would
help when sorting by columns individually or in tandem, but it doesn't help when
sorting by an aggregate—such as a function. Postgres will always need to compute
the trending score for every row in order to sort them all.

From the [index ordering documentation][pg-ordering]:

> An important special case is ORDER BY in combination with LIMIT n: an explicit
> sort will have to process all the data to identify the first n rows, but if
> there is an index matching the ORDER BY, the first n rows can be retrieved
> directly, without scanning the remainder at all.

Clearly we need an index that matches the `ORDER BY` statement.

Earlier I mentioned that there was an important property of the `IMMUTABLE`
function attribute. Because an immutable function is guaranteed not to alter any
external values it can safely be used to generate an index. Back in the `psql`
console try adding a new index:

```psql
CREATE INDEX index_posts_on_ranking
  ON posts (ranking(comments_count + likes_count, created_at::timestamp) DESC);
```

It doesn't work! In fact, it throws an error:

```
ERROR:  42P17: functions in index expression must be marked IMMUTABLE
```

The error is raised despite our marking the ranking function and its sub
functions as `IMMUTABLE`. What gives? Recall that earlier I mentioned that there
was a problem with immutability and timestamps. Time is a fluid concept, and is
naturally subject to change. Running the function at different times, in
different timezones, or even on different servers will yield a different result.
Any function that deals with a timestamp can not truly be immutable.

There is a simple workaround to the timestamp blocker. The integer value of a
timestamp is just an increasing counter, ticking off each microsecond. The
database itself has another form of increasing counter, the primary key. We
can replace the timestamp with the primary key for the "recentness" calculation:

```sql
DROP FUNCTION recentness(timestamp, integer);
DROP FUNCTION ranking(integer, timestamp);

CREATE FUNCTION ranking(id integer, counts integer, weight integer) RETURNS integer AS $$
  SELECT id + popularity(counts, weight)
$$ LANGUAGE SQL IMMUTABLE;
```

Now try adding the index again:

```psql
CREATE INDEX index_posts_on_ranking
  ON posts (ranking(id, comments_count + likes_count) DESC);
```

The index is accepted. Now we can try it out again:

```psql
SELECT * FROM posts
  ORDER BY ranking(id, comments_count + likes_count) DESC LIMIT 30;
```

The results come back in ~0.442ms, just as fast as the `id` only ordering. The
final ranking function is entirely trivial. New posts will slowly fall off as
new posts are added and get boosted by social activity. It has the exact effect
we aimed for and is *hundreds* of times faster! Granted, the simplicity comes at
the cost of being unable to fine tune the results—nothing that a little
weighting or logarithmic clamping can't fix. That is an exercise left up to the
reader.

[reddit-ranking]: http://amix.dk/blog/post/19588
[hn-ranking]: http://amix.dk/blog/post/19574
[pg-functions]: http://www.postgresql.org/docs/9.3/static/sql-createfunction.html
[pg-datetime]: http://www.postgresql.org/docs/current/static/functions-datetime.html
[pg-ordering]: http://www.postgresql.org/docs/9.3/static/indexes-ordering.html
