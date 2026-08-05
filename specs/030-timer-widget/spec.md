# Спецификация: Home Widget — TimerWidget (v2)

**Ветка**: `030-timer-widget` (работа на `master` допустима для doc/v2-slice)
**Дата**: 2026-08-04
**Статус**: ✅ DONE (2026-08-05) — v1 UI + v2 background (Intent→snapshot, silent push, Provider) + **device QA**
**Версия**: **v2** (background widget updates)
**Зависимости**:
- [014-timers-sync](../014-timers-sync/spec.md) ✅ DONE
- [023-push-notifications](../023-push-notifications/spec.md) ✅ DONE
- [044-timer-live-activity](../044-timer-live-activity/spec.md) ✅ DONE
- [058-live-activity-push](../058-live-activity-push/spec.md) ✅ v1 DONE
- [039-watchos-timers](../039-watchos-timers/spec.md) 🟡 companion (`GET /api/v1/timers/active`, `ServerActiveTimer`)

## Цель

**v1 (достигнуто):** показывать активные таймеры на Home Screen и Lock Screen через WidgetKit (`StaticConfiguration`), с живым отсчётом через `Text(timerInterval:)` — grid 2×2 + accessory families.

**v2 (этот документ):** обновлять Home/Lock виджет, когда main app **не активен**:

1. **Same-device (Phase A):** pause/resume с кнопки Live Activity на Lock Screen → виджет сразу отражает новое состояние (без ожидания `TimerManager`).
2. **Cross-device (Phase B):** pause/resume/start/delete с веба (или другого устройства), пока iPhone app в фоне/убит → виджет обновляется через silent `content-available` + Provider fetch (iOS 17–25, текущий primary); WidgetKit `content-changed` push — когда клиент сможет зарегистрировать widget token (SDK API iOS 26+, без поднятия appex DT выше 17).

## Источники макетов

Figma `rVzFwMDS5SECfIq4HRLHya` (без изменений в v2 — layout остаётся read-only):
- `107:207` — Timer light (Home Screen `systemSmall`)
- `107:266` — Timer dark
- `107:332` — Timer monochrome (Lock Screen / StandBy accessory)

Детали: [layout.md](./layout.md) · [layout-audit.json](./layout-audit.json).

---

## Пользовательские сценарии v2

### US-A1 — Pause/resume с Live Activity сразу обновляет виджет (P0, Phase A)

**Когда** пользователь нажимает Pause (или Resume) на карточке Live Activity Lock Screen,  
**тогда** Home Screen / Lock Screen `TimerWidget` в течение ~1 с показывает paused (или running) состояние того же таймера — даже если main app suspended и `TimerManager` ещё не обработал `TimerLiveActivityActionQueue`.

**Сегодня (баг / gap):** `PauseRecipeTimerIntent` / resume Intent только ставят событие в `TimerLiveActivityActionQueue` (Darwin). Пока app не проснётся, snapshot в App Group и timeline виджета **не** меняются.

**Требование:** в `perform()` Intent'а дополнительно:
1. `Activity.update(...)` для Live Activity content-state;
2. запись в `TimerSnapshotStore` (App Group);
3. `WidgetCenter.shared.reloadTimelines(ofKind: "TimerWidget")`;
4. **сохранить** enqueue в `TimerLiveActivityActionQueue` — для последующего drain `TimerManager` (SwiftData + sync).

### US-B1 — Pause/resume с веба обновляет виджет при фоне/killed app (P0, Phase B)

**Когда** пользователь ставит таймер на паузу или возобновляет его в вебе, а iPhone app в фоне или убит,  
**тогда** в течение ~3–5 с Home/Lock виджет отражает новое состояние.

### US-B2 — Start / delete с веба (P1, Phase B)

**Когда** с веба создают новый активный таймер или удаляют существующий,  
**тогда** виджет добавляет / убирает соответствующую ячейку (топ-4, empty state при нуле).

### US-B3 — Offline Provider не ломает виджет (P1, Phase B)

**Когда** WidgetKit reload срабатывает без сети (или `SharedAuthStore` без валидного bearer),  
**тогда** Provider оставляет **существующий** snapshot из App Group; не показывает spurious empty и не падает.

---

## Решения v1 (сохранены)

