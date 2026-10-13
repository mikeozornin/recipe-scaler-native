# 081 — отложено на потом

Найдено по ходу работы над iPad. Не входит в задачи 081 или ждёт решения владельца.

## Решено владельцем отложить

- **«Добавить в коллекцию»: три разных левых края у названий** (2026-10-13). Общий компонент, на iPhone то же самое.
  - Где: `CollectionAssignSheet.swift` ~:50-58. Строка — `HStack` с отступом по умолчанию, эмодзи — `Text(...).fixedSize()` без слота фиксированной ширины, у строк без эмодзи заглушки нет. «Новая коллекция» (~:124-173) уже на `RecipeRowLayoutMetrics.markerSlotWidth` / `rowMarkerSpacing`.
  - Видно: `tmp/ipad-verify/us4/recipes-collections-landscape-900.png` — «Выпечка», «На ужин» (с эмодзи) начинаются правее «Супы» (без эмодзи), «Новая коллекция» — третий край.
  - Как чинить: строка как `collectionRow` в `CollectionsRootView.swift` ~:354-373 — `HStack(spacing: RecipeRowLayoutMetrics.rowMarkerSpacing)`, эмодзи или цветная папка в `.frame(width: markerSlotWidth, height: titleLineHeight)`, `.listRowInsets(RecipeRowLayoutMetrics.listRowInsets)`.
  - Меняет пиксели iPhone: переснять эталон `verify-ipad-layout.sh` после правки.

## Вне 081

- Текст «В этой коллекции нет рецептов» (`CollectionFolderView.swift` ~:139, `String(localized:)`) идёт по языку системы, а не по языку приложения.
- Сохранённый id чата ассистента (`AssistantSessionStore`) не привязан к аккаунту.
- `SeedClient.createCollection` шлёт `POST /api/collections`, на бэкенде такого маршрута нет (404); ни один spec его не использует.
- Локальный бэкенд: массовое добавление ингредиентов отвечает 500; `calculate-nutrition` гоняется с фоновой обработкой таблицы после импорта текста.
- `IPadShellSpec.testCompactHasNoMoreTab` нестабилен: id элементов компактного таб-бара появляются поздно (14–39 с при ожидании 25 с). Надёжное ожидание — правка инфраструктуры UI-тестов.
- `SnapshotTests` починить до 2026-11-12.
- Описать особенности симулятора в `docs/AGENT-WORKFLOW.md`: эмодзи рисуются «?», альбомные скриншоты XCTest обрезаны (`simctl io screenshot` + `sips -r 270`), пиксельная регрессия iPhone чувствительна к нагрузке.
- `verify-recipe-collections.sh` и `verify-assistant.sh` пишут скриншоты в отслеживаемые папки `specs/`.
- Капсула таймеров (`MobileTimerPanel.swift` ~:76-86) без accessibility value «развёрнуто / свёрнуто».
- В dev-базе остались одноразовые тестовые пользователи.
