# Technical Design Document: Question Requests — Backend

**PRD Reference:** [PRD_QUESTION_REQUESTS.md](/docs/prd/PRD_QUESTION_REQUESTS.md)
**Related TDDs:**
- [question-requests-frontend.md](./question-requests-frontend.md) — Vue 3 views and components
- [question-requests-testing.md](./question-requests-testing.md) — Test plan and fixtures

---

## Overview

Implement the backend for a question request system that allows users to create question sets, send them to multiple recipients (each with a unique link), and collect answers as memories. Recipients can answer without an account, and responses appear in both the asker's and respondent's feeds.

---

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                  C#/.NET Backend                               │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ NEW: QuestionController                                   │ │
│  │   - Question set CRUD (authenticated)                     │ │
│  │   - Send requests (authenticated)                         │ │
│  │   - Public answer submission (token + rate limited)       │ │
│  │   - Token-authenticated media upload (image/video)        │ │
│  │   - Response tracking (authenticated)                     │ │
│  ├──────────────────────────────────────────────────────────┤ │
│  │ EXISTING: DropsService                                    │ │
│  │   - Reused for drop loading (no duplication)              │ │
│  │ EXISTING: ImageService, MovieService                      │ │
│  │   - Reused for media upload/S3 operations                 │ │
│  │ NEW: QuestionService → Context (EF Core) → SQL Server     │ │
│  └──────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Data Model & Core CRUD

### 1.1 Entity: QuestionSet

**File:** `cimplur-core/Memento/Domain/Entities/QuestionSet.cs`

```csharp
/// <summary>
/// A reusable collection of questions that can be sent to multiple recipients.
/// </summary>
public class QuestionSet
{
    public QuestionSet()
    {
        Questions = new List<Question>();
        Requests = new List<QuestionRequest>();
    }

    [Key]
    public int QuestionSetId { get; set; }

    public int UserId { get; set; }

    [Required]
    [MaxLength(200)]
    public string Name { get; set; }

    public DateTime CreatedAt { get; set; }

    public DateTime UpdatedAt { get; set; }

    public bool Archived { get; set; }

    [ForeignKey("UserId")]
    public virtual UserProfile Owner { get; set; }

    public virtual IList<Question> Questions { get; set; }

    public virtual IList<QuestionRequest> Requests { get; set; }
}
```

### 1.2 Entity: Question

**File:** `cimplur-core/Memento/Domain/Entities/Question.cs`

```csharp
/// <summary>
/// A single question within a QuestionSet.
/// </summary>
public class Question
{
    public Question()
    {
        Responses = new List<QuestionResponse>();
    }

    [Key]
    public int QuestionId { get; set; }

    public int QuestionSetId { get; set; }

    [Required]
    [MaxLength(500)]
    public string Text { get; set; }

    public int SortOrder { get; set; }

    public DateTime CreatedAt { get; set; }

    [ForeignKey("QuestionSetId")]
    public virtual QuestionSet QuestionSet { get; set; }

    public virtual IList<QuestionResponse> Responses { get; set; }
}
```

### 1.3 Entity: QuestionRequest

**File:** `cimplur-core/Memento/Domain/Entities/QuestionRequest.cs`

```csharp
/// <summary>
/// An instance of sending a QuestionSet to one or more recipients.
/// </summary>
public class QuestionRequest
{
    public QuestionRequest()
    {
        Recipients = new List<QuestionRequestRecipient>();
    }

    [Key]
    public int QuestionRequestId { get; set; }

    public int QuestionSetId { get; set; }

    public int CreatorUserId { get; set; }

    [MaxLength(1000)]
    public string Message { get; set; }

    public DateTime CreatedAt { get; set; }

    [ForeignKey("QuestionSetId")]
    public virtual QuestionSet QuestionSet { get; set; }

    [ForeignKey("CreatorUserId")]
    public virtual UserProfile Creator { get; set; }

    public virtual IList<QuestionRequestRecipient> Recipients { get; set; }
}
```

### 1.4 Entity: QuestionRequestRecipient

**File:** `cimplur-core/Memento/Domain/Entities/QuestionRequestRecipient.cs`

```csharp
/// <summary>
/// A recipient of a QuestionRequest, identified by a unique token.
/// Each recipient gets their own link that works across devices.
/// </summary>
public class QuestionRequestRecipient
{
    public QuestionRequestRecipient()
    {
        Responses = new List<QuestionResponse>();
    }

    [Key]
    public int QuestionRequestRecipientId { get; set; }

    public int QuestionRequestId { get; set; }

    public Guid Token { get; set; }

    [MaxLength(255)]
    public string Email { get; set; }

    [MaxLength(100)]
    public string Alias { get; set; }

    public int? RespondentUserId { get; set; }

    public bool IsActive { get; set; }

    public DateTime CreatedAt { get; set; }

    public int RemindersSent { get; set; }

    public DateTime? LastReminderAt { get; set; }

    [ForeignKey("QuestionRequestId")]
    public virtual QuestionRequest QuestionRequest { get; set; }

    [ForeignKey("RespondentUserId")]
    public virtual UserProfile Respondent { get; set; }

    public virtual IList<QuestionResponse> Responses { get; set; }
}
```

### 1.5 Entity: QuestionResponse

**File:** `cimplur-core/Memento/Domain/Entities/QuestionResponse.cs`

```csharp
/// <summary>
/// Links a recipient's answer (Drop) to the Question they answered.
/// One-way FK to Drop - no circular reference.
/// </summary>
public class QuestionResponse
{
    [Key]
    public int QuestionResponseId { get; set; }

    public int QuestionRequestRecipientId { get; set; }

    public int QuestionId { get; set; }

    public int DropId { get; set; }

    public DateTime AnsweredAt { get; set; }

    [ForeignKey("QuestionRequestRecipientId")]
    public virtual QuestionRequestRecipient Recipient { get; set; }

    [ForeignKey("QuestionId")]
    public virtual Question Question { get; set; }

    [ForeignKey("DropId")]
    public virtual Drop Drop { get; set; }
}
```

### 1.6 Drop Entity — No Changes Required

The `Drop` entity does **not** need modification. The relationship is one-way: `QuestionResponse.DropId` → `Drop`. To get question context for a drop, query `QuestionResponses` by `DropId`.

**Why:** Avoids circular FK reference (chicken-and-egg problem during insert). The `QuestionResponse` record is created after the `Drop`, and we can join to get context when needed.

### 1.7 StreamContext Configuration

**File:** `cimplur-core/Memento/Domain/Entities/StreamContext.cs`

Add DbSets:

```csharp
public DbSet<QuestionSet> QuestionSets { get; set; }
public DbSet<Question> Questions { get; set; }
public DbSet<QuestionRequest> QuestionRequests { get; set; }
public DbSet<QuestionRequestRecipient> QuestionRequestRecipients { get; set; }
public DbSet<QuestionResponse> QuestionResponses { get; set; }
```

Add to `OnModelCreating`:

```csharp
// QuestionSet
modelBuilder.Entity<QuestionSet>(entity =>
{
    entity.HasKey(e => e.QuestionSetId);
    entity.HasIndex(e => e.UserId);

    entity.HasOne(e => e.Owner)
        .WithMany()
        .HasForeignKey(e => e.UserId)
        .OnDelete(DeleteBehavior.Restrict);
});

// Question
modelBuilder.Entity<Question>(entity =>
{
    entity.HasKey(e => e.QuestionId);
    entity.HasIndex(e => e.QuestionSetId);

    entity.HasOne(e => e.QuestionSet)
        .WithMany(qs => qs.Questions)
        .HasForeignKey(e => e.QuestionSetId)
        .OnDelete(DeleteBehavior.Cascade);
});

// QuestionRequest
modelBuilder.Entity<QuestionRequest>(entity =>
{
    entity.HasKey(e => e.QuestionRequestId);
    entity.HasIndex(e => e.QuestionSetId);
    entity.HasIndex(e => e.CreatorUserId);

    entity.HasOne(e => e.QuestionSet)
        .WithMany(qs => qs.Requests)
        .HasForeignKey(e => e.QuestionSetId)
        .OnDelete(DeleteBehavior.Restrict);

    entity.HasOne(e => e.Creator)
        .WithMany()
        .HasForeignKey(e => e.CreatorUserId)
        .OnDelete(DeleteBehavior.Restrict);
});

// QuestionRequestRecipient
modelBuilder.Entity<QuestionRequestRecipient>(entity =>
{
    entity.HasKey(e => e.QuestionRequestRecipientId);
    entity.HasIndex(e => e.Token).IsUnique();
    entity.HasIndex(e => e.QuestionRequestId);
    entity.HasIndex(e => e.RespondentUserId);
    // Filtered index for reminder job queries
    entity.HasIndex(e => e.Email);

    entity.HasOne(e => e.QuestionRequest)
        .WithMany(qr => qr.Recipients)
        .HasForeignKey(e => e.QuestionRequestId)
        .OnDelete(DeleteBehavior.Cascade);

    entity.HasOne(e => e.Respondent)
        .WithMany()
        .HasForeignKey(e => e.RespondentUserId)
        .OnDelete(DeleteBehavior.Restrict);
});

// QuestionResponse
modelBuilder.Entity<QuestionResponse>(entity =>
{
    entity.HasKey(e => e.QuestionResponseId);

    // Unique constraint: one answer per question per recipient
    entity.HasIndex(e => new { e.QuestionRequestRecipientId, e.QuestionId }).IsUnique();

    entity.HasIndex(e => e.DropId).IsUnique();
    entity.HasIndex(e => e.AnsweredAt); // For chronological queries

    entity.HasOne(e => e.Recipient)
        .WithMany(r => r.Responses)
        .HasForeignKey(e => e.QuestionRequestRecipientId)
        .OnDelete(DeleteBehavior.Restrict);

    entity.HasOne(e => e.Question)
        .WithMany(q => q.Responses)
        .HasForeignKey(e => e.QuestionId)
        .OnDelete(DeleteBehavior.Restrict);

    entity.HasOne(e => e.Drop)
        .WithMany()
        .HasForeignKey(e => e.DropId)
        .OnDelete(DeleteBehavior.Restrict);
});
```

