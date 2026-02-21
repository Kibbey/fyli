# TDD: Local File Logging for cimplur-core

## Overview

Add file-based logging to the cimplur-core backend for local development:

1. **Split log files** — normal logs (`app.log`) and errors (`error.log`)
2. **Email logging** — all emails that would be sent are logged to `emails.log` with full details (to, template, subject, rendered body)
3. **Clear on restart** — all log files are truncated when the service starts
4. **Remove log4net** — migrate all 7 legacy log4net usages to `ILogger<T>` and remove the `log4net` package
5. **Production unchanged** — console-only logging, picked up by CloudWatch as before

## Current State

- **Framework**: `Microsoft.Extensions.Logging` (primary) + legacy `log4net` in a few services
- **Sinks**: Console only (`logging.AddConsole()` in `Program.cs`)
- **Config**: `appsettings.json` / `appsettings.Development.json` — both set `Default: Information`
- **Environment detection**: `env.IsDevelopment()` already used in `Startup.cs`
- **Email**: `SendEmailService.SendPostmarkEmail` silently returns early when `!InProduction` — no visibility into what emails would be sent locally
- **log4net**: 7 files still use legacy `log4net` (`ILog`/`LogManager`) instead of `ILogger<T>`:
  - `TransactionService` — 1 `Error` call
  - `SharingService` — 4 `Error` calls
  - `ImageService` — 1 `Error` call
  - `MovieService` — 5 `Error` calls, 1 `Info` call
  - `UserService` — 1 `Error` call
  - `LinksController` — 1 `Error` call
  - `TimelineController` — unused import + field (no actual log calls)

## Approach

Create a custom lightweight `ILoggerProvider` with zero external dependencies. The provider supports:
- **Level-based filtering** (min/max log level) for the app/error split
- **Category-based filtering** (optional category substring match) for the email log

This integrates cleanly with the existing `Microsoft.Extensions.Logging` pipeline — all existing `ILogger<T>` usage automatically gets file logging in Development.

For email logging, inject `ILogger<SendEmailService>` into `SendEmailService` and log email details at Information level. A dedicated `FileLoggerProvider` instance filters by category to capture only email logs into `emails.log`.

## Design

### Log file locations

```
cimplur-core/Memento/Memento/logs/
├── app.log        # Trace, Debug, Information (normal operations)
├── error.log      # Warning, Error, Critical
└── emails.log     # All emails (to, template, subject, body)
```

All files are created automatically by the provider. All files are truncated on service restart via `StreamWriter(append: false)`.

### Environment behavior

| Environment | Console | File logging | Email logging |
|---|---|---|---|
| Development | Yes | Yes | Yes (`emails.log`) |
| Production | Yes (CloudWatch) | No | No |

### Log level routing

| Log Level | `app.log` | `error.log` | `emails.log` |
|---|---|---|---|
| Trace | Yes | No | No |
| Debug | Yes | No | No |
| Information | Yes | No | Only `SendEmailService` category |
| Warning | No | Yes | No |
| Error | No | Yes | No |
| Critical | No | Yes | No |

## Component Diagram

```
Program.cs
  └── CreateHostBuilder
        └── ConfigureLogging (Development only)
              ├── AddConsole()                           ← all environments (unchanged)
              ├── FileLoggerProvider("app.log")          ← Trace–Information, all categories
              ├── FileLoggerProvider("error.log")        ← Warning–Critical, all categories
              └── FileLoggerProvider("emails.log")       ← Information, category: "SendEmailService"

SendEmailService
  └── SendAsync()
        └── logger.LogInformation(email details)        ← picked up by emails.log provider
```

## Implementation

### Phase 1: Custom File Logger Provider

Create `Memento/Memento/Libs/FileLoggerProvider.cs`:

