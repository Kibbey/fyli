# TDD: Email Link Fix for New Frontend

## Overview

The frontend has been rewritten from AngularJS (hash-based routing `/#/`) to Vue 3 (history-based clean URLs). All email templates still generate old hash-based links that are broken in the new frontend.

## Architecture Context

### Current Email Link Flow
```
1. Email template renders: BaseUrl + /#/path?link=TOKEN
2. SendEmail calls EmailSafeLinkCreator.FindAndReplaceLinks()
3. Regex /#/.+?(?=') converts to: /api/links?token=BASE64_ENCODED
4. User clicks → hits LinksController.Index()
5. Controller decodes route, extracts auth token, validates, generates JWT
6. Redirects to: HostUrl/auth/verify#token=JWT&route=ENCODED_PATH
7. MagicLinkView reads hash params, stores JWT, navigates to route
```

### Key Observations
- `HostUrl` (frontend): `http://localhost:5174` (dev) / `https://app.Fyli.com` (prod)
- `BaseUrl` (backend): `https://localhost:5001` (dev) / `https://app.Fyli.com` (prod)
- In production, both resolve to the same domain — the reverse proxy routes `/api/*` to the backend
- `EmailSafeLinkCreator.GetPath()` strips ALL query parameters from the route before redirecting, losing critical data like `dropId`, `questionId`, etc.

## Broken Links Analysis

### Category 1: Hash-Based Links (go through /api/links auto-auth flow)

| # | Email Type | Old Template Link | GetPath Result | New Frontend Route | Issue |
|---|---|---|---|---|---|
| 1 | ForgotPassword | `/#/resetPassword?token=T` | `resetPassword` | **Deprecated** | Remove link, keep username info only |
| 2 | ConnectionRequest | `/#/sharingRequest?request=T&link=L` | `sharingRequest` | `/invite/:token` | Route renamed, token in path not query |
| 3 | ConnectionRequestNewUser | `/#/sharingRequest?request=T` | `sharingRequest` | `/invite/:token` | Route renamed, token in path not query |
| 4 | EmailNotification | `/#/memory?dropId=ID&link=L` | `memory` | `/memory/:id` | dropId lost (was query, now path param) |
| 5 | CommentEmail | `/#/memory?dropId=ID&link=L` | `memory` | `/memory/:id` | dropId lost (was query, now path param) |
| 6 | ThankEmail | `/#/memory?dropId=ID&link=L` | `memory` | `/memory/:id` | dropId lost (was query, now path param) |
| 7 | Question | `/#/memory/add?questionId=ID&link=L` | `memory%2Fadd` | `/memory/new?questionId=ID` | Path renamed, questionId lost |
| 8 | ConnectionRequestQuestion | `/#/sharingRequest?request=T` | `sharingRequest` | `/invite/:token` | Route renamed |
| 9 | ConnectionRequestNewUserQuestion | `/#/sharingRequest?request=T` | `sharingRequest` | `/invite/:token` | Route renamed |
| 10 | Login | `/#/?link=T` | `` (empty) | `/` | Works if empty resolves to `/` |
| 11 | Welcome | `/#/welcome?link=T` | `welcome` | `/onboarding/welcome` | Route renamed |
| 12 | TimelineInviteExisting | `/#/sharingRequest?request=T&link=L` | `sharingRequest` | `/invite/:token` | Route renamed |
| 13 | TimelineInviteNew | `/#/sharingRequest?request=T` | `sharingRequest` | `/invite/:token` | Route renamed |
| 14 | TimelineShare | `/#/timelines/ID?link=L` | `timelines%2FID` | `/storylines/:id` | Path renamed |
| 15 | Suggestions | `/#/sharing?link=L` | `sharing` | `/connections` | Route renamed |
| 16 | Requests | `/#/sharing?link=L` | `sharing` | `/connections` | Route renamed |
| 17 | QuestionReminders | `/#/questions?link=L` | `questions` | `/questions` | **Works** (same path) |
| 18 | Footer (all emails) | `/#/emailSubscription` | `emailSubscription` | **No route exists** | Route missing |

### Category 2: Direct Links (bypass /api/links flow)

| # | Email Type | Template Link | New Route | Issue |
|---|---|---|---|---|
| 19 | QuestionRequestNotification | `BaseUrl/q/TOKEN` | `/q/:token` | Works in prod (same domain). Dev mismatch (BaseUrl≠HostUrl) |
| 20 | QuestionRequestReminder | `BaseUrl/q/TOKEN` | `/q/:token` | Same as above |
| 21 | QuestionAnswerNotification | `@Model.Link/questions/requests` | `/questions` (redirect) | **BUG**: `Model.Link` is set to `Constants.BaseUrl` in service code, but `AddTokenToModel()` overwrites it with auth token string because `QuestionAnswerNotification` is in `TokenAddedEmails` set. Result: link becomes `{raw_token_string}/questions/requests` — completely broken URL. |
| 22 | ClaimEmail | `BaseUrl/Connection/ClaimEmail?token=T` | Backend endpoint | **Works** (backend handles directly) |

### Category 3: No User-Facing Links (OK)
Receipt, ConnecionSuccess, Contact, SignUp, PaymentNotice, InviteNotice, Feedback, Fyli — internal or no links.

## Root Causes