- **Только TimerWidget** в этой фиче. ShoppingListWidget — вне scope.
- **Read-only**: `StaticConfiguration`, без интерактива на Home Widget. Тап → deep link в app.
- **Все плейсменты**: `systemSmall` + `accessoryCircular` / `accessoryRectangular` / `accessoryInline`.
- **Живой отсчёт** через `Text(timerInterval:)`.
- **Унифицированный цвет** по состоянию (`normal` / `soon` / `exceeded`).
- **Semantic colors** + шрифты Martian (`AppFonts`).
- **Target** `HomeWidgetExtension` (отдельно от `TimerLiveActivityExtension`).

## Решения v2

### R1 — Intent пишет snapshot сам (same-device)

`PauseRecipeTimerIntent` / `ResumeRecipeTimerIntent` (и аналоги) в `perform()` **обязаны** обновить:
- Live Activity (`Activity.update`);
- `TimerSnapshotStore` (тот же mapping, что `TimerManager` → snapshot);
- `WidgetCenter.reloadTimelines(ofKind: "TimerWidget")`.

Очередь `TimerLiveActivityActionQueue` **остаётся** — единственный канал для `TimerManager` → SwiftData + `TimerSyncService`, когда app проснётся. Intent **не** заменяет drain очереди.

### R2 — WidgetKit push (iOS 26+ SDK) как будущий primary cross-device путь

Apple `WidgetPushHandler` / `.pushHandler` — **`@available(iOS 26.0, *)`** (исторический текст спеки «iOS 18+» был неточен).

На устройствах с зарегистрированным widget token:

| Параметр | Значение |
|----------|----------|
| `apns-push-type` | `widgets` |
| `apns-topic` | `ru.recipescaler.RecipeScaler.push-type.widgets` |
| Body | `{ "aps": { "content-changed": true } }` |

Клиент (когда wire-up возможен без поднятия appex DT): `WidgetPushHandler` + registrar **device-level** token (не per-timer, в отличие от LA tokens в 058).  
**Текущий native клиент:** HomeWidgetExtension и main app остаются на **deployment iOS 17**. `.pushHandler` **не** прикреплён к `TimerWidget` (opaque `WidgetConfiguration` + DT 17). Референс-handler есть в коде; включение — future dual-target / type-erasure. До этого primary update path на клиенте — **R3 + R4**.  
Сервер: таблица `widget_push_tokens`; register/unregister; fan-out рядом с LA events (`timer_started` / `paused` / `resumed` / `updated` / `deleted`); debounce ~1 с; **exclude source device**.

Контракт: [contracts/widget-push.md](./contracts/widget-push.md).

### R3 — Silent push + Provider fetch на iOS 17–25 (текущий primary)

Deployment target main app и HomeWidgetExtension — **iOS 17**.

На iOS 17–25 (и на любом устройстве без widget token): silent `content-available: 1` на **существующий** device APNs token (spec 023) → app sync → `TimerSnapshotStore.save` → `WidgetCenter.reloadTimelines`, плюс Provider `GET /api/v1/timers/active` при reload (R4). Best-effort: OS может не разбудить app; при следующем foreground виджет всё равно догонит.

### R4 — Provider fetch при reload

`TimerWidgetProvider` при `getTimeline` / push-triggered reload:

1. Читает `SharedAuthStore` (App Group bearer).
2. `GET /api/v1/timers/active` (контракт 039 / `ServerActiveTimer`).
3. Маппит → `TimerSnapshotDocument` → пишет App Group.
4. Строит timeline из свежего (или при ошибке/offline — из предыдущего) snapshot.

Виджет **не** мутирует таймеры на сервере (read-only).

### R5 — Не дублировать LA push (058)

Server v1 для Live Activity `update`/`end` уже в 058. Эта спека **не** переописывает LA push payload / `liveactivity_tokens`. Widget fan-out — **параллельный** канал рядом с LA events.  
`event=start` для Live Activity — **вне scope 030**; см. 058 v2.

### R6 — Home Widget остаётся без кнопок pause

Интерактивные кнопки pause на Home Widget — **вне scope**. Pause/resume на Lock Screen — только через Live Activity Intent (Phase A).

---

## Унифицированный цвет (правило дизайнера)

| Состояние | Цвет всех элементов | Условие |
|-----------|---------------------|---------|
| `normal` | `labels/primary` (semantic `.label`) | remaining ≥ 10% duration |
| `soon` | `accents/orange` → системная `.orange` | remaining < duration/10 |
| `exceeded` | `accents/red` → `Color(red: 0.98, green: 0.153, blue: 0.188)` | remaining < 0 |

