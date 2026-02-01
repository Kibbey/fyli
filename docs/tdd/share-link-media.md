# TDD: Share Link — Display Images and Videos

## Problem

The shared memory view (`/s/:token`) does not display images or videos. The backend `MemoryShareLinkService.LoadDropModel()` returns image/movie **IDs** but never converts them to pre-signed S3 URLs. The frontend receives empty `imageLinks` and `movieLinks` arrays.

## Root Cause

`MemoryShareLinkService.LoadDropModel()` (line 225, `MemoryShareLinkService.cs`) populates `Images` and `Movies` with integer IDs but does not populate `ImageLinks` or `MovieLinks` with actual URLs. In contrast, `DropsService.OrderedWithImages()` (line 388, `DropsService.cs`) does this conversion using `ImageService.GetLink()` and `MovieService.GetLink()`/`GetThumbLink()`.

## Solution

Inject `ImageService` and `MovieService` into `MemoryShareLinkService` and populate the link lists in `LoadDropModel()` after building the `DropModel`.

### No database changes required.
### No frontend changes required — the Vue component already renders `imageLinks` and `movieLinks` correctly.

## Phase 1: Backend Fix

### File: `cimplur-core/Memento/Domain/Repositories/MemoryShareLinkService.cs`

**1. Add dependencies and `TranscodeSwitchDate` to the class:**

```csharp
public class MemoryShareLinkService : BaseService
{
    private SharingService sharingService;
    private GroupService groupService;
    private UserService userService;
    private ImageService imageService;
    private MovieService movieService;

    private DateTime TranscodeSwitchDate = new DateTime(2025, 12, 1);

    public MemoryShareLinkService(
        SharingService sharingService,
        GroupService groupService,
        UserService userService,
        ImageService imageService,
        MovieService movieService)
    {
        this.sharingService = sharingService;
        this.groupService = groupService;
        this.userService = userService;
        this.imageService = imageService;
        this.movieService = movieService;
    }
```

> **Note:** `TranscodeSwitchDate` is duplicated from `DropsService`. Kept inline to minimize scope of this fix.

**2. Replace `LoadDropModel()` — populate pre-signed S3 URLs for images and videos:**

The `Drop` entity uses `Created` (not `TimeStamp`) for the creation timestamp.

```csharp
private async Task<DropModel> LoadDropModel(int dropId)
{
    var drop = await Context.Drops
        .Include(d => d.ContentDrop)
        .Include(d => d.CreatedBy)
        .Include(d => d.Images)
        .Include(d => d.Movies)
        .Include(d => d.Comments)
            .ThenInclude(c => c.Owner)
        .SingleOrDefaultAsync(d => d.DropId == dropId);

    if (drop == null)
    {
        throw new NotFoundException("Memory not found.");
    }

    var model = new DropModel
    {
        DropId = drop.DropId,
        CreatedBy = drop.CreatedBy.Name,
        CreatedById = drop.CreatedBy.UserId,
        Date = drop.Date,
        DateType = drop.DateType,
        Content = new ContentModel
        {
            ContentId = drop.DropId,
            Stuff = drop.ContentDrop.Stuff
        },
        Images = drop.Images
            .Where(i => !i.CommentId.HasValue)
            .Select(i => i.ImageDropId),
        Movies = drop.Movies
            .Where(m => !m.CommentId.HasValue)
            .Select(m => m.MovieDropId),
        Comments = drop.Comments.Select(c => new CommentModel
        {
            Comment = c.Content,
            CommentId = c.CommentId,
            Kind = c.Kind,
            OwnerId = c.Owner.UserId,
            OwnerName = c.Owner.Name ?? c.Owner.UserName,
            Images = drop.Images
                .Where(i => i.CommentId == c.CommentId)
                .Select(i => i.ImageDropId),
            Movies = drop.Movies
                .Where(m => m.CommentId == c.CommentId)
                .Select(m => m.MovieDropId),
            Foreign = true,
            Created = c.TimeStamp.ToString(),
            Date = c.TimeStamp
        }),
        Editable = false,
        UserId = drop.CreatedBy.UserId,
        IsTask = false,
        CreatedAt = drop.Created
    };

    // Generate pre-signed S3 URLs for images and videos
    bool isTranscodeV2 = this.TranscodeSwitchDate < model.CreatedAt;

    foreach (var imageId in model.Images)
    {
        model.ImageLinks.Add(new ImageModel(
            imageService.GetLink(imageId, model.UserId, model.DropId), imageId));
    }

    foreach (var movieId in model.Movies)
    {
        model.MovieLinks.Add(new MovieModel(
            movieService.GetLink(movieId, model.UserId, model.DropId, isTranscodeV2),
            movieId,
            movieService.GetThumbLink(movieId, model.UserId, model.DropId, isTranscodeV2)));
    }

    foreach (var comment in model.Comments)
    {
        foreach (var imageId in comment.Images)
        {
            comment.ImageLinks.Add(new ImageModel(
                imageService.GetLink(imageId, comment.OwnerId, model.DropId), imageId));
        }
        foreach (var movieId in comment.Movies)
        {
            comment.MovieLinks.Add(new MovieModel(
                movieService.GetLink(movieId, comment.OwnerId, model.DropId, isTranscodeV2),
                movieId,
                movieService.GetThumbLink(movieId, comment.OwnerId, model.DropId, isTranscodeV2)));
        }
    }

    return model;
}
```

### File: `cimplur-core/Memento/DomainTest/Repositories/TestServiceFactory.cs`

**3. Update test factory to pass new dependencies:**

```csharp
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
    imageService = imageService ?? new ImageService();
    movieService = movieService ?? new MovieService();
    return new MemoryShareLinkService(sharingService, groupService, userService, imageService, movieService);
}
```

## Implementation Order

1. Add `ImageService` and `MovieService` fields + `TranscodeSwitchDate` to `MemoryShareLinkService`
2. Update the constructor to accept and assign the new dependencies
3. Replace `LoadDropModel()` to populate `ImageLinks`, `MovieLinks`, and comment media links
4. Update `TestServiceFactory.CreateMemoryShareLinkService()` to pass `ImageService` and `MovieService`
5. Build and verify no compile errors
6. Test with the share link: `http://localhost:5174/s/45e0850d-2541-44b4-b7d2-c61fbd210c44`
