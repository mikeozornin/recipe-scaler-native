# Спецификация: полный AI-ассистент

**Ветка**: `021-assistant-full`  
**Дата**: 2026-06-03  
**Статус**: Draft (перенос недоделок из 015)  
**Зависимости**: `015-assistant` (MVP-чат готов), `013` (account), recipe context 001/002  
**Эталон**: `assistant-sheet.tsx`, PRD § Assistant

## Контекст

В 015 отгружен MVP: `AssistantSheet` + `AssistantAPI` (createThread, respond-stream), FAB-launcher. Стрим **читается, но рендерится только финалом** — нет инкрементального вывода. Остальные сценарии веба не реализованы.

## Цель

Мобильный паритет ассистента: живой стрим, контекст рецепта, виджеты, voice, подтверждаемые действия, follow-up.

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

## Требования

### FR-021-001 — Стрим UI

Переписать `AssistantSheet.send` на инкрементальное обновление сообщения (binding на накапливаемый текст), а не append финала.

### FR-021-002 — Sanitization контекста

Attachment-контент — не в system prompt; очистка HTML/URL до отправки.

### FR-021-003 — Widgets / actions

Маппинг типов веба на нативные контролы и сервисы.

### FR-021-004 — i18n

Все строки — локализованные ключи ru/en (см. 022).

## Вне scope

- Переписывание серверной orchestration
- Desktop wide layout

## Критерии успеха

- **SC-001**: Вопрос по открытому рецепту → корректное имя рецепта в ответе.
- **SC-002**: Стрим обновляет UI инкрементально (видно набор текста).
- **SC-003**: Widget `quick_replies` → нативные кнопки; выбор отправляет текст.
- **SC-004**: Подтверждённый «add to shopping» → пункт в списке покупок.

## Артефакты

- `contracts/assistant-stream.md` (delta/widget/final/voice)
- `quickstart.md`
