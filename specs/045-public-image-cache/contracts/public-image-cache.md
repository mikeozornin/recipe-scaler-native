# Контракт: public image cache (iOS)

**Статус**: as-built (2026-06-15)  
**Реализация**: `PublicImageCacheService`, `PublicImageDiskCache`, `PublicCachedImageView`

## 1. REST (публичные URL)

Auth **не** требуется. Используемые endpoints:

| Surface | Method | Path |
|---------|--------|------|
| Curated grid | GET | `/api/discover/recipes/{id}/image` |
| Public profile grid | GET | `/api/recipes/{id}/image` (full, без `preview`) |
| Curated hero | GET | `/api/discover/recipes/{id}/image` |
| Public profile hero | GET | `/api/recipes/{id}/image` (full) |
| Avatar | GET | `/api/users/{username}/avatar?preview=true&v=…` |

Helpers: `DiscoverAPI.discoverRecipeImageURL`, `recipeImageURL`, `detailImageURL`, `avatarURL`.

## 2. Fetch pipeline (`PublicImageCacheService`)

### `ensureCached(url:allowNetwork:)`

```text
if disk file exists
  if allowNetwork → fetchAndCache (background revalidate)
  return local URL

if !allowNetwork → nil

else → fetchAndCache → local URL or nil
```

### `fetchAndCache(url:)`

```text
dedup by sha256(url) via inFlight set

build GET with If-None-Match OR If-Modified-Since (from UserDefaults)
cachePolicy = .reloadIgnoringLocalCacheData  // bypass URLCache, use our disk

200 → write {hash}.webp atomically, store etag/lastModified, enforceSizeLimit
304 → keep file; update metadata; if file missing → retry without validators
4xx/5xx → throw; UI shows cached decode or placeholder
```

### Eviction

После каждой записи: если `PublicImages/` > 150 MB — удалить старейшие файлы + их UserDefaults keys.

## 3. UI load order

### Grid (`DiscoverImageLoader.loadImage`)

1. `DiscoverImageMemoryCache`
2. `PublicImageDiskCache.existingFileURL` → `RecipeImageDecoder.decode`
3. `PublicImageCacheService.ensureCached` → decode → memory store

### Hero / Avatar (`PublicCachedImageView`)

1. Memory hit → show
2. Disk hit → decode off main actor → show + memory store
3. If `allowsNetworkRefresh` → `ensureCached` → decode

Decode: `RecipeImageDecoder` (`fullMaxPixelSize` для hero, `previewMaxPixelSize` для avatar).

## 4. Отличие от личного кеша (spec 003)

| | Personal (`RecipeImageService`) | Public (`PublicImageCacheService`) |
|---|--------------------------------|-------------------------------------|
| Directory | Application Support | Caches |
| Key | `{recipeId}_{variant}` | `{sha256(url)}` |
| Version token | `v=` from Y.Doc `imageUrl` | нет (только ETag) |
| Auth | Bearer / x-user-id | нет |
| Offline-first | да (prefetch all collection) | нет |
| UI component | `RecipeCachedImageView` | `PublicCachedImageView` |
| Notification | `recipeImageDidCache` | нет |

## 5. Migration контракт (личные)

```text
on first RecipeImageDiskCache access:
  if migrated flag → skip
  if Caches/RecipeImages/ empty → create Application Support dir, set flag
  else move all files to Application Support/RecipeImages/, remove legacy dir, set flag
```

UserDefaults keys `recipeImage.*` остаются валидными.

## 6. Тесты

| Тест | Файл |
|------|------|
| `testPublicImageDiskCacheDetectsExistingFile` | path + existence |
| `testPublicImageCacheServiceStoresAndRevalidates304` | mock URLProtocol |
| `testRecipeImageDiskCacheUsesApplicationSupport` | base path |
| `testRecipeImageMigrationFromCaches` | move legacy → support |
