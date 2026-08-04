# Layout: CookingModeView (peek-3 + voice + timers)

**Spec**: [spec.md](./spec.md)
**Figma**: _(макета нет — layout проектируется с нуля по web parity и iOS HIG)_

> Черновик для **ревью человеком** перед реализацией view. После согласования —
> источник истины для приёмки и `layout-audit.json`.

---

## Canvas

iOS 17+ phone (портретная ориентация, поддержка rotation в v1.1; v1 — fixed portrait).

| Параметр | Min (iPhone SE 3) | Max (iPhone 16 Pro Max) |
|----------|-------------------|--------------------------|
| Screen | 320 × 568 pt | 430 × 932 pt |
| Safe area | top 20 + bottom 0 | top 59 + bottom 34 (Dynamic Island) |
| Content area | 320 × 548 pt | 430 × 839 pt |
| Padding | 16 pt | 16 pt |
| Effective width | 288 pt | 398 pt |

Все размеры — **адаптивные**, никаких fixed width (кроме badge иконок/таймеров):

- `.frame(maxWidth: .infinity)` — горизонталь.
- `.frame(minHeight: 44)` — tap target HIG.
- Скролл — встроенный в `ScrollViewReader`.

---

## Токены

Один файл: `RecipeScalerNative/Views/Cooking/CookingLayout.swift`

| Token | Значение | Назначение |
|-------|----------|------------|
| `padding` | 16 pt | content padding от края экрана |
| `stepCardSpacing` | 12 pt | вертикальный gap между step cards |
| `peekEdgeVisible` | 24 pt | сколько пикселей соседней карточки видно сверху/снизу |
| `stepCardCornerRadius` | 16 pt | corner radius карточки шага |
| `stepCardFocusedElevation` | 1 pt | shadow elevation фокусной карточки (v1 — опционально, можно без) |
| `stepNumberBadgeSize` | 36 pt | диаметр круглого badge с номером |
| `stepNumberBadgeFontSize` | 18 pt | Martian Mono medium внутри badge |
| `stepTextFontSize` | 18 pt | Martian Grotesk body шага (больше стандарта 16 для иммерсивности) |
| `stepTextLineSpacing` | 6 pt | line spacing внутри шага |
| `voicePillHeight` | 36 pt | высота voice status pill |
| `voicePillCornerRadius` | 18 pt | pill radius (половина высоты) |
| `voicePillIconSize` | 14 pt | SF Symbol внутри pill |
| `voicePillFontSize` | 14 pt | Martian Grotesk compact |
| `voicePillHorizontalPadding` | 12 pt | padding внутри pill |
| `voicePillTopInset` | 8 pt | от top safe area до pill |
| `voicePillSideInset` | 16 pt | от левого/правого края до pill |
| `controlButtonSize` | 56 pt | prev/next кнопка (больше HIG min 44) |
| `controlButtonIconSize` | 24 pt | SF Symbol внутри control button |
| `controlButtonSpacing` | 16 pt | gap между prev и next |
| `controlButtonsBottomInset` | 16 pt | от bottom safe area |
| `timerRowMinHeight` | 56 pt | строка активного таймера |
| `timerPanelCornerRadius` | 12 pt | панель активных таймеров |
| `timerPanelTopOffset` | 8 pt | gap между step cards scroll и timer panel |

### Шрифты

Переферийно используем Martian (per CLAUDE.md и docs/UI.md).

| Где | Шрифт | Size | Weight |
|-----|-------|------|--------|
| Step number badge | Martian Mono | 18 pt | medium |
| Step body text | Martian Grotesk Nr Lt | 18 pt | regular |
| Voice pill label | Martian Grotesk Nr Lt | 14 pt | regular |
| Active timer recipe name | Martian Grotesk Nr Lt | 15 pt | regular |
| Active timer countdown | Martian Mono Nr Lt | 15 pt | light |
| Prev/Next button icon | SF Symbol | 24 pt | medium |
| Exit confirm title | Martian Grotesk Std xBd | 18 pt | display |
| Exit confirm message | Martian Grotesk Nr Lt | 14 pt | regular |
| Onboarding title | Martian Grotesk Nr Md | 20 pt | medium |
| Onboarding body | Martian Grotesk Nr Lt | 16 pt | regular |
| Onboarding permission row title | Martian Grotesk Nr Md | 16 pt | medium |
| Onboarding permission row desc | Martian Grotesk Nr Lt | 14 pt | regular |

