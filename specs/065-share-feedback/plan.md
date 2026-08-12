# План: Share your feedback

**Дата**: 2026-08-13  
**Спека**: [spec.md](./spec.md)  
**Canonical API**: [`../recipe-scaler-web/specs/065-share-feedback/spec.md`](../../../recipe-scaler-web/specs/065-share-feedback/spec.md)  
**Ветка**: работа на `master` (AGENTS.md: small fixes на master). Объём средний: новый nested screen + REST + Telegram forward.

> Канонический project template для Recipe Scaler Native. Артефакт пишется на
> русском.

## Границы

- **В scope**:
  - Native: второй ряд в Support Recipe Scaler, `AccountFeedbackView`, multipart-клиент, i18n, параметризация иконки зелёного тоста.
  - Server (`recipe-scaler-web`): `POST /api/feedback`, rate limit 1/мин/user, forward в `MODERATION_ABUSE_ALERT_CHAT_ID`, без хранения и без moderation.
- **Вне scope**:
  - Web-форма, камера, persist черновика, debug-log auto-attach, Watch/extensions, БД/S3.
- **STOP conditions**:
  - Если Telegram `sendDocument` из memory buffer в Telegraf не принимает `Buffer` без temp file — STOP и обсудить `Input.fromBuffer` vs короткий tmp + unlink в `finally` (tmp не считается «хранением», но это уже компромисс; предпочтителен buffer).
  - Если `uploadMultipart` нельзя расширить text-fields без поломки assistant/avatar/import — STOP, добавить отдельный overload, не ломая существующие call sites.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | Отзыв не в Y.Doc. |
| Web parity | PASS | UI iOS-only (как StoreKit tips). REST auxiliary; web-форму сознательно не делаем. Контракт общий. |
| Offline-first | PASS | Экран и черновик доступны офлайн; Send disabled без сети. Не ставим в SQLite queue — это не CRDT-мутация. |
| Native UI | PASS | SwiftUI List/Form, PhotosPicker, fileImporter. WebView не трогаем. |
| Phased delivery | PASS | Самостоятельная единица. |
| i18n | PASS | Все строки `account.feedback.*` в xcstrings en+ru; серверные ошибки — dot-keys. |
| Documentation | PASS | Native spec + web spec + FEATURE-MAP + этот план + contract. |

## Очерёдность

1. **Сервер `POST /api/feedback`** — клиенту некуда слать без endpoint; зависимости: ops-alert, multer, requireUserId.
2. **Расширить `uploadMultipart` + `AccountAPI.submitFeedback`** — зависит от 1 (контракт полей).
3. **Тост: параметризовать SF Symbol** — независимо от 1–2, нужно до UI успеха.
4. **`AccountFeedbackView` + второй ряд секции + i18n** — зависит от 2 и 3.
5. **Тесты + build + lint-i18n** — зависит от 1–4.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `../recipe-scaler-web/server/src/routes/feedback.ts` | Создать | Хендлер multipart. |
| `../recipe-scaler-web/server/src/app.ts` | Изменить | `app.use('/api/feedback', …)`. |
| `../recipe-scaler-web/server/src/services/ops-alert.ts` | Изменить | `sendOpsTelegramDocument(buffer, filename)`. |
| `../recipe-scaler-web/server/src/middleware/rateLimiter.ts` | Изменить | `feedbackRateLimiter` 60s / max 1 / key=`userId`. |
| `../recipe-scaler-web/server/src/__tests__/feedback-route.test.ts` | Создать | US1–US6 web spec. |
| `RecipeScalerCore/Networking/APIClient+Requests.swift` | Изменить | overload `uploadMultipart` с text fields. |
| `RecipeScalerNative/Services/AccountAPI.swift` | Изменить | `submitFeedback(message:files:)`. |
| `RecipeScalerCore/Networking/ServerErrorCode.swift` | Изменить | `account.feedback.*` cases. |
| `specs/031-error-i18n/server-error-keys.md` | Изменить | таблица ключей. |
| `RecipeScalerNative/Views/AccountFeedbackView.swift` | Создать | экран формы. |
| `RecipeScalerNative/Views/AccountTipsSection.swift` | Изменить | второй NavigationLink. |
| `RecipeScalerNative/Views/TransientStatusBanner.swift` | Изменить | `symbolName` параметр, default `cart.badge.plus`. |
| `RecipeScalerNative/Utils/ShoppingListPlainText.swift` | Изменить | `postStatus(_:symbolName:)`. |
| `RecipeScalerNative/Views/AppShellView.swift` | Изменить | хранить payload (message + symbol). |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменить | `account.feedback.*`. |
| `RecipeScalerNative/AccessibilityIdentifiers.swift` | Изменить | `account_feedback_*`. |
| `RecipeScalerNativeUITests/Pages/AccountPage.swift` | Изменить | page object. |
| `RecipeScalerNativeTests/LocalizationConsistencyTests.swift` | Изменить | новые ключи. |
| `RecipeScalerNativeTests/AccountFeedbackSubmitTests.swift` | Создать | single-flight, empty disabled, size/count. |

