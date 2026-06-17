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
2. **Архитектурный технический долг集中ён** — два god-объекта (`YjsSyncService` 2411 строк, `DocumentManager` 1603 строки) + сломанный `Package.swift` блокируют тестируемость и масштабирование.
3. **Производительность импорта/синхронизации под угрозой заявленных целей** — O(N²)-вставки, декомпрессия архивов в память целиком, merge через WKWebView на главном потоке прямо угрожают целевым «≤2 мин на 50 рецептов» / «до 500 рецептов».
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

#### 3. **[Security / Performance]** Декомпрессионная бомба: gzip и ZIP без ограничений на распакованный размер
- **Area**: `RecipeScalerCore/Import/ThirdParty/Gunzip.swift:22-44`; `RecipeScalerCore/Import/ThirdParty/ThirdPartyFormatDetector.swift:139-150` (`enumerateZipEntries`); `RecipeScalerCore/Export/Native/NativeRecipeImporter.swift:106-110,157-160`
- **Description**: `Gunzip.decompress` циклит `inflate`, дописывая чанки в `output = Data()` **без ограничения итогового размера** и без проверки коэффициента сжатия. `enumerateZipEntries` извлекает каждый entry в неограниченный `Data()`, держит все entries в памяти одновременно, без ограничения `uncompressedSize`/`compressedSize`/количества entries. (`maxRecipesPerImport = 500` ограничивает только распарсенные рецепты, не байты.) Записи `.paprikarecipe` — gzip-сжатый JSON из пользовательских архивов.
- **Impact**: Многомегабайтный gzip-stream разрастается до многих ГБ → OOM/краш (локальный DoS) при импорте crafted-файла. Маленький crafted `.zip` может распаковаться до произвольного размера.
- **Recommendation**: Ввести жёсткий максимум распакованного размера (масштабированный под `ThirdPartyImportLimits`), прерывать поток при превышении, проверять `entry.uncompressedSize`/`compressedSize` до извлечения, считать running total и отвергать архив заранее; для больших entries предпочитать streaming-извлечение на диск.

#### 4. **[Performance / Business Logic]** O(N²)-вставка ингредиентов + двойная full-doc кодировка при импорте
- **Area**: `RecipeScalerNative/Services/YjsSync/DocumentManager.swift:318-326,1492-1499,1058-1090,1189-1207`
- **Description**: `applyImportedRecipe`/`applyNativeRecipe` вызывают `addIngredient` по одному ингредиенту. Каждый `addIngredient` запускает `renumberIngredientOrders`, который обходит **весь** массив ингредиентов (O(N) на добавление → O(N²) на рецепт). Каждый вызов проходит через `mutateRecipe`, который (a) открывает write-txn, (b) `persistSnapshot` → `encodeStateAsUpdate` (весь документ), (c) `deliverPendingLocalUpdate` → `consumePendingLocalUpdates` + **вторая** `encodeStateAsUpdate` + запись SQLite. Для рецепта с K ингредиентами: K×O(K) renumber + 2K full-document кодировок CRDT + K записей SQLite.
- **Impact**: Импорт не укладывается в целевые «≤2 мин на 50 рецептов»; CPU/GC доминируют; главный поток может stall'ить, т.к. import-service на `@MainActor`.
- **Recommendation**: Батчить весь массив ингредиентов в одну write-транзакцию (без per-item `renumber`), затем один `persistSnapshot` + один `deliverPendingLocalUpdate` на рецепт; в `deliverPendingLocalUpdate` переиспользовать уже закодированное состояние вместо двойной кодировки.

