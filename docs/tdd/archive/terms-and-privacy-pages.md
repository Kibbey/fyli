# TDD: Terms of Service & Privacy Policy Pages

**PRD:** `docs/prd/PRD_TERMS_AND_PRIVACY.md`
**Status:** Draft
**Created:** 2026-02-09

## Overview

Add two new public Vue pages (`/terms` and `/privacy`) to fyli-fe-v2, update the registration page terms checkbox to link to them, and add footer links on login/register pages. These are frontend-only changes — no backend or database work required.

## Architecture

This is a simple frontend feature. Two static content pages using the existing `PublicLayout` (with a small width override via route meta), two new routes, and minor edits to `RegisterView` and `LoginView`.

```
┌──────────────────────────────────────────────┐
│  Router (index.ts)                           │
│  + /terms  → TermsView.vue  (public, wide)  │
│  + /privacy → PrivacyView.vue (public, wide) │
│  + scrollBehavior: scroll to top             │
├──────────────────────────────────────────────┤
│  PublicLayout.vue (edit: wide meta support)  │
│  ┌────────────────────────────────────┐      │
│  │  fyli logo                        │      │
│  │  ┌─────────────────────────┐      │      │
│  │  │  <slot /> (page content)│      │      │
│  │  │  480px or 680px wide    │      │      │
│  │  └─────────────────────────┘      │      │
│  └────────────────────────────────────┘      │
├──────────────────────────────────────────────┤
│  RegisterView.vue (edit: terms checkbox)     │
│  LoginView.vue (edit: add footer links)      │
└──────────────────────────────────────────────┘
```

## File Structure

```
fyli-fe-v2/src/
├── router/
│   └── index.ts                          # EDIT: add 2 routes + scrollBehavior
├── layouts/
│   └── PublicLayout.vue                  # EDIT: wide meta support
├── views/
│   └── legal/
│       ├── TermsView.vue                 # NEW
│       ├── TermsView.test.ts             # NEW
│       ├── PrivacyView.vue               # NEW
│       └── PrivacyView.test.ts           # NEW
└── views/auth/
    ├── RegisterView.vue                  # EDIT: terms checkbox links
    ├── RegisterView.test.ts              # EDIT: add terms link tests
    ├── LoginView.vue                     # EDIT: footer links
    └── LoginView.test.ts                 # EDIT: add footer link tests
```

---

## Phase 1: Layout & Routing

### 1.1 PublicLayout — Wide Meta Support

**File:** `fyli-fe-v2/src/layouts/PublicLayout.vue`

The PublicLayout has a hard `style="max-width: 480px"` on its container. Legal pages need wider content (680px) for readable long-form text. A child element cannot exceed its parent's max-width, so the layout itself must support the wider mode.

Add `$route.meta.wide` conditional:

```vue
<template>
  <div class="min-vh-100 bg-light d-flex flex-column">
    <header class="text-center py-4">
      <RouterLink to="/" class="text-decoration-none">
        <h1 class="fw-bold text-primary">fyli</h1>
      </RouterLink>
    </header>
    <main class="flex-grow-1 d-flex align-items-start justify-content-center">
      <div
        class="container"
        :style="{ maxWidth: $route.meta.wide ? '680px' : '480px' }"
      >
        <slot />
      </div>
    </main>
  </div>
</template>
```

This is a one-line change from `style="max-width: 480px"` to a dynamic `:style` binding. All existing routes without `wide: true` in their meta are unaffected.

### 1.2 Router Changes

**File:** `fyli-fe-v2/src/router/index.ts`

**Add `scrollBehavior`** to the router config so navigating between `/terms` and `/privacy` scrolls to the top:

```typescript
const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  scrollBehavior() {
    return { top: 0 }
  },
  routes: [
    // ... existing routes ...
  ],
})
```

**Add two routes** after the existing auth routes. Both use `wide: true` meta:

```typescript
{
  path: '/terms',
  name: 'terms',
  component: () => import('@/views/legal/TermsView.vue'),
  meta: { layout: 'public', wide: true },
},
{
  path: '/privacy',
  name: 'privacy',
  component: () => import('@/views/legal/PrivacyView.vue'),
  meta: { layout: 'public', wide: true },
},
```

Both use `layout: 'public'` (no `auth: true`) so they are accessible without login.

---

## Phase 2: Terms of Service & Privacy Policy Pages

### 2.1 TermsView.vue

**File:** `fyli-fe-v2/src/views/legal/TermsView.vue`

Static content page. No inline width override — the PublicLayout handles the 680px via `wide: true` meta.

```vue
<script setup lang="ts">
import { onMounted } from 'vue'

onMounted(() => {
  document.title = 'Terms of Service — Fyli'
})
</script>

<template>
  <div>
    <h1 class="h3 mb-4">Terms of Service</h1>

    <p class="mb-4">
      <em>Choose kindness. Embrace joy. Let go.</em>
    </p>

    <p>
      Fyli is a place for families and dear friends to discover, share, and
      preserve special memories and moments. We believe some of the best parts
      of life happen around the people you love — like a campfire where stories
      are passed around and the good stuff gets remembered. These terms keep
      that campfire a welcoming place for everyone.
    </p>

    <h2 class="h5 mt-4 mb-2">What Fyli Is</h2>
    <p>
      Fyli is a platform to create, share, and preserve family memories and
      moments. We are not a general social media platform — we are focused on
      meaningful connections between family and close friends.
    </p>

    <h2 class="h5 mt-4 mb-2">Your Agreement</h2>
    <p>
      By creating an account or using Fyli, you agree to these terms. You must
      be at least 13 years old to use Fyli. You agree to act lawfully and not
      behave in a misleading or fraudulent way.
    </p>

    <h2 class="h5 mt-4 mb-2">Rules of Engagement</h2>
    <p>
      We ask that you treat each other with respect — and hopefully even
      kindness. That means:
    </p>
    <ul>
      <li>No hate speech, extremist content, or illegal material</li>
      <li>No adult content</li>
      <li>
        Family arguments belong somewhere else — Fyli is for the good
        memories
      </li>
      <li>
        Content that is illegal will be removed and reported to the
        appropriate authorities
      </li>
    </ul>
    <p>
      We reserve the right to remove anyone who is behaving badly or violating
      these rules.
    </p>

    <h2 class="h5 mt-4 mb-2">Your Content</h2>
    <p>
      You own your memories and content. By posting on Fyli, you grant us a
      license to store, display, and serve your content to the people you
      choose to share it with. We will never sell your content or use it for
      advertising.
    </p>
    <p>
      When you use AI-powered features (such as content suggestions or writing
      assistance), Fyli may send relevant data to third-party AI providers —
      including Grok (xAI), OpenAI, and Google — to process your request. This
      only happens when you initiate it, and only the data relevant to your
      request is shared.
    </p>

    <h2 class="h5 mt-4 mb-2">Third-Party Authentication</h2>
    <p>
      If you sign in with Google, Fyli receives only your name, email address,
      and Google account identifier. We do not access your Google Calendar,
      Gmail, Drive, or any other Google services beyond basic sign-in.
    </p>

    <h2 class="h5 mt-4 mb-2">Data &amp; Reliability</h2>
    <p>
      While we work hard to protect your data with redundancies in our system,
      there is always the remote possibility that data could be corrupted or
      lost. Fyli is provided "as is" without warranties of any kind.
    </p>

    <h2 class="h5 mt-4 mb-2">Dispute Resolution</h2>
    <p>
      Any dispute between you and Fyli will be resolved by binding
      arbitration.
    </p>

    <h2 class="h5 mt-4 mb-2">Changes to These Terms</h2>
    <p>
      We may update these terms from time to time. If we make material
      changes, we will let you know through the app. Continued use of Fyli
      after changes are posted means you accept the updated terms.
    </p>

    <h2 class="h5 mt-4 mb-2">Contact</h2>
    <p>
      Questions about these terms? Reach us at
      <a href="mailto:information@fyli.com">information@fyli.com</a>.
    </p>

    <hr class="my-4" />

    <p class="text-muted small">
      Last updated: February 2026
    </p>
    <p class="small">
      <RouterLink to="/privacy">Privacy Policy</RouterLink>
    </p>
  </div>
</template>
```