```csharp
using System;
using System.IO;
using System.Threading;
using Microsoft.Extensions.Logging;

namespace Memento.Libs
{
    /// <summary>
    /// Lightweight file logger provider with level and category filtering.
    /// Files are truncated on construction (clears on restart).
    /// Provider is disposed by the DI container on host shutdown.
    /// On unclean shutdown, AutoFlush ensures all written logs are persisted.
    /// </summary>
    public class FileLoggerProvider : ILoggerProvider
    {
        private readonly LogLevel minLevel;
        private readonly LogLevel maxLevel;
        private readonly string categoryFilter;
        private readonly object @lock = new();
        private readonly StreamWriter writer;

        /// <param name="filePath">Absolute path to log file</param>
        /// <param name="minLevel">Minimum log level (inclusive)</param>
        /// <param name="maxLevel">Maximum log level (inclusive)</param>
        /// <param name="categoryFilter">
        /// Optional category substring filter. When set, only loggers
        /// whose category contains this string will write to the file.
        /// Null or empty means accept all categories.
        /// </param>
        public FileLoggerProvider(
            string filePath,
            LogLevel minLevel,
            LogLevel maxLevel,
            string categoryFilter = null)
        {
            this.minLevel = minLevel;
            this.maxLevel = maxLevel;
            this.categoryFilter = categoryFilter;

            var directory = Path.GetDirectoryName(filePath);
            if (!string.IsNullOrEmpty(directory))
                Directory.CreateDirectory(directory);

            this.writer = new StreamWriter(filePath, append: false)
            {
                AutoFlush = true
            };
        }

        public ILogger CreateLogger(string categoryName)
        {
            return new FileLogger(
                categoryName, writer, @lock,
                minLevel, maxLevel, categoryFilter);
        }

        public void Dispose()
        {
            writer?.Dispose();
        }
    }

    public class FileLogger : ILogger
    {
        private readonly string categoryName;
        private readonly StreamWriter writer;
        private readonly object @lock;
        private readonly LogLevel minLevel;
        private readonly LogLevel maxLevel;
        private readonly bool enabled;

        public FileLogger(
            string categoryName,
            StreamWriter writer,
            object lockObj,
            LogLevel minLevel,
            LogLevel maxLevel,
            string categoryFilter)
        {
            this.categoryName = categoryName;
            this.writer = writer;
            this.@lock = lockObj;
            this.minLevel = minLevel;
            this.maxLevel = maxLevel;

            // Pre-compute whether this logger is active based on category
            this.enabled = string.IsNullOrEmpty(categoryFilter)
                || categoryName.Contains(categoryFilter,
                    StringComparison.OrdinalIgnoreCase);
        }

        public IDisposable BeginScope<TState>(TState state)
            where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel)
        {
            return enabled
                && logLevel >= minLevel
                && logLevel <= maxLevel;
        }

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception exception,
            Func<TState, Exception, string> formatter)
        {
            if (!IsEnabled(logLevel))
                return;

            var message = formatter(state, exception);
            var threadId = Thread.CurrentThread.ManagedThreadId;
            var logLine =
                $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} " +
                $"[{logLevel}] " +
                $"[Thread {threadId}] " +
                $"{categoryName}: {message}";

            lock (@lock)
            {
                writer.WriteLine(logLine);
                if (exception != null)
                    writer.WriteLine(exception.ToString());
            }
        }
    }
}
```

### Phase 2: Register Providers in Program.cs

Update `Memento/Memento/Program.cs`:

```csharp
using System;
using Memento.Libs;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using System.IO;

namespace Memento
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var root = Directory.GetCurrentDirectory();
            var dotenv = Path.Combine(root, ".env");
            LoadDotEnv.Load(dotenv);
            CreateHostBuilder(args).Build().Run();
        }

        public static IHostBuilder CreateHostBuilder(string[] args) =>
            Host.CreateDefaultBuilder(args)
                .ConfigureLogging((context, logging) =>
                {
                    logging.ClearProviders();
                    logging.AddConsole();

                    if (context.HostingEnvironment.IsDevelopment())
                    {
                        var logsDir = Path.Combine(
                            Directory.GetCurrentDirectory(), "logs");

                        // Normal logs: Trace through Information
                        logging.AddProvider(new FileLoggerProvider(
                            Path.Combine(logsDir, "app.log"),
                            LogLevel.Trace,
                            LogLevel.Information));

                        // Error logs: Warning and above
                        logging.AddProvider(new FileLoggerProvider(
                            Path.Combine(logsDir, "error.log"),
                            LogLevel.Warning,
                            LogLevel.Critical));

                        // Email logs: only SendEmailService category
                        logging.AddProvider(new FileLoggerProvider(
                            Path.Combine(logsDir, "emails.log"),
                            LogLevel.Information,
                            LogLevel.Information,
                            "SendEmailService"));
                    }
                })
                .ConfigureWebHostDefaults(webBuilder =>
                {
                    webBuilder.UseStartup<Startup>();
                });
    }
}
```

