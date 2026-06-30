# План реализации: гайды по пунктам feature adoption

**Spec**: [spec.md](./spec.md)
**Дата**: 2026-06-30
**Scope**: только native iOS. Backend не трогается (использует 038).

## Стратегия

Сначала делаем фундамент и **4 текстовых гайда без CTA/карусели/видео** — это проверка паттерна на живом UI за минимум усилий. Затем подключаем карусель скриншотов и CTA-навигацию. Видео и MCP — последними, потому что требуют внешних ассетов (mp4) и веб-страницы.

Скриншоты в xcassets кладёт пользователь вручную. План строится на плейсхолдерах (`#colorLiteral` серый прямоугольник + название ассета в центре), которые потом заменяются на реальные imageset'ы. Видео записывает пользователь; план включает `AVPlayer`-обёртку и бандлинг mp4, на этапе верстки — `hasVideo=false`.

## Декомпозиция

### Фаза A — Foundation

1. **Модели контента** — `RecipeScalerNative/Models/FeatureAdoptionGuideContent.swift`.
   - `struct FeatureAdoptionGuideContent` (см. spec.md § Модель контента).
   - `struct GuideExampleImage { assetName, accessibilityLabelKey }`.
   - `enum GuideCTA`: `openImportTab`, `openAssistant`, `openProfileTelegram`, `openSafari(URL)`, `openProfilePublicSettings`.
   - `Sendable`, без `@Observable` — чистые данные.

2. **Расширение `FeatureAdoptionItem`** — в `FeatureAdoptionItem.swift`.
   - `var isGuideAvailable: Bool { self != .installedNativeApp }`.
   - `var guideContent: FeatureAdoptionGuideContent` — computed, возвращает готовый контент per case. i18n-ключи — `LocalizedStringKey`-литералы (не интерполяция).
   - CTA-маппинг — здесь же, per case. Для 4 гайдов CTA = `nil`.

3. **`FeatureAdoptionGuideView`** (без карусели/видео) — `RecipeScalerNative/Views/FeatureAdoptionGuideView.swift`.
   - `let item: FeatureAdoptionItem` + `@Environment(FeatureAdoptionStore.self)` для статуса.
   - Структура: status badge → why → шаги (`ForEach how.1...N` пока через switch по item, см. риски §3) → CTA primary (если не nil).
   - Стилизация: `ScrollView` + `VStack`; `.appBody()` / `.appFootnote()` по UI.md; `Color(uiColor: .systemGroupedBackground)`.
   - i18n только через `Text(LocalizedStringKey)` — без интерполяции.
   - Previews: 3 стейта — done/pending, с CTA / без CTA, ru/en.

4. **Кликабельность в `FeatureAdoptionDetailView`** — правка `FeatureAdoptionRow`.
   - Если `item.isGuideAvailable`: обернуть содержимое в `NavigationLink(value: item)` + trailing chevron.
   - `installedNativeApp`: без link, текущий вид.
   - В `FeatureAdoptionDetailView.body` добавить `.navigationDestination(for: FeatureAdoptionItem.self) { FeatureAdoptionGuideView(item: $0) }`.
   - Дополнительно: пустой `GuideAssetPlaceholder` view (серый фон + подпись) — для будущего использования в Previews пока нет реальных скриншотов.

5. **i18n Foundation** — 4 гайда без CTA + общий ключ.
   - `account.feature-adoption.guide.created_recipe.why / how.1 / how.2 / how.3 / how.4`
   - `account.feature-adoption.guide.created_collection.why / how.1 / how.2 / how.3`
   - `account.feature-adoption.guide.shared_recipe.why / how.1 / how.2 / how.3 / cta / cta-done`
   - `account.feature-adoption.guide.used_shopping_list.why / how.1 / how.2 / how.3`
   - ru + en значения — из spec.md § Контент гайдов.

6. **CTA-навигация для `shared_recipe`** — pop Profile, scroll к `publicRecipesSection`.
   - В `AccountView` повесить `@State private var publicRecipesScrollAnchor: String?` и `.scrollPosition(id:)` (или `ScrollViewReader` если секции уже в List).
   - `FeatureAdoptionGuideView` прокидывает CTA-колбэк через `@Environment(\.openFeatureAdoptionCTA)` — кастомный `EnvironmentKey` (см. Фаза B, ассистент).
   - На этом этапе создаём `FeatureAdoptionGuideCTAEnvironment` с одним кейсом `openProfilePublicSettings`.

7. **Verify-скрипт `scripts/verify-feature-adoption-guides.sh`** — grep на новые ключи в xcstrings + новые файлы + `xcodebuild build` (через fix-until-green).

**Контрольная точка A:** 4 гайда открываются из списка, текст локализован, CTA public-profile работает. Build зелёный.

