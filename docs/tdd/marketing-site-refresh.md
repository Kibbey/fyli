# TDD: Marketing Site Content Refresh

## Overview

The fyli marketing site (fyli-html) is significantly out of date. It markets "Discover, Share, Preserve Stories" with Albums, Timelines, and pricing plans — none of which match the current product. The actual product has Storylines, Questions, AI writing assist, share links, and a free-first model.

This TDD defines the content refresh to align the marketing site with the current product, shift messaging toward the busy-parent persona, and remove the pricing section in favor of driving signups directly.

**PRD:** `docs/prd/PRD_MARKETING_SITE_REFRESH.md`

## Problem Analysis

**Current state — what the site says vs. what the product does:**

| Marketing Site (Current) | Actual Product | Gap |
|--------------------------|---------------|-----|
| "Discover, Share, Preserve Stories" | Memory capture, Storylines, Questions, Sharing | Messaging is generic; misses the "busy parent" angle |
| Albums (People, Places, Pets) | Storylines (flexible themed collections) | Feature renamed and redesigned |
| Timelines | Storylines | Feature renamed |
| "Intriguing Fyli questions" | Questions with custom sets, recipient tracking, response collection | Undersells a major feature |
| Not mentioned | AI writing assist ("Help me write") | Missing entirely |
| Not mentioned | Share links (one-tap public sharing) | Missing entirely |
| Individual & Family pricing plans | Free tier focus | Pricing section should be removed |
| `app.fyli.com/#/start` links | `app.fyli.com/register` | Old hash-based routing |
| Copyright 2020 | 2026 | Stale |

## Design

### Approach

Content-only refresh within the existing tech stack (Gulp 4, Sass, jQuery, Swiper.js, Typer.js). No build system changes, no framework migration. Update HTML templates, add one new template (feature cards), update styles to support the new section, and remove the subscription include from the page.

### Section Flow (After Refresh)

```
index.html
  ├─ head.html         (+ SEO meta, OG tags)
  ├─ header.html       ("Contact Us" → "Sign In" in mobile menu)
  ├─ top-screen.html   (new headline, single CTA, updated links)
  ├─ about.html        (new value prop copy)
  ├─ features.html     (Capture / Connect / Preserve with current product copy)
  ├─ how-it-works.html (3 updated steps)
  ├─ feature-cards.html (NEW — 6 feature cards in 3×2 grid)
  ├─ engagement.html   (updated heading, relative dates)
  ├─ customers.html    (updated testimonials)
  ├─ [subscription.html removed from includes]
  ├─ security.html     (new copy with descriptions)
  ├─ get-started.html  (updated CTA copy and link)
  └─ footer.html       (copyright 2020 → 2026)
```

### Key Decisions

- **Subscription section**: Remove `@@include` from `index.html`; file stays on disk as dead code. Add `<!-- REMOVED FROM SITE: See docs/tdd/marketing-site-refresh.md -->` comment to top of `subscription.html` so future developers know it's intentionally orphaned.
- **trigger.js**: Remove `//= trigger.js` from `common.js`; file stays on disk. Add `// REMOVED FROM BUILD: See docs/tdd/marketing-site-refresh.md` comment to top of `trigger.js`.
- **subscription.scss**: Keep in Sass imports (dead CSS, negligible size)
- **Feature cards**: New 3×2 grid using existing `.width-box` / `.width-33` utility pattern, card design matches `.security-box` pattern
- **Hero title**: Changes from right-aligned "[word] Stories" to centered "Capture [animated phrase]"
- **All CTAs**: Updated from `app.fyli.com/#/start` to `app.fyli.com/register`
- **Sign In links**: Updated from `app.fyli.com/#/login` to `app.fyli.com/login`
- **Copyright**: 2020 → 2026
- **No build system changes**: Gulp 4, Sass, jQuery, Swiper.js, Typer.js all stay

## Implementation

### Phase 1: Content & Structure Updates (17 file changes)

#### 1.1 Update `src/index.html`

**File:** `fyli-html/src/index.html`

- Remove `@@include('templates/screens/subscription.html')` line
- Add `@@include('templates/screens/feature-cards.html')` after engagement section
- Update title parameter to `"Fyli — Capture your family's stories"`