1. **Route renaming**: Old AngularJS routes don't match new Vue routes (`sharing` → `connections`, `timelines` → `storylines`, `memory/add` → `memory/new`, `welcome` → `onboarding/welcome`)
2. **Query-to-path migration**: New frontend uses path params (`/memory/:id`) instead of query params (`?dropId=ID`)
3. **GetPath() strips query params**: Important data like `questionId` is lost during redirect
4. **Connection invite token format**: Old routes passed tokens as query params (`?request=TOKEN`), new routes use path params (`/invite/:token`)
5. **QuestionAnswerNotification bug**: `Model.Link` collision between BaseUrl and auth token
6. **Missing routes**: `emailSubscription` doesn't exist in new frontend (ForgotPassword is deprecated)
7. **New-user invite links route through `/api/links` unnecessarily**: `ConnectionRequestNewUser`, `ConnectionRequestNewUserQuestion`, and `TimelineInviteNew` are NOT in `TokenAddedEmails` so they have no `?link=` auth token. But `FindAndReplaceLinks` still converts them to `/api/links?token=...`. When `LinksController` decodes and finds no link token, `Login()` returns null. The current code redirects to `HostUrl` with **no path** — losing the invite token entirely. The Phase 3 fix to include the decoded path in the null-token redirect is critical for these flows.
8. **Login email `@Model.Token` is the auth token itself**: Unlike most templates, the `Login` email is NOT in `TokenAddedEmails`. The `@Model.Token` in `?link=@Model.Token` IS the raw encrypted link token passed from the controller. This token gets picked up by `EmailSafeLinkCreator` and goes through the normal `/api/links` flow. The regex must correctly match `/?link=...` (root path with only query params).
9. **`QuestionRequestNotification` has unused `Model.Link`**: It's in `TokenAddedEmails` so `AddTokenToModel` sets `Model.Link`, but the template only uses `@Model.AnswerLink`. The auto-added Link is harmless but wasteful. No action needed.
10. **`CreateMemoryView` doesn't handle `questionId` query param**: The `Question` email links to `/memory/new?questionId=ID` but the current `CreateMemoryView.vue` has no code to read or use this parameter. This is a frontend gap that must be addressed for the Question email flow to work end-to-end.

## Solution Design

### Approach: Update Templates + Modernize Link Flow

Since the new frontend uses clean URLs, we should:
1. Update email templates to build clean-URL paths (no `/#/`)
2. Update `EmailSafeLinkCreator` regex to match new URL patterns
3. Update `GetPath()` to preserve necessary query parameters
4. Fix the `QuestionAnswerNotification` token collision
5. Add missing frontend routes or redirect to appropriate pages

### Phase 1: Backend — Update Email Templates

**File: `cimplur-core/Memento/Domain/Emails/EmailTemplates.cs`**

Update `GetBody()` for each email type:

```csharp
// BEFORE → AFTER for each email type:

// ForgotPassword — DEPRECATED, remove reset link, just show username and direct to login
// BEFORE: /#/resetPassword?token=@Model.Token
// AFTER:  remove link, direct users to login page (magic link is the new auth)
case EmailTypes.ForgotPassword:
    return @"<p>We have recently received a request to recover your user name. Your user name is @Model.UserName. You can log in using a magic link on the <a href='" + Constants.HostUrl + "/login'>login page</a>.</p>";
// NOTE: Uses HostUrl (not BaseUrl) since /login is a public page and doesn't need
// the /api/links auto-auth flow. The ForgotPassword regex exclusion isn't needed
// because HostUrl links don't match the BaseUrl-based FindAndReplaceLinks pattern.

// ConnectionRequest
// BEFORE: /#/sharingRequest?request=@Model.Token&link=@Model.Link
// AFTER:  /invite/@Model.Token?link=@Model.Link
case EmailTypes.ConnectionRequest:
    return @"<p>@Model.User wants to share memories with you on Fyli. See what they shared <a href='" + Constants.BaseUrl + "/invite/@Model.Token?link=@Model.Link'>here</a>.</p>";

// ConnectionRequestNewUser
// BEFORE: /#/sharingRequest?request=@Model.Token
// AFTER:  /invite/@Model.Token
case EmailTypes.ConnectionRequestNewUser:
    return @"<p>@Model.User wants to preserve and share memories with you on Fyli. See what they shared <a href='" + Constants.BaseUrl + "/invite/@Model.Token'>here</a>.</p>" + aboutFyli;

// EmailNotification (shared memory)
// BEFORE: /#/memory?dropId=@Model.DropId&link=@Model.Link
// AFTER:  /memory/@Model.DropId?link=@Model.Link
case EmailTypes.EmailNotification:
    return @"<p>@Model.User has shared with you on <a href='" + Constants.BaseUrl + "/memory/@Model.DropId?link=@Model.Link'>Fyli</a>.</p>";

// CommentEmail
// BEFORE: /#/memory?dropId=@Model.DropId&link=@Model.Link
// AFTER:  /memory/@Model.DropId?link=@Model.Link
case EmailTypes.CommentEmail:
    return @"<p>@Model.User has commented on a memory you are following on <a href='" + Constants.BaseUrl + "/memory/@Model.DropId?link=@Model.Link'>Fyli</a>.</p>";

// ThankEmail
// BEFORE: /#/memory?dropId=@Model.DropId&link=@Model.Link
// AFTER:  /memory/@Model.DropId?link=@Model.Link
case EmailTypes.ThankEmail:
    return @"<p>@Model.User has thanked you for sharing a memory <a href='" + Constants.BaseUrl + "/memory/@Model.DropId?link=@Model.Link'>Fyli</a>.</p>";

// Question (answer a prompt question)
// BEFORE: /#/memory/add?questionId=@Model.Id&link=@Model.Link
// AFTER:  /memory/new?questionId=@Model.Id&link=@Model.Link
case EmailTypes.Question:
    return @"<p>@Model.User asked you a question on Fyli-</p><p><i><b>@Model.Question</b></i></p><p>Answer the question they asked you <a href='" + Constants.BaseUrl + "/memory/new?questionId=@Model.Id&link=@Model.Link'>here</a>.</p>";

// ConnectionRequestQuestion
// BEFORE: /#/sharingRequest?request=@Model.Token
// AFTER:  /invite/@Model.Token
case EmailTypes.ConnectionRequestQuestion:
    return @"<p>@Model.User asked you a question on Fyli-</p><p><i><b>@Model.Question</b></i></p><p>Answer the question they asked you <a href='" + Constants.BaseUrl + "/invite/@Model.Token'>here</a>.</p>";

// ConnectionRequestNewUserQuestion
// BEFORE: /#/sharingRequest?request=@Model.Token
// AFTER:  /invite/@Model.Token
case EmailTypes.ConnectionRequestNewUserQuestion:
    return @"<p>@Model.User asked you a question on Fyli-</p><p><i><b>@Model.Question</b></i></p><p>Answer the question they asked you <a href='" + Constants.BaseUrl + "/invite/@Model.Token'>here</a>.</p>" + aboutFyli;

// Login (magic link)
// NOTE: Login is NOT in TokenAddedEmails — @Model.Token is the raw encrypted link
// token passed from the controller. It goes through /api/links for auth.
// The model also includes Route (the user's intended destination, URL-encoded).
// BEFORE: /#/?link=@Model.Token
// AFTER:  /?link=@Model.Token
case EmailTypes.Login:
    return @"<p>@Model.Name, click this <a href='" + Constants.BaseUrl + "/?link=@Model.Token'>link</a> to log in to your Fyli account.</p>";

// Welcome
// BEFORE: /#/welcome?link=@Model.Token
// AFTER:  /onboarding/welcome?link=@Model.Token
case EmailTypes.Welcome:
    return @"<p>Welcome to Fyli @Model.Name!</p>..." +
         "<p style=\"text-align: center\"><a href='" + Constants.BaseUrl + "/onboarding/welcome?link=@Model.Token' style=\"...\">Yes</a></p>";

// TimelineInviteExisting
// BEFORE: /#/sharingRequest?request=@Model.Token&link=@Model.Link
// AFTER:  /invite/@Model.Token?link=@Model.Link
case EmailTypes.TimelineInviteExisting:
    return @"<p>@Model.User wants help preserving stories about @Model.TimelineName on Fyli.</p><p>What is your favorite memory of <a href='" + Constants.BaseUrl + "/invite/@Model.Token?link=@Model.Link'>@Model.TimelineName</a>?</p>";

// TimelineInviteNew
// BEFORE: /#/sharingRequest?request=@Model.Token
// AFTER:  /invite/@Model.Token
case EmailTypes.TimelineInviteNew:
    return @"<p>@Model.User wants help preserving stories about @Model.TimelineName on Fyli.</p><p>What is your favorite memory of <a href='" + Constants.BaseUrl + "/invite/@Model.Token'>@Model.TimelineName</a>?</p>" + aboutFyli;

// TimelineShare
// BEFORE: /#/timelines/@Model.TimelineId?link=@Model.Link
// AFTER:  /storylines/@Model.TimelineId?link=@Model.Link
case EmailTypes.TimelineShare:
    return @"<p>@Model.User wants help preserving stories about @Model.TimelineName on Fyli.</p><p>What is your favorite memory of <a href='" + Constants.BaseUrl + "/storylines/@Model.TimelineId?link=@Model.Link'>@Model.TimelineName</a>?</p>";

// Suggestions
// BEFORE: /#/sharing?link=@Model.Link
// AFTER:  /connections?link=@Model.Link
case EmailTypes.Suggestions:
    return @"<p>Connect with <span style='text-transform: capitalize'>@Model.Name</span> and others on <a href='" + Constants.BaseUrl + "/connections?link=@Model.Link'>Fyli</a>.</p>";

// Requests
// BEFORE: /#/sharing?link=@Model.Link
// AFTER:  /connections?link=@Model.Link
case EmailTypes.Requests:
    return @"<p>You have connection requests waiting for you on <a href='" + Constants.BaseUrl + "/connections?link=@Model.Link'>Fyli</a>.</p>";

// QuestionReminders
// BEFORE: /#/questions?link=@Model.Link
// AFTER:  /questions?link=@Model.Link
case EmailTypes.QuestionReminders:
    return @"<p><span style='text-transform: capitalize'>@Model.Name</span> asked you:</p> <p><i><b>@Model.Question</b></i></p> <p>Help preserve your family's history by <a href='" + Constants.BaseUrl + "/questions?link=@Model.Link'>sharing</a> your memories about this and other questions you have been asked.</p>";

// QuestionAnswerNotification — FIX the Model.Link collision
// BEFORE: @Model.Link/questions/requests (where Link gets overwritten by auth token)
// AFTER:  /questions?link=@Model.Link (use same pattern as other authenticated links)
case EmailTypes.QuestionAnswerNotification:
    return @"<p>@Model.User answered your question!</p><p><i><b>@Model.Question</b></i></p><p>View their answer on <a href='" + Constants.BaseUrl + "/questions?link=@Model.Link'>Fyli</a>.</p>";
```

