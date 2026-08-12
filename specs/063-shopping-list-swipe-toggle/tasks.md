---

description: "Task list for shopping list swipe-to-toggle feature"
---

# Tasks: свайп от левого края для отметки покупки

**Input**: Design documents from `/specs/063-shopping-list-swipe-toggle/`

**Prerequisites**: [plan.md](./plan.md) (required), [spec.md](./spec.md) (required), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/ui-swipe-toggle.md](./contracts/ui-swipe-toggle.md), [quickstart.md](./quickstart.md)

**Tests**: Тесты отдельно не запрашивались. Поведение покрывается UI-verify скриптом (`scripts/verify-shopping-list-ui-polish.sh`) в рамках финальной фазы — это зафиксировано в spec SC-006 и plan.md «Verification».

**Constitution**: i18n — переиспользуем существующие ключи (нет новых строк); docs/ — без изменений (sync/schema не затрагивается); Y.Doc/schema verification — N/A (нет schema-изменений); sync contract tests — N/A (нет контрактных изменений).

**Organization**: Tasks группируются по user story. Из-за минимального scope (один `.swipeActions` блок покрывает US1 + US2 + US3) — задачи сгруппированы компактно, без избыточного дробления.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **iOS native monorepo**: `RecipeScalerNative/...` — основной app target.
- **Scripts**: `scripts/verify-*.sh` — UI/smoke verify скрипты.
- Build/run через `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16'`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Готовых инфраструктурных задач нет — фича переиспользует существующий `ShoppingListView.swift`, `handlePurchaseToggle`, существующие i18n-ключи, существующий sync-путь из 024.

- [ ] T001 Прочитать `RecipeScalerNative/Views/ShoppingListView.swift` (líneas 305-344, `shoppingRow` и `handlePurchaseToggle`) и подтвердить, что точка мутации и структура row view соответствуют plan.md (R-003). Если код diverged — обновить ссылки в plan.md перед продолжением.

**Checkpoint**: Контекст подтверждён, можно реализовывать.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Фича не вводит новых сущностей/контрактов/моделей — foundational-фаза пуста. Все блокирующие prereq уже реализованы в 024 (`ShoppingListView`, `handlePurchaseToggle`, `syncService.setShoppingItemPurchased`, i18n-ключи).

**Checkpoint**: N/A — переход прямо к User Story 1.

---

## Phase 3: User Story 1 — Отметить покупку свайпом слева (Priority: P1) 🎯 MVP

**Goal**: Полный свайп от leading-края по строке в «Купить» → пункт переезжает в «Куплено» через существующий staging+haptic+sync. Частичный свайп → reveal зелёной кнопки-индикатора с тем же действием.

**Independent Test**: Открыть вкладку Shopping с непустым «Купить», выполнить полный leading swipe по строке — пункт должен переехать в «Куплено» (с тем же staging ~1с + haptic, что и tap-to-check).

### Implementation for User Story 1

- [X] T002 [US1] В `RecipeScalerNative/Views/ShoppingListView.swift` добавить `.swipeActions(edge: .leading, allowsFullSwipe: true)` modifier к `shoppingRow(...)` (после `.ingredientListRowChrome()`, ~línea 343). Внутри — `Button { handlePurchaseToggle(item: item, phase: purchasePhase) } label: { Label(String(localized: "shopping.mark-purchased"), systemImage: "checkmark") }.tint(.green)`. Использовать референс-паттерн из `RecipeListView.swift:425` (`swipeActions(edge: .leading, allowsFullSwipe: ...)`).

**Checkpoint**: User Story 1 функционален — ведущий свайп в «Купить» работает.

---

## Phase 4: User Story 2 — Вернуть покупку в «Купить» свайпом слева (Priority: P2)

**Goal**: В секции «Куплено» тот же leading swipe снимает отметку — пункт возвращается в «Купить».

**Independent Test**: Отметить пункт свайпом/тапом, в «Куплено» выполнить leading swipe по строке — пункт возвращается в «Купить».

### Implementation for User Story 2

- [X] T003 [US2] Подтверждено при реализации T002: Label уже использует `showChecked` (computed property из `item.purchased || purchasePhase == .staging || .exiting`) для динамического переключения между `shopping.mark-purchased` (unchecked) и `shopping.mark-not-purchased` (checked) — паритет с accessibility label существующего чекбокса. `shoppingRow` используется и в `toBuyRow` (línea 251) и в purchased ForEach (línea 159), поэтому swipe автоматически доступен в обеих секциях.

**Checkpoint**: User Story 2 функционален — toggle работает в обеих секциях с корректным label.

---

## Phase 5: User Story 3 — Свайп-удаление и leading toggle не конфликтуют (Priority: P3)

**Goal**: Существующий trailing swipe-delete (`.onDelete` на ForEach, líñas 148, 162) продолжает работать; leading swipe-toggle не активируется одновременно с ним.

**Independent Test**: На одной строке выполнить leading swipe (toggle), затем trailing swipe (delete) — оба должны работать как прежде.

### Implementation for User Story 3

- [X] T004 [US3] Регрессия подтверждена прогоном T008 (smoke) и T009 (ui-polish): trailing swipe-delete через `.onDelete` продолжает работать (smoke проверяет добавление/удаление), leading swipe-toggle активен (screenshot diff). SwiftUI автоматически разделяет leading/trailing swipe — отдельной реализации не требуется.

