# Plan: Режим готовки с голосовым управлением v1

**Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

> Источник истины о том, **что** и **в каком порядке** менять, чтобы ревьюер
> и агент видели один план. Все шаги — strict-sequential, без параллелей:
> speech pipeline зависит от ViewModel, ViewModel от `stepId`, UI от всего.

---

## Очерёдность

1. **Спека + layout артефакты** — нет зависимостей, всё остальное на них ссылается.
2. **Расширение `RecipeTimer.stepId`** — модельные изменения до UI; дальше тесты на sync.
3. **`CookingSessionViewModel`** — ядро без голоса; уже можно тестировать навигацию кнопками.
4. **`CookingCommandClassifier`** — pure-функция, не зависит от AVFoundation; снимки-тесты.
5. **`CookingAudioEngineSF` (iOS 17+)** — базовый STT; проверка на iOS 17 симуляторе.
6. **`CookingAudioAnalyzer` (iOS 26+)** — улучшенный STT; проверка на iOS 26 симуляторе.
7. **`CookingVoiceProvider` (strategy)** — связывает 5+6, единый AsyncStream интерфейс.
8. **`CookingSpeechSynthesizer`** — TTS, ставится после STT (нужно auto-mute).
9. **`CookingModeView` + кнопка входа** — финальный UI поверх всех сервисов.
10. **DI + i18n + privacy manifest** — интеграция в `AppContainer`, финальные строки.
11. **Verify + manual QA** — полный цикл проверок.

---

## Шаг 1. Спека + layout артефакты

### Изменения

| Файл | Действие |
|------|----------|
| `specs/056-cooking-voice-mode/spec.md` | Создан (готово) |
| `specs/056-cooking-voice-mode/plan.md` | Создан (этот файл) |
| `specs/056-cooking-voice-mode/tasks.md` | Создан |
| `specs/056-cooking-voice-mode/layout.md` | Создан |
| `specs/056-cooking-voice-mode/layout-audit.json` | Создан |

### Downstream consumers

- [x] **SwiftUI views** — нет (документация).
- [x] **Cross-process consumers** — нет.
- [x] **Sync boundaries** — нет.
- [x] **Persisted state** — нет.
- [x] **Tests / verify-скрипты** — `bash scripts/audit-ui-layout.sh specs/056-cooking-voice-mode` добавлен в CI check.

### Positive invariants

| Эффект | Инвариант | Где проверять |
|--------|-----------|---------------|
| `audit-ui-layout.sh` для spec 056 | exit code 0, все `must_contain` regex найдены | CI |

---

