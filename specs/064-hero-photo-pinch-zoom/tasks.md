---

description: "Task list for hero photo pinch-to-zoom feature"
---

# Tasks: pinch-to-zoom для hero-фотографий рецепта

**Input**: Design documents from `/specs/064-hero-photo-pinch-zoom/`

**Prerequisites**: [plan.md](./plan.md) (required), [spec.md](./spec.md) (required).

**Tests**: Автотесты на pinch-жест не реализуемы (XCUITest не поддерживает multi-touch pinch на iOS 17). Покрытие — build-green + ручная проверка через Simulator (Option + drag), зафиксировано в spec SC-001 … SC-007 и plan.md «Verification».

**Constitution**: i18n — новых пользовательских строк нет (FR-017); docs/ — без изменений (sync/schema не затрагивается); Y.Doc/schema verification — N/A (нет schema-изменений); sync contract tests — N/A (нет контрактных изменений).

**Organization**: Tasks группируются по user story. Фича минимальна (один новый файл + 2 точки вызова), поэтому много фаз не заводим; STOP-gate после T002 (MVP) для проверки на симуляторе перед расширением.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

- **iOS native monorepo**: `RecipeScalerNative/...` — основной app target.
- **Scripts**: `scripts/verify-*.sh` — UI/smoke verify скрипты (фича не расширяет их — новых жест-скриптов нет).
- Build/run через `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16'`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Подтвердить контекст до реализации — что точки вызова и структура cached-image-view'ов соответствуют плану.

- [ ] T001 Прочитать `RecipeScalerNative/Views/RecipeCachedImageView.swift` (líneas 96-111, `heroImageBody`) и `RecipeScalerNative/Views/PublicCachedImageView.swift` (líneas 60-74, `heroImageBody`). Подтвердить, что структура совпадает с plan.md (ZStack с Color + Image, `.aspectRatio`, `.frame(maxHeight:)`, `.clipped()`). Если код diverged — обновить ссылки в plan.md перед продолжением.

**Checkpoint**: Контекст подтверждён, можно реализовывать модификатор.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Создать переиспользуемый модификатор — фундамент для обеих точек вызова.

- [ ] T002 [US1,US2] Создать `RecipeScalerNative/Views/HeroPhotoPinchZoom.swift` с `HeroPhotoPinchZoomModifier: ViewModifier` и `extension View { func heroPhotoPinchZoom(isEnabled: Bool = true) -> some View }`. Реализовать:
  - `@GestureState private var zoom: CGFloat = 1.0` для текущего масштаба.
  - `@State private var dimOpacity: Double = 0` для анимируемой прозрачности dim.
  - `MagnifyGesture().minimumScaleDelta(0.05)` + `.updating(_:body:)` с clamp в диапазоне `1.0 … 2.5`.
  - `.scaleEffect(zoom, anchor: .center)` на `content`.
  - `.overlay { Color.black.opacity(dimOpacity).ignoresSafeArea().allowsHitTesting(false) }` — затемнение, не перехватывает касания.
  - `.onChange(of: zoom)` → `withAnimation(.smooth(duration: 0.15)) { dimOpacity = newValue > 1.001 ? 0.45 : 0 }`.
  - `.onEnded` → `withAnimation(.smooth(duration: 0.25)) { dimOpacity = 0 }` (zoom сбросится автоматически через `@GestureState`).
  - `isEnabled: Bool = true` — если `false`, `.gesture(nil)` и `.scaleEffect(1)`, модификатор no-op.
  - Добавить `#Preview` с тестовым `UIImage` (можно `Image(systemName: "photo")` в `ZStack` с цветным фоном) для проверки в Xcode Canvas.

**STOP-GATE**: После T002 — `xcodebuild build` + быстрый sanity-check в Xcode Canvas, что модификатор компилируется и preview рендерится. Только потом переходить к T003.

**Checkpoint**: Модификатор готов, но не подключён к продакшен-views.

---

## Phase 3: User Story 1 — Рассмотреть фото своего рецепта (Priority: P1) 🎯 MVP

**Goal**: В `YDocRecipeDetailView` (карточка своего рецепта) pinch на hero-фото увеличивает его в диапазоне 1.0× … 2.5× с появлением dim-overlay; после release возвращается к 1.0×.

**Independent Test**: Открыть свой рецепт с фото, выполнить pinch (Option + drag в Simulator) на hero — фото увеличивается, фон затемняется, после release возвращается.

### Implementation for User Story 1

