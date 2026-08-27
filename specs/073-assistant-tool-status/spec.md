# Спецификация: Assistant tool-status UI — native

**Номер**: 073  
**Дата**: 2026-08-27  
**Статус**: In Progress  
**Канон (cross-platform)**: [`recipe-scaler/specs/073-assistant-tool-status/spec.md`](../../../specs/073-assistant-tool-status/spec.md)  
**Web (as-built эталон)**: [`recipe-scaler-web/specs/073-assistant-tool-status/spec.md`](../../../recipe-scaler-web/specs/073-assistant-tool-status/spec.md)  
**План native**: [plan.md](./plan.md)

---

## Границы

**В scope:** `AssistantSheet` UI + stream handling + i18n map + unit tests.

**Вне scope:** server, web, Figma layout.md.

---

## Пользовательские сценарии

### US1 — Processing placeholder

**Given** пользователь отправил сообщение, **When** стрим открыт но text ещё пуст, **Then** видна shimmer-строка с `assistant.processing` (не серый bubble «Думаю…»).

### US2 — Tool-status row на `tool-start`

**Given** активный стрим, **When** приходит `tool-start`, **Then** появляется отдельная строка с локализованным статусом; id prefix `optimistic-tool-status-`; `accessibilityIdentifier` = `assistant_tool_status_row`.

### US3 — Несколько tool calls

**Given** ассистент вызывает несколько tools подряд, **When** каждый `tool-start`, **Then** накапливаются отдельные строки (не перезапись последней).

### US4 — Persist после final

**Given** tool-status rows в сессии, **When** приходит `final`, **Then** строки остаются в списке до reload/switch thread.

### US5 — i18n parity

**Given** любой tool name из web `assistant-tool-status.ts`, **Then** native показывает эквивалентный статус (в т.ч. `vkusvill-*`).

---

## Positive invariants

- Widgets, follow-ups, pendingAction gate — без регрессии
- Tool-status / processing: без meta row (timestamp/copy)
- Stream error: удалить все `optimistic-*` включая tool-status

---

## Verification

1. `xcodebuild`
2. `bash scripts/lint-i18n.sh`
3. `AssistantToolStatusI18nTests`
4. Manual: search recipe / shopping list prompt → shimmer → tool row → stream

---

## Downstream

- **072-vkusvill-integration**: FR-VV-005 — native показывает `vkusvill-*` tool-status как web
- **021-assistant-full**: US9 → 073
