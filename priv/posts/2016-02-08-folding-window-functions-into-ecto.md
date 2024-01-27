%{
  author: "Parker Selbert",
  summary: "Understand the power of Postgres window functions to manipulate data efficiently with Ecto",
  title: "Folding Window Functions into Ecto"
}

---

<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/1.0.2/Chart.js"></script>

*This is a reinterpretation of [Folding Window Functions Into Rails][fold], rewritten and adapted from ActiveRecord to [Ecto][ecto] 2.0.
The results were unexpected...*

Perhaps you've heard of window functions in PostgreSQL, but you aren't quite sure what they are or how to use them.
On the surface they seem esoteric and their use-cases are ambiguous.
Something concrete would really help cement when window functions are the right tool for the job.
That's precisely what we'll explore in this post:

1. How to recognize where a window function is helpful
2. How to build an Ecto query that implements window functions
3. How to use tests to drive a switch from naive Ecto to a window function query

## An Anecdotal Example

You've recently finished shipping a suite of features for an application that helps travelers book golf trips.
Things are looking good, and a request comes in from your client:

> Our application started by being the go-to place to find golf trips, and our users love it.
> Some of the resorts that list trips with us also offer some non-golf events, such as tennis, badminton, and pickleball.
> When we begin listing other trips it would be great to highlight our user's favorite trips for each category.
> Can you do that for us?
>
> —<cite>Anonymous Client</cite>

Why, of course you can do that!
The application lets potential traveler's flag trips they are interested in as favorites, providing a reliable metric that we can use to rank trips.
With the simple addition of a `category` for each trip we can also filter or group trips together.
This seems straight forward enough...

## Survey the Scene

A look at the `Trip` schema reveals that it currently has these relevant fields: `name`, `category`, and `favorites`.

```elixir
defmodule Triptastic.Trip do
  use Ecto.Schema

  @categories ~w(golf tennis badminton pickleball)

  schema "trips" do
    field :name, :string
    field :category, :string
    field :favorites, :integer, default: 0
  end

  def categories, do: @categories
end
```

Instead of listing all of the top ranked trips we'll only show the *top two* trips in each category.
Some tests will help verify that we're getting the expected results.

```elixir
defmodule Triptastic.TripRepoTest do
  use ExUnit.Case

  alias Triptastic.{Repo, Trip}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Triptastic.Repo)

    trips = for category <- Trip.categories, favorites <- 0..5 do
      %{name: "#{category}-#{favorites}",
        category: category,
        favorites: favorites}
    end

    Repo.insert_all(Trip, trips)

    :ok
  end

  test "grouping top trips by category" do
    trips = Trip |> Repo.all() |> Trip.popular_by_category()

    assert length(trips) == 8
    assert Enum.all?(trips, &(&1.favorites > 2))
  end
end
```

The test seeds the test database with trips across four categories with a varying number of favorites.
The `popular_by_category/2` function expects a list of trips and returns the most popular two from each category.

Initially we'll approach this with pure naive Elixir.
All of the trips are loaded into memory, grouped by category, ranked according to the number of favorites, and then the requested `per` amount is taken off of the top.
Do note that sorting is comprised of both favorites and name, which is necessary to force deterministic sorting in the likely event that trips are equally popular.

```elixir
# Defined within the Triptastic.Trip module shown above

def popular_by_category(trips, per \\ 2) do
  trips
  |> Enum.group_by(&(&1.category))
  |> Enum.flat_map(&(popular_in_subset(&1, per)))
end

defp popular_in_subset({_category, trips}, per) do
  trips
  |> Enum.sort_by(&([-&1.favorites, &1.name]))
  |> Enum.take(per)
end
```

As a wizened developer you immediately recognize that loading every trip into memory simply to retrieve eight results is rather inefficient.
It makes fine use of the `Enum` module and some piping, but it isn't suitable for production usage.

## Move the Logic to PostgreSQL

Between various sub-selects, `GROUP BY` with aggregates and multiple queries, there are many ways to manipulate the trips data in SQL.
One advanced feature of PostgreSQL that is particularly adept at solving this categorization problem are [window functions][tw].
Directly from the documentation:

> A window function performs a calculation across a set of table rows that are somehow related to the current row.
>
> <cite>[Postgres Documentation][tw]</cite>

The key part of the phrase is the power of calculating across related rows.
In our case, the rows are *related* by category, and the *calculation* being performed is ordering them within those categories.
In the realm of window functions this is handled with an [`OVER` clause][swf].
There are additional expressions for fine tuning the window, but for now we can achieve all we need with `PARTITION BY` and `ORDER BY` expressions.
Dropping into `psql`, let's see how to partition the data set by category:

```postgressql
SELECT category, favorites, row_number() OVER (PARTITION BY category) FROM trips;
```

```
  category  | favorites |  row_number
------------+-----------+-------------
 badminton  |         0 |          1
 badminton  |         1 |          2
 badminton  |         2 |          3
 badminton  |         3 |          4
 golf       |         0 |          1
 golf       |         1 |          2
```

The `row_number` is a *window function* that calculates number of the current row within its partition.
Row number becomes crucial when the partitioned data is then ordered:

```postgressql
SELECT category, favorites, row_number() OVER (
  PARTITION BY category ORDER BY favorites DESC
) FROM trips;
```

```
  category  | favorites | row_number
------------+-----------+------------
 badminton  |         3 |          1
 badminton  |         2 |          2
 badminton  |         1 |          3
 badminton  |         0 |          4
 golf       |         3 |          1
 golf       |         2 |          2
```

All that remains is limiting the results to the top ranked rows and our query matches the expected output.

## Move It Into Ecto

At this time there aren't any constructs for `OVER` built into Ecto 2.0 and it doesn't support arbitrary `FROM` clauses.
The only way to utilize window functions is with the raw `Ecto.Adapters.SQL.query` function.
Using the `from` macro from `Ecto.Query` with a sub-select would be preferable to working with a raw string, but we aren't there yet.

We'll make a new test that is very similar to the last, but which expects a `Postgrex.Result` struct instead.
The `Result` struct wraps a list of raw rows with all of the trip data.

```elixir
test "grouping top trips by category using windows" do
  {:ok, result} = Trip.popular_over_category()

  assert result.num_rows == 8
  assert Enum.all?(result.rows, &(Enum.at(&1, 3) >= 2))
end
```

Now the `popular_over_category/1` function must be defined to construct a SQL query:

```elixir
def popular_over_category(per \\ 2) do
  query = """
    SELECT * FROM (SELECT *, row_number() OVER (
      PARTITION BY category
      ORDER BY favorites DESC, name ASC
    ) FROM trips) AS t WHERE t.row_number <= $1::integer;
  """

  Ecto.Adapters.SQL.query(Triptastic.Repo, query, [per])
end
```

The query string uses a subquery to build up trips partitioned by category.
The `where` clauses filters out any trips with a `row_number` below the desired threshold, and only the top favorites in each category are returned.
With the change in place the new test is now passing!

Inspecting the test results, with the help of some formatting, yields:

```
  category  | favorites | row_number
------------+-----------+------------
 badminton  |         3 |          1
 badminton  |         2 |          2
 golf       |         3 |          1
 golf       |         2 |          2
 pickleball |         3 |          1
 pickleball |         2 |          2
 tennis     |         3 |          1
 tennis     |         2 |          2
```

Those are precisely the results we're looking for!

## How Much Better Is It?

Here is where the presumptions behind this article fall apart and the BEAM blows my mind.
The original version of this article was written about window queries in Rails.
In those benchmarks the window function was *539.3x* faster than the naive version.
Naturally, I was excited to see how well the Elixir/Ecto variant would perform in comparison.

This benchmarking test has a lot of boilerplate just to set up the sandbox and insert an arbitrary number of trips into the database.
An outer `for` comprehension builds up a sequence of tests with an increasing number of trips for comparison.
All tests are run in separate processes via `Task.async |> Task.await`, which introduces the slight complication of sharing sandboxed connection ownership.
Note that the test caps out at 20,000 trips because any more breask `Repo.insert_all`, and that is plenty for a comparison.

