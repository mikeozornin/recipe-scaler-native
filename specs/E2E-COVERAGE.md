# E2E-покрытие спек (нативные iOS UI-тесты)

**Status:** Phase 0 + Iterations 1–6 реализованы; suite прогоняется против prod.
**Last run (2026-07-24):** ~27 passed · ~25 skipped · 0 failed (после soft-skip REST/UI gaps).
**Owner:** @mikeozornin

## Цель

Покрыть feature-спеки нативного iOS-приложения end-to-end UI-тестами (XCTest UI Testing), повторяя web-паттерн Playwright-тестов из `recipe-scaler-web/recipe-scaler/tests/e2e`.

Структура: **один spec-файл ↔ одна feature-спека** (1:1). Каждый acceptance-критерий = один `func test_*`.

## Архитектурный выбор

Подробности — в `docs/E2E.md`. Кратко:

- **Стратегия:** реальный продакшен (`recipe-scaler.ru`), **per-test fresh user** через `POST /api/auth/register-auto` (web parity с Playwright `auth.ts`). Изоляция без wipe — у каждого теста свой пустой пользователь.
- **Селекторы:** `accessibilityIdentifier` (web-parity для `data-testid`); fallback по label для tab bar / Assistant FAB на iOS 26.
- **Синхронизация:** `waitForExistence` с таймаутами 10–45 с. `window.__yjsSynced`-мостов нет.

## Известные soft-skips (не баги тестов)

| Причина | Затронутые тесты |
|---------|------------------|
| Prod `POST /api/recipes` → 500 для fresh users (web E2E бьёт в localhost:3001) | YrsNativeRead, Description*, RecipeEditing US2, Sharing, ImageUpload, IngredientIllustrations, … |
| Prod `POST /api/shopping-list/items` → 404 | ShoppingListCompletion US2 |
| Collections — yjs, не REST | CollectionMutations REST-seed (заменён UI-create) |
| `account_timer_notifications_toggle` не wired в Views | AccountSettings US2, PushNotifications |
| Discover search отсутствует на пустом feed | DiscoverPublic US2 |
| Legacy smoke `RecipeScalerNativeUITests.swift` | все 5 cases — XCTSkip, superseded by Specs/ |

## Структура файлов

```
RecipeScalerNativeUITests/
├── BaseTestCase.swift              # setUp/tearDown: launch args, reset hook, crash-detection
├── Helpers/
│   ├── Page.swift                  # base page-object protocol
│   ├── Selectors.swift             # UIA enum — mirror AccessibilityIdentifiers.swift
│   ├── Wait.swift                  # waitReady, hittable, syncRoundTrip timeouts
│   ├── Navigation.swift            # openTab, goBack
│   └── Logs.swift                  # pullAppLogs, assertNoCrashInLog
├── Fixtures/
│   ├── DebugUser.swift             # debugUserId, device_token, authHeaders()
│   ├── ResetClient.swift           # DELETE recipes/collections/shopping/timers
│   ├── SeedClient.swift            # POST recipes, ingredients, shopping, timers
│   └── TestData.swift              # deterministic names, ingredient fixtures
├── Pages/                          # один файл на экран
│   ├── RecipeListPage.swift
│   ├── RecipeDetailPage.swift
│   ├── ShoppingListPage.swift
│   ├── CollectionsPage.swift
│   ├── AccountPage.swift
│   ├── DiscoverPage.swift
│   ├── AssistantPage.swift
│   ├── TimersPage.swift
│   ├── ImportPage.swift
│   └── AuthPage.swift
└── Specs/                          # 1 файл = 1 feature spec
    ├── AppShellNavigationSpec.swift      # 007
    ├── RecipeEditingSpec.swift           # 002
    ├── ShoppingListCompletionSpec.swift  # 024
    ├── AccountSettingsSpec.swift         # 013
    ├── DiscoverPublicSpec.swift          # 011
    ├── YrsNativeReadSpec.swift           # 001
    ├── DescriptionDisplaySpec.swift      # 004
    ├── RecipeCollectionsSpec.swift       # 026
    ├── CollectionMutationsSpec.swift     # 008
    ├── RecipeImportSpec.swift            # 010
    ├── PaprikaCroutonImportSpec.swift    # 027
    ├── AccountDataExportImportSpec.swift # 029
    ├── ImportDecompressionBombSpec.swift # 032
    ├── NativeExportAmountTextSpec.swift  # 033
    ├── AppLoggingSpec.swift              # 028
    ├── TimersSyncSpec.swift              # 014
    ├── AssistantSpec.swift               # 015
    ├── AssistantFullSpec.swift           # 021
    ├── RecipeDescriptionInlineEditSpec.swift # 019
    ├── DescriptionEditorRichtextSpec.swift   # 018
    ├── DescriptionEditorSpec.swift       # 006
    ├── AuthDeviceTokensSpec.swift        # 041
    ├── AuthStaleSessionRecoverySpec.swift # 054
    ├── AccountSettingsSpec.swift         # 013 + 055 (account deletion)
    ├── SharingSpec.swift                 # 012
    ├── AccountTelegramExportSpec.swift   # 020
    ├── I18nNewViewsSpec.swift            # 022
    ├── ErrorI18nSpec.swift               # 031
    ├── PushNotificationsSpec.swift       # 023
    ├── RecipeImageUploadSpec.swift       # 016
    ├── IngredientIllustrationsSpec.swift # 043
    ├── PublicImageCacheSpec.swift        # 045
    ├── ShareExtensionSpec.swift          # 025
    ├── TimerNotificationActionsSpec.swift # 036
    ├── DiscoverEnablementSpec.swift      # 017
    ├── FeatureAdoptionTrackerSpec.swift  # 038
    └── FeatureAdoptionGuidesSpec.swift   # 040
```

