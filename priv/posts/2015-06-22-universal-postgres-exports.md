%{
  author: "Parker Selbert",
  summary: "Export queries as CSV straight from PostgreSQL.",
  title: "Universal Postgres Exports"
}

---

The number of new accounts is on the rise, the platform is generating more
revenue than before, and operations wants to get a sense of the numbers. This is
a perfect opportunity to break out some SQL and generate a report. Of course the
c-levels all crunch their numbers with Excel. You can't simply dump a table of
non-portable tabulated data. This calls for the ubiquity of CSV!

Fire up a PostgreSQL REPL connected to your development environment and get to
work on a rough signup funnel.

```bash
psql widgets_development
```

Your platform lets account owners create and launch new embeddable widgets. An
important measure of success is how many new accounts then go on to create and
launch one or more widgets. You write up the funnel bundling account owners into
monthly cohorts:

```sql
WITH widgeters AS (
  SELECT id,
         date_trunc('month', created_at) AS created_at,
         NULLIF(widgets_count, 0) AS widgets_count,
         (SELECT NULLIF(COUNT(*), 0)
            FROM widgets
            WHERE widgets.account_id = accounts.id
            AND widgets.launched_at IS NOT NULL) AS launched_count
  FROM accounts
  AND created_at > current_timestamp - '1 year'::interval
)

SELECT created_at,
       COUNT(*)              AS signed_up,
       COUNT(widgets_count)  AS made_widget,
       COUNT(launched_count) AS launched_widget
  FROM widgeters
  GROUP BY created_at
  ORDER BY created_at;
```

That works. The data looks right to you. Now it is time to export it. No
problem. Modify the query by wrapping it in a `COPY` statement:

```sql
COPY (
  -- previous query
) TO '/tmp/cohorts.csv' WITH CSV HEADER;
```

That outputs a perfectly formatted CSV onto the local file system. After taking
a quick glance at the output you notice that your development data isn't
remotely accurate. It is mangled and out of date. Grabbing data from production
would be much more useful. Again, no problem, turn the query into a `.sql` file
that can be run against the remote database.

```bash
psql "postgres://username:password@widgets-server/widgets_production" -f cohorts.sql
```

Hmm, PostgreSQL didn't like that. It informs you that only `root` users can
export to the file system. You would have to `scp` the file back to your local
machine anyhow. Fortunately, the `COPY` command can also output to `STDOUT`.
Update the output in `cohorts.sql`:

```sql
COPY (
  -- previous query
) TO STDOUT WITH CSV HEADER
```

Now the results can be piped into a local file directly:

```bash
psql "postgres://username:password@widgets-server/widgets_production" \
     -f cohorts.sql \
     > cohorts-production.csv
```

## Export it Again. And Again.

As expected, operations liked the export. Now they want another one, but they
want to be able to generate it themselves right from the admin section.
Assuming the server is running Ruby (a safe assumption for the time being), we
may be tempted to reach for the CSV library. After all, it is right there in the
standard library. However, that may require rewriting our perfectly functional
query in `ActiveRecord`. It would also involve pulling all of the data back from
the server and instantiating objects for every column and row. There is a better
way!

Every database connection adapter has the means to execute a SQL query and read
back the results. Ruby's `pg` adapter is no exception. With a very thin wrapper
around a database connection you can generate exports from the same query file
right on the server.

First, the wrapper class:

```ruby
class PostgresCSVWriter
  attr_reader :adapter

  def initialize(adapter = ActiveRecord::Base)
    @adapter = adapter
  end

  def connection
    adapter.connection.instance_variable_get('@connection')
  end

  def write_rows(query, io: '')
    connection.copy_data(build_copy_query(query)) do
      while row = connection.get_copy_data
        io << row
      end
    end
  end

  private

  def build_copy_query(query)
    %(COPY (#{query}) TO STDOUT WITH DELIMITER ',' CSV HEADER)
  end
end
```

Please note that while the query itself is interpolated, it is *not* escaped,
and is therefore vulnerable to injection attacks. This is not suitable for user
generated queries.

With the base writer in place you can now write an exporter that injects an
existing `.sql` query and hands back a string suitable for streaming back to the
client.

```ruby
require 'postgres_csv_writer'

class PostgresCSVExporter
  def export(filename)
    writer.write_rows(query(filename))
  end

  def query(filename)
    IO.read(Rails.root.join('queries', filename))
  end

  private

  def writer
    PostgresCSVWriter.new
  end
end
```

Exports are now as simple as `PostgresCSVExporter.new.export('cohorts.sql')`.
Every export lives in its own `.sql` file which can be edited and executed
natively. For larger exports, this approach will build up multi-megabyte
strings, which is probably undesirable. In those situations you may reach for
`Tempfile` and send the file contents rather than a large string.

Now you can keep all of your queries written in completely portable SQL. The
queries can be accessed from any other tech stack without the need for an ORM or
an intermediate representation. Let the team know their exports are now just one
click away.