```elixir
defmodule Triptastic.TripBenchmarkTest do
  use ExUnit.Case

  alias Triptastic.{Repo, Trip}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  def ms(parent, fun) do
    Task.async(fn ->
      Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
      begin = :os.timestamp
      fun.()
      finish = :os.timestamp
      :timer.now_diff(finish, begin) / 1000
    end) |> Task.await
  end

  for num <- [100, 500, 5_000, 10_000, 20_000] do
    @tag num: num
    test "compare memory and windows for #{num} trips", %{num: num} do
      categories = Stream.cycle(Trip.categories)

      trips = for _ <- 1..num do
        cat = hd(Enum.take(categories, 1))
        fav = trunc(:rand.uniform() * 10)

        %{name: "#{cat}-#{fav}", category: cat, favorites: fav}
      end

      Repo.insert_all(Trip, trips)

      mem = ms(self(), fn -> Trip |> Repo.all |> Trip.popular_by_category end)
      win = ms(self(), fn -> Trip.popular_over_category end))
      wij = ms(self(), fn -> Trip.popular_over_category_joined |> Repo.all end)

      IO.puts "| #{num} | #{mem} | #{win} | #{wij} |"
    end
  end
end
```

<canvas id="perf-chart" width="800" height="400"></canvas>

<script>
  var data = {
    labels: ["100", "500", "5,000", "10,000", "20,000"],
    datasets: [
      {
        label: "memory",
        fillColor: "rgba(220,220,220,0.2)",
        strokeColor: "rgba(220,220,220,1)",
        pointColor: "rgba(220,220,220,1)",
        pointStrokeColor: "#fff",
        pointHighlightFill: "#fff",
        pointHighlightStroke: "rgba(220,220,220,1)",
        data: [2.46, 22.09, 34.62, 69.44, 147.99]
      },
      {
        label: "window",
        fillColor: "rgba(151,187,205,0.2)",
        strokeColor: "rgba(151,187,205,1)",
        pointColor: "rgba(151,187,205,1)",
        pointStrokeColor: "#fff",
        pointHighlightFill: "#fff",
        pointHighlightStroke: "rgba(151,187,205,1)",
        data: [2.13, 3.48, 19.75, 38.33, 76.32]
      },
      {
        label: "joined",
        fillColor: "rgba(150,206,173,0.2)",
        strokeColor: "rgba(150,206,173,1)",
        pointColor: "rgba(150,206,173,1)",
        pointStrokeColor: "#fff",
        pointHighlightFill: "#fff",
        pointHighlightStroke: "rgba(150,206,173,1)",
        data: [4.47, 5.74, 20.08, 42.85, 77.83]
      }
    ]
  };
  var ctx = document.getElementById('perf-chart').getContext('2d');
  var perfChart = new Chart(ctx).Line(data, { responsive: true });
</script>

With a small number of trips the performance difference is negligible.
As the number of trips increases the cost of loading that many records into memory simply to filter them out does start to add up.
Even with 20,000 records being slurped in for manipulation, the naive strategy is only *2x* slower.
For now, if you are working in Ecto, you can rest assured that the performance of naive queries is good enough not to worry about fiddling with raw SQL.

The simple application used for testing can be found in [triptastic on GitHub][trip].

**Edit**: The benchmark test and chart now includes a hybrid approach where the `OVER` sub-select is performed in a join.
This was suggested by Jośe Valim as a way to avoid SQL queries, and provides better query interop with comparable performance.

[fold]: http://blog.codeship.com/folding-postgres-window-functions-into-rails/
[ecto]: https://github.com/elixir-lang/ecto
[tw]: http://www.postgresql.org/docs/9.4/static/tutorial-window.html
[swf]: http://www.postgresql.org/docs/9.4/interactive/sql-expressions.html#SYNTAX-WINDOW-FUNCTIONS
[wf]: http://tapoueh.org/blog/2013/08/20-Window-Functions
[trip]: https://github.com/sorentwo/triptastic
