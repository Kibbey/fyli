# Technical Design Document: Question Requests — Testing

**PRD Reference:** [PRD_QUESTION_REQUESTS.md](/docs/prd/PRD_QUESTION_REQUESTS.md)
**Related TDDs:**
- [question-requests-backend.md](./question-requests-backend.md) — C#/.NET backend implementation
- [question-requests-frontend.md](./question-requests-frontend.md) — Vue 3 frontend implementation

---

## Overview

This document defines the comprehensive testing plan for the Question Requests feature, covering backend unit tests, frontend component tests, and integration tests.

---

## Test File Structure

```
cimplur-core/Memento/DomainTest/Repositories/
├── BaseRepositoryTest.cs            # EXISTING - Base class with transaction isolation
├── QuestionServiceTest.cs           # QuestionService unit tests (NEW)
├── QuestionReminderJobTest.cs       # Reminder job tests (NEW)
├── PermissionServiceTest.cs         # Add UserDrops access test (UPDATE)
├── DropsServiceTest.cs              # Add GetDropsByIds and AddQuestionContext tests (UPDATE)
├── QuestionTestFixtures.cs          # Shared test data factories (NEW)
├── TestServiceFactory.cs            # EXISTING - Add CreateQuestionService (UPDATE)

fyli-fe-v2/src/
├── components/question/
│   └── AnswerForm.test.ts
├── views/question/
│   ├── QuestionSetListView.test.ts
│   ├── QuestionSetEditView.test.ts
│   ├── QuestionSendView.test.ts
│   ├── QuestionAnswerView.test.ts
│   ├── QuestionDashboardView.test.ts
│   └── QuestionResponsesView.test.ts
├── services/
│   └── questionApi.test.ts
└── utils/
    └── errorMessage.test.ts        # Tests for existing error utility
```

---

## Test Infrastructure

### BaseRepositoryTest Pattern

All backend repository tests extend `BaseRepositoryTest` which provides:

- **Transaction-based isolation**: Each test runs in a transaction that's rolled back on cleanup
- **Shared test helpers**: `CreateTestUser`, `CreateTestDrop`, `CreateTestComment`, etc.
- **Context management**: `context` field with `InitializeWithTransaction()` and `CleanupWithTransaction()`

```csharp
// Example test class structure
[TestClass]
public class QuestionServiceTest : BaseRepositoryTest
{
    private QuestionService questionService;

    [TestInitialize]
    public void Setup()
    {
        InitializeWithTransaction();  // Creates context, starts transaction
        questionService = TestServiceFactory.CreateQuestionService();
        questionService.Context = context;
    }

    [TestCleanup]
    public void Cleanup()
    {
        CleanupWithTransaction();  // Rolls back transaction, disposes context
    }

    // Tests use context and BaseRepositoryTest helpers
}
```

### TestServiceFactory Updates

Add to `cimplur-core/Memento/DomainTest/Repositories/TestServiceFactory.cs`:

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

> **Note:** Add `using Microsoft.Extensions.Logging.Abstractions;` if not already present.

---

## Backend Unit Tests

### QuestionServiceTest.cs (38 tests)

#### Question Set CRUD (10 tests)

| Test | Description |
|------|-------------|
| `CreateQuestionSet_Valid_ReturnsSetWithQuestions` | Creates set with 1-5 questions, verifies all fields |
| `CreateQuestionSet_TooManyQuestions_ThrowsBadRequest` | Rejects >5 questions with clear error message |
| `CreateQuestionSet_EmptyName_ThrowsBadRequest` | Validates name is required |
| `CreateQuestionSet_NameTooLong_ThrowsBadRequest` | Validates name <= 200 characters |
| `CreateQuestionSet_EmptyQuestions_ThrowsBadRequest` | Validates at least one non-empty question |
| `CreateQuestionSet_QuestionTooLong_ThrowsBadRequest` | Validates each question <= 500 characters |
| `UpdateQuestionSet_NotOwner_ThrowsNotFoundException` | Different user ID returns 404 (not 403 to avoid leaking existence) |
| `UpdateQuestionSet_DeleteQuestionWithResponses_ThrowsBadRequest` | Cannot delete question that has responses |
| `UpdateQuestionSet_AddNewQuestions_Success` | Can add new questions while preserving existing |
| `DeleteQuestionSet_SetsArchivedTrue` | Soft delete sets Archived = true, preserves data |