## Шаг 2. Расширение `RecipeTimer.stepId`

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Models/RecipeTimer.swift` (или текущая локация `RecipeTimer`) | Добавить `stepId: String?` поле |
| `RecipeScalerNative/Services/TimerSyncService.swift` | В `timerDict` добавить `"stepId": stepId` если не nil (строка ~166) |
| `RecipeScalerNative/Services/TimerSyncService.swift` `recipeTimer(fromWebPayload:timerId:)` | Парсить `payload["stepId"] as? String` (строка ~400) |
| `RecipeScalerNativeTests/.../TimerSyncServiceTests.swift` (или новый файл) | Добавить 2 теста: round-trip + legacy |

### Downstream consumers

- [x] **SwiftUI views** — `MobileTimerPanel` читает `RecipeTimer`. Если захотим показывать step badge — v1.1, в v1 не трогаем.
- [x] **Cross-process consumers**:
  - `TimerLiveActivityCoordinator` — использует `RecipeTimerActivityAttributes` (timerId, timerName, recipeId). **Без изменений** в v1.
  - `HomeWidgetExtension` — без изменений.
  - `WatchCredentialsBridge` / watchOS app — без изменений (watch не использует stepId).
  - `TimerSnapshotStore` (App Group) — json-permissive, поле добавится прозрачно.
- [x] **Sync boundaries**:
  - `TimerSyncService` payload → server через WebSocket fan-out. Server должен игнорировать неизвестные поля (json). **Проверить на dev API перед релизом**.
  - Web client parity: `recipe-scaler-web` должен уметь принимать payload с неизвестным полем. Создать shared note в `specs/056-cooking-voice-mode/contracts/timer-stepid-payload.md`.
- [x] **Persisted state** — `TimerSnapshotStore` (App Group json), `UserDefaults` для pending events.
- [x] **Tests / verify-скрипты**:
  - `TimerSyncServiceTests` (существующий или новый) — добавить 2 теста.
  - `TimerManagerServiceTests` — добавить тест на создание таймера с stepId.

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| Создание `RecipeTimer(stepId: "step-3", ...)` и сериализация через `TimerSyncService.toWebPayload` | payload содержит `"stepId": "step-3"` | `TimerSyncServiceTests.test_stepId_includedInPayload` |
| Десериализация старого payload (без `stepId`) через `recipeTimer(fromWebPayload:)` | `RecipeTimer.stepId == nil`, без ошибки | `TimerSyncServiceTests.test_legacyPayload_stepId_nil` |
| Round-trip: создать → serialize → deserialize | `stepId` сохраняется | `TimerSyncServiceTests.test_stepId_roundTrip` |

### Note

Поле делаем `String?` (опциональным), backward-compatible. Server-side schema расширять не нужно — json permissive. В v2 можно сделать миграцию: заполнить `stepId` для существующих таймеров, если они привязаны к контексту шага.

---

## Шаг 3. `CookingSessionViewModel`

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/ViewModels/CookingSessionViewModel.swift` | Создан |
| `RecipeScalerNative/Models/CookingStep.swift` | Создан (struct, derived из `RecipeDescriptionBlock.orderedStep`) |
| `RecipeScalerNative/Models/CookingCommand.swift` | Создан (enum) |
| `RecipeScalerNativeTests/CookingSessionViewModelTests.swift` | Создан |

### Downstream consumers

- [x] **SwiftUI views** — `CookingModeView` будет читать (на шаге 9).
- [x] **Cross-process consumers** — нет.
- [x] **Sync boundaries** — нет (read-only интерфейс).
- [x] **Persisted state** — `UserDefaults(cooking.voice-mic-muted)`, `UserDefaults(cooking.onboarding-shown)`.
- [x] **Tests** — `CookingSessionViewModelTests` (новый), снимки-тесты модели `CookingStep`.

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| `goNext()` в середине | `currentStepIndex` +1 | `CookingSessionViewModelTests.test_goNext_advances` |
| `goNext()` на последнем шаге | `currentStepIndex` не меняется, без краша | `test_goNext_atLastStep_noOp` |
| `goPrev()` на первом шаге | `currentStepIndex` не меняется | `test_goPrev_atFirstStep_noOp` |
| `goto(0)` или `goto(-1)` | no-op, `lastCommand` записан | `test_goto_negativeOrZero_noOp` |
| `goto(count+1)` | no-op, voice "no such step" | `test_goto_outOfBounds_noOp` |
| `goto(5)` в валидном диапазоне | `currentStepIndex == 4` (0-based) | `test_goto_inRange_advances` |
| `repeatCurrent()` | вызывает TTS `speak(step:)` для текущего шага | `test_repeatCurrent_triggersTTS` |
| `startTimerForCurrentStep()` на шаге с 0 встроенных таймеров | no-op, voice "no timer" | `test_startTimer_noTimerInStep_noOp` |
| `isMicMuted` set + relaunch | `isMicMuted` восстановлен из UserDefaults | `test_micMute_persistence` |
| `CookingStep` extraction: recipe с шагами + paragraphs | paragraphs/headings отброшены, только `.orderedStep` | `test_cookingStep_extraction_filtersNonStepBlocks` |

### Note

