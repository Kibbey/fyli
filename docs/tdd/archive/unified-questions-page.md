# TDD: Unified Questions Page

**PRD:** `docs/prd/PRD_UNIFIED_QUESTIONS_PAGE.md`
**Related TDDs:** `docs/tdd/question-requests.md`, `docs/tdd/question-answer-ux-consistency.md`

## Overview

Combines `/questions` (set management) and `/questions/requests` (response tracking) into a single unified page. Each question set is displayed as a lifecycle card showing draft/sent/response status. Responses from multiple sends aggregate under one card. The create+send flow is merged into a single multi-step wizard. Email becomes required for recipients, and previously sent-to recipients are suggested for re-selection.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     QuestionController                       │
│  GET /sets/unified     GET /recipients/previous              │
│  POST /requests (updated validation)                         │
├──────────────────────────────────────────────────────────────┤
│                     QuestionService                          │
│  GetUnifiedQuestionSets()    GetPreviousRecipients()         │
│  CreateQuestionRequest() (email required + dedup)            │
├──────────────────────────────────────────────────────────────┤
│                     StreamContext (EF Core)                   │
│  QuestionSets → QuestionRequests → Recipients → Responses    │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                     Frontend (Vue 3)                          │
│  UnifiedQuestionsView → QuestionSetCard                      │
│  AskQuestionsView (multi-step wizard)                        │
│  questionApi.ts (new endpoints)                              │
│  types/question.ts (new types)                               │
└──────────────────────────────────────────────────────────────┘
```

## Implementation Phases

---

## Phase 1: Backend — New Endpoints + Sending Changes

### 1.1 New Models

**File:** `cimplur-core/Memento/Domain/Models/QuestionModels.cs`

Add to end of file:

```csharp
// ===== UNIFIED PAGE MODELS =====

