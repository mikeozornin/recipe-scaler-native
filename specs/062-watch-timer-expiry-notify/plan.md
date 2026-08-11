# План: watchOS — уведомление об окончании таймера + настройка

**Дата**: 2026-08-11  
**Спека**: [spec.md](./spec.md)

> Канонический project template для Recipe Scaler Native. Артефакт пишется на
> русском. Для завершённых исторических планов обратная миграция не требуется.

## Границы

- **В scope**:
  - Возврат кнопки Settings (раскомментирование `SettingsRow` в `TimerListView` и `WatchStateScreenLayout`) + навигация на экран настроек.
  - Новый watch-экран `WatchSettingsView` с одним переключателем «Haptics при окончании» (default ON), состояние в `UserDefaults` `watchExpiryNotificationsEnabled`.
  - Новый watch-сервис `WatchExpiryNotificationScheduler` (actor): запрос разрешения, планирование/отмена `UNCalendarNotificationTrigger` per-таймер, очистка при logout.
  - Интеграция планировщика в `TimerListViewModel.refresh()` после применения `service.state` (reconcile pending requests ↔ current `endDate`-set).
  - Интеграция планировщика в `WatchTimerService.pause/resume/delete` paths (отмена на pause/delete, реплан на resume).
  - Интеграция переключателя с существующим foreground haptic (`TimerListViewModel.checkForExpirations`): при OFF haptic не играет.
  - i18n: новые ключи в `RecipeScalerNative/Resources/Localizable.xcstrings` — заголовок/тело уведомления, лейблы Settings UI, accessibility hints.
  - Verify-скрипт `scripts/verify-watch-timer-expiry-notify.sh`.
- **Вне scope**:
  - Серверный APNs push для watch (`timer_completed`) — зависимость от spec 058 / бэкенд, в этой спеке обрабатывается только **дедубликация** при наличии push (FR-010), но не регистрация/отправка.
  - Звук уведомления — явно исключён пользователем.
  - Глубокий линк на конкретный рецепт по тапу на уведомлении (v2).
  - Экран «отказал в разрешении → как включить» (просто показываем состояние тумблера; система сама блокирует delivery).
  - `WKExtendedRuntimeSession` для долгих фоновых задач — out of scope, локальная `UNCalendarNotificationTrigger` достаточна.
- **STOP conditions**:
  - Build watch-таргета красный → остановка, фикс по `fix-until-green`.
  - Verify-скрипт для spec 062 не зелёный → задача не закрыта.
  - Серверная APNs-инфраструктура для watch неготова → P2-функционал (hybrid) остаётся в коде за флагом, P1 считается готовым локально.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | Фича не трогает recipe data / Y.Doc. Таймеры — отдельный REST-канал (`/api/v1/timers/active`, `/api/v1/timers/sync`), уже не CRDT по дизайну spec 014/039. |
| Web parity | PASS | Web parity здесь = «бэкенд не требуется». Серверный fan-out для watch APNs отдельно (spec 058), эта спека локальная. Никаких изменений серверного контракта. |
| Offline-first | PASS | Локальная `UNCalendarNotificationTrigger` планируется на часах автономно. Если iPhone оффлайн или далеко — уведомление всё равно приходит. При отсутствии сети обновление `endDate` приходит при следующем sync; планировщик reconcile-ит состояние. |
| Native UI | PASS | `WatchSettingsView` — SwiftUI `List { Section { Toggle } }`. Никакого WebView. |
| Phased delivery | PASS | P1 (local notification + toggle) — независимо доставляемая польза. P2 (hybrid dedup с серверным push) — отдельный шаг, не блокирует P1. |
| i18n | PASS | Все UI-строки через `RecipeScalerNative/Resources/Localizable.xcstrings`. Запрос системного разрешения использует системную локализованную строку. |
| Documentation | PASS | Обновляется `AGENTS.md` (SPECKIT-секция), `spec.md` + этот `plan.md`. Новых контрактов в `docs/ARCHITECTURE.md` нет (локальная OS-функция). |

## Очерёдность

