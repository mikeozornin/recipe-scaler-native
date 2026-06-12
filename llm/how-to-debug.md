# Отладка native iOS: журналирование для агента и человека

Краткий гайд: как включать NDJSON-логи, куда они пишутся, и почему **не** стоит слать их на `127.0.0.1` с физического iPhone.

## Принцип

1. **Один формат** — NDJSON (одна строка = один JSON-объект).
2. **Один файл в sandbox** — `Library/Application Support/debug-session.ndjson` (и симулятор, и телефон).
3. **Включение явное** — по умолчанию логи выключены (`AgentDebugLogging.isEnabled == false`).
4. **Доставка наружу** — копирование файла из sandbox (симулятор: скрипт; телефон: Xcode console или Download Container). Не HTTP на localhost с устройства.

## Почему не `127.0.0.1` / Cursor ingest с телефона

| Среда | Куда резолвится `127.0.0.1` |
|-------|------------------------------|
| Симулятор | Mac (часто работает ingest на Mac) |
| Физический iPhone | **Сам телефон** — ingest на Mac недоступен |

Если симулятор шлёт POST на `http://127.0.0.1:7868/...`, а телефон — в файл (или никуда), агент получает **разные** картины. Для parity используйте **файл + pull**, а не сетевой ingest.

Опциональный `CURSOR_DEBUG_INGEST_URL` в `CursorDebugIngestLog` — только если осознанно настраиваете (например, симулятор + ingest на Mac). Для телефона ingest **не использовать**.

## Классы (DEBUG-сборки)

| Класс | Назначение |
|-------|------------|
| `AgentDebugLogging` | Главный выключатель и env-переменные |
| `AgentSyncDebugLog` | Основной NDJSON: sync, общие trace; `AgentSyncDebugLog.sync(...)` помечает `topic: sync` |
| `DebugSessionNDJSONLog` | Gesture / description editor (`topic: gesture`) |
| `CursorDebugIngestLog` | Обёртка + опциональный Cursor ingest (обычно не нужен) |

Все `write()` — no-op, пока не включено журналирование.

### Включить логи

Xcode → Scheme → Run → Arguments → Environment Variables:

```
AGENT_DEBUG_LOG_ENABLED = 1
```

Опционально (редко):

```
CURSOR_DEBUG_SESSION_ID = my-session-id
CURSOR_DEBUG_INGEST_URL = http://<LAN-IP-Mac>:7868/ingest/...   # только симулятор / осознанный кейс
```

Пересоберите и перезапустите приложение после смены env.

## Куда пишется файл

Путь в коде: `AgentSyncDebugLog` → `sessionLogURL`.

По умолчанию:

```
<App Sandbox>/Library/Application Support/debug-session.ndjson
```

Переопределение (в основном **симулятор**, launch через `simctl`):

```
AGENT_DEBUG_LOG=/absolute/path/to/.debug-session.ndjson
# или при launch:
SIMCTL_CHILD_AGENT_DEBUG_LOG=/absolute/path/to/.debug-session.ndjson
```

`SIMCTL_CHILD_*` пробрасывается в процесс приложения на симуляторе — файл сразу на Mac. На **физическом устройстве** запись на путь Mac **невозможна**; остаётся sandbox + console/container.

Параллельно каждая строка дублируется в **OSLog** (`subsystem: com.recipescaler.native`, category `AgentSyncDebug`). В Xcode console фильтр: `[sync]` или `AgentSyncDebug`.

## Формат строки NDJSON

```json
{
  "sessionId": "sync-connection-native",
  "location": "YjsSyncService.swift:sendDebouncedUpdate",
  "message": "update_dispatched",
  "hypothesisId": "H",
  "timestamp": 1781263605972,
  "data": {
    "recipeId": "…",
    "bytes": "26",
    "topic": "sync"
  }
}
```

Поля `data` — только `[String: String]`. Без секретов, токенов, PII.

## Как добавить лог в код

```swift
// #region agent log
AgentSyncDebugLog.write(
    hypothesisId: "H2",
    location: "MyType.swift:myFunction",
    message: "short_event_name",
    data: [
        "recipeId": recipeId,
        "bytes": String(update.count),
    ]
)
// #endregion
```

Для Socket.IO / sync:

```swift
AgentSyncDebugLog.sync(
    location: "YjsSyncService.swift:handleDocumentLoaded",
    message: "document_loaded",
    data: ["recipeId": recipeId, "stateBytes": String(stateData.count)]
)
```

Правила:

