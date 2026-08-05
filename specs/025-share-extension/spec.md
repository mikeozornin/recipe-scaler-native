# Спецификация: Share Extension, Action Extension, Deep Link для импорта рецептов

**Ветка**: `025-share-extension`
**Дата**: 2026-06-06
**Статус**: ✅ DONE (2026-08-05) — код + **device smoke** (Safari Share / Messages / Telegram / Photos / Action / logout). Платный аккаунт — [PAID-doc](../../docs/PAID-APPLE-DEVELOPER-REQUIRED.md).  


**Зависимости**: `010-recipe-import` ✅ (RecipeImportAPI, ImportRecipeSheet), `007-app-shell-navigation` ✅ (AppShellView)  
**Эталон**: PRD § Import; нативный iOS Share Extension API (`NSExtensionContext`, `SLComposeServiceViewController`)

## Аудит реализации (2026-06-15)

| FR / US | Статус |
|---------|--------|
| FR-SE-001 RecipeScalerCore | ✅ `RecipeScalerCore/` |
| FR-SE-002 App Group | ✅ entitlements на main + extensions |
| FR-SE-003 Share Extension | ✅ `ShareExtension/` + `ShareView` |
| FR-SE-004–005 content + UI | ✅ `ShareContentLoader`, `ShareView` |
| FR-SE-006 Action Extension | ✅ `ActionExtension/` + `GetURLFromPage.js` |
| FR-SE-007–009 URL scheme + DeepLinkRouter | ✅ `recipe-scaler://`, `DeepLinkRouter.swift`, `.onOpenURL` |
| FR-SE-010–011 i18n | ✅ `Shared.xcstrings` |
| FR-SE-012 Provisioning | ✅ portal + Keychain Sharing подтверждены device smoke |
| SC-001…SC-010 | ✅ device smoke 2026-08-05 |

## Контекст

Импорт рецепта сегодня (spec 010) требует 4 шагов:

1. Скопировать URL/текст из источника (Safari, Messages, Telegram).
2. Открыть приложение Recipe Scaler.
3. Нажать вкладку Import.
4. Вставить URL/текст в sheet, нажать «Импорт».

Это главная UX-боль: нужно переключаться между приложениями и использовать буфер обмена.

iOS Share Sheet — нативный механизм для деления контентом между приложениями. Share Extension принимает URL / текст / фото из любого аппа, который поддерживает системный Share menu. Action Extension — близкая технология для контекстного меню Safari (long-press на странице).

Серверный парсинг (LLM/OCR) уже работает в spec 010: `RecipeImportAPI.importURLs`, `importText`, `importImages` принимают любой http(s) URL. Разделение Share / Action / Deep Link не требует серверных изменений — extension использует те же endpoints.

## Цель

Снизить шаги импорта из внешнего аппа с 4 до 2:

1. Share из источника → выбрать «Import to Recipe Scaler».
2. Нажать «Импорт» в карточке extension → экран успеха с кнопкой «Открыть рецепт» → апп открывается на новом рецепте.

Дополнительно: Action Extension в Safari для long-press → контекстное меню → «Импорт в Recipe Scaler».

## Пользовательские сценарии

### US1 — Share из Safari (P1)

**Когда** пользователь открывает страницу рецепта в Safari, **тогда** Share → «Import to Recipe Scaler» → карточка с превью URL → «Импорт» → успех → «Открыть рецепт» открывает главный апп на новом рецепте через `recipe-scaler://recipe/{id}`.

### US2 — Share из Messages (P1)

**Когда** пользователь получает сообщение со ссылкой или текстом рецепта в Messages, **тогда** long-press → Share → «Import to Recipe Scaler» → тот же flow, что US1. Поддерживается: один URL, текст рецепта, комбинация (URL + текст).

### US3 — Share из Telegram (P1)

**Когда** пользователь открывает сообщение в Telegram, **тогда** long-press → Share → «Import to Recipe Scaler» → тот же flow. Telegram передаёт либо URL сообщения, либо текст, либо и то и другое.

### US4 — Share фотографий (P2)

**Когда** пользователь выбирает 1–8 фото в Photos или другом аппе, **тогда** Share → «Import to Recipe Scaler» → multipart upload через `RecipeImportAPI.importImages` → успех → open.

### US5 — Action Extension в Safari (P2)

**Когда** пользователь на странице рецепта в Safari делает long-press, **тогда** в контекстном меню появляется «Импорт в Recipe Scaler» → сразу открывается карточка импорта с URL активной вкладки. Отличие от Share: не нужно искать иконку в Share menu, быстрее на повторяющихся операциях.

### US6 — Deep Link из Extension в главный апп (P1)

**Когда** extension успешно импортировал рецепт и юзер нажал «Открыть рецепт», **тогда** главный апп открывается на экране этого рецепта через URL scheme `recipe-scaler://recipe/{id}`. Если апп был убит (холодный старт), `YDocRecipeDetailView` открывается после `YjsSyncService.handleEnteredForeground()` подтянет Y.Doc; до этого показывается skeleton.