1. **`WatchExpiryNotificationsPrefs`** — тип-обёртка над `UserDefaults` (bool `watchExpiryNotificationsEnabled`, default ON). Почему первым: чистая synchronous dependency для всего остального.
2. **`WatchExpiryNotificationScheduler`** (actor) — `requestAuthorizationIfNeeded()`, `reconcile(timers:now:)`, `cancel(timerId:)`, `cancelAll()`, `handleForegroundExpiration(timerId:)`. Почему вторым: ядро фичи, нет UI-зависимостей.
3. **i18n-ключи** в `Localizable.xcstrings` (заголовок/тело нотификации, лейблы Settings, hints). Почему раньше кода UI: UI не должен хардкодить строки.
4. **`WatchSettingsView`** — экран с `Toggle`, навигация через `.navigationDestination` / `sheet` (по available API watchOS 10+).
5. **Раскомментировать `SettingsRow`** в `TimerListView` и `WatchStateScreenLayout`, повесить навигацию на `WatchSettingsView`.
6. **Интеграция scheduler в `TimerListViewModel`**: вызов `reconcile` в конце `refresh()`, `cancel(timerId:)` в pause/delete/optimistic paths, проверка `prefs.isEnabled` в `checkForExpirations`.
7. **Интеграция в `WatchCredentialsBridge`/logout path**: `cancelAll()` при purge userId. Отмена всех pending notifications.
8. **`UNUserNotificationCenterDelegate`** на watch app (опционально для P1: только если нужно подавить показ foreground banner — это и есть дедубликация с haptic, см. FR-008).
9. **Verify-скрипт** + unit tests для scheduler (mocked `UNUserNotificationCenter`).
10. **Manual QA** на paired simulator (iPhone+Watch): три сценария — foreground haptic, background notification, toggle off.
11. **P2 (опционально)**: серверная дедубликация — отмена локальной при получении remote `timer_completed` push. **Только если бэкенд готов**.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNativeWatch/Services/WatchExpiryNotificationsPrefs.swift` | Создать | Инкапсуляция `UserDefaults` bool + publisher для reactive UI. |
| `RecipeScalerNativeWatch/Services/WatchExpiryNotificationScheduler.swift` | Создать | Actor-владелец планирования/отмены `UNNotificationRequest`. |
| `RecipeScalerNativeWatch/Views/WatchSettingsView.swift` | Создать | Экран настроек с `Toggle`. |
| `RecipeScalerNativeWatch/Views/SettingsRow.swift` | Изменить | Заменить no-op `Button` на `NavigationLink`/`sheet` к `WatchSettingsView`. Сохранить haptic на tap. |
| `RecipeScalerNativeWatch/Views/TimerListView.swift` | Изменить | Раскомментировать `SettingsRow` (закомментирован ранее). |
| `RecipeScalerNativeWatch/Views/WatchStateScreenLayout.swift` | Изменить | Раскомментировать `SettingsRow`. |
| `RecipeScalerNativeWatch/Views/TimerListViewModel.swift` | Изменить | Добавить `scheduler` и `prefs`, вызывать `reconcile` в `refresh()`, `cancel(timerId:)` в pause/delete, проверять `prefs.isEnabled` в `checkForExpirations`. |
| `RecipeScalerNativeWatch/Services/WatchCredentialsBridge.swift` или `TimerListViewModel` init | Изменить | При purge userId вызывать `scheduler.cancelAll()`. |
| `RecipeScalerNativeWatch/App/RecipeScalerNativeWatchApp.swift` | Изменить | Установить `UNUserNotificationCenterDelegate` (если решаем foreground-дедубликацию через delegate). |
| `RecipeScalerNativeWatch/Info.plist` | (без изменений) | `NSUserNotificationsUsageDescription` для watchOS не требуется — `UNUserNotificationCenter.requestAuthorization` работает без plist-ключа. |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменить | Новые ключи (см. секцию i18n ниже). |
| `scripts/verify-watch-timer-expiry-notify.sh` | Создать | Static + build + unit-test + layout-audit checks для spec 062. |
| `specs/062-watch-timer-expiry-notify/verify-claims.md` | Создать | Falsifiable claims W1–Wn (см. секцию Verification). |
| `RecipeScalerNativeTests/WatchExpiryNotificationSchedulerTests.swift` | Создать | Unit-тесты reconcile/cancel/cancelAll логики с mock `UNUserNotificationCenter`. |

## Downstream consumers

- **SwiftUI views**: `TimerListView`, `WatchStateScreenLayout` (список и state-экраны) — снова потребляют `SettingsRow`. Новый `WatchSettingsView` — потребитель `WatchExpiryNotificationsPrefs`.
- **Cross-process**: widgets, extensions, watchOS, Live Activity, App Intents — `WatchExpiryNotificationScheduler` планирует local notifications в системе; iPhone Live Activity (spec 058) отдельно получает серверный push и не зависит от этой фичи. App Intents не затронуты.
- **Sync boundaries**: Yjs/CRDT, web, серверный contract — не затронуты. Никаких schema/protocol изменений. Если бэкенд в будущем начнёт слать `timer_completed` APNs на watch (P2), scheduler обработает это через `cancel(timerId:)` от push-handler.
- **Persisted state**: SQLite, SwiftData, UserDefaults, App Group, Keychain —新增 `UserDefaults` ключ `watchExpiryNotificationsEnabled` (watch-local, не App Group). `WatchCredentialsStore` (Keychain) не трогаем. Pending `UNNotificationRequest` — в системе, не в app state.
- **Tests / verify scripts**: новый `scripts/verify-watch-timer-expiry-notify.sh`; unit-тесты в `RecipeScalerNativeTests/WatchExpiryNotificationSchedulerTests.swift`; существующий `verify-watch-timers.sh` остаётся зелёным (мы расширяем, не ломаем).

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| Активный таймер с `endDate` через 30 с | После `refresh()` в `UNUserNotificationCenter.getPendingNotificationRequests` появляется запрос с `identifier = "watch-timer-<timerId>-complete"` и trigger-date = `endDate` | `WatchExpiryNotificationSchedulerTests/test_reconcile_schedules_for_active_timer` |
| Pause таймера | После `service.pause()` pending request с этим identifier исчезает | `WatchExpiryNotificationSchedulerTests/test_pause_cancels_pending` |
| Delete таймера | После `service.delete()` pending request с этим identifier исчезает | `WatchExpiryNotificationSchedulerTests/test_delete_cancels_pending` |
| Logout / userId = nil | `getPendingNotificationRequests` не содержит ни одного `watch-timer-*` | `WatchExpiryNotificationSchedulerTests/test_cancelAll_removes_every_watch_timer_request` |
| Toggle OFF в Settings | После переключения новые reconcile не планируют, старые pending отменяются | `WatchExpiryNotificationSchedulerTests/test_disabled_cancels_all_and_skips_scheduling` |
| Таймер уже истёк (`endDate <= now + grace`) | Reconcile НЕ планирует новый запрос (FR-007) | `WatchExpiryNotificationSchedulerTests/test_reconcile_skips_expired_timer` |
| Foreground haptic при foreground expiration при OFF | `WKInterfaceDevice.current().play(.notification)` НЕ вызывается | `TimerListViewModelExpiryDisabledTests/test_checkForExpirations_no_haptic_when_disabled` |
| Static: Settings снова в UI | `SettingsRow()` присутствует в `TimerListView.swift` и `WatchStateScreenLayout.swift` | `verify-watch-timer-expiry-notify.sh:assert-settings-row-present` |

Негативная формулировка «не должно сломаться» сама по себе недостаточна.

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| `scheduler.reconcile(timers:now:)` вызывается из `TimerListViewModel.refresh()` после `service.refresh()` | userId (epoch из `WatchCredentialsStore.userId`), snapshot of `timers` массива | После `await service.refresh()` проверяем что `WatchCredentialsStore.userId` не стал nil; после `await center.add(request)` не делаем повторных mutation без re-check reconcile-generation | `TimerListViewModel` (отменяется в `cancelAll` при logout); scheduler сам deduplicates по identifier | Concurrency test: два refresh() подряд → ровно один pending per timer |
| `scheduler.requestAuthorizationIfNeeded()` — async, дёргает `UNUserNotificationCenter.requestAuthorization` | userId на момент вызова | После await проверяем `await center.authorizationStatus()` (статус мог измениться в Settings) | WatchSettingsView lifecycle; повторяем при открытии экрана | Test: status `denied` → reconcile no-op |
| `scheduler.cancelAll()` при logout | userId до purge | sync операция (remove pending) — нет await | `WatchCredentialsBridge` callback | Test: после cancelAll pending list empty |
| `foregroundRefreshLoop()` (существующий) — sleep 15s → refresh | session epoch (`hasBootstrapped`, `WatchCredentialsStore.userId`) | После каждого sleep — `guard WatchCredentialsStore.userId != nil` (уже есть) | `Task.isCancelled` в условии `while` | Существующий тест в 039; не регрессирует |
| `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:)` — обработка foreground доставки | timerId из `userInfo` | sync callback | system | Test: при foreground deliver и `firedExpirations.contains(timerId)` → `.list` presentation option без звука |

Single-flight guard ставится до первого `await` и снимается через `defer`.

`WatchExpiryNotificationScheduler` — `actor`. Все мутации внутреннего `scheduled identifiers: Set<String>` идут через actor gate. Reconcile реализует single-flight через `reconcileGeneration: UInt64` — инкрементируется на старте, после `await` проверяем что generation не сменился.

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| logout (iPhone → WatchCredentialsBridge purge → userId nil) | `TimerListViewModel.firedExpirations` cleared; scheduler `scheduled` cleared | `foregroundRefreshLoop` task продолжает работать, но `guard userId != nil` (existing) → no-op до нового login | `UserDefaults.watchExpiryNotificationsEnabled` **не** сбрасывается (это UI-настройка, не session state) | `UNUserNotificationCenter.removePendingNotificationRequests` для всех `watch-timer-*` identifiers | `getPendingNotificationRequests` пуст, открывается `NotAuthorizedStateView`, при новом login reconcile стартует с нуля |
| account switch (logout → login под другим userId) | Аналогично logout + повторный `bootstrap()` | Аналогично | Настройка остаётся | Все старые pending удалены, новые запланированы после первого refresh под новым userId | После первого refresh под новым userId: pending set = ровно таймеры нового аккаунта |
| stale session / cold start | `hasBootstrapped=false`, `firedExpirations=[]` | `bootstrap()` в `.task` | `UserDefaults` intact | `getPendingNotificationRequests` может содержать orphan-запросы от прошлой сессии → первый `reconcile` их заменяет/отменяет | После `bootstrap` pending set = текущему таймер-сету; orphan-запросы на несуществующие timerId удалены через `removeDeliveredNotifications` reconcile-loop |
| reconnect / partial failure (network fail на `refresh`) | state остаётся `loaded` (previous good) | loop продолжает работу | Настройка intact | Pending requests не трогаются (последний known-good schedule остаётся) | При следующем успешном refresh reconcile приводит pending в соответствие с актуальным `endDate` (pause/resume с другого девайса мог поменять картину) |
| toggle OFF mid-session | prefs Publisher emits | `TimerListViewModel` подписан → `scheduler.cancelAll()` | `UserDefaults` updated | Все `watch-timer-*` removed | Ни новые, ни старые уведомления не придут; foreground haptic тоже отменён |
| permission denied системой | `authorizationStatus = .denied` | `requestAuthorization` rejected | prefs intact | `add(request)` тихо no-op (или кидает error — логируем через `AppLog`) | UI показывает тумблер, но уведомления не доставляются; Settings-экран показывает системную подсказку «включите в Watch settings» |

## Cross-target contracts

- **Canonical owner**: `WatchExpiryNotificationScheduler` — единственный, кто пишет в `UNUserNotificationCenter` для identifier-пространства `watch-timer-<timerId>-complete`. Никакой другой код в проекте не планирует notifications с этим prefix.
- **Writer/reader targets**: только watch app. iPhone `TimerManager` использует своё namespace (`<timerId>-complete`, без `watch-` prefix) — collision исключён.
- **Validator/normalizer**: scheduler валидирует `endDate > now + grace` (grace = 5s), иначе skip. Конвертация `Date` → `DateComponents` через `Calendar.current` (или фиксированный `gregorian` — см. Phase 1 research).
- **Raw literal exceptions**: prefix `"watch-timer-"` и suffix `"-complete"` — единственное место в коде, где эти строки собираются. Вынести в `Scheduler.identifier(for timerId:)` и `Scheduler.timerId(from identifier:)` для парсинга delivered notifications.

## Locale / theme consumers

- **SwiftUI environment**: `WatchSettingsView` наследует system locale через `@Environment(\.locale)` (неявно). `.appBody()` / `.appFootnote()` typography — согласно `docs/UI.md` (project typeface Martian).
- **UIKit / notification categories / scheduled content**: `UNMutableNotificationContent.title`/`.body` — локализуем через `Bundle.currentLocalizedString(key)` (тот же helper, что в `TimerManager.swift`). `Locale.current` берём из `Bundle.main.preferredLocalizations`, как везде в проекте. **Без** `String(localized:)` (запрещено verify-timer-notifications.sh и общим lint).
- **Widgets / Live Activities / App Intents**: не затронуты. iPhone Live Activity (spec 044/058) — отдельный channel.
- **Cached or generated assets**: нет новых ассетов. SF Symbol `gear` уже используется.
- **`.system` effective value**: `UNNotificationContent.sound = nil` (явно). Haptic при delivery управляется системой (`.notification` haptic по умолчанию для alert), либо кастомным `UNNotificationHapticFeedback` если доступен на watchOS — fallback на системный.

## Compatibility / migration

- **Current format/contract**: `UserDefaults` ключ `watchExpiryNotificationsEnabled` — новый. Нет предыдущей версии.
- **Previous supported format**: N/A.
- **Missing version/default behavior**: при отсутствии ключа возвращаем `true` (default ON — фича работает «из коробки»). Используем `UserDefaults.register(defaults:)` в `RecipeScalerNativeWatchApp.init()` для explicit default.
- **Unknown future version/ID behavior**: identifiers `watch-timer-<timerId>-complete` — если в будущем поменяем схему, старые orphan pending requests чистятся первым reconcile при новом login (он cancelAll → reconcile).
- **Required legacy fixture tests**: N/A — первая версия.

## Unknown IDs and fallback policy

- **DEBUG/CI**: unknown scene/route/manifest/server code → hard failure. Если `endDate` пустой или `timerId` malformed → `assertionFailure` + skip scheduling, логируем через `AppLog.error`.
- **Release**: safe user-facing state + structured log. Если `UNUserNotificationCenter.add` кидает ошибку → логируем, не падаем; пользователь просто не получит уведомление (foreground haptic всё ещё работает).
- **Legacy aliases**: explicit mapping в одном адаптере (`Scheduler.identifier(for:)` / `timerId(from:)`); prefix-based semantic fallback запрещён.

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app`/`.appex` assertion |
|----------|----------|---------------|----------------|---------------------------------|
| Новые i18n ключи в `Localizable.xcstrings` | Xcode project (`Resources` phase watch app copies `Localizable.xcstrings` из main app — проверить в build phases) | `RecipeScalerNative/Resources/Localizable.xcstrings` | Внутри `RecipeScalerNativeWatch.app` (если уже расшаривается) или дублируется в watch target — проверить в Phase 1 | `bash scripts/check-bundle-resources.sh` + `bash scripts/lint-i18n.sh` |
| SF Symbol `gear` | system | N/A | N/A | встроено в OS |

