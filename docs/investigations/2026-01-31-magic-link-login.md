# Investigation: Magic Link Login Not Working in Vue Migration

**Status:** ✅ Resolved
**Date opened:** 2026-01-31
**Date resolved:** 2026-01-31

## Problem Statement

Magic link login does not work in fyli-fe-vue. The backend redirects to `/#/links?route=...&token=<JWT>`, LinksView stores the JWT, then navigates to `/` where the router guard calls `getUser()` which fails, redirecting to login.

## Evidence

- Backend `/api/links?token=<base64>` returns a 302 redirect to `http://localhost:5173/#/links?route=%2F%3Flink%3D...&token=<JWT>`
- The JWT is valid (confirmed via curl — returns 200 from `/api/users`)
- The API returns data directly (e.g. `{"name":"Joshua Kibbey",...}`) with no envelope wrapper
- `userApi.ts` was using `data.data` to unwrap a non-existent `ApiResponse<T>` envelope, causing `undefined` errors

## Root Cause

All API functions in `userApi.ts` assumed the backend wrapped responses in `{ data: T, success: boolean, message?: string }` (the `ApiResponse<T>` type). The backend does NOT use this wrapper — it returns data directly. Every `data.data` call returned `undefined`, causing `getUser()` (and all other API calls) to fail.

## Resolution

Fixed `userApi.ts` to remove the extra `.data` unwrapping from all functions:
- `getUser()`: `data.data` → `data`
- `login()`: `data.data.token` → `data` (returns token string directly)
- `register()`: `data.data.token` → `data`
- `getRelationships()`: `data.data` → `data`
- `getReasons()`: `data.data` → `data.reasons`
- `shareRequest()`: `data.data` → `data`

Removed unused `ApiResponse` type import.