**Current:**
```html
@@include('templates/layout/head.html',{
"title": "Fyli"
})
...
  @@include('templates/screens/customers.html')
  @@include('templates/screens/subscription.html')
  @@include('templates/screens/security.html')
```

**Updated:**
```html
@@include('templates/layout/head.html',{
"title": "Fyli — Capture your family's stories"
})
...
  @@include('templates/screens/engagement.html')
  @@include('templates/screens/feature-cards.html')
  @@include('templates/screens/customers.html')
  @@include('templates/screens/security.html')
```

#### 1.2 Update `src/templates/layout/head.html`

**File:** `fyli-html/src/templates/layout/head.html`

Add SEO meta description, Open Graph tags, and Twitter card tags after the existing `<meta>` tags.

**Current:**
```html
<head>
    <title>@@title</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <link rel="stylesheet" href="https://unpkg.com/swiper/css/swiper.min.css">
    <link rel="stylesheet" href="/css/styles.min.css">
    <link rel="shortcut icon" type="image/png" href="/images/favicon.ico" />
</head>
```

**Updated:**
```html
<head>
    <title>@@title</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <meta name="description" content="Fyli helps busy families capture, share, and preserve their most meaningful stories — privately and together.">

    <!-- Open Graph -->
    <meta property="og:title" content="Fyli — Capture your family's stories">
    <meta property="og:description" content="The private place for families to capture, share, and preserve their most meaningful stories.">
    <meta property="og:type" content="website">
    <meta property="og:url" content="https://fyli.com">
    <meta property="og:image" content="https://fyli.com/images/og-image.png">

    <!-- Twitter Card -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="Fyli — Capture your family's stories">
    <meta name="twitter:description" content="The private place for families to capture, share, and preserve their most meaningful stories.">
    <meta name="twitter:image" content="https://fyli.com/images/og-image.png">

    <link rel="stylesheet" href="https://unpkg.com/swiper/css/swiper.min.css">
    <link rel="stylesheet" href="/css/styles.min.css">
    <link rel="shortcut icon" type="image/png" href="/images/favicon.ico" />
</head>
```

#### 1.3 Update `src/templates/layout/header.html`

**File:** `fyli-html/src/templates/layout/header.html`

Replace "Contact Us" with "Sign In" in the mobile slide-out menu, update link target.

**Current:**
```html
<div class="second-menu-bottom mb-20">
  <a href="https://app.fyli.com/#/contact" target="_blank">Contact Us</a>
  <a href="https://app.fyli.com/terms" target="_blank">Terms of Service</a>
  <a href="https://app.fyli.com/privacy" target="_blank">Privacy Policy</a>
</div>
```

**Updated:**
```html
<div class="second-menu-bottom mb-20">
  <a href="https://app.fyli.com/login" target="_blank">Sign In</a>
  <a href="https://app.fyli.com/terms" target="_blank">Terms of Service</a>
  <a href="https://app.fyli.com/privacy" target="_blank">Privacy Policy</a>
</div>
```

#### 1.4 Update `src/templates/layout/menu.html`

**File:** `fyli-html/src/templates/layout/menu.html`

Simplify navigation to match updated sections. Remove "About" and "Engagement" (no longer standalone sections), add "Sign In".

**Important:** The "Sign In" link must be placed **outside** the `.menuAnchor` `<ul>`, because `main-menu.js` iterates all `.menuAnchor a` elements on scroll and calls `$(trimSlash(href))` to look up DOM elements by anchor id. An external URL like `https://app.fyli.com/login` would produce an invalid jQuery selector and break the scroll-spy for the entire page.

**Current:**
```html
<ul class="nav-main menuAnchor">
  <li><a href="/#about">About</a></li>
  <li><a href="/#features">Features</a></li>
  <li><a href="/#how-it-works">How it works</a></li>
  <li><a href="/#engagement">Engagement</a></li>
  <li><a href="/#testimonials">Testimonials</a></li>
</ul>
```

