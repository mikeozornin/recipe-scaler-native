# Tasks: Side-by-side dev-сборка

## Phase 1 — Код-константы и plist (до pbxproj)

- [ ] T1 `AppGroup.id` под `RS_DEV_FLAVOR` ([RecipeScalerCore/AppGroup.swift](../../RecipeScalerCore/AppGroup.swift))
- [ ] T2 `SharedAuthStore.sharedKeychainAccessGroup` под флейвор ([RecipeScalerCore/Auth/SharedAuthStore.swift](../../RecipeScalerCore/Auth/SharedAuthStore.swift))
- [ ] T3 UTType identifier под флейвор ([RecipeScalerCore/Import/ThirdParty/UTTypeRecipeScaler.swift](../../RecipeScalerCore/Import/ThirdParty/UTTypeRecipeScaler.swift)) + вынос литерала scheme построения deep-link URL из `Bundle.main`
- [ ] T4 Info.plist: `$(RS_DISPLAY_NAME)`, `$(RS_URL_SCHEME)`, `$(RS_RECIPE_UTTYPE)` (+UTExportedTypeDeclarations)

## Phase 2 — Entitlements

- [ ] T5 `RecipeScalerNativeDev.entitlements` (main: app group .debug, keychain .debug, aps development, без Associated Domains)
- [ ] T6 `*Dev.entitlements` для ShareExtension / ActionExtension / HomeWidgetExtension / TimerLiveActivityExtension / RecipeScalerNativeWatch

## Phase 3 — pbxproj и схема

- [ ] T7 Project-level дефолты `RS_DISPLAY_NAME = Recipe Scaler`, `RS_URL_SCHEME = recipe-scaler`, `RS_RECIPE_UTTYPE = ru.recipescaler.recipe`
- [ ] T8 Дублировать Debug→DebugDevice, Release→ReleaseDevice во всех 7 таргетах + XCConfigurationList; в device-конфигах: `.debug` bundle IDs (кроме Core), `SWIFT_ACTIVE_COMPILATION_CONDITIONS += RS_DEV_FLAVOR`, `CODE_SIGN_ENTITLEMENTS → *Dev.entitlements`, на main также `RS_DISPLAY_NAME = RS Dev`, `RS_URL_SCHEME = recipe-scaler-dev`, `RS_RECIPE_UTTYPE = ru.recipescaler.recipe.debug`, `ASSETCATALOG_COMPILER_APPICON_NAME = AppIconDev`; в DebugDevice main сохранить `RS_ALLOWS_LOCAL_NETWORKING = YES`
- [ ] T9 Схема `RecipeScalerNative-Dev.xcscheme`: Run=DebugDevice, Archive=ReleaseDevice, Test=Debug (без UI-test бандла)

## Phase 4 — Иконка

- [ ] T10 `AppIconDev.appiconset` (Contents.json + placeholder PNG, синий фон с «D») — заменить PNG, когда владелец даст фирменную синюю

## Phase 5 — Портал и доки (руками владельцем до device-run)

- [ ] T11 Чеклист портала в docs/PAID-APPLE-DEVELOPER-REQUIRED.md: App Group `group.ru.recipescaler.RecipeScaler.debug`; App IDs `…RecipeScaler.debug` (+Push, без Associated Domains), `….debug.{Share,Action,HomeWidget,TimerLiveActivity,watchkitapp}`
- [ ] T12 AGENTS.md: строка про схемы; таблица dev-ID в PAID doc

## Phase 6 — Верификация

- [ ] T13 `bash scripts/build-for-verify.sh` && `bash scripts/test-fast.sh` (prod regression)
- [ ] T14 Dev-flavor build gate + static strings-check (.debug константы в dev, отсутствие в prod)
- [ ] T15 Device smoke чеклист (владелец): 2 иконки, разные аккаунты, независимый logout, отдельные виджеты/LA
