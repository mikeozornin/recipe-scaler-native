# Setup Guide - RecipeScalerNative

## Prerequisites

- macOS with Xcode 15+
- iOS 17+ device or simulator
- Recipe Scaler backend running

## Quick Start

### 1. Create Xcode Project

Open Xcode and create a new iOS App project:

1. File → New → Project
2. Choose "iOS" → "App"
3. Product Name: `RecipeScalerNative`
4. Interface: `SwiftUI`
5. Language: `Swift`
6. Storage: None (we'll add SwiftData manually)
7. Save to: `RecipeScalerNative` folder (this directory)

### 2. Add Files to Project

Drag these folders into Xcode project navigator:
- `Models/`
- `Views/`
- `ViewModels/`
- `Services/`
- `Resources/`

### 3. Add SPM Dependencies

File → Add Package Dependencies:

```
https://github.com/socketio/socket.io-client-swift
https://github.com/kishikawakatsumi/KeychainAccess
https://github.com/anquii/BIP39
```

### 4. Configure Info.plist

Add these keys:

```xml
<key>NSUserNotificationsUsageDescription</key>
<string>We need notifications to alert you when timers complete</string>

<key>NSCameraUsageDescription</key>
<string>Camera access is needed to scan QR codes</string>

<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
</array>
```

### 5. Configure Capabilities

Project Settings → Signing & Capabilities:

1. Enable "Push Notifications"
2. Enable "Background Modes" → check "Background fetch"

### 6. Update Configuration

Edit `Services/APIClient.swift`:

```swift
private init() {
    // Change to your backend URL
    self.baseURL = "https://your-server.com"
}
```

### 7. Build & Run

Cmd+R to build and run on simulator or device.

## Architecture

### Data Flow

```
UI (SwiftUI)
  ↓
ViewModels (@Published)
  ↓
Services (APIClient, WebSocket)
  ↓
SwiftData (Cache) ← REST API → Backend
```

### Sync Strategy

**WebSocket notifications** → **REST API for data**

1. WebSocket listens for events: `sync_confirmed`, `document_loaded`
2. On event → GET `/api/recipes-v1/` for fresh data
3. Update SwiftData cache
4. SwiftUI auto-updates via @Query

No backend changes needed!

## Project Structure

```
RecipeScalerNative/
├── RecipeScalerNativeApp.swift    # Entry point
├── ContentView.swift               # Root view
├── Models/
│   ├── Recipe.swift                # SwiftData model
│   ├── Ingredient.swift
│   └── RecipeTimer.swift
├── Views/
│   ├── RecipeListView.swift       # Main list
│   └── RecipeDetailView.swift     # Recipe details
├── ViewModels/
│   └── RecipeListViewModel.swift
├── Services/
│   ├── APIClient.swift            # REST API
│   ├── WebSocketService.swift    # Socket.io
│   ├── AuthService.swift          # Seed auth
│   └── TimerManager.swift         # Timer logic
└── Resources/
    ├── en.lproj/                  # English
    └── ru.lproj/                  # Russian
```

## Troubleshooting

### Build Errors

**"Cannot find 'SocketIO' in scope"**
- File → Add Package Dependencies → socket.io-client-swift

**"Cannot find 'KeychainAccess' in scope"**
- Add KeychainAccess package

**SwiftData errors**
- Ensure iOS deployment target is 17.0+

### Runtime Issues

**Empty recipes list**
- Check `baseURL` in APIClient.swift
- Verify backend is running
- Check network permissions

**WebSocket not connecting**
- Verify Socket.io server URL
- Check userId is set in AuthService

## Next Steps

1. Test with real backend
2. Implement QR scanner (Phase 4)
3. Add push notifications (Phase 5)
4. Implement PDF export (Phase 6)

## Documentation

- [README.md](README.md) - Project overview
- [Plan](../.claude/plans/keen-yawning-tide.md) - Full implementation plan
