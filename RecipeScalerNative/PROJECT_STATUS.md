# RecipeScalerNative - Project Status

## ✅ MVP Read-only - ГОТОВ К СБОРКЕ

### Создано файлов: 13 Swift + документация

## Структура проекта

```
RecipeScalerNative/
├── RecipeScalerNativeApp.swift        # App entry point с SwiftData
├── ContentView.swift                   # Root view
│
├── Models/ (3 файла)
│   ├── Recipe.swift                    # Рецепт (SwiftData @Model)
│   ├── Ingredient.swift                # Ингредиент с масштабированием
│   └── RecipeTimer.swift               # Таймер с управлением
│
├── Views/ (3 файла)
│   ├── RecipeListView.swift           # Список рецептов
│   ├── RecipeDetailView.swift         # Детальный просмотр
│   └── TimerExampleView.swift         # UI таймеров
│
├── ViewModels/ (1 файл)
│   └── RecipeListViewModel.swift      # Логика списка
│
├── Services/ (4 файла)
│   ├── APIClient.swift                # REST API клиент
│   ├── WebSocketService.swift         # Socket.io для уведомлений
│   ├── AuthService.swift              # Seed-based авторизация
│   └── TimerManager.swift             # Управление таймерами
│
└── Resources/
    ├── en.lproj/Localizable.strings   # Английский
    ├── ru.lproj/Localizable.strings   # Русский
    └── Localizable.xcstrings           # Xcode 14+ формат
```

## Реализованные фичи

### ✅ Core (MVP)
- [x] SwiftData модели (Recipe, Ingredient, RecipeTimer)
- [x] REST API клиент (GET /api/recipes-v1/)
- [x] WebSocket уведомления (Socket.io)
- [x] Список рецептов с поиском
- [x] Детальный просмотр рецепта
- [x] Масштабирование ингредиентов (slider)
- [x] Локализация (ru/en)

### ✅ Авторизация
- [x] Seed-based auth (BIP39)
- [x] Keychain для seed phrase
- [x] Auto-registration
- [x] Login with seed

### ✅ Таймеры
- [x] Создание/управление таймерами
- [x] Background execution
- [x] Локальные уведомления
- [x] SwiftData persistence

### ⏳ TODO (следующие фазы)
- [ ] QR сканер/генератор
- [ ] Push-уведомления (APNS)
- [ ] PDF экспорт
- [ ] Импорт из URL
- [ ] Widgets
- [ ] Siri Shortcuts

## Архитектура синхронизации

**БЕЗ ИЗМЕНЕНИЙ БЭКЕНДА!**

```
┌─────────────────┐
│   iOS App       │
└────────┬────────┘
         │
         ├─► REST API: GET /api/recipes-v1/
         │   └─► Загрузка данных в JSON
         │
         └─► WebSocket: Socket.io
             ├─► События: sync_confirmed, document_loaded
             └─► При событии → GET запрос к API
```

**Важно:** WebSocket НЕ передаёт Yjs state, только уведомления!

## Зависимости (SPM)

```swift
socket.io-client-swift  // WebSocket
KeychainAccess          // Secure storage
BIP39                   // Seed phrase
SwiftData (iOS 17+)     // Persistence
```

## Следующий шаг: Сборка в Xcode

### 1. Создать Xcode проект
```bash
# Открыть Xcode
# File → New → Project → iOS App
# Название: RecipeScalerNative
# Interface: SwiftUI
# Сохранить в: RecipeScalerNative/
```

### 2. Добавить файлы
Перетащить папки в Xcode:
- `Models/`
- `Views/`
- `ViewModels/`
- `Services/`
- `Resources/`

### 3. Добавить зависимости SPM
```
https://github.com/socketio/socket.io-client-swift
https://github.com/kishikawakatsumi/KeychainAccess
https://github.com/anquii/BIP39
```

### 4. Настроить Info.plist
```xml
<key>NSUserNotificationsUsageDescription</key>
<string>Timer notifications</string>

<key>NSCameraUsageDescription</key>
<string>QR code scanning</string>
```

### 5. Настроить baseURL
Изменить в `APIClient.swift`:
```swift
self.baseURL = "https://your-server.com"
```

### 6. Build & Run! 🚀

## Документация

- [README.md](README.md) - Обзор проекта
- [SETUP.md](SETUP.md) - Подробная инструкция
- [План](../.claude/plans/keen-yawning-tide.md) - Полный план

## Статистика

- **Swift файлов:** 13
- **Строк кода:** ~2500+
- **Модели:** 3
- **Views:** 3
- **Сервисы:** 4
- **Языки:** 2 (ru/en)

## MVP Scope

| Фича | Статус |
|------|--------|
| Просмотр рецептов | ✅ |
| Масштабирование | ✅ |
| Таймеры | ✅ |
| Поиск | ✅ |
| Авторизация | ✅ |
| WebSocket sync | ✅ |
| Offline cache | ✅ |
| i18n | ✅ |
| **Редактирование** | ❌ v2+ |
| **QR коды** | ⏳ Phase 4 |
| **Push** | ⏳ Phase 5 |

---

**Проект готов к сборке в Xcode!** 🎉
