# Спецификация: AI-ассистент

**Ветка**: `015-assistant`  
**Дата**: 2026-06-02  
**Статус**: Draft  
**Зависимости**: `007`, `013` (account), recipe context from 001/002  
**Эталон**: `assistant-sheet.tsx`, PRD § Assistant

## Контекст

Глобальный ассистент в вебе: threads, recipe attachments, streaming NDJSON, voice (120s client / 180s server), widgets (`quick_replies`, `select`, `number_input`), follow-up suggestions (max 3, правила PRD).

iOS: нет UI и нет streaming client.

## Цель

Мобильный паритет: sheet поверх app shell, те же ограничения sanitization context и языка ответа.

## Пользовательские сценарии

### US1 — Chat stream (P1)

**Когда** пользователь отправляет сообщение, **тогда** `POST .../respond-stream` — incremental UI render (Markdown subset для assistant).

### US2 — Recipe attachment (P1)

**Когда** прикреплён рецепт, **тогда** context = name, servings, ingredients, plain instructions (без HTML URLs — PRD).

### US3 — Widgets (P2)

**Когда** assistant возвращает widget, **тогда** нативные контролы тем же типам, что веб.

### US4 — Voice (P3)

Запись → `POST transcribe`; ошибка `audio_too_long` локализована.

### US5 — Actions (P2)

Подтверждённые действия (scale, add to shopping) вызывают существующие сервисы iOS.

### US6 — Follow-up suggestions (P3)

До 3 shortcuts; visible text = submitted text; скрыты при widget / clarifying / destructive pending (PRD).

## Требования

### FR-AST-001

Threads API: `GET/POST /api/assistant/threads` — `llm/API.md`.

### FR-AST-002

Untrusted attachment content — не system prompt (PRD security).

### FR-AST-003

Launcher FAB position — над tab bar + timer panel offset (как `mobileLauncherBottom` на вебе).

### FR-AST-004

Save recipe success только после backend id/URL (PRD).

## Вне scope

- Переписывание orchestration на сервере
- Desktop wide layout assistant

## Критерии успеха

- **SC-001**: Вопрос по открытому рецепту → ответ с корректным именем рецепта.
- **SC-002**: Stream не блокирует UI > 100ms между chunks (subjective smooth).

## Артефакты

- `contracts/assistant-stream.md`
- `quickstart.md`