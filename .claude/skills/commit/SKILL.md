---
name: commit
description: Commit and push changes across all repos in the monorepo. Detects which repos have changes, stages them, generates conventional commit messages, and pushes. Handles root repo and sub-repos (cimplur-core, fyli-fe-v2, fyli-html, fyli-infra) independently.
allowed-tools: Bash, Read, Grep, Glob
user-invocable: true
---

# Commit & Push Skill

Commit and push git changes across the fyli monorepo. Each sub-repo is an independent git repository.

## Repos

| Directory | Description |
|-----------|-------------|
| `/Users/joshuakibbey/Projects/fyli` | Root repo (docs, config, orchestration) |
| `/Users/joshuakibbey/Projects/fyli/cimplur-core` | Backend (C#/.NET) |
| `/Users/joshuakibbey/Projects/fyli/fyli-fe-v2` | Frontend (Vue.js) |
| `/Users/joshuakibbey/Projects/fyli/fyli-html` | Marketing site (static HTML/Sass/Gulp) |
| `/Users/joshuakibbey/Projects/fyli/fyli-infra` | Infrastructure (AWS) |

> `fyli-fe/` is the legacy frontend. Only include it if it has changes.

## Process

### 1. Scan for Changes

For each repo, run `git status -u` (never `-uall`) and `git diff` (staged + unstaged). Skip repos that have no changes or don't exist.

### 2. Analyze Changes Per Repo

For each repo with changes:
- Read the diff to understand **what** changed and **why**
- Check `git log --oneline -5` to match the repo's existing commit message style
- Identify files that should NOT be committed (secrets, `.env`, credentials, large binaries)

### 3. Stage Files

- Stage specific files by name — avoid `git add -A` or `git add .`
- **Never** stage `.env`, `credentials.json`, or other secret files
- If there are only untracked files that look like build artifacts or generated files, ask before staging

### 4. Write Commit Messages

Follow **Conventional Commits** format:

```
<type>(<scope>): <short summary>

<optional body — what and why, not how>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

**Types:** `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`, `perf`, `ci`, `build`

**Rules:**
- Summary line: imperative mood, lowercase, no period, under 72 chars
- Focus on **why** not **what** — the diff shows what
- If multiple logical changes exist in one repo, prefer a single commit with a body that lists them
- Always end with the `Co-Authored-By` line
- Use HEREDOC syntax for the commit message:

```bash
git -C <repo-path> commit -m "$(cat <<'EOF'
<type>(<scope>): <summary>

<body>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

### 5. Push

- Push each repo that was committed: `git -C <repo-path> push`
- If push fails due to upstream changes, report the error — do NOT force push
- If the branch has no upstream, use `git -C <repo-path> push -u origin <branch>`

### 6. Summary

After all repos are processed, output a summary table:

```
| Repo | Status | Commit |
|------|--------|--------|
| root | pushed | docs: update investigation notes |
| cimplur-core | pushed | fix(api): handle null user profile |
| fyli-fe-v2 | no changes | — |
| fyli-infra | no changes | — |
```

## Safety Rules

- **Never** force push (`--force`, `-f`)
- **Never** skip hooks (`--no-verify`)
- **Never** amend existing commits unless explicitly asked
- **Never** commit secrets or credentials
- **Never** push to main/master without the user explicitly asking
- If on main/master, warn the user and confirm before pushing
- If there are merge conflicts, report them — do NOT auto-resolve

## Arguments

The user may pass arguments after `/commit`:
- `/commit` — commit and push all repos with changes
- `/commit <message>` — use the provided message as the summary (still add Co-Authored-By)
- `/commit --no-push` — commit but don't push
- `/commit --dry-run` — show what would be committed without doing it
