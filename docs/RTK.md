# RTK - Rust Token Killer (Codex CLI)

**Usage**: Token-optimized CLI proxy for shell commands.

## Rule

Always prefix shell commands with `rtk`.

Examples:

```bash
rtk git status
rtk git diff
rtk find . -name "*.swift"
rtk grep "DocumentManager" RecipeScalerNative/
rtk read RecipeScalerNative/Config.swift

# Xcode — user-global filter in ~/Library/Application Support/rtk/filters.toml
# Do not pipe to `rtk grep` (ignores stdin); use `rtk xcodebuild` alone or `rtk pipe -f grep`.
rtk xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,id=<UDID>' build

# XCTest — RTK-фильтр для xcodebuild test ненадёжен (ложные fail, обрезанный вывод).
# Для test / test-without-building — без rtk или через rtk proxy (см. раздел ниже).
```

## Xcode: build vs test

| Задача | Команда | Почему |
|--------|---------|--------|
| **build**, **build-for-testing** | `rtk xcodebuild …` | Компактные ошибки, exit code корректен |
| **test**, **test-without-building** | `xcodebuild …` или `rtk proxy xcodebuild …` | Фильтр RTK может скрыть падения или дать ложный результат |

**Destination:** предпочитай `id=<UDID>` из `xcrun simctl list devices available`. Если по имени — укажи OS: `name=iPhone 16,OS=18.6` (без OS симулятор часто не резолвится).

Пример тестов (без RTK):

```bash
xcodebuild build-for-testing -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'

xcodebuild test-without-building -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -only-testing:RecipeScalerNativeTests/SomeTestClass
```

Тот же прогон через RTK без фильтра (как в `scripts/verify-third-party-import.sh`):

```bash
rtk proxy xcodebuild test-without-building …
```

Альтернатива: `RTK_DISABLED=1 xcodebuild test …` (хук Cursor не перепишет команду).

## Meta Commands

```bash
rtk gain            # Token savings analytics
rtk gain --history  # Recent command savings history
rtk proxy <cmd>     # Run raw command without filtering
```

## Verification

```bash
rtk --version
rtk gain
which rtk
```