```csharp
[TestClass]
public class QuestionServiceTest : BaseRepositoryTest
{
    private QuestionService questionService;

    [TestInitialize]
    public void Setup()
    {
        // Initialize context with transaction for automatic rollback
        InitializeWithTransaction();

        // Create service with test context
        questionService = TestServiceFactory.CreateQuestionService();
        questionService.Context = context;
    }

    [TestCleanup]
    public void Cleanup()
    {
        // Rollback transaction to clean up test data
        CleanupWithTransaction();
    }

    [TestMethod]
    public async Task CreateQuestionSet_Valid_ReturnsSetWithQuestions()
    {
        // Arrange - use BaseRepositoryTest helper
        var user = await CreateTestUser(context);
        var questions = new List<string> { "Question 1?", "Question 2?" };

        // Act
        var result = await questionService.CreateQuestionSet(user.UserId, "Test Set", questions);

        // Assert
        Assert.IsNotNull(result);
        Assert.AreEqual("Test Set", result.Name);
        Assert.AreEqual(2, result.Questions.Count);
        Assert.AreEqual("Question 1?", result.Questions[0].Text);
        Assert.AreEqual(0, result.Questions[0].SortOrder);
    }

    [TestMethod]
    [ExpectedException(typeof(BadRequestException))]
    public async Task CreateQuestionSet_TooManyQuestions_ThrowsBadRequest()
    {
        var user = await CreateTestUser(context);
        var questions = new List<string> { "Q1?", "Q2?", "Q3?", "Q4?", "Q5?", "Q6?" };

        await questionService.CreateQuestionSet(user.UserId, "Test", questions);
    }

    [TestMethod]
    [ExpectedException(typeof(BadRequestException))]
    public async Task CreateQuestionSet_EmptyName_ThrowsBadRequest()
    {
        var user = await CreateTestUser(context);
        await questionService.CreateQuestionSet(user.UserId, "", new List<string> { "Q?" });
    }

    // ... additional tests
}
```

#### Question Request Creation (6 tests)

| Test | Description |
|------|-------------|
| `CreateQuestionRequest_GeneratesUniqueTokens` | Each recipient gets distinct GUID token |
| `CreateQuestionRequest_NoRecipients_ThrowsBadRequest` | Validates at least one recipient required |
| `CreateQuestionRequest_EmptyRecipientsOnly_ThrowsBadRequest` | Recipients with only whitespace are filtered out |
| `CreateQuestionRequest_QuestionSetNotOwned_ThrowsNotFoundException` | Can't send from another user's question set |
| `CreateQuestionRequest_EmptyQuestionSet_ThrowsBadRequest` | Question set must have at least one question |
| `CreateQuestionRequest_SendsEmailToRecipientsWithEmail` | Email service called for each recipient with email |

#### Public Answer Flow (10 tests)

| Test | Description |
|------|-------------|
| `GetQuestionRequestByToken_ValidToken_ReturnsView` | Returns all questions with answered status |
| `GetQuestionRequestByToken_InactiveLink_ThrowsNotFoundException` | Deactivated tokens fail with 404 |
| `GetQuestionRequestByToken_InvalidToken_ThrowsNotFoundException` | Non-existent tokens fail with 404 |
| `SubmitAnswer_ValidToken_CreatesDropAndResponse` | Creates Drop, ContentDrop, and QuestionResponse |
| `SubmitAnswer_EmptyContent_ThrowsBadRequest` | Validates content is required |
| `SubmitAnswer_ContentTooLong_ThrowsBadRequest` | Validates content <= 4000 characters |
| `SubmitAnswer_AlreadyAnswered_ThrowsBadRequest` | Returns clear error if question already answered |
| `SubmitAnswer_QuestionNotInSet_ThrowsNotFoundException` | Wrong questionId for this token fails |
| `SubmitAnswer_SendsNotificationEmail` | Asker receives QuestionAnswerNotification email |
| `SubmitAnswer_AnonymousUser_DropOwnedByCreator` | When no respondentUserId, drop.UserId = creatorUserId |

