---
layout: default
summary: Lightweight testing for libraries that integrate with Rails
author: Parker Selbert
tags: ruby rack
---

Without full stack integration tests I never have complete confidence that a
system will function properly. As well tested and designed as the individual
components may be there is no way to truly know how they will interact without
exercising them together. At its core object orientation is about message
passing between objects, and it is the message passing that needs to be tested.

## Avoiding Rails

Just recently I revamped [Fragmenter][0], a multipart uploading library that
handles storing and reassembling binary data. Fragmenter is designed to work
with any web framework, but the most likely targets are Rails applications.
Even with such a strong imperative to integration test I still didn't want to
test against an entire Rails application.

Simply loading a fresh install of the current Rails (4.0.0 at the time of
writing) installs **44** gems, using **33 MB** of space, and takes **~1.05**
seconds to load:

```bash
$ bundle list | wc -l
# 44
$ du -h vendor/ruby/2.0.0 | tail -n 1
# 40M vendor/ruby/2.0.0
$ for i in {1..10}; do time rails r ''; done 2>&1 |\
  awk '{ sum += $4 } END { print sum / NR }'
# 1.05
```

Fragmenter provides two modules for mixing in to classes within an app, one for
`models` and one for `controllers`. The modules are insular and only rely on
services that Fragmenter provides, they have no reliance on Rails or Railties.
The decision to keep Fragmenter decoupled from Rails was made for ease of use
with other web frameworks, i.e. Sinatra. Decoupling gives the added benefit
of integrating against the most minimal API possible: Any class that can handle
Rack [requests][1] and [responses][2].

```ruby
class UploadsController < ApplicationController
  include Fragmenter::Rails::Controller
end

class Resource < ActiveRecord::Model
  include Fragmenter::Rails::Model
end
```

## Testing Requests

All of the interaction with Fragmenter's mixins are via HTTP, making it ideal
for exercising with a request spec. Using [Rack Test][3] makes sending
requests to a Rack app and making assertions on the response extremely easy.
The standard structure of a request spec looks like:

```ruby
require 'rack/test'

describe 'A Resource' do
  include Rack::Test::Methods

  let(:app) do
    lambda { [200, {}, 'Success!'] }
  end

  it 'performs a successful GET request' do
    get 'http://example.com'

    expect(last_response).to      eq(200)
    expect(last_response.body).to eq('Success!')
  end
end
```

All that Rack::Test expects is an `app` method returning an object that adheres
to the [Rack interface][4]. In the example above we have a hardcoded lambda
that will always return the same result. To test Fragmenter functionality we'll
replace the lambda with a Rack compatible class that includes Fragmenter's
controller mixin:

```ruby
require 'fragmenter/rails/controller'
require 'rack/request'

class UploadsApp
  include Fragmenter::Rails::Controller

  attr_reader :request, :resource

  def initialize(resource)
    @resource = resource
  end

  def call(env)
    @request = Rack::Request.new(env)

    case request.request_method
    when 'GET'    then show
    when 'PUT'    then update
    when 'DELETE' then destroy
    end
  end
end
```

When a Rails controller handles requests it automatically provides the
`request` object. Here we must instantiate the request manually, which is very
straight forward. Each of the HTTP verbs is then mapped directly to the
corresponding mixed in method—acting as a micro RESTful router.

Lets write a spec to actually test the request/response cycle for one of the
`UploadApp` methods:

```ruby
require 'fragmenter'
require 'json'
require 'rack/test'

describe 'Uploading Fragments' do
  include Rack::Test::Methods

  Resource = Struct.new(:id) do
    include Fragmenter::Rails::Model

    def rebuild_fragments
      fragmenter.rebuild && fragmenter.clean!
    end
  end

  let(:resource) { Resource.new(200) }
  let(:app)      { UploadsApp.new(resource) }

  it 'Stores uploaded fragments' do
    header 'Content-Type',      'image/gif'
    header 'X-Fragment-Number', '1'
    header 'X-Fragment-Total',  '2'

    put '/', file_data('micro.gif')

    expect(last_response.status).to eq(200)
    expect(decoded_response).to eq(
      'content_type' => 'image/gif',
      'fragments'    => %w[1],
      'total'        => '2'
    )

    header 'X-Fragment-Number', '2'
    header 'X-Fragment-Total',  '2'

    put '/', file_data('micro.gif')

    expect(last_response.status).to eq(202)
    expect(decoded_response).to eq('fragments' => [])
  end
```

The example simulates uploading two distinct parts of a very small `gif` and
sets expectations about the responses it gets back. It looks like there is a
lot more going on here, but all of the methods (`header`, `put`) are still
provided by Rack::Test. The most notable addition is the `Resource` class, a
generic model-like class that includes Fragmenter's model mixin.

Running the spec yields an unexpected error:

```bash
Failure/Error: put '/', file_data('micro.gif')
NoMethodError:
 undefined method `render' for #<UploadsApp:0x007fb96c1c2168>
```

The `render` method is the missing part of the Rails compatibility puzzle. Each
of the controller actions end with a call to `render` with some json and a
status code. Looking through the [signature for render][5] it is clear that
only need to implement a small part of the functionality to get Rails
compatibility with the `UploadsApp`:

```ruby
require 'fragmenter'
require 'rack/request'
require 'rack/response'

class UploadsApp
  # No change to the rest of the class

  private

  def render(options)
    body = if options[:json]
      JSON.dump(options[:json])
    else
      ''
    end

    Rack::Response.new(body, options[:status], {}).finish do
      @uploader = nil
    end
  end
end
```

The the compatible `render` method in place our specs pass, and very quickly at
that!

```bash
Uploading Fragments
  Stores uploaded fragments

Finished in 0.01303 seconds
1 example, 0 failures
```

## A Solid Victory

All of the integration issues exposed by the request spec were between
Fragmenter classes and Rack, there weren't any incompatibilities when it was
pulled into a full Rails app.

The tradeoff of testing without Rails is that it won't be resistant to changes
in `render`, but that has been stable for a **long** time. The risk is well
worth the savings in setup, boot time, run time, and complexity.

_Please note that in reality the spec was written before the `UploadApp`
implementation. It made more sense to explain the process slightly out of
order._

[0]: https://github.com/dscout/fragmenter
[1]: https://github.com/rack/rack/blob/master/lib/rack/request.rb
[2]: https://github.com/rack/rack/blob/master/lib/rack/response.rb
[3]: https://github.com/brynary/rack-test
[4]: http://www.ruby-doc.org/core-2.0/Proc.html#method-i-call
[5]: https://github.com/rails/rails/blob/master/actionpack/lib/abstract_controller/rendering.rb#L95
