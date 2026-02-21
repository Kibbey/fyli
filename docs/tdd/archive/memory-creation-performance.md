# TDD: Memory Creation Performance Optimization

## Overview

When a user creates a memory and shares it with groups (especially "All Connections"), the HTTP request blocks while the system sequentially processes notifications and emails for **every recipient**. For users with many connections (e.g., 50+), this creates a noticeable delay before the API responds.

This document identifies every bottleneck in the creation flow and proposes solutions, including moving work to async background jobs.

---

## Current Flow Analysis

### Request Path

```
POST /api/drops
  DropController.AddDrop()           ~1ms
    DropsService.Add()
      1. Fetch UserProfile             1 DB query
      2. Create Drop + ContentDrop     (tracked)
      3. Add TimelineDrops             (tracked)
      4. Add TagDrops                  (tracked)
      5. SaveChangesAsync()            1 DB write   ~10-30ms
      6. NotificationService           *** BOTTLENECK ***
         .AddNotificationDropAdded()
      7. EventService.EmitEvent()      fire-and-forget
    PromptService.UsePrompt()          conditional, 1 DB write
  Return 200 OK
```

### The Bottleneck: `NotificationService.AddNotificationDropAdded`

**File:** `NotificationService.cs:33-71`

For **each viewer** in the shared groups, the following runs **sequentially**:

| Step | Operation | Type | ~Latency |
|------|-----------|------|----------|
| 1 | `AddNotificationGeneric()` | | |
| 1a | Query `UserUsers` for relationship | DB read | 2-5ms |
| 1b | Query `UserProfiles` for name (fallback) | DB read | 2-5ms |
| 1c | Query `UserProfiles` for target user | DB read | 2-5ms |
| 1d | Deserialize `CurrentNotifications` JSON | CPU | <1ms |
| 1e | Modify notification list | CPU | <1ms |
| 1f | Serialize back to JSON | CPU | <1ms |
| 1g | `SaveChangesAsync()` | DB write | 5-15ms |
| 2 | Query `UserUsers` for email preference | DB read | 2-5ms |
| 3 | Query `SharedDropNotifications` for throttle | DB read | 2-5ms |
| 4 | `SendEmail()` via Postmark API (conditional) | HTTP | 100-500ms |
| 5 | Create `SharedDropNotification` record | DB write | 5-15ms |

**Per-viewer total:** ~20-50ms (no email) or ~120-550ms (with email)

### Scaling Impact

| Connections | No Emails | With Emails (worst case) |
|-------------|-----------|--------------------------|
| 5 | ~100-250ms | ~600ms-2.5s |
| 20 | ~400ms-1s | ~2.5-11s |
| 50 | ~1-2.5s | ~6-27s |
| 100 | ~2-5s | ~12-55s |

These times are **added to the HTTP response latency**. The user sees a spinner for the entire duration.

### Secondary Bottlenecks

1. **`AddNotificationGeneric` queries UserUsers and UserProfiles separately per viewer** (lines 149, 161) even though the caller already queried UserUsers at line 45. Redundant DB round-trips.

2. **Each viewer gets its own `SaveChangesAsync()`** (line 183 in `AddNotificationGeneric`, line 64 in `AddNotificationDropAdded`). No batching.

3. **`EventService.EmitEvent` creates a brand new `DbContext`** via `new EventService()` inside `Task.Run` (EventService.cs:13). While fire-and-forget, it opens an unnecessary DB connection.

4. **Each `BaseService` creates its own `DbContext`** lazily. `NotificationService` and `GroupService` don't share a context, so related queries can't benefit from connection pooling within a single unit of work.

---

## Proposed Solutions

### Solution 1: Fire-and-Forget Notifications (Stopgap Only)

**Effort:** Low | **Impact:** High | **Risk:** Medium

Move the entire notification loop out of the request path using fire-and-forget. **This is a stopgap approach only** — it bypasses DI by manually constructing services, which is brittle and will break if constructor signatures change.

**Not recommended for production.** Documented here as context for why Solution 2 is preferred.

