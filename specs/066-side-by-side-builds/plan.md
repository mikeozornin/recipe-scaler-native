# План: Side-by-side dev-сборка

**Дата**: 2026-08-26
**Спека**: [spec.md](./spec.md)

## Границы

- **В scope**: новые конфигурации DebugDevice/ReleaseDevice во всех таргетах; схема RecipeScalerNative-Dev; `*Dev.entitlements` для 6 таргетов; flavor-условия в `AppGroup.id` / `SharedAuthStore` / UTType; параметризация Info.plist; AppIconDev; портал-чеклист и документация.
- **Вне scope**: staging backend; push/UL в dev; TestFlight для dev; auto-login на устройстве; миграции данных (их нет — новый sandbox).
- **STOP conditions**: если Automatic Signing не может создать профили под `.debug` App IDs без ручных портальных действий — останавливаемся, владелец проходит чеклист из docs; если embedded-extension подпись падает с entitlement mismatch — сверять группу в каждом `*Dev.entitlements`.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | Синхронизация Yjs не меняется; dev-app работает с тем же API и своим CRDT-документом в своём sandbox. |
| Web parity | PASS | Web не затрагивается. |
| Offline-first | PASS | Разделение сборок не влияет на офлайн-поведение. |
| Native UI | PASS | Изменения UI минимальны: иконка и display name через asset catalog / build settings. |
| Phased delivery | PASS | Фазы: спека → константы/entitlements → pbxproj → схема → иконка → доки → верификация; каждая фаза собирается. |
| i18n | PASS | UI-строки не добавляются; display name задаётся build setting'ом (cfBundleName), не локализуемой строкой. |
| Documentation | PASS | Портал-чеклист + таблица ID в PAID-APPLE-DEVELOPER-REQUIRED.md; строка в AGENTS.md. |

## Очерёдность

