# Контракт: WatchConnectivity Credentials Bridge

Payload и lifecycle для передачи `userId` и `device_token` с iPhone на paired Apple Watch через WatchConnectivity.

Спеки: **039** (watch timers), **041** (device tokens).

## Канал

`WCSession.transferUserInfo(_:)` — queued, гарантированная доставка при следующем erreichаемом состоянии.

Дополнительно iPhone пишет тот же payload в `updateApplicationContext` — watch читает `receivedApplicationContext` при активации (cold start).

- **Преимущества**: не требует активного соединения; доставляется даже если watch был offline.
- **Недостатки**: queued (не мгновенно); может накапливаться при множественных publish.

## Payload contract

### Version 1 (legacy, pre-041)

```swift
["userId": <String>, "version": 1]  // или без version
```

Watch: только `userId` → API через `x-user-id` (grace period).

### Version 2 (spec 041, current)

```swift
// iPhone → Watch — login / register / session restore / republish
[
    "userId": <String>,
    "token": <String>,      // device_token (Bearer), опционально при transitional backend
    "version": 2
] as [String: Any]

// iPhone → Watch — logout / purge
[
    "userId": NSNull(),
    "token": NSNull(),
    "version": 2
] as [String: Any]

// iPhone → Watch — timers changed (может сопровождаться creds)
[
    "timersChangedAt": <Int64 ms epoch>,
    "userId": <String>?,
    "token": <String>?,
    "version": 2
]
```

### Примеры

```swift
// Login / registerAuto / restore
transferUserInfo([
    "userId": "user-uuid-xxx",
    "token": "base64url-device-token",
    "version": 2,
])

// Logout
transferUserInfo([
    "userId": NSNull(),
    "token": NSNull(),
    "version": 2,
])
```

**Критично**: `NSNull()` вместо прямого `nil` — `transferUserInfo` требует `Codable`-значений, `nil` в Dictionary не сериализуется.

## Lifecycle

### iPhone side (`WatchCredentialsBridge`)

```swift
final class WatchCredentialsBridge: NSObject, WCSessionDelegate {
    static let shared = WatchCredentialsBridge()

    func activate()  // AppDelegate / AppContainer bootstrap
    func publish(userId: String, token: String?)
    func publish(userId: String)  // reads SharedAuthStore.token
    func purge()
    func publishTimersChanged()
}
```

Точки wire-up в `AuthService`:

1. **`applySession`** (login / register / migration) — после записи в `SharedAuthStore`:
   ```swift
   WatchCredentialsBridge.shared.publish(userId: userId, token: SharedAuthStore.token)
   ```

2. **`logout`** — после `SharedAuthStore.clear()`:
   ```swift
   WatchCredentialsBridge.shared.purge()
   ```

3. **WCSession activation / paired / reachability** — `republishStoredCredentialsIfReady` при наличии `SharedAuthStore.userId`.

**Активация**: `WCSession.isSupported()` check (iPad-only builds), затем `session.activate()`.

### Watch side (`WatchCredentialsBridge`)

```swift
func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    applyPayload(userInfo)
}

private func applyPayload(_ payload: [String: Any]) {
    if payload.keys.contains("userId") {
        let userId = optionalString(from: payload, key: "userId")
        let token = optionalString(from: payload, key: "token")
        if let userId, !userId.isEmpty {
            WatchCredentialsStore.set(userId, token: token)
            configureAPIClient(userId: userId, token: token)  // Bearer if token present
        } else {
            WatchCredentialsStore.clear()
            deconfigureAPIClient()
        }
        onUserIdChange?(userId)
    }
    if payload["timersChangedAt"] != nil {
        onTimersChanged?()
    }
}
```

Forward-compat: payload **без** ключа `token` (v1) → watch сохраняет только `userId`, API на `x-user-id` до следующего publish с token.

## Storage

| Credential | iPhone | Watch |
|------------|--------|-------|
| `userId` | `SharedAuthStore` (Keychain, App Group) | Keychain `com.recipescaler.watch` / account `userId` |
| `device_token` | `SharedAuthStore.token` (Keychain, **не** iCloud sync) | Keychain account `token`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false` |

- Watch Keychain **не** shared с iPhone (нет общего keychain access group для token) — token приходит только через WC.
- **Seed phrase не передаётся** на watch (watch не умеет standalone re-login по seed).

## Edge cases

| Сценарий | Поведение |
|---|---|
| Watch ещё не активирован, iPhone уже залогинился | `transferUserInfo` + `applicationContext` queued → доставится при первой активации watch. |
| Watch не pair'ен с iPhone | `WCSession.isPaired == false`, publish no-op. |
| iPhone logout, watch offline | Queued purge → дойдёт позже. Watch показывает stale таймеры до доставки. |
| Несколько publish подряд | Каждый queued отдельно; watch обрабатывает по порядку. |
| Пользователь переключился между аккаунтами | Каждый login — новый publish; watch обновится при следующем erreichаемом состоянии. |
| Watch app переустановлен | `WatchCredentialsStore` пустой → not-authorized state до первого publish. |
| Token пустой на transitional backend | Watch работает на `x-user-id` до следующего publish с token. |

## Auth on watch API calls

- **Preferred (041)**: `Authorization: Bearer <device_token>` + `APIClient.configure(userId:)` для endpoints, которые pin user in body.
- **Fallback (grace)**: только `x-user-id` если token отсутствует в payload / Keychain.

## Out of scope v1

- Reachability-based messaging (`sendMessage` requires both apps active) — не используем, `transferUserInfo` достаточно.
- File transfer — не нужен.
- Bidirectional channel watch→iPhone — не нужен (часы ходят в API напрямую).
- Per-watch отдельный device_token — один token на пару iPhone↔watch (см. spec 041 non-goals).