/// <summary>
/// Question set with aggregated response data across all sends.
/// Used by the unified /questions page.
/// </summary>
public class UnifiedQuestionSetModel
{
    public int QuestionSetId { get; set; }
    public string Name { get; set; }
    public int QuestionCount { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    /// <summary>Total recipients across all sends.</summary>
    public int TotalRecipients { get; set; }

    /// <summary>Recipients who answered at least one question.</summary>
    public int RespondedRecipients { get; set; }

    /// <summary>Most recent answer or send date. Null for draft sets.</summary>
    public DateTime? LatestActivity { get; set; }

    /// <summary>Human-readable description of latest activity.</summary>
    public string LatestActivityDescription { get; set; }

    /// <summary>All sends grouped with full recipient details.</summary>
    public List<UnifiedRequestModel> Requests { get; set; } = new();
}

/// <summary>
/// A single send instance within a unified question set view.
/// </summary>
public class UnifiedRequestModel
{
    public int QuestionRequestId { get; set; }
    public DateTime CreatedAt { get; set; }
    public string Message { get; set; }
    public List<RecipientDetailModel> Recipients { get; set; } = new();
}

/// <summary>
/// A previous recipient the user has sent questions to.
/// </summary>
public class PreviousRecipientModel
{
    public string Email { get; set; }
    public string Alias { get; set; }
    public DateTime LastSentAt { get; set; }
}
```

### 1.2 New Service Methods

**File:** `cimplur-core/Memento/Domain/Repositories/IQuestionService.cs`

Add to interface:

```csharp
// Unified Page
Task<List<UnifiedQuestionSetModel>> GetUnifiedQuestionSets(int userId, int skip = 0, int take = 20);
Task<List<PreviousRecipientModel>> GetPreviousRecipients(int userId);
```

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`

#### GetUnifiedQuestionSets

Add after the `GetSentRequests` method:

```csharp
/// <summary>
/// Gets question sets with aggregated response data for the unified page.
/// Uses a two-phase approach: lightweight summary query for sorting/pagination,
/// then full detail load only for the page of results.
/// </summary>
public async Task<List<UnifiedQuestionSetModel>> GetUnifiedQuestionSets(int userId, int skip = 0, int take = 20)
{
    take = Math.Min(take, 100);

    // Phase 1: Lightweight query for sorting and pagination (no media/content)
    var summaries = await Context.QuestionSets
        .Where(qs => qs.UserId == userId && !qs.Archived)
        .Select(qs => new
        {
            qs.QuestionSetId,
            qs.Name,
            QuestionCount = qs.Questions.Count,
            qs.CreatedAt,
            qs.UpdatedAt,
            TotalRecipients = qs.Requests.SelectMany(r => r.Recipients).Count(),
            RespondedRecipients = qs.Requests
                .SelectMany(r => r.Recipients)
                .Count(r => r.Responses.Any()),
            LatestAnswer = qs.Requests
                .SelectMany(r => r.Recipients)
                .SelectMany(r => r.Responses)
                .OrderByDescending(resp => resp.AnsweredAt)
                .Select(resp => (DateTime?)resp.AnsweredAt)
                .FirstOrDefault(),
            LatestSend = qs.Requests
                .OrderByDescending(r => r.CreatedAt)
                .Select(r => (DateTime?)r.CreatedAt)
                .FirstOrDefault()
        })
        .ToListAsync();

    // Sort in memory (lightweight objects only) then paginate
    var sortedIds = summaries
        .Select(s => new
        {
            s.QuestionSetId,
            s.TotalRecipients,
            s.RespondedRecipients,
            LatestActivity = s.LatestAnswer.HasValue && s.LatestSend.HasValue
                ? (s.LatestAnswer > s.LatestSend ? s.LatestAnswer : s.LatestSend)
                : s.LatestAnswer ?? s.LatestSend,
            s.CreatedAt
        })
        .OrderByDescending(s => s.TotalRecipients > 0 && s.RespondedRecipients < s.TotalRecipients ? 1 : 0)
        .ThenByDescending(s => s.LatestActivity ?? DateTime.MinValue)
        .ThenByDescending(s => s.CreatedAt)
        .Skip(skip)
        .Take(take)
        .Select(s => s.QuestionSetId)
        .ToList();

    if (!sortedIds.Any())
        return new List<UnifiedQuestionSetModel>();

    // Phase 2: Full detail load only for the paginated set
    var questionSets = await Context.QuestionSets
        .Where(qs => sortedIds.Contains(qs.QuestionSetId))
        .Include(qs => qs.Questions)
        .Include(qs => qs.Requests)
            .ThenInclude(qr => qr.Recipients)
                .ThenInclude(r => r.Respondent)
        .Include(qs => qs.Requests)
            .ThenInclude(qr => qr.Recipients)
                .ThenInclude(r => r.Responses)
                    .ThenInclude(resp => resp.Drop)
                        .ThenInclude(d => d.ContentDrop)
        .Include(qs => qs.Requests)
            .ThenInclude(qr => qr.Recipients)
                .ThenInclude(r => r.Responses)
                    .ThenInclude(resp => resp.Drop)
                        .ThenInclude(d => d.Images)
        .Include(qs => qs.Requests)
            .ThenInclude(qr => qr.Recipients)
                .ThenInclude(r => r.Responses)
                    .ThenInclude(resp => resp.Drop)
                        .ThenInclude(d => d.Movies)
        .Include(qs => qs.Requests)
            .ThenInclude(qr => qr.Recipients)
                .ThenInclude(r => r.Responses)
                    .ThenInclude(resp => resp.Question)
        .AsSplitQuery()
        .ToListAsync();

    // Build result preserving the sort order from Phase 1
    var qsLookup = questionSets.ToDictionary(qs => qs.QuestionSetId);
    var result = new List<UnifiedQuestionSetModel>();

    foreach (var id in sortedIds)
    {
        if (!qsLookup.TryGetValue(id, out var qs)) continue;

        var allRecipients = qs.Requests.SelectMany(r => r.Recipients).ToList();
        var totalRecipients = allRecipients.Count;
        var respondedRecipients = allRecipients.Count(r => r.Responses.Any());

        // Find latest activity
        DateTime? latestAnswer = allRecipients
            .SelectMany(r => r.Responses)
            .OrderByDescending(resp => resp.AnsweredAt)
            .Select(resp => (DateTime?)resp.AnsweredAt)
            .FirstOrDefault();

        DateTime? latestSend = qs.Requests
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => (DateTime?)r.CreatedAt)
            .FirstOrDefault();

        DateTime? latestActivity = latestAnswer.HasValue && latestSend.HasValue
            ? (latestAnswer > latestSend ? latestAnswer : latestSend)
            : latestAnswer ?? latestSend;

        // Build activity description
        string activityDescription = null;
        if (latestAnswer.HasValue)
        {
            var latestResp = allRecipients
                .SelectMany(r => r.Responses.Select(resp => new { Recipient = r, Response = resp }))
                .OrderByDescending(x => x.Response.AnsweredAt)
                .First();
            var name = ResolveRespondentName(latestResp.Recipient);
            activityDescription = $"{name} answered {FormatRelativeTime(latestResp.Response.AnsweredAt)}";
        }
        else if (latestSend.HasValue)
        {
            activityDescription = $"Sent {FormatRelativeTime(latestSend.Value)}";
        }

        var questions = qs.Questions.OrderBy(q => q.SortOrder).ToList();

        var model = new UnifiedQuestionSetModel
        {
            QuestionSetId = qs.QuestionSetId,
            Name = qs.Name,
            QuestionCount = qs.Questions.Count,
            CreatedAt = qs.CreatedAt,
            UpdatedAt = qs.UpdatedAt,
            TotalRecipients = totalRecipients,
            RespondedRecipients = respondedRecipients,
            LatestActivity = latestActivity,
            LatestActivityDescription = activityDescription,
            Requests = qs.Requests
                .OrderByDescending(r => r.CreatedAt)
                .Select(req => new UnifiedRequestModel
                {
                    QuestionRequestId = req.QuestionRequestId,
                    CreatedAt = req.CreatedAt,
                    Message = req.Message,
                    Recipients = req.Recipients.Select(r =>
                    {
                        var answers = questions.Select(q =>
                        {
                            var response = r.Responses
                                .FirstOrDefault(resp => resp.QuestionId == q.QuestionId);

                            var answerModel = new RecipientAnswerModel
                            {
                                QuestionId = q.QuestionId,
                                QuestionText = q.Text,
                                SortOrder = q.SortOrder,
                                IsAnswered = response != null
                            };

                            if (response?.Drop != null)
                            {
                                var drop = response.Drop;
                                answerModel.DropId = drop.DropId;
                                answerModel.Content = drop.ContentDrop?.Stuff;
                                answerModel.Date = drop.Date;
                                answerModel.DateType = (int)drop.DateType;
                                answerModel.AnsweredAt = response.AnsweredAt;
                                answerModel.Images = drop.Images?
                                    .Where(i => !i.CommentId.HasValue)
                                    .Select(i => new AnswerImageModel
                                    {
                                        ImageDropId = i.ImageDropId,
                                        Url = imageService.GetLink(i.ImageDropId, userId, drop.DropId)
                                    }).ToList();
                                answerModel.Movies = drop.Movies?
                                    .Where(m => !m.CommentId.HasValue)
                                    .Select(m => new AnswerMovieModel
                                    {
                                        MovieDropId = m.MovieDropId,
                                        ThumbnailUrl = movieService.GetThumbLink(m.MovieDropId, userId, drop.DropId, m.IsTranscodeV2),
                                        VideoUrl = movieService.GetLink(m.MovieDropId, userId, drop.DropId, m.IsTranscodeV2)
                                    }).ToList();
                            }

                            return answerModel;
                        }).ToList();

                        return new RecipientDetailModel
                        {
                            QuestionRequestRecipientId = r.QuestionRequestRecipientId,
                            Token = r.Token,
                            DisplayName = ResolveRespondentName(r),
                            Email = r.Email,
                            Alias = r.Alias,
                            IsActive = r.IsActive,
                            RemindersSent = r.RemindersSent,
                            LastReminderAt = r.LastReminderAt,
                            Answers = answers
                        };
                    }).ToList()
                }).ToList()
        };

        result.Add(model);
    }

    return result;
}

/// <summary>
/// Formats a DateTime as a relative time string (e.g., "just now", "2 hours ago", "Dec 20").
/// </summary>
private static string FormatRelativeTime(DateTime utcDate)
{
    var diff = DateTime.UtcNow - utcDate;
    if (diff.TotalSeconds < 0) return "just now";
    if (diff.TotalMinutes < 1) return "just now";
    if (diff.TotalMinutes < 60) return $"{(int)diff.TotalMinutes}m ago";
    if (diff.TotalHours < 24) return $"{(int)diff.TotalHours}h ago";
    if (diff.TotalDays < 7) return $"{(int)diff.TotalDays}d ago";
    return utcDate.ToString("MMM d");
}
```

#### GetPreviousRecipients

Add after `GetUnifiedQuestionSets`:

```csharp
/// <summary>
/// Gets distinct previous recipients for this user, deduplicated by email (case-insensitive).
/// Returns most recently used alias for each email. Sorted by last sent date descending.
/// </summary>
public async Task<List<PreviousRecipientModel>> GetPreviousRecipients(int userId)
{
    var recipients = await Context.QuestionRequestRecipients
        .Where(r => r.QuestionRequest.CreatorUserId == userId
            && !string.IsNullOrEmpty(r.Email))
        .Select(r => new
        {
            Email = r.Email.ToLower().Trim(),
            r.Alias,
            r.CreatedAt
        })
        .OrderByDescending(r => r.CreatedAt)
        .ToListAsync();

    // Deduplicate by email, keeping most recent alias
    return recipients
        .GroupBy(r => r.Email)
        .Select(g => new PreviousRecipientModel
        {
            Email = g.First().Email,
            Alias = g.First().Alias, // most recent (already sorted desc)
            LastSentAt = g.Max(r => r.CreatedAt)
        })
        .OrderByDescending(r => r.LastSentAt)
        .ToList();
}
```

### 1.3 Update CreateQuestionRequest — Email Required + Deduplication

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`

Replace the existing validation and recipient creation in `CreateQuestionRequest` (lines ~254-296):

```csharp
public async Task<QuestionRequestResultModel> CreateQuestionRequest(
    int userId,
    int questionSetId,
    List<RecipientInputModel> recipients,
    string message)
{
    if (recipients == null || !recipients.Any())
        throw new BadRequestException("At least one recipient is required.");

    // Validate ALL recipients have email (email is now required)
    var validRecipients = recipients
        .Where(r => !string.IsNullOrWhiteSpace(r.Email))
        .ToList();

    if (!validRecipients.Any())
        throw new BadRequestException("Email is required for every recipient.");

    foreach (var recipient in validRecipients)
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

    // Check for existing active recipients with the same email for this question set
    var existingRecipients = await Context.QuestionRequestRecipients
        .Where(r => r.QuestionRequest.QuestionSetId == questionSetId
            && r.QuestionRequest.CreatorUserId == userId
            && r.IsActive)
        .ToListAsync();

    var existingByEmail = existingRecipients
        .Where(r => !string.IsNullOrEmpty(r.Email))
        .GroupBy(r => r.Email.ToLower().Trim())
        .ToDictionary(g => g.Key, g => g.First());

    var now = DateTime.UtcNow;
    var newRecipientEntities = new List<QuestionRequestRecipient>();
    var reusedRecipients = new List<QuestionRequestRecipient>();

    foreach (var r in validRecipients)
    {
        var emailKey = r.Email.Trim().ToLower();
        if (existingByEmail.TryGetValue(emailKey, out var existing))
        {
            // Reuse existing token — update alias if provided
            if (!string.IsNullOrWhiteSpace(r.Alias) && r.Alias.Trim() != existing.Alias)
            {
                existing.Alias = r.Alias.Trim();
            }
            reusedRecipients.Add(existing);
        }
        else
        {
            newRecipientEntities.Add(new QuestionRequestRecipient
            {
                Token = Guid.NewGuid(),
                Email = r.Email.Trim(),
                Alias = r.Alias?.Trim(),
                IsActive = true,
                CreatedAt = now,
                RemindersSent = 0
            });
        }
    }

    if (!newRecipientEntities.Any() && !reusedRecipients.Any())
        throw new BadRequestException("At least one valid recipient is required.");

    // Always create a QuestionRequest to record the send event
    var request = new QuestionRequest
    {
        QuestionSetId = questionSetId,
        CreatorUserId = userId,
        Message = message?.Trim(),
        CreatedAt = now,
        Recipients = newRecipientEntities
    };

    Context.QuestionRequests.Add(request);
    await Context.SaveChangesAsync();

    // Send emails to NEW recipients only (reused already have links)
    var creator = await Context.UserProfiles.SingleAsync(u => u.UserId == userId);
    var firstQuestion = qs.Questions.OrderBy(q => q.SortOrder).First().Text;

    foreach (var recipient in newRecipientEntities.Where(r => !string.IsNullOrEmpty(r.Email)))
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

    // Combine new + reused recipients in response
    var allResultRecipients = new List<RecipientLinkModel>();

    foreach (var r in newRecipientEntities)
    {
        allResultRecipients.Add(new RecipientLinkModel
        {
            QuestionRequestRecipientId = r.QuestionRequestRecipientId,
            Token = r.Token,
            Email = r.Email,
            Alias = r.Alias
        });
    }

    foreach (var r in reusedRecipients)
    {
        allResultRecipients.Add(new RecipientLinkModel
        {
            QuestionRequestRecipientId = r.QuestionRequestRecipientId,
            Token = r.Token,
            Email = r.Email,
            Alias = r.Alias
        });
    }

    return new QuestionRequestResultModel
    {
        QuestionRequestId = request.QuestionRequestId,
        Recipients = allResultRecipients
    };
}
```

### 1.4 New Controller Endpoints

**File:** `cimplur-core/Memento/Memento/Controllers/QuestionController.cs`

Add after the existing `GetSentRequests` endpoint:

```csharp
/// <summary>
/// Gets all question sets with aggregated response data for the unified page.
/// </summary>
[HttpGet("sets/unified")]
[CustomAuthorization]
public async Task<IActionResult> GetUnifiedQuestionSets(int skip = 0, int take = 20)
{
    var userId = GetUserId();
    var result = await questionService.GetUnifiedQuestionSets(userId, skip, take);
    return Ok(result);
}

/// <summary>
/// Gets distinct previous recipients for this user.
/// </summary>
[HttpGet("recipients/previous")]
[CustomAuthorization]
public async Task<IActionResult> GetPreviousRecipients()
{
    var userId = GetUserId();
    var result = await questionService.GetPreviousRecipients(userId);
    return Ok(result);
}
```

### 1.5 Backend Tests

**File:** `cimplur-core/Memento/DomainTest/Repositories/QuestionServiceTest.cs`

Add new test methods:

```csharp
// ===== UNIFIED PAGE TESTS =====

[TestMethod]
public async Task GetUnifiedQuestionSets_ReturnsDraftSets()
{
    var user = CreateTestUser(_context);
    QuestionTestFixtures.CreateQuestionSet(_context, user.UserId, "Draft Set");
    DetachAllEntities(_context);

    var result = await _questionService.GetUnifiedQuestionSets(user.UserId);

    Assert.AreEqual(1, result.Count);
    Assert.AreEqual("Draft Set", result[0].Name);
    Assert.AreEqual(0, result[0].TotalRecipients);
    Assert.AreEqual(0, result[0].RespondedRecipients);
    Assert.IsNull(result[0].LatestActivity);
    Assert.AreEqual(0, result[0].Requests.Count);
}

[TestMethod]
public async Task GetUnifiedQuestionSets_AggregatesAcrossMultipleSends()
{
    var user = CreateTestUserWithGroups(_context);
    var set = QuestionTestFixtures.CreateQuestionSet(_context, user.UserId, "Test Set");

    // Send 1: 2 recipients
    var req1 = QuestionTestFixtures.CreateQuestionRequest(_context, set.QuestionSetId, user.UserId);
    var r1 = QuestionTestFixtures.CreateRecipient(_context, req1, "a@test.com", "Alice");
    var r2 = QuestionTestFixtures.CreateRecipient(_context, req1, "b@test.com", "Bob");

    // Send 2: 1 recipient
    var req2 = QuestionTestFixtures.CreateQuestionRequest(_context, set.QuestionSetId, user.UserId);
    var r3 = QuestionTestFixtures.CreateRecipient(_context, req2, "c@test.com", "Charlie");

    // Alice answers question 1
    var drop = CreateTestDrop(_context, user.UserId);
    QuestionTestFixtures.CreateResponse(_context, r1.QuestionRequestRecipientId, set.Questions[0].QuestionId, drop.DropId);

    DetachAllEntities(_context);

    var result = await _questionService.GetUnifiedQuestionSets(user.UserId);

    Assert.AreEqual(1, result.Count);
    Assert.AreEqual(3, result[0].TotalRecipients);
    Assert.AreEqual(1, result[0].RespondedRecipients);
    Assert.AreEqual(2, result[0].Requests.Count);
}

[TestMethod]
public async Task GetUnifiedQuestionSets_SortsPendingBeforeComplete()
{
    var user = CreateTestUserWithGroups(_context);

    // Set A: fully responded
    var setA = QuestionTestFixtures.CreateQuestionSet(_context, user.UserId, "Complete Set");
    var reqA = QuestionTestFixtures.CreateQuestionRequest(_context, setA.QuestionSetId, user.UserId);
    var rA = QuestionTestFixtures.CreateRecipient(_context, reqA, "a@test.com");
    var dropA = CreateTestDrop(_context, user.UserId);
    QuestionTestFixtures.CreateResponse(_context, rA.QuestionRequestRecipientId, setA.Questions[0].QuestionId, dropA.DropId);

    // Set B: pending (created after A but has unanswered recipients)
    var setB = QuestionTestFixtures.CreateQuestionSet(_context, user.UserId, "Pending Set");
    var reqB = QuestionTestFixtures.CreateQuestionRequest(_context, setB.QuestionSetId, user.UserId);
    QuestionTestFixtures.CreateRecipient(_context, reqB, "b@test.com");

    DetachAllEntities(_context);

    var result = await _questionService.GetUnifiedQuestionSets(user.UserId);

    Assert.AreEqual(2, result.Count);
    Assert.AreEqual("Pending Set", result[0].Name); // pending first
    Assert.AreEqual("Complete Set", result[1].Name);
}

[TestMethod]
public async Task GetUnifiedQuestionSets_ExcludesArchivedSets()
{
    var user = CreateTestUser(_context);
    var set = QuestionTestFixtures.CreateQuestionSet(_context, user.UserId, "Archived Set");
    set.Archived = true;
    _context.SaveChanges();
    DetachAllEntities(_context);

    var result = await _questionService.GetUnifiedQuestionSets(user.UserId);

    Assert.AreEqual(0, result.Count);
}

[TestMethod]
public async Task GetUnifiedQuestionSets_IncludesLatestActivityDescription()
{
    var user = CreateTestUserWithGroups(_context);
    var set = QuestionTestFixtures.CreateQuestionSet(_context, user.UserId, "Test Set");
    var req = QuestionTestFixtures.CreateQuestionRequest(_context, set.QuestionSetId, user.UserId);
    var recipient = QuestionTestFixtures.CreateRecipient(_context, req, "grandma@test.com", "Grandma");
    var drop = CreateTestDrop(_context, user.UserId);
    QuestionTestFixtures.CreateResponse(_context, recipient.QuestionRequestRecipientId, set.Questions[0].QuestionId, drop.DropId);
    DetachAllEntities(_context);

    var result = await _questionService.GetUnifiedQuestionSets(user.UserId);

    Assert.AreEqual(1, result.Count);
    Assert.IsNotNull(result[0].LatestActivityDescription);
    Assert.IsTrue(result[0].LatestActivityDescription.Contains("Grandma"));
}

// ===== PREVIOUS RECIPIENTS TESTS =====

[TestMethod]
public async Task GetPreviousRecipients_ReturnsDistinctByEmail()
{
    var user = CreateTestUserWithGroups(_context);
    var set = QuestionTestFixtures.CreateQuestionSet(_context, user.UserId);
    var req1 = QuestionTestFixtures.CreateQuestionRequest(_context, set.QuestionSetId, user.UserId);
    QuestionTestFixtures.CreateRecipient(_context, req1, "same@test.com", "Name1");
    var req2 = QuestionTestFixtures.CreateQuestionRequest(_context, set.QuestionSetId, user.UserId);
    QuestionTestFixtures.CreateRecipient(_context, req2, "same@test.com", "Name2");
    DetachAllEntities(_context);

    var result = await _questionService.GetPreviousRecipients(user.UserId);

    Assert.AreEqual(1, result.Count);
    Assert.AreEqual("same@test.com", result[0].Email);
}

[TestMethod]
public async Task GetPreviousRecipients_ReturnsMostRecentAlias()
{
    var user = CreateTestUserWithGroups(_context);
    var set = QuestionTestFixtures.CreateQuestionSet(_context, user.UserId);

    var req1 = QuestionTestFixtures.CreateQuestionRequest(_context, set.QuestionSetId, user.UserId);
    var r1 = QuestionTestFixtures.CreateRecipient(_context, req1, "test@test.com", "Old Name");
    r1.CreatedAt = DateTime.UtcNow.AddDays(-10);
    _context.SaveChanges();

    var req2 = QuestionTestFixtures.CreateQuestionRequest(_context, set.QuestionSetId, user.UserId);
    var r2 = QuestionTestFixtures.CreateRecipient(_context, req2, "test@test.com", "New Name");
    r2.CreatedAt = DateTime.UtcNow;
    _context.SaveChanges();

    DetachAllEntities(_context);

    var result = await _questionService.GetPreviousRecipients(user.UserId);

    Assert.AreEqual(1, result.Count);
    Assert.AreEqual("New Name", result[0].Alias);
}

[TestMethod]
public async Task GetPreviousRecipients_ExcludesAliasOnlyRecipients()
{
    var user = CreateTestUserWithGroups(_context);
    var set = QuestionTestFixtures.CreateQuestionSet(_context, user.UserId);
    var req = QuestionTestFixtures.CreateQuestionRequest(_context, set.QuestionSetId, user.UserId);
    QuestionTestFixtures.CreateRecipient(_context, req, null, "NoEmail");
    QuestionTestFixtures.CreateRecipient(_context, req, "has@email.com", "HasEmail");
    DetachAllEntities(_context);

    var result = await _questionService.GetPreviousRecipients(user.UserId);

    Assert.AreEqual(1, result.Count);
    Assert.AreEqual("has@email.com", result[0].Email);
}

[TestMethod]
public async Task GetPreviousRecipients_OnlyReturnsOwnRecipients()
{
    var user1 = CreateTestUserWithGroups(_context);
    var user2 = CreateTestUserWithGroups(_context);
    var set1 = QuestionTestFixtures.CreateQuestionSet(_context, user1.UserId);
    var set2 = QuestionTestFixtures.CreateQuestionSet(_context, user2.UserId);
    var req1 = QuestionTestFixtures.CreateQuestionRequest(_context, set1.QuestionSetId, user1.UserId);
    var req2 = QuestionTestFixtures.CreateQuestionRequest(_context, set2.QuestionSetId, user2.UserId);
    QuestionTestFixtures.CreateRecipient(_context, req1, "user1recipient@test.com");
    QuestionTestFixtures.CreateRecipient(_context, req2, "user2recipient@test.com");
    DetachAllEntities(_context);

    var result = await _questionService.GetPreviousRecipients(user1.UserId);

    Assert.AreEqual(1, result.Count);
    Assert.AreEqual("user1recipient@test.com", result[0].Email);
}

// ===== EMAIL REQUIRED TESTS =====

[TestMethod]
public async Task CreateQuestionRequest_RequiresEmail()
{
    var user = CreateTestUserWithGroups(_context);
    var set = QuestionTestFixtures.CreateQuestionSet(_context, user.UserId);
    DetachAllEntities(_context);

    var recipients = new List<RecipientInputModel>
    {
        new RecipientInputModel { Alias = "NoEmail" }
    };

    await Assert.ThrowsExceptionAsync<BadRequestException>(() =>
        _questionService.CreateQuestionRequest(user.UserId, set.QuestionSetId, recipients, null));
}

[TestMethod]
public async Task CreateQuestionRequest_DeduplicatesExistingRecipients()
{
    var user = CreateTestUserWithGroups(_context);
    var set = QuestionTestFixtures.CreateQuestionSet(_context, user.UserId);
    var req = QuestionTestFixtures.CreateQuestionRequest(_context, set.QuestionSetId, user.UserId);
    var existingRecipient = QuestionTestFixtures.CreateRecipient(_context, req, "existing@test.com", "Existing");
    var existingToken = existingRecipient.Token;
    DetachAllEntities(_context);

    var recipients = new List<RecipientInputModel>
    {
        new RecipientInputModel { Email = "existing@test.com", Alias = "Updated Alias" },
        new RecipientInputModel { Email = "new@test.com", Alias = "New Person" }
    };

    var result = await _questionService.CreateQuestionRequest(user.UserId, set.QuestionSetId, recipients, null);

    Assert.AreEqual(2, result.Recipients.Count);
    // Existing recipient should keep their original token
    var reused = result.Recipients.Single(r => r.Email == "existing@test.com");
    Assert.AreEqual(existingToken, reused.Token);
    // New recipient should have a new token
    var newR = result.Recipients.Single(r => r.Email == "new@test.com");
    Assert.AreNotEqual(Guid.Empty, newR.Token);
}
```

---

## Phase 2: Frontend — Unified Page View

### 2.1 New TypeScript Types

**File:** `fyli-fe-v2/src/types/question.ts`

Add to end of file:

```typescript
// ===== Unified Page Types =====

/** Question set with aggregated response data from GET /questions/sets/unified */
export interface UnifiedQuestionSet {
	questionSetId: number;
	name: string;
	questionCount: number;
	createdAt: string;
	updatedAt: string;
	totalRecipients: number;
	respondedRecipients: number;
	latestActivity: string | null;
	latestActivityDescription: string | null;
	requests: UnifiedRequest[];
}

/** A single send instance within a unified question set. */
export interface UnifiedRequest {
	questionRequestId: number;
	createdAt: string;
	message: string | null;
	recipients: RecipientDetail[];
}

/** A previously sent-to recipient from GET /questions/recipients/previous */
export interface PreviousRecipient {
	email: string;
	alias: string | null;
	lastSentAt: string;
}
```

Also update `RecipientInput` to make email required:

```typescript
export interface RecipientInput {
	email: string;  // was: email?: string — now required
	alias?: string;
}
```

### 2.2 New API Functions

**File:** `fyli-fe-v2/src/services/questionApi.ts`

Add new imports and functions:

```typescript
// Add to imports:
import type {
	// ...existing imports...
	UnifiedQuestionSet,
	PreviousRecipient
} from "@/types";

// Unified Page
export function getUnifiedQuestionSets(skip = 0, take = 20) {
	return api.get<UnifiedQuestionSet[]>("/questions/sets/unified", { params: { skip, take } });
}

export function getPreviousRecipients() {
	return api.get<PreviousRecipient[]>("/questions/recipients/previous");
}
```

### 2.3 UnifiedQuestionsView

**File:** `fyli-fe-v2/src/views/question/UnifiedQuestionsView.vue`

```vue
<template>
	<div class="container py-4">
		<div class="d-flex justify-content-between align-items-center mb-4">
			<h1 class="h3 mb-0">Questions</h1>
			<router-link to="/questions/new" class="btn btn-primary">
				<span class="mdi mdi-plus" aria-hidden="true"></span> Ask Questions
			</router-link>
		</div>