### 1.8 Migration SQL Reference (SQL Server)

```sql
-- QuestionSets table
CREATE TABLE [QuestionSets] (
    [QuestionSetId] INT IDENTITY(1,1) PRIMARY KEY,
    [UserId] INT NOT NULL,
    [Name] NVARCHAR(200) NOT NULL,
    [CreatedAt] DATETIME2 NOT NULL,
    [UpdatedAt] DATETIME2 NOT NULL,
    [Archived] BIT NOT NULL DEFAULT 0,
    CONSTRAINT [FK_QuestionSets_UserProfiles] FOREIGN KEY ([UserId])
        REFERENCES [UserProfiles]([UserId])
);
CREATE INDEX [IX_QuestionSets_UserId] ON [QuestionSets]([UserId]);

-- Questions table
CREATE TABLE [Questions] (
    [QuestionId] INT IDENTITY(1,1) PRIMARY KEY,
    [QuestionSetId] INT NOT NULL,
    [Text] NVARCHAR(500) NOT NULL,
    [SortOrder] INT NOT NULL,
    [CreatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [FK_Questions_QuestionSets] FOREIGN KEY ([QuestionSetId])
        REFERENCES [QuestionSets]([QuestionSetId]) ON DELETE CASCADE
);
CREATE INDEX [IX_Questions_QuestionSetId] ON [Questions]([QuestionSetId]);

-- QuestionRequests table
CREATE TABLE [QuestionRequests] (
    [QuestionRequestId] INT IDENTITY(1,1) PRIMARY KEY,
    [QuestionSetId] INT NOT NULL,
    [CreatorUserId] INT NOT NULL,
    [Message] NVARCHAR(1000) NULL,
    [CreatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [FK_QuestionRequests_QuestionSets] FOREIGN KEY ([QuestionSetId])
        REFERENCES [QuestionSets]([QuestionSetId]),
    CONSTRAINT [FK_QuestionRequests_UserProfiles] FOREIGN KEY ([CreatorUserId])
        REFERENCES [UserProfiles]([UserId])
);
CREATE INDEX [IX_QuestionRequests_QuestionSetId] ON [QuestionRequests]([QuestionSetId]);
CREATE INDEX [IX_QuestionRequests_CreatorUserId] ON [QuestionRequests]([CreatorUserId]);

-- QuestionRequestRecipients table
CREATE TABLE [QuestionRequestRecipients] (
    [QuestionRequestRecipientId] INT IDENTITY(1,1) PRIMARY KEY,
    [QuestionRequestId] INT NOT NULL,
    [Token] UNIQUEIDENTIFIER NOT NULL,
    [Email] NVARCHAR(255) NULL,
    [Alias] NVARCHAR(100) NULL,
    [RespondentUserId] INT NULL,
    [IsActive] BIT NOT NULL DEFAULT 1,
    [CreatedAt] DATETIME2 NOT NULL,
    [RemindersSent] INT NOT NULL DEFAULT 0,
    [LastReminderAt] DATETIME2 NULL,
    CONSTRAINT [FK_QuestionRequestRecipients_QuestionRequests] FOREIGN KEY ([QuestionRequestId])
        REFERENCES [QuestionRequests]([QuestionRequestId]) ON DELETE CASCADE,
    CONSTRAINT [FK_QuestionRequestRecipients_UserProfiles] FOREIGN KEY ([RespondentUserId])
        REFERENCES [UserProfiles]([UserId])
);
CREATE UNIQUE INDEX [IX_QuestionRequestRecipients_Token] ON [QuestionRequestRecipients]([Token]);
CREATE INDEX [IX_QuestionRequestRecipients_QuestionRequestId] ON [QuestionRequestRecipients]([QuestionRequestId]);
CREATE INDEX [IX_QuestionRequestRecipients_RespondentUserId] ON [QuestionRequestRecipients]([RespondentUserId]);
-- Index for reminder job queries (recipients with email addresses)
CREATE INDEX [IX_QuestionRequestRecipients_Email] ON [QuestionRequestRecipients]([Email]) WHERE [Email] IS NOT NULL;

-- QuestionResponses table
CREATE TABLE [QuestionResponses] (
    [QuestionResponseId] INT IDENTITY(1,1) PRIMARY KEY,
    [QuestionRequestRecipientId] INT NOT NULL,
    [QuestionId] INT NOT NULL,
    [DropId] INT NOT NULL,
    [AnsweredAt] DATETIME2 NOT NULL,
    CONSTRAINT [FK_QuestionResponses_QuestionRequestRecipients] FOREIGN KEY ([QuestionRequestRecipientId])
        REFERENCES [QuestionRequestRecipients]([QuestionRequestRecipientId]),
    CONSTRAINT [FK_QuestionResponses_Questions] FOREIGN KEY ([QuestionId])
        REFERENCES [Questions]([QuestionId]),
    CONSTRAINT [FK_QuestionResponses_Drops] FOREIGN KEY ([DropId])
        REFERENCES [Drops]([DropId])
);
-- Unique constraint: one answer per question per recipient
CREATE UNIQUE INDEX [IX_QuestionResponses_Recipient_Question] ON [QuestionResponses]([QuestionRequestRecipientId], [QuestionId]);
CREATE UNIQUE INDEX [IX_QuestionResponses_DropId] ON [QuestionResponses]([DropId]);
CREATE INDEX [IX_QuestionResponses_AnsweredAt] ON [QuestionResponses]([AnsweredAt]);
```

---

## Phase 2: Service Layer

### 2.1 QuestionService

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`

```csharp
using System.Text.RegularExpressions;

/// <summary>
/// Handles question set management, request distribution, and answer collection.
/// </summary>
public class QuestionService : BaseService, IQuestionService
{
    private readonly SharingService sharingService;
    private readonly GroupService groupService;
    private readonly UserService userService;
    private readonly DropsService dropsService;
    private readonly SendEmailService sendEmailService;
    private readonly ILogger<QuestionService> logger;

    public QuestionService(
        SharingService sharingService,
        GroupService groupService,
        UserService userService,
        DropsService dropsService,
        SendEmailService sendEmailService,
        ILogger<QuestionService> logger)
    {
        this.sharingService = sharingService;
        this.groupService = groupService;
        this.userService = userService;
        this.dropsService = dropsService;
        this.sendEmailService = sendEmailService;
        this.logger = logger;
    }

    // ===== QUESTION SET CRUD =====

    /// <summary>
    /// Gets all non-archived question sets for a user with pagination.
    /// </summary>
    public async Task<List<QuestionSetModel>> GetQuestionSets(int userId, int skip = 0, int take = 50)
    {
        // Enforce maximum page size to prevent excessive data loading
        take = Math.Min(take, 100);

        return await Context.QuestionSets
            .Include(qs => qs.Questions.OrderBy(q => q.SortOrder))
            .Where(qs => qs.UserId == userId && !qs.Archived)
            .OrderByDescending(qs => qs.UpdatedAt)
            .Skip(skip)
            .Take(take)
            .Select(qs => MapToModel(qs))
            .ToListAsync();
    }

    /// <summary>
    /// Gets a single question set by ID, verifying ownership.
    /// </summary>
    public async Task<QuestionSetModel> GetQuestionSet(int userId, int questionSetId)
    {
        var qs = await Context.QuestionSets
            .Include(q => q.Questions.OrderBy(q => q.SortOrder))
            .SingleOrDefaultAsync(q => q.QuestionSetId == questionSetId && q.UserId == userId);

        if (qs == null)
            throw new NotFoundException("Question set not found.");

        return MapToModel(qs);
    }

    /// <summary>
    /// Creates a new question set with 1-5 questions.
    /// </summary>
    public async Task<QuestionSetModel> CreateQuestionSet(int userId, string name, List<string> questions)
    {
        // Input validation
        if (string.IsNullOrWhiteSpace(name))
            throw new BadRequestException("Name is required.");

        if (name.Length > 200)
            throw new BadRequestException("Name must be 200 characters or less.");

        if (questions == null || !questions.Any())
            throw new BadRequestException("At least one question is required.");

        if (questions.Count > 5)
            throw new BadRequestException("Maximum 5 questions per set.");

        var validQuestions = questions.Where(q => !string.IsNullOrWhiteSpace(q)).ToList();
        if (!validQuestions.Any())
            throw new BadRequestException("At least one non-empty question is required.");

        foreach (var q in validQuestions)
        {
            if (q.Length > 500)
                throw new BadRequestException("Each question must be 500 characters or less.");
        }

        var now = DateTime.UtcNow;
        var questionSet = new QuestionSet
        {
            UserId = userId,
            Name = name.Trim(),
            CreatedAt = now,
            UpdatedAt = now,
            Archived = false,
            Questions = validQuestions.Select((text, index) => new Question
            {
                Text = text.Trim(),
                SortOrder = index,
                CreatedAt = now
            }).ToList()
        };

        Context.QuestionSets.Add(questionSet);
        await Context.SaveChangesAsync();

        return MapToModel(questionSet);
    }