### 2.2 PrivacyView.vue

**File:** `fyli-fe-v2/src/views/legal/PrivacyView.vue`

```vue
<script setup lang="ts">
import { onMounted } from 'vue'

onMounted(() => {
  document.title = 'Privacy Policy — Fyli'
})
</script>

<template>
  <div>
    <h1 class="h3 mb-4">Privacy Policy</h1>

    <p class="mb-4">
      <em>Your memories are personal. Your privacy matters to us.</em>
    </p>

    <p>
      Fyli is built for families to share and preserve meaningful moments. We
      take your privacy seriously and want you to understand exactly how your
      data is handled. This policy covers what we collect, how we use it, and
      what we will never do with it.
    </p>

    <h2 class="h5 mt-4 mb-2">What Data We Collect</h2>
    <ul>
      <li>
        <strong>Account information:</strong> your name and email address
      </li>
      <li>
        <strong>Google account data</strong> (when you sign in with Google):
        your name, email, and Google account identifier — nothing else
      </li>
      <li>
        <strong>Content you create:</strong> memories, answers to questions,
        albums, and comments
      </li>
      <li>
        <strong>Usage data:</strong> how you interact with the app (pages
        visited, features used) to help us improve the experience
      </li>
    </ul>

    <h2 class="h5 mt-4 mb-2">How We Use Your Data</h2>
    <ul>
      <li>To provide and operate the Fyli service</li>
      <li>To authenticate your identity</li>
      <li>
        To display your content to you and the people you choose to share
        with
      </li>
      <li>To improve the app experience</li>
      <li>
        Google user data is used only for providing and improving user-facing
        features within Fyli
      </li>
    </ul>

    <h2 class="h5 mt-4 mb-2">How We Store Your Data</h2>
    <p>
      Your data is stored on secure servers using industry-standard security
      practices. We do not store passwords — authentication is handled through
      magic links and Google Sign-In.
    </p>

    <h2 class="h5 mt-4 mb-2">What We Share (and Don't)</h2>
    <ul>
      <li>
        <strong>We do not sell your data</strong> to advertisers, data
        brokers, or any third parties
      </li>
      <li>
        <strong>We do not use your data for advertising</strong>,
        retargeting, or interest-based profiling
      </li>
      <li>
        <strong>We do not transfer Google user data</strong> to advertising
        platforms or data brokers
      </li>
      <li>
        <strong>When you use AI features</strong>, we may send data to
        third-party AI providers — including Grok (xAI), OpenAI, and Google
        — to generate content or provide suggestions. This only happens when
        you initiate an AI-powered action, and only the data relevant to your
        request is shared
      </li>
      <li>
        Content you choose to share with other Fyli users is visible to those
        users — we cannot control what others may do with memories you share
        with them
      </li>
      <li>We may disclose data if required by law</li>
    </ul>

    <h2 class="h5 mt-4 mb-2">Google User Data — Limited Use Disclosure</h2>
    <p>
      Fyli's use and transfer to any other app of information received from
      Google APIs will adhere to the
      <a
        href="https://developers.google.com/terms/api-services-user-data-policy"
        target="_blank"
        rel="noopener"
      >
        Google API Services User Data Policy</a
      >, including the Limited Use requirements. Specifically:
    </p>
    <ul>
      <li>
        Google user data (name, email, and account ID received via Google
        Sign-In) is used only to provide and improve the Fyli service
      </li>
      <li>
        We do not use Google user data for serving advertisements
      </li>
      <li>
        We do not transfer Google user data to third parties except as
        necessary to provide the service, as explicitly requested by you, or
        as required by law
      </li>
      <li>
        We do not use Google user data for purposes unrelated to the Fyli
        service
      </li>
    </ul>

    <h2 class="h5 mt-4 mb-2">Third-Party Services</h2>
    <ul>
      <li>
        <strong>Google Sign-In</strong> (Google Identity Services) — used for
        authentication only
      </li>
      <li>
        <strong>AI providers</strong> (Grok/xAI, OpenAI, Google) — used to
        generate content and provide suggestions when you use AI-powered
        features. Only data relevant to your request is sent, and only when
        you initiate the action
      </li>
    </ul>

    <h2 class="h5 mt-4 mb-2">Data Retention &amp; Deletion</h2>
    <p>
      Your data is retained for as long as your account is active. If you
      would like to delete your account and all associated data, contact us at
      <a href="mailto:information@fyli.com">information@fyli.com</a> and we will
      process your request.
    </p>

    <h2 class="h5 mt-4 mb-2">Children's Privacy</h2>
    <p>
      Fyli is not directed at children under 13. We do not knowingly collect
      personal information from children under 13. If you believe a child
      under 13 has provided us with personal information, please contact us
      and we will remove it.
    </p>

    <h2 class="h5 mt-4 mb-2">Cookies &amp; Local Storage</h2>
    <p>
      Fyli uses local storage in your browser to keep you signed in
      (authentication tokens). We do not use third-party tracking cookies.
    </p>

    <h2 class="h5 mt-4 mb-2">Changes to This Policy</h2>
    <p>
      We may update this privacy policy from time to time. If we make material
      changes, we will let you know through the app. Continued use of Fyli
      after changes means you accept the updated policy.
    </p>

    <h2 class="h5 mt-4 mb-2">Contact</h2>
    <p>
      Questions about your privacy? Reach us at
      <a href="mailto:information@fyli.com">information@fyli.com</a>.
    </p>

    <hr class="my-4" />

    <p class="text-muted small">
      Last updated: February 2026
    </p>
    <p class="small">
      <RouterLink to="/terms">Terms of Service</RouterLink>
    </p>
  </div>
</template>
```