**Updated:**
```html
<ul class="nav-main menuAnchor">
  <li><a href="/#features">Features</a></li>
  <li><a href="/#how-it-works">How it works</a></li>
  <li><a href="/#testimonials">Testimonials</a></li>
</ul>
<a href="https://app.fyli.com/login" target="_blank" class="nav-signin">Sign In</a>
```

Note: The `about` section still has `id="about"` in the DOM for direct linking — it's just removed from the nav since it's no longer a distinct marketing section.

#### 1.5 Update `src/templates/layout/footer.html`

**File:** `fyli-html/src/templates/layout/footer.html`

Update copyright year from 2020 to 2026.

**Current:**
```html
<div class="flex-1 pt-10 pb-10">© Fyli  2020. All rights reserved</div>
```

**Updated:**
```html
<div class="flex-1 pt-10 pb-10">© Fyli 2026. All rights reserved</div>
```

#### 1.6 Update `src/templates/screens/top-screen.html`

**File:** `fyli-html/src/templates/screens/top-screen.html`

New headline with animated typing cycling through parent-relevant phrases, single "Get Started Free" CTA, updated links.

**Current:**
```html
<h2 class="dynamic-title">
  <b>
    <span class="typer" id="main" data-words="Share,Discover,Preserve" data-delay="100" data-deleteDelay="1000"></span>
    <span class="cursor" data-owner="main"></span>
  </b>
  <span class="second-word">Stories</span>
</h2>
<div class="text-big text-center moments-text">
  Fyli is the private place for families and dear friends to discover, share and preserve stories and memories
</div>
<div class="d-flex align-center justify-center direction-column-s">
  <a href="https://app.fyli.com/#/login" target="_blank" class="button transparent ml-5 mr-5">
    Sign In
  </a>
  <a href="https://app.fyli.com/#/start" target="_blank" class="button main ml-5 mr-5 mt-10-s">
    Get Started
  </a>
</div>
```

**Updated:**
```html
<h2 class="dynamic-title">
  Capture
  <b>
    <span class="typer" id="main" data-words="first steps,bedtime stories,Sunday mornings,family recipes,grandpa's adventures" data-delay="80" data-deleteDelay="1200"></span>
    <span class="cursor" data-owner="main"></span>
  </b>
</h2>
<div class="text-big text-center moments-text">
  Your family's moments deserve more than a camera roll. Fyli is the private place to capture, share, and preserve the stories that matter — even when life is busy.
</div>
<div class="d-flex align-center justify-center direction-column">
  <a href="https://app.fyli.com/register" target="_blank" class="button main">
    Get Started Free
  </a>
  <a href="https://app.fyli.com/login" target="_blank" class="signin-link mt-10">
    Already have an account? Sign in
  </a>
</div>
```

#### 1.7 Update `src/templates/screens/about.html`

**File:** `fyli-html/src/templates/screens/about.html`

New value proposition copy that leads with the busy-parent problem and positions fyli as the solution.

**Current:**
```html
<h2 class="mb-20 d-none-s">
  Transforming <b>the way</b> we share and remember
</h2>
<div class="text-big mb-20">
  Fyli provides thoughtful, intriguing and fun questions to spark inspiring conversations within your family.  You can select questions to send to family members or document stories no one has written down.
</div>
<div class="text-big">
  <b>
    Save stories, pictures and videos shared with you to timelines and albums.
  </b>
</div>
```

**Updated:**
```html
<h2 class="mb-20 d-none-s">
  Your family's stories <b>deserve to be kept</b>
</h2>
<div class="text-big mb-20">
  You know these moments matter — first words, family traditions, the stories only your parents remember. But life moves fast and capturing them always falls to the bottom of the list.
</div>
<div class="text-big">
  <b>
    Fyli makes it simple. Capture a memory in under 60 seconds, invite your family to share theirs, and know that your stories are private and preserved.
  </b>
</div>
```

Note: The `phone.png` image next to this section is replaced in Phase 3 (section 3.1). Until then, the updated copy will display alongside the old mockup. This is acceptable as an interim state during implementation.

Also update the mobile heading (duplicate `<h2>` block on line 19):

**Current:**
```html
<h2 class="mb-20 d-none d-block-s">
  Transforming <b>the way</b> we share and remember
</h2>
```