    /// <summary>
    /// Updates an existing question set. Cannot delete questions that have responses.
    /// </summary>
    public async Task<QuestionSetModel> UpdateQuestionSet(
        int userId,
        int questionSetId,
        string name,
        List<QuestionUpdateModel> questions)
    {
        // Input validation
        if (string.IsNullOrWhiteSpace(name))
            throw new BadRequestException("Name is required.");

        if (name.Length > 200)
            throw new BadRequestException("Name must be 200 characters or less.");

        if (questions == null || !questions.Any())
            throw new BadRequestException("At least one question is required.");

        if (questions.Count > 5)
            throw new BadRequestException("Maximum 5 questions per set.");

        var qs = await Context.QuestionSets
            .Include(q => q.Questions)
            .SingleOrDefaultAsync(q => q.QuestionSetId == questionSetId && q.UserId == userId);

        if (qs == null)
            throw new NotFoundException("Question set not found.");

        qs.Name = name.Trim();
        qs.UpdatedAt = DateTime.UtcNow;

        // Remove deleted questions
        var updatedIds = questions
            .Where(q => q.QuestionId.HasValue)
            .Select(q => q.QuestionId.Value)
            .ToHashSet();
        var toRemove = qs.Questions.Where(q => !updatedIds.Contains(q.QuestionId)).ToList();

        foreach (var q in toRemove)
        {
            var hasResponses = await Context.QuestionResponses.AnyAsync(r => r.QuestionId == q.QuestionId);
            if (hasResponses)
                throw new BadRequestException($"Cannot delete question '{q.Text}' because it has responses.");
            Context.Questions.Remove(q);
        }

        // Update existing and add new
        foreach (var (qm, index) in questions.Select((q, i) => (q, i)))
        {
            if (string.IsNullOrWhiteSpace(qm.Text))
                continue;

            if (qm.Text.Length > 500)
                throw new BadRequestException("Each question must be 500 characters or less.");

            if (qm.QuestionId.HasValue)
            {
                var existing = qs.Questions.SingleOrDefault(q => q.QuestionId == qm.QuestionId.Value);
                if (existing != null)
                {
                    existing.Text = qm.Text.Trim();
                    existing.SortOrder = index;
                }
            }
            else
            {
                qs.Questions.Add(new Question
                {
                    Text = qm.Text.Trim(),
                    SortOrder = index,
                    CreatedAt = DateTime.UtcNow
                });
            }
        }

        await Context.SaveChangesAsync();
        return MapToModel(qs);
    }

    /// <summary>
    /// Soft-deletes a question set by setting Archived = true.
    /// </summary>
    public async Task DeleteQuestionSet(int userId, int questionSetId)
    {
        var qs = await Context.QuestionSets
            .SingleOrDefaultAsync(q => q.QuestionSetId == questionSetId && q.UserId == userId);

        if (qs == null)
            throw new NotFoundException("Question set not found.");

        qs.Archived = true;
        await Context.SaveChangesAsync();
    }

    // ===== QUESTION REQUEST CREATION =====

    // Email validation regex (RFC 5322 simplified)
    private static readonly Regex EmailRegex = new Regex(
        @"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$",
        RegexOptions.Compiled);

    /// <summary>
    /// Creates a question request and generates unique tokens for each recipient.
    /// Sends notification emails asynchronously using fire-and-forget pattern.
    ///
    /// IMPORTANT: Email delivery failures are logged but not retried. This is a
    /// deliberate tradeoff for simplicity. The fire-and-forget pattern means:
    /// - Emails may be lost if the email service is temporarily unavailable
    /// - No retry mechanism exists for failed sends
    /// - Users should share links manually as a backup
    ///
    /// Future iterations could add a background queue (e.g., Hangfire) for
    /// reliable delivery if email reliability becomes a business requirement.
    /// </summary>
    public async Task<QuestionRequestResultModel> CreateQuestionRequest(
        int userId,
        int questionSetId,
        List<RecipientInputModel> recipients,
        string message)
    {
        if (recipients == null || !recipients.Any())
            throw new BadRequestException("At least one recipient is required.");

        // Validate email formats
        foreach (var recipient in recipients.Where(r => !string.IsNullOrWhiteSpace(r.Email)))
        {
            if (!EmailRegex.IsMatch(recipient.Email.Trim()))
                throw new BadRequestException($"Invalid email format: {recipient.Email}");
        }

        var qs = await Context.QuestionSets
            .Include(q => q.Questions)
            .SingleOrDefaultAsync(q => q.QuestionSetId == questionSetId && q.UserId == userId);

        if (qs == null)
            throw new NotFoundException("Question set not found.");

        if (!qs.Questions.Any())
            throw new BadRequestException("Question set has no questions.");

        var now = DateTime.UtcNow;
        var request = new QuestionRequest
        {
            QuestionSetId = questionSetId,
            CreatorUserId = userId,
            Message = message?.Trim(),
            CreatedAt = now,
            Recipients = recipients
                .Where(r => !string.IsNullOrWhiteSpace(r.Email) || !string.IsNullOrWhiteSpace(r.Alias))
                .Select(r => new QuestionRequestRecipient
                {
                    Token = Guid.NewGuid(),
                    Email = r.Email?.Trim(),
                    Alias = r.Alias?.Trim(),
                    IsActive = true,
                    CreatedAt = now,
                    RemindersSent = 0
                }).ToList()
        };

        if (!request.Recipients.Any())
            throw new BadRequestException("At least one valid recipient is required.");

        Context.QuestionRequests.Add(request);
        await Context.SaveChangesAsync();

        // Send emails asynchronously with error handling
        var creator = await Context.UserProfiles.SingleAsync(u => u.UserId == userId);
        var firstQuestion = qs.Questions.OrderBy(q => q.SortOrder).First().Text;

        foreach (var recipient in request.Recipients.Where(r => !string.IsNullOrEmpty(r.Email)))
        {
            var recipientEmail = recipient.Email;
            var answerLink = $"{Constants.BaseUrl}/q/{recipient.Token}";

            _ = Task.Run(async () =>
            {
                try
                {
                    await sendEmailService.SendAsync(
                        recipientEmail,
                        EmailTypes.QuestionRequestNotification,
                        new { User = creator.Name, Question = firstQuestion, AnswerLink = answerLink });
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Failed to send question request email to {Email}", recipientEmail);
                }
            });
        }

        return new QuestionRequestResultModel
        {
            QuestionRequestId = request.QuestionRequestId,
            Recipients = request.Recipients.Select(r => new RecipientLinkModel
            {
                QuestionRequestRecipientId = r.QuestionRequestRecipientId,
                Token = r.Token,
                Email = r.Email,
                Alias = r.Alias
            }).ToList()
        };
    }

    // ===== PUBLIC ANSWER FLOW =====

    /// <summary>
    /// Gets question request details by token for the public answer page.
    /// </summary>
    public async Task<QuestionRequestViewModel> GetQuestionRequestByToken(Guid token)
    {
        var recipient = await Context.QuestionRequestRecipients
            .Include(r => r.QuestionRequest)
                .ThenInclude(qr => qr.QuestionSet)
                    .ThenInclude(qs => qs.Questions.OrderBy(q => q.SortOrder))
            .Include(r => r.QuestionRequest)
                .ThenInclude(qr => qr.Creator)
            .Include(r => r.Responses)
            .SingleOrDefaultAsync(r => r.Token == token);

        if (recipient == null || !recipient.IsActive)
            throw new NotFoundException("This question link is no longer active.");

        var answeredQuestionIds = recipient.Responses.Select(r => r.QuestionId).ToHashSet();

        return new QuestionRequestViewModel
        {
            QuestionRequestRecipientId = recipient.QuestionRequestRecipientId,
            CreatorName = recipient.QuestionRequest.Creator.Name,
            Message = recipient.QuestionRequest.Message,
            QuestionSetName = recipient.QuestionRequest.QuestionSet.Name,
            Questions = recipient.QuestionRequest.QuestionSet.Questions
                .OrderBy(q => q.SortOrder)
                .Select(q => new QuestionViewModel
                {
                    QuestionId = q.QuestionId,
                    Text = q.Text,
                    SortOrder = q.SortOrder,
                    IsAnswered = answeredQuestionIds.Contains(q.QuestionId)
                }).ToList()
        };
    }

