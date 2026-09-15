---

description: "Task list for 077 iOS in-app release notes"
---

# Tasks: in-app новости релиза на iOS

**Input**: Design documents from `/specs/077-ios-release-notes/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/store.md

**Tests**: requested in spec (Positive invariants + LocalizationConsistencyTests).

**Organization**: by user story.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [x] T001 Add i18n chrome keys `release-notes.banner.label`, `release-notes.banner.open`, `release-notes.banner.dismiss`, `release-notes.sheet.title`, `release-notes.account.row` (en+ru) in `RecipeScalerNative/Resources/Localizable.xcstrings`
- [x] T002 [P] Add accessibility ids in `RecipeScalerNative/AccessibilityIdentifiers.swift`
- [x] T003 Register new Swift files in `RecipeScalerNative.xcodeproj/project.pbxproj`

## Phase 2: Foundational

- [x] T004 Create `IOSReleaseNote` in `RecipeScalerNative/Models/IOSReleaseNote.swift`
- [x] T005 Create empty catalog `IOSReleaseNotesCatalog` in `RecipeScalerNative/Services/IOSReleaseNotesCatalog.swift`
- [x] T006 Implement `ReleaseNotesStore` seed/dismiss/presentSheet in `RecipeScalerNative/Services/ReleaseNotesStore.swift`
- [x] T007 Wire store in `RecipeScalerNative/App/AppContainer.swift` and `RecipeScalerNative/App/AppEnvironment.swift` without logout clear

**Checkpoint**: store seeds; empty catalog hides banner

## Phase 3: User Story 1 — Баннер после обновления (P1) 🎯 MVP

**Independent Test**: lastViewed = N, max = N+1 → banner title of N+1; dismiss persists.

### Tests

- [x] T008 [US1] Write failing store tests `test_higher_max_shows_banner`, `test_dismiss_writes_max`, `test_caught_up_hides_banner` in `RecipeScalerNativeTests/ReleaseNotesStoreTests.swift`

### Implementation

- [x] T009 [US1] Implement banner card `RecipeScalerNative/Views/ReleaseNotesBannerView.swift`
- [x] T010 [US1] Implement chrome + list row with screenshot hide in `RecipeScalerNative/Views/ReleaseNotesChrome.swift`
- [x] T011 [US1] Place chrome under 061 in `RecipeScalerNative/Views/RecipeListView.swift` and `RecipeScalerNative/Views/CollectionsRootView.swift`

**Checkpoint**: banner slots and dismiss work

## Phase 4: User Story 2 — Seed / первая сборка молчит (P1)

**Independent Test**: missing key + max 3 → no banner, key 3; empty catalog → no surfaces.

- [x] T012 [US2] Tests `test_missing_key_seeds_max_no_banner`, `test_empty_catalog_hides_surfaces`, `test_empty_catalog_gesture_does_not_invent_notes`, `test_logout_does_not_reset_last_viewed` in `RecipeScalerNativeTests/ReleaseNotesStoreTests.swift`

**Checkpoint**: seed invariants green (store already implements in T006)

## Phase 5: User Story 3 — Архив в Профиле (P1)

**Independent Test**: non-empty catalog → row under adoption; open marks max.

- [x] T013 [US3] Tests `test_open_sheet_writes_max` in `RecipeScalerNativeTests/ReleaseNotesStoreTests.swift`
- [x] T014 [US3] Add archive row + sheet in `RecipeScalerNative/Views/AccountView.swift` under `featureAdoptionSection`

**Checkpoint**: Profile archive opens same store sheet

## Phase 6: User Story 4 — Непрочитанное раскрыто (P2)

**Independent Test**: lastViewed 2, notes 1…4 → 3 and 4 expanded at open.

- [x] T015 [US4] Test `test_unread_expanded_before_mark` in `RecipeScalerNativeTests/ReleaseNotesStoreTests.swift`
- [x] T016 [US4] Implement sheet list in `RecipeScalerNative/Views/ReleaseNotesSheet.swift`
- [x] T017 [US4] Present sheet from banner chrome (Recipes) using store flag

**Checkpoint**: expand-before-write

## Phase 7: Polish

- [x] T018 [P] Add chrome keys to `RecipeScalerNativeTests/LocalizationConsistencyTests.swift`
- [x] T019 Update `.agents/skills/prepare-ios-release/SKILL.md` and `docs/RELEASES.md`
- [x] T020 Run build + `ReleaseNotesStoreTests` + `LocalizationConsistencyTests` + `scripts/lint-i18n.sh`

---

## Dependencies

- Setup → Foundational blocks all stories
- US1 banner UI after store
- US2 tests overlap store (T006)
- US3/US4 need presentSheet
- Polish last

## MVP

T001–T011 (seed + banner + dismiss)

## Parallel

T001/T002; T009/T010 after T006
