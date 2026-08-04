# Tasks: Режим готовки с голосовым управлением v1

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

> Action-ориентированный checklist. Каждый таск — атомарная единица работы.
> Статусы: `[ ]` todo, `[~]` in progress, `[x]` done, `[!]` blocked.

---

## Шаг 1. Спека + layout артефакты

- [x] 1.1. Создать `specs/056-cooking-voice-mode/spec.md`
- [x] 1.2. Создать `specs/056-cooking-voice-mode/plan.md`
- [ ] 1.3. Создать `specs/056-cooking-voice-mode/tasks.md` (этот файл)
- [ ] 1.4. Создать `specs/056-cooking-voice-mode/layout.md`
- [ ] 1.5. Создать `specs/056-cooking-voice-mode/layout-audit.json`
- [ ] 1.6. Создать `specs/056-cooking-voice-mode/contracts/timer-stepid-payload.md` (shared note для server/web parity)
- [ ] 1.7. Прогнать `bash scripts/audit-ui-layout.sh specs/056-cooking-voice-mode`, зафиксировать baseline
- [ ] 1.8. Ревью `spec.md` + `layout.md` пользователем (точка остановки)

---

## Шаг 2. Расширение `RecipeTimer.stepId`

- [ ] 2.1. Найти текущее определение `struct RecipeTimer` (grep `struct RecipeTimer`)
- [ ] 2.2. Добавить поле `let stepId: String?` (опциональное, backward-compat)
- [ ] 2.3. Обновить все `init()` вызовы (`RecipeTimer(id:name:duration:...)`) — добавить `stepId: nil` где не передаём
- [ ] 2.4. В `TimerSyncService.swift` строка ~166: в `timerDict` добавить `"stepId": stepId` если не nil
- [ ] 2.5. В `TimerSyncService.swift` `recipeTimer(fromWebPayload:timerId:)` ~400: парсить `payload["stepId"] as? String`
- [ ] 2.6. Создать/обновить `TimerSyncServiceTests` (найти существующий файл через Glob `**/TimerSync*Tests*`)
- [ ] 2.7. Тест `test_stepId_includedInPayload`
- [ ] 2.8. Тест `test_legacyPayload_stepId_nil`
- [ ] 2.9. Тест `test_stepId_roundTrip`
- [ ] 2.10. `xcodebuild test` с новыми тестами green
- [ ] 2.11. Документировать server-side проверку в `contracts/timer-stepid-payload.md`

---

## Шаг 3. `CookingSessionViewModel`

- [ ] 3.1. Создать `RecipeScalerNative/Models/CookingStep.swift` (struct с `id`, `number`, `plainText`, `attributedRuns`, `attachedTimerIds`, `ingredientRefs`)
- [ ] 3.2. Создать `RecipeScalerNative/Models/CookingCommand.swift` (enum: `next`, `prev`, `repeatStep`, `goto(Int)`, `timerStart`, `timerPause`, `timerResume`, `timerStop`, `unknown`)
- [ ] 3.3. Создать `RecipeScalerNative/Models/CookingVoiceState.swift` (enum: `idle`, `listening`, `processing`, `speaking`, `muted`, `error`, `paused`)
- [ ] 3.4. Создать `RecipeScalerNative/ViewModels/CookingSessionViewModel.swift`:
  - [ ] 3.4.1. `init(recipe:)` — extract `CookingStep[]` из `RecipeDescriptionBlock.orderedStep`
  - [ ] 3.4.2. State properties: `currentStepIndex`, `voiceState`, `lastTranscript`, `lastCommand`, `isMicMuted` (load из UserDefaults)
  - [ ] 3.4.3. `goNext()`, `goPrev()`, `goto(Int)`, `repeatCurrent()` с bounds-check
  - [ ] 3.4.4. `handleCommand(_ command: CookingCommand)` — dispatch
  - [ ] 3.4.5. Timer actions: `startTimerForCurrentStep()`, `pauseTimer(id:)`, etc.
  - [ ] 3.4.6. `onChange(stepIndex)` — trigger `onSpeakStep` callback
  - [ ] 3.4.7. `toggleMicMute()` — persist в `UserDefaults(cooking.voice-mic-muted)`
- [ ] 3.5. Создать `RecipeScalerNativeTests/CookingSessionViewModelTests.swift`
- [ ] 3.6. Тесты (см. plan.md Шаг 3 — все positive invariants)
- [ ] 3.7. `xcodebuild test` green

---

## Шаг 4. `CookingCommandClassifier`

