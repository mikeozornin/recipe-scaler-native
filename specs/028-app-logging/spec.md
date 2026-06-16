# Спецификация: единый журнал приложения (AppLog)

**Ветка**: `028-app-logging`  
**Дата**: 2026-06-16  
**Статус**: 🟢 Реализовано (2026-06-16)  
**Зависимости**: существующий `AgentSyncDebugLog` (NDJSON), `scripts/sim-verify-lib.sh` (`sim_pull_debug_log`)

## Контекст

Журналирование фрагментировано: `AgentSyncDebugLog` пишет NDJSON только при `AGENT_DEBUG_LOG_ENABLED=1` и только из Views/Utils; `Services/` используют `os.Logger` и `print()` — эти сообщения не попадают в файл журнала. Кнопка экспорта в профиле доступна только в `#if DEBUG` и скрывается без файла.

## Цель

Единый фасад `AppLog` для всего приложения: NDJSON-файл в DEBUG (симулятор и телефон), зеркалирование в `os.Logger` во всех конфигурациях, экспорт из профиля, автоматическое получение логов агентом из симулятора.

## Пользовательские сценарии

### US1 — Агент забирает логи из симулятора (P1)

**Когда** приложение запущено в симуляторе (DEBUG), **тогда** агент выполняет `scripts/pull-app-logs.sh` и получает NDJSON в корне репозитория.

### US2 — Экспорт с телефона (P1)

**Когда** пользователь открывает профиль в DEBUG-сборке и файл журнала существует, **тогда** кнопка «Экспорт журнала» открывает share sheet с `debug-session.ndjson`.

### US3 — Понятное сообщение при отсутствии журнала (P1)

**Когда** файла журнала нет (Release или ещё не было записей), **тогда** в профиле отображается неактивная строка с объяснением — без пустого экрана и без скрытой секции.

## Функциональные требования

- **FR-LOG-001**: `AppLog` — единая точка входа (`debug` / `info` / `notice` / `error` / `fault`) с категориями (`sync`, `document`, `database`, …).
- **FR-LOG-002**: В DEBUG запись в `Library/Application Support/debug-session.ndjson` (или override через `AGENT_DEBUG_LOG` / `SIMCTL_CHILD_AGENT_DEBUG_LOG`).
- **FR-LOG-003**: В Release запись в файл отключена; OSLog остаётся.
- **FR-LOG-004**: Ротация: ≤ 5 МБ текущий файл + до 3 архивов (`.1`–`.3`).
- **FR-LOG-005**: `AgentSyncDebugLog` / `DebugSessionNDJSONLog` / `CursorDebugIngestLog` — тонкие обёртки над `AppLog` (обратная совместимость).
- **FR-LOG-006**: В DEBUG журнал включён по умолчанию; opt-out через `AGENT_DEBUG_LOG_DISABLED=1`.
- **FR-LOG-007**: Секция экспорта в `AccountView` всегда видна; i18n-ключи в `Localizable.xcstrings`.
- **FR-LOG-008**: `scripts/pull-app-logs.sh` — one-shot для агента.

## Вне области

- Crash logs (MetricKit / Crashlytics)
- Логи сторонних библиотек (yrs, Socket.IO)
- Серверное журналирование

## Критерии приёмки

1. DEBUG + симулятор: после запуска файл содержит строки с `category` из Services.
2. `bash scripts/pull-app-logs.sh` → exit 0, путь к NDJSON.
3. DEBUG + телефон: экспорт через share sheet.
4. Release: строка «журнал недоступен» без краша.
5. Ротация при > 5 МБ.
6. Сборка и `AppLogTests` зелёные.