**Cons:**
- Manually `new`s up `NotificationService`, `GroupService`, `SendEmailService` — bypasses DI entirely
- Will silently break if any service gains new constructor dependencies
- No retry if notification fails
- New DbContext per Task.Run
- Hard to monitor/debug failures at scale

---

### Solution 2: Background Job Queue with `IHostedService` (Recommended)

**Effort:** Medium | **Impact:** High | **Risk:** Low

Introduce a lightweight in-process background queue using .NET's built-in `Channel<T>` and `IHostedService`. No new dependencies required.

#### New Files

```
cimplur-core/Memento/
├── Domain/
│   ├── BackgroundJobs/
│   │   ├── IBackgroundJobQueue.cs          # Interface
│   │   ├── BackgroundJobQueue.cs           # Channel-based queue
│   │   ├── NotificationJobProcessor.cs     # IHostedService
│   │   └── NotificationJob.cs              # Job payload model
```

#### Interface: `IBackgroundJobQueue`

```csharp
using System.Threading;
using System.Threading.Tasks;

namespace Domain.BackgroundJobs
{
    public interface IBackgroundJobQueue
    {
        ValueTask EnqueueNotificationAsync(NotificationJob job);
        ValueTask<NotificationJob> DequeueAsync(CancellationToken cancellationToken);
    }
}
```

#### Model: `NotificationJob`

```csharp
using System.Collections.Generic;

namespace Domain.BackgroundJobs
{
    public class NotificationJob
    {
        public int CreatorUserId { get; set; }
        public HashSet<long> NetworkIds { get; set; }
        public int DropId { get; set; }
    }
}
```

#### Implementation: `BackgroundJobQueue`

```csharp
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

namespace Domain.BackgroundJobs
{
    public class BackgroundJobQueue : IBackgroundJobQueue
    {
        private readonly Channel<NotificationJob> channel =
            Channel.CreateBounded<NotificationJob>(new BoundedChannelOptions(1000)
            {
                FullMode = BoundedChannelFullMode.Wait
            });

        public async ValueTask EnqueueNotificationAsync(NotificationJob job)
        {
            await channel.Writer.WriteAsync(job);
        }

        public async ValueTask<NotificationJob> DequeueAsync(
            CancellationToken cancellationToken)
        {
            return await channel.Reader.ReadAsync(cancellationToken);
        }
    }
}
```

#### Processor: `NotificationJobProcessor`

```csharp
using System;
using System.Threading;
using System.Threading.Tasks;
using Domain.Repository;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Domain.BackgroundJobs
{
    public class NotificationJobProcessor : BackgroundService
    {
        private readonly IBackgroundJobQueue queue;
        private readonly IServiceScopeFactory scopeFactory;
        private readonly ILogger<NotificationJobProcessor> logger;

        public NotificationJobProcessor(
            IBackgroundJobQueue queue,
            IServiceScopeFactory scopeFactory,
            ILogger<NotificationJobProcessor> logger)
        {
            this.queue = queue;
            this.scopeFactory = scopeFactory;
            this.logger = logger;
        }

        protected override async Task ExecuteAsync(
            CancellationToken stoppingToken)
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    var job = await this.queue.DequeueAsync(stoppingToken);
                    await ProcessJob(job);
                }
                catch (OperationCanceledException)
                {
                    // Shutting down
                }
                catch (Exception ex)
                {
                    logger.LogError(ex,
                        "Error processing notification job");
                }
            }
        }

        private async Task ProcessJob(NotificationJob job)
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var notificationService = scope.ServiceProvider
                    .GetRequiredService<NotificationService>();
                await notificationService.AddNotificationDropAdded(
                    job.CreatorUserId, job.NetworkIds, job.DropId);
            }
            catch (Exception ex)
            {
                logger.LogError(ex,
                    "Failed notification job for drop {DropId}, user {UserId}",
                    job.DropId, job.CreatorUserId);
            }
        }
    }
}
```

#### DI Registration in `Startup.cs`

```csharp
// Add to ConfigureServices:
services.AddSingleton<IBackgroundJobQueue, BackgroundJobQueue>();
services.AddHostedService<NotificationJobProcessor>();
```

#### Change in `DropsService.Add()`