- [ ] 4.1. Создать `RecipeScalerNative/Services/Cooking/CookingSynonymDictionary.swift` (RU+EN словарь)
- [ ] 4.2. Создать `RecipeScalerNative/Services/Cooking/CookingCommandClassifier.swift`:
  - [ ] 4.2.1. `normalize(_ text: String) -> String` — NFKD + lowercase + strip diacritics
  - [ ] 4.2.2. `tokenize(_ text: String) -> [String]` — trim + split по пробелам + handle quoted phrases
  - [ ] 4.2.3. `parseGotoNumber(_ tokens: [String]) -> Int?` — digits + word-to-20 (RU+EN)
  - [ ] 4.2.4. `classify(_ transcript: String) -> CookingCommand` — main entry
- [ ] 4.3. Создать `RecipeScalerNativeTests/CookingCommandClassifierTests.swift`
- [ ] 4.4. Тесты (см. plan.md Шаг 4 — все cases + edge cases)
- [ ] 4.5. `xcodebuild test` green

---

## Шаг 5. `CookingAudioEngineSF` (iOS 17+)

- [ ] 5.1. Создать `RecipeScalerNative/Services/Cooking/CookingTranscript.swift` (`enum { case partial(String), final(String) }`)
- [ ] 5.2. Создать `RecipeScalerNative/Services/Cooking/CookingVoiceListening.swift` (protocol с `transcripts() -> AsyncStream<CookingTranscript>`, `start()`, `stop()`, `suspend()`, `resume()`)
- [ ] 5.3. Создать `RecipeScalerNative/Services/Cooking/CookingVoiceError.swift` (enum: `permissionDenied`, `speechUnavailable`, `onDeviceNotSupported`, `audioEngineFailure`)
- [ ] 5.4. Создать `RecipeScalerNative/Services/Cooking/CookingAudioEngineSF.swift`:
  - [ ] 5.4.1. `SFSpeechRecognizer(locale:)` init + `isAvailable` / `supportsOnDeviceRecognition` checks
  - [ ] 5.4.2. `AVAudioEngine` + `inputNode` tap
  - [ ] 5.4.3. `SFSpeechAudioBufferRecognitionRequest` с `requiresOnDeviceRecognition = true`, `shouldReportPartialResults = true`
  - [ ] 5.4.4. `AVAudioSession` setup: `.playAndRecord`, mode `.default`, options `[.defaultToSpeaker, .allowBluetoothHFP]`
  - [ ] 5.4.5. 60-сек re-arming logic (internal Task tracking elapsed)
  - [ ] 5.4.6. `interruptionNotification` observer
  - [ ] 5.4.7. `routeChangeNotification` observer
- [ ] 5.5. Создать `RecipeScalerNativeTests/CookingAudioEngineSFTests.swift` (state machine tests, mock recognizer)
- [ ] 5.6. Manual test в iOS 17 симуляторе: запись голоса → распознавание → транскрипция в логе
- [ ] 5.7. `xcodebuild test` green

---

## Шаг 6. `CookingAudioAnalyzer` (iOS 26+)

- [ ] 6.1. Создать `RecipeScalerNative/Services/Cooking/AssetInventoryInstaller.swift` (helper для `AssetInventory.assetInstallationRequest`)
- [ ] 6.2. Создать `RecipeScalerNative/Services/Cooking/CookingAudioAnalyzer.swift` (`@available(iOS 26.0, *)`):
  - [ ] 6.2.1. `SpeechAnalyzer` init с `SpeechTranscriber` module, `.volatileResults`
  - [ ] 6.2.2. `AVAudioConverter` setup: inputNode format → `bestAvailableAudioFormat(compatibleWith:)`
  - [ ] 6.2.3. Real-time audio tap на отдельном акторе (Swift 6 strict concurrency)
  - [ ] 6.2.4. `supportedLocales` check; fallback signal если локаль не поддержана
  - [ ] 6.2.5. `installedLocales` check; trigger install если не установлена
- [ ] 6.3. Manual test в iOS 26 симуляторе (требует установленного runtime)
- [ ] 6.4. `xcodebuild build` green с `@available` guard

---

## Шаг 7. `CookingVoiceProvider` (strategy)

- [ ] 7.1. Создать `RecipeScalerNative/Services/Cooking/CookingVoiceProvider.swift`:
  - [ ] 7.1.1. `@MainActor @Observable` class
  - [ ] 7.1.2. `init()` с `if #available(iOS 26.0, *)` выбором движка
  - [ ] 7.1.3. Exposed state: `voiceState`, `lastTranscript`, `engineName`, `isSuspended`
  - [ ] 7.1.4. `start(locale:)`, `stop()`, `suspend()`, `resume()`
  - [ ] 7.1.5. `transcripts: AsyncStream<CookingTranscript>` (publisher for VM)
- [ ] 7.2. Создать `RecipeScalerNativeTests/CookingVoiceProviderTests.swift` (mock engines)
- [ ] 7.3. Тесты на strategy switch (mock `SystemVersion` или inject)
- [ ] 7.4. `xcodebuild test` green