- [ ] T003 [US1] В `RecipeScalerNative/Views/RecipeCachedImageView.swift` добавить `.heroPhotoPinchZoom(isEnabled: uiImage != nil)` к `heroImageBody` (líneas 96-111) **после** `.clipped()` (línea 110). Параметр `isEnabled: uiImage != nil` подавляет pinch пока фото грузится / отсутствует (FR-013).
- [ ] T004 [US1] Проверить edit-mode: открыть свой рецепт в edit-mode с фото, выполнить pinch → убедиться, что delete-button (`xmark` в `.bottomTrailing`, `RecipeDetailImageSection.swift:58-67`) остаётся на месте и кликабельна (FR-011). Если ProgressView overlay (`isUploading || isDeleting`, líenas 72-76) пробивается pinch'ем — добавить параметр `pinchZoomEnabled` в `RecipeCachedImageView` и пробросить из `RecipeDetailImageSection` со значением `!(isUploading || isDeleting)` (FR-012).

**Checkpoint**: User Story 1 функционален — pinch работает на hero своего рецепта, edit-mode не сломан.

---

## Phase 4: User Story 2 — Рассмотреть фото публичного рецепта в Discovery (Priority: P1)

**Goal**: В `DiscoverRecipeView` (Discovery) pinch на hero работает идентично US1 — тот же модификатор.

**Independent Test**: Открыть любой публичный рецепт в Discovery с фото, выполнить pinch — поведение идентично US1.

### Implementation for User Story 2

- [ ] T005 [US2] В `RecipeScalerNative/Views/PublicCachedImageView.swift` добавить `.heroPhotoPinchZoom(isEnabled: uiImage != nil)` к `heroImageBody` (líneas 60-74) **после** `.clipped()` (línea 73). Аналогично T003.

**Checkpoint**: User Story 2 функционален — pinch работает на hero Discovery, поведение идентично US1.

---

## Phase 5: User Story 3 — Edit-mode и pinch не мешают друг другу (Priority: P2)

**Goal**: Зафиксировать регрессионную защиту для edit-mode: delete-button остаётся кликабельной, upload-progress подавляет pinch.

**Independent Test**: Войти в edit-mode своего рецепта, pinch → delete-button кликабельна; загрузить новое фото → во время upload pinch подавлён overlay'ом или параметром.

### Implementation for User Story 3

- [ ] T006 [US3] Подтвердить (или реализовать через параметр `pinchZoomEnabled`, см. T004), что во время `isUploading || isDeleting` в `RecipeDetailImageSection` pinch не активен. Если в T004 уже добавлен параметр — этот task становится regression-check на симуляторе.

**Checkpoint**: User Story 3 функционален — edit-mode и pinch coexist.

---

## Phase 6: User Story 4 — Случайный жест не ломает скролл (Priority: P3)

**Goal**: Обычная навигация (скролл карточки двумя пальцами через hero-зону) не активирует zoom.

**Independent Test**: Скроллить карточку двумя пальцами через hero-зону — скролл работает, zoom не активируется.

### Implementation for User Story 4

- [ ] T007 [US4] На симуляторе проверить scroll через hero-зону двумя пальцами. Если pinch активируется при случайном касании — повысить `minimumScaleDelta` (текущее 0.05) до 0.08 или 0.1 (зафиксировать значение в plan.md «Параметры»). Если scroll блокируется при активном pinch — переключиться с `.gesture(pinch)` на `.highPriorityGesture(pinch)` или `.simultaneousGesture(pinch)` (зафиксировать выбор в plan.md).

**Checkpoint**: User Story 4 функционален — обычный scroll не сломан.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Финальные проверки из plan.md «Verification» + tweak параметров по результатам тестирования.

- [ ] T008 [P] Прогон `bash scripts/lint-i18n.sh`: PASS, без новых предупреждений. Фича не добавляет UI-текста (FR-017).
- [ ] T009 Прогон `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16' build`: **BUILD SUCCEEDED**, без ошибок и warnings.
- [ ] T010 Мануально проверить в симуляторе ВСЕ сценарии из spec.md «Acceptance Scenarios»:
  - US1-1, US1-2, US1-3 — pinch своего рецепта (scale, dim, release, clamp).
  - US2-1 — pinch Discovery (идентичность US1).
  - US3-1, US3-2, US3-3 — edit-mode (delete-button кликабельна, upload-progress подавляет pinch, dropzone без pinch).
  - US4-1, US4-2, US4-3 — scroll (не блокируется, pinch не активируется случайно, pinch вне hero-зоны no-op).
  - Edge cases: рецепт без фото, фото грузится, быстрое повторное разведение, прерванный жест, поворот устройства, VoiceOver (читается как image), Reduce Motion (release-анимация уважается).