		<LoadingSpinner v-if="loading" />
		<ErrorState v-else-if="loadError" :message="loadError" @retry="loadData" />

		<EmptyState
			v-else-if="sets.length === 0"
			icon="mdi-comment-question-outline"
			message="Ask your family to share their stories. Create questions and send them to anyone — they can answer without an account."
			action-label="Ask Questions"
			@action="router.push('/questions/new')"
		/>

		<div v-else>
			<QuestionSetCard
				v-for="set in sets"
				:key="set.questionSetId"
				:set="set"
				@copy-link="handleCopyLink"
				@remind="handleRemind"
				@deactivate="handleDeactivate"
				@view-full="handleViewFull"
				@send="handleSend"
				@edit="handleEdit"
				@delete="handleDelete"
			/>
		</div>

		<!-- Toast -->
		<div v-if="toastMessage" class="toast-container position-fixed bottom-0 end-0 p-3">
			<div class="toast show" role="alert">
				<div class="toast-body">{{ toastMessage }}</div>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { useRouter } from "vue-router";
import {
	getUnifiedQuestionSets,
	deleteQuestionSet,
	sendReminder,
	deactivateRecipient
} from "@/services/questionApi";
import { getErrorMessage } from "@/utils/errorMessage";
import type { UnifiedQuestionSet } from "@/types";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import QuestionSetCard from "@/components/question/QuestionSetCard.vue";

const router = useRouter();
const sets = ref<UnifiedQuestionSet[]>([]);
const loading = ref(true);
const loadError = ref("");
const toastMessage = ref("");

onMounted(() => loadData());

async function loadData() {
	loading.value = true;
	loadError.value = "";
	try {
		const { data } = await getUnifiedQuestionSets();
		sets.value = data;
	} catch (e: unknown) {
		loadError.value = getErrorMessage(e, "Failed to load questions");
	} finally {
		loading.value = false;
	}
}

async function handleCopyLink(token: string) {
	try {
		await navigator.clipboard.writeText(`${window.location.origin}/q/${token}`);
		showToast("Link copied!");
	} catch {
		showToast("Failed to copy link");
	}
}

async function handleRemind(recipientId: number) {
	try {
		await sendReminder(recipientId);
		showToast("Reminder sent");
	} catch (e: unknown) {
		showToast(getErrorMessage(e, "Failed to send reminder"));
	}
}

async function handleDeactivate(recipientId: number) {
	if (!confirm("Deactivate this link? The recipient will no longer be able to answer.")) return;
	try {
		await deactivateRecipient(recipientId);
		await loadData();
	} catch (e: unknown) {
		showToast(getErrorMessage(e, "Failed to deactivate"));
	}
}

function handleViewFull(dropId: number) {
	router.push(`/memory/${dropId}`);
}

function handleSend(setId: number) {
	router.push(`/questions/new?setId=${setId}`);
}

function handleEdit(setId: number) {
	router.push(`/questions/${setId}/edit`);
}

async function handleDelete(setId: number) {
	if (!confirm("Delete this question set?")) return;
	try {
		await deleteQuestionSet(setId);
		sets.value = sets.value.filter((s) => s.questionSetId !== setId);
	} catch (e: unknown) {
		showToast(getErrorMessage(e, "Failed to delete"));
	}
}

function showToast(msg: string) {
	toastMessage.value = msg;
	setTimeout(() => { toastMessage.value = ""; }, 2000);
}
</script>
```

### 2.4 QuestionSetCard Component

**File:** `fyli-fe-v2/src/components/question/QuestionSetCard.vue`

```vue
<template>
	<div class="card mb-3" :class="{ 'border-dashed text-muted': isDraft }">
		<!-- Header -->
		<div
			class="card-header bg-white d-flex justify-content-between align-items-center"
			:role="hasSends ? 'button' : undefined"
			@click="hasSends && toggle()"
		>
			<div>
				<h5 class="mb-1 fw-semibold">
					{{ set.name }}
					<span v-if="isDraft" class="badge bg-secondary ms-2">draft</span>
					<span v-else-if="isComplete" class="badge bg-success ms-2">
						<span class="mdi mdi-check"></span> Complete
					</span>
				</h5>
				<small class="text-muted">
					{{ set.questionCount }} {{ set.questionCount === 1 ? "question" : "questions" }}
					<template v-if="hasSends">
						<span class="mx-1">&middot;</span>
						{{ set.respondedRecipients }}/{{ set.totalRecipients }} responded
					</template>
				</small>
				<div v-if="set.latestActivityDescription && !isDraft" class="text-muted small mt-1">
					{{ set.latestActivityDescription }}
				</div>
			</div>
			<div class="d-flex align-items-center gap-2">
				<!-- Draft actions inline -->
				<template v-if="isDraft">
					<button class="btn btn-sm btn-primary" @click.stop="$emit('send', set.questionSetId)">
						Ask Questions
					</button>
					<button class="btn btn-sm btn-outline-secondary" @click.stop="$emit('edit', set.questionSetId)">
						Edit
					</button>
					<button class="btn btn-sm btn-outline-danger" @click.stop="$emit('delete', set.questionSetId)">
						Delete
					</button>
				</template>
				<!-- Sent: expand chevron -->
				<span
					v-if="hasSends"
					class="mdi fs-5"
					:class="expanded ? 'mdi-chevron-up' : 'mdi-chevron-down'"
				></span>
			</div>
		</div>

