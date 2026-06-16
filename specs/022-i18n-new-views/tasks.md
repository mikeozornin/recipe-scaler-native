# Задачи: локализация новых экранов (022)

**Вход**: `/specs/022-i18n-new-views/`

**Аудит**: 2026-06-15 — все задачи закрыты; `xcodebuild build` зелёный.

## Формат: `[ID] [P?] Описание`

---

## Фаза 1: Edit/detail секции

- [x] T001 `Views/YDocIngredientsSection.swift` — `Text("No ingredients")` → `Text("recipes.no-ingredients")`
- [x] T002 `Views/RecipeDescriptionEditorBlock.swift` — `Text("Instructions")` → `Text("description.instructions")` (повторное использование)

## Фаза 2: `Button("OK", role: .cancel)` ×7

- [x] T003 [P] `Views/RecipeListView.swift:212` → `Button("common.ok", role: .cancel)`
- [x] T004 [P] `Views/CollectionAssignSheet.swift:87` → то же
- [x] T005 [P] `Views/CollectionFolderView.swift:180` → то же
- [x] T006 [P] `Views/ShoppingListView.swift:99` → то же
- [x] T007 [P] `Views/AssistantSheet.swift:119` → то же
- [x] T008 [P] `Views/ManageCollectionRecipesSheet.swift:111` → то же
- [x] T009 [P] `Views/AssistantComposer.swift:73` → то же

## Фаза 3: Splash + a11y

- [x] T010 [P] `Views/SplashView.swift` — `Text("Recipe Scaler")` → `Text("splash.app-name")`
- [x] T011 `Views/MobileTimerPanel.swift` — `.accessibilityLabel("Delete timer")` → `.accessibilityLabel("timer.delete")`
- [x] T012 `Views/MobileTimerPanel.swift` — `toggleAccessibilityLabel` literals (`"Overdue"/"Pause"/"Resume"/"Start"`) → `Bundle.currentLocalizedString("timer.toggle.*")`

## Фаза 4: Каталог

- [x] T013 [P] Добавить в `Localizable.xcstrings` (ru + en): `common.ok`, `recipes.no-ingredients`, `splash.app-name`, `timer.delete`, `timer.toggle.overdue`, `timer.toggle.pause`, `timer.toggle.resume`, `timer.toggle.start`

## Фаза 5: FR-022-002 параметр-тип

- [x] T014 Аудит сигнатур `AppLabel.make` (`String` overload уже локализует через `Bundle.currentLocalizedString`; `LocalizedStringKey` overload тоже работает) и `AppSegmentedControl.Segment.title` (уже `LocalizedStringKey`) — корректно

## Фаза 6: Проверка

- [x] T015 `rtk xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=7CC5ABD7-A34F-4B94-B8CE-A0B396467214' build` → **BUILD SUCCEEDED**

---

## Вне scope (отдельный долг / dead code)

- `Views/TimerExampleView.swift` (dev/demo экран) — внешние литералы; не в navigation path.
- `Views/RecipeDetailView.swift` (pre-YJS preview, не используется — `RecipeListView` открывает `YDocRecipeDetailView`) — внешние литералы; candidate на удаление вместе с `DescriptionEditorView` (см. [019 T021](../019-recipe-description-inline-edit/tasks.md)).
- `Views/DescriptionFixturePreviewView.swift` (debug) — `navigationTitle("Description fixture")`.

Эти три файла — debug/demo код, не виден пользователю в production-сборке; локализация не требуется (FR-022-001 распространяется на новые пользовательские экраны).