## Downstream consumers

- **SwiftUI views**: `AccountTipsSection`, `AccountFeedbackView`, `TransientStatusBanner`, `AppShellView`.
- **Cross-process**: N/A — widgets/extensions/watchOS/Live Activity/App Intents не трогаем.
- **Sync boundaries**: новый REST `POST /api/feedback`. Yjs/Socket.IO без изменений. Web UI не подключает endpoint в этом заходе.
- **Persisted state**: N/A — draft только `@State` экрана.
- **Tests / verify scripts**: server vitest `feedback-route.test.ts`; native unit + LocalizationConsistency; UITest ряда/экрана. Отдельный `verify-065-*.sh` не заводим, если UITest покрывает наличие ряда.

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| Открыть секцию tips | Два ряда: tip, feedback | UITest `account_feedback_menu` |
| Send текст, 2xx | Форма пустая + зелёный тост checkmark, экран открыт | ручная + UITest тоста |
| Send офлайн | Send disabled | `AccountFeedbackSubmitTests` |
| Повтор Send < 60 с | 429, форма цела | `feedback-route.test.ts` US3 |
| 1..5 файлов | Telegram `sendMessage` + N `sendDocument`; moderation не вызывалась | `feedback-route.test.ts` US2/US6 |
| Logout во время Send | нет тоста, буферы пусты | teardown в unit (cancel + epoch mismatch) |

Негативная формулировка «не должно сломаться» сама по себе недостаточна.

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| `submitFeedback` | `userId` + `submitGeneration` (Int, ++ на disappear/logout) | `Task.isCancelled`; generation совпадает; тот же userId | `onDisappear` / logout cancels `submitTask` | unit: после await generation++ → не clear, не toast |
| PhotosPicker `loadTransferable` | attachment slot id | экран ещё mounted; count < 5 | onDisappear cancel load Task | stale load не добавляет файл |
| fileImporter copy | security-scoped URL | startAccessing → copy → stopAccessing в `defer` | sync в callback | N/A — короткий copy |

Single-flight: `isSubmitting` ставится до первого await, снимается `defer`.

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| logout | draft/attachments discarded с view | `submitTask?.cancel()` | N/A | PhotosPicker/fileImporter dismissed | нет тоста чужой сессии |
| account switch | то же | то же | N/A | N/A | то же |
| stale session / cold start | view не restored | N/A | N/A | N/A | пустой экран при следующем входе |
| reconnect / partial failure | draft жив в `@State` | busy сброшен через defer | N/A | N/A | форма цела, Send снова enabled |

## Cross-target contracts

- **Canonical owner**: web spec `065-share-feedback` + [contracts/feedback-api.md](./contracts/feedback-api.md).
- **Writer/reader targets**: iOS app пишет; server читает и форвардит в Telegram. Web UI не writer в этом заходе.
- **Validator/normalizer**: server trim + length; multer size/count; filename sanitize только для Telegram `filename`.
- **Raw literal exceptions**: N/A — UI через xcstrings; ops Telegram text на английском (ops, не user-facing).

## Locale / theme consumers

