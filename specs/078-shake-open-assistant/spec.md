# Спецификация: Встряхнуть → открыть ассистента

**Feature Branch**: `078-shake-open-assistant`  
**Created**: 2026-09-30  
**Status**: Draft  
**Input**: Встряхнуть телефон → открыть диалог ассистента. В настройках (секция Интерфейс / Параметры, рядом с языком и КБЖУ) — тумблер «Встряхнуть, чтобы открыть ассистента», **по умолчанию выкл**. Если открыт рецепт — открыть ассистента и прикрепить этот рецепт; если рецепта нет — новый чат и сразу начать запись голоса. Разумный паритет: обе ветки стартуют голос; ветка с рецептом ещё и прикрепляет.

**Зависимости**:
- [015-assistant](../015-assistant/spec.md) / sheet + composer + voice
- [074-assistant-tab-entry](../074-assistant-tab-entry/spec.md) — programmatic open (`pendingAssistantTabOpen` / `openAssistantManually`)
- [007-app-shell-navigation](../007-app-shell-navigation/spec.md) — `AppShellView`, `AssistantRecipeContext.visibleRecipeId`

## Границы

**В scope:**
- Preference `shakeToOpenAssistantEnabled` в UserDefaults / `@AppStorage`, default **false**.
- Тумблер в `AccountView` секции `account.section.preferences` (язык / тема / КБЖУ).
- App-wide детектор shake через `UIWindow.motionEnded` + Notification + debounce.
- При shake (pref ON): открыть `AssistantSheet`; прикрепить текущий рецепт если `visibleRecipeId` есть; всегда стартовать voice recording (обе ветки); без рецепта — force new chat.
- i18n EN+RU; a11y id тумблера; unit-тесты preference / debounce / request routing.

**Вне scope:**
- Web parity.
- Watch / widgets / extensions.
- CMMotionManager / custom accelerometer thresholds.
- Изменение wire protocol ассистента.
- Figma layout (стандартный `Toggle` в List — без `layout.md`).
- Переопределение системного Shake to Undo (зовём `super`; конфликт с Undo — open question).

## Конституционная проверка

| Gate | Статус | Evidence |
|------|--------|----------|
| CRDT-first | N/A | Только UI/preference |
| Web parity | N/A | Native-only gesture |
| Offline-first | PASS | Sheet уже гейтит offline; voice start при offline не ломает карточку |
| Native UI | PASS | SwiftUI toggle + UIKit motion bridge |
| Phased delivery | PASS | pref → detector → open/attach/voice → settings → tests |
| i18n | PASS | xcstrings, без fallback |
| Documentation | PASS | spec, plan, research, tasks |

## Clarifications

### Session 2026-09-30

- Q: Default тумблера? → A: **OFF**.
- Q: Где тумблер? → A: Секция Preferences / Параметры (язык, тема, КБЖУ).
- Q: Голос при открытом рецепте? → A: Да, обе ветки стартуют voice; с рецептом ещё auto-attach.
- Q: Новый чат при рецепте? → A: Нет — только attach. Без рецепта — force new chat.
- Q: Что если sheet уже открыт? → A: Не dismiss/re-present; attach (если нужно) + start voice.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Включил и встряхнул без рецепта (Priority: P1)

Пользователь включает тумблер в Параметрах. На любом экране без открытой карточки рецепта встряхивает телефон — открывается ассистент на **новом** чате и сразу идёт запись голоса (после mic permission).

**Why this priority**: это основной hands-free вход без контекста.

**Independent Test**: pref ON → список рецептов → Hardware → Shake Gesture → sheet + recording UI.

**Acceptance Scenarios**:

1. **Given** pref OFF, **When** shake, **Then** ассистент не открывается.
2. **Given** pref ON, нет `visibleRecipeId`, **When** shake, **Then** sheet открыт, thread пустой/new chat, voice recording стартовал (или показан mic prompt).
3. **Given** pref ON и sheet уже открыт без рецепта, **When** shake, **Then** sheet не мигает; voice стартует если ещё не recording.

---

### User Story 2 — Встряхнул на карточке рецепта (Priority: P1)

На `YDocRecipeDetailView` с выставленным `visibleRecipeId` пользователь встряхивает телефон — ассистент открывается с этим рецептом **уже в attachments**, голос стартует.

**Why this priority**: контекстный ask-about-recipe — вторая половина ценности.

**Independent Test**: открыть рецепт → shake → chip рецепта в composer attachments; recording UI.

**Acceptance Scenarios**:

1. **Given** pref ON и `visibleRecipeId == R`, **When** shake, **Then** sheet открыт, `R` в `attachments`, voice стартует.
2. **Given** pref ON, sheet уже открыт на карточке R, R ещё не attached, **When** shake, **Then** R появляется в attachments и voice стартует.

---

### User Story 3 — Тумблер в настройках (Priority: P2)

В Профиле → Параметры виден тумблер с локализованным названием. По умолчанию выкл. Переключение переживает cold start.

**Acceptance Scenarios**:

1. **Given** fresh install, **When** открыть Параметры, **Then** тумблер OFF.
2. **Given** включил тумблер, убил процесс, **When** снова открыл, **Then** тумблер ON.

### Edge Cases

- Shake во время background / inactive — игнор.
- Двойной shake за < debounce (~0.8–1.0 s) — один fire.
- Offline: sheet открывается в offline state; voice start безопасен (ошибка mic/API не крашит).
- Logout: pending shake request очищается вместе с assistant pending.
- Shake to Undo в текстовом поле — `super.motionEnded` сохраняет системное поведение; наш fire при pref ON может идти параллельно (документировано).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Preference key `shakeToOpenAssistantEnabled`, missing key → false.
- **FR-002**: Toggle в `preferencesSection` AccountView; i18n `account.shake-open-assistant.label` (+ optional footer).
- **FR-003**: App-wide shake via `UIWindow.motionEnded(.motionShake)` → Notification; debounce ≥ 0.8 s.
- **FR-004**: Pref ON + foreground → open assistant (или reuse open sheet).
- **FR-005**: Если `AssistantRecipeContext.visibleRecipeId` не nil — auto-attach этот рецепт в attachments composer (не только context tag).
- **FR-006**: Если рецепта нет — `startNewChat` перед voice.
- **FR-007**: Обе ветки запрашивают start voice recording через composer (тот же `AssistantVoiceRecorder.start()`).
- **FR-008**: Logout clears pending shake open request.

### Positive invariants

| Effect | Invariant | Test |
|--------|-----------|------|
| Missing UserDefaults key | `isEnabled == false` | `ShakeToOpenAssistantPreferenceTests` |
| Debounce 0.5 s between shakes | second ignored | debounce unit |
| Shake request with recipeId | attachRecipeId set, forceNewChat false | coordinator/routing test |
| Shake request without recipeId | forceNewChat true | same |

## Verification

- `xcodebuild` build (RecipeScalerNative / Dev)
- `bash scripts/lint-i18n.sh`
- Unit tests preference + debounce
- Manual: Simulator Device → Shake / ⌘⌃Z with pref ON/OFF; recipe detail vs list
