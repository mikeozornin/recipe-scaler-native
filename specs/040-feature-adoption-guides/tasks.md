# Задачи: feature adoption guides

Чеклист выполнения. Зачеркиваем пункт по факту, не заранее.

## Spec Kit

- [x] `spec.md` — постановка, user stories, медиа-брифы, контент гайдов
- [x] `plan.md` — архитектура, фазы, файлы, риски
- [x] `tasks.md` — этот файл

## Фаза A — Foundation (4 текстовых гайда)

### A.1 Модели контента

- [ ] `RecipeScalerNative/Models/FeatureAdoptionGuideContent.swift` (новый)
  - [ ] `struct FeatureAdoptionGuideContent` (item, hasVideo, videoResourceName, screenshotAssetNames, exampleImages, primaryCTA)
  - [ ] `struct GuideExampleImage` (assetName, accessibilityLabelKey)
  - [ ] `enum GuideCTA` (.openImportTab, .openAssistant, .openProfileTelegram, .openSafari, .openProfilePublicSettings)
  - [ ] `Sendable`, нет `@Observable`
  - [ ] `var howStepKeys: [LocalizedStringKey]` через switch per item

### A.2 Расширение FeatureAdoptionItem

- [ ] `RecipeScalerNative/Models/FeatureAdoptionItem.swift` (правка)
  - [ ] `var isGuideAvailable: Bool` (false для `.installedNativeApp`)
  - [ ] `var guideContent: FeatureAdoptionGuideContent` — computed per case
  - [ ] CTA mapping: 4 гайда → nil (used_shopping_list, created_collection, shared_recipe, created_recipe — нет, см. ниже)
  - [ ] `shared_recipe` → `.openProfilePublicSettings`
  - [ ] Все i18n-ключи — литералы, не интерполяция

### A.3 FeatureAdoptionGuideView (без карусели и видео)

- [ ] `RecipeScalerNative/Views/FeatureAdoptionGuideView.swift` (новый)
  - [ ] `let item: FeatureAdoptionItem`, `@Environment(FeatureAdoptionStore.self)`
  - [ ] Status badge (`account.feature-adoption.state.done` / `.pending`)
  - [ ] Блок why → `Text(item.guideContent.whyKey).appBody()`
  - [ ] Блок как → `ForEach howStepKeys` с нумерацией
  - [ ] CTA primary `.borderedProminent` если primaryCTA != nil
  - [ ] `ScrollView` + `VStack`, `.appListBodyTypography` если уместно
  - [ ] navigationTitle = `item.titleKey`
  - [ ] `#Preview` × 3: done+CTA, pending+no-CTA, en-locale

### A.4 Кликабельность в списке

- [ ] `RecipeScalerNative/Views/FeatureAdoptionDetailView.swift` (правка)
  - [ ] `FeatureAdoptionRow`: если `item.isGuideAvailable` → `NavigationLink(value: item)` + chevron
  - [ ] `.installedNativeApp` → без link
  - [ ] `.navigationDestination(for: FeatureAdoptionItem.self)` в `FeatureAdoptionDetailView.body`

### A.5 Плейсхолдер для dev

- [ ] `RecipeScalerNative/Views/GuideAssetPlaceholder.swift` (новый)
  - [ ] Серый фон + подпись имени ассета/видео по центру
  - [ ] Используется в `#Preview` и как fallback когда imageset/mp4 отсутствует

### A.6 i18n для 4 гайдов

- [ ] `RecipeScalerNative/Resources/Localizable.xcstrings` (правка)
  - [ ] `account.feature-adoption.guide.created_recipe.{why,how.1,how.2,how.3,how.4}` (ru + en)
  - [ ] `account.feature-adoption.guide.created_collection.{why,how.1,how.2,how.3}` (ru + en)
  - [ ] `account.feature-adoption.guide.shared_recipe.{why,how.1,how.2,how.3,cta,cta-done}` (ru + en)
  - [ ] `account.feature-adoption.guide.used_shopping_list.{why,how.1,how.2,how.3}` (ru + en)

### A.7 Environment для CTA

- [ ] `RecipeScalerNative/Utils/FeatureAdoptionGuideCta.swift` (новый)
  - [ ] `struct FeatureAdoptionGuideCtaHandler { openAssistant, openImport, openProfileTelegram, openProfilePublicSettings, openSafari }`
  - [ ] `EnvironmentKey` + `EnvironmentValues.featureAdoptionGuideCta`
  - [ ] Default value — все замыкания `{}`
