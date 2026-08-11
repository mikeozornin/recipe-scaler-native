# Задачи: watchOS Companion — Timers v1

Чеклист выполнения. Зачеркиваем пункт по факту, не заранее.

**Статус**: MIK-184 закрыт (2026-08-11). Все автоматизируемые пункты выполнены.
Manual QA на paired simulator DEFERRED. Сверх scope реализован spec 062-watch-timer-expiry-notify.

## Spec Kit

- [x] `spec.md` — постановка, user stories, acceptance criteria
- [x] `plan.md` — ссылки и порядок
- [x] `tasks.md` — этот файл
- [x] `contracts/timer-api.md` — HTTP-контракт
- [x] `contracts/watchconnectivity-creds.md` — payload contract
- [x] `layout.md` — разложение Figma node `132:635`
- [x] `layout-audit.json` — машиночитаемые проверки

## Core refactor

- [x] `RecipeScalerCore/Networking/ServerActiveTimer.swift` — вынос `ServerActiveTimer`, `ActiveTimersResponse`, `TimerSyncHTTPResponse` из main app
- [x] `TimerSyncService.swift` — обновить чтобы использовать публичные типы из Core
- [x] `RecipeScalerCore/TimerViews/` — новая директория
  - [x] `TimerPalette.swift` (Core-only, без WidgetKit)
  - [x] `TimerLinearRow.swift` (адаптированный под `maxWidth: .infinity` + `minHeight: 44`)
  - [x] `TimerFormatting.swift`
  - [x] `TimerFonts.swift` (без `UIFont`/`NSAttributedString`, или через `#if os(iOS)`)
  - [x] `TimerOrdering.swift`, `ActiveTimerPresentation.swift` — дополнительные примитивы
- [x] `HomeWidgetExtension/Views/` — обновить чтобы использовать Core-примитивы (back-compat)
- [x] iOS build green

## watchOS target

- [x] Создать `RecipeScalerNativeWatch` target в `project.pbxproj`
  - [x] `PRODUCT_BUNDLE_IDENTIFIER = ru.recipescaler.RecipeScaler.watchkitapp`
  - [x] `WKCompanionAppBundleIdentifier = ru.recipescaler.RecipeScaler`
  - [x] `WKWatchOnly = NO`
  - [x] `WATCHOS_DEPLOYMENT_TARGET = 10.0`
  - [x] `SDKROOT = watchos`
  - [x] Embed `RecipeScalerCore.framework`
  - [x] `Watch.entitlements`: application-groups + keychain-access-groups
- [x] `RecipeScalerNativeWatch/App/RecipeScalerNativeWatchApp.swift` — `@main` entry
- [x] watchOS build green на `generic/platform=watchOS` (через `scripts/verify-watch-timers.sh`)

## iOS bridge

- [x] `RecipeScalerNative/Services/WatchCredentialsBridge.swift` (новый)
- [x] `RecipeScalerNative/Services/AuthService.swift` — wire-up в `loginWithSeed`, `registerAuto`, `logout` (строки 469, 561, 826)
- [x] `RecipeScalerNative/App/AppContainer.swift` — publish userId+token (строка 425)
- [x] iOS build green

## watch creds

- [x] `RecipeScalerNativeWatch/Services/WatchCredentialsStore.swift` — watch-local Keychain
- [x] `RecipeScalerNativeWatch/Services/WatchCredentialsBridge.swift` — `WCSessionDelegate`
- [ ] Manual test: paired simulator, login → creds доходят *(DEFERRED — нужен watchOS Simulator runtime)*

## watch service

- [x] `RecipeScalerNativeWatch/Services/WatchTimerService.swift`
  - [x] `refresh()` — GET `/api/v1/timers/active`
  - [x] `pause(timerId:)` — optimistic + POST `/sync`
  - [x] `resume(timerId:)` — optimistic + POST `/sync`
  - [x] `delete(timerId:)` — optimistic + POST `/sync`
  - [x] State machine: `.idle` / `.loading` / `.loaded` / `.empty` / `.error` / `.notAuthorized`

## watch haptics

- [x] `RecipeScalerNativeWatch/Haptics/WatchHaptics.swift`
  - [x] `click()`, `success()`, `notification()`
  - [x] `timerExpired()` — pattern 3× `.notification` с интервалом 0.5s

## watch UI

- [x] `RecipeScalerNativeWatch/Views/TimerListView.swift` — List + swipeActions
- [x] `RecipeScalerNativeWatch/Views/EmptyStateView.swift` — квадрат icon+text
- [x] `RecipeScalerNativeWatch/Views/ErrorStateView.swift` — квадрат icon+text
- [x] `RecipeScalerNativeWatch/Views/NotAuthorizedStateView.swift` — квадрат icon+text
- [x] `RecipeScalerNativeWatch/Views/SettingsRow.swift` — gear + label *(теперь открывает `WatchSettingsView`, см. spec 062; больше не no-op)*

## i18n

- [x] `RecipeScalerNative/Resources/Localizable.xcstrings` — ключи:
  - [x] `watch.timer.empty.title`
  - [x] `watch.timer.error.title`
  - [x] `watch.timer.error.subtitle`
  - [x] `watch.timer.not-authorized.title`
  - [x] `watch.timer.action.pause`
  - [x] `watch.timer.action.resume`
  - [x] `watch.timer.action.delete`
  - [x] `watch.timer.settings.label`
  - [x] `watch.timer.settings.hint`
  - [x] *доп. из spec 062:* `watch.timer.settings.title`, `watch.timer.settings.expiry-toggle.label`, `watch.timer.settings.expiry-toggle.hint`, `watch.timer.settings.notifications-disabled.footnote`

## Layout audit

- [x] `bash scripts/audit-ui-layout.sh specs/039-watchos-timers` green
- [x] Spawn layout-reviewer subagent — код ↔ layout.md

## Manual QA

**Статус**: DEFERRED — watchOS Simulator runtime не установлен в текущей среде.

Требуется для прохождения (после установки runtime через Xcode → Settings → Platforms → watchOS):

- [ ] Paired simulator (iPhone + Apple Watch)
- [ ] Login на iPhone → watch видит таймеры
- [ ] Swipe pause → таймер паузится на обоих устройствах
- [ ] Swipe resume → таймер продолжает
- [ ] Swipe delete → таймер исчезает с обоих
- [ ] Empty state когда нет активных таймеров
- [ ] Error state при отключённой сети
- [ ] Not-authorized state после logout на iPhone
- [ ] Settings tap → лёгкий haptic, ничего не происходит *(устарело после spec 062 — теперь открывает Settings screen)*
- [ ] Foreground timer expiration → 3× notification haptic

## Финал

- [x] Build green для обоих таргетов (`scripts/verify-watch-timers.sh`)
- [x] Коммит (не пушить без явной просьбы)
- [x] Закрыть Linear MIK-184 *(закрыт 2026-08-11)*

## Out of scope v1 — не реализовано

- [ ] `WatchPushRegistration` — APNs register для watch через `POST /api/push/apns-register` (platform=watch). Отложено до готовности серверного `timer_completed` push для watch (см. spec [058-live-activity-push](../058-live-activity-push/spec.md), [062 User Story 3](../062-watch-timer-expiry-notify/spec.md)). До тогда локальная `UNCalendarNotificationTrigger` работает как единственный канал. **Нужен отдельный тикет, когда бэкенд будет готов.**