VM НЕ зависит от AVFoundation на этом этапе — голосовой pipeline инжектится через protocol, в тестах мокается. Это позволяет тестировать навигацию изолированно.

---

## Шаг 4. `CookingCommandClassifier`

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Services/Cooking/CookingCommandClassifier.swift` | Создан (pure function, no dependencies) |
| `RecipeScalerNative/Services/Cooking/CookingSynonymDictionary.swift` | Создан (RU+EN синонимы) |
| `RecipeScalerNativeTests/CookingCommandClassifierTests.swift` | Создан (snapshot-стиль) |

### Downstream consumers

- [x] **SwiftUI views** — нет (pure logic).
- [x] **Cross-process consumers** — нет.
- [x] **Sync boundaries** — нет.
- [x] **Persisted state** — нет.
- [x] **Tests** — `CookingCommandClassifierTests` (новый).

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| `classify("дальше")` | `.next` | `test_ru_dalshe` |
| `classify("вперёд")` | `.next` | `test_ru_vperyod` |
| `classify("следующий")` | `.next` | `test_ru_sleduyushchiy` |
| `classify("next")` | `.next` | `test_en_next` |
| `classify("go")` | `.next` | `test_en_go` |
| `classify("назад")` | `.prev` | `test_ru_nazad` |
| `classify("вернись")` | `.prev` | `test_ru_vernis` |
| `classify("back")` | `.prev` | `test_en_back` |
| `classify("повтори")` | `.repeatStep` | `test_ru_povtori` |
| `classify("repeat")` | `.repeatStep` | `test_en_repeat` |
| `classify("шаг 5")` | `.goto(5)` | `test_ru_shag_5` |
| `classify("step 3")` | `.goto(3)` | `test_en_step_3` |
| `classify("пятый шаг")` | `.goto(5)` (word-to-number) | `test_ru_word_number` |
| `classify("запусти таймер")` | `.timerStart` | `test_ru_start_timer` |
| `classify("start timer")` | `.timerStart` | `test_en_start_timer` |
| `classify("пауза")` | `.timerPause` | `test_ru_pause` |
| `classify("pause")` | `.timerPause` | `test_en_pause` |
| `classify("продолжи")` | `.timerResume` | `test_ru_resume` |
| `classify("стоп")` | `.timerStop` | `test_ru_stop` |
| `classify("что-то непонятное")` | `.unknown` | `test_unknown_phrase` |
| `classify("   дальше   ")` (whitespace) | `.next` | `test_trim_whitespace` |
| `classify("дальше пожалуйста")` (token AND) | `.next` (оба токена не обязательны в одной команде) или `.unknown` (если "пожалуйста" не в словаре) | `test_token_and_logic` (определяем поведение явно) |
| `classify("ДАЛЬШЕ")` (uppercase) | `.next` | `test_case_insensitive` |
| `classify("café")` | normalizes, не падает | `test_diacritics_normalized` |
| `classify("Château")` | normalizes | `test_diacritics_chateau` |
| `classify("")` | `.unknown` | `test_empty_string` |

### Note

Per [.cursor/rules/search-behavior.mdc](../../.cursor/rules/search-behavior.mdc) — case-insensitive, trim, tokenize, NFKD-нормализация, поддержка quoted phrases. Словарь в Swift коде (не в Localizable.xcstrings — это не UI-текст).

---

## Шаг 5. `CookingAudioEngineSF` (iOS 17+)

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Services/Cooking/CookingTranscript.swift` | Создан (`enum { case partial(String), final(String) }`) |
| `RecipeScalerNative/Services/Cooking/CookingVoiceListening.swift` | Создан (protocol) |
| `RecipeScalerNative/Services/Cooking/CookingAudioEngineSF.swift` | Создан |

### Downstream consumers

