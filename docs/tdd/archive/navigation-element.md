# TDD: Navigation Element

## Overview

Add a primary navigation bar to the fyli-fe-v2 frontend with links to **Memories** (home), **Questions**, and **Account**. The navigation will be displayed on all authenticated pages and support future expansion with additional nav items.

## Current State

The current `AppNav.vue` component displays:
- "fyli" branding/logo (links to home)
- Invite button
- Logout button

The nav bar does not provide navigation to major sections of the app.

## Design Approach

### Option A: Bottom Navigation Bar (Mobile-First) - Recommended
A fixed bottom navigation bar with icon + label for each nav item. This pattern is optimal for mobile-first apps and follows conventions from the old fyli-fe frontend.

**Pros:**
- Easy thumb access on mobile
- Familiar pattern (iOS/Android apps)
- Scales well as nav items are added
- Clear visual hierarchy

**Cons:**
- Takes up screen real estate on mobile

### Option B: Top Navigation Bar (Integrated with Header)
Integrate nav links into the existing top header bar alongside the logo.

**Pros:**
- No additional screen space needed
- Traditional web pattern

**Cons:**
- Crowded on mobile
- Harder to tap on small screens
- Less scalable as items are added

**Selected: Option A (Bottom Navigation Bar)**

## Component Architecture

```
AppLayout.vue
├── AppNav.vue (existing - top bar with logo, invite, logout)
├── <slot /> (page content)
└── AppBottomNav.vue (new - bottom nav bar)
```

## File Structure

```
fyli-fe-v2/src/
├── components/
│   └── ui/
│       └── AppBottomNav.vue    # NEW - bottom navigation component
├── views/
│   └── account/
│       └── AccountView.vue     # NEW - account settings page (placeholder)
├── layouts/
│   └── AppLayout.vue           # MODIFY - add bottom nav
└── router/
    └── index.ts                # MODIFY - add account route
```

## Phase 1: Create Bottom Navigation Component

### 1.1 AppBottomNav.vue

Create a new component at `src/components/ui/AppBottomNav.vue`:

```vue
<script setup lang="ts">
import { useRoute } from 'vue-router'

const route = useRoute()

interface NavItem {
  name: string
  label: string
  icon: string
  iconActive: string
  to: string
  matchPaths: string[]
}

const navItems: NavItem[] = [
  {
    name: 'memories',
    label: 'Memories',
    icon: 'mdi-home-outline',
    iconActive: 'mdi-home',
    to: '/',
    matchPaths: ['/', '/memory'],
  },
  {
    name: 'questions',
    label: 'Questions',
    icon: 'mdi-comment-question-outline',
    iconActive: 'mdi-comment-question',
    to: '/questions',
    matchPaths: ['/questions'],
  },
  {
    name: 'account',
    label: 'Account',
    icon: 'mdi-account-outline',
    iconActive: 'mdi-account',
    to: '/account',
    matchPaths: ['/account'],
  },
]

function isActive(item: NavItem): boolean {
  return item.matchPaths.some((path) => {
    if (path === '/') {
      return route.path === '/'
    }
    return route.path.startsWith(path)
  })
}
</script>

<template>
  <nav class="bottom-nav border-top" role="navigation" aria-label="Main navigation">
    <RouterLink
      v-for="item in navItems"
      :key="item.name"
      :to="item.to"
      class="bottom-nav-item"
      :class="{ active: isActive(item) }"
      :aria-current="isActive(item) ? 'page' : undefined"
    >
      <span class="mdi" :class="isActive(item) ? item.iconActive : item.icon"></span>
      <span class="bottom-nav-label">{{ item.label }}</span>
    </RouterLink>
  </nav>
</template>

<style scoped>
.bottom-nav {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  display: flex;
  justify-content: space-around;
  align-items: center;
  background-color: var(--fyli-bg, #fff);
  padding: 0.5rem 0;
  padding-bottom: calc(0.5rem + env(safe-area-inset-bottom));
  z-index: 1000;
}

.bottom-nav-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.25rem;
  text-decoration: none;
  color: var(--fyli-text-muted);
  padding: 0.25rem 1rem;
  min-width: 64px;
  transition: color 0.15s ease-in-out;
}

.bottom-nav-item .mdi {
  font-size: 1.5rem;
}

.bottom-nav-label {
  font-size: 0.75rem;
  font-weight: 500;
}

.bottom-nav-item.active {
  color: var(--fyli-primary);
}

.bottom-nav-item:hover {
  color: var(--fyli-primary);
}
</style>
```

