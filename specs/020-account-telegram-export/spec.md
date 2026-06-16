# Спецификация: Telegram и export/import файлов аккаунта

**Ветка**: `020-account-telegram-export`  
**Дата**: 2026-06-03  
**Статус**: 🟢 Частично закрыт — Telegram ✅ в [013](../013-account-settings/spec.md); US3/US4 export/import перенесены в [029-account-data-export-import](../029-account-data-export-import/spec.md) (локально, без бекенда)
**Зависимости**: `013-account-settings` (вкладка Profile готова), `010-recipe-import` (import pipeline)  
**Эталон**: `/account` page (export/import), PRD § Export

## Контекст

**Telegram (US1–US2) закрыт в 013** — `TelegramConnectionView`, `TelegramAPI` (connect, poll status, disconnect), i18n `telegram.*`.

**Не закрыто** (перенесено в [029](../029-account-data-export-import/spec.md)):

- ~~US3 export всех данных (v1.3 zip/json)~~ → 029 US1
- ~~US4 import файла `.json/.zip`~~ → 029 US2

## Цель

Паритет мобильного account: подключение Telegram и выгрузка/загрузка пользовательских данных файлами.

## Пользовательские сценарии

### US1 — Telegram connect (P3)

**Закрыто в 013** — см. `TelegramConnectionView`.

### US2 — Telegram disconnect (P3)

**Закрыто в 013**.

### US3 — Export всех данных (P2)

**Перенесено в [029-account-data-export-import](../029-account-data-export-import/spec.md) US1** — реализуется локально из Y.Doc, без бекенда, формат v1.4.

### US4 — Import файла (P2)

**Перенесено в [029-account-data-export-import](../029-account-data-export-import/spec.md) US2** — локальный импорт v1.0–v1.4 через Y.Doc, без серверного pipeline.

### US5 — Офлайн / безопасность (P2)

Кнопки недоступны офлайн с i18n; не логировать чувствительные данные; pasteboard только по явному действию.

## Требования

### FR-020-001 — Telegram API

**Done (013)** — `TelegramAPI`: connect / status poll / disconnect.

### FR-020-002 — Export

**Перенесено в 029** — локальный экспорт из Y.Doc (v1.4 JSON/ZIP), без бекенд-эндпоинта.

### FR-020-003 — Import file

**Перенесено в 029** — локальный импорт v1.0–v1.4 через Y.Doc, без серверного pipeline.

### FR-020-004 — i18n

**Перенесено в 029** — ключи `account.data.*`.

## Вне scope

- PDF cookbook
- OAuth

## Критерии успеха

- **SC-001**: Connect Telegram → ✅ (013).
- **SC-002**: Export → перенесено в 029 SC-001.
- **SC-003**: Import → перенесено в 029 SC-002.
- **SC-004**: Офлайн — операции недоступны с i18n → перенесено в 029 SC-003.

## Артефакты

- `contracts/account-api.md` (Telegram + export/import)
- `quickstart.md`
