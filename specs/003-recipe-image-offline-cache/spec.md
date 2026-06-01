# Спецификация: офлайн-кэш изображений рецептов

**Ветка**: `003-recipe-image-offline-cache`  
**Дата**: 2026-06-02  
**Статус**: реализовано  
**Связано**: Phase 2 (`001-yrs-native-read`), паритет списка (`contracts/recipe-list-display.md`)

## Контекст

В Y.Doc поле `imageUrl` — **метаданные** (путь в storage + версия), а не URL для прямой загрузки в UI.  
Ранее список использовал `AsyncImage` по строке из Y.Doc — превью не отображались и нарушался offline-first.

Цель: как на вебе — REST только для загрузки байтов, отображение только из локального кэша.

## Требования

### FR-IMG-001 — Источник правды для «есть фото»

Приложение ДОЛЖНО считать, что у рецепта есть изображение, если в merged-метаданных `imageUrl` непустое (collection entry или recipe document после `RecipeCollectionMerge`).

Пустой или отсутствующий `imageUrl` → слот превью в списке не резервируется, кэш файлов для `recipeId` удаляется.

### FR-IMG-002 — Загрузка только через REST API

При `allowNetwork == true` приложение ДОЛЖНО загружать байты через:

- превью списка: `GET /api/recipes/:id/image?preview=true&v={token}`
- деталь: `GET /api/recipes/:id/image?v={token}` (без `preview`)

`token` = `RecipeImageVersion.token(imageUrl)` — последний сегмент пути без расширения (паритет с web `imageVersionToken`).

### FR-IMG-003 — Локальное хранение

Загруженные байты ДОЛЖНЫ сохраняться в `ImageCacheService`:

- `{Caches}/RecipeImages/{recipeId}_preview.webp`
- `{Caches}/RecipeImages/{recipeId}_full.webp`

Условные запросы (`If-None-Match` / `If-Modified-Since`) и ответ `304` — как в существующем `ImageCacheService`.

Метаданные кэша (etag, lastModified, version token) — в `UserDefaults` с ключами `recipeImage.{recipeId}.{variant}.*`.

### FR-IMG-004 — UI только с диска

`RecipeListView` и `YDocRecipeDetailView` НЕ ДОЛЖНЫ использовать `AsyncImage` с URL из `imageUrl` Y.Doc.

Отображение через `RecipeCachedImageView` → `UIImage(contentsOfFile:)` после `RecipeImageService.ensureCached`.

### FR-IMG-005 — Offline-first

При `connectionState != .connected`:

- сеть для изображений не вызывается;
- если локальный файл есть — показывается (в т.ч. устаревшая версия до следующего онлайн-sync);
- если файла нет — превью пустое, название и остальной UI без изменений.

### FR-IMG-006 — Prefetch

После `YjsSyncService.refreshCollectionEntries` при подключении к серверу приложение ДОЛЖНО в фоне prefetch превью для записей с непустым `imageUrl` (до 3 параллельных загрузок).

При открытии деталки — prefetch `full` для активного рецепта.

### FR-IMG-007 — Обновление UI после записи кэша

После успешной записи файла сервис ДОЛЖЕН отправить `Notification.Name.recipeImageDidCache`; `RecipeCachedImageView` обновляет `UIImage` без перезахода на экран.

## Вне scope

- Загрузка/удаление изображения с iOS (только веб / будущая фаза).
- Хранение etag в SwiftData `Recipe` / `ApiCacheEntry` (используется UserDefaults + файлы).
- Встраивание байтов изображения в `ydoc_snapshots` SQLite.

## Критерии приёмки

1. Онлайн: в списке появляются превью 44×44 для рецептов с `imageUrl` после sync коллекции.
2. Офлайн (режим полёта): те же превью видны без запросов к API.
3. Смена фото на вебе (новый `imageUrl`) → после reconnect превью обновляется.
4. Удаление фото (`imageUrl` пустой) → превью исчезает, файлы кэша удалены.

## Реализация (код)

| Компонент | Файл |
|-----------|------|
| Оркестрация кэша | `Services/RecipeImageService.swift` |
| Файлы на диске | `Services/ImageCacheService.swift` |
| URL API | `Services/APIClient.swift` → `recipeImageURL(id:preview:version:)` |
| UI | `Views/RecipeCachedImageView.swift` |
| Список | `Views/RecipeListView.swift` |
| Деталь | `Views/YDocRecipeDetailView.swift` |
| Prefetch | `Services/YjsSync/YjsSyncService.swift` → `scheduleImagePrefetch` |