- SwiftUI environment: `Text("account.feedback.*")`, `.localizedNavigationTitle("account.feedback.title")`, `.appBody()` / `.appFootnote()`.
- UIKit / notification categories: N/A.
- Widgets / Live Activities / App Intents: N/A.
- Cached or generated assets: N/A.
- `.system` effective value: зелёный тост уже `.green` / glass tint; не хардкодим новый цвет.

## Compatibility / migration

- Current format/contract: новый endpoint, нет предыдущей версии.
- Previous supported format: N/A.
- Missing version/default behavior: нет `metadata.version` — это не export/import файл.
- Unknown future version/ID behavior: неизвестный dot-key → существующий `ServerErrorCode.from(serverValue:fallback:)` с fallback `account.feedback.send-failed`.
- Required legacy fixture tests: N/A.

## Unknown IDs and fallback policy

- DEBUG/CI: неизвестный `ServerErrorCode` не добавляем как string sniffing; только typed cases.
- Release: unknown server error → fallback dot-key, structured log.
- Legacy aliases: нет.

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app`/`.appex` assertion |
|----------|----------|---------------|----------------|---------------------------------|
| Новые ресурсы не генерируются | N/A | N/A | N/A | N/A |

## Human gates

- [x] `layout.md` reviewed by human — **N/A**: не Figma-driven; nested account List.
- [x] `layout-audit.json` static audit passed — **N/A**.
- [x] Human acceptance artifact актуален — **N/A**.
- [ ] Отдельный review-agent выполнен; self-review не считается заменой — **ожидается после реализации**.

> **Human gate для плана**: AGENTS.md требует human review плана перед tasks/implementation. Останавливаюсь здесь и жду явного «продолжай» / `/speckit-tasks` перед кодом.

## Verification

- Server: `cd ../recipe-scaler-web/server && npx vitest run src/__tests__/feedback-route.test.ts` — exit 0, US1–US6.
- Native build: `SIM_ID="$(bash scripts/resolve-simulator.sh)"` + `xcodebuild -scheme RecipeScalerNative -destination "platform=iOS Simulator,id=$SIM_ID" build` — exit 0.
- Native tests: `AccountFeedbackSubmitTests`, `LocalizationConsistencyTests`.
- `bash scripts/lint-i18n.sh` — без новых предупреждений.
- Ручная: Profile → Support Recipe Scaler → Share your feedback → текст → Send → тост + пустая форма; Attach photos/files; офлайн Send disabled.
- Expected evidence: vitest + xcodebuild exit 0.

## Rollback / maintenance

- Как откатить: убрать второй ряд и `AccountFeedbackView`; серверный route можно оставить (без клиента мёртв) или снять mount в `app.ts`.
- Что будет взаимодействовать: будущая web-форма на тот же `POST /api/feedback`; не менять поля без bump контракта.
- Временные allowlist/quarantine: нет.

---

## UI (native)

Секция — тот же `Section` в [AccountTipsSection.swift](../../RecipeScalerNative/Views/AccountTipsSection.swift):

1. существующий NavigationLink «Send a tip»
2. новый NavigationLink → `AccountFeedbackView`

Экран:

- `List` / `Form`, `.listStyle(.insetGrouped)`, `.appListBodyTypography()`, `.localizedNavigationTitle("account.feedback.title")`, `.navigationBarTitleDisplayMode(.inline)`
- Секция текста: `TextEditor` + placeholder как в `ImportRecipeSheet` (`ZStack` + `.scrollContentBackground(.hidden)`)
- Секция аттачей: кнопка Attach → `.confirmationDialog` с `account.feedback.attach-photos` / `account.feedback.attach-files`; список имён + delete
- Toolbar trailing: Send (`account.feedback.send`), disabled по FR-007; ProgressView пока `isSubmitting`
- PhotosPicker: `matching: .images`, `maxSelectionCount` = оставшиеся слоты
- fileImporter: `allowedContentTypes: [.item]`, `allowsMultipleSelection: true`, security-scoped copy в `Data`
- Камеры нет, `NSCameraUsageDescription` не трогаем

Успех: `message = ""`; `attachments = []`; `ShoppingFeedback.postStatus(Bundle.currentLocalizedString("account.feedback.sent"), symbolName: "checkmark.circle.fill")`.

Ошибка: `errorMessage` в footer секции, `.foregroundStyle(.red)`, `.appFootnote()`.

## Тост

Сейчас `TransientStatusBanner` хардкодит `cart.badge.plus`, а notification несёт только `String`.

- Добавить `symbolName: String = "cart.badge.plus"` в баннер.
- `ShoppingFeedback.postStatus(_ message: String, symbolName: String = "cart.badge.plus")`.
- Notification `object`: либо payload struct, либо оставить message в object и symbol в `userInfo["symbol"]` — предпочтительно маленький `TransientStatusPayload` (message + symbolName), с fallback: если object всё ещё `String` (на случай пропущенного call site) — корзина как сейчас.
- `AppShellView`: `@State` payload вместо голой строки.

## Сеть (native)

Расширить [APIClient+Requests.swift](../../RecipeScalerCore/Networking/APIClient+Requests.swift):

```swift
uploadMultipart(
  path: String,
  fields: [String: String] = [:],
  fieldName: String,
  files: [(fileName: String, data: Data, mimeType: String)]
) async throws -> Data
```

Существующие overload без `fields` делегируют в новый (`fields: [:]`). Не ломать assistant/avatar/import.

`AccountAPI.submitFeedback`: path `/api/feedback`, field `files`, fields `["message": text]`, headers `X-App-Language`, `X-App-Version`.

## Сервер

Новый router, не смешивать с `users.ts` image-upload (там moderation).

Порядок middleware: `requireUserId` → `feedbackRateLimiter` → multer array `files` (max 5, 10 MB, memoryStorage) → handler.

Handler:

1. trim `message`; 400 invalid если пусто или > 4000
2. собрать ops-текст (userId, username/name из профиля если дёшево, иначе userId; platform `ios`; headers)
3. `sendOpsTelegramAlert(text)`
4. для каждого файла `sendOpsTelegramDocument`
5. если любой Telegram call false → 502
6. 200 `{ success: true }`

Не вызывать `moderationService` / `moderationAbuseService`.

`sendOpsTelegramDocument`: тот же chat id, `bot.telegram.sendDocument(chatId, { source: buffer, filename })`. Fail-open лог + `false`, как text alert.

## i18n keys

| Key | en | ru |
|-----|----|----|
| `account.feedback.menu` | Share your feedback | Оставить отзыв |
| `account.feedback.title` | Feedback | Отзыв |
| `account.feedback.placeholder` | What should we know? | Что нам стоит знать? |
| `account.feedback.attach` | Attach | Приложить |
| `account.feedback.attach-photos` | Photo Library | Медиатека |
| `account.feedback.attach-files` | Files | Файлы |
| `account.feedback.send` | Send | Отправить |
| `account.feedback.sent` | Thanks — we got your feedback. | Спасибо, отзыв получен. |
| `account.feedback.send-failed` | Couldn’t send your feedback. Try again. | Не получилось отправить отзыв. Попробуйте ещё раз. |
| `account.feedback.rate-limited` | Please wait a minute before sending again. | Подождите минуту перед следующей отправкой. |
| `account.feedback.invalid` | Write a short message before sending. | Напишите короткое сообщение перед отправкой. |
| `account.feedback.too-large` | A file is larger than 10 MB. | Файл больше 10 МБ. |
| `account.feedback.max-files` | You can attach up to 5 files. | Можно приложить не больше 5 файлов. |

Офлайн: существующий `account.offline.alert` (Send disabled, отдельную строку не плодим).

## Accessibility

| ID | Элемент |
|----|---------|
| `account_feedback_menu` | ряд в секции |
| `account_feedback_editor` | TextEditor |
| `account_feedback_attach` | кнопка Attach |
| `account_feedback_send` | Send |
| `account_feedback_error` | текст ошибки |
| `account_feedback_attachment_<index>` | строка файла |

## Composition root

Нового сервиса в `AppContainer` нет: `AccountAPI` — enum как сейчас; state экрана локальный. `.shared` не добавляем.
