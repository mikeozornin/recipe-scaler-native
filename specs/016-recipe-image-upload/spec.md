# Спецификация: загрузка и удаление изображения рецепта

**Ветка**: `016-recipe-image-upload`  
**Дата**: 2026-06-02  
**Статус**: Draft  
**Зависимости**: `003-recipe-image-offline-cache`, `002` (v3 edit mode)  
**Эталон**: PRD § Images, REST в `docs/PRD.md` §7

## Контекст

**003** реализует download + disk cache + display. Пользователь на вебе может **загрузить** фото, **удалить**, **import from URL** — через REST; `imageUrl` в Y.Doc обновляется с сервера/sync.

iOS: только чтение кэша, нет picker/upload.

## Цель

Паритет mobile recipe header: camera/gallery, upload, delete, invalidation кэша 003.

## Пользовательские сценарии

### US1 — Upload photo (P1)

**Дано** v3 edit mode, **когда** пользователь выбирает фото, **тогда** `POST /api/recipes/:id/image` (resize/WebP на сервере), новый `imageUrl` в doc после sync, кэш 003 перезагружается по token.

### US2 — Delete image (P1)

**Когда** удаление, **тогда** `DELETE /api/recipes/:id/image`, пустой `imageUrl`, файлы кэша удалены (FR-IMG-001 в 003).

### US3 — Image from URL (P2)

**Когда** вставлен URL картинки, **тогда** `POST .../image-from-url` как веб.

### US4 — List preview (P1)

После upload list square preview object-fit crop, **не** увеличивает высоту строки (PRD).

### US5 — Офлайн (P2)

Upload/delete disabled или queued message; без corrupt Y.Doc locally.

## Требования

### FR-IMG-UP-001

REST only для байтов; метаданные `imageUrl` приходят через sync (не писать URL вручную в Y.Doc на клиенте, если веб не делает — сверить ARCHITECTURE).

### FR-IMG-UP-002

`RecipeImageService` invalidate on version token change (003).

### FR-IMG-UP-003

UI: кнопка в edit toolbar / header menu (mobile `recipe-header`).

## Вне scope

- Avatar upload (013)
- Multiple images per recipe (PRD: one image)

## Критерии успеха

- **SC-001**: Upload iOS → preview в веб list ≤ 10 с.
- **SC-002**: Delete iOS → placeholder на вебе, кэш пуст на iOS.
- **SC-003**: Offline — кнопка недоступна с понятным i18n.

## Артефакты

- `contracts/recipe-image-upload.md`
- `quickstart.md`