# Contract: banner menu UI

**Owner**: `ScreenAwakeStatusBanner`  
**Layout**: [layout.md](../layout.md)

## Visibility

Баннер как сейчас: только `isScreenAwakeActive`. Menu живёт только в баннере.

## Menu

- Label: SF Symbol `ellipsis`, 16 pt, цвет `bannerText`.
- a11y label: `recipe.awake-scroll.menu`
- a11y id: `screen_awake_banner_menu`

### Item 1 — Hands-free

- `Toggle` bound to `AwakeHandsFreeStorage` / binding из parent.
- Title: `recipe.awake-scroll.hands-free`
- a11y id: `screen_awake_hands_free_toggle`
- ON → parent ставит pref true и просит controller arm.
- OFF → pref false, controller stop, awake не трогать.

### Item 2 — Help

- `Button` → `showingHelp = true`
- Title: `recipe.awake-scroll.help`
- a11y id: `screen_awake_help`
- Sheet: `AwakeScrollHelpSheet`

Запрещено: `Button` Hands-free в toolbar; второй `sun.max`.

## Help sheet copy keys

| Key | Содержание |
|-----|------------|
| `recipe.awake-scroll.help.title` | заголовок |
| `recipe.awake-scroll.help.voice` | фразы вверх/вниз RU+EN |
| `recipe.awake-scroll.help.hand` | thumbs-up сектора |
| `recipe.awake-scroll.help.face` | моргание L/R, TrueDepth |
| `recipe.awake-scroll.help.camera` | XOR Face/Hand |
| `recipe.awake-scroll.help.permissions` | запросы только после Hands-free |

Точные предложения — при impl в xcstrings; смысл не менять. Close: `common.close` если toolbar.

## Binding ownership

`isScreenAwakeActive` остаётся у `YDocRecipeDetailView`.  
`handsFreeEnabled` — `@AppStorage("awakeHandsFreeEnabled")` или storage helper, не дублировать ключ строкой в двух файлах: константа в `AwakeHandsFreeStorage.key`.
