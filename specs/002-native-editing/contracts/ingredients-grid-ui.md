# Контракт UI: сетка ингредиентов (mobile web parity)

**Фича**: `002-native-editing`  
**Статус**: принято (2026-06-04)  
**Эталон (веб)**: `recipe-scaler-web/recipe-scaler/src/components/recipe/ingredients-section.tsx`, `view-only-ingredient-row.tsx`, `draggable-ingredient-row.tsx`, `hooks/use-recipe-scale.ts`  
**Нативная реализация**: `RecipeScalerNative/Views/YDocIngredientsSection.swift`, `Utils/RecipeRowLayoutMetrics.swift`

## Цель

Секция ингредиентов на экране деталей v3-рецепта в **просмотре** и **редактировании** повторяет **мобильную веб-вёрстку**: та же колоночная сетка, те же два количества (база + масштаб), те же жесты (свайп удаления, reorder), без отдельного заголовка секции «Ingredients».

Пиксель-в-пиксель не требуется; обязательны иерархия, выравнивание, поведение масштаба и iOS-идиоматичные жесты.

---

## Заголовки колонок (не секции)

| Элемент | Требование |
|---------|------------|
| Заголовок секции «Ingredients» | **Не показывать** |
| Колонка 1 | `recipes.ingredient-header` — «Ingredient» / «Ингредиент» |
| Колонка 2 | `recipes.qty-header` — «Qty» / «Клв» |
| Стиль заголовков | Цвет **primary** (не muted), шрифт **semibold** (`font-medium` на вебе) |
| Позиция **Qty** | Заголовок **только над колонкой базового** (чёрного) количества; справа — пустая ячейка под scaled (на edit — под accent, без текста) |

Референс веб (header):

```text
[Ingredient flex-1] [Qty w-20 right] [accent w-16 empty] [reorder w-40 edit only]
```

---

## Колоночная сетка строки

Слева направо (все режимы, кроме оговорок):

| Слот | Ширина | Содержимое |
|------|--------|------------|
| Маркер | 22 pt | Номер строки (1, 2, …), «+» для новой строки, пусто для заголовка-разделителя |
| Название | `flex-1` | Имя; под ним (если включено питание) строка КБЖУ **в той же колонке**, не с отступом под всю строку |
| Базовое qty | `originalQtyColumnWidth` | Моноширинный текст/поле, **primary**, выравнивание **по правому краю** колонки |
| Scaled qty | `scaledQtyColumnWidth` | Моноширинный текст/поле, цвет **accent рецепта**, выравнивание **по правому краю** |
| Reorder (edit) | `listReorderColumnWidth` (~38 pt) | Системный control `List` + `onMove` (≡), не кастомная иконка с `draggable` |

### Ширина колонок количества

- Минимальная ширина **каждой** qty-колонки должна вмещать значение **`280.8`** в `AppFonts.mono` / body size + небольшой trailing padding.
- Расчёт: измерение строки `"280.8"` (см. `RecipeRowLayoutMetrics.qtyColumnMinWidth`); **обе** колонки используют это значение (на вебе view-mode scaled input тоже `w-20`).

### Нумерация строк (просмотр и edit)

- Нумеруются только строки с количеством (`hasQuantity`, не separator/header).
- Строки-заголовки (`isHeaderRow`) и разделители — **без номера**.

---

## Режим просмотра (v3, не edit)

| Поле | Поведение |
|------|-----------|
| Базовое qty | Только чтение, чёрный/primary текст (`quantityText` / `originalAmount`) |
| Scaled qty | **Редактируемое** поле (прозрачный `TextField`), цвет accent |
| Масштаб | Правка scaled **не пишет** в Y.Doc; пересчитывает **UI `scaleFactor`** для рецепта: `scaleFactor = scaled / original` (как `useRecipeScale.handleAmountChange`), сохранение в `RecipeScaleStorage` (`recipe-scale:{id}`, аналог `localStorage` на вебе) |
| Порции на экране | `viewServings = round(baseServings × scaleFactor)`; отображение scaled qty согласовано с этим множителем |
| Слайдер/степпер порций | По-прежнему меняет `scaleFactor` (FR-007); согласован с правкой scaled в сетке |

