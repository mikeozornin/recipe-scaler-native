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

Симулятор выбирай через `scripts/resolve-simulator.sh` (или явный `SIM_ID=`).
Не хардкодь UDID машины в скриптах/доках как единственный путь. В worktree задачи (см.
[AGENTS.md](../AGENTS.md), «Параллельная работа») резолвер отдаёт её собственный `RS-<name>`, а
быстрый цикл «собрать, поставить, запустить» — `bash scripts/wt.sh run [--ipad] [-SkipSplash=1]`.

```bash
SIM_ID="$(bash scripts/resolve-simulator.sh)"
xcodebuild -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  build
```

Имя без OS часто не резолвится — предпочитай `id=`. **Запрещено** `OS=18.x` /
`name=iPhone 16…` без `id=`: Xcode скачает рантаймы 18.4/18.6 заново. При ошибках —
исправить и пересобрать. После build — проверки из раздела «Agent loop» (тесты /
существующий `scripts/verify-*.sh`, если есть). Контракт verify-скриптов —
[agents/VERIFICATION.md](./agents/VERIFICATION.md).

Быстрые policy-gates без симулятора: `bash scripts/policy-check.sh`.

## XCTest

```bash
SIM_ID="$(bash scripts/resolve-simulator.sh)"
xcodebuild build-for-testing -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID"

xcodebuild test-without-building -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -only-testing:RecipeScalerNativeTests/MyTests
```

Паттерн build-for-testing + test-without-building — в `scripts/verify-third-party-import.sh`.

### iPad (spec 081)

iPad-симулятор выбирает `scripts/resolve-ipad-simulator.sh` (пара к `resolve-simulator.sh`):
`IPAD_SIM_ID=<udid>` побеждает, иначе «iPad Pro 11-inch (M4)» → «iPad Air 11-inch» → любой iPad,
свежий runtime, уже загруженный; в worktree задачи — её `RS-<name>-ipad`. Симуляторы `Scrapp…` и
чужие `RS-…` скрипт не берёт. Им пользуются все iPad-скрипты ниже.

```bash
IPAD_ID="$(bash scripts/resolve-ipad-simulator.sh)"
bash scripts/verify-ipad-layout.sh --list-states          # имена состояний
bash scripts/verify-ipad-layout.sh                        # все состояния на iPad → tmp/ipad-verify/
bash scripts/verify-ipad-layout.sh --skip-build --only recipes-sidebar,assistant-chat
IPAD_VERIFY_LANGUAGE=en bash scripts/verify-ipad-layout.sh --skip-build   # английский интерфейс (по умолчанию ru)
bash scripts/verify-ipad-layout.sh --iphone-regression    # iPhone: попиксельно с базой, FAILED при любом отличии
```

iPad-режим только снимает кадры (`CHECKED`): раскладку сверяешь глазами с `specs/081-ipad-adaptation/layout.md`.
`--iphone-regression` сравнивает те же состояния на iPhone с базой `tmp/ipad-verify/iphone-baseline/`
(снимается `--capture-baseline` на коде без Swift-правок spec 081). Данные — shared DEBUG-юзер на
prod, `-ScreenshotCapture=1` удаляет его активные таймеры; подробности в шапке скрипта.
`--matrix` запускает `scripts/verify-ipad-matrix.sh` (ширины многозадачности, см. ниже). iPad-кадры
App Store снимает `capture-app-store-screenshots.sh --device ipad-13`, см. `store/README.md`.

UI-спеки iPad, которые проверяют программную клавиатуру (`IPadRecipesSpec`), гоняй с открытым
Simulator.app на этом iPad, отключённой аппаратной клавиатурой
(`defaults read com.apple.iphonesimulator ConnectHardwareKeyboard` → 0) и выключенной
автоматической минимизацией клавиатуры в самом симуляторе:

```bash
xcrun simctl spawn <udid iPad> defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled
xcrun simctl spawn <udid iPad> defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool NO
```

Симулятор должен быть загружен; ключ действует со следующего запуска приложения, перезагрузка не
нужна. `typeText` шлёт аппаратные нажатия, и при включённой минимизации iPadOS после них может
свернуть клавиатуру до панели быстрых команд: следующее поле получает только её, `app.keyboards`
пуст («No software keyboard»), а в логе приложения (`xcrun simctl spawn <udid> log show --predicate
'eventMessage CONTAINS "Setting keyboard minimized"'`) видно `Setting keyboard minimized = 1`.