> **Phase 1 research**: проверить, как именно watch target сейчас получает доступ к `Localizable.xcstrings` — через shared build phase, через `Shared.xcstrings`, или дублированием. Это влияет на место для новых ключей.

## Human gates

- [ ] `layout.md` reviewed by human — **не требуется** для spec 062 (см. spec.md Assumptions: Settings — простой `List { Section { Toggle } }`, проходит через стандартный audit; Figma-макета нет).
- [ ] `layout-audit.json` static audit passed — не требуется (no Figma).
- [ ] Human acceptance Artifact актуален для hash `layout.md` — N/A.
- [ ] **Отдельный review-agent выполнен** (code-reviewer или security-review) перед merge; self-review не считается заменой. Триггер — после verify-скрипта зелёный, перед коммитом.
- [ ] Device QA (опционально, если есть Apple Watch у владельца): foreground haptic, background notification, toggle OFF — три сценария.

## Verification

- `bash scripts/verify-plan-state.sh` — контролирует, что active feature = `specs/062-watch-timer-expiry-notify` и `spec.md`/`plan.md` на месте. Ожидаемый stdout: `PLAN STATE: specs/062-watch-timer-expiry-notify`, exit 0.
- `xcodebuild -scheme RecipeScalerNativeWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build` — watch-таргет собирается. Exit 0.
- `xcodebuild test -scheme RecipeScalerNative -only-testing:RecipeScalerNativeTests/WatchExpiryNotificationSchedulerTests` — unit-тесты scheduler зелёные (mocked `UNUserNotificationCenter`). Exit 0.
- `bash scripts/verify-watch-timer-expiry-notify.sh` — comprehensive: static checks (presence `SettingsRow`, identifier-prefix, no `String(localized:)`, все ключи в xcstrings), watch build, unit tests. Exit 0.
- `bash scripts/lint-i18n.sh` — все новые ключи покрыты всеми поддерживаемыми локалями. Exit 0.
- `bash scripts/verify-watch-timers.sh` — существующая spec 039 регрессионно зелёная (мы расширяем, не ломаем). Exit 0.
- Expected evidence and exit codes: все скрипты exit 0; verify-watch-timer-expiry-notify.sh в конце печатает `[verify-062] All automated checks passed.`.

