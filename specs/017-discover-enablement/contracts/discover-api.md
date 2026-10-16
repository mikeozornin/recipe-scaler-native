# Discover & Public Profile API — контракт

**Версия**: 1.0 (2026-06-14)
**Связанные спецификации**: 011-discover-public, 017-discover-enablement
**Реализация**: `RecipeScalerNative/Services/DiscoverAPI.swift`, `RecipeScalerCore/Networking/APIClient.swift`

## Общее

Все endpoints — REST, JSON. Ответы оборачиваются в стандартный конверт:

```json
{
  "success": true,
  "data": { ... },
  "error": null
}
```

При ошибке:

```json
{
  "success": false,
  "data": null,
  "error": "Human-readable message"
}
```

Авторизация: для endpoints `/api/discover/*` **не требуется** (публичные). Для `/api/users/public/:username` авторизация опциональна (если есть `Authorization: Bearer` или `x-user-id` — сервер может персонализировать ответ, например, скрыть приватные рецепты).

Декодер: `JSONDecoder` с `dateDecodingStrategy = .iso8601`.

## Кэширование

- **Disk cache (public)**: `PublicImageCacheService` → `{Caches}/PublicImages/{sha256(url)}.webp`. ETag / `If-None-Match`, лимит ~150 MB. Spec 045.
- **Memory cache**: `DiscoverImageMemoryCache` (NSCache) для мгновенного restore при scroll.
- **Offline**: последний disk cache + placeholder; не offline-first persistence.
- **Личные рецепты**: `RecipeImageService` → `Application Support/RecipeImages/` (spec 003, 021). Для Discover **не** используется.

---

## Endpoints

### 1. `GET /api/discover/collections`

Список кураторских коллекций + featured-авторов.

**Response.data**:

```typescript
{
  collections: DiscoveryCollection[],
  profiles: PublicProfilePreview[]
}
```

**`DiscoveryCollection`**:

| Поле | Тип | Описание |
|---|---|---|
| `slug` | string | URL-идентификатор коллекции |
| `title` | string | Заголовок |
| `description` | string? | Описание |
| `author_name` | string? | Имя автора (если есть) |
| `cover_image_url` | string? | URL обложки (абсолютный или относительный) |
| `recipe_count` | int | Кол-во рецептов в коллекции |

**`PublicProfilePreview`** (превью, без деталей):

| Поле | Тип | Описание |
|---|---|---|
| `username` | string | `@username` |
| `name` | string? | Отображаемое имя |
| `avatar_url` | string? | URL аватара |
| `recipe_count` | int | Кол-во публичных рецептов |
| `description` | string? | Склейка названий рецептов автора, которую собирает сервер (до 20 названий через « · »), не текст «о себе». |
| `preview_recipes` | array | Всегда присутствует, 0–3 элемента, новые первыми (`recipes.created_at DESC`). Только рецепты с фото, видимые под `share_mode` автора. |
| `preview_recipes[].id` | string (UUID) | Ключ элемента |
| `preview_recipes[].name` | string | Название рецепта |
| `preview_recipes[].image_url` | string | Относительный URL: `/api/recipes/{id}/image?size=card&v={token}` (card-версия, 640 px) |

Поле `preview_recipes` добавлено в 082 ([spec](../../082-discover-author-cards/spec.md)). Старые серверы ключ не отдают — клиенты должны трактовать отсутствие ключа как `[]`.

Пример элемента `preview_recipes`:

```json
"preview_recipes": [
  { "id": "8b0c…", "name": "Шарлотка с яблоками", "image_url": "/api/recipes/8b0c…/image?size=card&v=3f9a…" }
]
```

### 2. `GET /api/discover/collections/:slug`

Полная коллекция с рецептами.

**Response.data**: `CollectionWithRecipes`

| Поле | Тип |
|---|---|
| `slug` | string |
| `title` | string |
| `description` | string? |
| `author_name` | string? |
| `recipes` | CuratedRecipeMetadata[] |

**`CuratedRecipeMetadata`** (минимальный набор для preview):