### 1.2 Design Notes

- **Icons**: Uses Material Design Icons with outline/filled variants for active state
  - Memories: `mdi-home-outline` / `mdi-home`
  - Questions: `mdi-comment-question-outline` / `mdi-comment-question`
  - Account: `mdi-account-outline` / `mdi-account`
- **Active State**: Primary brand color (#56c596) for active item
- **Safe Area**: Uses `env(safe-area-inset-bottom)` for iPhone notch/home indicator
- **Touch Targets**: Min 64px width for accessibility (44px minimum requirement met)
- **Z-index**: 1000 to stay above page content
- **Accessibility**: Uses `role="navigation"`, `aria-label`, and `aria-current="page"` for active item

## Phase 2: Update AppLayout

### 2.1 Modify AppLayout.vue

Add the bottom navigation and adjust content padding to account for the fixed bottom bar.

```vue
<script setup lang="ts">
import AppNav from '@/components/ui/AppNav.vue'
import AppBottomNav from '@/components/ui/AppBottomNav.vue'
</script>

<template>
  <div class="min-vh-100 bg-light d-flex flex-column">
    <AppNav />
    <main class="flex-grow-1">
      <div class="container py-3 pb-bottom-nav" style="max-width: 600px">
        <slot />
      </div>
    </main>
    <AppBottomNav />
  </div>
</template>

<style scoped>
.pb-bottom-nav {
  padding-bottom: 5rem;
}
</style>
```

### 2.2 Changes Summary

- Import and add `AppBottomNav` component
- Add `pb-bottom-nav` class to content container for bottom padding (prevents content from being hidden behind fixed nav)

### 2.3 Update AppLayout.test.ts

The existing test needs to be updated since there will now be two `<nav>` elements:

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount } from "@vue/test-utils";
import { createPinia, setActivePinia } from "pinia";
import AppLayout from "./AppLayout.vue";

vi.mock("vue-router", () => ({
	useRouter: () => ({ push: vi.fn() }),
	useRoute: () => ({ path: '/', params: {}, query: {} }),
	createRouter: () => ({ push: vi.fn(), beforeEach: vi.fn(), install: vi.fn() }),
	createWebHistory: vi.fn(),
	RouterLink: {
		name: "RouterLink",
		template: '<a :href="to"><slot /></a>',
		props: ["to"],
	},
}));

describe("AppLayout", () => {
	beforeEach(() => {
		setActivePinia(createPinia());
	});

	it("renders AppNav (top navigation)", () => {
		const wrapper = mount(AppLayout);
		expect(wrapper.find("nav.navbar").exists()).toBe(true);
	});

	it("renders AppBottomNav (bottom navigation)", () => {
		const wrapper = mount(AppLayout);
		expect(wrapper.find("nav.bottom-nav").exists()).toBe(true);
	});

	it("renders slot content", () => {
		const wrapper = mount(AppLayout, {
			slots: { default: '<p class="test-slot">Hello</p>' },
		});
		expect(wrapper.find(".test-slot").exists()).toBe(true);
		expect(wrapper.find(".test-slot").text()).toBe("Hello");
	});
});
```

## Phase 3: Add Account Route and Page

### 3.1 Create AccountView.vue

Create a placeholder account page at `src/views/account/AccountView.vue`:

```vue
<script setup lang="ts">
import { useAuthStore } from '@/stores/auth'
import { useRouter } from 'vue-router'

