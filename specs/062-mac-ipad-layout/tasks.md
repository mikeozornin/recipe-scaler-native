# Tasks: Mac и iPad — адаптивная оболочка

**Spec**: [spec.md](./spec.md)  
**Plan**: [plan.md](./plan.md)  
**Layout**: [layout.md](./layout.md)  
**Status**: кодовый срез реализован; ручные runtime/accessibility gates остаются незакрытыми.

> Статусы: `[ ]` todo, `[~]` in progress, `[x]` done, `[!]` blocked.  
> `[P]` означает, что задачу можно выполнять параллельно с соседними задачами без
> изменения тех же файлов.

## Phase 1: Setup — platform feasibility

**Цель**: доказать native macOS build path до пользовательского Mac UI.

- [x] T001 [P] Перенести feature-документы в `specs/062-mac-ipad-layout/` и обновить canonical path в `AGENTS.md`.
- [x] T002 [P] Зафиксировать platform matrix для `RecipeScalerCore`, Yrs, SwiftPM dependencies и iOS-only surfaces в `specs/062-mac-ipad-layout/plan.md`.
- [x] T003 Собрать `RecipeScalerCore` для `arm64-apple-macosx` через `Package.swift` и добавить macOS slice в `Frameworks/YrsXCFramework.xcframework/`.
- [x] T004 Добавить native `RecipeScalerMac` target, resources, framework phase и shared scheme в `RecipeScalerNative.xcodeproj/project.pbxproj` и `RecipeScalerNative.xcodeproj/xcshareddata/xcschemes/RecipeScalerMac.xcscheme`.

## Phase 2: Foundational — shared adaptive contracts

**Цель**: один coordinator/service lifecycle и явное разделение layout mode и input profile.

- [x] T005 [P] Добавить `LayoutMode` и resolver по size class в `RecipeScalerNative/ViewModels/LayoutMode.swift`.
- [x] T006 [P] Добавить `InteractionProfile` и neutral-between-strips state machine в `RecipeScalerNative/ViewModels/InteractionProfile.swift`.
- [x] T007 Реализовать clamped UserDefaults contract для route и split widths в `RecipeScalerNative/ViewModels/LayoutPreferencesStore.swift`.
- [x] T008 Расширить wide selection, folder route и compact↔regular bridge в `RecipeScalerNative/Routing/AppShellCoordinator.swift`.
- [x] T009 [P] Добавить sidebar/row/detail accessibility identifiers и необходимые i18n keys в `RecipeScalerNative/AccessibilityIdentifiers.swift` и `RecipeScalerNative/Resources/Localizable.xcstrings`.
- [x] T010 Сохранить единый `AppContainer`/`YjsSyncService`/`AuthService`/`TimerManager` composition root в `RecipeScalerNative/App/AppContainer.swift` и `RecipeScalerNative/App/AppEnvironment.swift`.

## Phase 3: User Story 1 — automatic compact/regular shell (P1) 🎯 MVP

**Цель**: iPhone и iPad compact сохраняют мобильную оболочку, iPad regular получает system split, Mac всегда regular.

**Independent test**: `AdaptiveShellLocalSmokeSpec` на iPad landscape/portrait и iPhone compact; `AdaptiveLayoutTests` для resolver/profile.

- [x] T011 [US1] Разделить iOS shell на compact и regular ветки в `RecipeScalerNative/Views/AppShellView.swift` и `RecipeScalerNative/Views/AdaptiveAppShell/CompactAppShell.swift`.
- [x] T012 [US1] Подключить iOS regular `NavigationSplitView` и Mac regular root в `RecipeScalerNative/Views/AdaptiveAppShell/RegularAppShell.swift`.
- [x] T013 [P] [US1] Добавить resolver/profile/persistence tests в `RecipeScalerNativeTests/AdaptiveLayoutTests.swift`.
- [x] T014 [P] [US1] Добавить backend-independent shell tests в `RecipeScalerNativeUITests/Specs/AppShellNavigationSpec.swift`.

## Phase 4: User Story 2 — system sidebar navigation (P1)

**Цель**: sidebar содержит пять разделов и Import action, использует HIG list chrome и не меняет selection при Import.

**Independent test**: regular sidebar AX smoke, system Show Sidebar toggle и route navigation для Discover/Shopping/Profile/Import.