    /// <summary>
    /// Submits an answer to a question, creating a Drop and QuestionResponse.
    /// Media uploads happen separately via token-authenticated endpoints.
    /// If media upload fails after this call, the answer exists as text-only.
    ///
    /// Transaction Scope: This method performs multiple database operations:
    /// 1. Creates Drop + ContentDrop (single SaveChanges, EF handles as transaction)
    /// 2. Creates QuestionResponse + optional UserDrop (single SaveChanges)
    ///
    /// Race Condition Handling: The unique index on (QuestionRequestRecipientId, QuestionId)
    /// prevents duplicate answers if the same question is submitted concurrently.
    /// The in-memory check (recipient.Responses.Any) is an optimization to fail fast,
    /// but the database constraint is the authoritative guard.
    /// </summary>
    public async Task<DropModel> SubmitAnswer(
        Guid token,
        int questionId,
        string content,
        DateTime date,
        DateTypes dateType)
    {
        // Input validation
        if (string.IsNullOrWhiteSpace(content))
            throw new BadRequestException("Answer content is required.");

        if (content.Length > 4000)
            throw new BadRequestException("Answer must be 4000 characters or less.");

        var recipient = await Context.QuestionRequestRecipients
            .Include(r => r.QuestionRequest)
                .ThenInclude(qr => qr.QuestionSet)
                    .ThenInclude(qs => qs.Questions)
            .Include(r => r.Responses)
            .SingleOrDefaultAsync(r => r.Token == token);

        if (recipient == null || !recipient.IsActive)
            throw new NotFoundException("This question link is no longer active.");

        var question = recipient.QuestionRequest.QuestionSet.Questions
            .SingleOrDefault(q => q.QuestionId == questionId);

        if (question == null)
            throw new NotFoundException("Question not found.");

        // Check if already answered (also enforced by unique index)
        if (recipient.Responses.Any(r => r.QuestionId == questionId))
            throw new BadRequestException("This question has already been answered.");

        var now = DateTime.UtcNow;
        var creatorUserId = recipient.QuestionRequest.CreatorUserId;

        // If respondent has an account, use their userId; otherwise use creator's
        var dropUserId = recipient.RespondentUserId ?? creatorUserId;

        var drop = new Drop
        {
            UserId = dropUserId,
            Date = date,
            DateType = dateType,
            Created = now,
            DayOfYear = date.DayOfYear,
            Archived = false,
            ContentDrop = new ContentDrop { Stuff = content.Trim() }
        };

        Context.Drops.Add(drop);
        await Context.SaveChangesAsync();

        // Create the QuestionResponse linking drop to question
        var response = new QuestionResponse
        {
            QuestionRequestRecipientId = recipient.QuestionRequestRecipientId,
            QuestionId = questionId,
            DropId = drop.DropId,
            AnsweredAt = now
        };

        Context.QuestionResponses.Add(response);

        // Grant creator access to the drop if owned by respondent
        if (dropUserId != creatorUserId)
        {
            await GrantDropAccessToUser(drop.DropId, creatorUserId);
        }

        await Context.SaveChangesAsync();

        // Notify asker that someone answered their question
        var creatorProfile = await Context.UserProfiles.SingleAsync(u => u.UserId == creatorUserId);
        var answeredQuestion = recipient.QuestionRequest.QuestionSet.Questions
            .Single(q => q.QuestionId == questionId);
        var respondentName = recipient.Alias ?? "Someone";

        _ = Task.Run(async () =>
        {
            try
            {
                await sendEmailService.SendAsync(
                    creatorProfile.Email,
                    EmailTypes.QuestionAnswerNotification,
                    new { User = respondentName, Question = answeredQuestion.Text, Link = Constants.BaseUrl });
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to send answer notification to {Email}", creatorProfile.Email);
            }
        });

        return await LoadDropModelWithQuestionContext(drop.DropId, dropUserId);
    }

    /// <summary>
    /// Updates an existing answer. Anonymous users have a 7-day edit window.
    /// </summary>
    public async Task<DropModel> UpdateAnswer(
        Guid token,
        int questionId,
        string content,
        DateTime date,
        DateTypes dateType,
        List<int> imageIds,
        List<int> movieIds)
    {
        // Input validation
        if (string.IsNullOrWhiteSpace(content))
            throw new BadRequestException("Answer content is required.");

        if (content.Length > 4000)
            throw new BadRequestException("Answer must be 4000 characters or less.");

        var recipient = await Context.QuestionRequestRecipients
            .Include(r => r.Responses)
            .SingleOrDefaultAsync(r => r.Token == token);

        if (recipient == null || !recipient.IsActive)
            throw new NotFoundException("This question link is no longer active.");

        var response = recipient.Responses.SingleOrDefault(r => r.QuestionId == questionId);
        if (response == null)
            throw new NotFoundException("Answer not found.");

        // Check edit window (7 days) for anonymous users
        if (!recipient.RespondentUserId.HasValue)
        {
            var daysSinceAnswer = (DateTime.UtcNow - response.AnsweredAt).TotalDays;
            if (daysSinceAnswer > 7)
                throw new BadRequestException("Anonymous answers can only be edited within 7 days. Create an account to edit anytime.");
        }

        var drop = await Context.Drops
            .Include(d => d.ContentDrop)
            .SingleAsync(d => d.DropId == response.DropId);

        drop.Date = date;
        drop.DateType = dateType;
        drop.DayOfYear = date.DayOfYear;
        drop.ContentDrop.Stuff = content.Trim();

        // Update media associations
        await UpdateDropMedia(drop.DropId, imageIds ?? new List<int>(), movieIds ?? new List<int>());

        await Context.SaveChangesAsync();

        return await LoadDropModelWithQuestionContext(drop.DropId, drop.UserId);
    }

    // ===== ACCOUNT CREATION & LINKING =====

    /// <summary>
    /// Registers a new user (or finds existing) and links all answers to their account.
    ///
    /// Transaction Scope: This operation MUST be atomic. It performs:
    /// 1. User lookup/creation
    /// 2. Recipient linking
    /// 3. Drop ownership transfer (multiple drops)
    /// 4. Creator access grants (UserDrop records)
    /// 5. Connection creation
    /// 6. Group population
    ///
    /// Uses EF Core's implicit transaction (single SaveChanges at the end).
    /// If any step fails, all changes are rolled back.
    /// </summary>
    public async Task<int> RegisterAndLinkAnswers(Guid token, string email, string name, bool acceptTerms)
    {
        // Input validation
        if (string.IsNullOrWhiteSpace(email))
            throw new BadRequestException("Email is required.");

        if (!EmailRegex.IsMatch(email.Trim()))
            throw new BadRequestException("Invalid email format.");

        if (string.IsNullOrWhiteSpace(name))
            throw new BadRequestException("Name is required.");

        if (!acceptTerms)
            throw new BadRequestException("You must accept the terms to create an account.");

        var recipient = await Context.QuestionRequestRecipients
            .Include(r => r.QuestionRequest)
            .Include(r => r.Responses)
                .ThenInclude(resp => resp.Drop)
            .SingleOrDefaultAsync(r => r.Token == token);

        if (recipient == null)
            throw new NotFoundException("Question link not found.");

        // Check if user already exists
        var existingUser = await Context.UserProfiles
            .SingleOrDefaultAsync(u => u.Email.ToLower() == email.ToLower().Trim());

        int userId;
        if (existingUser != null)
        {
            userId = existingUser.UserId;
        }
        else
        {
            userId = await userService.AddUser(email.Trim(), email.Trim(), null, acceptTerms, name.Trim(), null);
        }

        // Link recipient to user
        recipient.RespondentUserId = userId;

        // Transfer ownership of all answers to the new user
        // Grant creator explicit access via UserDrop before changing UserId
        var creatorUserId = recipient.QuestionRequest.CreatorUserId;
        foreach (var response in recipient.Responses)
        {
            // Ensure creator retains access after ownership transfer
            await GrantDropAccessToUser(response.DropId, creatorUserId);
            response.Drop.UserId = userId;
        }

        // Create connection between asker and respondent
        await sharingService.EnsureConnectionAsync(recipient.QuestionRequest.CreatorUserId, userId);

        // Grant respondent access to see asker's drops
        await groupService.PopulateEveryone(recipient.QuestionRequest.CreatorUserId);
        await groupService.PopulateEveryone(userId);

        await Context.SaveChangesAsync();

        return userId;
    }

    // ===== RESPONSE VIEWING =====

