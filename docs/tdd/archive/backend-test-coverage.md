# TDD: Backend Test Coverage Improvement

## Overview

This document defines the strategy and implementation plan for achieving meaningful test coverage in the cimplur-core backend. The current test coverage is minimal (~3-5%), focusing only on `DropsService` and `PermissionService`. This plan prioritizes high-value services and establishes patterns for sustainable testing.

## Current State Analysis

### Existing Test Infrastructure

- **Framework:** MSTest (Microsoft.VisualStudio.TestTools.UnitTesting)
- **Location:** `cimplur-core/Memento/DomainTest/`
- **Database:** Real SQL Server database (localhost:1433)
- **Pattern:** Integration tests against local database

### Existing Test Files

| File | Tests | Status |
|------|-------|--------|
| `DropsServiceTest.cs` | 11 tests | Well-covered |
| `PermissionServiceTest.cs` | 8 tests | Well-covered |
| `MemoryShareLinkServiceTest.cs` | 1 test | Minimal |
| `ImageServiceTest.cs` | 0 tests | Stub only |
| `UserServiceTest.cs` | 0 tests | Stub only |
| `BaseRepositoryTest.cs` | N/A | Test base class |
| `TestServiceFactory.cs` | N/A | Service factory |

### Services Without Tests (20 total services)

| Service | Lines | Complexity | Priority |
|---------|-------|------------|----------|
| `SharingService` | ~1200 | High | **P1** |
| `UserService` | ~450 | Medium-High | **P1** |
| `NotificationService` | ~400 | Medium | **P2** |
| `GroupService` | ~650 | Medium-High | **P2** |
| `TimelineService` | ~400 | Medium | **P2** |
| `AlbumService` | ~350 | Medium | **P3** |
| `PromptService` | ~550 | Medium | **P3** |
| `PlanService` | ~300 | Medium | **P3** |
| `ContactService` | ~150 | Low | **P4** |
| `TransactionService` | ~200 | Low | **P4** |
| `ExportService` | ~300 | Low | **P4** |
| `TokenService` | ~100 | Low | **P4** |
| `EventService` | ~50 | Low | **P4** |

---

## Service Method Reference

### GroupService Methods

| Method | Signature | Async |
|--------|-----------|-------|
| `Add` | `long Add(string tagName, int userId, bool setup = false)` | No |
| `AllGroups` | `Task<List<GroupModel>> AllGroups(int userId)` | Yes |
| `EditableGroups` | `Task<List<GroupModel>> EditableGroups(int userId)` | Yes |
| `Rename` | `Task<string> Rename(int currentUserId, int networkId, string name)` | Yes |
| `Archive` | `Task Archive(long networkId, int userId)` | Yes |
| `UpdateNetworkViewers` | `Task<GroupViewersModel> UpdateNetworkViewers(int ownerId, long networkId, List<int> viewerIds)` | Yes |
| `GetNetworksAndViewersModels` | `Task<List<GroupViewersModel>> GetNetworksAndViewersModels(int ownerId)` | Yes |

### TimelineService Methods

| Method | Signature | Async |
|--------|-----------|-------|
| `AddTimeline` | `Task<TimelineModel> AddTimeline(int currentUserId, string name, string description)` | Yes |
| `GetAllTimelines` | `Task<List<TimelineModel>> GetAllTimelines(int currentUserId)` | Yes |
| `GetTimeline` | `Task<TimelineModel> GetTimeline(int currentUserId, int timelineId)` | Yes |
| `SoftDeleteTimeline` | `Task<TimelineModel> SoftDeleteTimeline(int currentUserId, int timelineId)` | Yes |
| `AddDropToTimeline` | `Task AddDropToTimeline(int currentUserId, int dropId, int timelineId)` | Yes |
| `RemoveDropFromTimeline` | `Task RemoveDropFromTimeline(int currentUserId, int dropId, int timelineId)` | Yes |

### SharingService Methods

| Method | Signature | Async |
|--------|-----------|-------|
| `GetConnectionRequests` | `List<ConnectionModel> GetConnectionRequests(int userId)` | No |
| `GetSuggestions` | `Task<List<SuggestionModel>> GetSuggestions(int userId)` | Yes |
| `RequestConnection` | `Task<ReturnModel> RequestConnection(int currentUsrId, ConnectionRequestModel model, bool sharePlan = false)` | Yes |
| `IgnoreRequest` | `Task IgnoreRequest(string token, int currentUserId)` | Yes |
| `RemoveConnection` | `void RemoveConnection(int userId, int toRemoveuserId)` | No |

### AlbumService Methods

| Method | Signature | Async |
|--------|-----------|-------|
| `GetActive` | `Task<List<AlbumModel>> GetActive(int userId)` | Yes |
| `GetAll` | `Task<List<AlbumModel>> GetAll(int userId)` | Yes |
| `Create` | `Task<AlbumModel> Create(int userId, string name)` | Yes |
| `Delete` | `Task Delete(int userId, int albumId)` | Yes |
| `AddToMoment` | `Task AddToMoment(int userId, int id, int momentId)` | Yes |
| `RemoveToMoment` | `Task RemoveToMoment(int userId, int id, int momentId)` | Yes |

### NotificationService Methods

| Method | Signature | Async |
|--------|-----------|-------|
| `Notifications` | `NotificationsModel Notifications(int userId)` | No |
| `ViewNotification` | `void ViewNotification(int userId, int dropId)` | No |
| `RemoveAllNotifications` | `void RemoveAllNotifications(int userId)` | No |
| `AddNotificationDropAdded` | `Task AddNotificationDropAdded(int userId, HashSet<long> networkIds, int dropId)` | Yes |

### PromptService Methods

| Method | Signature | Async |
|--------|-----------|-------|
| `GetActivePrompts` | `Task<List<PromptModel>> GetActivePrompts(int currentUserId)` | Yes |
| `GetAllPrompts` | `Task<List<PromptModel>> GetAllPrompts(int currentUserId)` | Yes |
| `CreatePrompt` | `Task<PromptModel> CreatePrompt(int currentUserId, string question)` | Yes |
| `GetPrompt` | `Task<PromptModel> GetPrompt(int currentUserId, int promptId)` | Yes |
| `DismissPrompt` | `Task DismissPrompt(int currentUserId, int promptId)` | Yes |

### PlanService Methods

| Method | Signature | Async |
|--------|-----------|-------|
| `GetPremiumPlanByUserId` | `Task<PlanModel> GetPremiumPlanByUserId(int userId)` | Yes |
| `GetPremiumPlanById` | `Task<PlanModel> GetPremiumPlanById(int planId)` | Yes |
| `AddPremiumPlan` | `Task<PlanModel> AddPremiumPlan(int userId, PlanTypes planType, int? transactionId, int? sharePlanId, int? familyCount, int? parentPremiumPlanId)` | Yes |
| `GetSharedPlans` | `Task<List<SharedPlanModel>> GetSharedPlans(int userId)` | Yes |

---

## Architecture Considerations

### Current Service Design