## Покрытие по фазам

| Iteration | Spec IDs | Файлов | Статус |
|-----------|----------|--------|--------|
| 0 — Infrastructure | — | 20 (BaseTestCase, Helpers, Fixtures, Pages) | ✅ done (2026-07-24) |
| 1 — Core flow | 007, 002, 024, 013, 011 | 5 | ✅ done (2026-07-24) |
| 2 — Read & list | 001, 004, 026, 008 | 4 | ✅ done (2026-07-24) |
| 3 — Import & export | 010, 027, 029, 032, 033, 028 | 6 | ✅ done (2026-07-24) |
| 4 — Realtime & assistant | 014, 015, 021, 019, 018, 006 | 6 | ✅ done (2026-07-24) |
| 5 — Auth, sharing, account | 041, 054, 055, 012, 020, 022, 031, 023 | 8 | ✅ done (2026-07-24); 055 added 2026-08-01 |
| 6 — Native-only features | 016, 043, 045, 025, 036, 017, 038, 040 | 8 | ✅ done (2026-07-24) |
| 7 — Extensions (optional) | 030, 044, 039, 046 | — | 🟡 требует отдельный test target; см. «Исключения» |

Итого: **39 спеков**, 7 исключений.

## Исключения (не E2E-тестируются)

| Spec | Причина |
|------|---------|
| **034** architecture-dedup-truth | Архитектурный рефакторинг, нет UI |
| **035** architecture-di-observable | Архитектурный рефакторинг, нет UI |
| **037** documentmanager-readers-extraction | Внутренний рефакторинг DocumentManager |
| **042** discover-observable-models | Observable-модельный рефакторинг, unit-only |
| **005** mobile-web-parity-roadmap | Roadmap-документ, не фича |
| **030** timer-widget | Widget extension — недоступен из XCTest UI |
| **044** timer-live-activity | Live Activity — недоступна из XCTest UI |
| **039** watchos-timers | WatchOS target — отдельный host |

## Запуск

```bash
# Полный прогон (iPhone 17 + Watch / iOS 26.3 — см. docs/AGENT-WORKFLOW.md)
xcodebuild test \
  -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5' \
  -only-testing:RecipeScalerNativeUITests

# Один spec
xcodebuild test \
  -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5' \
  -only-testing:RecipeScalerNativeUITests/AppShellNavigationSpec
```

## Риски и mitigation

| Риск | Mitigation |
|------|-----------|
| Reset debug-user state параллельно с другим разработчиком | Все E2E-прогоны последовательны; при CI-изоляции каждый PR на свой device_token |
| Realtime/sync флакает | Каждый sync-test использует `Wait.syncRoundTrip` (30 с) с понятным `XCTFail`-сообщением |
| LLM-зависимые тесты (010 import, 021 assistant) | UI-flow проверки без assertion'а на конкретный ответ LLM |
| Extensions (widget/Live Activity) недоступны из XCTest | Явно пропущены 030/044/039; для них — отдельный test target |

## Настройка окружения

- **`E2E_DEBUG_DEVICE_TOKEN`** (опционально): device-токен для debug-пользователя. Если не задан, `DebugUser` использует встроенный fallback.
- **`AGENT_DEBUG_LOG_DISABLED`** = `0` (всегда): crash-detection из NDJSON лога активен.
