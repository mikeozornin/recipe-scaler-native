# Plan: AirDrop-передача рецепта через кастомный тип файла

**Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

> План реализации. Источник истины о том, **что** и **в каком порядке** менять,
> чтобы ревьюер и агент видели один план.

---

## Очерёдность

1. **UTType + Info.plist** — фундамент: без регистрации iOS не ассоциирует файлы с приложением.
2. **Поддержка `.recipe`/`.zip` в существующих content-types и детекторе** — чтобы share-extension и file-importer тоже их принимали.
3. **Экспорт одного рецепта в файл** — сервис, собирающий `.recipe` или `.zip` во `temporaryDirectory`.
4. **UI отправки в `RecipeShareSheet`** — новая опция «Отправить файлом», вызывает сервис, показывает `ShareLink(item: fileURL)`.
5. **Приём входящего файла** — `.onOpenURL` → новый `DeepLink.openRecipeFile(URL)` → `RecipeFileImportCoordinator` → прямой импорт через `NativeExportImportService.importFile`.
6. **Тесты и verify** — unit-тесты на экспорт одного рецепта, ручной E2E на симуляторе (или двух), проверка обратно совместимости.

> Шаги 1–2 можно делать параллельно. Шаг 3 требует шаг 1 (UTType для имени файла).
> Шаг 4 требует шаг 3 (нужен сервис). Шаг 5 требует шаг 2 (детектор должен распознать формат).

---

## 1. UTType + Info.plist

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Info.plist` | Изменён — добавлены `UTExportedTypeDeclarations`, `CFBundleDocumentTypes` |
| `RecipeScalerCore/Import/ThirdParty/RecipeImportContentTypes.swift` | Изменён — добавлен `.recipe` расширение в `supported` |
| `RecipeScalerCore/Import/ThirdParty/UTTypeRecipeScaler.swift` | Создан — `extension UTType { static let recipeScalerRecipe }` (conforms to `public.zip-archive`) |

### Downstream consumers

- [x] **SwiftUI views** — `ImportRecipeSheet` (file picker) — должен принимать новый UTType.
- [x] **Cross-process consumers** — Share Extension, Action Extension: читают `RecipeImportContentTypes.supported`, получат `.recipe` автоматически после шага 2.
- [x] **Sync boundaries** — не затрагивается; формат v1.4 не меняется.
- [x] **Persisted state** — не затрагивается.
- [x] **Tests / verify-скрипты** — `ThirdPartyFormatDetectorTests` нужно расширить под `.recipe` расширение.

### Positive invariants

| Эффект | Инвариант | Где проверять |
|--------|----------|---------------|
| `UTType.recipeScalerRecipe` существует и conforms-to `public.zip-archive` | `UTType("ru.recipescaler.recipe")?.conforms(to: .zipArchive) == true` | `UTTypeRecipeScalerTests` (новый) |
| `RecipeImportContentTypes.supported` содержит тип с расширением `.recipe` | `supported.contains(where: { $0.filenameExtensions?.contains("recipe") == true })` | существующий content-types тест |

### Note

`UTExportedTypeDeclarations` делает Recipe Scaler **владельцем** типа — iOS ставит приложение первым кандидатом в «Open in...». Стандартные `.json`/`.zip` оставляем в `supported` для back-compat, но в `CFBundleDocumentTypes` указываем **только** `ru.recipescaler.recipe` (Owner) — никакого `public.zip-archive` как document type, чтобы не перехватывать все зипы (SC-005).

App Store требует рядом с `CFBundleDocumentTypes` ключ `LSSupportsOpeningDocumentsInPlace` или `UISupportsDocumentBrowser`. Импорт копирует security-scoped URL в tmp (`RecipeFileImportCoordinator`) и не редактирует исходный файл — поэтому `LSSupportsOpeningDocumentsInPlace = NO`.

---

## 2. Поддержка `.recipe` в детекторе и content-types

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerCore/Export/Native/NativeFormatDetector.swift` | Изменён — `detect(url:)` понимает расширение `.recipe` как ZIP |
| `RecipeScalerNative/Services/NativeExportImportService.swift` | Изменён — `isNativeFormat(url:)` узнаёт `.recipe` |
| `RecipeScalerCore/Import/ThirdParty/RecipeImportContentTypes.swift` | (повторно из шага 1) — в `supported` уже добавили |

### Downstream consumers

- [x] **SwiftUI views** — `ImportRecipeSheet.handleFileImportSelection` использует `NativeExportImportService.isNativeFormat`; получит поддержку автоматически.
- [x] **Cross-process consumers** — Share/Action Extensions прогоняют входящий файл через `NativeFormatDetector`.
- [x] **Sync boundaries** — не затрагивается.
- [x] **Persisted state** — не затрагивается.
- [x] **Tests / verify-скрипты** — `NativeFormatDetectorTests`, `ThirdPartyFormatDetectorTests`, `NativeExportImportServiceTests` — расширить.

### Positive invariants

