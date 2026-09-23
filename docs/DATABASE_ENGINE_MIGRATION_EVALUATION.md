# Evaluation: Migrating off SQL Server (Postgres vs MySQL)

**Date:** 2026-09-19
**Status:** Proposal — for review, not approved
**Author:** drafted with Claude, from a read of `cimplur-core` at commit `a5c3d07`

---

## 1. Recommendation

**Move to PostgreSQL.** Not MySQL, and not as an emergency.

The performance crisis that would have forced a rushed decision is **resolved** — a
combination of missing indexes, poor query patterns, and SQL Server Express being
unable to function on a `db.t3.small`. That removes all time pressure and changes
this from a firefight into a planned cost-and-headroom decision, which is the right
way to do an engine migration.

The remaining case for moving is narrower but still real, and is laid out in §3.

**Acceptance criterion for the whole project:** the end-user experience must be
*byte-for-byte identical*. Internals are free to change — schema shapes, migration
history, index definitions, type mappings, ORM provider, test harness, ops tooling.
Anything a user can see — login behaviour, memory dates, list ordering, who can see
which memory — must not move. §6 is the risk register built around exactly that line.

---

## 2. What changed, and why the old framing was wrong

The earlier version of this analysis treated the engine migration as a possible fix
for the production `GetTimeline` timeouts. That framing is now dead, and it was the
wrong framing anyway:

- The fix (per `docs/investigations/2026-09-09-gettimeline-sql-timeout.md`, Final
  Resolution) was three changes in combination: the missing `Drops.Date` /
  `Drops.Created` sort indexes, the `Union` rewrite of the permission predicate, and
  the `t3.small` → `t3.medium` resize. No one of them was sufficient alone.
- Two of those three were **query and schema problems, not engine problems**. They
  would have followed us onto Postgres unchanged. Migrating first would have masked
  them and made all three harder to diagnose at once.

Having fixed them first, we now have a known-good performance baseline on SQL Server.
That baseline is what makes a safe migration possible: any regression after the
cutover is attributable to the engine change, because nothing else is in flight.

> **Housekeeping:** the investigation doc still reads
> `ROOT CAUSE IDENTIFIED ... not yet applied to prod` and `Date resolved: reopened`.
> It should be closed out with the final fix and confirmation, independently of this
> proposal. Right now it is the most misleading document in the repo.

---

## 3. The cost case (now the only case)

The premise "SQL Server costs more" is true, but not for the reason it first appears.

Production today is `db.t3.medium` (resized from `t3.small` as part of the performance
fix) running **`sqlserver-ex` — SQL Server Express**, which is *license-free*. We are
not paying a SQL Server licence bill right now. What we are paying is a capability tax:

| Express limit | Value | Consequence |
|---|---|---|
| Buffer pool | **1410 MB** | Hard cap regardless of instance size. The `t3.medium` resize gave the OS enough headroom for the engine to finally *reach* this cap — it did not raise it. Scaling further buys RAM the engine refuses to use. |
| Database size | **10 GB** | A wall, not a slowdown. Writes fail when hit. |
| CPU | 1 socket / 4 cores | Not currently binding. |

So the real decision is:

- **Stay on SQL Server** → the only route past the 1410 MB and 10 GB ceilings is
  **Standard Edition, licence-included on RDS**. Order of **$300–500/mo** at the
  smallest instance class SE permits. *(Ballpark — re-price against current AWS
  rates before anyone commits to a number.)*
  The `t3.medium` resize has already consumed the cheap headroom on this path; there
  is no further no-cost move left on Express.
- **Move to Postgres** → `db.t4g.medium`, **~$50/mo**, no licence,
  100% of instance RAM usable by the engine, no database size ceiling.

That is roughly an order of magnitude, not a rounding error.

### The forcing function is the 10 GB cap, not the money

Money alone would not justify this project. The 10 GB Express database limit would.
It is a hard stop that we *will* hit as memories, comments, and media metadata
accumulate, and hitting it means write failures, not degraded latency.

**This should be quantified before anything else happens.** Current database size
against 10 GB, plus the observed monthly growth rate, converts this from an opinion
into a date. That date is the only input that should determine the project's
priority. See §9.

---

## 4. Postgres, not MySQL

Not a close call, for reasons specific to this codebase:

1. **Provider quality.** Npgsql's EF Core provider is first-tier and tracks EF Core
   releases closely. Pomelo (MySQL) is community-maintained and lags. We are on EF
   Core 9.0.8 and will want 10.
