# TDD: Connection-to-Feed Visibility End-to-End Tests

## Overview

Add integration tests that verify the complete flow from connection creation through memory visibility in the connected user's feed. Currently, tests verify that the right database records are created (UserUser, TagViewer, TagDrop) but never verify that `GetAllDrops()` / `CanView()` actually returns the drops for the connected user.

## Problem

The feed visibility query in `DropsService.GetAllDrops()` is:

```csharp
var drops = Context.Drops.Where(x =>
    x.TagDrops.Any(t => t.UserTag.TagViewers.Any(a => a.UserId == userId))
    || x.UserId == userId);
```

The chain is: Connection (UserUser) → PopulateEveryone (TagViewer on "All Connections" group) → Drop tagged to group (TagDrop) → `GetAllDrops` finds the drop. No existing tests verify this full chain.

## Scope

Backend-only integration tests. No frontend changes. No schema changes.

## Data Flow Under Test

```
1. UserA and UserB connect (via method X)
2. Groups are populated via AllGroups/PopulateEveryone for BOTH users
3. UserA creates a drop and tags it to "All Connections" (or a specific group)
4. UserB calls CanView(UserB.UserId, drop.DropId) → should return true
5. UserA calls CanView(UserA.UserId, drop.DropId) → should return true (owner)
```

Bidirectional verification:

```
6. UserB creates a drop and tags it to "All Connections"
7. UserA calls CanView(UserA.UserId, dropB.DropId) → should return true
```

### PopulateEveryone Asymmetry

**Important:** The two connection methods handle `PopulateEveryone` differently:

- **Invitation flow (`ConfirmationSharingRequest`):** Only calls `PopulateEveryone` for the **acceptor**. The requester's "All Connections" group is not created or populated during this flow. In the real app, it gets populated when the requester next loads their groups via `AllGroups`. Tests must call `AllGroups` for both users to simulate this.
- **Share link flow (`GrantDropAccessAsync`):** Calls `PopulateEveryone` for **both** users. No additional setup needed.

## Connection Methods to Test

| Method | Location | Trigger |
|--------|----------|---------|
| `ConfirmationSharingRequest` | SharingService | User accepts connection invitation |
| `ClaimDropAccessAsync` → `GrantDropAccessAsync` (calls `SharingService.EnsureConnectionAsync`) | MemoryShareLinkService | User claims a share link |

## Test File

**File:** `cimplur-core/Memento/DomainTest/Repositories/FeedVisibilityTest.cs`

New test class dedicated to end-to-end feed visibility flows.

## Phase 1: Test Implementation

### Test 1: Invitation Connection → "All Connections" Share → Both See Feed

```csharp
[TestMethod]
public async Task InvitationConnect_ShareToAllConnections_BothUsersSeeDropInFeed()
{
    // Arrange: Create two users
    var userA = await CreateTestUser(context, name: "Alice");
    var userB = await CreateTestUser(context, name: "Bob");

    // Create a share request from A to B
    var request = new ShareRequest
    {
        RequesterUserId = userA.UserId,
        RequestorName = "Alice",
        TargetsEmail = userB.Email,
        TargetsUserId = userB.UserId,
        TargetAlias = "Bob",
        RequestKey = Guid.NewGuid(),
        TagsToShare = "[]",
        Used = false,
        Ignored = false,
        CreatedAt = DateTime.UtcNow,
        UpdatedAt = DateTime.UtcNow
    };
    context.ShareRequests.Add(request);
    await context.SaveChangesAsync();
    DetachAllEntities(context);

    // Act 1: UserB accepts the invitation (creates bidirectional connection)
    await sharingService.ConfirmationSharingRequest(
        request.RequestKey.ToString(), userB.UserId, "Alice");

    // ConfirmationSharingRequest only calls PopulateEveryone for the acceptor (B).
    // In the real app, A's groups get populated when A loads their groups.
    // Simulate this by calling AllGroups for both users.
    var groupsA = await groupService.AllGroups(userA.UserId);
    await groupService.AllGroups(userB.UserId);

    // Act 2: UserA creates a drop tagged to "All Connections"
    var allConnectionsTagA = groupsA
        .Single(g => g.Name == "All Connections").TagId;

    var dropModelA = new DropModel
    {
        Date = DateTime.UtcNow,
        DateType = DateTypes.Exact,
        Content = new ContentModel { Stuff = "Alice's memory" }
    };
    var (dropIdA, _) = await dropsService.Add(
        dropModelA, new List<long> { allConnectionsTagA },
        userA.UserId, new List<int>());

    // Assert: UserB can see UserA's drop
    Assert.IsTrue(dropsService.CanView(userB.UserId, dropIdA),
        "UserB should see UserA's drop shared to All Connections after invitation connect");

    // Assert: UserA can see own drop (owner always sees own drops)
    Assert.IsTrue(dropsService.CanView(userA.UserId, dropIdA));

    // Act 3: UserB creates a drop tagged to "All Connections" (bidirectional test)
    var groupsB = await groupService.AllGroups(userB.UserId);
    var allConnectionsTagB = groupsB
        .Single(g => g.Name == "All Connections").TagId;

    var dropModelB = new DropModel
    {
        Date = DateTime.UtcNow,
        DateType = DateTypes.Exact,
        Content = new ContentModel { Stuff = "Bob's memory" }
    };
    var (dropIdB, _) = await dropsService.Add(
        dropModelB, new List<long> { allConnectionsTagB },
        userB.UserId, new List<int>());

    // Assert: UserA can see UserB's drop (bidirectional)
    Assert.IsTrue(dropsService.CanView(userA.UserId, dropIdB),
        "UserA should see UserB's drop shared to All Connections after invitation connect");
}
```