1. **Константы флейвора в коде** (`AppGroup.id`, Keychain group, UTType) — от них зависят entitlements и verify; зависимости: нет.
2. **Info.plist параметризация** — до pbxproj, чтобы переменные сразу имели дефолты на уровне проекта.
3. **Entitlements-файлы** — до configurations.
4. **pbxproj: DebugDevice/ReleaseDevice** — самая большая правка; после неё проект обязан собираться в старых схемах.
5. **Схема RecipeScalerNative-Dev**.
6. **Иконка AppIconDev** (placeholder) + при предоставлении PNG владельцем — замена.
7. **Доки** (портал-чеклист идёт до первого device-ранa).
8. **Верификация**: симуляторные builds/tests обеих схем + статические проверки бинарника.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerCore/AppGroup.swift` | Изменить | Flavor-aware `id`. |
| `RecipeScalerCore/Auth/SharedAuthStore.swift` | Изменить | Flavor-aware keychain access group. |
| `RecipeScalerCore/Import/ThirdParty/UTTypeRecipeScaler.swift` | Изменить | Flavor-aware UTType identifier. |
| `RecipeScalerNative/Info.plist` | Изменить | `$(RS_DISPLAY_NAME)` / `$(RS_URL_SCHEME)` / `$(RS_RECIPE_UTTYPE)` (+extension объявления типа). |
| `RecipeScalerNative/*Dev.entitlements` + 5 extension/watch `*Dev.entitlements` | Создать | Debug App Group + Keychain, aps development, без Associated Domains у main. |
| `project.pbxproj` | Изменить | Дублировать пары Debug/Release → DebugDevice/ReleaseDevice во всех таргетах; `.debug` bundle IDs; `RS_DEV_FLAVOR`; display name/scheme/UTType переменные; AppIconDev. |
| `Assets.xcassets/AppIconDev.appiconset/Contents.json` | Создать | Синяя иконка дев-сборки (placeholder PNG). |
| `xcshareddata/xcschemes/RecipeScalerNative-Dev.xcscheme` | Создать | Run=DebugDevice, Archive=ReleaseDevice, Test=Debug. |
| `docs/PAID-APPLE-DEVELOPER-REQUIRED.md` | Изменить | Таблица dev-идентификаторов + портал-чеклист. |
| `AGENTS.md` | Изменить | Строка про две схемы. |
| `specs/066-side-by-side-builds/{spec,plan,tasks}.md` | Создать | Спека по конвенции репо. |

## Downstream consumers

- **SwiftUI views**: не затрагиваются напрямую; deep-link URLs строятся строками `recipe-scaler://…` в `DeepLinkRouter`, `ShareView`, `TimerLockScreenLiveActivityView`, `TimerHomeSmallView` — парсер должен принимать оба scheme (prod/dev по фактическому scheme хоста Bundle). Правка: резолвить scheme из `Bundle.main` вместо литерала, где URL **строятся**; тесты диплинков остаются на литерале prod-scheme (тестовый host = prod-flavor).
- **Cross-process**: HomeWidget, TimerLiveActivityExtension, Share/Action, Watch — все линкуют RecipeScalerCore и получают те же flavor-константы; виджеты дев-сборки встают отдельно (own kind strings) благодаря отдельному bundle ID.
- **Sync boundaries**: тот же `recipe-scaler.ru` API;deviceId/Yjs-документы живут в sandbox каждого приложения — пересечений нет; серверу всё равно, какой bundle id у клиента (bearer auth).
- **Persisted state**: SQLite/Yjs-файлы — per-sandbox автоматически; App Group `group.ru.recipescaler.RecipeScaler.debug`; Keychain access group `ZBPX4JYT24.ru.recipescaler.RecipeScaler.debug`; UserDefaults.standard — свой.
- **Tests / verify scripts**: `scripts/*.sh` и UI-тесты остаются на prod-ID (обычный Debug). Тесты `SharedAuthStoreTests.testKeychainAccessGroupIsTeamPrefixed` продолжают проходить (тест-fлейвор = prod). Новый smoke — по желанию.

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| Dev-сборка | В бинарнике main присутствуют строки `ru.recipescaler.RecipeScaler.debug` и `group.ru.recipescaler.RecipeScaler.debug` | xcodebuild + `strings` check (в плане tasks) |
| Prod-сборка | В бинарнике обычного Debug отсутствует суффикс `.debug` у bundle ID/App Group | существующие verify-скрипты |
| Константа группы | При RS_DEV_FLAVOR `AppGroup.id == "group.ru.recipescaler.RecipeScaler.debug"`, иначе prod-значение | unit smoke при необходимости |
| Иконки | В собранном .app dev-flavor имя аппкон-каталога = AppIconDev | actool output / info.plist CFBundleIcons |

Негативная формулировка «не должно сломаться» сама по себе недостаточна.

## Async lifecycle

Правки асинхронной логики не содержат: только build settings, plist, константы, entitlements. N/A — нет async side effects.

## Teardown / resource inventory

State machine приложений не меняется; таблица не применима. Единственный teardown-смежный эффект — logout в одном приложении больше не может «задеть» другой: гарантируется разными Keychain access groups.

## Cross-target contracts

- **Canonical owner**: `AppGroup.id` (все записи/чтения App Group) и `SharedAuthStore.keychainAccessGroup`.
- **Writer/reader targets**: main ↔ Share/Action/HomeWidget/TimerLiveActivity/Watch — каждый target читает константу из линкуемого RecipeScalerCore; entitlements-файлы должны совпадать с константой по построению (проверка verify-скриптом по образцу verify-share-extension.sh).
- **Validator/normalizer**: static `strings`-check собранных бинарей.
- **Raw literal exceptions**: литералы `recipe-scaler://` внутри тестов (допустимо: тест-fлейвор = prod); Explore-верификация grep'ом после правок.

## Locale / theme consumers

N/A — ни одного изменения текстов, локализации или темы. Имя приложения — build setting.

## Compatibility / migration

- Current format/contract: одно приложение prod-ID, App Group без суффикса, keychain без суффикса.
- Previous supported format: то же самое (продолжает работать как есть в обычных конфигурациях).
- Missing version/default behavior: дефолтные значения RS_* переменных заданы project-level = prod значения.
- Unknown future version/ID behavior: n/a.
- Required legacy fixture tests: `UTTypeRecipeScalerTests`, `SharedAuthStoreTests`, `DeepLinkRouterTests` должны остаться зелёными без правок семантики.

## Verification

1. `bash scripts/build-for-verify.sh` — регрессия prod (обычная симуляторная сборка).
2. `bash scripts/test-fast.sh` — юнит-тесты.
3. `xcodebuild -scheme RecipeScalerNative-Dev -destination 'generic/platform=iOS' build` — компиляция dev-флейвора (Automatic Signing; требует VPN-независимой доступности портала либо `-allowProvisioningUpdates` с аккаунтом в Xcode).
4. Static: `strings` по product binary: наличие `.debug` констант в dev-сборке и отсутствие — в проде.
5. Device smoke — руками владельцем: две иконки, разные аккаунты, независимый logout, отдельные виджеты/LA.

<!-- SPECKIT: generated for specs/066-side-by-side-builds -->
