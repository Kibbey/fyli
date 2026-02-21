# Product Requirements Document: Question Requests

## Overview

Question Requests enables users to send questions to friends and family and collect their answers as memories. Users can batch-send multiple questions to multiple recipients, with each recipient receiving their own unique link. Recipients can answer without creating an account, using text, photos, and/or videos. Answered memories appear in both the asker's and respondent's feeds, creating a collaborative way to collect old stories and recent events (e.g., "Share your favorite Christmas memory from this year"). Respondents who create accounts can see each other's answers, enabling a shared family memory collection experience.

## Problem Statement

Busy parents want to preserve family stories and collect memories from multiple family members, but the current sharing flow is one-directional — you share *your* memories with others. There's no easy way to *ask* grandma about her childhood, request everyone's Christmas memories, or collect stories about a loved one who has passed. The friction of creating accounts and the lack of guided prompts means these stories often go uncaptured.

## Goals

1. **Collect family stories** — Make it effortless to ask family members specific questions and receive their memories
2. **Reduce respondent friction** — Allow anyone to answer questions without creating an account
3. **Enable batch collection** — Send the same questions to multiple family members, each receiving their own unique link
4. **Preserve memories for both parties** — Responses become memories owned by both the asker and respondent
5. **Drive organic growth** — Question links serve as invitation pathways to the platform

---

## User Stories

### Asking Questions

1. As a busy parent, I want to create a set of questions to ask my family so that I can collect specific memories and stories.
2. As a user, I want to save questions as reusable templates so that I can send the same questions to different people over time.
3. As a user, I want to send multiple questions in a single request so that the recipient can answer several related prompts without multiple share links.
4. As a user, I want to send the same question set to multiple email addresses at once so that I can collect Christmas memories from everyone in one action.
5. As a user, I want to get unique shareable links for each recipient so that I can text the right link to each family member.

### Answering Questions

6. As a recipient, I want to view and answer questions without creating an account so that I can respond immediately.
7. As a recipient, I want to answer each question separately so that my responses stay organized and distinct.
8. As a recipient, I want to add text, photos, and/or videos to my answer so that I can fully capture the memory.
9. As a recipient, I want an easy path to create an account after answering so that my memories are preserved in my own feed.

### Viewing Responses

10. As an asker, I want to see responses in my feed with the original question displayed above so that I have context for each answer.
11. As an asker, I want to see all responses to a question set grouped together so that I can view everyone's Christmas memories in one place.
12. As a user who answered questions and created an account, I want my answers to appear in my own feed so that I own and can revisit my memories.
13. As a respondent with an account, I want to see how other family members answered the same questions so that we can share in the memory collection experience together.

### Reminders & Management

14. As a user, I want the system to automatically remind recipients who haven't answered after a set period so that I don't have to manually follow up.
15. As a user, I want to see which questions are pending, answered, and by whom so that I can track collection progress.

---

## Feature Requirements

### 1. Question Set Creation

#### 1.1 Create Question Set
- User can create a named "Question Set" containing 1-5 questions
- Each question is plain text (max 500 characters)
- Question sets are saved to the user's library for reuse
- User can add, edit, reorder, and remove questions within a set

#### 1.2 Question Templates
- Users build their own library of question sets over time
- Future: System can provide starter templates (out of scope for initial release)

### 2. Question Request Distribution

#### 2.1 Create Question Request
- User selects a question set to send
- User enters one or more email addresses (separate inputs)
- System generates and displays a **unique share token per recipient**
- Share link format: `{baseUrl}/q/{token}` (each recipient has their own token)

#### 2.2 Per-Recipient Links
- Each recipient gets their own unique link
- Links are displayed in a list after creation for easy copying/sharing
- The same link works across multiple devices for the same recipient (token identifies the person, not the session)
- Links never expire and remain active indefinitely unless deactivated by the asker

#### 2.3 Email Notifications
- If email addresses provided, system sends email to each recipient with:
  - Asker's name and personalized message (optional)
  - Their unique direct link to answer questions
  - Preview of the first question

### 3. Answer Flow (No Account Required)

#### 3.1 Landing Page
- Display asker's name: "[Name] asked you some questions"
- Show all questions in the set with "Answer" button for each
- Track which questions have been answered in this session

#### 3.2 Answer Individual Question
- Display single question prominently
- Have the same default behavoir as creating a memory.
- Text input for memory description (required, max 4000 characters)
- Date picker (defaults to today, allows backdating)
- Photo upload (optional, multiple)
- Video upload (optional, multiple, max 500MB)
- "Submit Answer" button
- After submit, return to question list showing completion status