Минимизацию включают аппаратные нажатия `IPadKeyboardSpec` (`typeKey` и `axe key-combo` из
`verify-ipad-keyboard.sh`): iPadOS запоминает аппаратную клавиатуру (`HardwareKeyboardLastSeen`) и
ставит `AutomaticMinimizationEnabled = 1`. Сворачивает UIKit, только если считает аппаратную
клавиатуру подключённой. Это состояние запущенного симулятора, его меняют нажатия, поэтому с ключом 1
спека то падает, то проходит, даже без перезагрузки. `verify-ipad-keyboard.sh` возвращает оба ключа
как были. После `IPadKeyboardSpec` прямо через `xcodebuild` или на симуляторе, где её гоняли до
этого, выключи минимизацию командой выше. Код приложения тут ни при чём: на устройстве без
аппаратной клавиатуры клавиатура в шагах есть. Окно симулятора держи видимым: под чужими окнами
`testEditTwoColumns` проходил, но ждал анимаций по минуте и шёл 19 минут вместо двух.

`IPadKeyboardSpec` (шорткаты iPad, spec 081 US6) окно Simulator.app не нужно, `ConnectHardwareKeyboard`
любой: `typeKey` шлёт аппаратные события. Ограничения `typeKey` на симуляторе iPadOS 26.3:

- первое событие после запуска может потеряться — тесты сначала жмут свободный ⌘K;
- ⌘↩ и ⌘⌫ (любой шорткат с Return, `.delete` или `"\u{8}"`) до приложения не доходят, а те же
  клавиши HID-событиями (`axe key-combo`) доходят;
- `typeKey("+", .command)` добавляет ⇧, поэтому ⌘+ жмётся как ⌘=.

Поэтому ⌘↩ и ⌘⌫ проверяет `testHostKeys`: без хоста он пропускается, а с ним спеку гоняет

```bash
bash scripts/verify-ipad-keyboard.sh               # build-for-testing + вся IPadKeyboardSpec
bash scripts/verify-ipad-keyboard.sh --skip-build --only testHostKeys
```

Скрипту нужны AXe (`brew install cameroncooke/axe/axe`) и локальный бэкенд на 127.0.0.1:3001. Тест
печатает `IPAD_KEYBOARD_HOST_KEY <n> <combo>`, скрипт шлёт клавишу в симулятор, тест проверяет
результат. Пока скрипт идёт, не печатай на Mac. Логи — `tmp/ipad-keyboard/`.

`IPadMultitaskingSpec` (одно окно на ширинах многозадачности, spec 081 US7) меняет ширину корня
приложения на лету (`-DebugWindowWidthLive=1`, Darwin-уведомление из теста) и проверяет раскладку,
открытый рецепт и коллекцию на каждой ширине. Скриншоты снимает хост:

```bash
bash scripts/verify-ipad-layout.sh --matrix                 # build-for-testing + вся спека
bash scripts/verify-ipad-layout.sh --matrix --skip-build --only testAssistantWidthsLandscape
IPAD_SIM_ID=<udid 13″> bash scripts/verify-ipad-layout.sh --matrix --skip-build
```

Нужен локальный бэкенд на 127.0.0.1:3001. Скриншоты и таблица `matrix.txt` — в
`tmp/ipad-verify/us7/<устройство>/`, логи — в `tmp/ipad-verify/us7/`. Настоящие Split View,
Slide Over и Stage Manager симулятор не скриптует: они остаются ручной проверкой на устройстве.
На iPad-симуляторе ниже iPadOS 26.2 (`IPAD_SIM_ID=…`) та же спека проходит старую оболочку
(системный таб-бар, без сайдбара). Рантаймы симулятора iOS 18.4/18.5 приложение не запускают:
dyld не находит `/usr/lib/swift/libswiftWebKit.dylib` (баг рантайма, WebKit 293831), так что
старую оболочку проверяет владелец на устройстве. Спека идёт около 15 минут на экран. Mac не должен
засыпать: на батарее он уходит в сон обслуживания даже под `caffeinate -i`, и xcodebuild встаёт.

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