- [x] T015 [US2] Реализовать `List` + `.listStyle(.sidebar)` и labels в `RecipeScalerNative/Views/AdaptiveAppShell/AppSidebarView.swift`.
- [x] T016 [US2] Подключить sidebar selection/reset/deep-link routing в `RecipeScalerNative/Routing/AppShellCoordinator.swift` и `RecipeScalerNative/Views/AppShellView.swift`.
- [x] T017 [US2] Подключить Mac sidebar commands и Import/assistant command bridge в `RecipeScalerMac/RecipeScalerMacApp.swift`.
- [x] T018 [US2] Покрыть sidebar routes и hide/show system control в `RecipeScalerNativeUITests/Specs/AppShellNavigationSpec.swift`.

## Phase 5: User Story 3 — Recipes three-column selection (P1)

**Цель**: sidebar | list | detail, folder drill-in, auto-select и selection-based detail без push navigation.

**Independent test**: iPad live local-backend seed → row tap → `recipe_detail_menu`; Mac startup/AX smoke с list/detail.

- [x] T019 [US3] Реализовать iOS Recipes columns, empty detail и persisted list divider в `RecipeScalerNative/Views/AdaptiveAppShell/RecipesSplitColumns.swift`.
- [x] T020 [US3] Подключить wide selection/folder bindings и touch `.swipeActions` в `RecipeScalerNative/Views/RecipeListView.swift` и `RecipeScalerNative/Views/CollectionFolderView.swift`.
- [x] T021 [US3] Реализовать scoped auto-select, folder route persistence и selection transition в `RecipeScalerNative/Routing/AppShellCoordinator.swift`.
- [x] T022 [US3] Реализовать native Mac collections/list/selection/actions в `RecipeScalerMac/Views/MacRecipeListView.swift`.
- [x] T023 [US3] Реализовать Mac detail loading, selection fallback и shared mutation actions в `RecipeScalerMac/Views/MacRecipeDetailView.swift`.
- [x] T024 [US3] Исправить wide AX row lookup и live E2E harness в `RecipeScalerNativeUITests/Pages/RecipeListPage.swift`, `RecipeScalerNativeUITests/Helpers/E2EConfig.swift` и `RecipeScalerNativeUITests/Specs/AppShellNavigationSpec.swift`.

## Phase 6: User Story 5 — Discover, Shopping and Profile regular surfaces (P1)

**Цель**: остальные разделы используют настоящий двухколоночный shell без пустой средней колонки.

**Independent test**: iPad/Mac route smoke открывает Discover, Shopping и Profile из sidebar; Shopping share живёт в toolbar.

- [x] T025 [US5] Подключить iOS two-column regular branch в `RecipeScalerNative/Views/AdaptiveAppShell/RegularAppShell.swift`.
- [x] T026 [US5] Реализовать native Mac Discover/Shopping/Profile surfaces в `RecipeScalerMac/Views/MacSurfaceViews.swift`.
- [x] T027 [US5] Перенести Mac Shopping share и nested route actions в `RecipeScalerMac/Views/MacSurfaceViews.swift`.
- [x] T028 [US5] Добавить route assertions для regular surfaces в `RecipeScalerNativeUITests/Specs/AppShellNavigationSpec.swift`.

## Phase 7: User Story 6 — timers in toolbar/inspector (P1)

**Цель**: regular timers не занимают fixed trailing web column и соблюдают description suppress rules.

**Independent test**: toolbar timer entry point и inspector presentation на regular shell; existing timer suppress contract не регрессирует.

- [x] T029 [US6] Добавить regular timer toolbar/inspector content в `RecipeScalerNative/Views/AdaptiveAppShell/TimerInspector.swift` и `RecipeScalerNative/Views/AdaptiveAppShell/RegularAppShell.swift`.
- [x] T030 [US6] Сохранить timer lifecycle/suppress integration через `RecipeScalerNative/Services/TimerManager.swift` и `RecipeScalerNative/Views/DescriptionEditorBridge.swift`.

## Phase 8: User Story 7 — Import and Assistant (P1)

**Цель**: Import открывает sheet без смены selection, Assistant в regular — toolbar, в compact — FAB.

**Independent test**: iPad sidebar Import sheet, Mac `⌘I` Import sheet и `⌘K` Assistant; compact FAB остаётся видимым.

