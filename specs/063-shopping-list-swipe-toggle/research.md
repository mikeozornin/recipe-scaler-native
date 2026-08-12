# Research: свайп от левого края для отметки покупки

**Дата**: 2026-08-12
**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)

Phase 0 research. Все неизвестные разрешены из существующей кодовой базы и канонических SwiftUI patterns.

---

## R-001: SwiftUI API для leading swipe в List row

**Вопрос**: Какой SwiftUI API использовать для leading swipe-to-toggle, и какой порог (full/partial) он даёт «из коробки»?

**Decision**: `.swipeActions(edge: .leading, allowsFullSwipe: true)` — нативный SwiftUI modifier (iOS 15.0+).

**Rationale**:
- Это стандартный API для swipe-actions в `List` row; проект уже использует его в `RecipeListView.swift:425` (`swipeActions(edge: .leading, allowsFullSwipe: false)` для add-to-shopping).
- `allowsFullSwipe: true` даёт поведение FR-010: полный свайп через весь ряд автоматически коммитит; частичный только reveal кнопку.
- SwiftUI обрабатывает «отмену жеста возвратом пальца» автоматически — ничего дополнительно кодировать не нужно (clarification Q2).

**Alternatives considered**:
- `DragGesture` + кастомный offset: отвергнут — дублирование работы SwiftUI, регрессия accessibility, несовместимость с `.onDelete`.
- `UIScreenEdgePanGesture`: отвергнут — UIKit API, ломает SwiftUI-декларативность.

---

## R-002: Сосуществование с существующим `.onDelete` (trailing swipe)

**Вопрос**: Можно ли добавить `.swipeActions(edge: .leading)` к строке, у которой уже есть `.onDelete(perform:)` на родительском `ForEach`?

**Decision**: Да, сосуществуют. Apple явно документирует: `.onDelete` добавляет trailing swipe, а `.swipeActions(edge: .leading)` добавляет ведущий — они не конфликтуют и активируются каждый со своей стороны.

**Rationale**:
- В `ShoppingListView.swift:148,162` `ForEach` использует `.onDelete(perform:)` — это trailing swipe-delete из 024.
- Leading `.swipeActions` вешается на `shoppingRow` (отдельная `@ViewBuilder` функция, строка 306) — на уровне самой row view.
- SwiftUI различает trailing (от `.onDelete`) и leading (от `.swipeActions`) — это разные edges, активируются строго по направлению свайпа.

**Alternatives considered**:
- Переписать `.onDelete` на явный `.swipeActions(edge: .trailing)`: отвергнуто — refactor выходит за scope фичи, риск регрессии 024.

---

## R-003: Переиспользование точки мутации `handlePurchaseToggle`

**Вопрос**: Можно ли вызвать тот же обработчик, что и у tap-to-check, чтобы staging/haptic/sync-логика не дублировалась?

**Decision**: Да. `handlePurchaseToggle(item:phase:)` в `ShoppingListView.swift:372` — единая точка; вызывается из `Button.action` в `shoppingRow` (línea 315). SwipeAction будет вызывать её с теми же аргументами.

**Rationale**:
- Функция уже реализует всё необходимое: staging в `purchasePhases[item.id] = .staging` (línea 398), haptic через `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator` (líneas 384-386), sync через `syncService.setShoppingItemPurchased` (línea 407).
- Idempotent guard на líneas 373-378: если `phase` уже `.staging`, повторный tap/swipe — no-op.
- FR-006 выполнено автоматически.

**Alternatives considered**:
- Дублировать логику в action swipe-кнопки: отвергнуто — нарушение DRY, рассинхрон с tap-to-check.

---

## R-004: i18n-ключи — переиспользование vs новые

**Вопрос**: Заводить ли новые ключи `shopping.action.mark-purchased`/`shopping.action.unmark-purchased` (как зафиксировано в FR-009 после clarify Q3), или переиспользовать существующие?

**Decision**: **Переиспользовать** существующие `shopping.mark-purchased` и `shopping.mark-not-purchased`.

**Rationale**:
- В `ShoppingListView.swift:325-329` accessibility-label существующего чекбокса уже использует именно эти ключи.
- Они уже есть в `Localizable.xcstrings:11206, 11223` (со всеми переводами).
- FR-011 (a11y-консистентность) уже выполнен — чекбокс и swipe-кнопка автоматически будут озвучиваться одинаково.
- Заводить новые `shopping.action.*` дублировало бы строки и нарушило инвариант «a11y-описание отметки покупки одинаковое по всему экрану».

