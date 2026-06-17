# План: локализация error-типов (AuthError, APIError, YrsError)

**Спецификация**: [spec.md](spec.md)
**Ветка**: `031-error-i18n`
**Дата**: 2026-06-17

## Этап 1. Каталог строк

### 1.1. Добавить ключи в `Localizable.xcstrings`

~40 новых ключей в `en` + `ru`, `extractionState: manual`:

- `auth.error.*` (7): `keychain`, `decoding`, `network`, `invalid-seed`, `seed-not-found`, `api-generic`, `invalid-response`
- `api.error.*` (7): `invalid-url`, `invalid-response`, `decoding`, `unauthorized`, `server-generic`, `http-4xx`, `http-5xx`
- `yrs.error.*` (3): `technical`, `apply-failed`, `transaction`
- `account.profile.load-failed`, `account.sharing.load-failed`, `account.sharing.update-failed`, `account.settings.load-failed`
- `discover.fetch-failed`, `discover.collection-failed`, `discover.recipe-failed`, `discover.clone-failed`, `discover.public-recipe-failed`, `discover.public-profile-failed`, `discover.copy-failed`
- `recipe.import.no-images`, `recipe.import.failed`
- `recipe.image.upload-failed`, `recipe.image.delete-failed`
- `sharing.update-failed`
- `telegram.failed-to-get-code`, `telegram.status-failed`, `telegram.failed-to-disconnect`

## Этап 2. Error-типы

### 2.1. `AuthError` (RecipeScalerNative/Services/AuthService.swift)

- Удалить dead-code: `userNotFound`, `seedPhraseGenerationFailed`.
- Inline-паттерн через `Bundle.currentLocalizedString`.
- Добавить `static func userFacingMessage(for:)` или `userFacingMessage()` extension для типизированного вызова из view-слоя.
- `apiError(statusCode:message:)` — dot-key детекция + generic fallback.

### 2.2. `APIError` (RecipeScalerCore/Networking/APIClient.swift)

- `errorDescription` возвращает dot-key (без перевода) — Core не имеет доступа к Native xcstrings.
- Native-extension `RecipeScalerNative/Utils/APIError+Localization.swift`:
  - `func userFacingMessage() -> String` — резолвит через `Bundle.currentLocalizedString`.
  - `httpError(code)` → категориальный fallback (4xx / 5xx).
  - `serverError(message)` → dot-key детекция + generic.
- Удалить extension `APIError.httpError(statusCode:message:)` в `AssistantAPI.swift:267-273`.

### 2.3. `YrsError` (RecipeScalerNative/Services/Yrs/YrsError.swift)

- Удалить dead-code: `invalidState`, `corruptedState`.
- Inline-паттерн через `Bundle.currentLocalizedString` для живых кейсов.
- Контекст остаётся в associated value для логов, не интерполируется в `errorDescription`.
- В `YrsDocument.swift` сайты создания добавляют `AppLog.error(.document, ...)`.

## Этап 3. API-сервисы (30 throw-сайтов)

### 3.1. AccountAPI (4 сайта)

- `fetchProfile`: `"Profile load failed"` → `"account.profile.load-failed"`
- `fetchSharingSettings`: `"Sharing settings load failed"` → `"account.sharing.load-failed"`
- `patchSharingSettings`: `"Sharing settings update failed"` → `"account.sharing.update-failed"`
- `fetchUserSettings`: `"Settings load failed"` → `"account.settings.load-failed"`

### 3.2. DiscoverAPI (8 сайтов)

- `fetchDiscovery`: `"Discover fetch failed"` → `"discover.fetch-failed"`
- `fetchCollection`: `"Collection fetch failed"` → `"discover.collection-failed"`
- `fetchRecipe`: `"Recipe fetch failed"` → `"discover.recipe-failed"`
- `cloneRecipe`: `"Clone failed"` → `"discover.clone-failed"`
- `fetchPublicRecipeState` (2): `"Public recipe fetch failed"` → `"discover.public-recipe-failed"`, `"Public recipe decode failed: \(error)"` → `"discover.public-recipe-failed"`
- `copyRecipe`: `"Copy failed"` → `"discover.copy-failed"`
- `fetchPublicProfile` (2): `"Public profile fetch failed"` → `"discover.public-profile-failed"`, `"Public profile decode failed: \(error)"` → `"discover.public-profile-failed"`

### 3.3. RecipeImageUploadAPI (2 сайта)

- `upload`: `"Upload failed"` → `"recipe.image.upload-failed"`
- `delete`: `"Delete failed"` → `"recipe.image.delete-failed"`

### 3.4. SharingAPI (1 сайт)

- `updateShoppingListShare`: `"Share update failed"` → `"sharing.update-failed"`

### 3.5. TelegramAPI (3 сайта)

