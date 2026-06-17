# UI и UX

Web reference: `../recipe-scaler-web/recipe-scaler`.

**Макеты (Figma):** перед версткой — [UI-LAYOUT-FROM-FIGMA.md](./UI-LAYOUT-FROM-FIGMA.md) (`layout.md`, `layout-audit.json`, `scripts/audit-ui-layout.sh`).

---

## Типографика

Все текстовые стили определены в `AppTypography.swift` и `AppFonts.swift`. **Не хардкодь** шрифты и размеры в view-файлах — используй константы и extension-ы.

### Шрифты (AppFonts)

| Роль | Имя | Когда использовать |
|---|---|---|
| `sans` | Martian Grotesk Nr Lt | Body, footnote, subheadline — основной текст |
| `sansMedium` | Martian Grotesk Nr Md | Headline, title3, semibold-варианты |
| `display` | Martian Grotesk Std xBd | Заголовки (title2, large title) |
| `mono` | Martian Grotesk Nr Lt | Числа, код (`/connect`) |

### Размеры и стили (AppTypography)

| Стиль | Размер | Шрифт | lineSpacing | Использование |
|---|---|---|---|---|
| `body` | 16 pt | sans | 4 pt | Основной текст списков, строк рецептов, ингредиентов |
| `footnote` | 13 pt | sans | 2 pt | Подписи, badge-и, secondary-текст |
| `subheadline` | 15 pt | sans | — | Редко; prefer body |
| `headline` | 16 pt | sansMedium | — | Жирный body |
| `title3` | 20 pt | sansMedium | — | Подзаголовки |
| `title2` | 22 pt | display | — | Заголовки экранов |
| `compact` | 14 pt | sans | — | Секционные заголовки в списке |
| empty state icon | 48 pt | SF Symbol | — | `AppEmptyState.icon` / `ContentUnavailableView` |

### Text extensions (SwiftUI)

Используй вместо ручного `.font(...)` + `.lineSpacing(...)`:

```swift
Text("some key").appBody()       // 16 pt + lineSpacing 4
Text("some key").appFootnote()   // 13 pt + lineSpacing 2
```

**Почему:** гарантирует единый интерлиньяж везде. Если нужно добавить lineSpacing для нового стиля — добавь константу в `AppTypography` + `Text` extension.

**Ограничение:** `.appBody()` / `.appFootnote()` возвращают `some View`, а не `Text`. После них нельзя вызывать Text-specific модификаторы (`.textCase`, `.tracking`). Для таких случаев используй `.font(AppTypography.footnote)` напрямую (например, `AppSectionHeader`).

### View extension для List/Form

```swift
.appListBodyTypography()   // font(AppTypography.body) на весь List
.appBodyFieldTypography()  // body 16 pt + lineSpacing 4 для TextField
```

Применяй к корневому view списка, чтобы все некастомные Text внутри наследовали body.

### Секционные заголовки

```swift
AppSectionHeader("key")       // footnote, .secondary, uppercase, tracking 0.8
AppSectionHeaderSpacer()      // невидимый placeholder для отступа
```

### UIKit chrome (AppChromeAppearance)

Глобально настраивает шрифты для NavigationBar, BarButtonItems, TabBar, UITextField, UISegmentedControl через `appearance()`. Вызывается один раз при старте приложения.

### Keyboard toolbar

Кастомная панель над клавиатурой — `ToolbarItemGroup(placement: .keyboard)`. Стили кнопок — `AppToolbarStyle` + `.appToolbarIconButton()` / `.appToolbarTextButton()`.

#### Отступы между кнопками

SwiftUI не добавляет зазор между соседними icon-кнопками в одной группе. Между **соседними кнопками слева** (например, `chevron.up` и `chevron.down`) — **8 pt**:

```swift
ToolbarItemGroup(placement: .keyboard) {
    Button { focusPrevious() } label: {
        AppToolbarStyle.icon("chevron.up")
    }
    .appToolbarIconButton()
    .disabled(!canFocusPrevious)

    Color.clear.frame(width: 8)

    Button { focusNext() } label: {
        AppToolbarStyle.icon("chevron.down")
    }
    .appToolbarIconButton()
    .disabled(!canFocusNext)

    Spacer()

    Button(String(localized: "edit.done")) { focusedField = nil }
        .appToolbarTextButton()
}
```

**Правила:**

1. **8 pt** — стандартный горизонтальный зазор между соседними icon-кнопками в левой группе; реализуй через `Color.clear.frame(width: 8)`, не через `padding` на самих кнопках.
2. **Левая группа / правая кнопка** — между ними `Spacer()` (как в примере выше).
3. **Одна текстовая кнопка справа** (Done, Add, Create) — `Spacer()` слева, без дополнительных отступов.
4. Новые keyboard toolbar с несколькими icon-кнопками подряд — тот же паттерн: `Color.clear.frame(width: 8)` между каждой парой соседних.