### Test 2: Share Link Connection → "All Connections" Share → Both See Feed

```csharp
[TestMethod]
public async Task ShareLinkConnect_ShareToAllConnections_BothUsersSeeDropInFeed()
{
    // Arrange: Creator creates a drop shared to "All Connections"
    var creator = await CreateTestUser(context, name: "Creator");
    var viewer = await CreateTestUser(context, name: "Viewer");

    // Create "All Connections" group for creator via service
    var creatorGroups = await groupService.AllGroups(creator.UserId);
    var allConnTagId = creatorGroups
        .Single(g => g.Name == "All Connections").TagId;

    // Create a drop tagged to creator's "All Connections"
    var initialDropModel = new DropModel
    {
        Date = DateTime.UtcNow,
        DateType = DateTypes.Exact,
        Content = new ContentModel { Stuff = "Shared via link" }
    };
    var (initialDropId, _) = await dropsService.Add(
        initialDropModel, new List<long> { allConnTagId },
        creator.UserId, new List<int>());

    // Act 1: Creator creates a share link and viewer claims it
    // ClaimDropAccessAsync → GrantDropAccessAsync calls PopulateEveryone
    // for BOTH users, so no additional AllGroups calls needed
    var token = await shareLinkService.CreateLinkAsync(
        creator.UserId, initialDropId);
    await shareLinkService.ClaimDropAccessAsync(token, viewer.UserId);

    // Assert: Viewer can see the initially shared drop
    Assert.IsTrue(dropsService.CanView(viewer.UserId, initialDropId),
        "Viewer should see the drop they claimed via share link");

    // Act 2: Creator creates a NEW drop tagged to "All Connections"
    var newDropModel = new DropModel
    {
        Date = DateTime.UtcNow,
        DateType = DateTypes.Exact,
        Content = new ContentModel { Stuff = "Creator's new memory" }
    };
    var (newDropId, _) = await dropsService.Add(
        newDropModel, new List<long> { allConnTagId },
        creator.UserId, new List<int>());

    // Assert: Viewer can see the NEW drop (connection gives ongoing access)
    Assert.IsTrue(dropsService.CanView(viewer.UserId, newDropId),
        "Viewer should see creator's new drops shared to All Connections after share link connect");

    // Act 3: Viewer creates a drop tagged to their "All Connections" (bidirectional)
    // PopulateEveryone was called for viewer during ClaimDropAccessAsync,
    // so viewer's "All Connections" exists and has creator as TagViewer
    var viewerGroups = await groupService.AllGroups(viewer.UserId);
    var viewerAllConnTagId = viewerGroups
        .Single(g => g.Name == "All Connections").TagId;

    var viewerDropModel = new DropModel
    {
        Date = DateTime.UtcNow,
        DateType = DateTypes.Exact,
        Content = new ContentModel { Stuff = "Viewer's memory" }
    };
    var (viewerDropId, _) = await dropsService.Add(
        viewerDropModel, new List<long> { viewerAllConnTagId },
        viewer.UserId, new List<int>());

    // Assert: Creator can see viewer's drop (bidirectional)
    Assert.IsTrue(dropsService.CanView(creator.UserId, viewerDropId),
        "Creator should see viewer's drops shared to All Connections after share link connect");
}
```

### Test 3: Connection → Share to Specific User Group → Only Target Sees