    /// <summary>
    /// Gets question responses for requests created by this user, with pagination.
    /// Only loads requests that have at least one response to avoid excessive data.
    /// </summary>
    public async Task<List<QuestionResponseFeedModel>> GetMyQuestionResponses(int userId, int skip = 0, int take = 20)
    {
        // Enforce maximum page size
        take = Math.Min(take, 100);

        // Only load requests that have at least one response
        var requests = await Context.QuestionRequests
            .Include(r => r.QuestionSet)
                .ThenInclude(qs => qs.Questions.OrderBy(q => q.SortOrder))
            .Include(r => r.Recipients.Where(rec => rec.Responses.Any()))
                .ThenInclude(rec => rec.Responses)
                    .ThenInclude(resp => resp.Drop)
                        .ThenInclude(d => d.ContentDrop)
            .Include(r => r.Recipients.Where(rec => rec.Responses.Any()))
                .ThenInclude(rec => rec.Respondent)
            .Where(r => r.CreatorUserId == userId
                && r.Recipients.Any(rec => rec.Responses.Any()))
            .OrderByDescending(r => r.CreatedAt)
            .Skip(skip)
            .Take(take)
            .ToListAsync();

        // Separately count total recipients per request for the summary
        var requestIds = requests.Select(r => r.QuestionRequestId).ToList();
        var totalRecipientCounts = await Context.QuestionRequestRecipients
            .Where(rec => requestIds.Contains(rec.QuestionRequestId))
            .GroupBy(rec => rec.QuestionRequestId)
            .Select(g => new { QuestionRequestId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.QuestionRequestId, x => x.Count);

        return requests.Select(r => new QuestionResponseFeedModel
        {
            QuestionRequestId = r.QuestionRequestId,
            QuestionSetName = r.QuestionSet.Name,
            CreatedAt = r.CreatedAt,
            TotalRecipients = totalRecipientCounts.GetValueOrDefault(r.QuestionRequestId, 0),
            RespondedCount = r.Recipients.Count,
            Questions = r.QuestionSet.Questions.OrderBy(q => q.SortOrder).Select(q => new QuestionWithResponsesModel
            {
                QuestionId = q.QuestionId,
                Text = q.Text,
                Responses = r.Recipients
                    .SelectMany(rec => rec.Responses
                        .Where(resp => resp.QuestionId == q.QuestionId)
                        .Select(resp => new ResponseSummaryModel
                        {
                            DropId = resp.DropId,
                            RespondentName = rec.Alias ?? rec.Respondent?.Name ?? "Anonymous",
                            AnsweredAt = resp.AnsweredAt,
                            ContentPreview = resp.Drop.ContentDrop.Stuff.Length > 100
                                ? resp.Drop.ContentDrop.Stuff.Substring(0, 100) + "..."
                                : resp.Drop.ContentDrop.Stuff
                        }))
                    .OrderBy(resp => resp.AnsweredAt)
                    .ToList()
            }).ToList()
        }).ToList();
    }

    /// <summary>
    /// Gets other respondents' answers to the same question request.
    /// Only shows answers from users who have accounts (privacy protection).
    /// </summary>
    public async Task<List<DropModel>> GetOtherResponsesToSameQuestions(int userId, int questionRequestId)
    {
        // User must be a respondent with an account
        var myRecipient = await Context.QuestionRequestRecipients
            .Include(r => r.QuestionRequest)
            .SingleOrDefaultAsync(r => r.QuestionRequest.QuestionRequestId == questionRequestId
                && r.RespondentUserId == userId);

        if (myRecipient == null)
            throw new NotFoundException("You are not a participant in this question request.");

        // Batch load all responses from OTHER recipients who have accounts
        var otherResponses = await Context.QuestionResponses
            .Include(r => r.Recipient)
                .ThenInclude(rec => rec.Respondent)
            .Include(r => r.Question)
            .Where(r => r.Recipient.QuestionRequestId == questionRequestId
                && r.Recipient.RespondentUserId.HasValue
                && r.Recipient.RespondentUserId != userId)
            .OrderBy(r => r.QuestionId)
            .ThenBy(r => r.AnsweredAt)
            .ToListAsync();

        if (!otherResponses.Any())
            return new List<DropModel>();

        // Batch load all drops in a single query to avoid N+1
        var dropIds = otherResponses.Select(r => r.DropId).ToList();
        var drops = await dropsService.GetDropsByIds(dropIds, userId);

        // Add question context to each drop
        var dropModels = new List<DropModel>();
        foreach (var response in otherResponses)
        {
            var dropModel = drops.FirstOrDefault(d => d.DropId == response.DropId);
            if (dropModel != null)
            {
                dropModel.QuestionContext = new QuestionContextModel
                {
                    QuestionId = response.QuestionId,
                    QuestionText = response.Question.Text,
                    QuestionRequestId = questionRequestId
                };
                dropModels.Add(dropModel);
            }
        }

        return dropModels;
    }

    // ===== REQUEST MANAGEMENT =====

    /// <summary>
    /// Gets all sent question requests with recipient status, with pagination.
    /// </summary>
    public async Task<List<QuestionRequestDashboardModel>> GetSentRequests(int userId, int skip = 0, int take = 20)
    {
        // Enforce maximum page size
        take = Math.Min(take, 100);

        return await Context.QuestionRequests
            .Include(r => r.QuestionSet)
                .ThenInclude(qs => qs.Questions)
            .Include(r => r.Recipients)
                .ThenInclude(rec => rec.Responses)
            .Where(r => r.CreatorUserId == userId)
            .OrderByDescending(r => r.CreatedAt)
            .Skip(skip)
            .Take(take)
            .Select(r => new QuestionRequestDashboardModel
            {
                QuestionRequestId = r.QuestionRequestId,
                QuestionSetName = r.QuestionSet.Name,
                CreatedAt = r.CreatedAt,
                Recipients = r.Recipients.Select(rec => new RecipientStatusModel
                {
                    QuestionRequestRecipientId = rec.QuestionRequestRecipientId,
                    Token = rec.Token,
                    Alias = rec.Alias,
                    Email = rec.Email,
                    IsActive = rec.IsActive,
                    AnsweredCount = rec.Responses.Count,
                    TotalQuestions = r.QuestionSet.Questions.Count,
                    LastReminderAt = rec.LastReminderAt,
                    RemindersSent = rec.RemindersSent
                }).ToList()
            })
            .ToListAsync();
    }

    /// <summary>
    /// Deactivates a recipient's link so they can no longer answer.
    /// </summary>
    public async Task DeactivateRecipientLink(int userId, int recipientId)
    {
        var recipient = await Context.QuestionRequestRecipients
            .Include(r => r.QuestionRequest)
            .SingleOrDefaultAsync(r => r.QuestionRequestRecipientId == recipientId);

        if (recipient == null)
            throw new NotFoundException("Recipient not found.");

        if (recipient.QuestionRequest.CreatorUserId != userId)
            throw new NotAuthorizedException("You can only manage your own question requests.");

        recipient.IsActive = false;
        await Context.SaveChangesAsync();
    }

    /// <summary>
    /// Sends a reminder email to a recipient who hasn't answered.
    /// </summary>
    public async Task SendReminder(int userId, int recipientId)
    {
        var recipient = await Context.QuestionRequestRecipients
            .Include(r => r.QuestionRequest)
                .ThenInclude(qr => qr.Creator)
            .Include(r => r.QuestionRequest)
                .ThenInclude(qr => qr.QuestionSet)
                    .ThenInclude(qs => qs.Questions)
            .SingleOrDefaultAsync(r => r.QuestionRequestRecipientId == recipientId);

        if (recipient == null)
            throw new NotFoundException("Recipient not found.");

        if (recipient.QuestionRequest.CreatorUserId != userId)
            throw new NotAuthorizedException("You can only manage your own question requests.");

        if (string.IsNullOrEmpty(recipient.Email))
            throw new BadRequestException("Recipient has no email address.");

        var answerLink = $"{Constants.BaseUrl}/q/{recipient.Token}";
        await sendEmailService.SendAsync(
            recipient.Email,
            EmailTypes.QuestionRequestReminder,
            new { User = recipient.QuestionRequest.Creator.Name,
                  Question = recipient.QuestionRequest.QuestionSet.Questions
                      .OrderBy(q => q.SortOrder).First().Text,
                  AnswerLink = answerLink });

        recipient.RemindersSent++;
        recipient.LastReminderAt = DateTime.UtcNow;
        await Context.SaveChangesAsync();
    }

    // ===== TOKEN VALIDATION FOR MEDIA UPLOAD =====

    /// <summary>
    /// Validates that a token owns a response linked to the given dropId.
    /// Returns the recipient with QuestionRequest loaded, or null if invalid.
    /// </summary>
    public async Task<QuestionRequestRecipient> ValidateTokenOwnsDropAsync(Guid token, int dropId)
    {
        return await Context.QuestionRequestRecipients
            .Include(r => r.QuestionRequest)
            .Include(r => r.Responses)
            .SingleOrDefaultAsync(r =>
                r.Token == token
                && r.IsActive
                && r.Responses.Any(resp => resp.DropId == dropId));
    }

    // ===== HELPER METHODS =====

    private static QuestionSetModel MapToModel(QuestionSet qs)
    {
        return new QuestionSetModel
        {
            QuestionSetId = qs.QuestionSetId,
            Name = qs.Name,
            CreatedAt = qs.CreatedAt,
            UpdatedAt = qs.UpdatedAt,
            Questions = qs.Questions.OrderBy(q => q.SortOrder).Select(q => new QuestionModel
            {
                QuestionId = q.QuestionId,
                Text = q.Text,
                SortOrder = q.SortOrder
            }).ToList()
        };
    }

    private async Task GrantDropAccessToUser(int dropId, int userId)
    {
        var exists = await Context.UserDrops.AnyAsync(ud => ud.DropId == dropId && ud.UserId == userId);
        if (!exists)
        {
            Context.UserDrops.Add(new UserDrop
            {
                DropId = dropId,
                UserId = userId
            });
        }
    }

    private async Task UpdateDropMedia(int dropId, List<int> imageIds, List<int> movieIds)
    {
        // Handle images: remove deleted, verify new ones belong to this drop
        var currentImages = await Context.ImageDrops
            .Where(i => i.DropId == dropId && !i.CommentId.HasValue)
            .ToListAsync();

        var currentImageIds = currentImages.Select(i => i.ImageDropId).ToHashSet();

        // Remove images no longer in the list
        foreach (var img in currentImages.Where(i => !imageIds.Contains(i.ImageDropId)))
        {
            Context.ImageDrops.Remove(img);
        }

        // Verify new image IDs actually belong to this drop
        // (images are uploaded via token endpoint which creates ImageDrop records)
        var newImageIds = imageIds.Where(id => !currentImageIds.Contains(id)).ToList();
        if (newImageIds.Any())
        {
            var validNew = await Context.ImageDrops
                .Where(i => newImageIds.Contains(i.ImageDropId) && i.DropId == dropId)
                .CountAsync();
            if (validNew != newImageIds.Count)
                throw new BadRequestException("Some image IDs do not belong to this memory.");
        }

        // Handle movies: same pattern
        var currentMovies = await Context.MovieDrops
            .Where(m => m.DropId == dropId && !m.CommentId.HasValue)
            .ToListAsync();

        var currentMovieIds = currentMovies.Select(m => m.MovieDropId).ToHashSet();

        foreach (var mov in currentMovies.Where(m => !movieIds.Contains(m.MovieDropId)))
        {
            Context.MovieDrops.Remove(mov);
        }

        var newMovieIds = movieIds.Where(id => !currentMovieIds.Contains(id)).ToList();
        if (newMovieIds.Any())
        {
            var validNew = await Context.MovieDrops
                .Where(m => newMovieIds.Contains(m.MovieDropId) && m.DropId == dropId)
                .CountAsync();
            if (validNew != newMovieIds.Count)
                throw new BadRequestException("Some movie IDs do not belong to this memory.");
        }
    }

    /// <summary>
    /// Loads a drop model with question context using DropsService.
    /// </summary>
    private async Task<DropModel> LoadDropModelWithQuestionContext(int dropId, int viewerUserId)
    {
        // Use DropsService to load the drop (reuse existing logic)
        var dropModel = await dropsService.Drop(viewerUserId, dropId);

        // Add question context if this drop is a question response
        var questionResponse = await Context.QuestionResponses
            .Include(qr => qr.Question)
            .Include(qr => qr.Recipient)
            .SingleOrDefaultAsync(qr => qr.DropId == dropId);

        if (questionResponse != null)
        {
            dropModel.QuestionContext = new QuestionContextModel
            {
                QuestionId = questionResponse.QuestionId,
                QuestionText = questionResponse.Question.Text,
                QuestionRequestId = questionResponse.Recipient.QuestionRequestId
            };
        }

        return dropModel;
    }
}
```

### 2.2 DropsService Extension

**File:** `cimplur-core/Memento/Domain/Repositories/DropsService.cs`

Add new method to support batch loading. Uses the existing `MapDrops` → `OrderedWithImages` pipeline so image/movie pre-signed URL generation is reused exactly:

```csharp
/// <summary>
/// Gets multiple drops by IDs in a single query.
/// Reuses MapDrops + OrderedWithImages for consistent link generation.
/// </summary>
public async Task<List<DropModel>> GetDropsByIds(List<int> dropIds, int viewerUserId)
{
    if (!dropIds.Any())
        return new List<DropModel>();

    var tagIds = groupService.AllNetworkModels(viewerUserId)
        .Select(s => s.TagId).ToList();

    var query = Context.Drops.Where(d => dropIds.Contains(d.DropId));
    var dropModels = await MapDrops(query, dropIds.Count, viewerUserId, 0, tagIds, true);

    return dropModels;
}
```

> **Note:** `MapDrops` is an existing private method that maps `IQueryable<Drop>` to `List<DropModel>` including image/movie links via `OrderedWithImages`. If `MapDrops` is not already `async Task<List<DropModel>>`, the signature will need to be updated and all existing callers audited. Verify before implementing.

### 2.3 QuestionContext in Main Feed

When drops that are question-answers appear in the main feed (`GET /api/drops`), they need `QuestionContext` populated. Add a post-processing step in `DropsService`:

**File:** `cimplur-core/Memento/Domain/Repositories/DropsService.cs`

```csharp
/// <summary>
/// Enriches drop models with question context if they are question responses.
/// Called after OrderedWithImages in feed loading.
/// </summary>
private async Task<List<DropModel>> AddQuestionContext(List<DropModel> dropModels)
{
    var dropIds = dropModels.Select(d => d.DropId).ToList();
    var questionResponses = await Context.QuestionResponses
        .Include(qr => qr.Question)
        .Include(qr => qr.Recipient)
        .Where(qr => dropIds.Contains(qr.DropId))
        .ToDictionaryAsync(qr => qr.DropId);

    foreach (var dropModel in dropModels)
    {
        if (questionResponses.TryGetValue(dropModel.DropId, out var qr))
        {
            dropModel.QuestionContext = new QuestionContextModel
            {
                QuestionId = qr.QuestionId,
                QuestionText = qr.Question.Text,
                QuestionRequestId = qr.Recipient.QuestionRequestId
            };
        }
    }

    return dropModels;
}
```

> **Integration:** In `MapDrops` (around line ~385 of `DropsService.cs`), change:
> ```csharp
> return OrderedWithImages(dropModels);
> ```
> to:
> ```csharp
> var result = OrderedWithImages(dropModels);
> return await AddQuestionContext(result);
> ```
>
> **Important:** This changes `MapDrops` to be async if it wasn't already. Before implementing:
> 1. Verify `MapDrops` current signature
> 2. If changing to async, update all callers to await the result
> 3. Run existing tests to ensure no regressions

### 2.4 Request/Response Models

**File:** `cimplur-core/Memento/Domain/Models/QuestionModels.cs`

```csharp
// Input models
public class QuestionSetCreateModel
{
    public string Name { get; set; }
    public List<string> Questions { get; set; }
}

public class QuestionSetUpdateModel
{
    public string Name { get; set; }
    public List<QuestionUpdateModel> Questions { get; set; }
}

public class QuestionUpdateModel
{
    public int? QuestionId { get; set; }
    public string Text { get; set; }
}

public class RecipientInputModel
{
    public string Email { get; set; }
    public string Alias { get; set; }
}

public class QuestionRequestCreateModel
{
    public int QuestionSetId { get; set; }
    public List<RecipientInputModel> Recipients { get; set; }
    public string Message { get; set; }
}

public class AnswerSubmitModel
{
    public int QuestionId { get; set; }
    public string Content { get; set; }
    public DateTime Date { get; set; }
    public DateTypes DateType { get; set; }
}

public class AnswerUpdateModel
{
    public int QuestionId { get; set; }
    public string Content { get; set; }
    public DateTime Date { get; set; }
    public DateTypes DateType { get; set; }
    public List<int> Images { get; set; }
    public List<int> Movies { get; set; }
}

public class RegisterViaQuestionModel
{
    public string Email { get; set; }
    public string Name { get; set; }
    public bool AcceptTerms { get; set; }
}

// Output models
public class QuestionSetModel
{
    public int QuestionSetId { get; set; }
    public string Name { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public List<QuestionModel> Questions { get; set; }
}

public class QuestionModel
{
    public int QuestionId { get; set; }
    public string Text { get; set; }
    public int SortOrder { get; set; }
}

public class QuestionRequestResultModel
{
    public int QuestionRequestId { get; set; }
    public List<RecipientLinkModel> Recipients { get; set; }
}

public class RecipientLinkModel
{
    public int QuestionRequestRecipientId { get; set; }
    public Guid Token { get; set; }
    public string Email { get; set; }
    public string Alias { get; set; }
}

public class QuestionRequestViewModel
{
    public int QuestionRequestRecipientId { get; set; }
    public string CreatorName { get; set; }
    public string Message { get; set; }
    public string QuestionSetName { get; set; }
    public List<QuestionViewModel> Questions { get; set; }
}

public class QuestionViewModel
{
    public int QuestionId { get; set; }
    public string Text { get; set; }
    public int SortOrder { get; set; }
    public bool IsAnswered { get; set; }
}

public class QuestionContextModel
{
    public int QuestionId { get; set; }
    public string QuestionText { get; set; }
    public int QuestionRequestId { get; set; }
}

public class QuestionResponseFeedModel
{
    public int QuestionRequestId { get; set; }
    public string QuestionSetName { get; set; }
    public DateTime CreatedAt { get; set; }
    public int TotalRecipients { get; set; }
    public int RespondedCount { get; set; }
    public List<QuestionWithResponsesModel> Questions { get; set; }
}

public class QuestionWithResponsesModel
{
    public int QuestionId { get; set; }
    public string Text { get; set; }
    public List<ResponseSummaryModel> Responses { get; set; }
}

public class ResponseSummaryModel
{
    public int DropId { get; set; }
    public string RespondentName { get; set; }
    public DateTime AnsweredAt { get; set; }
    public string ContentPreview { get; set; }
}

public class QuestionRequestDashboardModel
{
    public int QuestionRequestId { get; set; }
    public string QuestionSetName { get; set; }
    public DateTime CreatedAt { get; set; }
    public List<RecipientStatusModel> Recipients { get; set; }
}

public class RecipientStatusModel
{
    public int QuestionRequestRecipientId { get; set; }
    public Guid Token { get; set; }
    public string Alias { get; set; }
    public string Email { get; set; }
    public bool IsActive { get; set; }
    public int AnsweredCount { get; set; }
    public int TotalQuestions { get; set; }
    public DateTime? LastReminderAt { get; set; }
    public int RemindersSent { get; set; }
}
```

### 2.5 Extend DropModel

**File:** `cimplur-core/Memento/Domain/Models/DropModel.cs`

Add to existing DropModel:

```csharp
// Add to existing DropModel class
public QuestionContextModel QuestionContext { get; set; }
```

---

## Phase 3: Controller

**File:** `cimplur-core/Memento/Memento/Controllers/QuestionController.cs`

```csharp
/// <summary>
/// Handles question set management, request distribution, and answer collection.
/// </summary>
[Route("api/questions")]
public class QuestionController : BaseApiController
{
    private readonly QuestionService questionService;
    private readonly UserWebToken userWebToken;
    private readonly ImageService imageService;
    private readonly MovieService movieService;
    private readonly ILogger<QuestionController> logger;

