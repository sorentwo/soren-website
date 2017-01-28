---
layout: default
title: Rails Speed Audit
---

<section class="wrapper room-on-top audit" markdown="1">
# Is a slow Rails app hurting your business?

* Are customers losing time (and sanity) waiting for pages to load?
* Have you lost conversions because pages load too slowly?
* Are you hemorrhaging sales because the app feels sluggish?
* Is the business growing while the servers fail to keep up?
* Have your business partners complained that your app is slow and unreliable?

There's an answer, and throwing more hardware or developers at the problem isn't it.

**Rails can be blazing fast with caching!**

Caching is vital to any fast production application.
It **makes your app faster** by letting it doing less work.
Whether that means pages are built once and shared, or that content is served from geographically closer locations, customers will **feel the difference**.

Caching is a broad topic with a lot of nuance.
It is one of the classic [hard things in computer science](https://martinfowler.com/bliki/TwoHardThings.html)!
Even experienced developers may not be familiar with every technique or strategy available in Rails.
We'll help you identify what is holding your app back and where to apply caching to speed it up using techniques like:

* Caching Headers
* Page & Asset Compression
* Page Caching
* Fragment Caching
* Russian Doll Caching
* Content Expiration Strategies
* Content Delivery Networks (CDN)
* Optimizing Infrastructure

Caching isn't always the solution, but when it is the results are dramatic.
After applying these strategies a **3&times;—4&times;** improvement in page load times is common.
In extreme cases we've seen load times drop from **30s** to **under 1s**, that's a **30&times;** improvement!.

A lack of caching may be **hurting your revenue**, and you may not even know it!
Don't take our word for it, extensive research has been done on the subject:

* [How Loading Time Affects Your Bottom Line](https://blog.kissmetrics.com/loading-time/)
* [Slow Pages Lose Users](http://www.icrossing.com/uk/ideas/slow-pages-lose-users)
* [Importance of Website Loading Speed](https://www.linkedin.com/pulse/20140516013608-1981105-the-importance-of-website-loading-speed-top-3-factors-that-limit-website-speed)

With a slow site your business is leaving money on the table.
Regain customer trust and increase profits by getting your application fast again.
</section>

<section class="wrapper audit audit-case-study" markdown="1">
  <h2>10&times; Performance Improvements for First</h2>

  When we were approached by the predictive real estate company [First](https://first.io/), some of their critical API endpoints took **10s** or more to load.
  During diagnosis we measured and identified the worst offending endpoints and devised a robust caching strategy.

  After working with First to build out their infrastructure and apply nested caching we saw **full page response times fall below 1s**, and select endpoints responding in **under 100ms**.

  ![Skylight Performance](/assets/skylight-sample.jpg)

  <hr class="audit-rule" />

  <div class="audit-testimonial">
    <img class="audit-testimonial__photo" src="/assets/jess-martin.jpg" />
    <div class="audit-testimonial__body">
      <blockquote class="audit-testimonial__quote">
        Before Soren, our app was <b>painfully</b> slow.
        Paying customers were complaining and our customer success team cringed when they had to answer questions about the app's performance.
        We had already made all the obvious speed improvements and weren't quite sure where to turn.
        I still remember when we finished the work on caching — the team would just refresh the app over and over and say 'Look how much faster that is!'
      </blockquote>
      <cite class="audit-testimonial__cite">Jess Martin, CTO</cite>
    </div>
  </div>

  <div class="audit-testimonial">
    <img class="audit-testimonial__photo" src="/assets/glenn-vanderburg.jpg" />
    <div class="audit-testimonial__body">
      <blockquote class="audit-testimonial__quote">
        Soren not only made our app a lot faster, but left us with a clear, sensible caching policy that was easy for us to work with.
        They actually improved our understanding of our own domain.
      </blockquote>
      <cite class="audit-testimonial__cite">Glenn Vanderburg</cite>
    </div>
  </div>
</section>

<section class="wrapper audit" markdown="1">
## Interested? Here's what we'll do together.

Within **3 days** of kickoff we'll generate a performance prescription report diagnosing *precisely* what is making your application so slow.
The report identifies layers of slowdown and where caching, tuning and performance can be improved.
Each step of the report prescribes a plan of attack, starting with the changes that will have the biggest impact.

1. A **30 minute** onboarding call to discuss your current pain points
2. Application audit to generate an **actionable** performance report
3. Prescription of specific changes, fixes and optimizations to speed the app up
4. A follow up **7 days** after completion

Price **$1,500**, no fees or variable rates.
</section>

<section class="audit wrapper audit-guarantee" markdown="1">
#### Satisfaction Guaranteed

Not every performance problem can be solved by caching.
We may tell you that there are underlying problems and there is other work that you need to do.
If we're not the right people for the job, we'll tell you so!

If you apply the prescription and don't get results, we will keep working with you until you do.
</section>

<form class="wrapper audit audit-form" accept-charset="UTF-8" action="https://formkeep.com/f/f33270e65797" method="POST">
  <h2>Ready to get started?</h2>
  <p class="form-subtitle">Speed up your app and start earning more.</p>

  <input type="hidden" name="utf8" value="✓">

  <fieldset class="audit-form__fieldset">
    <div class="input">
      <label for="name">What is your name?</label>
      <input type="text"  name="name" required>
    </div>

    <div class="input">
      <label for="email">What is your email address?</label>
      <input type="email" name="email" required>
    </div>

    <div class="input">
      <label for="website">What is your app's website?</label>
      <input type="url" name="website" required>
    </div>
  </fieldset>

  <button class="button">Request Free Consult</button>
</form>

<section class="wrapper audit" markdown="1">
## About Soren

We've been helping startups and mid-size businesses speed up, stabilize, and all around improve their Rails apps for **10 years**.
Along the way we've seen a lot of apps with performance problems, fixed them, written about it, and authored some of the fastest caching libraries in the Rails world.

Here are a few technical articles for you:

* [High Performance Caching With Readthis](http://sorentwo.com/2015/07/20/high-performance-caching-with-readthis.html)
* [Layering API Defenses With Caching](http://sorentwo.com/2015/10/19/layering-api-defenses-with-caching.html)
* [Knuckles, The Next Level of API Caching](http://sorentwo.com/2016/05/10/knuckles-the-next-level-of-api-caching.html)
* [Essentials of Cache Expiration in Rails](http://sorentwo.com/2016/07/11/essentials-of-cache-expiration-in-rails.html)
* [Optimizing Redis Usage for Caching](http://sorentwo.com/2015/07/27/optimizing-redis-usage-for-caching.html)
</section>
