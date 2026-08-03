# Code Review: master (uncommitted)

**Дата**: 2026-08-03
**Ветка**: `master`
**Спека**: [`specs/057-airdrop-recipe-transfer/spec.md`](specs/057-airdrop-recipe-transfer/spec.md)
**Объём**: +841 / −958 строк, 5 новых + 30 изменённых файлов

## Summary

Changeset реализует **Spec 057 — AirDrop-передача рецепта через кастомный UTType** (`.recipe`), плюс несколько ортогональных правок: web-parity фикс `ingredient.order` (Y_JSON_NUM вместо BigInt), defensive-mitigation для duplicate-id в `SpotlightIndexer`, удаление устаревших debug-логов.

Качество реализации в целом **высокое**: отличный spec/plan, плотное тестовое покрытие, зрелое переиспользование существующих hardened-путей (`NativeRecipeImporter.parseZip` с тройной защитой от zip-бомб). Однако есть **несколько блокеров перед merge**, в первую очередь — нарушение DI/composition-root паттерна, silent-failure на 0-import, и дыра в размерности staging-копии.

**Проверено областей**: Security, Business Logic, Architecture, Standards/i18n. Каждая область гонялась отдельным subagent'ом, отчёты агрегированы.

## Findings (sorted by priority)

### High

#### 1. **[business-logic]** Silent failure при `importedCount == 0` — получатель не видит тоста

- **Files**: `RecipeScalerNative/Services/RecipeFileImportCoordinator.swift:82-89` + `RecipeScalerNative/Routing/AppShellCoordinator.swift:89-97`
- **Description**: Если `.recipe` распарсился, но **ни один** рецепт не применился (все упали в `applyNativeRecipe` или были отфильтрованы), `RecipeFileImportCoordinator` всё равно вызывает `shellCoordinator.completeImport(result)` с `importedCount == 0`. Контракт `completeImport` (строка 95): `guard result.importedCount > 0 else { return nil }`. То есть тост = `nil`. Дальше в `AppShellCoordinator.handleDeepLink(.openRecipeFile)` `if let message { pendingFileImportToast = message }` → `pendingFileImportToast` остаётся `nil`, `AppShellView.onChange` не срабатывает. Пользователь **не получает никакого фидбэка** — файл тихо исчез.
- **Impact**: Прямое нарушение spec **SC-001** («по завершении показан тост») и **US2** («пользователь видит только результат: тост "рецепт импортирован" / сообщение об ошибке»). Контр-интуитивный сценарий: AirDrop принят, файл валидный, но рецепты конфликтуют с лимитами → ноль фидбэка.
- **Recommendation**: В `RecipeFileImportCoordinator.importFile` явно различать три исхода и всегда возвращать тост:
  - `importedCount > 0` → существующий путь `completeImport`
  - `importedCount == 0` (archive распарсился, но ничего не применилось) → возвращать локализованное сообщение-предупреждение (например, ключ `import.no-recipes-applied`) и **не** звать `completeImport`
  - `throw` → текущий error path
- **Status: FIXED** — `RecipeFileImportCoordinator.importFile` теперь возвращает `import.no-recipes-applied` для 0-import success и всегда выставляет toast; добавлен тест `test_importFile_emptyRecipes_stillSurfacesToast`.

#### 2. **[security]** Staged file copy без size pre-flight — disk-fill / local DoS

