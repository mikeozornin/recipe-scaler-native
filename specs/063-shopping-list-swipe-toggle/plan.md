# План: свайп от левого края для отметки покупки

**Дата**: 2026-08-12
**Спека**: [spec.md](./spec.md)
**Ветка**: работа на `master` (AGENTS.md: small fixes на master; feature-ветки только для крупных specs). Изменение ~10 строк в одном файле + минорное расширение verify-скрипта.

> Канонический project template для Recipe Scaler Native. Артефакт пишется на
> русском.

## Границы

- **В scope**:
  - Добавить `.swipeActions(edge: .leading, allowsFullSwipe: true)` к строке списка покупок в `ShoppingListView.swift` (обе секции).
  - Действие кнопки вызывает уже существующий `handlePurchaseToggle(item:phase:)` (без дублирования логики staging/haptic/sync).
  - Визуал: `Button(role: nil)` с `systemName: "checkmark"`, `tint: .green` — паритет Apple Reminders.
  - Минорное расширение `scripts/verify-shopping-list-ui-polish.sh` одним assert-блоком.
- **Вне scope**:
  - Любые изменения в Y.Doc схеме, sync-событиях, контрактах с вебом.
  - Refactor существующего `.onDelete`/tap-to-check/inline-edit.
  - Исправление массового `extractionState: "stale"` в `Localizable.xcstrings` — это существующий техдолг, не относится к фиче.
  - Новые i18n-ключи (переиспользуем `shopping.mark-purchased` / `shopping.mark-not-purchased`).
- **STOP conditions**:
  - Если на iOS 17.0 leading swipeActions конфликтует с `.onDelete` (нестандартное поведение) — STOP и обсудить альтернативу.
  - Если `handlePurchaseToggle` ведёт себя отлично от tap-to-check при вызове из swipe (staging визуально ломается) — STOP.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | PASS | Мутация `checked` переиспользует существующий `syncService.setShoppingItemPurchased(id:purchased:)` → Y.Doc путь из 024. Новых полей/коллекций нет. |
| Web parity | PASS | iOS-only UX-ускорение ввода. Схема Y.Doc, Socket.IO события — без изменений. Веб-клиент не затрагивается. |
| Offline-first | PASS | Мутация идёт через `runShoppingMutation` → offline-queue. Паритет с tap-to-check (FR-007). |
| Native UI | PASS | `.swipeActions` — чистый SwiftUI, не WebView. Паритет с `RecipeListView.swift:425`. |
| Phased delivery | PASS | iOS-only UX polish, не требует sync/schema работ. Самостоятельно тестируемая единица. |
| i18n | PASS | Переиспользуем существующие ключи `shopping.mark-purchased`/`shopping.mark-not-purchased` из `Localizable.xcstrings:11206,11223`. Новых пользовательских строк нет. |
| Documentation | PASS | Sync/schema docs не меняются. Меняется только поведение UI-строки. |

## Очерёдность