    public QuestionController(
        QuestionService questionService,
        UserWebToken userWebToken,
        ImageService imageService,
        MovieService movieService,
        ILogger<QuestionController> logger)
    {
        this.questionService = questionService;
        this.userWebToken = userWebToken;
        this.imageService = imageService;
        this.movieService = movieService;
        this.logger = logger;
    }

    // ===== QUESTION SET CRUD (Authenticated) =====

    [CustomAuthorization]
    [HttpGet]
    [Route("sets")]
    public async Task<IActionResult> GetQuestionSets([FromQuery] int skip = 0, [FromQuery] int take = 50)
    {
        var sets = await questionService.GetQuestionSets(CurrentUserId, skip, take);
        return Ok(sets);
    }

    [CustomAuthorization]
    [HttpGet]
    [Route("sets/{id:int}")]
    public async Task<IActionResult> GetQuestionSet(int id)
    {
        var set = await questionService.GetQuestionSet(CurrentUserId, id);
        return Ok(set);
    }

    [CustomAuthorization]
    [HttpPost]
    [Route("sets")]
    public async Task<IActionResult> CreateQuestionSet(QuestionSetCreateModel model)
    {
        var set = await questionService.CreateQuestionSet(CurrentUserId, model.Name, model.Questions);
        return Ok(set);
    }