**Update email footer** in `GetTemplate()`:
```csharp
// BEFORE: /#/emailSubscription (via BaseUrl — goes through /api/links)
// AFTER:  /account via HostUrl directly (no auth needed, no /api/links round-trip)
// Using HostUrl avoids needless backend redirect since no auto-login is needed.
// The data-pm-no-track attribute prevents Postmark from rewriting this link.
"<a data-pm-no-track style=\"text-decoration: none;\" href='" + Constants.HostUrl + "/account'>Manage email subscription</a>."
```

**Fix QuestionRequestNotification/Reminder** — use `HostUrl` for direct frontend links:

**File: `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`** (line 356, 1320)
**File: `cimplur-core/Memento/Domain/Repositories/QuestionReminderJob.cs`** (line 71)

```csharp
// BEFORE:
var answerLink = $"{Constants.BaseUrl}/q/{recipient.Token}";
// AFTER:
var answerLink = $"{Constants.HostUrl}/q/{recipient.Token}";
```

**Fix QuestionAnswerNotification service code:**

**File: `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`** (~line 616-622)

```csharp
// BEFORE:
await EnqueueEmail(creatorProfile.Email, EmailTypes.QuestionAnswerNotification,
    new Dictionary<string, object>
    {
        ["User"] = respondentName,
        ["Question"] = answeredQuestion.Text,
        ["Link"] = Constants.BaseUrl   // ← gets overwritten by AddTokenToModel!
    });

// AFTER: Remove "Link" from model — let AddTokenToModel add it since
// QuestionAnswerNotification is already in TokenAddedEmails
await EnqueueEmail(creatorProfile.Email, EmailTypes.QuestionAnswerNotification,
    new Dictionary<string, object>
    {
        ["User"] = respondentName,
        ["Question"] = answeredQuestion.Text,
    });
```

### Phase 2: Backend — Update EmailSafeLinkCreator

Since templates no longer use `/#/`, update the regex to match clean URLs.

**File: `cimplur-core/Memento/Domain/Utilities/EmailSafeLinkCreator.cs`**

The current regex `\/#\/.+?(?=')` matches `/#/path...` up to a single quote. We need it to match clean URL paths after `BaseUrl`.

The new regex matches the path+query portion after `BaseUrl` in href attributes, converting it to the `/api/links?token=BASE64(...)` format. Key exclusions:
- `/api/*` — backend endpoints (e.g., `/Connection/ClaimEmail`)
- `/q/*` — public question answer routes (no auth needed)
- `/Connection/*` — backend-handled directly

**How it works with the full flow:**
1. Template renders: `href='BaseUrl/memory/123?link=TOKEN'`
2. `FindAndReplaceLinks` matches `/memory/123?link=TOKEN` (the path after BaseUrl)
3. Replaces with: `BaseUrl/api/links?token=BASE64(/memory/123?link=TOKEN)`
4. `LinksController` decodes, extracts `link=` auth token, validates, generates JWT
5. `GetPath` returns `memory%2F123` (path without `link=` param)
6. Redirects to: `HostUrl/auth/verify#token=JWT&route=memory%2F123`

**For links without `?link=` (new-user invites):**
The regex still matches (e.g., `/invite/GUID`). `LinksController` decodes it, finds no `link=` token, `Login()` returns null. The updated controller (Phase 3) redirects to `HostUrl/invite/GUID` — correctly preserving the path for unauthenticated users.

**Updated `EmailSafeLinkCreator`:**

```csharp
public class EmailSafeLinkCreator
{
    public static string ConvertLink(string link)
    {
        var plainTextBytes = Encoding.UTF8.GetBytes(link);
        return  "/api/links?token=" + WebUtility.UrlEncode(Convert.ToBase64String(plainTextBytes));
    }

    public static string FindAndReplaceLinks(string emailBody)
    {
        // Match path portion after BaseUrl in href attributes
        // Captures: /path?query... up to closing single quote
        // Excludes: /api/, /q/, /Connection/ (backend-handled or public routes)
        // NOTE: In dev, HostUrl links (footer, ForgotPassword) are naturally excluded
        // because the regex lookbehind only matches BaseUrl (different domains).
        // In production, BaseUrl and HostUrl are the same domain, so HostUrl links
        // WILL match the regex. This is OK because:
        // - Footer (/account): no ?link= param, LinksController falls through to
        //   null-token path, redirects to HostUrl/account (same destination).
        // - ForgotPassword (/login): same — no ?link=, redirects to HostUrl/login.
        var baseUrlPattern = Regex.Escape(Constants.BaseUrl);
        var fullPattern = $@"(?<=href='{baseUrlPattern})(\/(?!api\/)(?!q\/)(?!Connection\/).+?)(?=')";
        return Regex.Replace(emailBody, fullPattern, m =>
            ConvertLink(m.Groups[0].Value));
    }

    public static string UnencodeLink(string route) {
        var buffer = Convert.FromBase64String(route);
        return Encoding.UTF8.GetString(buffer, 0, buffer.Length);
    }

    public static string RetrieveLink(string route) {
        var match = Regex.Match(route, linkPattern);
        return WebUtility.UrlDecode(match.Value);
    }

    // Updated: preserve query params that aren't "link"
    public static string GetPath(string route) {
        // Remove leading slash if present
        var path = route.TrimStart('/');

        // Separate path and query string
        var queryIndex = path.IndexOf("?");
        string queryString = null;
        if (queryIndex >= 0) {
            queryString = path.Substring(queryIndex + 1);
            path = path.Substring(0, queryIndex);
        }

        // Filter out the "link" parameter but keep others (e.g., questionId)
        string filteredQuery = null;
        if (!string.IsNullOrEmpty(queryString)) {
            var queryParams = queryString.Split('&')
                .Where(p => !p.StartsWith("link=", StringComparison.OrdinalIgnoreCase))
                .ToArray();
            if (queryParams.Any()) {
                filteredQuery = string.Join("&", queryParams);
            }
        }

        // Reconstruct: path + remaining query params
        var result = filteredQuery != null ? $"{path}?{filteredQuery}" : path;
        return WebUtility.UrlEncode(result);
    }

    private static string linkPattern = @"(?<=link=).+?((?=&)|\z)";
}
```

