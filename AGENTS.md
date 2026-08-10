# AGENTS.md — контекст для coding agents

> Router. Длинные правила живут в специализированных документах ниже; этот
> файл — точка входа, не справочник. Precedence: явный запрос пользователя →
> активная feature spec/plan → shared контракты → constitution → domain
> rules → workflow docs → decision history.

## Обязательно при старте

- **Сборка** — после Swift/Xcode правок агент сам прогоняет build. Команды и цикл проверок — [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md).
- **i18n** — строки только в `RecipeScalerNative/Resources/Localizable.xcstrings` (Share/Action extensions — `Shared.xcstrings`); не хардкодь UI-текст; без fallback на дефолтные строки. [docs/I18N.md](docs/I18N.md), [scripts/lint-i18n.sh](scripts/lint-i18n.sh).
- **UI / UX** — `.appBody()` / `.appFootnote()`, web parity. [docs/UI.md](docs/UI.md).
- **UI по Figma** — `specs/<feature>/layout.md` + `layout-audit.json` до view, **human review `layout.md` обязателен**. Static audit ≠ human acceptance. [docs/UI-LAYOUT-FROM-FIGMA.md](docs/UI-LAYOUT-FROM-FIGMA.md), [docs/agents/VERIFICATION.md](docs/agents/VERIFICATION.md).
- **Spec Kit** — артефакты в `specs/<feature>/` на русском; канонический план — `.specify/templates/overrides/plan-template.md`; обязательные секции: Границы, Конституционная проверка, Downstream consumers, Positive invariants, Async lifecycle, Teardown / resource inventory, Verification.
- **Async lifecycle / contracts / fallbacks** — project-wide правила, выведенные из `llm/reviews`. [docs/agents/ASYNC-LIFECYCLE.md](docs/agents/ASYNC-LIFECYCLE.md).

## Контекст проекта (кратко)

- Monorepo: native здесь, web — `../recipe-scaler-web`, API — `https://recipe-scaler.ru`.
- Offline-first; debug builds auto-login prod debug user.
- Recipes v1/v2 — read-only на iOS; v3 editing и миграция — только web.
- **Composition root:** app-level сервисы строятся в `RecipeScalerNative/App/AppContainer.swift` и инжектятся через `.appEnvironment(_:)`. `.shared` разрешён только для AppIntents/pre-bootstrap и OS-фасадов. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (Composition Root).

## Журналирование

- Фасад: `AppLog` (`RecipeScalerNative/Utils/AppLog.swift`).
- NDJSON (DEBUG): `<sandbox>/Library/Application Support/debug-session.ndjson`; pull: `bash scripts/pull-app-logs.sh`.
- Полный гайд: [llm/how-to-debug.md](llm/how-to-debug.md). Не использовать HTTP ingest на `127.0.0.1` с физического iPhone.

## Документация по задаче

| Документ | Когда читать |
|----------|--------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | CRDT, yrs, sync layers, composition root (current source of truth) |
| [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md) | fix-until-green, verify scripts, simulator selection |
| [docs/TESTING.md](docs/TESTING.md) | positive invariants, downstream consumers, DEBUG/edge-cases, postmortem-дисциплина |
| [docs/agents/ASYNC-LIFECYCLE.md](docs/agents/ASYNC-LIFECYCLE.md) | async lifecycle, teardown, contracts, fallbacks |
| [docs/agents/VERIFICATION.md](docs/agents/VERIFICATION.md) | verify script contract: verdict vocabulary, behavioral assertions, build freshness |
| [docs/I18N.md](docs/I18N.md) | runtime locale, свизл, navigationTitle, pluralization, safe Int casts (ссылка на `SafeIntCasts.swift`) |
| [docs/UI.md](docs/UI.md) | типографика, HIG, web parity, паттерны экранов |
| [docs/UI-LAYOUT-FROM-FIGMA.md](docs/UI-LAYOUT-FROM-FIGMA.md) | layout.md, layout-audit.json, audit-ui-layout, agent loop |
| [docs/E2E.md](docs/E2E.md) | E2E UI-тесты (XCTest): infrastructure, page-objects, REST fixtures |
| [docs/PAID-APPLE-DEVELOPER-REQUIRED.md](docs/PAID-APPLE-DEVELOPER-REQUIRED.md) | TestFlight, extensions, App Groups |

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
at specs/062-mac-ipad-layout/plan.md
<!-- SPECKIT END -->

## Learned User Preferences

- All app text must use the project typeface (Martian), not the default SF — if a text block renders in the system font, it's a bug.
- Verify UI changes via the simulator accessibility server, not screenshot reads — `read`-tool image rendering is unreliable for visual verification.
- For Figma-driven UI: write `layout.md` + `layout-audit.json` before SwiftUI views; human reviews `layout.md`; run `audit-ui-layout.sh` in the agent loop.
- Never use the `composer-fast` model for subagents — always use the primary model (composer-2.5).
- Commit/close Linear issue only on explicit «закрой задачу» or `/solve-issue` with commit authorization; otherwise stop after `VERIFIED`.
- Prefer plan-driven implementation: `specs/<feature>/spec.md` → `plan.md` → `tasks.md` → execute tasks sequentially **after** required human gates (layout, plan, review-isolation).

## Learned Workspace Facts

- Small fixes and review cleanups are done on `master` directly; feature branches used only for larger specs.
- Plan-driven specs live under `specs/<number>-<feature>/` (e.g. `specs/034-architecture-dedup-truth/`).
- `llm/reviews/*.md` — append-only historical evidence; recurring lessons уже перенесены в `docs/agents/ASYNC-LIFECYCLE.md` и machine gates.