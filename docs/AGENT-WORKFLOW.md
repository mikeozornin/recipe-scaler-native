# Процесс агента

## Agent loop (чинить до зелёного)

Для задач «почини», «доделай», «пока не работает» — **сначала прочитай и выполни** skill `.agents/skills/fix-until-green/SKILL.md` (триггеры: `/fix-until-green`, «дочини», «пока не заработает»).

Кратко:

1. **Claim** — одна проверяемая формулировка: условие + как измерить + порог (не «стало лучше»).
2. **Цикл** (до 5 итераций): правка → проверка агентом → при провале снова правка. **Не** писать «готово», пока claim не подтверждён локально.
3. **Проверки** (по возрастанию, что реально доступно в сессии):
   - обязательно: `xcodebuild … build` (см. ниже);
   - если есть тест под область: `xcodebuild … test` или `xcodebuild … test-without-building`;
   - если уже есть `scripts/verify-<feature>.sh` под эту фичу — запустить (готовый shortcut, **новый скрипт не обязателен**);
   - баг без автотеста: `/debug` + логи симулятора (`bash scripts/pull-app-logs.sh` → `.debug-session.ndjson`) или XCTest, не «проверь на телефоне».
4. **Вердикт** в конце: `VERIFIED` / `NOT VERIFIED` / `INCONCLUSIVE` + одна строка evidence (команда, exit code, метрика).
5. **Физический iPhone** — агент не может замкнуть UI-loop без тебя; для UX-багов приоритет — симулятор или XCTest.

Отдельные skills: `debug` (root cause по логам), `verify-this` (оформление claim/evidence), `check-work` (опциональный второй проход по diff).

Принципы тестирования (positive invariants, downstream consumers, DEBUG/edge-cases, postmortem) — см. [TESTING.md](./TESTING.md).

## Сборка после правок

После изменений в Swift/Xcode **агент обязан сам прогнать сборку** и убедиться, что проект компилируется, прежде чем считать задачу выполненной. Не проси пользователя проверить compile, если сборку можно запустить локально.

```bash
xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  build
```

`<UDID>` — из `xcrun simctl list devices available` (например iPhone 16, OS 18.6). Имя без OS часто не резолвится — предпочитай `id=`. При ошибках — исправить и пересобрать. После build — проверки из раздела «Agent loop» (тесты / существующий `scripts/verify-*.sh`, если есть).

## XCTest

```bash
xcodebuild build-for-testing -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'

xcodebuild test-without-building -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -only-testing:RecipeScalerNativeTests/MyTests
```

Паттерн build-for-testing + test-without-building — в `scripts/verify-third-party-import.sh`.

**Быстрый gate для PR / агента** — один build + все unit-тесты (без UI), с лимитом 30 с на кейс:

```bash
bash scripts/test-fast.sh
```

Полный simulator parity-прогон (14 verify-скриптов, один shared build):

```bash
bash scripts/verify-all.sh
```

Перед `verify-all` можно отдельно прогнать только сборку: `bash scripts/build-for-verify.sh`.

**Парный iPhone + Apple Watch** (WatchConnectivity / companion):

```bash
bash scripts/run-dual-simulators.sh
bash scripts/run-dual-simulators.sh -SkipSplash=1
SKIP_BUILD=1 bash scripts/run-dual-simulators.sh   # без пересборки
PHONE_SIM_NAME="iPhone 17 + Watch" bash scripts/run-dual-simulators.sh
```

Если линковка watch падает с `missing required architecture x86_64` / `RecipeScalerCore.tbd`:

```bash
bash scripts/xcode-clean-watch-tbd.sh
# или полная пересборка через run-dual-simulators (очистка встроена в sim_ensure_built)
bash scripts/run-dual-simulators.sh
```

Скрипт ищет пару через `simctl list pairs`, собирает `RecipeScalerNative` (watch embedded в `Watch/`), ставит iPhone `.app` и companion `Watch/RecipeScalerNativeWatch.app`, запускает сначала телефон, затем часы.

## Проверка фич