Services inherit from `BaseService` which creates its own `DbContext`:

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
                var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection");
                builder.UseSqlServer(connectionString);
                context = new StreamContext(builder.Options);
            }
            return context;
        }
    }
}
```

### Testing Challenges

1. **Context Ownership:** Services create their own `DbContext`, not injected
2. **Entity State:** Test context and service context are separate - requires detaching entities
3. **External Dependencies:** Some services call AWS (S3, SQS), Stripe, Postmark
4. **Circular Dependencies:** Services reference each other (e.g., UserService → DropsService → NotificationService)

### Testing Strategy

**Approach: Integration Tests with Real Database + Transaction Rollback**

The existing pattern uses the local development database. We enhance this with transaction-based isolation:
- Tests actual database behavior (constraints, cascades, queries)
- Catches EF Core query translation issues
- Transaction rollback ensures clean state after each test
- No orphaned test data pollutes the database

---

## Implementation Plan

### Phase 1: Enhance Test Infrastructure ✅ COMPLETE

Improve the base test classes to support more scenarios with proper isolation.

#### 1.1 Extend BaseRepositoryTest with Transaction Support and More Helpers

**File:** `DomainTest/Repositories/BaseRepositoryTest.cs`

```csharp
using Domain.Entities;
using Domain.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace DomainTest.Repositories
{
    /// <summary>
    /// Base class for repository tests that provides database setup, teardown,
    /// and transaction-based isolation for test data cleanup.
    /// </summary>
    public abstract class BaseRepositoryTest
    {
        protected StreamContext context;
        private IDbContextTransaction transaction;

        /// <summary>
        /// Creates a new database context for test operations.
        /// Uses environment variable or falls back to local dev connection.
        /// </summary>
        protected StreamContext CreateTestContext()
        {
            var builder = new DbContextOptionsBuilder<StreamContext>();
            builder.EnableDetailedErrors(true);
            var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection")
                ?? "Server=localhost,1433; Database=Master; User Id=SA; Password=Dog1$Dobbie!; Encrypt=False;";
            builder.UseSqlServer(connectionString);
            return new StreamContext(builder.Options);
        }

        /// <summary>
        /// Initializes test context with transaction for automatic rollback.
        /// Call this in [TestInitialize] for transaction-based isolation.
        /// </summary>
        protected void InitializeWithTransaction()
        {
            this.context = CreateTestContext();
            this.transaction = context.Database.BeginTransaction();
        }

        /// <summary>
        /// Rolls back transaction and disposes context.
        /// Call this in [TestCleanup] to ensure clean state.
        /// </summary>
        protected void CleanupWithTransaction()
        {
            try
            {
                transaction?.Rollback();
            }
            catch
            {
                // Transaction may already be disposed
            }
            finally
            {
                transaction?.Dispose();
                context?.Dispose();
            }
        }

        #region User Helpers

        /// <summary>
        /// Creates a test user with unique email and optional custom name.
        /// </summary>
        protected async Task<UserProfile> CreateTestUser(StreamContext context, string email = null, string name = null)
        {
            email = email ?? $"test_{Guid.NewGuid():N}@test.com";
            name = name ?? "Test User";

            var user = new UserProfile
            {
                Email = email,
                UserName = email.Split('@')[0],
                Name = name,
                Created = DateTime.UtcNow,
                SuggestionReminderSent = DateTime.UtcNow,
                QuestionRemindersSent = DateTime.UtcNow,
                Token = Guid.NewGuid().ToString()
            };

            context.UserProfiles.Add(user);
            await context.SaveChangesAsync();
            return user;
        }

        /// <summary>
        /// Creates a test user with premium membership.
        /// </summary>
        protected async Task<UserProfile> CreateTestPremiumUser(StreamContext context, int premiumDays = 30)
        {
            var user = await CreateTestUser(context);
            user.PremiumExpiration = DateTime.UtcNow.AddDays(premiumDays);
            await context.SaveChangesAsync();
            return user;
        }

        #endregion

        #region Drop Helpers

        /// <summary>
        /// Creates a test drop (memory) with content.
        /// </summary>
        protected async Task<Drop> CreateTestDrop(StreamContext context, int userId, DateTime? date = null, string content = "Test content")
        {
            date = date ?? DateTime.UtcNow;
            var drop = new Drop
            {
                UserId = userId,
                Date = date.Value,
                DateType = DateTypes.Exact,
                Created = DateTime.UtcNow,
                DayOfYear = date.Value.DayOfYear,
                ContentDrop = new ContentDrop
                {
                    Stuff = content
                }
            };

            context.Drops.Add(drop);
            await context.SaveChangesAsync();
            return drop;
        }

        #endregion

        #region Comment Helpers

        /// <summary>
        /// Creates a test comment on a drop.
        /// </summary>
        protected async Task<Comment> CreateTestComment(StreamContext context, int dropId, int userId, string content = "Test comment")
        {
            var comment = new Comment
            {
                DropId = dropId,
                UserId = userId,
                Content = content,
                TimeStamp = DateTime.UtcNow,
                Kind = KindOfComments.Normal
            };

            context.Comments.Add(comment);
            await context.SaveChangesAsync();
            return comment;
        }

        #endregion

        #region Media Helpers

        /// <summary>
        /// Creates a test image attached to a drop, optionally on a comment.
        /// </summary>
        protected async Task<ImageDrop> CreateTestImageDrop(StreamContext context, int dropId, int? commentId = null)
        {
            var drop = await context.Drops.FindAsync(dropId);
            if (drop == null)
            {
                throw new ArgumentException($"Drop with id {dropId} not found");
            }

            var imageDrop = new ImageDrop
            {
                DropId = dropId
            };

            // Use reflection to set CommentId since it has internal set
            if (commentId.HasValue)
            {
                var commentIdProperty = typeof(ImageDrop).GetProperty("CommentId");
                commentIdProperty?.SetValue(imageDrop, commentId.Value);
            }

            drop.Images.Add(imageDrop);
            await context.SaveChangesAsync();
            return imageDrop;
        }

        /// <summary>
        /// Creates a test movie attached to a drop, optionally on a comment.
        /// </summary>
        protected async Task<MovieDrop> CreateTestMovieDrop(StreamContext context, int dropId, int? commentId = null, bool isTranscodeV2 = true)
        {
            var drop = await context.Drops.FindAsync(dropId);
            if (drop == null)
            {
                throw new ArgumentException($"Drop with id {dropId} not found");
            }

            var movieDrop = new MovieDrop
            {
                DropId = dropId,
                IsTranscodeV2 = isTranscodeV2
            };

            // Use reflection to set CommentId since it has internal set
            if (commentId.HasValue)
            {
                var commentIdProperty = typeof(MovieDrop).GetProperty("CommentId");
                commentIdProperty?.SetValue(movieDrop, commentId.Value);
            }

            drop.Movies.Add(movieDrop);
            await context.SaveChangesAsync();
            return movieDrop;
        }

        #endregion

        #region Group/Network Helpers

        /// <summary>
        /// Creates a test group (UserTag/Network) for a user.
        /// </summary>
        protected async Task<UserTag> CreateTestGroup(StreamContext context, int userId, string name = null)
        {
            name = name ?? $"TestGroup_{Guid.NewGuid():N}";
            var group = new UserTag
            {
                UserId = userId,
                Name = name,
                Created = DateTime.UtcNow,
                Archived = false,
                IsTask = false
            };
            context.UserNetworks.Add(group);
            await context.SaveChangesAsync();
            return group;
        }

        /// <summary>
        /// Adds a viewer to a group.
        /// </summary>
        protected async Task<TagViewer> AddViewerToGroup(StreamContext context, long groupId, int viewerUserId)
        {
            var tagViewer = new TagViewer
            {
                UserTagId = groupId,
                ViewerUserId = viewerUserId,
                Created = DateTime.UtcNow
            };
            context.NetworkViewers.Add(tagViewer);
            await context.SaveChangesAsync();
            return tagViewer;
        }

        /// <summary>
        /// Tags a drop to a group.
        /// </summary>
        protected async Task<TagDrop> TagDropToGroup(StreamContext context, long groupId, int dropId)
        {
            var tagDrop = new TagDrop
            {
                UserTagId = groupId,
                DropId = dropId
            };
            context.NetworkDrops.Add(tagDrop);
            await context.SaveChangesAsync();
            return tagDrop;
        }

        #endregion

        #region Connection Helpers

        /// <summary>
        /// Creates a connection between two users (owner shares with reader).
        /// </summary>
        protected async Task<UserUser> CreateTestConnection(StreamContext context, int ownerUserId, int readerUserId, string readerName = null)
        {
            var connection = new UserUser
            {
                OwnerUserId = ownerUserId,
                ReaderUserId = readerUserId,
                ReaderName = readerName,
                Created = DateTime.UtcNow,
                SendNotificationEmail = false
            };
            context.UserUsers.Add(connection);
            await context.SaveChangesAsync();
            return connection;
        }

        /// <summary>
        /// Creates a share request from one user to another.
        /// </summary>
        protected async Task<ShareRequest> CreateTestShareRequest(StreamContext context, int requesterUserId, int? targetUserId = null, string targetEmail = null)
        {
            var request = new ShareRequest
            {
                RequesterUserId = requesterUserId,
                TargetsUserId = targetUserId,
                TargetsEmail = targetEmail ?? $"target_{Guid.NewGuid():N}@test.com",
                RequestKey = Guid.NewGuid(),
                Pending = true,
                Ignored = false,
                Used = false,
                Created = DateTime.UtcNow,
                CreatedAt = DateTime.UtcNow
            };
            context.ShareRequests.Add(request);
            await context.SaveChangesAsync();
            return request;
        }

        #endregion

        #region Album Helpers

        /// <summary>
        /// Creates a test album for a user.
        /// </summary>
        protected async Task<Album> CreateTestAlbum(StreamContext context, int userId, string name = null)
        {
            name = name ?? $"TestAlbum_{Guid.NewGuid():N}";
            var album = new Album
            {
                UserId = userId,
                Name = name,
                Created = DateTime.UtcNow,
                Archived = false
            };
            context.Albums.Add(album);
            await context.SaveChangesAsync();
            return album;
        }

        /// <summary>
        /// Adds a drop to an album.
        /// </summary>
        protected async Task<AlbumDrop> AddDropToAlbum(StreamContext context, int albumId, int dropId)
        {
            var albumDrop = new AlbumDrop
            {
                AlbumId = albumId,
                DropId = dropId
            };
            context.AlbumDrops.Add(albumDrop);
            await context.SaveChangesAsync();
            return albumDrop;
        }

        #endregion

        #region Timeline Helpers

        /// <summary>
        /// Creates a test timeline for a user.
        /// </summary>
        protected async Task<TimeLine> CreateTestTimeline(StreamContext context, int userId, string name = null, string description = null)
        {
            name = name ?? $"TestTimeline_{Guid.NewGuid():N}";
            var timeline = new TimeLine
            {
                UserId = userId,
                Name = name,
                Description = description ?? "Test description",
                Created = DateTime.UtcNow
            };
            context.Timelines.Add(timeline);
            await context.SaveChangesAsync();
            return timeline;
        }

        /// <summary>
        /// Adds a drop to a timeline.
        /// </summary>
        protected async Task<TimelineDrop> AddDropToTimeline(StreamContext context, int timelineId, int dropId)
        {
            var timelineDrop = new TimelineDrop
            {
                TimeLineId = timelineId,
                DropId = dropId
            };
            context.TimelineDrops.Add(timelineDrop);
            await context.SaveChangesAsync();
            return timelineDrop;
        }

        #endregion

        #region Prompt Helpers

        /// <summary>
        /// Creates a test prompt (question).
        /// </summary>
        protected async Task<Prompt> CreateTestPrompt(StreamContext context, string question = null, bool active = true)
        {
            question = question ?? $"Test question {Guid.NewGuid():N}?";
            var prompt = new Prompt
            {
                Question = question,
                Created = DateTime.UtcNow,
                Active = active
            };
            context.Prompts.Add(prompt);
            await context.SaveChangesAsync();
            return prompt;
        }

        /// <summary>
        /// Creates a user prompt association.
        /// </summary>
        protected async Task<UserPrompt> CreateTestUserPrompt(StreamContext context, int userId, int promptId)
        {
            var userPrompt = new UserPrompt
            {
                UserId = userId,
                PromptId = promptId,
                Created = DateTime.UtcNow
            };
            context.UserPrompts.Add(userPrompt);
            await context.SaveChangesAsync();
            return userPrompt;
        }

        #endregion

        #region Notification Helpers

        /// <summary>
        /// Creates a test notification for a user.
        /// </summary>
        protected async Task<SharedDropNotification> CreateTestNotification(StreamContext context, int targetUserId, int dropId, int sourceUserId)
        {
            var notification = new SharedDropNotification
            {
                TargetUserId = targetUserId,
                DropId = dropId,
                SourceUserId = sourceUserId,
                Created = DateTime.UtcNow,
                Viewed = false
            };
            context.SharedDropNotifications.Add(notification);
            await context.SaveChangesAsync();
            return notification;
        }

        /// <summary>
        /// Creates a UserDrop record for tracking viewed state.
        /// </summary>
        protected async Task<UserDrop> CreateTestUserDrop(StreamContext context, int userId, int dropId, bool viewed = false)
        {
            var userDrop = new UserDrop
            {
                UserId = userId,
                DropId = dropId,
                ViewedDate = viewed ? DateTime.UtcNow : (DateTime?)null
            };
            context.UserDrops.Add(userDrop);
            await context.SaveChangesAsync();
            return userDrop;
        }

        #endregion

        #region Utility Methods

        /// <summary>
        /// Detaches all tracked entities from the context.
        /// Use this before calling service methods so they can load fresh data.
        /// </summary>
        protected void DetachAllEntities(StreamContext context)
        {
            foreach (var entry in context.ChangeTracker.Entries())
            {
                entry.State = EntityState.Detached;
            }
        }

        /// <summary>
        /// Creates a fresh context for verification after service operations.
        /// </summary>
        protected StreamContext CreateVerificationContext()
        {
            return CreateTestContext();
        }

        #endregion
    }
}
```

#### 1.2 Extend TestServiceFactory

**File:** `DomainTest/Repositories/TestServiceFactory.cs`

```csharp
using Domain.Emails;
using Domain.Models;
using Domain.Repository;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System;

