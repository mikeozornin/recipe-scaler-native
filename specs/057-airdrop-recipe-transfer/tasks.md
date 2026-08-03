# Tasks: AirDrop-передача рецепта через кастомный тип файла

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

> Задачи генерируются вручную по плану. Источник истины о прогрессе — чек-боксы ниже.

---

## Шаг 1 — UTType + Info.plist

- [X] T001. Создать `RecipeScalerCore/Import/ThirdParty/UTTypeRecipeScaler.swift` с `extension UTType { public static let recipeScalerRecipe = UTType(exportedAs: "ru.recipescaler.recipe", conformingTo: .zipArchive) }`.
- [X] T002. Добавить `UTExportedTypeDeclarations` в `RecipeScalerNative/Info.plist` для `ru.recipescaler.recipe` (extension `.recipe`, MIME `application/vnd.recipescaler.recipe`, conforms to `public.zip-archive`).
- [X] T003. Добавить `CFBundleDocumentTypes` в `RecipeScalerNative/Info.plist` с **одной** записью: для `ru.recipescaler.recipe` (Owner, Editor). `public.zip-archive` **не** заявлять (иначе перехватим все zip-файлы — нарушит SC-005).
- [X] T004. Создать `RecipeScalerNativeTests/UTTypeRecipeScalerTests.swift`: проверить что UTType существует, conforms-to `.zipArchive`, имеет extension `.recipe`.

## Шаг 2 — Поддержка `.recipe` в детекторе и content-types

- [X] T005. В `RecipeImportContentTypes.supported` добавить `UTType.recipeScalerRecipe` (если отсутствует) — после этого Share/Action Extensions начнут принимать `.recipe` файлы.
- [X] T006. В `NativeFormatDetector.detect(url:)` — расширить проверку расширения: `.recipe` трактовать как ZIP (распаковывать через `readRecipesJsonFromZip`, как для `.zip`).
- [X] T007. В `NativeExportImportService.isNativeFormat(url:)` — добавить `.recipe` в список допустимых расширений.
- [X] T008. Расширить `NativeFormatDetectorTests` кейсом с `.recipe` расширением (ZIP-архив с `recipes.json` внутри).
- [X] T009. Расширить `ThirdPartyFormatDetectorTests` кейсом с `.recipe` расширением.

## Шаг 3 — Экспорт одного рецепта в файл

- [X] T010. В `NativeRecipeExporter` добавить `exportSingle(recipe:imageData:) -> ExportResult` — **всегда** возвращает ZIP-архив с расширением `.recipe` (с картинкой или без — branching по `imageData` влияет только на наличие `images/` внутри, не на расширение).
- [X] T011. В `NativeExportImportService` добавить `exportRecipe(id:progress:) async throws -> URL` (читает recipe data + image через `syncService`, вызывает `exportSingle`, пишет файл в `temporaryDirectory`).
- [X] T012. Реализовать slugification имени файла: заменить небезопасные символы (`/`, `:`, `\n`) на `-`, обрезать до разумной длины (например, 80 символов), fallback `recipe-<short-uuid>` если имя пустое.
- [X] T013. Добавить unit-тест `NativeRecipeExporterTests.testSingleRecipeExportWithoutImages` — без картинки → `.recipe` файл, ZIP без images/.
- [X] T014. Добавить unit-тест `NativeRecipeExporterTests.testSingleRecipeExportWithImages` — с картинкой → `.recipe` файл, ZIP с images/.
- [X] T015. Добавить roundtrip-тест: single-recipe export → import → recipe name совпадает, картинка восстанавливается.

## Шаг 4 — UI отправки

- [X] T016. Добавить строковые ключи в `Localizable.xcstrings`: `recipe.share.send-file`, `recipe.share.preparing-file`, `recipe.share.file-failed` (с pluralization/переводами по документации I18N).
- [X] T017. В `RecipeShareSheet` добавить новый раздел «Отправить файлом» с кнопкой → по тапу асинхронно вызывает `NativeExportImportService.exportRecipe(id:)`, показывает progress, затем `ShareLink(item: fileURL)`.
- [X] T018. Прогнать `bash scripts/lint-i18n.sh` — проверить что новые ключи валидны и нет хардкода.
- [ ] T019. Ручная проверка UI: share sheet открывается, кнопка видна всегда (вне зависимости от `isPublic`), после тапа появляется share sheet с AirDrop в списке.

