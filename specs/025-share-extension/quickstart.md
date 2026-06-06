# Быстрый старт: Share Extension, Action Extension, Deep Link

**Фича**: `025-share-extension`
**Предусловие**: spec 010 (`RecipeImportAPI`) реализован; главный апп собирается и работает с импортом рецептов через sheet.

Этот документ — чеклист настройки Xcode + ручной smoke для проверки Share/Action Extension.

## Часть 1. Настройка Xcode (выполняется один раз)

> **Важно**: эти шаги выполняются вручную в Xcode UI. Агент не может надёжно редактировать `project.pbxproj` под создание target'ов.

### 1.1. Создать App Group

1. Зайти на https://developer.apple.com/account/resources/identifiers/list/applicationGroup
2. + New Identifier → App Groups
3. Identifier: `group.ru.recipescaler.RecipeScalerNative`
4. Description: `Recipe Scaler — shared storage for extensions`
5. Сохранить

### 1.2. Создать target `RecipeScalerCore` (framework)

1. В Xcode: File → New → Target...
2. iOS → Framework & Library → Cocoa Touch Framework
3. Product Name: `RecipeScalerCore`
4. Language: Swift
5. Include Tests: No
6. Embed in Application: `RecipeScalerNative`
7. Finish

В появившемся `RecipeScalerCore.h` оставить стандартный шаблон (он нужен для umbrella header).

### 1.3. Создать target `ShareExtension`

1. File → New → Target...
2. iOS → Application Extension → Share Extension
3. Product Name: `ShareExtension`
4. Language: Swift
5. Project: `RecipeScalerNative`
6. Embed in Application: `RecipeScalerNative`
7. Finish
8. В появившемся окне "Activate ShareExtension scheme?" — нажать Activate

### 1.4. Создать target `ActionExtension`

1. File → New → Target...
2. iOS → Application Extension → Action Extension
3. Product Name: `ActionExtension`
4. Language: Swift
5. Action Type: "Presents User Interface"
6. Project: `RecipeScalerNative`
7. Embed in Application: `RecipeScalerNative`
8. Finish
9. Activate scheme

### 1.5. App Group entitlements на 3 target'ах

Для каждого target (`RecipeScalerNative`, `ShareExtension`, `ActionExtension`):

1. Project Navigator → выбрать `RecipeScalerNative.xcodeproj`
2. выбрать target
3. вкладка "Signing & Capabilities"
4. + Capability → App Groups
5. выбрать `group.ru.recipescaler.RecipeScalerNative`

### 1.6. RecipeScalerCore на 3 target'ах

**Main app (`RecipeScalerNative`):**

1. Target → `RecipeScalerNative` → General → Frameworks, Libraries, and Embedded Content
2. + → `RecipeScalerCore.framework` → "Embed & Sign"

**ShareExtension и ActionExtension:**

1. Target → ShareExtension → General → Frameworks and Libraries
2. + → `RecipeScalerCore.framework` → "Do Not Embed"
3. То же для `ActionExtension`

> Extension'ы не могут embed'ить framework — это должен делать host app.

### 1.7. Scheme build targets

1. Product → Scheme → Edit Scheme...
2. Build → проверить, что выбраны все 4 target'а:
   - `RecipeScalerNative` (app)
   - `RecipeScalerCore` (framework)
   - `ShareExtension`
   - `ActionExtension`

### 1.8. URL scheme в main app Info.plist

Расширить `RecipeScalerNative/Info.plist` (или в Target → Info → URL Types):

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>ru.recipescaler.RecipeScalerNative</string>
    <key>CFBundleURLSchemes</key>
    <array><string>recipe-scaler</string></array>
  </dict>