#### Answer Update (4 tests)

| Test | Description |
|------|-------------|
| `UpdateAnswer_WithinEditWindow_Success` | Anonymous users can edit within 7 days |
| `UpdateAnswer_AnonymousAfter7Days_ThrowsBadRequest` | Anonymous users blocked after 7 days |
| `UpdateAnswer_RegisteredUser_NoTimeLimit` | Registered users can edit anytime |
| `UpdateAnswer_MediaValidation_InvalidIds_ThrowsBadRequest` | Image/movie IDs must belong to the drop |

#### Registration & Linking (6 tests)

| Test | Description |
|------|-------------|
| `RegisterAndLinkAnswers_NewUser_CreatesAccountAndTransfersOwnership` | New user created, all drops transferred |
| `RegisterAndLinkAnswers_ExistingUser_LinksWithoutCreating` | Finds existing user by email, links answers |
| `RegisterAndLinkAnswers_CreatesConnection` | EnsureConnectionAsync called between creator and respondent |
| `RegisterAndLinkAnswers_CreatorRetainsAccess` | Creator gets UserDrop record for each transferred drop |
| `RegisterAndLinkAnswers_EmptyEmail_ThrowsBadRequest` | Email is required |
| `RegisterAndLinkAnswers_TermsNotAccepted_ThrowsBadRequest` | Must accept terms |

#### Response Viewing (4 tests)

| Test | Description |
|------|-------------|
| `GetMyQuestionResponses_OnlyLoadsRespondedRecipients` | Excludes recipients with no responses |
| `GetMyQuestionResponses_IncludesTotalRecipientCount` | Separate count query for dashboard display |
| `GetOtherResponses_OnlyShowsAccountHolders` | Anonymous respondents' answers are hidden |
| `GetOtherResponses_NotParticipant_ThrowsNotFoundException` | Non-participants can't view responses |

#### Request Management (4 tests)

| Test | Description |
|------|-------------|
| `DeactivateRecipientLink_SetsIsActiveFalse` | Link becomes inactive |
| `DeactivateRecipientLink_NotOwner_ThrowsNotAuthorizedException` | Only creator can deactivate |
| `SendReminder_UpdatesReminderCount` | Increments RemindersSent and sets LastReminderAt |
| `SendReminder_NoEmail_ThrowsBadRequest` | Recipient must have email address |

#### Token Validation (3 tests)

| Test | Description |
|------|-------------|
| `ValidateTokenOwnsDropAsync_ValidTokenAndDrop_ReturnsRecipient` | Returns recipient with QuestionRequest loaded |
| `ValidateTokenOwnsDropAsync_InvalidToken_ReturnsNull` | Non-existent token returns null |
| `ValidateTokenOwnsDropAsync_WrongDrop_ReturnsNull` | Token doesn't own that dropId returns null |

---

### PermissionServiceTest.cs (2 new tests)

| Test | Description |
|------|-------------|
| `CanView_UserHasUserDropAccess_ReturnsTrue` | User with UserDrop record can view drop they don't own |
| `GetAllDrops_IncludesUserDrops` | Query includes drops accessible via OtherUsersDrops |

