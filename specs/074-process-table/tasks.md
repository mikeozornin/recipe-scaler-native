# Tasks: Таблица процесса (074)

**Input**: `specs/074-process-table/` (spec, plan, layout, contracts)

## Phase 1: Setup

- [x] T001 Create `tasks.md` and Cooking/YDoc file stubs listed in plan.md
- [x] T002 [P] Add i18n keys `recipe.process-table.*` + `time.short.*` in `Localizable.xcstrings`

## Phase 2: Foundational

- [x] T003 `ProcessTableV1` decode in `RecipeScalerNative/Models/YDoc/ProcessTableV1.swift`
- [x] T004 `processTableRaw` on `RecipeData` + codec/reader read
- [x] T005 Port source hash in `ProcessTableSourceHash.swift`
- [x] T006 Merge/order/timers in `ProcessTableMatrix.swift`
- [x] T007 Preserve `processTable` on ingredient write (no map clear)
- [x] T008 Unit tests: hash, decode, merge, preserve

## Phase 3: US1 Cooking entry + matrix (P1)

- [x] T009 `ProcessTableLayout.swift` tokens matching layout-audit
- [x] T010 CTA in `StepsSection` header row + `ProcessTableStartButton`
- [x] T011 `ProcessTableCookingView` NavigationStack + geometry + keep-awake
- [x] T012 Prep stack + grid sticky 25% + merge spans + checkboxes
- [x] T013 Timer chips + leftover inset; wire YDoc + Discover covers
- [x] T014 Status banner (stale / not-built)

## Phase 4: US2 Rebuild (P2)

- [x] T015 `APIClient.rebuildProcessTable`
- [x] T016 `ProcessTableRebuildModel` single-flight + toast + identity
- [x] T017 Rebuild unit test (stale completion)

## Phase 5: Polish

- [x] T018 Accessibility ids, LocalizationConsistencyTests
- [x] T019 `audit-ui-layout.sh specs/074-process-table`
- [x] T020 i18n lint + xcodebuild
- [x] T021 Hosted cooking layout XCTest (finite frames + cover stays presented; no app shell)
- [x] T022 Live-scene XCTest: present cooking host → `requestGeometryUpdate(.landscape)` succeeds
