# Платный Apple Developer Program — что отложено до $99/год

**Проект**: Recipe Scaler Native (весь `recipe-scaler-native`)  
**Статус**: платный аккаунт **пока нет** — единый чеклист, чтобы не потерять шаги в портале и на устройстве.

Программа: [Apple Developer Program](https://developer.apple.com/programs/).

---

## Краткий вывод

| Без платного (Personal Team / бесплатный Apple ID) | С платным Developer Program |
|----------------------------------------------------|-----------------------------|
| Сборка и запуск **основного приложения** на симуляторе; часто на своём iPhone (подпись ~7 дней, лимиты Apple) | Стабильнее подпись, меньше сюрпризов с **app extensions** |
| Разработка UI, API, offline, Yjs, импорт из **sheet** внутри app | То же |
| **Deep link** `recipe-scaler://` в main app | То же |
| **TestFlight**, **App Store**, публичное распространение | Да |
| **App Groups** в портале + общие данные app ↔ extension на **реальном iPhone** | Нужно для production |
| Полноценный **Push** (APNs) в проде | Capability + ключи в портале (когда включим push в релизе; **после Activity Charts**) |

Большую часть нативки можно вести и собирать **без** платного аккаунта. Ниже — всё, что для **продакшена на устройствах пользователей** или для **расширений системы** требует платной программы.

---

## Идентификаторы (сверять с Xcode → Signing)

| Сущность | Значение |
|----------|----------|
| Team ID (в `project.pbxproj`) | `ZBPX4JYT24` |
| Main app | `ru.recipescaler.RecipeScaler` |
| Framework `RecipeScalerCore` | `ru.recipescaler.RecipeScaler.Core` |
| Share Extension | `ru.recipescaler.RecipeScaler.Share` |
| Action Extension | `ru.recipescaler.RecipeScaler.Action` |
| Home Widget | `ru.recipescaler.RecipeScaler.HomeWidget` |
| Timer Live Activity | `ru.recipescaler.RecipeScaler.TimerLiveActivity` |
| Watch app | `ru.recipescaler.RecipeScaler.watchkitapp` |
| **App Group** | `group.ru.recipescaler.RecipeScaler` |

Файлы entitlements в репозитории (должны совпасть с порталом и provisioning):

- `RecipeScalerNative/RecipeScalerNative.entitlements` — App Groups
- `ShareExtension/ShareExtension.entitlements` — App Groups
- `ActionExtension/ActionExtension.entitlements` — App Groups

---

## 1. Apple Developer Portal (после оплаты программы)

### 1.1 App Group

1. [Identifiers → App Groups](https://developer.apple.com/account/resources/identifiers/list/applicationGroup)
2. **+** → App Groups
3. Identifier: `group.ru.recipescaler.RecipeScaler`
4. Description: например `Recipe Scaler — shared storage for extensions`

### 1.2 App IDs и capabilities

Для **main app** и **каждого extension** (Bundle ID из Xcode):

- App ID существует или создаётся.
- Включить **App Groups** → привязать `group.ru.recipescaler.RecipeScaler`.

Минимум для фичи Share/Action (spec `025-share-extension`):

- Main + Share + Action — все три с одним App Group.

**На будущее** (spec `023-push-notifications`, когда пойдём в прод с пушами — **только после Activity Charts**):

- На App ID main app включить **Push Notifications**.
- Создать APNs key / сертификат в портале; настроить backend.

### 1.3 Provisioning profiles

- Development (и при необходимости Distribution) для:
  - `RecipeScalerNative`
  - `ShareExtension`
  - `ActionExtension`
- Xcode: **Automatically manage signing**, одна Team, без ошибок на всех таргетах.

### 1.4 Распространение (только платное)

- **TestFlight** — тест на чужих iPhone, Share Sheet, extensions.
- **App Store** — релиз; extensions встроены в основной бинарник.

---

## 2. Xcode (после портала)

На таргетах **RecipeScalerNative**, **ShareExtension**, **ActionExtension**:

1. **Signing & Capabilities** → **+ Capability** → **App Groups**
2. Отметить `group.ru.recipescaler.RecipeScaler`

Детальный setup таргетов и smoke: `specs/025-share-extension/quickstart.md`.

---

## 3. Что на нативке **не** считается «готово на iPhone» без платного

### Share / Action extensions (`025-share-extension`)

- Extension видит тот же `userId`, что main app (`SharedAuthStore` / App Group) — на **физическом iPhone** без портала часто **nil** → `share-extension.error-not-signed-in`.
- Стабильный импорт из **Safari / Messages / Photos / Telegram** через системный Share Sheet на **устройстве**.
- **Action Extension** в контекстном меню Safari без ошибок provisioning.

На **симуляторе** можно отлаживать UI и цепочку импорта; это **не заменяет** проверку на телефоне перед релизом.

### Весь продукт

- Раздача сборки тестерам через **TestFlight**.
- Публикация в **App Store**.
- Любые **новые** App IDs / App Groups / Push / Associated Domains / iCloud — регистрация в портале под платной программой.

### Что можно **сейчас** без платного

- `xcodebuild` / Xcode, схема `RecipeScalerNative` (main + Core + extensions embed).
- Симулятор: основной флоу приложения, deep link внутри app.
- Импорт рецепта из **ImportRecipeSheet** в main app.
- Unit-тесты, локализация, offline/Yjs (как сейчас в проекте).

---

## 4. Порядок действий в день оформления программы

1. Чеклист портала (§ 1).
2. Xcode: три таргета с App Groups, Signing без красных ошибок.
3. Установка на **свой iPhone** (не только симулятор).
4. Логин в app → Share из Safari → extension **не** «не залогинен», если сессия есть в app.
5. Импорт URL → «Открыть рецепт» → cold start по `recipe-scaler://recipe/{id}`.
6. Safari → Action «Импорт в Recipe Scaler» (если виден в меню).
7. При необходимости: TestFlight.

---

## 5. Заметки

- Бесплатная подпись: срок действия, лимит приложений/устройств; **extensions** и **App Groups** — частые ошибки `Failed to register bundle identifier` / provisioning profile.
- Платный аккаунт не заменяет код в репозитории; он **включает** портал и профили под уже прописанные entitlements.
- Сменили Bundle ID extension в Xcode — обновить этот файл и App IDs в портале.

**Связанные спеки**: `025-share-extension` (extensions, deep link), `023-push-notifications` (push — отдельно при релизе, **после Activity Charts**).

**Дата фиксации**: 2026-06-06; обновлено 2026-07-24 (Team ID `ZBPX4JYT24`, App Group `group.ru.recipescaler.RecipeScaler`, bundle ID prefix `ru.recipescaler.RecipeScaler`).