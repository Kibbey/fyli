# Technical Design Document: Question Requests

**PRD Reference:** [PRD_QUESTION_REQUESTS.md](/docs/prd/PRD_QUESTION_REQUESTS.md)

---

## Overview

Implement a system that allows users to create question sets, send them to multiple recipients (each with a unique link), and collect answers as memories. Recipients can answer without an account, and responses appear in both the asker's and respondent's feeds.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Vue 3 Frontend                            │
│   QuestionSetViews, QuestionAnswerView, ResponseViews        │
└───────────────────────┬─────────────────────────────────────┘
                        │ HTTPS / JSON
┌───────────────────────▼─────────────────────────────────────┐
│                  C#/.NET Backend                             │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ NEW: QuestionController                                 │ │
│  │   - Question set CRUD (authenticated)                   │ │
│  │   - Send requests (authenticated)                       │ │
│  │   - Public answer submission (token + rate limited)     │ │
│  │   - Token-authenticated media upload (image/video)      │ │
│  │   - Response tracking (authenticated)                   │ │
│  ├────────────────────────────────────────────────────────┤ │
│  │ EXISTING: DropsService                                  │ │
│  │   - Reused for drop loading (no duplication)            │ │
│  │ EXISTING: ImageService, MovieService                    │ │
│  │   - Reused for media upload/S3 operations    
│  │ NEW: QuestionService → Context (EF Core) → PostgreSQL  │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│           │
└──────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Backend — Data Model & Core CRUD

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

## Phase 2: Backend — Service Layer

