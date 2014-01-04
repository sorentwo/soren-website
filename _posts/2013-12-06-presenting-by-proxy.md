---
layout: default
summary: Leveraging ES6 Harmony's Proxy object for MVP
---

The [mediator pattern][1] is an essential technique for cleanly stratifying any
data-driven system into layers with distinct responsibilities. The concept is
simple, take an object and wrap it in another object. When methods are called on
the wrapping object it, selectively overrides the method to process the original
object's data, or it just passes the method call through to the original object.
That description doesn't do the pattern justice, and probably confused you if
you already implement mediator pattern style presenters. Let's illustrate the
concept with some Ruby code:

```ruby
require 'delegate'

Model = Struct.new(:id, :title)

class Presenter < SimpleDelegator
  def slug
    title.downcase.gsub(/\s+/, '-')
  end
end

model = Model.new(100, 'Presenters Rule')
presenter = Presenter.new(model)

presenter.title # 'Presenters Rule'
presenter.slug  # 'presenters-rule'
```

Implementing the presenter pattern in Ruby is almost free because of the
[Delegate](2) module from the standard library. It is a fairly thin wrapper
around Ruby's dynamic method dispatch, `method_missing`. Whenever an unknown
method is sent to a delegate it dynamically checks whether the object it is
delegating to has that method and calls that instead. In the instance above the
*delegator* is being elevated to a *presenter* by manipulating the data
slightly.

What about languages that don't have `method_missing`? One such language is
JavaScript. There isn't any [standard tracked method](3) for [handling method
calls](4) dynamically. Fortunately, JavaScript is highly malleable, allowing for
dynamic assignment instead. Let's take a shot at a JavaScript presenter:

```javascript
var Presenter = function(model) {
  this.model = model;

  for (key in model) {
    if (model.hasOwnProperty(key) && !this.hasOwnProperty(key)) {
      this[key] = model[key]
    }
  }
}

Presenter.prototype.slug = function() {
  return this.title.toLowerCase().replace(/\s+/, '-');
};

model = { id: 100, title: 'Presenters Are Fun!' };
presenter = new Presenter(model);

presenter.title  // 'Presenters Are Fun'
presenter.slug() // 'presenters-are-fun'
```

That was a bit more work wasn't it? Not only that, it has some major pitfalls.

First, there is the issue of [uniform access principal](5). In Ruby every
message sent to an object with `.` is a method call, whether that particular
method returns a static value or is a proper method definition. That isn't the
case in JavaScript. Calling a method on an object with `.` will always yield the
value of that object. That means if the value of an object is a function you'll
get a `[Function]` reference back, not the evaluated function. This is evident
in the call to `presenter.slug()` above—it required the trailing `()` to invoke
the function, whereas the call to `presenter.title` did not.

There is also the issue of duplicating all of the data from the model onto the
presenter. For trivial applications or models with only a few attributes
duplication isn't much of an issue. When you have hundreds or thousands of
models with nested objects or sizable data the duplication is entirely wasteful.
In addition, as soon as the model's data changes the presenter will be out of
sync. Referencing the example above:

```javascript
console.log(model.id, presenter.id); // 100, 100
model.id = 101;
console.log(model.id, presenter.id); // 101, 100
```

It turns out that [ES6 Harmony](6) proposes a clean solution to our presenter
problem. As of Firefox 18.0, Chrome 24.0 there is a new [Proxy API](7), allowing
objects to be created and have properties computed at runtime. This is an ideal
tool for a presenter. Here is a simple example of how the `Proxy` object
behaves:

```javascript
var handler = {
  get: function(target, name) {
    return name in target ? target[name] : 'missing';
  }
}

var data  = { id: 100 },
    proxy = new Proxy(data, handler);

console.log(proxy.id); // 100
console.log(proxy.title); // 'missing'
```

Three objects are interacting together here: a data object, a handler, and the
proxy itself. There is a wealth of what are called `traps` available to the
handler object. The example above uses the `get` trap to determine how to
respond to property access. This is exactly what we need for a proper presenter!

```javascript
var Presenter = {
  present: function(model) {
    return new Proxy(model, this.handler);
  },

  handler: {
    get: function(target, name) {
      var value = name in target ? target[name] : this[name];

      return typeof value == 'function' ? value(target) : value;
    },

    slug: function(target) {
      return target.title.toLowerCase().replace(/\s+/, '-');
    }
  }
};

var model = { id: 100, title: 'Proxy Presenter' },
    presenter = Presenter.present(model);

console.log(presenter.id, presenter.slug); // 100, proxy-presenter

model.title = 'Dynamic Presenter';
console.log(presenter.slug); // dynamic-presenter
```

This version holds all of the benefits of a presenter with none of the drawbacks
enumerated before.

1. The handler's `get` trap uniformly handles values from the model and methods
   from the presenter.
2. There is no data duplication.
3. The data will always be in sync, as it is dynamically retrieved during
   runtime. There is no need to observe the original object or keep properties
   synchronized with events.

Unfortunately, as with any new web technology, there is the adoption hurdle.
Proxy isn't available in many browser's, even in Chrome without explicitly
enabling [javascript harmony](8). Until the shiny future where the vast majority
of browsers support `Proxy` you will need to provide a hybridized version using
feature flags. That is precisely what I'll be doing for my MVP needs.

[1]: http://c2.com/cgi/wiki?MediatorPattern
[2]: http://www.ruby-doc.org/stdlib-1.9.3/libdoc/delegate/rdoc/SimpleDelegator.html
[3]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/noSuchMethod
[4]: http://yehudakatz.com/2008/08/18/method_missing-in-javascript/
[5]: http://martinfowler.com/bliki/UniformAccessPrinciple.html
[6]: https://wiki.mozilla.org/ES6_plans
[7]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Proxy
[8]: chrome://flags/#enable-javascript-harmony