#### 5. **[Performance]** Весь архив декодируется в память до цикла импорта
- **Area**: `RecipeScalerCore/Import/ThirdParty/ThirdPartyFormatDetector.swift:117-159`; `RecipeScalerNative/Services/ThirdPartyRecipeImportService.swift:38-42`
- **Description**: `enumerateZipEntries` извлекает и буферизует **полную распакованную Data** каждого entry заранее (плюс позже декодируется и держится base64 `photo_data` каждого). Для 500-рецептного Paprika-архива это могут быть сотни МБ resident-памяти одновременно.
- **Impact**: OOM на устройствах с малым RAM; пиковая память масштабируется с размером архива, а не с одним рецептом; подрывает безопасность лимита в 500 рецептов.
- **Recommendation**: Стримить entries лениво — сначала enumerate путей, затем extract+parse+import по одному entry за раз (освобождать Data перед следующим), чтобы пик ≈ один рецепт + одно изображение.

#### 6. **[Performance]** Yjs merge/encode выполняется на главном потоке через WKWebView
- **Area**: `RecipeScalerNative/Services/YjsSync/YjsMergeHelper.swift:10-67`; вызовы `UpdateDebouncer.swift:54-69`, `YjsSyncService.swift:286,1535,1721,1738`
- **Description**: `YjsMergeHelper` — `@MainActor`, выполняет `Y.mergeUpdates`/`Y.encodeStateAsUpdate` через `evaluateJavaScript` в скрытом WKWebView. Конвертирует каждую `Data` в `[NSNumber]` (boxing байта) → JSON-сериализация → eval JS → парсинг `[NSNumber]` обратно. Вызывается из debouncer-flush, reconnect-drain, wire-snapshot-rebuild и offline-push-resolution — часто и потенциально подряд.
- **Impact**: Каждый merge блокирует главный поток (JS синхронный для `evaluateJavaScript`); большие апдейты дают видимый jank/freeze при reconnect-storms. Boxing в NSNumber удваивает память и аллоцирует тяжело.
- **Recommendation**: Реализовать merge нативно в yrs (Rust `merge_updates_v1`/`encode_state_as_update` уже доступны через FFI, обёрнутый в `YrsDocument`); полностью уйти с `@MainActor`. Если WebView остаётся — хотя бы убрать NSNumber-boxing в пользу base64.

#### 7. **[Performance]** Экспорт грузит все рецепты + все байты изображений в память на MainActor
- **Area**: `RecipeScalerNative/Services/NativeExportImportService.swift:34-94`
- **Description**: `exportAll` сначала обходит все рецепты через `readRecipeData` (каждый — полный Y.Doc read + XmlFragment→HTML), накапливая все `ExportRecipe` в памяти; затем вторым проходом грузит **и full, и preview** изображения `Data(contentsOf:)` для каждого рецепта в `imageData: [String:(full,preview)]` — всё до сериализации.
- **Impact**: Для сотен рецептов с изображениями пиковая память = сумма всех картинок на диске (легко >1 ГБ); работает на `@MainActor` → UI заморожен на всё время экспорта. Вероятный OOM на больших библиотеках.
- **Recommendation**: Стримить в экспортёр (записывать каждый рецепт/изображение в вывод по мере обработки,释放 после эмиссии); уйти с MainActor.

#### 8. **[Architecture]** `Package.swift` сломан: не объявляет `RecipeScalerCore` и `YrsC`
- **Area**: `Package.swift:33-58`; реальный сборка живёт в `RecipeScalerNative.xcodeproj`
- **Description**: SPM-манифест опускает таргет `RecipeScalerCore` и XCFramework `YrsC`. `swift build` из CLI не работает; только Xcode-проект (встраивает `RecipeScalerCore.framework` через `project.pbxproj:86,128,162,204`) может собрать приложение. Два графа сборки дрейфуют незаметно.
- **Impact**: CI-скрипты, agent-loops и внешний tooling, вызывающие `swift build`, получают ложный green или жёсткий fail; любой SwiftPM-native consumer не может зависеть от пакета. Блокирует миграцию на чистый SPM-workspace.
- **Recommendation**: Либо удалить `Package.swift` и задокументировать Xcode-only, либо сделать его каноническим: добавить таргет `RecipeScalerCore` (path `RecipeScalerCore`), `.binaryTarget(name: "YrsC", path: "Frameworks/YrsC.xcframework")`, объявить `YrsC`/`RecipeScalerCore` зависимостями `RecipeScalerNative`.

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