		<!-- Expanded body -->
		<div v-show="expanded && hasSends" class="card-body">
			<div
				v-for="req in set.requests"
				:key="req.questionRequestId"
				class="mb-4"
			>
				<div class="text-muted small fw-semibold mb-2 border-bottom pb-1">
					Sent {{ formatDate(req.createdAt) }} to {{ req.recipients.length }}
					{{ req.recipients.length === 1 ? "recipient" : "recipients" }}
				</div>

				<div
					v-for="recipient in req.recipients"
					:key="recipient.questionRequestRecipientId"
					class="mb-3 ps-2 border-start border-2"
					:class="recipientBorderClass(recipient)"
				>
					<div class="d-flex justify-content-between align-items-center mb-1">
						<div class="d-flex align-items-center">
							<span class="mdi me-2" :class="statusIconClass(recipient)"></span>
							<strong>{{ recipient.displayName }}</strong>
							<small v-if="partialCount(recipient)" class="text-muted ms-1">
								({{ answeredCount(recipient) }}/{{ recipient.answers.length }})
							</small>
						</div>
						<div v-if="recipient.isActive" class="btn-group btn-group-sm">
							<button
								class="btn btn-outline-secondary btn-sm"
								title="Copy link"
								@click.stop="$emit('copyLink', recipient.token)"
							>
								<span class="mdi mdi-link"></span>
							</button>
							<button
								v-if="!isFullyAnswered(recipient)"
								class="btn btn-outline-secondary btn-sm"
								title="Send reminder"
								@click.stop="$emit('remind', recipient.questionRequestRecipientId)"
							>
								<span class="mdi mdi-bell-outline"></span>
							</button>
							<button
								class="btn btn-outline-secondary btn-sm"
								title="Deactivate"
								@click.stop="$emit('deactivate', recipient.questionRequestRecipientId)"
							>
								<span class="mdi mdi-close-circle-outline"></span>
							</button>
						</div>
						<span v-else class="badge bg-secondary">Deactivated</span>
					</div>

