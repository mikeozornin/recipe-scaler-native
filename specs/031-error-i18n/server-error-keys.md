# Контракт: серверные dot-key сообщения об ошибках

**Дата**: 2026-06-17
**Версия**: 1.0
**Аудитория**: backend-команда recipe-scaler-web/server

## Соглашение

Сервер в поле `response.error` JSON-ответа (формат `APIResponse<T>`: `{success, data, error}`) **обязан** возвращать dot-key строку, а не человекочитаемый английский текст. iOS-клиент детектит dot-key по регулярному выражению и резолвит через `Bundle.currentLocalizedString(message)`. Если строка не dot-key, показывается generic локализованное сообщение, а конкретный текст пишется только в логи.

## Регулярное выражение dot-key

```
^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*){1,}$
```

- lowercase ASCII, цифры, дефис
- минимум 2 сегмента, разделённых точкой
- примеры валидных: `assistant.threads.create.failed`, `account.profile.not-found`, `recipe.import.failed`
- примеры невалидных: `Profile load failed`, `Failed: error 42`, `assistantError`

## Таблица ключей

| HTTP endpoint | HTTP context | Старый английский fallback | Новый dot-key |
|---------------|--------------|----------------------------|---------------|
| `POST /api/auth/register-auto` | register | `"Registration failed"` | `auth.register.failed` |
| `POST /api/auth/login-with-seed` | login | `"Login failed"` | `auth.login.failed` |
| `POST /api/auth/login-with-seed` | seed invalid | `"Invalid seed phrase"` | `auth.error.invalid-seed` |
| `*` | generic auth API failure | `"Request failed"` | `auth.error.api-generic` |
| `GET /api/users/profile` | profile load | `"Profile load failed"` | `account.profile.load-failed` |
| `GET /api/users/sharing-settings` | load | `"Sharing settings load failed"` | `account.sharing.load-failed` |
| `PATCH /api/users/sharing-settings` | update | `"Sharing settings update failed"` | `account.sharing.update-failed` |
| `GET /api/settings` | load | `"Settings load failed"` | `account.settings.load-failed` |
| `GET /api/discover/collections` | discover list | `"Discover fetch failed"` | `discover.fetch-failed` |
| `GET /api/discover/collections/:slug` | collection | `"Collection fetch failed"` | `discover.collection-failed` |
| `GET /api/discover/recipes/:id` | recipe | `"Recipe fetch failed"` | `discover.recipe-failed` |
| `POST /api/discover/recipes/:id/clone` | clone | `"Clone failed"` | `discover.clone-failed` |
| `GET /api/v2/recipes/public/:id/state` | state | `"Public recipe fetch failed"` | `discover.public-recipe-failed` |
| `GET /api/v2/recipes/public/:id/state` | decode error | `"Public recipe decode failed: ..."` | `discover.public-recipe-failed` |
| `POST /api/v2/recipes/:id/copy` | copy | `"Copy failed"` | `discover.copy-failed` |
| `GET /api/users/public/:username` | profile | `"Public profile fetch failed"` | `discover.public-profile-failed` |
| `GET /api/users/public/:username` | decode error | `"Public profile decode failed: ..."` | `discover.public-profile-failed` |
| `POST /api/recipes/import/image` | no images | `"No images"` | `recipe.import.no-images` |
| `POST /api/recipes/import/*` | generic import | `"Import failed"` | `recipe.import.failed` |
| `POST /api/recipes/:id/image` | upload | `"Upload failed"` | `recipe.image.upload-failed` |
| `DELETE /api/recipes/:id/image` | delete | `"Delete failed"` | `recipe.image.delete-failed` |
| `PUT /api/v1/shopping-list/share` | update | `"Share update failed"` | `sharing.update-failed` |
| `POST /api/telegram/connect` | code | `"Telegram failed to get code"` / `String(localized:)` | `telegram.failed-to-get-code` |
| `GET /api/telegram/status` | status | `"Telegram status failed"` | `telegram.status-failed` |
| `POST /api/telegram/disconnect` | disconnect | `"Telegram failed to disconnect"` / `String(localized:)` | `telegram.failed-to-disconnect` |
| `POST /api/assistant/threads` | create | `"assistant.threads.create.failed"` (уже OK) | `assistant.threads.create.failed` |
| `GET /api/assistant/threads` | list | `"assistant.threads.list.failed"` (уже OK) | `assistant.threads.list.failed` |
| `GET /api/assistant/threads/:id/messages` | messages | `"assistant.messages.load.failed"` (уже OK) | `assistant.messages.load.failed` |
| `DELETE /api/assistant/threads/:id` | delete | `"assistant.threads.delete.failed"` (уже OK) | `assistant.threads.delete.failed` |
| `POST /api/assistant/threads/:id/respond-stream` | empty | `"assistant.message.empty"` (уже OK) | `assistant.message.empty` |
| `POST /api/assistant/threads/:id/respond-stream` | too long | `"assistant.message.too-long"` (уже OK) | `assistant.message.too-long` |
| `POST /api/assistant/threads/:id/respond-stream` | http error | `"assistant.stream.http-error"` (уже OK) | `assistant.stream.http-error` |
| `POST /api/assistant/transcribe` | audio too long | `"assistant.voice-error.too-long"` (уже OK) | `assistant.voice-error.too-long` |
| `POST /api/assistant/transcribe` | transcription | `"assistant.voice-error.transcription"` (уже OK) | `assistant.voice-error.transcription` |

## Совместимость

iOS-клиент принимает оба формата:
1. **Новый (рекомендуется)**: dot-key, резолвится локально.
2. **Старый**: человекочитаемый английский — показывается generic-сообщение, конкретный текст пишется в `AppLog`.

После миграции сервера на dot-key можно удалить regex-детекцию (она станет no-op).

## Client API (post-MIK-135 — типизация)

Throw-сайты **не** передают строку напрямую. Используется enum `ServerErrorCode`
(`RecipeScalerCore/Networking/ServerErrorCode.swift`) — исчерпывающий список всех
dot-key контракта. Неизвестные / legacy строки коллапсируют в endpoint-специфичный
fallback ещё на throw-сайте:

```swift
// Было (хрупко — английский мог утекать в Bundle.currentLocalizedString):
throw APIError.serverError(message: response.error ?? "account.profile.load-failed")

// Стало (типизировано — fallback гарантирует валидный dot-key):
let code = ServerErrorCode.from(
    serverValue: response.error,
    fallback: .accountProfileLoadFailed
)
throw APIError.serverError(code: code)
```

`APIError.userFacingMessage()` теперь вызывает `Bundle.currentLocalizedString(code.rawValue)`
напрямую — никакой prefix-детекции на view-слое для типизированных путей.

`DotKeyLocalizer` сохранён как safe-decoder helper для нетипизированных
edge-кейсов (`AuthError.apiError(_, message:)`, `ImportPhotoValidator`). Когда эти
пути тоже мигрируют на `ServerErrorCode`, helper можно будет удалить.

## Локализация

iOS-каталог `Localizable.xcstrings` содержит переводы en + ru для всех ключей выше. Бэкенду **не нужно** локализовать сообщения — клиент резолвит по ключу.

## Валидация

JSON-схема валидации контракта: [schema.json](schema.json).
