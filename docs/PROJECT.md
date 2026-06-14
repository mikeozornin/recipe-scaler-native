# Контекст проекта

Дополнительный контекст по технологиям и структуре — в [specs/002-native-editing/plan.md](../specs/002-native-editing/plan.md). Архитектура — [ARCHITECTURE.md](ARCHITECTURE.md).

## Структура репозитория

- Native app — здесь; web sources — `../recipe-scaler-web`; production API — `https://recipe-scaler.ru`.
- Offline-first: приложение работает офлайн, кроме отдельных фич (например Discover).
- Debug builds auto-login configured prod debug user — не полагайся на ручный ввод seed в рутинном тестировании. Seed phrase при необходимости: `mass layer gossip slight bachelor broken spend story rabbit biology tower blast`
- Architecture/sync markdown (`sync.md` и т.п.) может быть устаревшим — сверяй с live code и web `yjs-client.ts` перед тем как считать источником правды.

## Рецепты и форматы

- Recipes **v1/v2** — read-only на iOS с legacy banner; **v3** editing и миграция v1/v2→v3 — только в web app.
- Native `YrsDocument` выставляет `Y_SKIP_GC` на recipe docs, чтобы yrs не эмитил skip structures, которые y-prosemirror на yjs 13 не читает; custom `contentEditable` bridge заменяется на real Tiptap — `specs/019-recipe-description-inline-edit`.

## Синхронизация и данные

- Apple Reminders shopping-list sync: CRDT list — source of truth; bidirectional completion sync; completed items остаются в Reminders (marked, not deleted); note text в Reminders — локализован.
- Native collections parity guide: `../recipe-scaler-web/llm/NATIVE_APP_COLLECTIONS.md` (web-authored reference для iOS).

## Spec Kit

Артефакты фичи в `specs/<feature>/` пишутся **на русском**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `tasks.md`, `quickstart.md`, `contracts/`.

Чеклисты (`checklists/`) — на усмотрение автора фичи; по умолчанию русский, если не указано иное.

- Spec Kit task order гибкий; закрывать polish tasks можно в любом порядке.
- Долговечные UX-требования фиксируй в `specs/<feature>/`, чтобы follow-up work не терял constraints.

## Платформа и расширения

- Paid Apple Developer Program ($99/yr): optional for simulator/dev; TestFlight, App Store, App Groups on device, extensions, APNs — см. [PAID-APPLE-DEVELOPER-REQUIRED.md](PAID-APPLE-DEVELOPER-REQUIRED.md). Timer push toggle hidden until server-synced APNs works; production push planned after Live Activities.
- Share Extension + Action Extension targets exist for URL/text import (`specs/025-share-extension`); full on-device Share Sheet testing needs paid program + App Group provisioning.