- [ ] T011 По результатам T007/T010 — финализировать значения параметров в plan.md «Параметры» (clamp, dim, minimumScaleDelta, release duration). Если значения менялись — обновить таблицу в plan.md.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 — только проверка контекста, ~2 минуты.
- **Foundational (Phase 2)**: T002 — создание модификатора, зависит от T001. **STOP-GATE после T002**.
- **User Story 1 (Phase 3)**: T003, T004 — зависят от T002.
- **User Story 2 (Phase 4)**: T005 — зависит от T002 (параллельно с T003, разные файлы).
- **User Story 3 (Phase 5)**: T006 — зависит от T004 (нужно знать, есть ли параметр `pinchZoomEnabled`).
- **User Story 4 (Phase 6)**: T007 — зависит от T003 и T005 (оба hero подключены).
- **Polish (Phase 7)**: T008 [P], T009, T010, T011 — после T003-T007. T008 параллелен с T009-build; T009 → T010 sequential (build сначала зелёный, потом ручная проверка); T011 после T007 и T010.

### User Story Dependencies

- **User Story 1 (P1, MVP)**: Реализуется первым через T003 + T004. После STOP-GATE T002 можно доставить только US1 и проверить.
- **User Story 2 (P1)**: T005 — параллелен T003 (разные cached-image-view'ы, оба зависят только от T002). Симметричен US1.
- **User Story 3 (P2)**: T006 — зависит от решения в T004 (параметр `pinchZoomEnabled` или нет).
- **User Story 4 (P3)**: T007 — зависит от T003 + T005; регрессионная проверка scroll.

### Within Each User Story

- Нет tests-first фазы (тесты на pinch невозможны).
- Нет моделей/сервисов — фича переиспользует существующий декодированный `UIImage`.
- US1 и US2 — каждый один файл; US3 — расширение US1 в `RecipeDetailImageSection` (если нужно); US4 — только проверка/tweak.

### Parallel Opportunities

- T003 (`RecipeCachedImageView.swift`) и T005 (`PublicCachedImageView.swift`) — параллельны, разные файлы.
- T008 (lint-i18n) и T009 (build) — параллельны.
- T010 (ручная проверка) и T011 (tweak параметров) — последовательны (сначала проверка, потом фиксация значений).

---

## Parallel Example

```bash
# После T002 (STOP-GATE пройден) — T003 и T005 параллельны (разные файлы):
Task T003: "RecipeCachedImageView.swift: добавить .heroPhotoPinchZoom(isEnabled: uiImage != nil)"
Task T005: "PublicCachedImageView.swift: добавить .heroPhotoPinchZoom(isEnabled: uiImage != nil)"

# T004 зависит от T003 (проверка edit-mode, возможно нужен параметр)
# T006 зависит от T004 (проверка/extension upload-progress подавления)

# Polish-фаза:
Task T008: "bash scripts/lint-i18n.sh"        # параллельно с T009
Task T009: "xcodebuild build"                 # параллельно с T008
Task T010: "симулятор: все Acceptance Scenarios"  # после T009 зелёного
Task T011: "финализировать параметры в plan.md"   # после T010
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. **T001** — подтвердить контекст `RecipeCachedImageView` и `PublicCachedImageView` (~2 минуты).
2. **T002** — создать `HeroPhotoPinchZoom.swift` с модификатором и preview (~80 строк).
3. **STOP-GATE**: `xcodebuild build` + Canvas preview рендерится. Если есть проблемы — фикс здесь.
4. **T003** — подключить `.heroPhotoPinchZoom()` к `RecipeCachedImageView.heroImageBody`.
5. **T004** — проверить edit-mode на симуляторе; если pinch пробивается через upload-progress overlay → добавить параметр `pinchZoomEnabled`.
6. **STOP and VALIDATE**: полный build + ручной тест US1 в симуляторе (свой рецепт с фото).
7. Если устраивает — продолжить T005 (Discovery), T006 (edit-mode regression), T007 (scroll).

### Incremental Delivery

1. T001 + T002 + STOP-GATE → модификатор готов, не подключён.
2. T003 (+ T004 при необходимости) → MVP готов (US1 работает на своём рецепте).
3. T005 → US2 работает (Discovery, тот же модификатор).
4. T006 → US3 подтверждён (edit-mode regression).
5. T007 → US4 подтверждён (scroll не сломан).
6. T008-T011 → verify зелёные, параметры финализированы, фича готова к коммиту.

### Notes

- Служебная длина: ~80 строк нового кода (модификатор) + 2 строки вызова.
- Точек мутации: 0 новых (только UI-state в `@GestureState`).
- Новых i18n-ключей: 0 (FR-017).
- Новых контрактов: 0 (sync/schema без изменений).
- STOP conditions (из plan.md):
  - `MagnifyGesture` конфликтует с родительским `ScrollView` → переключиться на `.simultaneousGesture` / `.highPriorityGesture`.
  - `scaleEffect` ломает `.clipped()` → решать отдельным контейнером (маской).
  - Release-анимация через `withAnimation` не срабатывает с `@GestureState` → перейти на `@State` + ручной сброс.

---

## Human Gate (из AGENTS.md / plan.md)

> Реализация начинается **только** после явного «продолжай» от пользователя на spec.md и plan.md. Этот tasks.md — следующий шаг после того гейта; он сам по себе не запускает кодинг.
