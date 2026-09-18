# Database Guide

## Overview

- **Database:** SQL Server (via Docker, `localhost:1433`) — see [Local SQL Server (Docker)](#local-sql-server-docker) for how to start it
- **ORM:** EF Core 9.0.8 (Code-First)
- **Target Framework:** .NET 9.0
- **Context:** `StreamContext` in `cimplur-core/Memento/Domain/Entities/StreamContext.cs`

## SQL Server Syntax

All raw SQL must use SQL Server syntax (not PostgreSQL):

| Type | SQL Server | NOT |
|------|-----------|-----|
| Auto-increment | `INT IDENTITY(1,1)` | `SERIAL` |
| Timestamps | `DATETIME2` | `TIMESTAMPTZ` |
| Booleans | `BIT` | `BOOLEAN` |
| GUIDs | `UNIQUEIDENTIFIER` | `UUID` |
| Unicode strings | `NVARCHAR` | `TEXT` |
| Identifiers | `[TableName]` | `"TableName"` |

## Generating Raw SQL for Migrations

Production does **not** use EF migrations directly. Raw SQL scripts are generated from migrations and applied manually.

**Always use the EF Core tooling to generate SQL — never hand-write migration scripts.**

```bash
cd cimplur-core/Memento

# Generate idempotent SQL for all migrations after a given migration:
dotnet ef migrations script <from_migration_name> --idempotent --project Domain --startup-project Memento

# Example: generate SQL for everything after transcode_update:
dotnet ef migrations script 20251207185045_transcode_update --idempotent --project Domain --startup-project Memento
```

The `--idempotent` flag wraps each step in `IF NOT EXISTS` checks against `__EFMigrationsHistory`, making scripts safe to re-run.

Save generated SQL to `docs/migrations/` and update the relevant TDD post creation.

## Creating Schema Changes (EF Core Code-First)

Never write raw SQL for schema changes. Always use the Code-First workflow:

1. Create or update the POCO entity in `cimplur-core/Memento/Domain/Entities/`
2. Add `DbSet<T>` property to `StreamContext.cs`
3. Configure FKs, indexes, and constraints in `StreamContext.OnModelCreating`
4. Generate the migration:
   ```bash
   cd cimplur-core/Memento && dotnet ef migrations add <Name> --project Domain --startup-project Memento
   ```
5. Generate the raw SQL (see above) and save to the TDD

Migrations are auto-generated in `cimplur-core/Memento/Domain/Migrations/`.

## Local SQL Server (Docker)

The local database runs in Docker on `localhost:1433`. **It is not started automatically.**
If it is not running, every integration test in `DomainTest` fails at
`SqlConnection.TryOpen` — roughly 298 of 375 — with a connection error rather than an
assertion failure. That symptom means "the container is stopped," not "the code is broken."

### Start it

Most checkouts already have a hand-created container named `sql_server_instance`:

```bash
docker start sql_server_instance

# Wait until it accepts connections (first start after a long gap takes ~30s
# while it recovers databases):
until docker exec sql_server_instance /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U SA -P 'Dog1$Dobbie!' -C -Q "SELECT 1" >/dev/null 2>&1; do sleep 3; done
```

Check state with `docker ps -a | grep mssql`. An exit code of `137` is a SIGKILL from a
`docker stop` that exceeded its timeout or from Docker Desktop shutting down — SQL Server
takes longer than the default 10s to stop. It is not a crash and not data loss.

### Two things to know about that container

**It has no volume.** `docker inspect sql_server_instance --format '{{.Mounts}}'` returns
`[]`. The databases live in the container's writable layer, so `docker rm
sql_server_instance` — or a `docker system prune -a` — **permanently destroys the local
schema**. Several stale `mcr.microsoft.com/mssql/server` containers tend to accumulate
alongside it, which makes an incautious cleanup sweep a real risk.

**The application tables live in `master`.** There is no separate `fyli` database; the ~49
tables sit in the `master` system database, which is why the connection string ends in
`Database=Master`. This is why the container cannot simply be backed up and restored onto a
fresh instance: `master` is a system database, and restoring it requires single-user mode
and a matching SQL Server build. Moving to a volume-backed instance means recreating the
schema, not copying it.

### Fresh machine, or migrating off the volumeless container

`docker-compose.yml` in the repo root defines a `fyli-sql` service with a named volume
(`fyli_sql_data`), so its databases survive container removal.

```bash
docker stop sql_server_instance   # port 1433 can only be bound once
docker compose up -d
```

It starts **empty**. Apply the schema before running tests:

```bash
cd cimplur-core/Memento
dotnet ef database update --project Domain --startup-project Memento
```

The image is amd64-only, so it runs under emulation on Apple Silicon; the compose file sets
`platform: linux/amd64` and allows a 90s `start_period` for first boot.

## Connection Configuration

- **Design-time** (migrations): reads `DatabaseConnection` from `cimplur-core/Memento/Domain/appsettings.json` via `DesignTimeDbContextFactory`
- **Runtime** (services): reads `DatabaseConnection` from environment variable (loaded from `.env`)
- **Tests**: `DatabaseConnection` env var if set, otherwise the localhost fallback hardcoded in `DomainTest/Repositories/BaseRepositoryTest.cs`

## Service Data Access Pattern

Services extend `BaseService`, which lazy-creates its own `StreamContext`:

```csharp
public class BaseService : IDisposable
{
    private StreamContext context;
    protected StreamContext Context
    {
        get
        {
            if (context == null)
            {
                var builder = new DbContextOptionsBuilder<StreamContext>();
                builder.EnableDetailedErrors(true);
                builder.UseSqlServer(Environment.GetEnvironmentVariable("DatabaseConnection"));
                context = new StreamContext(builder.Options);
            }
            return context;
        }
    }
}
```

Each service instance creates its own context. This means:
- Services read **committed** data only — they do not share a test transaction
- Tests that call service methods must commit data first (see test patterns in `MEMORY.md`)

## OnModelCreating Conventions

### Delete Behaviors
- **`DeleteBehavior.Restrict`** — default for most FKs (MemoryShareLinks, ExternalLogins, QuestionRequests, etc.)
- **`DeleteBehavior.NoAction`** — used when circular dependencies exist
- **`DeleteBehavior.Cascade`** — parent-child hierarchies only (Questions → QuestionSet, QuestionRequestRecipients → QuestionRequest)

### Composite Keys
Used for many-to-many join tables:
- `AlbumDrop` → `(AlbumId, DropId)`
- `TagViewer` → `(UserTagId, UserId)`
- `TimelineDrop` → `(TimelineId, DropId)`
- `SharingSuggestion` → `(OwnerUserId, SuggestedUserId)`

### Unique Indexes
- `MemoryShareLink.Token` (UNIQUEIDENTIFIER)
- `TimelineShareLink.Token` (UNIQUEIDENTIFIER)
- `QuestionRequestRecipient.Token` (UNIQUEIDENTIFIER)
- `ExternalLogin` → `(Provider, ProviderUserId)`
- `QuestionResponse` → `(QuestionRequestRecipientId, QuestionId)`
- `UserPrompt` → `(PromptId, UserId)`
- `UserRelationship` → `(UserId, Relationship)`
- `TimelineUser` → `(UserId, TimelineId)`
- `UserTag` → `(UserId, Name)` with filter `WHERE [Name] IS NOT NULL`

### JSON Columns
Some `UserProfile` fields store serialized JSON in large varchar columns:
- `CurrentNotifications` (varchar 8000)
- `CurrentTagIds` (varchar 4000)
- `CurrentPeople` (varchar 8000)

### Soft Deletes
Several entities use an `Archived` (BIT) flag rather than hard deletes:
- `Drop`, `UserTag`, `Album`, `QuestionSet`

## Entity Summary

The `StreamContext` defines 40+ DbSets. The core domain model is user-centric:

- **UserProfile** — central entity connecting everything
- **Drop** — primary content unit (memories)
- **UserUser / ShareRequest / MemoryShareLink** — sharing layer
- **Timeline / TimelineUser / TimelineDrop** — collections of drops
- **UserTag (Network) / TagViewer / TagDrop** — categorization
- **Prompt / UserPrompt / PromptTimeline** — drop creation workflows
- **QuestionSet / Question / QuestionRequest / QuestionRequestRecipient / QuestionResponse** — survey system
- **ExternalLogin** — OAuth providers (Google)
- **UserRole** — additive roles (`admin`); users with no rows are normal users
- **Ask** — in-product ask/bug submissions from Account
- **AdminAudit** — admin email-change history and dispute tokens
- **PremiumPlan / SharedPlan / Transaction** — subscriptions and billing

## Migration History

| Migration | Description |
|-----------|-------------|
| 20210502004355 | Initial schema |
| 20251207185045 | Transcode update |
| 20260201014219 | AddMemoryShareLinks |
| 20260206032422 | QuestionRequests (5 tables) |
| 20260209005943 | AddExternalLogin |
| 20260210222732 | AddTimelineShareLinks |
| 20260219192308 | AddCacheEntry (AI suggestion rate limiting) |
| 20260918015825 | AddUserRole |
| 20260918015900 | AddAsk |
| 20260918020101 | AddAdminAudit |
| 20260918032350 | AddDropSortIndexes (Drops.Created, Drops.Date — RESOURCE_SEMAPHORE fix) |
