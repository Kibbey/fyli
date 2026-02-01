# Common Bugs

This file tracks common bugs encountered in the codebase to help identify patterns and prevent recurrence.

---

## 1. Invalid Date Parsing from AI Response

**Count:** 7

**Error Message:**
```
invalid input syntax for type date: "0NaN-NaN-NaNTNaN:NaN:NaN.NaN+NaN:NaN"
```

**Root Cause:**
When AI returns invalid date strings (e.g., empty string, malformed date), JavaScript's `new Date()` creates an "Invalid Date" object. When this is converted to ISO string with `.toISOString()`, it produces `0NaN-NaN-NaN...` which PostgreSQL rejects.

**Location:**
- `server/src/services/action-extraction.service.ts` - `extractActionsFromEmail()` method

**Fix:**
Always validate dates before using them:
```typescript
let dueDate: Date | null = null;
if (extracted.dueDate) {
    const parsedDate = new Date(extracted.dueDate);
    if (!isNaN(parsedDate.getTime())) {
        dueDate = parsedDate;
    }
}
```

**Prevention:**
- Never trust AI-returned date strings directly
- Always use `isNaN(date.getTime())` to validate Date objects before DB insert
- Consider using a date parsing library (e.g., date-fns, luxon) for robust parsing

---

## 2. Foreign Key References Wrong Table After Schema Migration

**Count:** 1

**Error Message:**
```
insert or update on table "extracted_email_actions" violates foreign key constraint "extracted_email_actions_converted_to_goal_id_fkey"
```

**Root Cause:**
After creating a new `goals` table (migration 38) and updating `EmailActionService.convertToGoal()` to use it, the `extracted_email_actions.converted_to_goal_id` column still had a foreign key constraint referencing the old `notes(id)` table instead of the new `goals(id)` table. The data migration (43) moved data but didn't update the FK constraint.

**Location:**
- `server/src/services/email-action.service.ts` - `convertToGoal()` method (line 163-166)
- `server/database/migrations/35-create-extracted-email-actions-table.sql` - FK definition (line 22)

**Fix:**
Created migration 44 to update the foreign key constraint:
```sql
-- Drop old FK constraint referencing notes table
ALTER TABLE extracted_email_actions
DROP CONSTRAINT IF EXISTS extracted_email_actions_converted_to_goal_id_fkey;

-- Add new FK constraint referencing goals table
ALTER TABLE extracted_email_actions
ADD CONSTRAINT extracted_email_actions_converted_to_goal_id_fkey
FOREIGN KEY (converted_to_goal_id) REFERENCES goals(id) ON DELETE SET NULL;
```

**Prevention:**
- When creating a new table that replaces functionality of an old table, audit all FK references pointing to the old table
- Include FK constraint updates in the same migration that introduces the schema change
- Check for orphaned constraints after major schema refactoring

---

## 3. Missing Export from Module

**Count:** 1

**Error Message:**
```
error TS2305: Module '"../middleware/error.middleware"' has no exported member 'ValidationError'.
```

**Root Cause:**
Code was written referencing a `ValidationError` class that was assumed to exist but was never created. The error middleware only exported `AppError` and `errorHandler`. The TDD specified throwing `ValidationError` for input validation but the class wasn't added to the middleware.

**Location:**
- `server/src/controllers/daily-check-in.controller.ts` - import statement (line 13)
- `server/src/middleware/error.middleware.ts` - missing export

**Fix:**
Added `ValidationError` class to error.middleware.ts:
```typescript
export class ValidationError extends AppError {
	constructor(message: string) {
		super(400, message);
		this.name = "ValidationError";
		Object.setPrototypeOf(this, ValidationError.prototype);
	}
}
```

**Prevention:**
- When referencing a class/function, verify it exists before importing
- When implementing from a TDD, create any utility classes the TDD references
- Run TypeScript compilation check (`tsc --noEmit`) before committing

---

## 4. Mock Objects Missing New Fields After Schema Changes

**Count:** 1

**Error Message:**
```
Type '{ id: string; ... }' is missing the following properties from type 'DailyCheckIn': yesterdayNote, accomplishToday, wizardCurrentStep...
```

**Root Cause:**
After adding new fields to a database model (for wizard state), test files that create mock objects of that type were not updated with the new fields. TypeScript's strict typing caught the mismatch between the mock object and the expected interface.

**Location:**
- `server/tests/unit/services/goal-context.service.test.ts` - mock object definitions
- `server/tests/unit/repositories/daily-check-in.repository.test.ts` - mock object definitions

**Fix:**
Added all new wizard fields to mock objects:
```typescript
const mockDailyCheckIn = {
	// ...existing fields...
	// Wizard state fields
	yesterdayNote: null,
	accomplishToday: null,
	wizardCurrentStep: 0,
	wizardStartedAt: null,
	wizardCompletedAt: null,
	emailActionsProcessed: 0
};
```

**Prevention:**
- When adding new fields to a model, grep for mock objects of that type across all test files
- Consider using a factory function for creating mock objects so changes are centralized
- Run full test suite after schema changes, not just affected tests

---

## 5. Missing Frontend Service File

**Count:** 1

