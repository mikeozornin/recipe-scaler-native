# Data Model: Share your feedback

**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)

## Сущности

Сервер **не персистит** отзыв. Модель — in-memory на клиенте + эфемерные multer buffers на сервере.

### `FeedbackDraft` (iOS, `@State` экрана)

| Поле | Тип | Правила |
|------|-----|---------|
| `message` | `String` | Send enabled только если `trim` непустой и `count ≤ 4000` |
| `attachments` | `[FeedbackAttachment]` | 0..5 |
| `isSubmitting` | `Bool` | single-flight |
| `submitGeneration` | `Int` | ++ при disappear/logout |
| `errorMessage` | `String?` | локализованный текст; nil после успеха |

Не пишется в UserDefaults / SQLite / Keychain. Уничтожается с view.

### `FeedbackAttachment` (iOS)

| Поле | Тип | Правила |
|------|-----|---------|
| `id` | `UUID` | identity в ForEach |
| `fileName` | `String` | display + multipart filename |
| `mimeType` | `String` | `public.item` → `application/octet-stream` если неизвестен |
| `data` | `Data` | целиком в памяти |
| `byteCount` | `Int` | `data.count`; reject если > 10_000_000 до добавления в массив |

### Server (эфемерно)

| Поле | Источник | Правила |
|------|----------|---------|
| `message` | multipart text | trim, 1..4000 |
| `files[]` | multer memory | 0..5, каждый ≤ 10_000_000 |
| `userId` | `req.user_id` | обязателен |
| `locale` | `X-App-Language` | optional |
| `appVersion` | `X-App-Version` | optional |

После handler buffers недоступны. Таблиц/миграций нет.

## Validation

| Правило | Где | Эффект |
|---------|-----|--------|
| empty/whitespace message | client + server | Send disabled / 400 `account.feedback.invalid` |
| message > 4000 | client + server | Send disabled или 400 |
| > 5 files | client + server | не добавлять / 400 invalid |
| file > 10 MB | client + multer | не добавлять + `account.feedback.too-large` / 400 |
| unauthenticated | client + `requireUserId` | Send disabled / 401 |
| second request < 60s | `feedbackRateLimiter` | 429 `account.feedback.rate-limited` |

## State transitions (экран)

```
idle → submitting → idle+empty+toast     (2xx)
idle → submitting → idle+draft+error     (4xx/5xx/cancel)
idle → submitting → discarded            (disappear/logout, generation mismatch)
```