					<!-- Inline answer previews -->
					<template v-if="hasAnswers(recipient)">
						<div
							v-for="answer in getAnswered(recipient)"
							:key="answer.questionId"
						>
							<QuestionAnswerCard
								:question-text="answer.questionText"
								:answer-content="answer.content ?? ''"
								:date="answer.date ?? undefined"
								:date-type="(answer.dateType as DateType | undefined)"
								:images="answer.images"
								:movies="answer.movies"
								variant="compact"
							/>
							<div class="text-end">
								<button class="btn btn-sm btn-link p-0" @click="$emit('viewFull', answer.dropId!)">
									View Full
								</button>
							</div>
						</div>
					</template>
					<div v-else class="text-muted small ps-4">
						<span class="mdi mdi-clock-outline me-1"></span>
						Waiting for response...
					</div>
				</div>
			</div>

			<!-- Card footer actions -->
			<div class="d-flex gap-2 pt-2 border-top">
				<button class="btn btn-sm btn-outline-primary" @click="$emit('send', set.questionSetId)">
					<span class="mdi mdi-account-plus-outline me-1"></span>Ask More People
				</button>
				<button class="btn btn-sm btn-outline-secondary" @click="$emit('edit', set.questionSetId)">
					<span class="mdi mdi-pencil-outline me-1"></span>Edit Set
				</button>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, computed } from "vue";
import type { UnifiedQuestionSet, RecipientDetail, RecipientAnswer, DateType } from "@/types";
import QuestionAnswerCard from "./QuestionAnswerCard.vue";

const props = defineProps<{
	set: UnifiedQuestionSet;
}>();

defineEmits<{
	(e: "copyLink", token: string): void;
	(e: "remind", recipientId: number): void;
	(e: "deactivate", recipientId: number): void;
	(e: "viewFull", dropId: number): void;
	(e: "send", setId: number): void;
	(e: "edit", setId: number): void;
	(e: "delete", setId: number): void;
}>();

const expanded = ref(false);

const isDraft = computed(() => props.set.requests.length === 0);
const hasSends = computed(() => props.set.requests.length > 0);
const isComplete = computed(() =>
	hasSends.value &&
	props.set.totalRecipients > 0 &&
	props.set.respondedRecipients === props.set.totalRecipients
);

function toggle() {
	expanded.value = !expanded.value;
}

function recipientStatus(r: RecipientDetail): "complete" | "partial" | "pending" | "deactivated" {
	if (!r.isActive) return "deactivated";
	const answered = r.answers.filter((a) => a.isAnswered).length;
	if (answered === r.answers.length && r.answers.length > 0) return "complete";
	if (answered > 0) return "partial";
	return "pending";
}

function statusIconClass(r: RecipientDetail): string {
	const s = recipientStatus(r);
	switch (s) {
		case "complete": return "mdi-check-circle text-success";
		case "partial": return "mdi-progress-clock text-warning";
		case "pending": return "mdi-circle-outline text-muted";
		case "deactivated": return "mdi-close-circle text-secondary";
	}
}

function recipientBorderClass(r: RecipientDetail): string {
	const s = recipientStatus(r);
	switch (s) {
		case "complete": return "border-success";
		case "partial": return "border-warning";
		default: return "border-light";
	}
}

function isFullyAnswered(r: RecipientDetail) { return recipientStatus(r) === "complete"; }
function hasAnswers(r: RecipientDetail) { return r.answers.some((a) => a.isAnswered); }
function getAnswered(r: RecipientDetail): RecipientAnswer[] { return r.answers.filter((a) => a.isAnswered); }
function answeredCount(r: RecipientDetail) { return r.answers.filter((a) => a.isAnswered).length; }
function partialCount(r: RecipientDetail) { return recipientStatus(r) === "partial"; }

function formatDate(dateStr: string): string {
	return new Date(dateStr).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}
</script>

<style scoped>
.border-dashed {
	border-style: dashed !important;
}
</style>
```

### 2.5 Router Updates

**File:** `fyli-fe-v2/src/router/index.ts`

Replace existing question routes:

```typescript
// Question management (authenticated)
{
  path: '/questions',
  name: 'questions',
  component: () => import('@/views/question/UnifiedQuestionsView.vue'),
  meta: { auth: true, layout: 'app' },
},
{
  path: '/questions/new',
  name: 'question-ask',
  component: () => import('@/views/question/AskQuestionsView.vue'),
  meta: { auth: true, layout: 'app' },
},
{
  path: '/questions/:id/edit',
  name: 'question-set-edit',
  component: () => import('@/views/question/QuestionSetEditView.vue'),
  meta: { auth: true, layout: 'app' },
},
// Redirects for old routes
{
  path: '/questions/requests',
  redirect: '/questions',
},
{
  path: '/questions/dashboard',
  redirect: '/questions',
},
{
  path: '/questions/responses',
  redirect: '/questions',
},
{
  path: '/questions/:id/send',
  redirect: to => `/questions/new?setId=${to.params.id}`,
},
// Public answer flow (no auth required)
{
  path: '/q/:token',
  name: 'question-answer',
  component: () => import('@/views/question/QuestionAnswerView.vue'),
  meta: { layout: 'public' },
},
```

### 2.6 Update Internal Links

**File:** `fyli-fe-v2/src/components/memory/MemoryCard.vue`

Change `to="/questions/requests"` → `to="/questions"`

**File:** `fyli-fe-v2/src/components/question/QuestionAnswerCard.vue`

Change `to="/questions/requests"` → `to="/questions"` (line 47, in the "View all responses" router-link)

**File:** `fyli-fe-v2/src/views/question/QuestionSetEditView.vue`

Change `router.push("/questions")` — no change needed (already points to `/questions`)
Change `to="/questions"` — no change needed

### 2.7 Frontend Tests — Phase 2

**File:** `fyli-fe-v2/src/views/question/UnifiedQuestionsView.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount, flushPromises } from "@vue/test-utils";
import { createRouter, createWebHistory } from "vue-router";
import UnifiedQuestionsView from "./UnifiedQuestionsView.vue";
import type { UnifiedQuestionSet } from "@/types";

vi.mock("@/services/questionApi", () => ({
	getUnifiedQuestionSets: vi.fn(),
	deleteQuestionSet: vi.fn(),
	sendReminder: vi.fn(),
	deactivateRecipient: vi.fn()
}));

import {
	getUnifiedQuestionSets,
	deleteQuestionSet
} from "@/services/questionApi";

const mockSets: UnifiedQuestionSet[] = [
	{
		questionSetId: 1,
		name: "Christmas Memories",
		questionCount: 3,
		createdAt: "2026-01-01T00:00:00Z",
		updatedAt: "2026-01-01T00:00:00Z",
		totalRecipients: 2,
		respondedRecipients: 1,
		latestActivity: "2026-01-15T00:00:00Z",
		latestActivityDescription: "Grandma answered 2d ago",
		requests: []
	},
	{
		questionSetId: 2,
		name: "Draft Set",
		questionCount: 2,
		createdAt: "2026-02-01T00:00:00Z",
		updatedAt: "2026-02-01T00:00:00Z",
		totalRecipients: 0,
		respondedRecipients: 0,
		latestActivity: null,
		latestActivityDescription: null,
		requests: []
	}
];

