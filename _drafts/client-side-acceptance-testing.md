---
layout: default
author: Parker Selbert
summary: Writing acceptance tests for client side JavaScript
---

The [testing pyramid][0] is a guideline for how much testing
attention should be spent on each layer of an application. Without repeating too
much of that excellent article I'll summarize each layer briefly:

* **Unit** — At the very bottom of the pyramid are unit tests. They should be
  cheap to write, quick to run, and as numerous as the developer sees fit.
* **Service** — The objects and methods that glue an application together. When
  written with [dependency injection][1] in mind they can as light weight as a
  unit test. However, they tend to be stateful and require more context.
* **Acceptance** — High level tests that are designed to express how an
  application is expected to behave. Because acceptance tests exercise every
  layer of an application *without* mocking any dependencies they are much more
  expensive to run than unit and service tests.

How does the testing pyramid apply to client side applications? When a client
side application is actually test driven, often the code stops being tested at
the unit level. Unit tests perform beautifully for functional helper objects and
minimally stateful objects like models. It gets messier when you start trying to
test a complex view with sub-views and complex state. At that point you are
caught mocking dependencies, faking events, faking the DOM, or otherwise setting
up uncomfortably elaborate context.

* nod to ember (fixtures, testing mode, reset)
* nod to angular (dependency injection)

pain points of acceptance testing the full stack

* slow tests due to rendering, database persistence, framework startup times
* dependent on working on the entire application at once. that isn't always
  the case.
* constant race conditions from running multiple instances of the same server

benefits of writing acceptance tests only for the client side:

* drive the development of a feature from tests. start with a higher level
  description of **what** a feature is doing and the expected behavior.
* test across the full client side stack, data, event handling, rendering
* performance is an undeniable benefit. a full acceptance test suite for a
  small app can run in less than 250ms.

drawbacks of client side acceptance tests

* no resistance to changes on the server. if any parameters are incorrectly
  formatted for the server you won't know about it. this is a minor concern
  though, as you don't have any assurance that your client side app is
  working as expected **without** the tests.

## A Real Example

```coffeescript
describe 'Acceptance / Login', ->
  beforeEach ->
    console.log('sign in')

  afterEach ->
    console.log('sign out')

  it 'authorizes the user logs them in', ->
    expect(true).to.be.false
```

[0]: http://www.mountaingoatsoftware.com/blog/the-forgotten-layer-of-the-test-automation-pyramid
[1]: http://need-this-link
