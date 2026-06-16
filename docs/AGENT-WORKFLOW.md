# Процесс агента

## Agent loop (чинить до зелёного)

Для задач «почини», «доделай», «пока не работает» — **сначала прочитай и выполни** skill `.agents/skills/fix-until-green/SKILL.md` (триггеры: `/fix-until-green`, «дочини», «пока не заработает»).

Кратко:

1. **Claim** — одна проверяемая формулировка: условие + как измерить + порог (не «стало лучше»).
2. **Цикл** (до 5 итераций): правка → проверка агентом → при провале снова правка. **Не** писать «готово», пока claim не подтверждён локально.
3. **Проверки** (по возрастанию, что реально доступно в сессии):
   - обязательно: `rtk xcodebuild … build` (см. ниже);
   - если есть тест под область: `rtk xcodebuild … test` с нужным `-only-testing:…`;
   - если уже есть `scripts/verify-<feature>.sh` под эту фичу — запустить (готовый shortcut, **новый скрипт не обязателен**);
   - баг без автотеста: `/debug` + логи симулятора (`bash scripts/pull-app-logs.sh` → `.debug-session.ndjson`) или XCTest, не «проверь на телефоне».
4. **Вердикт** в конце: `VERIFIED` / `NOT VERIFIED` / `INCONCLUSIVE` + одна строка evidence (команда, exit code, метрика).
5. **Физический iPhone** — агент не может замкнуть UI-loop без тебя; для UX-багов приоритет — симулятор или XCTest.

Отдельные skills: `debug` (root cause по логам), `verify-this` (оформление claim/evidence), `check-work` (опциональный второй проход по diff).

## Сборка после правок

После изменений в Swift/Xcode **агент обязан сам прогнать сборку** и убедиться, что проект компилируется, прежде чем считать задачу выполненной. Не проси пользователя проверить compile, если сборку можно запустить локально.

```bash
rtk xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  build
```

`<UDID>` — из `xcrun simctl list devices available` (например iPhone 16, OS 18.6). Имя без OS часто не резолвится — предпочитай `id=`. При ошибках — исправить и пересобрать. После build — проверки из раздела «Agent loop» (тесты / существующий `scripts/verify-*.sh`, если есть).

## Shell и RTK

Прочитай и выполняй [RTK.md](RTK.md). Prefix shell commands with `rtk` when filtering output (see `CLAUDE.md` / `RTK.md`).

## Проверка фич

- Feature verification scripts: `scripts/verify-<feature>.sh` и `scripts/verify-all.sh`.

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