---

## Шаг 8. `CookingSpeechSynthesizer`

- [ ] 8.1. Создать `RecipeScalerNative/Services/Cooking/CookingSpeechSynthesizer.swift`:
  - [ ] 8.1.1. `AVSpeechSynthesizer` instance
  - [ ] 8.1.2. Voice selection по `AppLanguagePreference.current.locale`
  - [ ] 8.1.3. Priority queue: `[CookingUtterance]` sorted by priority
  - [ ] 8.1.4. `speak(text:, priority:)` — main entry
  - [ ] 8.1.5. `stopSpeaking(_:AVSpeechBoundary)` — immediate or word boundary
- [ ] 8.2. Создать delegate class (`NSObject`, `AVSpeechSynthesizerDelegate`):
  - [ ] 8.2.1. `willSpeakRange` → trigger `onMicSuspend?()`
  - [ ] 8.2.2. `didFinish` → trigger `onMicResume?()`, dequeue next
  - [ ] 8.2.3. `didCancel` → trigger `onMicResume?()`
- [ ] 8.3. Создать `RecipeScalerNativeTests/CookingSpeechSynthesizerTests.swift`
- [ ] 8.4. Тесты на приоритетах, auto-mute callback
- [ ] 8.5. `xcodebuild test` green

---

## Шаг 9. `CookingModeView` + кнопка входа

- [ ] 9.1. Создать `RecipeScalerNative/Views/Cooking/CookingLayout.swift` (токены из layout.md)
- [ ] 9.2. Создать `RecipeScalerNative/Views/Cooking/CookingStepCard.swift`:
  - [ ] 9.2.1. Number badge (Martian Mono)
  - [ ] 9.2.2. Step text (Martian Grotesk, увеличенный размер)
  - [ ] 9.2.3. Inline timer references styling
  - [ ] 9.2.4. Ingredient refs styling
- [ ] 9.3. Создать `RecipeScalerNative/Views/Cooking/VoiceStatusPill.swift` (5 состояний)
- [ ] 9.4. Создать `RecipeScalerNative/Views/Cooking/ActiveTimerPanel.swift`
- [ ] 9.5. Создать `RecipeScalerNative/Views/Cooking/CookingPermissionsSheet.swift`
- [ ] 9.6. Создать `RecipeScalerNative/Views/Cooking/CookingModeView.swift`:
  - [ ] 9.6.1. `ScrollViewReader` + `scrollTargetBehavior(.viewAligned)` для peek-3
  - [ ] 9.6.2. Voice status pill сверху
  - [ ] 9.6.3. Step cards vertical scroll
  - [ ] 9.6.4. Active timers panel
  - [ ] 9.6.5. Large prev/next buttons внизу (≥49pt)
  - [ ] 9.6.6. `.onAppear` → `ScreenAwakeController.setActive(true)` + voice start
  - [ ] 9.6.7. `.onDisappear` → `ScreenAwakeController.deactivate()` + voice stop + TTS stop
  - [ ] 9.6.8. `.persistentSystemOverlays(.hidden)`
  - [ ] 9.6.9. `@Environment(CookingVoiceProvider.self)`, `@Environment(CookingSpeechSynthesizer.self)`
  - [ ] 9.6.10. Subscribe на `voiceProvider.transcripts` → `commandClassifier.classify` → `viewModel.handleCommand`
  - [ ] 9.6.11. Onboarding sheet trigger при первом входе
- [ ] 9.7. Изменить `RecipeScalerNative/Views/YDocRecipeDetailView.swift`:
  - [ ] 9.7.1. Найти `StepsSection` (grep)
  - [ ] 9.7.2. Добавить `NavigationLink("cooking.start-button", value: CookingRoute(recipeId:))` рядом
  - [ ] 9.7.3. Скрыть если 0 шагов
- [ ] 9.8. Создать `RecipeScalerNativeTests/CookingModeViewLifecycleTests.swift`
- [ ] 9.9. `xcodebuild build` green
- [ ] 9.10. `bash scripts/audit-ui-layout.sh specs/056-cooking-voice-mode` green
- [ ] 9.11. `bash scripts/verify-ui-smoke.sh` green

---

## Шаг 10. DI + i18n + privacy manifest

- [ ] 10.1. Изменить `RecipeScalerNative/App/AppContainer.swift`:
  - [ ] 10.1.1. Найти текущую структуру (grep `class AppContainer`)
  - [ ] 10.1.2. Добавить lazy properties: `cookingVoiceProvider`, `cookingSpeechSynthesizer`, `cookingCommandClassifier`
  - [ ] 10.1.3. Inject в `.appEnvironment(_:)` если есть pattern, или создать extension
