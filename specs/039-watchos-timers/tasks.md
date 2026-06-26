# Задачи: watchOS Companion — Timers v1

Чеклист выполнения. Зачеркиваем пункт по факту, не заранее.

## Spec Kit

- [x] `spec.md` — постановка, user stories, acceptance criteria
- [x] `plan.md` — ссылки и порядок
- [ ] `tasks.md` — этот файл
- [ ] `contracts/timer-api.md` — HTTP-контракт
- [ ] `contracts/watchconnectivity-creds.md` — payload contract
- [ ] `layout.md` — разложение Figma node `132:635`
- [ ] `layout-audit.json` — машиночитаемые проверки

## Core refactor

- [ ] `RecipeScalerCore/Networking/ServerActiveTimer.swift` — вынос `ServerActiveTimer`, `ActiveTimersResponse`, `TimerSyncHTTPResponse` из main app
- [ ] `TimerSyncService.swift` — обновить чтобы использовать публичные типы из Core
- [ ] `RecipeScalerCore/TimerViews/` — новая директория
  - [ ] `TimerPalette.swift` (Core-only, без WidgetKit)
  - [ ] `TimerLinearRow.swift` (адаптированный под `maxWidth: .infinity` + `minHeight: 44`)
  - [ ] `TimerFormatting.swift`
  - [ ] `TimerFonts.swift` (без `UIFont`/`NSAttributedString`, или через `#if os(iOS)`)
- [ ] `HomeWidgetExtension/Views/` — обновить чтобы использовать Core-примитивы (back-compat)
- [ ] iOS build green

## watchOS target

- [ ] Создать `RecipeScalerNativeWatch` target в `project.pbxproj`
  - [ ] `PRODUCT_BUNDLE_IDENTIFIER = ru.recipescaler.RecipeScalerNative.watchkitapp`
  - [ ] `WKCompanionAppBundleIdentifier = ru.recipescaler.RecipeScalerNative`
  - [ ] `WKWatchOnly = NO`
  - [ ] `WATCHOS_DEPLOYMENT_TARGET = 10.0`
  - [ ] `SDKROOT = watchos`
  - [ ] Embed `RecipeScalerCore.framework`
  - [ ] `Watch.entitlements`: application-groups + keychain-access-groups
- [ ] `RecipeScalerNativeWatch/App/RecipeScalerNativeWatchApp.swift` — `@main` entry
- [ ] watchOS build green на `generic/platform=watchOS`

## iOS bridge

- [ ] `RecipeScalerNative/Services/WatchCredentialsBridge.swift` (новый)
- [ ] `RecipeScalerNative/Services/AuthService.swift` — wire-up в `loginWithSeed`, `registerAuto`, `logout`
- [ ] `RecipeScalerNative/App/AppDelegate.swift` (или эквивалент) — `activate()` в `didFinishLaunching`
- [ ] iOS build green

## watch creds

- [ ] `RecipeScalerNativeWatch/Services/WatchCredentialsStore.swift` — watch-local Keychain
- [ ] `RecipeScalerNativeWatch/Services/WatchCredentialsBridge.swift` — `WCSessionDelegate`
- [ ] Manual test: paired simulator, login → creds доходят

## watch service

- [ ] `RecipeScalerNativeWatch/Services/WatchTimerService.swift`
  - [ ] `refresh()` — GET `/api/v1/timers/active`
  - [ ] `pause(timerId:)` — optimistic + POST `/sync`
  - [ ] `resume(timerId:)` — optimistic + POST `/sync`
  - [ ] `delete(timerId:)` — optimistic + POST `/sync`
  - [ ] State machine: `.idle` / `.loading` / `.loaded` / `.error` / `.notAuthorized`

## watch haptics

- [ ] `RecipeScalerNativeWatch/Haptics/WatchHaptics.swift`
  - [ ] `click()`, `success()`, `notification()`
  - [ ] `timerExpired()` — pattern 3× `.notification` с интервалом 0.5s

## watch UI

- [ ] `RecipeScalerNativeWatch/Views/TimerListView.swift` — List + swipeActions
- [ ] `RecipeScalerNativeWatch/Views/EmptyStateView.swift` — квадрат icon+text
- [ ] `RecipeScalerNativeWatch/Views/ErrorStateView.swift` — квадрат icon+text
- [ ] `RecipeScalerNativeWatch/Views/NotAuthorizedStateView.swift` — квадрат icon+text
- [ ] `RecipeScalerNativeWatch/Views/SettingsRow.swift` — gear + label, no-op + light haptic

## i18n

- [ ] `RecipeScalerNative/Resources/Localizable.xcstrings` — ключи:
  - [ ] `watch.timer.empty.title`
  - [ ] `watch.timer.error.title`
  - [ ] `watch.timer.error.subtitle`
  - [ ] `watch.timer.not-authorized.title`
  - [ ] `watch.timer.not-authorized.subtitle`
  - [ ] `watch.timer.action.pause`
  - [ ] `watch.timer.action.resume`
  - [ ] `watch.timer.action.delete`
  - [ ] `watch.timer.settings.label`
  - [ ] `watch.timer.settings.hint`

## Layout audit

- [ ] `bash scripts/audit-ui-layout.sh specs/039-watchos-timers` green
- [ ] Spawn layout-reviewer subagent — код ↔ layout.md

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
- [ ] Settings tap → лёгкий haptic, ничего не происходит
- [ ] Foreground timer expiration → 3× notification haptic

## Финал

- [ ] Build green для обоих таргетов
- [ ] Коммит (не пушить без явной просьбы)
- [ ] Закрыть Linear MIK-184
