# Tasks: 078 Shake → open assistant

**Input**: `specs/078-shake-open-assistant/`  
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md)

## Phase 1: Spec Kit

- [x] T001 Write spec.md / plan.md / research.md / tasks.md

## Phase 2: Preference + detector

- [x] T002 Create `ShakeToOpenAssistantPreference.swift`
- [x] T003 Create `DeviceShakeDetector.swift` (Notification name, UIWindow override, debounce)
- [x] T004 [P] Create `ShakeToOpenAssistantPreferenceTests.swift` (default false, persist, debounce)
- [x] T005 Add new Swift sources to `project.pbxproj`

## Phase 3: Open / attach / voice

- [x] T006 Add `AssistantShakeOpenRequest` + pending/consume/logout clear in `AppShellCoordinator`
- [x] T007 Wire shake `onReceive` + route in `AppShellView` / `AssistantSheetModifier`
- [x] T008 Consume shake in `AssistantSheet` (forceNewChat / auto-attach)
- [x] T009 Auto-start voice one-shot in `AssistantComposer` / Chrome

## Phase 4: Settings + i18n

- [x] T010 Toggle in `AccountView.preferencesSection` + a11y id
- [x] T011 Localizable.xcstrings EN+RU keys
- [x] T012 Add keys to `LocalizationConsistencyTests` critical list

## Phase 5: Verify

- [x] T013 `xcodebuild` build
- [x] T014 `bash scripts/lint-i18n.sh`
- [x] T015 Run preference/debounce unit tests
- [x] T016 Commit on branch (no push; leave release-notes stash)