### Phase 3: Backend — Update LinksController

The `LinksController` needs two changes:

1. **Critical: Include decoded path in null-token redirect.** The current code redirects to `HostUrl` with no path when `loginToken` is null. This breaks new-user invite flows (`ConnectionRequestNewUser`, `ConnectionRequestNewUserQuestion`, `TimelineInviteNew`) because they have no `?link=` auth token — the path (e.g., `/invite/GUID`) is lost entirely. The fix preserves the path so users land on the correct page.

2. Minor: No change needed to `CreateRoute` — it already produces `/auth/verify#token=JWT&route=PATH`.

```csharp
[HttpGet]
[Route("")]
public async Task<IActionResult> Index(string token)
{
    var routeWithToken = EmailSafeLinkCreator.UnencodeLink(token);
    var loginToken = await Login(routeWithToken);
    var path = EmailSafeLinkCreator.GetPath(routeWithToken);
    if (loginToken == null) {
        // No valid auth token — redirect to frontend WITH path but without JWT.
        // This is critical for new-user invite flows (ConnectionRequestNewUser,
        // TimelineInviteNew, etc.) where no ?link= auth token is present.
        // User will need to log in or register on the destination page.
        return Redirect($"{Constants.HostUrl}/{WebUtility.UrlDecode(path)}");
    } else {
        return Redirect(CreateRoute(path, loginToken));
    }
}
```

### Phase 4: Frontend — Handle Route with Query Params in MagicLinkView

**File: `fyli-fe-v2/src/views/auth/MagicLinkView.vue`**

The `MagicLinkView` receives `route=ENCODED_PATH` in the hash. After URL decoding, the route may contain query params (e.g., `memory%2Fnew%3FquestionId%3D5` → `memory/new?questionId=5`).

Update to properly parse and navigate:

```typescript
// In MagicLinkView setup/onMounted:
const hashParams = new URLSearchParams(window.location.hash.substring(1))
const token = hashParams.get('token')
const route = hashParams.get('route')

// Clear hash for security
window.location.hash = ''

if (token) {
  // Store JWT
  localStorage.setItem('token', token)
  // ... any other auth setup
}

// Navigate to intended route
if (route) {
  const decodedRoute = decodeURIComponent(route)
  // Navigate using full path (may include query params)
  router.push('/' + decodedRoute)
} else {
  router.push('/')
}
```

### Phase 5: Frontend — Fix CreateMemoryView for questionId

**File: `fyli-fe-v2/src/views/memory/CreateMemoryView.vue`**

The `Question` email links to `/memory/new?questionId=ID`. Currently `CreateMemoryView` does not read or use the `questionId` query parameter. Without this, users clicking the Question email link land on a blank create-memory form with no question context.

Add `questionId` handling:

```typescript
// In CreateMemoryView.vue <script setup>:
import { useRoute } from 'vue-router'

const route = useRoute()
const questionId = computed(() => route.query.questionId as string | undefined)

// Use questionId to:
// 1. Fetch the question text from the API to display as context/prompt
// 2. Pass questionId when saving the memory so it's linked to the question
```

The exact implementation depends on what API exists for fetching prompt questions by ID and how the create-memory form submission includes the questionId. This needs investigation during implementation.

#### 5b. Email Subscription / Unsubscribe

The footer links to `emailSubscription`. The email template footer is updated to link directly to `HostUrl/account` (done in Phase 1). No new route needed.

### Phase 6: Backend Tests — Email Link Verification

Create a test class that verifies all email template links match valid frontend routes.

**File: `cimplur-core/Memento/DomainTest/Emails/EmailTemplateLinkTests.cs`**