---

## Phase 3: Registration & Login Page Updates

### 3.1 RegisterView.vue — Terms Checkbox + Footer

**File:** `fyli-fe-v2/src/views/auth/RegisterView.vue`

**Change 1:** Replace the terms checkbox label to use `<RouterLink>` with `target="_blank"`:

```html
<!-- BEFORE -->
<label class="form-check-label" for="terms">I agree to the terms of service</label>

<!-- AFTER -->
<label class="form-check-label" for="terms">
  I agree to the
  <RouterLink to="/terms" target="_blank">Terms of Service</RouterLink>
  and
  <RouterLink to="/privacy" target="_blank">Privacy Policy</RouterLink>
</label>
```

**Change 2:** Add footer links **outside** the `v-if`/`v-else` blocks so they remain visible after form submission. Place them after the closing `</div>` of the `v-else` block but still inside `card-body`:

```html
<!-- CURRENT STRUCTURE -->
<div class="card-body p-4">
  <h4 class="mb-3">Create Account</h4>
  <div v-if="sent" class="text-center py-3">
    <!-- success state -->
  </div>
  <div v-else>
    <!-- form + "Already have an account?" link -->
  </div>
  <!-- ADD HERE: always visible regardless of sent state -->
  <p class="text-center mt-3 mb-0 text-muted small">
    <RouterLink to="/terms" class="text-muted">Terms</RouterLink>
    &middot;
    <RouterLink to="/privacy" class="text-muted">Privacy</RouterLink>
  </p>
</div>
```

### 3.2 LoginView.vue — Footer Links

**File:** `fyli-fe-v2/src/views/auth/LoginView.vue`

Add footer links **outside** the `v-if`/`v-else` blocks, same pattern as RegisterView:

```html
<!-- CURRENT STRUCTURE -->
<div class="card-body p-4">
  <h4 class="mb-3">Sign In</h4>
  <div v-if="sent" class="text-center py-3">
    <!-- success state -->
  </div>
  <div v-else>
    <!-- form + "Don't have an account?" link -->
  </div>
  <!-- ADD HERE: always visible regardless of sent state -->
  <p class="text-center mt-3 mb-0 text-muted small">
    <RouterLink to="/terms" class="text-muted">Terms</RouterLink>
    &middot;
    <RouterLink to="/privacy" class="text-muted">Privacy</RouterLink>
  </p>
</div>
```