#### 12. **[Security]** Креденшал (`userId`) хранится plaintext в UserDefaults, не в Keychain
- **Area**: `RecipeScalerNative/Services/AuthService.swift:117-119,154-156`; `RecipeScalerCore/Auth/SharedAuthStore.swift:24-34`
- **Description**: `userId` (единственный креденшал по находке №1) персистится в `UserDefaults.standard` и зеркалируется в App Group `UserDefaults`. UserDefaults — plaintext plist на диске. Keychain (правильно используемый для сид-фразы) дал бы hardware-backed шифрованное хранилище.
- **Impact**: На скомпрометированном/резервном устройстве forensic-инструменты читают UserDefaults тривиально; получение userId = полный takeover.
- **Recommendation**: Хранить креденшал в Keychain (класс `.afterFirstUnlockThisDeviceOnly`); если extensions должны читать — добавить keychain access group в entitlements.

#### 13. **[Security]** Нет TLS certificate/SPKI-pinning'а
- **Area**: `RecipeScalerCore/Networking/APIClient.swift:145`; Socket.IO в `YjsSyncService.swift:1120`
- **Description**: Весь нетворкинг использует `URLSession.shared` и дефолтный `URLSession` Socket.IO. Никакой `URLSessionDelegate` не делает pinning.
- **Impact**: Атакующий с доверенным CA (enterprise MDM, jailbreak) может MITM'ить и читать `x-user-id`/тела. В связке с находкой №1 один перехваченный запрос = полный takeover.
- **Recommendation**: Пинить API/WS-эндпоинты (SPKI-pinning — устойчивый выбор) через кастомный `URLSessionDelegate`, fail closed при несовпадении.

#### 14. **[Business Logic]** Crouton `Int(amountValue)` крэшит на больших значениях
- **Area**: `RecipeScalerCore/Import/ThirdParty/CroutonRecipeParser.swift:113-115`
- **Description**: `parseQuantity` делает `Int(amountValue)`. При `quantity.amount` целочисленном Double вне диапазона `Int64` (напр. `1e19`) — это Swift-предусловие trap (overflow), не throw. Импорт — фича, обрабатывающая недоверенные `.crumb`/zip.
- **Impact**: Crafted (или патологически большой) Crouton-файл прерывает весь импорт жёстким крэшем; нет изоляции per-entry-ошибок.
- **Recommendation**: Гард через `Int(exactly: amountValue)` (вернёт `nil` при overflow) с fallback на `String(amountValue)`, либо clamp.

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

#### 18. **[Performance]** Полная конверсия XmlFragment→HTML на каждом чтении рецепта
- **Area**: `RecipeScalerNative/Services/YjsSync/DocumentManager.swift:189-211`; `RecipeScalerNative/Utils/XmlFragmentToHTML.swift:108-476`
- **Description**: `readRecipeData` всегда прогоняет `XmlFragmentToHTML.serializedFragment` + `html(fromSerializedXML:)`, который применяет ~15 `NSRegularExpression`-проходов (`replacingOccurrences` + match-циклы) по всей строке описания. Выполняется для `refreshCurrentRecipe`, `peekRecipeData` (поиск до 100 рецептов, Spotlight), экспорта, покупок.
- **Impact**: Поиск по 100 рецептам = 100 полных чтений + 100 HTML-конверсий на каждое нажатие; Spotlight-reindex столь же тяжёлый.
- **Recommendation**: Кешировать сконвертированный HTML/`RecipeDescriptionDocument` по состоянию документа (`updatedAt`); для поиска/индекса читать лёгкую plain-text-проекцию вместо полного HTML.