| Эффект | Инвариант | Где проверять |
|--------|----------|---------------|
| `NativeFormatDetector.detect` распознаёт `.recipe` файл | `try NativeFormatDetector.detect(url: .init(fileURLWithPath: "x.recipe"))` возвращает `.v1_4` для валидного v1.4 ZIP-payload | `NativeFormatDetectorTests` |
| `isNativeFormat` true для `.recipe` | `NativeExportImportService.isNativeFormat(url:) == true` для файла `recipe.recipe` | `NativeExportImportServiceTests` |

### Note

`.recipe` файл — это ZIP-архив; внутри него `recipes.json` + опционально `images/<recipeId>/`. То есть обработка полностью идентична уже существующему `.zip`-path: `NativeRecipeImporter.parseZip` уже умеет распаковывать такой формат. Расширение — это **alias ZIP** с нашим UTType.

---

## 3. Экспорт одного рецепта в файл

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerCore/Export/Native/NativeRecipeExporter.swift` | Изменён — добавлен `exportSingle(recipe:imageData:) -> ExportResult`, **всегда** возвращает ZIP-архив с расширением `.recipe` (с картинкой или без) |
| `RecipeScalerNative/Services/NativeExportImportService.swift` | Изменён — добавлен `exportRecipe(id:progress:) async throws -> URL` (собирает recipe data + image, вызывает `exportSingle`, пишет файл в `temporaryDirectory`) |

### Downstream consumers

- [x] **SwiftUI views** — `RecipeShareSheet` будет вызывать новый метод (шаг 4).
- [x] **Cross-process consumers** — не затрагивается (экспортёр только в основном приложении).
- [x] **Sync boundaries** — payload v1.4, совместим с веб-импортёром и существующим нативным импортёром.
- [x] **Persisted state** — не затрагивается; файл пишется в `temporaryDirectory`.
- [x] **Tests / verify-скрипты** — `NativeRecipeExporterTests` — добавить тест single-recipe export с `.recipe` расширением.

### Positive invariants

| Эффект | Инвариант | Где проверять |
|--------|----------|---------------|
| Один рецепт без картинки → `.recipe` файл (ZIP без images/) | `result.filename` ends with `.recipe`; `result.hasImages == false` | `NativeRecipeExporterTests.testSingleRecipeExportWithoutImages` (новый) |
| Один рецепт с картинкой → `.recipe` файл (ZIP с images/) | `result.filename` ends with `.recipe`; `result.hasImages == true` | `NativeRecipeExporterTests.testSingleRecipeExportWithImages` (новый) |
| Сгенерированный файл валидно импортируется обратно | `NativeRecipeImporter.parse(url:)` succeeds, recipe name совпадает, картинка восстанавливается | `NativeFormatRoundtripTests` (новый или extend существующий) |

### Note

Имя файла: `{slugified-name}.recipe` (без транслитерации, чтобы не ломать i18n — юникод-имя нормален для файловой системы). Если имя пустое — fallback `recipe-<timestamp>.recipe`.

`NativeRecipeExporter.exportStreaming` уже умеет стримить — переиспользуем его, но с одним рецептом. Отдельный `exportSingle`-метод только для удобства API и формирования расширения `.recipe`. Внутри — стандартный ZIP с теми же entry-именами (`recipes.json`, `images/<id>/full.webp`, `images/<id>/preview.webp`), что и в bulk-экспорте.

---

## 4. UI отправки

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Views/RecipeDetailShareButton.swift` | Изменён — в `RecipeShareSheet` добавлен раздел «Отправить файлом» с кнопкой → вызывает `NativeExportImportService.exportRecipe(id:)`, показывает `ShareLink(item: fileURL)` |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменён — добавлены ключи `recipe.share.send-file`, `recipe.share.preparing-file`, `recipe.share.file-ready` |

### Downstream consumers

- [x] **SwiftUI views** — только сам `RecipeShareSheet`; downstream — `AppShellCoordinator.completeImport` (на принимающей стороне, шаг 5).
- [x] **Cross-process consumers** — не затрагивается.
- [x] **Sync boundaries** — не затрагивается (`isPublic` отправителя **не меняется** — это явно проверено в SC-002).
- [x] **Persisted state** — не затрагивается.
- [x] **Tests / verify-скрипты** — `RecipeShareSheetTests` (если есть) / E2E UI-тест; `lint-i18n.sh` для новых ключей.

### Positive invariants

| Эффект | Инвариант | Где проверять |
|--------|----------|---------------|
| Кнопка «Отправить файлом» появляется всегда, без зависимости от `isPublic` | UI snapshot показывает опцию даже когда `isPublic == false` | ручная проверка на симуляторе / `RecipeShareSheetUITests` (если есть) |
| После тапа файл появляется во временной директории и шарится | `ShareLink` открывает системный share sheet с AirDrop в списке | ручная проверка |
| `isPublic` отправителя не меняется | до/после `RecipeShareSheet` `syncService.recipes[id].isPublic` равны | `RecipeShareSheetTests` (новый) |

### Note