2. **The query shapes we actually run.** `GetAllDrops` is a three-way `OR` of
   correlated `EXISTS` subqueries, followed by `OFFSET`/`FETCH` paging and a nested
   collection projection. Postgres handles this with hash semi-joins and bitmap OR.
   MySQL's optimiser has historically been weak at precisely that combination.
3. **Type mapping is nearly free.**

   | SQL Server | Postgres | MySQL |
   |---|---|---|
   | `nvarchar(max)` | `text` (UTF-8 native, no length cost) | `longtext` |
   | `uniqueidentifier` | native `uuid` | no UUID type — `binary(16)`/`char(36)` |
   | `bit` | native `boolean` | no real boolean — `tinyint(1)` |
   | `datetime2` | `timestamptz` / `timestamp` | `datetime(6)` |

4. **Index features we need.** Postgres has partial indexes, expression indexes, and
   covering `INCLUDE` indexes (v11+) — the toolkit the timeline access patterns
   benefit from.
5. **Minor but telling.** The single piece of raw SQL in the codebase
   (`Memento/Domain/Repositories/MemoryShareLinkService.cs:85`) already uses
   double-quoted identifiers — Postgres syntax. MySQL would need backticks.

---

## 5. Migration surface — why this is smaller than it looks

Verified by reading the code, not assumed:

| Dimension | Finding |
|---|---|
| Raw SQL in application code | **One statement**, `MemoryShareLinkService.cs:85` |
| Stored procs / triggers / views / full-text | **None** |
| Dapper or other second data access path | **None** |
| Provider-specific model config | **One** — `HasDefaultValueSql("GETUTCDATE()")`, `StreamContext.cs:304` |
| Provider call sites | **Two** — `BaseRepositoryTest.cs:29`, plus `BaseService` |
| Entities / DbSets | 47 / 48, all plain code-first POCOs |
| Domain LOC (excl. migrations) | 14,187 |
| Test suite | **419 tests against a real database** |

That last row is the most important line in this document. The test suite is an
integration suite, not mocks — it will catch the large majority of LINQ-translation
regressions the moment the provider is flipped. Most projects attempting this have
no such safety net.

**Existing EF migrations are not an obstacle.** All 27 are SQL-Server-shaped
(`nvarchar`, `datetime2`), but production has never run `dotnet ef database update` —
it applies hand-generated SQL scripts. The migrations therefore have no production
role to preserve. They get **deleted and squashed into a single `InitialPostgres`**
generated from the current model. This is invisible to users and is the standard play.

The 13 scripts in `docs/migrations/` are one-shot history (`IF OBJECT_ID`,
`IDENTITY(1,1)`, `GO`, `sys.indexes`). Only `IndexDriftAudit.sql` is an ongoing tool
and needs a `pg_indexes` rewrite.

---

## 6. Risk register — what could leak to the end user

Everything in §5 is internal and safe. This section is the part that matters, ordered
by user-visible blast radius.

### R1 — Case sensitivity breaks login and account recovery 🔴 CRITICAL

SQL Server's default collation (`SQL_Latin1_General_CP1_CI_AS`) is case-**insensitive**.
Postgres is case-**sensitive**. Today `Josh@X.com` matches a stored `josh@x.com`.
After a naive cutover it silently stops matching.

Affected call sites (~95 string comparisons in `Repositories/` overall):

```
UserService.cs:48   x.UserName == userName
UserService.cs:353  x.Email.Equals(email)
UserService.cs:411  x.Email.Equals(email)
UserService.cs:416  x.Email.Equals(email)
UserService.cs:594  x.Email.Equals(email)
UserService.cs:616  x.Email.Equals(email)
```

This reaches account lookup, magic-link login, and share-link claim. It fails
*quietly* — the user is told no such account exists rather than seeing an error.

**Mitigation:** `citext` extension (or a non-deterministic ICU collation) on email
and username columns. **Before migrating, audit production for rows that are
duplicates-by-case** — `citext` will make a previously-legal pair collide and the
load will fail, or worse, succeed against the wrong row.

**Related finding:** `UserService.cs:422` and `:456` use
`Email.Equals(email, StringComparison.OrdinalIgnoreCase)`. EF Core cannot translate
that overload on *any* provider — worth confirming whether these are silently
client-evaluating today, which would be a pre-existing bug independent of this project.

### R2 — Permission-graph fidelity during data migration 🔴 CRITICAL

