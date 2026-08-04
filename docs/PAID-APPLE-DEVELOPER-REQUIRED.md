# Платный Apple Developer Program — портал и device smoke

**Проект**: Recipe Scaler Native (весь `recipe-scaler-native`)  
**Статус**: платный аккаунт **есть** (team `ZBPX4JYT24`) — остаётся сверить портал (App Group / App IDs / Keychain Sharing) и прогнать device smoke для Share/Action.

Программа: [Apple Developer Program](https://developer.apple.com/programs/).

---

## Краткий вывод

| Без платного (Personal Team / бесплатный Apple ID) | С платным Developer Program |
|----------------------------------------------------|-----------------------------|
| Сборка и запуск **основного приложения** на симуляторе; часто на своём iPhone (подпись ~7 дней, лимиты Apple) | Стабильнее подпись, меньше сюрпризов с **app extensions** |
| Разработка UI, API, offline, Yjs, импорт из **sheet** внутри app | То же |
| **Deep link** `recipe-scaler://` в main app | То же |
| **TestFlight**, **App Store**, публичное распространение | Да |
| **App Groups** + **Keychain Sharing** в портале → общие креды app ↔ extension на **реальном iPhone** | Нужно для production Share/Action |
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
| **Keychain access group** | `$(AppIdentifierPrefix)ru.recipescaler.RecipeScaler` → runtime `ZBPX4JYT24.ru.recipescaler.RecipeScaler` |

Файлы entitlements в репозитории (должны совпасть с порталом и provisioning):

- `RecipeScalerNative/RecipeScalerNative.entitlements` — App Groups + Keychain Sharing
- `RecipeScalerNative/RecipeScalerNativeDebug.entitlements` — то же (+ debug push env)
- `ShareExtension/ShareExtension.entitlements` — App Groups + Keychain Sharing
- `ActionExtension/ActionExtension.entitlements` — App Groups + Keychain Sharing
- `HomeWidgetExtension/HomeWidgetExtension.entitlements`
- `TimerLiveActivityExtension/TimerLiveActivityExtension.entitlements`

---

## 1. Apple Developer Portal (чеклист — сверить / донастроить)

### 1.1 App Group

1. [Identifiers → App Groups](https://developer.apple.com/account/resources/identifiers/list/applicationGroup)
2. Если нет — **+** → App Groups
3. Identifier: `group.ru.recipescaler.RecipeScaler`
4. Description: например `Recipe Scaler — shared storage for extensions`
5. Сохранить

### 1.2 App IDs и capabilities

Для каждого Bundle ID ниже:

| Bundle ID | Нужные capabilities |
|-----------|---------------------|
| `ru.recipescaler.RecipeScaler` | App Groups → `group.ru.recipescaler.RecipeScaler`; **Keychain Sharing** → `ru.recipescaler.RecipeScaler`; **Associated Domains** → `applinks:recipe-scaler.ru` (spec `059-universal-links`) |
| `ru.recipescaler.RecipeScaler.Share` | App Groups + Keychain Sharing (как выше; **без** Associated Domains) |
| `ru.recipescaler.RecipeScaler.Action` | App Groups + Keychain Sharing (как выше; **без** Associated Domains) |

Минимум для фичи Share/Action (spec `025-share-extension`):

- Main + Share + Action — один App Group + один Keychain Sharing group.
- Креды (`SharedAuthStore.token` / `userId`) живут в **Keychain access group**, не в App Group UserDefaults.

### 1.2.1 Associated Domains (Universal Links, spec `059-universal-links`)

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → App ID `ru.recipescaler.RecipeScaler` → **Associated Domains** → On.
2. Xcode main target: **Signing & Capabilities** → Associated Domains → `applinks:recipe-scaler.ru` (уже в entitlements).
3. Сервер: `GET https://recipe-scaler.ru/.well-known/apple-app-site-association` → 200, `application/json`, `appID` = `ZBPX4JYT24.ru.recipescaler.RecipeScaler`, paths = `["/public/@/*"]`.
4. Smoke:

```bash
curl -sI https://recipe-scaler.ru/.well-known/apple-app-site-association
curl -s https://recipe-scaler.ru/.well-known/apple-app-site-association | jq .
```

Apple CDN может кэшировать AASA до ~1 суток после первого fetch.

**На будущее** (spec `023-push-notifications`, когда пойдём в прод с пушами — **только после Activity Charts**):

- На App ID main app включить **Push Notifications**.
- Создать APNs key / сертификат в портале; настроить backend.

### 1.3 Provisioning profiles

- Development (и при необходимости Distribution) для:
  - `RecipeScalerNative`
  - `ShareExtension`
  - `ActionExtension`
- Xcode: **Automatically manage signing**, одна Team (`ZBPX4JYT24`), без ошибок на всех таргетах.

### 1.4 Распространение (только платное)

- **TestFlight** — тест на чужих iPhone, Share Sheet, extensions.
- **App Store** — релиз; extensions встроены в основной бинарник.

### 1.5 Проверка entitlements на установленном бинарнике

После install на device/sim:

```bash
codesign -d --entitlements :- /path/to/RecipeScalerNative.app
codesign -d --entitlements :- /path/to/RecipeScalerNative.app/PlugIns/ShareExtension.appex
```

Ожидается:

- `com.apple.security.application-groups` = `group.ru.recipescaler.RecipeScaler`
- `keychain-access-groups` содержит `ZBPX4JYT24.ru.recipescaler.RecipeScaler` (не литерал `$(AppIdentifierPrefix)…`)

---

## 2. Xcode (после портала)

На таргетах **RecipeScalerNative**, **ShareExtension**, **ActionExtension**:

1. **Signing & Capabilities** → **App Groups** → `group.ru.recipescaler.RecipeScaler`
2. **Keychain Sharing** → `ru.recipescaler.RecipeScaler` (Xcode допишет team prefix)

Детальный setup таргетов и smoke: `specs/025-share-extension/quickstart.md`.

---

## 3. Share / Action на iPhone

### Что блокировало без портала / при сломанном access group

- Extension читает `SharedAuthStore.token` (Keychain). Без общего **keychain-access-groups** main app и extension видят разные скоупы → `share-extension.error-not-signed-in`.
- App Group нужен для других shared IPC (snapshots и т.п.); **логин extension зависит от Keychain Sharing**.

### Device smoke (обязателен перед релизом)

Полный чеклист SC-001…SC-008 — в `specs/025-share-extension/quickstart.md` (Часть 2 / device). Кратко:

1. Логин в main app → Safari Share → extension **не** «не залогинен».
2. Импорт URL → «Открыть рецепт» → `recipe-scaler://recipe/{id}`.
3. Messages / Telegram / Photos / Safari Action.
4. Logout → Share показывает not-signed-in; offline → сетевая ошибка + Retry.

На **симуляторе** можно отлаживать UI и deep link; это **не заменяет** проверку на телефоне.

### Весь продукт

- Раздача сборки тестерам через **TestFlight**.
- Публикация в **App Store**.
- Любые **новые** App IDs / App Groups / Push / Associated Domains / iCloud — регистрация в портале под платной программой.

---

## 4. Порядок действий (portal → device)

1. Чеклист портала (§ 1) — App Group + Keychain Sharing на трёх App ID.
2. Xcode: три таргета, Signing без красных ошибок.
3. Установка на **свой iPhone** (не только симулятор).
4. Логин в app → убедиться, что `SharedAuthStore.token` записан (debug auto-login OK).
5. Share из Safari → extension видит сессию → импорт → «Открыть рецепт» / deep link.
6. Safari → Action «Импорт в Recipe Scaler».
7. Остальной smoke (Messages / Telegram / Photos / logout / offline).
8. При необходимости: TestFlight.

---

## 5. Заметки

- Бесплатная подпись: срок действия, лимит приложений/устройств; **extensions**, **App Groups** и **Keychain Sharing** — частые ошибки `Failed to register bundle identifier` / provisioning profile.
- Платный аккаунт не заменяет код в репозитории; он **включает** портал и профили под уже прописанные entitlements.
- Runtime access group в `SharedAuthStore` — `ZBPX4JYT24.ru.recipescaler.RecipeScaler` (макрос `$(AppIdentifierPrefix)` раскрывается только в entitlements XML).
- Сменили Bundle ID extension в Xcode — обновить этот файл и App IDs в портале.

**Связанные спеки**: `025-share-extension` (extensions, deep link), `023-push-notifications` (push — отдельно при релизе, **после Activity Charts**), `041-auth-device-tokens` (bearer в Keychain).

**Дата фиксации**: 2026-06-06; обновлено 2026-08-04 (платный аккаунт активен; Keychain Sharing + SharedAuthStore access group; device smoke checklist).