#### 19. **[Performance]** Spotlight-индексация полностью на `@MainActor` + синхронные дисковые чтения + NSAttributedString HTML
- **Area**: `RecipeScalerNative/Services/SpotlightIndexer.swift:18,103-156,233-265`
- **Description**: `SpotlightIndexer` — `@MainActor`. `indexOne` вызывает `peekRecipeData` (полный doc read + HTML-конверсия), `Data(contentsOf:)` (синхронный дисковый read) для thumbnail и `plainText(fromHTML:)` через `NSAttributedString(..., documentType: .html)` — одну из самых дорогих UIKit-операций — на главном потоке, на каждый dirty-рецепт. Уже есть план-документ `plans/007-move-spotlight-off-main-thread.md`.
- **Impact**: Reindex-всплески (коллекция, импорт) stall'ят главный поток; `NSAttributedString` HTML-init может занимать десятки ms на рецепт.
- **Recommendation**: Вынести тяжёлую per-recipe работу в background-`Task`; заменить `NSAttributedString` HTML на нативный `RecipeDescriptionParser` plain-text.

#### 20. **[Performance]** Image upload preprocessor до ~112 encode-проходов на `@MainActor`
- **Area**: `RecipeScalerNative/Utils/RecipeImageUploadPreprocessor.swift:34-60,134-165`; вызов `YjsSyncService.swift:620-621`
- **Description**: `payloadForUpload` работает на главном actor'е. В не-passthrough-режиме декодирует, затем `imageDataUnderLimit` циклит до 14 resize-итераций, каждая пробует 8 уровней качества WebP/JPEG `CGImageDestinationFinalize` — до ~112 полных encode-проходов синхронно на main.
- **Impact**: При multi-recipe импорте с изображениями каждая картинка замораживает UI на время поиска encode; большой battery/CPU.
- **Recommendation**: Вынести preprocess в `Task.detached`; сократить quality-ladder (один WebP q=0.8, один JPEG-fallback); полагаться на даунсэмплинг вместо brute-force.

#### 21. **[Performance]** Offline-очередь: full-table fetch на рецепт (N+1) и per-row DELETE
- **Area**: `YjsSyncService.swift:313-328` (`hasUnsyncedLocalChanges`), вызовы в циклах 375,1518-1521,1694-1696; per-entry deletes 1639-1645, 1682-1686
- **Description**: `hasUnsyncedLocalChanges` вызывает `offlineQueue.fetchAll()` (full scan) и `.contains(where:)` для одного рецепта, но вызывается **раз на рецепт** в `fetchAndMergeServerDocuments`, `refreshWireSnapshotsForRecipes`, `pushUnsyncedWireSnapshots`. `handleSyncConfirmed`/`drainOfflineQueue` удаляют entries по одному `deleteEntry(id:)` (отдельные транзакции).
- **Impact**: Reconnect/offline-drain с R рецептами и Q entries — O(R×Q) чтений + O(Q) транзакций; квадратичное масштабирование.
- **Recommendation**: Фетчить очередь один раз, построить `Set<String>` pending recipeIds, проверять membership; заменить per-row deletes на единый `DELETE ... WHERE recipeId = ?`.

