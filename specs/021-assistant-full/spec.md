# Спецификация: полный AI-ассистент

**Ветка**: `021-assistant-full`  
**Дата**: 2026-06-03  
**Статус**: 🟢 Готово (аудит 2026-06-15, US5 закрыт 2026-06-15, US8 добавлен 2026-07-22) — 8/8 US в коде. Подтверждаемые actions: UI только через `interactiveWidget` (quick replies), как на web; `pendingAction` в metadata — серверный gate + подписи user bubble. Sanitization — архитектурно (клиент шлёт только `recipeId`, сервер очищает контент). Haptic на завершение ответа: `.success` на `final`, `.error` на stream-error (US8).  
**Зависимости**: `015-assistant` (основной scope в production), `013` (account), recipe context 001/002  
**Эталон**: `assistant-sheet.tsx`, PRD § Assistant

## Контекст

Большая часть scope перенесена из 015 и **реализована в коде** (2026-06-15):

| US | Статус в коде |
|----|---------------|
| US1 инкрементальный стрим | ✅ `AssistantSheet.consumeStream` |
| US2 recipe attachment | ✅ IDs на сервер; client HTML sanitization — не найдена |
| US3 widgets | ✅ |
| US4 voice | ✅ |
| US5 actions | ✅ quick replies из `interactiveWidget` (web parity); submit как user message с `confirmValue`/`cancelValue`; `pendingAction` — metadata для gate и подписи bubble |
| US6 follow-up | ✅ |
| US7 threads | ✅ |
| US8 haptic на завершение ответа | ✅ `AssistantSheet.consumeStream` |

## Цель

Закрыть остаток: подтверждаемые actions (scale, add to shopping) и аудит sanitization контекста (FR-021-002).

## Пользовательские сценарии

### US1 — Инкрементальный стрим (P1)

**Когда** ассистент отвечает, **тогда** UI рендерит `text-delta` по мере поступления (Markdown subset), без блокировки > 100 ms между чанками (SC-002 из 015).

### US2 — Recipe attachment (P1)

**Когда** прикреплён рецепт, **тогда** контекст = name, servings, ingredients, plain instructions **без HTML/URL** (PRD security, FR-AST-002).

### US3 — Widgets (P2)

**Когда** приходит widget (`quick_replies`, `select`, `number_input`), **тогда** нативные контролы соответствующих типов.

### US4 — Voice (P3)

**Когда** запись голоса, **тогда** `POST transcribe`; ошибка `audio_too_long` локализована (лимиты 120s client / 180s server).

### US5 — Actions (P2)

**Когда** подтверждено действие (scale, add to shopping), **тогда** вызываются существующие сервисы iOS (`YjsSyncService`); save recipe success только после backend id/URL (FR-AST-004).

### US6 — Follow-up suggestions (P3)

До 3 shortcuts; visible text = submitted text; скрыты при widget / clarifying / destructive pending (PRD).

### US7 — Threads (P2)

Список и переключение тредов (`GET/POST /api/assistant/threads`).

### US8 — Haptic на завершение ответа (P3)

**Когда** ассистент дописал ответ в открытом чате (стрим завершился `final`), **тогда** устройство единоразово вибрирует success-паттерном (`UINotificationFeedbackGenerator.notificationOccurred(.success)`), чтобы пользователь с телефоном в руке узнал о готовности ответа без визуального контроля экрана. При stream-error срабатывает error-паттерн (`.error`), чтобы отличить нормальное завершение от сбоя. iOS-only через `#if os(iOS)`.

### US9 — Tool-status UI (P2) → [073-assistant-tool-status](../073-assistant-tool-status/spec.md)

**Когда** ассистент вызывает tools во время стрима, **тогда** native показывает отдельные tool-status строки и processing shimmer — паритет web ([`073` kanon](../../../specs/073-assistant-tool-status/spec.md)).

### US10 — Ответ не теряется при обрыве стрима (P1)

**Когда** стрим ответа оборвался (закрыт чат, приложение ушло в фон, сеть пропала, сервер закрыл ответ без `final`), **тогда** приложение не показывает ошибку сразу: сервер дописывает и сохраняет ответ сам, а клиент дожидается его и показывает сохранённую историю. Пользователю не нужно переотправлять вопрос, сервер не делает работу повторно.

## Требования

### FR-021-001 — Стрим UI

**Done (015)** — инкрементальное обновление в `AssistantSheet`.

### FR-021-002 — Sanitization контекста ✅

Архитектурно: клиент (`AssistantAPI.stream`) шлёт только `recipeId` (`attachedRecipeIds`) — никогда не встраивает ingredients/instructions в system prompt. Серверная сторона (`recipe-scaler-web` orchestrator) вытягивает recipe plain-text и фильтрует HTML/URL. На iOS доп. очистка не нужна.