- [ ] 10.2. Проверить/обновить `RecipeScalerNative/RecipeScalerNativeApp.swift` или `ContentView.swift` для `.appEnvironment`
- [ ] 10.3. Добавить строки в `RecipeScalerNative/Resources/Localizable.xcstrings`:
  - [ ] 10.3.1. `cooking.start-button` (RU «Готовить» / EN «Cook»)
  - [ ] 10.3.2. `cooking.exit-button` (RU «Выйти» / EN «Exit»)
  - [ ] 10.3.3. `cooking.exit-confirm.title` (RU «Выйти из режима готовки?» / EN «Exit cooking mode?»)
  - [ ] 10.3.4. `cooking.exit-confirm.message-with-timer`
  - [ ] 10.3.5. `cooking.voice-status.listening` (RU «Слушаю» / EN «Listening»)
  - [ ] 10.3.6. `cooking.voice-status.processing`
  - [ ] 10.3.7. `cooking.voice-status.speaking`
  - [ ] 10.3.8. `cooking.voice-status.muted`
  - [ ] 10.3.9. `cooking.voice-status.error`
  - [ ] 10.3.10. `cooking.confirm.step-n` (с плейсхолдером `{n}`)
  - [ ] 10.3.11. `cooking.confirm.timer-started`
  - [ ] 10.3.12. `cooking.confirm.timer-paused`
  - [ ] 10.3.13. `cooking.confirm.timer-resumed`
  - [ ] 10.3.14. `cooking.confirm.timer-stopped`
  - [ ] 10.3.15. `cooking.confirm.not-understood`
  - [ ] 10.3.16. `cooking.confirm.no-such-step`
  - [ ] 10.3.17. `cooking.confirm.no-timer-in-step`
  - [ ] 10.3.18. `cooking.permission.title` (RU «Для режима готовки» / EN «For cooking mode»)
  - [ ] 10.3.19. `cooking.permission.mic-title` / `.mic-desc`
  - [ ] 10.3.20. `cooking.permission.speech-title` / `.speech-desc`
  - [ ] 10.3.21. `cooking.permission.awake-title` / `.awake-desc`
  - [ ] 10.3.22. `cooking.permission.privacy-hint` (on-device + battery warning)
  - [ ] 10.3.23. `cooking.permission.continue-button`
  - [ ] 10.3.24. `cooking.permission.denied-title` / `.denied-message`
  - [ ] 10.3.25. `cooking.permission.cook-without-voice`
  - [ ] 10.3.26. `cooking.permission.open-settings`
  - [ ] 10.3.27. `cooking.asset-installing.title` / `.message`
  - [ ] 10.3.28. `cooking.prev-button` / `cooking.next-button` (accessibility)
- [ ] 10.4. Обновить `RecipeScalerNative/PrivacyInfo.xcprivacy`:
  - [ ] 10.4.1. Найти текущий файл (Glob `**/PrivacyInfo.xcprivacy`)
  - [ ] 10.4.2. Добавить `NSMicrophoneUsageDescription` privacy key
  - [ ] 10.4.3. Добавить `NSSpeechRecognitionUsageDescription` privacy key
- [ ] 10.5. Обновить `RecipeScalerNative/Info.plist`:
  - [ ] 10.5.1. `NSMicrophoneUsageDescription` (локализованная строка-ключ, не сам текст)
  - [ ] 10.5.2. `NSSpeechRecognitionUsageDescription`
- [ ] 10.6. Обновить `docs/PROJECT.md` — раздел про cooking mode
- [ ] 10.7. Проверить `docs/NATIVE-FEATURES-NO-PAID-ACCOUNT.md` — всё локальное, без paid account
- [ ] 10.8. `bash scripts/lint-i18n.sh` green (если есть)

---

## Шаг 11. Verify + manual QA

- [ ] 11.1. `xcodebuild build` green (iOS 17+ deployment)
- [ ] 11.2. `xcodebuild test` — все новые тест-классы green
- [ ] 11.3. `bash scripts/audit-ui-layout.sh specs/056-cooking-voice-mode` green
- [ ] 11.4. `bash scripts/verify-ui-smoke.sh` green
- [ ] 11.5. iOS 17 симулятор smoke: вход → навигация кнопками → выход
- [ ] 11.6. iOS 26 симулятор smoke: voice pipeline использует SpeechAnalyzer (по логам)
- [ ] 11.7. `bash scripts/pull-app-logs.sh` — проверить `cooking.*` события
- [ ] 11.8. Manual QA чеклист (US1-US10, см. plan.md Шаг 11)
- [ ] 11.9. Battery test: 30 мин готовки
- [ ] 11.10. Bluetooth HFP test
- [ ] 11.11. Dark mode + Dynamic Type test

---

## Post-релиз

- [ ] 12.1. Postmortem (если были регрессии)
- [ ] 12.2. v2 spec: voice-chat + Siri App Intents