```csharp
[TestMethod]
public async Task InvitationConnect_ShareToSpecificUserGroup_OnlyTargetSees()
{
    // Arrange: Three users - A connects with B and C
    var userA = await CreateTestUser(context, name: "Alice");
    var userB = await CreateTestUser(context, name: "Bob");
    var userC = await CreateTestUser(context, name: "Charlie");

    // Connect A↔B via invitation
    var requestAB = new ShareRequest
    {
        RequesterUserId = userA.UserId,
        RequestorName = "Alice",
        TargetsEmail = userB.Email,
        TargetsUserId = userB.UserId,
        TargetAlias = "Bob",
        RequestKey = Guid.NewGuid(),
        TagsToShare = "[]",
        Used = false,
        Ignored = false,
        CreatedAt = DateTime.UtcNow,
        UpdatedAt = DateTime.UtcNow
    };
    context.ShareRequests.Add(requestAB);

    // Connect A↔C via invitation
    var requestAC = new ShareRequest
    {
        RequesterUserId = userA.UserId,
        RequestorName = "Alice",
        TargetsEmail = userC.Email,
        TargetsUserId = userC.UserId,
        TargetAlias = "Charlie",
        RequestKey = Guid.NewGuid(),
        TagsToShare = "[]",
        Used = false,
        Ignored = false,
        CreatedAt = DateTime.UtcNow,
        UpdatedAt = DateTime.UtcNow
    };
    context.ShareRequests.Add(requestAC);
    await context.SaveChangesAsync();
    DetachAllEntities(context);

    await sharingService.ConfirmationSharingRequest(
        requestAB.RequestKey.ToString(), userB.UserId, "Alice");
    await sharingService.ConfirmationSharingRequest(
        requestAC.RequestKey.ToString(), userC.UserId, "Alice");

    // Act: Create a custom group for Bob and share a drop only with Bob
    var bobGroup = groupService.Add("Just Bob", userA.UserId);
    await groupService.UpdateNetworkViewers(
        userA.UserId, bobGroup, new List<int> { userB.UserId });

    var dropModel = new DropModel
    {
        Date = DateTime.UtcNow,
        DateType = DateTypes.Exact,
        Content = new ContentModel { Stuff = "Only for Bob" }
    };
    var (dropId, _) = await dropsService.Add(
        dropModel, new List<long> { bobGroup },
        userA.UserId, new List<int>());

    // Assert: Bob can see it
    Assert.IsTrue(dropsService.CanView(userB.UserId, dropId),
        "Bob should see drop shared to his specific group");

    // Assert: Charlie cannot see it
    Assert.IsFalse(dropsService.CanView(userC.UserId, dropId),
        "Charlie should NOT see drop shared only to Bob's group");

    // Assert: Alice (owner) can always see it
    Assert.IsTrue(dropsService.CanView(userA.UserId, dropId));
}
```

### Test 4: Unconnected User Cannot See Shared Drops

```csharp
[TestMethod]
public async Task UnconnectedUser_CannotSeeSharedDrops()
{
    // Arrange: UserA and UserB are connected; UserC is not connected to anyone
    var userA = await CreateTestUser(context, name: "Alice");
    var userB = await CreateTestUser(context, name: "Bob");
    var userC = await CreateTestUser(context, name: "Charlie");

    var request = new ShareRequest
    {
        RequesterUserId = userA.UserId,
        RequestorName = "Alice",
        TargetsEmail = userB.Email,
        TargetsUserId = userB.UserId,
        TargetAlias = "Bob",
        RequestKey = Guid.NewGuid(),
        TagsToShare = "[]",
        Used = false,
        Ignored = false,
        CreatedAt = DateTime.UtcNow,
        UpdatedAt = DateTime.UtcNow
    };
    context.ShareRequests.Add(request);
    await context.SaveChangesAsync();
    DetachAllEntities(context);

    await sharingService.ConfirmationSharingRequest(
        request.RequestKey.ToString(), userB.UserId, "Alice");

    // Populate groups for both users
    // (ConfirmationSharingRequest only populates acceptor)
    var groupsA = await groupService.AllGroups(userA.UserId);
    await groupService.AllGroups(userB.UserId);

    // Act: UserA creates a drop shared to "All Connections"
    var allConnectionsTagId = groupsA
        .Single(g => g.Name == "All Connections").TagId;

    var dropModel = new DropModel
    {
        Date = DateTime.UtcNow,
        DateType = DateTypes.Exact,
        Content = new ContentModel { Stuff = "Shared memory" }
    };
    var (dropId, _) = await dropsService.Add(
        dropModel, new List<long> { allConnectionsTagId },
        userA.UserId, new List<int>());

    // Assert: Connected UserB sees it
    Assert.IsTrue(dropsService.CanView(userB.UserId, dropId));

    // Assert: Unconnected UserC does NOT see it
    Assert.IsFalse(dropsService.CanView(userC.UserId, dropId),
        "Unconnected user should NOT see drops shared to All Connections");
}
```