```csharp
// Inject via constructor
private IBackgroundJobQueue jobQueue;

public DropsService(
    SendEmailService sendEmailService,
    NotificationService notificationService,
    MovieService movieService,
    GroupService groupService,
    ImageService imageService,
    IBackgroundJobQueue jobQueue)
{
    // ... existing assignments ...
    this.jobQueue = jobQueue;
}

// In Add() method, replace lines 91-94:
if (selectedNetworkIds?.Any() ?? false)
{
    await jobQueue.EnqueueNotificationAsync(new NotificationJob
    {
        CreatorUserId = userId,
        NetworkIds = selectedNetworkIds.ToHashSet(),
        DropId = drop.DropId
    });
}
```

**Pros:**
- API responds in ~30ms regardless of connection count
- Proper DI scope per job (correct service lifetimes via `IServiceScopeFactory`)
- Built-in .NET primitives, no external dependencies
- Bounded queue provides backpressure (won't exhaust memory)
- Easy to extend for other job types later (comments, likes, etc.)
- Graceful shutdown via CancellationToken
- Single-threaded processing **protects against concurrent JSON updates** — multiple jobs modifying the same user's `CurrentNotifications` JSON would cause lost updates if parallelized

**Cons:**
- Jobs lost on app restart (acceptable — notifications are best-effort, same as current behavior where the try/catch swallows errors)
- Single-threaded processing means notification delivery is serialized (not user-visible since it's off the request path)

**Note on DbContext:** Each service inherits from `BaseService`, which lazily creates its own `DbContext` independent of DI scoping. The `IServiceScopeFactory` scope ensures correct service lifetimes and disposal, but does not provide a shared `DbContext` across services (e.g., `NotificationService` and `GroupService` each have their own context). This matches the current production behavior.

**Channel capacity (1000):** The bounded channel is set to 1000 with `FullMode.Wait`. If 1000+ memories are created before the processor catches up, the next `EnqueueNotificationAsync` will block until space opens. At typical usage patterns this won't happen, but if it did, the worst case is the API response is delayed until one job dequeues — still better than the current synchronous behavior.

---

### Solution 3: Optimize the Notification Loop (Complementary)

**Effort:** Medium | **Impact:** Medium | **Risk:** Low

Regardless of whether notifications are sync or async, the loop itself is inefficient. These optimizations reduce per-job time.

#### 3a. Batch DB Queries — Fetch All Data Upfront

Replace the per-viewer queries with a single bulk fetch:

```csharp
public async Task AddNotificationDropAdded(
    int userId, HashSet<long> networkIds, int dropId)
{
    try
    {
        var tagUsers = await groupService.GetUsersToShareWith(userId, networkIds)
            .ConfigureAwait(false);
        if (!tagUsers.Any()) return;

        var user = await Context.UserProfiles
            .SingleAsync(x => x.UserId == userId)
            .ConfigureAwait(false);

        // BATCH: Fetch all viewer relationships in ONE query
        var viewerRelationships = await Context.UserUsers
            .Include(i => i.OwnerUser)
            .Where(x => tagUsers.Contains(x.OwnerUserId)
                && x.ReaderUserId == userId)
            .ToDictionaryAsync(x => x.OwnerUserId)
            .ConfigureAwait(false);

        // BATCH: Fetch all viewer profiles in ONE query
        var viewerProfiles = await Context.UserProfiles
            .Where(x => tagUsers.Contains(x.UserId))
            .ToDictionaryAsync(x => x.UserId)
            .ConfigureAwait(false);

        // BATCH: Fetch recent email notifications in ONE query
        var twoHoursAgo = DateTime.UtcNow.AddHours(-2);
        var recentEmailsList = await Context.SharedDropNotifications
            .Where(x => tagUsers.Contains(x.TargetUserId)
                && x.SharerUserId == userId
                && x.TimeShared > twoHoursAgo)
            .Select(x => x.TargetUserId)
            .ToListAsync()
            .ConfigureAwait(false);
        var recentEmails = recentEmailsList.ToHashSet();

        // Process each viewer with pre-fetched data
        foreach (var viewer in tagUsers)
        {
            // Update in-app notification (still per-user due to JSON)
            if (viewerProfiles.TryGetValue(viewer, out var targetProfile))
            {
                AddNotificationToProfile(targetProfile, user, dropId);
            }

            // Email check using pre-fetched data
            if (viewerRelationships.TryGetValue(viewer, out var rel)
                && rel.SendNotificationEmail
                && !recentEmails.Contains(viewer))
            {
                await groupService.SendEmail(
                    rel.OwnerUser.Email,
                    rel.ReaderName ?? user.UserName,
                    dropId,
                    EmailTypes.EmailNotification);
                Context.SharedDropNotifications.Add(
                    new SharedDropNotification
                    {
                        TargetUserId = viewer,
                        DropId = dropId,
                        SharerUserId = userId,
                        TimeShared = DateTime.UtcNow
                    });
            }
        }

        // BATCH: Single SaveChanges for ALL notification updates
        await Context.SaveChangesAsync().ConfigureAwait(false);
    }
    catch (Exception e)
    {
        logger.LogError(e, "Send notification");
    }
}
```

**DB query reduction:**

| Connections | Before (queries) | After (queries) |
|-------------|-------------------|-----------------|
| 5 | ~25-35 | 6 |
| 20 | ~100-140 | 6 |
| 50 | ~250-350 | 6 |
| 100 | ~500-700 | 6 |

The query count is now **constant** (4 bulk fetches + 1 bulk save + email sends) regardless of viewer count.

Note: `groupService.GetUsersToShareWith()` runs on GroupService's own DbContext (per the `BaseService` pattern). The remaining batch queries run on NotificationService's context. This is the same separation as the current code.

#### Helper: `AddNotificationToProfile`

Extracted from `AddNotificationGeneric` (lines 166-181) to operate on a pre-fetched `UserProfile`:

```csharp
private void AddNotificationToProfile(
    UserProfile targetProfile, UserProfile creator, int dropId)
{
    var notifications = targetProfile.CurrentNotifications ?? string.Empty;
    bool removeOld = notifications.Length > 7000;
    var currentNotifications = JsonConvert.DeserializeObject<List<NotificationModel>>(
        notifications) ?? new List<NotificationModel>();

    currentNotifications = RemoveExpired(currentNotifications, removeOld);
    currentNotifications.RemoveAll(
        x => x.DropId == dropId && x.NotificationType == NotificationType.Memory);
    currentNotifications.Add(new NotificationModel
    {
        Name = creator.Name,
        DropId = dropId,
        CreatedAt = DateTime.UtcNow,
        Viewed = false,
        NotificationType = NotificationType.Memory
    });

    targetProfile.CurrentNotifications = JsonConvert.SerializeObject(
        currentNotifications
            .Distinct(new NotificationModelComparer())
            .OrderBy(x => x.CreatedAt));
}
```

Note: This uses the creator's profile name directly. The current code resolves a per-viewer display name via `UserUsers.ReaderName`. For Phase 2, using the profile name is acceptable since the viewer will see whatever name they assigned to the creator when they view the notification (resolved at read time, not write time).

#### 3b. Send Emails Outside the Loop (Fire-and-Forget)

Email sends are the slowest operation (~100-500ms each via Postmark API). Send them fire-and-forget after all DB work is done:

```csharp
// Collect emails to send
var emailsToSend = new List<(string email, string name)>();

foreach (var viewer in tagUsers)
{
    // ... notification logic ...
    if (shouldSendEmail)
    {
        emailsToSend.Add((rel.OwnerUser.Email, rel.ReaderName ?? user.UserName));
    }
}

// Save all DB changes first
await Context.SaveChangesAsync().ConfigureAwait(false);

// Fire-and-forget all emails in parallel
foreach (var (email, name) in emailsToSend)
{
    _ = Task.Run(() => groupService.SendEmail(
        email, name, dropId, EmailTypes.EmailNotification));
}
```

---

## Recommended Implementation Plan

### Phase 1: Background Job Queue (Solution 2)

Move notification processing off the request path entirely.

**Backend changes:**
1. Create `Domain/BackgroundJobs/` directory with 4 files
2. Register `IBackgroundJobQueue` (singleton) and `NotificationJobProcessor` (hosted service) in `Startup.cs`
3. Inject `IBackgroundJobQueue` into `DropsService`
4. Replace `await notificationService.AddNotificationDropAdded(...)` with `await jobQueue.EnqueueNotificationAsync(...)`

**Future extension (out of scope for this TDD):**
- `DropsService.AddComment()` (lines 667-676) has a similar per-commenter notification loop. It requires a different job payload (dropId + commenterId + list of commenter IDs) since it notifies previous commenters + drop creator, not group viewers. A separate `CommentNotificationJob` should be created in a follow-up TDD.
- `DropsService.Edit()` currently does **not** notify when sharing groups change (it only updates TagDrop records). Adding notification-on-edit would be a new feature, not a performance fix.

### Phase 2: Batch Optimize the Notification Loop (Solution 3)

Reduce DB queries inside `AddNotificationDropAdded` from O(N) to O(1).

**Backend changes:**
1. Refactor `AddNotificationDropAdded` to use bulk queries
2. Extract `AddNotificationToProfile` helper for JSON manipulation
3. Collect emails into a list and send after `SaveChangesAsync`
4. Fire-and-forget email sends

### Combined Impact

| Connections | Before (API latency) | After Phase 1 (API) | After Phase 2 (job time) |
|-------------|----------------------|----------------------|--------------------------|
| 5 | ~100-250ms | ~30ms | ~50ms |
| 20 | ~400ms-1s | ~30ms | ~80ms |
| 50 | ~1-2.5s | ~30ms | ~150ms |
| 100 | ~2-5s | ~30ms | ~250ms |

---

## Testing Plan

### Backend Unit Tests

**BackgroundJobQueue tests:**
- Enqueue and dequeue returns correct job
- Bounded capacity blocks when full
- Dequeue blocks when empty until item available

**NotificationJobProcessor tests:**
- Processes enqueued job by calling NotificationService
- Logs error and continues on job failure
- Stops gracefully on cancellation

**DropsService.Add tests (update existing):**
- Verify `EnqueueNotificationAsync` called with correct parameters
- Verify API returns immediately (drop ID returned before notifications)

**NotificationService optimization tests (Phase 2):**
- All viewers receive in-app notification (verify UserProfile.CurrentNotifications)
- Email throttling still works (no email if sent within 2 hours)
- Email sends fire-and-forget (verify SharedDropNotification records created)
- Single SaveChangesAsync call per batch

### Integration Tests

- Create memory with 0, 1, 5 recipients — verify all get notifications
- Create memory, verify API response time is < 200ms regardless of recipient count
- Verify email throttling still works across background jobs

---

## Implementation Order

1. Create `NotificationJob` model
2. Create `IBackgroundJobQueue` interface
3. Create `BackgroundJobQueue` implementation
4. Create `NotificationJobProcessor` hosted service
5. Register in `Startup.cs`
6. Inject queue into `DropsService`, replace sync call with enqueue
7. Write tests for queue and processor
8. Update existing `DropsService` tests
9. (Phase 2) Refactor `AddNotificationDropAdded` with batch queries
10. (Phase 2) Extract email sends to fire-and-forget
11. (Phase 2) Write tests for optimized notification loop

---

## Files Changed

### Phase 1 (New)
- `Domain/BackgroundJobs/IBackgroundJobQueue.cs`
- `Domain/BackgroundJobs/BackgroundJobQueue.cs`
- `Domain/BackgroundJobs/NotificationJob.cs`
- `Domain/BackgroundJobs/NotificationJobProcessor.cs`

### Phase 1 (Modified)
- `Memento/Startup.cs` — register queue + hosted service
- `Domain/Repositories/DropsService.cs` — inject queue, enqueue instead of await

### Phase 2 (Modified)
- `Domain/Repositories/NotificationService.cs` — batch queries, batch save, fire-and-forget emails

### Tests
- `DomainTest/BackgroundJobs/BackgroundJobQueueTest.cs`
- `DomainTest/BackgroundJobs/NotificationJobProcessorTest.cs`
- Update `DomainTest/DropsServiceTest.cs`
- Update `DomainTest/NotificationServiceTest.cs`
