# Quickstart: TimerWidget (v2)

**Spec**: [030-timer-widget](./spec.md)
**Дата**: 2026-08-04

## Сборка

```bash
xcodebuild \
  -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

## Автоматическая проверка

```bash
bash scripts/verify-timer-widget.sh
```

Повтор без пересборки:

```bash
SKIP_BUILD=1 DERIVED_DATA=~/Library/Developer/Xcode/DerivedData/RecipeScalerNative-<hash> \
  bash scripts/verify-timer-widget.sh
```

### Seed snapshot на симуляторе (без UI)

```bash
SIM_UDID=$(xcrun simctl list devices booted -j | python3 -c "import sys,json; d=json.load(sys.stdin); print(next(i['udid'] for r in d['devices'].values() for i in r if i.get('state')=='Booted'))")
python3 scripts/seed-timer-snapshot.py "$SIM_UDID" four
python3 scripts/seed-timer-snapshot.py "$SIM_UDID" empty
python3 scripts/seed-timer-snapshot.py "$SIM_UDID" one
```

---

## Ручная проверка v1 (регрессия)

### 1. Home Screen виджет

1. Запустить app → создать таймер.
2. Home Screen → long-press → `+` → Recipe Scaler → TimerWidget `systemSmall`.
3. Живой countdown; empty / 1 / 2 / 3 / 4 layouts.

### 2. Lock Screen accessory + StandBy

Accessory circular/rectangular/inline — монохром; StandBy на iPhone 16 Pro.

### 3. Dark / Light + deep link

Тап по виджету → app на вкладке `.recipes`.

---

## Phase A QA — Live Activity pause → widget (US-A1)

**Цель:** pause/resume с Lock Screen Live Activity обновляет Home/Lock виджет **без** открытия app.

1. Добавить TimerWidget на Home Screen.
2. Запустить таймер из app → убедиться, что Live Activity на Lock Screen видна и виджет показывает running.
3. Увести app в background (`Cmd+Shift+H` на симе) или подождать suspend; **не** открывать app снова.
4. Lock Screen → нажать **Pause** на Live Activity.
5. Вернуться на Home Screen (**не** через icon app — через Home gesture / `Cmd+Shift+H`).
6. **Ожидание:** виджет показывает paused (время не тикает / фаза paused) в течение ~1 с.
7. Resume с Live Activity → виджет снова running с живым countdown.
8. После открытия app: SwiftData/sync/таймер-панель согласованы с виджетом (drain ActionQueue).

**Fail:** виджет остаётся running до ручного открытия app → Intent не пишет snapshot/reload (gap v1).

---

## Phase B QA — Web → widget (US-B1–B3)

**Требования:** физический iPhone предпочтительно; залогиненный user; виджет на Home Screen; app в background или force-quit. Primary path на iOS 17–25 — silent `content-available` + Provider fetch; WidgetKit `content-changed` — только когда клиент зарегистрирует widget token (SDK iOS 26+, future).

### B. Pause / resume с веба

1. На iPhone: активный таймер + виджет + Live Activity (опционально).
2. Force-quit или оставить app в фоне.
3. В браузере на [recipe-scaler.ru](https://recipe-scaler.ru) (тот же аккаунт) — Pause таймера.
4. **Ожидание (iOS 17–25, silent + Provider):** виджет обновляется best-effort после silent wake / timeline reload (или при следующем foreground). **WidgetKit push (SDK iOS 26+):** ~3–5 с при зарегистрированном widget token.
5. Resume в вебе → виджет снова running.

### B. Start / delete с веба

1. Start нового таймера в вебе → виджет добавляет ячейку (до 4).
2. Delete в вебе → ячейка исчезает; при нуле — empty «Таймеров нет».

### B. Offline (US-B3)

1. Airplane Mode на iPhone с уже заполненным виджетом.
2. Триггер reload (если возможно) или перезапуск timeline.
3. **Ожидание:** виджет **не** вспыхивает empty; остаётся последний snapshot.

### B. iOS 17–25 (silent + Provider, текущий primary)

На iOS 17–25 WidgetKit `WidgetPushHandler` / `.pushHandler` недоступен (SDK API — iOS 26+): после web-pause виджет обновляется через silent push (best-effort) + Provider `GET /api/v1/timers/active`, либо при следующем foreground. Зафиксировать результат в QA notes.

---

## Дебаг

| Симптом | Куда смотреть |
|---------|----------------|
| Виджет не в галерее | `HomeWidgetBundle` `@main`, iOS 17+ |
| Виджет пустой / не обновляется из app | `TimerSnapshotStore` App Group; `TimerManager` save+reload |
| Pause с LA не двигает виджет | Intent `perform()` — snapshot + `reloadTimelines` (Phase A) |
| Web pause не двигает виджет (iOS 17–25) | silent 023 path + Provider GET `/api/v1/timers/active`; ожидаемо best-effort |
| Web pause не двигает виджет (future WidgetKit push / SDK iOS 26+) | registrar token; server `widget_push_tokens`; APNs topic `…push-type.widgets` |
| Виджет обнулился offline | Provider clear на error — баг US-B3 |
| LA карточка ок, виджет нет (cross-device) | 058 ≠ 030: разные tokens/topics; проверить widget fan-out отдельно |

Логи (DEBUG): `bash scripts/pull-app-logs.sh` → `.debug-session.ndjson`. См. [llm/how-to-debug.md](../../llm/how-to-debug.md).

## Платный аккаунт / push

Платный Developer Program есть. Alert push — 023; Live Activity push — 058; **WidgetKit push — 030 v2** ([contracts/widget-push.md](./contracts/widget-push.md)).

Подробнее: [PAID-APPLE-DEVELOPER-REQUIRED.md](../../docs/PAID-APPLE-DEVELOPER-REQUIRED.md).
