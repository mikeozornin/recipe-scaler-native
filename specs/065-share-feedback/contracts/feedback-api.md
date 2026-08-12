# Contract: `POST /api/feedback`

**Spec**: [spec.md](./spec.md)  
**Canonical**: [`recipe-scaler-web/specs/065-share-feedback/spec.md`](../../../../recipe-scaler-web/specs/065-share-feedback/spec.md)

## Endpoint

```
POST /api/feedback
Authorization: Bearer <token>   (или существующий auth, requireUserId)
Content-Type: multipart/form-data
```

### Fields

| Name | Part | Required | Constraints |
|------|------|----------|-------------|
| `message` | text | yes | trim, 1–4000 Unicode scalars |
| `files` | file, repeated | no | 0–5 parts, each ≤ 10_000_000 bytes, any MIME |

### Headers (optional, copied into Telegram text)

| Header | Example |
|--------|---------|
| `X-App-Language` | `ru` |
| `X-App-Version` | `1.4.0` |

## Responses

### 200

```json
{ "success": true }
```

Тело `data` нет. Id отзыва нет — ничего не сохранено.

### Errors

`error` — dot-key (spec 031). Клиент резолвит через `ServerErrorCode`.

| Status | `error` | Meaning |
|--------|---------|---------|
| 400 | `account.feedback.invalid` | empty/too-long message or >5 files |
| 400 | `account.feedback.too-large` | multer `LIMIT_FILE_SIZE` |
| 401/403 | existing auth keys | no session |
| 429 | `account.feedback.rate-limited` | 1 / 60s / user exceeded |
| 502 | `account.feedback.send-failed` | Telegram/chat/bot failure |

## Side effects

1. `sendMessage` в `MODERATION_ABUSE_ALERT_CHAT_ID` с метаданными + текстом.
2. По одному `sendDocument` на файл из memory buffer.
3. Buffers discarded. No DB, no S3, no disk, no moderation API.

## Client mapping

`AccountAPI.submitFeedback(message:files:)` → `APIClient.uploadMultipart(path: "/api/feedback", fields: ["message": …], fieldName: "files", files: …)`.

Rate limit и Telegram — только server; клиент показывает dot-key как есть.