namespace DomainTest.Repositories
{
    /// <summary>
    /// Factory for creating test service instances with minimal dependencies.
    /// All services use the DatabaseConnection environment variable for their context.
    /// </summary>
    public static class TestServiceFactory
    {
        #region Core Services

        public static PermissionService CreatePermissionService()
        {
            return new PermissionService();
        }

        public static ImageService CreateImageService(PermissionService permissionService = null)
        {
            permissionService = permissionService ?? CreatePermissionService();
            return new ImageService(permissionService);
        }

        public static MovieService CreateMovieService(PermissionService permissionService = null)
        {
            permissionService = permissionService ?? CreatePermissionService();
            return new MovieService(permissionService);
        }

        public static SendEmailService CreateSendEmailService()
        {
            var appSettings = Options.Create(new AppSettings
            {
                Production = false,
                Owner = "test@test.com",
                EmailCode = "test",
                EmailToken = "test"
            });
            return new SendEmailService(appSettings, null);
        }

        #endregion

        #region Group & Sharing Services

        public static GroupService CreateGroupService(SendEmailService sendEmailService = null)
        {
            sendEmailService = sendEmailService ?? CreateSendEmailService();
            return new GroupService(sendEmailService);
        }

        public static NotificationService CreateNotificationService(
            SendEmailService sendEmailService = null,
            GroupService groupService = null,
            ILogger<NotificationService> logger = null)
        {
            sendEmailService = sendEmailService ?? CreateSendEmailService();
            groupService = groupService ?? CreateGroupService(sendEmailService);
            return new NotificationService(sendEmailService, groupService, logger);
        }

        public static SharingService CreateSharingService(
            SendEmailService sendEmailService = null,
            NotificationService notificationService = null,
            GroupService groupService = null)
        {
            sendEmailService = sendEmailService ?? CreateSendEmailService();
            groupService = groupService ?? CreateGroupService(sendEmailService);
            notificationService = notificationService ?? CreateNotificationService(sendEmailService, groupService);
            var dropsService = CreateDropsService(sendEmailService, notificationService, null, groupService);
            var userService = new UserService(
                notificationService, sendEmailService, dropsService,
                new AlbumService(dropsService), null);
            var timelineService = new TimelineService(notificationService, dropsService, userService);
            var promptService = new PromptService(sendEmailService, timelineService, dropsService, userService);
            return new SharingService(
                sendEmailService,
                notificationService,
                promptService,
                timelineService,
                groupService
            );
        }

        #endregion

        #region User & Profile Services

        public static UserService CreateUserService(
            SendEmailService sendEmailService = null,
            NotificationService notificationService = null,
            DropsService dropsService = null)
        {
            sendEmailService = sendEmailService ?? CreateSendEmailService();
            var groupService = CreateGroupService(sendEmailService);
            notificationService = notificationService ?? CreateNotificationService(sendEmailService, groupService);
            dropsService = dropsService ?? CreateDropsService(sendEmailService, notificationService, null, groupService);
            return new UserService(
                notificationService,
                sendEmailService,
                dropsService,
                new AlbumService(dropsService),
                null
            );
        }

        #endregion

        #region Content Services

        public static DropsService CreateDropsService(
            SendEmailService sendEmailService = null,
            NotificationService notificationService = null,
            MovieService movieService = null,
            GroupService groupService = null,
            ImageService imageService = null)
        {
            sendEmailService = sendEmailService ?? CreateSendEmailService();
            groupService = groupService ?? CreateGroupService(sendEmailService);
            notificationService = notificationService ?? CreateNotificationService(sendEmailService, groupService);
            movieService = movieService ?? CreateMovieService();
            imageService = imageService ?? CreateImageService();

            return new DropsService(
                sendEmailService,
                notificationService,
                movieService,
                groupService,
                imageService
            );
        }

        public static AlbumService CreateAlbumService(DropsService dropsService = null)
        {
            dropsService = dropsService ?? CreateDropsService();
            return new AlbumService(dropsService);
        }

        public static TimelineService CreateTimelineService(
            NotificationService notificationService = null,
            DropsService dropsService = null,
            UserService userService = null)
        {
            var sendEmailService = CreateSendEmailService();
            var groupService = CreateGroupService(sendEmailService);
            notificationService = notificationService ?? CreateNotificationService(sendEmailService, groupService);
            dropsService = dropsService ?? CreateDropsService(sendEmailService, notificationService, null, groupService);
            userService = userService ?? CreateUserService(sendEmailService, notificationService, dropsService);
            return new TimelineService(notificationService, dropsService, userService);
        }

        public static PromptService CreatePromptService(
            SendEmailService sendEmailService = null,
            TimelineService timelineService = null,
            DropsService dropsService = null,
            UserService userService = null)
        {
            sendEmailService = sendEmailService ?? CreateSendEmailService();
            var groupService = CreateGroupService(sendEmailService);
            var notificationService = CreateNotificationService(sendEmailService, groupService);
            dropsService = dropsService ?? CreateDropsService(sendEmailService, notificationService, null, groupService);
            userService = userService ?? CreateUserService(sendEmailService, notificationService, dropsService);
            timelineService = timelineService ?? CreateTimelineService(notificationService, dropsService, userService);
            return new PromptService(sendEmailService, timelineService, dropsService, userService);
        }

        #endregion

        #region Memory Share Links

        public static MemoryShareLinkService CreateMemoryShareLinkService(
            SharingService sharingService = null,
            GroupService groupService = null,
            UserService userService = null,
            ImageService imageService = null,
            MovieService movieService = null)
        {
            var sendEmailService = CreateSendEmailService();
            groupService = groupService ?? CreateGroupService(sendEmailService);
            sharingService = sharingService ?? CreateSharingService(sendEmailService, null, groupService);
            userService = userService ?? CreateUserService(sendEmailService);
            imageService = imageService ?? new ImageService(new PermissionService());
            movieService = movieService ?? new MovieService(new PermissionService());
            return new MemoryShareLinkService(sharingService, groupService, userService, imageService, movieService);
        }

        #endregion

        #region Business Services

        public static PlanService CreatePlanService()
        {
            return new PlanService();
        }

        public static TransactionService CreateTransactionService()
        {
            return new TransactionService();
        }

        public static ContactService CreateContactService(SendEmailService sendEmailService = null)
        {
            sendEmailService = sendEmailService ?? CreateSendEmailService();
            return new ContactService(sendEmailService);
        }

