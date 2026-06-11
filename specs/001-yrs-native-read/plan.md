# Implementation Plan: Интеграция yrs и нативное чтение

**Branch**: `001-yrs-native-read` | **Date**: 2026-06-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-yrs-native-read/spec.md`

## Summary

Фаза 2 — фундаментальная миграция с REST API на CRDT-конвейер через yrs (Rust). Приложение переходит от REST+WebSocket-уведомлений к нативному чтению данных рецептов из Y.Doc. Ключевые компоненты: сборка yrs XCFramework, Swift-обёртка над yffi C API, YjsSyncService для Socket.IO синхронизации, SQLite-хранение снимков Y.Doc, реактивное обновление SwiftUI. REST API остаётся только для изображений и авторизации.

## Technical Context

**Language/Version**: Swift 5.9+ (iOS 17+), Rust (stable, для yrs XCFramework)

**Primary Dependencies**:
- yrs (y-crdt) — CRDT-движок через C FFI (yffi), компилируется как XCFramework
- socket.io-client-swift 16.1.0+ — уже подключён (SPM)
- KeychainAccess 4.2.2+ — уже подключён (SPM)
- GRDB (добавляется) — SQLite-хранение снимков Y.Doc

**Storage**: SQLite через GRDB — снимки Y.Doc state (бинарные данные + lastSyncedAt), локальная очередь операций (Phase 5). SwiftData остаётся для UI-кеширования (Recipe, Ingredient модели).

**Testing**: XCTest — модульные тесты для yrs-обёртки, YjsSyncService, парсинга Y.Doc; контрактные тесты для Socket.IO событий.

**Target Platform**: iOS 17.0+, Xcode 16.0+, arm64 (device), arm64 + x86_64 (simulator)

**Project Type**: mobile-app (native iOS)

**Performance Goals**: список рецептов < 2 сек при запуске (из SQLite), обновления реального времени < 3 сек, переподключение < 5 сек

**Constraints**: офлайн-first, бинарная совместимость с Yjs 13.6.30, без изменений бэкенда, минимальное потребление памяти (Y.Doc instances)

**Scale/Scope**: один пользователь, до 200 рецептов в коллекции, до 50 ингредиентов в рецепте

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Reference: [.specify/memory/constitution.md](../../.specify/memory/constitution.md)

| Gate | Status | Notes |
|------|--------|-------|
| CRDT-first | ✅ PASS | Все данные рецептов читаются из Y.Doc через yrs. SwiftData остаётся только как UI-кеш (derived data) — не авторитетный источник. REST только для изображений и авторизации. |
| Web parity | ✅ PASS | Ключи документов, структура Y.Doc, Socket.IO события — точное соответствие docs/YJS-SCHEMA.md и docs/ARCHITECTURE.md. Бэкенд не изменяется. |
| Offline-first | ✅ PASS | SQLite-снимки загружаются мгновенно при запуске. В этой фазе нет мутаций — очередь офлайн-операций будет добавлена в Phase 3 (native editing). Для read-only достаточно локальных снимков. |
| Native UI | ✅ PASS | Все views — SwiftUI. WKWebView не используется (описание в v3 не рендерится в этой фазе, v1/v2 — plain text). |
| Phased delivery | ✅ PASS | Scope точно соответствует Phase 2 из PROJECT_STATUS.md: yrs интеграция + нативное чтение. Редактирование (Phase 3), WebView (Phase 4), shopping list (Phase 5) исключены. |
| i18n | ✅ PASS | Все новые пользовательские строки (ошибки синхронизации, индикатор офлайна) — через i18n ресурс файлы. |
| Docs | ✅ PASS | docs/SETUP.md обновляется при добавлении yrs XCFramework. AGENTS.md обновляется ссылкой на план. |

No violations. No entries in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/001-yrs-native-read/
├── plan.md              # This file
├── spec.md              # Feature specification (Russian)
├── research.md          # Phase 0: technical research
├── data-model.md        # Phase 1: data model & entities
├── quickstart.md        # Phase 1: developer quickstart guide
├── contracts/           # Phase 1: interface contracts
│   ├── yffi-api.md      # yrs C API surface needed
│   └── sync-protocol.md # Socket.IO sync protocol contract
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (repository root)

```text
RecipeScalerNative/
├── RecipeScalerNativeApp.swift        # App entry (update: init sync service)
├── ContentView.swift                  # Root view (unchanged)
├── Config.swift                       # Server config (unchanged)
├── Models/
│   ├── Recipe.swift                   # SwiftData model (keep for UI cache)
│   ├── Ingredient.swift              # SwiftData model (keep for UI cache)
│   ├── RecipeTimer.swift             # Unchanged
│   ├── ApiCacheEntry.swift           # Keep for REST image caching
│   └── YDoc/                         # NEW — Y.Doc data models
│       ├── CollectionEntry.swift     # Recipe metadata from collection Y.Doc
│       ├── RecipeData.swift          # Full recipe from recipe Y.Doc
│       ├── IngredientData.swift      # Ingredient from Y.Array/Y.Map
│       └── NutritionData.swift       # Nutrition from Y.Map/JSON
├── Services/
│   ├── APIClient.swift               # Keep (images, auth)
│   ├── WebSocketService.swift        # REPLACE → YjsSyncService
│   ├── YjsSync/                      # NEW — Sync subsystem
│   │   ├── YjsSyncService.swift      # Central sync orchestrator
│   │   ├── DocumentManager.swift     # Y.Doc lifecycle management
│   │   ├── SyncEventHandler.swift    # Socket.IO event processing
│   │   └── ConnectionState.swift     # Offline/online state machine
│   ├── Yrs/                          # NEW — yrs C FFI wrapper
│   │   ├── YrsDocument.swift         # Y.Doc wrapper (lifecycle, transactions)
│   │   ├── YrsMap.swift              # Y.Map read operations
│   │   ├── YrsArray.swift            # Y.Array read operations
│   │   ├── YrsText.swift             # Y.Text read operations
│   │   ├── YrsValue.swift            # YOutput → Swift type bridging
│   │   └── YrsError.swift            # Error types
│   ├── Storage/                      # NEW — SQLite persistence
│   │   ├── YDocStore.swift           # Y.Doc snapshot CRUD via GRDB
│   │   └── Database.swift            # GRDB database setup & migrations
│   ├── AuthService.swift             # Unchanged (seed auth)
│   ├── TimerManager.swift            # Unchanged
│   └── ImageCacheService.swift       # Unchanged
├── Views/
│   ├── RecipeListView.swift          # Update: data source → Y.Doc
│   ├── RecipeDetailView.swift        # Update: data source → Y.Doc
│   └── ... (other views unchanged)
├── ViewModels/
│   └── RecipeListViewModel.swift     # REWRITE: Y.Doc data source
├── Resources/
│   ├── Localizable.xcstrings         # Update: add sync error strings
│   └── ... (fonts, assets unchanged)
└── Bridging/                         # NEW — C bridging
    └── libyrs.h                      # Copy from y-crdt/tests-ffi/include

Frameworks/
└── YrsXCFramework.xcframework/       # NEW — compiled from y-crdt/yffi

scripts/
├── build-yrs-xcframework.sh          # NEW — build yrs for iOS
├── copy-dev-icons.sh                  # Existing
└── copy-production-icons.sh           # Existing
```

**Structure Decision**: Используется существующая структура iOS-приложения. Новые компоненты добавляются в подпапки: `Yrs/` для обёртки над C API, `YjsSync/` для сервиса синхронизации, `Storage/` для GRDB, `YDoc/` для моделей данных из Y.Doc. WebSocketService заменяется на YjsSyncService.

## Complexity Tracking

> No violations. Table intentionally empty.