**Updated:**
```html
<h2 class="mb-20 d-none d-block-s">
  Your family's stories <b>deserve to be kept</b>
</h2>
```

#### 1.8 Update `src/templates/screens/features.html`

**File:** `fyli-html/src/templates/screens/features.html`

Rewrite three pillars to Capture / Connect / Preserve with current product copy. Keep the alternating image+text layout and research citations. Update all CTA links.

Verify the two research citation links still resolve:
- `https://www.ncbi.nlm.nih.gov/pubmed/25347125`
- `http://shared.web.emory.edu/emory/news/releases/2010/03/children-benefit-if-they-know-about-their-relatives-study-finds.html`

**Full updated HTML:**

```html
<section class="features" id="features">
  <div class="bg-grey pt-big pb-medium pl-10-s pr-10-s">
    <div class="container text-center">
      <h3 class="mb-10">Fyli Features</h3>
      <div class="text features-text">
        Sharing stories about your life and family history can elevate your sense of thriving
        (<a class="link" target="_blank" href="https://www.ncbi.nlm.nih.gov/pubmed/25347125">1</a>,
        <a class="link" target="_blank" href="http://shared.web.emory.edu/emory/news/releases/2010/03/children-benefit-if-they-know-about-their-relatives-study-finds.html">2</a>) and those you share with.
      </div>
    </div>
    <div class="pt-medium d-flex direction-column-s">
      <div class="flex-1 d-flex justify-end order-2-s">
        <div class="container-half pr-medium pt-20-s d-flex direction-column justify-center">
          <h4 class="mb-20 mb-0-s mt-20-s">Capture</h4>
          <ul>
            <li>Create a memory in under 60 seconds — write it, snap a photo, or record a video.</li>
            <li>Add dates as precise or fuzzy as you want — even "sometime in the '90s" works.</li>
            <li>Stuck on how to say it? Smart writing tools help you find the words while keeping your voice.</li>
          </ul>
          <div class="d-flex">
            <a href="https://app.fyli.com/register" target="_blank" class="button main mr-auto-s ml-auto-s">Start Capturing</a>
          </div>
        </div>
      </div>
      <div class="flex-1 pl-10 order-1-s pl-0-s features-img">
        <img src="/images/Img-1.png" />
      </div>
    </div>
  </div>

  <div class="pt-medium pb-medium d-flex direction-column-s pl-10-s pr-10-s">
    <div class="flex-1 pr-10 order-1-s pr-0-s features-img">
      <img src="/images/Img-2.png" style="margin-left: auto;" />
    </div>
    <div class="flex-1 d-flex justify-start order-2-s">
      <div class="container-half pl-medium d-flex direction-column justify-center">
        <h4 class="mb-20 pt-20-s mb-0-s mt-20-s">Connect</h4>
        <ul>
          <li>Send questions to parents, grandparents, siblings — get the stories only your family knows.</li>
          <li>Share any memory with a single link — recipients don't need an account.</li>
          <li>Comments and reactions keep the conversation going across generations.</li>
        </ul>
        <div class="d-flex">
          <a href="https://app.fyli.com/register" target="_blank" class="button main mr-auto-s ml-auto-s">Connect Your Family</a>
        </div>
      </div>
    </div>
  </div>

  <div class="bg-grey pt-medium pb-medium d-flex direction-column-s pl-10-s pr-10-s">
    <div class="flex-1 d-flex justify-end order-2-s">
      <div class="container-half pr-medium d-flex direction-column justify-center">
        <h4 class="mb-20 pt-20-s mb-0-s mt-20-s">Preserve</h4>
        <ul>
          <li>Group memories into Storylines — "Dad's childhood", "Our first year", "Family recipes".</li>
          <li>Invite family members to contribute to shared Storylines.</li>
          <li>Your family's story, organized the way you want — and kept safe for the next generation.</li>
        </ul>
        <div class="d-flex">
          <a href="https://app.fyli.com/register" target="_blank" class="button main mr-auto-s ml-auto-s">Preserve Your Stories</a>
        </div>
      </div>
    </div>
    <div class="flex-1 pl-10 order-1-s pl-0-s features-img">
      <img src="/images/Img-3.png" />
    </div>
  </div>
</section>
```

