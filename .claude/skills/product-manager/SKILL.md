---
name: product-manager
description: Create and manage product documentation including PRDs, user stories, and feature specifications. Use when asked to write a PRD, define requirements, create user stories, analyze features, or update product vision.  Should ask for clarification and interview the user about product decisions.
allowed-tools: Read, Grep, Glob, Task, Write, Edit
---

# Product Manager Skill

Create product documentation for Cimplur following established patterns and busy professional balancing life and work product vision.

## Product Context

**Cimplur** helps busy professionals protect and prioritize family time while maintaining work excellence.

### Core Principles (Always Apply These)

1. **Simplicity Over Completeness** - We're not replacing Todoist or Notion; we do fewer things better
1. **Reduce Cognitive Load** - Every feature must work without the user needing to think about it.  Always provide next steps and walk the user through the experience.
3. **Customer First** - Look for ways to make the users life easier and more organized. Always start with what problem are we solving for the user. Push back on product ideas that don't put the user first.
4. **Presence and Productivity** - Success = quality family time AND tasks completed

### Target User 1: "The Stretched Parent"

- Age 32-48, knowledge worker, 1-3 children
- Works 45-55 hours/week, dual-income household
- Values family deeply but struggles with time allocation
- Feels guilty about work-life imbalance
- Wants to be remembered as a great parent, not just successful professional

### Target User 2: "Stay at Home Parent"

- Age 32-48, 1-3 children
- Wants to contribute back to schools and organizations that their kids are part of
- Needs to make time for themselves to learn and grow
- Wants to work towards getting back in the workforce at some point but not now

### Language Guidelines

**DO use:**
- "protect family time"
- "be more present"
- "moments that matter"
- "work-life balance"
- "meaningful connection"
- "live an intentional life"
- "reduce stress"

**DON'T use:**
- "powered by AI" or "AI suggested"
- Generic task management language

## Documentation Types

### 1. Product Requirements Document (PRD)

**Location:** `/docs/prd/PRD_[FEATURE_NAME].md`

**Template:**

```markdown
# Product Requirements Document: [Feature Name]

## Overview

[2-3 sentence description of the feature and its purpose]

## Problem Statement

[What problem are we solving? How does this affect the Stretched Parent?]

## Goals

1. [Goal 1 - tied to family-work balance]
2. [Goal 2]
3. [Goal 3]

## User Stories

### [Category 1]
1. As a user, I want [action] so that [family-focused benefit]
2. As a user, I want [action] so that [benefit]

### [Category 2]
3. As a user, I want [action] so that [benefit]

## Feature Requirements

### 1. [Requirement Area]

#### 1.1 [Specific Requirement]
- [Detail]
- [Detail]

#### 1.2 [Specific Requirement]
- [Detail]

### 2. [Requirement Area]

[Continue pattern...]

## Data Model

### [Model Name]
```
ModelName {
  field: type
  field: type
}
```

## UI/UX Requirements

### [Section] Display
- [Requirement]
- [Requirement]

### [Section] Interactions
- [Requirement]

## Technical Considerations

### [Area]
- [Consideration]

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| [Name] | [How measured] | [Target value] |

## Out of Scope (Future Considerations)

- [Item 1]
- [Item 2]

## Implementation Phases

### Phase 1: [Name]
- [Deliverable]
- [Deliverable]

### Phase 2: [Name]
- [Deliverable]

## Open Questions

1. [Question needing stakeholder input]
2. [Question]

---

*Document Version: 1.0*
*Created: [Date]*
*Status: Draft*
```

### 2. User Stories

**Format:**
```
As a [user type], I want [action/capability] so that [family-focused benefit]
```

**Acceptance Criteria Format:**
```
Given [context]
When [action]
Then [expected outcome]
```

**Example:**
```
User Story: Family Event Protection
As a busy parent, I want to automatically protect family events on my calendar
so that work meetings don't get scheduled over my kids' activities.

Acceptance Criteria:
- Given I have a calendar event with my child's name in the title
- When the system analyzes my calendar
- Then the event is automatically flagged as "Family - Protected"

- Given a protected family event exists
- When someone tries to schedule a meeting at that time
- Then I receive a warning about the conflict
```

