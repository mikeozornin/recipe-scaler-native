# План реализации: нативное редактирование рецепта (Phase 3)

**Ветка**: `002-native-editing` | **Дата**: 2026-06-01 | **Спека**: [spec.md](./spec.md) | **Статус**: ✅ реализовано в коде (2026-06-04); открыты T034 quickstart и T045 SC-002a (ручной parity + скриншот сетки)

**Вход**: спецификация `/specs/002-native-editing/spec.md`

## Кратко

Phase 3 добавляет **путь записи** поверх чтения/синка Phase 2: рецепты **v3** редактируются на iOS через write-транзакции yrs, debounced `sync_request` на сервер и офлайн-очередь SQLite. Рецепты **v1/v2** остаются **только для чтения** с баннером legacy; миграция в v3 — только в вебе.

Ключевые добавления: обёртки записи yrs (`ymap_insert`, `yarray_insert_range`, …), `UpdateDebouncer`, `OfflineWriteQueue`, API редактирования в `YjsSyncService`, UX на `YDocRecipeDetailView` (режим редактирования, sheet ингредиента, статус sync).

## Технический контекст

**Язык / версия**: Swift 5.9+ (iOS 17+), существующий `YrsXCFramework` (пересборка Rust не нужна, если не требуются новые символы yffi)

**Основные зависимости** (существующие + расширение):
- yrs / YrsC — **write**-транзакции и мутации shared-типов (в Phase 2 уже есть `ydoc_write_transaction` для `applyUpdate`)
- socket.io-client-swift — emit `sync_request`, обработка `sync_confirmed`
- GRDB — новая таблица `offline_sync_queue` + существующая `ydoc_snapshots`
- Стек Phase 2: `YjsSyncService`, `DocumentManager`, `SyncEventHandler`, `YDocStore`

**Хранение**:
- `ydoc_snapshots` — без изменений схемы; обновление после локальной записи и `sync_confirmed`
- `offline_sync_queue` — отложенные бинарные апдейты по `docKey` (FIFO на документ, merge перед отправкой где возможно)

**Тестирование**: XCTest для debouncer, drain очереди, gate v3, round-trip записи yrs на фикстуре; ручные тесты iOS ↔ web

**Платформа**: iOS 17.0+, Xcode 16.0+

**Тип проекта**: mobile-app (нативный iOS)

**Цели по производительности**: debounced send ≤1 `sync_request` на 1 с паузы ввода; drain очереди <10 с после reconnect; UI отражает локальную запись <100 мс

**Ограничения**: запись только v3; без изменений бэкенда; без редактирования XmlFragment описания; без CRUD коллекции; debounce ~1 с как на вебе; CRDT-merge при одновременном редактировании

**Масштаб**: как в Phase 2 (≤200 рецептов, ≤50 ингредиентов); один активный экран редактирования на рецепт

## Проверка конституции

*GATE: пройти до Phase 0 research. Перепроверить после Phase 1 design.*

Ссылка: [.specify/memory/constitution.md](../../.specify/memory/constitution.md)

| Gate | Статус | Примечания |
|------|--------|------------|
| CRDT-first | ✅ PASS | Все мутации рецепта через yrs → Y.Doc; REST только для изображений/auth |
| Паритет с вебом | ✅ PASS | `sync_request` / `sync_confirmed` тот же payload; запись только схема v3 |
| Offline-first | ✅ PASS | Офлайн-очередь + drain при reconnect; локальный apply до сети |
| Нативный UI | ✅ PASS | SwiftUI на `YDocRecipeDetailView`; без WKWebView для описания |
| Поэтапная поставка | ✅ PASS | только Phase 3; редактор описания (4), операции коллекции (5) — позже |
| i18n | ✅ PASS | Баннер, статусы sync, подписи Edit через `Localizable.xcstrings` |
| Документация | ✅ PASS | Расширить `docs/ARCHITECTURE.md`, `contracts/`, `PROJECT_STATUS.md` на этапе implement |

Нарушений нет. Complexity Tracking пуст.

## UX (Phase 3)

### Референс дизайна (веб, мобильный вид)

Если неясны визуал или взаимодействие — ориентир: **веб-приложение в stacked (мобильной) вёрстке** (не пиксель-в-пиксель, та же иерархия информации на SwiftUI):

**Путь к репо** (сосед native): [`../recipe-scaler-web/recipe-scaler`](../recipe-scaler-web/recipe-scaler)

