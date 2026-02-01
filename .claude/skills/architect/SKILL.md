---
name: architect
description: Design and plan software architecture for new features or refactoring. Use when asked to architect a solution, design a feature, create TDD, plan implementation, or make architectural decisions.
allowed-tools: Read, Grep, Glob, Task
---

# Architect Skill

Design software architecture for the personal_assistant project following established patterns and principles.

## Architecture Principles

This project follows **Domain Driven Design** and **Onion Architecture**:

```
┌─────────────────────────────────────────────────────┐
│                   Controllers                        │
│              (Presentation Layer)                    │
│         HTTP handling, request validation            │
├─────────────────────────────────────────────────────┤
│                    Services                          │
│              (Business/Domain Layer)                 │
│    Core business logic, domain rules, validation     │
├─────────────────────────────────────────────────────┤
│                  Repositories                        │
│              (Data Access Layer)                     │
│         Database operations, data mapping            │
├─────────────────────────────────────────────────────┤
│                    Database                          │
│                   (PostgreSQL)                       │
└─────────────────────────────────────────────────────┘
```

## Design Process

For every request, always create an md file and save it to directory /docs/tdd.

### 1. Understand Requirements
- Clarify the feature/change scope
- Identify affected domains
- Determine integration points with existing code

### 2. Identify Components

**For Backend Features:**
- Which controllers need modification/creation?
- What services handle the business logic?
- What repositories are needed for data access?
- What domain models represent the data?
- What request/response models are needed?

**For Frontend Features:**
- Which views/pages are affected?
- What components need creation/modification?
- What composables provide shared logic?
- What Pinia stores manage state?
- What service layer handles API calls?
- Use `docs/FRONTEND_STYLE_GUIDE.md` for all style decisions.

### 3. Design Patterns to Apply

**Factory Pattern** - Use instead of if/else chains or switch statements:
```csharp
// Good: Factory pattern via dictionary or DI registration
var handlerFactory = new Dictionary<string, INotificationHandler>
{
    ["email"] = new EmailHandler(),
    ["sms"] = new SmsHandler(),
    ["push"] = new PushHandler()
};
var handler = handlerFactory[type];

// Avoid: Switch statements
switch (type)
{
    case "email": ...
    case "sms": ...
}
```

**Repository Pattern** - Abstract database operations:
```csharp
public interface IUserRepository
{
    Task<User?> FindByIdAsync(string id);
    Task<User> SaveAsync(User user);
}
```

**Service Pattern** - Encapsulate business logic:
```csharp
public class AgendaService
{
    private readonly ICalendarRepository _calendarRepo;
    private readonly ITodoRepository _todoRepo;

    public AgendaService(ICalendarRepository calendarRepo, ITodoRepository todoRepo)
    {
        _calendarRepo = calendarRepo;
        _todoRepo = todoRepo;
    }

    public async Task<Agenda> GenerateDailyAgendaAsync(string userId, DateTime date)
    {
        // Business logic here
    }
}
```

**Composable Pattern (Frontend)** - Share reactive logic:
```typescript
// useCalendar.ts
export function useCalendar() {
  const events = ref<CalendarEvent[]>([]);
  const loading = ref(false);

  async function fetchEvents(range: DateRange) { ... }

  return { events, loading, fetchEvents };
}
```

### 4. Data Flow Design

```
Request → Controller → Service → Repository → Database
                ↓
         Validation
                ↓
         Domain Logic
                ↓
Database → Repository → Service → Controller → Response
```

**Model Transformations:**
- Controller receives `RequestDTO` → transforms to `DomainModel`
- Service works with `DomainModel`
- Repository transforms `DomainModel` ↔ `DatabaseEntity`
- Controller transforms `DomainModel` → `ResponseDTO`

### 5. Error Handling Strategy

- Throw typed exceptions immediately when errors occur
- Let global error handler catch and format responses
- Define custom exception types for business errors:
```csharp
public class NotFoundException : AppException { ... }
public class ValidationException : AppException { ... }
public class AuthorizationException : AppException { ... }
```

### 6. Testing Strategy

Following TDD approach:
1. Write failing tests first
2. Implement minimum code to pass
3. Refactor while keeping tests green

**Test Boundaries:**
- Unit tests: Services, Repositories, Utilities
- Integration tests: API endpoints
- Frontend: Component tests, Store tests

## Architecture Output Format

When designing a feature, provide:

### Overview
Brief description of the architectural approach

### Component Diagram
Visual representation of component relationships

### File Structure
```
cimplur-core/
├── Controllers/
│   └── [NewController]Controller.cs
├── Services/
│   └── [NewService]Service.cs
├── Repositories/
│   └── [NewRepo]Repository.cs
└── Models/
    └── [NewModel].cs
```

### Interface Definitions
Key interfaces and types needed

### Data Flow
Step-by-step flow through the system

### Database Changes
This project uses **EF Core Code-First migrations**. Never write raw SQL for schema changes. To add/modify tables:
1. Create/update POCO entity class in `cimplur-core/Memento/Domain/Entities/`
2. Add FK and index configuration in `StreamContext.cs` → `OnModelCreating`
3. Add `DbSet<T>` property to `StreamContext.cs`
4. Generate migration: `cd cimplur-core/Memento && dotnet ef migrations add <Name>`

When documenting schema in TDDs, show the POCO entity, the `OnModelCreating` configuration, and the `DbSet` line. 

Raw SQL MUST be included as a reference comment.

Always create the raw sql for each migration and save it in the TDD.  That is the way the code gets to production (we don't use EF migrations in production).

### Database Schema
Do not use jsonb fields if it can be avoided.

### API Endpoints
New or modified endpoints

### Frontend Components
Vue components and their responsibilities

### Testing Plan
What tests are needed and at what level

### Implementation Order
Recommended sequence for building the feature

### Review
After creating the TDD call the /code-review skill to review the TDD and get feedback.  Display feedback to the user to decide if to address.

## Project-Specific Considerations

- **Calendar Integration**: Consider Google Calendar and Outlook APIs
- **Notes/Reminders**: Auto-organization requires AI/categorization logic
- **Daily Agenda**: Combines calendar, todos, and priority algorithms
- **Weekly Summary**: Aggregation of completed items and accomplishments
- **Focus Planning**: AI-assisted priority recommendations

Remember: Keep methods under 100 lines, favor composability, and always consider testability in designs.