### Phase 3: Add Email Logging to SendEmailService

Update `Memento/Domain/Emails/SendEmail.cs`:

Add `ILogger<SendEmailService>` to the constructor and log email details in `SendAsync`.

**Constructor change:**
```csharp
using Microsoft.Extensions.Logging;

// Add field
private readonly ILogger<SendEmailService> logger;

// Updated constructor
public SendEmailService(
    IOptions<AppSettings> appSettings,
    TokenService tokenService,
    ILogger<SendEmailService> logger)
{
    var settings = appSettings.Value;
    InProduction = settings.Production;
    EmailAddress = settings.Owner;
    EmailPW = settings.EmailCode;
    PostMarkToken = settings.EmailToken;
    this.tokenService = tokenService;
    this.logger = logger;
}
```

**Add logging in `SendAsync` — after subject is rendered, before `SendPostmarkEmail`:**
```csharp
public async Task SendAsync(string email, EmailTypes template, object model)
{
    var extendedModel = await AddTokenToModel(email, template, model)
        .ConfigureAwait(false);
    var from = GetFrom(template, model);
    var body = await EmailRender.GetStringFromView(
        template.ToString(),
        EmailTemplates.GetTemplateByName(template),
        extendedModel);
    body = EmailSafeLinkCreator.FindAndReplaceLinks(body);
    var subject = await EmailRender.GetStringFromView(
        template.ToString(),
        EmailTemplates.GetSubjectByName(template),
        model);
    var text = GetPlainTextFromHtml(body);

    logger?.LogInformation(
        "EMAIL | To: {To} | Template: {Template} | Subject: {Subject}\n{Body}",
        email, template, subject, text);

    await SendPostmarkEmail(
        email, from, subject, text, body, template.ToString(), subject)
        .ConfigureAwait(false);
}
```

The `logger?.` null-conditional handles cases where logger is null (e.g., in tests).

**Example `emails.log` output:**
```
2026-02-07 14:23:01.123 [Information] [Thread 12] Domain.Emails.SendEmailService:
  EMAIL | To: user@example.com | Template: Welcome | Subject: Welcome to Fyli!
  Welcome to Fyli, Josh!

  We're glad you're here. Get started by creating your first memory...
```

### Phase 4: Update TestSendEmailService

Update `Memento/DomainTest/Repositories/TestSendEmailService.cs` to pass `null` for the new logger parameter:

```csharp
public TestSendEmailService() : base(
    Options.Create(new AppSettings
    {
        Production = false,
        Owner = "test@test.com",
        EmailCode = "test",
        EmailToken = "test"
    }),
    null,
    null) // ILogger<SendEmailService> — not needed in tests
{
}
```

### Phase 5: Migrate log4net to ILogger&lt;T&gt;

Replace all `log4net` usage with `Microsoft.Extensions.Logging` and remove the package.

#### Step 1: TransactionService

Update `Memento/Domain/Repositories/TransactionService.cs`:

**Remove:**
```csharp
using log4net;
```
```csharp
private ILog logger = LogManager.GetLogger(nameof(TransactionService));
```

**Add:**
```csharp
using Microsoft.Extensions.Logging;
```
```csharp
private readonly ILogger<TransactionService> logger;

public TransactionService(ILogger<TransactionService> logger)
{
    this.logger = logger;
}
```