`CLAUDE.md` requires that access to drops be 100% preserved. The `TagViewer` /
`UserDrop` / `TimelineDrop` graph decides who can see which memory. An error here is
both unrecoverable and the worst possible user-visible outcome — someone loses access
to their own memories, or sees someone else's.

**This is the riskiest part of the entire project, and it is in the data migration,
not the code port.**

**Mitigation:** per-table row-count diffs, plus a *semantic* check — for a sample of
users, compute the exact set of accessible drop IDs on both engines and assert
equality. Rehearse the full migration at least twice against a production copy.

### R3 — Sort order changes visibly 🟠 HIGH

Two distinct problems, both user-visible in album, group, timeline, and connection lists:

**(a) Collation ordering.** SQL Server's `CI_AS` sorts case-insensitively.
Postgres under the `C` collation sorts uppercase before lowercase, so a list that
reads `album, Beta, cat` today becomes `Beta, album, cat`.
*Mitigation:* use an ICU collation (`en-US-x-icu`) as the database default to match
current behaviour, rather than `C`.

**(b) NULL ordering.** SQL Server places NULLs **first** on `ASC`; Postgres places
them **last**. This bites wherever a nullable column is ordered server-side:

```
AlbumService.cs:26   .OrderBy(x => x.Name)     — Name is nullable, server-side
GroupService.cs:412  .OrderBy(x => x.Name)     — returns IQueryable, server-side
```

*Mitigation:* explicit `NULLS FIRST`, or normalise the nulls. Note that many of the
81 ordering sites are client-side (`.ToList().OrderBy(...)`, LINQ-to-Objects) and are
therefore unaffected — each needs classifying, not blanket-fixing.

`DropsService.cs:337` orders by `Drop.Date`, which is non-nullable — **the main
timeline ordering is safe.** `PlanService`'s `ExpirationDate` is likewise non-nullable.

### R4 — Dates shift or throw 🟠 HIGH

Npgsql maps `DateTime` to `timestamptz` and **throws** on a non-UTC `DateTimeKind`.
The Domain layer has **13 `DateTime.Now`** and **116 `DateTime.UtcNow`**. Each of
those 13 is a runtime exception waiting for the cutover.

Beyond the exceptions, memory dates are sentimental, user-entered, and displayed. A
memory dated 1998 rendering one day off is a visible, upsetting regression.

**Mitigation:** either standardise on `UtcNow` throughout, or globally map to
`timestamp without time zone` to preserve exact current semantics. Given the
identical-experience requirement, **the second is the safer default** — it changes
nothing about how dates round-trip. Also port the `GETUTCDATE()` default at
`StreamContext.cs:304` to `now() at time zone 'utc'`.

### R5 — Identity sequences not reseeded 🟠 HIGH

The classic post-migration corruption: data loads fine, then the first new insert
collides with an existing key or the save fails outright. Every identity column needs
an explicit `setval` after load, verified.

### R6 — Unicode and emoji in memory content 🟡 MEDIUM

`nvarchar` → `text` is clean in principle, but the dump/load pipeline must be
end-to-end UTF-8. Emoji in memory text and comments is near-certain in this product.
**Mitigation:** include emoji and non-Latin text in the rehearsal fixture set and
round-trip them explicitly.

### R7 — Query plans differ; performance must be re-earned 🟡 MEDIUM

The index set that is now correct for SQL Server will not be optimal for Postgres.
The recently-fixed timeline path must be re-benchmarked and re-tuned after cutover.
**This does not mean it will be slower** — with the full instance RAM available
instead of 1410 MB, the headroom is considerably better. But it is not automatic, and
"we fixed performance already" does not transfer for free.

Note also that EF 9 parameterises `Contains()` via `OPENJSON` on SQL Server and
`= ANY(@p)` on Postgres. The Postgres form is generally better, but plans will change.

The specific thing to re-verify after cutover is the `Union`-rewritten `GetAllDrops`
(`DropsService.cs:553-554`). It was shaped to stop the SQL Server optimizer falling
back to a scan of `Drops`. Postgres's planner makes that choice differently, so the
rewrite may be unnecessary there — or may need a different shape. Benchmark it rather
than assuming it carries over.

---

## 7. Phased plan

**Phase 0 — ~~fix the query~~ ✅ DONE.** Indexes, the `Union` rewrite, and instance
sizing resolved; investigation closed 2026-09-19. This phase existed to establish a
clean performance baseline before changing engines; that baseline now exists.

