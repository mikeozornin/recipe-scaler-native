# Tasks: Hands-free scroll при keep-awake (rev 4)

**Input**: `specs/075-hands-free-cook-controls/` (spec, plan, layout, research, data-model, contracts)  
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md)

> Rev 1 cook Next/Back/List **сняты**. Rev 2 auto-arm **снят**. Rev 3 Menu+один флажок **снят UI**. T005–T052 — сделанный фундамент.  
> Chrome rev 4 (banner icons, sheet) — **после human review** [layout.md](./layout.md).

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

- [x] T005 Create `RecipeScalerNative/Services/Cooking/AwakeScrollAction.swift` (`up`/`down`)
- [x] T006 [P] Create `RecipeScalerNative/Services/Cooking/AwakeHandsFreeStorage.swift` (key `awakeHandsFreeEnabled`, default false)
- [x] T007 Create `RecipeScalerNative/Services/Cooking/AwakeScrollEngine.swift` per `contracts/scroll-delta.md`
- [x] T008 [P] Create `RecipeScalerNativeTests/AwakeScrollEngineTests.swift` (`test_down_scrolls_75_percent`, clamp start/end, height 0 no-op)
- [x] T009 Create `RecipeScalerNative/Views/DetailScrollViewProbe.swift` (weak host `UIScrollView`, не nested WKWebView)
- [x] T010 Create `RecipeScalerNative/Services/Cooking/AwakeScrollController.swift` (epoch, F1.1 predicate, cooldown 0.6s, `stop`, single-flight; без capture/speech)
- [x] T011 [P] Create `RecipeScalerNativeTests/AwakeScrollControllerTests.swift` (predicate false → stop; HF off keeps awake flag; cooking cover disarm; stale epoch ignores apply)
- [x] T012 Attach `DetailScrollViewProbe` to the recipe `ScrollView` in `RecipeScalerNative/Views/YDocRecipeDetailView.swift` (no Menu yet; apply engine on test hook / controller)
- [x] T013 Confirm `RecipeScalerNative/Views/YDocRecipeDetailScrollSupport.swift` caret-anchor API unchanged

**Checkpoint**: Unit engine+controller green. Probe compiles. Нет permission dialog от sun.max.

## Phase 3: US0 — Opt-in меню баннера (P1 chrome)

**Goal**: Ellipsis в баннере: флажок Hands-free + справка.  
**Independent Test**: Awake ON → меню видно; HF OFF → нет camera; Help sheet открывается.  
**STOP**: не начинать, пока human не принял `layout.md`.

### Tests

- [x] T014 [P] [US0] Add LocalizationConsistency coverage for `recipe.awake-scroll.*` after keys exist (`RecipeScalerNativeTests/LocalizationConsistencyTests.swift` if required by project)

### Implementation

- [x] T015 [US0] Create `RecipeScalerNative/Views/AwakeScrollLayout.swift` tokens (`scrollViewportFraction` 0.75, `bannerAccessorySize` 16, `cameraPreviewDiameter` 48)
- [x] T016 [P] [US0] Add i18n keys `recipe.awake-scroll.hands-free`, `.help`, `.help.title`, `.help.voice`, `.help.hand`, `.help.face`, `.help.camera`, `.help.permissions`, `.menu` in `RecipeScalerNative/Resources/Localizable.xcstrings` (en+ru)
- [x] T017 [P] [US0] Add `screen_awake_banner_menu`, `screen_awake_hands_free_toggle`, `screen_awake_help` in `RecipeScalerNative/AccessibilityIdentifiers.swift`
- [x] T018 [US0] Create `RecipeScalerNative/Views/AwakeScrollHelpSheet.swift` per `contracts/banner-menu.md` + `#Preview`
- [x] T019 [US0] Extend `RecipeScalerNative/Views/ScreenAwakeStatusBanner.swift` with trailing `Menu` (ellipsis, Toggle, Help) — не `AppToolbarStyle`
- [x] T020 [US0] Wire banner bindings + controller arm/stop to `handsFreeEnabled` in `RecipeScalerNative/Views/YDocRecipeDetailView.swift`
- [x] T021 [US0] Run `bash scripts/audit-ui-layout.sh specs/075-hands-free-cook-controls` (expect STATIC PASS after files exist)

**Checkpoint**: sun.max не запрашивает permissions. Quickstart § Awake без Hands-free.

## Phase 4: US1 — Голос (P1)

**Goal**: Armed → «вниз»/«вверх» скроллят 75%.  
**Independent Test**: Simulator/device с mic: final «вниз» двигает offset; near-miss не двигает. Работает без камеры.

### Tests

- [x] T022 [P] [US1] Create `RecipeScalerNativeTests/AwakeScrollVoiceClassifierTests.swift` (RU/EN whitelist, reject `stop`/`top`/`вверх пожалуйста`)

### Implementation