#### 1.9 Update `src/templates/screens/how-it-works.html`

**File:** `fyli-html/src/templates/screens/how-it-works.html`

Update 3-step flow to reflect actual onboarding. Keep the existing step icon images (`step1.svg`, `step2.svg`, `step3.svg`).

**Current steps:**
1. "Add Memories" — prompting you with intriguing questions
2. "Connect" — invite family by sharing memories or asking questions
3. "Enjoy" — comment, create albums or timelines

**Updated steps:**
1. **"Sign up in seconds"** — "Create a free account with email or Google. No credit card needed."
2. **"Capture your first memory"** — "Write it, snap a photo, or just jot a few words — we'll help you tell the story."
3. **"Invite your family"** — "Share a memory or send a question to get the stories flowing."

Update subtitle from "3 simple steps to stronger, deeper connections" to "3 simple steps to start preserving your family's stories".

Update CTA link from `app.fyli.com/#/start` to `app.fyli.com/register`.

#### 1.10 Update `src/templates/screens/engagement.html`

**File:** `fyli-html/src/templates/screens/engagement.html`

- Update section heading from "Connect" to "See your family's stories come alive"
- Replace hardcoded 2020 dates with relative timeframes (oldest message first, matching conversation flow):
  - "Wed Apr 15 2020" → "6 days ago"
  - "Wed Apr 17 2020" → "4 days ago"
  - "Fr Apr 17 2020" → "4 days ago"
  - "Wed Apr 19 2020" → "2 days ago"
  - "Wed Apr 19 2020" → "2 days ago"

#### 1.11 Update `src/templates/screens/customers.html`

**File:** `fyli-html/src/templates/screens/customers.html`

Update testimonials to reference current product features (Questions and writing assist). Update the section heading. Keep the Swiper carousel format.

**Current heading:** "Fyli members feel connected and are having fun."
**Updated heading:** "Families are capturing stories they almost lost."

**Updated testimonials (replace both slides):**

**Slide 1:**
> "I sent my dad a question about his childhood and he wrote back three memories I'd never heard before. Now my kids know stories about their grandpa that would have been lost. Fyli makes it so easy — I didn't even have to nag him!"
> — *Beth O.*

**Slide 2:**
> "I'm terrible at journaling but Fyli's writing help makes it simple. I jot down a few words about a moment with my kids and it helps me turn it into something worth keeping. Our family Storyline is already something I treasure."
> — *Marco W.*

#### 1.12 Update `src/templates/screens/security.html`

**File:** `fyli-html/src/templates/screens/security.html`

Add descriptive text below each heading. Update headings to be more specific.

**Current cards (heading only):**
1. "We respect your privacy"
2. "We won't sell your data"
3. "We won't show you advertisements"

**Updated cards (heading + description):**
1. **"Private by default"** — "Your memories are yours. You control exactly who sees what — share with everyone, specific people, or keep it just for you."
2. **"Your data stays yours"** — "We will never sell your data or use your family's stories for advertising. Your memories belong to you."
3. **"Not social media"** — "No followers, no feeds, no algorithms. Fyli is your family's private space — not a platform for the world."

Keep the existing `.security-box` card layout and `check-round.svg` icon. Add a `<p>` tag below each `<h5>` for the description text.

#### 1.13 Update `src/templates/screens/get-started.html`

**File:** `fyli-html/src/templates/screens/get-started.html`

Update closing CTA copy and link.

**Current:**
```html
<div class="get-started-text flex-2">Join Fyli today to start preserving your memories and passing them on to the next generation.</div>
...
<a href="https://app.fyli.com/#/start?b=1" target="_blank" class="button main mr-auto-s ml-auto-s d-flex align-center">
  Get Started
  <img class="ml-10" src="/images/arrow2.svg" />
</a>
```

**Updated:**
```html
<div class="get-started-text flex-2">Your family's stories are worth keeping. Start preserving them today.</div>
...
<a href="https://app.fyli.com/register" target="_blank" class="button main mr-auto-s ml-auto-s d-flex align-center">
  Get Started Free
  <img class="ml-10" src="/images/arrow2.svg" />
</a>
```