### US7 — Ошибка / не залогинен (P1)

**Когда** юзер не залогинен в главном аппе (нет `userId` в `SharedAuthStore`), **тогда** extension показывает сообщение «Войдите в приложение Recipe Scaler, чтобы импортировать рецепт» без возможности сабмита.

### US8 — Ошибка сети / парсинга (P1)

**Когда** сервер вернул ошибку или нет интернета, **тогда** extension показывает локализованное сообщение об ошибке (`ImportErrorLocalizer` из spec 010) и предлагает «Повторить» или «Отмена».

## Требования

### FR-SE-001 — Framework RecipeScalerCore

Выделить общие компоненты в Cocoa Touch Framework `RecipeScalerCore`:

- `APIClient`, `APIClient+Requests` (без `@MainActor`, потокобезопасный через `os.OSUnfairLock`).
- `RecipeImportAPI` (без `@MainActor`).
- `ImportContentClassifier`, `ImportPhotoValidator`, `ImportErrorLocalizer`, `Config`, `APIResponse`, `AnyEncodable`.
- `SharedAuthStore` (новый) — чтение/запись `userId` через App Group `UserDefaults`.

Framework используется main app target, Share Extension target, Action Extension target.

### FR-SE-002 — App Group

Создать App Group `group.ru.recipescaler.RecipeScaler`:

- Добавить entitlement в main app (`RecipeScalerNative.entitlements`).
- Добавить entitlement в Share Extension (`ShareExtension.entitlements`).
- Добавить entitlement в Action Extension (`ActionExtension.entitlements`).

`AuthService` главного аппа пишет `userId` в `SharedAuthStore` при логине; стирает при логауте.

### FR-SE-003 — Share Extension Target

- Bundle ID: `ru.recipescaler.RecipeScaler.Share`.
- Display Name: «Импорт в Recipe Scaler» (локализованный).
- `NSExtensionActivationRule`:
  - `NSExtensionActivationSupportsWebURLWithMaxCount: 1`
  - `NSExtensionActivationSupportsWebPageWithMaxCount: 1`
  - `NSExtensionActivationSupportsText: 1`
  - `NSExtensionActivationSupportsImageWithMaxCount: 8`
- Принципал: `ShareViewController` (UIKit), который хостит SwiftUI `ShareView`.

### FR-SE-004 — Извлечение контента

Извлекать контент из `NSExtensionContext.inputItems[*].attachments[*]` по приоритетам:

1. `UTType.url` (один URL, допускается `NSExtensionActivationSupportsWebURLWithMaxCount: 1`).
2. `UTType.text` → прогон через `ImportContentClassifier.classify(_:)`:
   - `isUrlOnly: true` → `importURLs(_:)`.
   - иначе → `importText(_:)`.
3. `UTType.image` (до 8 штук) → `ImportPhotoValidator.validate` → `importImages(_:)`.

Если ничего не найдено → экран ошибки с локализованной строкой.

### FR-SE-005 — UI Share Extension

SwiftUI `ShareView`:

- **Preview состояние**: показывает превью контента (URL / первые 2 строки текста / thumbnails фото) + кнопка «Импорт».
- **Loading**: `ProgressView` + текст «Импортируем...».
- **Success**: иконка успеха + текст «Импортировано!» + кнопка «Открыть рецепт».
- **Error**: иконка ошибки + локализованное сообщение + кнопки «Повторить» / «Отмена».

Localization через `Bundle.module` (framework resources).

### FR-SE-006 — Action Extension Target

- Bundle ID: `ru.recipescaler.RecipeScaler.Action`.
- Display Name: «Импорт в Recipe Scaler».
- `NSExtensionPointIdentifier`: `com.apple.ui-services`.
- `NSExtensionJavaScriptPreprocessingFile`: `GetURLFromPage.js` — берёт `document.URL` из активной вкладки Safari.
- UI: переиспользует `ShareView` из shared framework, контент — только URL.

### FR-SE-007 — URL Scheme (Deep Link)

В main app `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>ru.recipescaler.RecipeScaler</string>
    <key>CFBundleURLSchemes</key>
    <array><string>recipe-scaler</string></array>
  </dict>
</array>
```

Формат: `recipe-scaler://recipe/{recipeId}`. `{recipeId}` — UUID в нижнем регистре (как в URL веб-клиента).

### FR-SE-008 — DeepLinkRouter

В main app создать `Routing/DeepLinkRouter.swift`:

- `handle(_ url: URL)`: парсит `recipe-scaler://recipe/{id}`, валидирует UUID и **нормализует id в нижний регистр**, пишет pending id в `UserDefaults.standard` + post уведомление.
- Поддержка холодного старта: `AppShellView.onAppear` читает pending id и пушит в `recipesPath`.
- Поддержка тёплого старта: `AppShellView.onReceive(.openRecipeRequested)` обрабатывает уведомление.

### FR-SE-009 — .onOpenURL в main app