**Девиация от clarify Q3**: пользователь в Q3 выбрал вариант B с двумя ключами и заметил: «желательно сделать вместе с Accessibility у чекбоксов». Анализ кода показал, что **a11y у чекбоксов уже использует подходящие ключи** — следовательно, семантически вариант B уже реализован. Заводить дублирующие `shopping.action.*` было бы антипаттерном.

> Это нужно явно подсветить пользователю в Completion Report как уточнение к спеке. Спеку НЕ меняю (он уже согласован), но план фиксирует переиспользование с обоснованием.

**Alternatives considered**:
- Завести новые ключи `shopping.action.*`: отвергнуто — дублирование, нарушение принципа «одна строка = одна семантика».
- Заменить существующие ключи на новые `shopping.action.*`: отвергнуто — выходит за scope, сломает существующий tap-to-check.

**Note про `extractionState: "stale"`**: Xcode пометил многие ключи (включая `shopping.mark-purchased`) как `stale`, несмотря на активное использование. Это существующий техдолг (mass-effect), не относится к данной фиче. Xcode автоматически обновит `extractionState` на следующем билде; в рамках плана мы не трогаем это, чтобы не раздувать diff.

---

## R-005: Подавление swipe в inline-edit режиме (FR-008)

**Вопрос**: Как подавить leading swipe, когда строка в режиме inline-edit (`inlineEditItemId == item.id`)?

**Decision**: В `toBuyRow` (líneas 245-266) уже есть ветвление: в edit-режиме рисуется `inlineEditRow` (без swipe), иначе `shoppingRow`. Поскольку swipe action будет жить внутри `shoppingRow`, в edit-режиме он автоматически недоступен — дополнительных guard не нужно.

**Rationale**: `inlineEditRow` (línea 268) — отдельная `HStack` с `TextField`, не имеющая `.swipeActions`. SwiftUI автоматически не активирует swipe-actions для строки, где они не объявлены.

**Alternatives considered**:
- Условный `.swipeActions` только при `inlineEditItemId != item.id`: не нужно, т.к. edit-row не имеет swipe-actions.
- Глобальный guard в action: не нужно,ActionTypes в edit-row не доходит.

---

## R-006: Цвет/иконка действия

**Вопрос**: Какой именно system color и symbol использовать для зелёной галочки?

**Decision**: `Color.green` + `systemName: "checkmark"` внутри `Button { ... } label: { Label(...) }`. Tint кнопки — `.green` через `.tint(.green)` на самой кнопке.

**Rationale**:
- `Color.green` — system semantic, корректно адаптируется под light/dark и accessibility.
- `checkmark` — стандартный SF Symbol для «отметить», паритет с Reminders/Mail.
- Tint `.green` на кнопке автоматически красит swipe-reveal-фон и иконку — стандартный SwiftUI behaviour.

**Alternatives considered**:
- `Color.accentColor`: отвергнут — не совпадает с Apple Reminders-стилем (clarify Q1/Q3 выбрали именно зелёную галочку).
- Кастомный asset color: отвергнут — избыточно для одной кнопки.

---

## R-007: Расширение verify-скрипта

**Вопрос**: Как добавить assert на leading swipe в `verify-shopping-list-ui-polish.sh` без сильного refactor?

**Decision**: Добавить новый блок после существующего copy-as-text блока (líneas 49-85), используя `sim_swipe` или accessibility-based assertion.

**Rationale**:
- В скрипте уже используется паттерн `sim_launch -SkipSplash=1 -OpenTab=shopping ... sim_screenshot ... assert`.
- Для swipe потребуется либо `simctl` drag gesture через `xcrun simctl ui <udid> swipe ...`, либо accessibility-based проверка через `simctl` accessibility server.
- Точная команда уточнится в implementation phase — это технический detail, не блокирующий план.

**Alternatives considered**:
- Новый отдельный скрипт `verify-shopping-list-swipe-toggle.sh`: отвергнут в clarify Q4 (расширяем существующий).
- Только ручная проверка: отвергнут — нарушит SC-006.

---

## Итог Phase 0

Все неизвестные разрешены. Конституционная проверка пройдена по всем 7 gates. Можно переходить к Phase 1 (data-model, contracts, quickstart).