const auth = useAuthStore()
const router = useRouter()

function logout() {
  auth.logout()
  router.push('/login')
}
</script>

<template>
  <div>
    <h1 class="h4 mb-4">Account</h1>

    <div class="card mb-3">
      <div class="card-body">
        <h2 class="h6 text-muted mb-1">Name</h2>
        <p class="mb-0">{{ auth.user?.name || 'Loading...' }}</p>
      </div>
    </div>

    <div class="card mb-3">
      <div class="card-body">
        <h2 class="h6 text-muted mb-1">Email</h2>
        <p class="mb-0">{{ auth.user?.email || 'Loading...' }}</p>
      </div>
    </div>

    <div class="card mb-3">
      <div class="card-body">
        <h2 class="h6 text-muted mb-1">Plan</h2>
        <p class="mb-0">{{ auth.user?.premiumMember ? 'Premium' : 'Free' }}</p>
      </div>
    </div>

    <div class="mt-4">
      <button class="btn btn-outline-danger w-100" @click="logout">
        <span class="mdi mdi-logout me-2"></span>Logout
      </button>
    </div>
  </div>
</template>
```

### 3.2 Add Account Route

Update `src/router/index.ts` to add the account route:

```typescript
// Add after invite route
{
  path: '/account',
  name: 'account',
  component: () => import('@/views/account/AccountView.vue'),
  meta: { auth: true, layout: 'app' },
},
```

## Phase 4: Simplify Top Navigation

### 4.1 Update AppNav.vue

Remove the logout button from the top nav (it's now on the Account page) and keep it minimal:

```vue
<template>
  <nav class="navbar navbar-expand navbar-light bg-white border-bottom px-3">
    <RouterLink class="navbar-brand fw-bold" to="/">fyli</RouterLink>
    <div class="ms-auto d-flex align-items-center gap-2">
      <RouterLink to="/invite" class="btn btn-sm btn-outline-secondary">
        <span class="mdi mdi-account-plus-outline me-1"></span>Invite
      </RouterLink>
    </div>
  </nav>
</template>
```

**Note**: The logout button is removed since it will be accessible on the Account page. The Invite button remains in the header as it's a frequent action that benefits from visibility. The script block is removed entirely since no logic is needed.

### 4.2 Update AppNav.test.ts

Update the existing test to reflect the removed logout button:

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount } from "@vue/test-utils";
import { createPinia, setActivePinia } from "pinia";
import AppNav from "./AppNav.vue";

vi.mock("vue-router", () => ({
	useRouter: () => ({ push: vi.fn() }),
	useRoute: () => ({ params: {}, query: {} }),
	createRouter: () => ({ push: vi.fn(), beforeEach: vi.fn(), install: vi.fn() }),
	createWebHistory: vi.fn(),
	RouterLink: {
		name: "RouterLink",
		template: '<a :href="to"><slot /></a>',
		props: ["to"],
	},
}));

describe("AppNav", () => {
	beforeEach(() => {
		setActivePinia(createPinia());
	});

	it("renders brand/logo", () => {
		const wrapper = mount(AppNav);
		expect(wrapper.text()).toContain("fyli");
	});

	it("renders invite link", () => {
		const wrapper = mount(AppNav);
		expect(wrapper.text()).toContain("Invite");
	});

	it("links to home from logo", () => {
		const wrapper = mount(AppNav);
		const logoLink = wrapper.find('a[href="/"]');
		expect(logoLink.exists()).toBe(true);
	});

	it("links to invite page", () => {
		const wrapper = mount(AppNav);
		const inviteLink = wrapper.find('a[href="/invite"]');
		expect(inviteLink.exists()).toBe(true);
	});
});
```

## Phase 5: Testing

### 5.1 Component Tests

