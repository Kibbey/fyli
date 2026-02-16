# TDD: Move Multi-Recipient Email Sends to Background Jobs

## Problem

Multiple email-sending callsites use unsafe patterns that cause production errors:

1. **`Task.Run()` fire-and-forget** — Runs email sending after the HTTP request scope disposes the `DbContext`, causing "The connection is closed" errors (confirmed production bug in `QuestionService.CreateQuestionRequest`)
2. **Unawaited `.SendAsync()` calls** — Fire-and-forget without even `Task.Run`, same disposed-scope risk
3. **Multi-recipient loops blocking request** — Even the now-fixed `CreateQuestionRequest` awaits N emails sequentially, slowing the API response proportional to recipient count

## Existing Infrastructure

The codebase already has a working background job queue:

- **`IBackgroundJobQueue`** — Channel-based bounded queue (capacity 1000)
- **`NotificationJobProcessor`** — `BackgroundService` that dequeues jobs and processes them in a **fresh DI scope** via `IServiceScopeFactory.CreateScope()`, which gives each job a new `DbContext`
- **Currently only handles `NotificationJob`** (drop-added notifications)

## Solution

Generalize the background job queue to also handle email jobs. Add an `EmailJob` model and an `EmailJobProcessor` that creates a fresh DI scope per job — same proven pattern as `NotificationJobProcessor`.

## Audit: All Email Callsites

| # | Location | Email Type | Multi? | Current Pattern | Action |
|---|----------|-----------|--------|-----------------|--------|
| 1 | `QuestionService.CreateQuestionRequest:354` | QuestionRequestNotification | **YES** | awaited in loop (just fixed) | **Move to job** |
| 2 | `QuestionService.SubmitAnswer:618` | QuestionAnswerNotification | No | awaited (just fixed) | **Move to job** (was Task.Run) |
| 3 | `DropsService.AddComment:688` | CommentEmail | **YES** | `Task.Run` in loop | **Move to job** |
| 4 | `DropsService.Thank:630` | ThankEmail | No | `Task.Run` | **Move to job** (was Task.Run) |
| 5 | `PromptService.AskQuestion:266` | Question | **YES** | unawaited in `.ForEach` | **Move to job** |
| 6 | `SharingService.RequestConnection:162` | ConnectionRequest* | No | unawaited | **Move to job** (same scope risk) |
| 7 | `SharingService.RequestConnection:168` | InviteNotice | No | unawaited | **Move to job** (same scope risk) |
| 8 | `SharingService.RequestReminder:199` | ConnectionRequest* | No | unawaited | **Move to job** (same scope risk) |
| 9 | `SharingService.ConfirmSharingRequest:376` | ConnecionSuccess | No | `Task.Run` | **Move to job** |
| 10 | `PlanController.AddPremiumPlan:68-69` | Receipt, PaymentNotice | No | unawaited x2 | **Move to job** |
| 11 | `ContactService.SendEmailToUsers:32` | Fyli | **YES** | awaited in loop | **Move to job** (broadcast) |
| 12 | `NotificationService.AddNotificationDropAdded:57` | EmailNotification | **YES** | awaited via groupService | Leave (already runs in job queue via `NotificationJobProcessor`) |
| 13 | `GroupService.SendEmail:590` | EmailNotification | No | awaited | Leave (called by NotificationService which already runs in job queue) |
| 14 | `UserService.SendClaimEmail:315` | ClaimEmail | No | awaited | Leave (single, no scope issue) |
| 15 | `ShareLinkController.SignIn:104` | Login | No | awaited | Leave (single, user-facing magic link) |
| 16 | `UserController.CreatePassword:111` | Login | No | awaited | Leave (single, user-facing magic link) |
| 17 | `TimelineShareLinkController.SignIn:103` | Login | No | awaited | Leave (single, user-facing magic link) |
| 18 | `ContactService.SendMessage:19` | Contact | No | awaited | Leave (single, admin notification) |
| 19 | `SharingService.FindAndEmailSuggestions:646-664` | Requests/Suggestions/QuestionReminders | No | awaited | Leave (called from scheduled job) |
| 20 | `NotificationService.AddNotificationGeneric:187` | Variable | No | awaited | Leave (called within request scope, single) |
| 21 | `QuestionReminderJob.ProcessReminders:72` | QuestionRequestReminder | **YES** | awaited in loop | Leave (already a background job) |

