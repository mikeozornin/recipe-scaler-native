# Контракт UI: thumb иллюстрации в сетке ингредиентов

**Фича**: `043-ingredient-illustrations`  
**Статус**: draft — **заменяет** колонку «маркер/номер» из `002-native-editing/contracts/ingredients-grid-ui.md` для строк с количеством  
**Базовый контракт сетки**: [ingredients-grid-ui.md](../../002-native-editing/contracts/ingredients-grid-ui.md)  
**Нативная реализация**: `YDocIngredientsSection.swift`, `RecipeRowLayoutMetrics.swift`, `IngredientIllustrationThumb.swift`

## Цель

Слева от имени ингредиента — **иконка продукта 40×40 pt** (веб `IngredientIllustrationThumb`), а не порядковый номер `1, 2, 3…`. Заголовки секций и разделители — пустой слот той же ширины.

## Слот слева (замена «Маркер 22 pt»)

| Строка | Ширина | Содержимое |
|--------|--------|------------|
| Обычный ингредиент (view/edit) | **40 pt** | Thumb или Bowl |
| Заголовок / separator (`isHeaderRow`) | **40 pt** | Пусто (spacer), без номера |
| Новая строка (edit, «+») | **40 pt** | Символ «+» (как сегодня), не thumb |

Константа: `RecipeRowLayoutMetrics.illustrationSlotWidth` (или `IngredientIllustrationLayoutMetrics.displaySlotPt`).

Gap между слотом и именем: сохранить `ingredientMarkerSpacing` (2 pt) или уточнить в `layout.md`.

## Thumb

| Параметр | Значение |
|----------|----------|
| Размер слота | 40×40 pt |
| Bitmap | 120×120 px bundled (`@3x`) |
| Corner radius | `rounded-md` parity (~6–8 pt, в layout.md) |
| Фон контейнера | Белый в light **и** dark («полароид») |
| Content | `aspect fill` / `scaledToFill` + clip |
| Нет id / invalid | Bowl ~22 pt по центру |

## Режимы

| Режим | Thumb |
|-------|-------|
| View | Не кнопка; decorative a11y (`accessibilityHidden` если имя рядом) |
| Edit, строка с qty | Кнопка → picker sheet |
| Edit, header | Не интерактивен, пустой слот |
| Discover / public read-only | Как view |

## Колонки qty / reorder

Без изменений относительно `002`: base qty, scaled qty, reorder column в edit.

## Заголовки колонок

`IngredientColumnHeaderRow`: первая колонка по-прежнему «Ингредиент» над блоком **thumb+name** (не отдельный заголовок «иконка»).

## Нумерация

**Убрать** отображение порядковых номеров для ингредиентов с количеством. Порядок по-прежнему в данных (`order`); только UI-номера нет.

## Web reference (mobile)

```text
[thumb 40px] [name flex-1] [qty] [scaled] [reorder edit]
```

## Приёмка

- [ ] Колоночный заголовок «Ингредиент»: **без** пустого 40 pt; leading совпадает с leading thumb
- [ ] `isHeaderRow` / separator: выравнивание имени с обычными строками (пустой 40 pt слева)
- [ ] Dark mode: белый фон thumb читаем
- [ ] 10+ строк: горизонтальный скролл **не** появляется
- [ ] VoiceOver: имя ингредиента один раз; edit thumb — отдельный label «выбрать иконку»