### FR-021-003 — Widgets / actions ✅

Widgets — done (015). Actions — `pendingAction` в metadata (серверный gate); UI подтверждения только `interactiveWidget` (quick replies), как `assistant-message-list.tsx`. Сабмит — как user message с `confirmValue`/`cancelValue`.

### FR-021-004 — i18n

Все строки — локализованные ключи ru/en (см. 022).

### FR-021-005 — Haptic на завершение ответа ✅

iOS-only (через `#if os(iOS)`). Триггер — терминальные события стрима в `AssistantSheet.consumeStream`:
- `case .final` → `UINotificationFeedbackGenerator().notificationOccurred(.success)` — ответ дописан успешно.
- `case .error` → `UINotificationFeedbackGenerator().notificationOccurred(.error)` — stream-error (пользователь увидит локализованное сообщение об ошибке).

Ответ, восстановленный после обрыва стрима (FR-021-006), тоже даёт success-haptic; путь ошибки после неудачного восстановления — error-haptic.

Haptic срабатывает только когда чат открыт (пока стрим активен, sheet жив: закрытие → `streamTask?.cancel()` в `onDisappear`, поэтому отдельная проверка `AssistantRecipeContext.isAssistantSheetOpen` не нужна). На `textDelta`/`toolStart`/`textStart` haptic не срабатывает.

### FR-021-006 — Восстановление ответа после обрыва стрима

Контракт сервера: `respond-stream` может слать `{"type":"heartbeat"}` каждые ~15 с (клиент их пропускает); после отключения клиента сервер продолжает генерацию; `GET /api/assistant/threads/:id/messages` отдаёт `responseInProgress` (нет поля → `false`); новый ход во время идущего ответа отклоняется кодом `assistant.response.in-progress` (stream-событие `error`, HTTP 200; не-стрим маршрут — 409).

`AssistantSessionModel`:
- **Обрыв в `send()`** — любой `URLError` (и `NSURLErrorDomain`) или стрим, закрытый без `final`/`error` (`AssistantStreamInterruptedError`). Серверные `error`-события, HTTP-статусы и валидация — обычная ошибка, без восстановления. При обрыве optimistic-пузырь пользователя и стрим-плейсхолдер (с уже пришедшим текстом) остаются, `isSending` остаётся `true`, а модель опрашивает историю треда каждые ~2 с, пока `responseInProgress == true`, не дольше ~10 мин. Неудачный опрос повторяется с удвоением паузы (до 30 с).
- **Наш ход в истории** — последнее user-сообщение после всех сообщений, которые были на экране до отправки (по id), с текстом, равным отправленному после trim. Засчитывается, только если после него есть ответ ассистента (как в web `findSentUserTurn` + `findReplyAfter`). Нашёлся — `messages` заменяются серверной историей, success-haptic. Не нашёлся или истёк срок — прежний путь ошибки: optimistic-сообщения убираются, ввод и вложения восстанавливаются, пузырь ошибки («Не удалось связаться с сервером»), error-haptic.
- **Тред с идущим ответом** — `loadHistory` при `responseInProgress == true` показывает историю, typing-плейсхолдер и `isSending = true`, ждёт тем же опросом и подменяет историю финальной. Срок истёк — убирается только плейсхолдер.
- **`assistant.response.in-progress`** в `send()` — путь ошибки (локализованный пузырь, ввод восстановлен), затем то же ожидание идущего ответа с плейсхолдером.
- Всё ожидание принадлежит `streamTask` и привязано к `interactionGeneration` и `threadId`: `close`, `startNewChat`, `openThread`, новая отправка и logout его останавливают, после остановки ничего не приходит.
- Отправка (стрим и восстановление) обёрнута в `UIApplication.beginBackgroundTask` (`#if os(iOS)`, шов `AssistantSessionClient.beginBackgroundTask`), задача завершается всегда: по окончании, отмене и истечении времени.

Тайминги — `AssistantReplyRecoveryTiming` (в тестах миллисекунды). Тесты: `AssistantSessionModelTests` (обрыв после tool-start, стрим без `final`, ход не дошёл, `close` во время ожидания, тред с идущим ответом, `in-progress`), `AssistantThreadMessagesEnvelopeTests` (поле есть / `false` / отсутствует).

## Вне scope

- Переписывание серверной orchestration
- Desktop wide layout

## Критерии успеха

- **SC-001**: ✅ (attachment по recipeId).
- **SC-002**: ✅ инкрементальный стрим.
- **SC-003**: ✅ widgets.
- **SC-004**: ✅ actions — `interactiveWidget` + `submitWidgetValue` (US5, web parity 2026-06-16).

## Артефакты

- `contracts/assistant-stream.md` (delta/widget/final/voice)
- `quickstart.md`