    [CustomAuthorization]
    [HttpPut]
    [Route("sets/{id:int}")]
    public async Task<IActionResult> UpdateQuestionSet(int id, QuestionSetUpdateModel model)
    {
        var set = await questionService.UpdateQuestionSet(CurrentUserId, id, model.Name, model.Questions);
        return Ok(set);
    }

    [CustomAuthorization]
    [HttpDelete]
    [Route("sets/{id:int}")]
    public async Task<IActionResult> DeleteQuestionSet(int id)
    {
        await questionService.DeleteQuestionSet(CurrentUserId, id);
        return Ok();
    }

    // ===== QUESTION REQUEST CREATION (Authenticated) =====

    [CustomAuthorization]
    [HttpPost]
    [Route("requests")]
    public async Task<IActionResult> CreateQuestionRequest(QuestionRequestCreateModel model)
    {
        var result = await questionService.CreateQuestionRequest(
            CurrentUserId,
            model.QuestionSetId,
            model.Recipients,
            model.Message);
        return Ok(result);
    }

    // ===== PUBLIC ANSWER FLOW (No Auth, Rate Limited) =====

    [EnableRateLimiting("public")]
    [HttpGet]
    [Route("answer/{token:guid}")]
    public async Task<IActionResult> GetQuestionsForAnswer(Guid token)
    {
        var view = await questionService.GetQuestionRequestByToken(token);
        return Ok(view);
    }

    [EnableRateLimiting("public")]
    [HttpPost]
    [Route("answer/{token:guid}")]
    public async Task<IActionResult> SubmitAnswer(Guid token, AnswerSubmitModel model)
    {
        var drop = await questionService.SubmitAnswer(
            token,
            model.QuestionId,
            model.Content,
            model.Date,
            model.DateType);
        return Ok(drop);
    }

    [EnableRateLimiting("public")]
    [HttpPut]
    [Route("answer/{token:guid}")]
    public async Task<IActionResult> UpdateAnswer(Guid token, AnswerUpdateModel model)
    {
        var drop = await questionService.UpdateAnswer(
            token,
            model.QuestionId,
            model.Content,
            model.Date,
            model.DateType,
            model.Images,
            model.Movies);
        return Ok(drop);
    }

    [EnableRateLimiting("registration")]
    [HttpPost]
    [Route("answer/{token:guid}/register")]
    public async Task<IActionResult> RegisterViaQuestion(Guid token, RegisterViaQuestionModel model)
    {
        var userId = await questionService.RegisterAndLinkAnswers(
            token,
            model.Email,
            model.Name,
            model.AcceptTerms);

        var jwt = userWebToken.generateJwtToken(userId);
        return Ok(jwt);
    }

    // ===== TOKEN-AUTHENTICATED MEDIA UPLOAD =====

    /// <summary>
    /// Uploads an image to an answer drop, authenticated via recipient token.
    /// </summary>
    [EnableRateLimiting("public")]
    [HttpPost]
    [Route("answer/{token:guid}/images")]
    public async Task<IActionResult> UploadAnswerImage(Guid token)
    {
        var file = HttpContext.Request.Form.Files.Count > 0
            ? HttpContext.Request.Form.Files[0] : null;
        var dropIdParam = HttpContext.Request.Form["dropId"];

        if (file == null)
            return BadRequest("No file provided.");

        if (!int.TryParse(dropIdParam, out var dropId))
            return BadRequest("dropId is required.");

        if (file.ContentType.Split('/')[0] != "image"
            && !file.FileName.ToLower().Contains(".heic"))
            return BadRequest("Only image files are supported.");

        // Verify the token owns a response with this dropId
        var recipient = await questionService.ValidateTokenOwnsDropAsync(token, dropId);
        if (recipient == null)
            return NotFound("Invalid token or drop.");

        var userId = recipient.RespondentUserId
            ?? recipient.QuestionRequest.CreatorUserId;

        var result = await imageService.Add(file, userId, dropId, null);
        return Ok(result);
    }

    /// <summary>
    /// Requests a pre-signed S3 URL for video upload, authenticated via recipient token.
    /// </summary>
    [EnableRateLimiting("public")]
    [HttpPost]
    [Route("answer/{token:guid}/movies/upload/request")]
    public async Task<IActionResult> RequestAnswerMovieUpload(
        Guid token,
        [FromBody] MovieUploadRequestModel request)
    {
        if (request == null || request.DropId <= 0)
            return BadRequest("DropId is required.");

        if (request.FileSize <= 0)
            return BadRequest("FileSize must be greater than 0.");

        if (request.ContentType.Split('/')[0] != "video")
            return BadRequest("Only video files are supported.");

        var recipient = await questionService.ValidateTokenOwnsDropAsync(token, request.DropId);
        if (recipient == null)
            return NotFound("Invalid token or drop.");

        var userId = recipient.RespondentUserId
            ?? recipient.QuestionRequest.CreatorUserId;

        var response = movieService.GetUploadUrl(
            userId,
            request.DropId,
            request.CommentId,
            request.FileSize,
            request.ContentType);

        return Ok(response);
    }

    /// <summary>
    /// Completes a video upload and triggers transcoding, authenticated via recipient token.
    /// </summary>
    [EnableRateLimiting("public")]
    [HttpPost]
    [Route("answer/{token:guid}/movies/upload/complete")]
    public async Task<IActionResult> CompleteAnswerMovieUpload(
        Guid token,
        [FromBody] MovieUploadCompleteModel request)
    {
        if (request == null || request.MovieId <= 0 || request.DropId <= 0)
            return BadRequest("MovieId and DropId are required.");

        var recipient = await questionService.ValidateTokenOwnsDropAsync(token, request.DropId);
        if (recipient == null)
            return NotFound("Invalid token or drop.");

        var userId = recipient.RespondentUserId
            ?? recipient.QuestionRequest.CreatorUserId;

        var result = await movieService.CompleteDirectUpload(
            request.MovieId, userId, request.DropId);

        return Ok(new { success = result });
    }

    // ===== RESPONSE VIEWING (Authenticated) =====

    [CustomAuthorization]
    [HttpGet]
    [Route("responses")]
    public async Task<IActionResult> GetMyQuestionResponses([FromQuery] int skip = 0, [FromQuery] int take = 20)
    {
        var responses = await questionService.GetMyQuestionResponses(CurrentUserId, skip, take);
        return Ok(responses);
    }

    [CustomAuthorization]
    [HttpGet]
    [Route("responses/{requestId:int}/others")]
    public async Task<IActionResult> GetOtherResponses(int requestId)
    {
        var drops = await questionService.GetOtherResponsesToSameQuestions(CurrentUserId, requestId);
        return Ok(drops);
    }

    // ===== REQUEST MANAGEMENT (Authenticated) =====

    [CustomAuthorization]
    [HttpGet]
    [Route("requests/sent")]
    public async Task<IActionResult> GetSentRequests([FromQuery] int skip = 0, [FromQuery] int take = 20)
    {
        var requests = await questionService.GetSentRequests(CurrentUserId, skip, take);
        return Ok(requests);
    }

    [CustomAuthorization]
    [HttpPost]
    [Route("recipients/{recipientId:int}/deactivate")]
    public async Task<IActionResult> DeactivateRecipient(int recipientId)
    {
        await questionService.DeactivateRecipientLink(CurrentUserId, recipientId);
        return Ok();
    }

    [CustomAuthorization]
    [HttpPost]
    [Route("recipients/{recipientId:int}/remind")]
    public async Task<IActionResult> SendReminder(int recipientId)
    {
        await questionService.SendReminder(CurrentUserId, recipientId);
        return Ok();
    }
}
```

### 3.1 Rate Limiting Configuration

This is **new infrastructure** — the project has no existing rate limiting. Requires the built-in ASP.NET Core 7+ rate limiting middleware.

**Step 1: Add NuGet package** (if targeting < .NET 7, otherwise built-in):

```bash
cd cimplur-core/Memento/Memento
dotnet add package Microsoft.AspNetCore.RateLimiting
```

> **Note:** If the project targets .NET 7+, `Microsoft.AspNetCore.RateLimiting` is included by default and no package install is needed.

**Step 2: Configure rate limiting policies**

**File:** `cimplur-core/Memento/Memento/Startup.cs`

Add to `ConfigureServices`:

```csharp
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;

// In ConfigureServices
services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.AddPolicy("public", context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 60,
                Window = TimeSpan.FromMinutes(1)
            }));

    options.AddPolicy("registration", context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(1)
            }));
});
```

**Step 3: Add middleware to pipeline**

**File:** `cimplur-core/Memento/Memento/Startup.cs`

Add to `Configure` method — **after** `UseRouting()` but **before** `UseEndpoints()`:

```csharp
app.UseRouting();
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();      // <-- Add here
app.UseEndpoints(endpoints => { ... });
```

**Step 4: Add using to controller**

```csharp
using Microsoft.AspNetCore.RateLimiting;
```

### 3.2 Register Services in Startup.cs

**File:** `cimplur-core/Memento/Memento/Startup.cs`

Add to `ConfigureServices`:

```csharp
// Interface-based registration for testability
services.AddScoped<IQuestionService, QuestionService>();
services.AddScoped<IQuestionReminderJob, QuestionReminderJob>();
```

> **Note:** Create interfaces `IQuestionService` and `IQuestionReminderJob` matching the public method signatures. This enables mocking in tests and follows the project's DI patterns.

### 3.3 Test Factory Method

**File:** `cimplur-core/Memento/DomainTest/Repositories/TestServiceFactory.cs`

Add to the Content Services region:

```csharp
public static QuestionService CreateQuestionService(
    SharingService sharingService = null,
    GroupService groupService = null,
    UserService userService = null,
    DropsService dropsService = null,
    SendEmailService sendEmailService = null,
    ILogger<QuestionService> logger = null)
{
    sendEmailService = sendEmailService ?? CreateSendEmailService();
    groupService = groupService ?? CreateGroupService(sendEmailService);
    sharingService = sharingService ?? CreateSharingService(sendEmailService, null, groupService);
    userService = userService ?? CreateUserService(sendEmailService);
    dropsService = dropsService ?? CreateDropsService();
    logger = logger ?? new NullLogger<QuestionService>();
    return new QuestionService(sharingService, groupService, userService, dropsService, sendEmailService, logger);
}