**Replace log call (line 57):**
```csharp
// Before:
logger.Error("HIGH IMPORTANCE ERROR - ALERT!", e);
// After:
logger.LogError(e, "HIGH IMPORTANCE ERROR - ALERT!");
```

#### Step 2: SharingService

Update `Memento/Domain/Repositories/SharingService.cs`:

**Remove:**
```csharp
using log4net;
```
```csharp
private ILog log = LogManager.GetLogger(nameof(SharingService));
```

**Add to imports:**
```csharp
using Microsoft.Extensions.Logging;
```

**Add `ILogger` to constructor:**
```csharp
private readonly ILogger<SharingService> logger;

public SharingService(
    SendEmailService sendEmailService,
    NotificationService notificationService,
    PromptService promptService,
    TimelineService timelineService,
    GroupService groupService,
    ILogger<SharingService> logger)
{
    this.sendEmailService = sendEmailService;
    this.notificationService = notificationService;
    this.promptService = promptService;
    this.timelineService = timelineService;
    this.groupService = groupService;
    this.logger = logger;
}
```

**Replace log calls:**
```csharp
// log.Error("Share Request", e)  →
logger.LogError(e, "Share Request");

// log.Error(ex)  →  (3 occurrences)
logger.LogError(ex, "An error occurred");
```

#### Step 3: ImageService

Update `Memento/Domain/Repositories/ImageService.cs`:

**Remove:**
```csharp
using log4net;
```
```csharp
private readonly ILog log = LogManager.GetLogger(nameof(ImageService));
```

**Add to imports:**
```csharp
using Microsoft.Extensions.Logging;
```

**Add `ILogger` to constructor:**
```csharp
private readonly ILogger<ImageService> logger;

public ImageService(
    PermissionService permissionService,
    ILogger<ImageService> logger)
{
    this.permissionService = permissionService;
    this.logger = logger;
}
```

**Replace log call:**
```csharp
// log.Error("Delete", e)  →
logger.LogError(e, "Delete");
```

#### Step 4: MovieService

Update `Memento/Domain/Repositories/MovieService.cs`:

**Remove:**
```csharp
using log4net;
```
```csharp
private ILog log = LogManager.GetLogger(nameof(MovieService));
```

**Add to imports:**
```csharp
using Microsoft.Extensions.Logging;
```

**Add `ILogger` to constructor:**
```csharp
private readonly ILogger<MovieService> logger;

public MovieService(
    PermissionService permissionService,
    ILogger<MovieService> logger)
{
    this.permissionService = permissionService;
    this.logger = logger;
}
```

**Replace log calls:**
```csharp
// log.Error("get thumb", e)  →
logger.LogError(e, "get thumb");

// log.Error("Delete 1", e)  →
logger.LogError(e, "Delete 1");

// log.Error("Delete 2", e)  →
logger.LogError(e, "Delete 2");

// log.Error("Delete folder", e)  →
logger.LogError(e, "Delete folder");

// log.Error($"Error creating MediaConvert job for {name}", e)  →
logger.LogError(e, "Error creating MediaConvert job for {Name}", name);

// log.Info($"MediaConvert job created successfully. Job ID: {response.Job.Id}, Status: {response.Job.Status}")  →
logger.LogInformation(
    "MediaConvert job created successfully. Job ID: {JobId}, Status: {Status}",
    response.Job.Id, response.Job.Status);
```

#### Step 5: Remove log4net package

Update `Memento/Domain/Domain.csproj` — remove:
```xml
<PackageReference Include="log4net" Version="3.2.0" />
```

After removal, build to confirm no remaining log4net references:
```bash
cd cimplur-core/Memento && dotnet build
```

### Phase 6: Update .gitignore

Add to `cimplur-core/.gitignore`:
```
Memento/Memento/logs/
```

This matches the specificity pattern already used in the file (e.g., `Memento/Memento/obj/`).

### Phase 7: Verification

#### Manual Testing

