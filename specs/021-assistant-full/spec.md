# Спецификация: полный AI-ассистент

**Ветка**: `021-assistant-full`  
**Дата**: 2026-06-03  
**Статус**: 🟡 Почти готово (аудит 2026-06-15) — 6/7 US в коде; остаток: подтверждаемые actions + sanitization audit  
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
| US5 actions | ❌ `AssistantPendingAction` в моделях, UI подтверждения нет |
| US6 follow-up | ✅ |
| US7 threads | ✅ |

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

## Требования

### FR-021-001 — Стрим UI

**Done (015)** — инкрементальное обновление в `AssistantSheet`.

### FR-021-002 — Sanitization контекста

Attachment-контент — не в system prompt; очистка HTML/URL до отправки.

### FR-021-003 — Widgets / actions

Widgets **done (015)**. Actions — маппинг на `YjsSyncService` / shopping **todo**.

### FR-021-004 — i18n

Все строки — локализованные ключи ru/en (см. 022).

## Вне scope

- Переписывание серверной orchestration
- Desktop wide layout

## Критерии успеха

- **SC-001**: ✅ (attachment по recipeId).
- **SC-002**: ✅ инкрементальный стрим.
- **SC-003**: ✅ widgets.
- **SC-004**: ❌ actions — todo.

## Артефакты

- `contracts/assistant-stream.md` (delta/widget/final/voice)
- `quickstart.md`