**Исключения** (всегда монохром `labels/primary`):
- Empty state «Таймеров нет»
- Accessory families — без цветных акцентов

## Семейства виджетов

| Family | Размер | Layout |
|--------|--------|--------|
| `systemSmall` | 169×169 | Grid 2×2, состояния 0/1/2/3/4 |
| `accessoryCircular` | ~52×52 | Ring + одна цифра (минуты) |
| `accessoryRectangular` | ~160×72 | Name + `Text(timerInterval:)` |
| `accessoryInline` | 1 строка | `Text(timerInterval:) — name` |

## Состояния `systemSmall`

| Таймеров | Layout |
|----------|--------|
| 0 | Empty: «Таймеров нет» центрировано |
| 1 | 1 кольцо (62pt) + 2 строки с названием рецепта |
| 2 | 2 row: прогресс-бар (linear) + имя + время справа |
| 3 | Grid 2×2, занято 3 ячейки, 4-я пустая |
| 4 | Grid 2×2, занято 4 ячейки |

> Больше 4 активных таймеров → топ-4 по приоритету (ближайший к концу → превышенный → остальные).

## Deep links

- `recipe-scaler://home` (TimerWidget) → main app, вкладка `.recipes`.
- `recipe-scaler://shopping` (будущий ShoppingListWidget).

## Timeline policy

**v1 (сохраняется):**
- Backgrounding app → `WidgetCenter.shared.reloadAllTimelines()`.
- Мутация в `TimerManager` → reload kind `TimerWidget`, debounce 200 мс.
- Fallback в Provider: `.atEnd(after: now + 15min)`.

**v2 (добавляется):**
- Intent `perform()` → snapshot + reload (US-A1).
- Silent push (iOS 17–25) → app wake → sync → snapshot → reload + Provider fetch (US-B*).
- WidgetKit push `content-changed` (SDK iOS 26+, когда token wire-up без DT 26) → system reload → Provider fetch.

---

## Вне scope

| Тема | Куда |
|------|------|
| Интерактивные pause-кнопки на Home Widget | будущий spec (не 030) |
| ShoppingListWidget | отдельная итерация |
| Recipe / pinned-recipes widget | отдельный spec |
| Live Activity `event=start` через push | [058 v2](../058-live-activity-push/spec.md) |
| Переспецификация LA push `update`/`end` | уже [058](../058-live-activity-push/spec.md) |

> ~~Push-обновления виджета (APNs) — после платного аккаунта~~ — **снято в v2**: платный аккаунт есть; WidgetKit push + silent fallback — **в scope**.

---

## Критерии успеха

### v1 (регрессия — не ломать)

- Запущенный таймер → виджет на Home Screen с живым countdown.
- Empty state когда нет активных таймеров.
- Pause/delete из **foreground** app → виджет обновляется.
- Сборка `RecipeScalerNative` + `HomeWidgetExtension` green на симуляторе.
- Accessory families + dark/light.

### v2 (новые)

- **US-A1:** Pause с Live Activity при suspended app → виджет показывает paused без открытия app.
- **US-B1–B2:** Pause/resume/start/delete с веба при фоне/killed → виджет обновляется best-effort на iOS 17–25 (silent + Provider); WidgetKit `content-changed` — когда клиент зарегистрирует widget token (SDK iOS 26+).
- **US-B3:** Offline / нет auth → виджет сохраняет последний snapshot.
- Deployment target **iOS 17** (main app **и** HomeWidgetExtension); WidgetKit push API только за `#available(iOS 26, *)` и без поднятия appex DT.
- Register/unregister widget push token (server + registrar ready); серверный fan-out с debounce ~1 с и exclude source device.
- Контракт [contracts/widget-push.md](./contracts/widget-push.md) согласован с web-зеркалом (когда появится).

## Артефакты

| Файл | Назначение |
|------|------------|
| [plan.md](./plan.md) | Архитектура + шаги A→B + Downstream / invariants |
| [data-model.md](./data-model.md) | Snapshot + widget push token + network refresh |
| [contracts/widget-push.md](./contracts/widget-push.md) | Register API + APNs headers/payload |
| [tasks.md](./tasks.md) | Упорядоченные задачи для implementers |
| [quickstart.md](./quickstart.md) | Сборка + device QA |
| [layout.md](./layout.md) | Figma layout (v1, без rewrite в v2) |
