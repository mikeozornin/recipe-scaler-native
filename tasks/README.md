# tasks/

Nightly loop task queue. Managed by the `nightly-loop` skill
(`~/.cursor/skills/nightly-loop/`).

## Workflow

1. Drop a `.md` file into `todo/` (copy `todo/_TEMPLATE.md` for a starting
   point).
2. Run `/nightly-loop start` in chat — the orchestrator picks up tasks,
   dispatches each to an isolated subagent, and moves files through the
   lifecycle below.
3. Inspect results in `done/` (`.result.md` next to the task) or failures in
   `failed/` (`.error.md`).

## Lifecycle

```
todo/ ──(picked up)──▶ in-progress/ ──(success)──▶ done/
                                   │
                   └──(non-quota error)──▶ failed/
                                   │
                   └──(quota burned)──▶ todo/  (returned to queue)
```

## Folder purpose

| Folder | Purpose |
|--------|---------|
| `todo/` | Inbox. Drop new `.md` task files here. |
| `in-progress/` | Transient. Files being worked on right now. |
| `done/` | Completed. Original task + `.result.md`. |
| `failed/` | Permanently failed. Original task + `.error.md`. |
| `.loop/` | State + logs (auto-created on first run). |

## Task file format

See `todo/_TEMPLATE.md` and `~/.cursor/skills/nightly-loop/task-template.md`.

Minimum required frontmatter:

```yaml
---
id: unique-kebab-case-id
title: Short title
priority: medium         # low | medium | high | critical
---
```

Optional fields: `parallel`, `budget_minutes`, `max_retries`, `type`, `tags`,
`created`.

Tasks always run in the project root (the directory that contains `tasks/`).
There is no per-task `repo` field.

## Inspecting state

- Live: `tasks/.loop/state.json`
- Daily log: `tasks/.loop/logs/nightly-YYYY-MM-DD.log`
- Quota events: `tasks/.loop/logs/quota-events.log`