**Items 1-11 move to background job. Items 12-21 are safe — already in jobs, single-user, or user-facing (magic links must be synchronous).**

## Phase 1: Email Job Infrastructure

### 1.1 Create `EmailJob` model

**File:** `Domain/BackgroundJobs/EmailJob.cs`

```csharp
using static Domain.Emails.EmailTemplates;

namespace Domain.BackgroundJobs
{
    public class EmailJob
    {
        public string Email { get; set; }
        public EmailTypes EmailType { get; set; }
        public Dictionary<string, object> Model { get; set; }
    }
}
```

Use the `EmailTypes` enum directly since the queue is in-memory (no serialization boundary). `Dictionary<string, object>` for the model keeps it decoupled from anonymous types.

### 1.2 Add email methods to `IBackgroundJobQueue`

**File:** `Domain/BackgroundJobs/IBackgroundJobQueue.cs`

```csharp
public interface IBackgroundJobQueue
{
    // Existing
    ValueTask EnqueueNotificationAsync(NotificationJob job);
    ValueTask<NotificationJob> DequeueAsync(CancellationToken cancellationToken);

    // New
    ValueTask EnqueueEmailAsync(EmailJob job);
    ValueTask<EmailJob> DequeueEmailAsync(CancellationToken cancellationToken);
}
```

### 1.3 Add email channel to `BackgroundJobQueue`

**File:** `Domain/BackgroundJobs/BackgroundJobQueue.cs`

Add a second `Channel<EmailJob>` alongside the existing `Channel<NotificationJob>`:

```csharp
public class BackgroundJobQueue : IBackgroundJobQueue
{
    private readonly Channel<NotificationJob> _channel = ...;

    private readonly Channel<EmailJob> _emailChannel =
        Channel.CreateBounded<EmailJob>(new BoundedChannelOptions(1000)
        {
            FullMode = BoundedChannelFullMode.Wait
        });

    // Existing methods unchanged...

    public async ValueTask EnqueueEmailAsync(EmailJob job)
    {
        await _emailChannel.Writer.WriteAsync(job);
    }

    public async ValueTask<EmailJob> DequeueEmailAsync(CancellationToken cancellationToken)
    {
        return await _emailChannel.Reader.ReadAsync(cancellationToken);
    }
}
```

### 1.4 Create `EmailJobProcessor`

**File:** `Domain/BackgroundJobs/EmailJobProcessor.cs`

Same pattern as `NotificationJobProcessor` — fresh DI scope per job:

```csharp
public class EmailJobProcessor : BackgroundService
{
    private readonly IBackgroundJobQueue _queue;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<EmailJobProcessor> _logger;

    public EmailJobProcessor(
        IBackgroundJobQueue queue,
        IServiceScopeFactory scopeFactory,
        ILogger<EmailJobProcessor> logger)
    {
        _queue = queue;
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var job = await _queue.DequeueEmailAsync(stoppingToken);
                await ProcessJob(job);
            }
            catch (OperationCanceledException) { }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing email job");
            }
        }
    }

    protected virtual async Task ProcessJob(EmailJob job)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var emailService = scope.ServiceProvider.GetRequiredService<SendEmailService>();
            var model = DictionaryToExpando(job.Model);
            await emailService.SendAsync(job.Email, job.EmailType, model);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send {EmailType} to {Email}", job.EmailType, job.Email);
        }
    }

    private static ExpandoObject DictionaryToExpando(Dictionary<string, object> dict)
    {
        var expando = new ExpandoObject();
        var expandoDict = (IDictionary<string, object>)expando;
        foreach (var kvp in dict)
            expandoDict[kvp.Key] = kvp.Value;
        return expando;
    }
}
```