1. **Прочитать существующий `handlePurchaseToggle` и `shoppingRow`** — почему первым: точка мутации и место вставки swipeAction; зависимости: нет.
2. **Добавить `.swipeActions(edge: .leading, allowsFullSwipe: true)` к `shoppingRow`** — зависит от 1; проверка `inlineEditItemId == item.id` для подавления жеста в edit-режиме (FR-008).
3. **Подавить leading swipe в inline-edit режиме** — зависит от 2; проверка через guard на `inlineEditItemId == item.id`.
4. **Расширить `verify-shopping-list-ui-polish.sh` одним assert-блоком** — зависит от 2; новый скрипт `sim_swipe` если нужно, или accessibility-based assert.
5. **Прогнать `xcodebuild build` + `verify-shopping-list-ui-polish.sh` + `lint-i18n.sh`** — фикс-until-green.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNative/Views/ShoppingListView.swift` | Изменить | Добавить `.swipeActions(edge: .leading, allowsFullSwipe: true)` к `shoppingRow` (линия ~310-344). Действие кнопки → `handlePurchaseToggle(item: item, phase: purchasePhase)`. В edit-режиме swipe подавляется. |
| `scripts/verify-shopping-list-ui-polish.sh` | Изменить | Добавить assert-блок: sim_swipe на первой строке to-buy → проверить, что пункт переехал в purchased (по accessibility или screenshot diff). |

## Downstream consumers

- **SwiftUI views**: `ShoppingListView` — единственный потребитель; `shoppingRow` используется и в `toBuy` и в `purchased` секциях.
- **Cross-process**: N/A — изменение в SwiftUI List row; widgets/watchOS/Live Activity/App Intents не обращаются к shopping row UI.
- **Sync boundaries**: N/A — Yjs/CRDT/web/сервер без изменений. Мутация через `syncService.setShoppingItemPurchased` (024).
- **Persisted state**: N/A — SQLite/Keychain/App Group без изменений. Offline-queue из 024 работает как есть.
- **Tests / verify scripts**: `scripts/verify-shopping-list*.sh` — три скрипта, должны остаться зелёными; расширяем только `ui-polish.sh`.

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| Full swipe от leading-края по строке в «Купить» | Строка проходит staging (~1с, haptic) и перезжает в секцию «Куплено» | `verify-shopping-list-ui-polish.sh:assert-leading-swipe-toggle` (новый) |
| Full swipe от leading-края по строке в «Куплено» | Строка возвращается в секцию «Купить» | `verify-shopping-list-ui-polish.sh:assert-leading-swipe-unmark` (новый) |
| Trailing swipe на той же строке | Показывается delete-кнопка из `.onDelete` (024); leading-toggle не активен одновременно | `verify-shopping-list-ui-polish.sh:assert-trailing-delete-coexists` (новый) |
| Inline-edit активен | Leading swipe suppressed, не мешает вводу текста | Manual (нельзя автоматизировать без UI-теста ввода) |
| Офлайн swipe | Мутация уходит в offline-queue, drain после реконнекта | Покрыто архитектурой 024; не требует нового теста |

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| `handlePurchaseToggle` staging Task | `purchasePhases[item.id]` | `purchasePhases[item.id] == .staging / .exiting` проверяется в самой функции (líneas 401, 404) | Идемпотентен через `purchasePhases.removeValue` | `guard purchasePhases[item.id] == .staging/.exiting else { return }` |
| `runShoppingMutation` | errorMessage state | N/A (одиночная await) | N/A — нет конкурирующих запросов на тот же id | N/A |

Single-flight guard: `purchasePhases` словарь уже действует как guard — повторный tap/swipe во время staging возвращается на первой линии `handlePurchaseToggle` (líneas 373-378).

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| logout | `purchasePhases` сбрасывается через `shoppingModel.recompute` на новый snapshot | In-flight staging Task завершается, проверка guard'ом не найдёт `.staging` → no-op | Offline-queue на синке из 024 продолжает drain при следующем логине | N/A | Нет зависших staging-фаз |
| account switch | Аналогично logout — snapshot меняется, recompute сбрасывает view-state | Аналогично | Аналогично | N/A | Аналогично |
| stale session / cold start | `purchasePhases` пустой при init | N/A | N/A | N/A | Стартовое состояние — пустое |
| reconnect / partial failure | `purchasePhases` unaffected; sync retry из 024 | staging Task продолжит | offline-queue drain из 024 | N/A | Мутация дойдёт через очередь |

## Cross-target contracts

- **Canonical owner**: `ShoppingListView.handlePurchaseToggle(item:phase:)` — единственная точка мутации для toggle.
- **Writer/reader targets**: только `ShoppingListView` (iOS app target). Widgets/Watch/App Intents не пишут `checked` через этот UI-путь.
- **Validator/normalizer**: `YjsSyncService.setShoppingItemPurchased` (из 024) — валидирует и нормализует перед записью в Y.Doc.
- **Raw literal exceptions**: N/A — нет UI-строк вне `Localizable.xcstrings`.

## Locale / theme consumers

- SwiftUI environment: `shopping.mark-purchased`/`shopping.mark-not-purchased` разрешаются через `Bundle.currentLocalizedString` (как существующий accessibility label, líñas 325-329).
- UIKit / notification categories: N/A — swipe action локален в SwiftUI List.
- Widgets / Live Activities / App Intents: N/A — не показывают shopping row.
- Cached or generated assets: N/A.
- `.system` effective value: tint swipe-кнопки — `Color.green` (system semantic), автоматически адаптируется под light/dark.

## Compatibility / migration

- Current format/contract: `shoppingList` Y.Doc (из 024) — без изменений.
- Previous supported format: N/A.
- Missing version/default behavior: N/A.
- Unknown future version/ID behavior: N/A.
- Required legacy fixture tests: N/A — нет форматов/контрактов.

## Unknown IDs and fallback policy

- DEBUG/CI: неизвестных scene/route нет — фича не вводит новые ID.
- Release: N/A — мутация ошибочного `item.id` обрабатывается существующим `runShoppingMutation` через `errorMessage`.
- Legacy aliases: N/A.

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app`/`.appex` assertion |
|----------|----------|---------------|----------------|---------------------------------|
| Новые ресурсы не генерируются | N/A | N/A | N/A | N/A |

## Human gates

- [x] `layout.md` reviewed by human — **N/A**: меняется только поведение строки, не вёрстка (см. spec.md: «Допущения», пункт про layout). Figma-driven UI gate не требуется.
- [x] `layout-audit.json` static audit passed — **N/A** (та же причина).
- [x] Human acceptance Artifact актуален — **N/A**.
- [ ] Отдельный review-agent выполнен; self-review не считается заменой — **ожидается после реализации; на этапе плана не требуется**.

> **Human gate для плана**: AGENTS.md требует human review плана перед tasks/implementation. Останавливаюсь здесь и жду явного «продолжай» перед `/speckit-tasks`.

## Verification

- `bash scripts/verify-plan-state.sh` — проверка консистентности plan/spec.
- `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16' build` — компиляция.
- `bash scripts/verify-shopping-list-smoke.sh` — sync + add flows из 024 должны остаться зелёными.
- `bash scripts/verify-shopping-list-ui-polish.sh` — расширен assert-блоком на leading swipe toggle.
- `bash scripts/lint-i18n.sh` — должно быть без новых предупреждений (новых ключей не добавляем).
- Expected: exit 0 на всех.

## Rollback / maintenance

- Как откатить: удалить блок `.swipeActions(edge: .leading) { ... }` из `shoppingRow` — код остаётся рабочим, tap-to-check продолжает работать.
- Что будет взаимодействовать в будущем: если добавят свайп-в-рецепт или другие жесты в List, нужно держать leading-edge reserved для shopping toggle (либо явно переработать mapping жестов).
- Временные allowlist/quarantine: нет.
