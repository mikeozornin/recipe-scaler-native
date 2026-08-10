# Quickstart: 062 Mac/iPad layout

## Prerequisites

- Xcode 16+
- iOS 17+ Simulator (iPhone 16 + iPad Pro 13")
- macOS 14+ (для Фазы B)

## Эталон web (ручная сверка)

```bash
# Dev (из recipe-scaler-web/recipe-scaler)
npm install && npm run dev
# Открыть http://localhost:5173/#/
# В DevTools → Application → localStorage: userId = <your-id>

# Prod
open 'https://recipe-scaler.ru/#/'
# userId cfcd839f-56f2-4411-9632-7795b75f96d1 (demo account пользователя)
```

Сравнить при ширинах:

| Viewport | Web | Native (HIG) |
|----------|-----|--------------|
| 390×844 | Bottom nav | TabView bottom tabs |
| 1180×820 | Icon sidebar + split | `NavigationSplitView` 3-col + system sidebar list |
| 1440×900 | Fixed right timers | Timers in toolbar/inspector |

## Build & run

```bash
cd /Users/mike/work/git-repos/projects/recipe-scaler/recipe-scaler-native

# iPhone compact regression
xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# iPad wide
xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build

# Mac native target
xcodebuild -scheme RecipeScalerMac \
  -destination 'platform=macOS' build

# Optional DEBUG shell smoke without entering a seed phrase:
/path/to/RecipeScalerMac.app/Contents/MacOS/RecipeScalerMac \
  -DebugMacAutoLogin=1
```

## DEBUG launch args

| Arg | Effect |
|-----|--------|
| `-ForceLayout=wide` | Wide shell на iPad landscape (UI tests; на узком устройстве NavigationSplitView может свернуть sidebar) |
| `-ForceLayout=compact` | Force compact на iPad |
| `-OpenTab=recipes` | Открыть Recipes при запуске |

## Manual QA checklist (wide)

1. Login → sidebar visible, 5 items + import.
2. Recipes → list + first recipe detail side by side.
3. Resize split → width restored after relaunch.
4. Discover nested → tap Discover again → root.
5. Recipe detail open → tap Recipes → list root.
6. Active timers → desktop panel (not above content).
7. Assistant → sidebar button, no FAB.
8. Import → sheet from sidebar import item.
9. Rotate iPad to portrait → compact tabs (if width &lt; threshold).
10. Mac: ⌘1 switches to Discover.

## Interaction QA

| Check | iPad | Mac |
|-------|------|-----|
| Recipe row pin/delete | Finger swipe leading/trailing | Trackpad swipe or context menu |
| Shopping delete | No hover-only button | Delete on row hover |
| Assistant message copy | Always visible | Visible on hover |
| iPad regular + trackpad | Still finger swipeActions, not desktop strips | — |

## Layout audit

```bash
bash scripts/audit-ui-layout.sh specs/062-mac-ipad-layout
```

Требует заполненных `layout.md` + `layout-audit.json` перед merge UI PR.