### 1.5 Register in DI

**File:** `Memento/Startup.cs`

```csharp
// Existing
services.AddSingleton<IBackgroundJobQueue, BackgroundJobQueue>();
services.AddHostedService<NotificationJobProcessor>();
// New
services.AddHostedService<EmailJobProcessor>();
```

## Phase 2: Migrate Callsites

For each callsite, replace the direct `sendEmailService.SendAsync()` call with `jobQueue.EnqueueEmailAsync()`. The job queue is injected as `IBackgroundJobQueue jobQueue = null` (optional, for test compatibility).

### 2.1 QuestionService — inject `IBackgroundJobQueue`

Add to constructor: `IBackgroundJobQueue jobQueue = null`

#### CreateQuestionRequest (line ~354)

**Before:**
```csharp
try
{
    await sendEmailService.SendAsync(recipientEmail, EmailTypes.QuestionRequestNotification,
        new { User = creator.Name, Question = firstQuestion, AnswerLink = answerLink });
}
catch (Exception ex)
{
    logger.LogError(ex, "Failed to send question request email to {Email}", recipientEmail);
}
```

**After:**
```csharp
await EnqueueEmail(recipientEmail, EmailTypes.QuestionRequestNotification,
    new Dictionary<string, object>
    {
        ["User"] = creator.Name,
        ["Question"] = firstQuestion,
        ["AnswerLink"] = answerLink
    });
```

#### SubmitAnswer (line ~618)

**Before:**
```csharp
try
{
    await sendEmailService.SendAsync(creatorProfile.Email, EmailTypes.QuestionAnswerNotification,
        new { User = respondentName, Question = answeredQuestion.Text, Link = Constants.BaseUrl });
}
catch (Exception ex)
{
    logger.LogError(ex, "Failed to send answer notification to {Email}", creatorProfile.Email);
}
```

**After:**
```csharp
await EnqueueEmail(creatorProfile.Email, EmailTypes.QuestionAnswerNotification,
    new Dictionary<string, object>
    {
        ["User"] = respondentName,
        ["Question"] = answeredQuestion.Text,
        ["Link"] = Constants.BaseUrl
    });
```

### 2.2 DropsService — already has `IBackgroundJobQueue jobQueue = null`

#### AddComment (line ~688)

**Before:**
```csharp
Task.Run(() =>
    this.sendEmailService.SendAsync(commenter.Email, EmailTypes.CommentEmail,
        new { User = name, DropId = dropId.ToString() })
);
```

**After:**
```csharp
await EnqueueEmail(commenter.Email, EmailTypes.CommentEmail,
    new Dictionary<string, object>
    {
        ["User"] = name,
        ["DropId"] = dropId.ToString()
    });
```

#### Thank (line ~630)

**Before:**
```csharp
Task.Run(() =>
    this.sendEmailService.SendAsync(drop.CreatedBy.Email, EmailTypes.ThankEmail,
        new { User = lookupCommentor[drop.UserId], DropId = dropId.ToString() })
);
```

**After:**
```csharp
await EnqueueEmail(drop.CreatedBy.Email, EmailTypes.ThankEmail,
    new Dictionary<string, object>
    {
        ["User"] = lookupCommentor[drop.UserId],
        ["DropId"] = dropId.ToString()
    });
```

### 2.3 PromptService — inject `IBackgroundJobQueue`

#### AskQuestion (line ~266)

**Before:**
```csharp
userIds.ForEach(userId =>
    sendEmailService.SendAsync(usersEmailDictionary[userId], EmailTypes.Question,
        new { User = nameDictionary[userId], Question = prompt.Question, Id = prompt.PromptId })
);
```

**After:**
```csharp
foreach (var uid in userIds)
{
    await EnqueueEmail(usersEmailDictionary[uid], EmailTypes.Question,
        new Dictionary<string, object>
        {
            ["User"] = nameDictionary[uid],
            ["Question"] = prompt.Question,
            ["Id"] = prompt.PromptId
        });
}
```

### 2.4 SharingService — inject `IBackgroundJobQueue`