### 2.1 QuestionService

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`

```csharp
/// <summary>
/// Handles question set management, request distribution, and answer collection.
/// </summary>
public class QuestionService : BaseService
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

    /// <summary>
    /// Creates a question request and generates unique tokens for each recipient.
    /// Sends notification emails asynchronously.
    /// </summary>
    public async Task<QuestionRequestResultModel> CreateQuestionRequest(
        int userId,
        int questionSetId,
        List<RecipientInputModel> recipients,
        string message)
    {
        if (recipients == null || !recipients.Any())
            throw new BadRequestException("At least one recipient is required.");

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
    /// </summary>
    public async Task<int> RegisterAndLinkAnswers(Guid token, string email, string name, bool acceptTerms)
    {
        // Input validation
        if (string.IsNullOrWhiteSpace(email))
            throw new BadRequestException("Email is required.");

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

> **Note:** `MapDrops` is an existing private method that maps `IQueryable<Drop>` to `List<DropModel>` including image/movie links via `OrderedWithImages`. Making it `private` → `private` is fine since `GetDropsByIds` is in the same class. If `MapDrops` access level needs adjustment, change it to `internal`.

### 2.3 Request/Response Models

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

### 2.4 Extend DropModel

**File:** `cimplur-core/Memento/Domain/Models/DropModel.cs`

Add to existing DropModel:

```csharp
// Add to existing DropModel class
public QuestionContextModel QuestionContext { get; set; }
```

### 2.5 Update PermissionService — Check UserDrops for Shared Access

`PermissionService.CanView(userId, dropId)` currently checks only two access paths: group membership (`TagDrops`) and direct ownership (`x.UserId == userId`). When `RegisterAndLinkAnswers` transfers drop ownership from the creator to the respondent, the creator loses access because the drop's `UserId` changes and no `TagDrop` entries exist yet (they're created asynchronously via `PopulateEveryone`).

Adding a `UserDrops` check ensures `GrantDropAccessToUser` (used in `SubmitAnswer`) provides a durable access path that survives ownership transfer.

**File:** `cimplur-core/Memento/Domain/Repositories/PermissionService.cs`

Replace `GetAllDrops`:

```csharp
private IQueryable<Drop> GetAllDrops(int userId)
{
    DateTime now = DateTime.UtcNow.AddHours(1); // give them an extra hour
    var drops = Context.Drops.Where(x =>
        x.TagDrops.Any(t => t.UserTag.TagViewers.Any(a => a.UserId == userId))
        || x.UserId == userId
        || x.OtherUsersDrops.Any(ud => ud.UserId == userId));
    return drops;
}
```

> **Change:** Added `|| x.OtherUsersDrops.Any(ud => ud.UserId == userId)` to the WHERE clause. `OtherUsersDrops` is the existing `UserDrop` navigation collection on the `Drop` entity. This is **100% backwards compatible** — it only broadens visibility, never restricts it.

> **Why this is safe:** The `UserDrops` table is currently used only in limited contexts (test factories, share links). Adding it to `CanView` doesn't change existing behavior because existing drops have no `UserDrop` records unless explicitly created. New `UserDrop` records are only created by `GrantDropAccessToUser` in `QuestionService.SubmitAnswer`.

---

## Phase 3: Backend — Controller

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

The `[EnableRateLimiting("public")]` and `[EnableRateLimiting("registration")]` attributes on controller actions reference the named policies above.

### 3.2 Token-Authenticated Media Upload Endpoints

The existing `ImageController` and `MovieController` require JWT authentication via `[CustomAuthorization]`. Anonymous respondents need to upload media to their answer drops using their **recipient token** instead.

Add these endpoints to `QuestionController`:

```csharp
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
```

> **Note:** The controller constructor in Phase 3 already includes `ImageService` and `MovieService`.

> **Important Limitation:** Token-authenticated media uploads are intended only for the **initial answer flow before registration**. After `RegisterAndLinkAnswers` transfers drop ownership to the respondent, the creator's userId no longer matches the drop's `UserId`, so `ImageService.Add` (which calls `PermissionService.CanView`) would fail for the creator. Post-registration, respondents should use standard JWT-authenticated endpoints (`/api/images`, `/api/movies/*`) for edits. This is acceptable because registered users have JWT tokens.

Add the validation helper to `QuestionService`:

```csharp
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
```

### 3.3 Register Service in Startup.cs

**File:** `cimplur-core/Memento/Memento/Startup.cs`

Add to `ConfigureServices`:

```csharp
services.AddScoped<QuestionService, QuestionService>();
services.AddScoped<QuestionReminderJob, QuestionReminderJob>();
```

### 3.4 Test Factory Method

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

## Phase 4: Frontend — API Services

### 4.1 Question API Service

**File:** `fyli-fe-v2/src/services/questionApi.ts`

```typescript
import api from './api'
import type {
  QuestionSet,
  QuestionSetCreate,
  QuestionSetUpdate,
  QuestionRequestCreate,
  QuestionRequestResult,
  QuestionRequestView,
  AnswerSubmit,
  AnswerUpdate,
  QuestionResponseFeed,
  QuestionRequestDashboard,
  Drop
} from '@/types'

// Question Set CRUD
export function getQuestionSets(skip = 0, take = 50) {
  return api.get<QuestionSet[]>('/questions/sets', { params: { skip, take } })
}

export function getQuestionSet(id: number) {
  return api.get<QuestionSet>(`/questions/sets/${id}`)
}

export function createQuestionSet(data: QuestionSetCreate) {
  return api.post<QuestionSet>('/questions/sets', data)
}

export function updateQuestionSet(id: number, data: QuestionSetUpdate) {
  return api.put<QuestionSet>(`/questions/sets/${id}`, data)
}

export function deleteQuestionSet(id: number) {
  return api.delete(`/questions/sets/${id}`)
}

// Question Request
export function createQuestionRequest(data: QuestionRequestCreate) {
  return api.post<QuestionRequestResult>('/questions/requests', data)
}

// Public Answer Flow (no auth)
export function getQuestionsForAnswer(token: string) {
  return api.get<QuestionRequestView>(`/questions/answer/${token}`)
}

export function submitAnswer(token: string, data: AnswerSubmit) {
  return api.post<Drop>(`/questions/answer/${token}`, data)
}

export function updateAnswer(token: string, data: AnswerUpdate) {
  return api.put<Drop>(`/questions/answer/${token}`, data)
}

export function registerViaQuestion(token: string, email: string, name: string, acceptTerms: boolean) {
  return api.post<string>(`/questions/answer/${token}/register`, {
    email,
    name,
    acceptTerms
  })
}

// Token-Authenticated Media Upload (for anonymous respondents)
export function uploadAnswerImage(token: string, dropId: number, file: File) {
  const formData = new FormData()
  formData.append('file', file)
  formData.append('dropId', dropId.toString())
  return api.post<boolean>(`/questions/answer/${token}/images`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' }
  })
}

export function requestAnswerMovieUpload(
  token: string,
  dropId: number,
  fileSize: number,
  contentType: string
) {
  return api.post(`/questions/answer/${token}/movies/upload/request`, {
    dropId,
    fileSize,
    contentType
  })
}

export function completeAnswerMovieUpload(token: string, movieId: number, dropId: number) {
  return api.post(`/questions/answer/${token}/movies/upload/complete`, {
    movieId,
    dropId
  })
}

// Response Viewing
export function getMyQuestionResponses(skip = 0, take = 20) {
  return api.get<QuestionResponseFeed[]>('/questions/responses', { params: { skip, take } })
}

export function getOtherResponses(requestId: number) {
  return api.get<Drop[]>(`/questions/responses/${requestId}/others`)
}

// Request Management
export function getSentRequests(skip = 0, take = 20) {
  return api.get<QuestionRequestDashboard[]>('/questions/requests/sent', { params: { skip, take } })
}

export function deactivateRecipient(recipientId: number) {
  return api.post(`/questions/recipients/${recipientId}/deactivate`)
}

export function sendReminder(recipientId: number) {
  return api.post(`/questions/recipients/${recipientId}/remind`)
}
```

### 4.2 TypeScript Types

**File:** `fyli-fe-v2/src/types/question.ts`

```typescript
export interface QuestionSet {
  questionSetId: number
  name: string
  createdAt: string
  updatedAt: string
  questions: Question[]
}

export interface Question {
  questionId: number
  text: string
  sortOrder: number
}

export interface QuestionSetCreate {
  name: string
  questions: string[]
}

export interface QuestionSetUpdate {
  name: string
  questions: QuestionUpdate[]
}

export interface QuestionUpdate {
  questionId?: number
  text: string
}

export interface RecipientInput {
  email?: string
  alias?: string
}

export interface QuestionRequestCreate {
  questionSetId: number
  recipients: RecipientInput[]
  message?: string
}

export interface QuestionRequestResult {
  questionRequestId: number
  recipients: RecipientLink[]
}

export interface RecipientLink {
  questionRequestRecipientId: number
  token: string
  email?: string
  alias?: string
}

export interface QuestionRequestView {
  questionRequestRecipientId: number
  creatorName: string
  message?: string
  questionSetName: string
  questions: QuestionView[]
}

export interface QuestionView {
  questionId: number
  text: string
  sortOrder: number
  isAnswered: boolean
}

// DateType: 0=Exact, 1=Month, 2=Year, 3=Decade (matches backend DateTypes enum)
export type DateType = 0 | 1 | 2 | 3

export interface AnswerSubmit {
  questionId: number
  content: string
  date: string
  dateType: DateType
}

export interface AnswerUpdate {
  questionId: number
  content: string
  date: string
  dateType: DateType
  images: number[]
  movies: number[]
}

export interface QuestionResponseFeed {
  questionRequestId: number
  questionSetName: string
  createdAt: string
  totalRecipients: number
  respondedCount: number
  questions: QuestionWithResponses[]
}

export interface QuestionWithResponses {
  questionId: number
  text: string
  responses: ResponseSummary[]
}

export interface ResponseSummary {
  dropId: number
  respondentName: string
  answeredAt: string
  contentPreview: string
}

export interface QuestionRequestDashboard {
  questionRequestId: number
  questionSetName: string
  createdAt: string
  recipients: RecipientStatus[]
}

export interface RecipientStatus {
  questionRequestRecipientId: number
  token: string
  alias?: string
  email?: string
  isActive: boolean
  answeredCount: number
  totalQuestions: number
  lastReminderAt?: string
  remindersSent: number
}

export interface QuestionContext {
  questionId: number
  questionText: string
  questionRequestId: number
}
```

Add to `fyli-fe-v2/src/types/index.ts`:

```typescript
export * from './question'

// Extend existing Drop interface
export interface Drop {
  // ... existing fields
  questionContext?: QuestionContext
}
```

---

## Phase 5: Frontend — Views & Components

### 5.1 Router Updates

**File:** `fyli-fe-v2/src/router/index.ts`

Add new routes:

```typescript
// Question management (authenticated)
{
  path: '/questions',
  name: 'question-sets',
  component: () => import('@/views/question/QuestionSetListView.vue'),
  meta: { auth: true, layout: 'app' }
},
{
  path: '/questions/new',
  name: 'question-set-new',
  component: () => import('@/views/question/QuestionSetEditView.vue'),
  meta: { auth: true, layout: 'app' }
},
{
  path: '/questions/:id/edit',
  name: 'question-set-edit',
  component: () => import('@/views/question/QuestionSetEditView.vue'),
  meta: { auth: true, layout: 'app' }
},
{
  path: '/questions/:id/send',
  name: 'question-send',
  component: () => import('@/views/question/QuestionSendView.vue'),
  meta: { auth: true, layout: 'app' }
},
{
  path: '/questions/dashboard',
  name: 'question-dashboard',
  component: () => import('@/views/question/QuestionDashboardView.vue'),
  meta: { auth: true, layout: 'app' }
},
{
  path: '/questions/responses',
  name: 'question-responses',
  component: () => import('@/views/question/QuestionResponsesView.vue'),
  meta: { auth: true, layout: 'app' }
},

// Public answer flow (no auth)
{
  path: '/q/:token',
  name: 'question-answer',
  component: () => import('@/views/question/QuestionAnswerView.vue'),
  meta: { layout: 'public' }
}
```

### 5.2 Question Set List View

**File:** `fyli-fe-v2/src/views/question/QuestionSetListView.vue`

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { getQuestionSets, deleteQuestionSet } from '@/services/questionApi'
import type { QuestionSet } from '@/types'
import ErrorState from '@/components/ui/ErrorState.vue'
import LoadingSpinner from '@/components/ui/LoadingSpinner.vue'

const router = useRouter()
const sets = ref<QuestionSet[]>([])
const loading = ref(true)
const error = ref('')

onMounted(async () => {
  await loadSets()
})

async function loadSets() {
  loading.value = true
  error.value = ''
  try {
    const { data } = await getQuestionSets()
    sets.value = data
  } catch (e: any) {
    error.value = e.response?.data || 'Failed to load question sets'
  } finally {
    loading.value = false
  }
}

function goToCreate() {
  router.push('/questions/new')
}

function goToEdit(id: number) {
  router.push(`/questions/${id}/edit`)
}

function goToSend(id: number) {
  router.push(`/questions/${id}/send`)
}

async function handleDelete(id: number) {
  if (!confirm('Delete this question set?')) return
  try {
    await deleteQuestionSet(id)
    sets.value = sets.value.filter((s) => s.questionSetId !== id)
  } catch (e: any) {
    error.value = e.response?.data || 'Failed to delete'
  }
}
</script>

<template>
  <div class="container py-4">
    <div class="d-flex justify-content-between align-items-center mb-4">
      <h1 class="h3 mb-0">My Question Sets</h1>
      <button class="btn btn-primary" @click="goToCreate">
        <span class="mdi mdi-plus"></span> New Set
      </button>
    </div>

    <LoadingSpinner v-if="loading" />

    <ErrorState v-else-if="error" :message="error" @retry="loadSets" />

    <div v-else-if="sets.length === 0" class="text-center py-5 text-muted">
      <p>You haven't created any question sets yet.</p>
      <button class="btn btn-primary" @click="goToCreate">Create Your First Set</button>
    </div>

    <div v-else class="list-group">
      <div
        v-for="set in sets"
        :key="set.questionSetId"
        class="list-group-item d-flex justify-content-between align-items-center"
      >
        <div>
          <h5 class="mb-1">{{ set.name }}</h5>
          <small class="text-muted">{{ set.questions.length }} questions</small>
        </div>
        <div class="btn-group">
          <button class="btn btn-sm btn-outline-primary" @click="goToSend(set.questionSetId)">
            Send
          </button>
          <button class="btn btn-sm btn-outline-secondary" @click="goToEdit(set.questionSetId)">
            Edit
          </button>
          <button class="btn btn-sm btn-outline-danger" @click="handleDelete(set.questionSetId)">
            Delete
          </button>
        </div>
      </div>
    </div>

    <div class="mt-4">
      <router-link to="/questions/dashboard" class="btn btn-outline-secondary">
        View Sent Requests
      </router-link>
    </div>
  </div>
</template>
```

### 5.3 Question Answer View (Public) with Optimistic UI

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.vue`

```vue
<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import {
  getQuestionsForAnswer,
  submitAnswer,
  registerViaQuestion,
  uploadAnswerImage,
  requestAnswerMovieUpload,
  completeAnswerMovieUpload
} from '@/services/questionApi'
import type { QuestionRequestView, QuestionView, Drop } from '@/types'
import AnswerForm from '@/components/question/AnswerForm.vue'
import type { AnswerPayload } from '@/components/question/AnswerForm.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import LoadingSpinner from '@/components/ui/LoadingSpinner.vue'

const route = useRoute()
const auth = useAuthStore()
const token = route.params.token as string

const view = ref<QuestionRequestView | null>(null)
const loading = ref(true)
const error = ref('')
const activeQuestionId = ref<number | null>(null)
const answeredDrops = ref<Map<number, Drop>>(new Map())
// Optimistic state for pending submissions
const pendingAnswers = ref<Set<number>>(new Set())

// Registration state
const showRegister = ref(false)
const regEmail = ref('')
const regName = ref('')
const regAcceptTerms = ref(false)
const regSubmitting = ref(false)
const regError = ref('')

const answeredCount = computed(() => {
  if (!view.value) return 0
  return view.value.questions.filter(
    (q) => q.isAnswered || answeredDrops.value.has(q.questionId) || pendingAnswers.value.has(q.questionId)
  ).length
})

const totalCount = computed(() => view.value?.questions.length ?? 0)

onMounted(async () => {
  await loadQuestions()
})

async function loadQuestions() {
  loading.value = true
  error.value = ''
  try {
    const { data } = await getQuestionsForAnswer(token)
    view.value = data
  } catch (e: any) {
    error.value = e.response?.data || 'This question link is no longer active.'
  } finally {
    loading.value = false
  }
}

function startAnswer(questionId: number) {
  activeQuestionId.value = questionId
}

function cancelAnswer() {
  activeQuestionId.value = null
}

async function handleAnswerSubmit(payload: AnswerPayload) {
  const { questionId, content, date, dateType, images, videos } = payload

  // Optimistic update - show as pending immediately
  pendingAnswers.value.add(questionId)
  activeQuestionId.value = null

  try {
    const { data: drop } = await submitAnswer(token, {
      questionId,
      content,
      date,
      dateType
    })

    // Upload images via token-authenticated endpoint
    for (const image of images) {
      await uploadAnswerImage(token, drop.dropId, image)
    }

    // Upload videos via token-authenticated endpoint
    for (const video of videos) {
      const { data: uploadReq } = await requestAnswerMovieUpload(
        token,
        drop.dropId,
        video.size,
        video.type
      )
      // Upload directly to S3 using pre-signed URL
      await fetch(uploadReq.presignedUrl, {
        method: 'PUT',
        body: video,
        headers: { 'Content-Type': video.type }
      })
      await completeAnswerMovieUpload(token, uploadReq.movieId, drop.dropId)
    }

    // Success - move from pending to answered
    pendingAnswers.value.delete(questionId)
    answeredDrops.value.set(questionId, drop)

    // Show registration prompt after first answer
    if (answeredCount.value === 1 && !auth.isAuthenticated) {
      showRegister.value = true
    }
  } catch (e: any) {
    // Rollback optimistic update
    pendingAnswers.value.delete(questionId)
    error.value = e.response?.data || 'Failed to submit answer'
  }
}

async function handleRegister() {
  if (!regEmail.value.trim() || !regName.value.trim()) {
    regError.value = 'Email and name are required'
    return
  }
  if (!regAcceptTerms.value) {
    regError.value = 'You must accept the terms to create an account'
    return
  }

  regSubmitting.value = true
  regError.value = ''

  try {
    const { data: jwt } = await registerViaQuestion(
      token,
      regEmail.value.trim(),
      regName.value.trim(),
      regAcceptTerms.value
    )
    auth.setToken(jwt)
    await auth.fetchUser()
    showRegister.value = false
  } catch (e: any) {
    regError.value = e.response?.data || 'Registration failed'
  } finally {
    regSubmitting.value = false
  }
}
</script>

<template>
  <div class="container py-4" style="max-width: 600px">
    <LoadingSpinner v-if="loading" />

    <ErrorState v-else-if="error && !view" :message="error" />

    <div v-else-if="view">
      <!-- Header -->
      <div class="text-center mb-4">
        <h1 class="h4">{{ view.creatorName }} asked you some questions</h1>
        <p v-if="view.message" class="text-muted">{{ view.message }}</p>
        <div class="badge bg-secondary">
          {{ answeredCount }} of {{ totalCount }} answered
        </div>
      </div>

      <!-- Error banner -->
      <div v-if="error" class="alert alert-danger mb-4">{{ error }}</div>

      <!-- Active Answer Form -->
      <div v-if="activeQuestionId !== null">
        <AnswerForm
          :question="view.questions.find((q) => q.questionId === activeQuestionId)!"
          @submit="handleAnswerSubmit"
          @cancel="cancelAnswer"
        />
      </div>

      <!-- Question List -->
      <div v-else class="list-group mb-4">
        <div
          v-for="q in view.questions"
          :key="q.questionId"
          class="list-group-item"
        >
          <div class="d-flex justify-content-between align-items-start">
            <div>
              <p class="mb-1">{{ q.text }}</p>
              <span
                v-if="pendingAnswers.has(q.questionId)"
                class="badge bg-warning"
              >
                Submitting...
              </span>
              <span
                v-else-if="q.isAnswered || answeredDrops.has(q.questionId)"
                class="badge bg-success"
              >
                Answered
              </span>
            </div>
            <button
              v-if="!q.isAnswered && !answeredDrops.has(q.questionId) && !pendingAnswers.has(q.questionId)"
              class="btn btn-sm btn-primary"
              @click="startAnswer(q.questionId)"
            >
              Answer
            </button>
            <button
              v-else-if="!pendingAnswers.has(q.questionId)"
              class="btn btn-sm btn-outline-secondary"
              @click="startAnswer(q.questionId)"
            >
              Edit
            </button>
          </div>
        </div>
      </div>

      <!-- Registration Prompt -->
      <div v-if="showRegister && !auth.isAuthenticated" class="card">
        <div class="card-body">
          <h5 class="card-title">Keep your memories safe</h5>
          <p class="card-text text-muted">
            Create an account to save your answers to your own feed and get notified when
            {{ view.creatorName }} shares with you.
          </p>

          <div class="mb-3">
            <input
              v-model="regEmail"
              type="email"
              class="form-control mb-2"
              placeholder="Email"
            />
            <input
              v-model="regName"
              type="text"
              class="form-control mb-2"
              placeholder="Your name"
            />
            <div class="form-check">
              <input
                v-model="regAcceptTerms"
                type="checkbox"
                class="form-check-input"
                id="acceptTerms"
              />
              <label class="form-check-label" for="acceptTerms">
                I agree to the <a href="/terms" target="_blank">Terms of Service</a>
              </label>
            </div>
          </div>

          <div v-if="regError" class="alert alert-danger py-2">{{ regError }}</div>

          <div class="d-flex gap-2">
            <button
              class="btn btn-primary"
              :disabled="regSubmitting"
              @click="handleRegister"
            >
              {{ regSubmitting ? 'Creating...' : 'Create Account' }}
            </button>
            <button class="btn btn-link text-muted" @click="showRegister = false">
              Skip for now
            </button>
          </div>
        </div>
      </div>

      <!-- All Done Message -->
      <div v-if="answeredCount === totalCount && !showRegister" class="text-center py-4">
        <p class="text-success mb-2">All questions answered!</p>
        <p class="text-muted">
          {{ view.creatorName }} will be notified of your responses.
        </p>
      </div>
    </div>
  </div>
</template>
```

### 5.4 Answer Form Component

**File:** `fyli-fe-v2/src/components/question/AnswerForm.vue`

```vue
<template>
	<div class="answer-form">
		<div class="card">
			<div class="card-body">
				<div class="question-prompt mb-3 p-3 bg-light rounded border-start border-primary border-4">
					<p class="mb-0 fst-italic">"{{ question.text }}"</p>
				</div>

				<div class="mb-3">
					<textarea
						v-model="content"
						class="form-control"
						rows="4"
						placeholder="Share your memory..."
						maxlength="4000"
					></textarea>
					<small class="text-muted">{{ content.length }}/4000</small>
				</div>

				<div class="mb-3">
					<label class="form-label">When did this happen?</label>
					<input v-model="date" type="date" class="form-control" />
				</div>

				<div class="mb-3">
					<label class="form-label">Photos</label>
					<input
						type="file"
						class="form-control"
						accept="image/*,.heic"
						multiple
						@change="handleImageSelect"
					/>
					<div v-if="selectedImages.length" class="mt-2 d-flex gap-2 flex-wrap">
						<div v-for="(img, i) in imagePreviews" :key="i" class="position-relative">
							<img :src="img.url" class="rounded" style="width: 80px; height: 80px; object-fit: cover" />
							<button
								class="btn btn-sm btn-danger position-absolute top-0 end-0"
								@click="removeImage(i)"
							>
								<span class="mdi mdi-close"></span>
							</button>
						</div>
					</div>
				</div>

				<div class="mb-3">
					<label class="form-label">Videos</label>
					<input
						type="file"
						class="form-control"
						accept="video/*"
						multiple
						@change="handleVideoSelect"
					/>
					<div v-if="videoError" class="text-danger mt-1">{{ videoError }}</div>
					<div v-if="selectedVideos.length" class="mt-2">
						<div v-for="(vid, i) in selectedVideos" :key="i" class="d-flex align-items-center gap-2 mb-1">
							<span class="mdi mdi-video"></span>
							<span>{{ vid.name }} ({{ formatFileSize(vid.size) }})</span>
							<button class="btn btn-sm btn-outline-danger" @click="removeVideo(i)">
								<span class="mdi mdi-close"></span>
							</button>
						</div>
					</div>
				</div>

				<div class="d-flex gap-2">
					<button
						class="btn btn-primary"
						:disabled="!content.trim() || submitting"
						@click="handleSubmit"
					>
						{{ submitting ? 'Submitting...' : 'Submit Answer' }}
					</button>
					<button class="btn btn-outline-secondary" :disabled="submitting" @click="emit('cancel')">
						Cancel
					</button>
				</div>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, onBeforeUnmount } from "vue";
import type { QuestionView } from "@/types";

export interface AnswerPayload {
	questionId: number;
	content: string;
	date: string;
	dateType: number;
	images: File[];
	videos: File[];
}

const MAX_VIDEO_SIZE = 500 * 1024 * 1024; // 500MB

const props = defineProps<{
	question: QuestionView;
}>();

const emit = defineEmits<{
	(e: "submit", payload: AnswerPayload): void;
	(e: "cancel"): void;
}>();

const content = ref("");
const date = ref(new Date().toISOString().split("T")[0]);
const submitting = ref(false);
const selectedImages = ref<File[]>([]);
const selectedVideos = ref<File[]>([]);
const videoError = ref("");

// Manually manage object URLs to avoid memory leaks
const imagePreviews = ref<{ url: string }[]>([]);

function addImagePreviews(files: File[]) {
	for (const file of files) {
		imagePreviews.value.push({ url: URL.createObjectURL(file) });
	}
}

function revokeAllPreviews() {
	for (const preview of imagePreviews.value) {
		URL.revokeObjectURL(preview.url);
	}
	imagePreviews.value = [];
}

onBeforeUnmount(() => {
	revokeAllPreviews();
});

function handleImageSelect(e: Event) {
	const input = e.target as HTMLInputElement;
	if (input.files) {
		const files = Array.from(input.files);
		selectedImages.value.push(...files);
		addImagePreviews(files);
	}
}

function handleVideoSelect(e: Event) {
	const input = e.target as HTMLInputElement;
	videoError.value = "";
	if (input.files) {
		const files = Array.from(input.files);
		const oversized = files.filter((f) => f.size > MAX_VIDEO_SIZE);
		if (oversized.length) {
			videoError.value = `Videos must be under 500 MB. ${oversized.map((f) => f.name).join(", ")} too large.`;
			return;
		}
		selectedVideos.value.push(...files);
	}
}

function removeImage(index: number) {
	URL.revokeObjectURL(imagePreviews.value[index].url);
	imagePreviews.value.splice(index, 1);
	selectedImages.value.splice(index, 1);
}

function removeVideo(index: number) {
	selectedVideos.value.splice(index, 1);
}

function formatFileSize(bytes: number): string {
	if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
	return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function handleSubmit() {
	if (!content.value.trim()) return;
	submitting.value = true;
	emit("submit", {
		questionId: props.question.questionId,
		content: content.value.trim(),
		date: date.value,
		dateType: 0, // DateTypes.Exact
		images: selectedImages.value,
		videos: selectedVideos.value
	});
	// Parent hides this component on success; reset in case it stays visible on error
	submitting.value = false;
}
</script>
```

### 5.5 Question Set Edit View

**File:** `fyli-fe-v2/src/views/question/QuestionSetEditView.vue`

```vue
<template>
	<div class="container py-4" style="max-width: 600px">
		<h1 class="h3 mb-4">{{ isEdit ? "Edit Question Set" : "New Question Set" }}</h1>

		<LoadingSpinner v-if="loading" />
		<ErrorState v-else-if="error" :message="error" @retry="loadSet" />

		<form v-else @submit.prevent="handleSave">
			<div class="mb-3">
				<label class="form-label">Set Name</label>
				<input
					v-model="name"
					type="text"
					class="form-control"
					placeholder="e.g., Christmas Memories 2025"
					maxlength="200"
					required
				/>
			</div>

			<div class="mb-3">
				<label class="form-label">Questions ({{ questions.length }}/5)</label>
				<div v-for="(q, i) in questions" :key="i" class="input-group mb-2">
					<span class="input-group-text">{{ i + 1 }}</span>
					<input
						v-model="questions[i].text"
						type="text"
						class="form-control"
						:placeholder="`Question ${i + 1}`"
						maxlength="500"
					/>
					<button
						v-if="questions.length > 1"
						type="button"
						class="btn btn-outline-danger"
						@click="removeQuestion(i)"
					>
						<span class="mdi mdi-close"></span>
					</button>
				</div>

				<button
					v-if="questions.length < 5"
					type="button"
					class="btn btn-sm btn-outline-secondary"
					@click="addQuestion"
				>
					<span class="mdi mdi-plus"></span> Add Question
				</button>
			</div>

			<div v-if="saveError" class="alert alert-danger">{{ saveError }}</div>

			<div class="d-flex gap-2">
				<button type="submit" class="btn btn-primary" :disabled="saving">
					{{ saving ? "Saving..." : "Save" }}
				</button>
				<router-link to="/questions" class="btn btn-outline-secondary">Cancel</router-link>
			</div>
		</form>
	</div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import {
	getQuestionSet,
	createQuestionSet,
	updateQuestionSet
} from "@/services/questionApi";
import type { QuestionUpdate } from "@/types";
import ErrorState from "@/components/ui/ErrorState.vue";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

const route = useRoute();
const router = useRouter();
const id = computed(() => route.params.id ? Number(route.params.id) : null);
const isEdit = computed(() => id.value !== null);

const name = ref("");
const questions = ref<QuestionUpdate[]>([{ text: "" }]);
const loading = ref(false);
const saving = ref(false);
const error = ref("");
const saveError = ref("");

onMounted(async () => {
	if (isEdit.value) await loadSet();
});

async function loadSet() {
	loading.value = true;
	error.value = "";
	try {
		const { data } = await getQuestionSet(id.value!);
		name.value = data.name;
		questions.value = data.questions.map((q) => ({
			questionId: q.questionId,
			text: q.text
		}));
	} catch (e: any) {
		error.value = e.response?.data || "Failed to load question set";
	} finally {
		loading.value = false;
	}
}

function addQuestion() {
	if (questions.value.length < 5) {
		questions.value.push({ text: "" });
	}
}

function removeQuestion(index: number) {
	questions.value.splice(index, 1);
}

async function handleSave() {
	const validQuestions = questions.value.filter((q) => q.text.trim());
	if (!name.value.trim() || !validQuestions.length) {
		saveError.value = "Name and at least one question are required";
		return;
	}

	saving.value = true;
	saveError.value = "";

	try {
		if (isEdit.value) {
			await updateQuestionSet(id.value!, { name: name.value.trim(), questions: validQuestions });
		} else {
			await createQuestionSet({
				name: name.value.trim(),
				questions: validQuestions.map((q) => q.text.trim())
			});
		}
		router.push("/questions");
	} catch (e: any) {
		saveError.value = e.response?.data || "Failed to save";
	} finally {
		saving.value = false;
	}
}
</script>
```

### 5.6 Question Send View

**File:** `fyli-fe-v2/src/views/question/QuestionSendView.vue`

```vue
<template>
	<div class="container py-4" style="max-width: 600px">
		<h1 class="h3 mb-4">Send Questions</h1>

		<LoadingSpinner v-if="loading" />
		<ErrorState v-else-if="error" :message="error" @retry="loadSet" />

		<div v-else-if="questionSet && !result">
			<div class="card mb-4">
				<div class="card-body">
					<h5>{{ questionSet.name }}</h5>
					<ul class="list-unstyled mb-0">
						<li v-for="q in questionSet.questions" :key="q.questionId" class="mb-1">
							{{ q.sortOrder + 1 }}. {{ q.text }}
						</li>
					</ul>
				</div>
			</div>

			<div class="mb-3">
				<label class="form-label">Recipients</label>
				<div v-for="(r, i) in recipients" :key="i" class="row g-2 mb-2">
					<div class="col">
						<input
							v-model="recipients[i].email"
							type="email"
							class="form-control"
							placeholder="Email (optional)"
						/>
					</div>
					<div class="col">
						<input
							v-model="recipients[i].alias"
							type="text"
							class="form-control"
							placeholder="Name (e.g., Grandma)"
						/>
					</div>
					<div class="col-auto">
						<button
							v-if="recipients.length > 1"
							class="btn btn-outline-danger"
							@click="recipients.splice(i, 1)"
						>
							<span class="mdi mdi-close"></span>
						</button>
					</div>
				</div>
				<button class="btn btn-sm btn-outline-secondary" @click="addRecipient">
					<span class="mdi mdi-plus"></span> Add Recipient
				</button>
			</div>

			<div class="mb-3">
				<label class="form-label">Personal message (optional)</label>
				<textarea
					v-model="message"
					class="form-control"
					rows="2"
					maxlength="1000"
					placeholder="Add a note to your recipients..."
				></textarea>
			</div>

			<div v-if="sendError" class="alert alert-danger">{{ sendError }}</div>

			<button class="btn btn-primary" :disabled="sending" @click="handleSend">
				{{ sending ? "Sending..." : "Send Questions" }}
			</button>
		</div>

		<!-- Result: show generated links -->
		<div v-else-if="result">
			<div class="alert alert-success">Questions sent! Share these links:</div>
			<div class="list-group">
				<div v-for="r in result.recipients" :key="r.questionRequestRecipientId" class="list-group-item">
					<div class="d-flex justify-content-between align-items-center">
						<div>
							<strong>{{ r.alias || r.email || "Recipient" }}</strong>
						</div>
						<button class="btn btn-sm btn-outline-primary" @click="copyLink(r.token)">
							{{ copiedToken === r.token ? 'Copied!' : 'Copy Link' }}
						</button>
					</div>
					<small class="text-muted d-block mt-1">{{ buildLink(r.token) }}</small>
				</div>
			</div>
			<div class="mt-3">
				<router-link to="/questions" class="btn btn-outline-secondary">Back to Question Sets</router-link>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { useRoute } from "vue-router";
import { getQuestionSet, createQuestionRequest } from "@/services/questionApi";
import type { QuestionSet, QuestionRequestResult, RecipientInput } from "@/types";
import ErrorState from "@/components/ui/ErrorState.vue";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

const route = useRoute();
const id = Number(route.params.id);

const questionSet = ref<QuestionSet | null>(null);
const recipients = ref<RecipientInput[]>([{ email: "", alias: "" }]);
const message = ref("");
const result = ref<QuestionRequestResult | null>(null);
const loading = ref(true);
const sending = ref(false);
const error = ref("");
const sendError = ref("");

onMounted(async () => { await loadSet(); });

async function loadSet() {
	loading.value = true;
	error.value = "";
	try {
		const { data } = await getQuestionSet(id);
		questionSet.value = data;
	} catch (e: any) {
		error.value = e.response?.data || "Failed to load question set";
	} finally {
		loading.value = false;
	}
}

function addRecipient() {
	recipients.value.push({ email: "", alias: "" });
}

const copiedToken = ref<string | null>(null);

function buildLink(token: string) {
	return `${window.location.origin}/q/${token}`;
}

async function copyLink(token: string) {
	await navigator.clipboard.writeText(buildLink(token));
	copiedToken.value = token;
	setTimeout(() => {
		if (copiedToken.value === token) copiedToken.value = null;
	}, 2000);
}

async function handleSend() {
	const valid = recipients.value.filter((r) => r.email?.trim() || r.alias?.trim());
	if (!valid.length) {
		sendError.value = "At least one recipient is required";
		return;
	}

	sending.value = true;
	sendError.value = "";

	try {
		const { data } = await createQuestionRequest({
			questionSetId: id,
			recipients: valid,
			message: message.value.trim() || undefined
		});
		result.value = data;
	} catch (e: any) {
		sendError.value = e.response?.data || "Failed to send";
	} finally {
		sending.value = false;
	}
}
</script>
```

### 5.7 Question Dashboard View

**File:** `fyli-fe-v2/src/views/question/QuestionDashboardView.vue`

```vue
<template>
	<div class="container py-4">
		<h1 class="h3 mb-4">Sent Requests</h1>

		<LoadingSpinner v-if="loading" />
		<ErrorState v-else-if="error" :message="error" @retry="loadRequests" />

		<div v-else-if="requests.length === 0" class="text-center py-5 text-muted">
			<p>You haven't sent any question requests yet.</p>
			<router-link to="/questions" class="btn btn-primary">Go to Question Sets</router-link>
		</div>

		<div v-else>
			<div v-for="req in requests" :key="req.questionRequestId" class="card mb-3">
				<div class="card-body">
					<h5 class="card-title">{{ req.questionSetName }}</h5>
					<small class="text-muted">Sent {{ formatDate(req.createdAt) }}</small>

					<div class="mt-3">
						<div v-for="r in req.recipients" :key="r.questionRequestRecipientId" class="d-flex justify-content-between align-items-center py-2 border-bottom">
							<div>
								<span>{{ r.alias || r.email || "Recipient" }}</span>
								<span v-if="!r.isActive" class="badge bg-secondary ms-2">Deactivated</span>
								<span v-else-if="r.answeredCount === r.totalQuestions" class="badge bg-success ms-2">
									Complete
								</span>
								<span v-else-if="r.answeredCount > 0" class="badge bg-warning ms-2">
									{{ r.answeredCount }}/{{ r.totalQuestions }}
								</span>
								<span v-else class="badge bg-light text-dark ms-2">Pending</span>
							</div>
							<div v-if="r.isActive" class="btn-group btn-group-sm">
								<button
									class="btn btn-outline-primary"
									@click="copyLink(r.token)"
								>
									{{ copiedToken === r.token ? 'Copied!' : 'Copy Link' }}
								</button>
								<button
									v-if="r.answeredCount < r.totalQuestions && r.email"
									class="btn btn-outline-secondary"
									:disabled="reminding === r.questionRequestRecipientId"
									@click="handleRemind(r.questionRequestRecipientId)"
								>
									{{ reminding === r.questionRequestRecipientId ? "Sending..." : "Remind" }}
								</button>
								<button
									class="btn btn-outline-danger"
									@click="handleDeactivate(r.questionRequestRecipientId)"
								>
									Deactivate
								</button>
							</div>
						</div>
					</div>
				</div>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { getSentRequests, sendReminder, deactivateRecipient } from "@/services/questionApi";
import type { QuestionRequestDashboard } from "@/types";
import ErrorState from "@/components/ui/ErrorState.vue";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

const requests = ref<QuestionRequestDashboard[]>([]);
const loading = ref(true);
const error = ref("");
const reminding = ref<number | null>(null);
const copiedToken = ref<string | null>(null);

onMounted(async () => { await loadRequests(); });

function buildLink(token: string) {
	return `${window.location.origin}/q/${token}`;
}

async function copyLink(token: string) {
	await navigator.clipboard.writeText(buildLink(token));
	copiedToken.value = token;
	setTimeout(() => {
		if (copiedToken.value === token) copiedToken.value = null;
	}, 2000);
}

async function loadRequests() {
	loading.value = true;
	error.value = "";
	try {
		const { data } = await getSentRequests();
		requests.value = data;
	} catch (e: any) {
		error.value = e.response?.data || "Failed to load requests";
	} finally {
		loading.value = false;
	}
}

async function handleRemind(recipientId: number) {
	reminding.value = recipientId;
	try {
		await sendReminder(recipientId);
	} catch (e: any) {
		error.value = e.response?.data || "Failed to send reminder";
	} finally {
		reminding.value = null;
	}
}

async function handleDeactivate(recipientId: number) {
	if (!confirm("Deactivate this link? The recipient will no longer be able to answer.")) return;
	try {
		await deactivateRecipient(recipientId);
		await loadRequests();
	} catch (e: any) {
		error.value = e.response?.data || "Failed to deactivate";
	}
}

function formatDate(dateStr: string) {
	return new Date(dateStr).toLocaleDateString();
}
</script>
```

### 5.8 Question Responses View

**File:** `fyli-fe-v2/src/views/question/QuestionResponsesView.vue`

```vue
<template>
	<div class="container py-4">
		<h1 class="h3 mb-4">Question Responses</h1>

		<LoadingSpinner v-if="loading" />
		<ErrorState v-else-if="error" :message="error" @retry="loadResponses" />

		<div v-else-if="responses.length === 0" class="text-center py-5 text-muted">
			<p>No responses yet. Send some questions to get started!</p>
			<router-link to="/questions" class="btn btn-primary">Go to Question Sets</router-link>
		</div>

		<div v-else>
			<div v-for="group in responses" :key="group.questionRequestId" class="card mb-4">
				<div class="card-header d-flex justify-content-between align-items-center">
					<div>
						<h5 class="mb-0">{{ group.questionSetName }}</h5>
						<small class="text-muted">
							{{ group.respondedCount }}/{{ group.totalRecipients }} responded
						</small>
					</div>
				</div>

				<div class="card-body">
					<div v-for="q in group.questions" :key="q.questionId" class="mb-4">
						<div class="question-prompt p-2 bg-light rounded border-start border-primary border-4 mb-2">
							<p class="mb-0 fst-italic">"{{ q.text }}"</p>
						</div>

						<div v-if="q.responses.length === 0" class="text-muted ps-3">
							No answers yet
						</div>

						<div v-for="resp in q.responses" :key="resp.dropId" class="ps-3 mb-2 border-start">
							<div class="d-flex justify-content-between">
								<strong>{{ resp.respondentName }}</strong>
								<small class="text-muted">{{ formatDate(resp.answeredAt) }}</small>
							</div>
							<p class="mb-0">{{ resp.contentPreview }}</p>
						</div>
					</div>
				</div>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { getMyQuestionResponses } from "@/services/questionApi";
import type { QuestionResponseFeed } from "@/types";
import ErrorState from "@/components/ui/ErrorState.vue";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

const responses = ref<QuestionResponseFeed[]>([]);
const loading = ref(true);
const error = ref("");

onMounted(async () => { await loadResponses(); });

async function loadResponses() {
	loading.value = true;
	error.value = "";
	try {
		const { data } = await getMyQuestionResponses();
		responses.value = data;
	} catch (e: any) {
		error.value = e.response?.data || "Failed to load responses";
	} finally {
		loading.value = false;
	}
}

function formatDate(dateStr: string) {
	return new Date(dateStr).toLocaleDateString();
}
</script>
```

### 5.9 QuestionContext in Main Feed

When drops that are question-answers appear in the main feed (`GET /api/drops`), they need `QuestionContext` populated. Add a post-processing step in `DropsService`:

**File:** `cimplur-core/Memento/Domain/Repositories/DropsService.cs`

After `OrderedWithImages` returns the drop models, add question context for any drops that are question responses:

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

> **Integration:** In `MapDrops` (line ~385 of `DropsService.cs`), change:
> ```csharp
> return OrderedWithImages(dropModels);
> ```
> to:
> ```csharp
> var result = OrderedWithImages(dropModels);
> return await AddQuestionContext(result);
> ```
> This is a single batch query (no N+1) and adds zero overhead for drops that aren't question responses (the dictionary lookup is O(1) per drop).

### 5.10 Memory Card Update for Question Context

**File:** `fyli-fe-v2/src/components/memory/MemoryCard.vue`

Add question context display (insert before the content section):

```vue
<!-- Add this block before the content display -->
<div v-if="memory.questionContext" class="question-context mb-3">
  <div class="question-quote p-3 bg-light rounded border-start border-primary border-4">
    <small class="text-muted d-block mb-1">Answering:</small>
    <p class="mb-0 fst-italic">"{{ memory.questionContext.questionText }}"</p>
  </div>
</div>
```

---

## Phase 6: Email Templates

The existing email system uses **Postmark** with inline HTML templates defined in `EmailTemplates.cs`. Each email type has an `EmailTypes` enum value, a body template, and a subject template that use `@Model.*` tokens for string substitution.

### 6.1 New EmailTypes Enum Values

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

### 6.2 Email Body Templates

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

### 6.3 Email Subject Templates

Add cases to the `GetSubjectByName()` switch statement:

```csharp
case EmailTypes.QuestionRequestNotification:
    return "@Model.User asked you some questions";

case EmailTypes.QuestionRequestReminder:
    return "Reminder: @Model.User is waiting for your answers";

case EmailTypes.QuestionAnswerNotification:
    return "@Model.User answered your question";
```

### 6.4 Token-Added Emails

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

### 6.5 Updated Service Calls

The `SendAsync(email, EmailTypes, model)` pattern is used everywhere. The model is a dynamic object with properties matching the `@Model.*` tokens.

**In QuestionService.CreateQuestionRequest** (replacing the inline email calls):

```csharp
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
```

**In QuestionService.SendReminder:**

```csharp
var answerLink = $"{Constants.BaseUrl}/q/{recipient.Token}";

await sendEmailService.SendAsync(
    recipient.Email,
    EmailTypes.QuestionRequestReminder,
    new { User = recipient.QuestionRequest.Creator.Name,
          Question = recipient.QuestionRequest.QuestionSet.Questions
              .OrderBy(q => q.SortOrder).First().Text,
          AnswerLink = answerLink });
```

**In QuestionService.SubmitAnswer** (notification to asker, already added above):

```csharp
await sendEmailService.SendAsync(
    creator.Email,
    EmailTypes.QuestionAnswerNotification,
    new { User = respondentName, Question = question.Text, Link = Constants.BaseUrl });
```

### 6.6 Constants.BaseUrl

The existing `Constants` class provides `BaseUrl` which is environment-aware (e.g., `https://localhost:5001` in dev, `https://app.Fyli.com` in production). No new configuration is needed.

---

## Phase 7: Background Job — Automatic Reminders

### 7.1 Reminder Job Service

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

### 7.2 Job Registration

Add to `Startup.cs`:

```csharp
services.AddScoped<QuestionReminderJob, QuestionReminderJob>();
```

Use a background service host or scheduled task to run `ProcessReminders()` daily.

---

## Testing Plan

### Test File Structure

```
cimplur-core/Memento/DomainTest/Repositories/
├── QuestionServiceTest.cs           # QuestionService unit tests
├── QuestionReminderJobTest.cs       # Reminder job tests
├── PermissionServiceTest.cs         # Add UserDrops access test
├── DropsServiceTest.cs              # Add GetDropsByIds and AddQuestionContext tests

fyli-fe-v2/src/components/question/__tests__/
├── AnswerForm.spec.ts
├── QuestionSetListView.spec.ts
├── QuestionSetEditView.spec.ts
├── QuestionSendView.spec.ts
├── QuestionAnswerView.spec.ts
├── QuestionDashboardView.spec.ts
├── QuestionResponsesView.spec.ts
```

### Backend Unit Tests — QuestionServiceTest.cs (38 tests)

#### Question Set CRUD (8 tests)

| Test | Description |
|------|-------------|
| CreateQuestionSet_Valid_ReturnsSetWithQuestions | Creates set with 1-5 questions, verifies all fields |
| CreateQuestionSet_TooManyQuestions_ThrowsBadRequest | Rejects >5 questions with clear error message |
| CreateQuestionSet_EmptyName_ThrowsBadRequest | Validates name is required |
| CreateQuestionSet_NameTooLong_ThrowsBadRequest | Validates name <= 200 characters |
| CreateQuestionSet_EmptyQuestions_ThrowsBadRequest | Validates at least one non-empty question |
| CreateQuestionSet_QuestionTooLong_ThrowsBadRequest | Validates each question <= 500 characters |
| UpdateQuestionSet_NotOwner_ThrowsNotFoundException | Different user ID returns 404 (not 403 to avoid leaking existence) |
| UpdateQuestionSet_DeleteQuestionWithResponses_ThrowsBadRequest | Cannot delete question that has responses |
| UpdateQuestionSet_AddNewQuestions_Success | Can add new questions while preserving existing |
| DeleteQuestionSet_SetsArchivedTrue | Soft delete sets Archived = true, preserves data |

#### Question Request Creation (6 tests)

| Test | Description |
|------|-------------|
| CreateQuestionRequest_GeneratesUniqueTokens | Each recipient gets distinct GUID token |
| CreateQuestionRequest_NoRecipients_ThrowsBadRequest | Validates at least one recipient required |
| CreateQuestionRequest_EmptyRecipientsOnly_ThrowsBadRequest | Recipients with only whitespace are filtered out |
| CreateQuestionRequest_QuestionSetNotOwned_ThrowsNotFoundException | Can't send from another user's question set |
| CreateQuestionRequest_EmptyQuestionSet_ThrowsBadRequest | Question set must have at least one question |
| CreateQuestionRequest_SendsEmailToRecipientsWithEmail | Email service called for each recipient with email |

#### Public Answer Flow (10 tests)

| Test | Description |
|------|-------------|
| GetQuestionRequestByToken_ValidToken_ReturnsView | Returns all questions with answered status |
| GetQuestionRequestByToken_InactiveLink_ThrowsNotFoundException | Deactivated tokens fail with 404 |
| GetQuestionRequestByToken_InvalidToken_ThrowsNotFoundException | Non-existent tokens fail with 404 |
| SubmitAnswer_ValidToken_CreatesDropAndResponse | Creates Drop, ContentDrop, and QuestionResponse |
| SubmitAnswer_EmptyContent_ThrowsBadRequest | Validates content is required |
| SubmitAnswer_ContentTooLong_ThrowsBadRequest | Validates content <= 4000 characters |
| SubmitAnswer_AlreadyAnswered_ThrowsBadRequest | Returns clear error if question already answered |
| SubmitAnswer_QuestionNotInSet_ThrowsNotFoundException | Wrong questionId for this token fails |
| SubmitAnswer_SendsNotificationEmail | Asker receives QuestionAnswerNotification email |
| SubmitAnswer_AnonymousUser_DropOwnedByCreator | When no respondentUserId, drop.UserId = creatorUserId |

#### Answer Update (4 tests)

| Test | Description |
|------|-------------|
| UpdateAnswer_WithinEditWindow_Success | Anonymous users can edit within 7 days |
| UpdateAnswer_AnonymousAfter7Days_ThrowsBadRequest | Anonymous users blocked after 7 days |
| UpdateAnswer_RegisteredUser_NoTimeLimit | Registered users can edit anytime |
| UpdateAnswer_MediaValidation_InvalidIds_ThrowsBadRequest | Image/movie IDs must belong to the drop |

#### Registration & Linking (6 tests)

| Test | Description |
|------|-------------|
| RegisterAndLinkAnswers_NewUser_CreatesAccountAndTransfersOwnership | New user created, all drops transferred |
| RegisterAndLinkAnswers_ExistingUser_LinksWithoutCreating | Finds existing user by email, links answers |
| RegisterAndLinkAnswers_CreatesConnection | EnsureConnectionAsync called between creator and respondent |
| RegisterAndLinkAnswers_CreatorRetainsAccess | Creator gets UserDrop record for each transferred drop |
| RegisterAndLinkAnswers_PopulatesEveryone | PopulateEveryone called for both users |
| RegisterAndLinkAnswers_EmptyEmail_ThrowsBadRequest | Email is required |
| RegisterAndLinkAnswers_EmptyName_ThrowsBadRequest | Name is required |
| RegisterAndLinkAnswers_TermsNotAccepted_ThrowsBadRequest | Must accept terms |

#### Response Viewing (4 tests)

| Test | Description |
|------|-------------|
| GetMyQuestionResponses_OnlyLoadsRespondedRecipients | Excludes recipients with no responses |
| GetMyQuestionResponses_IncludesTotalRecipientCount | Separate count query for dashboard display |
| GetOtherResponses_OnlyShowsAccountHolders | Anonymous respondents' answers are hidden |
| GetOtherResponses_NotParticipant_ThrowsNotFoundException | Non-participants can't view responses |

#### Request Management (4 tests)

| Test | Description |
|------|-------------|
| DeactivateRecipientLink_SetsIsActiveFalse | Link becomes inactive |
| DeactivateRecipientLink_NotOwner_ThrowsNotAuthorizedException | Only creator can deactivate |
| SendReminder_UpdatesReminderCount | Increments RemindersSent and sets LastReminderAt |
| SendReminder_NoEmail_ThrowsBadRequest | Recipient must have email address |

#### Token Validation (3 tests)

| Test | Description |
|------|-------------|
| ValidateTokenOwnsDropAsync_ValidTokenAndDrop_ReturnsRecipient | Returns recipient with QuestionRequest loaded |
| ValidateTokenOwnsDropAsync_InvalidToken_ReturnsNull | Non-existent token returns null |
| ValidateTokenOwnsDropAsync_WrongDrop_ReturnsNull | Token doesn't own that dropId returns null |

### Backend Unit Tests — PermissionServiceTest.cs (2 new tests)

| Test | Description |
|------|-------------|
| CanView_UserHasUserDropAccess_ReturnsTrue | User with UserDrop record can view drop they don't own |
| GetAllDrops_IncludesUserDrops | Query includes drops accessible via OtherUsersDrops |

### Backend Unit Tests — DropsServiceTest.cs (3 new tests)

| Test | Description |
|------|-------------|
| GetDropsByIds_ReturnsDropsWithImageLinks | Batch load includes pre-signed URLs |
| GetDropsByIds_EmptyList_ReturnsEmptyList | No error on empty input |
| AddQuestionContext_EnrichesDropsWithQuestionData | Drops that are answers get QuestionContext populated |

### Backend Unit Tests — QuestionReminderJobTest.cs (4 tests)

| Test | Description |
|------|-------------|
| ProcessReminders_Day7_SendsFirstReminder | Recipients created 7+ days ago get reminder |
| ProcessReminders_Day14_SendsSecondReminder | Recipients with 1 reminder sent 7+ days ago get second |
| ProcessReminders_MaxTwoReminders | Recipients with 2 reminders sent are skipped |
| ProcessReminders_PartialAnswers_StillSendsReminder | Recipients with incomplete answers receive reminders |
| ProcessReminders_CompleteAnswers_Skipped | Recipients who answered all questions are skipped |

### Frontend Component Tests (15 tests)

#### AnswerForm.spec.ts (4 tests)

| Test | Description |
|------|-------------|
| AnswerForm_SubmitsPayloadOnClick | Emits AnswerPayload object with all fields |
| AnswerForm_DisablesButtonWhenSubmitting | Submit button disabled while submitting |
| AnswerForm_VideoSizeValidation | Shows error for videos over 500MB |
| AnswerForm_RevokesObjectURLsOnUnmount | No memory leaks from image previews |

#### QuestionSetListView.spec.ts (2 tests)

| Test | Description |
|------|-------------|
| QuestionSetListView_LoadsAndDisplaysSets | Renders list of question sets |
| QuestionSetListView_ShowsErrorOnFailure | ErrorState component displayed on API error |

#### QuestionSetEditView.spec.ts (2 tests)

| Test | Description |
|------|-------------|
| QuestionSetEditView_AddRemoveQuestions | Add/remove buttons work correctly |
| QuestionSetEditView_SavesChanges | Calls createQuestionSet or updateQuestionSet |

#### QuestionSendView.spec.ts (2 tests)

| Test | Description |
|------|-------------|
| QuestionSendView_GeneratesLinks | Shows links after successful send |
| QuestionSendView_CopyLinkFeedback | Copy button shows "Copied!" for 2 seconds |

#### QuestionAnswerView.spec.ts (3 tests)

| Test | Description |
|------|-------------|
| QuestionAnswerView_TracksProgress | Progress indicator shows X of Y answered |
| QuestionAnswerView_OptimisticUI | Shows pending state immediately on submit |
| QuestionAnswerView_RegistrationFlow | Shows registration prompt after first answer |

#### QuestionDashboardView.spec.ts (1 test)

| Test | Description |
|------|-------------|
| QuestionDashboardView_ShowsRecipientStatus | Displays badges for pending/partial/complete |

#### QuestionResponsesView.spec.ts (1 test)

| Test | Description |
|------|-------------|
| QuestionResponsesView_GroupsResponsesByQuestion | Shows responses organized under questions |

### Integration Tests (12 tests)

| Test | Description |
|------|-------------|
| FullAnswerFlow_NoAccount | Answer all questions without registration |
| FullAnswerFlow_WithRegistration | Answer → register → verify drop ownership transferred |
| FullAnswerFlow_WithImageUpload | Upload image via token-authenticated endpoint |
| FullAnswerFlow_WithVideoUpload | Request presigned URL, upload, complete via token endpoints |
| CrossDeviceAnswer_SameToken | Same token works across different sessions |
| TokenMediaUpload_InvalidToken_Returns404 | Wrong token can't upload media |
| TokenMediaUpload_WrongDrop_Returns404 | Token can't upload to drop it doesn't own |
| RateLimiting_PublicEndpoints_60PerMinute | Rate limits enforced on /questions/answer/* |
| RateLimiting_Registration_5PerMinute | Stricter rate limit on /register endpoint |
| ReminderJob_SendsAtCorrectTimes | Day 7 and 14 reminders sent correctly |
| QuestionContext_AppearsInMainFeed | GET /api/drops returns QuestionContext for answers |
| CreatorRetainsAccess_AfterOwnershipTransfer | Creator can still view drops after RegisterAndLinkAnswers |

### Test Coverage Summary

| Area | Tests | Critical Paths Covered |
|------|-------|------------------------|
| QuestionService | 38 | CRUD, public flow, registration, management |
| PermissionService | 2 | UserDrops access check |
| DropsService | 3 | Batch loading, question context |
| QuestionReminderJob | 5 | Timing, filtering, partial answers |
| Frontend Components | 15 | All 8 views/components |
| Integration | 12 | End-to-end flows, security, rate limiting |
| **Total** | **75** | |

### Test Data Fixtures

Create a `QuestionTestFixtures.cs` helper class:

```csharp
public static class QuestionTestFixtures
{
    public static QuestionSet CreateQuestionSet(StreamContext context, int userId, string name = "Test Set")
    {
        var qs = new QuestionSet
        {
            UserId = userId,
            Name = name,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
            Questions = new List<Question>
            {
                new Question { Text = "Question 1?", SortOrder = 0, CreatedAt = DateTime.UtcNow },
                new Question { Text = "Question 2?", SortOrder = 1, CreatedAt = DateTime.UtcNow }
            }
        };
        context.QuestionSets.Add(qs);
        context.SaveChanges();
        return qs;
    }

    public static QuestionRequestRecipient CreateRecipient(
        StreamContext context,
        QuestionRequest request,
        string email = "test@example.com",
        string alias = "Test Recipient")
    {
        var recipient = new QuestionRequestRecipient
        {
            QuestionRequestId = request.QuestionRequestId,
            Token = Guid.NewGuid(),
            Email = email,
            Alias = alias,
            IsActive = true,
            CreatedAt = DateTime.UtcNow
        };
        context.QuestionRequestRecipients.Add(recipient);
        context.SaveChanges();
        return recipient;
    }
}
```

---

## Implementation Order

| Phase | Scope | Dependencies |
|-------|-------|--------------|
| **Phase 1** | Backend entities, migrations, StreamContext | None |
| **Phase 2** | Backend QuestionService + DropsService extension | Phase 1 |
| **Phase 3** | Backend QuestionController + rate limiting | Phase 2 |
| **Phase 4** | Frontend API services, types | Phase 3 |
| **Phase 5** | Frontend views and components | Phase 4 |
| **Phase 6** | Email templates | Phase 2 |
| **Phase 7** | Background reminder job | Phase 6 |

Phases 1-3 (backend) should be completed before frontend work begins. Phases 6-7 can run in parallel with Phase 5.

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

> **Auth types:** JWT = `[CustomAuthorization]` requiring Bearer token. Token = recipient GUID token in URL path (validated by `QuestionService.ValidateTokenOwnsDropAsync`).

---

## Code Review Feedback Addressed

### Review 1 (v1.0 → v1.1)

| Issue | Resolution |
|-------|------------|
| Circular FK between Drop and QuestionResponse | Removed `QuestionResponseId` from Drop; one-way FK only |
| Missing rate limiting on public endpoints | Added `[EnableRateLimiting]` attributes |
| Missing input validation | Added comprehensive validation in all service methods |
| LoadDropModel duplicates DropsService | Refactored to use DropsService.Drop() and GetDropsByIds() |
| Fire-and-forget email without error handling | Wrapped in try-catch with logging |
| N+1 query in GetOtherResponsesToSameQuestions | Added batch loading via DropsService.GetDropsByIds() |
| Missing summary comments | Added XML doc comments to all public methods |
| Missing error states in frontend | Added ErrorState and LoadingSpinner components |
| Missing unique constraint on responses | Added unique index on (QuestionRequestRecipientId, QuestionId) |
| Missing pagination | Added skip/take to list endpoints |
| Missing index on AnsweredAt | Added index for chronological queries |
| Optimistic UI missing | Added pendingAnswers state for immediate feedback |

### Review 2 (v1.1 → v1.2)

| Issue | Severity | Resolution |
|-------|----------|------------|
| DropsService method name mismatch (`GetDrop` vs `Drop`) | Critical | Changed to `dropsService.Drop(viewerUserId, dropId)` matching actual signature |
| `MapToDropModel` doesn't exist in DropsService | Critical | Rewrote `GetDropsByIds` to use existing `MapDrops` pipeline |
| SendEmailService API mismatch (inline HTML vs Postmark templates) | Critical | Rewrote to use `SendAsync(email, EmailTypes, model)` with new enum values and template definitions |
| Anonymous media upload path undefined | Critical | Added token-authenticated endpoints on QuestionController (`/answer/{token}/images`, `/answer/{token}/movies/*`) |
| Rate limiting is new infrastructure (not configured) | Critical | Added full setup: NuGet package, policy config, middleware order, using statements |
| `DateType` as `int` instead of `DateTypes` enum | Improvement | Changed model to use `DateTypes` enum directly, removed casts |
| Missing answer notification email | Improvement | Added `SendAsync` call with `QuestionAnswerNotification` in `SubmitAnswer` |
| `UpdateDropMedia` doesn't handle new additions | Improvement | Added validation that new media IDs belong to the drop |
| `GetMyQuestionResponses` loads excessive data | Improvement | Filtered to only load recipients with responses; separate count query for totals |
| Terms checkbox missing from registration UI | Suggestion | Added `regAcceptTerms` state and checkbox with Terms of Service link |
| Missing view implementations (4 views) | Suggestion | Added QuestionSetEditView, QuestionSendView, QuestionDashboardView, QuestionResponsesView |
| Missing AnswerForm component | Suggestion | Added full AnswerForm.vue with text, date, image, and video upload support |
| QuestionContext not populated in main feed | Suggestion | Added `AddQuestionContext` batch method to DropsService for feed enrichment |

### Review 3 (v1.2 → v1.3)

| Issue | Severity | Resolution |
|-------|----------|------------|
| `GrantDropAccessToUser` creates `UserDrop` but `CanView` doesn't check `UserDrops` — creator loses access after ownership transfer | Critical | Added Phase 2.5: update `PermissionService.GetAllDrops` to include `x.OtherUsersDrops.Any(ud => ud.UserId == userId)`. Backwards compatible (broadens access only). |
| `QuestionAnswerNotification` template uses `@Model.Link` but model doesn't include `Link` property | Critical | Added `Link = Constants.BaseUrl` to both the `SubmitAnswer` email model and the Phase 6.5 reference call |
| `AnswerForm` submitting state never resets — button stays disabled if parent doesn't unmount | Improvement | Reset `submitting = false` after emit; disabled cancel button while submitting |
| `AnswerForm` emit uses 6 positional args — fragile and error-prone | Improvement | Changed to single `AnswerPayload` object; updated `QuestionAnswerView` handler to destructure |
| `imagePreviews` computed creates `URL.createObjectURL` on every re-evaluation without revoking — memory leak | Improvement | Replaced with manual `ref<{ url: string }[]>` management; revoke on remove and `onBeforeUnmount` |
| Frontend `AnswerSubmit.dateType` typed as `number` — loses domain meaning | Improvement | Added `DateType = 0 \| 1 \| 2 \| 3` union type with comment mapping to backend enum |
| Inconsistent catch blocks — some views swallow error messages, others capture `e.response?.data` | Improvement | Updated all catch blocks to use `e.response?.data \|\| 'fallback message'` pattern consistently |
| No client-side video size validation — 500MB limit only enforced server-side | Suggestion | Added `MAX_VIDEO_SIZE` check in `handleVideoSelect` with error message listing oversized files |
| Remind button only shows when `answeredCount === 0` — hides for partially-answered recipients | Suggestion | Changed condition to `r.answeredCount < r.totalQuestions` so partial responders are also remindable |
| Copy link button has no visual feedback | Suggestion | Added `copiedToken` state with 2-second timeout; button text changes to "Copied!" |
| `AddQuestionContext` integration point in `MapDrops` is vague | Suggestion | Specified exact code change: replace `return OrderedWithImages(dropModels)` with intermediate variable and `await AddQuestionContext(result)` |

### Review 4 (v1.3 → v1.4)

| Issue | Severity | Resolution |
|-------|----------|------------|
| Migration SQL uses PostgreSQL syntax but project uses SQL Server | Critical | Rewrote all SQL to SQL Server syntax: `IDENTITY` instead of `SERIAL`, `DATETIME2` instead of `TIMESTAMPTZ`, `BIT` instead of `BOOLEAN`, `UNIQUEIDENTIFIER` instead of `UUID`, `NVARCHAR` for Unicode, square brackets instead of quotes |
| Token-auth media upload fails after ownership transfer — `ImageService.Add` calls `CanView` which fails when creator's userId doesn't match drop's new `UserId` | Improvement | Added documentation note in Phase 3.2 explaining that token-authenticated uploads are for initial answer flow only; post-registration edits should use JWT endpoints |
| No `PermissionService` test for `OtherUsersDrops` check added in Phase 2.5 | Improvement | Added 2 tests to PermissionServiceTest.cs in expanded testing plan |
| Missing `TestServiceFactory.CreateQuestionService` method | Improvement | Added Phase 3.4 with `CreateQuestionService` and `CreateQuestionReminderJob` factory methods |
| `RegisterAndLinkAnswers` doesn't create `UserDrop` for creator — relies on timing of `PopulateEveryone` | Improvement | Added explicit `GrantDropAccessToUser(response.DropId, creatorUserId)` call before ownership transfer |
| `RecipientStatusModel` missing `Token` field — can't re-copy links from dashboard | Suggestion | Added `Token` property to backend model, TypeScript type, and `GetSentRequests` projection |
| Dashboard view missing copy link functionality | Suggestion | Added `copyLink` function and "Copy Link" button to QuestionDashboardView |
| Reminder job only sends for `!r.Responses.Any()` — misses partial responders | Suggestion | Changed filter to `r.Responses.Count < r.QuestionRequest.QuestionSet.Questions.Count` |
| Testing plan inadequate — only 23 backend tests, 7 frontend tests | Improvement | Expanded to 75 tests: 48 backend (38 QuestionService + 2 Permission + 3 Drops + 5 ReminderJob), 15 frontend, 12 integration |

---

*Document Version: 1.4*
*Created: 2026-02-04*
*Updated: 2026-02-05 — Addressed fourth code review feedback, expanded testing plan*
*PRD Version: 1.1*
*Status: Draft*
