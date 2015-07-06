---
layout: default
summary: Fixing inconsistent timestamp serialization in Rails 4
author: Parker Selbert
tags: rails
---

The de-facto standard for representing dates and times is [ISO8601][0]. The
standard describes a variety of date/time formats, but as developers on the
modern web the format that we routinely encounter looks like this:

```
YYYY-MM-DDThh:mm:ssTZD (eg 1997-07-16T19:20:30+01:00)
```

If you read slightly farther in the spec you'll see that there is also an
enhanced form that includes fractions of a second:

```
YYYY-MM-DDThh:mm:ss.sTZD (eg 1997-07-16T19:20:30.45+01:00)
```

Note the decimal near the end of the second format (`ss.s`). The decimal allows
sub-second precision within date/time, which is potentially useful. Ruby's
standard `Date` and `Time` libraries support parsing the higher resolution
format via methods like [Date.iso6801][1]. Though they support parsing they don't
output fractions of a second when the `#iso8601` method is called on an
instance of `Time`:

```ruby
Time.now.iso8601 #=> "2013-07-22T20:57:21-05:00"
```

## Changes in Rails 4

Those of you with a test suite that verifies timestamps may have noticed a
[change when upgrading to Rails 4][2]. Given a request spec similar to this:

```ruby
it 'lists an existing post' do
  post = Post.create(title: 'Strawberries')

  get "http://example.com/api/posts/#{post.id}"

  decoded = JSON.parse(last_response.body)

  expect(decoded).to eq(
    'id'         => post.id,
    'title'      => 'Strawberries',
    'created_at' => post.created_at.iso8601,
    'updated_at' => post.updated_at.iso8601
  )
end
```

The spec will fail when comparing both timestamps, even though they have been
formatted as `iso8601`. The fake diff below attempts to illustrate this:

```bash
-"created_at"=>"2013-07-22T21:48:19Z",
+"created_at"=>"2013-07-22T21:48:19.355Z",
```

The problem stems from an inconsistent overriding of `as_json` that only
applies to instances of `TimeWithZone` but does not effect the `as_json` monkey
patching of [Time, Date, and DateTime][3].

## Temporary Solution

The sub-second resolution change, as small as it is, was enough to break
timestamp parsing within some iOS apps. To prevent backward incompatibilities
I've laid my own monkey patch over `TimeWithZone`:

```ruby
# config/initializers/time_with_zone.rb

module ActiveSupport
  class TimeWithZone
    def as_json(options = nil)
      iso8601
    end
  end
end
```

Going forward I'm looking to [expose configuration][4] that allows the
resolution to be configured. The default behavior in Rails 4 will remain `3`
digits of resolution, but setting the resolution to `0` will remove it
entirely.

[0]: http://www.w3.org/TR/NOTE-datetime
[1]: http://ruby-doc.org/stdlib-2.0/libdoc/date/rdoc/Date.html#method-c-_iso8601
[2]: https://github.com/rails/rails/commit/28ab79d7c579fa1d76ac868be02b38b02818428a
[3]: https://github.com/rails/rails/blob/master/activesupport/lib/active_support/json/encoding.rb#L316
[4]: https://github.com/rails/rails/pull/11464
