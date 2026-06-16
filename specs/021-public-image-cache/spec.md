# Спецификация: disk cache публичных изображений + миграция личных

**Ветка**: `021-public-image-cache`  
**Дата**: 2026-06-15 (постфактум)  
**Статус**: **Done** — реализовано, `verify-discover-public.sh` зелёный, build succeeded  
**Зависимости**: `003-recipe-image-offline-cache`, `017-discover-enablement`

## Контекст (до изменений)

Discover-изображения (grid, hero, аватары) жили только в RAM (`DiscoverImageMemoryCache`) и дефолтном `URLCache` (~20 MB disk). После kill app превью загружались заново.

`DiscoverRecipeView` ошибочно использовал `RecipeCachedImageView` → `RecipeImageService` → `{Caches}/RecipeImages/`. Публичный контент попадал в offline-first кеш личных рецептов.

Личные изображения по spec 003 лежали в `Caches/`, хотя это «полезные данные» — iOS может их удалить при нехватке места.

## Решение

Разделить два класса хранилищ по семантике iOS:

| Класс | Примеры | Директория | iOS может удалить | Инвалидация |
|-------|---------|------------|-------------------|-------------|
| Полезный storage | «Мои рецепты» preview/full | `Application Support/RecipeImages/` | Нет | `v=` token + ETag |
| Ephemeral cache | Discover grid/hero, аватары | `Caches/PublicImages/` | Да | ETag / Last-Modified |

Аналогия с браузером: личные — как saved files; публичные — как HTTP cache.

## Что реализовано

### Публичный disk cache

- `PublicImageDiskCache` — ключ `SHA256(url.absoluteString)` → `{hash}.webp`
- `PublicImageCacheService` (actor) — conditional GET, 304, in-flight dedup, LRU eviction при >150 MB
- Метаданные в UserDefaults: `publicImage.{hash}.etag`, `publicImage.{hash}.lastModified`
- Без auth headers (публичные URL)

### UI Discover

| Поверхность | Было | Стало |
|-------------|------|-------|
| Grid превью | memory + URLCache | memory → disk → network (`DiscoverImageLoader`) |
| Hero рецепта | `RecipeCachedImageView` | `PublicCachedImageView` |
| Аватар профиля | `AsyncImage` | `PublicCachedImageView` |
| Обложка коллекции | `AsyncImage` | без изменений |

### Маршрутизация URL hero

`DiscoverRecipeImageSource` + `DiscoverAPI.detailImageURL(recipeId:imageSource:)`:

- `.curatedDiscover` (default) → `GET /api/discover/recipes/:id/image` — из коллекций
- `.publicRecipe` → `GET /api/recipes/:id/image` (full) — из публичного профиля

`DiscoverPublicProfileView` передаёт `.publicRecipe` в `DiscoverRoute.recipe`.

### Миграция личных изображений

`RecipeImageDiskCache` → `Application Support/RecipeImages/`.

One-time migration при первом `fileURL()` / `existingFileURL()`:
- move файлов из `Caches/RecipeImages/`
- флаг `recipeImage.diskCache.migratedToApplicationSupport` в UserDefaults
- ключи `recipeImage.{id}.{variant}.*` не меняются

## Требования (as-built)

### FR-021-001 — Публичный disk cache

Публичные URL ДОЛЖНЫ кешироваться в `{Caches}/PublicImages/{sha256}.webp`.

Условные запросы и 304 — паритет с `ImageCacheService`. При 304 без файла на диске — retry без validators.

### FR-021-002 — UI Discover

Grid, hero, аватары — через public cache stack. `RecipeImageService` для Discover **не** вызывается.

### FR-021-003 — imageSource в навигации

`DiscoverRoute.recipe(id:allowDownloads:imageSource:)` — см. [data-model.md](./data-model.md).

### FR-021-004 — Application Support для личных

Личные `.webp` только в Application Support. Migration прозрачна для пользователя.

## Вне scope

- Disk cache обложек коллекций (`cover_image_url`) — остаются на `AsyncImage`
- Offline-first для Discover (нет prefetch-all, нет sync status sheet)
- Перенос etag-метаданных личных рецептов из UserDefaults в SQLite

## Критерии приёмки

| # | Сценарий | Статус |
|---|----------|--------|
| SC-001 | Discover grid после kill app — превью без сетевой задержки | ручная / disk path |
| SC-002 | Hero и аватар — повторный просмотр из disk | ручная |
| SC-003 | Публичные URL не в `RecipeImages/` | по архитектуре |
| SC-004 | Личные превью offline после migration | ручная |
| SC-005 | `verify-discover-public.sh` | VERIFIED 2026-06-15 |
| SC-006 | Unit-тесты disk paths, migration, 304 | добавлены в `RecipeScalerNativeTests` |

## Verify

```bash
rtk xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16e,OS=18.6' build
scripts/verify-discover-public.sh
```

## Артефакты

| Документ | Назначение |
|----------|------------|
| [spec.md](./spec.md) | этот файл |
| [data-model.md](./data-model.md) | пути, ключи, flow |
| [contracts/public-image-cache.md](./contracts/public-image-cache.md) | контракт fetch/UI |
| [quickstart.md](./quickstart.md) | ручная проверка |

## Связанные изменения в других спеках

- `003-recipe-image-offline-cache` — путь `{Application Support}/RecipeImages/`
- `017-discover-enablement` — disk cache вместо «только URLCache»

## Карта кода

| Компонент | Файл |
|-----------|------|
| Пути (public) | `RecipeScalerNative/Services/PublicImageDiskCache.swift` |
| Fetch + ETag | `RecipeScalerNative/Services/PublicImageCacheService.swift` |
| UI (public) | `RecipeScalerNative/Views/PublicCachedImageView.swift` |
| Grid loader | `RecipeScalerNative/Views/Discover/DiscoverRecipePreviewImage.swift` |
| imageSource | `RecipeScalerNative/Services/DiscoverAPI.swift` |
| Пути (personal) + migration | `RecipeScalerNative/Services/RecipeImageDiskCache.swift` |