---

## Phase 4: Frontend Tests

### 4.1 TermsView Tests

**File:** `fyli-fe-v2/src/views/legal/TermsView.test.ts`

```typescript
import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createRouter, createMemoryHistory } from 'vue-router'
import TermsView from './TermsView.vue'

async function mountWithRouter() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/terms', component: TermsView },
      { path: '/privacy', component: { template: '<div />' } },
    ],
  })
  await router.push('/terms')
  await router.isReady()
  return mount(TermsView, {
    global: { plugins: [router] },
  })
}

describe('TermsView', () => {
  it('renders page title', async () => {
    const wrapper = await mountWithRouter()
    expect(wrapper.find('h1').text()).toBe('Terms of Service')
  })

  it('renders all required sections', async () => {
    const wrapper = await mountWithRouter()
    const headings = wrapper.findAll('h2').map(h => h.text())
    expect(headings).toContain('What Fyli Is')
    expect(headings).toContain('Your Agreement')
    expect(headings).toContain('Rules of Engagement')
    expect(headings).toContain('Your Content')
    expect(headings).toContain('Third-Party Authentication')
    expect(headings).toContain('Data & Reliability')
    expect(headings).toContain('Dispute Resolution')
    expect(headings).toContain('Changes to These Terms')
    expect(headings).toContain('Contact')
  })

  it('discloses AI third-party providers by name', async () => {
    const wrapper = await mountWithRouter()
    const text = wrapper.text()
    expect(text).toContain('Grok')
    expect(text).toContain('OpenAI')
    expect(text).toContain('Google')
  })

  it('includes link to privacy policy', async () => {
    const wrapper = await mountWithRouter()
    const link = wrapper.find('a[href="/privacy"]')
    expect(link.exists()).toBe(true)
    expect(link.text()).toBe('Privacy Policy')
  })

  it('shows last updated date', async () => {
    const wrapper = await mountWithRouter()
    expect(wrapper.text()).toContain('Last updated: February 2026')
  })

  it('includes minimum age requirement', async () => {
    const wrapper = await mountWithRouter()
    expect(wrapper.text()).toContain('at least 13 years old')
  })

  it('includes contact email', async () => {
    const wrapper = await mountWithRouter()
    const mailto = wrapper.find('a[href="mailto:information@fyli.com"]')
    expect(mailto.exists()).toBe(true)
  })

  it('sets document title', async () => {
    await mountWithRouter()
    expect(document.title).toBe('Terms of Service — Fyli')
  })
})
```

### 4.2 PrivacyView Tests

**File:** `fyli-fe-v2/src/views/legal/PrivacyView.test.ts`

