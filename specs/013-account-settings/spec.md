# Спецификация: аккаунт и настройки (вкладка Profile)

**Ветка**: `013-account-settings`  
**Дата**: 2026-06-02  
**Статус**: Draft  
**Зависимости**: `007-app-shell-navigation`, auth Phase 1  
**Эталон**: `/account` page, PRD § Assistant (settings subset), Telegram, export

## Контекст

Вкладка Profile на вебе: display name, avatar, language, theme, nutrition toggle, seed/QR, public profile settings, Telegram, export/import файлов, logout.

iOS: `AuthView` + Keychain; полноценного Account screen нет.

## Цель

Паритет настроек **мобильного** account (не desktop-only панели).

## Пользовательские сценарии

### US1 — Профиль (P1)

**Когда** пользователь меняет display name или avatar, **тогда** REST `PATCH name`, `POST/DELETE avatar` (WebP на сервере); отображение в assistant/public — по вебу.

### US2 — Username / public profile (P2)

**Когда** включает public profile, **тогда** username (3–128 PRD, сверить с DB 64 — open question PRD), share mode, allow downloads — `PUT /api/users/public-profile`.

### US3 — Seed phrase & QR (P1)

**Когда** просмотр seed, **тогда** Face ID / Touch ID gate; QR scan/generator для входа на другом устройстве (`QRScannerView` уже есть — интеграция).

### US4 — Language & theme (P2)

**Когда** меняет язык, **тогда** ru/en app locale; theme system/light/dark — SwiftUI `preferredColorScheme`.

### US5 — Nutrition display toggle (P2)

Глобальный toggle отображения nutrition (как веб local pref).

### US6 — Export / import file (P2)

**Когда** export all, **тогда** v1.3 zip/json через API или client-side сбор из Y.Doc (сверить с веб); import file → 010 pipeline.

### US7 — Telegram (P3)

**Когда** connect, **тогда** показ кода, `POST connect`, status poll; disconnect.

### US8 — Logout (P1)

Очистка Keychain, SQLite snapshots, offline queue, stop sync — без утечки userId.

## Требования

### FR-ACC-001

Все строки i18n; биометрия для seed — `docs/PRD.md` § Security.

### FR-ACC-002

Не логировать seed; pasteboard только по явному Copy.

## Вне scope

- PDF cookbook (отдельная фича)
- OAuth

## Критерии успеха

- **SC-001**: Avatar change iOS → веб account ≤ 10 с.
- **SC-002**: Logout → другой seed не видит старые snapshots.

## Артефакты

- `contracts/account-api.md`
- `quickstart.md`