Прогресс-индикатор нужен только когда собирается zip с картинкой (чтение с диска + упаковка). Для `.recipe` без картинки это быстро — можно без индикатора.

---

## 5. Приём входящего файла (прямой импорт)

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Routing/DeepLinkRouter.swift` | Изменён — добавлен кейс `.openRecipeFile(URL)` в `DeepLink` |
| `RecipeScalerNative/RecipeScalerNativeApp.swift` | Изменён — `.onOpenURL` проверяет `url.isFileURL` → `.openRecipeFile(url)` |
| `RecipeScalerNative/Routing/AppShellCoordinator.swift` | Изменён — `handleDeepLink(.openRecipeFile(url))` запускает импорт напрямую через `NativeExportImportService.importFile`, показывает прогресс/тост, навигирует к импортированному рецепту |
| `RecipeScalerNative/Services/RecipeFileImportCoordinator.swift` | Создан — оркестратор: принимает `URL`, дергает `NativeExportImportService.importFile`, формирует `ImportRecipesResult`, пробрасывает результат в `AppShellCoordinator.completeImport` и показывает тост (success / partial / error) |
| `RecipeScalerNative/Views/AppShellView.swift` | Изменён — показывает прогресс-overlay и тост по триггерам из `AppShellCoordinator` |

### Downstream consumers

- [x] **SwiftUI views** — `ContentView` (владелец `AppShellCoordinator`), `AppShellView` (overlay для прогресса/тоста).
- [x] **Cross-process consumers** — не затрагивается (на принимающей стороне — только основное приложение).
- [x] **Sync boundaries** — после импорта рецепт идёт в Y.Doc → sync как обычно.
- [x] **Persisted state** — security-scoped URL нужно **скопировать** из Inbox в стабильную локацию перед импортом (iOS чистит Inbox).
- [x] **Tests / verify-скрипты** — `DeepLinkRouterTests` (URL → link), `AppShellCoordinatorTests` (link → импорт запущен), `RecipeFileImportCoordinatorTests` (оркестрация результата).

### Positive invariants

| Эффект | Инвариант | Где проверять |
|--------|----------|---------------|
| `file://` URL попадает в `DeepLink.openRecipeFile` | после `.onOpenURL(file://...)` → `deepLinkRouter.pending == .openRecipeFile(url)` | `DeepLinkRouterTests` (новый или extend) |
| После `.openRecipeFile` запускается импорт без открытия `ImportRecipeSheet` | `coordinator.importPresentation == nil`; запущен `RecipeFileImportCoordinator` (или эквивалент); `NativeExportImportService.importFile` вызван | `AppShellCoordinatorTests` (новый) |
| Успешный импорт → тост + навигация к рецепту | после импорта `selectedTab == .recipes`; `recipesPath` содержит `.recipe(id)`; показан тост `import.success` | `AppShellCoordinatorTests` + ручная проверка |
| Импорт с ошибкой → тост с сообщением об ошибке | при throw из `importFile` показан тост с `UserFacingAPIError.message(for: error)` | `RecipeFileImportCoordinatorTests` + ручная проверка |

### Note

Security-scoped URL: `NativeExportImportService.importFile` уже использует `NativeRecipeImporter.parse` который дёргает `startAccessingSecurityScopedResource()` для чтения ZIP-архива. Но ZIP-чтение через `Archive` может потребовать нескольких проходов — **сначала копируем** файл из Inbox в `tmp`, затем работаем с копией. Это уже частично реализовано в file-import path; выносим в общий хелпер для переиспользования.

Прогресс-overlay: показывается только если импорт идёт дольше 500ms (чтобы не мигал UI для маленьких рецептов). Реализуется через `Task` + `try? await Task.sleep(for: .milliseconds(500))` перед показом overlay.

---

## 6. Тесты и verify

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNativeTests/NativeRecipeExporterTests.swift` | Изменён — новые кейсы single-recipe export |
| `RecipeScalerNativeTests/NativeFormatDetectorTests.swift` | Изменён — кейс с `.recipe` расширением |
| `RecipeScalerNativeTests/UTTypeRecipeScalerTests.swift` | Создан — проверка `UTType.recipeScalerRecipe` |
| `RecipeScalerNativeTests/DeepLinkRouterTests.swift` | Создан/Изменён — кейсы для `file://` URL |
| `RecipeScalerNativeTests/LocalizationConsistencyTests.swift` | (без изменений — просто прогон) |

### Verify

- `xcodebuild build` — `RecipeScalerNative` scheme, все green
- `xcodebuild test` — `NativeRecipeExporterTests`, `NativeFormatDetectorTests`, `ThirdPartyFormatDetectorTests`, `UTTypeRecipeScalerTests`, `DeepLinkRouterTests` — все green
- `bash scripts/lint-i18n.sh` — для новых строковых ключей
- `bash scripts/verify-ui-smoke.sh` — если есть; для проверки что share sheet не сломан
- Ручной E2E на 2 симуляторах: открыть на одном деталь рецепта → Share → AirDrop → подтвердить на втором → проверить что импорт прошёл автоматически без `ImportRecipeSheet`