- [ ] `RecipeScalerNative/Views/AccountView.swift` (правка)
  - [ ] `.environment(\.featureAdoptionGuideCta, …)` для `openProfilePublicSettings` (scroll к `publicRecipesSection`)
  - [ ] Scroll anchor: `publicRecipesSection` через `ScrollViewReader` или `.scrollPosition(id:)`

### A.8 Контрольная точка A

- [ ] Build зелёный
- [ ] 4 гайда открываются, текст локализован (ru + en)
- [ ] CTA `shared_recipe` скроллит к public-профилю в `AccountView`
- [ ] `scripts/verify-feature-adoption-guides.sh` — написан и проходит

## Фаза B — Carousel + Assistant

### B.1 GuideExampleCarousel

- [ ] `RecipeScalerNative/Views/GuideExampleCarousel.swift` (новый)
  - [ ] `let images: [GuideExampleImage]`
  - [ ] `TabView` + `.tabViewStyle(.page(indexDisplayMode: .always))`
  - [ ] Image с `.resizable().aspectRatio(.fit)`, corner radius 12
  - [ ] `accessibilityElement(children: .ignore)` + `accessibilityLabel(image.accessibilityLabelKey)`
  - [ ] `accessibilityValue` «N из M» через `appPluralizedString`
  - [ ] Fallback на `GuideAssetPlaceholder` если imageset отсутствует
- [ ] `RecipeScalerNative/Utils/GuideAssetResolver.swift` (новый)
  - [ ] `static func assetName(_ base: String) -> String` → `"\(base)_ru"` / `"\(base)_en"` по `AppLanguagePreference.current`

### B.2 CTA openAssistant wiring

- [ ] `RecipeScalerNative/Views/AppShellView.swift` (правка)
  - [ ] `.environment(\.featureAdoptionGuideCta, …)` с реализацией `openAssistant`
  - [ ] В `openAssistant`: сброс navigation stack Profile + `coordinator.selectedTab = .profile` + `showAssistant = true`
  - [ ] Также заполнить `openImport` → `coordinator.presentImport()`

### B.3 Гайд sent_assistant_message

- [ ] `Localizable.xcstrings` (правка)
  - [ ] `account.feature-adoption.guide.sent_assistant_message.{why,how.1,how.2,how.3,carousel-hint,cta,cta-done}` (ru + en)
  - [ ] `account.feature-adoption.guide.sent_assistant_message.example.{1..5}.accessibility-label` (ru + en)
- [ ] `FeatureAdoptionItem.guideContent` для `.sentAssistantMessage`: exampleImages = 5 шт.
- [ ] `FeatureAdoptionGuideView`: рендер `GuideExampleCarousel` если `exampleImages != nil`, между «Как» и CTA
- [ ] carousel-hint — `Text(item.guideContent.carouselHintKey).appFootnote()` под каруселью

### B.4 Скриншоты ассистента (пользователь)

- [ ] `Resources/GuideAssets.xcassets/guide_sent_assistant_message_ex_01_ru.imageset/` (RU)
- [ ] `..._ex_02_ru`, `..._ex_03_ru`, `..._ex_04_ru`, `..._ex_05_ru`
- [ ] `..._ex_01_en` … `..._ex_05_en` (EN)
- [ ] Все 10 imageset'ов представлены в `FeatureAdoptionGuideContentTests`

### B.5 Контрольная точка B

- [ ] Build зелёный
- [ ] Карусель листается, page dots видны
- [ ] VoiceOver: «Пример 2 из 5, [description]»
- [ ] CTA «Спросить ассистента» открывает `AssistantSheet`

## Фаза C — Видео + Import и Telegram

### C.1 GuideVideoPlayer

- [ ] `RecipeScalerNative/Views/GuideVideoPlayer.swift` (новый)
  - [ ] `let videoResourceName: String?`
  - [ ] Загрузка через `Bundle.main.url(forResource:, withExtension: "mp4")`
  - [ ] `AVPlayer` + `VideoPlayer` (AVKit) или `UIViewRepresentable`
  - [ ] `player.isMuted = true` по умолчанию
  - [ ] Контролы: play/pause, fullscreen
  - [ ] Fallback на `GuideAssetPlaceholder` если ресурс отсутствует

### C.2 Гайд imported_recipe

- [ ] `Localizable.xcstrings`: `account.feature-adoption.guide.imported_recipe.{why,how.1..4,cta,cta-done}` (ru + en)
- [ ] `guideContent` для `.importedRecipe`: `hasVideo: true`, `videoResourceName: "guide_imported_recipe_video"`, `primaryCTA: .openImportTab`
- [ ] `FeatureAdoptionGuideView`: между why и how — `GuideVideoPlayer` если `hasVideo`