1. Run the service locally: `cd cimplur-core/Memento && dotnet run --project Memento`
2. Verify `logs/app.log` exists and contains startup Information-level messages
3. Verify `logs/error.log` exists (may be empty if no errors)
4. Trigger an action that sends an email (e.g., forgot password flow) and verify it appears in `emails.log` with full details
5. Trigger an error and verify it appears in `error.log` but not `app.log`
6. Restart the service and verify all three files are cleared (previous content gone)
7. Verify console output still works as before

#### Tail Commands for Monitoring

```bash
# Watch normal logs
tail -f cimplur-core/Memento/Memento/logs/app.log

# Watch error logs
tail -f cimplur-core/Memento/Memento/logs/error.log

# Watch emails
tail -f cimplur-core/Memento/Memento/logs/emails.log
```

#### Production Verification

1. Confirm `ASPNETCORE_ENVIRONMENT` is **not** `Development` in production
2. No file logging providers are registered — only console (unchanged behavior)
3. CloudWatch continues to pick up stdout/stderr as before
4. `logger?.LogInformation()` in `SendEmailService` still fires but goes to console only — acceptable since production emails are actually sent via Postmark

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Custom `ILoggerProvider` | Zero external dependencies, full control over level and category filtering |
| File cleared via `StreamWriter(append: false)` | File is truncated when provider is constructed (on startup) — no separate cleanup step needed |
| `AutoFlush = true` | Logs are immediately written, readable in real-time via `tail -f` |
| Level-based split using min/max | `app.log` gets Trace-Information, `error.log` gets Warning-Critical |
| Category filter for emails | `emails.log` only captures `SendEmailService` logs — clean separation |
| `IsDevelopment()` guard | Production remains console-only, no file I/O overhead |
| Thread-safe via `lock` | Multiple loggers from different threads write safely |
| Thread ID in log format | Helps debug concurrency issues in async operations |
| Null-conditional `logger?.` | `TestSendEmailService` passes `null` — avoids breaking existing tests |
| Provider disposed by DI container | Host shutdown disposes registered providers. `AutoFlush` ensures logs are persisted even on unclean shutdown |
| Remove log4net entirely | Single logging pipeline — all logs flow through `ILogger<T>` into console + file providers. No split behavior between frameworks |

## Files Summary

| File | Action | Description |
|---|---|---|
| `Memento/Memento/Libs/FileLoggerProvider.cs` | **Create** | Custom file logger provider with level + category filtering |
| `Memento/Memento/Program.cs` | **Modify** | Register three file logger providers in Development |
| `Memento/Domain/Emails/SendEmail.cs` | **Modify** | Add `ILogger`, log email details in `SendAsync` |
| `Memento/DomainTest/Repositories/TestSendEmailService.cs` | **Modify** | Pass `null` for new logger parameter |
| `Memento/Domain/Repositories/TransactionService.cs` | **Modify** | Replace log4net with `ILogger<TransactionService>` |
| `Memento/Domain/Repositories/SharingService.cs` | **Modify** | Replace log4net with `ILogger<SharingService>` |
| `Memento/Domain/Repositories/ImageService.cs` | **Modify** | Replace log4net with `ILogger<ImageService>` |
| `Memento/Domain/Repositories/MovieService.cs` | **Modify** | Replace log4net with `ILogger<MovieService>` |
| `Memento/Domain/Repositories/UserService.cs` | **Modify** | Replace log4net with `ILogger<UserService>` |
| `Memento/Memento/Controllers/LinksController.cs` | **Modify** | Replace log4net with `ILogger<LinksController>` |
| `Memento/Memento/Controllers/TimelineController.cs` | **Modify** | Remove unused log4net import and field |
| `Memento/Domain/Domain.csproj` | **Modify** | Remove `log4net` package reference |
| `Memento/DomainTest/Repositories/TestServiceFactory.cs` | **Modify** | Add `NullLogger<T>` for new logger constructor params |
| `cimplur-core/.gitignore` | **Modify** | Add `Memento/Memento/logs/` |
