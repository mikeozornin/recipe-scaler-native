# Contract: merge consecutive spans

Канон UI: web spec 074 + `process-table.tsx` `mergeFilledRowsWithCellTitles`.

Для каждой cook-колонки, сверху вниз по `rows`:

1. Ячейка filled ⇔ есть assignment `(ingredientId, columnId)`.
2. Подряд filled → один span (`rowSpan = count`).
3. Пустая строка рвёт span.
4. Текст span = `cellTitles` на **первой** строке span для этой колонки, иначе `columns[].title`.
5. `cellTitles` на внутренней строке span (параллельная сковорода) режет span, как web (старт нового span).
6. Prep в этот грид не входят.

Native не invent-ит assignment. Новый ингредиент без id в таблице — пустые cook-ячейки. Исчезнувший id — строка не рисуется.

Timer chips: из `timer-reference` в HTML шагов; первая cook-колонка с тем же `stepIndex` получает чипы шага; остальные чипы рецепта — leftover bar.