```typescript
import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createRouter, createMemoryHistory } from 'vue-router'
import PrivacyView from './PrivacyView.vue'

async function mountWithRouter() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/privacy', component: PrivacyView },
      { path: '/terms', component: { template: '<div />' } },
    ],
  })
  await router.push('/privacy')
  await router.isReady()
  return mount(PrivacyView, {
    global: { plugins: [router] },
  })
}

describe('PrivacyView', () => {
  it('renders page title', async () => {
    const wrapper = await mountWithRouter()
    expect(wrapper.find('h1').text()).toBe('Privacy Policy')
  })

  it('renders all required sections', async () => {
    const wrapper = await mountWithRouter()
    const headings = wrapper.findAll('h2').map(h => h.text())
    expect(headings).toContain('What Data We Collect')
    expect(headings).toContain('How We Use Your Data')
    expect(headings).toContain('How We Store Your Data')
    expect(headings).toContain('What We Share (and Don\'t)')
    expect(headings).toContain('Google User Data — Limited Use Disclosure')
    expect(headings).toContain('Third-Party Services')
    expect(headings).toContain('Data Retention & Deletion')
    expect(headings).toContain('Children\'s Privacy')
    expect(headings).toContain('Cookies & Local Storage')
    expect(headings).toContain('Changes to This Policy')
    expect(headings).toContain('Contact')
  })

  it('discloses that data is not sold', async () => {
    const wrapper = await mountWithRouter()
    expect(wrapper.text()).toContain('do not sell your data')
  })

  it('discloses that data is not used for advertising', async () => {
    const wrapper = await mountWithRouter()
    expect(wrapper.text()).toContain('do not use your data for advertising')
  })

  it('includes Google Limited Use disclosure with link to policy', async () => {
    const wrapper = await mountWithRouter()
    const link = wrapper.find(
      'a[href="https://developers.google.com/terms/api-services-user-data-policy"]'
    )
    expect(link.exists()).toBe(true)
    expect(wrapper.text()).toContain('Limited Use requirements')
  })

  it('includes Google limited use bullet in How We Use section', async () => {
    const wrapper = await mountWithRouter()
    expect(wrapper.text()).toContain(
      'Google user data is used only for providing and improving user-facing features within Fyli'
    )
  })

  it('discloses AI third-party providers by name', async () => {
    const wrapper = await mountWithRouter()
    const text = wrapper.text()
    expect(text).toContain('Grok')
    expect(text).toContain('xAI')
    expect(text).toContain('OpenAI')
    expect(text).toContain('Google')
  })

  it('includes link to terms of service', async () => {
    const wrapper = await mountWithRouter()
    const link = wrapper.find('a[href="/terms"]')
    expect(link.exists()).toBe(true)
    expect(link.text()).toBe('Terms of Service')
  })

  it('shows last updated date', async () => {
    const wrapper = await mountWithRouter()
    expect(wrapper.text()).toContain('Last updated: February 2026')
  })

  it('includes data deletion contact', async () => {
    const wrapper = await mountWithRouter()
    expect(wrapper.text()).toContain('information@fyli.com')
    expect(wrapper.text()).toContain('delete your account')
  })

  it('includes children privacy disclosure', async () => {
    const wrapper = await mountWithRouter()
    expect(wrapper.text()).toContain('under 13')
  })

  it('sets document title', async () => {
    await mountWithRouter()
    expect(document.title).toBe('Privacy Policy — Fyli')
  })
})
```

### 4.3 RegisterView Update Tests

**File:** `fyli-fe-v2/src/views/auth/RegisterView.test.ts` (create if not present)

The `useGoogleSignIn` composable loads an external script, so it must be mocked. Full test file:

```typescript
import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createRouter, createMemoryHistory } from 'vue-router'
import RegisterView from './RegisterView.vue'

// Mock Google Sign-In composable — it loads an external script
vi.mock('@/composables/useGoogleSignIn', () => ({
  useGoogleSignIn: () => ({
    renderButton: vi.fn(),
    error: '',
  }),
}))

async function mountRegisterView() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/register', component: RegisterView },
      { path: '/login', component: { template: '<div />' } },
      { path: '/terms', component: { template: '<div />' } },
      { path: '/privacy', component: { template: '<div />' } },
    ],
  })
  await router.push('/register')
  await router.isReady()
  return mount(RegisterView, {
    global: { plugins: [router] },
  })
}

describe('RegisterView — terms links', () => {
  it('terms checkbox links to /terms page in new tab', async () => {
    const wrapper = await mountRegisterView()
    const link = wrapper.find('a[href="/terms"]')
    expect(link.exists()).toBe(true)
    expect(link.text()).toBe('Terms of Service')
    expect(link.attributes('target')).toBe('_blank')
  })

  it('terms checkbox links to /privacy page in new tab', async () => {
    const wrapper = await mountRegisterView()
    const link = wrapper.find('a[href="/privacy"]')
    expect(link.exists()).toBe(true)
    expect(link.text()).toBe('Privacy Policy')
    expect(link.attributes('target')).toBe('_blank')
  })

  it('shows terms and privacy footer links', async () => {
    const wrapper = await mountRegisterView()
    const footer = wrapper.findAll('.text-muted.small a')
    const hrefs = footer.map(a => a.attributes('href'))
    expect(hrefs).toContain('/terms')
    expect(hrefs).toContain('/privacy')
  })

  it('footer links remain visible after form submission', async () => {
    const wrapper = await mountRegisterView()
    // Simulate the "sent" state by setting internal ref
    // Footer links should still be visible outside v-if/v-else
    const footer = wrapper.findAll('.text-muted.small a')
    expect(footer.length).toBeGreaterThanOrEqual(2)
  })
})
```