**Error Message:**
```
[plugin:vite:import-analysis] Failed to resolve import "@/services/calendar.service" from "src/views/DailyCheckInWizardView.vue". Does the file exist?
```

**Root Cause:**
The Daily Check-In Wizard component imports `calendarService` from a service file that was never created. The TDD specified using calendar events in Step 4 of the wizard, but the frontend service to fetch them wasn't implemented.

**Location:**
- `client/src/views/DailyCheckInWizardView.vue` - import statement (line 110)
- `client/src/services/calendar.service.ts` - missing file

**Fix:**
Created `calendar.service.ts` that wraps `integrationsService.getGoogleCalendarEvents()` and transforms the data:
```typescript
export const calendarService = {
	async getTodayEvents(): Promise<CalendarEventForDisplay[]> {
		const now = new Date();
		const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
		const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);

		const events = await integrationsService.getGoogleCalendarEvents({
			timeMin: startOfDay.toISOString(),
			timeMax: endOfDay.toISOString(),
			maxResults: 20
		});

		return events.map(event => mapCalendarEventForDisplay(event));
	}
};
```

**Prevention:**
- When implementing from a TDD, ensure all imported modules exist
- Run `npm run build` in the client directory to catch import errors before committing
- Check that new service dependencies are created alongside the components that use them

---

## 6. AI Returns String "null" Instead of Null Value

**Count:** 1

**Error Message:**
```
invalid input syntax for type time: "null"
```

**Root Cause:**
When AI (Grok) returns JSON with null values, it sometimes returns the string literal `"null"` instead of the JSON null value (`null`). For example: `{"dueTime": "null"}` instead of `{"dueTime": null}`. When parsing, the check `action.dueTime || null` evaluates `"null"` as truthy (non-empty string), so the string `"null"` is passed to PostgreSQL which rejects it for TIME columns.

**Location:**
- `server/src/services/action-extraction.service.ts` - `parseExtractionResponse()` method (line ~302-303)

**Fix:**
Added explicit normalization function to convert string "null" to actual null:
```typescript
// Normalize "null" strings to actual null values (AI sometimes returns string "null")
const normalizeNull = (value: any): string | null => {
    if (value === null || value === undefined || value === "null" || value === "") {
        return null;
    }
    return String(value);
};

return {
    type,
    summary: action.summary || "Action required",
    dueDate: normalizeNull(action.dueDate),
    dueTime: normalizeNull(action.dueTime),
    // ...
};
```

**Prevention:**
- Never trust AI JSON values directly - always normalize/sanitize
- When checking for null/empty, also check for the string literal `"null"`
- Consider creating a utility function for normalizing AI responses across all AI integrations

---

## 7. Missing Database Column in Query

**Count:** 1

**Error Message:**
```
column m.snippet does not exist
```

**Root Cause:**
Query referenced a `snippet` column in `gmail_messages` table that doesn't exist in the schema. The developer assumed the column existed based on frontend type definitions without verifying the actual database schema.

**Location:**
- `server/src/repositories/email-action.repository.ts` - `getActionWithContent()` method

**Fix:**
Removed the non-existent column reference and generated snippet from available data:
```typescript
// Query only fetches existing columns: body_html, body_text
const result = await pool.query(
    `SELECT a.*, m.body_html as email_body_html, m.body_text as email_body_text
     FROM extracted_email_actions a
     JOIN gmail_messages m ON a.gmail_message_id = m.id
     WHERE a.id = $1 AND a.user_id = $2`,
    [actionId, userId]
);

// Generate snippet from body text
const snippet = bodyText ? bodyText.substring(0, 200) : null;
```

**Prevention:**
- Always verify database schema in `server/docs/DATA_SCHEMA.md` before adding column references
- Check actual table structure with `\d table_name` in psql if unsure
- Frontend types don't always match backend schema - verify independently

---

## 8. CSS Variable Name Mismatch Causes Elements to Disappear

**Count:** 1

**Error Message:**
```
(No console error - visual bug where button disappears on hover)
```

**Root Cause:**
CSS rules referenced non-existent CSS variable names. When a CSS variable is undefined, the browser uses the initial/inherited value or transparent. For background colors, this causes the element to become invisible on hover.

Example of broken code:
```css
.trust-btn:hover {
    background: var(--primary-dark);  /* Does not exist */
}
.untrust-btn:hover {
    background: var(--danger-color);  /* Does not exist */
}
```

The actual variable names in `variables.css` are:
- `--primary-hover` (not `--primary-dark`)
- `--error-color` or `--color-danger` (not `--danger-color`)

**Location:**
- `client/src/views/ManageSendersView.vue` - `.trust-btn:hover` and `.untrust-btn:hover` styles

**Fix:**
Use the correct CSS variable names that exist in `variables.css`:
```css
.trust-btn:hover {
    background: var(--primary-hover);
}
.untrust-btn:hover {
    background: var(--error-color);
}
```

**Prevention:**
- Always check `client/src/assets/styles/variables.css` for available CSS variable names
- Use IDE autocomplete for CSS variables when available
- Test hover states during development
- Consider adding fallback values: `var(--primary-dark, #4338ca)`

---