- [x] T023 [P] [US1] Create `RecipeScalerNative/Services/Cooking/AwakeScrollVoiceClassifier.swift` per `contracts/voice-whitelist.md`
- [x] T024 [US1] Create `RecipeScalerNative/Services/Cooking/AwakeScrollVoiceEngine.swift` (on-device `SFSpeechRecognizer`, 60s re-arm, final-only, epoch)
- [x] T025 [US1] Start/stop voice from `AwakeScrollController` when F1.1 and speech/mic granted; apply engine to probe
- [x] T026 [US1] Keep voice in `RecipeScalerNative/Services/Cooking/AwakeScrollVoiceEngine.swift` only; do not create `CookingVoiceProvider.swift` / CookingModeView from spec 056

**Checkpoint**: Voice-only device (camera denied) still scrolls.

## Phase 5: US2 — Рука (P2)

**Goal**: Нет TrueDepth → thumbs-up сектора.  
**Independent Test**: Фикстуры точек → один `.up`; dead-zone ignore. На SE/симе без TrueDepth capture path — Hand.

### Tests

- [x] T027 [P] [US2] Create `RecipeScalerNativeTests/AwakeScrollHandClassifierTests.swift` (`test_hand_up_once`, dead-zone)

### Implementation

- [x] T028 [P] [US2] Create `RecipeScalerNative/Services/Cooking/AwakeScrollHandClassifier.swift` per `contracts/gesture-mapping.md`
- [x] T029 [US2] Create `RecipeScalerNative/Services/Cooking/AwakeScrollCaptureSession.swift` Hand branch (≤20 fps, `maximumHandCount` 1, stopRunning on teardown)
- [x] T030 [US2] Controller selects `.hand` when TrueDepth unsupported; share cooldown with voice
- [x] T031 [US2] After layout review: optional `RecipeScalerNative/Views/AwakeScrollCameraPreview.swift` 48○ overlay, `allowsHitTesting(false)`, no safeAreaInset

**Checkpoint**: TrueDepth устройства не должны включать Hand одновременно с Face.

## Phase 6: US3 — Лицо (P2)

**Goal**: TrueDepth → blink left/up, right/down.  
**Independent Test**: Classifier tests + 13 Pro quickstart.

### Tests

- [x] T032 [P] [US3] Create `RecipeScalerNativeTests/AwakeScrollFaceClassifierTests.swift` (`test_left_up`, `test_right_down`, double-blink ignore)

### Implementation

- [x] T033 [P] [US3] Create `RecipeScalerNative/Services/Cooking/AwakeScrollFaceClassifier.swift`
- [x] T034 [US3] Capture session Face/ARKit branch when `ARFaceTrackingConfiguration.isSupported`; XOR vs Hand
- [x] T035 [US3] Help copy already describes Face — verify `recipe.awake-scroll.help.face` matches canon

**Checkpoint**: 13 Pro uses Face; no Hand session alongside.

## Phase 7: US4 — Выключение HF / awake (P1)

**Goal**: HF OFF стопает камеру/mic, awake жив; awake OFF прячет баннер и стопает всё; pref не сбрасывается.  
**Independent Test**: `test_hands_free_off_keeps_awake`; `test_awake_off_teardown`.

- [x] T036 [US4] Implement HF OFF vs awake OFF paths in `AwakeScrollController` + `YDocRecipeDetailView.swift` (`deactivateScreenAwake` existing)
- [x] T037 [US4] Assert UserDefaults pref unchanged on awake OFF in `AwakeScrollControllerTests.swift`
- [x] T038 [US4] Re-arm on next awake ON if pref true (no extra permission if granted)

**Checkpoint**: Quickstart § Выключения 1–4.

## Phase 8: US5 — Отказ permission (P2)

**Goal**: Denied каналы no-op; карточка не блокируется.  
**Independent Test**: Camera denied → voice still; both denied → keep-awake + ручной scroll.

- [x] T039 [US5] Extend `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` in `RecipeScalerNative/Info.plist` + `RecipeScalerNative/Resources/InfoPlist.xcstrings` (keep QR + assistant; add hands-free)
- [x] T040 [US5] Add `NSSpeechRecognitionUsageDescription` in `RecipeScalerNative/Info.plist` + `InfoPlist.xcstrings` (en+ru)
- [x] T041 [US5] Request mic→speech→camera only on HF false→true in `AwakeScrollController` per `contracts/permission-teardown.md`
- [x] T042 [US5] Stale permission completion test in `AwakeScrollControllerTests.swift`; both denied → no capture, pref may stay true

**Checkpoint**: sun.max never presents speech/camera alerts.

## Phase 9: US6 — Leave / background / cooking / assistant (P1)

**Goal**: Нет listening вне видимой карточки.  
**Independent Test**: Cover present → stopRunning; assistant sheet → stop; background via existing awake teardown.

