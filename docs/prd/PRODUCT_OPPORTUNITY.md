# Product Opportunity: What Fyli Is Missing

A product opportunity review of the current app: who it is really for, what that person wants, and the gaps between the product we have and the product they would keep.

---

## Summary

Fyli is a **private family storytelling app**, not a social network and not a photo dump. The v2 rebuild has the skeleton of a real product. What it does not yet have is a habit, a home, or a finished artifact.

The core loop that works today:

**write a memory → maybe attach media → pick who sees it → copy a link → hope someone opens it**

That is enough to *use* once. It is not enough to *need*.

The opportunity is not “more features.” It is completing two jobs for one person: **catch today**, and **catch the past before it dies** — privately, for the same family.

---

## Current Product (What We Have)

The capture-and-share skeleton is in place:

- Memories with text, photos, videos, date precision, and writing assist
- Per-person sharing at creation (everyone / specific people / only me)
- Share links and question links that work without an account
- Storylines as named collections, with invites
- Questions with sets, recipients, reminders, and AI suggestions
- Comments and likes
- Connections via email invite
- Onboarding: first moment + optional missions
- Google sign-in and magic link

This is a coherent MVP. It is not yet a product that pulls someone back on a random Wednesday.

---

## The Ideal Person

Not “busy parents” in general. That is too wide.

**The family memory keeper.** Usually a parent in their 30s–40s, often the one who already takes all the photos, with 1–3 kids and at least one aging parent or grandparent still around.

### A concrete picture

**Sarah, 38.** Two kids, 6 and 9. Dual-income household. Her dad is 71 and starting to repeat stories. She has 14,000 photos in her camera roll and feels guilty about all of them. She tried Tinybeans when the kids were babies and it died when school started. She will not put the kids on Instagram. Last Christmas she bought her dad StoryWorth; he answered 8 of 52 questions and then it sat. On Sunday she talks to her mom and thinks “I should write that down,” then doesn’t.

She wants **one private place** that does two jobs:

1. **Catch today** — the funny thing her son said at dinner, in under a minute, shared with grandma without posting it to the internet.
2. **Catch the past before it dies** — her dad’s childhood, how her parents met, the house they grew up in.

Those two jobs *are* the product. Tinybeans does (1). StoryWorth does (2). Fyli’s shot is being the only place that does both, privately, for the same family.

### Secondary people she needs to succeed

| Person | Role | What they will actually do |
|---|---|---|
| Partner | Viewer / occasional poster | Open a text, like a photo, almost never “create a storyline” |
| Grandparent | Contributor, not organizer | Answer a question from a link or email. Will not learn an app |
| Adult sibling | Occasional | Show up for holidays and dad’s stories |
| The kids, later | Audience | This is for them in 15 years. They are not users now |

If Sarah cannot get grandma in without teaching her software, Sarah churns. If Sarah cannot find last Christmas in six months, the archive is worthless. If nothing pulls her back on a Tuesday, she becomes another empty account.

---

## Who This Is Not For

Do not chase:

- Productivity / work-life-balance professionals. That is a different product.
- People who are happy putting kids on Instagram.
- Power genealogists (Ancestry / FamilySearch). Too heavy.
- Users who want a social feed, likes-as-status, and public discovery.
- Anyone who needs a native-quality camera app first. Fyli will not beat Photos. It has to sit *on top of* Photos.

Trying to be a calendar, a todo list, or a generic “family OS” would make the product worse for Sarah.

---

## What She Wants That We Are Missing

Ranked by how much it would change whether she stays.

### 1. A reason to open the app tomorrow

This is the biggest hole.

The home screen is a reverse-chronological list. No “on this day,” no “you haven’t captured anything in 11 days,” no “Grandma answered,” no weekly email, no in-app notifications. After onboarding missions, the product goes silent.

Sarah does not forget that family matters. She forgets to *do the thing*. Facebook, Google Photos, and Apple Photos all learned this: **rediscovery is the habit, capture is the action.**

Missing in practice:

- On this day / look-back (the old app had date look-back; v2 dropped it)
- A weekly family digest email (“here’s what your family captured”)
- A nudge when someone comments, answers, or shares
- A prompt that is specific, not generic (“Liam’s last game is Friday”)

Without this, retention is willpower. Willpower loses to bedtime.

### 2. Capture that matches real life, not a form

Creating a memory is still: textarea → date widget → file picker → Next → pick share audience → Save.

That is a CMS. Sarah is holding a spatula.

She wants:

- **Voice** — talk the memory, get text
- **Camera-first** — tap, shoot, a sentence, done. Today the file input opens the library, not the camera
- **Share from the camera roll** — “Share to Fyli” from iOS/Android. That is how photos actually leave the phone
- **One step, not two.** The write-then-share wizard is correct for privacy and wrong for speed. Default sharing should be remembered (“Grandparents + Mike”) so most captures are one screen
- **Native share sheet**, not “copy link” buried in a kebab menu. Link-copy is a developer’s idea of sharing. Sarah texts grandma from the iOS share sheet

The 60-second promise is in the marketing and the onboarding. Daily capture does not keep it.

### 3. People as the unit of the product

She does not think in “drops.” She thinks in **kids, parents, grandma**.

Right now you can share *with* people. You cannot browse *about* people. Kids are not first-class. Storylines are a manual filing cabinet she has to remember to use. The old app had people filters and albums; v2 has a flat stream.

She wants:

- “Emma” as a person she can open — everything about Emma, over time
- Filter the stream by person, year, or place
- Search: “beach,” “first day of school,” “what Dad said about the farm”
- Saved audiences: “Grandparents,” not re-picking names every time (groups existed in the old product and in the API; they are not in the UI)

Without this, at 80 memories the stream becomes the camera roll she was trying to escape.

### 4. Grandma should never need an account

The right mechanic already exists: share links and question links that work logged-out. Then the product asks her to become a user to comment, and invites are email-only.

Grandma lives in **texts and email**. She will not open a hamburger menu named Storylines.

What Sarah wants:

- Text a memory (SMS / iMessage / WhatsApp), not only email invite + copied URL
- A weekly email that *is* the product for less-technical relatives — photos, a sentence, a reply button
- Commenting that is as light as “reply to this email”
- Faces next to names (avatars are specced, not shipped). A stream of initials feels like a mailing list, not a family

The growth loop is hidden: Share Link sits behind three dots, and only on memories you own. The most important button in the product is in an overflow menu.

### 5. Questions should feel like a gift, not a project

Questions are the most differentiated feature in the product. The flow is still a four-step wizard: choose set → write questions → pick recipients → send. Suggestion chips are behind “Need ideas?”

Sarah’s actual intent: **“Ask Dad about growing up. I have five minutes.”**

She wants:

- Start from a person, not a “question set”
- Three great questions, already written, tap send
- A reminder that does not depend on her checking `/questions`
- Answers that accumulate into something that looks like a story, not a list of cards
- A thing she can print or PDF and give at Christmas

StoryWorth’s whole business is: questions in, hardcover book out. Fyli collects the raw material and stops. That leaves the emotional payoff on the table.

### 6. Storylines should become stories

A storyline today is a named list of memories. Useful. Not what she pictures when she hears “Emma’s first year” or “Dad’s childhood.”

She wants:

- A narrative she can read, not a feed she can scroll
- Export / print / share the whole storyline as one artifact
- Help assembling it (even a simple chronological “chapter” view beats a card stack)
- A cover, a title, a sense that this is a *thing* the family owns

Until then, Storylines compete with a Notes folder.

### 7. The product should live on her phone

No PWA, no add-to-home-screen, no native app, no share extension. Fyli is a website she has to remember.

For this persona, if it is not on the home screen next to Photos and Messages, it loses the moment. The moment is the whole product.

### 8. Trust and “finished-ness” details she will notice

Small, but they tell her this is or isn’t a real family space:

- Avatars (specced, not shipped)
- Edit her own name (Account is display-only plus a help form)
- Notification preferences
- Default privacy (“always share with grandparents”)
- Export my family’s data
- A stream that looks like people talking, not records in a database

---

## Strategic Gaps (Not a Backlog)

These are the gaps that matter as a product. Not a list of tickets.

**Habit vs. archive.** We built capture and storage. We did not build return. On This Day + a weekly digest would do more for retention than another creation wizard.

**Two jobs, one home screen.** Capture-today and harvest-the-past are different moods. Home is only a feed. Sarah never gets a surface that says “ask your dad something” unless she already knows to open Questions in the drawer. The two differentiators are behind a hamburger.

**The rewrite dropped archive tools and did not replace them.** Look Back, people filters, albums, groups, notifications. v2 is cleaner and also less useful once the library grows. That is the most expensive kind of rewrite.

**Sharing is technically possible and socially weak.** Per-person sharing at create time is good. Copy-link, email-only invites, no groups, no native share, no SMS — that is not how families actually distribute photos.

**AI is in the wrong place relative to the promise.** Writing assist and question suggestions help *if she already sat down to write.* The blank-page problem for this user is not prose. It is remembering to capture, and not knowing what to ask Dad. Voice, prompts, and a story assembled from answers are the AI that matches the persona. “Help me write” is a nice assist, not the product.

**There is no heirloom.** People pay (and stay) for the thing they can hold: a book, a PDF, a timeline of a life. Feeds are free and forgettable.

---

## The Product She Actually Wants

**A private family attic that fills itself.**

She drops in a moment in 20 seconds. Grandma sees it in a text or a Sunday email and can reply without signing up. A few times a year she asks her dad a question and the answers pile up under his name. In December she gets “this year with Emma” as something she could print. Next March she opens the app because it is the anniversary of a trip she forgot she wrote down.

We have the attic. We do not yet have the filling, the knocking on the door, or the book on the shelf.

---

## Highest-Leverage Next Moves

In her language, not ours:

1. **Bring me back** — On This Day + weekly digest
2. **Let me capture with my voice and my camera, and text it to Grandma**
3. **Let me open Emma, or Dad, not an infinite feed**
4. **Turn questions into a gift I can give**
5. **Put Fyli on my home screen**

Everything else is downstream of whether Sarah still has a reason to open this on a random Wednesday.

---

## Related Docs

- [Product Features](archive/PRODUCT_FEATURES.md) — feature inventory and original priorities
- [Feature Ideas Q1 2026](archive/FEATURE_IDEAS_2026_Q1.md) — voice capture, prompts, search / On This Day, story builder, digest
- [MVP Core](archive/PRD_MVP_CORE.md) — capture & share loop
- [Storylines](archive/PRD_STORYLINES.md)
- [Onboarding](archive/PRD_ONBOARDING.md)
- [User Avatars](PRD_USER_AVATARS.md) — in progress; addresses the “mailing list” stream

---

*Document Version: 1.0*
*Created: 2026-09-19*
*Status: Draft*