#### RequestConnection (line ~162)

**Before:**
```csharp
this.sendEmailService.SendAsync(connectionRequestModel.Email, template,
    new { User = connectionRequestModel.RequestorName, Question = question,
        TimelineName = timelineName, Token = request.RequestKey.ToString() });
this.sendEmailService.SendAsync(Constants.Email, EmailTypes.InviteNotice,
    new { Name = connectionRequestModel.RequestorName });
```

**After:**
```csharp
await EnqueueEmail(connectionRequestModel.Email, template,
    new Dictionary<string, object>
    {
        ["User"] = connectionRequestModel.RequestorName,
        ["Question"] = question,
        ["TimelineName"] = timelineName,
        ["Token"] = request.RequestKey.ToString()
    });
await EnqueueEmail(Constants.Email, EmailTypes.InviteNotice,
    new Dictionary<string, object>
    {
        ["Name"] = connectionRequestModel.RequestorName
    });
```

#### RequestReminder (line ~199)

**Before:**
```csharp
this.sendEmailService.SendAsync(invitation.TargetsEmail, template,
    new { User = invitation.RequestorName, Token = invitation.RequestKey.ToString() });
```

**After:**
```csharp
await EnqueueEmail(invitation.TargetsEmail, template,
    new Dictionary<string, object>
    {
        ["User"] = invitation.RequestorName,
        ["Token"] = invitation.RequestKey.ToString()
    });
```

#### ConfirmSharingRequest (line ~376)

**Before:**
```csharp
Task.Run(() =>
    this.sendEmailService.SendAsync(requestor.Email,
        EmailTemplates.EmailTypes.ConnecionSuccess, new { User = targetName })
);
```

**After:**
```csharp
await EnqueueEmail(requestor.Email, EmailTypes.ConnecionSuccess,
    new Dictionary<string, object> { ["User"] = targetName });
```

### 2.5 PlanController — inject `IBackgroundJobQueue jobQueue = null`

#### AddPremiumPlan (line ~68)

**Before:**
```csharp
sendEmailService.SendAsync(email, EmailTemplates.EmailTypes.Receipt, new { });
sendEmailService.SendAsync(Constants.Email, EmailTemplates.EmailTypes.PaymentNotice, new { Email = email });
```

**After:**
```csharp
await EnqueueEmail(email, EmailTypes.Receipt,
    new Dictionary<string, object>());
await EnqueueEmail(Constants.Email, EmailTypes.PaymentNotice,
    new Dictionary<string, object> { ["Email"] = email });
```

Add the same `EnqueueEmail` helper pattern to `PlanController` (with fallback to `sendEmailService`) for consistency and test compatibility.

### 2.6 ContactService — inject `IBackgroundJobQueue`

#### SendEmailToUsers (line ~32)

**Before:**
```csharp
foreach (var user in users)
{
    await sendEmailService.SendAsync(user.Email, EmailTypes.Fyli, new { Name = user.Name });
}
```

**After:**
```csharp
foreach (var user in users)
{
    await EnqueueEmail(user.Email, EmailTypes.Fyli,
        new Dictionary<string, object> { ["Name"] = user.Name });
}
```

### 2.7 Helper method pattern

Each service that uses the job queue gets a private helper to keep callsites clean:

```csharp
private async Task EnqueueEmail(string email, EmailTypes type, Dictionary<string, object> model)
{
    if (jobQueue != null)
    {
        await jobQueue.EnqueueEmailAsync(new EmailJob
        {
            Email = email,
            EmailType = type,
            Model = model
        });
    }
    else
    {
        try { await sendEmailService.SendAsync(email, type, ToExpando(model)); }
        catch { /* Fallback path — matches EmailJobProcessor error handling */ }
    }
}

private static ExpandoObject ToExpando(Dictionary<string, object> dict)
{
    var expando = new ExpandoObject();
    var d = (IDictionary<string, object>)expando;
    foreach (var kvp in dict) d[kvp.Key] = kvp.Value;
    return expando;
}
```