### Фаза B — Carousel + Assistant guide

8. **`GuideExampleCarousel`** — `RecipeScalerNative/Views/GuideExampleCarousel.swift`.
   - `let images: [GuideExampleImage]`.
   - `TabView` с `.tabViewStyle(.page(indexDisplayMode: .always))`.
   - На каждой странице: `Image(uiType:)` с `.resizable().aspectRatio(contentMode: .fit)`, скругление 12 pt.
   - `accessibilityElement(children: .ignore)` + `accessibilityLabel(Text(image.accessibilityLabelKey))` + `accessibilityValue("N из M")` (плюр. через `appPluralizedString`).
   - Если imageset отсутствует — fallback на `GuideAssetPlaceholder` с подписью имени ассета (для dev-режима).
   - Под каруселью `Text(item.guideContent.carouselHintKey)` `.appFootnote()`.

9. **`AssistantCTAEnvironment`** — `@Environment(\.openAssistant)` в `AppShellView`.
   - Новый `EnvironmentKey` `OpenAssistantKey` с `() -> Void`.
   - В `AppShellView` (где уже есть `@State showAssistant`) пробросить `.environment(\.openAssistant) { showAssistant = true; assistantRecipeContext.isAssistantSheetOpen = true }`.
   - Расширить `FeatureAdoptionGuideCTAEnvironment` из таска 6 — теперь он умеет `openAssistant` + `openProfilePublicSettings`.

10. **Гайд `sent_assistant_message`** — контент из spec.md.
    - i18n: `why / how.1 / how.2 / how.3 / carousel-hint / example.{1..5}.accessibility-label / cta / cta-done` (ru + en).
    - В `FeatureAdoptionItem.guideContent` для `.sentAssistantMessage`: `exampleImages` = 5 `GuideExampleImage`.
    - `FeatureAdoptionGuideView` обновить: рендерить `GuideExampleCarousel` если `exampleImages != nil`, между «Как» и CTA.
    - CTA `.openAssistant` через environment.

11. **Скриншоты ассистента** — пользователь снимает 5 кадров вручную с симулятора (RU-локаль) и кладёт в `Resources/GuideAssets.xcassets/guide_sent_assistant_message_ex_0{1..5}_ru.imageset/`.
    - EN-набор — отдельный imageset с суффиксом `_en`.
    - Лоадер: `GuideAssetResolver` выбирает imageset по `AppLanguagePreference.current`.

**Контрольная точка B:** гайд ассистента открывается, карусель листается, VoiceOver читает «Пример 2 из 5: …», CTA открывает `AssistantSheet`.

### Фаза C — Видео + Import и Telegram

12. **`GuideVideoPlayer`** — `RecipeScalerNative/Views/GuideVideoPlayer.swift`.
    - `AVPlayer`-обёртка через `VideoPlayer` (AVKit) или кастомный `UIViewRepresentable`.
    - `let videoResourceName: String?` — загружает из `Bundle.main.url(forResource:, withExtension: "mp4")`.
    - Контролы: play/pause, mute, fullscreen. Без autoplay (по spec US7 — inline + кнопка fullscreen).
    - Если ресурс отсутствует — `GuideAssetPlaceholder` с подписью «видео: <name>».
    - `import AVKit`.

13. **Гайд `imported_recipe`** — контент из spec.md + видео `guide_imported_recipe_video`.
    - i18n: `why / how.1..4 / cta / cta-done`.
    - В `guideContent` для `.importedRecipe`: `hasVideo: true`, `videoResourceName: "guide_imported_recipe_video"`, `primaryCTA: .openImportTab`.
    - `FeatureAdoptionGuideView`: между why и how вставить `GuideVideoPlayer`, если `hasVideo`.
    - CTA `.openImportTab` → через `@Bindable var coordinator` или `FeatureAdoptionGuideCTAEnvironment` с новым кейсом. Так как guide в стеке Profile, а импорт — модальный `coordinator.presentImport()` — передаём environment-action `openImport`.

14. **Гайд `connected_telegram`** — контент из spec.md + видео `guide_connected_telegram_video`.
    - i18n: `why / how.1..4 / cta / cta-done`.
    - В `guideContent`: `hasVideo: true`, `videoResourceName: "guide_connected_telegram_video"`, `primaryCTA: .openProfileTelegram`.
    - CTA `.openProfileTelegram` → pop до Profile + scroll к `telegramSection` (anchor id).

15. **Скриншоты и видео импорт/Telegram** — пользователь кладёт вручную.
    - Видео: `Resources/GuideVideos/guide_imported_recipe_video.mp4`, `guide_connected_telegram_video.mp4` (H.264, ≤5 MB каждое).
    - Скриншоты: `guide_imported_recipe_0{1..3}` (3 шт.) + `guide_connected_telegram_0{1..2}` (2 шт.).
    - На этом этапе `_ru`/`_en` суффиксы для скриншотов — опциональны; можно начать с одного набора.