- Feature verification scripts: `scripts/verify-<feature>.sh` и `scripts/verify-all.sh`.
- **UI smoke (после правок view / navigation):** `bash scripts/verify-ui-smoke.sh` — обходит основные табы, ловит crash / main-thread hang / empty-state flicker. Не заменяет per-feature verify-*.sh, а закрывает дыру между ними.
- **i18n lint (после правок view или новых экранов):** `bash scripts/lint-i18n.sh` — детектор хардкода UI-строк в Swift. Расширение `verify-translations.sh` на `Views/`, `Screens/`, `Widgets/` и т.п.

## Планы Spec Kit

При написании `specs/<feature>/plan.md` используй шаблон [`specs/_template/plan.md`](../specs/_template/plan.md). Шаблон требует:

- **Downstream consumers** — список всех, кто читает изменяемое состояние или вызывает меняемый API (views, widgets, extensions, sync, persisted state, tests). Класс регрессий MIK-187: функция делает две вещи, одну забыли — план без этой секции пропускает такие баги.
- **Positive invariants** — для каждого observable-эффекта хотя бы один положительный инвариант для теста. Не «не должно сломаться», а «должно произойти X».

## UI по макетам (Figma)

Если в spec есть Figma frames / pixel-perfect UI — см. [UI-LAYOUT-FROM-FIGMA.md](./UI-LAYOUT-FROM-FIGMA.md).

**До tasks на view:**

1. `specs/<feature>/layout.md` — дерево вёрстки, токены, матрица состояний, falsifiable claims (**ревью человеком**).
2. `specs/<feature>/layout-audit.json` — проверки для скрипта.

**В agent loop (после layout-правок):**

```bash
bash scripts/audit-ui-layout.sh specs/<feature>
```

**Порядок субагентов для UI-фич** (после зелёного build + audit):

1. **layout-reviewer** — код ↔ `layout.md` (дерево, размеры, platform constraints).
2. **fix-until-green** — claim из `layout.md`, не «выглядит ок».

Шаблоны: `specs/_template/layout.md`, `specs/_template/layout-audit.json`. Эталон: `specs/030-timer-widget/`.

## Отладка

- Run builds, simulator checks, and reproduction steps yourself when possible — do not ask the user to verify what the agent can run locally.
- For bugs, find root cause from logs/crash reports first (`/debug`); avoid speculative fixes.
- **Журналирование:** читай [llm/how-to-debug.md](../llm/how-to-debug.md) перед добавлением trace или разбором бага.

### Журнал приложения (AppLog)

| Что | Где |
|-----|-----|
| Фасад | `RecipeScalerNative/Utils/AppLog.swift` |
| NDJSON-файл (DEBUG) | `<sandbox>/Library/Application Support/debug-session.ndjson` |
| Pull из симулятора | `bash scripts/pull-app-logs.sh` → печатает путь к `.debug-session.ndjson` |
| Pull в verify-скриптах | `source scripts/sim-verify-lib.sh` → `sim_pull_debug_log` |
| Экспорт с телефона | Профиль → Диагностика → «Экспорт журнала» (DEBUG) |
| Выключить файл | env `AGENT_DEBUG_LOG_DISABLED=1` (редко) |
| Release | файла нет; OSLog остаётся; в профиле — сообщение «журнал недоступен» |

**Типичный цикл агента:**

```bash
# 1. Собрать и запустить (sim_launch чистит старый лог)
source scripts/sim-verify-lib.sh
sim_build && sim_prepare && sim_install && sim_launch -SkipSplash=1
# … воспроизвести баг …
# 2. Забрать лог
bash scripts/pull-app-logs.sh
# 3. Grep по message / category / hypothesisId
rg '"message":"sync_error"' .debug-session.ndjson
rg '"category":"sync"' .debug-session.ndjson | tail -20
```

**Добавить лог в код:** `AppLog.info(.sync, "event", data: ["recipeId": id])`. Agent-trace (гипотезы): `AgentSyncDebugLog.sync(location:message:data:)` — обёртка над `AppLog.agent`.

- Agent debug ingest to Mac `localhost` does not work on a physical iPhone — use file pull, Xcode console, or profile export (`127.0.0.1` on device is the device itself).