Эталон: `YDocIngredientsSection`, `EditIngredientNutritionSheet`.

### Правила типографики

1. **Text view** → используй `.appBody()` / `.appFootnote()` вместо ручного `.font()` + `.lineSpacing()`.
2. **Не-Text view** (SF Symbols, HStack, ZStack) → используй `.font(AppTypography.xxx)` напрямую.
3. **TextField** → `.font(AppTypography.body)`; если нужна та же высота строки, что у `.appBody()` (поля названия ингредиента), — `.appBodyFieldTypography()`.
4. **Toggle label** → передавай `Text(...)` с `.appBody()` вместо строкового ключа.
5. **Новый стиль с lineSpacing** → добавь константу в `AppTypography` + `Text` extension, обнови `RecipeRowLayoutMetrics` если нужно.
6. Не создавай fallback вроде `t('key') || 'Default'` — см. [I18N.md](I18N.md).
7. **Keyboard toolbar** — см. раздел выше; между соседними icon-кнопками слева всегда 8 pt.
8. **ContentUnavailableView** — см. подраздел ниже; не полагайся на наследование от `.appListBodyTypography()`.

### ContentUnavailableView

`ContentUnavailableView` **не наследует** Martian от `.appListBodyTypography()` на родителе — рисует системный SF Pro. Явно задавай типографику в каждом слоте:

- **Title:** `AppEmptyState.label(key, symbol:)` — Martian title + **48 pt** icon (`AppTypography.emptyStateIconSize`, weight `.light` по умолчанию).
- **Description:** всегда `Text(...).appBody()` (или `.font(AppTypography.body)`).
- **Кастомная иконка** (цвет папки и т.п.): `AppEmptyState.icon("folder").foregroundStyle(color)` в `Label { … } icon: { … }`.
- **Не использовать** convenience-инициализатор `ContentUnavailableView("title", systemImage:)` — SF-текст и нет единого размера иконки.
- **`ContentUnavailableView.search`** — не использовать; для поиска без результатов — `AppEmptyState.label("recipe.list.search-empty.title", symbol: "magnifyingglass")` (без description).
- При необходимости перебить системный стиль label-слота — `.font(AppTypography.body)` на весь `ContentUnavailableView`.

Эталоны: `RecipeListView`, `CollectionFolderView`, `DiscoverRootView`.

```swift
ContentUnavailableView {
    AppEmptyState.label("recipe.list.empty.title", symbol: "fork.knife")
} description: {
    Text("recipe.list.empty.description")
        .appBody()
}
.font(AppTypography.body)
```

---

## Стандартные компоненты iOS

Если запрос **противоречит поведению или гайдлайнам стандартных компонентов iOS** (Human Interface Guidelines, системным компонентам iOS) — **сначала уточни у пользователя**, что он действительно хочет именно это, а не обходной путь.

Примеры, когда нужно спросить:

- ручное переключение outline / `.fill` в `tabItem` вместо штатного tint активной вкладки;
- кастомный UIKit поверх SwiftUI там, где системный компонент уже решает задачу;
- поведение, которое ломает ожидаемые жесты, accessibility или внешний вид платформы.

Предложи **стандартный вариант** (кратко, почему так принято на iOS) и **альтернативу** (кастом / полная переделка), если пользователь настаивает — делай по его выбору.

## Web parity

- UX/UI parity with the **mobile web** layout (same hierarchy and behavior; pixel-perfect match not required).
- Match web behavior for shared UI: masked `userId`, ingredient rows without unit labels, component-level nutrition editing, recipe ellipsis menu order, ingredient qty column right-aligned to main value with compact drag handle and swipe-from-right delete only; description formatting toolbar active states must mirror Tiptap `selectionState` (e.g. H1 must not imply bold).

## Экраны и паттерны

### Account / public profile

iOS Settings patterns (toggles, `NavigationLink` submenus, label–value rows); no explicit Save button; avatar as centered circle with Set photo below; descriptive copy uses `.appBody()` line-height.

### Shopping list

Header matches Recipes: large title with sort segment in the collapsible search slot (`UISearchController` / `UISearchBar` pattern — SwiftUI has no separate API for a custom block under large title).

### Collections

Folder rename uses inline **Cancel / Done** toolbar, auto-focus with select-all, hides back button and ellipsis while editing; folder color picker is a preset grid in the rename toolbar (web parity, iOS-adapted).

### Discover + assistant

- **Discover** — horizontal cards (photo right, 16:9 previews, count badge, no username, list-level padding only).
- **Assistant** — no Close on swipe-dismissible sheets, keyboard Done, history left / new chat right, always-visible timestamps/copy, `.appFootnote()` text, attach picker sort matches All Recipes flat list.
