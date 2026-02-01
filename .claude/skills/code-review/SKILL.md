---
name: code-review
description: Review code for quality, standards compliance, and best practices. Use when asked to review code, check for issues, audit code quality, or validate implementations against project standards.
allowed-tools: Read, Grep, Glob
---

# Code Review Skill

Perform a comprehensive code review for the personal_assistant project, checking against established standards and best practices.

## Review Checklist

### Architecture Compliance

**Backend (C#/.NET):**
- [ ] 3-tier architecture respected (Controllers → Services → Repositories)
- [ ] Controllers only handle HTTP request/response and basic validation
- [ ] Services contain business logic and business validation
- [ ] Repositories handle all database operations
- [ ] Domain models used between layers (not raw DB entities in controllers)
- [ ] Request/Response DTOs defined for controllers
- [ ] Dependency injection used for all service/repository wiring
- [ ] Global error handling used (throw immediately, catch globally via middleware)
- [ ] Jsonb column was not used.  Only use Jsonb if other alternatives are not available.
- [ ] Database changes use EF Core Code-First pattern: POCO entity in `Entities/`, FK config in `StreamContext.OnModelCreating`, `DbSet<T>` property added, migration generated via `dotnet ef migrations add`. No raw SQL for schema changes.

**Frontend (Vue.js):**
- [ ] Composition API with `<script setup>` syntax used
- [ ] Components are single-responsibility
- [ ] Props for parent-to-child, Emits for child-to-parent
- [ ] Pinia stores for app-wide state, composables for simple sharing
- [ ] Business logic in stores, components focused on presentation
- [ ] Template order: `<template>`, `<script setup>`, `<style scoped>`

### Code Quality

- [ ] Methods under 100 lines
- [ ] SOLID principles followed
- [ ] Factory patterns used instead of if/else chains or switch statements where appropriate
- [ ] DRY - no unnecessary code duplication
- [ ] Composability favored for reusable logic
- [ ] C# types properly defined (no `dynamic` or `object` without justification)
- [ ] Functions have brief summary comments

### Type Standards

**Frontend:**
- [ ] Props typed with `defineProps<PropsType>()`
- [ ] Emits typed with `defineEmits<EmitsType>()`
- [ ] Explicit types for refs
- [ ] Interfaces for API responses and store state

**Backend (C#):**
- [ ] Request/Response DTOs defined
- [ ] Domain model classes with proper encapsulation
- [ ] Repository interfaces with explicit return types
- [ ] Async methods return `Task<T>` and follow `Async` naming suffix

### Testing

- [ ] Tests written for new functionality (TDD approach)
- [ ] Business layer has unit tests
- [ ] Repository layer has unit tests
- [ ] Utilities have unit tests
- [ ] Minimum 70% coverage target

### Security

- [ ] No hardcoded secrets or credentials
- [ ] Input validation at system boundaries
- [ ] No SQL injection vulnerabilities
- [ ] No XSS vulnerabilities
- [ ] Authentication/authorization properly checked

### Performance (Frontend)

- [ ] `v-show` for frequent toggles, `v-if` for rare changes
- [ ] Routes lazy loaded
- [ ] Unique IDs (not indexes) as v-for keys
- [ ] `shallowRef` for large objects
- [ ] Virtual scroll for long lists

### Documentation

- [ ] AI prompts documented in `/docs/AI_PROMPTS.md` if modified
- [ ] Database migrations documented in `cimplur-core/docs/DATA_SCHEMA.md`
- [ ] Release notes updated in `/docs/release_note.md` for new features

### Style Compliance

- [ ] No "powered by AI" or "AI suggested" terminology
- [ ] Tabs for indentation
- [ ] Double quotes
- [ ] Semicolons used
- [ ] Line length under 100 characters
- [ ] **Backend (C#):** PascalCase for methods, properties, and public members; camelCase for local variables and parameters; `_camelCase` for private fields; PascalCase for classes and interfaces (prefix interfaces with `I`)
- [ ] **Frontend:** camelCase for variables/functions; PascalCase for components
- [ ] UPPER_CASE for constants

### Look and Feel
- [ ] Have the designer skill review the work and verify compliance with design standards
- [ ] Add designer feedback on changes that need to be made

## Review Output Format

Provide findings organized by severity:

### Critical Issues
Issues that must be fixed (security vulnerabilities, breaking bugs, architecture violations)

### Improvements
Recommended changes for better code quality

### Suggestions
Optional enhancements and best practice recommendations

### Positive Notes
Well-implemented patterns worth highlighting