---

## Режим редактирования (v3, edit)

| Поле | Поведение |
|------|-----------|
| Строка «Servings» | Первая строка сетки: label + базовое qty (редактируемое) + scaled preview (accent), выравнивание как у ингредиентов |
| Имя | Inline `TextField`, многострочный при необходимости |
| Базовое qty | Inline `TextField`, primary, правая колонка |
| Scaled qty | **Только preview** (accent), пересчёт от черновика base и `viewServings` / scale в edit-контексте |
| Новая строка | Маркер «+», name + base + scaled preview, кнопка submit справа (в колонке reorder) |
| КБЖУ | Под именем в той же `VStack`; tap → sheet редактирования nutrition |

### Удаление ингредиента

- **Только** системный паттерн iOS: `List` + `.swipeActions(edge: .trailing)` с `Button(role: .destructive)` и `Label(..., systemImage: "trash.fill")`.
- **Запрещено**: `contextMenu` / long-press delete, кастомный swipe с узкой кнопкой и переносом текста «Delete», обрезание названия при свайпе.

### Изменение порядка (drag-and-drop)

- **Только** `List` + `.onMove` + `environment(\.editMode, .constant(.active))`.
- При перетаскивании — **системный призрак** строки (как Reminders), без самописного `draggable` / `dropDestination` на всю строку.
- После drop — `onReorder(fromIndex, toIndex)` → мутация `Y.Array` (как сейчас в `DocumentManager.moveIngredient`).
- Reorder control справа; жест не конфликтует со swipe delete (разные оси/зоны).

### Вертикальные отступы строк

- Единый `ingredientListRowChrome()` для строк с одной линией текста (min height 44 pt).
- Строки с КБЖУ: `ingredientListRowChromeCompact()` или эквивалент без лишнего `padding.leading` под всю ширину (КБЖУ только под колонкой имени).
- `List`: `listRowSpacing(0)`, `listRowInsets` нулевые, горизонтальный inset секции `px-4` (16 pt) снаружи.

---

## Синхронизация порций и масштаба (связанные баги, вне чистого UI)

Зафиксировано для паритета с вебом (не дублировать регрессии):

| Тема | Правило |
|------|---------|
| `servings` в Y.Doc | Запись **double** с iOS; веб `normalizeServingsValue` принимает также Yrs **int** / boxed number |
| UI `scaleFactor` | Только локально (`RecipeScaleStorage` / `recipe-scale:{id}`), **не** поле Y.Doc (FR-007) |
| После сохранения базовых порций из edit | Сброс `scaleFactor` к 1 (если продуктово согласовано с вебом при смене base servings) |
| Веб `updateRecipe` | Не `delete('servings')` при неудачной нормализации входящего значения (вторично для сценария «только iOS писал») |

---

## Локализация

| Ключ | EN | RU |
|------|----|----|
| `recipes.ingredient-header` | Ingredient | Ингредиент |
| `recipes.qty-header` | Qty | Клв |
| `edit.ingredient.delete` | Delete | (существующий перевод) |

Ключ `"Ingredients"` как заголовок секции **не использовать** в `YDocIngredientsSection`.

---

## Проверка (ручная / агент)

1. Открыть v3-рецепт с длинными числами (например «Васкески чизкейк») — в колонках видно `280.8` / `1,000` без обрезки.
2. Просмотр: правка зелёного qty → меняются все scaled qty и степпер порций; Y.Doc `servings` не меняется от scale alone.
3. Edit: свайп влево → красная системная кнопка удаления; long-press меню удаления нет.
4. Edit: перетаскивание за ≡ → призрак, порядок на вебе совпадает после sync.
5. Заголовок Qty стоит над чёрной колонкой, не по центру двух колонок.
6. Однострочный ингредиент с КБЖУ — подпись сразу под именем, не «уезжает» влево из-за drag-колонки.

**Сборка**: `xcodebuild -scheme RecipeScalerNative` (см. `AGENTS.md`).

---

## История изменений

| Дата | Изменение |
|------|-----------|
| 2026-06-04 | Первая версия: итог обсуждения parity ingredients grid (две колонки qty, заголовки, swipe, List reorder, scale в view, ширины, KBJU) |