```csharp
[TestMethod]
public async Task CanView_UserHasUserDropAccess_ReturnsTrue()
{
    // Arrange - uses BaseRepositoryTest helpers
    InitializeWithTransaction();

    var owner = await CreateTestUser(context);
    var viewer = await CreateTestUser(context);
    var drop = await CreateTestDrop(context, owner.UserId);

    // Grant access via UserDrop
    context.UserDrops.Add(new UserDrop { DropId = drop.DropId, UserId = viewer.UserId });
    await context.SaveChangesAsync();

    var permissionService = new PermissionService();
    permissionService.Context = context;

    // Act
    var canView = permissionService.CanView(viewer.UserId, drop.DropId);

    // Assert
    Assert.IsTrue(canView);

    CleanupWithTransaction();
}
```

---

### DropsServiceTest.cs (3 new tests)

| Test | Description |
|------|-------------|
| `GetDropsByIds_ReturnsDropsWithImageLinks` | Batch load includes pre-signed URLs |
| `GetDropsByIds_EmptyList_ReturnsEmptyList` | No error on empty input |
| `AddQuestionContext_EnrichesDropsWithQuestionData` | Drops that are answers get QuestionContext populated |

---

### QuestionReminderJobTest.cs (5 tests)

| Test | Description |
|------|-------------|
| `ProcessReminders_Day7_SendsFirstReminder` | Recipients created 7+ days ago get reminder |
| `ProcessReminders_Day14_SendsSecondReminder` | Recipients with 1 reminder sent 7+ days ago get second |
| `ProcessReminders_MaxTwoReminders` | Recipients with 2 reminders sent are skipped |
| `ProcessReminders_PartialAnswers_StillSendsReminder` | Recipients with incomplete answers receive reminders |
| `ProcessReminders_CompleteAnswers_Skipped` | Recipients who answered all questions are skipped |

```csharp
[TestClass]
public class QuestionReminderJobTest : BaseRepositoryTest
{
    private QuestionReminderJob reminderJob;
    private Mock<SendEmailService> mockEmailService;

    [TestInitialize]
    public void Setup()
    {
        // Initialize context with transaction for automatic rollback
        InitializeWithTransaction();

        mockEmailService = new Mock<SendEmailService>();
        reminderJob = new QuestionReminderJob(
            mockEmailService.Object,
            new NullLogger<QuestionReminderJob>());
        reminderJob.Context = context;
    }

    [TestCleanup]
    public void Cleanup()
    {
        // Rollback transaction to clean up test data
        CleanupWithTransaction();
    }

    [TestMethod]
    public async Task ProcessReminders_Day7_SendsFirstReminder()
    {
        // Arrange
        var user = await CreateTestUser(context);
        var qs = QuestionTestFixtures.CreateQuestionSet(context, user.UserId);
        var request = QuestionTestFixtures.CreateQuestionRequest(context, qs.QuestionSetId, user.UserId);
        var recipient = QuestionTestFixtures.CreateRecipient(context, request);

        // Set created date to 8 days ago
        recipient.CreatedAt = DateTime.UtcNow.AddDays(-8);
        await context.SaveChangesAsync();

        // Act
        await reminderJob.ProcessReminders();

        // Assert
        mockEmailService.Verify(
            x => x.SendAsync(
                recipient.Email,
                EmailTypes.QuestionRequestReminder,
                It.IsAny<object>()),
            Times.Once);

        await context.Entry(recipient).ReloadAsync();
        Assert.AreEqual(1, recipient.RemindersSent);
        Assert.IsNotNull(recipient.LastReminderAt);
    }

    [TestMethod]
    public async Task ProcessReminders_CompleteAnswers_Skipped()
    {
        // Arrange
        var user = await CreateTestUser(context);
        var qs = QuestionTestFixtures.CreateQuestionSet(context, user.UserId);
        var request = QuestionTestFixtures.CreateQuestionRequest(context, qs.QuestionSetId, user.UserId);
        var recipient = QuestionTestFixtures.CreateRecipient(context, request);
        recipient.CreatedAt = DateTime.UtcNow.AddDays(-8);

        // Answer all questions
        foreach (var question in qs.Questions)
        {
            var drop = await CreateTestDrop(context, user.UserId);
            context.QuestionResponses.Add(new QuestionResponse
            {
                QuestionRequestRecipientId = recipient.QuestionRequestRecipientId,
                QuestionId = question.QuestionId,
                DropId = drop.DropId,
                AnsweredAt = DateTime.UtcNow
            });
        }
        await context.SaveChangesAsync();

        // Act
        await reminderJob.ProcessReminders();

        // Assert
        mockEmailService.Verify(
            x => x.SendAsync(It.IsAny<string>(), It.IsAny<EmailTypes>(), It.IsAny<object>()),
            Times.Never);
    }
}
```