Create `src/components/ui/AppBottomNav.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import AppBottomNav from './AppBottomNav.vue'

let mockPath = '/'

vi.mock('vue-router', () => ({
	useRouter: () => ({ push: vi.fn() }),
	useRoute: () => ({ path: mockPath, params: {}, query: {} }),
	RouterLink: {
		name: 'RouterLink',
		template: '<a :href="to" :class="$attrs.class" :aria-current="$attrs[\'aria-current\']"><slot /></a>',
		props: ['to'],
	},
}))

describe('AppBottomNav', () => {
	beforeEach(() => {
		mockPath = '/'
	})

	it('renders all navigation items', () => {
		const wrapper = mount(AppBottomNav)

		expect(wrapper.text()).toContain('Memories')
		expect(wrapper.text()).toContain('Questions')
		expect(wrapper.text()).toContain('Account')
	})

	it('renders navigation with correct accessibility attributes', () => {
		const wrapper = mount(AppBottomNav)
		const nav = wrapper.find('nav')

		expect(nav.attributes('role')).toBe('navigation')
		expect(nav.attributes('aria-label')).toBe('Main navigation')
	})

	it('highlights Memories when on home route', () => {
		mockPath = '/'
		const wrapper = mount(AppBottomNav)

		const memoriesLink = wrapper.find('a[href="/"]')
		expect(memoriesLink.classes()).toContain('active')
		expect(memoriesLink.attributes('aria-current')).toBe('page')
	})

	it('highlights Memories when on memory detail route', () => {
		mockPath = '/memory/123'
		const wrapper = mount(AppBottomNav)

		const memoriesLink = wrapper.find('a[href="/"]')
		expect(memoriesLink.classes()).toContain('active')
	})

	it('highlights Questions when on questions route', () => {
		mockPath = '/questions'
		const wrapper = mount(AppBottomNav)

		const questionsLink = wrapper.find('a[href="/questions"]')
		expect(questionsLink.classes()).toContain('active')
		expect(questionsLink.attributes('aria-current')).toBe('page')
	})

	it('highlights Questions when on questions sub-route', () => {
		mockPath = '/questions/dashboard'
		const wrapper = mount(AppBottomNav)

		const questionsLink = wrapper.find('a[href="/questions"]')
		expect(questionsLink.classes()).toContain('active')
	})

	it('highlights Account when on account route', () => {
		mockPath = '/account'
		const wrapper = mount(AppBottomNav)

		const accountLink = wrapper.find('a[href="/account"]')
		expect(accountLink.classes()).toContain('active')
		expect(accountLink.attributes('aria-current')).toBe('page')
	})

	it('does not highlight inactive items', () => {
		mockPath = '/account'
		const wrapper = mount(AppBottomNav)

		const memoriesLink = wrapper.find('a[href="/"]')
		const questionsLink = wrapper.find('a[href="/questions"]')

		expect(memoriesLink.classes()).not.toContain('active')
		expect(questionsLink.classes()).not.toContain('active')
	})

	it('has correct icons for each nav item', () => {
		const wrapper = mount(AppBottomNav)

		expect(wrapper.find('.mdi-home-outline, .mdi-home').exists()).toBe(true)
		expect(wrapper.find('.mdi-comment-question-outline, .mdi-comment-question').exists()).toBe(true)
		expect(wrapper.find('.mdi-account-outline, .mdi-account').exists()).toBe(true)
	})

	it('shows filled icon for active item', () => {
		mockPath = '/'
		const wrapper = mount(AppBottomNav)

		const activeItem = wrapper.find('a[href="/"]')
		expect(activeItem.find('.mdi-home').exists()).toBe(true)
		expect(activeItem.find('.mdi-home-outline').exists()).toBe(false)
	})

	it('shows outline icon for inactive item', () => {
		mockPath = '/account'
		const wrapper = mount(AppBottomNav)

		const inactiveItem = wrapper.find('a[href="/"]')
		expect(inactiveItem.find('.mdi-home-outline').exists()).toBe(true)
		expect(inactiveItem.find('.mdi-home').exists()).toBe(false)
	})
})
```

