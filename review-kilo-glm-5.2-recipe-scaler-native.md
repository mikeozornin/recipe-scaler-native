# Code Review: recipe-scaler-native (весь проект)

**Дата**: 2026-06-17
**Ревьюер**: Kilo (glm-5.2), 5 параллельных специализированных сабагентов
**Объект**: весь проект `master`, не отдельная ветка
**Объём**: ~44 455 LOC Swift, 278 файлов (RecipeScalerNative 225 / RecipeScalerCore 31 / extensions)
**Метод**: параллельный анализ по 5 направлениям (Security, Business Logic, Performance, Architecture, Standards) с дедупликацией и сортировкой

---

## Краткое резюме

Проект зрелый, с продуманной offline-first CRDT-архитектурой (Yjs/yrs), хорошим покрытием тестами новых фич (импорт Paprika/Crouton) и корректным применением i18n-паттернов в большинстве мест. SQL-инъекций, захардкоженных секретов и XXE не найдено; загрузка изображений устойчива к декомпрессионным бомбам.

Однако есть **системные проблемы**, требующие внимания:

1. **Модель аутентификации критически уязвима** — всё доверие построено на публичном `userId`, а не на секрете ( bearer-токене). Это корневая причина каскада проблем (plaintext-хранение, отсутствие TLS-pinning'а, утечка в логи, бэкдор-UUID в репо).
2. **Архитектурный технический долг集中ён** — два god-объекта (`YjsSyncService` 2411 строк, `DocumentManager` 1603 строки) ~~+ сломанный `Package.swift`~~ блокируют тестируемость и масштабирование (`Package.swift` исправлен — #8, см. таблицу ниже).
3. **Производительность импорта/синхронизации** — частично исправлено (2026-06-18): ~~O(N²)-вставки (#4)~~, ~~декомпрессия архивов в память целиком (#5)~~, ~~экспорт all-in-memory (#7)~~ ✅; merge через WKWebView на главном потоке (#6) и Socket.IO wire format (#17) — по-прежнему открыты.
4. ~~**i18n-нарушения в обработке ошибок**~~ — ~~`AuthError`/`APIError`/`YrsError` возвращают захардкоженный английский~~ → исправлено (spec `031-error-i18n`, см. таблицу ниже).

**Уровень риска**: высокий. Функциональность работает, но безопасность аутентификации и производительность batch-операций требуют срочных доработок до production-нагрузки.

---

## Perf remediation (2026-06-18)

Исправлены perf-находки из плана агента (без изменения security/logic). Пропущены по решению: **#6** (WKWebView merge), **#17** (Socket.IO wire format).

| # | Статус | Кратко |
|---|--------|--------|
| 4 | ✅ | Батч-вставка ингредиентов + один renumber |
| 5 | ✅ | Streaming ZIP import |
| 7 | ✅ | Streaming export off MainActor |
| 18 | ✅ | XmlFragment→HTML cache по stateVector |
| 19 | ✅ | Spotlight: Task.detached + NSCache plainText |
| 20 | ✅ | ≤3 encode qualities + Task.detached upload |
| 21 | ✅ | `recipeIdsInQueue` + batch `deleteEntries` |
| 22 | ✅ | `scheduleCollectionEntriesRefresh` debounce 150ms |
| 38 | ✅ | Batch `loadSnapshots` / `existingSnapshotKeys` / wire |
| 39 | ✅ | Migration once at app launch |
| 40 | ✅ | Memoized `cacheStatus` fingerprint |
| 41 | ✅ | Panel refresh only on displayed-second change |
| 42 | ✅ | `readSearchIndex` / `peekSearchIndex` |
| 43 | ✅ | `persistAndDeliver` single encode |
| 65 | ✅ | Equatable rows + memoized pin split |
| 66 | ✅ | Single write-txn in `mergeYjsUpdates` |

---

## Error i18n remediation (2026-06-18)

Исправлена находка **#11** (spec [`031-error-i18n`](specs/031-error-i18n/spec.md)).

| # | Статус | Кратко |
|---|--------|--------|
| 11 | ✅ | `AuthError` / `APIError` / `YrsError` — локализация через `Bundle.currentLocalizedString` + dot-key контракт |
| 11a | ✅ | `DotKeyLocalizer` + `APIError+Localization.swift` + `UserFacingAPIError.message(for:)` |
| 11b | ✅ | 29 throw-сайтов `APIError.serverError(message:)` → dot-key fallback |
| 11c | ✅ | ~56 view-сайтов: `UserFacingAPIError.message(for: error)` вместо `error.localizedDescription` |
| 11d | ✅ | 622 ключа в `Localizable.xcstrings` (en+ru), `ErrorLocalizationTests` + расширенный `LocalizationConsistencyTests` |
| 11e | ✅ | Dead-code удалён: `AuthError.userNotFound`, `AuthError.seedPhraseGenerationFailed`, `YrsError.invalidState`, `YrsError.corruptedState` |
| 11f | ✅ | Документация: `docs/I18N.md` (секция Error-типы), `server-error-keys.md` синхронизирован с кодом |

**Вне scope #11** (отдельная задача): `NativeImportError` в Core всё ещё возвращает английский из `errorDescription` — в UI попадает generic fallback через `UserFacingAPIError`, не сырой текст.

---

## Package.swift remediation (2026-06-18)

Исправлена находка **#8** — SPM-манифест сделан каноническим.

| # | Статус | Кратко |
|---|--------|--------|
| 8 | ✅ | `.binaryTarget(name: "YrsC", path: "Frameworks/YrsXCFramework.xcframework")` добавлен |
| 8a | ✅ | Source-target `RecipeScalerCore` (path `RecipeScalerCore`, ресурсы `Resources` + `Export/Native/schemas`) |
| 8b | ✅ | `RecipeScalerNative` явно зависит от `"RecipeScalerCore"` и `"YrsC"` |
| 8c | ✅ | `RecipeScalerNativeTests` явно зависит от `"RecipeScalerCore"` и `"YrsC"` (для `@testable import RecipeScalerCore` и `import YrsC`) |
| 8d | ✅ | `RecipeScalerCore` добавлен в `products` (доступен как library для будущих SPM-consumer'ов) |
| 8e | ✅ | Баг в exclude: убран `"RecipeScalerNative.xcodeproj"` (указывал на несуществующий путь `RecipeScalerNative/RecipeScalerNative.xcodeproj`, давал warning) |
| 8f | ✅ | Валидация: `swift package describe` — 4 таргета / 2 продукта; `swift package resolve` exit 0; `xcodebuild build -scheme RecipeScalerCore -destination 'generic/platform=iOS Simulator'` → BUILD SUCCEEDED |

**Замечание**: `swift build` под macOS-host падает с `requires macos 10.13, but depends on the product 'GRDB' which requires macos 10.15` — ожидаемое ограничение iOS-only манифеста (`.iOS(.v17)`), не дефект правки. Проверка SPM-сборки под iOS — через `xcodebuild -destination 'platform=iOS Simulator'`.

**Вне scope #8**: `swift build` всё ещё не собирает полный app-target из CLI — `xcodeproj`-схема `RecipeScalerNative` падает на pre-existing проблемах (entitlements ShareExtension, архитектурный конфликт SocketIO без явного `-destination`). Это не относится к манифесту и требует отдельной работы по xcodeproj-конфигурации.

---

## Int(Double) overflow safety remediation (2026-06-18)

Исправлена находка **#14** — Swift precondition trap на `Int(amountValue)` в Crouton-парсере. Audit также выявил и закрыл ~6 связанных сайтов с тем же классом бага.

| # | Статус | Кратко |
|---|--------|--------|
| 14 | ✅ | `CroutonRecipeParser.parseQuantity` → `Int(exactly:)` + fallback на `String(amountValue)`; NaN/Inf → `""`; 5 TP14 edge-case тестов |
| 14a | ✅ | `AssistantMessageFooter.formattedValue`/`stepperRange` — NaN/Inf guard + `Int(exactly:)` fallback; Stepper range clamp к `Double(Int.min)...Double(Int.max)` |
| 14b | ✅ | `RecipeServings` / `RecipeNutritionDisplay` / `IngredientNutritionDisplay` / `EditIngredientNutritionSheet` — safe-casts через shared `Int(clampingFinite:)` / `Int(exactlySafe:)` |
| 14c | ✅ | `XmlFragmentToHTML.formatAmount` / `RecipeDescriptionXmlFragmentWriter.formatAmount` — `Int(exactlySafe:)` guard |
| 14d | ✅ | `DescriptionMarkupFlow.durationSeconds` / `parseDurationSeconds` / `ratioPercent` — `intRoundedClamped` |
| 14e | ✅ | Timer internals: `TimerSnapshot.remainingSeconds`, `RecipeTimerActivityAttributes.remainingSeconds`, `TimerLiveActivityAccent.resolve`, `WidgetTimerAccent.resolve`, `TimerSyncService.timerCreatedPayload` — inline guards (extension-target-aware) |
| 14f | ✅ | Shared helper `RecipeScalerNative/Utils/SafeIntCasts.swift` (`Int(exactlySafe:)`, `Int(clampingFinite:)`, `Int64(clampingFinite:)`, `intRoundedClamped`); зарегистрирован в `project.pbxproj` main app target |
| 14g | ✅ | Документация: [docs/I18N.md](docs/I18N.md) — новая секция «Int(Double) safe casts» с таблицей API, примерами и правилами для extension-target кода |

**Вне scope #14**: ad-hoc `Int(...)` на `BinaryInteger`/`UInt32` FFI-длинах (Yjs/Yrs C-pointer reads, `YjsPayloadBytes` byte boxing) — остаются `init(clamping:)` или `truncatingIfNeeded:` из stdlib, не относятся к `Double`-overflow.

---

## Architecture remediation (завершено, 2026-06-18)

Две серии архитектурных refactor'ов из review-kilo (#23-26), разбитые на 2 PR. Layout-аудит не требовался (бэкенд/модельный слой; единственная view-правка — удаление legacy `RecipeDetailView`).

| # | Статус | Кратко |
|---|--------|--------|
| 24 | ✅ | PR1 `033-architecture-modularization`: `YrsXmlFragment`/`YrsXmlElement`/`YrsXmlText`/`YrsXmlAttrIterator` (RAII по образцу `YrsMapEntry`); `YrsDocument.xmlFragment`/`recipeMap`; 5 Utils → `Services/Yrs/Description/`; 5 call sites `DocumentManager`; `project.pbxproj`; `YrsXmlFragmentTests` (7 round-trip green) |
| 25 | ✅ | PR1 `033-architecture-modularization`: SPM-target `ShareExtensionUI` (depends on Core); `ShareView`/`ShareContentLoader`/`ShareContentClassifier` + `Shared.xcstrings` → `ShareExtensionUI/`; удалить `RecipeScalerCore/UI/`; `PBXNativeTarget` + link Share/Action; `ShareContentClassifierTests` → `@testable import ShareExtensionUI` |
| 23 | ✅ | PR2 `034-architecture-dedup-truth`: расширить Core `ImportPhotoItem` (`Identifiable`+`Sendable`+`Equatable` через data+fileName, `byteCount`, convenience init); объединить `ValidationError` cases (dot-key + args в `errorDescription`); перенести Native-only `ImportErrorLocalizer` cases в Core (per-recipe, servings, ICU-substitution, `locale:`); удалить 2 Native-файла (были мёртвым кодом — не в pbxproj); обновить callers (`ImportRecipeSheet`); `ImportLimitsConsistencyTests` — комментарий 3→2 места |
| 26 | ✅ | PR2 `034-architecture-dedup-truth` (`keep_timer_only` + `extract_then_delete`): извлечь `StepsSection` → `Views/RecipeStepsSection.swift` и `DisplayIngredient` → `Models/YDoc/`; удалить `RecipeDetailView.swift` (444 LOC, unreachable в runtime) + snapshot-тесты; удалить `Models/Recipe.swift`/`Ingredient.swift`/`ApiCacheEntry.swift`; `RecipeScalerNativeApp.swift` Schema → `[RecipeTimer.self]`; обновить `TestSupport`/`SnapshotTests`/`RecipeListViewModel`/`ContentView #Preview`; обновить `docs/ARCHITECTURE.md`/`SETUP.md`/`PROJECT_STATUS.md`/`specs/001/` (historical notes) |

**Очерёдность**: PR1 (#24 → #25) → PR2 (#26 → #23). Build verify: `xcodebuild build` (main + Share + Action schemes) — все 3 scheme green; test verify: `xcodebuild test` (PluralizationTests, ImportLimitsConsistencyTests, ShareContentClassifierTests, SnapshotTests, YrsXmlFragmentTests — все green). Fix-until-green по `.agents/skills/fix-until-green/SKILL.md`.

**Риски и решения**: #24 — FFI-lifetime semantics (`ychunks_destroy`/`yxmlattr_destroy` в `deinit`), покрыто `YrsXmlFragmentTests` round-trip'ами; #25 — `Bundle.module` для `Shared.xcstrings` — `Shared.xcstrings` остался в Core, `ShareView` использует `Bundle(for: APIClient.self)`; #23 — `Identifiable`+`Sendable`+`Equatable` одновременно — UUID генерируется при init, Equatable по data+fileName (id исключён), соответствует прежнему Native-поведению; #26 — потеря визуального регрессионного покрытия для legacy `RecipeDetailView` (unreachable в runtime, замены нет — зафиксировано в spec'е).

---

## Находки (отсортированы по приоритету)

### Critical

#### 1. **[Security]** Аутентификация построена только на публичном `userId`, без секрета
- **Area**: `RecipeScalerCore/Networking/APIClient.swift:95-97,122-127`; `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1115,1287-1290`; `RecipeScalerNative/Services/AuthService.swift:122,305`
- **Description**: После логина auth-токен явно отбрасывается (`token = nil`). Каждый последующий HTTP и Socket.IO запрос аутентифицируется **только** строкой `userId` — в заголовке `x-user-id` (APIClient), в Socket.IO `connectParams` (`["userId": userId, "deviceId": deviceId]`) и в `auth`-эмите. Сид-фраза (настоящий секрет) используется ровно один раз при логине. `userId` — публичный идентификатор, не bearer-секрет.
- **Impact**: Любой, кто узнает `userId`, может полностью выдать себя за жертву — чтение/запись всех рецептов, списков покупок, профиля, push-состояния. Нет второго фактора и нет отзываемого сервером креденшала на клиенте. Корневая причина находок №2, №3, №8 (Critical/High), №12 (Low).
- **Recommendation**: Выпускать и отправлять настоящий короткоживущий bearer-токен (или подписывать запросы device-ключом); перестать доверять «голому» `userId`. Это изменение бэкенда+клиента.

#### 2. **[Security]** Захардкоженный production UUID пользователя закоммичен в репо
- **Area**: `RecipeScalerNative/ContentView.swift:19` — `private let debugUserId = "cfcd839f-56f2-4411-9632-7795b75f96d1"`
- **Description**: Из-за находки №1 этот UUID **и есть** живой креденшал реального production-аккаунта, в который каждый сборка симулятора делает auto-login (`effectiveUserId`/`isAuthenticated` возвращают его безусловно под `#if targetEnvironment(simulator)`). Он лежит в VCS, читается любым, у кого есть доступ к репо.
- **Impact**: Полная компрометация debug-аккаунта (и всех реальных данных в нём) любым, кто прочитает репо. Гард `#if targetEnvironment(simulator)` не защищает сам креденшал.
- **Recommendation**: Считать UUID скомпрометированным и ротировать аккаунт. Не встраивать рабочий креденшал в исходники; если нужен debug auto-login — получать эфемерный токен с сервера в рантайме.

#### 3. ~~**[Security / Performance]** Декомпрессионная бомба: gzip и ZIP без ограничений на распакованный размер~~ ✅ Исправлено (2026-06-18, spec [`032-import-decompression-bomb`](specs/032-import-decompression-bomb/spec.md))
- ~~**Area**: `RecipeScalerCore/Import/ThirdParty/Gunzip.swift:22-44`; `RecipeScalerCore/Import/ThirdParty/ThirdPartyFormatDetector.swift:139-150` (`enumerateZipEntries`); `RecipeScalerCore/Export/Native/NativeRecipeImporter.swift:106-110,157-160`~~
- ~~**Description**: `Gunzip.decompress` циклит `inflate`, дописывая чанки в `output = Data()` **без ограничения итогового размера**…~~ Triple-guard (pre-flight `entry.uncompressedSize` + streaming running total + aggregate cap) во всех путях; JSON pre-flight (см. #32); TDD-покрытие 21 кейсом.
- ~~**Impact**: Многомегабайтный gzip-stream разрастается до многих ГБ → OOM/краш…~~ Закрыто.

#### 4. ~~**[Performance / Business Logic]** O(N²)-вставка ингредиентов + двойная full-doc кодировка при импорте~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerNative/Services/YjsSync/DocumentManager.swift:318-326,1492-1499,1058-1090,1189-1207`~~
- ~~**Description**: `applyImportedRecipe`/`applyNativeRecipe` вызывают `addIngredient` по одному ингредиенту…~~ Батч-вставка ингредиентов + один renumber; `persistAndDeliver` — одна кодировка (#43).
- ~~**Impact**: Импорт не укладывается в целевые «≤2 мин на 50 рецептов»…~~
- ~~**Recommendation**: Батчить весь массив ингредиентов…~~

#### 5. ~~**[Performance]** Весь архив декодируется в память до цикла импорта~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerCore/Import/ThirdParty/ThirdPartyFormatDetector.swift:117-159`; `RecipeScalerNative/Services/ThirdPartyRecipeImportService.swift:38-42`~~
- ~~**Description**: `enumerateZipEntries` извлекает и буферизует **полную распакованную Data** каждого entry заранее…~~ Streaming ZIP import.
- ~~**Impact**: OOM на устройствах с малым RAM…~~
- ~~**Recommendation**: Стримить entries лениво…~~

#### 6. **[Performance]** Yjs merge/encode выполняется на главном потоке через WKWebView
- **Area**: `RecipeScalerNative/Services/YjsSync/YjsMergeHelper.swift:10-67`; вызовы `UpdateDebouncer.swift:54-69`, `YjsSyncService.swift:286,1535,1721,1738`
- **Description**: `YjsMergeHelper` — `@MainActor`, выполняет `Y.mergeUpdates`/`Y.encodeStateAsUpdate` через `evaluateJavaScript` в скрытом WKWebView. Конвертирует каждую `Data` в `[NSNumber]` (boxing байта) → JSON-сериализация → eval JS → парсинг `[NSNumber]` обратно. Вызывается из debouncer-flush, reconnect-drain, wire-snapshot-rebuild и offline-push-resolution — часто и потенциально подряд.
- **Impact**: Каждый merge блокирует главный поток (JS синхронный для `evaluateJavaScript`); большие апдейты дают видимый jank/freeze при reconnect-storms. Boxing в NSNumber удваивает память и аллоцирует тяжело.
- **Recommendation**: Реализовать merge нативно в yrs (Rust `merge_updates_v1`/`encode_state_as_update` уже доступны через FFI, обёрнутый в `YrsDocument`); полностью уйти с `@MainActor`. Если WebView остаётся — хотя бы убрать NSNumber-boxing в пользу base64.

#### 7. ~~**[Performance]** Экспорт грузит все рецепты + все байты изображений в память на MainActor~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerNative/Services/NativeExportImportService.swift:34-94`~~
- ~~**Description**: `exportAll` сначала обходит все рецепты…~~ Streaming export off MainActor (`Task.detached`).
- ~~**Impact**: Для сотен рецептов с изображениями пиковая память…~~
- ~~**Recommendation**: Стримить в экспортёр…~~

#### 8. ~~**[Architecture]** `Package.swift` сломан: не объявляет `RecipeScalerCore` и `YrsC`~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `Package.swift:33-58`; реальный сборка живёт в `RecipeScalerNative.xcodeproj`~~
- ~~**Description**: SPM-манифест опускает таргет `RecipeScalerCore` и XCFramework `YrsC`. `swift build` из CLI не работает; только Xcode-проект…~~ Манифест сделан каноническим: добавлены `.binaryTarget(name: "YrsC", path: "Frameworks/YrsXCFramework.xcframework")`, source-target `RecipeScalerCore` (path `RecipeScalerCore`, ресурсы `Resources/Shared.xcstrings` + `.copy("Export/Native/schemas")`), явные зависимости `RecipeScalerCore`/`YrsC` у `RecipeScalerNative` и `RecipeScalerNativeTests`, `RecipeScalerCore` добавлен в `products`. Заодно убран баг в exclude (`"RecipeScalerNative.xcodeproj"` указывал на несуществующий путь внутри `RecipeScalerNative/`). Валидация: `swift package describe` — 4 таргета / 2 продукта корректно описаны; `swift package resolve` exit 0; `xcodebuild build -scheme RecipeScalerCore -destination 'generic/platform=iOS Simulator'` → **BUILD SUCCEEDED**.
- ~~**Impact**: CI-скрипты, agent-loops и внешний tooling, вызывающие `swift build`, получают ложный green или жёсткий fail…~~ Граф SPM теперь определён и согласован с графом Xcode.
- ~~**Recommendation**: Либо удалить `Package.swift`…~~ Выполнено (канонический путь). Замечание: `swift build` под macOS-host всё равно падает с `requires macos 10.13, but depends on the product 'GRDB' which requires macos 10.15` — это ожидаемое ограничение iOS-only манифеста (`.iOS(.v17)`), не дефект правки. Для проверки используется `xcodebuild -scheme ... -destination 'platform=iOS Simulator'`.

#### 9. **[Architecture]** `YjsSyncService` — god-объект на 2411 строк, `@MainActor ObservableObject`
- **Area**: `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift`
- **Description**: Один тип владеет: жизненным циклом сокета, auth-handshake, watchdog-таймерами (5 разных `Task`-watchdogs на строках 64-69), загрузкой документов, mutation API рецептов/коллекций/списка покупок (~40 публичных методов), drain'ом offline-очереди, network reachability, статусом image-cache, реестром description-editor-сессий, маршрутизацией sync-ошибок и 22 `@Published`-свойствами. `start(userId:)` лезет в `APIClient.shared`, `TimerSyncService.shared`, `PushRegistrationService.shared` и назначает callback на себя.
- **Impact**: Нетестируем как unit (любой тест тянет весь граф), единая точка отказа, каждое конкурентное изменение ре-рендерит всех `@Published`-наблюдателей, race-prone reconnect-логика, блокирует любую будущую параллелизацию.
- **Recommendation**: Разделить по 4 реальным ответственностям: `SocketTransport` (connect/auth/watchdog/reconnect), `DocumentStore` (load/apply/snapshot), `SyncCoordinator` (offline queue + merge + wire export), тонкий `YjsSyncService`-facade. Инжектить `TimerSyncService`/`PushRegistrationService` вместо `.shared`.

#### 10. **[Architecture]** `DocumentManager` — god-объект на 1603 строки с утечкой closure-API
- **Area**: `RecipeScalerNative/Services/YjsSync/DocumentManager.swift`
- **Description**: Один actor обрабатывает lifecycle документов, GRDB-персистентность снапшотов, парсинг коллекций, version-aware чтение рецептов, запись полей рецепта (name/servings/color/ingredients/nutrition/image/isPublic), запись коллекций, CRUD папок, операции списка покупок, применение description-editor-апдейтов, установку наблюдателей. Мутаторы вроде `updateCollectionEntry(recipeId:_:)` (строки 384-408) отдают вызывающим сырые `(YrsMap, OpaquePointer)` и позволяют тем вызывать YrsC FFI напрямую вне actor'а.
- **Recommendation**: Вынести `RecipeRepository`, `CollectionRepository`, `FolderRepository`, `ShoppingListRepository`, `DescriptionFragmentRepository` (каждый с типизированными value-in/value-out API); оставить `DocumentManager` тонким doc-pool-actor'ом.

#### 11. ~~**[Standards / Architecture]** `AuthError`, `APIError`, `YrsError` возвращают захардкоженный английский, видимы пользователю~~ ✅ Исправлено (2026-06-18)
- **Area**: `RecipeScalerNative/Services/AuthService.swift` (AuthError); `RecipeScalerCore/Networking/APIClient.swift` (APIError); `RecipeScalerNative/Services/Yrs/YrsError.swift`; view-layer через `UserFacingAPIError.message(for:)`
- **Description**: ~~Несмотря на строгое i18n-правило AGENTS.md…~~ Реализован гибридный паттерн: fixed cases → `Bundle.currentLocalizedString`, server messages → dot-key контракт (`specs/031-error-i18n/server-error-keys.md`), view-layer → `UserFacingAPIError.message(for:)`. Dead-code кейсы удалены.
- **Impact**: ~~Пользователи на ru-локали видят непереведённые ошибки…~~ Ошибки аутентификации/сети/CRDT/resolver'ов локализуются; legacy English от сервера → generic fallback, не утекает в UI.
- **Recommendation**: ~~Взять за образец…~~ Выполнено. Следующий шаг (опционально): локализовать `NativeImportError` в Core по тому же паттерну.

---

### High

#### 12. ~~**[Security]** Креденшал (`userId`) хранится plaintext в UserDefaults, не в Keychain~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerNative/Services/AuthService.swift:117-119,154-156`; `RecipeScalerCore/Auth/SharedAuthStore.swift:24-34`~~
- ~~**Description**: `userId` (единственный креденшал по находке №1) персистится в `UserDefaults.standard` и зеркалируется в App Group `UserDefaults`. UserDefaults — plaintext plist на диске. Keychain (правильно используемый для сид-фразы) дал бы hardware-backed шифрованное хранилище.~~ `SharedAuthStore` переписан на `kSecClassGenericPassword` через raw Security framework (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); `AuthService` пишет/читает `userId` только через Keychain; legacy plaintext-следы в `UserDefaults.standard` и App Group `UserDefaults` вычищаются один раз за холодный старт (`purgeLegacyUserDefaultsCredentials`).
- ~~**Impact**: На скомпрометированном/резервном устройстве forensic-инструменты читают UserDefaults тривиально; получение userId = полный takeover.~~
- ~~**Recommendation**: Хранить креденшал в Keychain (класс `.afterFirstUnlockThisDeviceOnly`); если extensions должны читать — добавить keychain access group в entitlements.~~ Выполнено: `keychain-access-groups = [$(AppIdentifierPrefix)ru.recipescaler.RecipeScalerNative]` добавлен во все 5 entitlements (main + Share/Action/HomeWidget/TimerLiveActivity); тесты `SharedAuthStoreTests` (6) + `AuthServiceMigrationTests` (3) зелёные.

#### 13. **[Security]** Нет TLS certificate/SPKI-pinning'а
- **Area**: `RecipeScalerCore/Networking/APIClient.swift:145`; Socket.IO в `YjsSyncService.swift:1120`
- **Description**: Весь нетворкинг использует `URLSession.shared` и дефолтный `URLSession` Socket.IO. Никакой `URLSessionDelegate` не делает pinning.
- **Impact**: Атакующий с доверенным CA (enterprise MDM, jailbreak) может MITM'ить и читать `x-user-id`/тела. В связке с находкой №1 один перехваченный запрос = полный takeover.
- **Recommendation**: Пинить API/WS-эндпоинты (SPKI-pinning — устойчивый выбор) через кастомный `URLSessionDelegate`, fail closed при несовпадении.

#### 14. ~~**[Business Logic]** Crouton `Int(amountValue)` крэшит на больших значениях~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerCore/Import/ThirdParty/CroutonRecipeParser.swift:113-115`~~
- ~~**Description**: `parseQuantity` делает `Int(amountValue)`. При `quantity.amount` целочисленном Double вне диапазона `Int64` (напр. `1e19`) — это Swift-предусловие trap (overflow), не throw. Импорт — фича, обрабатывающая недоверенные `.crumb`/zip.~~ Заменено на `Int(exactly:)` с fallback на `String(amountValue)`; NaN/Infinity → пустая строка. Audit также выявил и закрыл ~6 связанных `Int(Double)`-сайтов (AssistantMessageFooter Stepper, RecipeServings/RecipeNutritionDisplay/IngredientNutritionDisplay/XmlFragmentToHTML/RecipeDescriptionXmlFragmentWriter/EditIngredientNutritionSheet/DescriptionMarkupFlow через shared helper, timer internals в `TimerSnapshot` / `RecipeTimerActivityAttributes` / `TimerLiveActivityAccent` / `WidgetTimerAccent` / `TimerSyncService`).
- ~~**Impact**: Crafted (или патологически большой) Crouton-файл прерывает весь импорт жёстким крэшем; нет изоляции per-entry-ошибок.~~ Закрыто. 5 новых TP14 edge-case тестов (overflow / in-range-large / negative / normal / fractional) в `CroutonRecipeParserTests.swift` — все зелёные.
- Shared helper: [`RecipeScalerNative/Utils/SafeIntCasts.swift`](../RecipeScalerNative/Utils/SafeIntCasts.swift) (`Int(exactlySafe:)`, `Int(clampingFinite:)`, `Int64(clampingFinite:)`). Для UI-форматирования — `IngredientData.formatScalarNumber`. Паттерн задокументирован в [docs/I18N.md](../docs/I18N.md) (секция «Int(Double) safe casts»).

#### 15. **[Business Logic]** Нативный экспорт молча теряет нечисловые количества ингредиентов при roundtrip
- **Area**: `RecipeScalerNative/Services/NativeExportImportService.swift:50`; `RecipeScalerNative/Models/YDoc/IngredientData.swift:127-132`
- **Description**: `ExportIngredient.originalAmount` питается `ing.numericValue` (= `Double(originalAmount)`). Значения вроде `"1/2"`, `"2-3"`, `"1½"`, `"to taste"` дают `nil`. У `ExportIngredient` нет строкового поля суммы → значение потеряно безвозвратно. На реимпорте `nil` originalAmount → `hasQuantity = false` → ингредиент становится заголовком без количества.
- **Impact**: Export→import roundtrip теряет дробные/диапазонные количества: «1/2 стакана сахара» → «стакан, сахар» без количества.
- **Recommendation**: Экспортировать сырую `originalAmount`/`amount`-строку рядом с Double (как веб-экспортёр), либо добавить строковое поле в `ExportIngredient`/`NativeIngredient`.

#### 16. **[Business Logic]** Ошибка `applyUpdateToDoc` удаляет весь локальный снапшот (потеря данных)
- **Area**: `RecipeScalerNative/Services/YjsSync/DocumentManager.swift:113-126` и `:1156-1164`
- **Description**: При любом throw из `doc.applyUpdate`/`applyLocalUpdate` код делает `docs.removeValue`, `observerTokens.removeValue` и `store.deleteSnapshot(docKey:)` перед re-throw. yrs `applyUpdate` обычно атомарный (плохой remote-апдейт отвергается без мутации), поэтому эта оборонительная очистка слишком агрессивна: один malformed **remote**-апдейт (или транзиентная ошибка yrs) уничтожает снапшот, который может содержать несинхронизированные локальные правки. Последующий `requestDocumentReload` → `replaceDocument` с сервера навсегда их дропает.
- **Impact**: Транзиентный/мусорный remote `recipe_updated` может вызвать перманентную потерю offline-first локальных правок этого рецепта.
- **Recommendation**: При ошибке remote-апдейта не удалять локальный снапшот; только эвиктить in-memory doc (или ретраить yrs). Резервировать удаление снапшота для случая, когда он доказуемо повреждён (как в `getOrCreateDoc:72-77`).

#### 17. **[Performance]** Socket.IO sync-payloads упаковывают каждый байт в `[Int]`
- **Area**: `RecipeScalerNative/Services/YjsSync/YjsPayloadBytes.swift:5-7`; `YjsSyncService.swift:1590`; `SyncEventHandler.swift:83-125`
- **Description**: `YjsPayloadBytes.array(from:)` = `data.map { Int($0) }`, создаёт boxed `[Int]` (16×+ рост памяти против сырых байт) для каждого исходящего `sync_request`. Входящий парсинг тоже кастует к `[Any]` и упаковывает поэлементно.
- **Impact**: Усиление памяти 2–3× на каждом sync round-trip; тяжёлый Obj-C bridging + autorelease; GC-stall'ы на больших апдейтах.
- **Recommendation**: Использовать binary/`Data` Socket.IO (или base64 в JSON); если сервер требует JSON number-array — кодировать через `Array(UnsafeBufferPointer)` без per-element boxing.

#### 18. ~~**[Performance]** Полная конверсия XmlFragment→HTML на каждом чтении рецепта~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerNative/Services/YjsSync/DocumentManager.swift:189-211`; `RecipeScalerNative/Utils/XmlFragmentToHTML.swift:108-476`~~
- ~~**Description**: `readRecipeData` всегда прогоняет `XmlFragmentToHTML.serializedFragment`…~~ Кеш по stateVector.
- ~~**Impact**: Поиск по 100 рецептам = 100 полных чтений…~~
- ~~**Recommendation**: Кешировать сконвертированный HTML…~~

#### 19. ~~**[Performance]** Spotlight-индексация полностью на `@MainActor` + синхронные дисковые чтения + NSAttributedString HTML~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerNative/Services/SpotlightIndexer.swift:18,103-156,233-265`~~
- ~~**Description**: `SpotlightIndexer` — `@MainActor`. `indexOne` вызывает `peekRecipeData`…~~ `Task.detached` + NSCache plainText.
- ~~**Impact**: Reindex-всплески stall'ят главный поток…~~
- ~~**Recommendation**: Вынести тяжёлую per-recipe работу в background-`Task`…~~

#### 20. ~~**[Performance]** Image upload preprocessor до ~112 encode-проходов на `@MainActor`~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerNative/Utils/RecipeImageUploadPreprocessor.swift:34-60,134-165`; вызов `YjsSyncService.swift:620-621`~~
- ~~**Description**: `payloadForUpload` работает на главном actor'е…~~ ≤3 encode qualities + `Task.detached`.
- ~~**Impact**: При multi-recipe импорте с изображениями…~~
- ~~**Recommendation**: Вынести preprocess в `Task.detached`…~~

#### 21. ~~**[Performance]** Offline-очередь: full-table fetch на рецепт (N+1) и per-row DELETE~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `YjsSyncService.swift:313-328` (`hasUnsyncedLocalChanges`), вызовы в циклах 375,1518-1521,1694-1696; per-entry deletes 1639-1645, 1682-1686~~
- ~~**Description**: `hasUnsyncedLocalChanges` вызывает `offlineQueue.fetchAll()`…~~ `recipeIdsInQueue` + batch `deleteEntries`.
- ~~**Impact**: Reconnect/offline-drain с R рецептами…~~
- ~~**Recommendation**: Фетчить очередь один раз…~~

#### 22. ~~**[Performance]** Каскад `refreshCollectionEntries` не дебаунсится и перезапускается на каждую мутацию~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `YjsSyncService.swift:2129-2154`; observer wiring 2213-2218~~
- ~~**Description**: Collection deep observer вызывает `Task { await refreshCollectionEntries() }` напрямую…~~ `scheduleCollectionEntriesRefresh` debounce 150ms.
- ~~**Recommendation**: Дебаунсить/coalesce `refreshCollectionEntries`…~~

#### 23. ~~**[Architecture]** Дубликаты валидаторов/локализаторов между `RecipeScalerCore` и `RecipeScalerNative`~~ ✅ Remediated (2026-06-18, PR2 = `specs/034-architecture-dedup-truth`, задача #23)
- ~~**Area**: `RecipeScalerCore/Import/ImportPhotoValidator.swift` vs `RecipeScalerNative/Utils/ImportPhotoValidator.swift`; аналогично `ImportErrorLocalizer`~~
- ~~**Description**: Два `ImportPhotoValidator` с разными `ValidationError` (Core: `.tooMany(count:)`, `.tooLarge(name:size:)`; Native: `.tooMany`, `.tooLarge`). Два `ImportPhotoItem` (Core — `Equatable + Sendable` без id; Native — `Identifiable` UUID, не `Sendable`). Native-файл импортирует Core и дизэмбигуирует `RecipeScalerCore.ImportPhotoValidator.maxRecipes`.~~
- ~~**Impact**: Type-juggling при пересечении границ модулей, дрейф лимитов/сообщений, два пути локализации, каждый фикс применяется дважды.~~
- ~~**Recommendation**: Удалить Native-дубликаты; main app потребляет Core public-типы, плюрализацию через `Bundle.main`.~~ — **сделано**: Core `ImportPhotoItem` расширен (`Identifiable`+`byteCount`+convenience init, Equatable по data+fileName), Core `ImportErrorLocalizer` расширен (per-recipe, servings, ICU-substitution, `locale:` параметр), 2 Native-файла удалены (были мёртвым кодом — не в pbxproj), callers обновлены (`ImportRecipeSheet`), `ImportLimitsConsistencyTests` — комментарий 3→2 места. Build green (3 scheme), tests green (PluralizationTests, ImportLimitsConsistencyTests, ShareContentClassifierTests).

#### 24. ~~**[Architecture]** YrsC FFI вызывается из файлов `Utils/`, ломая границу `Services/Yrs/`~~ ✅ Remediated (2026-06-18, PR1 = `specs/033-architecture-modularization`, задача #24)
- ~~**Area**: `RecipeScalerNative/Utils/XmlFragmentToHTML.swift` (713 LOC), `Utils/DescriptionXmlFragmentWriter.swift`, `Utils/RecipeDescriptionXmlFragmentWriter.swift` (314 LOC), `Utils/RecipeReader.swift`~~
- ~~**Description**: Дизайн-намерение (AGENTS.md) — «`Yrs/` C FFI wrappers». В реальности `XmlFragmentToHTML.serializedFragment` (строка 18), `DescriptionXmlFragmentWriter.apply`, `RecipeReader` вызывают `ytype_get`, `yxmlelem_insert_elem` и т.п. напрямую на сыром `OpaquePointer`-txn, переданном из `DocumentManager`. У обёрток `Yrs*` вообще нет `XmlFragment`-типа.~~
- ~~**Impact**: Каждый FFI-фикс безопасности приходится выводить заново на каждом сайте вызова; рефакторинг FFI-поверхности невозможен без правок Utils.~~
- ~~**Recommendation**: Добавить `YrsXmlFragment`, `YrsXmlElement`, `YrsXmlText` под `Services/Yrs/`; переместить эти Utils в `Services/Yrs/Description/`.~~ — **сделано**: введены `YrsXmlFragment`/`YrsXmlElement`/`YrsXmlText`/`YrsXmlAttrIterator` (RAII-обёртки по образцу `YrsMapEntry`), `YrsDocument` расширен (`xmlFragment(txn:name:)`, `recipeMap(txn:)`), 5 Utils-файлов переписаны и перенесены в `Services/Yrs/Description/`, 5 call sites в `DocumentManager` обновлены, `project.pbxproj` обновлён, `YrsXmlFragmentTests` (7 round-trip green).

#### 25. ~~**[Architecture]** `RecipeScalerCore/UI/` сцепляет «core»-фреймворк с UIKit/SwiftUI~~ ✅ Remediated (2026-06-18, PR1 = `specs/033-architecture-modularization`, задача #25)
- ~~**Area**: `RecipeScalerCore/UI/ShareContentLoader.swift:10` (`import UIKit`), `ShareContentLoader.swift:11` (`import UniformTypeIdentifiers`), `ShareView.swift:11` (`import SwiftUI`)~~
- ~~**Description**: AGENTS.md: «yrs writer in Core (no UIKit)». Но `UI/` внутри Core держит SwiftUI-views и UIKit-связанные loaders, не имеющие отношения к CRDT-writer'у или domain-логике; это extension-host glue. Нахождение их в Core заставляет каждого consumer'а Core линковать UIKit/SwiftUI.~~
- ~~**Impact**: SPM-consumers of Core вынужденно линкуют UIKit/SwiftUI/UTType; нарушение AGENTS.md «yrs writer in Core (no UIKit)».~~
- ~~**Recommendation**: Перенести `ShareContentLoader`, `ShareContentClassifier`, `ShareView` в выделенный `ShareExtensionUI`-таргет (или в сами extension-таргеты); оставить в Core только чистую логику.~~ — **сделано**: новый SPM-target `ShareExtensionUI` (depends on `RecipeScalerCore`), 3 файла перенесены в `ShareExtensionUI/`, `RecipeScalerCore/UI/` удалён, `Shared.xcstrings` остался в Core (`ShareView` использует `Bundle(for: APIClient.self)`), `project.pbxproj` обновлён (`PBXNativeTarget` + link Share/Action extensions), `ShareContentClassifierTests` → `@testable import ShareExtensionUI` (green).

#### 26. ~~**[Architecture]** Двойной source of truth: SwiftData `Recipe` сосуществует с Y.Doc-производным `RecipeData`~~ ✅ Remediated (2026-06-18, PR2 = `specs/034-architecture-dedup-truth`, задача #26)
- ~~**Area**: `RecipeScalerNative/Models/Recipe.swift` (`@Model`, зарегистрирован в `RecipeScalerNativeApp.swift:64-85`) vs `RecipeScalerNative/Models/YDoc/RecipeData.swift`~~
- ~~**Description**: AGENTS.md/`docs/ARCHITECTURE.md` объявляют Y.Doc source of truth. Но SwiftData-схема `Recipe`/`Ingredient`/`RecipeTimer`/`ApiCacheEntry` зарегистрирована в `ModelContainer`, и только `TimerManager` читает её через `FetchDescriptor<Recipe>`. Ни одного `@Query` против `Recipe` в views нет. Рядом живут legacy `RecipeDetailView.swift` (444 LOC) и Y.Doc-backed `YDocRecipeDetailView.swift` (1168 LOC).~~
- ~~**Impact**: Два параллельных представления рецепта, риск дрейфа, неясно новичку, что канонично. `Recipe` несёт legacy-поля (`scaleFactor`, `detailEtag`, `imagePreviewLocalPath`).~~
- ~~**Recommendation**: Либо уйти от SwiftData `Recipe` полностью (таймеры читают из `peekRecipeData`), либо явно ограничить SwiftData до `RecipeTimer`/`ApiCacheEntry` и удалить `Recipe`/`Ingredient`-модели. Удалить legacy `RecipeDetailView.swift`.~~ — **сделано** (вариант `keep_timer_only` + `extract_then_delete`): `StepsSection` → `Views/RecipeStepsSection.swift` и `DisplayIngredient` → `Models/YDoc/DisplayIngredient.swift` извлечены, `RecipeDetailView.swift` (444 LOC, unreachable в runtime) + snapshot-тесты удалены, `Models/Recipe.swift`/`Ingredient.swift`/`ApiCacheEntry.swift` удалены, `RecipeScalerNativeApp.swift` Schema → `[RecipeTimer.self]`, `TestSupport`/`SnapshotTests`/`RecipeListViewModel`/`ContentView #Preview` обновлены, `docs/ARCHITECTURE.md`/`SETUP.md`/`PROJECT_STATUS.md`/`specs/001/` обновлены (historical notes). Build green (3 scheme), tests green.

#### 27. **[Architecture]** Нет composition root с DI; 14 синглтонов тянутся друг в друга
- **Area**: `RecipeScalerNative/RecipeScalerNativeApp.swift`, `ContentView.swift:21-54`; синглтоны в `AuthService`, `TimerManager`, `APIClient`, `TimerSyncService`, `RecipeImageService`, `PushRegistrationService`, `PushScheduleService`, `ImageCacheService`, `PublicImageCacheService`, `TimerLiveActivityCoordinator`, `YjsMergeHelper`, `AssistantModels`, `DeepLinkRouter`
- **Description**: `ContentView.init` — фактический composition root, вручную связывает 4 из ~14 сервисов; остальные через `.shared`. Cross-service wiring спрятан внутри методов: `YjsSyncService.start` (858) конфигурит `TimerSyncService.shared`, затем (863) назначает `TimerSyncService.shared.sendTimerEvent = { ... self? ... }` — циклический callback. 79 call sites ссылаются на «большую четвёрку» синглтонов.
- **Impact**: Нетестируемость, скрытая связность, lifecycle-баги, mock'и невозможны.
- **Recommendation**: Ввести `AppContainer` (`@MainActor`, в `App.init`), конструирующий все сервисы с явными зависимостями. Инжектить через `@Environment`/`@EnvironmentObject`.

#### 28. **[Architecture]** Смешаны `ObservableObject` и `@Observable` в слое сервисов/view-моделей
- **Area**: `YjsSyncService` (ObservableObject, 22 `@Published`), `RecipeListViewModel`, `SpotlightIndexer` vs `AuthService`, `RecipeEditViewModel`, `RecipeListSearchStore`, `TimerManager`, `DeepLinkRouter` (`@Observable`)
- **Description**: Кодбейз в середине миграции. Самый большой state-holder (`YjsSyncService`) — на старом фреймворке, форсит `@StateObject`/`@EnvironmentObject`. `ContentView` смешивает оба на одном view.
- **Impact**: Per-property observation `@Observable` потеряна на самом высокочернонном сервисе; SwiftUI ре-рендерит целые поддеревья на любой `@Published`-запись.
- **Recommendation**: Доделать миграцию: `YjsSyncService` → `@Observable`, затем `RecipeListViewModel`, `SpotlightIndexer`, `RemindersSyncService`.

#### 29. ~~**[Standards]** `NativeExportImportService` содержит захардкоженные английские ошибки/предупреждения~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerNative/Services/NativeExportImportService.swift:266,281`~~
- ~~**Description**: Строки «Folder with empty name skipped.», «Failed to import folder "\(...)": ...» аппендятся в `errors`/`warnings`, которые `DataManagementView` рендерит как есть через `Text(error)`/`Text(warning)`.~~ `importFolders` теперь использует `NativeImportMessageLocalizer.folderEmptySkipped()` и `NativeImportMessageLocalizer.folderFailed(name:error:)`; localizer расширен двумя методами, идёт через `Bundle.currentLocalizedString` + явный `AppLanguagePreference.current.locale` — единый паттерн с уже существующими `recipeFailed`/`imageFailed`.
- ~~**Impact**: Панель результата импорта показывает непереведённый английский…~~ Закрыто.
- ~~**Recommendation**: Роутить через `NativeImportMessageLocalizer`…~~ Выполнено. Ключи в `Localizable.xcstrings`: `account.data.import.folder-empty-skipped` (en: "Folder with empty name skipped.", ru: "Пропущена папка с пустым именем."), `account.data.import.folder-failed %@ %@` (en: "Failed to import folder \"%1$@\": %2$@", ru: "Не удалось импортировать папку «%1$@»: %2$@"). Удалены устаревшие `recipe.import.folder-empty-skipped` и `recipe.import.folder-failed-prefix`. Тесты в `NativeImportMessageLocalizerTests` (5 новых кейсов).

#### 30. ~~**[Standards]** Paprika/Crouton-парсеры вшивают английские лейблы в контент импортируемого рецепта~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerCore/Import/ThirdParty/PaprikaRecipeParser.swift:122,125` («Prep:», «Cook:»); `CroutonRecipeParser.swift:124,126` («min»)~~
- ~~**Description**: Парсеры синтезируют параграфы с английскими словами из числовых метаданных и встраивают их в описание рецепта (`DescriptionBlock.paragraph`). Этот текст становится **данными** пользователя, не UI-строкой.~~ Решение: Y.Doc-схема **не меняется** (см. `specs/027-paprika-crouton-import/contracts/third-party-recipe-formats.md` строки 33–34, 149–150 и `docs/I18N.md` секция «Импорт сторонних форматов — синтезированные лейблы»). Core-парсеры возвращают **структурные сигналы** через расширенный `DescriptionBlock` (новые case'ы `.prepTime(String)`, `.cookTime(String)`, `.durationMinutes(Int)`, `.difficulty(String)`); Native-слой локализует их в `.paragraph` в момент applying к Y.Doc через новый `DescriptionBlockLocalizer` (точка вызова — `DocumentManager.applyImportedRecipe`).
- ~~**Impact**: Импортированные рецепты навсегда содержат английские фрагменты…~~ Закрыто: новые импорты получают лейблы по runtime-локали. Уже сохранённые рецепты (с захардкоженным «Prep:») **не мигрируются автоматически** — это допустимо, т.к. контент — данные пользователя, перезапись была бы более инвазивной.
- ~~**Recommendation**: Либо опускать синтезированные лейблы…~~ Выбран второй вариант (локализованный префикс при импорте). Ключи в `Localizable.xcstrings`: `recipe.import.metadata.prep-time %@`, `recipe.import.metadata.cook-time %@`, `recipe.import.metadata.duration-minutes %d` (en/ru). `difficulty` — pass-through (free-form значение из исходного файла, не подлежит детерминированной локализации). Тесты: `DescriptionBlockLocalizerTests` (14 кейсов) + обновлённые `PaprikaRecipeParserTests` и `CroutonRecipeParserTests` (теперь проверяют структурные case'ы).

#### 31. ~~**[Standards]** Логирование через `print()` вместо фасада `AppLog`~~ ✅ Исправлено (2026-06-18)
- **Area**: `RecipeScalerNative/RecipeScalerNativeApp.swift:24` (провал APNs); `RecipeScalerNative/Views/RecipeDetailView.swift:227`
- **Description**: ~~Используется сырой `print(...)` вместо `AppLog.error/info(...)`.~~ Оба сайта заменены на `AppLog.error(...)` с dot-key event name + `data: [...]`.
- **Impact**: ~~Эти провалы обходят NDJSON debug-session log и `/debug` agent-trace pipeline; невидимы для `pull-app-logs.sh`.~~ Провалы теперь идут через фасад → видны в NDJSON-журнале и `pull-app-logs.sh`.
- **Recommendation**: ~~`AppLog.error(.push, "apns_register_failed", data: [...])` и `AppLog.error(.image, "image_cache_save_failed", data: [...])`.~~ Выполнено: `AppLog.error(.push, "apns_register_failed", data: ["error": ...])` и `AppLog.error(.app, "image_cache_save_failed", data: ["error": ...])`. Категория `.app` вместо рекомендованной `.image` — такой категории в `AppLog.Category` нет, прецедент `RecipeImageDiskCache.swift:81`. Коммит `05d0a40`; `xcodebuild build` → `BUILD SUCCEEDED`, `AppLogTests` 7/7 passed, `rg 'print(' RecipeScalerNative RecipeScalerCore` → 0 совпадений в продакшн-коде.

---

### Medium

#### 32. ~~**[Security]** Недоверенные архивы парсятся без ограничения размера ввода~~ ✅ Исправлено (2026-06-18, spec `032-import-decompression-bomb`)
- ~~**Area**: `PaprikaRecipeParser.swift:37`, `CroutonRecipeParser.swift:16` (`JSONSerialization.jsonObject`); `NativeRecipeImporter.swift:72,117`; `ThirdPartyFormatDetector.isCroutonJSON:169`~~
- ~~**Description**: JSON из attacker-контролируемых файлов декодируется без byte-size/depth-гарда…~~ Добавлен pre-flight cap `ThirdPartyImportLimits.maxRecipeJSONBytes` (16 MB) во всех 4 местах.
- ~~**Impact**: Патологический JSON (большой/глубокий) потребляет много CPU/памяти — локальный DoS.~~ Закрыто.
- **Recommendation**: Валидировать `Data.count` против разумного ceiling'а перед парсингом; предпочитать `JSONDecoder` для attacker-input.

#### 33. **[Security]** Расширения аутентифицируются только plaintext, не-секретным `userId`
- **Area**: `RecipeScalerNative/RecipeScalerNative.entitlements:5-8` (App Group, без keychain access group); `RecipeScalerCore/Auth/SharedAuthStore.swift`; `RecipeScalerNative/ContentView.swift:44-46`
- **Description**: Не объявлен keychain access group → Share/Action/Widget extensions не могут читать сид-фразу и полагаются только на `SharedAuthStore.userId` (App Group UserDefaults) для `x-user-id`.
- **Recommendation**: Расшарить short-lived токен через keychain access group; не давать extensions аутентифицироваться userId alone.

#### 34. **[Security]** Недоверенное CRDT-состояние публичных рецептов применяется без валидации размера
- **Area**: `RecipeScalerNative/Services/DiscoverAPI.swift:215-248` (`fetchPublicRecipeState`); `YrsDocument.swift:97-102,115-130`; `SyncEventHandler.swift:83-107`
- **Description**: Бинарное Yjs-состояние из public/чужих рецептов (и из realtime-сокета) применяется в локальный Y.Doc без верхнего предела размера. FFI кастует длину в `UInt32`.
- **Recommendation**: Ограничить принимаемый `yjsState`/`yjsUpdate` по размеру перед apply; отвергать oversized-пейлоады.

#### 35. **[Business Logic]** Фото Paprika/Crouton >25 МБ молча дропаются без фидбека
- **Area**: `PaprikaRecipeParser.swift:150-158`, `CroutonRecipeParser.swift:163-172`, `ThirdPartyRecipeImportService.swift:60-73`
- **Description**: `decodePhotoData`/`decodeFirstImage` возвращают `nil` при `data.count > maxImageBytes`. Сервис трогает `photosFailed`/`photosSkippedOffline` только при `draft.imageData != nil`, т.ч. oversized-фото не даёт ни счётчика, ни предупреждения (в отличие от native-пути с `.tooLarge`).
- **Recommendation**: Возвращать «oversized»-исход из парсеров (флаг на draft), чтобы сервис инкрементировал dedicated-счётчик/предупреждение.

#### 36. **[Business Logic]** Nutrition `totalWeight` теряется при нативном экспорте
- **Area**: `NativeRecipeExporter.swift:85-94`; `NativeFormatTypes.swift`
- **Description**: `readNutrition` заполняет `extra["totalWeight"]` из Y.Doc, но `ExportNutrition` несёт только calories/protein/fat/carbs/...; экспортёр не мапит `extra`. `NativeNutrition` объявляет `totalWeight`, но `applyNativeRecipe` его не пишет.
- **Recommendation**: Добавить `totalWeight` в `ExportNutrition` и round-trip'ить через `applyNativeRecipe`.

#### 37. **[Business Logic]** `recipeBatchLoadInFlight` может остаться `true` навсегда
- **Area**: `YjsSyncService.swift:1873-1879` и `:1908-1913`
- **Description**: Сбрасывается только когда `recipeBatchLoadCompleted >= recipeBatchLoadTotal`. Если сервер вернёт подмножество запрошенных ids — `completed` никогда не достигнет `total`, `isDownloading` зависнет `true`.
- **Recommendation**: Сбрасывать по таймауту или сверять `total` с реально возвращёнными ids.

#### 38. ~~**[Performance]** N индивидуальных SQLite-запросов для missing/cached снапшотов~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `YjsSyncService.swift:1916-1926`, `2046-2073`~~
- ~~**Description**: Оба метода циклят коллекцию и вызывают `store.loadSnapshot(docKey:)`…~~ Batch `loadSnapshots` / `existingSnapshotKeys`.
- ~~**Recommendation**: Один `SELECT docKey FROM ydoc_snapshots WHERE docKey IN (...)`…~~

#### 39. ~~**[Performance]** Проверка миграции дискового кеша на каждом lookup пути изображения~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerNative/Services/RecipeImageDiskCache.swift:14-18` (`fileURL` → `migrateFromCachesIfNeeded`)~~
- ~~**Description**: `fileURL(...)` безусловно вызывает `migrateFromCachesIfNeeded()`…~~ Migration once at app launch (`AppShellView`).
- ~~**Recommendation**: Запускать миграцию раз при запуске…~~

#### 40. ~~**[Performance]** Статус кеша изображений делает 2 `fileExists`-stat'а на рецепт, часто~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeImageService.swift:44-89` (`cacheStatus`), через `refreshImageCacheStatus`~~
- ~~**Description**: `cacheStatus(for:)` вызывает `isVariantCached` дважды…~~ Memoized `cacheStatus` fingerprint.
- ~~**Recommendation**: Держать in-memory cached/known set…~~

#### 41. ~~**[Performance]** MainActor-таймер 0.5 c гоняет рефреш панели + Live Activity~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerNative/Services/TimerManager.swift:29,320-352`~~
- ~~**Description**: `timerUpdateInterval = 0.5s`; `updateRunningTimers` мутирует `remainingTime`…~~ Panel refresh only on displayed-second change.
- ~~**Recommendation**: Гнать видимый отсчёт через display-link/seconds-гранулярность…~~

#### 42. ~~**[Performance]** Поиск на каждое нажатие грузит до 100 полных doc-ов~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeListSearchStore.swift:97-115`; `peekRecipeData` `YjsSyncService.swift:1027-1031`~~
- ~~**Description**: На каждый query фоновый `Task` вызывает `peekRecipeData` для до 100 name-miss-кандидатов…~~ `readSearchIndex` / `peekSearchIndex`.
- ~~**Recommendation**: Индексировать лёгкий нормализованный text-blob…~~

#### 43. ~~**[Performance]** Избыточные полные кодировки документа на каждую мутацию~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `DocumentManager.swift:107-126,428-438,1189-1207`~~
- ~~**Description**: Одна локальная мутация триггерит: write-txn → `persistSnapshot`…~~ `persistAndDeliver` — single encode.
- ~~**Recommendation**: Кодировать раз и переиспользовать байты…~~

#### 44. **[Architecture]** App Group identifier захардкожен в двух местах
- **Area**: `RecipeScalerCore/AppGroup.swift:28`; `RecipeScalerCore/Auth/SharedAuthStore.swift:14`
- **Description**: Один литерал `"group.ru.recipescaler.RecipeScalerNative"` в обоих файлах. Комментарий в `AppGroup.swift:8-11` говорит, что миграция ожидается — но не сделана.
- **Recommendation**: Заменить `SharedAuthStore.appGroupID` на `AppGroup.id`.

#### 45. **[Architecture]** Per-recipe sync-флаги в `UserDefaults.standard` вместо существующего SQLite
- **Area**: `YjsSyncService.swift:86-127`
- **Description**: `unsyncedRecipeIds`/`lastServerDocBytes` держатся в `UserDefaults.standard` per-recipe. Существующий `YDocStore` управляет per-doc SQLite-строками, куда это ляжет лучше.
- **Impact**: 500 рецептов → 500+ ключей в plist (медленно на каждом запуске); `UserDefaults.didChangeNotification` fire'ит на каждую запись.
- **Recommendation**: Добавить `unsynced: Bool`/`lastServerBytes: Int` колонки в `ydoc_snapshots` (миграция v5).

#### 46. **[Architecture]** Классификация sync-ошибок — по строковым паттернам серверных сообщений
- **Area**: `YjsSyncService.swift:2285-2327` (`handleSyncError`), `2399-2410` (`localizedSyncError`)
- **Description**: Бранчит на `message.contains("Ownership validation failed")`, `"Recipe is deleted"`, `"Empty"`, `"Invalid update"`. Веб-клиент держит свою копию паттернов.
- **Impact**: Смена формулировки на сервере (перевод, рефактор) тихо реклассифицирует ошибки.
- **Recommendation**: Добавить `code: string` в `sync_error`-пейлоад, парсить в enum `SyncError`, роутить по enum.

#### 47. **[Architecture]** Dead-code от abandoned-рефакторинга «local update bridge»
- **Area**: `DocumentManager.swift:1220-1223` (no-op `installLocalUpdateBridge`), `YrsDocument.swift:76-78` (`setOnLocalUpdateHandler` отбрасывает аргумент)
- **Recommendation**: Удалить методы и call sites.

#### 48. **[Architecture]** Реестр description-editor-сессий и continuation-map рискуют unbounded-ростом
- **Area**: `YjsSyncService.swift:77,80,81`
- **Description**: Три словаря долгоживущих ресурсов по `recipeId`. `documentLoadContinuations` resumed в `completePendingDocumentLoad`, но safety-net — только 10-сек таймаут; при удалении рецепта/тирдауне сокета mid-load continuation может остаться висеть или resumed дважды.
- **Recommendation**: Привязать lifetime сессии к owner'у, отменяющему tasks в `deinit`; заменить continuations на один in-flight `Task` на рецепт.

#### 49. **[Architecture]** Sprawl reconnect/watchdog-таймеров — 5 перекрывающихся state-машин
- **Area**: `YjsSyncService.swift:64-69` (5 `Task`-полей) + ещё в DocumentManager
- **Description**: Восемь разных timer `Task`-полей координируют socket/engine/auth/collection/network-recovery. Корректность зависит от отмены каждого таймера в каждой ветке. Повторяющийся `socketSessionId`-UUID-гард — code smell.
- **Recommendation**: Смоделировать соединение как `ConnectionStateMachine` enum с одним таймером на переход.

#### 50. **[Architecture]** Неконсистентное размещение HTTP API-сервисов
- **Area**: `RecipeScalerCore/Networking/APIClient.swift`+`RecipeImportAPI.swift` (Core) vs `RecipeScalerNative/Services/{AccountAPI,AssistantAPI,DiscoverAPI,RecipeImageUploadAPI,RecipeLLMParseAPI,SharingAPI,TelegramAPI}.swift` (Native)
- **Description**: Нет правила, какой API-клиент где живёт. `RecipeImageUploadAPI`/`RecipeLLMParseAPI` в Native без UI-coupling.
- **Recommendation**: Установить правило (напр. все `APIClient`-endpoint helpers в Core/Networking/Endpoints).

#### 51. **[Architecture]** Concurrency-safety сырых FFI-указателей через actor-closures не верифицирована
- **Area**: `YrsDocument.withReadTransaction`/`withWriteTransaction` (167-181); closures в `DocumentManager.mutateRecipe`
- **Description**: `Yrs*`-обёртки не `Sendable`, держат сырые C-указатели; аргумент безопасности — «DocumentManager actor сериализует все FFI». Но closures захватывают произвольное состояние. Swift exclusivity-checker не видит внутрь C FFI.
- **Recommendation**: Сделать `YrsDocument` единственным держателем `UnsafeMutablePointer<YDoc>`; экспонировать высокоуровневые операции вместо transaction-closures.

#### 52. **[Standards]** Хрупкая string-prefix-связка решает локализацию в AssistantComposer
- **Area**: `RecipeScalerNative/Views/AssistantComposer.swift:401` (`message.hasPrefix("assistant.")`)
- **Description**: View инспектирует, начинается ли serverError с «assistant.», чтобы решить, локализовать ли как ключ. Дублирует и хардкодит API-конвенцию именования ключей внутри view.
- **Recommendation**: Заставить serverError нести типизированный индикатор (enum/dedicated `localizedKey`) вместо prefix-сниффинга.

#### 53. ~~**[Standards]** `YrsError.errorDescription` возвращает захардкоженный английский~~ ✅ Исправлено (2026-06-18, вместе с #11)
- ~~**Area**: `RecipeScalerNative/Services/Yrs/YrsError.swift:12-25`~~
- ~~**Description**: «Yrs null pointer: ...», «Yrs apply failed: ...»…~~ Локализация через `Bundle.currentLocalizedString`; view-layer через `UserFacingAPIError.message(for:)`.
- ~~**Recommendation**: Локализовать через ключи…~~

#### 54. **[Standards]** Silent catch без логирования на провал кеша изображений
- **Area**: `RecipeScalerNative/Views/RecipeDetailView.swift:224-232`
- **Description**: Внешний `catch { // Ignore full image cache errors }` проглатывает без лога; внутренний использует `print` (№31).
- **Recommendation**: Логировать оба через `AppLog.info(.image, ...)`.

#### 55. **[Standards]** Захардкоженный лейбл кнопки «OK» вне namespace проекта
- **Area**: `RecipeScalerNative/Views/AssistantSheet.swift:119`
- **Description**: Все прочие ~10 OK-кнопок используют ключ `common.ok`; эта — голый литерал «OK». Дублирует ключ в xcstrings.
- **Recommendation**: `Button("common.ok", role: .cancel)`; удалить избыточный standalone-ключ «OK».

---

### Low

#### 56. **[Security]** `NSAllowsLocalNetworking = true` в release ATS-конфиге
- **Area**: `RecipeScalerNative/Info.plist:90-94`
- **Recommendation**: Скоупить exception в DEBUG либо ограничить через `NSExceptionDomains`.

#### 57. **[Security]** Integer truncation в аргументе длины yrs FFI
- **Area**: `RecipeScalerNative/Services/Yrs/YrsDocument.swift:54,122`
- **Recommendation**: Гардить `buffer.count <= UInt32.max`.

#### 58. **[Security]** `userId` (креденшал) пишется в логи
- **Area**: `YjsSyncService.swift:886,1291`; `Database.swift:21`; DEBUG-трейсы в `ContentView.init`
- **Recommendation**: Редактировать userId в логах (или фиксить №1, чтобы userId не был креденшалом).

#### 59. **[Security / Standards]** `try!` на regex-литералах при static-init
- **Area**: `PaprikaRecipeParser.swift:9`, `ThirdPartyIngredientAmountSplitter.swift:9`, `PaprikaIngredientSplitter.swift:9`
- **Recommendation**: Лениво-инициализируемый shared-инстанс с safe-fallback.

#### 60. **[Business Logic]** `normalizeColor` — баг приоритета операторов + дубль нормализации
- **Area**: `DocumentManager.swift:1214-1218`
- **Description**: `guard trimmed.hasPrefix("#"), trimmed.count == 7 || trimmed.count == 4` парсится как `(hasPrefix && count==7) || count==4` → любая 4-символьная строка без `#` uppercased. Дублирует `RecipeAccentColor.normalizedStored`.
- **Recommendation**: Скобки явно, либо роутить через `RecipeAccentColor.normalizedStored`.

#### 61. **[Business Logic]** `NativeFormatValidator` допускает servings=0 несмотря на «positive»-интенцию
- **Area**: `NativeFormatValidator.swift:57-60`
- **Recommendation**: `servings < 1`.

#### 62. **[Business Logic]** Дивергентная нормализация единиц Paprika vs Crouton
- **Area**: `ThirdPartyIngredientAmountSplitter.swift:9-12` vs `CroutonRecipeParser.swift:95-111`
- **Recommendation**: Единая таблица нормализации единиц для обоих путей.

#### 63. ~~**[Business Logic]** Дивергентные константы `maxImageBytes` между путями импорта~~ ✅ Исправлено (2026-06-18, spec `032-import-decompression-bomb`)
- ~~**Area**: `ThirdPartyImportTypes.swift:113` (26 214 400) vs `ImportPhotoValidator.swift:16/32` (25 000 000)~~
- ~~**Recommendation**: Одна shared-константа.~~ `ThirdPartyImportLimits.maxImageBytes = 25_000_000`, все сайты ссылаются на неё.

#### 64. **[Business Logic]** `NativeFormatDetector.detect()` классифицирует не-object JSON как v1.0
- **Area**: `NativeFormatDetector.swift:17-28`
- **Recommendation**: При не-object JSON кидать `invalidJSON`.

#### 65. ~~**[Performance]** Список без pagination/virtualization-гарда~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeListView.swift:106-124,362-436`~~
- ~~**Description**: `RecipeRow` не `Equatable`; `pinnedRowItems`/`unpinnedRowItems` — computed-свойства…~~ Equatable rows + memoized pin split.
- ~~**Recommendation**: Мемоизировать split-массивы…~~

#### 66. ~~**[Performance]** `mergeYjsUpdates` (native fallback) аллоцирует ydoc + коммит на апдейт~~ ✅ Исправлено (2026-06-18)
- ~~**Area**: `RecipeScalerNative/Services/Yrs/YrsDocument.swift:44-67`~~
- ~~**Recommendation**: Применять все updates в одной write-транзакции.~~ Single write-txn в `mergeYjsUpdates`.

#### 67. **[Architecture]** Пустая директория `RecipeScalerNative/Routing/`; роутер в `Utils/`
- **Area**: `RecipeScalerNative/Routing/` (0 entries); `Utils/DeepLinkRouter.swift`
- **Recommendation**: Перенести `DeepLinkRouter` в `Routing/` либо удалить пустую директорию.

#### 68. **[Architecture]** `fatalError` при провале init `ModelContainer`
- **Area**: `RecipeScalerNativeApp.swift:83`
- **Description**: Повреждённый SwiftData-store крашит приложение при запуске без recovery. `YrsDatabase` имеет in-memory-fallback.
- **Recommendation**: Ловить, удалять и пересоздавать store, либо in-memory-fallback.

#### 69. **[Standards]** Захардкоженный navigation title в DEBUG-only fixture-view
- **Area**: `RecipeScalerNative/Views/DescriptionFixturePreviewView.swift:30`
- **Recommendation**: Приемлемо оставить (DEBUG-only).

#### 70. **[Standards]** `try! YrsDatabase()` в `#Preview`
- **Area**: `RecipeScalerNative/Views/RecipeListView.swift:823`
- **Recommendation**: Оставить (preview-контекст).

---

## Чек-лист

- [x] SQL-инъекции — нет (GRDB parameterized; см. Security-резюме)
- [x] Захардкоженные секреты/API-ключи — не найдены
- [x] XXE — нет (нет `XMLParser` недоверенного ввода)
- [x] Декомпрессионные бомбы изображений — обработаны (`RecipeImageUploadPreprocessor`)
- [x] Path traversal в ZIP — нет (строгий 3-component-split для изображений)
- [ ] **Уязвимости безопасности аутентификации** — Critical №1–3, High №12–13
- [ ] **Корректность бизнес-логики** — ~~High №14~~ ✅ (2026-06-18), High №15–16, Medium №35–37
- [x] **Узкие места производительности (большая часть)** — ✅ №4, 5, 7, 18–22, 38–43, 65, 66 (2026-06-18); остаются **#6** (WKWebView merge), **#17** (Socket.IO wire format)
- [ ] Код следует стандартам проекта — ~~Critical №11~~ ✅, ~~High №29–30~~ ✅ (2026-06-18), №31 ✅ (2026-06-18)
- [x] Маркеры `// TODO`/`FIXME`/`HACK` — не найдены
- [x] Пустые `catch {}` — не найдены в проде
- [ ] Комплексная обработка ошибок — ~~критично №11~~ ✅, №16, №46
- [x] Тесты новые (Paprika/Crouton/XmlFragmentWriter) — есть, хорошо названы
- [x] Документация — ~~`Package.swift` не соответствует реальности (№8)~~ ✅ Исправлено (2026-06-18)
- [ ] Архитектура — god-объекты (№9, №10), сломанные границы (№24, №25)
- [ ] Deployment-концерны — debug-UUID в репо (№2)

---

## Рекомендация

**Изменения требуются (Changes Requested).**

Функциональность проекта работает и дизайн offline-first CRDT-архитектуры продуман, но перед production-нагрузкой обязательно устранить:

1. **Безопасность (блокирующе)**: Critical №1–3 — модель аутентификации на публичном `userId` + закоммиченный prod-UUID — это прямой путь к full account takeover. Минимум как срочный quick-win: ротировать debug-UUID, перенести `userId` в Keychain, добавить TLS-pinning.
2. ~~**Производительность (блокирующе для целевых метрик)**: Critical №4–7 — O(N²)-импорт, decode архива в память, merge на main thread и export all-in-memory~~ ✅ Исправлено (2026-06-18), кроме **#6** (WKWebView merge) и **#17** (Socket.IO wire format).
3. **Стабильность данных**: High №16 — оборонительное удаление снапшота при ошибке remote-апдейта может потерять несинхронизированные локальные правки.
4. ~~**i18n**: ~~Critical №11~~ ✅ + High №29–31 — захардкоженный английский в ошибках импорта/контенте.~~ ✅ Исправлено (2026-06-18): №11, №29, №30, №31 — все закрыты.

Архитектурные находки (god-объекты, ~~сломанный `Package.swift`~~ ✅, дубликаты Core/Native) — это технический долг, который не блокирует релиз, но должен попасть в roadmap: они блокируют тестируемость и ускоряют регрессии.

Позитив: новые import-фичи (парсеры, локализаторы ошибок, валидаторы) демонстрируют правильное применение i18n-паттернов и хорошее тестовое покрытие — их стоит взять за образец для приведения остального кода в норму.
