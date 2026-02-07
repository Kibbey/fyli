# Fyli

Monorepo-style wrapper for three subprojects. Each subproject has its own git repository and is gitignored from this root repo.

## Subprojects

- **cimplur-core/** — Backend (C#/.NET)
- **fyli-fe/** — Frontend (AngularJS / Angular 1) - this is the old project.  Use it for guidance on functionality.
- **fyli-fe-v2/** - New Frontend
- **fyli-infra/** — Infrastructure (AWS)

## Structure

This root repo tracks only shared configuration and orchestration. All subproject directories are gitignored—each manages its own source control independently.

## Backend Conventions (cimplur-core)

### Database
The project uses **SQL Server** (not PostgreSQL). All raw SQL scripts must use SQL Server syntax:
- `INT IDENTITY(1,1)` for auto-increment (not `SERIAL`)
- `DATETIME2` for timestamps (not `TIMESTAMPTZ`)
- `BIT` for booleans (not `BOOLEAN`)
- `UNIQUEIDENTIFIER` for GUIDs (not `UUID`)
- `NVARCHAR` for Unicode strings
- Square brackets `[TableName]` for identifiers (not double quotes)

### Backwards Compatibility
All backend changes must be 100% backwards compatible for drops (memories) and access to drops (which users have access to drops they or others created).

### Database Migrations (EF Core Code-First)

The project uses **EF Core Code-First migrations**. Never write raw SQL for schema changes.

1. Create/update POCO entity in `cimplur-core/Memento/Domain/Entities/`
2. Add FK and index configuration in `StreamContext.cs` → `OnModelCreating`
3. Add `DbSet<T>` property to `StreamContext.cs`
4. Generate migration: `cd cimplur-core/Memento && dotnet ef migrations add <Name>`

Always create raw sql for each migration and save them in the TDD.  That is the way the code get's to production (we don't use EF migrations in production).

Migrations are auto-generated in `cimplur-core/Memento/Domain/Migrations/`.

## Backend API Reference

The backend API is documented via Swagger at: **https://localhost:5001/swagger/v1/swagger.json**

All frontend API service files in `fyli-fe-v2/src/services/` must match the backend API contracts defined in this swagger spec. When building or modifying frontend features, always verify request paths, HTTP methods, query parameters, and request/response body schemas against the swagger definition.

### Frontend API Conventions (fyli-fe-v2)

- Base URL: `/api` (configured in `src/services/api.ts`)
- HTTP client: Axios with Bearer token auth
- API service files are in `src/services/*Api.ts`

## Frontend Style Guide

All visual design decisions are documented in **`docs/FRONTEND_STYLE_GUIDE.md`**. Key points:

- **Brand primary color:** `#56c596` — used for logo, primary buttons, links, active states
- **Framework:** Bootstrap 5 with the primary color overridden via Sass variables
- **Icons:** Material Design Icons (`@mdi/font`)
- No hardcoded hex colors in components — use Bootstrap classes or `var(--fyli-*)` custom properties
- See the style guide for the full color palette, component patterns, and rules