#### 1.14 Create `src/templates/screens/feature-cards.html`

**File:** `fyli-html/src/templates/screens/feature-cards.html` (NEW)

6 feature cards in a 3×2 grid. Uses existing `.width-box` / `.width-33` utilities from the security section pattern. Each card has an SVG icon, heading, and description.

```html
<section class="bg-grey feature-cards" id="feature-cards">
  <div class="container text-center">
    <h3 class="mb-10">Everything your family needs</h3>
    <div class="text">Simple tools to capture, share, and preserve what matters most.</div>
    <div class="d-flex width-box direction-column-s">
      <div class="width-33">
        <div class="feature-card">
          <img src="/images/icon-memories.svg" alt="Memories" />
          <h5>Memories</h5>
          <p>Write, photograph, or video meaningful moments. Add dates as precise or fuzzy as you want.</p>
        </div>
      </div>
      <div class="width-33">
        <div class="feature-card">
          <img src="/images/icon-questions.svg" alt="Questions" />
          <h5>Questions</h5>
          <p>Prompt family members to share their stories. Track who's responded and send gentle reminders.</p>
        </div>
      </div>
      <div class="width-33">
        <div class="feature-card">
          <img src="/images/icon-storylines.svg" alt="Storylines" />
          <h5>Storylines</h5>
          <p>Curate themed collections. Invite others to contribute. Build your family's narrative together.</p>
        </div>
      </div>
      <div class="width-33">
        <div class="feature-card">
          <img src="/images/icon-share-links.svg" alt="Share Links" />
          <h5>Share Links</h5>
          <p>Share any memory with a single link. Recipients don't need an account.</p>
        </div>
      </div>
      <div class="width-33">
        <div class="feature-card">
          <img src="/images/icon-writing.svg" alt="Smart Writing" />
          <h5>Smart Writing</h5>
          <p>Stuck on how to say it? We help you find the words while keeping your voice.</p>
        </div>
      </div>
      <div class="width-33">
        <div class="feature-card">
          <img src="/images/icon-private.svg" alt="Private by Design" />
          <h5>Private by Design</h5>
          <p>Fyli isn't social media — it's your family's private space.</p>
        </div>
      </div>
    </div>
  </div>
</section>
```

#### 1.15 Update `src/js/common.js`

**File:** `fyli-html/src/js/common.js`

Remove `//= trigger.js` include (subscription toggle no longer needed since pricing section is removed).

**Current:**
```js
$(document).ready(function(){
  //= slider.js
  //= main-menu.js
  //= scroll.js
  //= trigger.js
});
```

**Updated:**
```js
$(document).ready(function(){
  //= slider.js
  //= main-menu.js
  //= scroll.js
});
```

### Phase 2: Style Updates (5 files)

#### 2.1 Create `src/sass/4pages/feature-cards.scss`

**File:** `fyli-html/src/sass/4pages/feature-cards.scss` (NEW)

3-column card grid for the 6 feature cards. Follows the existing `.security-box` and `.width-box` / `.width-33` patterns.

```scss
.feature-cards {
  padding-top: 80px;
  padding-bottom: 80px;

  .width-box {
    flex-wrap: wrap;
  }
}

.feature-card {
  background-color: $white;
  padding: 30px 25px;
  border-radius: 8px;
  text-align: center;
  margin-top: 30px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);

  img {
    margin-left: auto;
    margin-right: auto;
    margin-bottom: 15px;
    height: 48px;
  }

  h5 {
    margin-bottom: 10px;
  }

  p {
    color: $blue-light;
    font-size: 15px;
    line-height: 1.6;
    margin-bottom: 0;
  }

  @include tablet-max {
    margin-top: 15px;
    margin-left: 20px;
    margin-right: 20px;
  }
}
```

#### 2.2 Update `src/sass/4pages/top-screen.scss`

**File:** `fyli-html/src/sass/4pages/top-screen.scss`

Update `.dynamic-title` to center-align and widen `max-width` for the new "Capture [phrase]" headline. Add `.signin-link` style for the subtle sign-in text link.

**Current:**
```scss
.dynamic-title {
  max-width: 535px;
  margin-left: auto;
  margin-right: auto;
  text-align: right;
  height: 68px;
  ...
}
```