- [x] **SwiftUI views** — нет (служба).
- [x] **Cross-process consumers** — нет.
- [x] **Sync boundaries** — нет.
- [x] **Persisted state** — нет (session in-memory).
- [x] **Tests** — manual в симуляторе (тяжело автоматизировать реальный голос); unit-тесты на state machine (`idle` → `listening` → `processing` → `listening`).

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| `start()` без разрешения | throws `CookingVoiceError.permissionDenied` | `CookingAudioEngineSFTests.test_start_noPermission_throws` |
| `start()` когда `SFSpeechRecognizer.isAvailable == false` | throws `CookingVoiceError.speechUnavailable` | `test_start_unavailable_throws` |
| `start()` когда `supportsOnDeviceRecognition == false` для локали | throws `CookingVoiceError.onDeviceNotSupported` | `test_start_onDeviceNotSupported_throws` |
| 60-сек re-arming: после ~55с listening | начинается новая сессия, AsyncStream не закрывается | manual в симуляторе + лог `cooking.sf_rearm` |
| `stop()` во время listening | stream завершается (`.finished`), `AVAudioSession` деактивирована | `test_stop_releasesResources` |
| `suspend()` во время TTS | tap приостановлен, resume() возобновляет | `test_suspend_resume` |

### Note

`AVAudioSession` категория `.playAndRecord`, mode `.default`, options `[.defaultToSpeaker, .allowBluetoothHFP]` (НЕ `.duckOthers` — нам нужен чистый capture). Для iOS 17 — `requestRecordPermission` через `AVAudioApplication.requestRecordPermission` (старый `AVAudioSession.requestRecordPermission` deprecated).

Re-arming: внутренний `Task` отслеживает elapsed time; за 5 сек до таймаута SFSpeechRecognizer'а закрываем текущий `SFSpeechRecognitionTask` и открываем новый с тем же `request`. Без видимого прерывания.

---

## Шаг 6. `CookingAudioAnalyzer` (iOS 26+)

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Services/Cooking/CookingAudioAnalyzer.swift` | Создан (`@available(iOS 26.0, *)`) |
| `RecipeScalerNative/Services/Cooking/AssetInventoryInstaller.swift` | Создан (helper для установки языковой модели) |

### Downstream consumers

- [x] **SwiftUI views** — UI overlay «Устанавливается модель…» в `CookingModeView`.
- [x] **Cross-process consumers** — нет.
- [x] **Sync boundaries** — нет.
- [x] **Persisted state** — нет (assets managed системой через AssetInventory).
- [x] **Tests** — manual в iOS 26 симуляторе.

### Positive invariants

| Эффект | Инвариант | Где проверять |
|--------|-----------|---------------|
| `start()` если RU модель не установлена | triggers `AssetInventory.assetInstallationRequest` download | manual + лог `cooking.asset_install_started` |
| `start()` если `SpeechTranscriber.supportedLocales` не содержит текущую локаль | fallback к `CookingAudioEngineSF` (decides `CookingVoiceProvider`) | manual |
| `start()` после установки модели | успешно стартует transcribe session | manual |
| Cancel install mid-flight | `AssetInstallationRequest.cancel()`, ресурс освобождён | manual |

### Note

API требует careful handling: `AVAudioConverter` из `inputNode.outputFormat` → `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`. Real-time audio tap на отдельном акторе. `reportingOptions = [.volatileResults]` для partial results.

`if #available(iOS 26.0, *)` guard обязателен. Файл компилируется условно (`@available` annotation на class).

---

