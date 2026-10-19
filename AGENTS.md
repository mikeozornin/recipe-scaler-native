# AGENTS.md — контекст для coding agents

> Router. Длинные правила живут в специализированных документах ниже; этот
> файл — точка входа, не справочник. Precedence: явный запрос пользователя →
> активная feature spec/plan → shared контракты → constitution → domain
> rules → workflow docs → decision history.

## Параллельная работа: worktree и симуляторы

С репозиторием одновременно работают несколько чатов агентов. У каждой задачи свой git worktree,
своя ветка и свои симуляторы; всем этим управляет `scripts/wt.sh`.

| Что | Где |
|-----|-----|
| Основная копия | `recipe-scaler-native/` на `master` — папка владельца |
| Папка задачи | `recipe-scaler-native-wt/<name>/` (рядом с `recipe-scaler-native/`) |
| Ветка | `feature/<name>` |
| Симуляторы | `RS-<name>` (iPhone 17 Pro), `RS-<name>-ipad` (iPad Pro 11″ M4) |
| Запуск | `bash scripts/wt.sh run [-SkipSplash=1]`, на iPad — `bash scripts/wt.sh run --ipad` |
| Список / удаление | `bash scripts/wt.sh ls`, `bash scripts/wt.sh rm <name>` |

- Если рабочая папка уже `recipe-scaler-native-wt/<name>/` — работай в ней.
- Если ты в основной копии и задача меняет код — `bash scripts/wt.sh new <name>` (короткое kebab-case
  имя, не на `-ipad`) и вся работа в новой папке. Незакоммиченные правки основной копии туда не
  попадают — скажи об этом, если задача от них зависит. Консультации и чтение кода — без worktree.
- Не правь, не собирай и не меняй git-состояние основной копии и чужих папок задач.
- Внутри worktree `scripts/resolve-simulator.sh` и `scripts/resolve-ipad-simulator.sh` сами отдают
  `RS-<name>` / `RS-<name>-ipad`, поэтому все `verify-*.sh`, `test-fast.sh` и команды из
  [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md) работают без правок. Чужие `RS-…` и `Scrapp…`
  они не выбирают никогда.
- Не ставь сборку на чужой симулятор или на дефолтный: у всех копий один bundle id
  (`ru.recipescaler.RecipeScaler`) и App Group, они перезапишут друг друга. Явный `SIM_ID=` /
  `IPAD_SIM_ID=` — только на свой симулятор.
- Пара iPhone + Watch (`run-dual-simulators.sh`) и App Store-скриншоты используют общие симуляторы —
  только по прямой просьбе и не параллельно с другим чатом.
- DerivedData у каждой копии своя (Xcode держит отдельную папку на путь проекта); `wt.sh rm` её
  удаляет. Сборка занимает несколько ГБ: `wt.sh` не собирает при < 8 ГБ свободного места —
  остановись и скажи пользователю, не удаляй ничего ради места.
- Релизы (`bump-build-number.sh`, TestFlight, ASC) — только из основной копии на `master`.

**Git.** Коммить свободно в свою `feature/<name>`. Перед сдачей — `git rebase master`. В `master`
мёржить только по просьбе пользователя; вызов `finish-thread` — это просьба. Конфликт в
`project.pbxproj` сводится руками с сохранением обеих сторон, затем build.
Чтобы закрыть чат — [.agents/skills/finish-thread/SKILL.md](.agents/skills/finish-thread/SKILL.md):
коммит, rebase на `master`, merge в `master`, удаление worktree, ветки, симуляторов и временных
файлов — без повторных вопросов.

## Установка на устройство

Глобальный скилл `install-on-device`, из папки задачи:

```bash
bun ~/.agents/skills/install-on-device/scripts/install.ts --scheme RecipeScalerNative-Dev \
  --configuration DebugDevice --derived-data tmp/device-build-dd --server https://recipe-scaler.ru
```

- По умолчанию — Mike-13; добавь `--device iPad` или `--device Mike-13,iPad`.
- `DebugDevice` — bundle `ru.recipescaler.RecipeScaler.debug` с дев-иконкой: встаёт рядом с App Store-версией
  (спека 066). `Debug` и `Release` ставят прод-ID поверх App Store-сборки — только по прямой просьбе.
- Сервер на устройстве всегда прод: `E2E_OVERRIDE_API_BASE` читается только из окружения запуска.
- Последнюю строку скрипта («На … стоит ветка@sha …») — в отчёт.

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
- **Side-by-side сборки (spec 066):** схема **RecipeScalerNative-Dev** = dev-иконка «RS Dev» (`ru.recipescaler.RecipeScaler.debug`) рядом с App Store версией; константы флейвора — `AppGroup.id` / `SharedAuthStore` / `DeepLinkURL.baseScheme` под `RS_DEV_FLAVOR`; портал-чеклист и ограничения — [docs/PAID-APPLE-DEVELOPER-REQUIRED.md](docs/PAID-APPLE-DEVELOPER-REQUIRED.md) §1.3.1.
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
from [specs/078-shake-open-assistant/plan.md](specs/078-shake-open-assistant/plan.md).
<!-- SPECKIT END -->

## Learned User Preferences

- All app text must use the project typeface (Martian), not the default SF — if a text block renders in the system font, it's a bug.
- For Figma-driven UI: write `layout.md` + `layout-audit.json` before SwiftUI views; human reviews `layout.md`; run `audit-ui-layout.sh` in the agent loop.
- Never use the `composer-fast` model for subagents — always use the primary model (composer-2.5).
- Commit/close Linear issue only on explicit «закрой задачу» or `/solve-issue` with commit authorization; otherwise stop after `VERIFIED`.
- Prefer plan-driven implementation: `specs/<feature>/spec.md` → `plan.md` → `tasks.md` → execute tasks sequentially **after** required human gates (layout, plan, review-isolation).

## Learned Workspace Facts

- Any task that changes code runs in its own worktree (`scripts/wt.sh new <name>`, branch `feature/<name>`) and is merged into `master` via `finish-thread`; the main checkout on `master` belongs to the owner.
- Plan-driven specs live under `specs/<number>-<feature>/` (e.g. `specs/034-architecture-dedup-truth/`).
- `llm/reviews/*.md` — append-only historical evidence; recurring lessons уже перенесены в `docs/agents/ASYNC-LIFECYCLE.md` и machine gates.