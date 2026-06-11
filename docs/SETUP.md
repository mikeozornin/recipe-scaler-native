# Setup Guide — RecipeScalerNative

## Prerequisites

- Paid Apple Developer account: optional for simulator/dev; portal checklist for production — [PAID-APPLE-DEVELOPER-REQUIRED.md](PAID-APPLE-DEVELOPER-REQUIRED.md)
- macOS with Xcode 16+
- iOS 17+ device or simulator
- Rust toolchain (for building yrs XCFramework)
- Recipe Scaler backend running
- Node.js (for building Tiptap WebView bundle, Phase 4+)

## Quick Start

### 1. Build yrs XCFramework

yrs is the CRDT engine (Rust). It compiles as an XCFramework that Swift calls via C FFI (`libyrs.h`).

```bash
# Install Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Add iOS targets
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim

# From repo root — clones y-crdt if needed, builds all slices
./scripts/build-yrs-xcframework.sh

# Or with an existing y-crdt checkout:
./scripts/build-yrs-xcframework.sh ~/repos/y-crdt ./Frameworks
```

Output: `Frameworks/YrsXCFramework.xcframework` (device + simulator slices, `libyrs.h`, `module.modulemap`).

Bridging headers for Xcode: `RecipeScalerNative/Bridging/libyrs.h` and `module.modulemap` (module `YrsC`).

### 2. Create/Update Xcode Project

If starting fresh:

1. Open Xcode → File → New → Project → iOS App
2. Product Name: `RecipeScalerNative`
3. Interface: `SwiftUI`, Language: `Swift`
4. Save to `recipe-scaler-native/`

If project exists, open `RecipeScalerNative.xcodeproj`.

### 3. Add XCFramework

1. Drag `Frameworks/YrsXCFramework.xcframework` into the Xcode project (or verify it is already linked)
2. Target → General → Frameworks → verify it's listed
3. Ensure "Embed & Sign" is selected

### 4. Add SPM Dependencies

File → Add Package Dependencies:

```
https://github.com/socketio/socket.io-client-swift    # 16.1.0+
https://github.com/kishikawakatsumi/KeychainAccess     # 4.2.2+
https://github.com/anquii/BIP39                        # 1.0.0+
```

SQLite for Y.Doc snapshots (required for Phase 2):
```
https://github.com/groue/GRDB.swift                    # from 7.0.0 — YDocStore / YrsDatabase
```

SwiftData remains for UI-side `Recipe` / `Ingredient` cache models.

### 5. Configure Info.plist

```xml
<key>NSUserNotificationsUsageDescription</key>
<string>Timer notifications</string>

<key>NSCameraUsageDescription</key>
<string>QR code scanning</string>

<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
</array>
```

### 6. Configure Server URL

Edit `Services/APIClient.swift` or `Config.swift`:

```swift
static let baseURL = "https://your-server.com"
```

### 7. Build & Run

```bash
# From Xcode
Cmd+R

# Or command line
xcodebuild build -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Phase 4: Tiptap WebView Bundle

When reaching Phase 4 (description editing), build the Tiptap bundle:

```bash
cd recipe-scaler-native/TiptapEditor

npm install
npm run build    # Outputs tiptap-editor.bundle.js
```

Add `tiptap-editor.bundle.js` and `tiptap-editor.html` to Xcode project resources.

The bundle includes:
- yjs
- @tiptap/core + StarterKit, Highlight, Link
- Custom extensions: TimerNode, IngredientNode, HeadingWithHash
- @tiptap/extension-collaboration
- Bridge module for Swift ↔ WebView communication

## Project Structure (Target)

```
RecipeScalerNative/
├── RecipeScalerNativeApp.swift
├── ContentView.swift
├── Config.swift
│
├── Models/
│   ├── Recipe.swift
│   ├── Ingredient.swift
│   └── RecipeTimer.swift
│
├── Services/
│   ├── APIClient.swift              # REST (auth, images)
│   ├── YjsSync/                     # YjsSyncService, DocumentManager, SyncEventHandler
│   ├── Yrs/                         # Swift wrapper over yrs C API (YrsDocument, YrsMap, …)
│   ├── Storage/                     # GRDB Y.Doc snapshots (YDocStore, YrsDatabase)
│   ├── AuthService.swift            # Seed auth
│   ├── TimerManager.swift           # Timers
│   └── ImageCacheService.swift      # Image caching
│
├── Views/
│   ├── RecipeListView.swift
│   ├── RecipeDetailView.swift
│   ├── RecipeEditView.swift
│   ├── DescriptionEditorView.swift  # WKWebView wrapper
│   ├── ShoppingListView.swift
│   └── TimerExampleView.swift
│
├── ViewModels/
│   ├── RecipeListViewModel.swift
│   └── RecipeEditViewModel.swift
│
├── Resources/
│   ├── TiptapEditor/                # WebView bundle (Phase 4)
│   │   ├── tiptap-editor.html
│   │   └── tiptap-editor.bundle.js
│   ├── Localizable.xcstrings
│   └── Assets.xcassets
│
├── Frameworks/
│   └── YrsXCFramework.xcframework   # yrs Rust library (prebuilt via scripts/build-yrs-xcframework.sh)
│
└── docs/
    ├── ARCHITECTURE.md
    ├── YJS-SCHEMA.md
    └── ADD_SPM_PACKAGES.md
```

## Troubleshooting

### Rust build errors

**"rustup target not found"**
```bash
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim
```

**"library not found for -lyrs"**
- Verify XCFramework is in Target → General → Frameworks
- Clean build folder (Cmd+Shift+K) and rebuild

### Socket.IO errors

**"Cannot find 'SocketIO' in scope"**
- File → Add Package Dependencies → socket.io-client-swift

**WebSocket not connecting**
- Verify server URL in Config.swift
- Check userId is set via AuthService
- Ensure backend Socket.IO is running

### SwiftData errors

**"Cannot find type 'Schema' in scope"**
- Ensure iOS deployment target is 17.0+

## Testing

```bash
# Build (simulator)
xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Unit tests (if test target is in scheme)
xcodebuild test -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# UI tests
xcodebuild test -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:RecipeScalerNativeUITests
```

### Phase 3 — native editing (manual)

Requires backend + web client. Full matrix: [`specs/002-native-editing/quickstart.md`](../specs/002-native-editing/quickstart.md).

1. Sign in on iOS (seed phrase) and open a **v3** recipe → **Edit** → change name/servings → verify on web within ~5 s.
2. Open **v1/v2** recipe → legacy banner, no **Edit** button; scale slider still works locally.
3. Airplane mode → edit field → reconnect → change appears on web within ~10 s.
