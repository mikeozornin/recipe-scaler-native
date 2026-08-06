# План: скриншоты App Store

**Date**: 2026-08-05 | **Spec**: [spec.md](./spec.md)

## Очерёдность

1. **Fixtures** — отфильтровать RU zip и собрать EN (нет зависимостей от съёмки).
2. **Манифест + README** — контракт локалей/тем/кадров.
3. **DEBUG launch hooks** — import zip, язык/тема, scale, awake, timer, assistant fixture, discover slug, shopping seed.
4. **Гейты** — iPhone-only (`TARGETED_DEVICE_FAMILY = 1`); Watch не в v1 store (документировано, Debug dual-sim без изменений).
5. **Capture script** — цикл locale × appearance.
6. **Validate** — размеры PNG + `xcodebuild build`.

## Downstream consumers

- [x] **SwiftUI views** — `AppShellView`, `RecipeListView`, `YDocRecipeDetailView`, `AssistantSheet`, `ContentView` читают новые DEBUG launch-args.
- [x] **Cross-process** — widget / LA / push читают те же таймеры (`TimerManager` / App Group); скрипт только запускает таймер, не меняет IPC-контракт.
- [x] **Sync** — import пишет Y.Doc через 029 на постоянных store-юзерах (`users.yaml`), не debug-shared и не register-auto на каждый прогон.
- [x] **Persisted state** — `appLanguage` / `appThemePreference` UserDefaults выставляются launch-args на время съёмки.
- [x] **Tests / verify** — `scripts/capture-app-store-screenshots.sh`; build после Swift-правок.

## Positive invariants

| Эффект | Инвариант | Где |
|--------|-----------|-----|
| `curate-store-fixtures.py` | RU zip содержит ровно 11 рецептов с `full.webp` | скрипт + assert |
| EN zip | все 11 имён, ингредиентов и шагов на EN | скрипт |
| capture | PNG 1260×2736 или 1320×2868 | `store/README.md` + validate в скрипте |
| OS locale | lock-screen дата + push relative time на языке кадра | `set_os_locale` + SpringBoard bounce |
| LA wake | после Lock — tap для `MM:SS` (AOD иначе `44m`) | `wake_lock_screen` |
| store users | `ru` / `en` / `app-store-review` seeds в `store/fixtures/users.yaml` | `store_users.py` |
