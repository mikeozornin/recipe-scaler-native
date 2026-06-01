# Quickstart: Интеграция yrs и нативное чтение

**Date**: 2026-06-01
**Phase**: Phase 1 — Developer Guide

## Prerequisites

- macOS с Apple Silicon (M1+) или Intel
- Xcode 16.0+
- Rust toolchain: `rustup install stable`
- iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`
- Backend Recipe Scaler запущен и доступен (см. `Config.swift`)
- Учётная запись пользователя, созданная через веб-клиент

## Step 1: Build yrs XCFramework

```bash
# Clone y-crdt (если ещё нет)
git clone https://github.com/y-crdt/y-crdt.git /tmp/y-crdt
cd /tmp/y-crdt

# Build для всех iOS таргетов
./scripts/build-xcframework.sh ios
# или вручную:
cargo build -p yffi --release --target aarch64-apple-ios
cargo build -p yffi --release --target aarch64-apple-ios-sim
cargo build -p yffi --release --target x86_64-apple-ios

# Создать XCFramework
mkdir -p /tmp/yrs-framework
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libyrs.a \
  -headers tests-ffi/include/ \
  -library .../simulator/libyrs.a \
  -headers tests-ffi/include/ \
  -output /tmp/yrs-framework/YrsXCFramework.xcframework
```

Скопировать в проект:
```bash
mkdir -p Frameworks
cp -R /tmp/yrs-framework/YrsXCFramework.xcframework Frameworks/
```

## Step 2: Add XCFramework to Xcode Project

1. Откройте `RecipeScalerNative.xcodeproj` в Xcode
2. Перетащите `Frameworks/YrsXCFramework.xcframework` в навигатор проекта
3. В настройках target → "General" → "Frameworks, Libraries, and Embedded Content":
   - Установите "Embed & Sign" для `YrsXCFramework.xcframework`
4. Убедитесь, что `module.modulemap` включён в XCFramework и Swift видит `import YrsC`

## Step 3: Add GRDB SPM Dependency

1. Xcode → File → Add Package Dependencies
2. URL: `https://github.com/groue/GRDB.swift`
3. Version: `7.0.0+` (последняя стабильная)
4. Add to target `RecipeScalerNative`

## Step 4: Verify Build

```bash
# Build project
xcodebuild build \
  -project RecipeScalerNative.xcodeproj \
  -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Или через Xcode: Cmd+B
```

## Step 5: Project Module Map (if needed)

Если XCFramework не содержит modulemap, создайте `Frameworks/module.modulemap`:

```
module YrsC {
    header "libyrs.h"
    export *
}
```

Убедитесь, что `libyrs.h` доступен в XCFramework's headers directory.

## Development Workflow

### Running the App

1. Откройте `RecipeScalerNative.xcodeproj`
2. Выберите target simulator или device
3. Cmd+R для запуска
4. Авторизуйтесь с seed-фразой (созданной через веб-клиент)

### Running Tests

```bash
xcodebuild test \
  -project RecipeScalerNative.xcodeproj \
  -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Key Files to Modify

| Component | Files | Description |
|-----------|-------|-------------|
| yrs wrapper | `RecipeScalerNative/Services/Yrs/*.swift` | New — C FFI wrapper |
| Sync service | `RecipeScalerNative/Services/YjsSync/*.swift` | New — replaces WebSocketService |
| Storage | `RecipeScalerNative/Services/Storage/*.swift` | New — GRDB SQLite |
| Y.Doc models | `RecipeScalerNative/Models/YDoc/*.swift` | New — domain models |
| Recipe list VM | `RecipeScalerNative/ViewModels/RecipeListViewModel.swift` | Rewrite — Y.Doc data source |
| Recipe list view | `RecipeScalerNative/Views/RecipeListView.swift` | Update — use Y.Doc data |
| Recipe detail view | `RecipeScalerNative/Views/RecipeDetailView.swift` | Update — use Y.Doc data |
| App entry | `RecipeScalerNative/RecipeScalerNativeApp.swift` | Update — init YjsSyncService |

### Data Flow for Development

```
yrs XCFramework (Rust)
  ↓ C FFI
YrsDocument / YrsMap / YrsArray (Swift wrapper)
  ↓ parsed values
CollectionEntry / RecipeData / IngredientData (domain models)
  ↓ observer callbacks
RecipeListViewModel (@Published)
  ↓ @Published
SwiftUI Views
```

## Troubleshooting

### "No such module 'YrsC'"
- Убедитесь, что XCFramework добавлен с "Embed & Sign"
- Проверьте, что `module.modulemap` существует и корректен
- Clean build folder (Cmd+Shift+K) и rebuild

### yrs crash on `ytransaction_apply`
- Проверьте, что binary data не повреждена
- Убедитесь, что `yjsState` array содержит корректные UInt8 значения (0-255)
- Проверьте, что Y.Doc не был изменён из другого потока (yrs — single-threaded per doc)

### GRDB migration error
- Удалите приложение с симулятора/устройства (сбросит базу)
- Пересоберите и запустите

### Socket.IO не подключается
- Проверьте URL сервера в `Config.swift`
- Убедитесь, что backend запущен
- Проверьте, что userId корректен (после seed auth)