---

### QuestionTestFixtures.cs

**File:** `cimplur-core/Memento/DomainTest/Repositories/QuestionTestFixtures.cs`

```csharp
public static class QuestionTestFixtures
{
    public static QuestionSet CreateQuestionSet(
        StreamContext context,
        int userId,
        string name = "Test Set",
        int questionCount = 2)
    {
        var qs = new QuestionSet
        {
            UserId = userId,
            Name = name,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
            Questions = Enumerable.Range(0, questionCount)
                .Select(i => new Question
                {
                    Text = $"Question {i + 1}?",
                    SortOrder = i,
                    CreatedAt = DateTime.UtcNow
                }).ToList()
        };
        context.QuestionSets.Add(qs);
        context.SaveChanges();
        return qs;
    }

    public static QuestionRequest CreateQuestionRequest(
        StreamContext context,
        int questionSetId,
        int creatorUserId,
        string message = null)
    {
        var request = new QuestionRequest
        {
            QuestionSetId = questionSetId,
            CreatorUserId = creatorUserId,
            Message = message,
            CreatedAt = DateTime.UtcNow
        };
        context.QuestionRequests.Add(request);
        context.SaveChanges();
        return request;
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
            CreatedAt = DateTime.UtcNow,
            RemindersSent = 0
        };
        context.QuestionRequestRecipients.Add(recipient);
        context.SaveChanges();
        return recipient;
    }

    public static QuestionResponse CreateResponse(
        StreamContext context,
        int recipientId,
        int questionId,
        int dropId)
    {
        var response = new QuestionResponse
        {
            QuestionRequestRecipientId = recipientId,
            QuestionId = questionId,
            DropId = dropId,
            AnsweredAt = DateTime.UtcNow
        };
        context.QuestionResponses.Add(response);
        context.SaveChanges();
        return response;
    }
}
```

---

## Frontend Unit Tests (Vitest + Vue Test Utils)

### questionApi.test.ts

**File:** `fyli-fe-v2/src/services/questionApi.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import api from "./api";
import * as questionApi from "./questionApi";

vi.mock("./api");

describe("questionApi", () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	describe("getQuestionSets", () => {
		it("calls GET /questions/sets with pagination params", async () => {
			const mockData = [{ questionSetId: 1, name: "Test" }];
			vi.mocked(api.get).mockResolvedValue({ data: mockData });

			const result = await questionApi.getQuestionSets(10, 20);

			expect(api.get).toHaveBeenCalledWith("/questions/sets", {
				params: { skip: 10, take: 20 }
			});
			expect(result.data).toEqual(mockData);
		});
	});

	describe("submitAnswer", () => {
		it("calls POST /questions/answer/{token}", async () => {
			const mockDrop = { dropId: 1 };
			vi.mocked(api.post).mockResolvedValue({ data: mockDrop });

			const data = {
				questionId: 1,
				content: "Test answer",
				date: "2026-01-01",
				dateType: 0 as const
			};

			const result = await questionApi.submitAnswer("abc-123", data);

			expect(api.post).toHaveBeenCalledWith("/questions/answer/abc-123", data);
			expect(result.data).toEqual(mockDrop);
		});
	});

	describe("uploadAnswerImage", () => {
		it("sends multipart form data", async () => {
			vi.mocked(api.post).mockResolvedValue({ data: true });

			const file = new File(["test"], "test.jpg", { type: "image/jpeg" });
			await questionApi.uploadAnswerImage("token-123", 42, file);

			expect(api.post).toHaveBeenCalledWith(
				"/questions/answer/token-123/images",
				expect.any(FormData),
				{ headers: { "Content-Type": "multipart/form-data" } }
			);

			const formData = vi.mocked(api.post).mock.calls[0][1] as FormData;
			expect(formData.get("dropId")).toBe("42");
			expect(formData.get("file")).toBe(file);
		});
	});
});
```