public static QuestionReminderJob CreateQuestionReminderJob(
    SendEmailService sendEmailService = null,
    ILogger<QuestionReminderJob> logger = null)
{
    sendEmailService = sendEmailService ?? CreateSendEmailService();
    logger = logger ?? new NullLogger<QuestionReminderJob>();
    return new QuestionReminderJob(sendEmailService, logger);
}
```

> **Note:** Add `using Microsoft.Extensions.Logging.Abstractions;` to the file imports if not already present.

---

## Phase 4: Email Templates

The existing email system uses **Postmark** with inline HTML templates defined in `EmailTemplates.cs`. Each email type has an `EmailTypes` enum value, a body template, and a subject template that use `@Model.*` tokens for string substitution.

### 4.1 New EmailTypes Enum Values

**File:** `cimplur-core/Memento/Domain/Emails/EmailTemplates.cs`

Add new enum values after the existing `ThankEmail = 26`:

```csharp
public enum EmailTypes
{
    // ... existing values ...
    ThankEmail = 26,
    QuestionRequestNotification = 27,
    QuestionRequestReminder = 28,
    QuestionAnswerNotification = 29,
}
```

### 4.2 Email Body Templates

**File:** `cimplur-core/Memento/Domain/Emails/EmailTemplates.cs`

Add cases to the `GetBody()` switch statement:

```csharp
case EmailTypes.QuestionRequestNotification:
    return @"
        <p>@Model.User wants to hear from you!</p>
        <p><i><b>@Model.Question</b></i></p>
        <p>Answer the questions they asked you <a href='@Model.AnswerLink'>here</a>.</p>
        <p>No account needed to respond.</p>";

case EmailTypes.QuestionRequestReminder:
    return @"
        <p>Don't forget to share your memories!</p>
        <p>@Model.User asked you some questions and is waiting for your response.</p>
        <p><i><b>@Model.Question</b></i></p>
        <p>Answer their questions <a href='@Model.AnswerLink'>here</a>.</p>";

case EmailTypes.QuestionAnswerNotification:
    return @"
        <p>@Model.User answered your question!</p>
        <p><i><b>@Model.Question</b></i></p>
        <p>View their answer on <a href='@Model.Link'>Fyli</a>.</p>";
```

### 4.3 Email Subject Templates

Add cases to the `GetSubjectByName()` switch statement:

```csharp
case EmailTypes.QuestionRequestNotification:
    return "@Model.User asked you some questions";

case EmailTypes.QuestionRequestReminder:
    return "Reminder: @Model.User is waiting for your answers";

case EmailTypes.QuestionAnswerNotification:
    return "@Model.User answered your question";
```

### 4.4 Token-Added Emails

Add `QuestionRequestNotification` and `QuestionAnswerNotification` to the `TokenAddedEmails` set so auto-login tokens are included:

```csharp
private static HashSet<EmailTypes> TokenAddedEmails = new HashSet<EmailTypes>{
    // ... existing values ...
    EmailTypes.QuestionReminders,
    EmailTypes.ThankEmail,
    EmailTypes.QuestionRequestNotification,
    EmailTypes.QuestionAnswerNotification,
};
```

> **Note:** `QuestionRequestReminder` is NOT in `TokenAddedEmails` because the recipient may not have an account. The answer link uses the recipient token directly.

---

## Phase 5: Background Job — Automatic Reminders

### 5.1 Reminder Job Service

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionReminderJob.cs`

```csharp
/// <summary>
/// Background job to send automatic reminder emails for unanswered questions.
/// Run daily via scheduled task or background service.
/// </summary>
public class QuestionReminderJob : BaseService
{
    private readonly SendEmailService sendEmailService;
    private readonly ILogger<QuestionReminderJob> logger;

    public QuestionReminderJob(
        SendEmailService sendEmailService,
        ILogger<QuestionReminderJob> logger)
    {
        this.sendEmailService = sendEmailService;
        this.logger = logger;
    }

    /// <summary>
    /// Processes all pending reminders (day 7 and day 14).
    /// </summary>
    public async Task ProcessReminders()
    {
        var now = DateTime.UtcNow;
        var day7Threshold = now.AddDays(-7);

        // Find recipients who need reminders:
        // - Active link
        // - Has email
        // - Less than 2 reminders sent
        // - Incomplete answers (answered < total questions, including zero)
        // - Either: never reminded and created 7+ days ago
        //   Or: reminded once and last reminder was 7+ days ago
        var recipientsNeedingReminder = await Context.QuestionRequestRecipients
            .Include(r => r.QuestionRequest)
                .ThenInclude(qr => qr.Creator)
            .Include(r => r.QuestionRequest)
                .ThenInclude(qr => qr.QuestionSet)
                    .ThenInclude(qs => qs.Questions)
            .Include(r => r.Responses)
            .Where(r => r.IsActive
                && !string.IsNullOrEmpty(r.Email)
                && r.RemindersSent < 2
                && r.Responses.Count < r.QuestionRequest.QuestionSet.Questions.Count
                && (
                    (r.RemindersSent == 0 && r.CreatedAt <= day7Threshold) ||
                    (r.RemindersSent == 1 && r.LastReminderAt <= day7Threshold)
                ))
            .ToListAsync();

        logger.LogInformation("Found {Count} recipients needing reminders", recipientsNeedingReminder.Count);

        foreach (var recipient in recipientsNeedingReminder)
        {
            try
            {
                var firstQuestion = recipient.QuestionRequest.QuestionSet.Questions
                    .OrderBy(q => q.SortOrder)
                    .First().Text;

                var answerLink = $"{Constants.BaseUrl}/q/{recipient.Token}";
                await sendEmailService.SendAsync(
                    recipient.Email,
                    EmailTypes.QuestionRequestReminder,
                    new { User = recipient.QuestionRequest.Creator.Name,
                          Question = firstQuestion,
                          AnswerLink = answerLink });

                recipient.RemindersSent++;
                recipient.LastReminderAt = now;

                logger.LogInformation("Sent reminder {Count} to {Email}",
                    recipient.RemindersSent, recipient.Email);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to send reminder to {Email}", recipient.Email);
            }
        }

        await Context.SaveChangesAsync();
    }
}
```

### 5.2 Job Registration

Use a background service host or scheduled task to run `ProcessReminders()` daily.

---

## API Endpoints Summary

| Endpoint | Auth | Rate Limit | Description |
|----------|------|------------|-------------|
| `GET /api/questions/sets` | JWT | - | List user's question sets |
| `GET /api/questions/sets/{id}` | JWT | - | Get single question set |
| `POST /api/questions/sets` | JWT | - | Create question set |
| `PUT /api/questions/sets/{id}` | JWT | - | Update question set |
| `DELETE /api/questions/sets/{id}` | JWT | - | Archive question set |
| `POST /api/questions/requests` | JWT | - | Create question request |
| `GET /api/questions/answer/{token}` | Token | 60/min | Get questions for public page |
| `POST /api/questions/answer/{token}` | Token | 60/min | Submit answer |
| `PUT /api/questions/answer/{token}` | Token | 60/min | Update answer |
| `POST /api/questions/answer/{token}/images` | Token | 60/min | Upload image to answer |
| `POST /api/questions/answer/{token}/movies/upload/request` | Token | 60/min | Request video upload URL |
| `POST /api/questions/answer/{token}/movies/upload/complete` | Token | 60/min | Complete video upload |
| `POST /api/questions/answer/{token}/register` | Token | 5/min | Register via question link |
| `GET /api/questions/responses` | JWT | - | Get my question responses |
| `GET /api/questions/responses/{id}/others` | JWT | - | View other respondents' answers |
| `GET /api/questions/requests/sent` | JWT | - | Dashboard of sent requests |
| `POST /api/questions/recipients/{id}/deactivate` | JWT | - | Deactivate recipient link |
| `POST /api/questions/recipients/{id}/remind` | JWT | - | Send manual reminder |

---

## Implementation Order

| Phase | Scope | Dependencies |
|-------|-------|--------------|
| **Phase 1** | Entities, migrations, StreamContext | None |
| **Phase 2** | QuestionService + DropsService extension | Phase 1 |
| **Phase 3** | QuestionController + rate limiting | Phase 2 |
| **Phase 4** | Email templates | Phase 2 |
| **Phase 5** | Background reminder job | Phase 4 |

---

*Document Version: 1.6*
*Created: 2026-02-04*
*Updated: 2026-02-05 — Addressed review feedback: pagination limits, email validation, transaction scoping, interface-based DI*
*PRD Version: 1.1*
*Status: Draft*