### Test 5: Private Drop Not Visible to Connection (Until Shared)

```csharp
[TestMethod]
public async Task PrivateDrop_NotVisibleToConnection_UntilShared()
{
    // Arrange: Connect A↔B
    var userA = await CreateTestUser(context, name: "Alice");
    var userB = await CreateTestUser(context, name: "Bob");

    var request = new ShareRequest
    {
        RequesterUserId = userA.UserId,
        RequestorName = "Alice",
        TargetsEmail = userB.Email,
        TargetsUserId = userB.UserId,
        TargetAlias = "Bob",
        RequestKey = Guid.NewGuid(),
        TagsToShare = "[]",
        Used = false,
        Ignored = false,
        CreatedAt = DateTime.UtcNow,
        UpdatedAt = DateTime.UtcNow
    };
    context.ShareRequests.Add(request);
    await context.SaveChangesAsync();
    DetachAllEntities(context);

    await sharingService.ConfirmationSharingRequest(
        request.RequestKey.ToString(), userB.UserId, "Alice");

    // Act: UserA creates a PRIVATE drop (no network tags)
    var dropModel = new DropModel
    {
        Date = DateTime.UtcNow,
        DateType = DateTypes.Exact,
        Content = new ContentModel { Stuff = "Private thought" }
    };
    var (dropId, _) = await dropsService.Add(
        dropModel, new List<long>(),
        userA.UserId, new List<int>());

    // Assert: UserB cannot see the private drop
    Assert.IsFalse(dropsService.CanView(userB.UserId, dropId),
        "Connected user should NOT see private (untagged) drops");

    // Assert: UserA can see own private drop
    Assert.IsTrue(dropsService.CanView(userA.UserId, dropId));
}
```

## Test Infrastructure

### Service Dependencies

The test class needs multiple services that share contexts:

```csharp
[TestClass]
[TestCategory("Integration")]
[TestCategory("FeedVisibility")]
public class FeedVisibilityTest : BaseRepositoryTest
{
    private SharingService sharingService;
    private DropsService dropsService;
    private GroupService groupService;
    private MemoryShareLinkService shareLinkService;

    [TestInitialize]
    public void Setup()
    {
        var connectionString = Environment.GetEnvironmentVariable("DatabaseConnection")
            ?? "Server=localhost,1433; Database=Master; User Id=SA; Password=Dog1$Dobbie!; Encrypt=False;";
        Environment.SetEnvironmentVariable("DatabaseConnection", connectionString);

        this.context = CreateTestContext();

        // Wire services with a non-null logger for NotificationService.
        // Default factory passes null, which throws when DropsService.Add
        // triggers AddNotificationDropAdded and an exception is caught/logged.
        var sendEmailService = TestServiceFactory.CreateSendEmailService();
        this.groupService = TestServiceFactory.CreateGroupService(sendEmailService);
        var notificationService = TestServiceFactory.CreateNotificationService(
            sendEmailService, groupService, new NullLogger<NotificationService>());
        this.dropsService = TestServiceFactory.CreateDropsService(
            sendEmailService, notificationService, null, groupService);
        this.sharingService = TestServiceFactory.CreateSharingService(
            sendEmailService, notificationService, groupService);
        this.shareLinkService = TestServiceFactory.CreateMemoryShareLinkService(
            sharingService, groupService);
    }

    [TestCleanup]
    public void Cleanup()
    {
        sharingService?.Dispose();
        dropsService?.Dispose();
        groupService?.Dispose();
        shareLinkService?.Dispose();
        context?.Dispose();
    }
}
```

## Implementation Order

1. Create `FeedVisibilityTest.cs` with class setup
2. Implement Test 1 (invitation → all connections → bidirectional feed)
3. Implement Test 2 (share link → all connections → bidirectional feed)
4. Implement Test 3 (specific user group → only target sees)
5. Implement Test 4 (unconnected user cannot see)
6. Implement Test 5 (private drop not visible until shared)
7. Run all tests, fix any failures

## Success Criteria

- All 5 tests pass
- Tests verify the actual feed query (`CanView`), not just database records
- Bidirectional visibility is confirmed for both connection methods
- Negative cases verified (unconnected users, private drops)
