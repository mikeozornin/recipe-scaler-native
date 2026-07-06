# Спецификация: AI-ассистент

**Ветка**: `015-assistant`  
**Дата**: 2026-06-02  
**Статус**: 🟢 Реализовано почти полностью (аудит 2026-06-15). Остаток actions → [021-assistant-full](../021-assistant-full/spec.md)  
**Зависимости**: `007`, `013` (account), recipe context from 001/002  
**Эталон**: `assistant-sheet.tsx`, PRD § Assistant

## Аудит реализации (2026-06-15)

| Требование | Статус |
|------------|--------|
| US1 chat stream (инкрементальный) | ✅ `textDelta` в `AssistantSheet` |
| US2 recipe attachment | ✅ `AssistantComposer` + `attachedRecipeIds` |
| US3 widgets | ✅ `AssistantMessageFooter` (quick_replies, select, number_input) |
| US4 voice | ✅ `AssistantVoiceRecorder` + transcribe API |
| US5 actions (scale/add to shopping) | ❌ → **021** |
| US6 follow-up suggestions | ✅ до 3 shortcuts |
| US7 threads | ✅ `AssistantThreadListSheet` |
| FR-AST-003 FAB position | ✅ |

## Прошлый аудит (2026-06-03)

MVP-чат только; стрим без инкрементального UI — устарел.

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

**UI parity с веб-коммитом `a9f193ff` (2026-07-05):**

- `AssistantRecordingShimmer` — анимированный `MeshGradient` 4×4 (iOS 18+) через весь composer shell во время `recording`/`transcribing` (`AssistantComposer.swift`). Один диагональный flow-band переливается cyan↔sky-blue, без «многоточного моргания»; reduce-motion → статичный градиент. Для iOS 17 — fallback на `LinearGradient` с теми же цветами.
- `AssistantVoiceLevelMeter` переписан как «tape»: 2pt бары, gap 2pt, окно ~40s (200 баров при одном баре на ~200ms — с запасом больше любого реального видимого количества, см. `AssistantVoiceRecorder.meterBarWindow`). Высота каждого бара предвычислена в `AssistantVoiceRecorder.barHeights` и стабильна после записи (web peak-RMS parity). Каждый бар идентифицирован по абсолютному индексу в `barHeights`, поэтому добавление нового бара справа вызывает появление, а не морфинг соседних. Новые семплы справа, старые скроллятся влево.
- `recordingControls`: X (cancel — сбрасывает запись без транскрипции, `voiceRecorder.cancel()`) + meter + ✓ (stop, `symbolEffect(.pulse)`). Web `check`/`xmark` icons parity.
- `transcribingControls`: центрированный `ProgressView` + localized label, фиксированная высота `AppToolbarStyle.minimumTapSide` — исправляет скачки высоты composer между состояниями (web `h-9` parity).
- Composer shell border → `.clear` во время recording/transcribing (web `border-transparent` parity).
- i18n: `assistant.voice-cancel` (en/ru); accessibility id `assistantVoiceCancelButton`.

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