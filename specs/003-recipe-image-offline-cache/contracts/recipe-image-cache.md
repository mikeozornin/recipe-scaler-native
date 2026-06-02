# Контракт: кэш изображений рецепта (iOS)

**Статус**: принято (2026-06-02)  
**Эталон (web)**: `recipe-scaler-web/.../services/recipe-image-api.ts` (`getRecipeImageUrl`, `imageVersionToken`)

## 1. REST (загрузка байтов)

| Параметр | Значение |
|----------|----------|
| Method | `GET` |
| Path | `/api/recipes/{recipeId}/image` |
| Query `preview` | `true` — превью для списка |
| Query `v` | токен версии из Y.Doc `imageUrl` (опционально, если токен извлекается) |
| Auth | как у остального REST-клиента; endpoint без обязательной авторизации (см. web AGENTS.md) |

**iOS**: `APIClient.recipeImageURL(id:preview:version:)`.

## 2. Условный кэш

| Заголовок запроса | Источник |
|-------------------|----------|
| `If-None-Match` | сохранённый etag |
| `If-Modified-Since` | сохранённый lastModified |

| Ответ | Действие |
|-------|----------|
| `200` | записать body в `.webp`, обновить etag/lastModified/version |
| `304` | оставить файл; обновить etag/lastModified из ответа |
| ошибка | показать существующий локальный файл, если есть |

## 3. Поведение `RecipeImageService`

### `ensureCached(recipeId, imageUrl, variant, allowNetwork)`

```text
if imageUrl empty → removeCache(recipeId); return nil

if local file exists AND stored version == token(imageUrl)
  → return local URL

if !allowNetwork
  → return local URL or nil (без сети)

else
  → GET REST → ImageCacheService.fetchAndCache → notify recipeImageDidCache
```

### `prefetchPreviews(entries, allowNetwork)`

- `allowNetwork == false` → только очистка кэша для entries без `imageUrl`; загрузок нет
- только entries с непустым `imageUrl`
- concurrency: 3 рецепта параллельно
- на каждый рецепт: `ensureCached` для `preview`, затем для `full`

Триггер: `YjsSyncService.scheduleImagePrefetch` после обновления `collectionEntries` при `connectionState == .connected`.

### `prefetchFull(recipeId, imageUrl, allowNetwork)`

- `allowNetwork == false` → no-op
- триггер: `.task` в `YDocRecipeDetailView` при открытии деталки (догрузка, если full ещё не в кэше)

## 4. Поведение UI

### Список (`RecipeListView`)

| Условие | UI |
|---------|-----|
| `imageUrl` непустой | слот 44×44 справа, `RecipeCachedImageView` variant `preview` |
| `imageUrl` пустой | без слота |
| `allowsNetworkRefresh` | `true` только при `connectionState == .connected` |

### Деталь (`YDocRecipeDetailView`)

| Условие | UI |
|---------|-----|
| merged `imageUrl` непустой | `RecipeCachedImageView` variant `full`, height 250 |
| иначе | без блока изображения |

**Запрещено**: `AsyncImage(url: imageUrl из Y.Doc)`.

## 5. Тесты

| Тип | Что |
|-----|-----|
| Unit | `testRecipeImageVersionToken` — парсинг токена из пути |
| Ручной | `quickstart.md` |