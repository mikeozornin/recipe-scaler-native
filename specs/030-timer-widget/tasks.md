# Tasks: Home Widget — TimerWidget v2 (background updates)

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Contract**: [contracts/widget-push.md](./contracts/widget-push.md)

> Action-ориентированный checklist. **Сначала Phase A, потом Phase B.**  
> Статусы: `[ ]` todo, `[~]` in progress, `[x]` done, `[!]` blocked.  
> Не создавать `specs/059-*`. LA push — владение [058](../058-live-activity-push/spec.md).

---

## Phase A — Same-device Intent → snapshot (US-A1)

- [x] A.1. Найти `PauseRecipeTimerIntent` / resume Intent (grep `PauseRecipeTimerIntent`, `TimerLiveActivityActionQueue`)
- [x] A.2. Зафиксировать текущий gap: Intent только enqueue ActionQueue — без snapshot/reload
- [x] A.3. Добавить shared helper: обновить/смержить `TimerSnapshot` для `timerId` в `TimerSnapshotDocument` (load → patch → top-4 → save)
- [x] A.4. В `perform()` Pause: `Activity.update` (paused content-state) + helper save + `WidgetCenter.reloadTimelines(ofKind: "TimerWidget")` + **сохранить** ActionQueue enqueue
- [x] A.5. В `perform()` Resume: то же для running (`endDate`, phase)
- [x] A.6. Unit tests: после pause perform snapshot `phase == .paused`; ActionQueue не пустой; reload вызван (spy)
- [x] A.7. Unit tests: resume → `phase == .running`, `endDate != nil`
- [x] A.8. `xcodebuild test` green для новых тестов
- [ ] A.9. Device/sim QA: [quickstart.md](./quickstart.md) § «Phase A — Live Activity pause → widget» (app suspended) — manual / physical device; agent cannot close UI loop alone

---

## Phase B1 — Server widget tokens + fan-out

> Код server — в `recipe-scaler-web`. Здесь задачи для координации / зеркала контракта.

- [x] B1.1. Согласовать [contracts/widget-push.md](./contracts/widget-push.md) с web-командой (пути POST/DELETE)
- [x] B1.2. Migration: таблица `widget_push_tokens` (UNIQUE user_id+device_id)
- [x] B1.3. `POST /api/push/apns-register-widget` UPSERT
- [x] B1.4. `DELETE /api/push/apns-register-widget?device_id=`
- [x] B1.5. Fan-out widgets push на `timer_started|paused|resumed|updated|deleted`
- [x] B1.6. Debounce ~1 с; exclude source `device_id`
- [x] B1.7. Cleanup BadDeviceToken / Unregistered
- [x] B1.8. Server tests: register, exclude source, debounce
- [x] B1.9. Зеркало контракта в web specs (когда принято)

---

## Phase B2 — Client WidgetPushHandler + registrar (SDK iOS 26+)

- [x] B2.1. Проверить entitlements Push + App Group (не дублировать лишние capability без нужды)
- [x] B2.2. Реализовать registrar: hex → POST register с `device_id` (token source: future `WidgetPushHandler`; SDK `@available(iOS 26.0, *)`)
- [x] B2.3. Token rotation → повторный POST
- [x] B2.4. Unregister на logout / account wipe
- [x] B2.5. Wire в `AppContainer` / bootstrap рядом с 023 и 058 registrars
- [x] B2.6. Логирование через `AppLog` (английские event names)
- [x] B2.7. Unit tests registrar (mock APIClient)
- [x] B2.8. Сборка на deployment iOS 17: main app **и** HomeWidgetExtension DT **17.0**; `.pushHandler` **не** на `TimerWidget` (opaque config); handler-файл как reference; primary path = B3/B4 silent + Provider

---

## Phase B3 — TimerWidgetProvider network refresh

- [x] B3.1. В Provider: читать `SharedAuthStore` bearer
- [x] B3.2. `GET /api/v1/timers/active` (переиспользовать `ServerActiveTimer` / `ActiveTimersResponse` из Core)
- [x] B3.3. Map `ServerActiveTimer` → `TimerSnapshot` / document (см. [data-model.md](./data-model.md))
- [x] B3.4. `TimerSnapshotStore.save` перед построением timeline
- [x] B3.5. Offline / 401 / transport error → **не** clear; timeline из existing load
- [x] B3.6. Нет bearer → skip fetch, existing snapshot
- [x] B3.7. Unit tests: mapping running/paused/exceeded; offline keeps previous; no-auth no-clear
- [x] B3.8. `xcodebuild test` + `bash scripts/verify-timer-widget.sh`

---

## Phase B4 — iOS 17 silent fallback

- [x] B4.1. Server: silent `content-available` на device token 023 для устройств без widget token (или dual-send policy — зафиксировать в web)
- [x] B4.2. Client silent handler: sync active timers → snapshot save → `reloadTimelines`
- [x] B4.3. Не ломать alert push 023 (регрессия)
- [ ] B4.4. Manual QA на iOS 17 device/sim policy (best-effort)

---

## Phase V — Verify + docs

- [ ] V.1. Пройти [quickstart.md](./quickstart.md) Phase A и Phase B checklists на физическом iPhone
- [ ] V.2. Регрессия v1: foreground pause из app → widget; empty state; accessories
- [ ] V.3. Убедиться, что `layout.md` / `layout-audit.json` не переписаны без нужды
- [ ] V.4. Обновить статус в [spec.md](./spec.md) когда A+B done
- [x] V.5. Cross-link в [docs/PAID-APPLE-DEVELOPER-REQUIRED.md](../../docs/PAID-APPLE-DEVELOPER-REQUIRED.md) на 030 v2 widget push

---

## Вне scope (не брать в эти tasks)

- [ ] ~~Интерактивные pause на Home Widget~~
- [ ] ~~ShoppingListWidget~~
- [ ] ~~LA `event=start`~~ → 058 v2
- [ ] ~~Новый feature number 059~~
