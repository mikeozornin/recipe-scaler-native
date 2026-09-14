# Tasks: Hands-free scroll при keep-awake (rev 3)

**Input**: `specs/075-hands-free-cook-controls/` (spec, plan, layout, research, data-model, contracts)  
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md)

> Rev 1 cook Next/Back/List **сняты**. Rev 2 auto-arm с awake **снят**. Ниже только rev 3.  
> Chrome (banner Menu, help, preview) — **после human review** [layout.md](./layout.md).

## Format: `[ID] [P?] [Story] Description`

Пути — от корня репозитория.

## Phase 1: Setup

**Purpose**: Документы Spec Kit (этот проход)

- [x] T001 Rewrite `specs/075-hands-free-cook-controls/spec.md` rev 3 (opt-in banner)
- [x] T002 [P] Rewrite `specs/075-hands-free-cook-controls/layout.md` + `layout-audit.json`
- [x] T003 [P] Rewrite `specs/075-hands-free-cook-controls/research.md` + canonical `plan.md`
- [x] T004 [P] Add `data-model.md`, `contracts/*`, `quickstart.md`, this `tasks.md`

**Checkpoint**: Артефакты на русском, plan с обязательными секциями. STOP: human review layout до UI.

## Phase 2: Foundational

**Purpose**: Engine + probe + arm predicate. BLOCKS stories. Без banner chrome.

- [ ] T005 Create `RecipeScalerNative/Services/Cooking/AwakeScrollAction.swift` (`up`/`down`)
- [ ] T006 [P] Create `RecipeScalerNative/Services/Cooking/AwakeHandsFreeStorage.swift` (key `awakeHandsFreeEnabled`, default false)
- [ ] T007 Create `RecipeScalerNative/Services/Cooking/AwakeScrollEngine.swift` per `contracts/scroll-delta.md`
- [ ] T008 [P] Create `RecipeScalerNativeTests/AwakeScrollEngineTests.swift` (`test_down_scrolls_75_percent`, clamp start/end, height 0 no-op)
- [ ] T009 Create `RecipeScalerNative/Views/DetailScrollViewProbe.swift` (weak host `UIScrollView`, не nested WKWebView)
- [ ] T010 Create `RecipeScalerNative/Services/Cooking/AwakeScrollController.swift` (epoch, F1.1 predicate, cooldown 0.6s, `stop`, single-flight; без capture/speech)
- [ ] T011 [P] Create `RecipeScalerNativeTests/AwakeScrollControllerTests.swift` (predicate false → stop; HF off keeps awake flag; cooking cover disarm; stale epoch ignores apply)
- [ ] T012 Attach `DetailScrollViewProbe` to the recipe `ScrollView` in `RecipeScalerNative/Views/YDocRecipeDetailView.swift` (no Menu yet; apply engine on test hook / controller)
- [ ] T013 Confirm `RecipeScalerNative/Views/YDocRecipeDetailScrollSupport.swift` caret-anchor API unchanged

**Checkpoint**: Unit engine+controller green. Probe compiles. Нет permission dialog от sun.max.

## Phase 3: US0 — Opt-in меню баннера (P1 chrome)

**Goal**: Ellipsis в баннере: флажок Hands-free + справка.  
**Independent Test**: Awake ON → меню видно; HF OFF → нет camera; Help sheet открывается.  
**STOP**: не начинать, пока human не принял `layout.md`.

### Tests

- [ ] T014 [P] [US0] Add LocalizationConsistency coverage for `recipe.awake-scroll.*` after keys exist (`RecipeScalerNativeTests/LocalizationConsistencyTests.swift` if required by project)

### Implementation

- [ ] T015 [US0] Create `RecipeScalerNative/Views/AwakeScrollLayout.swift` tokens (`scrollViewportFraction` 0.75, `bannerAccessorySize` 16, `cameraPreviewDiameter` 48)
- [ ] T016 [P] [US0] Add i18n keys `recipe.awake-scroll.hands-free`, `.help`, `.help.title`, `.help.voice`, `.help.hand`, `.help.face`, `.help.camera`, `.help.permissions`, `.menu` in `RecipeScalerNative/Resources/Localizable.xcstrings` (en+ru)
- [ ] T017 [P] [US0] Add `screen_awake_banner_menu`, `screen_awake_hands_free_toggle`, `screen_awake_help` in `RecipeScalerNative/AccessibilityIdentifiers.swift`
- [ ] T018 [US0] Create `RecipeScalerNative/Views/AwakeScrollHelpSheet.swift` per `contracts/banner-menu.md` + `#Preview`
- [ ] T019 [US0] Extend `RecipeScalerNative/Views/ScreenAwakeStatusBanner.swift` with trailing `Menu` (ellipsis, Toggle, Help) — не `AppToolbarStyle`
- [ ] T020 [US0] Wire banner bindings + controller arm/stop to `handsFreeEnabled` in `RecipeScalerNative/Views/YDocRecipeDetailView.swift`
- [ ] T021 [US0] Run `bash scripts/audit-ui-layout.sh specs/075-hands-free-cook-controls` (expect STATIC PASS after files exist)

