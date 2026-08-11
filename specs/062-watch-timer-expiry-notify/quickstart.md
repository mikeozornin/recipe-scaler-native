# Quickstart: spec 062 — watchOS expiry notification + Settings

**Спека**: [spec.md](./spec.md) | **План**: [plan.md](./plan.md)

## Запуск watch app на paired simulator

```bash
# iPhone + Watch paired sim
bash scripts/run-dual-simulators.sh  # если есть
# Или вручную через Xcode: Run на RecipeScalerNativeWatch scheme,
# destination — "Apple Watch Series 11 (46mm) - iPhone Air" (paired).
```

## Сценарий 1 — background notification (P1)

1. Открой watch app → залогинься через iPhone (если ещё не).
2. С iPhone (или через web/curl) запусти таймер на 30 секунд.
3. Убедись, что watch app показал таймер в списке.
4. **Закрой watch app** (digital crown → home).
5. Жди ~30 секунд.
6. Watch должен завибрировать и показать карточку уведомления с названием таймера.
7. Тап по карточке → открывается watch app на списке.

## Сценарий 2 — foreground haptic (регрессия spec 039)

1. Открой watch app, запусти таймер на 30 с (с iPhone/web).
2. Оставайся на экране списка.
3. Через ~30 с — haptic-паттерн (3× `.notification`), карточка **не** показывается.

## Сценарий 3 — toggle OFF (P1)

1. Открой watch app → Settings (внизу списка).
2. Выключи тумблер «Haptics при окончании».
3. Закрой Settings, закрой watch app.
4. С iPhone запусти таймер на 30 с.
5. Жди ~30 секунд — должно быть **тихо**: ни haptic, ни карточки.

## Сценарий 4 — pause отменяет запланированное уведомление

1. Watch app открыт, активный таймер с endDate через 30 с.
2. Свайп влево от левого края по таймеру → pause.
3. Закрой watch app, подожди 60 секунд.
4. Никакого уведомления не приходит (paused → cancelled).

## Сценарий 5 — logout отменяет всё

1. Запусти таймер на час вперёд.
2. На iPhone выйди из аккаунта.
3. Watch app переходит в NotAuthorized.
4. Дождись endDate (можно через `xcrun simctl clock` для ускорения симулятора).
5. Никакого уведомления не приходит.

## Verify scripts

```bash
# Static + build + unit tests для spec 062
bash scripts/verify-watch-timer-expiry-notify.sh

# Регрессия spec 039
bash scripts/verify-watch-timers.sh

# i18n
bash scripts/lint-i18n.sh

# All
bash scripts/verify-all.sh
```

## Inspecting pending notifications (debug)

```swift
// В watch app коде (например, в TimerListViewModel.refresh после reconcile):
let center = UNUserNotificationCenter.current()
center.getPendingNotificationRequests { requests in
    let watch = requests.filter { $0.identifier.hasPrefix("watch-timer-") }
    print("Pending watch-timer requests: \(watch.map { $0.identifier })")
}
```

## Известные ограничения (P2/out of scope)

- Нет глубокого линка на конкретный рецепт по тапу (v2).
- Звук намеренно отключён.
- Hybrid-дедубликация с серверным push активируется только когда бэкенд 058 начнёт слать APNs на watch (см. plan.md STOP conditions).
