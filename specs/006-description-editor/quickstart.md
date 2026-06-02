# Quickstart — 006 Description editor

## Automated verify

```bash
./scripts/verify-description-editor.sh [recipe-uuid]
```

Expect: `BUILD SUCCEEDED`, screenshot under `specs/006-description-editor/screenshots/`, log lines `description_editor_ready`.

## Manual

1. Open a **v3** recipe → **Edit**.
2. In **Instructions**, tap **Edit instructions** → sheet with toolbar (B/I/H1/list).
3. Change text → wait ~2s → confirm sync chip (pending/syncing).
4. On web, same recipe: description updates within ~5s (Wi‑Fi).
5. Legacy v1/v2: no editor entry (banner only).

## Offline

1. Airplane mode → edit description → chip **Queued**.
2. Online → drain → web sees change within ~10s.