- **Files**: `RecipeScalerNative/Services/RecipeFileImportCoordinator.swift:97-120`
- **Description**: `stageSecurityScopedFile` делает безусловный `FileManager.copyItem(at: source, to: destination)` **до** любого size-check'а. ZIP-guards (`maxDecompressedArchiveBytes = 500 MB` и т.д.) запускаются только позже в `NativeRecipeImporter.parse`. iOS Inbox-источники (AirDrop, Files, Mail) могут deliver'нуть multi-GB файл — AirDrop не имеет системного cap на `.recipe` payload сверх свободного места, получатель тапает Accept без preview размера.
- **Impact**: Злоумышленник (или случайный большой файл) пишет multi-GB blob в sandbox `tmp/` ДО запуска guards. На low-space устройстве это может вытолкнуть app за container quota или триггерить iOS Jetsam / `.data` eviction. Cleanup в Step 3 (строка 79) срабатывает только на success-path; на staging-failure-path частичная копия утекает.
- **Recommendation**: Перед `copyItem` — stat'нуть source через `FileManager.default.attributesOfItem(atPath: source.path)[.size]` (работает под security scope, т.к. мы уже в `startAccessingSecurityScopedResource`) и reject'ить с явной ошибкой, если размер превышает `ThirdPartyImportLimits.maxDecompressedArchiveBytes` (или tighter ceiling 100 MB — реальные `.recipe` payloads < 25 MB). Также обернуть cleanup так, чтобы staged-файл удалялся и на staging-failure-path.
- **Status: FIXED** — `stageSecurityScopedFile` теперь делает `attributesOfItem(.size)` pre-flight против `maxDecompressedArchiveBytes`, на превышение бросает `NativeImportError.archiveSizeLimitExceeded`, и чистит частичную копию на провале `copyItem`; добавлен тест `test_importFile_oversizedFile_returnsErrorMessageWithoutStaging`.

#### 3. **[architecture]** `RecipeFileImportCoordinator` строится внутри `AppShellCoordinator`, а не в `AppContainer`