### Falsifiable claims (specs/062-watch-timer-expiry-notify/verify-claims.md)

- **W1** — В `TimerListView.swift` и `WatchStateScreenLayout.swift` `SettingsRow()` не закомментирован (rg).
- **W2** — В `RecipeScalerNativeWatch/` есть файл `WatchExpiryNotificationScheduler.swift` с типом `WatchExpiryNotificationScheduler` (`actor`).
- **W3** — В `Localizable.xcstrings` есть ключи `watch.timer.notification.title`, `watch.timer.notification.body`, `watch.timer.settings.title`, `watch.timer.settings.expiry-haptics-toggle`, `watch.timer.settings.expiry-haptics-hint`.
- **W4** — В проекте нет `String(localized: "watch.timer.notification.` или `String(localized: "watch.timer.settings.` (запрет pattern из verify-timer-notifications.sh).
- **W5** — `WatchExpiryNotificationSchedulerTests` содержит тесты: `test_reconcile_schedules_for_active_timer`, `test_pause_cancels_pending`, `test_delete_cancels_pending`, `test_cancelAll_removes_every_watch_timer_request`, `test_disabled_cancels_all_and_skips_scheduling`, `test_reconcile_skips_expired_timer`.
- **W6** — `verify-watch-timer-expiry-notify.sh` существует и exit 0.
- **W7** (manual) — На paired simulator (iPhone + Watch): запустить таймер на 30 с с iPhone, закрыть watch app, через ~30 с watch показывает карточку уведомления и вибрирует.
- **W8** (manual) — Settings → toggle OFF → закрыть app → завершить таймер → нет ни haptic, ни карточки.

