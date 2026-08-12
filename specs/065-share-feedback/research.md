# Research: Share your feedback

**Дата**: 2026-08-13
**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)

Phase 0. Неизвестные закрыты кодовой базой native + `recipe-scaler-web` и решениями clarify-сессии.

---

## R-001: Куда слать ops-сообщение

**Decision**: Тот же `MODERATION_ABUSE_ALERT_CHAT_ID` и фасад [`ops-alert.ts`](../../../recipe-scaler-web/server/src/services/ops-alert.ts), плюс новый `sendOpsTelegramDocument`.

**Rationale**: Пользователь явно указал «тому же пользователю, кому идёт модерация». Spec 063 уже держит numeric chat id @mikeozornin. Новый env не нужен.

**Alternatives considered**:
- Отдельный `FEEDBACK_ALERT_CHAT_ID` — лишняя конфигурация при одном получателе.
- Email / Linear issue — вне запроса.

---

## R-002: Хранение и moderation

**Decision**: multer `memoryStorage`, буферы живут только на время хендлера. Не вызывать `moderationService` и `moderationAbuseService.assertNotBlocked`.

**Rationale**: Пользователь: аттачи не через защиту и не в хранение. Это ops-канал, не user-generated public content.

**Alternatives considered**:
- Прогон картинок через OpenAI moderation «на всякий случай» — отвергнуто явно.
- S3 + signed URL в Telegram — это хранение, отвергнуто.
- Temp file на диске для Telegraf — только если buffer API не сработает (STOP в плане).

---

## R-003: Rate limit

**Decision**: 1 запрос / 60 с / `userId`, по образцу `deleteAccountRateLimiter` (key = `req.user_id`, fallback IP). Env: `FEEDBACK_RATE_LIMIT_WINDOW_MS` / `FEEDBACK_RATE_LIMIT_MAX_REQUESTS`.

**Rationale**: Clarify: «1 в минуту», не 5/час. Per-user, не per-IP: иначе NAT/debug-device делят квоту.

**Alternatives considered**:
- 5/час как delete-account — отвергнуто пользователем.
- Только global `rateLimiter` (100/15 мин) — слишком слабо для unmoderated attachments.

---

## R-004: Attach UI без камеры

**Decision**: `confirmationDialog` с двумя кнопками → `PhotosPicker` и `.fileImporter(allowedContentTypes: [.item])`. Камеры нет.

**Rationale**: Пользователь хотел «идиотский» iOS-диалог с опциями, затем уточнил убрать камеру, если можно. Photo Library покрывает скриншоты; Files — остальное. Не трогаем `NSCameraUsageDescription` (сейчас только QR).

**Alternatives considered**:
- Только fileImporter — хуже для скриншотов (Files, не Recents в Photos).
- Только PhotosPicker — нельзя приложить лог/zip.
- UIImagePickerController camera — лишний permission copy, отвергнуто.

---

## R-005: Success chrome

**Decision**: Очистить форму, остаться на экране, зелёный `TransientStatusBanner` с `checkmark.circle.fill`. Параметризовать symbol; shopping оставляет default `cart.badge.plus`.

**Rationale**: Пользователь отверг alert+pop. В приложении уже есть зелёный тост через `ShoppingFeedback.postStatus` → overlay в `AppShellView`.

**Alternatives considered**:
- Alert «спасибо» + pop — отвергнуто.
- Локальный overlay только на `AccountFeedbackView` — дубль chrome; канон уже app-shell.

---

## R-006: Multipart с текстовым полем

**Decision**: Расширить `APIClient.uploadMultipart` опциональным `fields: [String: String]`, существующие overload делегируют с `[:]`.

**Rationale**: Сейчас метод пишет только file parts. `message` должен быть form field, не query. Call sites assistant/avatar/import не должны сломаться.

**Alternatives considered**:
- JSON + base64 файлы — раздувает память, другой контракт.
- Отдельный `uploadFeedbackMultipart` — дубль boundary-кода.

---

## R-007: Telegram sendDocument vs sendPhoto

**Decision**: Всегда `sendDocument` из buffer.

**Rationale**: Смешанные типы (png + zip + pdf). `sendPhoto` ломается на не-картинках; `sendMediaGroup` — до 10 и только media.

**Alternatives considered**:
- sendPhoto для image MIME, sendDocument иначе — лишняя ветка, выигрыш маленький (превью в TG).