- **Files**: `RecipeScalerNative/Routing/AppShellCoordinator.swift:20-35`
- **Description**: `AppShellCoordinator` владеет `_fileImportCoordinator` как private var с ручным lazy-init и сам конструирует его от `syncService`. Это нарушает прямой запрет `AGENTS.md` (Composition Root): «все app-level сервисы строятся в `AppContainer.swift` и инжектятся через `.appEnvironment(_:)`». Из-за этого `RecipeFileImportCoordinator` нельзя подменить фейком в тестах, а его зависимости (`NativeExportImportService`) оказываются захардкожены.
- **Note**: Коммент на строках 25-26 («Stored as `var` (not `lazy`) because `@Observable`'s macro transforms every stored property and rejects `lazy` combinations») **фактически неверен** — `@Observable` macro не запрещает `lazy`. Реальная причина ручного workaround'а — желание иметь lazy-init без `lazy`. Неверный коммент вводит в заблуждение и закрепляет workaround.
- **Impact**: Тесты `RecipeFileImportCoordinatorTests` проходят через реальный `NativeExportImportService` + реальный `YjsSyncService` (in-memory) — это integration-test masquerading as unit-test. Любая будущая декорация сервисов (метрики, feature-флаги) обходит этот путь. `weak var shellCoordinator` создаёт скрытую связность между координаторами.
- **Recommendation**: Перенести конструирование в `AppContainer.init`: `let fileImportCoordinator = RecipeFileImportCoordinator(syncService: syncService); fileImportCoordinator.shellCoordinator = appShellCoordinator`. В `AppShellCoordinator` оставить только `let fileImportCoordinator: RecipeFileImportCoordinator` через `init`. Это решает сразу три проблемы: DI-дисциплину, тест-isolation и неверный коммент.
- **Status: FIXED** — `RecipeFileImportCoordinator` конструируется в `AppContainer.init` с wire'ингом `shellCoordinator`; `AppShellCoordinator` принимает его как инжектируемый `var fileImportCoordinator: RecipeFileImportCoordinator?` (internal setter, доступен AppContainer); неверный коммент про `@Observable`/`lazy` удалён; `handleDeepLink(.openRecipeFile)` `guard let`'ит координатор.

#### 4. **[business-logic]** Прогресс-индикатор исчезает до того, как картинка и ZIP собраны

- **Files**: `RecipeScalerNative/Services/NativeExportImportService.swift:200-216`
- **Description**: В `exportRecipe(id:progress:)` вызов `await MainActor.run { progress?(1, 1) }` стоит **сразу после** `readRecipeData`, но **до** чтения картинки с диска и упаковки ZIP. Spec FR-004 явно требует: «progress indicator, т.к. сбор картинки может занять время». UI `RecipeShareSheet` скрывает spinner по этому сигналу и сразу показывает кнопку — пользователь не видит, что работа ещё идёт.
- **Impact**: UX-регрессия vs спеки. Для рецепта с большой картинкой (webp full ~200–500 KB) пользователь увидит «зависшую» кнопку после исчезновения индикатора.
- **Recommendation**: Вызвать `progress?(1, 1)` **после** `NativeRecipeExporter.exportSingle(...)` (строка ~265), прямо перед возвратом `fileURL`. Или: для одного рецепта проще вернуть `(recipeData, imageData)` snapshot на MainActor и полностью собрать ZIP на главном потоке без лишней прогресс-сигнализации.
- **Status: FIXED** — `await MainActor.run { progress?(1, 1) }` перенесён в конец `exportRecipe`, после успешной записи `.recipe` файла (throw-path не триггерит progress).

#### 5. **[business-logic]** Утечка временных файлов в `makeInMemoryDataURL` без cleanup

- **Files**: `RecipeScalerCore/Export/Native/NativeRecipeExporter.swift:263-269` (private static func)
- **Description**: Каждый вызов `exportSingle` с картинкой создаёт **два** tmp-файла (`rs-export-<UUID>.bin` для full и preview, до 25 MB каждый) через `try? data.write(to: tmp)`. Они **не удаляются** — код рассчитывает на iOS-scavenging `temporaryDirectory`. В рамках одной сессии пользователь может десятками раз шарить рецепты; файлы накапливаются до перезапуска. Для bulk-export этого нет — там URL'ы картинок читаются напрямую с диска. Также есть privacy smell: full-resolution recipe images остаются в `tmp` после dismiss share sheet'а.
- **Impact**: Диск-лирик на sandbox; после 100 отправленных рецептов с картинками в tmp копится ~50–100 MB мусора. Не критично (OS чистит), но нарушает hygiene.
- **Recommendation**: Возвращать URL'ы и чистить их в `defer` после `createZipStreaming(...)`. Или: расширить `createZipStreaming` так, чтобы он принимал `Data` напрямую для in-memory данных (минуя file URL), либо просто `try? FileManager.default.removeItem(at:)` после упаковки.
- **Status: FIXED** — `exportSingle` собирает оба `.bin` URL'а в local-переменные и удаляет их `removeItem(at:)` в обеих ветках (success + catch) после `createZipStreaming`.

### Medium

#### 6. **[business-logic / architecture]** `.onOpenURL` ранним return'ом импортирует **любой** `file://` URL, не только `.recipe`

- **Files**: `RecipeScalerNative/RecipeScalerNativeApp.swift:137-143`
- **Description**: Проверка только `url.isFileURL` означает, что если iOS deliver'ит любой file URL (например, из «Open in…» для произвольного файла, или универсальный Universal Link с file-attachment), `AppShellCoordinator` попытается импортировать его как рецепт и покажет ошибку-тост. Spec SC-005 прямо требует: произвольные файлы **не** должны попадать в Recipe Scaler.
- **Impact**: UX-баг: пользователь увидит «Не удалось импортировать» для нерецептных файлов. Сценарий редкий, но противоречит spec.
- **Recommendation**: Гейтить по расширению/детектору:
  ```swift
  if url.isFileURL, NativeExportImportService.isNativeFormat(url: url) {
      DeepLinkRouter.shared.handle(.openRecipeFile(url))
      return
  }
  ```
  Или хотя бы `url.pathExtension.lowercased() == "recipe"`.

#### 7. **[security]** Хардкод production debug-credentials в VCS

- **Files**: `RecipeScalerNative/App/DebugSimulatorAutoLogin.swift:17,21,25-26` (rotated values); также в `docs/PROJECT.md:9`, `docs/E2E.md:128`
- **Description**: Дифф заменяет одну пару prod-credentials на другую: `userId`, `bundledDeviceToken` (живой Bearer по spec 041), и `seedPhrase` (recovery seed для того же аккаунта) — всё это лежит в git-истории. `#if DEBUG` / `targetEnvironment(simulator)` guards защищают только compile-time, но не credentials: любой с read-доступом к репо может аутентифицироваться как этот prod-аккаунт на `recipe-scaler.ru`, читать/менять его рецепты, и (через seed) выпускать новые device-token'ы. Это та же проблема, что была в архивном `review-kilo-glm-5.2-recipe-scaler-native.md` — дифф merely ротирует значения, не убирая класс проблемы.
- **Impact**: Anyone with repo read access → full impersonation этого аккаунта.
- **Recommendation**:
  1. Считать старые credentials скомпрометированными, ротировать server-side (ревокнуть `device_token`, сменить seed).
  2. Не хранить рабочий seed phrase в VCS. Брать `device_token` из launch-env (`DEBUG_DEVICE_TOKEN`) или CI secret; для авто-логина в симуляторе — отдельный ephemeral test-аккаунт без чек-ин-значимых данных.

#### 8. **[i18n / standards]** Пустая запись `"Recipe Scaler recipe"` в `InfoPlist.xcstrings` — ru-пользователи увидят английский

- **Files**: `RecipeScalerNative/Resources/InfoPlist.xcstrings:75-77`
- **Description**: Добавлена пустая запись `{}` без `en` / `ru` переводов. Это описание кастомного UTType, которое iOS показывает в share sheets, AirDrop-баннере, Files «Open in…». Все остальные InfoPlist-записи (`NSCameraUsageDescription`, `spotlight.action.addToShopping.title`) имеют обе локализации. AGENTS.md: «без fallback на дефолтные строки».
- **Impact**: Долгосрочная визуальная регрессия — русскоязычный пользователь видит `Recipe Scaler recipe` (англ.) в системных UI.
- **Recommendation**: Добавить переводы, например:
  ```diff
       "Recipe Scaler recipe" : {
+        "localizations" : {
+          "en" : { "stringUnit" : { "state" : "translated", "value" : "Recipe Scaler recipe" } },
+          "ru" : { "stringUnit" : { "state" : "translated", "value" : "Рецепт Recipe Scaler" } }
+        }
       },
  ```

#### 9. **[architecture]** `NativeExportImportService` конструируется ad-hoc в 4 местах

- **Files**:
  - `RecipeScalerNative/Views/RecipeDetailShareButton.swift:178` (`prepareAndShareFile`)
  - `RecipeScalerNative/Services/RecipeFileImportCoordinator.swift:39` (`init`)
  - и 2 сайта в `ImportRecipeSheet` / `AppContainer` (grep)
- **Description**: Каждый вызов `NativeExportImportService(syncService:)` создаёт новый инстанс; нет гарантий singleton-lifecycle и нет способа залогировать инстанс-уровневые метрики.
- **Impact**: Несущественно для функциональности, но нарушает DI-дисциплину и затрудняет future-extensions (например, кэширование или сборщих метрик).
- **Recommendation**: Внедрить `NativeExportImportService` через `AppContainer` и пробросить в `RecipeFileImportCoordinator` и `RecipeShareSheet` как зависимость.

#### 10. **[architecture]** `RecipeFileImportCoordinator.importFile` асимметричный return-контракт

- **Files**: `RecipeScalerNative/Services/RecipeFileImportCoordinator.swift:46-90`
- **Description**: Ветвление:
  - success + `shellCoordinator != nil` → возвращает toast `completeImport(result)`, вызывает `onComplete?(result)`
  - success + `shellCoordinator == nil` → вызывает `onComplete?(result)`, возвращает `nil` (т.к. `failureMessage` == nil)
  - failure → `onComplete?(nil)`, возвращает `failureMessage`

  То есть `return toast` имеет разный семантический смысл в success-ветке без shell: для тестов это значит «success не дал тоста». Контракт запутан.
- **Impact**: Дальнейшие caller'ы могут неправильно интерпретировать `nil` как ошибку. Тесты проходят случайно.
- **Recommendation**: Разделить метод на два: либо `importFile(...) async throws -> ImportRecipesResult` с throw'ом на ошибке, либо явный `Result<ImportRecipesResult, String>` return type. Тост должен рендериться caller'ом (AppShellView), а не возвращаться строкой.

#### 11. **[architecture / plan]** T025 не закрыт — helper для security-scoped staging не извлечён

- **Files**: `RecipeScalerNative/Services/RecipeFileImportCoordinator.swift:97-120` (новый хелпер), но `ImportRecipeSheet` остался со своим
- **Description**: Plan 057 шаг 5 / T025: «security-scoped доступ — вынести общий хелпер, если он размазан по `ImportRecipeSheet`». В диффе новый `stageSecurityScopedFile` добавлен в `RecipeFileImportCoordinator`, но в `ImportRecipeSheet` аналогичный код **не отрефакторен** — дублирование осталось.
- **Impact**: Дальнейшее расхождение — два пути могут эволюционировать независимо и снова разойтись.
- **Recommendation**: Либо извлечь в `SecurityScopedFileStager` (Core или Utils), либо явно закрыть T025 как «decided to keep separate» с комментарием-обоснованием.

#### 12. **[standards]** "Temporary" duplicate-id mitigation в `SpotlightIndexer` без tracker-ссылки

- **Files**: `RecipeScalerNative/Services/SpotlightIndexer.swift:147-156`, `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:2477-2481` (+ `duplicateIdSummary` helper)
- **Description**: Замена `fatalError` (от `Dictionary(uniqueKeysWithValues:)`) на `uniquingKeysWith: { _, last in last }` — defensive mitigation, чтобы не крашить на дублях в `Y.Array(recipes)`. Коммент «Temporary: do not fatalError while we trace how duplicate application ids land» — но без Linear/спеки-ссылки. Дополнительная проблема: `AppLog.notice(.spotlight, "Duplicate collection ids in…")` использует free-form string вместо snake_case event-name паттерна (как `force_reconnect`, `native_import_image_skipped_offline` в соседних вызовах).
- **Impact**: "Temporary" без tracker'а имеет свойство становиться permanent. Лог-паранойя нарушает conventions.
- **Recommendation**:
  1. Привести к единому формату: `AppLog.notice(.spotlight, "duplicate_collection_ids_in_dirty_set", data: ["ids": ...])`.
  2. Добавить Linear ID: `// Temporary (MIK-XXX / spec 058): trace duplicate collection ids...`.

#### 13. **[security]** `waitForConnection` не кооперативен с `Task.isCancelled` — local DoS

- **Files**: `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:614-622`
- **Description**: `waitForConnection(timeoutSeconds:)` busy-loop'ит на `Task.sleep(200ms)` до 5 секунд, **игнорируя `Task.isCancelled`**. В цикле нет проверки cancellation. Вызывается из `NativeExportImportService.importFile` (строка 348) — по разу на каждый recipe с картинкой. Для multi-recipe `.zip`/`.recipe` (технически возможно через bulk path) worst case = N × 5s.
- **Impact**: Local DoS-сценарий — злоумышленник AirDrop'ит файл с многими recipes+images сразу после cold launch (WS в `.reconnecting`). Каждый recipe блокирует import Task на 5 секунд перед fallback'ом в offline-skip, замораживая progress-overlay и starving MainActor. `.onOpenURL` не дедуплицирует поставки, так что поток файлов амплифицирует.
- **Recommendation**: Добавить `if Task.isCancelled { return false }` внутри loop'а. Снизить per-call ceiling (напр., до 2s). Лучше — один `AsyncStream`-backed waiter, на который подписываются несколько imports (N imports не умножают wait).

#### 14. **[security]** `NativeFormatDetector.readRecipesJsonFromZip` без decompression-guards (defense-in-depth gap)

- **Files**: `RecipeScalerCore/Export/Native/NativeFormatDetector.swift:38-53`
- **Description**: `readRecipesJsonFromZip` делает `archive.extract(entry) { chunk in data.append(chunk) }` **без** size cap, без streaming running total, без aggregate cap. Это вызывается из `detect(url:)`, который `NativeExportImportService.isNativeFormat(url:)` инвоит на каждый входящий `.recipe` URL **до** того, как `NativeRecipeImporter.parse` запустит guarded-path.
- **Impact**: Крафтовый `.recipe` с `recipes.json` entry, у которой `uncompressedSize` ~2 GB, будет полностью материализован в память внутри `detect()` и только потом reject'нут. Это regression-window vs spec 032 (который закрыл importer-side). Reachable с silent `.onOpenURL(file://)` без user interaction.
- **Recommendation**: Применить тот же triple-guard (pre-flight `entry.uncompressedSize <= ThirdPartyImportLimits.maxRecipeJSONBytes`, streaming running total, post-extract `data.count` cap), что в `NativeRecipeImporter.parseZip`. Или short-circuit'нуть `detect`, чтобы он peek'ал central directory без extraction (нужен только `version` из manifest).

#### 15. **[architecture]** `pendingFileImportToast` дублирует существующий toast-channel

- **Files**: `RecipeScalerNative/Routing/AppShellCoordinator.swift:48`, `RecipeScalerNative/Views/AppShellView.swift:164-168`
- **Description**: На coordinator добавлен `var pendingFileImportToast: String?`, который `AppShellView.onChange` пробрасывает в `postTransientStatus`. Но в кодбазе уже есть standard toast-channel через `ShoppingFeedback`/`NotificationCenter` (используется в `completeImport` для `import.success`). Две разные механики для одной ответственности.
- **Impact**: Дальнейшая divergence-эволюция; новые caller'ы не будут знать, какой канал использовать.
- **Recommendation**: Унифицировать — рендерить тост из `completeImport` через тот же `ShoppingFeedback`/`NotificationCenter`, что уже используется. Или явно задокументировать, что `.openRecipeFile` использует другой канал по какой-то причине.

#### 16. **[architecture]** `UTTypeRecipeScaler` misplaced в `Import/ThirdParty/`

- **Files**: `RecipeScalerCore/Import/ThirdParty/UTTypeRecipeScaler.swift`
- **Description**: Файл лежит в `Import/ThirdParty/`, но `ru.recipescaler.recipe` — это собственный nativ тип Recipe Scaler (FR-001: «мы — владельцы типа»), а не third-party. Папка `ThirdParty/` содержит Paprika/Crouton parsners; логически наш UTType там чужой.
- **Impact**: Лёгкая путаница для future-контрибьюторов; сложно найти файл по смыслу.
- **Recommendation**: Перенести в `RecipeScalerCore/Export/Native/` (рядом с `NativeRecipeExporter`) или в новый `RecipeScalerCore/Common/UTTypeRecipeScaler.swift`.

#### 17. **[standards]** Stale `RecipeReadDiagnostics` references в 3 скриптах + how-to-debug.md

- **Files**: `scripts/debug-recipe-detail.sh`, `scripts/verify-description-editor.sh`, `scripts/verify-recipe-description-native.sh`, `llm/how-to-debug.md`
- **Description**: Файл `RecipeScalerNative/Utils/RecipeReadDiagnostics.swift` удалён в этом changeset'е, но в трёх shell-скриптах и в how-to-debug.md остались references на него (через launch arg `-RecipeReadDiagnostics=1`). Не compile-error (это runtime env-var name), но запуск скриптов будет have no effect.
- **Impact**: Скрипты «тихо молчат» вместо явной ошибки;调试-flow в how-to-debug.md битый.
- **Recommendation**: Удалить `-RecipeReadDiagnostics` launch-args из всех 3 скриптов; обновить таблицу в `llm/how-to-debug.md`.

### Low

#### 18. **[architecture]** Двойная точка входа в routing `.onOpenURL`

- **Files**: `RecipeScalerNative/RecipeScalerNativeApp.swift:137-143`
- **Description**: Для file:// URL — `DeepLinkRouter.shared.handle(.openRecipeFile(url))`; для остальных — статический `DeepLinkRouter.handle(url)`. Два разных API для одной ответственности.
- **Recommendation**: Унифицировать: один `DeepLinkRouter.handle(url:)` (статический или инстанс), который внутри разбирает scheme и file'ы.

#### 19. **[business-logic]** `slugify` капает `slug.count > 80` по `Character` (не Unicode scalar)

- **Files**: `RecipeScalerCore/Export/Native/NativeRecipeExporter.swift:259-263`
- **Description**: `String.prefix(80)` работает по `Character` (grapheme cluster). Для имени с большим количеством combining-диакритик (редко, но возможно) фактическая длина в байтах может превысить ожидаемую. Также edge-case: имя `"--"` → после collapse → `""` → `slugify` возвращает `nil` → fallback `recipe-<timestamp>` — это правильно, тест есть.
- **Impact**: Косметика. Имя файла может быть чуть длиннее, чем 80 символов, в редких случаях.
- **Recommendation**: Если принципиально — перейти на `String(scalar.unicodeScalars.prefix(N))`. Иначе — оставить; поведение интуитивное.

#### 20. **[standards]** Section header в `RecipeDetailShareButton` воспроизводит `AppSectionHeader` вручную

- **Files**: `RecipeScalerNative/Views/RecipeDetailShareButton.swift:184-192`
- **Description**: Ручной `Text(...).font(.footnote).foregroundStyle(.secondary).textCase(AppSectionHeader.usesUpperCase ? .uppercase : nil)`, при том что в 15+ других экранов используется `AppSectionHeader("key")`. Теряется `letterSpacing` (0.06em) и единообразие.
- **Recommendation**: Заменить на `AppSectionHeader("recipe.share.send-file")`.

#### 21. **[standards]** `airdropFileSection` нейминг обещает AirDrop, но открывает все каналы share sheet'а

- **Files**: `RecipeScalerNative/Views/RecipeDetailShareButton.swift:148`
- **Description**: `UIActivityViewController(activityItems: [fileURL])` показывает AirDrop + Mail + Messages + Files + сторонние extensions. Лейбл `recipe.share.send-file` → `Send via AirDrop` вводит в заблуждение.
- **Recommendation**: Либо переименовать UI-строку в «Отправить файлом» (как в plan 057 шаг 4), либо ограничить `activityCategory: .share` + `excludedActivityTypes`.

#### 22. **[standards]** Тесты в new-файлах используют `snake_case`, окружение — `camelCase`

- **Files**: `RecipeFileImportCoordinatorTests.swift`, `NativeFormatDetectorTests.swift`, `UTTypeRecipeScalerTests.swift`, новые тест-кейсы в `AppShellCoordinatorTests.swift`, `DeepLinkRouterTests.swift`
- **Description**: `test_importFile_success_callsCompleteImportAndReturnsToast` (snake_case) vs `testImportFileSuccess` / `test_openShoppingList_switchesTabAndClearsRouter`. Окружение смешано.
- **Recommendation**: Либо зафиксировать snake_case как новый стандарт в `docs/TESTING.md` (читаемость выше для оркестраций), либо переименовать. Не блокер.

#### 23. **[standards]** Step-N комментарии в `RecipeFileImportCoordinator.importFile` — narrating

- **Files**: `RecipeScalerNative/Services/RecipeFileImportCoordinator.swift:51, 61, 78, 81`
- **Description**: `// Step 1: copy the Inbox file...`, `// Step 2: run the existing import pipeline...` — narrate code. AGENTS.md: «Do NOT add comments that just narrate what the code does».
- **Impact**: Класс-левел doc-comment (строки 7-23) уже описывает 4 шага; внутренние — дублирование.
- **Recommendation**: Удалить `// Step N:` (helper-имена самодокументирующие) или заменить на intent-bearing comments (например, `// Stage first — iOS Inbox URLs are reclaimed mid-read`).

### Informational (no action)

- **[business-logic]** `YrsMap.int(key:)` fallback to `youtput_read_float` корректен и обратно совместим: старые iOS-данные (stored as `.int`) читаются через `youtput_read_long`, новые (web parity) — через fallback. Grep по `.int(key:)` caller'ам не выявил регрессий (только ingredient order, servings, timestamps). Дополнительно — silent-фикс для servings/shopping-timestamp reads, которые на web-parity данных тоже стали бы работать.
- **[business-logic]** `DeepLink.openRecipeFile(URL)` Equatable работает корректно через synthesized implementation (URL — Equatable). Тесты `test_fileURL_setsOpenRecipeFilePending` / `test_handle_fileURL_routesToOpenRecipeFile` проверяют точное равенство URL, чего достаточно для AirDrop Inbox-URL'ов (iOS даёт уникальный путь).
- **[security]** AirDrop/file import trust boundary — clean. `stageSecurityScopedFile` правильно балансирует `startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource`. Destination filename — UUID-based, без path traversal. ZIP parsing делегирует в hardened `NativeRecipeImporter.parseZip` с тройной защитой от zip-бомб (16 MB JSON cap, 25 MB image cap, 500 MB aggregate cap) и строгой 3-компонентной валидацией image-путей (нет symlink/absolute-path extraction).
- **[security]** UTType declaration — clean. `LSHandlerRank: Owner` только для `ru.recipescaler.recipe` (не для `public.zip-archive`) → SC-005 соблюдён, произвольные `.zip`/`.json` не перехватываются.
- **[security]** `DebugSimulatorAutoLogin` — `enum` обёрнут в `#if DEBUG ... #endif` (строки 3, 54); Swift вырезает тип целиком в Release. `isEnabled` дополнительно гейтит `targetEnvironment(simulator)`. Build-level gating корректный — но не защищает сами credentials (см. finding #7).
- **[security]** `exportRecipe` temp-файлы в `temporaryDirectory/RecipeScalerExport/` — sandbox-only, не world-readable, без auth-токенов в payload. Hygiene-замечание (finding #5), но не security.
- **[standards]** Все новые ключи в `Localizable.xcstrings` имеют `en` + `ru`. `fileErrorMessage: LocalizedStringKey?` правильно резолвится через `Text(fileErrorMessage)`.
- **[standards]** Удалённые debug-log файлы (`CursorDebugIngestLog`, `DebugSessionNDJSONLog`) не имеют dangling references в live-коде. `RecipeReadDiagnostics` — есть stale references в scripts/docs (см. finding #17).
- **[standards]** `await MainActor.run { progress?(1, 1) }` — паттерн совпадает с `exportAll` (строка 68). Консистентно (но self-инвалидируется ранним вызовом — см. finding #4).
- **[standards]** Spec-references (`Spec 057 T027`, `Spec 057 — silent importer`) — стиль консистентен с существующими (`Spec 054`, `Spec 055`, `Spec 041` — 15+ hits).

## Recommendation

**Changes Requested** — изначально **5 HIGH-блокеров** перед merge. Все **FIXED в working tree** и проверены (build + тесты + `lint-i18n` green):

1. **Silent failure при `importedCount == 0`** (business-logic finding #1) — **FIXED**: `RecipeFileImportCoordinator` всегда выставляет toast; тест `test_importFile_emptyRecipes_stillSurfacesToast`.
2. **Staged file copy без size pre-flight** (security finding #2) — **FIXED**: `.size` pre-flight против `maxDecompressedArchiveBytes`; тест `test_importFile_oversizedFile_returnsErrorMessageWithoutStaging`.
3. **Composition-root нарушение** (architecture finding #3) — **FIXED**: `RecipeFileImportCoordinator` в `AppContainer.init`, `AppShellCoordinator` инжектит его.
4. **Прогресс-индикатор исчезает до сборки ZIP'а** (business-logic finding #4) — **FIXED**: `progress?(1, 1)` перенесён на конец `exportRecipe` (success-only).
5. **Утечка tmp-файлов в `makeInMemoryDataURL`** (business-logic/security finding #5) — **FIXED**: `.bin` файлы удаляются в обеих ветках `exportSingle`.

**MEDIUM, оставшиеся открытыми (вне scope "fix high")** — рекомендуется в follow-up:
- **#6** (`.onOpenURL` file-gating по `isNativeFormat`)
- **#7** (production debug-credentials в VCS — серверная ротация + не хранить seed)
- **#8** (InfoPlist.xcstrings ru-перевод для UTType description)
- **#13** (`waitForConnection` кооперативная с `Task.isCancelled`)
- **#14** (`NativeFormatDetector.readRecipesJsonFromZip` triple-guard)
Остальные MEDIUM и все LOW — тоже follow-up.

Защитная механика импорта (zip-bomb guards, recipe count cap, security-scoped resource handling) реализована отлично — critique сосредоточена на architectural discipline, нескольких контрактовых bug'ах и defense-in-depth gap'ах в less-traveled code paths, не на безопасности основного pipeline'а.