### errorMessage.test.ts

The existing `getErrorMessage` function at `fyli-fe-v2/src/utils/errorMessage.ts` should already have tests. If not present, add:

**File:** `fyli-fe-v2/src/utils/errorMessage.test.ts`

```typescript
import { describe, it, expect } from "vitest";
import { getErrorMessage } from "./errorMessage";

describe("getErrorMessage", () => {
	it("returns fallback for null/undefined", () => {
		expect(getErrorMessage(null, "fallback")).toBe("fallback");
		expect(getErrorMessage(undefined, "fallback")).toBe("fallback");
	});

	it("extracts string response data", () => {
		const error = { response: { data: "Server error message" } };
		expect(getErrorMessage(error, "fallback")).toBe("Server error message");
	});

	it("extracts message property from object", () => {
		const error = { response: { data: { message: "Validation failed" } } };
		expect(getErrorMessage(error, "fallback")).toBe("Validation failed");
	});

	it("returns fallback when data is empty object", () => {
		const error = { response: { data: {} } };
		expect(getErrorMessage(error, "Default error")).toBe("Default error");
	});

	it("returns fallback when no response property", () => {
		const error = new Error("Network error");
		expect(getErrorMessage(error, "Connection failed")).toBe("Connection failed");
	});
});
```

### AnswerForm.test.ts

**File:** `fyli-fe-v2/src/components/question/AnswerForm.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mount } from "@vue/test-utils";
import AnswerForm from "./AnswerForm.vue";

describe("AnswerForm", () => {
	const question = {
		questionId: 1,
		text: "What is your favorite memory?",
		sortOrder: 0,
		isAnswered: false
	};

	beforeEach(() => {
		// Mock URL.createObjectURL
		global.URL.createObjectURL = vi.fn(() => "blob:mock-url");
		global.URL.revokeObjectURL = vi.fn();
	});

	afterEach(() => {
		vi.restoreAllMocks();
	});

	it("renders question text", () => {
		const wrapper = mount(AnswerForm, { props: { question } });
		expect(wrapper.text()).toContain("What is your favorite memory?");
	});

	it("emits submit with payload on button click", async () => {
		const wrapper = mount(AnswerForm, { props: { question } });

		await wrapper.find("textarea").setValue("My favorite memory is...");
		await wrapper.find('button[class*="btn-primary"]').trigger("click");

		expect(wrapper.emitted("submit")).toBeTruthy();
		const payload = wrapper.emitted("submit")![0][0];
		expect(payload).toMatchObject({
			questionId: 1,
			content: "My favorite memory is...",
			dateType: 0
		});
	});

	it("disables submit button when isSubmitting is true", () => {
		const wrapper = mount(AnswerForm, {
			props: { question, isSubmitting: true }
		});

		const button = wrapper.find('button[class*="btn-primary"]');
		expect(button.attributes("disabled")).toBeDefined();
		expect(button.text()).toBe("Submitting...");
	});

	it("validates video size", async () => {
		const wrapper = mount(AnswerForm, { props: { question } });

		const largeFile = new File(["x".repeat(600 * 1024 * 1024)], "large.mp4", {
			type: "video/mp4"
		});

		// Simulate file selection
		const input = wrapper.find('input[accept="video/*"]');
		Object.defineProperty(input.element, "files", {
			value: [largeFile]
		});
		await input.trigger("change");

		expect(wrapper.text()).toContain("Videos must be under 500 MB");
	});

	it("revokes object URLs on unmount", async () => {
		const wrapper = mount(AnswerForm, { props: { question } });

		// Add an image
		const file = new File(["test"], "test.jpg", { type: "image/jpeg" });
		const input = wrapper.find('input[accept*="image"]');
		Object.defineProperty(input.element, "files", { value: [file] });
		await input.trigger("change");

		wrapper.unmount();

		expect(global.URL.revokeObjectURL).toHaveBeenCalled();
	});
});
```

