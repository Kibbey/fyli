# Testing Best Practices

## Overview

- **Coverage target:** 70% minimum for new code
- **TDD approach:** Write failing tests first, implement minimum code to pass, refactor while keeping tests green
- All new features and bug fixes should include tests

## Running Tests

### Backend

```bash
# Full test suite
cd cimplur-core/Memento && dotnet test DomainTest/DomainTest.csproj

# With coverage
dotnet test DomainTest/DomainTest.csproj --collect:"XPlat Code Coverage"

# Filter by category
dotnet test --filter "TestCategory=Integration"
dotnet test --filter "TestCategory=UserService"

# Filter by class
dotnet test --filter "FullyQualifiedName~UserServiceTest"

# Filter by test name
dotnet test --filter "Name~AddUser"
```

### Frontend

```bash
# Full test suite
cd fyli-fe-v2 && npm run test:unit -- --run

# Run specific test file
cd fyli-fe-v2 && npx vitest run src/stores/auth.test.ts
```

---

## Backend Testing (C# / MSTest)

### Test Infrastructure

- **Framework:** MSTest (`Microsoft.VisualStudio.TestTools.UnitTesting`)
- **Location:** `cimplur-core/Memento/DomainTest/`
- **Database:** Real SQL Server database (localhost:1433)
- **Pattern:** Integration tests against local database
- **Base class:** `BaseRepositoryTest` — provides test helpers and context management
- **Service factory:** `TestServiceFactory` — creates service instances for testing

### Naming Convention

```
MethodName_Scenario_ExpectedBehavior
```

Examples:
- `AddUser_WithValidData_ShouldCreateUser`
- `UpdateComment_ByNonOwner_ShouldThrowNotAuthorizedException`
- `GetConnections_WithNoConnections_ShouldReturnEmptyList`

### AAA Pattern (Arrange / Act / Assert)

```csharp
[TestMethod]
public async Task MethodName_Scenario_ExpectedBehavior()
{
    // Arrange - Set up test data and preconditions
    var user = await CreateTestUser(_context);
    DetachAllEntities(_context);

    // Act - Execute the method under test
    var result = await _service.Method(user.UserId);

    // Assert - Verify the expected outcome
    Assert.IsNotNull(result);
}
```

### Critical: Context Isolation for Service Tests

Services create their own `DbContext` via `BaseService`. A transaction on the test `_context` will lock rows and cause 30-second timeout errors.

**Never use `InitializeWithTransaction()` for tests that call service methods.**

#### Correct Pattern

1. `_context = CreateTestContext()` (no transaction)
2. Insert test data, call `DetachAllEntities(_context)` before service calls
3. Service creates its own context and reads committed data
4. Verify with `CreateVerificationContext()`

```csharp
[TestInitialize]
public void Setup()
{
    _context = CreateTestContext();  // No transaction
    _service = TestServiceFactory.CreateService();
}

[TestMethod]
public async Task Example_ServiceTest()
{
    // Arrange
    var user = await CreateTestUser(_context);
    DetachAllEntities(_context);  // Detach so service context can read

    // Act
    var result = await _service.DoSomething(user.UserId);

    // Assert
    Assert.IsNotNull(result);
}
```

#### MemoryShareLinkServiceTest Exception

`MemoryShareLinkServiceTest` uses a try/finally manual cleanup pattern instead of `DetachAllEntities`. Do not change this pattern.

### Navigation Property Gotcha (EF Core Change Tracker)

When testing methods that rely on navigation properties (e.g., `RemoveConnection`), create entities via service methods rather than test helpers. Test helpers insert raw entities that may not have navigation properties loaded, causing the service to fail.

```csharp
// BAD - navigation properties not loaded
var connection = await CreateTestConnection(_context, user1.UserId, user2.UserId);
DetachAllEntities(_context);
await _service.RemoveConnection(user1.UserId, user2.UserId); // May fail

// GOOD - service creates entities with proper navigation properties
await _service.EnsureConnectionAsync(user1.UserId, user2.UserId);
await _service.RemoveConnection(user1.UserId, user2.UserId); // Works
```

### Verification with Fresh Context

Always verify database state with a fresh context to avoid reading cached data:

```csharp
using (var verifyContext = CreateVerificationContext())
{
    var result = await verifyContext.Entities.FindAsync(id);
    Assert.IsNotNull(result);
}
```

### Exception Testing

```csharp
[TestMethod]
[ExpectedException(typeof(NotAuthorizedException))]
public async Task Method_InvalidCondition_ShouldThrowException()
{
    await _service.Method(invalidArg);
}
```

### Test Categories

Use MSTest categories to organize and filter tests:

```csharp
[TestCategory("Integration")]    // All integration tests
[TestCategory("UserService")]    // Service-specific tests
```

