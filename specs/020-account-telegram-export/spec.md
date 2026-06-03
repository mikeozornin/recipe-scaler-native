# Спецификация: Telegram и export/import файлов аккаунта

**Ветка**: `020-account-telegram-export`  
**Дата**: 2026-06-03  
**Статус**: Draft (перенос недоделок из 013, связь с 010)  
**Зависимости**: `013-account-settings` (вкладка Profile готова), `010-recipe-import` (import pipeline)  
**Эталон**: `/account` page (Telegram, export/import), PRD § Telegram / Export

## Контекст

В 013 отгружено большинство настроек аккаунта. **Не закрыто**:

- US7 Telegram connect/status/disconnect — есть только `telegramUsername` в `UserProfileDTO`, нет UI и API-вызовов;
- US6 export/import файлов — секция данных = заглушка `account.data.coming-soon`.

Импорт файла export (`.json/.zip`) также отмечен как недоделка в 010 — закрываем единым file pipeline здесь.

## Цель

Паритет мобильного account: подключение Telegram и выгрузка/загрузка пользовательских данных файлами.

## Пользовательские сценарии

### US1 — Telegram connect (P3)

**Когда** пользователь нажимает «Подключить Telegram», **тогда** показывается код / deep link, `POST connect`, polling статуса; после подключения — `@username` и кнопка disconnect.

### US2 — Telegram disconnect (P3)

**Когда** disconnect, **тогда** связь снимается, UI обновляется.

### US3 — Export всех данных (P2)

**Когда** «Экспортировать всё», **тогда** v1.3 zip/json (через API или сбор из Y.Doc — сверить с вебом), сохранение через share sheet / Files.

### US4 — Import файла (P2)

**Когда** пользователь выбирает `.json/.zip` (v1.0–v1.3), **тогда** тот же серверный pipeline, что 010; результат — рецепты в коллекции через sync. Точка входа — Import sheet (010) и/или раздел данных аккаунта.

### US5 — Офлайн / безопасность (P2)

Кнопки недоступны офлайн с i18n; не логировать чувствительные данные; pasteboard только по явному действию.

## Требования

### FR-020-001 — Telegram API

`POST connect` / status poll / disconnect — пути в `contracts/account-api.md` (сверить с `llm/API.md`).

### FR-020-002 — Export

Формат v1.3; сверить, отдаёт ли сервер готовый файл или собирается клиентом из Y.Doc.

### FR-020-003 — Import file

Расширить `RecipeImportAPI` / `ImportRecipeSheet` режимом «файл»; `fileImporter` SwiftUI.

### FR-020-004 — i18n

Заменить `account.data.coming-soon` и все новые строки на локализованные ключи ru/en (см. 022).

## Вне scope

- PDF cookbook
- OAuth

## Критерии успеха

- **SC-001**: Connect Telegram → статус «подключён» с `@username`.
- **SC-002**: Export → валидный v1.3 файл, открываемый вебом.
- **SC-003**: Import `.zip` v1.3 → рецепты появляются в коллекции на обоих клиентах.
- **SC-004**: Офлайн — операции недоступны с i18n.

## Артефакты

- `contracts/account-api.md` (Telegram + export/import)
- `quickstart.md`
