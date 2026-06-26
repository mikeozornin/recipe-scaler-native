# Контракт: WatchConnectivity Credentials Bridge

Payload и lifecycle для передачи `userId` с iPhone на paired Apple Watch через WatchConnectivity.

## Канал

`WCSession.transferUserInfo(_:)` — queued, гарантированная доставка при следующем erreichаемом состоянии.

- **Преимущества**: не требует активного соединения; доставляется даже если watch был offline.
- **Недостатки**: queued (не мгновенно); может накапливаться при множественных publish.

## Payload contract

```swift
// iPhone → Watch
[
    "userId": <String?>  // String для login, NSNull()/nil для purge
] as [String: Any]
```

### Примеры

```swift
// Login / registerAuto
transferUserInfo(["userId": "user-uuid-xxx"])

// Logout
transferUserInfo(["userId": NSNull()])
```

**Критично**: `NSNull()` вместо прямого `nil` — `transferUserInfo` требует `Codable`-значений, `nil` в Dictionary не сериализуется.

## Lifecycle

### iPhone side (`WatchCredentialsBridge`)

```swift
final class WatchCredentialsBridge: NSObject, WCSessionDelegate {
    static let shared = WatchCredentialsBridge()

    func activate()  // AppDelegate.didFinishLaunching
    func publish(userId: String)
    func purge()
}
```

Точки wire-up в `AuthService`:

1. **`loginWithSeed`** — после `SharedAuthStore.userId = data.user.id`:
   ```swift
   WatchCredentialsBridge.shared.publish(userId: data.user.id)
   ```

2. **`registerAuto`** — аналогично.

3. **`logout`** — после `SharedAuthStore.clear()`:
   ```swift
   WatchCredentialsBridge.shared.purge()
   ```

**Активация**: `WCSession.isSupported()` check (iPad-only builds), затем `session.activate()`.

### Watch side (`WatchCredentialsBridge`)

```swift
func session(
    _ session: WCSession,
    didReceiveUserInfo userInfo: [String: Any] = [:]
) {
    if let userId = userInfo["userId"] as? String, !userId.isEmpty {
        WatchCredentialsStore.userId = userId
        configureAPIClient(userId: userId)
        Task { await WatchTimerService.shared.refresh() }
    } else {
        // Purge (NSNull / nil / пустая строка)
        WatchCredentialsStore.clear()
        deconfigureAPIClient()
        WatchTimerService.shared.clear()
    }
}
```

## Storage

- **Watch Keychain** (НЕ shared с iPhone): `kSecClassGenericPassword`, service `com.recipescaler.watch`, account `userId`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Без `keychain-access-groups` — изолировано от iPhone keychain.

## Edge cases

| Сценарий | Поведение |
|---|---|
| Watch ещё не активирован, iPhone уже залогинился | `transferUserInfo` queued → доставится при первой активации watch. |
| Watch не pair'ен с iPhone | `WCSession.isPaired == false`, publish no-op. |
| iPhone logout, watch offline | Queued purge → дойдёт позже. Watch показывает stale таймеры до доставки. |
| Несколько publish подряд | Каждый queued отдельно; watch обрабатывает по порядку. |
| Пользователь переключился между аккаунтами | Каждый login — новый publish; watch обновится при следующем erreichаемом состоянии. |
| Watch app переустановлен | `WatchCredentialsStore` пустой → not-authorized state до первого publish. |

## Не передаём

- `seedPhrase` — часы не умеют реконструировать сессию standalone.
- `authToken` — не используется (current auth model — только `userId`).
- Любые другие креды — `x-user-id` достаточно для `/api/v1/timers/*`.

## Out of scope v1

- Reachability-based messaging (`sendMessage` requires both apps active) — не используем, `transferUserInfo` достаточно.
- File transfer — не нужен.
- Bidirectional channel watch→iPhone — не нужен (часы ходят в API напрямую).
