# TDD: Dev Script Cleanup

## Overview

Update the root `npm run dev` script to:
1. Kill existing processes on all dev ports
2. Clear backend error log files
3. Start the backend (`cimplur-core`) and new frontend (`fyli-fe-v2`) concurrently

## Problem

The current `npm run dev` has two issues:

1. **Port conflict** — If a previous backend process is still running on port 5001, `dotnet watch run` fails with `Address already in use`. The `error.log` confirms this is happening.
2. **Stale frontend target** — `dev:frontend` still starts the old `fyli-fe` (AngularJS on port 8000) instead of `fyli-fe-v2` (Vue 3 on port 5174).

## Current State

```json
{
  "scripts": {
    "dev": "concurrently -n be,fe -c blue,green \"npm run dev:backend\" \"npm run dev:frontend\"",
    "dev:backend": "cd cimplur-core/Memento/Memento && dotnet watch run",
    "dev:frontend": "cd fyli-fe && npx concurrently -n tsc,srv \"npx tsc --watch --preserveWatchOutput\" \"npx http-server ./src -a localhost -p 8000 -c-1 --cors\"",
    "stop": "lsof -ti :5001,:5000,:8000 | xargs kill -9 2>/dev/null; echo 'All dev servers stopped'",
    "restart": "npm run stop && npm run dev"
  }
}
```

## Implementation

Update `package.json` scripts:

```json
{
  "scripts": {
    "dev": "npm run stop && npm run clear:logs && concurrently -n be,fe -c blue,green \"npm run dev:backend\" \"npm run dev:frontend\"",
    "dev:backend": "cd cimplur-core/Memento/Memento && dotnet watch run",
    "dev:frontend": "cd fyli-fe-v2 && npm run dev",
    "stop": "lsof -ti :5001,:5000,:5174 | xargs kill -9 2>/dev/null; echo 'All dev servers stopped'",
    "clear:logs": "rm -f cimplur-core/Memento/Memento/logs/*.log; echo 'Logs cleared'",
    "restart": "npm run stop && npm run dev"
  }
}
```

### Changes

| Script | Before | After | Why |
|---|---|---|---|
| `dev` | Just runs concurrently | `stop` + `clear:logs` + concurrently | Kill stale processes and clear logs before starting |
| `dev:frontend` | Old `fyli-fe` on port 8000 | `fyli-fe-v2` via `npm run dev` on port 5174 | Use the new Vue 3 frontend |
| `stop` | Kills ports 5001, 5000, 8000 | Kills ports 5001, 5000, 5174 | Match the new frontend port |
| `clear:logs` | N/A (new) | `rm -f` all `.log` files in logs dir | Clear stale error logs so each session starts fresh |
| `restart` | No change | No change | Already chains `stop` + `dev`, inherits improvements |

### Notes

- `rm -f` won't error if the logs directory or files don't exist
- The FileLoggerProvider already creates the logs directory and truncates files on startup via `StreamWriter(append: false)`, so `clear:logs` is belt-and-suspenders — it ensures a completely clean slate even for logs written by a crashed process that didn't go through normal startup
- `fyli-fe-v2` already has its own predev hook that kills port 5174, but we include it in `stop` too for the standalone `npm run stop` use case
- `dev:backend` is unchanged — `dotnet watch run` handles hot reload

## Files Summary

| File | Action | Description |
|---|---|---|
| `package.json` | **Modify** | Update dev scripts for new frontend, add stop-first and log clearing |

## Verification

1. With backend already running: `npm run dev` should kill it, clear logs, and restart cleanly (no port conflict error)
2. Frontend should open on `http://localhost:5174` (not port 8000)
3. `cimplur-core/Memento/Memento/logs/error.log` should be empty after startup (assuming no errors)
4. `npm run stop` should kill all three ports (5001, 5000, 5174)
5. `npm run clear:logs` should work standalone
