# Отладка native iOS: журналирование для агента и человека

Краткий гайд: как работает NDJSON-журнал, куда он пишется, и почему **не** стоит слать логи на `127.0.0.1` с физического iPhone.

## Для агента (quickstart)

1. **Собрать и запустить** (DEBUG): `source scripts/sim-verify-lib.sh && sim_build && sim_install && sim_launch`
2. **Воспроизвести** баг в симуляторе
3. **Забрать лог:** `bash scripts/pull-app-logs.sh` → читать `.debug-session.ndjson`
4. **Искать:** `rg '"message":"…"' .debug-session.ndjson` или `rg '"category":"sync"' .debug-session.ndjson`
5. **Добавить trace:** `AppLog.info(.sync, "event", data: [:])` или `AgentSyncDebugLog.sync(location:message:data:)`

См. также: `docs/AGENT-WORKFLOW.md` §Отладка, `AGENTS.md` §Журналирование.

## Принцип

1. **Один формат** — NDJSON (одна строка = один JSON-объект).
2. **Один файл в sandbox** — `Library/Application Support/debug-session.ndjson` (симулятор и телефон).
3. **DEBUG-сборка** — журнал в файл включён по умолчанию; opt-out: `AGENT_DEBUG_LOG_DISABLED=1`.
4. **Доставка наружу** — pull из симулятора (`scripts/pull-app-logs.sh`) или share sheet в профиле (телефон).

## Единая точка входа: `AppLog`

| API | Назначение |
|-----|------------|
| `AppLog.debug/info/notice/error/fault(_:message:data:)` | Обычное журналирование с категорией (`sync`, `document`, `database`, …) |
| `AppLog.agent(hypothesisId:location:message:data:)` | Agent/debug trace (совместим со старым `AgentSyncDebugLog`) |
| `AppLog.currentLogFileURL()` | Путь к файлу для экспорта (nil в Release или если файла нет) |

Все записи зеркалируются в **OSLog** (`subsystem: com.recipescaler.native`). В DEBUG дополнительно пишутся в NDJSON-файл.

### Совместимые обёртки (deprecated, не удалять)

| Класс | Назначение |
|-------|------------|
| `AgentDebugLogging` | Выключатель (`isEnabled` → `AppLog.isFileLoggingEnabled`) |
| `AgentSyncDebugLog` | Sync/agent trace → `AppLog.agent` |
| `DebugSessionNDJSONLog` | Gesture / description editor |
| `CursorDebugIngestLog` | + опциональный Cursor ingest (только симулятор) |

## Почему не `127.0.0.1` / Cursor ingest с телефона

| Среда | Куда резолвится `127.0.0.1` |
|-------|------------------------------|
| Симулятор | Mac (ingest иногда работает) |
| Физический iPhone | **Сам телефон** — ingest на Mac недоступен |

Для parity используйте **файл + pull**, а не сетевой ingest.

## Включить / выключить журнал в файл

По умолчанию в DEBUG журнал **включён**. Выключить (редко, например чистый verify-прогон):

```
AGENT_DEBUG_LOG_DISABLED = 1
```

Опционально Cursor ingest (только симулятор):

```
CURSOR_DEBUG_SESSION_ID = my-session-id
CURSOR_DEBUG_INGEST_URL = http://<LAN-IP-Mac>:7868/ingest/...
```

## Куда пишется файл

```
<App Sandbox>/Library/Application Support/debug-session.ndjson
```

Ротация: ≤ 5 МБ текущий файл + архивы `.1`–`.3`.

Переопределение пути (симулятор):

```
AGENT_DEBUG_LOG=/absolute/path/to/.debug-session.ndjson
SIMCTL_CHILD_AGENT_DEBUG_LOG=/absolute/path/to/.debug-session.ndjson
```

## Формат строки NDJSON

```json
{
  "sessionId": "sync-connection-native",
  "location": "YjsSyncService.swift:123",
  "message": "document_loaded",
  "hypothesisId": "sync",
  "timestamp": 1781263605972,
  "data": {
    "category": "sync",
    "level": "info",
    "recipeId": "…"
  }
}
```

Поля `data` — только `[String: String]`. Без секретов, токенов, PII.

## Как добавить лог в код

```swift
AppLog.info(.sync, "document_loaded", data: ["recipeId": recipeId])
```

Agent/debug trace (старый стиль):

```swift
// #region agent log
AgentSyncDebugLog.sync(
    location: "YjsSyncService.swift:handleDocumentLoaded",
    message: "document_loaded",
    data: ["recipeId": recipeId]
)
// #endregion
```

## Снять лог: симулятор (агент)

### One-shot (рекомендуется)

```bash
bash scripts/pull-app-logs.sh
# печатает путь к $ROOT/.debug-session.ndjson
```

### Через verify-скрипты

```bash
source scripts/sim-verify-lib.sh
sim_build && sim_install
sim_launch
# … воспроизведение …
sim_pull_debug_log
```

### Прямой pull

```bash
CONTAINER=$(xcrun simctl get_app_container booted ru.recipescaler.RecipeScalerNative data)
cp "$CONTAINER/Library/Application Support/debug-session.ndjson" .debug-session.ndjson
```

## Снять лог: физический iPhone

1. **Профиль → Диагностика → Экспорт журнала** (DEBUG-сборка, файл уже создан).
2. **Xcode console** — фильтр по категории `sync`, `document`, …
3. **Download Container** — `AppData/Library/Application Support/debug-session.ndjson`

В Release-сборке файла нет — в профиле показывается сообщение «Файл журнала недоступен».

## Release-сборки

Запись в файл отключена (`#if DEBUG`). OSLog остаётся. Экспорт в профиле показывает понятное сообщение об отсутствии файла.

## Связанные файлы

| Файл | Роль |
|------|------|
| `RecipeScalerNative/Utils/AppLog.swift` | Единый фасад |
| `RecipeScalerNative/Utils/AgentDebugLogging.swift` | Выключатель |
| `RecipeScalerNative/Utils/AgentSyncDebugLog.swift` | Совместимость sync/agent |
| `scripts/pull-app-logs.sh` | One-shot pull для агента |
| `scripts/sim-verify-lib.sh` | `sim_pull_debug_log`, launch helpers |
| `RecipeScalerNative/Views/AccountView.swift` | Экспорт журнала из профиля |