- [x] T031 [US7] Подключить Import presentation/result bridge в `RecipeScalerNative/Views/ImportRecipeSheet.swift`, `RecipeScalerNative/Routing/ImportRecipesResult.swift` и `RecipeScalerNative/Routing/AppShellCoordinator.swift`.
- [x] T032 [US7] Подключить regular Assistant toolbar и compact FAB в `RecipeScalerNative/Views/AppShellView.swift` и `RecipeScalerNative/Views/AdaptiveAppShell/RegularAppShell.swift`.
- [x] T033 [US7] Реализовать Mac Assistant/Import sheets и keyboard-first actions в `RecipeScalerMac/Views/MacSurfaceViews.swift` и `RecipeScalerMac/RecipeScalerMacApp.swift`.
- [x] T034 [US7] Пройти Mac AX smoke для `⌘I`/`⌘K` и Import/Assistant accessibility identifiers в `RecipeScalerMac/Views/MacSurfaceViews.swift`.

## Phase 9: User Story 9 — sync/offline lifecycle (P1)

**Цель**: layout transitions не пересоздают sync session и не очищают offline queue.

**Independent test**: shared AppContainer identity remains stable across shell mode changes; existing Yjs stale-session/reconnect tests remain green.

- [x] T035 [US9] Сохранить service ownership and injection boundary в `RecipeScalerNative/App/AppContainer.swift`, `RecipeScalerNative/App/AppEnvironment.swift` и `RecipeScalerMac/RecipeScalerMacApp.swift`.
- [x] T036 [US9] Добавить DEBUG-only loopback Socket.IO polling override без release transport leakage в `RecipeScalerCore/Config/Config.swift` и `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift`.
- [x] T037 [US9] Сделать локальный E2E URL/ATS harness безопасным для Release в `RecipeScalerNative/Info.plist`, `RecipeScalerNative.xcodeproj/project.pbxproj` и `RecipeScalerNativeUITests/Helpers/E2EConfig.swift`.

## Phase 10: User Story 10 — deep links and Spotlight (P2)

**Цель**: deep links на wide выбирают Recipes/detail selection, на compact сохраняют stack behavior.

**Independent test**: coordinator unit cases и Mac cold-launch pending-link path.

- [x] T038 [US10] Реализовать wide deep-link/import/Spotlight resolution в `RecipeScalerNative/Routing/AppShellCoordinator.swift` и `RecipeScalerMac/RecipeScalerMacApp.swift`.
- [x] T039 [US10] Сохранить compact navigation path behavior и transition bridge в `RecipeScalerNative/Views/AdaptiveAppShell/CompactAppShell.swift` и `RecipeScalerNative/Routing/AppShellCoordinator.swift`.

## Phase 11: User Stories 8 and 11 — platform chrome and comparable actions (P1/P2)

**Цель**: операции одинаковы на iPad и Mac, affordance зависит от `InteractionProfile`.

**Independent test**: iPad `.swipeActions` и Mac hover/context menu/trackpad/keyboard action matrix.

- [x] T040 [US8] Сохранить iOS recipe/ingredient/shopping touch actions в `RecipeScalerNative/Views/RecipeListView.swift`, `RecipeScalerNative/Views/CollectionFolderView.swift`, `RecipeScalerNative/Views/YDocIngredientsSection.swift` и `RecipeScalerNative/Views/ShoppingListView.swift`.
- [x] T041 [US11] Реализовать Mac recipe pointer adapter, context menu, hover/focus strip и `NSEvent.scrollWheel` в `RecipeScalerMac/Views/MacRecipeListView.swift`.
- [x] T042 [US8] Реализовать Mac Shopping hover delete/context menu и Assistant copy/timestamp affordances в `RecipeScalerMac/Views/MacSurfaceViews.swift`.
- [x] T043 [US11] Добавить stable accessibility labels/identifiers и neutral-between-strips unit contract в `RecipeScalerNative/AccessibilityIdentifiers.swift`, `RecipeScalerNative/ViewModels/InteractionProfile.swift` и `RecipeScalerNativeTests/AdaptiveLayoutTests.swift`.

## Phase 12: User Story 4 — Mac nested recipe detail split (P2)

