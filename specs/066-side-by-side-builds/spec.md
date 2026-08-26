# Спецификация: Side-by-side dev-сборка (native)

**Ветка**: работа на `master` (AGENTS.md: small fixes на master)
**Дата**: 2026-08-26
**Статус**: Approved
**Зависимости**: платный Apple Developer Program (`ZBPX4JYT24`), Automatic Signing, embedded extensions (Share/Action/HomeWidget/TimerLiveActivity/Watch)

## Контекст и мотивация

У владельца один iPhone. Сейчас Debug и Release конфигурации ставят одно и то же приложение `ru.recipescaler.RecipeScaler`: установка dev-сборки из Xcode затирает prod (из App Store), данные и аккаунт общие. Нужны две независимые иконки на одном устройстве: продакшен-сборка с продакшен-аккаунтом (App Store) и девелоперская с отдельным тестовым аккаунтом, своими таймерами в виджетах и своей Live Activity.

## Цель

1. Новая пара build-конфигураций **DebugDevice / ReleaseDevice** во всех таргетах: bundle ID с суффиксом `.debug`, отдельный App Group, Keychain access group и иконка.
2. Отдельная схема **RecipeScalerNative-Dev**: Run = DebugDevice (дев-иконка), Archive = ReleaseDevice.
3. Обычные Debug/Release и вся симуляторная инфраструктура (скрипты, UI-тесты) остаются на prod-ID без изменений.
4. Дев-флейвор визуально отличим: имя «RS Dev», синяя иконка.

## Non-goals

- Staging backend / второй API (`recipe-scaler.ru` один; разделение — локальные данные + аккаунт).
- TestFlight-канал для dev-сборки.
- Auto-login debug user на физическом устройстве (остаётся simulator-only).
- Universal Links и push-нотификации в dev-флейворе (включаются позже при необходимости).
- Watch: dev-tаргет собирается по ID, но функционально не проверяется (нет железа).

---

## Clarifications

### Session 2026-08-26

- Q: Изолировать только main app или все расширения? → A: **Полная изоляция** (main + widget + LA + Share/Action + Watch + Core constants) — держать prod-расширения рядом с dev-main хуже: Share/Keychain всё равно дублировать по ID, дырки в изоляции остаются.
- Q: Prod на телефоне? → A: **App Store версия** — ничего удалять и переустанавливать не нужно; dev со своим ID просто ставится рядом.
- Q: Механизм флейвора? → A: **Отдельные конфигурации DebugDevice/ReleaseDevice**, а не суффикс в существующем Debug — иначе ломается симуляторный workflow (~8 скриптов/доков завязаны на prod-ID).
- Q: Имя дев-иконки? → A: **RS Dev**, иконка синяя (предоставит владелец; до этого — placeholder).

---

## Границы (Scope)

**Входит:**

- pbxproj: пары DebugDevice/ReleaseDevice для таргетов main, RecipeScalerCore, ShareExtension, ActionExtension, HomeWidgetExtension, TimerLiveActivityExtension, RecipeScalerNativeWatch.
- Bundle IDs с `.debug`; константы флейвора через `SWIFT_ACTIVE_COMPILATION_CONDITIONS = RS_DEV_FLAVOR`.
- Файлы `*Dev.entitlements`: App Group `group.ru.recipescaler.RecipeScaler.debug`, Keychain `$(AppIdentifierPrefix)ru.recipescaler.RecipeScaler.debug`.
- Код-константы под флейвором: `AppGroup.id`, `SharedAuthStore.sharedKeychainAccessGroup`, UTType рецепта.
- Info.plist: параметризация display name / URL scheme / UTType.
- Asset catalog: `AppIconDev.appiconset` (синий placeholder) + `ASSETCATALOG_COMPILER_APPICON_NAME` в device-конфигах.
- Схема `RecipeScalerNative-Dev` (shared): Run=DebugDevice, Archive=ReleaseDevice, Test=Debug (prod-ID для UI-тестов).
- Portal-чеклист в docs (руками: App Group + App IDs).
- Документация workflow двух сборок.

**Не входит:** см. Non-goals.

---

## Пользовательские сценарии и тестирование *(обязательно)*

### User Story 1 — Поставить dev рядом с prod (P1)

Владелец открывает проект, выбирает схему RecipeScalerNative-Dev, Run на своём iPhone. На экране появляется вторая иконка «RS Dev» (синяя); установленная из App Store «Recipe Scaler» не затрагивается: данные, сессия, рецепты остаются как были.

**Почему приоритет**: основной смысл фичи — два аккаунта на одном телефоне.

### User Story 2 — Независимые данные и сессии (P1)

В RS Dev логинятся другим аккаунтом. Рецепты двух приложений не пересекаются; logout в одном не разлогинивает другое; ключи не читают друг друга (разные Keychain access groups); таймеры виджетов/LA у каждой свои (разные App Groups).

### User Story 3 — Рутинная разработка без регрессии (P2)

Обычная схема RecipeScalerNative (Debug на симуляторе) работает как раньше: auto-login debug user, verify-скрипты, UI-тесты — без правок, потому что bundle ID остался prod.

---

## Требования

| ID | Требование |
|----|------------|
| FR-1 | Схема RecipeScalerNative-Dev собирает всё приложение целиком (main + Core + расширения) в идентификаторах с `.debug`. |
| FR-2 | В обычных схемах Debug/Release nothing changed: bundle IDs, App Group, entitlements, иконка — prod. |
| FR-3 | Все свифтовые точки доступа к shared-состоянию резолвят группу/группу keychain/UTType из flavor-условия; новых хардкодов литералов нет. |
| FR-4 | Dev-приложение различимо: display name «RS Dev», отдельная синяя иконка. |
| FR-5 | URL scheme в dev — `recipe-scaler-dev://…`, чтобы deep link из одного приложения не открывал другое. |
| FR-6 | UTType в dev — `ru.recipescaler.recipe.debug`, чтобы AirDrop/«Открыть в» разводили файлы по приложениям. |
| FR-7 | В dev-entitlements main отсутствует Associated Domains (Universal Links всегда открывают prod). |
| FR-8 | Существующие юнит-тесты продолжают проходить без изменений семантики (тестовый host собирается в обычном Debug = prod-флейвор). |

## Acceptance criteria

- [ ] `xcodebuild -list` показывает схемы RecipeScalerNative и RecipeScalerNative-Dev; в первой Debug/Release, во второй DebugDevice/ReleaseDevice (+Debug для Test action).
- [ ] Сборка обеих схем зелёная на симуляторе; unit-тесты зелёные.
- [ ] Сборка RecipeScalerNative-Dev для устройства проходит codesign (Automatic Signing) после ручного создания портальных сущностей.
- [ ] На устройстве: две иконки (Recipe Scaler из App Store + RS Dev), разные аккаунты, logout независим, виджет RS Dev читает таймеры только dev-app.

## Верификация

- `bash scripts/build-for-verify.sh` (prod-flavor regression)
- `bash scripts/test-fast.sh`
- `xcodebuild -scheme RecipeScalerNative-Dev -destination 'generic/platform=iOS' build` (dev-flavor compile gate)
- Static check: в бинарнике dev-сборки строки `.debug` группы/bundle ID присутствуют (по образцу `scripts/verify-timer-widget.sh`)
- Device smoke руками по чеклисту acceptance criteria (агент не может замкнуть UI-loop на физическом iPhone — см. AGENT-WORKFLOW)