**Important:** The fallback path must convert `Dictionary<string, object>` to `ExpandoObject` because `SendEmailService.AddTokenToModel` uses reflection on the model's properties. A raw Dictionary would fail with `TargetParameterCountException`. The try/catch matches the `EmailJobProcessor`'s error handling — in tests, Razor template compilation fails without `PreserveCompilationContext`, and these errors were previously silently swallowed by fire-and-forget patterns.

All callsites — including `PlanController` — use this same pattern with `IBackgroundJobQueue jobQueue = null` for test compatibility.

## Phase 3: Tests

### 3.1 Unit tests for `EmailJobProcessor`

**File:** `DomainTest/BackgroundJobs/EmailJobProcessorTest.cs`

Follow the same `TestableProcessor` subclass pattern as `NotificationJobProcessorTest` — override `ProcessJob` to collect jobs in a list instead of using real DI/email service.

| Test Method | Description |
|-------------|-------------|
| `ExecuteAsync_ProcessesEnqueuedEmailJob` | Enqueue one email job, start processor, verify it's processed with correct Email/EmailType/Model |
| `ExecuteAsync_ContinuesAfterEmailJobFailure` | Enqueue two jobs, first throws, verify second still processes |
| `ExecuteAsync_StopsGracefullyOnCancellation` | Start with empty queue, stop — no exceptions |

### 3.2 Unit tests for `BackgroundJobQueue` email channel

**File:** Update `DomainTest/BackgroundJobs/BackgroundJobQueueTest.cs`

| Test Method | Description |
|-------------|-------------|
| `EmailEnqueueAndDequeue_ReturnsCorrectJob` | Enqueue email job, dequeue, verify all properties match |
| `EmailDequeue_BlocksUntilItemAvailable` | Start dequeue on empty queue, verify it blocks, then enqueue to unblock |
| `EmailDequeue_ThrowsOnCancellation` | Dequeue with cancelled token throws `OperationCanceledException` |
| `MultipleEmailEnqueueDequeue_MaintainsFIFOOrder` | Enqueue 3 jobs, dequeue 3, verify order preserved |
| `EmailChannel_IndependentFromNotificationChannel` | Enqueue to email channel, verify notification dequeue still blocks (and vice versa) |

### 3.3 Verify existing service tests still pass

Since the `EnqueueEmail` helper falls back to `sendEmailService.SendAsync` when `jobQueue == null`, all existing tests that don't inject the queue continue to work unchanged.

## Implementation Order

1. **Phase 1:** Create `EmailJob`, update `IBackgroundJobQueue`/`BackgroundJobQueue`, create `EmailJobProcessor`, register in DI
2. **Phase 2:** Migrate callsites (service by service, each is independent)
3. **Phase 3:** Add tests

## Files Changed

| File | Change |
|------|--------|
| `Domain/BackgroundJobs/EmailJob.cs` | **NEW** — job model |
| `Domain/BackgroundJobs/IBackgroundJobQueue.cs` | Add email enqueue/dequeue methods |
| `Domain/BackgroundJobs/BackgroundJobQueue.cs` | Add email channel |
| `Domain/BackgroundJobs/EmailJobProcessor.cs` | **NEW** — background processor |
| `Domain/Repositories/QuestionService.cs` | Inject queue, migrate 2 callsites |
| `Domain/Repositories/DropsService.cs` | Migrate 2 callsites (already has queue) |
| `Domain/Repositories/PromptService.cs` | Inject queue, migrate 1 callsite |
| `Domain/Repositories/SharingService.cs` | Inject queue, migrate 4 callsites |
| `Domain/Repositories/ContactService.cs` | Inject queue, migrate 1 callsite |
| `Memento/Controllers/PlanController.cs` | Inject queue, migrate 2 callsites |
| `Memento/Startup.cs` | Register `EmailJobProcessor` |
| `DomainTest/BackgroundJobs/EmailJobProcessorTest.cs` | **NEW** — tests |
| `DomainTest/BackgroundJobs/BackgroundJobQueueTest.cs` | Add email channel tests |
