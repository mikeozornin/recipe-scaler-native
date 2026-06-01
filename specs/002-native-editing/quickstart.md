# Быстрый старт: Phase 3 — нативное редактирование

**Фича**: `002-native-editing`  
**Предусловие**: Phase 2 (`001-yrs-native-read`) завершена — чтение из Y.Doc, web → iOS работает.

## Проверка базы Phase 2

```bash
cd recipe-scaler-native
xcodebuild -scheme RecipeScalerNative -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' build
```

Запустить приложение → вход → список из Y.Doc → открыть рецепт v3 (если есть).

## Рекомендуемый порядок реализации

1. **Policy + gate API** — `RecipeEditPolicy`, блок записи в `DocumentManager` для non-v3
2. **Обёртки yrs write** — `YrsInput`, расширения `YrsMap` / `YrsArray`
3. **`UpdateDebouncer` + emit `sync_request`** — подключить `sync_confirmed`
4. **Миграция `offline_sync_queue`** — enqueue / drain
5. **UI** — баннер legacy, edit mode на `YDocRecipeDetailView`, sheet ингредиента (референс: веб mobile, см. `plan.md`)
6. **Ручной тест** — iOS edit → обновить веб; web edit → iOS

## Ручной тест: iOS → Web

1. Открыть рецепт **v3** на iOS (`version` в Y.Doc = `v3`)
2. **Edit** → изменить название → **Done**
3. Подождать ~2 с (debounce + сеть)
4. Обновить веб-клиент — название должно совпасть

## Ручной тест: Legacy read-only

1. Открыть рецепт **v1** или **v2**
2. Виден **баннер**, нет Edit (или disabled)
3. После миграции в v3 в вебе — баннер исчезает после `recipe_updated`

## Ручной тест: Офлайн-очередь

1. Включить авиарежим
2. Изменить порции v3-рецепта → Done
3. Опционально завершить приложение; выключить авиарежим
4. Перезапуск — на вебе изменение в течение ~10 с

## Ключевые файлы (после implement)

| Область | Путь |
|---------|------|
| Политика edit | `Services/YjsSync/RecipeEditPolicy.swift` |
| Debouncer | `Services/YjsSync/UpdateDebouncer.swift` |
| Очередь | `Services/YjsSync/OfflineWriteQueue.swift` |
| UI | `Views/YDocRecipeDetailView.swift` |
| Контракты | `specs/002-native-editing/contracts/` |

## Следующий шаг Spec Kit

```text
/speckit-implement
```