## Шаг 7. `CookingVoiceProvider` (strategy)

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Services/Cooking/CookingVoiceProvider.swift` | Создан |

### Downstream consumers

- [x] **SwiftUI views** — `CookingModeView` читает `voiceState`, `lastTranscript`.
- [x] **Cross-process consumers** — нет.
- [x] **Sync boundaries** — нет.
- [x] **Persisted state** — нет.
- [x] **Tests** — unit на strategy switch (mock both engines).

### Positive invariants

| Эффект | Инвариант | Где проверять |
|--------|-----------|---------------|
| iOS 26+ device с SpeechAnalyzer available | `voiceProvider.engineName == "speechAnalyzer"` | `CookingVoiceProviderTests.test_ios26_usesSpeechAnalyzer` |
| iOS 17 device | `voiceProvider.engineName == "sfSpeechRecognizer"` | `test_ios17_usesSFSpeechRecognizer` |
| `suspend()` → `resume()` | состояние корректно переходит | `test_suspend_resume` |

---

## Шаг 8. `CookingSpeechSynthesizer`

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Services/Cooking/CookingSpeechSynthesizer.swift` | Создан |
| `RecipeScalerNative/Services/Cooking/CookingSpeechSynthesizerDelegate.swift` | Создан (или inline class) |

### Downstream consumers

- [x] **SwiftUI views** — `CookingModeView` слушает `isSpeaking` для voice status pill.
- [x] **Cross-process consumers** — нет.
- [x] **Sync boundaries** — нет.
- [x] **Persisted state** — нет.
- [x] **Tests** — unit на приоритетах очереди, auto-mute.

### Positive invariants

| Эффект | Инвариант | Где проверять |
|--------|-----------|---------------|
| `speak(step:, priority: .high)` во время говорения low-priority | текущий low-priority прерывается, high начинает говорить | `test_priority_preemption` |
| `speak(step:, priority: .high)` во время говорения high | текущий продолжает, новый встаёт в очередь или дропается | `test_high_priority_no_interrupt` (определяем явно) |
| Start speaking → `CookingVoiceProvider.suspend()` | вызывается на `willSpeakRange` | `test_speaking_suspends_mic` |
| Stop speaking → `CookingVoiceProvider.resume()` | вызывается на `didFinish` | `test_finished_resumes_mic` |
| `stopSpeaking(.immediate)` | все utterances отменены, mic resume() вызван | `test_stopSpeaking_immediate` |

---

## Шаг 9. `CookingModeView` + кнопка входа

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Views/Cooking/CookingModeView.swift` | Создан |
| `RecipeScalerNative/Views/Cooking/CookingStepCard.swift` | Создан (карточка шага для peek-3) |
| `RecipeScalerNative/Views/Cooking/VoiceStatusPill.swift` | Создан |
| `RecipeScalerNative/Views/Cooking/ActiveTimerPanel.swift` | Создан |
| `RecipeScalerNative/Views/Cooking/CookingPermissionsSheet.swift` | Создан (onboarding) |
| `RecipeScalerNative/Views/YDocRecipeDetailView.swift` | Изменён: добавить кнопку «Готовить» рядом с `StepsSection` |
| `RecipeScalerNative/Views/Cooking/CookingLayout.swift` | Создан (токены из layout.md) |

### Downstream consumers

- [x] **SwiftUI views** — `YDocRecipeDetailView` получит новую кнопку (navigation link).
- [x] **Cross-process consumers** — нет.
- [x] **Sync boundaries** — нет (read-only).
- [x] **Persisted state** — `UserDefaults(cooking.voice-mic-muted)`, `UserDefaults(cooking.onboarding-shown)`.
- [x] **Tests** — `bash scripts/verify-ui-smoke.sh`, E2E (UI тест на навигацию кнопками), manual QA voice.

### Positive invariants

| Эффект | Инвариант | Где проверять |
|--------|-----------|---------------|
| `.onAppear` CookingModeView | `ScreenAwakeController.isActive == true`, `CookingVoiceProvider` запущен | `CookingModeViewLifecycleTests.test_onAppear_startsAll` |
| `.onDisappear` CookingModeView | `ScreenAwakeController.isActive == false`, voice stopped, TTS stopped, session released | `test_onDisappear_stopsAll` |
| Recipe с 0 шагов | кнопка «Готовить» не показана | `test_zeroSteps_hidesButton` (UI test) |
| Нажатие «Готовить» без permissions | показывается `CookingPermissionsSheet` | `test_entry_withoutPermissions_showsSheet` (UI test) |
| Tap voice status pill | toggles `isMicMuted`, persist в UserDefaults | `test_tapPill_togglesMute` |

### Note

Layout строго по `layout.md` (см. ниже). Peek-3 через `ScrollViewReader` + `scrollTargetBehavior(.viewAligned)`. Кнопка «Готовить» — `NavigationLink` с push (не sheet).

---

## Шаг 10. DI + i18n + privacy manifest

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/App/AppContainer.swift` | Изменён: добавить lazy properties для `CookingVoiceProvider`, `CookingSpeechSynthesizer`, `CookingCommandClassifier` |
| `RecipeScalerNative/RecipeScalerNativeApp.swift` или `ContentView.swift` | Изменён: `.appEnvironment(_:)` extension |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменён: добавить `cooking.*` ключи (RU + EN) |
| `RecipeScalerNative/PrivacyInfo.xcprivacy` | Изменён: добавить microphone + speech usage |
| `RecipeScalerNative/Info.plist` | Изменён: добавить `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` |
| `docs/PROJECT.md` | Изменён: раздел про cooking mode |
| `docs/NATIVE-FEATURES-NO-PAID-ACCOUNT.md` | Проверить: ничего не требует paid account |