## Rollback / maintenance

- **Как откатить**: revert коммита(ов) ветки `062-watch-timer-expiry-notify`. После revert — `SettingsRow` снова закомментировать (вручную или через cherry-pick первого коммита). Pending notifications в системе переживут uninstall/reinstall в рамках одной install-сессии, но при удалении app OS автоматически очищает pending requests — ручной cleanup не нужен.
- **Что будет взаимодействовать с изменением в будущем**:
  - spec 058 v2 — серверный push для watch: тот же `timerId` будет приходить через APNs; push-handler должен будет дёргать `scheduler.cancel(timerId:)` (и `firedExpirations.insert(timerId)` для haptic dedup). Сейчас оставлено место через FR-010.
  - watchOS major version bump — проверить, не депрекейтнули ли `UNCalendarNotificationTrigger` / `WKInterfaceDevice.play(.notification)`.
  - Future новые настройки в `WatchSettingsView` — добавлять новые Section/Toggle в тот же файл.
- **Временные allowlist/quarantine**: нет. Если unit-тесты на `UNUserNotificationCenter` окажутся нестабильны на CI (sandbox-ограничения), завести quarantine с owner=arch, reason=«CI sandbox blocks UNUserNotificationCenter mock», expiry=«следующий sprint» — до перехода на injection-friendly wrapper.