</array>
```

### 1.9. Контрольная точка

```bash
rtk xcodebuild -scheme RecipeScalerNative \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    build
```

Ожидаемый результат: BUILD SUCCEEDED, в логе видно, что собираются все 4 target'а.

Если есть ошибки "missing module" — проверить framework embedding (1.6).

---

## Часть 2. Ручной smoke (симулятор)

### 2.1. Запуск main app

1. `xcrun simctl list devices available | rg 'iPhone 16'` — взять UDID.
2. Запустить симулятор: `open -a Simulator`.
3. Build & run из Xcode на симуляторе.
4. Залогиниться (на debug-сборке — автологин).
5. Подтвердить, что в `SharedAuthStore.userId` записан id:
   ```bash
   xcrun simctl get_app_container booted ru.recipescaler.RecipeScalerNative data
   # в папке /Library/Preferences/ должен быть plist
   ```
   Или: добавить debug-принт в `ContentView.init`.

### 2.2. Smoke: Share Extension из Safari (SC-001)

1. В симуляторе открыть Safari.
2. Перейти на любой рецепт — например, https://www.allrecipes.com/recipe/228285/easy-meatloaf/
3. Share button → должна появиться карточка «Import to Recipe Scaler» (или «Импорт в Recipe Scaler»).
4. Тапнуть → открывается `ShareView` с превью URL.
5. Тапнуть «Импорт» → loading 5–30 с.
6. Успех → экран «Импортировано!» + кнопка «Открыть рецепт».
7. Тапнуть «Открыть рецепт» → main app открывается на экране рецепта.

### 2.3. Smoke: Share Extension из Messages (SC-002)

1. Сообщение со ссылкой: отправить себе через Messages любой URL.
2. Long-press на сообщение → Share.
3. Выбрать «Import to Recipe Scaler».
4. Дальше — как 2.2.

Текст рецепта:

1. Сообщение с текстом «Борщ с говядиной, 4 порции. 500 г мяса, 2 свёклы, ...».
2. Long-press → Share → «Import to Recipe Scaler» → текстовый импорт.

### 2.4. Smoke: Share Extension из Telegram (SC-003)

1. Установить Telegram в симулятор (или через TestFlight на устройство).
2. Открыть любой чат с URL в сообщении.
3. Long-press → Share → «Import to Recipe Scaler».
4. Дальше — как 2.2.

### 2.5. Smoke: Share Extension из Photos (SC-004)

1. Открыть Photos.
2. Выбрать 1–8 фото (скриншоты рецептов).
3. Share → «Import to Recipe Scaler» → multipart upload → успех.

### 2.6. Smoke: Action Extension в Safari (SC-005)

1. Safari открыт на странице рецепта.
2. Long-press на странице (не на ссылке) → должно появиться контекстное меню.
3. Если в меню есть «Импорт в Recipe Scaler» → тап → Action Extension открывается с URL активной вкладки.
4. Импорт → «Открыть рецепт» → main app.

> В старых iOS Action Extension может быть в подменю "More..." или "Share". Зависит от iOS.

### 2.7. Smoke: Deep Link (SC-006)

```bash
xcrun simctl openurl booted recipe-scaler://recipe/test-recipe-id
```

Ожидаемое: main app открывается (если был закрыт — холодный старт), пытается показать рецепт. `YDocRecipeDetailView` показывает skeleton, если doc ещё не загружен.

### 2.8. Smoke: Не залогинен (SC-007)

1. Запустить main app, залогиниться, убедиться что `SharedAuthStore.userId` заполнен.
2. Выйти из аккаунта (Profile → Logout).
3. Открыть Safari → Share → «Import to Recipe Scaler».
4. Ожидаемое: экран ошибки «Войдите в приложение Recipe Scaler...», кнопка «Импорт» отсутствует.

### 2.9. Smoke: Ошибка сети (SC-008)

1. Включить авиарежим.
2. Safari → Share → «Import to Recipe Scaler».
3. Тапнуть «Импорт».
4. Ожидаемое: локализованная ошибка сети, кнопка «Повторить».

Альтернатива: ошибка сервера (плохой URL без рецепта) → локализованное сообщение от `ImportErrorLocalizer`.

---

## Часть 3. Unit-тесты

### 3.1. DeepLinkRouterTests

```bash
rtk xcodebuild test \
    -scheme RecipeScalerNative \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:RecipeScalerNativeTests/DeepLinkRouterTests
```

5 кейсов:

- Валидный URL → pending id сохранён.
- Чужая схема (`https://recipe/abc`) → игнор.
- Чужой host (`recipe-scaler://other/abc`) → игнор.
- Пустой id (`recipe-scaler://recipe/`) → игнор.
- consumePendingRecipeId() → возвращает id и стирает.

### 3.2. LocalizationConsistencyTests

```bash
rtk xcodebuild test \
    -scheme RecipeScalerNative \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:RecipeScalerNativeTests/LocalizationConsistencyTests
```

Проверяет, что все ключи `share-extension.*` (11 шт) есть в `Shared.xcstrings` (en + ru).

---

## Часть 4. Скрипт верификации

```bash
./scripts/verify-share-extension.sh
```

Делает:

1. `rtk xcodebuild build` всех 4 target'ов.
2. Запускает `DeepLinkRouterTests` + `LocalizationConsistencyTests`.
3. Проверяет через `rg`, что в `project.pbxproj` есть 3 новых product type:
   - `com.apple.product-type.framework` (RecipeScalerCore)
   - `com.apple.product-type.app-extension` × 2

---

## Ключевые файлы (после implement)

| Область | Путь |
|---------|------|
| Framework | `RecipeScalerCore/` (новая папка) |
| Auth store | `RecipeScalerCore/Auth/SharedAuthStore.swift` |
| Network | `RecipeScalerCore/Networking/APIClient.swift`, `APIClient+Requests.swift` |
| Import | `RecipeScalerCore/Import/RecipeImportAPI.swift` + 3 утилиты |
| i18n | `RecipeScalerCore/Resources/Shared.xcstrings` |
| Share Extension | `ShareExtension/ShareViewController.swift`, `ShareView.swift`, `ShareContentLoader.swift`, `ShareContentClassifier.swift` |
| Action Extension | `ActionExtension/ActionViewController.swift`, `GetURLFromPage.js` |
| Deep Link | `RecipeScalerNative/Routing/DeepLinkRouter.swift` |
| Main app hooks | `RecipeScalerNative/RecipeScalerNativeApp.swift` (`.onOpenURL`), `Views/AppShellView.swift` (`.onReceive`), `Services/AuthService.swift` (SharedAuthStore) |

---

## Возможные проблемы

| Проблема | Решение |
|----------|---------|
| Share Extension не появляется в Share Sheet | Проверить `NSExtensionActivationRule` в Info.plist; проверить, что extension embed'нут в main app (Build Phases → Embed App Extensions) |
| Memory limit (Action Extension 16 MB) | Только URL в Action Extension; не передавать изображения |
| Memory limit (Share Extension 120 MB) | Stream фото через autoreleasepool, не держать `[Data]` в памяти |
| `recipe-scaler://` не открывает main app | Проверить `CFBundleURLTypes` в Info.plist; проверить, что URL scheme уникальный (не конфликтует с другими аппами) |
| `SharedAuthStore.userId` nil из extension | Проверить, что App Group entitlement добавлен на ОБА target'а; что `AuthService` пишет в App Group `UserDefaults` |
| `Bundle.module` не находит strings | Проверить, что `Shared.xcstrings` добавлен в target membership `RecipeScalerCore` (Build Phases → Copy Bundle Resources) |
| Холодный старт по deep link показывает список, не рецепт | Проверить, что `AppShellView.onAppear` читает pending id и пушит в `recipesPath` |

---

## Следующий шаг Spec Kit

```text
/speckit-implement
```
