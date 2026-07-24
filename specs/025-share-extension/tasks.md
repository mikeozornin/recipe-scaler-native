# Задачи: Share Extension, Action Extension, Deep Link

**Вход**: артефакты из `/specs/025-share-extension/`

**Предусловия**: spec.md, plan.md

**Аудит 2026-06-15 (обновлено 2026-06-15)**: фазы 1–6 в основном реализованы в коде; открыты T001 (portal — требует платный аккаунт разработчика), T038 (стриминг фото — оптимизация памяти), T046 (ручной smoke — требует device с extensions). Скрипты `scripts/verify-share-extension.sh` и `DeepLinkRouterTests` существуют и проходят на симуляторе.

**Тесты**: минимум — `DeepLinkRouterTests`, `LocalizationConsistencyTests` (расширение).

**Организация**: задачи сгруппированы по фазам; пользовательские истории US1–US8 покрываются фазами 4–6.

## Формат: `[ID] [P?] [Story] Описание`

- **[P]**: можно параллельно (разные файлы, нет зависимостей от незавершённых задач)
- **[Story]**: пользовательская история (US1–US8), если применимо
- Пути файлов — от корня репозитория

---

## Фаза 1: Setup (Xcode UI, вручную)

**Цель**: создать 3 target'а + App Group entitlements

**⚠️ КРИТИЧНО**: эти задачи выполняются вручную в Xcode по чеклисту из `quickstart.md`. Агент может только писать код и обновлять существующие файлы; создание target'ов в pbxproj без UI рискованно.

- [ ] T001 Создать App Group `group.ru.recipescaler.RecipeScaler` на Apple Developer Portal (team `ZBPX4JYT24`) — **блокер**: требует платный Apple Developer Program; код использует этот group id во всех entitlements (проверено verify-share-extension.sh)
- [x] T002 Создать target `RecipeScalerCore` (Cocoa Touch Framework, Swift, iOS 17). Bundle ID `ru.recipescaler.RecipeScaler.Core`
- [x] T003 Создать target `ShareExtension` (Share Extension template). Bundle ID `ru.recipescaler.RecipeScaler.Share`
- [x] T004 Создать target `ActionExtension` (Action Extension template, "Presents user interface"). Bundle ID `ru.recipescaler.RecipeScaler.Action`
- [x] T005 На 3 target'ах (main app, Share, Action) добавить capability "App Groups" → выбрать `group.ru.recipescaler.RecipeScaler`
- [x] T006 На main app target → General → Frameworks → добавить `RecipeScalerCore.framework` → "Embed & Sign"
- [x] T007 На ShareExtension + ActionExtension → Frameworks → `RecipeScalerCore.framework` → "Do Not Embed"
- [x] T008 Embed App Extensions build phase главного аппа должен содержать ShareExtension + ActionExtension
- [x] T009 В scheme `RecipeScalerNative` → Build → выбрать все 4 target'а
- [x] T010 [P] Добавить в main app `Info.plist` `CFBundleURLTypes` для URL scheme `recipe-scaler` (см. spec FR-SE-007)

**Контрольная точка**: пустой проект собирается; Share Extension появляется в Share Sheet (с шаблонным UI от Xcode)

---

## Фаза 2: Framework RecipeScalerCore (рефакторинг)

**Цель**: выделить network/import слой в shared framework

### Перенос файлов (target membership меняется на RecipeScalerCore)

- [x] T011 Перенести `RecipeScalerNative/Config.swift` → `RecipeScalerCore/Config/Config.swift`. Все типы сделать `public`
- [x] T012 [P] Перенести `RecipeScalerNative/Services/APIClient.swift` → `RecipeScalerCore/Networking/APIClient.swift`
  - Убрать `@MainActor` с класса
  - `authToken`, `userId` хранить под `Mutex<AuthState>` (Swift Concurrency) или `os.OSUnfairLock`
  - Все методы `nonisolated`
  - `APIResponse`, `CachedAPIResponse`, `APIError` → `public`
- [x] T013 [P] Перенести `RecipeScalerNative/Services/APIClient+Requests.swift` → `RecipeScalerCore/Networking/APIClient+Requests.swift`. Методы `nonisolated`; `AnyEncodable` → `public`
- [x] T014 [P] Перенести `RecipeScalerNative/Services/RecipeImportAPI.swift` → `RecipeScalerCore/Import/RecipeImportAPI.swift`
  - Убрать `@MainActor enum`
  - `ImportRecipesResultDTO` → `public struct`
  - Методы `public static func ... async throws`