#### 22. **[Performance]** Каскад `refreshCollectionEntries` не дебаунсится и перезапускается на каждую мутацию
- **Area**: `YjsSyncService.swift:2129-2154`; observer wiring 2213-2218
- **Description**: Collection deep observer вызывает `Task { await refreshCollectionEntries() }` напрямую (без debounce/coalescing). Каждый вызов: полный `readCollectionEntries`, `CollectionRecipesIndexBuilder.build`, `readFolders`, `scheduleImagePrefetch`, `refreshImageCacheStatus` (цикл по всем, 2 stat'а), `refreshRecipeDocumentCacheStatus` (цикл, 1 SQLite-запрос). При импорте коллекция меняется раз на рецепт → 50-рецептный импорт = ~50 полных каскадов.
- **Recommendation**: Дебаунсить/coalesce `refreshCollectionEntries` (cancel-in-flight + задержка, как `scheduleRecipeDocumentsBatchLoad`); считать cache-статусы из уже прочитанных entries без доп. SQLite/stat-проходов.

#### 23. **[Architecture]** Дубликаты валидаторов/локализаторов между `RecipeScalerCore` и `RecipeScalerNative`
- **Area**: `RecipeScalerCore/Import/ImportPhotoValidator.swift` vs `RecipeScalerNative/Utils/ImportPhotoValidator.swift`; аналогично `ImportErrorLocalizer`
- **Description**: Два `ImportPhotoValidator` с разными `ValidationError` (Core: `.tooMany(count:)`, `.tooLarge(name:size:)`; Native: `.tooMany`, `.tooLarge`). Два `ImportPhotoItem` (Core — `Equatable + Sendable` без id; Native — `Identifiable` UUID, не `Sendable`). Native-файл импортирует Core и дизэмбигуирует `RecipeScalerCore.ImportPhotoValidator.maxRecipes`.
- **Impact**: Type-juggling при пересечении границ модулей, дрейф лимитов/сообщений, два пути локализации, каждый фикс применяется дважды.
- **Recommendation**: Удалить Native-дубликаты; main app потребляет Core public-типы, плюрализацию через `Bundle.main`.

#### 24. **[Architecture]** YrsC FFI вызывается из файлов `Utils/`, ломая границу `Services/Yrs/`
- **Area**: `RecipeScalerNative/Utils/XmlFragmentToHTML.swift` (713 LOC), `Utils/DescriptionXmlFragmentWriter.swift`, `Utils/RecipeDescriptionXmlFragmentWriter.swift` (314 LOC), `Utils/RecipeReader.swift`
- **Description**: Дизайн-намерение (AGENTS.md) — «`Yrs/` C FFI wrappers». В реальности `XmlFragmentToHTML.serializedFragment` (строка 18), `DescriptionXmlFragmentWriter.apply`, `RecipeReader` вызывают `ytype_get`, `yxmlelem_insert_elem` и т.п. напрямую на сыром `OpaquePointer`-txn, переданном из `DocumentManager`. У обёрток `Yrs*` вообще нет `XmlFragment`-типа.
- **Impact**: Каждый FFI-фикс безопасности приходится выводить заново на каждом сайте вызова; рефакторинг FFI-поверхности невозможен без правок Utils.
- **Recommendation**: Добавить `YrsXmlFragment`, `YrsXmlElement`, `YrsXmlText` под `Services/Yrs/`; переместить эти Utils в `Services/Yrs/Description/`.

#### 25. **[Architecture]** `RecipeScalerCore/UI/` сцепляет «core»-фреймворк с UIKit/SwiftUI
- **Area**: `RecipeScalerCore/UI/ShareContentLoader.swift:10` (`import UIKit`), `ShareContentLoader.swift:11` (`import UniformTypeIdentifiers`), `ShareView.swift:11` (`import SwiftUI`)
- **Description**: AGENTS.md: «yrs writer in Core (no UIKit)». Но `UI/` внутри Core держит SwiftUI-views и UIKit-связанные loaders, не имеющие отношения к CRDT-writer'у или domain-логике; это extension-host glue. Нахождение их в Core заставляет каждого consumer'а Core линковать UIKit/SwiftUI.
- **Recommendation**: Перенести `ShareContentLoader`, `ShareContentClassifier`, `ShareView` в выделенный `ShareExtensionUI`-таргет (или в сами extension-таргеты); оставить в Core только чистую логику.

#### 26. **[Architecture]** Двойной source of truth: SwiftData `Recipe` сосуществует с Y.Doc-производным `RecipeData`
- **Area**: `RecipeScalerNative/Models/Recipe.swift` (`@Model`, зарегистрирован в `RecipeScalerNativeApp.swift:64-85`) vs `RecipeScalerNative/Models/YDoc/RecipeData.swift`
- **Description**: AGENTS.md/`docs/ARCHITECTURE.md` объявляют Y.Doc source of truth. Но SwiftData-схема `Recipe`/`Ingredient`/`RecipeTimer`/`ApiCacheEntry` зарегистрирована в `ModelContainer`, и только `TimerManager` читает её через `FetchDescriptor<Recipe>`. Ни одного `@Query` против `Recipe` в views нет. Рядом живут legacy `RecipeDetailView.swift` (444 LOC) и Y.Doc-backed `YDocRecipeDetailView.swift` (1168 LOC).
- **Impact**: Два параллельных представления рецепта, риск дрейфа, неясно новичку, что канонично. `Recipe` несёт legacy-поля (`scaleFactor`, `detailEtag`, `imagePreviewLocalPath`).
- **Recommendation**: Либо уйти от SwiftData `Recipe` полностью (таймеры читают из `peekRecipeData`), либо явно ограничить SwiftData до `RecipeTimer`/`ApiCacheEntry` и удалить `Recipe`/`Ingredient`-модели. Удалить legacy `RecipeDetailView.swift`.

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

#### 29. **[Standards]** `NativeExportImportService` содержит захардкоженные английские ошибки/предупреждения
- **Area**: `RecipeScalerNative/Services/NativeExportImportService.swift:266,281`
- **Description**: Строки «Folder with empty name skipped.», «Failed to import folder "\(...)": ...» аппендятся в `errors`/`warnings`, которые `DataManagementView` рендерит как есть через `Text(error)`/`Text(warning)`.
- **Impact**: Панель результата импорта показывает непереведённый английский; противоречит паттерну `ThirdPartyImportErrorLocalizer`/`NativeImportMessageLocalizer`.
- **Recommendation**: Роутить через `NativeImportMessageLocalizer` с ключами вида `account.data.import.folder-empty-skipped`.

#### 30. **[Standards]** Paprika/Crouton-парсеры вшивают английские лейблы в контент импортируемого рецепта
- **Area**: `RecipeScalerCore/Import/ThirdParty/PaprikaRecipeParser.swift:122,125` («Prep:», «Cook:»); `CroutonRecipeParser.swift:124,126` («min»)
- **Description**: Парсеры синтезируют параграфы с английскими словами из числовых метаданных и встраивают их в описание рецепта (`DescriptionBlock.paragraph`). Этот текст становится **данными** пользователя, не UI-строкой.
- **Impact**: Импортированные рецепты навсегда содержат английские фрагменты для ru-пользователей; не лечится переводом, т.к. это данные.
- **Recommendation**: Либо опускать синтезированные лейблы (хранить prep/cook структурно, рендерить локализованно), либо локализовать префикс по runtime-локали при импорте. Уточнить желаемое поведение в спеке.

#### 31. **[Standards]** Логирование через `print()` вместо фасада `AppLog`
- **Area**: `RecipeScalerNative/RecipeScalerNativeApp.swift:24` (провал APNs); `RecipeScalerNative/Views/RecipeDetailView.swift:227`
- **Description**: Используется сырой `print(...)` вместо `AppLog.error/info(...)`.
- **Impact**: Эти провалы обходят NDJSON debug-session log и `/debug` agent-trace pipeline; невидимы для `pull-app-logs.sh`.
- **Recommendation**: `AppLog.error(.push, "apns_register_failed", data: [...])` и `AppLog.error(.image, "image_cache_save_failed", data: [...])`.

---

### Medium

#### 32. **[Security]** Недоверенные архивы парсятся без ограничения размера ввода
- **Area**: `PaprikaRecipeParser.swift:37`, `CroutonRecipeParser.swift:16` (`JSONSerialization.jsonObject`); `NativeRecipeImporter.swift:72,117`; `ThirdPartyFormatDetector.isCroutonJSON:169`
- **Description**: JSON из attacker-контролируемых файлов декодируется без byte-size/depth-гарда. `JSONSerialization` не закалён против deep-nesting CPU-бомб.
- **Impact**: Патологический JSON (большой/глубокий) потребляет много CPU/памяти — локальный DoS.
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

#### 38. **[Performance]** N индивидуальных SQLite-запросов для missing/cached снапшотов
- **Area**: `YjsSyncService.swift:1916-1926`, `2046-2073`
- **Description**: Оба метода циклят коллекцию и вызывают `store.loadSnapshot(docKey:)` раз на рецепт — один DB round-trip на рецепт, без батчинга. `refreshRecipeDocumentCacheStatus` гоняется на каждом refresh коллекции.
- **Recommendation**: Один `SELECT docKey FROM ydoc_snapshots WHERE docKey IN (...)` или фетчить все ключи раз в `Set`; кешировать множество до инвалидации.

#### 39. **[Performance]** Проверка миграции дискового кеша на каждом lookup пути изображения
- **Area**: `RecipeScalerNative/Services/RecipeImageDiskCache.swift:14-18` (`fileURL` → `migrateFromCachesIfNeeded`)
- **Description**: `fileURL(...)` (самая вызываемая функция) безусловно вызывает `migrateFromCachesIfNeeded()`, который читает `UserDefaults.standard.bool` на каждом вызове и до установки флага перечисляет legacy-директорию.
- **Recommendation**: Запускать миграцию раз при запуске; `fileURL` должна быть чистой арифметикой.

#### 40. **[Performance]** Статус кеша изображений делает 2 `fileExists`-stat'а на рецепт, часто
- **Area**: `RecipeImageService.swift:44-89` (`cacheStatus`), через `refreshImageCacheStatus`
- **Description**: `cacheStatus(for:)` вызывает `isVariantCached` дважды (preview + full), каждый `FileManager.fileExists` + UserDefaults read. Весь массив ре-сканируется на каждое `recipeImageDidCache`/status-уведомление (дебаунс 300ms) и каждый refresh коллекции.
- **Recommendation**: Держать in-memory cached/known set, обновляемый на write/delete; статить только когда set dirty. Агрессивнее дебаунсить при активном prefetch.

#### 41. **[Performance]** MainActor-таймер 0.5 c гоняет рефреш панели + Live Activity
- **Area**: `RecipeScalerNative/Services/TimerManager.swift:29,320-352`
- **Description**: `timerUpdateInterval = 0.5s`; `updateRunningTimers` мутирует `remainingTime` на каждом бегущем таймере каждые 0.5 c и зовёт `refreshPanelTimers()` (`persistTimerSnapshot` → App Group write + `WidgetCenter.reloadTimelines`, дебаунс 0.2 c) и `syncLiveActivityProgress` (троттл 3 c). Мутация `remainingTime` на `@Observable` инвалидирует SwiftUI-диффинг 2 Гц для всей панели таймеров.
- **Recommendation**: Гнать видимый отсчёт через display-link/seconds-гранулярность только для on-screen rows; не мутировать published `remainingTime` на 2 Гц для невидимых таймеров.

#### 42. **[Performance]** Поиск на каждое нажатие грузит до 100 полных doc-ов
- **Area**: `RecipeListSearchStore.swift:97-115`; `peekRecipeData` `YjsSyncService.swift:1027-1031`
- **Description**: На каждый query фоновый `Task` вызывает `peekRecipeData` для до 100 name-miss-кандидатов; каждый — `getOrCreateDoc` + полный `readRecipeData` incl. XmlFragment→HTML (см. №18). Первичный проход по свежему термину над большой библиотекой тяжёлый.
- **Recommendation**: Индексировать лёгкий нормализованный text-blob (name + ингредиенты + plain-описание) раз на изменение рецепта и искать по нему; лимитировать/рейт-лимитить candidate-loading.

#### 43. **[Performance]** Избыточные полные кодировки документа на каждую мутацию
- **Area**: `DocumentManager.swift:107-126,428-438,1189-1207`
- **Description**: Одна локальная мутация триггерит: write-txn → `persistSnapshot` (`encodeStateAsUpdate`), затем `deliverPendingLocalUpdate` → `consumePendingLocalUpdates` + **вторая** `encodeStateAsUpdate`. Remote `applyUpdate` тоже ре-кодирует+saves на каждый входящий delta.
- **Recommendation**: Кодировать раз и переиспользовать байты для персистентности и outbound-доставки; пропускать re-persist на pure remote-apply, когда снапшот уже актуален.

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

#### 53. **[Standards]** `YrsError.errorDescription` возвращает захардкоженный английский
- **Area**: `RecipeScalerNative/Services/Yrs/YrsError.swift:12-25`
- **Description**: «Yrs null pointer: ...», «Yrs apply failed: ...». `YDocRecipeDetailView` назначает `error.localizedDescription` в `editErrorMessage`.
- **Recommendation**: Локализовать через ключи либо держать внутренним (не выводить в UI, гейтить generic-сообщением).

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

#### 63. **[Business Logic]** Дивергентные константы `maxImageBytes` между путями импорта
- **Area**: `ThirdPartyImportTypes.swift:113` (26 214 400) vs `ImportPhotoValidator.swift:16/32` (25 000 000)
- **Recommendation**: Одна shared-константа.

#### 64. **[Business Logic]** `NativeFormatDetector.detect()` классифицирует не-object JSON как v1.0
- **Area**: `NativeFormatDetector.swift:17-28`
- **Recommendation**: При не-object JSON кидать `invalidJSON`.

#### 65. **[Performance]** Список без pagination/virtualization-гарда
- **Area**: `RecipeListView.swift:106-124,362-436`
- **Description**: `RecipeRow` не `Equatable`; `pinnedRowItems`/`unpinnedRowItems` — computed-свойства, ребилдятся на каждом рендере.
- **Recommendation**: Мемоизировать split-массивы; `RecipeRow` сделать `Equatable`/`EquatableView`.

#### 66. **[Performance]** `mergeYjsUpdates` (native fallback) аллоцирует ydoc + коммит на апдейт
- **Area**: `RecipeScalerNative/Services/Yrs/YrsDocument.swift:44-67`
- **Recommendation**: Применять все updates в одной write-транзакции.

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
- [ ] **Корректность бизнес-логики** — High №14–16, Medium №35–37
- [ ] **Узкие места производительности** — Critical №4–7, High №17–22
- [ ] Код следует стандартам проекта — нарушений i18n много (Critical №11, High №29–31)
- [x] Маркеры `// TODO`/`FIXME`/`HACK` — не найдены
- [x] Пустые `catch {}` — не найдены в проде
- [ ] Комплексная обработка ошибок — нет (критично №11, №16, №46)
- [x] Тесты новые (Paprika/Crouton/XmlFragmentWriter) — есть, хорошо названы
- [ ] Документация — `Package.swift` не соответствует реальности (№8)
- [ ] Архитектура — god-объекты (№9, №10), сломанные границы (№24, №25)
- [ ] Deployment-концерны — debug-UUID в репо (№2)

---

## Рекомендация

**Изменения требуются (Changes Requested).**

Функциональность проекта работает и дизайн offline-first CRDT-архитектуры продуман, но перед production-нагрузкой обязательно устранить:

1. **Безопасность (блокирующе)**: Critical №1–3 — модель аутентификации на публичном `userId` + закоммиченный prod-UUID — это прямой путь к full account takeover. Минимум как срочный quick-win: ротировать debug-UUID, перенести `userId` в Keychain, добавить TLS-pinning.
2. **Производительность (блокирующе для целевых метрик)**: Critical №4–7 — O(N²)-импорт, decode архива в память, merge на main thread и export all-in-memory прямо угрожают заявленным «≤2 мин / 50 рецептов» и «до 500 рецептов».
3. **Стабильность данных**: High №16 — оборонительное удаление снапшота при ошибке remote-апдейта может потерять несинхронизированные локальные правки.
4. **i18n**: Critical №11 + High №29–31 — захардкоженный английский в ошибках и контенте импорта нарушает заявленную конвенцию.

Архитектурные находки (god-объекты, сломанный `Package.swift`, дубликаты Core/Native) — это технический долг, который не блокирует релиз, но должен попасть в roadmap: они блокируют тестируемость и ускоряют регрессии.

Позитив: новые import-фичи (парсеры, локализаторы ошибок, валидаторы) демонстрируют правильное применение i18n-паттернов и хорошее тестовое покрытие — их стоит взять за образец для приведения остального кода в норму.