        #endregion
    }
}
```

---

### Phase 2: P1 Services - User & Sharing (High Priority) ✅ COMPLETE

#### 2.1 UserServiceTest.cs

**File:** `DomainTest/Repositories/UserServiceTest.cs`

```csharp
using Domain.Entities;
using Domain.Exceptions;
using Domain.Repository;
using Microsoft.EntityFrameworkCore;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace DomainTest.Repositories
{
    [TestClass]
    [TestCategory("Integration")]
    [TestCategory("UserService")]
    public class UserServiceTest : BaseRepositoryTest
    {
        private UserService userService;

        [TestInitialize]
        public void Setup()
        {
            var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection")
                ?? "Server=localhost,1433; Database=Master; User Id=SA; Password=Dog1$Dobbie!; Encrypt=False;";
            Environment.SetEnvironmentVariable("DatabaseConnection", connectionString);

            InitializeWithTransaction();
            this.userService = TestServiceFactory.CreateUserService();
        }

        [TestCleanup]
        public void Cleanup()
        {
            userService?.Dispose();
            CleanupWithTransaction();
        }

        #region AddUser Tests

        [TestMethod]
        public async Task AddUser_WithValidData_ShouldCreateUser()
        {
            // Arrange
            var email = $"test_{Guid.NewGuid():N}@test.com";
            var userName = $"user_{Guid.NewGuid():N}";

            // Act
            var userId = await userService.AddUser(email, userName, null, true, "Test User", null);

            // Assert
            Assert.IsTrue(userId > 0);

            using (var verifyContext = CreateVerificationContext())
            {
                var user = await verifyContext.UserProfiles.FindAsync(userId);
                Assert.IsNotNull(user);
                Assert.AreEqual(email, user.Email);
                Assert.AreEqual(userName, user.UserName);
                Assert.AreEqual("Test User", user.Name);
                Assert.IsNotNull(user.AcceptedTerms);
                Assert.IsNotNull(user.PremiumExpiration);
            }
        }

        [TestMethod]
        [ExpectedException(typeof(BadRequestException))]
        public async Task AddUser_WithExistingUserName_ShouldThrowBadRequestException()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            await userService.AddUser("new@test.com", user.UserName, null, true, "New User", null);
        }

        [TestMethod]
        public async Task AddUser_WithReasons_ShouldSerializeReasons()
        {
            // Arrange
            var email = $"test_{Guid.NewGuid():N}@test.com";
            var userName = $"user_{Guid.NewGuid():N}";
            var reasons = new List<Domain.Models.ReasonModel>
            {
                new Domain.Models.ReasonModel { Reason = "Family memories" }
            };

            // Act
            var userId = await userService.AddUser(email, userName, null, true, "Test User", reasons);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var user = await verifyContext.UserProfiles.FindAsync(userId);
                Assert.IsNotNull(user.Reasons);
                Assert.IsTrue(user.Reasons.Contains("Family memories"));
            }
        }

        [TestMethod]
        public async Task AddUser_WithNullName_ShouldCreateUserWithNullName()
        {
            // Arrange
            var email = $"test_{Guid.NewGuid():N}@test.com";
            var userName = $"user_{Guid.NewGuid():N}";

            // Act
            var userId = await userService.AddUser(email, userName, null, true, null, null);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var user = await verifyContext.UserProfiles.FindAsync(userId);
                Assert.IsNotNull(user);
                Assert.IsNull(user.Name);
            }
        }

        [TestMethod]
        public async Task AddUser_WithoutAcceptingTerms_ShouldNotSetPremiumExpiration()
        {
            // Arrange
            var email = $"test_{Guid.NewGuid():N}@test.com";
            var userName = $"user_{Guid.NewGuid():N}";

            // Act
            var userId = await userService.AddUser(email, userName, null, false, "Test User", null);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var user = await verifyContext.UserProfiles.FindAsync(userId);
                Assert.IsNotNull(user);
                Assert.IsNull(user.AcceptedTerms);
            }
        }

        #endregion

        #region GetUser Tests

        [TestMethod]
        public async Task GetUser_WithValidId_ShouldReturnUserModel()
        {
            // Arrange
            var user = await CreateTestPremiumUser(context, 30);
            DetachAllEntities(context);

            // Act
            var result = await userService.GetUser(user.UserId);

            // Assert
            Assert.IsNotNull(result);
            Assert.AreEqual(user.Name, result.Name);
            Assert.IsTrue(result.PremiumMember);
        }

        [TestMethod]
        [ExpectedException(typeof(NotFoundException))]
        public async Task GetUser_WithInvalidId_ShouldThrowNotFoundException()
        {
            // Act
            await userService.GetUser(99999);
        }

        [TestMethod]
        public async Task GetUser_WithExpiredPremium_ShouldReturnNonPremiumMember()
        {
            // Arrange
            var user = await CreateTestUser(context);
            user.PremiumExpiration = DateTime.UtcNow.AddDays(-1);
            await context.SaveChangesAsync();
            DetachAllEntities(context);

            // Act
            var result = await userService.GetUser(user.UserId);

            // Assert
            Assert.IsFalse(result.PremiumMember);
        }

        #endregion

        #region GetProfile Tests

        [TestMethod]
        public async Task GetProfile_WithValidId_ShouldReturnProfileModel()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await userService.GetProfile(user.UserId);

            // Assert
            Assert.IsNotNull(result);
            Assert.AreEqual(user.UserId, result.Id);
            Assert.AreEqual(user.Email, result.Email);
        }

        [TestMethod]
        [ExpectedException(typeof(NotFoundException))]
        public async Task GetProfile_WithInvalidId_ShouldThrowNotFoundException()
        {
            // Act
            await userService.GetProfile(99999);
        }

        #endregion

        #region ChangeName Tests

        [TestMethod]
        public async Task ChangeName_WithValidName_ShouldUpdateName()
        {
            // Arrange
            var user = await CreateTestUser(context, name: "Original Name");
            DetachAllEntities(context);

            // Act
            var result = await userService.ChangeName(user.UserId, "New Name");

            // Assert
            Assert.AreEqual("New Name", result.Name);

            using (var verifyContext = CreateVerificationContext())
            {
                var updated = await verifyContext.UserProfiles.FindAsync(user.UserId);
                Assert.AreEqual("New Name", updated.Name);
            }
        }

        [TestMethod]
        public async Task ChangeName_WithEmptyName_ShouldUseUserName()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await userService.ChangeName(user.UserId, "");

            // Assert
            Assert.AreEqual(user.UserName, result.Name);
        }

        [TestMethod]
        public async Task ChangeName_WithWhitespace_ShouldUseUserName()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await userService.ChangeName(user.UserId, "   ");

            // Assert
            Assert.AreEqual(user.UserName, result.Name);
        }

        [TestMethod]
        [ExpectedException(typeof(NotFoundException))]
        public async Task ChangeName_WithInvalidUserId_ShouldThrowNotFoundException()
        {
            // Act
            await userService.ChangeName(99999, "New Name");
        }

        #endregion

        #region GetConnections Tests

        [TestMethod]
        public async Task GetConnections_WithConnections_ShouldReturnList()
        {
            // Arrange
            var owner = await CreateTestUser(context, name: "Owner");
            var reader = await CreateTestUser(context, name: "Reader");
            await CreateTestConnection(context, owner.UserId, reader.UserId);
            DetachAllEntities(context);

            // Act
            var result = userService.GetConnections(owner.UserId);

            // Assert
            Assert.IsTrue(result.Count > 0);
            Assert.IsTrue(result.Exists(c => c.Id == reader.UserId));
        }

        [TestMethod]
        public async Task GetConnections_WithNoConnections_ShouldReturnEmptyList()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = userService.GetConnections(user.UserId);

            // Assert
            Assert.AreEqual(0, result.Count);
        }

        [TestMethod]
        public async Task GetConnections_ShouldReturnOrderedByName()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var readerA = await CreateTestUser(context, name: "Zebra");
            var readerB = await CreateTestUser(context, name: "Apple");
            await CreateTestConnection(context, owner.UserId, readerA.UserId);
            await CreateTestConnection(context, owner.UserId, readerB.UserId);
            DetachAllEntities(context);

            // Act
            var result = userService.GetConnections(owner.UserId);

            // Assert
            Assert.AreEqual(2, result.Count);
            Assert.AreEqual("Apple", result[0].Name);
            Assert.AreEqual("Zebra", result[1].Name);
        }

        #endregion

        #region UpdatePrivateMode Tests

        [TestMethod]
        public async Task UpdatePrivateMode_ToTrue_ShouldEnablePrivateMode()
        {
            // Arrange
            var user = await CreateTestUser(context);
            user.PrivateMode = false;
            await context.SaveChangesAsync();
            DetachAllEntities(context);

            // Act
            var result = await userService.UpdatePrivateMode(user.UserId, true);

            // Assert
            Assert.IsTrue(result.PrivateMode);
        }

        [TestMethod]
        public async Task UpdatePrivateMode_ToFalse_ShouldDisablePrivateMode()
        {
            // Arrange
            var user = await CreateTestUser(context);
            user.PrivateMode = true;
            await context.SaveChangesAsync();
            DetachAllEntities(context);

            // Act
            var result = await userService.UpdatePrivateMode(user.UserId, false);

            // Assert
            Assert.IsFalse(result.PrivateMode);
        }

        [TestMethod]
        [ExpectedException(typeof(NotFoundException))]
        public async Task UpdatePrivateMode_WithInvalidUserId_ShouldThrowNotFoundException()
        {
            // Act
            await userService.UpdatePrivateMode(99999, true);
        }

        #endregion

        #region CheckEmail Tests

        [TestMethod]
        public async Task CheckEmail_WithExistingEmail_ShouldReturnTrue()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = userService.CheckEmail(user.Email);

            // Assert
            Assert.IsTrue(result);
        }

        [TestMethod]
        public void CheckEmail_WithNonExistingEmail_ShouldReturnFalse()
        {
            // Act
            var result = userService.CheckEmail($"nonexistent_{Guid.NewGuid():N}@test.com");

            // Assert
            Assert.IsFalse(result);
        }

        [TestMethod]
        public async Task CheckEmail_WithExactMatch_ShouldReturnTrue()
        {
            // Arrange
            var user = await CreateTestUser(context, email: "TestUser@test.com");
            DetachAllEntities(context);

            // Act
            var result = userService.CheckEmail("TestUser@test.com");

            // Assert
            Assert.IsTrue(result);
        }

        #endregion

        #region IgnoreConnectionRequest Tests

        [TestMethod]
        public async Task IgnoreConnectionRequest_WithValidRequest_ShouldMarkAsIgnored()
        {
            // Arrange
            var requester = await CreateTestUser(context);
            var target = await CreateTestUser(context);
            var request = await CreateTestShareRequest(context, requester.UserId, target.UserId);
            DetachAllEntities(context);

            // Act
            userService.IgnoreConnectionRequest(target.UserId, requester.Email);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var updated = await verifyContext.ShareRequests.FindAsync(request.ShareRequestId);
                Assert.IsTrue(updated.Ignored);
            }
        }

        [TestMethod]
        public async Task IgnoreConnectionRequest_WithNonExistentRequester_ShouldNotThrow()
        {
            // Arrange
            var target = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act - Should not throw
            userService.IgnoreConnectionRequest(target.UserId, "nonexistent@test.com");

            // Assert - No exception thrown
        }

        #endregion

        #region Relationships Tests

        [TestMethod]
        public async Task GetRelationships_ShouldReturnAllRelationshipTypes()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await userService.GetRelationships(user.UserId);

            // Assert
            Assert.IsTrue(result.Count > 0);
        }

        [TestMethod]
        public async Task UpdateRelationships_ShouldAddSelectedRelationships()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var selected = new List<int> { 1, 2 };
            var result = await userService.UpdateRelationships(selected, user.UserId);

            // Assert
            Assert.IsTrue(result.Exists(r => r.Id == 1 && r.Selected));
            Assert.IsTrue(result.Exists(r => r.Id == 2 && r.Selected));
        }

        [TestMethod]
        public async Task UpdateRelationships_WithEmptyList_ShouldRemoveAllRelationships()
        {
            // Arrange
            var user = await CreateTestUser(context);
            await userService.UpdateRelationships(new List<int> { 1 }, user.UserId);
            DetachAllEntities(context);

            // Act
            var result = await userService.UpdateRelationships(new List<int>(), user.UserId);

            // Assert
            Assert.IsFalse(result.Exists(r => r.Selected));
        }

        #endregion
    }
}
```

#### 2.2 SharingServiceTest.cs

**File:** `DomainTest/Repositories/SharingServiceTest.cs`

```csharp
using Domain.Entities;
using Domain.Exceptions;
using Domain.Models;
using Domain.Repository;
using Microsoft.EntityFrameworkCore;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace DomainTest.Repositories
{
    [TestClass]
    [TestCategory("Integration")]
    [TestCategory("SharingService")]
    public class SharingServiceTest : BaseRepositoryTest
    {
        private SharingService sharingService;

        [TestInitialize]
        public void Setup()
        {
            var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection")
                ?? "Server=localhost,1433; Database=Master; User Id=SA; Password=Dog1$Dobbie!; Encrypt=False;";
            Environment.SetEnvironmentVariable("DatabaseConnection", connectionString);

            InitializeWithTransaction();
            this.sharingService = TestServiceFactory.CreateSharingService();
        }

        [TestCleanup]
        public void Cleanup()
        {
            sharingService?.Dispose();
            CleanupWithTransaction();
        }

        #region GetConnectionRequests Tests

        [TestMethod]
        public async Task GetConnectionRequests_WithPendingRequest_ShouldReturnRequests()
        {
            // Arrange
            var requester = await CreateTestUser(context, name: "Requester");
            var target = await CreateTestUser(context, name: "Target");
            var request = await CreateTestShareRequest(context, requester.UserId, target.UserId);
            request.RequestorName = "Requester";
            await context.SaveChangesAsync();
            DetachAllEntities(context);

            // Act
            var result = sharingService.GetConnectionRequests(target.UserId);

            // Assert
            Assert.IsTrue(result.Any());
        }

        [TestMethod]
        public async Task GetConnectionRequests_WithNoRequests_ShouldReturnEmptyList()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = sharingService.GetConnectionRequests(user.UserId);

            // Assert
            Assert.AreEqual(0, result.Count);
        }

        [TestMethod]
        public async Task GetConnectionRequests_WithIgnoredRequest_ShouldNotReturnIgnored()
        {
            // Arrange
            var requester = await CreateTestUser(context);
            var target = await CreateTestUser(context);
            var request = await CreateTestShareRequest(context, requester.UserId, target.UserId);
            request.Ignored = true;
            await context.SaveChangesAsync();
            DetachAllEntities(context);

            // Act
            var result = sharingService.GetConnectionRequests(target.UserId);

            // Assert
            Assert.AreEqual(0, result.Count);
        }

        [TestMethod]
        public async Task GetConnectionRequests_WithUsedRequest_ShouldNotReturnUsed()
        {
            // Arrange
            var requester = await CreateTestUser(context);
            var target = await CreateTestUser(context);
            var request = await CreateTestShareRequest(context, requester.UserId, target.UserId);
            request.Used = true;
            await context.SaveChangesAsync();
            DetachAllEntities(context);

            // Act
            var result = sharingService.GetConnectionRequests(target.UserId);

            // Assert
            Assert.AreEqual(0, result.Count);
        }

        #endregion

        #region GetSuggestions Tests

        [TestMethod]
        public async Task GetSuggestions_ForNewUser_ShouldReturnEmpty()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await sharingService.GetSuggestions(user.UserId);

            // Assert
            Assert.AreEqual(0, result.Count);
        }

        #endregion

        #region RemoveConnection Tests

        [TestMethod]
        public async Task RemoveConnection_ShouldRemoveConnection()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var reader = await CreateTestUser(context);
            var connection = await CreateTestConnection(context, owner.UserId, reader.UserId);
            DetachAllEntities(context);

            // Act
            sharingService.RemoveConnection(owner.UserId, reader.UserId);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var removed = await verifyContext.UserUsers
                    .FirstOrDefaultAsync(u => u.OwnerUserId == owner.UserId && u.ReaderUserId == reader.UserId);
                Assert.IsNull(removed);
            }
        }

        [TestMethod]
        public async Task RemoveConnection_WithNonExistentConnection_ShouldNotThrow()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var reader = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act - Should not throw
            sharingService.RemoveConnection(owner.UserId, reader.UserId);
        }

        #endregion

        #region IgnoreRequest Tests

        [TestMethod]
        public async Task IgnoreRequest_WithValidToken_ShouldMarkAsUsed()
        {
            // Arrange
            var requester = await CreateTestUser(context);
            var target = await CreateTestUser(context);
            var request = await CreateTestShareRequest(context, requester.UserId, target.UserId);
            DetachAllEntities(context);

            // Act
            await sharingService.IgnoreRequest(request.RequestKey.ToString(), target.UserId);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var updated = await verifyContext.ShareRequests.FindAsync(request.ShareRequestId);
                Assert.IsTrue(updated.Used);
            }
        }

        #endregion

        #region RequestConnection Tests

        [TestMethod]
        public async Task RequestConnection_WithValidData_ShouldCreateShareRequest()
        {
            // Arrange
            var requester = await CreateTestUser(context, name: "Requester");
            var model = new ConnectionRequestModel
            {
                Email = $"target_{Guid.NewGuid():N}@test.com",
                RequestorName = "Requester",
                ContactName = "Target"
            };
            DetachAllEntities(context);

            // Act
            var result = await sharingService.RequestConnection(requester.UserId, model);

            // Assert
            Assert.IsTrue(result.Success);
        }

        [TestMethod]
        public async Task RequestConnection_ToSelf_ShouldFail()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var model = new ConnectionRequestModel
            {
                Email = user.Email,
                RequestorName = user.Name,
                ContactName = user.Name
            };
            DetachAllEntities(context);

            // Act
            var result = await sharingService.RequestConnection(user.UserId, model);

            // Assert
            Assert.IsFalse(result.Success);
        }

        [TestMethod]
        public async Task RequestConnection_ToExistingConnection_ShouldReturnAlreadyConnected()
        {
            // Arrange
            var owner = await CreateTestUser(context, name: "Owner");
            var reader = await CreateTestUser(context, name: "Reader");
            await CreateTestConnection(context, owner.UserId, reader.UserId);
            var model = new ConnectionRequestModel
            {
                Email = reader.Email,
                RequestorName = "Owner",
                ContactName = "Reader"
            };
            DetachAllEntities(context);

            // Act
            var result = await sharingService.RequestConnection(owner.UserId, model);

            // Assert
            Assert.IsFalse(result.Success);
        }

        #endregion

        #region Authorization Tests

        [TestMethod]
        public async Task GetConnectionRequests_AsWrongUser_ShouldReturnEmpty()
        {
            // Arrange
            var requester = await CreateTestUser(context);
            var target = await CreateTestUser(context);
            var other = await CreateTestUser(context);
            await CreateTestShareRequest(context, requester.UserId, target.UserId);
            DetachAllEntities(context);

            // Act - Other user should not see target's requests
            var result = sharingService.GetConnectionRequests(other.UserId);

            // Assert
            Assert.AreEqual(0, result.Count);
        }

        #endregion
    }
}
```

---

### Phase 3: P2 Services - Groups, Notifications, Timelines ✅ COMPLETE

#### 3.1 GroupServiceTest.cs

**File:** `DomainTest/Repositories/GroupServiceTest.cs`

```csharp
using Domain.Entities;
using Domain.Exceptions;
using Domain.Repository;
using Microsoft.EntityFrameworkCore;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace DomainTest.Repositories
{
    [TestClass]
    [TestCategory("Integration")]
    [TestCategory("GroupService")]
    public class GroupServiceTest : BaseRepositoryTest
    {
        private GroupService groupService;

        [TestInitialize]
        public void Setup()
        {
            var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection")
                ?? "Server=localhost,1433; Database=Master; User Id=SA; Password=Dog1$Dobbie!; Encrypt=False;";
            Environment.SetEnvironmentVariable("DatabaseConnection", connectionString);

            InitializeWithTransaction();
            this.groupService = TestServiceFactory.CreateGroupService();
        }

        [TestCleanup]
        public void Cleanup()
        {
            groupService?.Dispose();
            CleanupWithTransaction();
        }

        #region AllGroups Tests

        [TestMethod]
        public async Task AllGroups_WithGroups_ShouldReturnGroupList()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var group = await CreateTestGroup(context, user.UserId, "Test Group");
            DetachAllEntities(context);

            // Act
            var result = await groupService.AllGroups(user.UserId);

            // Assert
            Assert.IsTrue(result.Any(g => g.Name == "Test Group"));
        }

        [TestMethod]
        public async Task AllGroups_WithNoGroups_ShouldReturnEmptyList()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await groupService.AllGroups(user.UserId);

            // Assert
            Assert.AreEqual(0, result.Count);
        }

        [TestMethod]
        public async Task AllGroups_ShouldNotReturnOtherUsersGroups()
        {
            // Arrange
            var user1 = await CreateTestUser(context);
            var user2 = await CreateTestUser(context);
            await CreateTestGroup(context, user1.UserId, "User1 Group");
            await CreateTestGroup(context, user2.UserId, "User2 Group");
            DetachAllEntities(context);

            // Act
            var result = await groupService.AllGroups(user1.UserId);

            // Assert
            Assert.IsTrue(result.All(g => g.Name != "User2 Group"));
        }

        #endregion

        #region Add (Create Group) Tests

        [TestMethod]
        public async Task Add_WithValidName_ShouldCreateGroup()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var groupId = groupService.Add("New Group", user.UserId);

            // Assert
            Assert.IsTrue(groupId > 0);

            using (var verifyContext = CreateVerificationContext())
            {
                var created = await verifyContext.UserNetworks.FindAsync(groupId);
                Assert.IsNotNull(created);
                Assert.AreEqual("New Group", created.Name);
            }
        }

        [TestMethod]
        public async Task Add_WithExistingName_ShouldReturnExistingId()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var existingGroup = await CreateTestGroup(context, user.UserId, "Existing Group");
            DetachAllEntities(context);

            // Act
            var groupId = groupService.Add("Existing Group", user.UserId);

            // Assert
            Assert.AreEqual(existingGroup.UserTagId, groupId);
        }

        [TestMethod]
        [ExpectedException(typeof(BadRequestException))]
        public void Add_WithNullName_ShouldThrowBadRequestException()
        {
            // Act
            groupService.Add(null, 1);
        }

        [TestMethod]
        [ExpectedException(typeof(BadRequestException))]
        public void Add_WithEmptyName_ShouldThrowBadRequestException()
        {
            // Act
            groupService.Add("", 1);
        }

        [TestMethod]
        [ExpectedException(typeof(BadRequestException))]
        public void Add_WithWhitespaceName_ShouldThrowBadRequestException()
        {
            // Act
            groupService.Add("   ", 1);
        }

        [TestMethod]
        [ExpectedException(typeof(BadRequestException))]
        public void Add_WithNameTooLong_ShouldThrowBadRequestException()
        {
            // Arrange - Name > 50 characters
            var longName = new string('a', 51);

            // Act
            groupService.Add(longName, 1);
        }

        [TestMethod]
        [ExpectedException(typeof(BadRequestException))]
        public async Task Add_WithEveryoneName_ShouldThrowBadRequestException()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act - "everyone" is reserved
            groupService.Add("everyone", user.UserId);
        }

        #endregion

        #region UpdateNetworkViewers Tests

        [TestMethod]
        public async Task UpdateNetworkViewers_ShouldAddViewers()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var member = await CreateTestUser(context);
            await CreateTestConnection(context, owner.UserId, member.UserId);
            var group = await CreateTestGroup(context, owner.UserId, "Family");
            DetachAllEntities(context);

            // Act
            var result = await groupService.UpdateNetworkViewers(owner.UserId, group.UserTagId, new List<int> { member.UserId });

            // Assert
            Assert.IsNotNull(result);

            using (var verifyContext = CreateVerificationContext())
            {
                var viewer = await verifyContext.NetworkViewers
                    .FirstOrDefaultAsync(v => v.UserTagId == group.UserTagId && v.ViewerUserId == member.UserId);
                Assert.IsNotNull(viewer);
            }
        }

        [TestMethod]
        public async Task UpdateNetworkViewers_WithEmptyList_ShouldRemoveAllViewers()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var member = await CreateTestUser(context);
            var group = await CreateTestGroup(context, owner.UserId, "Friends");
            await AddViewerToGroup(context, group.UserTagId, member.UserId);
            DetachAllEntities(context);

            // Act
            await groupService.UpdateNetworkViewers(owner.UserId, group.UserTagId, new List<int>());

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var viewers = await verifyContext.NetworkViewers
                    .Where(v => v.UserTagId == group.UserTagId)
                    .ToListAsync();
                Assert.AreEqual(0, viewers.Count);
            }
        }

        #endregion

        #region Rename Tests

        [TestMethod]
        public async Task Rename_WithValidName_ShouldUpdateName()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var group = await CreateTestGroup(context, user.UserId, "Old Name");
            DetachAllEntities(context);

            // Act
            var result = await groupService.Rename(user.UserId, (int)group.UserTagId, "New Name");

            // Assert
            Assert.AreEqual("New Name", result);

            using (var verifyContext = CreateVerificationContext())
            {
                var updated = await verifyContext.UserNetworks.FindAsync(group.UserTagId);
                Assert.AreEqual("New Name", updated.Name);
            }
        }

        #endregion

        #region Archive Tests

        [TestMethod]
        public async Task Archive_ShouldArchiveGroup()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var group = await CreateTestGroup(context, user.UserId, "To Archive");
            DetachAllEntities(context);

            // Act
            await groupService.Archive(group.UserTagId, user.UserId);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var archived = await verifyContext.UserNetworks.FindAsync(group.UserTagId);
                Assert.IsTrue(archived.Archived);
            }
        }

        #endregion

        #region Authorization Tests

        [TestMethod]
        public async Task AllGroups_ForDifferentUser_ShouldNotReturnOthersGroups()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var other = await CreateTestUser(context);
            await CreateTestGroup(context, owner.UserId, "Owner's Group");
            DetachAllEntities(context);

            // Act
            var result = await groupService.AllGroups(other.UserId);

            // Assert
            Assert.IsFalse(result.Any(g => g.Name == "Owner's Group"));
        }

        #endregion
    }
}
```

#### 3.2 NotificationServiceTest.cs

**File:** `DomainTest/Repositories/NotificationServiceTest.cs`

```csharp
using Domain.Entities;
using Domain.Repository;
using Microsoft.EntityFrameworkCore;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace DomainTest.Repositories
{
    [TestClass]
    [TestCategory("Integration")]
    [TestCategory("NotificationService")]
    public class NotificationServiceTest : BaseRepositoryTest
    {
        private NotificationService notificationService;

        [TestInitialize]
        public void Setup()
        {
            var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection")
                ?? "Server=localhost,1433; Database=Master; User Id=SA; Password=Dog1$Dobbie!; Encrypt=False;";
            Environment.SetEnvironmentVariable("DatabaseConnection", connectionString);

            InitializeWithTransaction();
            this.notificationService = TestServiceFactory.CreateNotificationService();
        }

        [TestCleanup]
        public void Cleanup()
        {
            notificationService?.Dispose();
            CleanupWithTransaction();
        }

        #region Notifications Tests

        [TestMethod]
        public async Task Notifications_WithNotifications_ShouldReturnModel()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var target = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, owner.UserId);
            await CreateTestNotification(context, target.UserId, drop.DropId, owner.UserId);
            DetachAllEntities(context);

            // Act
            var result = notificationService.Notifications(target.UserId);

            // Assert
            Assert.IsNotNull(result);
        }

        [TestMethod]
        public async Task Notifications_WithNoNotifications_ShouldReturnEmptyModel()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = notificationService.Notifications(user.UserId);

            // Assert
            Assert.IsNotNull(result);
        }

        #endregion

        #region ViewNotification Tests

        [TestMethod]
        public async Task ViewNotification_ShouldMarkAsViewed()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var target = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, owner.UserId);
            await CreateTestUserDrop(context, target.UserId, drop.DropId, viewed: false);
            DetachAllEntities(context);

            // Act
            notificationService.ViewNotification(target.UserId, drop.DropId);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var viewed = await verifyContext.UserDrops
                    .FirstOrDefaultAsync(ud => ud.DropId == drop.DropId && ud.UserId == target.UserId);
                Assert.IsNotNull(viewed?.ViewedDate);
            }
        }

        [TestMethod]
        public async Task ViewNotification_WithNoUserDrop_ShouldNotThrow()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var target = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, owner.UserId);
            DetachAllEntities(context);

            // Act - Should not throw even without UserDrop record
            notificationService.ViewNotification(target.UserId, drop.DropId);
        }

        #endregion

        #region RemoveAllNotifications Tests

        [TestMethod]
        public async Task RemoveAllNotifications_ShouldRemoveAll()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var target = await CreateTestUser(context);
            var drop1 = await CreateTestDrop(context, owner.UserId);
            var drop2 = await CreateTestDrop(context, owner.UserId);
            await CreateTestNotification(context, target.UserId, drop1.DropId, owner.UserId);
            await CreateTestNotification(context, target.UserId, drop2.DropId, owner.UserId);
            DetachAllEntities(context);

            // Act
            notificationService.RemoveAllNotifications(target.UserId);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var remaining = await verifyContext.SharedDropNotifications
                    .Where(n => n.TargetUserId == target.UserId)
                    .ToListAsync();
                Assert.AreEqual(0, remaining.Count);
            }
        }

        #endregion

        #region Authorization Tests

        [TestMethod]
        public async Task Notifications_OnlyReturnsOwnNotifications()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var target1 = await CreateTestUser(context);
            var target2 = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, owner.UserId);
            await CreateTestNotification(context, target1.UserId, drop.DropId, owner.UserId);
            DetachAllEntities(context);

            // Act
            var result = notificationService.Notifications(target2.UserId);

            // Assert - target2 should not see target1's notifications
            Assert.IsNotNull(result);
        }

        #endregion
    }
}
```

#### 3.3 TimelineServiceTest.cs

**File:** `DomainTest/Repositories/TimelineServiceTest.cs`

```csharp
using Domain.Entities;
using Domain.Exceptions;
using Domain.Repository;
using Microsoft.EntityFrameworkCore;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Linq;
using System.Threading.Tasks;