- `connect`: `String(localized: "telegram.failed-to-get-code")` → `"telegram.failed-to-get-code"` (ключ уже существовал в каталоге — `String(localized:)` заменён на прямой литерал, чтобы резолв шёл через `DotKeyLocalizer`, а не в момент throw)
- `status`: `"Telegram status failed"` → `"telegram.status-failed"`
- `disconnect`: `String(localized: "telegram.failed-to-disconnect")` → `"telegram.failed-to-disconnect"` (аналогично connect)

### 3.6. RecipeImportAPI (Core, 2 сайта)

- `importImages`: `"No images"` → `"recipe.import.no-images"`
- `unwrap`: `"Import failed"` → `"recipe.import.failed"`

### 3.7. AssistantAPI (без изменений)

Уже использует dot-key.

## Этап 4. View-слой (~50 сайтов)

Заменить `error.localizedDescription` на типизированный catch:

```swift
} catch let error as APIError {
    errorMessage = error.userFacingMessage()
} catch let error as AuthError {
    errorMessage = error.errorDescription ?? ""
} catch {
    errorMessage = error.localizedDescription
}
```

Файлы (детально в исследовании):

- `AuthView.swift:267,281`
- `AssistantSheet.swift:287,327,339,360,378,458`
- `AssistantComposer.swift:400-405` (удалить prefix-сниффинг)
- `DiscoverRootView.swift:118`, `DiscoverRecipeView.swift:315,333`, `DiscoverPublicProfileView.swift:144`, `DiscoverCollectionView.swift:119`
- `TelegramConnectionView.swift:220,236`
- `YDocRecipeDetailView.swift:414,698,915,976,1009,1020,1031,1056,1082`
- `RecipeListView.swift:288,302,314,334,347`
- `CollectionFolderView.swift:308,327,345,358,367,381,390`
- `ManageCollectionRecipesSheet.swift:140`, `CollectionAssignSheet.swift:185,214`
- `ShoppingListView.swift:383`, `AppShellView.swift:337`
- `RecipeDetailActionsMenu.swift:98,110,118`
- `RecipeDetailImageSection.swift:177` (расширить `uploadErrorMessage` через `APIError.userFacingMessage()`)
- `DescriptionEditorBridge.swift:136`
- `ImportRecipeSheet.swift:322`, `DataManagementView.swift:263,276,321,326`
- `UserFacingAPIError.swift:24-32` — заменить `return message` на `return APIErrorUserLocalizer.localizeServerMessage(message)`

`AccountView.swift:571` не трогать (`LAError`).

## Этап 5. Тесты

### 5.1. `LocalizationConsistencyTests.swift`

Расширить проверку ключей — все новые ключи есть в en + ru.

### 5.2. `AuthErrorLocalizationTests.swift` (новый)

```swift
func testErrorDescriptionIsLocalized() {
    XCTAssertNotEqual(AuthError.invalidSeedPhrase.errorDescription, "Invalid seed phrase")
    XCTAssertNotNil(AuthError.invalidSeedPhrase.errorDescription)
}
```

### 5.3. `APIErrorUserLocalizerTests.swift` (новый)

```swift
func testDotKeyResolves() {
    let msg = APIError.serverError(message: "assistant.threads.create.failed").userFacingMessage()
    XCTAssertNotEqual(msg, "assistant.threads.create.failed")  // resolved
}

func testRawEnglishFallback() {
    let msg = APIError.serverError(message: "Profile load failed").userFacingMessage()
    // Should fall back to generic, not pass English through
    XCTAssertNotEqual(msg, "Profile load failed")
}
```

### 5.4. `YrsErrorLocalizationTests.swift` (новый)

```swift
func testErrorDescriptionLocalized() {
    XCTAssertNotEqual(YrsError.nullPointer(context: "x").errorDescription, "Yrs null pointer: x")
}
```

## Этап 6. Build & Verify

- `xcodebuild build` — без warning'ов.
- `xcodebuild test` — все тесты зелёные.
- Ручной прогон ru/en в симуляторе.

## Этап 7. Документация

- `docs/I18N.md` — секция «Error-типы».
- `specs/031-error-i18n/server-error-keys.md` — контракт для бэкенда.
- `AGENTS.md` — ссылка на контракт.

## Зависимости

- Этап 1 → все остальные (каталог нужен раньше кода).
- Этап 2 (типы) → Этап 3 (сервисы) → Этап 4 (views).
- Этап 5 можно писать параллельно с Этапом 4.
- Этап 6 в конце.

## Риски

- **R1**: Изменение `APIError.errorDescription` с английского литерала на dot-key может сломать существующие тесты, сравнивающие строки. Проверить все тесты на `APIError.*.errorDescription`.
- **R2**: Удаление dead-code `YrsError.invalidState`/`corruptedState` может вскрыть неявные ссылки — прогнать grep перед удалением.
- **R3**: Some `response.error` от сервера могут содержать локализованные строки для ru-локали (если сервер уже i18n-aware) — fallback-логика может их маскировать. Это acceptable, т.к. dot-key контракт — требуемый путь.
