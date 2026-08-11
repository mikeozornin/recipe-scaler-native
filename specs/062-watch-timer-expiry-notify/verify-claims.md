# Verify Claims: spec 062 — watchOS expiry notification + Settings

**Спека**: [spec.md](./spec.md) | **План**: [plan.md](./plan.md)

Все claims falsifiable — это значит, что для каждого можно написать конкретный check (static, unit или manual), который либо проходит (claim подтверждён), либо падает (claim нарушен).

## Automated (static + unit)

### W1 — Settings снова в UI (static)

**Claim**: `SettingsRow()` вызов **не закомментирован** в обоих экранах.

**Verifier**: `scripts/verify-watch-timer-expiry-notify.sh`

```bash
rg -q '^\s*SettingsRow\(\)' RecipeScalerNativeWatch/Views/TimerListView.swift
rg -q '^\s*SettingsRow\(\)' RecipeScalerNativeWatch/Views/WatchStateScreenLayout.swift
# Дополнительно: ни в одном из них нет "// SettingsRow" в актуальной строке
rg -q '^\s*//\s*SettingsRow' RecipeScalerNativeWatch/Views/TimerListView.swift && exit 1 || true
```

### W2 — Scheduler существует (static)

**Claim**: Создан файл `WatchExpiryNotificationScheduler.swift` с типом `WatchExpiryNotificationScheduler` (`actor`).

**Verifier**:

```bash
test -f RecipeScalerNativeWatch/Services/WatchExpiryNotificationScheduler.swift
rg -q '^actor WatchExpiryNotificationScheduler' RecipeScalerNativeWatch/Services/WatchExpiryNotificationScheduler.swift
rg -q 'identifierPrefix = "watch-timer-"' RecipeScalerNativeWatch/Services/WatchExpiryNotificationScheduler.swift
rg -q 'identifierSuffix = "-complete"' RecipeScalerNativeWatch/Services/WatchExpiryNotificationScheduler.swift
```

### W3 — Prefs тип существует (static)

**Claim**: Создан `WatchExpiryNotificationsPrefs.swift` с `isEnabled`, `setEnabled`, `registerDefaults`, `didChangeNotification`.

**Verifier**:

```bash
test -f RecipeScalerNativeWatch/Services/WatchExpiryNotificationsPrefs.swift
rg -q 'static var isEnabled' RecipeScalerNativeWatch/Services/WatchExpiryNotificationsPrefs.swift
rg -q 'static func setEnabled' RecipeScalerNativeWatch/Services/WatchExpiryNotificationsPrefs.swift
rg -q 'static func registerDefaults' RecipeScalerNativeWatch/Services/WatchExpiryNotificationsPrefs.swift
rg -q 'didChangeNotification' RecipeScalerNativeWatch/Services/WatchExpiryNotificationsPrefs.swift
```

### W4 — i18n ключи в `Localizable.xcstrings` (static)

**Claim**: Все новые ключи присутствуют в `RecipeScalerNative/Resources/Localizable.xcstrings`.

**Verifier**:

```bash
XC="RecipeScalerNative/Resources/Localizable.xcstrings"
rg -q 'watch\.timer\.notification\.title' "$XC"
rg -q 'watch\.timer\.notification\.body' "$XC"
rg -q 'watch\.timer\.settings\.title' "$XC"
rg -q 'watch\.timer\.settings\.expiry-toggle\.label' "$XC"
rg -q 'watch\.timer\.settings\.expiry-toggle\.hint' "$XC"
rg -q 'watch\.timer\.settings\.notifications-disabled\.footnote' "$XC"
```

### W5 — Запрет `String(localized: "watch.timer.*")` (static)

**Claim**: В watch-коде нет запрещённого паттерна `String(localized: ...)` (паритета с `verify-timer-notifications.sh`).

**Verifier**:

```bash
if rg -n 'String\(localized: "watch\.timer\.' RecipeScalerNativeWatch/; then
  echo "FAIL: forbidden String(localized:) pattern in watch target" >&2
  exit 1
fi
```

### W6 — Unit-тесты scheduler существуют и проходят

**Claim**: `RecipeScalerNativeTests/WatchExpiryNotificationSchedulerTests.swift` содержит все тесты из data-model.md и проходит.

**Verifier**:

```bash
TM="RecipeScalerNativeTests/WatchExpiryNotificationSchedulerTests.swift"
test -f "$TM"
rg -q 'test_reconcile_schedules_for_active_timer' "$TM"
rg -q 'test_reconcile_skips_paused_timer' "$TM"
rg -q 'test_reconcile_skips_expired_timer' "$TM"
rg -q 'test_reconcile_skips_within_grace' "$TM"
rg -q 'test_pause_cancels_pending' "$TM"
rg -q 'test_delete_cancels_pending' "$TM"
rg -q 'test_cancelAll_removes_every_watch_timer_request' "$TM"
rg -q 'test_disabled_cancels_all_and_skips_scheduling' "$TM"
rg -q 'test_double_reconcile_single_pending_per_timer' "$TM"
rg -q 'test_reconcile_removes_orphan_pending' "$TM"
rg -q 'test_timerId_from_invalid_identifier_returns_nil' "$TM"

# Run
xcodebuild test ... -only-testing:RecipeScalerNativeTests/WatchExpiryNotificationSchedulerTests
```

### W7 — Watch target собирается

**Claim**: `xcodebuild build -scheme RecipeScalerNativeWatch` exit 0.

**Verifier**:

```bash
xcodebuild \
  -scheme RecipeScalerNativeWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
  -configuration Debug \
  build
```

### W8 — verify-скрипт сам зелёный

**Claim**: `bash scripts/verify-watch-timer-expiry-notify.sh` exit 0.

## Manual (simulator QA)

### W9 — Background notification (P1)

**Claim**: Таймер, запущенный с iPhone, при закрытом watch app вызывает haptic + карточку в течение 5 секунд после endDate на paired simulator.

**Procedure**: см. [quickstart.md](./quickstart.md) Сценарий 1.

### W10 — Toggle OFF подавляет всё

**Claim**: После выключения тумблера в Settings ни haptic, ни карточка не приходят.

**Procedure**: см. [quickstart.md](./quickstart.md) Сценарий 3.

### W11 — Pause отменяет уведомление

**Claim**: Pause таймера с часов после планирования отменяет pending request; никакого уведомления в endDate не приходит.

**Procedure**: см. [quickstart.md](./quickstart.md) Сценарий 4.

### W12 — Foreground haptic остаётся работать (регрессия spec 039)

**Claim**: При включённой настройке foreground haptic при окончании таймера проигрывается ровно один паттерн (3× notification).

**Procedure**: см. [quickstart.md](./quickstart.md) Сценарий 2.

---

Все W1–W8 обязательны для `VERIFIED`. W9–W12 — manual QA, не блокируют automated-гейт, но фиксируются в коммите к задаче / Linear issue.