namespace DomainTest.Repositories
{
    [TestClass]
    [TestCategory("Integration")]
    [TestCategory("TimelineService")]
    public class TimelineServiceTest : BaseRepositoryTest
    {
        private TimelineService timelineService;

        [TestInitialize]
        public void Setup()
        {
            var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection")
                ?? "Server=localhost,1433; Database=Master; User Id=SA; Password=Dog1$Dobbie!; Encrypt=False;";
            Environment.SetEnvironmentVariable("DatabaseConnection", connectionString);

            InitializeWithTransaction();
            this.timelineService = TestServiceFactory.CreateTimelineService();
        }

        [TestCleanup]
        public void Cleanup()
        {
            timelineService?.Dispose();
            CleanupWithTransaction();
        }

        #region GetAllTimelines Tests

        [TestMethod]
        public async Task GetAllTimelines_WithTimelines_ShouldReturnList()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var timeline = await CreateTestTimeline(context, user.UserId, "My Timeline");
            DetachAllEntities(context);

            // Act
            var result = await timelineService.GetAllTimelines(user.UserId);

            // Assert
            Assert.IsTrue(result.Any(t => t.Name == "My Timeline"));
        }

        [TestMethod]
        public async Task GetAllTimelines_WithNoTimelines_ShouldReturnEmptyList()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await timelineService.GetAllTimelines(user.UserId);