```csharp
using Domain.Emails;
using Domain.Models;
using Domain.Utilities;
using static Domain.Emails.EmailTemplates;
using Xunit;

namespace DomainTest.Emails
{
    public class EmailTemplateLinkTests
    {
        // Known valid frontend routes (update when routes change)
        // Uses {param} as a unified placeholder for all dynamic segments
        // (route params like :id, :token are all normalized to {param})
        private static readonly HashSet<string> ValidFrontendPaths = new()
        {
            "/",
            "/login",
            "/register",
            "/auth/verify",
            "/memory/new",
            "/memory/{param}",
            "/memory/{param}/edit",
            "/connections",
            "/account",
            "/questions",
            "/questions/new",
            "/questions/{param}/edit",
            "/storylines",
            "/storylines/{param}",
            "/storylines/new",
            "/storylines/{param}/edit",
            "/storylines/{param}/invite",
            "/onboarding/welcome",
            "/onboarding/first-memory",
            "/onboarding/first-share",
            "/s/{param}",
            "/q/{param}",
            "/st/{param}",
            "/invite/{param}",
            "/terms",
            "/privacy",
        };

        // Extract all href links from a rendered template
        private static List<string> ExtractHrefs(string html)
        {
            var hrefs = new List<string>();
            var matches = System.Text.RegularExpressions.Regex.Matches(
                html, @"href='([^']+)'");
            foreach (System.Text.RegularExpressions.Match match in matches)
            {
                hrefs.Add(match.Groups[1].Value);
            }
            return hrefs;
        }

        // Normalize a URL path to a route pattern
        // All dynamic segments (IDs, GUIDs, Razor model refs) → {param}
        private static string NormalizeToPattern(string path)
        {
            // Remove BaseUrl and HostUrl prefixes
            path = path.Replace(Constants.BaseUrl, "");
            path = path.Replace(Constants.HostUrl, "");
            // Remove query string
            var queryIdx = path.IndexOf('?');
            if (queryIdx >= 0) path = path.Substring(0, queryIdx);
            // Replace GUIDs (with dashes) → {param}
            path = System.Text.RegularExpressions.Regex.Replace(
                path, @"/[0-9a-fA-F-]{36}", "/{param}");
            // Replace numeric IDs → {param}
            path = System.Text.RegularExpressions.Regex.Replace(
                path, @"/\d+", "/{param}");
            // Replace Razor model references (@Model.Token, @Model.DropId, etc.) → {param}
            path = System.Text.RegularExpressions.Regex.Replace(
                path, @"/@Model\.\w+", "/{param}");
            return path;
        }

        [Theory]
        [MemberData(nameof(GetUserFacingEmailTypes))]
        public void EmailTemplate_Links_MatchValidFrontendRoutes(EmailTypes emailType)
        {
            // Arrange
            var template = EmailTemplates.GetTemplateByName(emailType);

            // Act
            var hrefs = ExtractHrefs(template);

            // Assert
            foreach (var href in hrefs)
            {
                // Skip backend endpoints (ClaimEmail, etc.)
                if (href.Contains("/Connection/") || href.Contains("/api/"))
                    continue;
                // Skip data-pm-no-track (unsubscribe)
                // Already handled — just check the route exists

                var pattern = NormalizeToPattern(href);
                Assert.True(
                    ValidFrontendPaths.Contains(pattern),
                    $"Email type {emailType} contains link to '{href}' " +
                    $"which normalizes to '{pattern}' — not a valid frontend route. " +
                    $"Valid routes: {string.Join(", ", ValidFrontendPaths)}");
            }
        }

        [Fact]
        public void ForgotPassword_LinksToLoginPage()
        {
            var template = EmailTemplates.GetTemplateByName(EmailTypes.ForgotPassword);
            // Should link to HostUrl/login, NOT a BaseUrl hash route
            Assert.Contains(Constants.HostUrl + "/login", template);
            Assert.DoesNotContain("/#/", template);
            Assert.DoesNotContain("resetPassword", template);
        }

        [Fact]
        public void EmailTemplate_Footer_LinksToAccountPage()
        {
            // The footer is shared across all templates — just check one
            var template = EmailTemplates.GetTemplateByName(EmailTypes.Login);
            // Footer should use HostUrl directly (not BaseUrl) since no auth is needed
            Assert.Contains(Constants.HostUrl + "/account", template);
            Assert.DoesNotContain("emailSubscription", template);
        }

        [Fact]
        public void EmailTemplate_NoHashRoutes_Remain()
        {
            // Ensure no templates still use /#/ hash routing
            foreach (EmailTypes emailType in Enum.GetValues(typeof(EmailTypes)))
            {
                var template = EmailTemplates.GetTemplateByName(emailType);
                Assert.DoesNotContain("/#/", template,
                    StringComparison.Ordinal);
            }
        }

        public static IEnumerable<object[]> GetUserFacingEmailTypes()
        {
            // All email types that contain user-facing links
            // ForgotPassword excluded — deprecated, links to HostUrl/login (not BaseUrl pattern)
            yield return new object[] { EmailTypes.ConnectionRequest };
            yield return new object[] { EmailTypes.ConnectionRequestNewUser };
            yield return new object[] { EmailTypes.EmailNotification };
            yield return new object[] { EmailTypes.CommentEmail };
            yield return new object[] { EmailTypes.ThankEmail };
            yield return new object[] { EmailTypes.Question };
            yield return new object[] { EmailTypes.ConnectionRequestQuestion };
            yield return new object[] { EmailTypes.ConnectionRequestNewUserQuestion };
            yield return new object[] { EmailTypes.Login };
            yield return new object[] { EmailTypes.Welcome };
            yield return new object[] { EmailTypes.TimelineInviteExisting };
            yield return new object[] { EmailTypes.TimelineInviteNew };
            yield return new object[] { EmailTypes.TimelineShare };
            yield return new object[] { EmailTypes.Suggestions };
            yield return new object[] { EmailTypes.Requests };
            yield return new object[] { EmailTypes.QuestionReminders };
            yield return new object[] { EmailTypes.QuestionRequestNotification };
            yield return new object[] { EmailTypes.QuestionRequestReminder };
            yield return new object[] { EmailTypes.QuestionAnswerNotification };
        }
    }
}
```