function createWrapper() {
	const router = createRouter({
		history: createWebHistory(),
		routes: [
			{ path: "/questions", component: { template: "<div />" } },
			{ path: "/questions/new", component: { template: "<div />" } }
		]
	});
	return mount(UnifiedQuestionsView, {
		global: { plugins: [router] }
	});
}

describe("UnifiedQuestionsView", () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it("shows loading spinner initially", () => {
		(getUnifiedQuestionSets as any).mockReturnValue(new Promise(() => {}));
		const wrapper = createWrapper();
		expect(wrapper.findComponent({ name: "LoadingSpinner" }).exists()).toBe(true);
	});

	it("renders question set cards after loading", async () => {
		(getUnifiedQuestionSets as any).mockResolvedValue({ data: mockSets });
		const wrapper = createWrapper();
		await flushPromises();
		const cards = wrapper.findAllComponents({ name: "QuestionSetCard" });
		expect(cards).toHaveLength(2);
	});

	it("shows empty state when no sets", async () => {
		(getUnifiedQuestionSets as any).mockResolvedValue({ data: [] });
		const wrapper = createWrapper();
		await flushPromises();
		expect(wrapper.findComponent({ name: "EmptyState" }).exists()).toBe(true);
	});

	it("shows error state on load failure", async () => {
		(getUnifiedQuestionSets as any).mockRejectedValue(new Error("fail"));
		const wrapper = createWrapper();
		await flushPromises();
		expect(wrapper.findComponent({ name: "ErrorState" }).exists()).toBe(true);
	});

	it("deletes a set and removes from list", async () => {
		(getUnifiedQuestionSets as any).mockResolvedValue({ data: [...mockSets] });
		(deleteQuestionSet as any).mockResolvedValue({});
		const wrapper = createWrapper();
		await flushPromises();

		// Simulate delete event from card
		window.confirm = vi.fn(() => true);
		const card = wrapper.findComponent({ name: "QuestionSetCard" });
		card.vm.$emit("delete", 1);
		await flushPromises();

		expect(deleteQuestionSet).toHaveBeenCalledWith(1);
	});
});
```

**File:** `fyli-fe-v2/src/components/question/QuestionSetCard.test.ts`

```typescript
import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import QuestionSetCard from "./QuestionSetCard.vue";
import type { UnifiedQuestionSet, DateType } from "@/types";

const draftSet: UnifiedQuestionSet = {
	questionSetId: 1,
	name: "Draft Set",
	questionCount: 2,
	createdAt: "2026-01-01T00:00:00Z",
	updatedAt: "2026-01-01T00:00:00Z",
	totalRecipients: 0,
	respondedRecipients: 0,
	latestActivity: null,
	latestActivityDescription: null,
	requests: []
};

const sentSet: UnifiedQuestionSet = {
	questionSetId: 2,
	name: "Sent Set",
	questionCount: 3,
	createdAt: "2026-01-01T00:00:00Z",
	updatedAt: "2026-01-01T00:00:00Z",
	totalRecipients: 2,
	respondedRecipients: 1,
	latestActivity: "2026-01-15T00:00:00Z",
	latestActivityDescription: "Grandma answered 2d ago",
	requests: [{
		questionRequestId: 10,
		createdAt: "2026-01-10T00:00:00Z",
		message: null,
		recipients: [{
			questionRequestRecipientId: 100,
			token: "abc-123",
			displayName: "Grandma",
			email: "grandma@test.com",
			isActive: true,
			remindersSent: 0,
			answers: [
				{
					questionId: 1,
					questionText: "Q1",
					sortOrder: 0,
					isAnswered: true,
					dropId: 5,
					content: "My answer",
					date: "2026-01-15T00:00:00Z",
					dateType: 0 as DateType,
					answeredAt: "2026-01-15T00:00:00Z"
				}
			]
		}]
	}]
};

describe("QuestionSetCard", () => {
	it("shows draft badge for unsent sets", () => {
		const wrapper = mount(QuestionSetCard, { props: { set: draftSet } });
		expect(wrapper.text()).toContain("draft");
	});

	it("shows response count for sent sets", () => {
		const wrapper = mount(QuestionSetCard, { props: { set: sentSet } });
		expect(wrapper.text()).toContain("1/2 responded");
	});

	it("shows Ask Questions button for draft sets", () => {
		const wrapper = mount(QuestionSetCard, { props: { set: draftSet } });
		expect(wrapper.text()).toContain("Ask Questions");
	});

	it("emits send event when Ask Questions clicked", async () => {
		const wrapper = mount(QuestionSetCard, { props: { set: draftSet } });
		await wrapper.find("button.btn-primary").trigger("click");
		expect(wrapper.emitted("send")).toBeTruthy();
		expect(wrapper.emitted("send")![0]).toEqual([1]);
	});

	it("toggles expanded state on header click for sent sets", async () => {
		const wrapper = mount(QuestionSetCard, { props: { set: sentSet } });
		const header = wrapper.find(".card-header");
		await header.trigger("click");
		expect(wrapper.find(".card-body").isVisible()).toBe(true);
	});

	it("shows latest activity description", () => {
		const wrapper = mount(QuestionSetCard, { props: { set: sentSet } });
		expect(wrapper.text()).toContain("Grandma answered 2d ago");
	});
});
```

---

## Phase 3: Combined Ask Questions Flow

### 3.1 AskQuestionsView

**File:** `fyli-fe-v2/src/views/question/AskQuestionsView.vue`

```vue
<template>
	<div class="container py-4" style="max-width: 600px">
		<!-- Step 0: Pick existing or create new -->
		<template v-if="step === 0">
			<h1 class="h3 mb-4">Ask Questions</h1>

			<div v-if="loadingSets" class="text-center py-3">
				<LoadingSpinner />
			</div>
			<div v-else>
				<div class="mb-4">
					<div class="form-check mb-3">
						<input
							id="create-new"
							v-model="choice"
							type="radio"
							value="new"
							class="form-check-input"
						/>
						<label for="create-new" class="form-check-label fw-semibold">
							Create new questions
						</label>
					</div>

					<template v-if="existingSets.length > 0">
						<div class="form-check mb-2">
							<input
								id="use-existing"
								v-model="choice"
								type="radio"
								value="existing"
								class="form-check-input"
							/>
							<label for="use-existing" class="form-check-label fw-semibold">
								Use existing set
							</label>
						</div>
						<div v-if="choice === 'existing'" class="ms-4">
							<div
								v-for="s in existingSets"
								:key="s.questionSetId"
								class="form-check mb-1"
							>
								<input
									:id="`set-${s.questionSetId}`"
									v-model="selectedSetId"
									type="radio"
									:value="s.questionSetId"
									class="form-check-input"
								/>
								<label :for="`set-${s.questionSetId}`" class="form-check-label">
									{{ s.name }} ({{ s.questions.length }} Qs)
								</label>
							</div>
						</div>
					</template>
				</div>

				<button
					class="btn btn-primary"
					:disabled="choice === 'existing' && !selectedSetId"
					@click="handlePickStep"
				>
					Next
				</button>
				<router-link to="/questions" class="btn btn-outline-secondary ms-2">Cancel</router-link>
			</div>
		</template>

		<!-- Step 1: Create questions (same as QuestionSetEditView) -->
		<template v-if="step === 1">
			<h1 class="h3 mb-4">Create Questions</h1>
			<div class="mb-3">
				<label for="set-name" class="form-label">Set Name</label>
				<input
					id="set-name"
					v-model="setName"
					type="text"
					class="form-control"
					placeholder="e.g., Christmas Memories 2026"
					maxlength="200"
					required
				/>
			</div>
			<div class="mb-3">
				<label class="form-label">Questions ({{ questions.length }}/5)</label>
				<div v-for="(q, i) in questions" :key="i" class="input-group mb-2">
					<span class="input-group-text">{{ i + 1 }}</span>
					<input
						v-model="q.text"
						type="text"
						class="form-control"
						:placeholder="`Question ${i + 1}`"
						maxlength="500"
					/>
					<button
						v-if="questions.length > 1"
						type="button"
						class="btn btn-outline-danger"
						@click="questions.splice(i, 1)"
					>
						<span class="mdi mdi-close"></span>
					</button>
				</div>
				<button
					v-if="questions.length < 5"
					type="button"
					class="btn btn-sm btn-outline-secondary"
					@click="questions.push({ text: '' })"
				>
					<span class="mdi mdi-plus"></span> Add Question
				</button>
			</div>
			<div v-if="stepError" class="alert alert-danger">{{ stepError }}</div>
			<button class="btn btn-primary" :disabled="saving" @click="handleCreateSet">
				{{ saving ? "Saving..." : "Next" }}
			</button>
			<button class="btn btn-outline-secondary ms-2" @click="step = 0">Back</button>
		</template>

		<!-- Step 2: Recipients -->
		<template v-if="step === 2">
			<h1 class="h3 mb-4">Who should answer?</h1>

			<LoadingSpinner v-if="loadingSets" />
			<template v-else>
			<!-- Previous recipients -->
			<div v-if="previousRecipients.length > 0" class="mb-4">
				<label class="form-label text-muted small fw-semibold">Previously sent to</label>
				<div
					v-for="prev in previousRecipients"
					:key="prev.email"
					class="form-check mb-2"
				>
					<input
						:id="`prev-${prev.email}`"
						v-model="selectedPrevious"
						type="checkbox"
						:value="prev.email"
						class="form-check-input"
					/>
					<label :for="`prev-${prev.email}`" class="form-check-label">
						{{ prev.email }}
						<span v-if="prev.alias" class="text-muted">({{ prev.alias }})</span>
						<br />
						<small class="text-muted">
							Last sent: {{ formatDate(prev.lastSentAt) }}
						</small>
					</label>
				</div>
			</div>

			<!-- Manual recipients -->
			<fieldset class="mb-3">
				<legend class="form-label text-muted small fw-semibold">Add new recipients</legend>
				<div v-for="(r, i) in recipients" :key="i" class="row g-2 mb-2">
					<div class="col">
						<input
							v-model="r.email"
							type="email"
							class="form-control"
							placeholder="Email"
							required
						/>
					</div>
					<div class="col">
						<input
							v-model="r.alias"
							type="text"
							class="form-control"
							placeholder="Name (optional)"
						/>
					</div>
					<div class="col-auto">
						<button
							v-if="recipients.length > 1 || selectedPrevious.length > 0"
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
			</fieldset>

			<div class="mb-3">
				<label for="message" class="form-label">Personal message (optional)</label>
				<textarea
					id="message"
					v-model="message"
					class="form-control"
					rows="2"
					maxlength="1000"
					placeholder="Add a note to your recipients..."
				></textarea>
			</div>

			<div v-if="stepError" class="alert alert-danger">{{ stepError }}</div>
			<button class="btn btn-primary" :disabled="sending" @click="handleSend">
				{{ sending ? "Sending..." : "Send Questions" }}
			</button>
			<button class="btn btn-outline-secondary ms-2" @click="goBackFromRecipients">Back</button>
			</template>
		</template>

		<!-- Step 3: Confirmation -->
		<template v-if="step === 3">
			<div class="alert alert-success">
				<span class="mdi mdi-check-circle me-1"></span> Questions sent!
			</div>

			<div class="list-group mb-4">
				<div
					v-for="r in sendResult!.recipients"
					:key="r.questionRequestRecipientId"
					class="list-group-item"
				>
					<div class="d-flex justify-content-between align-items-center">
						<div>
							<strong>{{ r.alias || r.email || "Recipient" }}</strong>
							<span v-if="r.alias && r.email" class="text-muted ms-1">({{ r.email }})</span>
						</div>
						<button class="btn btn-sm btn-outline-primary" @click="copyLink(r.token)">
							{{ copiedToken === r.token ? "Copied!" : "Copy Link" }}
						</button>
					</div>
					<small class="text-muted d-block mt-1 text-break">
						{{ buildLink(r.token) }}
					</small>
				</div>
			</div>

			<router-link to="/questions" class="btn btn-primary">Back to Questions</router-link>
		</template>
	</div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import {
	getQuestionSets,
	createQuestionSet,
	createQuestionRequest,
	getPreviousRecipients
} from "@/services/questionApi";
import { getErrorMessage } from "@/utils/errorMessage";
import type {
	QuestionSet,
	QuestionRequestResult,
	RecipientInput,
	PreviousRecipient
} from "@/types";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