> The closeout records four items that did **not** ship — chiefly that
> `GetTimelineDrops` still drives from `GetAllDrops` rather than from `TimelineDrops`.
> Those are complexity problems that will follow us onto Postgres unchanged. Not
> blockers for this project, but they should not be *expected* to be fixed by it.

**Phase 1 — Quantify the forcing function.** Measure current database size against
the 10 GB Express cap and the monthly growth rate. **Do this before committing
engineering time** — it determines whether this is a Q4 project or a next-year
project. One afternoon of work.

**Phase 2 — Portability prep, still on SQL Server, shippable today.**
Normalise `DateTime.Now` → `UtcNow`. Replace the untranslatable `StringComparison`
overloads. Make email/username lookups explicitly case-normalised in code.
Classify the 81 ordering sites into server-side and client-side.
Every one of these is independently testable against the existing suite on the
existing database, and each ships to production on its own. **This is the phase that
de-risks the whole project, and it has value even if we never migrate.**

**Phase 3 — Dual-provider build.** Add `Npgsql.EntityFrameworkCore.PostgreSQL`. Make
provider selection config-driven in `BaseService` and `BaseRepositoryTest:29`. Squash
the 27 migrations into one Postgres-only initial. Add `postgres:17` to the compose
file. Choose and apply the ICU collation and `citext` decisions from R1 and R3.

**Phase 4 — Green the suite on Postgres.** The bulk of the effort, and where the
unknown unknowns surface. All 419 tests must pass.

**Phase 5 — Data migration rehearsal.** `pgloader` or a purpose-built dotnet script.
Per-table row-count diff; **the R2 semantic permission check**; sequence reseed
verification; R6 Unicode round-trip. Run the real application against the loaded
copy. **Rehearse at least twice.**

**Phase 6 — Cutover.** Read-only window, final delta sync, flip the connection
string. Keep the SQL Server instance **stopped, not deleted**, for 2–4 weeks.

**Phase 7 — Retune.** `ANALYZE`, enable `pg_stat_statements`, re-benchmark the
timeline path against the Phase 0 baseline, adjust indexes.

**Estimate:** 2–4 weeks part-time for one person, dominated by Phases 4 and 5.
The absence of stored procs, triggers, views, full-text search, and any second data
access path is what keeps this cheap.

---

## 8. Downsides and honest arguments against

- **The dollar saving is modest in absolute terms today.** We are on free Express.
  The ~$300–450/mo saving only materialises in the counterfactual where we would
  otherwise have upgraded to Standard Edition. If we never would have, the migration
  saves roughly $10–25/mo and the case rests entirely on the 10 GB cap.
- **We lose tooling we are demonstrably good at.** The GetTimeline investigation shows
  real SQL Server depth — wait types, memory grants, `sys.dm_exec_requests`, SSMS.
  That knowledge does not transfer 1:1. `pg_stat_activity` and
  `EXPLAIN (ANALYZE, BUFFERS)` are as capable, but there will be a period of being a
  beginner again, on production.
- **Documentation debt.** `docs/DATABASE_GUIDE.md` contains an explicit
  "SQL Server syntax, NOT PostgreSQL" mapping table that inverts wholesale. The
  migration scripts and investigation docs become historical artifacts.
- **The identical-experience requirement is strict, and R1/R3 are exactly the kind of
  regression that passes code review and fails in production.** Case-insensitive
  matching and collation ordering are invisible until a real user with a
  mixed-case email tries to log in.
- **Risk is concentrated in the data migration, not the code.** The code port is well
  understood and well tested. The one-shot, hard-to-reverse step is moving the
  permission graph (R2).
- **Doing nothing is a legitimate option right now.** Performance is fixed. If the
  database-size runway measured in Phase 1 turns out to be years, the correct call is
  to ship Phase 2 (which is pure hygiene and independently valuable) and revisit.

---

## 9. Open questions for review

1. **What is the current database size, and the monthly growth rate?** This is the
   single input that sets the project's priority. Nothing else should be decided
   until it is known.
2. **Would we actually pay for SQL Server Standard Edition if forced?** If the honest
   answer is no, the migration is inevitable and should be scheduled rather than
   debated.
3. **Do we accept `timestamp without time zone` (preserving exact current date
   semantics) over `timestamptz` (more correct, but a behaviour change)?** The
   identical-experience requirement argues for the former.
4. **Are there any mixed-case duplicate emails in production today?** Determines
   whether R1's mitigation is clean or needs a data-repair step first.
5. **Who owns the Phase 5 rehearsal sign-off?** This is the irreversible step.
