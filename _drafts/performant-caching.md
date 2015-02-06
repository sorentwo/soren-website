---
layout: default
author: Parker Selbert
summary: Strategies behind building a fast cache
---

- Gently introduce readthis
  - Redis backed cache implementation
  - Focus on lightweight startup and lightweight runtime
  - Ultimately focused on raw speed
- Identifying the largest performance bottlenecks:
  - Roundtrip to redis
  - Marshalling
  - Object creation (entities)
- Mitigating the redis roundrip
  - Forcing the use of hiredis
  - Layering a LRU cache in front redis. More general than `LocalCache`, but not markedly thread safe.
- Comparing to the entity store in active support:
  - Using pure methods, avoid instantiating objects
  - Allowing other marshallers such as JSON or Oj, even a pass-through for pure strings
- Overall the fastest cache available
  - Even faster than ActiveSupport::MemoryCache.
  - No need to choose just one type of cache, get the best of both worlds