const route = useRoute();
const router = useRouter();
const preSelectedSetId = route.query.setId ? Number(route.query.setId) : null;

// Flow state
const step = ref(preSelectedSetId ? 2 : 0);
const stepError = ref("");

// Step 0: Pick
const choice = ref<"new" | "existing">(preSelectedSetId ? "existing" : "new");
const existingSets = ref<QuestionSet[]>([]);
const selectedSetId = ref<number | null>(preSelectedSetId);
const loadingSets = ref(true);
const activeSetId = ref<number | null>(preSelectedSetId);

// Step 1: Create
const setName = ref("");
const questions = ref([{ text: "" }]);
const saving = ref(false);

// Step 2: Recipients
const recipients = ref<RecipientInput[]>([{ email: "", alias: "" }]);
const message = ref("");
const previousRecipients = ref<PreviousRecipient[]>([]);
const selectedPrevious = ref<string[]>([]);
const sending = ref(false);

// Step 3: Result
const sendResult = ref<QuestionRequestResult | null>(null);
const copiedToken = ref<string | null>(null);

onMounted(async () => {
	try {
		const [setsRes, prevRes] = await Promise.all([
			getQuestionSets(),
			getPreviousRecipients()
		]);
		existingSets.value = setsRes.data;
		previousRecipients.value = prevRes.data;
	} catch {
		// Non-critical — empty lists are fine
	} finally {
		loadingSets.value = false;
	}

	// If pre-selected set, skip to step 2
	if (preSelectedSetId) {
		activeSetId.value = preSelectedSetId;
		step.value = 2;
	}
});

function handlePickStep() {
	stepError.value = "";
	if (choice.value === "new") {
		step.value = 1;
	} else if (selectedSetId.value) {
		activeSetId.value = selectedSetId.value;
		step.value = 2;
	}
}

async function handleCreateSet() {
	stepError.value = "";
	const validQs = questions.value.filter((q) => q.text.trim());
	if (!setName.value.trim() || !validQs.length) {
		stepError.value = "Name and at least one question are required";
		return;
	}

	saving.value = true;
	try {
		const { data } = await createQuestionSet({
			name: setName.value.trim(),
			questions: validQs.map((q) => q.text.trim())
		});
		activeSetId.value = data.questionSetId;
		step.value = 2;
	} catch (e: unknown) {
		stepError.value = getErrorMessage(e, "Failed to save");
	} finally {
		saving.value = false;
	}
}

function addRecipient() {
	recipients.value.push({ email: "", alias: "" });
}

function goBackFromRecipients() {
	if (preSelectedSetId) {
		// Came from "Ask More People" — go back to questions page
		router.push("/questions");
	} else if (choice.value === "new") {
		step.value = 1;
	} else {
		step.value = 0;
	}
}

async function handleSend() {
	stepError.value = "";

	// Combine selected previous + manual recipients
	const allRecipients: RecipientInput[] = [];

	for (const email of selectedPrevious.value) {
		const prev = previousRecipients.value.find((p) => p.email === email);
		allRecipients.push({ email, alias: prev?.alias ?? undefined });
	}

	for (const r of recipients.value) {
		if (r.email?.trim()) {
			allRecipients.push({ email: r.email.trim(), alias: r.alias?.trim() || undefined });
		}
	}

	if (!allRecipients.length) {
		stepError.value = "At least one recipient with an email is required";
		return;
	}

	// Validate all have email
	const missing = allRecipients.filter((r) => !r.email?.trim());
	if (missing.length) {
		stepError.value = "Email is required for every recipient";
		return;
	}

	sending.value = true;
	try {
		const { data } = await createQuestionRequest({
			questionSetId: activeSetId.value!,
			recipients: allRecipients,
			message: message.value.trim() || undefined
		});
		sendResult.value = data;
		step.value = 3;
	} catch (e: unknown) {
		stepError.value = getErrorMessage(e, "Failed to send");
	} finally {
		sending.value = false;
	}
}

function buildLink(token: string) {
	return `${window.location.origin}/q/${token}`;
}

async function copyLink(token: string) {
	try {
		await navigator.clipboard.writeText(buildLink(token));
		copiedToken.value = token;
		setTimeout(() => { if (copiedToken.value === token) copiedToken.value = null; }, 2000);
	} catch {
		stepError.value = "Failed to copy link";
	}
}

function formatDate(dateStr: string): string {
	return new Date(dateStr).toLocaleDateString("en-US", { month: "short", day: "numeric" });
}
</script>
```

### 3.2 Frontend Tests — Phase 3

**File:** `fyli-fe-v2/src/views/question/AskQuestionsView.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount, flushPromises } from "@vue/test-utils";
import { createRouter, createWebHistory } from "vue-router";
import AskQuestionsView from "./AskQuestionsView.vue";

vi.mock("@/services/questionApi", () => ({
	getQuestionSets: vi.fn(),
	createQuestionSet: vi.fn(),
	createQuestionRequest: vi.fn(),
	getPreviousRecipients: vi.fn()
}));

import {
	getQuestionSets,
	createQuestionSet,
	createQuestionRequest,
	getPreviousRecipients
} from "@/services/questionApi";

function createWrapper(query = {}) {
	const router = createRouter({
		history: createWebHistory(),
		routes: [
			{ path: "/questions/new", component: { template: "<div />" } },
			{ path: "/questions", component: { template: "<div />" } }
		]
	});
	router.push({ path: "/questions/new", query });
	return mount(AskQuestionsView, {
		global: { plugins: [router] }
	});
}