- [x] T043 [US6] `onChange` of `ProcessTableCookingCoordinator.presentation` in `YDocRecipeDetailView.swift` (or controller bind) → CoverDisarmed
- [x] T044 [US6] Disarm when `AssistantRecipeContext.isAssistantSheetOpen` in `YDocRecipeDetailView.swift`
- [x] T045 [US6] Tests `test_cooking_cover_disarm` and recipeId change stop in `AwakeScrollControllerTests.swift`
- [x] T046 [US6] Do not listen after `onDisappear` / `scenePhase.background` (reuse `deactivateScreenAwake()`)

**Checkpoint**: Quickstart § 5–7. Green dot off under cooking matrix.

## Phase 10: Polish

- [x] T047 [P] `bash scripts/lint-i18n.sh`
- [x] T048 `xcodebuild` build per `docs/AGENT-WORKFLOW.md`
- [x] T049 Run unit `AwakeScroll*` tests
- [ ] T050 Manual [quickstart.md](./quickstart.md) on iPhone 13 Pro
- [x] T051 Spawn layout-reviewer subagent vs `layout.md` after chrome
- [x] T052 Isolated code review-agent (not self-review)

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

## Phase 11: Rev 4 — каналы + Figma sheet (P1 chrome)

**Goal**: Ellipsis открывает единый sheet; три тумблера; иконки в баннере; XOR; live; denied+Settings.  
**Independent Test**: Awake ON, каналы OFF → нет camera; ellipsis → sheet; voice-only → waveform, нет green dot.  
**STOP**: не начинать UI, пока human не принял [layout.md](./layout.md) rev 4.

### Tests

- [x] T053 [P] [US0] XOR + migration + snap-off tests in `RecipeScalerNativeTests/AwakeScrollControllerTests.swift` (`test_hand_xor_disables_face`, `test_face_xor_disables_hand`, `test_mic_denied_snaps_voice_off`, migrate old `awakeHandsFreeEnabled`)
- [x] T054 [P] [US0] Storage tests / coverage for three keys in `RecipeScalerNative/Services/Cooking/AwakeHandsFreeStorage.swift` (or controller tests)

### Implementation

- [x] T055 [US0] Replace `AwakeHandsFreeStorage` with voice/hand/face keys + one-shot migration from `awakeHandsFreeEnabled` in `RecipeScalerNative/Services/Cooking/AwakeHandsFreeStorage.swift`
- [x] T056 [US0] Per-channel F1.1 in `RecipeScalerNative/Services/Cooking/AwakeScrollController.swift` (voice vs camera; hide/ignore face without TrueDepth)
- [x] T057 [US0] Tokens `bannerChannelIconSize` 16, `helpChipHeight` 34, `helpGestureIconSize` 64 in `RecipeScalerNative/Views/AwakeScrollLayout.swift`
- [x] T058 [P] [US0] Add i18n keys from `contracts/banner-menu.md` (intro, energy, channel titles, try-*, chips, denied, open-settings) in `RecipeScalerNative/Resources/Localizable.xcstrings` (en+ru)
- [x] T059 [P] [US0] Accessibility ids for three toggles, settings button, banner channel icons in `RecipeScalerNative/AccessibilityIdentifiers.swift`
- [x] T060 [US0] Rewrite `RecipeScalerNative/Views/AwakeScrollHelpSheet.swift` per layout.md + Figma `404:4872` + `#Preview` for off / voice+hand / fired / denied
- [x] T061 [US0] `ScreenAwakeStatusBanner`: Button ellipsis (no Menu Toggle), channel icons after title, in `RecipeScalerNative/Views/ScreenAwakeStatusBanner.swift`
- [x] T062 [US0] Wire three prefs + sheet + XOR + Open Settings in `RecipeScalerNative/Views/YDocRecipeDetailView.swift`
- [x] T063 [US1] Live chip color from last matched phrase in `AwakeScrollHelpSheet.swift` / controller pulse
- [x] T064 [US2] Live 64pt hand icons; user XOR disables face in controller + storage
- [x] T065 [US3] Live eyes; hide Face row when TrueDepth unsupported
- [x] T066 [US5] Request permissions per channel; snap-off+disable; Settings button per `contracts/permission-teardown.md`
- [x] T067 `bash scripts/audit-ui-layout.sh specs/075-hands-free-cook-controls`
- [x] T068 `bash scripts/lint-i18n.sh` + `xcodebuild` build + unit `AwakeScroll*`

**Checkpoint**: quickstart rev 4. Human layout-acceptance до VERIFIED.

## Dependencies (rev 4)

- T053–T056 до T060–T062.
- T057–T059 параллельны после layout gate.
- T063–T066 после T060.
- Engine T005–T013 и classifiers T022–T034 остаются; не переписывать без нужды.

## MVP rev 4

T055–T062 + voice live + denied Settings. Hand/face live icons — тот же инкремент v1.
