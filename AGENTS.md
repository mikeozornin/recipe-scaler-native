# AGENTS.md — контекст для coding agents

План и технологии: [specs/027-paprika-crouton-import/plan.md](specs/027-paprika-crouton-import/plan.md).

## Обязательно при старте

- **Сборка** — после Swift/Xcode правок агент сам прогоняет build (не проси пользователя). Команда и цикл проверок — [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md).
- **Shell / XCTest** — `xcodebuild build` и `xcodebuild test`, см. [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md).
- **i18n** — строки только в `RecipeScalerNative/Resources/Localizable.xcstrings`; не хардкодь текст в view; без fallback на дефолтные строки. Подробности — [docs/I18N.md](docs/I18N.md).
- **UI / UX** — `.appBody()` / `.appFootnote()`, web parity, паттерны экранов. Подробности — [docs/UI.md](docs/UI.md).
- **UI по Figma / макетам** — до реализации view обязательны `specs/<feature>/layout.md` (ревью человеком) и `layout-audit.json`; прогон `bash scripts/audit-ui-layout.sh specs/<feature>`. Подробности — [docs/UI-LAYOUT-FROM-FIGMA.md](docs/UI-LAYOUT-FROM-FIGMA.md).
- **Spec Kit** — артефакты в `specs/<feature>/` на **русском** (`spec.md`, `plan.md`, …).

## Контекст проекта (кратко)

- Monorepo: native здесь, web — `../recipe-scaler-web`, API — `https://recipe-scaler.ru`.
- Offline-first; debug builds auto-login prod debug user.
- Recipes v1/v2 — read-only на iOS; v3 editing и миграция — только web.

## Журналирование (агент)

- **Фасад:** `AppLog` (`RecipeScalerNative/Utils/AppLog.swift`) — единая точка для Services и agent-trace.
- **Файл (DEBUG):** `Library/Application Support/debug-session.ndjson` в sandbox; включён по умолчанию, opt-out: `AGENT_DEBUG_LOG_DISABLED=1`.
- **Забрать логи из симулятора:** `bash scripts/pull-app-logs.sh` → `.debug-session.ndjson` в корне репо.
- **Телефон:** Профиль → Диагностика → Экспорт журнала (DEBUG); в Release файла нет — в UI понятное сообщение.
- **Добавить лог:** `AppLog.info(.sync, "event_name", data: ["key": "value"])`; для `/debug`-trace — `AgentSyncDebugLog.sync(...)` или `AppLog.agent(...)`.
- **Полный гайд:** [llm/how-to-debug.md](llm/how-to-debug.md). Не использовать HTTP ingest на `127.0.0.1` с физического iPhone.

## Документация по задаче

| Документ | Когда читать |
|----------|--------------|
| [docs/PROJECT.md](docs/PROJECT.md) | рецепты, sync, Reminders, collections, Spec Kit, платформа |
| [docs/I18N.md](docs/I18N.md) | runtime locale, свизл, navigationTitle, pluralization |
| [docs/UI.md](docs/UI.md) | типографика, HIG, web parity, паттерны экранов |
| [docs/UI-LAYOUT-FROM-FIGMA.md](docs/UI-LAYOUT-FROM-FIGMA.md) | **макеты**: layout.md, layout-audit.json, audit-ui-layout, agent loop |
| [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md) | fix-until-green, verify-скрипты, отладка |
| [llm/how-to-debug.md](llm/how-to-debug.md) | **журналирование**: `AppLog`, NDJSON, `pull-app-logs.sh`, экспорт с телефона |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | CRDT, yrs, sync layers |
| [docs/PAID-APPLE-DEVELOPER-REQUIRED.md](docs/PAID-APPLE-DEVELOPER-REQUIRED.md) | TestFlight, extensions, App Groups |

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
at specs/034-architecture-dedup-truth/plan.md
<!-- SPECKIT END -->

## Learned User Preferences

- All app text must use the project typeface (Martian), not the default SF — if a text block renders in the system font, it's a bug.
- Verify UI changes via the simulator accessibility server, not screenshot reads — `read`-tool image rendering is unreliable for visual verification.
- For Figma-driven UI: write `layout.md` + `layout-audit.json` before SwiftUI views; human reviews `layout.md`; run `audit-ui-layout.sh` in the agent loop.

## Learned Workspace Facts

_(none yet)_