16. **Добавить mp4 в Xcode target** — убедиться, что `RecipeVideos` folder добавлен в `RecipeScalerNative` target membership (Build Phases → Copy Bundle Resources). Без этого `Bundle.main.url` вернёт nil.

**Контрольная точка C:** гайды импорта и Telegram показывают видео, CTA работают. Build зелёный, IPA-размер разумный (<+10 MB).

### Фаза D — MCP + финализация

17. **Гайд `connected_mcp_assistant`** — контент из spec.md.
    - i18n: `why / how.1..3 / carousel-hint / example.{1..3}.accessibility-label / cta`.
    - В `guideContent`: `exampleImages` = 3 шт., `primaryCTA: .openSafari(URL("https://recipe-scaler.ru/mcp")!)` (placeholder URL; уточнить).
    - CTA `.openSafari` → `UIApplication.shared.open(url)` (внешний Safari, не InAppSafari).

18. **Скриншоты MCP** — пользователь кладёт 5 imageset'ов: `guide_connected_mcp_assistant_0{1..2}` + `guide_connected_mcp_assistant_ex_0{1..3}`.

19. **`AppLog` события** — `AppLog.info(.ui, "feature_adoption_guide_opened", data: ["item": item.rawValue])` в `.onAppear` guide; `feature_adoption_guide_cta` — в обработчике CTA.

20. **Локализация audit** — `LocalizationConsistencyTests` расширить на новые ключи. Прогнать `xcodebuild test -only-testing:RecipeScalerNativeTests/LocalizationConsistencyTests`.

21. **Layout audit** — если верстка от Figma не использовалась (текстовые гайды, нет pixel-perfect) — `audit-ui-layout.sh` опционален. Если есть макет — обязательно.

22. **Финальный fix-until-green** — `xcodebuild build`, проверка VoiceOver для 2 гайдов (assistant + import).

## Архитектурные решения

### 1. Environment actions для CTA

`FeatureAdoptionGuideView` сидит глубоко в стеке (Profile → Detail → Guide). Чтобы не прокидывать `coordinator` через init, вводим один кастомный `EnvironmentKey`:

```swift
private struct FeatureAdoptionGuideCtaKey: EnvironmentKey {
    static let defaultValue: FeatureAdoptionGuideCtaHandler = .init()
}

struct FeatureAdoptionGuideCtaHandler {
    var openAssistant: () -> Void = {}
    var openImport: () -> Void = {}
    var openProfileTelegram: () -> Void = {}
    var openProfilePublicSettings: () -> Void = {}
    var openSafari: (URL) -> Void = { _ in }
}

extension EnvironmentValues {
    var featureAdoptionGuideCta: FeatureAdoptionGuideCtaHandler {
        get { self[FeatureAdoptionGuideCtaKey.self] }
        set { self[FeatureAdoptionGuideCtaKey.self] = newValue }
    }
}
```

Заполняется в `AccountView` (или `AppShellView` — для `openAssistant`). Один environment — все 5 колбэков; view выбирает нужный по `primaryCTA`.

### 2. Шаги «Как» через switch per item

В spec.md шаги заданы как `how.1 ... how.N` с переменным N. Дешёвый вариант без JSON-манифеста:

```swift
extension FeatureAdoptionGuideContent {
    var howStepKeys: [LocalizedStringKey] {
        switch item {
        case .importedRecipe: return ["...how.1", "...how.2", "...how.3", "...how.4"]
        case .usedShoppingList: return ["...how.1", "...how.2", "...how.3"]
        // ...
        }
    }
}
```

`FeatureAdoptionGuideView` рендерит `ForEach(howStepKeys.indices, id: \.self)` с литералом-номером.

### 3. Разрешение локали для imagesets

`GuideAssetResolver.assetName(_ base: String) -> String`:
- Если `AppLanguagePreference.current == .ru` → `"\(base)_ru"`.
- Иначе → `"\(base)_en"`.
- `Image(uiType:)` загружает через `UIImage(named:)` — imageset с тем же именем.

Не использовать `@2x`/`@3x` для различения локали — нужны разные imageset'ы.

### 4. Видео без звука по умолчанию

`AVPlayer(_: url).isMuted = true` на init; пользователь может включить звук. Обоснование: гайд открывается из тихого контекста (профиль).

## Deployment

Native-only, без backend-координации:

1. **Feature flag** — на время разработки добавить `UserDefaults.standard.bool(forKey: "feature-adoption-guides.enabled")` (default `false` для main, `true` для debug). В `FeatureAdoptionRow` если флаг off → нет chevron, нет link. Для релиза — переключить в `true` через debug-меню или hardcode после smoke.
2. **TestFlight smoke** — пройти все 8 гайдов на реальном устройстве, проверить CTA-навигацию (assistant sheet, import, profile scroll, Safari).
3. **VoiceOver audit** — минимум 2 гайда (assistant, import).
4. **i18n check** — переключить язык на EN, пройти те же гайды.

### Rollback

- Feature flag → `false`: строки и ресурсы остаются в бандле (раздувают IPA на ~5–10 MB), но UI остаётся прежним.
- Hard rollback: revert коммита — отдельная фича, не задевает 038.

## Риски

1. **Раздувание IPA от видео.** Два mp4 по 5 MB = ~10 MB. Mitigation: H.264, 720p вместо 1080p если качество приемлемо; сжимать через `ffmpeg -crf 28`.
2. **Скриншоты устаревают при ребрендинге.** Mitigation: каждый imageset в comments указывает дату/версию UI; перед большим релизом — ревью.
3. **`how.N`-итерация в SwiftUI** — литералы в switch verbose, но явно и устойчиво. Альтернатива (JSON manifest) — out of scope (см. spec.md § Вне scope).
4. **`openAssistant` из Profile-стека** — если guide открыт из `FeatureAdoptionDetailView` (Profile tab), а `AssistantSheet` презентится в `AppShellView`, нужно pop до root Profile + презентовать sheet. Mitigation: `featureAdoptionGuideCta.openAssistant` в `AppShellView` делает `coordinator.selectedTab = .profile` + dismiss navigation stack + present sheet.
5. **Двойные суффиксы `_ru`/`_en`** — легко забыть и положить только один набор. Mitigation: `LocalizationConsistencyTests`-style тест, проверяющий наличие обоих imageset'ов для каждого `exampleImages`.

## Файлы

### Native (новые)

- `RecipeScalerNative/Models/FeatureAdoptionGuideContent.swift` — модели контента
- `RecipeScalerNative/Views/FeatureAdoptionGuideView.swift` — экран гайда
- `RecipeScalerNative/Views/GuideExampleCarousel.swift` — карусель скриншотов
- `RecipeScalerNative/Views/GuideVideoPlayer.swift` — AVPlayer-обёртка
- `RecipeScalerNative/Views/GuideAssetPlaceholder.swift` — серый плейсхолдер для dev
- `RecipeScalerNative/Utils/GuideAssetResolver.swift` — выбор imageset по локали
- `RecipeScalerNative/Utils/FeatureAdoptionGuideCta.swift` — EnvironmentKey + handler
- `RecipeScalerNative/Resources/GuideAssets.xcassets` — каталог скриншотов (пользователь)
- `RecipeScalerNative/Resources/GuideVideos/` — mp4 файлы (пользователь)

### Native (правки)

- `RecipeScalerNative/Models/FeatureAdoptionItem.swift` — `isGuideAvailable`, `guideContent`
- `RecipeScalerNative/Views/FeatureAdoptionDetailView.swift` — `NavigationLink` + `.navigationDestination`
- `RecipeScalerNative/Views/AccountView.swift` — scroll anchor для public profile / telegram; `featureAdoptionGuideCta` environment
- `RecipeScalerNative/Views/AppShellView.swift` — `featureAdoptionGuideCta.openAssistant` + `openImport`
- `RecipeScalerNative/Resources/Localizable.xcstrings` — все новые ключи
- `RecipeScalerNativeTests/LocalizationConsistencyTests.swift` — расширить на guide.* ключи
- `RecipeScalerNativeTests/FeatureAdoptionGuideContentTests.swift` — тест `howStepKeys` per case, CTA mapping, нет интерполированных ключей
- `scripts/verify-feature-adoption-guides.sh` — новый

## Open questions

1. **URL MCP-страницы** — финальный адрес у веб-команды (placeholder `https://recipe-scaler.ru/mcp`).
2. **`AppShellCoordinator.dismissProfileStack()`** — есть ли готовый метод для сброса navigation path Profile? Проверить при реализации таска 9/14.
3. **`AssistantSheet` презентация из гайда** — нужно ли передавать `contextRecipeId`? По spec US нет — открываем без контекста рецепта. Сверить с сигнатурой `AssistantSheet.init`.
4. **Бандлинг видео для Extensions** — `GuideVideos/` folder должен быть только в `RecipeScalerNative` target, не в Share/Action extensions. Проверить membership.
5. **iOS version floor** — `VideoPlayer` из AVKit доступен с iOS 14; `TabView` page style — iOS 14+. Сверить с deployment target проекта.