            // Assert
            Assert.AreEqual(0, result.Count);
        }

        #endregion

        #region AddTimeline Tests

        [TestMethod]
        public async Task AddTimeline_WithValidData_ShouldCreateTimeline()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await timelineService.AddTimeline(user.UserId, "New Timeline", "Description");

            // Assert
            Assert.IsNotNull(result);
            Assert.AreEqual("New Timeline", result.Name);

            using (var verifyContext = CreateVerificationContext())
            {
                var created = await verifyContext.Timelines.FindAsync(result.Id);
                Assert.IsNotNull(created);
            }
        }

        [TestMethod]
        public async Task AddTimeline_WithNullDescription_ShouldCreateTimeline()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await timelineService.AddTimeline(user.UserId, "New Timeline", null);

            // Assert
            Assert.IsNotNull(result);
        }

        #endregion

        #region AddDropToTimeline Tests

        [TestMethod]
        public async Task AddDropToTimeline_ShouldAssociateDrop()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var timeline = await CreateTestTimeline(context, user.UserId, "Test Timeline");
            var drop = await CreateTestDrop(context, user.UserId);
            DetachAllEntities(context);

            // Act
            await timelineService.AddDropToTimeline(user.UserId, drop.DropId, timeline.TimeLineId);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var timelineDrop = await verifyContext.TimelineDrops
                    .FirstOrDefaultAsync(td => td.TimeLineId == timeline.TimeLineId && td.DropId == drop.DropId);
                Assert.IsNotNull(timelineDrop);
            }
        }

        #endregion

        #region RemoveDropFromTimeline Tests

        [TestMethod]
        public async Task RemoveDropFromTimeline_ShouldRemoveAssociation()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var timeline = await CreateTestTimeline(context, user.UserId, "Test Timeline");
            var drop = await CreateTestDrop(context, user.UserId);
            await AddDropToTimeline(context, timeline.TimeLineId, drop.DropId);
            DetachAllEntities(context);

            // Act
            await timelineService.RemoveDropFromTimeline(user.UserId, drop.DropId, timeline.TimeLineId);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var timelineDrop = await verifyContext.TimelineDrops
                    .FirstOrDefaultAsync(td => td.TimeLineId == timeline.TimeLineId && td.DropId == drop.DropId);
                Assert.IsNull(timelineDrop);
            }
        }

        #endregion

        #region SoftDeleteTimeline Tests

        [TestMethod]
        public async Task SoftDeleteTimeline_ShouldMarkAsDeleted()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var timeline = await CreateTestTimeline(context, user.UserId, "To Delete");
            DetachAllEntities(context);

            // Act
            var result = await timelineService.SoftDeleteTimeline(user.UserId, timeline.TimeLineId);

            // Assert
            Assert.IsNotNull(result);

            using (var verifyContext = CreateVerificationContext())
            {
                var deleted = await verifyContext.Timelines.FindAsync(timeline.TimeLineId);
                Assert.IsTrue(deleted.Deleted);
            }
        }

        #endregion

        #region Authorization Tests

        [TestMethod]
        public async Task GetAllTimelines_OnlyReturnsOwnTimelines()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var other = await CreateTestUser(context);
            await CreateTestTimeline(context, owner.UserId, "Owner's Timeline");
            DetachAllEntities(context);

            // Act
            var result = await timelineService.GetAllTimelines(other.UserId);

            // Assert
            Assert.IsFalse(result.Any(t => t.Name == "Owner's Timeline"));
        }

        #endregion
    }
}
```

---

### Phase 4: P3 Services - Albums, Prompts, Plans ✅ COMPLETE

#### 4.1 AlbumServiceTest.cs

**File:** `DomainTest/Repositories/AlbumServiceTest.cs`

```csharp
using Domain.Entities;
using Domain.Exceptions;
using Domain.Repository;
using Microsoft.EntityFrameworkCore;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Linq;
using System.Threading.Tasks;