| Поле | Тип |
|---|---|
| `id` | string (UUID) |
| `name` | string |
| `image_url` | string? |
| `color` | string (oklch или hex) |

### 3. `GET /api/discover/recipes/:id`

Полный curated-рецепт.

**Response.data**: `CuratedRecipe`

| Поле | Тип |
|---|---|
| `id` | string |
| `name` | string |
| `description` | string? (HTML) |
| `ingredients` | Ingredient[] |
| `image_url` | string? |
| `color` | string |
| `source_url` | string? |
| `prep_time_minutes` | int? |
| `cook_time_minutes` | int? |
| `servings` | int? |

**`Ingredient`**:

| Поле | Тип |
|---|---|
| `name` | string |
| `amount` | double? |
| `unit` | string |

### 4. `POST /api/discover/recipes/:id/clone`

Клонирование curated-рецепта в коллекцию пользователя.

**Request body**:

```json
{
  "locale": "ru"
}
```

`locale` — текущий язык приложения (`AppLanguagePreference.current.locale.language.languageCode`), используется сервером для перевода системных полей или локализации upstream-уведомлений.

**Response.data**: `{ "recipeId": "uuid" }`

ID нового рецепта в коллекции пользователя.

**Post-clone flow** (iOS):

1. `await syncService.loadRecipe(recipeId: newId)` — подгружаем Y.Doc.
2. `DeepLinkRouter.shared.handle(.openRecipe(recipeId: newId))` — `AppShellView` переключает на `.recipes` таб и открывает рецепт.
3. `ShoppingFeedback.postStatus(...)` — toast «Скопировано в ваши рецепты».

### 5. `GET /api/users/public/:username`

Публичный профиль автора с рецептами.

**Response.data**: `{ profile: PublicProfile, recipes: PublicRecipePreview[] }`

**`PublicProfile`**:

| Поле | Тип | Описание |
|---|---|---|
| `username` | string | `@username` |
| `name` | string? | Отображаемое имя |
| `avatar_url` | string? | URL аватара |
| `recipe_count` | int | Кол-во рецептов |
| `description` | string? | Био |
| `allow_recipe_downloads` | bool? | Разрешён ли PDF cookbook export (iOS: не используется) |
| `share_mode` | ShareMode? | Индикатор того, как автор делится рецептами |

**`ShareMode`** (enum):

| Значение | Описание |
|---|---|
| `one_by_one` | Рецепты публикуются по одному |
| `all` | Весь профиль публичный |
| `with_images_and_steps` | Полные рецепты с фото и шагами |

**`PublicRecipePreview`**:

| Поле | Тип |
|---|---|
| `id` | string (UUID) |
| `name` | string |
| `description` | string? |
| `image_url` | string? |
| `color` | string? |
| `created_at` | date (ISO 8601) |

---

## Images (статические)

### `GET /api/discover/recipes/:id/image`

**Public**, без auth. Возвращает байты изображения (JPEG/PNG/WEBP). Используется в:

- Hero изображение на `DiscoverRecipeView`
- Preview изображения в `DiscoverCollectionView` / `DiscoverPublicProfileView`

**URL helper**: `DiscoverAPI.discoverImageURL(recipeId:)` → `URL(string: "\(Config.baseURL)/api/discover/recipes/\(recipeId)/image")`.

### Аватары и обложки

URL приходит в DTO (`avatar_url`, `cover_image_url`). Может быть как абсолютным (`https://...`), так и относительным (`/uploads/...`). Парсинг — через `DiscoverAPI.avatarURL(from:)` / `DiscoverAPI.collectionCoverURL(from:)`.

---

## Ошибки

| HTTP status | `APIError` | Что показывает UI |
|---|---|---|
| 200 | — | Данные |
| 404 | `httpError(404)` | `discover.profile.not-found` / `discover.collection.not-found` |
| 5xx | `httpError(5xx)` | `discover.error-server` |
| Network failure | `localizedDescription` | `discover.error` |

Парсинг ошибок: `APIError.serverError(message: response.error)` если `response.success == false`.