#### 3.3 Cross-Device Persistence
- Answers are saved server-side immediately upon submission, linked to the recipient token
- If user closes browser and returns to same link (even on a different device), they see which questions they've answered
- Unanswered questions remain available
- All answers submitted via the same token are treated as coming from the same person
- User can edit their answers withen 7 days of creating them.  After that, answers are only viewable unless the user creates an account.

### 4. Account Creation (Post-Answer)

#### 4.1 Conversion Prompt
- After answering at least one question, show: "Create an account to keep your memories and get notified when [Asker] shares with you"
- Simple registration: email + name + terms checkbox
- If email matches an existing account, prompt to sign in instead

#### 4.2 Memory Ownership Transfer
- Upon account creation, all answers from this session become memories owned by the new user
- Bidirectional connection created between asker and respondent
- Memories appear in both users' feeds

#### 4.3 Skip Option
- User can skip account creation
- Memories are still delivered to the asker
- If user returns later and creates account with same email, memories are linked retroactively

### 5. Response Display in Asker's Feed

#### 5.1 Question-Answer Format
- Response memories display with the original question shown above the answer
- Visual treatment: question in a highlighted/quoted style, answer below as normal memory content
- Creator shown as the respondent's name

#### 5.2 Grouped Response View
- New feed filter/view: "Question Responses"
- Groups all responses to a question set together
- Shows: Question Set name, list of recipients, response status per person
- Tap to expand and see all answers to each question side-by-side

#### 5.3 Feed Integration
- Responses appear in the main feed in reverse chronological order (when answered)
- Each response is a separate memory card with question context

### 6. Response Display in Respondent's Feed