### 5.2 AccountView Tests

Create `src/views/account/AccountView.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import AccountView from './AccountView.vue'
import { useAuthStore } from '@/stores/auth'

const push = vi.fn()

vi.mock('vue-router', () => ({
	useRouter: () => ({ push }),
	useRoute: () => ({ params: {}, query: {} }),
}))

describe('AccountView', () => {
	beforeEach(() => {
		setActivePinia(createPinia())
		push.mockReset()
	})

	it('displays user information', () => {
		const auth = useAuthStore()
		auth.user = {
			name: 'John Doe',
			email: 'john@example.com',
			premiumMember: false,
			privateMode: false,
			canShareDate: '',
			variants: {},
		}

		const wrapper = mount(AccountView)

		expect(wrapper.text()).toContain('John Doe')
		expect(wrapper.text()).toContain('john@example.com')
		expect(wrapper.text()).toContain('Free')
	})

	it('shows Premium for premium members', () => {
		const auth = useAuthStore()
		auth.user = {
			name: 'Jane Doe',
			email: 'jane@example.com',
			premiumMember: true,
			privateMode: false,
			canShareDate: '',
			variants: {},
		}

		const wrapper = mount(AccountView)

		expect(wrapper.text()).toContain('Premium')
	})

	it('shows Loading when user not yet loaded', () => {
		const auth = useAuthStore()
		auth.user = null

		const wrapper = mount(AccountView)

		expect(wrapper.text()).toContain('Loading...')
	})

	it('calls logout and redirects on button click', async () => {
		const auth = useAuthStore()
		auth.user = {
			name: 'Test User',
			email: 'test@example.com',
			premiumMember: false,
			privateMode: false,
			canShareDate: '',
			variants: {},
		}

		const logoutSpy = vi.spyOn(auth, 'logout')

		const wrapper = mount(AccountView)

		await wrapper.find('button').trigger('click')

		expect(logoutSpy).toHaveBeenCalled()
		expect(push).toHaveBeenCalledWith('/login')
	})

	it('renders logout button with correct styling', () => {
		const auth = useAuthStore()
		auth.user = {
			name: 'Test User',
			email: 'test@example.com',
			premiumMember: false,
			privateMode: false,
			canShareDate: '',
			variants: {},
		}

		const wrapper = mount(AccountView)
		const button = wrapper.find('button')

		expect(button.classes()).toContain('btn-outline-danger')
		expect(button.text()).toContain('Logout')
	})
})
```

## Implementation Order

| Phase | Task | Files |
|-------|------|-------|
| 1 | Create bottom nav component | `AppBottomNav.vue`, `AppBottomNav.test.ts` |
| 2 | Update layout to include bottom nav | `AppLayout.vue`, `AppLayout.test.ts` |
| 3 | Add account route and page | `router/index.ts`, `AccountView.vue`, `AccountView.test.ts` |
| 4 | Simplify top navigation | `AppNav.vue`, `AppNav.test.ts` |

## Future Expansion

The bottom nav is designed to easily add more items. To add a new nav item:

1. Add entry to `navItems` array in `AppBottomNav.vue`
2. Create the corresponding route and view
3. Add test coverage

Example additions for later:
- Connections (`mdi-account-group-outline` / `mdi-account-group`)
- Albums (`mdi-image-multiple-outline` / `mdi-image-multiple`)
- Storylines (`mdi-clock-outline` / `mdi-clock`)

## Accessibility Considerations

- All nav items use semantic `<a>` elements (via RouterLink)
- `role="navigation"` and `aria-label` on nav element for screen readers
- `aria-current="page"` on active nav item
- Minimum touch target size of 64px width
- Clear visual distinction for active state
- Labels included for screen readers
- Sufficient color contrast for brand color on white

## Raw SQL (N/A)

No database changes required for this feature.
