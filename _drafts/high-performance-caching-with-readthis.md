---
layout: default
author: Parker Selbert
summary: Strategies behind building a faster Redis cache
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
  - Bulk operations wherever possible
  - Forcing the use of hiredis
- Faster marshalling
  - Allowing plug in marshallers such as JSON
  - Pass through, because no code is faster than no code
- Comparing to the entity store in active support:
  - Using pure methods, avoid instantiating objects
  - Doesn't contain any legacy methods or intermediate wrappers (elaborate)