В `RecipeScalerNativeApp.swift` добавить:

```swift
WindowGroup {
    ContentView()
        .onOpenURL { url in
            DeepLinkRouter.handle(url)
        }
}
```

### FR-SE-010 — i18n

Новые ключи в `RecipeScalerCore/Resources/Shared.xcstrings` (en + ru):

- `share-extension.title` — «Импорт в Recipe Scaler» / «Import to Recipe Scaler»
- `share-extension.button-import` — «Импорт» / «Import»
- `share-extension.button-open` — «Открыть рецепт» / «Open recipe»
- `share-extension.button-retry` — «Повторить» / «Retry»
- `share-extension.button-cancel` — «Отмена» / «Cancel»
- `share-extension.importing` — «Импортируем...» / «Importing...»
- `share-extension.success` — «Импортировано!» / «Imported!»
- `share-extension.success-multiple` — «Импортировано рецептов: %d» / «Imported recipes: %d»
- `share-extension.error-no-content` — «Нет контента для импорта» / «Nothing to import»
- `share-extension.error-not-signed-in` — «Войдите в приложение Recipe Scaler, чтобы импортировать рецепт» / «Sign in to Recipe Scaler to import a recipe»
- `share-extension.error-network` — «Ошибка сети» / «Network error»

Эти же ключи добавляются в `RecipeScalerNativeTests/LocalizationConsistencyTests.swift` (en + ru проверка).

### FR-SE-011 — Локализация ошибок

`ImportErrorLocalizer` получает параметр `bundle: Bundle`:

- Из main app: `Bundle.main`.
- Из extension: `Bundle.module` (framework).

Существующие ключи `import.*` (offline, captcha, too-many-recipes и т.д.) используются повторно — extension подкладывает `Shared.xcstrings` с теми же ключами.

### FR-SE-012 — Provisioning

На Apple Developer Portal (team `ZBPX4JYT24`):

- Создать App Group `group.ru.recipescaler.RecipeScaler`.
- Создать App ID для `ru.recipescaler.RecipeScaler.Share` с включённым App Group.
- Создать App ID для `ru.recipescaler.RecipeScaler.Action` с включённым App Group.
- Обновить provisioning profile для main app + оба extension.

Симулятор не требует реальных entitlements для smoke-тестирования, но `UserDefaults(suiteName:)` работает только если App Group объявлен — на симуляторе валиден любой suiteName, поэтому логику покрывает без профиля.

## Критерии успеха

- **SC-001**: Safari на recipe URL → Share → «Import to Recipe Scaler» → «Импорт» → «Открыть рецепт» → главный апп открывается на рецепте ≤ 5 с (парсинг + открытие).
- **SC-002**: Messages с текстом рецепта → Share → «Import to Recipe Scaler» → импорт проходит через `importText`, не через URL endpoint.
- **SC-003**: Telegram сообщение с URL → Share → extension корректно извлекает URL (не всё сообщение), импорт как US1.
- **SC-004**: Photos 1–8 фото → Share → multipart upload, тот же серверный ответ, что `importImages` из sheet.
- **SC-005**: Safari long-press на странице → «Импорт в Recipe Scaler» в контекстном меню → Action Extension открывается с URL активной вкладки.
- **SC-006**: Холодный старт: апп убит, extension открыл deep link → главный апп открывается на экране рецепта после подтягивания Y.Doc.
- **SC-007**: Юзер не залогинен → extension показывает `share-extension.error-not-signed-in`, кнопка «Импорт» не активна.
- **SC-008**: Сетевая ошибка / captcha → локализованное сообщение из `ImportErrorLocalizer`, кнопка «Повторить».
- **SC-009**: Сборка всех 3 target'ов зелёная (`xcodebuild build`).
- **SC-010**: `LocalizationConsistencyTests` зелёные (все новые ключи есть в en + ru).

## Артефакты

- `plan.md` — реализация framework extraction, Share Extension, Action Extension, Deep Link.
- `tasks.md` — декомпозиция по фазам.
- `quickstart.md` — чеклист Xcode setup + ручной smoke на симуляторе.
- `contracts/share-extension-payload.md` (опционально) — формат данных между Safari Action preprocessing и extension.

## Связь с закрытыми спеками

| Было в 010 | Стало |
|------------|--------|
| Импорт через sheet только | Sheet остаётся, добавляется extension как второй entry point |
| `RecipeImportAPI` в main app | Переносится в `RecipeScalerCore` framework |
| Нет навигации извне | `recipe-scaler://recipe/{id}` deep link |

## Вне scope

- File `.json/.zip` импорт через share extension → spec **020-account-telegram-export**.
- Universal Links (`applinks:recipe-scaler.ru`) — требует серверных `apple-app-site-association`, отдельная фича.
- Telegram bot integration как Share target — серверная фича.
- Push notification после импорта из extension — пользователь видит рецепт через deep link.
- `AppIntent` / Siri Shortcuts для импорта — можно рассмотреть как следующий шаг.
- Редактирование результата до save (опционально v2).