### Цвета палитры

Все semantic, поддержка light/dark автоматически.

| Состояние | Цвет | Условие |
|-----------|------|---------|
| `voice.listening` | `.green` (system) | микрофон активен |
| `voice.processing` | `.orange` (system) | обрабатывается команда |
| `voice.speaking` | `.blue` (system) | TTS говорит |
| `voice.muted` | `.secondary` | тоггл выключен |
| `voice.error` | `.red` (system) | ошибка распознавания / unavailable |
| `step.focused` | `(Color.primary, Color(uiColor: .secondarySystemBackground))` | foreground/background |
| `step.peek` | `(Color.secondary, Color.clear)` | foreground/background (dimmed) |
| `stepNumber.badge` | `(Color.white, Color.accentColor)` | text/badge |
| `timer.soon` | `Color(red: 1.0, green: 0.553, blue: 0.157)` (#ff8d28) | remaining < duration/10 |
| `timer.exceeded` | `Color(red: 0.98, green: 0.153, blue: 0.188)` | remaining < 0 |

---

## State: Cooking mode — active (default)

Главный экран. Peek-3 layout: текущий шаг в центре, края prev/next видны.

### Размеры блоков

| Элемент | W×H | Примечание |
|---------|-----|------------|
| Voice status pill | auto × 36 pt | top-center, pinned to safe area |
| Step card (focused) | full × auto (min 200) | card с текстом шага, max 80% viewport height |
| Step card (peek top) | full × 24 pt visible | край предыдущего шага |
| Step card (peek bottom) | full × 24 pt visible | край следующего шага |
| Active timer panel | full × auto (0 если нет активных) | появляется между scroll и controls |
| Active timer row | full × min 56 pt | recipe name + countdown |
| Controls row | auto × 56 pt | prev + spacer + next |

### Дерево (DOM)

```text
CookingModeView
├─ GeometryReader { geo in
│   VStack(spacing: 0) {
│   │   VoiceStatusPill(state: voiceProvider.voiceState)
│   │       .padding(.top, CookingLayout.voicePillTopInset)
│   │       .padding(.horizontal, CookingLayout.voicePillSideInset)
│   │
│   │   ScrollViewReader { proxy in
│   │       ScrollView(.vertical, showsIndiveIndicators: false) {
│   │           LazyVStack(spacing: CookingLayout.stepCardSpacing) {
│   │               ForEach(viewModel.steps) { step in
│   │                   CookingStepCard(step: step, isFocused: step.id == viewModel.currentStepId)
│   │                       .id(step.id)
│   │                       .frame(maxWidth: .infinity)
│   │               }
│   │           }
│   │           .padding(.horizontal, CookingLayout.padding)
│   │           .padding(.top, CookingLayout.peekEdgeVisible)        // give peek room
│   │           .padding(.bottom, CookingLayout.peekEdgeVisible * 2) // bottom peek + clearance for controls
│   │       }
│   │       .scrollTargetBehavior(.viewAligned)
│   │       .scrollTargetLayout()
│   │       .onChange(of: viewModel.currentStepId) { _, newId in
│   │           if let newId { proxy.scrollTo(newId, anchor: .center) }
│   │       }
│   │   }
│   │
│   │   // Active timers panel (conditional, не overlays, sibling в VStack)
│   │   if !viewModel.activeTimers.isEmpty {
│   │       ActiveTimerPanel(timers: viewModel.activeTimers)
│   │           .padding(.horizontal, CookingLayout.padding)
│   │           .padding(.top, CookingLayout.timerPanelTopOffset)
│   │   }
│   │
│   │   // Controls (always visible)
│   │   HStack(spacing: CookingLayout.controlButtonSpacing) {
│   │       Button { viewModel.goPrev() } label: {
│   │           Image(systemName: "chevron.up")
│   │               .frame(width: CookingLayout.controlButtonSize, height: CookingLayout.controlButtonSize)
│   │       }
│   │       .buttonStyle(.bordered)
│   │       .disabled(viewModel.currentStepIndex == 0)
│   │
│   │       Button { viewModel.goNext() } label: {
│   │           Image(systemName: "chevron.down")
│   │               .frame(width: CookingLayout.controlButtonSize, height: CookingLayout.controlButtonSize)
│   │       }
│   │       .buttonStyle(.borderedProminent)
│   │       .disabled(viewModel.currentStepIndex == viewModel.steps.count - 1)
│   │   }
│   │   .padding(.bottom, CookingLayout.controlButtonsBottomInset)
│   │   .padding(.top, 8)
│   │}
│   .persistentSystemOverlays(.hidden)
│   .background(Color(uiColor: .systemBackground))     // ensure opaque
│   .onAppear { ScreenAwakeController.setActive(true); /* start voice */ }
│   .onDisappear { ScreenAwakeController.deactivate(); /* stop voice */ }
│   .navigationTitle("")                                // иммерсивность
│   .navigationBarTitleDisplayMode(.inline)
│   .toolbar { ExitButton }
└─ .sheet(isPresented: $showPermissions) { CookingPermissionsSheet(...) }   // onboarding
```

**Критично:**

- **`scrollTargetBehavior(.viewAligned)`** доступен с iOS 17.0 — ровно наш deployment target.
- **Voice status pill — overlay top center, не sibling**. Делаем через `.overlay(alignment: .top)` на родительском VStack, иначе влияет на layout высоты.
- **Active timer panel** — sibling в VStack (не overlay), появляется/исчезает через `if`, двигает controls.
- **Controls** — всегда видны внизу. `chevron.up` для prev, `chevron.down` для next (вертикальная метафора свайпа).
- `.buttonStyle(.borderedProminent)` для next — primary action; `.bordered` для prev — secondary.
- **Без `.tabView` и `.tabBar`** — это push-экран, imbricated в navigation.

### SwiftUI / platform notes

- `ScrollViewReader` + `scrollTargetBehavior(.viewAligned)` — official API iOS 17+. Альтернатива (`TabView` с `.page`) плоха: нет точного контроля над peek-3.
- `.scrollTargetLayout()` — обязательно на корневом LazyVStack, чтобы viewAligned работал корректно.
- `onChange(of: viewModel.currentStepId)` — на iOS 17 используется deprecated single-param closure; в коде проекта принят iOS 17 deployment, поэтому старый синтаксис принимается.
- **Запрещено**: `Timer.publish` для countdown — только `Text(timerInterval:)` (батарея + автоматически работает в AOD).
- **Запрещено**: `fixedSize` на step text без max line limit — иначе break layout на длинных шагах.
- **Запрещено**: any `.font(.system(size:))` на Text — только Martian через `AppTypography` или `.custom` (per CLAUDE.md, SF Pro — баг).

---

## Component: VoiceStatusPill

5 состояний. Tappable (toggle mute).

```text
VoiceStatusPill
├─ Button { viewModel.toggleMicMute() } label: {
│   HStack(spacing: 8) {
│   │   Image(systemName: iconName)         // см. таблицу ниже
│   │       .font(.system(size: CookingLayout.voicePillIconSize, weight: .medium))
│   │       .foregroundStyle(tint)
│   │   Text(labelKey)                       // localized string
│   │       .font(.custom("Martian Grotesk Nr Lt", size: 14))
│   │       .foregroundStyle(tint)
│   │   }
│   │   .padding(.horizontal, CookingLayout.voicePillHorizontalPadding)
│   │   .frame(height: CookingLayout.voicePillHeight)
│   │   .background(
│       Capsule().fill(tint.opacity(0.15))
│   )
│   .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 1))
│   .accessibilityIdentifier("cooking_voice_status_pill")
│   .accessibilityLabel(accessibilityLabel)
└─
```

| State | Icon | Label key | Tint |
|-------|------|-----------|------|
| `.listening` | `waveform` | `cooking.voice-status.listening` | `.green` |
| `.processing` | `ellipsis` | `cooking.voice-status.processing` | `.orange` |
| `.speaking` | `speaker.wave.2` | `cooking.voice-status.speaking` | `.blue` |
| `.muted` | `mic.slash` | `cooking.voice-status.muted` | `.secondary` |
| `.error` | `exclamationmark.triangle` | `cooking.voice-status.error` | `.red` |
| `.paused` (interruption) | `pause.circle` | `cooking.voice-status.paused` | `.secondary` |

Tinted capsule в стиле iOS 26 Liquid Glass (но без явного `.glassEffect` — работаем на iOS 17+). Tint opacity 0.15 для background, 0.3 для border — даёт нужную мягкость без glass зависимости.

---

## Component: CookingStepCard

Карточка шага.

```text
CookingStepCard
├─ HStack(alignment: .top, spacing: 12) {
│   │   // Number badge
│   │   Text("\(step.number)")
│   │       .font(.custom("Martian Mono", size: 18).weight(.medium))
│   │       .foregroundStyle(.white)
│   │       .frame(width: 36, height: 36)
│   │       .background(Circle().fill(Color.accentColor))
│   │
│   │   // Step body
│   │   VStack(alignment: .leading, spacing: 8) {
│   │       InlineRunsText(runs: step.attributedRuns)        // reuses existing component
│   │           .font(.custom("Martian Grotesk Nr Lt", size: 18))
│   │           .lineSpacing(6)
│   │           .frame(maxWidth: .infinity, alignment: .leading)
│   │           .foregroundStyle(isFocused ? Color.primary : Color.secondary)
│   │
│   │       // Inline timer references
│   │       if !step.inlineTimerReferences.isEmpty {
│   │           FlowHStack(step.inlineTimerReferences) { ref in
│   │               TimerRefChip(reference: ref)
│   │           }
│   │       }
│   │   }
│   }
│   .padding(16)
│   .frame(maxWidth: .infinity, alignment: .leading)
│   .background(
│       RoundedRectangle(cornerRadius: 16)
│           .fill(isFocused ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(Color.clear))
│   )
│   .accessibilityElement(children: .combine)
│   .accessibilityLabel("Шаг \(step.number). \(step.plainText)")
```

**Критично:**

- **`isFocused`** — visual hint: background fill + foregroundStyle. Без изменения размеров (иначе viewAligned дёргается).
- **`InlineRunsText`** — переиспользуем существующий компонент из `RecipeDescriptionView.swift` (вынести в общий файл, если ещё не там).
- **Timer references** — чипсы, кликабельные (tap → старт таймера из карточки тоже).

---

## Component: ActiveTimerPanel

Панель активных таймеров под step scroll, над controls.

```text
ActiveTimerPanel
├─ VStack(spacing: 8) {
│   ForEach(timers) { timer in
│       HStack {
│           Text(timer.recipeName)
│               .font(.custom("Martian Grotesk Nr Lt", size: 15))
│               .lineLimit(1)
│               .truncationMode(.tail)
│
│           Spacer()
│
│           Text(timerInterval: timer.startDate...timer.endDate)
│               .font(.custom("Martian Mono Nr Lt", size: 15))
│               .monospacedDigit()
│               .foregroundStyle(color(for: timer))
│
│           Button { viewModel.pauseTimer(id: timer.id) } label: {
│               Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
│                   .font(.system(size: 16, weight: .medium))
│           }
│           .buttonStyle(.borderless)
│           .tint(.blue)
│       }
│       .frame(minHeight: 56)
│       .padding(.horizontal, 12)
│       .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
│   }
│}
```

Цвет countdown: `normal` (primary), `soon` (orange), `exceeded` (red).

---

## Component: CookingPermissionsSheet

Onboarding при первом входе.

```text
CookingPermissionsSheet (sheet)
├─ VStack(alignment: .leading, spacing: 16) {
│   Text("cooking.permission.title")           // «Для режима готовки»
│       .font(.custom("Martian Grotesk Nr Md", size: 20))
│
│   VStack(alignment: .leading, spacing: 16) {
│       PermissionRow(icon: "mic.fill", titleKey: "cooking.permission.mic-title", descKey: "cooking.permission.mic-desc")
│       PermissionRow(icon: "waveform.badge.checkmark", titleKey: "cooking.permission.speech-title", descKey: "cooking.permission.speech-desc")
│       PermissionRow(icon: "sun.max.fill", titleKey: "cooking.permission.awake-title", descKey: "cooking.permission.awake-desc")
│   }
│
│   // Privacy hint
│   HStack(alignment: .top, spacing: 8) {
│       Image(systemName: "lock.shield")
│           .foregroundStyle(.green)
│       Text("cooking.permission.privacy-hint")    // on-device + battery
│           .font(.custom("Martian Grotesk Nr Lt", size: 14))
│           .foregroundStyle(.secondary)
│   }
│   .padding(12)
│   .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.1)))
│
│   Spacer()
│
│   Button("cooking.permission.continue-button") {
│       Task { await requestPermissions() }
│   }
│       .buttonStyle(.borderedProminent)
│       .frame(maxWidth: .infinity)
│       .controlSize(.large)
│}
├─ .padding(20)
└─ .presentationDetents([.large])
```

`PermissionRow` — переиспользуемая локальная подсущность.

---

## State: Asset install overlay (iOS 26+)

Показывается поверх `CookingModeView` пока `AssetInventory.assetInstallationRequest(supporting:).downloadAndInstall()` в полёте.

```text
AssetInstallOverlay (overlay)
├─ ZStack {
│   Color.black.opacity(0.4).ignoresSafeArea()
│   VStack(spacing: 16) {
│       ProgressView()
│           .controlSize(.large)
│       Text("cooking.asset-installing.title")
│           .font(.custom("Martian Grotesk Nr Md", size: 16))
│       Text("cooking.asset-installing.message")
│           .font(.custom("Martian Grotesk Nr Lt", size: 14))
│           .foregroundStyle(.secondary)
│           .multilineTextAlignment(.center)
│       Button("cooking.permission.cancel") { ... }
│           .font(.custom("Martian Grotesk Nr Lt", size: 14))
│           .foregroundStyle(.red)
│   }
│   .padding(24)
│   .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .systemBackground)))
│}
```

---

## State: Exit confirmation alert

При свайпе back / кнопке Exit:

```swift
.alert("cooking.exit-confirm.title", isPresented: $showExitConfirm) {
    Button("cooking.exit-confirm.exit-anyway", role: .destructive) { dismiss() }
    Button("cooking.exit-confirm.keep-cooking", role: .cancel) {}
} message: {
    if viewModel.activeTimers.isEmpty {
        Text("cooking.exit-confirm.message-no-timer")
    } else {
        Text("cooking.exit-confirm.message-with-timer")
    }
}
```

---

## State: Mic muted (voice disabled)

Пользователь выключил микрофон через pill.

- Voice status pill → `.muted` state.
- Микрофон деактивирован, `AVAudioSession` освобождена (если не запущены таймеры — иначе оставляем для timer Live Activity, но это уже не наш AudioSession).
- Остальной UI работает: навигация кнопками, запуск таймеров из карточки, exit.

---

## State: Error (speech unavailable)

`SFSpeechRecognizer.isAvailable == false` или on-device не поддержан.

- Voice status pill → `.error` state.
- Tap pill → alert «Голос недоступен» с описанием и кнопкой «Открыть настройки».
- Микрофон off, остальные controls работают.

---

## Примитивы (реализовать до экранов)

| Примитив | Файл | Ответственность |
|----------|------|-----------------|
| `CookingLayout` | `RecipeScalerNative/Views/Cooking/CookingLayout.swift` | Все токены из layout.md |
| `InlineRunsText` | переиспользуем из `RecipeDescriptionView` или выносим в `RecipeScalerNative/Views/Common/InlineRunsText.swift` | Рендер `[RecipeDescriptionInlineRun]` (text + strong + em + link + timer ref + ingredient ref) |
| `TimerRefChip` | `RecipeScalerNative/Views/Cooking/TimerRefChip.swift` | Чип ссылки на таймер в шаге |
| `CookingStepCard` | `RecipeScalerNative/Views/Cooking/CookingStepCard.swift` | Карточка шага |
| `VoiceStatusPill` | `RecipeScalerNative/Views/Cooking/VoiceStatusPill.swift` | Pill со статусом голоса |
| `ActiveTimerPanel` | `RecipeScalerNative/Views/Cooking/ActiveTimerPanel.swift` | Панель активных таймеров |
| `CookingPermissionsSheet` | `RecipeScalerNative/Views/Cooking/CookingPermissionsSheet.swift` | Onboarding sheet |
| `PermissionRow` | встроен в PermissionsSheet | Строка иконка + текст + описание |
| `AssetInstallOverlay` | `RecipeScalerNative/Views/Cooking/AssetInstallOverlay.swift` | Overlay установки AssetInventory |
| `CookingModeView` | `RecipeScalerNative/Views/Cooking/CookingModeView.swift` | Главный экран (assembly) |

---

## Матрица приёмки

| State | Light | Dark | Edge data |
|-------|-------|------|-----------|
| Cooking mode, 1 шаг (минимум) | ☐ | ☐ | 1 шаг, без соседей |
| Cooking mode, 3 шага, mid | ☐ | ☐ | peek prev + peek next видимы |
| Cooking mode, 10 шагов, scroll | ☐ | ☐ | lazy load, smooth scroll |
| Cooking mode, очень длинный шаг | ☐ | ☐ | 5+ строк, scroll inside card? (нет, card растёт) |
| Cooking mode, шаг с inline timer | ☐ | ☐ | чип кликабельный |
| Cooking mode, шаг с ingredient ref | ☐ | ☐ | чип/подсветка |
| Voice listening | ☐ | ☐ | pill green, animated waveform? (no, static) |
| Voice processing | ☐ | ☐ | pill orange |
| Voice speaking | ☐ | ☐ | pill blue |
| Voice muted | ☐ | ☐ | pill grey, mic.slash |
| Voice error | ☐ | ☐ | pill red, alert on tap |
| 1 активный таймер | ☐ | ☐ | panel внизу |
| 3 активных таймера | ☐ | ☐ | panel скроллится? (нет, показывает до 3, дальше overflow) |
| Timer exceeded | ☐ | ☐ | countdown красный |
| Timer soon (<10%) | ☐ | ☐ | countdown оранжевый |
| Timer paused | ☐ | ☐ | static time, play.fill icon |
| Asset install overlay (iOS 26+) | ☐ | ☐ | spinner, cancel |
| Permissions sheet, 1st entry | ☐ | ☐ | все 3 row + privacy hint |
| Permissions denied sheet | ☐ | ☐ | warning + 2 кнопки |
| Exit confirm, no timers | ☐ | ☐ | 2 строки |
| Exit confirm, with timers | ☐ | ☐ | warning о таймерах |
| Empty recipe (0 шагов) | n/a | n/a | кнопка "Готовить" не показана |
| Dynamic Type XL | ☐ | ☐ | step text не ломает layout |
| Landscape (v1 не поддерживается) | n/a | n/a | lock to portrait |

---

## Falsifiable claims

1. **Peek prev/next видимы**: на любом screen size виден хотя бы `peekEdgeVisible` (24 pt) предыдущего и следующего шага, когда они есть. Измерение: accessibility frame в preview.
2. **Step card focused отличается от peek**: у focused есть secondary background + primary foreground, у peek — clear background + secondary foreground. Измерение: accessibility value / inspectable.
3. **Voice status pill всегда сверху**: при скролле шагов pill остаётся в top safe area. Измерение: accessibility frame после скролла.
4. **Controls всегда внизу**: при скролле шагов prev/next кнопки не уезжают. Измерение: accessibility frame после скролла.
5. **Tap voice pill toggles mute**: голос включается/выключается, состояние persist в UserDefaults между запусками. Измерение: UserDefaults read.
6. **Step number badge всегда Martian Mono**: измерение: grep `Martian Mono` в `CookingStepCard.swift`.
7. **Все тексты Martian**: ни одной `.font(.system(size:))` на `Text` в `Cooking/` (SF Symbol для `Image` — ок). Измерение: grep.
8. **Все UI строки — `LocalizedStringKey`**: ни одной русской/английской строки в view-файлах (кроме логов в `AppLog`). Измерение: grep.
9. **No `Timer.publish`**: countdown только через `Text(timerInterval:)`. Измерение: grep в `Cooking/`.
10. **`scrollTargetBehavior(.viewAligned)`**: используется для peek-3. Измерение: grep.
11. **`@available(iOS 26.0, *)`** — только в `CookingAudioAnalyzer.swift` и местах где вызывается `SpeechAnalyzer`. Остальное iOS 17+. Измерение: grep.
12. **Tap target ≥ 44pt** на всех кнопках (control buttons — 56pt, mic pill — 36pt height но tap area ≥ 44 через padding). Измерение: accessibility frame.
13. **На exit из CookingModeView** — `ScreenAwakeController.isActive == false` и voice stopped. Измерение: unit test + manual.
14. **PrivacyInfo.xcprivacy** содержит microphone + speech keys. Измерение: file audit.

---

## Stub data (preview / seed)

| Сценарий | Данные | Где |
|----------|--------|-----|
| 3 шага, short | 3 шага по 1-2 строки | `#Preview` в `CookingModeView.swift` |
| 10 шагов, mix | короткие + длинные (5+ строк) | `#Preview` |
| Шаг с inline timer | 1 шаг содержит timer ref | `#Preview` в `CookingStepCard.swift` |
| Шаг с ingredient ref | 1 шаг содержит ingredient ref | `#Preview` |
| Worst-case wrap | «добавьте муку и хорошо перемешайте до однородной консистенции без комочков» | `#Preview` |
| Active timers panel | 2 таймера: 1 running normal, 1 paused | `#Preview` в `ActiveTimerPanel.swift` |
| Voice pill all states | listening, processing, speaking, muted, error | `#Preview` в `VoiceStatusPill.swift` |
| Permissions sheet | все 3 row | `#Preview` в `CookingPermissionsSheet.swift` |

---

## Платформенные ограничения

- **iOS 17+** (deployment target app, без поднятия).
- **`scrollTargetBehavior(.viewAligned)`** — iOS 17.0+ (доступно на нашем deployment target).
- **`SpeechAnalyzer`** — iOS 26.0+, guarded through `CookingVoiceProvider` strategy.
- **`AssetInventory`** — iOS 26.0+.
- **`AVAudioSession` interrupt/route change observers** — iOS 13+, без проблем.
- **`ScreenAwakeController`** — iOS 13+, без проблем.
- **`AVSpeechSynthesizer`** — iOS 7+, без проблем. Voice selection по locale — iOS 9+.
- **Liquid Glass** (`.glassEffect`) — не используем; работаем на iOS 17+ через tinted capsule (см. VoiceStatusPill).
- **Landscape orientation** — v1 не поддерживается. Если пользователь поворачивает телефон — экран остаётся portrait (через `.persistentSystemOverlays(.hidden)` + lock orientation в `Info.plist` для этого экрана? Проверить — может проще через `.supportedInterfaceOrientations` на root). В v1.1 — добавить landscape support.
- **Dynamic Island** (iPhone 14 Pro+) — top safe area увеличена, padding учтён.
- **`ScenePhase` changes** — on background, stop voice; on foreground, resume (если пользователь не выключал тоггл).

---

## Changelog

| Дата | Изменение |
|------|-----------|
| 2026-08-02 | Черновик. Layout проектируется с нуля (нет Figma макета). Web parity по компонентам RecipeDescriptionView + новые для voice. |