---

## Phase 0 — Research (поэтому — `research.md`)

Список NEEDS CLARIFICATION, которые нужно закрыть в `research.md` до Phase 1:

1. **Доступ watch-таргета к `Localizable.xcstrings`**: shared build phase? `Shared.xcstrings`? Дублирование? Влияет на место для новых ключей и на verify-скрипт.
2. **`UNUserNotificationCenter` на watchOS**: точные supported options (`.alert`/`.sound`/`.badge` — что из этого валидно на watchOS 10+), поведение `requestAuthorization` если пользователь отказал — можно ли обнаружить и отразить в UI.
3. **Foreground delivery suppression**: нужно ли реализовывать `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:)` на watch app, чтобы suppress duplicate banner когда foreground haptic уже отработал. Или достаточно не ставить `sound` + rely on system.
4. **`UNCalendarNotificationTrigger` vs `UNTimeIntervalNotificationTrigger`**: что надёжнее на watchOS для нашего use case (dateComponents vs seconds-from-now). Account for timezone.
5. **`WKInterfaceDevice.current().play(.notification)` поведение когда app в background**: действительно не вибрирует (подтвердить) — мотивация для local notification.

## Phase 1 — Design & Contracts (поэтому — `data-model.md`, `contracts/`, `quickstart.md`)