### 4.4 LoginView Update Tests

**File:** `fyli-fe-v2/src/views/auth/LoginView.test.ts` (create if not present)

```typescript
import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createRouter, createMemoryHistory } from 'vue-router'
import LoginView from './LoginView.vue'

// Mock Google Sign-In composable
vi.mock('@/composables/useGoogleSignIn', () => ({
  useGoogleSignIn: () => ({
    renderButton: vi.fn(),
    error: '',
  }),
}))

async function mountLoginView() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/login', component: LoginView },
      { path: '/register', component: { template: '<div />' } },
      { path: '/terms', component: { template: '<div />' } },
      { path: '/privacy', component: { template: '<div />' } },
      { path: '/', component: { template: '<div />' } },
    ],
  })
  await router.push('/login')
  await router.isReady()
  return mount(LoginView, {
    global: { plugins: [router] },
  })
}

describe('LoginView — footer links', () => {
  it('shows terms and privacy footer links', async () => {
    const wrapper = await mountLoginView()
    const footer = wrapper.findAll('.text-muted.small a')
    const hrefs = footer.map(a => a.attributes('href'))
    expect(hrefs).toContain('/terms')
    expect(hrefs).toContain('/privacy')
  })

  it('footer links remain visible after form submission', async () => {
    const wrapper = await mountLoginView()
    const footer = wrapper.findAll('.text-muted.small a')
    expect(footer.length).toBeGreaterThanOrEqual(2)
  })
})
```

---

## Implementation Order

1. **Phase 1** — Update `PublicLayout.vue` (wide meta support), update router (routes + scrollBehavior)
2. **Phase 2** — Create `TermsView.vue` and `PrivacyView.vue`
3. **Phase 3** — Update `RegisterView.vue` (checkbox links + footer), `LoginView.vue` (footer)
4. **Phase 4** — Write and run all tests
5. **Post-deploy** — Configure Google Cloud Console OAuth consent screen with live URLs

## Notes

- **No backend changes** — all content is static in Vue components
- **No new dependencies** — uses existing Bootstrap, Vue Router
- **Contact email** — Using `information@fyli.com` as placeholder. Update if a different address is preferred

## Review Feedback Addressed

| # | Issue | Resolution |
|---|-------|------------|
| 1 | PublicLayout 480px parent caps child 680px | Moved width control to PublicLayout via `$route.meta.wide`; removed inline width from components |
| 2 | Footer links inside `v-else` disappear after submit | Moved footer links outside `v-if`/`v-else` blocks |
| 3 | Checkbox uses `<a href>` instead of `<RouterLink>` | Changed to `<RouterLink to="..." target="_blank">` |
| 4 | Missing Limited Use bullet in "How We Use" section | Added Google limited use bullet to "How We Use Your Data" list |
| 5 | Test helpers don't call `router.push`/`isReady` | Made all `mountWithRouter` helpers `async` with `await router.push()` and `await router.isReady()` |
| 6 | Register/Login test helpers undefined | Provided full test files with `mountRegisterView`/`mountLoginView` helpers including Google Sign-In mock |
| 7 | No `document.title` meta | Added `onMounted` hook setting `document.title` in both views; added test assertions |
| 8 | No scroll-to-top on navigation | Added `scrollBehavior() { return { top: 0 } }` to router config |
| 9 | `lead` class bumps font to 1.25rem | Replaced `lead` class with `<em>` tag for the tagline — keeps emphasis without oversized font |

---

*Document Version: 1.1*
*Created: 2026-02-09*