### Downstream consumers

- [x] **SwiftUI views** — `CookingModeView` теперь может `@Environment(CookingVoiceProvider.self)` и т.д.
- [x] **Cross-process consumers** — нет.
- [x] **Sync boundaries** — нет.
- [x] **Persisted state** — нет.
- [x] **Tests** — `bash scripts/lint-i18n.sh` (если есть).

### Positive invariants

| Эффект | Инвариант | Где проверять |
|--------|-----------|---------------|
| Все строки `cooking.*` присутствуют в xcstrings для RU + EN | без fallbacks | `bash scripts/lint-i18n.sh` |
| PrivacyInfo.xcprivacy содержит microphone key | NSMicrophoneUsageDescription reference | manual audit |

### Note

Per CLAUDE.md — все app-level сервисы в `AppContainer`, инжектятся через `.appEnvironment(_:)`. View читает через `@Environment(ServiceType.self)`, НЕ через `.shared`.

---

## Шаг 11. Verify + manual QA

### Verify

- `xcodebuild build` — основной target, iOS 17+ deployment.
- `xcodebuild test` — все новые тест-классы green.
- `bash scripts/audit-ui-layout.sh specs/056-cooking-voice-mode` — passes.
- `bash scripts/verify-ui-smoke.sh` — passes.
- `bash scripts/lint-i18n.sh` — passes (если есть).
- `bash scripts/pull-app-logs.sh` — проверить логи `cooking.*` событий.
- iOS 17 симулятор: навигация кнопками работает, voice работает (если permission).
- iOS 26 симулятор: voice pipeline использует `SpeechAnalyzer` (по логу `cooking.voice_provider`).

### Manual QA чеклист

- [ ] US1: Вход в режим готовки.
- [ ] US2: Навигация голосом (RU + EN).
- [ ] US3: Управление таймером голосом.
- [ ] US4: «Не расслышали» feedback.
- [ ] US5: Прерывание входящим звонком.
- [ ] US6: Выход из режима.
- [ ] US7: Тоггл микрофона.
- [ ] US8: Ошибка распознавания (отключить в Settings → speech unavailable).
- [ ] US9: Установка языковой модели на iOS 26 симуляторе.
- [ ] US10: Privacy hint в onboarding.
- [ ] Battery test: 30 мин готовки, замер drain.
- [ ] Bluetooth HFP: переключение во время готовки.
- [ ] Dark mode: весь UI корректен.
- [ ] Dynamic Type: max size не ломает layout.