## Шаг 5 — Приём входящего файла (прямой импорт)

- [X] T020. Добавить кейс `.openRecipeFile(URL)` в `DeepLink` enum (с `Equatable` реализацией для URL).
- [X] T021. В `RecipeScalerNativeApp.swift` `.onOpenURL` — если `url.isFileURL` → `DeepLinkRouter.shared.handle(.openRecipeFile(url))`; иначе существующий путь `recipe-scaler://` схемы.
- [X] T022. Создать `RecipeScalerNative/Services/RecipeFileImportCoordinator.swift` — оркестратор: принимает `URL`, копирует в tmp (security-scoped), вызывает `NativeExportImportService.importFile`, формирует `ImportRecipesResult`, пробрасывает в `AppShellCoordinator.completeImport`, показывает тост (success / partial / error) с локализованными сообщениями.
- [X] T023. В `AppShellCoordinator.handleDeepLink(.openRecipeFile(url))` — дергает `RecipeFileImportCoordinator`, **не** открывает `ImportRecipeSheet` (то есть `importPresentation` остаётся `nil`).
- [X] T024. В `AppShellView` / `ContentView` — показать прогресс-overlay (если импорт идёт дольше 500ms) и тост по триггерам из `AppShellCoordinator`.
- [X] T025. Убедиться, что security-scoped доступ корректно обрабатывается: `RecipeFileImportCoordinator` копирует файл из Inbox в `tmp` (вынести общий хелпер, если он размазан по `ImportRecipeSheet`).
- [X] T026. Расширить/создать `DeepLinkRouterTests` для `file://` URL.
- [X] T027. Расширить/создать `AppShellCoordinatorTests` для `.openRecipeFile(url)` — что `importPresentation` остаётся `nil`, импорт запускается через координатор.
- [X] T028. Добавить `RecipeFileImportCoordinatorTests` — success / partial / error-сценарии оркестации.

## Шаг 6 — Интеграционные проверки

- [ ] T029. Прогнать `xcodebuild build` — все таргеты green (main + Share Extension + Action Extension).
- [ ] T030. Прогнать `xcodebuild test` — все новые тесты green.
- [ ] T031. Ручной E2E на 2 симуляторах или 2 физических устройствах: отправка рецепта через AirDrop → приём → автоматический импорт → тост + навигация к рецепту.
- [ ] T032. Ручная проверка SC-004: произвольный `.json` (не recipe-формат) **не** вызывает предложение открыть в Recipe Scaler.
- [ ] T033. Ручная проверка SC-005: произвольный `.zip` **не** вызывает предложение открыть в Recipe Scaler.
- [ ] T034. Ручная проверка SC-002: `isPublic` отправителя не изменился после отправки через AirDrop.

## Замечания

- T011 `exportRecipe` — тяжелая работа (чтение recipe data + image) должна идти в `Task.detached`, как уже сделано в `exportAll`. Не делать синхронно на MainActor.
- T017 — `ShareLink` в SwiftUI требует, чтобы `item` был доступен на момент рендера. Для асинхронной генерации файла используем `@State fileURL: URL?` + условный `if let fileURL { ShareLink(item: fileURL) }`.
- T020 — `URL` — `Equatable` из коробки, но `DeepLink: Equatable` получает synthesized-реализацию автоматически; проблем нет.
- T021 — порядок проверок важен: сначала `isFileURL`, потом scheme, т.к. `file://` URLs имеют схему `file` и не должны идти в `recipe-scaler` router.
- T022 — `RecipeFileImportCoordinator` инкапсулирует логику «URL → результат импорта + feedback»; это позволяет переиспользовать его в будущем для Universal Links и push-уведомлений с вложениями, не только AirDrop.
- T024 — прогресс-overlay показывается с задержкой 500мс чтобы не мигать на маленьких рецептах; тост — стандартный через `ShoppingFeedback.postStatus` (или аналог), как в `completeImport`.
