# Recipe Scaler Native iOS

Нативное iOS приложение для Recipe Scaler (read-only MVP).

## Требования

- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

## Архитектура

### Модели данных
- **Recipe** - рецепт с ингредиентами
- **Ingredient** - ингредиент с масштабированием
- **RecipeTimer** - таймер для готовки

### Сервисы
- **APIClient** - REST API клиент для получения данных
- **WebSocketService** - Socket.io для real-time уведомлений

### Синхронизация (MVP)

**Подход:** REST API + WebSocket уведомления (БЕЗ изменений бэкенда)

1. **REST API**: `GET /api/recipes-v1/` для загрузки рецептов в JSON
2. **WebSocket**: События `sync_confirmed`, `document_loaded` как уведомления
3. **При событии**: делать GET запрос к REST API для обновления

```
┌─────────────┐
│  iOS App    │
└──────┬──────┘
       │
       ├─► REST API (/api/recipes-v1/)
       │   └─► Загрузка рецептов (JSON)
       │
       └─► WebSocket (Socket.io)
           ├─► Подписка на события
           └─► При событии → GET запрос
```

**Важно:** WebSocket НЕ передаёт Yjs бинарные данные, только уведомления!

## Зависимости (SPM)

```swift
// Обязательные
- SwiftData (встроено в iOS 17+)
- socket.io-client-swift - WebSocket для real-time
- KeychainAccess - хранение seed phrase
- BIP39 - генерация seed phrase

// Будущее (v2+)
- y-crdt/yswift - для редактирования
```

## Функции MVP

### ✅ Включено
- Просмотр списка рецептов
- Детальный просмотр рецепта
- Масштабирование ингредиентов
- Таймеры готовки
- Поиск рецептов
- Локализация (ru/en)
- Offline кэширование (SwiftData)
- Seed-based авторизация
- QR для авторизации
- WebSocket обновления

### ❌ Не включено (требует yswift)
- Создание рецептов
- Редактирование рецептов
- Rich-text редактор
- Real-time collaboration

Внутри приложения используется логотип из `AppLogo.imageset`. Иконка на домашнем экране — из `AppIcon.appiconset` (одна и та же для Debug и Release).

## Проект Xcode

Проект поддерживается вручную (без XcodeGen). Все изменения в структуре, таргетах и зависимостях вносятся в `RecipeScalerNative.xcodeproj` через Xcode.

## Настройка

1. Открыть `RecipeScalerNative.xcodeproj` в Xcode
2. Настроить `baseURL` в `APIClient.swift`
3. Build & Run (для dev-иконки собирайте в конфигурации Debug)

## Тестирование

### Unit + Snapshot
```bash
xcodebuild test -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 15'
```

### UI Tests
```bash
xcodebuild test -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:RecipeScalerNativeUITests
```

### Примечания
- Snapshot-тесты используют `SnapshotTesting` и сохраняют эталонные изображения рядом с тестами.
- Для UI тестов используется `accessibilityIdentifier` на ключевых элементах экрана авторизации.

## Структура проекта

```
RecipeScalerNative/
├── Models/
│   ├── Recipe.swift
│   ├── Ingredient.swift
│   └── RecipeTimer.swift
├── Views/
│   ├── RecipeListView.swift
│   ├── RecipeDetailView.swift
│   └── ContentView.swift
├── ViewModels/
│   └── RecipeListViewModel.swift
├── Services/
│   ├── APIClient.swift
│   └── WebSocketService.swift (TODO)
└── Resources/
    └── Localizations/ (TODO)
```

## TODO

- [ ] WebSocket сервис для уведомлений
- [ ] Seed-based авторизация
- [ ] QR сканер/генератор
- [ ] Таймеры с уведомлениями
- [ ] Локализация (ru/en)
- [ ] HTML → AttributedString конвертация
- [ ] Синхронизация SwiftData с API

## API Endpoints

### Используемые в MVP
- `GET /api/recipes-v1/` - список рецептов
- `GET /api/recipes-v1/:id` - детали рецепта
- `GET /api/recipes-v1/search?query=...` - поиск

### WebSocket события (слушаем)
- `sync_confirmed` - рецепт синхронизирован
- `document_loaded` - документ загружен
- `collection_updated` - коллекция обновлена

## License

Совместимо с лицензией основного проекта Recipe Scaler.
