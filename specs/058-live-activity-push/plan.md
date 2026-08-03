# Plan: Live Activity Push Updates

**Date**: 2026-08-03 | **Spec**: [spec.md](./spec.md)
**Server twin**: `recipe-scaler-web/specs/058-live-activity-push/spec.md`

---

## Очерёдность

1. **Server DB + token store + routes** — регистрация работает до того, как iOS начнёт слать tokens
2. **Server APNs liveactivity send + fan-out hook** (после 1) — можно тестировать curl → APNs
3. **iOS: pushType `.token` + register/unregister** (в параллель с 2 после контракта) — tokens появляются в БД
4. **Device QA** iPhone + Watch / web pause (после 2+3)
5. **Account deletion wipe** `liveactivity_tokens` (после 1; можно в параллель с 3)
6. **Widget silent push** — **не** в этой спеке; см. **[030-timer-widget v2](../030-timer-widget/spec.md)** (не «будущая 059»)
7. **v2 `event=start`** (iOS 18+, remote create LA) — после стабилизации v1; см. [spec.md § v2](./spec.md)

---

## 1. Server: DB + token store + routes

### Изменения

| Файл | Действие |
|------|----------|
| Supabase SQL / migration | Создан: `liveactivity_tokens` |
| `server/src/services/apns-service.ts` (или `liveactivity-token-store.ts`) | Методы save/remove/getTokens |
| `server/src/routes/push.ts` | POST + DELETE `/apns-register-liveactivity` |
| `server/src/__tests__/…` | Unit: upsert, delete idempotent, get excludes device |

### Downstream consumers

- [ ] **iOS `PushRegistration`-like client** — будет POST/DELETE (шаг 3)
- [ ] **TimerSyncService fan-out** — читает tokens (шаг 2)
- [ ] **AccountDeletionService** — wipe по user_id (шаг 5)
- [ ] **Persisted state** — новая таблица; FK/CASCADE или явный delete

### Positive invariants

| Эффект | Инвариант | Где |
|--------|-----------|-----|
| POST register | row exists with latest token for (user, device, timer) | unit test |
| DELETE | row gone; second DELETE still 200 | unit test |
| getTokens(exclude) | source deviceId отсутствует в результате | unit test |

---

## 2. Server: APNs liveactivity + TimerSync fan-out

### Изменения

| Файл | Действие |
|------|----------|
| `apns-service.ts` | `sendLiveActivityUpdate` — topic, push-type, content-state dates as Unix sec |
| `timer-sync-service.ts` | после `emitToUser` — debounce → build state → push |
| recipe name helper | collection Y.Doc + `findRecipeEntry`, cache 60s |
| `__tests__/…` | mock APNs; assert exclude source; end on delete; unconfigured no-op |

### Downstream consumers

- [ ] **ActivityKit on device** — применяет content-state (device QA)
- [ ] **Web Push / alert APNs** — не должны сломаться (отдельный path)
- [ ] **WebSocket timer_event** — остаётся primary для foreground clients

### Positive invariants

| Эффект | Инвариант | Где |
|--------|-----------|-----|
| `timer_paused` from A | APNs called for B's token with `phase=paused` | unit |
| `timer_deleted` | APNs `event=end` | unit |
| `!isConfigured` | zero APNs calls, WS still emitted | unit |
| recipeId present | `recipeName` string when collection has entry | unit |

---

## 3. iOS: Activity push token lifecycle

### Изменения

| Файл | Действие |
|------|----------|
| `TimerLiveActivityCoordinator.swift` | `pushType: .token`; observe `pushTokenUpdates`; register/unregister |
| New thin service e.g. `LiveActivityPushRegistrar.swift` | POST/DELETE HTTP |
| `AppContainer.swift` | DI wiring |
| Tests | coordinator registers on request; unregister on end (mock URLProtocol) |

### Downstream consumers

- [ ] **Live Activity UI** — local update path unchanged
- [ ] **Server token table** — заполняется
- [ ] **Watch / web mutations** — начинают доезжать через push (после шага 2)
- [ ] **App Group / intents** — не трогаем

### Positive invariants

| Эффект | Инвариант | Где |
|--------|-----------|-----|
| `Activity.request` success | POST register invoked with timerId + deviceId | unit/integration |
| `end(timerId)` | DELETE unregister invoked | unit |
| Token rotation from stream | second POST with new token | unit |

---

## 4. Device QA

См. [quickstart.md](./quickstart.md) (создать на шаге 4).

- SC-001…SC-006 из spec.md
- Логи сервера: `[APNs]` liveactivity success
- `APNS_PRODUCTION=false` для debug-сборки

### Downstream / invariants

Device QA is the gate; no code change expected unless topic/payload mismatch.

---

## 5. Account deletion wipe

### Изменения

| Файл | Действие |
|------|----------|
| `account-deletion-service.ts` | DELETE FROM liveactivity_tokens WHERE user_id |
| `055` acceptance / test | assert table empty after delete |

### Positive invariants

| Эффект | Инвариант | Где |
|--------|-----------|-----|
| delete-account | no rows in liveactivity_tokens for user | account-deletion test |

---

## Verify

### Native
- `xcodebuild build` — scheme `RecipeScalerNative`
- Unit: LiveActivity push registrar / coordinator hooks
- Manual: iPhone + Watch SC-001…003

### Server
- `bun test` — push / timer-sync / account-deletion affected files
- `bun run typecheck` on server
- Manual: register token → pause from web → Lock Screen updates

### Docs
- FEATURE-MAP web: строка 058
- `docs/PAID-APPLE-DEVELOPER-REQUIRED.md` — отметить Live Activity push как разблокированный после APNs