### Test Helper Methods (BaseRepositoryTest)

Available helpers in the base class:
- `CreateTestUser(_context)` — creates a user with profile
- `CreateTestDrop(_context, userId)` — creates a drop (memory)
- `CreateTestConnection(_context, userId1, userId2)` — creates a connection between users
- `CreateTestGroup(_context, userId, name)` — creates a group
- `CreateTestTimeline(_context, userId, name)` — creates a timeline
- `CreateTestAlbum(_context, userId, name)` — creates an album
- `DetachAllEntities(_context)` — detaches all tracked entities
- `CreateTestContext()` — creates a new DbContext
- `CreateVerificationContext()` — creates a fresh context for verification

### What to Test

- **Repositories:** CRUD operations, query filters, edge cases
- **Services:** Business logic, authorization checks, validation rules
- **API endpoints:** Request/response contracts, status codes, error responses
- **Edge cases:** Null inputs, empty collections, boundary values
- **Error paths:** Authorization failures, not-found scenarios, invalid data

---

## Frontend Testing (Vitest + Vue Test Utils)

### Test Infrastructure

- **Framework:** Vitest with jsdom environment
- **Component testing:** `@vue/test-utils` for mounting and interacting with Vue components
- **File placement:** Next to source file as `<name>.test.ts` (e.g., `src/stores/auth.test.ts`)
- **Run command:** `cd fyli-fe-v2 && npm run test:unit -- --run`

### Component Tests

- Mount components using `@vue/test-utils` (`mount` or `shallowMount`)
- Test prop rendering and default behavior
- Test emitted events via `wrapper.emitted()`
- Test user interactions (clicks, input, form submission)
- Test conditional rendering (v-if/v-show states)
- Provide mock Pinia stores and router when needed

```typescript
import { mount } from "@vue/test-utils";
import MyComponent from "./MyComponent.vue";

describe("MyComponent", () => {
  it("renders prop value", () => {
    const wrapper = mount(MyComponent, {
      props: { title: "Hello" },
    });
    expect(wrapper.text()).toContain("Hello");
  });

  it("emits update on click", async () => {
    const wrapper = mount(MyComponent);
    await wrapper.find("button").trigger("click");
    expect(wrapper.emitted("update")).toBeTruthy();
  });
});
```

### Pinia Store Tests

- Create a fresh Pinia instance per test with `setActivePinia(createPinia())`
- Test actions including async API calls (mock Axios)
- Test getters with various state configurations
- Test state mutations and verify reactivity

```typescript
import { setActivePinia, createPinia } from "pinia";
import { useAuthStore } from "./auth";

describe("AuthStore", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it("logs in successfully", async () => {
    const store = useAuthStore();
    await store.login({ email: "test@test.com", password: "pass" });
    expect(store.isAuthenticated).toBe(true);
  });
});
```

### API Service Tests

- Mock Axios using `vi.mock('axios')` or mock the api instance
- Verify correct HTTP method, URL path, query params, and request body
- Test success responses and error handling paths
- Verify auth headers are sent

```typescript
import { vi } from "vitest";
import api from "./api";
import { fetchUsers } from "./userApi";

vi.mock("./api");

describe("userApi", () => {
  it("fetches users with correct params", async () => {
    vi.mocked(api.get).mockResolvedValue({ data: [] });
    await fetchUsers({ page: 1 });
    expect(api.get).toHaveBeenCalledWith("/users", { params: { page: 1 } });
  });
});
```

### Composable Tests

- Test composables inside a Vue component context or with a `withSetup` helper
- Verify reactive state changes
- Test cleanup/teardown behavior

### Utility / Helper Tests

- Pure function testing — straightforward input/output assertions
- Test edge cases (null, undefined, empty strings, boundary values)

### What to Test

```
Frontend Testing Checklist:
[ ] New Vue components have corresponding .test.ts files
[ ] Component tests cover rendering, props, emits, and user interactions
[ ] Pinia stores have tests for actions, getters, and state mutations
[ ] API service files have tests with Axios mocked
[ ] Composables have tests verifying reactive behavior
[ ] Utility/helper functions have unit tests
[ ] Tests mock external dependencies (API, router, etc.)
[ ] Both success and error paths are tested
[ ] All frontend tests pass (cd fyli-fe-v2 && npm run test:unit -- --run)
```

---

## Regression Testing for Bug Fixes

When fixing bugs, always add regression tests to prevent recurrence:

1. **Unit test the fix** — Test the specific function that was fixed
2. **Edge case tests** — Cover the scenario that caused the bug
3. **Run existing tests** — Ensure the fix doesn't break other functionality

```bash
# Backend
cd cimplur-core/Memento && dotnet test

# Frontend
cd fyli-fe-v2 && npm run test:unit -- --run
```
