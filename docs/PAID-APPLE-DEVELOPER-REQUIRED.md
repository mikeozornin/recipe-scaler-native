# Платный Apple Developer Program — портал и device smoke

**Проект**: Recipe Scaler Native  
**Статус**: платный аккаунт **есть** (team `ZBPX4JYT24`). Device QA ✅: Share (025), push (023), LA (044/058), widget (030), Universal Links (059). Watch (039) — ⏸️ нет железа; TestFlight — по желанию.

Программа: [Apple Developer Program](https://developer.apple.com/programs/).

---

## Карта фич (актуально 2026-08-05)

Сверка по спекам + свежим коммитам (`c63ce83` APNs toggle, `4d29d9a` widget silent push, `f4c1983` LA→widget, `058` LA push, `374e705`/`ac96282` Universal Links, `42c5c47` Share, `19d7baf`+ watch).

| Фича | Spec | Код | Портал / entitlements | Device QA |
|------|------|-----|------------------------|-----------|
| **Alert + silent push (таймеры)** | [023](../specs/023-push-notifications/spec.md) | ✅ register + schedule/cancel + Account toggle | `aps-environment` на main (prod/debug); Push capability + APNs `.p8` на backend | ✅ alert push device QA 2026-08-05 |
| **LA local + Lock Screen Intent** | [044](../specs/044-timer-live-activity/spec.md) | ✅ ActivityKit + Intent → snapshot/widget | App Group на LA extension | ✅ вместе с 058 device QA |
| **LA push update/end** | [058](../specs/058-live-activity-push/spec.md) | ✅ client v1; server v1 (web) | Push на main; topic `…push-type.liveactivity` | ✅ Watch/web → LA на фоне, 2026-08-05 |
| **LA remote start** | 058 v2 | ❌ отдельно | то же + iOS 18+ | — |
| **Home Widget v1 UI** | [030](../specs/030-timer-widget/spec.md) | ✅ | App Group + Keychain на widget | ✅ device QA 2026-08-05 |
| **Widget background refresh** | 030 v2 | ✅ Phase A–B4 в коде (silent + Provider; WidgetKit push registrar iOS 26+) | Push на main (+ widget `aps-environment` development в repo) | ✅ LA→widget + silent/Provider 2026-08-05 |
| **Share / Action** | [025](../specs/025-share-extension/spec.md) | ✅ + Keychain Sharing / deep link fixes | App Group + Keychain на main/Share/Action | ✅ device smoke 2026-08-05 |
| **Universal Links** | [059](../specs/059-universal-links/spec.md) | ✅ + AASA на prod | Associated Domains `applinks:recipe-scaler.ru` | ✅ device QA 2026-08-05 |
| **watchOS timers** | [039](../specs/039-watchos-timers/spec.md) | ✅ companion v1 | App ID + App Group watch | ⏸️ нет Apple Watch у владельца — отложено |
| **TestFlight / App Store** | — | — | Distribution profiles | ⬜ по готовности smoke |
| Associated Domains / iCloud / Sign in with Apple (прочее) | — | UL только | по необходимости | — |

**Не блокер кода:** milestone «production push после Activity Charts / Live Activities» (DECISIONS 2026-06-08) **закрыт** — LA shipped; push capability включать и проверять сейчас.

---

## Идентификаторы (сверять с Xcode → Signing)

| Сущность | Значение |
|----------|----------|
| Team ID | `ZBPX4JYT24` |
| Main app | `ru.recipescaler.RecipeScaler` |
| Framework `RecipeScalerCore` | `ru.recipescaler.RecipeScaler.Core` |
| Share Extension | `ru.recipescaler.RecipeScaler.Share` |
| Action Extension | `ru.recipescaler.RecipeScaler.Action` |
| Home Widget | `ru.recipescaler.RecipeScaler.HomeWidget` |
| Timer Live Activity | `ru.recipescaler.RecipeScaler.TimerLiveActivity` |
| Watch app | `ru.recipescaler.RecipeScaler.watchkitapp` |
| **App Group** | `group.ru.recipescaler.RecipeScaler` |
| **Keychain access group** | `$(AppIdentifierPrefix)ru.recipescaler.RecipeScaler` → runtime `ZBPX4JYT24.ru.recipescaler.RecipeScaler` |

Entitlements в репо (должны совпасть с порталом):

| Файл | Capabilities |
|------|----------------|
| `RecipeScalerNative/RecipeScalerNative.entitlements` | App Groups, Keychain Sharing, **Push** (`aps-environment=production`), **Associated Domains** |
| `RecipeScalerNative/RecipeScalerNativeDebug.entitlements` | то же, `aps-environment=development` |
| `ShareExtension` / `ActionExtension` | App Groups + Keychain Sharing |
| `HomeWidgetExtension` | App Groups + Keychain + `aps-environment` |
| `TimerLiveActivityExtension` | App Groups + Keychain |
| `RecipeScalerNativeWatch` | App Groups + Keychain |

---

## 1. Apple Developer Portal (сверить / донастроить)

### 1.1 App Group

1. [Identifiers → App Groups](https://developer.apple.com/account/resources/identifiers/list/applicationGroup)
2. Identifier: `group.ru.recipescaler.RecipeScaler`
3. Description: например `Recipe Scaler — shared storage for extensions`

### 1.2 App IDs и capabilities

| Bundle ID | Capabilities |
|-----------|----------------|
| `ru.recipescaler.RecipeScaler` | App Groups; Keychain Sharing `ru.recipescaler.RecipeScaler`; **Push Notifications**; **Associated Domains** `applinks:recipe-scaler.ru` |
| `…Share` / `…Action` | App Groups + Keychain Sharing (**без** Associated Domains / без Push) |
| `…HomeWidget` | App Groups (+ Push, если нужен WidgetKit push token path) |
| `…TimerLiveActivity` | App Groups |
| `…watchkitapp` | App Groups |

Share/Action (025): креды (`SharedAuthStore.token` / `userId`) в **Keychain access group**, не в App Group UserDefaults.

### 1.2.1 Push / APNs (023 + 058 + 030 silent)

1. Main App ID → **Push Notifications** → On.
2. [Keys](https://developer.apple.com/account/resources/authkeys/list) → APNs key (`.p8`) → backend (`recipe-scaler-web`).
3. Topics (server):
   - alert / silent device: `ru.recipescaler.RecipeScaler`
   - Live Activity: `ru.recipescaler.RecipeScaler.push-type.liveactivity`
   - WidgetKit push (iOS 26+): `ru.recipescaler.RecipeScaler.push-type.widgets`
4. Debug builds → development APNs; Release/TestFlight → production.

### 1.2.2 Associated Domains (059)

1. Main App ID → Associated Domains → On.
2. Xcode: `applinks:recipe-scaler.ru` (уже в entitlements).
3. AASA: `GET https://recipe-scaler.ru/.well-known/apple-app-site-association` → 200, `application/json`, `appID` = `ZBPX4JYT24.ru.recipescaler.RecipeScaler`.

```bash
curl -sI https://recipe-scaler.ru/.well-known/apple-app-site-association
curl -s https://recipe-scaler.ru/.well-known/apple-app-site-association | jq .
```

Apple CDN может кэшировать AASA до ~1 суток.

### 1.3 Provisioning

Development (+ Distribution при TestFlight) для всех таргетов выше.  
Xcode: **Automatically manage signing**, team `ZBPX4JYT24`, без красных ошибок.

### 1.4 Распространение

- **TestFlight** — Share Sheet, extensions, push, чужие устройства.
- **App Store** — extensions внутри основного бинарника.

### 1.5 Проверка entitlements на бинарнике

```bash
codesign -d --entitlements :- /path/to/RecipeScalerNative.app
codesign -d --entitlements :- /path/to/RecipeScalerNative.app/PlugIns/ShareExtension.appex
```

Ожидается: App Group; `keychain-access-groups` с `ZBPX4JYT24.ru.recipescaler.RecipeScaler`; на main — `aps-environment` и Associated Domains.

---

## 2. Xcode

На **main / Share / Action** (минимум для 025):

1. App Groups → `group.ru.recipescaler.RecipeScaler`
2. Keychain Sharing → `ru.recipescaler.RecipeScaler`
3. Main: Push + Associated Domains

Детали Share: `specs/025-share-extension/quickstart.md`.  
Widget: `specs/030-timer-widget/quickstart.md`.

---

## 3. Device smoke — приоритеты

### ✅ Share / Action (025) — device QA 2026-08-05

Проверено: логин → Safari Share (сессия видна) → импорт → «Открыть рецепт»; Messages / Telegram / Photos / Safari Action; logout → not-signed-in.

### ✅ Alert push (023) — device QA 2026-08-05

Проверено: Profile toggle → permission → completion в фоне/killed; reminder / deep link / pause-cancel — по прогону пользователя.

### ✅ LA push (058) + local LA (044) — device QA 2026-08-05

Проверено: таймер → Lock Screen; pause/resume/delete с Watch/web при свёрнутом iPhone → карточка обновляется/исчезает без открытия app.

### ✅ Home Widget (030) — device QA 2026-08-05

Проверено: TimerWidget на Home/Lock; pause/resume с LA → виджет сразу; pause с веба/другого устройства при фоне app → подтягивание (silent/Provider).

### ✅ Universal Links (059) — device QA 2026-08-05

Проверено: Notes/Messages → `https://recipe-scaler.ru/public/@/{user}` (+ recipe) открывает app на Discover; cold start сохраняет навигацию.

### ⏸️ Watch (039) — отложено (нет Apple Watch)

Код companion v1 есть. Device QA на парных часах — когда появится железо или тестер с Watch. LA push с «другого устройства» уже проверен через веб (058).

### P2 — TestFlight

Сборка с production `aps-environment` + Distribution; smoke Share + push на чужом устройстве.

---

## 4. Порядок на ближайшие дни

1. TestFlight — по желанию / перед релизом.
2. Watch (039) device QA — когда будет Apple Watch.

---

## 5. Заметки

- Платный аккаунт не заменяет код; он открывает портал и профили под уже прописанные entitlements.
- Runtime Keychain group в `SharedAuthStore`: `ZBPX4JYT24.ru.recipescaler.RecipeScaler`.
- Смена Bundle ID → обновить этот файл и App IDs в портале.
- Исторический список «что можно было без платного» — [`NATIVE-FEATURES-NO-PAID-ACCOUNT.md`](NATIVE-FEATURES-NO-PAID-ACCOUNT.md) (архив).

**Связанные спеки**: `023`, `025`, `030`, `039`, `044`, `058`, `059`, `041` (bearer Keychain).

**Дата фиксации**: 2026-06-06; обновлено **2026-08-05** (аккаунт активен; push/LA/widget/UL/watch в карте; убрано «после Activity Charts»).