**Updated:**
```scss
.dynamic-title {
  max-width: 700px;
  margin-left: auto;
  margin-right: auto;
  text-align: center;
  height: 68px;
  ...
}

.signin-link {
  color: $blue-light;
  font-size: 14px;
  text-decoration: underline;

  &:hover {
    color: $base;
  }
}
```

#### 2.3 Update `src/sass/4pages/security.scss`

**File:** `fyli-html/src/sass/4pages/security.scss`

Add `<p>` styling inside `.security-box` for the new description text added in section 1.12.

**Add to existing `.security-box` block:**
```scss
.security-box {
  // ... existing styles ...

  p {
    color: $blue-light;
    font-size: 14px;
    line-height: 1.5;
    margin-top: 10px;
    margin-bottom: 0;
  }
}
```

#### 2.4 Add `.nav-signin` style to `src/sass/3elements/_menu.scss`

**File:** `fyli-html/src/sass/3elements/_menu.scss`

Add styling for the Sign In link that sits outside the `.menuAnchor` list (see section 1.4).

```scss
.nav-signin {
  color: $base;
  font-size: 14px;
  text-decoration: none;
  margin-left: 20px;

  &:hover {
    color: $green-title;
  }
}
```

#### 2.5 Update `src/sass/4pages/index.scss`

**File:** `fyli-html/src/sass/4pages/index.scss`

Add the new feature-cards import.

**Current:**
```scss
@import "layout/index";
@import "moments.scss";
@import "features.scss";
...
```

**Updated:**
```scss
@import "layout/index";
@import "moments.scss";
@import "features.scss";
@import "feature-cards.scss";
...
```

### Phase 3: Visual Assets & Polish

#### 3.1 Replace Product Screenshots

Replace outdated product screenshots with current fyli-fe-v2 UI captures:

| Image | Current | Replacement |
|-------|---------|-------------|
| `src/images/phone.png` | Old app mockup in about section | Current memory stream or memory creation UI |
| `src/images/Img-1.png` | Discover feature screenshot | Capture feature — memory creation with date picker |
| `src/images/Img-2.png` | Share feature screenshot | Connect feature — Questions list or share link UI |
| `src/images/Img-3.png` | Preserve feature screenshot | Preserve feature — Storyline view |

Screenshots should be taken from fyli-fe-v2 running locally and cropped/framed to match the existing image dimensions.

#### 3.2 Create Visual Assets

| Asset | Purpose | Spec |
|-------|---------|------|
| `src/images/og-image.png` | Open Graph social sharing image | 1200×630px, fyli logo + tagline on brand green background |
| `src/images/icon-memories.svg` | Feature card icon | 48×48px, line-style, brand green accent |
| `src/images/icon-questions.svg` | Feature card icon | 48×48px, line-style, brand green accent |
| `src/images/icon-storylines.svg` | Feature card icon | 48×48px, line-style, brand green accent |
| `src/images/icon-share-links.svg` | Feature card icon | 48×48px, line-style, brand green accent |
| `src/images/icon-writing.svg` | Feature card icon | 48×48px, line-style, brand green accent |
| `src/images/icon-private.svg` | Feature card icon | 48×48px, line-style, brand green accent |

Note: SVG icons can use Material Design Icons as a reference or be created as simple line illustrations matching the existing `step1.svg` / `step2.svg` / `step3.svg` style.

#### 3.3 Link Verification & Testing

Verify all links resolve correctly:
- [ ] `https://app.fyli.com/register` — signup page loads
- [ ] `https://app.fyli.com/login` — login page loads
- [ ] `https://app.fyli.com/terms` — terms page loads
- [ ] `https://app.fyli.com/privacy` — privacy page loads
- [ ] `https://www.ncbi.nlm.nih.gov/pubmed/25347125` — research citation loads
- [ ] `http://shared.web.emory.edu/emory/news/releases/2010/03/children-benefit-if-they-know-about-their-relatives-study-finds.html` — research citation loads

Cross-browser testing:
- [ ] Chrome (latest)
- [ ] Safari (latest)
- [ ] Firefox (latest)
- [ ] Mobile Safari (iOS)
- [ ] Chrome Mobile (Android)