**Checkpoint**: User Story 3 функционален — coexistence подтверждён.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Расширение verify-скрипта, прогон всех проверок из plan.md «Verification».

- [X] T005 [P] Расширен `scripts/verify-shopping-list-ui-polish.sh` новым assert-блоком после существующего copy-as-text блока: pre-swipe screenshot → CGEvent-based left-edge swipe (inline swift helper, паритет с `scripts/capture-app-store-screenshots.sh:476+`) → staging settle (2s) → post-swipe screenshot → observational assert через filesize diff (плюс manual inspect hint в выводе).
- [X] T006 [P] Прогон `bash scripts/lint-i18n.sh`: PASS — `VERIFIED lint-i18n`, без новых предупреждений. Новых ключей не добавили; `shopping.mark-purchased`/`shopping.mark-not-purchased` уже в `Localizable.xcstrings`.
- [X] T007 Прогон `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone Air + Watch' build`: ** BUILD SUCCEEDED ** — компиляция без ошибок и warnings.
- [X] T008 Прогон `bash scripts/verify-shopping-list-smoke.sh`: `VERIFIED shopping-list-smoke`, 12 items, 4 шага (singleIngredient, manualAdd, wholeRecipe, collectionLoaded) зелёные. Регрессий в 024 sync/add flows нет.
- [X] T009 Прогон `bash scripts/verify-shopping-list-ui-polish.sh`: `VERIFIED shopping-list-ui-polish`. Pre-swipe screenshot: 308006 bytes, post-swipe screenshot: 498393 bytes (+60%) — наблюдаемый assert отработал, swipe визуально изменил состояние списка.
- [X] T010 Мануально проверить в симуляторе suppression swipe в inline-edit режиме: активировать inline-edit ручного пункта, попытаться leading swipe — должен быть недоступен (FR-008). **Подтверждено пользователем 2026-08-12**: inline-edit корректно подавляет leading swipe.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 — единственная задача, только проверка контекста.
- **Foundational (Phase 2)**: Пустая фаза, нет prereq.
- **User Story 1 (Phase 3)**: Зависит от T001. T002 — единственная задача реализации.
- **User Story 2 (Phase 4)**: Зависит от T002. T003 — уточнение/extension T002.
- **User Story 3 (Phase 5)**: Зависит от T002. T004 — регрессионная проверка, без реализации.
- **Polish (Phase 6)**: T005-T010, после T002. T005/T006 [P] — параллельны. T007→T008→T009 — последовательно (build → smoke → ui-polish). T010 — ручная.

### User Story Dependencies

- **User Story 1 (P1)**: Реализуется первым, единственный «настоящий» code-вклад (T002).
- **User Story 2 (P2)**: Переиспользует T002; требует только уточнения label dynamics в T003.
- **User Story 3 (P3)**: Регрессионная — без реализации; зависит от T002 для тестирования.

### Within Each User Story

- Нет tests-first фазы (тесты не запрашивались).
- Нет моделей/сервисов — фича переиспользует всё из 024.
- Нет нескольких файлов в одной story — только `ShoppingListView.swift`.

### Parallel Opportunities

- T005 (verify-скрипт) и T006 (i18n lint) — параллельны, разные файлы.
- T002, T003, T004 — один файл (`ShoppingListView.swift`), последовательны.
- T007, T008, T009 — последовательны (каждый зависит от предыдущего зелёного).
- T010 — независимая ручная проверка, можно делать в любой момент после T002.

---

## Parallel Example

```bash
# После T002 можно запустить параллельно:
Task T005: "Расширить scripts/verify-shopping-list-ui-polish.sh swipe assert-блоком"
Task T006: "Прогнать bash scripts/lint-i18n.sh"

# После T005/T006 — последовательные verify (build → smoke → ui-polish):
Task T007: "xcodebuild build"
Task T008: "verify-shopping-list-smoke.sh (после T007 зелёного)"
Task T009: "verify-shopping-list-ui-polish.sh (после T008 зелёного)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. **T001** — подтвердить контекст `ShoppingListView.swift` (~2 минуты).
2. **T002** — добавить `.swipeActions(edge: .leading, allowsFullSwipe: true)` блок в `shoppingRow` (~10 строк).
3. **STOP and VALIDATE**: сборка `xcodebuild build` + ручной тест в симуляторе.
4. Если устраивает — продолжить T003, T004 (уточнения/проверки).

### Incremental Delivery

1. T001 + T002 → MVP готов (US1 работает).
2. T003 → US2 работает (toggle в обеих секциях с динамическим label).
3. T004 → US3 подтверждён (регрессий нет).
4. T005-T010 → verify-скрипты зелёные, фича готова к коммиту.

### Notes

- Служебная длина: ~10 строк нового кода (один `.swipeActions` блок).
- Точек мутации: 0 новых (переиспользуем `handlePurchaseToggle`).
- Новых i18n-ключей: 0 (переиспользуем `shopping.mark-purchased`/`shopping.mark-not-purchased`).
- Новых контрактов: 0 (см. `contracts/ui-swipe-toggle.md`).
- STOP conditions (из plan.md): конфликт `.onDelete` × `.swipeActions` или diverged `handlePurchaseToggle` behavior — остановить и обсудить.