### 3. Feature Specification

**For smaller features or enhancements:**

```markdown
# Feature Spec: [Feature Name]

## Summary
[One paragraph description]

## User Benefit
[How this helps the Stretched Parent]

## Requirements
1. [Requirement]
2. [Requirement]

## Acceptance Criteria
- [ ] [Criterion]
- [ ] [Criterion]

## Dependencies
- [Dependency if any]

## Notes
- [Implementation notes]
```

## PRD Writing Process

### Step 1: Understand the Request
- What problem does this solve for families?
- How does it fit the three pillars: PROTECT, CAPTURE, REFLECT?
- Does it align with our core principles?

### Step 2: Research Existing Context
- Read `/docs/prd/PRODUCT_VISION_2026.md` for strategic alignment
- Check existing PRDs in `/docs/prd/` for patterns and related features
- Review relevant TDDs in `/docs/tdd/` for technical constraints

### Step 3: Draft the PRD
- Start with the problem statement (user pain)
- Write user stories from the Stretched Parent perspective
- Define requirements clearly and specifically
- Include data models for new entities
- Specify UI/UX requirements
- Define success metrics tied to family outcomes

### Step 4: Validate Against Principles
- [ ] Does this help users be better parents/partners?
- [ ] Is it simple enough? Can we remove anything?
- [ ] Is it proactive (prevents problems) or just reactive?
- [ ] Does it measure presence/connection, not just productivity?

## Existing Product Features

Reference these when writing PRDs:

### Currently Implemented
- **Daily Check-in** - Morning briefing with calendar, goals, insights
- **Weekly Check-in** - Reflection wizard with goal setting
- **Goal Tracking** - Weekly, daily, and recurring goals
- **Check-in Streaks** - Consistency tracking with levels
- **Calendar Integration** - Google Calendar sync
- **Gmail Integration** - Email sync with category filtering

### Planned (from Vision 2026)
- **Work-Life Balance Dashboard** - Time allocation visualization
- **Family Event Detection** - Automatic protection of family time
- **Family Moments Capture** - Quick logging of meaningful moments
- **Milestone Tracking** - Children's achievements and growth
- **Partner Sharing** - Coordinate with spouse/partner

### Deprecated/Simplifying
- Complex 8-level streak system (simplifying)
- Email sender importance (removing)
- Grace day system (removing)

## Tech Stack Reference

When writing technical requirements, consider:

**Backend:** C#, .NET, PostgreSQL
**Frontend:** Vue.js 3, TypeScript, Pinia, Composition API
**Architecture:** 3-tier (Controllers → Services → Repositories)

## Example PRD Sections

### Good Problem Statement
```
Busy parents often miss important family events because work meetings
get scheduled during kids' activities. A parent might have "Emma's
soccer game" on their personal calendar, but their work calendar shows
"available" at that time, leading to meeting conflicts they discover
too late to resolve gracefully.
```

### Good User Story
```
As a working parent, I want the system to detect when a calendar event
involves my family so that I can protect that time from work conflicts
and be present for moments that matter.
```

### Good Success Metric
```
| Metric | Definition | Target |
|--------|------------|--------|
| Family Events Protected | % of detected family events where no work conflict occurred | >95% |
| Presence Score | User self-reported "I was present with family this week" rating | 4+ out of 5 |
```

## Output Location

- **PRDs:** `/docs/prd/PRD_[FEATURE_NAME].md`
- **Vision updates:** `/docs/prd/PRODUCT_VISION_2026.md`
- **Feature specs:** `/docs/prd/SPEC_[FEATURE_NAME].md`

## Checklist Before Completing PRD

- [ ] Aligns with family-first vision
- [ ] Problem statement is user-centric (not solution-centric)
- [ ] User stories use "so that [family benefit]" format
- [ ] Requirements are specific and testable
- [ ] Data model defined for new entities
- [ ] Success metrics measure family outcomes
- [ ] Out of scope section prevents scope creep
- [ ] Implementation phases are incremental
- [ ] Open questions documented for stakeholder review
