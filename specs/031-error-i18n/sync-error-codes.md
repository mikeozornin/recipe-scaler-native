# Контракт: коды ошибок Socket.IO `sync_error`

**Дата**: 2026-06-20
**Версия**: 1.0
**Аудитория**: backend-команда recipe-scaler-web/server; iOS-клиент
**Ревью**: Linear MIK-129 (review finding #46)
**Связанный REST-контракт**: [server-error-keys.md](server-error-keys.md)

## Соглашение

Серверное Socket.IO-событие `sync_error` **должно** содержать поле `code: string` с dot-key из таблицы ниже, наряду с существующим полем `error: String`. iOS-клиент классифицирует ошибку через `SyncErrorCode.from(code:legacyMessage:fallback:)` — `code` имеет приоритет, `error` остаётся для back-compat и логов.

```json
{
  "code": "sync.error.ownership",
  "error": "Ownership validation failed",
  "recipeId": "optional-string"
}
```

## Регулярное выражение dot-key

Такое же, как для REST-контракта:

```
^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*){1,}$
```

## Таблица кодов

| `code` (dot-key) | Legacy English `error` (back-compat) | Действие iOS-клиента | Локализационный ключ |
|------------------|---------------------------------------|----------------------|----------------------|
| `sync.error.ownership` | `"Ownership validation failed"` | `setConnectionState(.error)`, не ретраить | `sync.error.ownership` |
| `sync.error.recipe-deleted` | `"Recipe is deleted"` | Удалить рецепт из локального списка, очистить offline-очередь, закрыть UI | `sync.error.recipe-deleted` |
| `sync.error.empty-update` | `"Empty"` | Запросить полную перезагрузку документа | `sync.error.empty-update` |
| `sync.error.invalid-update` | `"Invalid update"` | Запросить полную перезагрузку документа | `sync.error.invalid-update` |
| `sync.error.generic` | (любая другая строка) | Sleep 5s, затем перезагрузка документа | `sync.error.generic` |

## Совместимость

iOS-клиент принимает оба формата:

1. **Новый (рекомендуется)**: payload содержит `code` dot-key — используется напрямую, `error` игнорируется для классификации (но пишется в логи).
2. **Старый**: payload без `code` — клиент матчингит поле `error` по подстроке (legacy English-паттерны выше), классифицирует в соответствующий enum case. Если ничего не совпало — `.generic`.

После миграции сервера на `code` можно удалить substring-matching (станет no-op).

## Client API

iOS-сторона (post-MIK-129):

```swift
// RecipeScalerNative/Services/YjsSync/SyncErrorCode.swift
public enum SyncErrorCode: String, Sendable, Equatable, CaseIterable {
    case ownershipFailed = "sync.error.ownership"
    case recipeDeleted   = "sync.error.recipe-deleted"
    case emptyUpdate     = "sync.error.empty-update"
    case invalidUpdate   = "sync.error.invalid-update"
    case generic         = "sync.error.generic"
}

let code = SyncErrorCode.from(
    code: payload["code"] as? String,         // будущий dot-key
    legacyMessage: payload["error"] as? String // сегодняшний English
)
// code.localizedMessage → user-facing string via Bundle.currentLocalizedString
```

`YjsSyncService.handleSyncError(code:message:recipeId:)` роутит через `switch code` — поведение каждого кейса зафиксировано в таблице.

## Локализация

iOS-каталог `RecipeScalerNative/Resources/Localizable.xcstrings` содержит переводы en + ru для всех 5 ключей выше. Бэкенду **не нужно** локализовать `error` — клиент резолвит по `code`.

## Связанные задачи

- **MIK-129** (native): ввести тип `SyncErrorCode`, свернуть `contains`-блоки, покрыть тестами.
- **Backend task** (recipe-scaler-web/server): добавить `code: string` в payload `sync_error`-события.