describe("AskQuestionsView", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		(getQuestionSets as any).mockResolvedValue({ data: [] });
		(getPreviousRecipients as any).mockResolvedValue({ data: [] });
	});

	it("shows step 0 (pick) by default", async () => {
		const wrapper = createWrapper();
		await flushPromises();
		expect(wrapper.text()).toContain("Ask Questions");
		expect(wrapper.text()).toContain("Create new questions");
	});

	it("shows existing sets when available", async () => {
		(getQuestionSets as any).mockResolvedValue({
			data: [{ questionSetId: 1, name: "Existing Set", questions: [{ text: "Q1" }] }]
		});
		const wrapper = createWrapper();
		await flushPromises();
		expect(wrapper.text()).toContain("Existing Set");
	});

	it("navigates to step 1 when create new selected", async () => {
		const wrapper = createWrapper();
		await flushPromises();
		await wrapper.find("button.btn-primary").trigger("click");
		expect(wrapper.text()).toContain("Create Questions");
	});

	it("skips to step 2 when setId query param provided", async () => {
		const wrapper = createWrapper({ setId: "5" });
		await flushPromises();
		expect(wrapper.text()).toContain("Who should answer");
	});

	it("shows previous recipients in step 2", async () => {
		(getPreviousRecipients as any).mockResolvedValue({
			data: [{ email: "grandma@test.com", alias: "Grandma", lastSentAt: "2026-01-01T00:00:00Z" }]
		});
		const wrapper = createWrapper({ setId: "5" });
		await flushPromises();
		expect(wrapper.text()).toContain("grandma@test.com");
		expect(wrapper.text()).toContain("Grandma");
	});

	it("validates email required on send", async () => {
		const wrapper = createWrapper({ setId: "5" });
		await flushPromises();
		// Try to send with empty recipients
		const sendBtn = wrapper.findAll("button.btn-primary").find(b => b.text().includes("Send"));
		await sendBtn!.trigger("click");
		expect(wrapper.text()).toContain("At least one recipient");
	});

	it("calls createQuestionRequest on send", async () => {
		(createQuestionRequest as any).mockResolvedValue({
			data: { questionRequestId: 1, recipients: [{ questionRequestRecipientId: 1, token: "abc", email: "test@test.com" }] }
		});
		const wrapper = createWrapper({ setId: "5" });
		await flushPromises();

		// Fill in email
		const emailInput = wrapper.find('input[type="email"]');
		await emailInput.setValue("test@test.com");

		const sendBtn = wrapper.findAll("button.btn-primary").find(b => b.text().includes("Send"));
		await sendBtn!.trigger("click");
		await flushPromises();

		expect(createQuestionRequest).toHaveBeenCalledWith({
			questionSetId: 5,
			recipients: [{ email: "test@test.com", alias: undefined }],
			message: undefined
		});
	});

	it("shows confirmation with links after send", async () => {
		(createQuestionRequest as any).mockResolvedValue({
			data: {
				questionRequestId: 1,
				recipients: [{ questionRequestRecipientId: 1, token: "abc-token", email: "test@test.com", alias: "Test" }]
			}
		});
		const wrapper = createWrapper({ setId: "5" });
		await flushPromises();
		const emailInput = wrapper.find('input[type="email"]');
		await emailInput.setValue("test@test.com");
		const sendBtn = wrapper.findAll("button.btn-primary").find(b => b.text().includes("Send"));
		await sendBtn!.trigger("click");
		await flushPromises();

		expect(wrapper.text()).toContain("Questions sent!");
		expect(wrapper.text()).toContain("abc-token");
	});
});
```

**File:** `fyli-fe-v2/src/services/questionApi.test.ts`

Add to existing test file (or create):

```typescript
import { describe, it, expect, vi } from "vitest";
import { getUnifiedQuestionSets, getPreviousRecipients } from "./questionApi";
import api from "./api";

vi.mock("./api");

describe("questionApi - unified page", () => {
	it("getUnifiedQuestionSets calls correct endpoint", async () => {
		(api.get as any).mockResolvedValue({ data: [] });
		await getUnifiedQuestionSets(0, 20);
		expect(api.get).toHaveBeenCalledWith("/questions/sets/unified", { params: { skip: 0, take: 20 } });
	});

	it("getPreviousRecipients calls correct endpoint", async () => {
		(api.get as any).mockResolvedValue({ data: [] });
		await getPreviousRecipients();
		expect(api.get).toHaveBeenCalledWith("/questions/recipients/previous");
	});
});
```

---

## Phase 4: Cleanup & Polish

### 4.1 Files to Remove

- `fyli-fe-v2/src/views/question/QuestionSetListView.vue` — replaced by UnifiedQuestionsView
- `fyli-fe-v2/src/views/question/QuestionRequestsView.vue` — merged into UnifiedQuestionsView
- `fyli-fe-v2/src/views/question/QuestionSendView.vue` — replaced by AskQuestionsView
- `fyli-fe-v2/src/views/question/QuestionDashboardView.vue` — legacy, not routed
- `fyli-fe-v2/src/views/question/QuestionResponsesView.vue` — legacy, not routed

### 4.2 Files to Update

- `fyli-fe-v2/src/components/memory/MemoryCard.vue` — change `/questions/requests` → `/questions`
- `fyli-fe-v2/src/components/question/QuestionAnswerCard.vue` — change `/questions/requests` → `/questions`
- `fyli-fe-v2/src/views/question/QuestionSetEditView.vue` — update cancel link and save redirect to `/questions`

### 4.3 Verify

- All redirects from old routes work (`/questions/requests`, `/questions/dashboard`, `/questions/responses`, `/questions/:id/send`)
- Bottom nav "Questions" still highlights for all `/questions/*` paths (already works — `matchPaths: ['/questions']`)
- Empty state on unified page guides new users through flow

---

## Database Changes

No new tables or columns required. The new endpoints aggregate existing data using JOINs across:
- `QuestionSets`
- `Questions`
- `QuestionRequests`
- `QuestionRequestRecipients`
- `QuestionResponses`
- `Drops` (with `ContentDrop`, `Images`, `Movies`)

No migration needed.

---

## Raw SQL Reference

No schema changes. For reference, the existing schema used by the new queries:

```sql
-- Aggregation query conceptual shape (implemented via EF Core LINQ, not raw SQL)
SELECT
    qs.QuestionSetId,
    qs.Name,
    COUNT(DISTINCT qrr.QuestionRequestRecipientId) AS TotalRecipients,
    COUNT(DISTINCT CASE WHEN EXISTS (
        SELECT 1 FROM [QuestionResponses] qresp
        WHERE qresp.QuestionRequestRecipientId = qrr.QuestionRequestRecipientId
    ) THEN qrr.QuestionRequestRecipientId END) AS RespondedRecipients
FROM [QuestionSets] qs
LEFT JOIN [QuestionRequests] qr ON qr.QuestionSetId = qs.QuestionSetId
LEFT JOIN [QuestionRequestRecipients] qrr ON qrr.QuestionRequestId = qr.QuestionRequestId
WHERE qs.UserId = @userId AND qs.Archived = 0
GROUP BY qs.QuestionSetId, qs.Name;
```

---

## Testing Summary

### Backend Tests (Phase 1)
| Test | Description |
|------|-------------|
| `GetUnifiedQuestionSets_ReturnsDraftSets` | Draft sets returned with zero recipients |
| `GetUnifiedQuestionSets_AggregatesAcrossMultipleSends` | Counts aggregate across sends |
| `GetUnifiedQuestionSets_SortsPendingBeforeComplete` | Pending sets sort first |
| `GetUnifiedQuestionSets_ExcludesArchivedSets` | Archived sets filtered out |
| `GetUnifiedQuestionSets_IncludesLatestActivityDescription` | Activity description populated |
| `GetPreviousRecipients_ReturnsDistinctByEmail` | Deduplication works |
| `GetPreviousRecipients_ReturnsMostRecentAlias` | Most recent alias returned |
| `GetPreviousRecipients_ExcludesAliasOnlyRecipients` | No-email recipients excluded |
| `GetPreviousRecipients_OnlyReturnsOwnRecipients` | User isolation |
| `CreateQuestionRequest_RequiresEmail` | Alias-only rejected |
| `CreateQuestionRequest_DeduplicatesExistingRecipients` | Existing tokens reused |

### Frontend Tests (Phases 2-3)
| Test | Description |
|------|-------------|
| `UnifiedQuestionsView` shows loading | Spinner on load |
| `UnifiedQuestionsView` renders cards | Cards rendered after load |
| `UnifiedQuestionsView` empty state | Empty state displayed |
| `UnifiedQuestionsView` error state | Error handling |
| `UnifiedQuestionsView` delete | Delete flow |
| `QuestionSetCard` draft badge | Draft state rendering |
| `QuestionSetCard` response count | Sent state rendering |
| `QuestionSetCard` Ask Questions button | Draft action |
| `QuestionSetCard` send emit | Event emission |
| `QuestionSetCard` expand toggle | Expand/collapse |
| `QuestionSetCard` activity description | Activity text |
| `AskQuestionsView` step 0 default | Initial state |
| `AskQuestionsView` existing sets | Set picker |
| `AskQuestionsView` step 1 navigation | Create flow |
| `AskQuestionsView` step 2 with setId | Direct send flow |
| `AskQuestionsView` previous recipients | Recipient suggestions |
| `AskQuestionsView` email validation | Required email |
| `AskQuestionsView` send call | API integration |
| `AskQuestionsView` confirmation | Result display |
| `questionApi` unified endpoint | API function |
| `questionApi` previous recipients | API function |

**Total: 11 backend + 21 frontend = 32 tests**

---

## Implementation Order

1. **Phase 1:** Backend models, service methods, controller endpoints, backend tests
2. **Phase 2:** Frontend types, API functions, UnifiedQuestionsView, QuestionSetCard, router updates, frontend tests
3. **Phase 3:** AskQuestionsView (multi-step wizard), frontend tests
4. **Phase 4:** Remove old files, update internal links, verify redirects

---

*Document Version: 1.1*
*Created: 2026-02-07*
*Updated: 2026-02-07 — Code review fixes (pagination perf, dedup ID, type safety, UX improvements)*