- Оборачивать в `// #region agent log` … `// #endregion` (сворачивается в IDE).
- `hypothesisId` — буква/код гипотезы при отладке бага.
- `message` — стабильное имя события (grep по логам).
- Не логировать пароли, seed phrase, токены.

WKWebView (JS): не использовать `fetch('http://127.0.0.1/...')`. Если нужен trace из bridge — `postMessage` в Swift и `AgentSyncDebugLog.write` на стороне native.

## Снять лог: симулятор

### Вариант A — скрипты verify (рекомендуется)

```bash
source scripts/sim-verify-lib.sh
export AGENT_DEBUG_LOG_ENABLED=1   # задать в scheme; здесь только pull
sim_build && sim_install
sim_launch
# … воспроизведение …
sim_pull_debug_log    # → $ROOT/.debug-session.ndjson
```

Или готовый сценарий:

```bash
./scripts/debug-recipe-detail.sh
```

### Вариант B — прямой pull

```bash
CONTAINER=$(xcrun simctl get_app_container booted ru.recipescaler.RecipeScalerNative data)
cp "$CONTAINER/Library/Application Support/debug-session.ndjson" .debug-session.ndjson
```

### Вариант C — запись сразу в репозиторий (только sim)

```bash
export SIMCTL_CHILD_AGENT_DEBUG_LOG="$PWD/.debug-session.ndjson"
xcrun simctl launch booted ru.recipescaler.RecipeScalerNative
```

Перед прогоном: `rm -f .debug-session.ndjson`.

## Снять лог: физический iPhone

1. **Xcode console** — Run на устройстве, фильтр `[sync]` или `recipe_updated`. Удобно для быстрой проверки; для агента лучше файл.
2. **Файл из sandbox** — Window → Devices and Simulators → устройство → Installed Apps → RecipeScalerNative → **Download Container…**  
   Путь внутри контейнера:
   ```
   AppData/Library/Application Support/debug-session.ndjson
   ```
3. Сохранить как `console-sync-N.txt` или `.debug-session.ndjson` в корень репозитория для анализа агентом.

Не ожидайте, что ingest на Mac или `AGENT_DEBUG_LOG` с путём Mac сработает на телефоне.

## Workflow для агента (/debug)

1. Сформулировать 3–5 гипотез с `hypothesisId`.
2. Включить `AGENT_DEBUG_LOG_ENABLED=1`, добавить `write` у ключевых точек.
3. Очистить старый лог (`rm .debug-session.ndjson` или `sim_launch` в скрипте).
4. Воспроизвести баг (симулятор и/или телефон).
5. Снять **один** NDJSON-файл тем же способом для обеих сред.
6. Разобрать строки: CONFIRMED / REJECTED по `hypothesisId`.
7. Чинить только подтверждённое; instrumentation не снимать до верификации.
8. После фикса — выключить `AGENT_DEBUG_LOG_ENABLED` (или оставить `0` по умолчанию).

Skill: `.agents/skills/fix-until-green/SKILL.md`, `.claude/skills/debug/SKILL.md`.

## Release-сборки

`#if DEBUG` + `AgentDebugLogging.isEnabled` — в Release логи не пишутся. Для TestFlight/App Store отдельного NDJSON-трейса нет.

## Чеклист «сделал правильно»

- [ ] `AGENT_DEBUG_LOG_ENABLED=1` в scheme, перезапуск после смены
- [ ] Нет `fetch`/ingest на `127.0.0.1` в JS на устройстве
- [ ] Симулятор и телефон: одинаковый приёмник — `debug-session.ndjson` в sandbox
- [ ] Агент читает файл или console dump, а не «ожидает ingest на Mac» с телефона
- [ ] Гипотезы помечены `hypothesisId` в `data` / корне JSON
- [ ] После отладки логи можно оставить в коде (выключены по умолчанию)

## Связанные файлы

| Файл | Роль |
|------|------|
| `RecipeScalerNative/Utils/AgentDebugLogging.swift` | Выключатель |
| `RecipeScalerNative/Utils/AgentSyncDebugLog.swift` | Запись NDJSON + OSLog |
| `RecipeScalerNative/Utils/CursorDebugIngestLog.swift` | Обёртка (ingest опционален) |
| `RecipeScalerNative/Utils/DebugSessionNDJSONLog.swift` | Gesture/editor |
| `scripts/sim-verify-lib.sh` | `sim_pull_debug_log`, launch helpers |
| `scripts/debug-recipe-detail.sh` | Пример с `SIMCTL_CHILD_AGENT_DEBUG_LOG` |
