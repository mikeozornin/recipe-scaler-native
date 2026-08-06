# Контекст проекта

Дополнительный контекст по технологиям и структуре — в [specs/002-native-editing/plan.md](../specs/002-native-editing/plan.md). Архитектура — [ARCHITECTURE.md](ARCHITECTURE.md).

## Структура репозитория

- Native app — здесь; web sources — `../recipe-scaler-web`; production API — `https://recipe-scaler.ru`.
- Offline-first: приложение работает офлайн, кроме отдельных фич (например Discover).
- Debug builds auto-login configured prod debug user — не полагайся на ручный ввод seed в рутинном тестировании. Seed phrase при необходимости: `breeze roast wink solar guess tongue nothing subway theme palace mask wrist`
- **Store / App Review users** (отдельные от debug): [`store/fixtures/users.yaml`](../store/fixtures/users.yaml) — `ru`, `en`, `app-store-review`. Provision: `python3 scripts/store_users.py provision`.
- DEBUG simulator auto-login injects `device_token` together with `debugUserId` in `AuthService.init` (spec 041; legacy `x-user-id` disabled on prod). Override via launch env `DEBUG_DEVICE_TOKEN`. Credentials: `RecipeScalerNative/App/DebugSimulatorAutoLogin.swift`. Post-wipe recovery still re-exchanges via `AppContainer.bootstrap`.
- Architecture/sync markdown (`sync.md` и т.п.) может быть устаревшим — сверяй с live code и web `yjs-client.ts` перед тем как считать источником правды.
- **Shared contracts (Yjs, sync, auth, export, error codes):** `../recipe-scaler-web/specs/shared/` — SoT для wire; native `docs/YJS-SCHEMA.md` и contracts — pointers + platform notes.

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

- Paid Apple Developer Program ($99/yr): **active** (team `ZBPX4JYT24`). Portal + device smoke — [PAID-APPLE-DEVELOPER-REQUIRED.md](PAID-APPLE-DEVELOPER-REQUIRED.md). Timer push toggle registers APNs; silent push wakes widget timelines; Universal Links (`059`) + Share/Action (`025`) need device verification.
- Share Extension + Action Extension targets exist for URL/text import (`specs/025-share-extension`); full on-device Share Sheet testing needs paid program + App Group provisioning.
- **App Store screenshots** (raw 6.9″, ru/en × light/dark): [store/README.md](../store/README.md), spec [060](../specs/060-app-store-screenshots/spec.md). v1 store: iPhone-only, без Watch.

## Экспорт и импорт данных (native)

Локальный офлайн-first экспорт/импорт рецептов в формате Recipe Scaler JSON/ZIP **v1.0–v1.4** (parity с вебом). Спека: `specs/029-account-data-export-import`.

- **Экспорт**: Профиль → Управление данными → «Экспортировать все рецепты». Сбор из Y.Doc через `YjsSyncService.readRecipeData`, сериализация `NativeRecipeExporter` (всегда v1.4), ShareLink на временный файл.
- **Импорт**: тот же экран или `ImportRecipeSheet` (file mode). Detect → validate → `NativeRecipeImporter` → `DocumentManager.applyNativeRecipe`. Папки — batch после рецептов; **изображения** загружаются сразу после каждого рецепта (как Paprika/Crouton), не отдельной фазой; офлайн — skip с i18n warning.
- **Описание рецепта** при импорте парсится из HTML в `RecipeDescriptionDocument` (`RecipeDescriptionParser`) и пишется в Y.XmlFragment как дерево v3-узлов (`paragraph` / `heading` / `orderedList` / `bulletList` + inline `timer` / `ingredient` / `link` / `bold` / `italic`) через `RecipeDescriptionXmlFragmentWriter` (parity с Tiptap/y-prosemirror). round-trip тесты: `RecipeScalerNativeTests/NativeFormatHtmlImportRoundtripTests.swift`.
- **Core**: `RecipeScalerCore/Export/Native/` — типы, detector, validator, exporter/importer, JSON Schema reference в `schemas/`.
- **Лимиты**: `ThirdPartyImportLimits` (500 рецептов, 25 MB/image, 50 MB/entry, 500 MB/archive, 16 MB/recipe-JSON). Защита от декомпрессионных бомб — см. [specs/032-import-decompression-bomb/spec.md](../specs/032-import-decompression-bomb/spec.md).