| Native (Phase 3) | Референс в вебе | Примечания |
|------------------|-----------------|------------|
| `YDocRecipeDetailView`, stacked | `src/pages/recipe-detail.tsx` — ветка `!isContainerWide` / `.recipe-detail-stacked-only` | Мобильный = узкий viewport; split pane только desktop |
| Toolbar назад + Edit / Done | `src/components/recipe/recipe-header.tsx` | `Pencil` → edit; Done сбрасывает debounced save на вебе |
| Название (edit) | `recipe-detail.tsx` ~2207 — mobile `textarea` 32px | iOS: `TextField` или многострочное поле той же заметности |
| Цвет (edit) | `recipe-detail.tsx` ~2264 — `<input type="color">` | iOS: чипы пресетов или `ColorPicker` → `recipe.color` |
| Порции + слайдер масштаба | `servings-control.tsx` + `useRecipeScale` | В edit меняется **базовый** `servings`; слайдер — UI-local scale (FR-007) |
| Список ингредиентов | `ingredients-section.tsx`, `view-only-ingredient-row.tsx`, `draggable-ingredient-row.tsx` | Две колонки qty (base + scaled), заголовки Ingredient/Qty; см. **`contracts/ingredients-grid-ui.md`** |
| Просмотр: правка scaled qty | `use-recipe-scale.ts` | Пересчёт локального `scaleFactor`, не Y.Doc |
| Edit: inline CRUD | `draggable-ingredient-row.tsx` | Inline name/amount; строка «+»; nutrition — sheet по tap на КБЖУ |
| Swipe delete | `swipeable-row.tsx` | iOS: **`List` + `swipeActions(trailing)`** — нативный iOS, без context menu |
| Reorder | dnd-kit на вебе / drag handle | iOS: **`List` + `onMove`** + системный призрак (Reminders), reorder control справа |
| Nutrition | `nutrition-section.tsx`, `nutrition-block.tsx` | Поля read-only / editable; LLM-пересчёт в Phase 3 не обязателен |
| Legacy / миграция | `migration-alert.tsx` | **Только веб** — кнопка миграции в v3. iOS: **баннер read-only** без миграции (спека) |
| Debounced save | `use-recipe-persistence.ts` (`SAVE_DEBOUNCE_MS`) | ~1 с перед `sync_request` |

**Как смотреть мобильный веб**: recipe detail в браузере на ширине телефона (&lt;640px) или DevTools — переключение на `isContainerWide`.

**База**: экран **`YDocRecipeDetailView`** (Phase 2, чтение). Новый корень навигации не нужен.

### Состояния экрана

| Состояние | Когда | UI |
|-----------|-------|-----|
| **Legacy read-only** | `version` v1 или v2 | Верхний **баннер** (info): «Старый формат рецепта — только просмотр. Обновите рецепт в веб-приложении.» Без Edit. Слайдер масштаба работает (UI-local). |
| **Просмотр v3** | v3, не edit | Toolbar: **Edit** (карандаш). Поля текстом. Ингредиенты read-only. Nutrition read-only. **Чип sync записи**: idle / synced. |
| **Редактирование v3** | v3, edit | Toolbar: **Done**. Название → `TextField`. Порции в сетке ингредиентов + степпер в просмотре. Цвет → чипы. Ингредиенты: **inline** сетка (`YDocIngredientsEditSection`), swipe-delete, **List reorder**; nutrition строки — tap → sheet. Чип sync: pending / syncing / error. |

### Правила взаимодействия

- **Без autosave на сервер на каждый символ** — локальная запись yrs по Done или commit поля; на сервер — debounced пакет.
- **Done** выходит из edit; debouncer отправляет в течение ~1 с.
- **Cancel** (опционально) откатывает черновик UI к последнему `currentRecipe` без yrs write.
- **Ингредиенты inline**: commit по blur/смене фокуса; Delete — swipe; reorder — `onMove`. **Sheet** — только nutrition ингредиента (КБЖУ).
- Баннер legacy скрывается сразу, когда после `recipe_updated` `version` стала v3.

### Новые компоненты SwiftUI (планируемые пути)

```text
RecipeScalerNative/Views/
├── YDocRecipeDetailView.swift      # расширение: режимы, баннер, toolbar
├── RecipeLegacyBanner.swift        # NEW
├── RecipeEditToolbar.swift         # NEW — чип статуса sync
├── YDocIngredientsSection.swift    # view + edit grid (web parity)
└── EditIngredientNutritionSheet.swift  # nutrition per ingredient

RecipeScalerNative/ViewModels/
└── RecipeEditViewModel.swift       # NEW — черновик, мутации через sync service
```

## Структура проекта

### Документация (фича)

```text
specs/002-native-editing/
├── plan.md              # этот файл
├── spec.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── yffi-write-api.md
│   ├── sync-write-protocol.md
│   └── ingredients-grid-ui.md
└── checklists/
    └── requirements.md
```

### Исходный код (корень репозитория)

```text
RecipeScalerNative/
├── Services/
│   ├── Yrs/
│   │   ├── YrsDocument.swift
│   │   ├── YrsMap.swift
│   │   ├── YrsArray.swift
│   │   └── YrsInput.swift             # NEW
│   ├── YjsSync/
│   │   ├── YjsSyncService.swift
│   │   ├── DocumentManager.swift
│   │   ├── SyncEventHandler.swift
│   │   ├── UpdateDebouncer.swift      # NEW
│   │   ├── OfflineWriteQueue.swift    # NEW
│   │   └── RecipeEditPolicy.swift     # NEW
│   └── Storage/
│       ├── Database.swift
│       └── OfflineWriteQueueStore.swift
├── ViewModels/
│   └── RecipeEditViewModel.swift
└── Views/
    ├── YDocRecipeDetailView.swift
    ├── RecipeLegacyBanner.swift
    └── IngredientEditSheet.swift
```

**Решение по структуре**: расширять layout Phase 2; отдельного REST write path нет.

## Complexity Tracking

> Пусто — все gates пройдены.