### QuestionAnswerView.test.ts

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount, flushPromises } from "@vue/test-utils";
import { createTestingPinia } from "@pinia/testing";
import { createRouter, createMemoryHistory } from "vue-router";
import QuestionAnswerView from "./QuestionAnswerView.vue";
import * as questionApi from "@/services/questionApi";

vi.mock("@/services/questionApi");

describe("QuestionAnswerView", () => {
	const mockView = {
		questionRequestRecipientId: 1,
		creatorName: "John",
		message: "Please answer these",
		questionSetName: "Family Memories",
		questions: [
			{ questionId: 1, text: "Q1?", sortOrder: 0, isAnswered: false },
			{ questionId: 2, text: "Q2?", sortOrder: 1, isAnswered: true }
		]
	};

	let router: ReturnType<typeof createRouter>;

	beforeEach(() => {
		vi.clearAllMocks();
		router = createRouter({
			history: createMemoryHistory(),
			routes: [{ path: "/q/:token", component: QuestionAnswerView }]
		});
	});

	async function mountComponent() {
		router.push("/q/test-token");
		await router.isReady();

		return mount(QuestionAnswerView, {
			global: {
				plugins: [router, createTestingPinia()],
				stubs: ["LoadingSpinner", "AnswerForm"]
			}
		});
	}

	it("displays progress indicator", async () => {
		vi.mocked(questionApi.getQuestionsForAnswer).mockResolvedValue({
			data: mockView
		} as any);

		const wrapper = await mountComponent();
		await flushPromises();

		expect(wrapper.text()).toContain("1 of 2 answered");
	});

	it("shows optimistic pending state on submit", async () => {
		vi.mocked(questionApi.getQuestionsForAnswer).mockResolvedValue({
			data: mockView
		} as any);
		vi.mocked(questionApi.submitAnswer).mockImplementation(
			() => new Promise((resolve) => setTimeout(resolve, 100))
		);

		const wrapper = await mountComponent();
		await flushPromises();

		// Simulate starting an answer
		await wrapper.find("button").trigger("click");

		// The pending state should show
		expect(wrapper.html()).toContain("Submitting");
	});

	it("shows registration prompt after first answer", async () => {
		const unansweredView = {
			...mockView,
			questions: [{ questionId: 1, text: "Q1?", sortOrder: 0, isAnswered: false }]
		};

		vi.mocked(questionApi.getQuestionsForAnswer).mockResolvedValue({
			data: unansweredView
		} as any);
		vi.mocked(questionApi.submitAnswer).mockResolvedValue({
			data: { dropId: 1 }
		} as any);

		const wrapper = await mountComponent();
		await flushPromises();

		// Trigger submit from AnswerForm stub
		const form = wrapper.findComponent({ name: "AnswerForm" });
		form.vm.$emit("submit", {
			questionId: 1,
			content: "Test",
			date: "2026-01-01",
			dateType: 0,
			images: [],
			videos: []
		});

		await flushPromises();

		expect(wrapper.text()).toContain("Keep your memories safe");
	});
});
```

### QuestionSetListView.test.ts

**File:** `fyli-fe-v2/src/views/question/QuestionSetListView.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount, flushPromises } from "@vue/test-utils";
import { createRouter, createMemoryHistory } from "vue-router";
import QuestionSetListView from "./QuestionSetListView.vue";
import * as questionApi from "@/services/questionApi";

vi.mock("@/services/questionApi");

