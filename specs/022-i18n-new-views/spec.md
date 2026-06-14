# Спецификация: локализация новых экранов (ru/en)

**Ветка**: `022-i18n-new-views`  
**Дата**: 2026-06-03  
**Статус**: 🟡 В работе (~75%, аудит 2026-06-15) — Discover/Import/Assistant/Account/Collections на ключах; остаток: edit-секции, `Button("OK")`, a11y, lint  
**Зависимости**: новые экраны 006/007/024/010/011/012/013/015  
**Эталон**: принцип паритета #6 в `005-mobile-web-parity-roadmap` («i18n ru/en для всех новых строк»), существующие ключи `discover.*`, `account.*`, `recipe.*`

## Контекст

Аудит 2026-06-03 зафиксировал массовые английские литералы. **2026-06-15**: доменные экраны (Discover, Import, Assistant, Account, Collections, Shopping) переведены на ключи. Остаётся debt в edit/detail секциях.

## Затронутые файлы — остаток (2026-06-15)

| Файл | Проблема |
|------|----------|
| `Views/YDocIngredientsSection.swift` | `Text("No ingredients")` |
| `Views/RecipeDescriptionEditorBlock.swift` | `Text("Instructions")` |
| `Views/RecipeListView.swift`, `CollectionFolderView.swift`, … | `Button("OK", role: .cancel)` (7 view) |
| `Views/SplashView.swift` | `Text("Recipe Scaler")` |
| `Views/MobileTimerPanel.swift` | `.accessibilityLabel("Delete timer")` |

## Прошлый перечень (2026-06-03, частично закрыт)

| Файл | Было |
|------|------|
| `Views/AssistantSheet.swift` | ✅ на `assistant.*` |
| `Views/DiscoverRootView.swift` | ✅ на `discover.*` |
| `Views/ImportRecipeSheet.swift` | ✅ на `import.*` |
| `Views/RecipeDetailActionsMenu.swift` | ✅ |
| `Views/AccountView.swift` | ✅ (кроме `account.data.coming-soon`) |

> Примечание: `String(localized: "…")` и `Text("…")` используют строку как ключ и авто-локализуются **только если ключ есть в каталоге с ru-переводом**. `AppLabel.make(_:symbol:)` и `AppSegmentedControl.Segment(title:)` — проверить, что параметр типа `LocalizedStringKey`, а не `String` (иначе локализации не будет вовсе).

## Цель

Все пользовательские строки новых экранов — через ключи в `Localizable.xcstrings` с ru- и en-значениями; в русской локали нет английских подписей.

## Пользовательские сценарии

### US1 — Русская локаль (P1)

**Дано** язык приложения = ru, **когда** пользователь открывает Discover, Import, Assistant, меню действий рецепта, **тогда** все подписи на русском.

### US2 — Английская локаль (P1)

**Дано** язык = en, **тогда** те же экраны на английском (значения из каталога, не «случайные» литералы-ключи).

### US3 — Полнота каталога (P1)

**Тогда** в `Localizable.xcstrings` нет строк со state `needs_review`/отсутствующим ru для новых ключей.

## Требования

### FR-022-001 — Вынести литералы в ключи

Заменить bare-литералы в перечисленных файлах на доменные ключи (стиль `discover.*`, `import.*`, `assistant.*`, `recipe.detail.*`).

### FR-022-002 — Тип параметров

Проверить/исправить сигнатуры хелперов (`AppLabel.make`, `AppSegmentedControl.Segment`) на `LocalizedStringKey`.

### FR-022-003 — Каталог

Добавить ru + en значения для всех новых ключей; пройти полным проходом по `Views/` (grep на `Text("[A-Z]`, `Button("[A-Z]`, `title: "`, `navigationTitle("`).

### FR-022-004 — Проверка

Скрипт/линт: список вьюх без захардкоженных литералов; ручной прогон ru/en.

## Вне scope

- Перевод контента рецептов (пользовательские данные)
- Новые фичи (только локализация существующих экранов)

## Критерии успеха

- **SC-001**: В ru-локали на Discover/Import/Assistant/меню рецепта нет английских подписей.
- **SC-002**: Grep по `Views/` не находит новых пользовательских bare-литералов вне каталога.
- **SC-003**: `Localizable.xcstrings` содержит ru+en для всех новых ключей.

## Артефакты

- `quickstart.md` — ручной чек ru ↔ en по экранам
- список ключей в `Localizable.xcstrings`
