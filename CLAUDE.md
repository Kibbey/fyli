# Fyli

Monorepo-style wrapper for subprojects. Each subproject has its own git repository and is gitignored from this root repo.

## Subprojects

- **cimplur-core/** — Backend (C#/.NET)
- **fyli-fe/** — Frontend (AngularJS / Angular 1) - this is the old project.  Use it for guidance on functionality.
- **fyli-fe-v2/** - New Frontend
- **fyli-html/** — Marketing site (static HTML/Sass/Gulp)
- **fyli-infra/** — Infrastructure (AWS)

## Structure

This root repo tracks only shared configuration and orchestration. All subproject directories are gitignored—each manages its own source control independently.

## Backend Conventions (cimplur-core)

### Database

All database conventions, EF Core workflows, SQL Server syntax, migration scripts, and schema patterns are documented in **`docs/DATABASE_GUIDE.md`**.

### Backwards Compatibility
All backend changes must be 100% backwards compatible for drops (memories) and access to drops (which users have access to drops they or others created).

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