### C.3 Гайд connected_telegram

- [ ] `Localizable.xcstrings`: `account.feature-adoption.guide.connected_telegram.{why,how.1..4,cta,cta-done}` (ru + en)
- [ ] `guideContent` для `.connectedTelegram`: `hasVideo: true`, `videoResourceName: "guide_connected_telegram_video"`, `primaryCTA: .openProfileTelegram`
- [ ] CTA `.openProfileTelegram` → scroll к `telegramSection` в `AccountView` (дополнить `featureAdoptionGuideCta`)

### C.4 Видео (пользователь)

- [ ] `Resources/GuideVideos/guide_imported_recipe_video.mp4` (H.264, ≤5 MB)
- [ ] `Resources/GuideVideos/guide_connected_telegram_video.mp4` (H.264, ≤5 MB)
- [ ] `Resources/GuideAssets.xcassets/guide_imported_recipe_0{1..3}.imageset/` (3 шт.)
- [ ] `Resources/GuideAssets.xcassets/guide_connected_telegram_0{1..2}.imageset/` (2 шт.)

### C.5 Бандлинг

- [ ] `GuideVideos/` folder — target membership: только `RecipeScalerNative` (НЕ extensions)
- [ ] Build Phases → Copy Bundle Resources — проверить наличие mp4
- [ ] Ручная проверка: `Bundle.main.url(forResource: "guide_imported_recipe_video", withExtension: "mp4")` не nil в runtime

### C.6 Контрольная точка C

- [ ] Build зелёный
- [ ] Видео воспроизводятся офлайн
- [ ] CTA импорта открывает `ImportRecipeSheet`
- [ ] CTA Telegram скроллит к секции Telegram в `AccountView`
- [ ] IPA размер увеличился на ≤10 MB

## Фаза D — MCP + финализация

### D.1 Гайд connected_mcp_assistant

- [ ] `Localizable.xcstrings`: `account.feature-adoption.guide.connected_mcp_assistant.{why,how.1..3,carousel-hint,cta}` (ru + en)
- [ ] `account.feature-adoption.guide.connected_mcp_assistant.example.{1..3}.accessibility-label` (ru + en)
- [ ] `guideContent` для `.connectedMcpAssistant`: exampleImages = 3 шт., `primaryCTA: .openSafari(URL("https://recipe-scaler.ru/mcp")!)`
- [ ] CTA `.openSafari` → `UIApplication.shared.open(url)` (внешний Safari)
- [ ] `featureAdoptionGuideCta.openSafari` реализация

### D.2 Скриншоты MCP (пользователь)

- [ ] `guide_connected_mcp_assistant_0{1..2}.imageset/` (2 шт.)
- [ ] `guide_connected_mcp_assistant_ex_0{1..3}_ru.imageset/` + `_en` (6 imageset'ов)

### D.3 Логирование и аудит

- [ ] `AppLog.info(.ui, "feature_adoption_guide_opened", data: ["item": item.rawValue])` в `FeatureAdoptionGuideView.onAppear`
- [ ] `AppLog.info(.ui, "feature_adoption_guide_cta", data: ["item": ..., "cta": ...])` в обработчике CTA
- [ ] `RecipeScalerNativeTests/LocalizationConsistencyTests.swift` — расширить на все `guide.*` ключи
- [ ] `RecipeScalerNativeTests/FeatureAdoptionGuideContentTests.swift` (новый)
  - [ ] `howStepKeys` per case — нет nil/пустых
  - [ ] CTA mapping per case соответствует таблице в spec
  - [ ] Все `LocalizedStringKey` — литералы, не интерполяция (grep на `\\(` в ключах)

### D.4 Контрольная точка D (финальная)

- [ ] Build зелёный (`xcodebuild build`)
- [ ] `xcodebuild test` — LocalizationConsistencyTests green
- [ ] VoiceOver audit на 2 гайдах: assistant + import
- [ ] Тест на EN-локали: пройти все 8 гайдов, убедиться что нет hardcoded RU
- [ ] TestFlight smoke: реальные устройство, все 8 CTA работают

## Feature flag (опционально для релиза)

- [ ] `UserDefaults.standard.bool(forKey: "feature-adoption-guides.enabled")` — default false
- [ ] `FeatureAdoptionRow`: если флаг off → без chevron, без link
- [ ] Debug-меню: toggle для smoke
- [ ] Перед релизом — hardcode в `true` или убрать флаг