**Checkpoint**: sun.max не запрашивает permissions. Quickstart § Awake без Hands-free.

## Phase 4: US1 — Голос (P1)

**Goal**: Armed → «вниз»/«вверх» скроллят 75%.  
**Independent Test**: Simulator/device с mic: final «вниз» двигает offset; near-miss не двигает. Работает без камеры.

### Tests

- [ ] T022 [P] [US1] Create `RecipeScalerNativeTests/AwakeScrollVoiceClassifierTests.swift` (RU/EN whitelist, reject `stop`/`top`/`вверх пожалуйста`)

### Implementation

- [ ] T023 [P] [US1] Create `RecipeScalerNative/Services/Cooking/AwakeScrollVoiceClassifier.swift` per `contracts/voice-whitelist.md`
- [ ] T024 [US1] Create `RecipeScalerNative/Services/Cooking/AwakeScrollVoiceEngine.swift` (on-device `SFSpeechRecognizer`, 60s re-arm, final-only, epoch)
- [ ] T025 [US1] Start/stop voice from `AwakeScrollController` when F1.1 and speech/mic granted; apply engine to probe
- [ ] T026 [US1] Keep voice in `RecipeScalerNative/Services/Cooking/AwakeScrollVoiceEngine.swift` only; do not create `CookingVoiceProvider.swift` / CookingModeView from spec 056

**Checkpoint**: Voice-only device (camera denied) still scrolls.

## Phase 5: US2 — Рука (P2)

**Goal**: Нет TrueDepth → thumbs-up сектора.  
**Independent Test**: Фикстуры точек → один `.up`; dead-zone ignore. На SE/симе без TrueDepth capture path — Hand.

### Tests

- [ ] T027 [P] [US2] Create `RecipeScalerNativeTests/AwakeScrollHandClassifierTests.swift` (`test_hand_up_once`, dead-zone)

### Implementation

- [ ] T028 [P] [US2] Create `RecipeScalerNative/Services/Cooking/AwakeScrollHandClassifier.swift` per `contracts/gesture-mapping.md`
- [ ] T029 [US2] Create `RecipeScalerNative/Services/Cooking/AwakeScrollCaptureSession.swift` Hand branch (≤20 fps, `maximumHandCount` 1, stopRunning on teardown)
- [ ] T030 [US2] Controller selects `.hand` when TrueDepth unsupported; share cooldown with voice
- [ ] T031 [US2] After layout review: optional `RecipeScalerNative/Views/AwakeScrollCameraPreview.swift` 48○ overlay, `allowsHitTesting(false)`, no safeAreaInset

**Checkpoint**: TrueDepth устройства не должны включать Hand одновременно с Face.

## Phase 6: US3 — Лицо (P2)

**Goal**: TrueDepth → blink left/up, right/down.  
**Independent Test**: Classifier tests + 13 Pro quickstart.

### Tests

- [ ] T032 [P] [US3] Create `RecipeScalerNativeTests/AwakeScrollFaceClassifierTests.swift` (`test_left_up`, `test_right_down`, double-blink ignore)

### Implementation

- [ ] T033 [P] [US3] Create `RecipeScalerNative/Services/Cooking/AwakeScrollFaceClassifier.swift`
- [ ] T034 [US3] Capture session Face/ARKit branch when `ARFaceTrackingConfiguration.isSupported`; XOR vs Hand
- [ ] T035 [US3] Help copy already describes Face — verify `recipe.awake-scroll.help.face` matches canon

**Checkpoint**: 13 Pro uses Face; no Hand session alongside.

## Phase 7: US4 — Выключение HF / awake (P1)

**Goal**: HF OFF стопает камеру/mic, awake жив; awake OFF прячет баннер и стопает всё; pref не сбрасывается.  
**Independent Test**: `test_hands_free_off_keeps_awake`; `test_awake_off_teardown`.