namespace DomainTest.Repositories
{
    [TestClass]
    [TestCategory("Integration")]
    [TestCategory("AlbumService")]
    public class AlbumServiceTest : BaseRepositoryTest
    {
        private AlbumService albumService;

        [TestInitialize]
        public void Setup()
        {
            var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection")
                ?? "Server=localhost,1433; Database=Master; User Id=SA; Password=Dog1$Dobbie!; Encrypt=False;";
            Environment.SetEnvironmentVariable("DatabaseConnection", connectionString);

            InitializeWithTransaction();
            this.albumService = TestServiceFactory.CreateAlbumService();
        }

        [TestCleanup]
        public void Cleanup()
        {
            albumService?.Dispose();
            CleanupWithTransaction();
        }

        #region GetActive Tests

        [TestMethod]
        public async Task GetActive_WithActiveAlbums_ShouldReturnActiveAlbums()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var album = await CreateTestAlbum(context, user.UserId, "My Album");
            DetachAllEntities(context);

            // Act
            var result = await albumService.GetActive(user.UserId);

            // Assert
            Assert.IsTrue(result.Any(a => a.Name == "My Album"));
        }

        [TestMethod]
        public async Task GetActive_WithArchivedAlbum_ShouldNotReturnArchived()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var album = await CreateTestAlbum(context, user.UserId, "Archived Album");
            album.Archived = true;
            await context.SaveChangesAsync();
            DetachAllEntities(context);

            // Act
            var result = await albumService.GetActive(user.UserId);

            // Assert
            Assert.IsFalse(result.Any(a => a.Name == "Archived Album"));
        }

        #endregion

        #region Create Tests

        [TestMethod]
        public async Task Create_WithValidName_ShouldCreateAlbum()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await albumService.Create(user.UserId, "New Album");

            // Assert
            Assert.IsNotNull(result);
            Assert.AreEqual("New Album", result.Name);

            using (var verifyContext = CreateVerificationContext())
            {
                var created = await verifyContext.Albums.FindAsync(result.AlbumId);
                Assert.IsNotNull(created);
            }
        }

        #endregion

        #region AddToMoment Tests

        [TestMethod]
        public async Task AddToMoment_ShouldAssociateDrop()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var album = await CreateTestAlbum(context, user.UserId, "Test Album");
            var drop = await CreateTestDrop(context, user.UserId);
            DetachAllEntities(context);

            // Act
            await albumService.AddToMoment(user.UserId, album.AlbumId, drop.DropId);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var albumDrop = await verifyContext.AlbumDrops
                    .FirstOrDefaultAsync(ad => ad.AlbumId == album.AlbumId && ad.DropId == drop.DropId);
                Assert.IsNotNull(albumDrop);
            }
        }

        #endregion

        #region RemoveToMoment Tests

        [TestMethod]
        public async Task RemoveToMoment_ShouldDisassociateDrop()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var album = await CreateTestAlbum(context, user.UserId, "Test Album");
            var drop = await CreateTestDrop(context, user.UserId);
            await AddDropToAlbum(context, album.AlbumId, drop.DropId);
            DetachAllEntities(context);

            // Act
            await albumService.RemoveToMoment(user.UserId, album.AlbumId, drop.DropId);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var removed = await verifyContext.AlbumDrops
                    .FirstOrDefaultAsync(ad => ad.AlbumId == album.AlbumId && ad.DropId == drop.DropId);
                Assert.IsNull(removed);
            }
        }

        #endregion

        #region Delete Tests

        [TestMethod]
        public async Task Delete_ShouldRemoveAlbum()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var album = await CreateTestAlbum(context, user.UserId, "To Delete");
            DetachAllEntities(context);

            // Act
            await albumService.Delete(user.UserId, album.AlbumId);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var deleted = await verifyContext.Albums.FindAsync(album.AlbumId);
                Assert.IsNull(deleted);
            }
        }

        #endregion

        #region Authorization Tests

        [TestMethod]
        public async Task GetActive_OnlyReturnsOwnAlbums()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var other = await CreateTestUser(context);
            await CreateTestAlbum(context, owner.UserId, "Owner's Album");
            DetachAllEntities(context);

            // Act
            var result = await albumService.GetActive(other.UserId);

            // Assert
            Assert.IsFalse(result.Any(a => a.Name == "Owner's Album"));
        }

        #endregion
    }
}
```

#### 4.2 PromptServiceTest.cs

**File:** `DomainTest/Repositories/PromptServiceTest.cs`

```csharp
using Domain.Entities;
using Domain.Repository;
using Microsoft.EntityFrameworkCore;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Linq;
using System.Threading.Tasks;

namespace DomainTest.Repositories
{
    [TestClass]
    [TestCategory("Integration")]
    [TestCategory("PromptService")]
    public class PromptServiceTest : BaseRepositoryTest
    {
        private PromptService promptService;

        [TestInitialize]
        public void Setup()
        {
            var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection")
                ?? "Server=localhost,1433; Database=Master; User Id=SA; Password=Dog1$Dobbie!; Encrypt=False;";
            Environment.SetEnvironmentVariable("DatabaseConnection", connectionString);

            InitializeWithTransaction();
            this.promptService = TestServiceFactory.CreatePromptService();
        }

        [TestCleanup]
        public void Cleanup()
        {
            promptService?.Dispose();
            CleanupWithTransaction();
        }

        #region GetActivePrompts Tests

        [TestMethod]
        public async Task GetActivePrompts_ShouldReturnActivePrompts()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var prompt = await CreateTestPrompt(context, "What is your favorite memory?", active: true);
            DetachAllEntities(context);

            // Act
            var result = await promptService.GetActivePrompts(user.UserId);

            // Assert
            Assert.IsTrue(result.Any(p => p.Question.Contains("favorite memory")));
        }

        [TestMethod]
        public async Task GetActivePrompts_ShouldNotReturnInactivePrompts()
        {
            // Arrange
            var user = await CreateTestUser(context);
            await CreateTestPrompt(context, "Inactive prompt", active: false);
            DetachAllEntities(context);

            // Act
            var result = await promptService.GetActivePrompts(user.UserId);

            // Assert
            Assert.IsFalse(result.Any(p => p.Question == "Inactive prompt"));
        }

        #endregion

        #region CreatePrompt Tests

        [TestMethod]
        public async Task CreatePrompt_WithValidQuestion_ShouldCreatePrompt()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await promptService.CreatePrompt(user.UserId, "What makes you happy?");

            // Assert
            Assert.IsNotNull(result);
            Assert.AreEqual("What makes you happy?", result.Question);
        }

        #endregion

        #region GetPrompt Tests

        [TestMethod]
        public async Task GetPrompt_WithValidId_ShouldReturnPrompt()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var prompt = await CreateTestPrompt(context, "Test question?");
            DetachAllEntities(context);

            // Act
            var result = await promptService.GetPrompt(user.UserId, prompt.PromptId);

            // Assert
            Assert.IsNotNull(result);
            Assert.AreEqual("Test question?", result.Question);
        }

        #endregion

        #region DismissPrompt Tests

        [TestMethod]
        public async Task DismissPrompt_ShouldMarkAsDismissed()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var prompt = await CreateTestPrompt(context);
            await CreateTestUserPrompt(context, user.UserId, prompt.PromptId);
            DetachAllEntities(context);

            // Act
            await promptService.DismissPrompt(user.UserId, prompt.PromptId);

            // Assert - Verify dismissed (implementation varies)
        }

        #endregion
    }
}
```

#### 4.3 PlanServiceTest.cs

**File:** `DomainTest/Repositories/PlanServiceTest.cs`

```csharp
using Domain.Entities;
using Domain.Models;
using Domain.Repository;
using Microsoft.EntityFrameworkCore;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Threading.Tasks;

namespace DomainTest.Repositories
{
    [TestClass]
    [TestCategory("Integration")]
    [TestCategory("PlanService")]
    public class PlanServiceTest : BaseRepositoryTest
    {
        private PlanService planService;

        [TestInitialize]
        public void Setup()
        {
            var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection")
                ?? "Server=localhost,1433; Database=Master; User Id=SA; Password=Dog1$Dobbie!; Encrypt=False;";
            Environment.SetEnvironmentVariable("DatabaseConnection", connectionString);

            InitializeWithTransaction();
            this.planService = TestServiceFactory.CreatePlanService();
        }

        [TestCleanup]
        public void Cleanup()
        {
            planService?.Dispose();
            CleanupWithTransaction();
        }

        #region GetPremiumPlanByUserId Tests

        [TestMethod]
        public async Task GetPremiumPlanByUserId_WithNoPlan_ShouldReturnNull()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await planService.GetPremiumPlanByUserId(user.UserId);

            // Assert
            Assert.IsNull(result);
        }

        [TestMethod]
        public async Task GetPremiumPlanByUserId_WithPlan_ShouldReturnPlan()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var plan = new PremiumPlan
            {
                UserId = user.UserId,
                PlanType = PlanTypes.Monthly,
                Created = DateTime.UtcNow,
                ExpirationDate = DateTime.UtcNow.AddDays(30)
            };
            context.PremiumPlans.Add(plan);
            await context.SaveChangesAsync();
            DetachAllEntities(context);

            // Act
            var result = await planService.GetPremiumPlanByUserId(user.UserId);