describe("QuestionSetListView", () => {
	let router: ReturnType<typeof createRouter>;

	beforeEach(() => {
		vi.clearAllMocks();
		router = createRouter({
			history: createMemoryHistory(),
			routes: [{ path: "/questions", component: QuestionSetListView }]
		});
	});

	it("renders list of question sets", async () => {
		vi.mocked(questionApi.getQuestionSets).mockResolvedValue({
			data: [
				{ questionSetId: 1, name: "Set 1", questions: [{ questionId: 1, text: "Q?", sortOrder: 0 }] },
				{ questionSetId: 2, name: "Set 2", questions: [] }
			]
		} as any);

		const wrapper = mount(QuestionSetListView, {
			global: { plugins: [router], stubs: ["LoadingSpinner"] }
		});

		await flushPromises();

		expect(wrapper.text()).toContain("Set 1");
		expect(wrapper.text()).toContain("Set 2");
		expect(wrapper.text()).toContain("1 questions");
	});

	it("shows error state on API failure", async () => {
		vi.mocked(questionApi.getQuestionSets).mockRejectedValue({
			response: { data: "Server error" }
		});

		const wrapper = mount(QuestionSetListView, {
			global: { plugins: [router], stubs: ["LoadingSpinner"] }
		});

		await flushPromises();

		expect(wrapper.text()).toContain("Server error");
		expect(wrapper.find('[role="alert"]').exists()).toBe(true);
	});
});
```

---

## Integration Tests (12 tests)

These tests verify end-to-end flows across the API.

| Test | Description |
|------|-------------|
| `FullAnswerFlow_NoAccount` | Answer all questions without registration |
| `FullAnswerFlow_WithRegistration` | Answer → register → verify drop ownership transferred |
| `FullAnswerFlow_WithImageUpload` | Upload image via token-authenticated endpoint |
| `FullAnswerFlow_WithVideoUpload` | Request presigned URL, upload, complete via token endpoints |
| `CrossDeviceAnswer_SameToken` | Same token works across different sessions |
| `TokenMediaUpload_InvalidToken_Returns404` | Wrong token can't upload media |
| `TokenMediaUpload_WrongDrop_Returns404` | Token can't upload to drop it doesn't own |
| `RateLimiting_PublicEndpoints_60PerMinute` | Rate limits enforced on /questions/answer/* |
| `RateLimiting_Registration_5PerMinute` | Stricter rate limit on /register endpoint |
| `ReminderJob_SendsAtCorrectTimes` | Day 7 and 14 reminders sent correctly |
| `QuestionContext_AppearsInMainFeed` | GET /api/drops returns QuestionContext for answers |
| `CreatorRetainsAccess_AfterOwnershipTransfer` | Creator can still view drops after RegisterAndLinkAnswers |

---

## Test Coverage Summary

| Area | Tests | Critical Paths Covered |
|------|-------|------------------------|
| QuestionService | 38 | CRUD, public flow, registration, management |
| PermissionService | 2 | UserDrops access check |
| DropsService | 3 | Batch loading, question context |
| QuestionReminderJob | 5 | Timing, filtering, partial answers |
| Frontend Components | 4 | AnswerForm interactions |
| Frontend Views | 6 | All 6 views |
| Frontend Services | 3 | API client methods |
| Frontend Utils | 5 | Error extraction |
| Integration | 12 | End-to-end flows |
| **Total** | **78** | |

---

## Running Tests

### Backend

```bash
cd cimplur-core/Memento
dotnet test --filter "FullyQualifiedName~QuestionService"
dotnet test --filter "FullyQualifiedName~QuestionReminderJob"
```

### Frontend

```bash
cd fyli-fe-v2
npm run test:unit -- --run
npm run test:unit -- --run --coverage
```

---

*Document Version: 1.6*
*Created: 2026-02-04*
*Updated: 2026-02-05 — Addressed review feedback: BaseRepositoryTest patterns, transaction isolation, test factory updates*
*PRD Version: 1.1*
*Status: Draft*