**Цель**: широкая Mac detail column показывает ingredients | description, узкая — единый vertical scroll.

**Independent test**: Mac detail width threshold and persisted ingredients divider; parser renders markup and timer links.

- [x] T044 [US4] Реализовать `HSplitView`, threshold, clamped ingredients width and narrow fallback в `RecipeScalerMac/Views/MacRecipeDetailView.swift`.
- [x] T045 [US4] Реализовать shared markup parser/OpenURL timer links в `RecipeScalerMac/Views/MacRecipeDescriptionView.swift`.
- [x] T046 [US4] Проверить parser/timer/detail runtime smoke на native Mac target в `RecipeScalerMac/Views/MacRecipeDescriptionView.swift` и `RecipeScalerMac/Views/MacRecipeDetailView.swift`.

## Phase 13: Polish and cross-cutting acceptance

**Цель**: закрыть обязательные runtime/manual gates и зафиксировать доказательства.

- [x] T047 [P] Прогнать `xcodebuild build-for-testing` для iOS и Debug/Release `xcodebuild build` для Mac без signing в `RecipeScalerNative.xcodeproj/project.pbxproj`.
- [x] T048 [P] Прогнать `scripts/policy-check.sh`, `scripts/lint-i18n.sh`, `scripts/audit-ui-layout.sh` и `scripts/verify-plan-policy.py` для feature artifacts.
- [x] T049 Обновить `specs/062-mac-ipad-layout/spec.md`, `plan.md`, `layout.md`, `layout-audit.json` и `AGENTS.md` evidence/status.
- [ ] T050 Провести живую iPad regular/Stage Manager проверку: system sidebar collapse, resize, compact fallback, selection/folder preservation и переход compact↔regular за целевые `<300 ms` в `specs/062-mac-ipad-layout/layout.md`.
- [ ] T051 Провести живую Mac проверку default/minimum window, HSplitView fallback, hover/focus/context menu/trackpad actions и accessibility в `specs/062-mac-ipad-layout/layout.md`.
- [ ] T052 После human acceptance создать matching-hash `specs/062-mac-ipad-layout/layout-acceptance.json`, отметить checklist и обновить status в `specs/062-mac-ipad-layout/plan.md`.
- [ ] T053 После acceptance выполнить финальный `xcodebuild test` на доступных iOS destinations и сохранить xcresult paths в `specs/062-mac-ipad-layout/plan.md`.

## Dependencies and execution order

- Phase 1 → Phase 2 → US1/US2/US3 foundational shell.
- US3 depends on US1 and US2; US4 depends on US3 Mac detail selection.
- US5/US6/US7 can proceed after US2 and shared regular shell; US9 is foundational for all live sync flows.
- US10 depends on coordinator bridge from US1/US3; US11 depends on `InteractionProfile` from Phase 2 and row surfaces from US3/US5.
- T050–T053 are final acceptance tasks and must not be marked done from static audit alone.

### Parallel opportunities

- T003, T005, T006 and T009 can run in parallel after the feature docs are stable.
- T013/T014, T026 and T043 touch disjoint test/surface files and can run in parallel after their foundations.
- T029, T031 and T038 are independent regular entry points once `RegularAppShell` exists.
- T050 and T051 can be performed in parallel on iPad and Mac, but T052 depends on both.

## Verification contract

- Build evidence: iOS Simulator `build-for-testing`, Mac Debug and Release generic builds.
- Behavioral evidence: iPad/iPhone AX shell smoke, local-backend iPad selection E2E, Mac startup/AX smoke.
- Static evidence: `git diff --check`, `scripts/policy-check.sh`, `scripts/lint-i18n.sh`, `scripts/audit-ui-layout.sh specs/062-mac-ipad-layout`, `python3 scripts/verify-plan-policy.py specs/062-mac-ipad-layout/plan.md`.
- Final acceptance requires user-reviewed `layout.md` plus `layout-acceptance.json`; a static PASS is not final acceptance.

## Implementation strategy

1. MVP = Phase 1–5: native Mac Recipes slice plus iPad regular shell and compact preservation.
2. Add regular surfaces, timer/assistant/import and shared pointer/touch action matrix.
3. Finish nested Mac detail split and then perform live/manual acceptance.
4. Do not commit or claim completion until T050–T053 are genuinely evidenced.