- [x] T015 [P] Перенести `RecipeScalerNative/Utils/ImportContentClassifier.swift` → `RecipeScalerCore/Import/ImportContentClassifier.swift`. Типы `public`
- [x] T016 [P] Перенести `RecipeScalerNative/Utils/ImportPhotoValidator.swift` → `RecipeScalerCore/Import/ImportPhotoValidator.swift`
  - `ImportPhotoItem` → `public struct`
  - `ValidationError` → `public`
  - `validate(items:)` → `public static`
  - Убрать зависимости от `PhotosPicker` (оставить только типы)
- [x] T017 [P] Перенести `RecipeScalerNative/Utils/ImportErrorLocalizer.swift` → `RecipeScalerCore/Import/ImportErrorLocalizer.swift`
  - Добавить параметр `bundle: Bundle = .main`
  - Все `Bundle.currentLocalizedString` заменить на `bundle.localizedString(forKey:value:table:)`

### Совместимость с main app

- [x] T018 В main app там, где нужны `APIClient` / `RecipeImportAPI` / `Config` / `APIResponse` / `AnyEncodable` — добавить `import RecipeScalerCore`
- [x] T019 Убрать перенесённые файлы из Compile Sources главного target'а (target membership: только `RecipeScalerCore`)

**Контрольная точка**: `xcodebuild build` зелёный; main app работает идентично до рефакторинга

---

## Фаза 3: SharedAuthStore + i18n для framework

**Цель**: расшарить userId через App Group + добавить локализацию для extension

### Auth

- [x] T020 Создать `RecipeScalerCore/Auth/SharedAuthStore.swift` (см. plan Фаза 2). Тип `public enum`, статические свойства `userId`, `clear()`
- [x] T021 Расширить `RecipeScalerNative/Services/AuthService.swift` — после успешного логина писать `SharedAuthStore.userId = userId`; при логауте `SharedAuthStore.clear()`
- [x] T022 В `RecipeScalerNative/ContentView.swift` init — заполнять `APIClient.shared.configure(userId: SharedAuthStore.userId ?? authService.userId)` (переходная совместимость)

### i18n

- [x] T023 Создать `RecipeScalerCore/Resources/Shared.xcstrings` с ключами (см. spec FR-SE-010): `share-extension.*` (11 шт) + дублирование `import.*` ключей из main xcstrings
- [x] T024 [P] Расширить `RecipeScalerNativeTests/LocalizationConsistencyTests.swift` — добавлен `testShareExtensionKeysResolveInBothLanguages` (парсит `Shared.xcstrings` JSON напрямую; 10 `share-extension.*` ключей в en+ru, 2026-06-15)

**Контрольная точка**: `SharedAuthStore.userId` возвращает валидный id из main app и из extension; тесты локализации зелёные

---

## Фаза 4: Deep Link (main app)

**Цель**: main app ловит `recipe-scaler://recipe/{id}` и открывает рецепт

- [x] T025 Создать `RecipeScalerNative/Routing/DeepLinkRouter.swift` (см. plan Фаза 5)
- [x] T026 Расширить `RecipeScalerNative/RecipeScalerNativeApp.swift` — добавить `.onOpenURL` в `WindowGroup`
- [x] T027 Расширить `RecipeScalerNative/Views/AppShellView.swift` — `.onAppear` + `.onReceive(.openRecipeRequested)` для потребления pending id
- [x] T028 [US6] Создать `RecipeScalerNativeTests/DeepLinkRouterTests.swift` — 8 кейсов: valid URL, uppercase UUID → lowercase, wrong scheme, wrong host, non-UUID path, clear, consumePendingRecipeId legacy path (×2)

**Контрольная точка**: `xcrun simctl openurl booted recipe-scaler://recipe/test-id` открывает main app и пытается показать рецепт (fallback на missing в `YDocRecipeDetailView`)

---

## Фаза 5: Share Extension (US1, US2, US3, US4)

**Цель**: импорт из любого аппа через системный Share Sheet

### Scaffold (Xcode template сгенерировал; настроить)

- [x] T029 [P] Заменить `ShareExtension/Info.plist` — `NSExtensionActivationRule` по spec FR-SE-003; `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).ShareViewController`
- [x] T030 [P] Настроить `ShareExtension/ShareExtension.entitlements` — App Group `group.ru.recipescaler.RecipeScaler`
- [x] T031 [P] Добавить `import RecipeScalerCore` в `ShareExtension/ShareViewController.swift` (template)

### Content extraction

- [x] T032 Создать `ShareExtension/ShareContentLoader.swift` — async/await обёртки вокруг `NSItemProvider.loadItem(forTypeIdentifier:)` для `public.url`, `public.text`, `public.image`. Возвращает `ContentKind`
- [x] T033 [US2, US3] Создать `RecipeScalerCore/UI/ShareContentClassifier.swift` — чистая логика приоритета URL > Images > Text, делегирует `ImportContentClassifier` для single-URL текста; `ShareContentLoader.classify` теперь вызывает его. `RecipeScalerNativeTests/ShareContentClassifierTests.swift` (9 кейсов, 2026-06-15).