            // Assert
            Assert.IsNotNull(result);
        }

        #endregion

        #region GetSharedPlans Tests

        [TestMethod]
        public async Task GetSharedPlans_WithNoSharedPlans_ShouldReturnEmptyList()
        {
            // Arrange
            var user = await CreateTestUser(context);
            DetachAllEntities(context);

            // Act
            var result = await planService.GetSharedPlans(user.UserId);

            // Assert
            Assert.AreEqual(0, result.Count);
        }

        #endregion

        #region Authorization Tests

        [TestMethod]
        public async Task GetPremiumPlanByUserId_OnlyReturnsOwnPlan()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var other = await CreateTestUser(context);
            var plan = new PremiumPlan
            {
                UserId = owner.UserId,
                PlanType = PlanTypes.Monthly,
                Created = DateTime.UtcNow
            };
            context.PremiumPlans.Add(plan);
            await context.SaveChangesAsync();
            DetachAllEntities(context);

            // Act
            var result = await planService.GetPremiumPlanByUserId(other.UserId);

            // Assert
            Assert.IsNull(result);
        }

        #endregion
    }
}
```

---

### Phase 5: Expand MemoryShareLinkServiceTest ✅ COMPLETE

**File:** `DomainTest/Repositories/MemoryShareLinkServiceTest.cs`

```csharp
using Domain.Entities;
using Domain.Exceptions;
using Domain.Repository;
using Microsoft.EntityFrameworkCore;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Threading.Tasks;

namespace DomainTest.Repositories
{
    [TestClass]
    [TestCategory("Integration")]
    [TestCategory("MemoryShareLinkService")]
    public class MemoryShareLinkServiceTest : BaseRepositoryTest
    {
        private MemoryShareLinkService shareLinkService;

        [TestInitialize]
        public void Setup()
        {
            var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection")
                ?? "Server=localhost,1433; Database=Master; User Id=SA; Password=Dog1$Dobbie!; Encrypt=False;";
            Environment.SetEnvironmentVariable("DatabaseConnection", connectionString);

            InitializeWithTransaction();
            this.shareLinkService = TestServiceFactory.CreateMemoryShareLinkService();
        }

        [TestCleanup]
        public void Cleanup()
        {
            shareLinkService?.Dispose();
            CleanupWithTransaction();
        }

        #region CreateLink Tests

        [TestMethod]
        public async Task CreateLink_ValidDrop_ReturnsToken()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, user.UserId);
            DetachAllEntities(context);

            // Act
            var result = await shareLinkService.CreateLink(user.UserId, drop.DropId, null);

            // Assert
            Assert.IsNotNull(result);
            Assert.IsFalse(string.IsNullOrEmpty(result.Token));
        }

        [TestMethod]
        public async Task CreateLink_WithExpiration_ShouldSetExpirationDate()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, user.UserId);
            var expirationDays = 7;
            DetachAllEntities(context);

            // Act
            var result = await shareLinkService.CreateLink(user.UserId, drop.DropId, expirationDays);

            // Assert
            Assert.IsNotNull(result);

            using (var verifyContext = CreateVerificationContext())
            {
                var link = await verifyContext.MemoryShareLinks
                    .FirstOrDefaultAsync(l => l.Token == result.Token);
                Assert.IsNotNull(link.ExpiresAt);
            }
        }

        [TestMethod]
        public async Task CreateLink_WithNullExpiration_ShouldCreatePermanentLink()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, user.UserId);
            DetachAllEntities(context);

            // Act
            var result = await shareLinkService.CreateLink(user.UserId, drop.DropId, null);

            // Assert
            using (var verifyContext = CreateVerificationContext())
            {
                var link = await verifyContext.MemoryShareLinks
                    .FirstOrDefaultAsync(l => l.Token == result.Token);
                Assert.IsNull(link.ExpiresAt);
            }
        }

        [TestMethod]
        [ExpectedException(typeof(NotAuthorizedException))]
        public async Task CreateLink_ForOtherUsersDrop_ShouldThrow()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var other = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, owner.UserId);
            DetachAllEntities(context);

            // Act
            await shareLinkService.CreateLink(other.UserId, drop.DropId, null);
        }

        #endregion

        #region GetByToken Tests

        [TestMethod]
        public async Task GetByToken_ValidToken_ReturnsDrop()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, user.UserId);
            DetachAllEntities(context);
            var linkResult = await shareLinkService.CreateLink(user.UserId, drop.DropId, null);

            // Act
            var result = await shareLinkService.GetByToken(linkResult.Token);

            // Assert
            Assert.IsNotNull(result);
            Assert.AreEqual(drop.DropId, result.DropId);
        }

        [TestMethod]
        public async Task GetByToken_ExpiredToken_ReturnsNull()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, user.UserId);

            var link = new MemoryShareLink
            {
                DropId = drop.DropId,
                UserId = user.UserId,
                Token = Guid.NewGuid().ToString(),
                CreatedAt = DateTime.UtcNow.AddDays(-10),
                ExpiresAt = DateTime.UtcNow.AddDays(-1), // Expired
                IsActive = true
            };
            context.MemoryShareLinks.Add(link);
            await context.SaveChangesAsync();
            DetachAllEntities(context);

            // Act
            var result = await shareLinkService.GetByToken(link.Token);

            // Assert
            Assert.IsNull(result);
        }

        [TestMethod]
        public async Task GetByToken_InvalidToken_ReturnsNull()
        {
            // Act
            var result = await shareLinkService.GetByToken("invalid-token-that-does-not-exist");

            // Assert
            Assert.IsNull(result);
        }

        [TestMethod]
        public async Task GetByToken_DeactivatedLink_ReturnsNull()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, user.UserId);

            var link = new MemoryShareLink
            {
                DropId = drop.DropId,
                UserId = user.UserId,
                Token = Guid.NewGuid().ToString(),
                CreatedAt = DateTime.UtcNow,
                IsActive = false // Deactivated
            };
            context.MemoryShareLinks.Add(link);
            await context.SaveChangesAsync();
            DetachAllEntities(context);

            // Act
            var result = await shareLinkService.GetByToken(link.Token);

            // Assert
            Assert.IsNull(result);
        }

        #endregion

        #region RevokeLink Tests

        [TestMethod]
        public async Task RevokeLink_ValidToken_ShouldDeactivateLink()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, user.UserId);
            DetachAllEntities(context);
            var linkResult = await shareLinkService.CreateLink(user.UserId, drop.DropId, null);

            // Act
            await shareLinkService.RevokeLink(user.UserId, linkResult.Token);

            // Assert
            var fetchedDrop = await shareLinkService.GetByToken(linkResult.Token);
            Assert.IsNull(fetchedDrop);
        }

        [TestMethod]
        [ExpectedException(typeof(NotAuthorizedException))]
        public async Task RevokeLink_ByNonOwner_ShouldThrow()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var other = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, owner.UserId);
            DetachAllEntities(context);
            var linkResult = await shareLinkService.CreateLink(owner.UserId, drop.DropId, null);

            // Act
            await shareLinkService.RevokeLink(other.UserId, linkResult.Token);
        }

        #endregion

        #region GetLinksForDrop Tests

        [TestMethod]
        public async Task GetLinksForDrop_WithLinks_ShouldReturnList()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, user.UserId);
            DetachAllEntities(context);
            await shareLinkService.CreateLink(user.UserId, drop.DropId, null);
            await shareLinkService.CreateLink(user.UserId, drop.DropId, 30);

            // Act
            var result = await shareLinkService.GetLinksForDrop(user.UserId, drop.DropId);

            // Assert
            Assert.AreEqual(2, result.Count);
        }

        [TestMethod]
        public async Task GetLinksForDrop_WithNoLinks_ShouldReturnEmptyList()
        {
            // Arrange
            var user = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, user.UserId);
            DetachAllEntities(context);

            // Act
            var result = await shareLinkService.GetLinksForDrop(user.UserId, drop.DropId);

            // Assert
            Assert.AreEqual(0, result.Count);
        }

        [TestMethod]
        [ExpectedException(typeof(NotAuthorizedException))]
        public async Task GetLinksForDrop_ByNonOwner_ShouldThrow()
        {
            // Arrange
            var owner = await CreateTestUser(context);
            var other = await CreateTestUser(context);
            var drop = await CreateTestDrop(context, owner.UserId);
            DetachAllEntities(context);

            // Act
            await shareLinkService.GetLinksForDrop(other.UserId, drop.DropId);
        }

        #endregion
    }
}
```

---

## Testing Guidelines & Running Tests

Testing conventions (naming, AAA pattern, context isolation, categories, exception testing) and all run commands are documented in **`docs/TESTING_BEST_PRACTICES.md`**.

Primary run command:
```bash
cd cimplur-core/Memento && dotnet test DomainTest/DomainTest.csproj
```

---

## Expected Coverage After Implementation

| Service | Before | After Phase |
|---------|--------|-------------|
| DropsService | ~70% | ~70% |
| PermissionService | ~60% | ~60% |
| UserService | 0% | ~50% (Phase 2) |
| SharingService | 0% | ~40% (Phase 2) |
| GroupService | 0% | ~50% (Phase 3) |
| NotificationService | 0% | ~40% (Phase 3) |
| TimelineService | 0% | ~40% (Phase 3) |
| AlbumService | 0% | ~50% (Phase 4) |
| PromptService | 0% | ~30% (Phase 4) |
| PlanService | 0% | ~40% (Phase 4) |
| MemoryShareLinkService | ~10% | ~60% (Phase 5) |

**Overall Expected Coverage:** ~35-40% (up from ~5%)

---

## Future Improvements (Out of Scope)

1. **Dependency Injection for DbContext** - Would enable unit testing with mocks
2. **Controller Integration Tests** - Test full HTTP request/response cycle
3. **Separate Test Database** - Avoid sharing with development data
4. **CI/CD Integration** - Run tests on every commit
5. **Mocking External Services** - AWS, Stripe, Postmark

---

## Implementation Order

1. **Phase 1:** Enhance test infrastructure (BaseRepositoryTest, TestServiceFactory)
2. **Phase 2:** P1 services (UserService, SharingService) - Highest business value
3. **Phase 3:** P2 services (GroupService, NotificationService, TimelineService)
4. **Phase 4:** P3 services (AlbumService, PromptService, PlanService)
5. **Phase 5:** Expand MemoryShareLinkServiceTest

Each phase should be completed and verified before moving to the next.