### Phase 7: Backend Tests — EmailSafeLinkCreator

**File: `cimplur-core/Memento/DomainTest/Emails/EmailSafeLinkCreatorTests.cs`**

```csharp
using Domain.Utilities;
using Xunit;

namespace DomainTest.Emails
{
    public class EmailSafeLinkCreatorTests
    {
        [Theory]
        [InlineData("/memory/123?link=abc", "memory%2F123")]
        [InlineData("/connections?link=abc", "connections")]
        [InlineData("/memory/new?questionId=5&link=abc", "memory%2Fnew%3FquestionId%3D5")]
        [InlineData("/questions?link=abc", "questions")]
        [InlineData("/invite/some-guid?link=abc", "invite%2Fsome-guid")]
        [InlineData("/storylines/42?link=abc", "storylines%2F42")]
        [InlineData("/onboarding/welcome?link=abc", "onboarding%2Fwelcome")]
        [InlineData("/?link=abc", "")]
        public void GetPath_ExtractsPathWithoutLinkParam(string input, string expected)
        {
            var result = EmailSafeLinkCreator.GetPath(input);
            Assert.Equal(expected, result);
        }

        [Theory]
        [InlineData("/memory/123?link=abc", "abc")]
        [InlineData("/connections?link=abc123&other=x", "abc123")]
        public void RetrieveLink_ExtractsLinkToken(string input, string expected)
        {
            var result = EmailSafeLinkCreator.RetrieveLink(input);
            Assert.Equal(expected, result);
        }

        [Fact]
        public void ConvertLink_RoundTrips()
        {
            var original = "/memory/123?link=sometoken";
            var encoded = EmailSafeLinkCreator.ConvertLink(original);
            Assert.StartsWith("/api/links?token=", encoded);

            // Extract the token value
            var token = encoded.Replace("/api/links?token=", "");
            token = System.Net.WebUtility.UrlDecode(token);
            var decoded = EmailSafeLinkCreator.UnencodeLink(token);
            Assert.Equal(original, decoded);
        }

        [Fact]
        public void FindAndReplaceLinks_ConvertsCleanUrls()
        {
            var html = $"<a href='{Domain.Models.Constants.BaseUrl}/memory/123?link=abc'>Click</a>";
            var result = EmailSafeLinkCreator.FindAndReplaceLinks(html);

            // Should have replaced with /api/links?token=...
            Assert.Contains("/api/links?token=", result);
            Assert.DoesNotContain("/memory/123", result);
        }

        [Fact]
        public void FindAndReplaceLinks_DoesNotConvert_PublicRoutes()
        {
            // /q/ routes should not be converted (they're public, no auth needed)
            var html = $"<a href='{Domain.Models.Constants.BaseUrl}/q/some-token'>Click</a>";
            var result = EmailSafeLinkCreator.FindAndReplaceLinks(html);

            Assert.Contains("/q/some-token", result);
            Assert.DoesNotContain("/api/links", result);
        }

        [Fact]
        public void FindAndReplaceLinks_DoesNotConvert_BackendEndpoints()
        {
            var html = $"<a href='{Domain.Models.Constants.BaseUrl}/Connection/ClaimEmail?token=abc'>Click</a>";
            var result = EmailSafeLinkCreator.FindAndReplaceLinks(html);

            Assert.Contains("/Connection/ClaimEmail", result);
            Assert.DoesNotContain("/api/links", result);
        }

        [Fact]
        public void FindAndReplaceLinks_ConvertsRootPathWithLink()
        {
            // Login email: /?link=TOKEN (root path with only link param)
            // This must be matched by the regex even though the path is just /
            var html = $"<a href='{Domain.Models.Constants.BaseUrl}/?link=abc'>Click</a>";
            var result = EmailSafeLinkCreator.FindAndReplaceLinks(html);

            Assert.Contains("/api/links?token=", result);
            Assert.DoesNotContain("/?link=abc", result);
        }

        [Fact]
        public void FindAndReplaceLinks_DoesNotConvert_HostUrlLinks()
        {
            // Footer and ForgotPassword use HostUrl directly — should NOT be converted
            var html = $"<a href='{Domain.Models.Constants.HostUrl}/account'>Click</a>";
            var result = EmailSafeLinkCreator.FindAndReplaceLinks(html);

            Assert.Contains("/account", result);
            Assert.DoesNotContain("/api/links", result);
        }

        [Fact]
        public void FindAndReplaceLinks_ConvertsNewUserInviteWithoutLink()
        {
            // New user invites have no ?link= param but still go through /api/links
            // LinksController handles the null-token case by redirecting with path
            var html = $"<a href='{Domain.Models.Constants.BaseUrl}/invite/abc-123'>Click</a>";
            var result = EmailSafeLinkCreator.FindAndReplaceLinks(html);

            Assert.Contains("/api/links?token=", result);
            Assert.DoesNotContain("/invite/abc-123", result);
        }

        [Fact]
        public void FindAndReplaceLinks_NoHashRoutes()
        {
            // Verify the old pattern no longer appears
            var html = $"<a href='{Domain.Models.Constants.BaseUrl}/#/memory?dropId=123'>Click</a>";
            var result = EmailSafeLinkCreator.FindAndReplaceLinks(html);

            // Old hash route should NOT be converted by new pattern
            // (This test documents that old-format links would be broken)
            Assert.DoesNotContain("/api/links", result);
        }
    }
}
```