### UI

- [x] T034 [US1, US4] Создать `ShareExtension/ShareView.swift` — SwiftUI state machine: preview / loading / success / error. Локализация через `Bundle.module`
- [x] T035 [US7] В `ShareView` добавить проверку `SharedAuthStore.userId` — если nil, экран ошибки `share-extension.error-not-signed-in`
- [x] T036 [US1] Реализовать кнопку «Открыть рецепт» → `extensionContext.open(URL(string: "recipe-scaler://recipe/\(id)")!)` → `completeRequest`
- [x] T037 [US8] Реализовать экран ошибки с локализацией через `ImportErrorLocalizer.localize(error, bundle: .module)`, кнопки «Повторить» / «Отмена»
- [ ] T038 [US4] Реализовать стриминг фото (autoreleasepool per item, не держать `[Data]` целиком) для обхода memory limit

### Хост UIViewController

- [x] T039 [P] Переписать `ShareExtension/ShareViewController.swift` (template) — `UIHostingController(rootView: ShareView(...))`; переопределить `didSelectCancel` → `extensionContext.cancelRequest(withError:)`

**Контрольная точка**: SC-001 (Safari → Share → успех → Open), SC-002 (Messages), SC-003 (Telegram), SC-004 (Photos)

---

## Фаза 6: Action Extension (US5)

**Цель**: контекстное меню Safari

### Scaffold

- [x] T040 [P] Настроить `ActionExtension/Info.plist` — `NSExtensionJavaScriptPreprocessingFile: GetURLFromPage`, `NSExtensionActivationRule` (см. spec FR-SE-006)
- [x] T041 [P] Настроить `ActionExtension/ActionExtension.entitlements` — App Group

### Preprocessing

- [x] T042 [US5] Создать `ActionExtension/GetURLFromPage.js` (см. plan Фаза 6)

### UI

- [x] T043 [US5] Переписать `ActionExtension/ActionViewController.swift` — извлечь URL из `NSExtensionJavaScriptPreprocessingResultsKey` → хостить SwiftUI `ShareView(content: .url(url))` из RecipeScalerCore

**Контрольная точка**: SC-005 (Safari long-press → Action Extension → импорт)

---

## Фаза 7: Polish и верификация

**Цель**: документация, ручной smoke, обновление spec 010

- [x] T044 [P] Обновить `specs/010-recipe-import/spec.md` — строка аудита Share/Action Extension расширена (добавлено указание на spec 025 + артефакты 2026-06-15)
- [x] T045 [P] Создан `scripts/verify-share-extension.sh` — проверки pbxproj target'ов (3), entitlements (App Group), Info.plist URL scheme, DeepLinkRouter wiring, SharedAuthStore, Shared.xcstrings ключи, ShareContentClassifier; затем `xcodebuild build` + 3 test suites (DeepLink, Classifier, Localization)
- [ ] T046 Полный ручной smoke по `quickstart.md` (Safari/Messages/Telegram/Photos/long-press)

**Контрольная точка**: SC-001..SC-010 зелёные

---

## Зависимости и порядок

```text
Фаза 1 (Setup, вручную)
    ↓
Фаза 2 (Framework extraction)
    ↓
Фаза 3 (Auth + i18n) ── параллельно с Фазой 4
    ↓                       ↓
    └───────────┬───────────┘
                ↓
        Фаза 5 (Share Extension)
                ↓
        Фаза 6 (Action Extension)
                ↓
        Фаза 7 (Polish)
```

### Параллельные возможности

- T002 + T003 + T004 (создание target'ов) — последовательно в одной Xcode-сессии, но логически независимы
- T011..T017 — перенос файлов параллелен (после T002)
- T023 + T024 — i18n параллельно фазе 2
- T028 (тесты DeepLink) — параллельно фазе 5
- T029 + T030 + T031 (scaffold) — параллельно
- T040 + T041 (Action scaffold) — параллельно фазе 5

---

## Стратегия реализации

### MVP (после Фазы 4)

Минимальный жизнеспособный набор:

1. Фазы 1–4: framework extraction + deep link.
2. Фаза 5: Share Extension, только URL (US1).
3. Ручной smoke: Safari → Share → Импорт → Открыть рецепт.

Photos (US4) и Action Extension (US5) — после подтверждения MVP.

### Полный scope

Все 7 фаз; полный smoke; обновление spec 010.