- [ ] T036 [US4] Implement HF OFF vs awake OFF paths in `AwakeScrollController` + `YDocRecipeDetailView.swift` (`deactivateScreenAwake` existing)
- [ ] T037 [US4] Assert UserDefaults pref unchanged on awake OFF in `AwakeScrollControllerTests.swift`
- [ ] T038 [US4] Re-arm on next awake ON if pref true (no extra permission if granted)

**Checkpoint**: Quickstart § Выключения 1–4.

## Phase 8: US5 — Отказ permission (P2)

**Goal**: Denied каналы no-op; карточка не блокируется.  
**Independent Test**: Camera denied → voice still; both denied → keep-awake + ручной scroll.

- [ ] T039 [US5] Extend `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` in `RecipeScalerNative/Info.plist` + `RecipeScalerNative/Resources/InfoPlist.xcstrings` (keep QR + assistant; add hands-free)
- [ ] T040 [US5] Add `NSSpeechRecognitionUsageDescription` in `RecipeScalerNative/Info.plist` + `InfoPlist.xcstrings` (en+ru)
- [ ] T041 [US5] Request mic→speech→camera only on HF false→true in `AwakeScrollController` per `contracts/permission-teardown.md`
- [ ] T042 [US5] Stale permission completion test in `AwakeScrollControllerTests.swift`; both denied → no capture, pref may stay true

**Checkpoint**: sun.max never presents speech/camera alerts.

## Phase 9: US6 — Leave / background / cooking / assistant (P1)

**Goal**: Нет listening вне видимой карточки.  
**Independent Test**: Cover present → stopRunning; assistant sheet → stop; background via existing awake teardown.

- [ ] T043 [US6] `onChange` of `ProcessTableCookingCoordinator.presentation` in `YDocRecipeDetailView.swift` (or controller bind) → CoverDisarmed
- [ ] T044 [US6] Disarm when `AssistantRecipeContext.isAssistantSheetOpen` in `YDocRecipeDetailView.swift`
- [ ] T045 [US6] Tests `test_cooking_cover_disarm` and recipeId change stop in `AwakeScrollControllerTests.swift`
- [ ] T046 [US6] Do not listen after `onDisappear` / `scenePhase.background` (reuse `deactivateScreenAwake()`)

**Checkpoint**: Quickstart § 5–7. Green dot off under cooking matrix.

## Phase 10: Polish

- [ ] T047 [P] `bash scripts/lint-i18n.sh`
- [ ] T048 `xcodebuild` build per `docs/AGENT-WORKFLOW.md`
- [ ] T049 Run unit `AwakeScroll*` tests
- [ ] T050 Manual [quickstart.md](./quickstart.md) on iPhone 13 Pro
- [ ] T051 Spawn layout-reviewer subagent vs `layout.md` after chrome
- [ ] T052 Isolated code review-agent (not self-review)

## Dependencies

- Phase 1 → 2 → (US0 after layout gate) → US1. US2/US3 after capture session skeleton (T029). US4/US5/US6 can overlap controller tests in Phase 2 but complete after voice/capture exist.
- US1 не зависит от US2/US3.
- US2 и US3 XOR: не параллелить запись в один capture file без интеграции T034.
- US0 UI не блокирует T005–T011.

### Parallel examples

- T006 ∥ T005; T008 ∥ T007 after engine exists.
- T016 ∥ T017 ∥ T015 after layout gate.
- T022 ∥ T023; T027 ∥ T028; T032 ∥ T033.

## Parallel opportunities

Classifier tests/impl pairs (voice, hand, face) — разные файлы.  
i18n и accessibility ids — параллельно layout tokens.

## Independent test criteria

| Story | Как проверить отдельно |
|-------|-------------------------|
| US0 | Баннер+меню без STT/камеры |
| US1 | Voice + probe, camera denied |
| US2 | Hand fixtures / non-TrueDepth |
| US3 | Face fixtures / 13 Pro |
| US4 | Toggle matrix unit tests |
| US5 | Denied snapshot unit tests |
| US6 | Cover/assistant flags unit tests |

## MVP

T005–T013 + US0 (после layout) + US1 + US4/US6 teardown. Hand/Face и preview — следующий инкремент, но в той же спеке v1.

## Implementation strategy

1. Engine tests first (T008), затем код.  
2. Не класть сервис в `AppContainer`.  
3. Не стартовать 056.  
4. После UI — audit-ui-layout + human acceptance hash `layout.md`.  
5. VERIFIED только с device camera pass и layout acceptance.
