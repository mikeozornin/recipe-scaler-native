# Спецификация: push-уведомления (APNs + таймеры)

**Ветка**: `023-push-notifications`  
**Дата**: 2026-06-04  
**Статус**: 🟡 В работе (~90% кода, аудит 2026-06-15) — регистрация APNs + schedule/cancel реализованы; QA на устройстве и toggle в Account pending. **Блокер**: device QA требует платный Apple Developer Account (см. [PAID-APPLE-DEVELOPER-REQUIRED.md](../../docs/PAID-APPLE-DEVELOPER-REQUIRED.md)); кодовая часть полностью готова.  
**Зависимости**: `014-timers-sync` ✅ (синк и UI таймеров), Phase 1 `TimerManager` (локальные UN)  
**Эталон**: PRD § Timers, `recipe-scaler-web/llm/ARCHITECTURE.md` § Timers And Push, `recipe-scaler-web/recipe-scaler/src/services/timer-service.ts`, `server/src/routes/push.ts`

## Аудит реализации (2026-06-15)

| Требование | Статус |
|------------|--------|
| US1 APNs registration | ✅ `PushRegistrationService` → `POST /api/push/apns-register`; `RecipeScalerNativeApp` delegate |
| US2 completion в фоне | 🟡 код есть; device QA pending |
| US3 reminder >30 мин | 🟡 серверная логика; клиент передаёт `duration_seconds` |
| US4 pause/delete/resume → cancel/schedule | ✅ `PushScheduleService` + хуки в `TimerManager` |
| US5 coexistence с локальными UN | ✅ дедуп в `TimerManager` |
| FR-PUSH-004 deep link | 🟡 через payload (проверить на device) |
| Toggle push в Account | ❌ вне v1 (см. `docs/DECISIONS.md`) |

Код: `PushRegistrationService.swift`, `PushScheduleService.swift`, контракт `contracts/timer-push-schedule.md`.

## Контекст

- **014** закрыта: кросс-девайс состояние таймеров, mobile `TimerPanel`, старт из описания. Локальные `UNUserNotification` при completion остаются на устройстве.
- **Веб** планирует server push через `POST /api/push/schedule` и `POST /api/push/cancel` при создании/изменении таймера; доставка сейчас через **Web Push (VAPID)** в `push_subscriptions`.
- **iOS** должен участвовать в том же контракте планирования на сервере и получать уведомления в фоне, когда приложение не на экране.

Перенос из 014: всё, что было «фаза пуши» / US3 / SC-push.

## Цель

1. Зарегистрировать iOS-устройство для доставки push (APNs token → бэкенд).  
2. При жизненном цикле таймера вызывать те же **schedule/cancel** API, что веб-клиент.  
3. Соблюдать **правила PRD** для reminder и completion (сервер уже реализует логику в `pushService.scheduleTimerNotifications`).

## Пользовательские сценарии

### US1 — Разрешение и регистрация (P1)

**Когда** пользователь впервые запускает таймер или открывает настройки уведомлений, **тогда** приложение запрашивает разрешение APNs, регистрирует token и привязывает к `userId` + `deviceId` (как auth/sync).

### US2 — Completion в фоне (P1)

**Когда** таймер >0 с завершился, приложение в фоне или закрыто, **тогда** приходит push «таймер завершён» (ru/en по языку приложения/аккаунта), tap открывает рецепт при наличии `recipe_id`.

### US3 — Reminder для длинных таймеров (P1)

**Когда** оставшаяся длительность при планировании **> 30 мин** (1800 с), **тогда** сервер планирует reminder за **2 мин** до конца + completion в конец (как `shouldScheduleReminder: duration_seconds > 1800` в `push.ts`).

### US4 — Pause / delete / resume (P1)

| Действие | iOS |
|----------|-----|
| Старт / create+start | `POST /api/push/schedule` с `duration_seconds` = оставшиеся секунды до `endTime` |
| Pause | `POST /api/push/cancel` для `timer_id` |
| Delete | `POST /api/push/cancel` |
| Resume | cancel → schedule с новым `duration_seconds` (оставшееся время); reminder не планируется, если осталось ≤120 с (логика сервера + явный флаг при необходимости) |

Паритет с `ARCHITECTURE.md`: `resume_timer` без reminder при ≤120 с до конца.

### US5 — Coexistence с локальными UN (P2)

**Когда** приложение на переднем плане, **тогда** локальный звук/UN Phase 1 допустимы; server push не должен дублировать completion дважды на одном устройстве (дедуп по `timer_id` / policy в `TimerManager`).

## Требования

### FR-PUSH-001 — APNs registration

- `UIApplication.registerForRemoteNotifications` после grant `UNUserNotificationCenter`.
- Token отправляется на бэкенд с `device_id` (тот же, что sync).  
- **Исследование**: сегодня `POST /api/push/subscribe` принимает только Web Push `endpoint` + `keys`. Для натива нужен **контракт APNs** (новое поле/роут или расширение subscribe) — зафиксировать в `contracts/apns-registration.md` на этапе plan.

### FR-PUSH-002 — Schedule / cancel API (таймеры)

Тело как у веб `timer-service.scheduleServerNotification`:

```json
{
  "timer_id": "<id>",
  "title": "<name>",
  "locale": "ru|en",
  "duration_seconds": <remaining>,
  "recipe_id": "<optional>"
}
```

- `POST /api/push/schedule` — при `createTimer`, `createAndStartTimer`, `resumeTimer` (после вычисления remaining).
- `POST /api/push/cancel` — при `pauseTimer`, `deleteTimer`.
- Офлайн: очередь schedule/cancel (аналогично `TimerSyncService`) или повтор при reconnect; не блокировать UI.

### FR-PUSH-003 — Правила reminder (сервер)

Не дублировать бизнес-логику на iOS: `duration_seconds > 1800` → сервер планирует reminder + completion (`push-service.scheduleTimerNotifications`). iOS передаёт актуальный remaining при каждом schedule.

### FR-PUSH-004 — Deep link

Payload push содержит `recipeId` / url — открыть `YDocRecipeDetailView` для рецепта.

### FR-PUSH-005 — i18n

Строки уведомлений — с сервера (как web push); клиент передаёт `locale` из настроек приложения.

## Вне scope

- Web Push / VAPID на iOS
- Push не про таймеры (маркетинг, discover, assistant) — отдельные подфичи позже
- Apple Watch, Live Activities (опционально позже)
- Изменение правил `timer_event` sync (014)

## Критерии успеха

- **SC-PUSH-001**: Таймер 35 мин, app в фоне → reminder ~за 2 мин до конца + completion push (два события на устройстве с APNs).
- **SC-PUSH-002**: Pause → push не приходит в запланированное время; resume с 5 мин остатка → только completion, без reminder.
- **SC-PUSH-003**: Таймер стартован на iOS → веб в фоне получает completion через Web Push (если подписан), без расхождения времени >10 с.
- **SC-PUSH-004**: Delete таймера отменяет pending server schedule.

## Артефакты (планируются)

- `plan.md` — APNs registration vs backend gap, `PushScheduleService` на iOS
- `contracts/apns-registration.md` — формат token + device_id
- `contracts/timer-push-schedule.md` — когда schedule/cancel, mapping `TimerManager` hooks
- `quickstart.md` — фон, два устройства, длинный/короткий таймер

## Связь с закрытыми спеками

| Было в 014 | Стало |
|------------|--------|
| US3 Background / push | US2–US4 здесь |
| SC-push | SC-PUSH-001…004 |
| `POST /api/push/schedule` | FR-PUSH-002 |