Build verification:
- [ ] `gulp build` completes without errors
- [ ] All sections render correctly at desktop (1200px+)
- [ ] All sections render correctly at tablet (768px)
- [ ] All sections render correctly at mobile (480px)
- [ ] Typer.js animation cycles through new phrases
- [ ] Swiper testimonial carousel still works
- [ ] Smooth scroll navigation works for updated menu items
- [ ] Mobile hamburger menu opens/closes correctly

## File Changes Summary

| Action | File | Change |
|--------|------|--------|
| Modify | `fyli-html/src/index.html` | Remove subscription include, add feature-cards include, update title |
| Modify | `fyli-html/src/templates/layout/head.html` | Add SEO meta, OG tags, Twitter card |
| Modify | `fyli-html/src/templates/layout/header.html` | Replace "Contact Us" with "Sign In" in mobile menu |
| Modify | `fyli-html/src/templates/layout/menu.html` | Simplify nav, add Sign In outside `.menuAnchor` |
| Modify | `fyli-html/src/templates/layout/footer.html` | Copyright 2020 → 2026 |
| Modify | `fyli-html/src/templates/screens/top-screen.html` | New headline, single CTA, updated links |
| Modify | `fyli-html/src/templates/screens/about.html` | New value prop copy |
| Modify | `fyli-html/src/templates/screens/features.html` | Capture / Connect / Preserve with current product copy |
| Modify | `fyli-html/src/templates/screens/how-it-works.html` | Updated 3 steps and CTA link |
| Modify | `fyli-html/src/templates/screens/engagement.html` | Updated heading, relative dates |
| Modify | `fyli-html/src/templates/screens/customers.html` | Updated testimonials and heading |
| Modify | `fyli-html/src/templates/screens/security.html` | New headings with descriptions |
| Modify | `fyli-html/src/templates/screens/get-started.html` | Updated CTA copy and link |
| Create | `fyli-html/src/templates/screens/feature-cards.html` | 6 feature cards template |
| Modify | `fyli-html/src/js/common.js` | Remove `//= trigger.js` include |
| Modify | `fyli-html/src/templates/screens/subscription.html` | Add dead-code comment |
| Modify | `fyli-html/src/js/trigger.js` | Add dead-code comment |
| Create | `fyli-html/src/sass/4pages/feature-cards.scss` | Feature card grid styles (incl. `flex-wrap`) |
| Modify | `fyli-html/src/sass/4pages/top-screen.scss` | Center-align hero, add signin-link |
| Modify | `fyli-html/src/sass/4pages/security.scss` | Add `.security-box p` description styling |
| Modify | `fyli-html/src/sass/3elements/_menu.scss` | Add `.nav-signin` styling |
| Modify | `fyli-html/src/sass/4pages/index.scss` | Add feature-cards import |
| Create | `fyli-html/src/images/og-image.png` | OG social sharing image |
| Create | `fyli-html/src/images/icon-memories.svg` | Feature card icon |
| Create | `fyli-html/src/images/icon-questions.svg` | Feature card icon |
| Create | `fyli-html/src/images/icon-storylines.svg` | Feature card icon |
| Create | `fyli-html/src/images/icon-share-links.svg` | Feature card icon |
| Create | `fyli-html/src/images/icon-writing.svg` | Feature card icon |
| Create | `fyli-html/src/images/icon-private.svg` | Feature card icon |
| Replace | `fyli-html/src/images/phone.png` | Updated product screenshot |
| Replace | `fyli-html/src/images/Img-1.png` | Updated feature screenshot |
| Replace | `fyli-html/src/images/Img-2.png` | Updated feature screenshot |
| Replace | `fyli-html/src/images/Img-3.png` | Updated feature screenshot |

## Implementation Order

1. **Phase 1** — Content & structure: all 17 HTML/JS file changes (includes feature-cards.html template + dead-code comments)
2. **Phase 2** — Styles: feature-cards.scss, top-screen.scss, security.scss, _menu.scss, index.scss
3. **Phase 3** — Visual assets: screenshots, SVG icons, OG image, link verification, testing
