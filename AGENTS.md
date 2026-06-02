<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan:
specs/002-native-editing/plan.md

## Spec Language

Артефакты фичи в `specs/<feature>/` пишутся **на русском**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `tasks.md`, `quickstart.md`, `contracts/`.
Чеклисты (`checklists/`) — на усмотрение автора фичи; по умолчанию русский, если не указано иное.
<!-- SPECKIT END -->

## iOS и стандартные компоненты

Если запрос **противоречит поведению или гайдлайнам стандартных компонентов iOS** (Human Interface Guidelines, `UITabBar`, `NavigationStack`, системные `Label` / SF Symbols, sheet, alert и т.п.) — **сначала уточни у пользователя**, что он действительно хочет именно это, а не обходной путь.

Примеры, когда нужно спросить:

- ручное переключение outline / `.fill` в `tabItem` вместо штатного tint активной вкладки;
- кастомный UIKit поверх SwiftUI там, где системный компонент уже решает задачу;
- поведение, которое ломает ожидаемые жесты, accessibility или внешний вид платформы.

Предложи **стандартный вариант** (кратко, почему так принято на iOS) и **альтернативу** (кастом / полная переделка), если пользователь настаивает — делай по его выбору.

@RTK.md

## Learned User Preferences

- UX/UI parity with the **mobile web** layout in `../recipe-scaler-web/recipe-scaler` (same hierarchy and behavior; pixel-perfect match not required).
- Run builds, simulator checks, and reproduction steps yourself when possible — do not ask the user to verify what the agent can run locally.
- For bugs, find root cause from logs/crash reports first (`/debug`); avoid speculative fixes.
- Agent debug ingest to Mac `localhost` does not work on a physical iPhone — use Xcode console, on-device logs, or prod-safe instrumentation.
- Spec Kit task order is flexible; closing remaining polish tasks in any order is fine.
- Capture durable UX requirements in `specs/<feature>/` so follow-up work does not lose constraints.
- Match web behavior for shared UI (e.g. masked `userId`, ingredient rows without unit labels, component-level nutrition editing).
- Prefix shell commands with `rtk` when filtering output (see `CLAUDE.md` / `RTK.md`).

## Learned Workspace Facts

- Monorepo layout: native app here; web sources in `../recipe-scaler-web`; production API host `https://recipe-scaler.ru`.
- Recipe data path: Y.Doc + Socket.IO sync (`YjsSyncService`, `DocumentManager`); REST is for auth, images, and ancillary APIs — not full recipe bodies.
- Offline-first: GRDB `ydoc_snapshots`, Phase 3 offline write queue, disk recipe image cache (`specs/003-recipe-image-offline-cache`).
- Recipes **v1/v2** are read-only on iOS with a legacy banner; **v3** editing and v1/v2→v3 migration happen on web only.
- Active implementation plan for editing: `specs/002-native-editing/plan.md`; feature specs live under `specs/NNN-<name>/`.
- Feature verification scripts: `scripts/verify-<feature>.sh` and `scripts/verify-all.sh`.
- Debug builds auto-login the configured prod debug user — do not rely on manual seed entry in routine testing.
- Grok Build session transcripts: `~/.grok/sessions/%2FUsers%2F...%2Frecipe-scaler-native/<session-id>/` (`updates.jsonl`, `summary.json`).