### Phase 8: Frontend Tests — Route Coverage for Email Links

**File: `fyli-fe-v2/src/router/__tests__/emailRoutes.test.ts`**

```typescript
import { describe, it, expect } from 'vitest'
import router from '@/router'

// All paths that email links can redirect to (after /api/links processing)
const emailDestinationPaths = [
  '/',
  '/memory/123',
  '/memory/new',
  '/memory/new?questionId=5',
  '/connections',
  '/questions',
  '/onboarding/welcome',
  '/storylines/42',
  '/invite/abc-def-123',
  '/q/abc-def-123',
  '/account',
  '/login',
]

describe('Email link destination routes', () => {
  emailDestinationPaths.forEach((path) => {
    it(`should resolve route for: ${path}`, () => {
      const resolved = router.resolve(path)
      // Should not fall through to a catch-all/404
      expect(resolved.matched.length).toBeGreaterThan(0)
      expect(resolved.name).not.toBe('not-found')
    })
  })

  it('should NOT have any hash-based routes', () => {
    const routes = router.getRoutes()
    routes.forEach((route) => {
      expect(route.path).not.toContain('#')
    })
  })
})
```

## Implementation Order

| Phase | Description | Files Modified | Depends On |
|-------|-------------|----------------|------------|
| 1 | Update email templates | `EmailTemplates.cs`, `QuestionService.cs`, `QuestionReminderJob.cs` | — |
| 2 | Update EmailSafeLinkCreator | `EmailSafeLinkCreator.cs` | Phase 1 |
| 3 | Update LinksController (critical for new-user invites) | `LinksController.cs` | Phase 2 |
| 4 | Update MagicLinkView | `MagicLinkView.vue` | Phase 1 |
| 5 | Add questionId handling to CreateMemoryView | `CreateMemoryView.vue` | — |
| 6 | Backend template tests | `EmailTemplateLinkTests.cs` | Phase 1 |
| 7 | Backend SafeLink tests | `EmailSafeLinkCreatorTests.cs` | Phase 2 |
| 8 | Frontend route tests | `emailRoutes.test.ts` | Phase 5 |

Also fix in Phase 1:
- `QuestionService.cs` lines 356, 616-622, 1320
- `QuestionReminderJob.cs` line 71

## Testing Strategy

### Preventing Silent Breakage

The key tests that prevent future regressions:

1. **`EmailTemplate_NoHashRoutes_Remain`** — Fails if any template still uses `/#/`
2. **`EmailTemplate_Links_MatchValidFrontendRoutes`** — Fails if any template link doesn't match a known frontend route pattern. When new routes are added/removed in the frontend, this `ValidFrontendPaths` set must be updated.
3. **`EmailSafeLinkCreator` round-trip tests** — Ensures encode/decode works correctly
4. **Frontend `emailRoutes.test.ts`** — Ensures all email destination paths resolve to real routes

### Manual Testing Checklist

For each email type, verify end-to-end:
- [ ] ForgotPassword → lands on login page (deprecated — no reset link, just login redirect)
- [ ] ConnectionRequest → lands on invite page, auto-logged-in
- [ ] ConnectionRequestNewUser → lands on invite page (no auth)
- [ ] EmailNotification → lands on memory detail, auto-logged-in
- [ ] CommentEmail → lands on memory detail, auto-logged-in
- [ ] ThankEmail → lands on memory detail, auto-logged-in
- [ ] Question → lands on create memory with questionId pre-filled
- [ ] ConnectionRequestQuestion → lands on invite page
- [ ] ConnectionRequestNewUserQuestion → lands on invite page
- [ ] Login → auto-logged-in, lands on home
- [ ] Welcome → auto-logged-in, lands on onboarding
- [ ] TimelineInviteExisting → lands on invite page, auto-logged-in
- [ ] TimelineInviteNew → lands on invite page
- [ ] TimelineShare → lands on storyline detail, auto-logged-in
- [ ] Suggestions → lands on connections, auto-logged-in
- [ ] Requests → lands on connections, auto-logged-in
- [ ] QuestionReminders → lands on questions, auto-logged-in
- [ ] QuestionRequestNotification → lands on /q/ page (public)
- [ ] QuestionRequestReminder → lands on /q/ page (public)
- [ ] QuestionAnswerNotification → lands on questions, auto-logged-in
- [ ] Footer "Manage email subscription" → lands on account page

## Open Questions

1. **Connection Invite Token**: Verified — `ConnectionInviteView.vue` reads `route.params.token` and calls `getConnectionInvitePreview(token)` → `GET /users/shareRequest/{token}/preview` and `confirmConnection(token)` → `POST /users/shareRequest/{token}/confirm`. This matches the `ShareRequest.RequestKey` (Guid) used in email templates as `@Model.Token`. **No issue here.**
2. **Email Subscription in Account**: Does the `/account` page already have email preference management, or does a section need to be added?
3. **CreateMemoryView questionId**: What API exists for fetching a prompt question by ID? How does the create-memory form submission link a new memory to a question? This needs investigation during Phase 5 implementation.