После Phase 0 — конкретные артефакты:

- `data-model.md`: схема `WatchExpiryNotificationsPrefs`, invariant scheduler identifier-space, state diagram для `reconcile` (state → desired pending set → diff → add/cancel).
- `contracts/notification-identifiers.md`: `watch-timer-<timerId>-complete` формат, regex для парсинга, владельцы prefix-пространства.
- `contracts/prefs-key.md`: `UserDefaults` ключ `watchExpiryNotificationsEnabled`, тип, default, owner.
- `quickstart.md`: как запустить watch app на paired simulator, как дёрнуть тестовый сценарий.

## Итоговая таблица артефактов Phase 1

| Артефакт | Статус после `/speckit-plan` |
|----------|------------------------------|
| `specs/062-watch-timer-expiry-notify/plan.md` | ✅ Этот файл |
| `specs/062-watch-timer-expiry-notify/spec.md` | ✅ (ранее) |
| `specs/062-watch-timer-expiry-notify/checklists/requirements.md` | ✅ (ранее) |
| `specs/062-watch-timer-expiry-notify/research.md` | 🟡 Создаётся в Phase 0 (после `/speckit-plan`, но до `/speckit-tasks`) |
| `specs/062-watch-timer-expiry-notify/data-model.md` | 🟡 Phase 1 |
| `specs/062-watch-timer-expiry-notify/contracts/*.md` | 🟡 Phase 1 |
| `specs/062-watch-timer-expiry-notify/quickstart.md` | 🟡 Phase 1 |
| `specs/062-watch-timer-expiry-notify/verify-claims.md` | 🟡 Phase 1 |
| `specs/062-watch-timer-expiry-notify/tasks.md` | 🟡 Создаётся через `/speckit-tasks` |