#### 6.1 Memory Ownership
- If respondent created an account, their answers appear in their own feed
- Memory shows the question as context (same treatment as asker's view)
- Memory is fully editable by the respondent

#### 6.2 View Other Responses (Account Holders Only)
- Respondents who have created an account can see other respondents' answers to the same question set
- "View others' responses" link appears on question-answer memories
- Only shows responses from other respondents who also have accounts (protects anonymous respondents' privacy)
- Creates a shared experience: "See how your family answered the same questions"

### 7. Reminders & Tracking

#### 7.1 Automatic Reminders
- If recipient hasn't answered after 7 days, send reminder email
- Maximum 2 automatic reminders (day 7 and day 14)
- User can disable reminders per request

#### 7.2 Request Dashboard
- View all sent question requests
- Status per request: pending, partially answered, complete
- Per-recipient breakdown: who answered, who hasn't
- Option to manually send reminder
- Option to deactivate/revoke link

### 8. Privacy & Permissions

#### 8.1 Response Visibility
- Responses are shared only with the asker (not publicly visible to non-participants)
- If respondent creates account, the memory is private to them by default
- Connection is created between asker and respondent
- **Cross-respondent visibility:** Respondents who have accounts can see other account-holding respondents' answers to the same question set

#### 8.2 Link Security
- UUID token per recipient (122 bits of randomness)
- Rate limiting on answer submissions
- Individual recipient links can be deactivated by asker
- Links never auto-expire — remain active indefinitely unless manually deactivated

---

## Data Model

### QuestionSet
```
QuestionSet {
  questionSetId: int (PK)
  userId: int (FK → UserProfile)
  name: string (max 200)
  createdAt: datetime
  updatedAt: datetime
  archived: boolean
}
```

### Question
```
Question {
  questionId: int (PK)
  questionSetId: int (FK → QuestionSet)
  text: string (max 500)
  sortOrder: int
  createdAt: datetime
}
```

### QuestionRequest
```
QuestionRequest {
  questionRequestId: int (PK)
  questionSetId: int (FK → QuestionSet)
  creatorUserId: int (FK → UserProfile)
  message: string (max 1000, nullable) -- optional personal message
  createdAt: datetime
}
```

### QuestionRequestRecipient
```
QuestionRequestRecipient {
  questionRequestRecipientId: int (PK)
  questionRequestId: int (FK → QuestionRequest)
  token: guid (unique) -- each recipient has their own unique link token
  email: string (nullable) -- optional, for email notifications
  alias: string (max 100, nullable) -- friendly name like "Grandma"
  respondentUserId: int (FK → UserProfile, nullable) -- populated if they have/create account
  isActive: boolean (default true) -- can deactivate individual recipient links
  createdAt: datetime
  remindersSent: int (default 0)
  lastReminderAt: datetime (nullable)
}
```

### QuestionResponse
```
QuestionResponse {
  questionResponseId: int (PK)
  questionRequestRecipientId: int (FK → QuestionRequestRecipient)
  questionId: int (FK → Question)
  dropId: int (FK → Drop) -- the memory created as the answer
  answeredAt: datetime
}
```

### Drop Extensions
- Add `QuestionId` (FK, nullable) to `Drop` entity to link answer memories to their question
- Add `QuestionRequestRecipientId` (FK, nullable) to `Drop` for tracking origin

---

## UI/UX Requirements

### Question Set Creation
- Accessible from main navigation or "+" menu
- Simple list interface for managing questions
- Inline editing of question text
- Drag-to-reorder on mobile

### Share Flow
- After creating/selecting question set, modal for entering recipients
- Bulk email entry with validation
- Copy link button with toast confirmation
- Preview of what recipients will see

### Answer Landing Page (Public)
- Clean, focused design — no distracting navigation
- Fyli branding minimal but present
- Progress indicator showing X of Y questions answered
- Clear "Submit" and "Skip" actions per question

### Response Viewing
- Question displayed in a subtle card/quote style above the memory
- "View all responses" link on question-based memories
- Dashboard for tracking sent requests accessible from profile/settings

### Mobile Optimization
- Full mobile-responsive design
- Camera access for photo/video capture during answer flow
- Touch-friendly question reordering

---

## Technical Considerations

### Backend
- New entities: QuestionSet, Question, QuestionRequest, QuestionRequestRecipient, QuestionResponse
- New controller: QuestionController (CRUD for question sets, send requests, submit answers)
- Extend DropController or create QuestionResponseController for answer submission
- Background job for reminder emails (check daily for requests needing reminders)
- Rate limiting on public answer endpoints

### Frontend
- New views: QuestionSetList, QuestionSetEdit, QuestionRequestSend, QuestionAnswerPublic
- New feed filter for question responses
- Grouped response view component

### Email
- New email template: Question request notification
- New email template: Reminder for unanswered questions
- New email template: "Someone answered your question" notification

---

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Question Sets Created | Number of users who create at least one question set | 20% of active users |
| Questions Sent | Average questions sent per user who uses feature | > 3 per month |
| Answer Rate | % of question requests that receive at least one answer | > 50% |
| Multi-Recipient Usage | % of requests sent to 2+ recipients | > 40% |
| Respondent Conversion | % of respondents who create an account | > 25% |
| Response-to-Memory | % of responses that are edited/enhanced by respondent after account creation | > 10% |

---

## Out of Scope (Future Considerations)

- System-provided question templates (starter library)
- Question categories/tags
- Scheduled/recurring question sends (e.g., "Ask this every Christmas")
- Video questions (asker records video prompt)
- Anonymous responses
- Public question sets (shareable templates between users)
- AI-suggested questions based on respondent relationship
- Response reactions/comments from asker
- Export question responses as PDF/book

---

## Implementation Phases

### Phase 1: Core Question Flow
- QuestionSet and Question entities and CRUD
- QuestionRequest creation and share link generation
- Public answer landing page (single recipient, no account)
- Basic response creation as Drop with question reference
- Response display in asker's feed with question context

### Phase 2: Multi-Recipient & Accounts
- QuestionRequestRecipient entity for batch sends
- Email notifications to recipients
- Account creation flow for respondents
- Memory ownership transfer on account creation
- Response appears in both feeds

### Phase 3: Tracking & Reminders
- Question request dashboard
- Response status tracking
- Automatic reminder system
- Manual reminder sending

### Phase 4: Grouped Responses
- Grouped response view in feed
- "View all responses" aggregation
- Enhanced filtering by question set

---

## Resolved Decisions

1. **Questions per set:** Maximum 5 questions per set
2. **Reminder cadence:** Automatic reminders at day 7 and day 14
3. **Link expiration:** Links never auto-expire; remain active indefinitely unless manually deactivated
4. **Cross-respondent visibility:** Yes — respondents who create accounts can see other account-holding respondents' answers
5. **Multi-device handling:** Each recipient gets their own unique token; all answers via that token are treated as the same person regardless of device

---

*Document Version: 1.1*
*Created: 2026-02-04*
*Updated: 2026-02-04 — Resolved open questions, changed to per-recipient tokens*
*Status: Draft*
