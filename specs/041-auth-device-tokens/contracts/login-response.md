# Контракт: Auth response shape

**Спека**: [../spec.md](../spec.md) (F1, F16, F17)
**Связанные AC**: AC1, AC2, AC3

## Зависимые endpoints

| Endpoint | Когда |
|---|---|
| `POST /api/auth/login-with-seed` | seed-login на любом клиенте |
| `POST /api/auth/register-auto` | первый запуск, авто-регистрация |
| `POST /api/auth/exchange-seed-for-token` | миграция уже залогиненного клиента |

## Принципы

1. **Plaintext `device_token` возвращается ровно один раз** в response body. Сервер хранит только `sha256(token)`.
2. **Legacy `data.user.id` сохраняется** в response на transitional period — чтобы неизменившиеся клиенты продолжили работать. Удаляется после истечения последнего активного `legacy_auth_cutoff_at` всех user'ов (F17).
3. **`success: boolean` обёртка** — как везде в API (`routes/auth.ts:424` сегодня).

## Response shapes

### `POST /api/auth/login-with-seed`

**Request body:**
```json
{
  "seed_phrase": "word1 word2 ... word12",
  "device_id": "client-side-uuid",
  "platform": "ios-native | web | pwa | ios-watch | android-native",
  "app_version": "1.2.3",
  "language": "ru | en",
  "old_user_id": "uuid (optional, для promote auto-created user)"
}
```

**Response 200 (post-PR1, transitional):**
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "data_version": "v3"
    },
    "device_token": "dGVzdC0zMi1ieXRlcy1iYXNlNjR1cmwtdG9rZW4"
  }
}
```

**Response 200 (post-cutoff, после удаления legacy shim):**
```json
{
  "success": true,
  "data": {
    "user": {
      "data_version": "v3"
    },
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "device_token": "dGVzdC0zMi1ieXRlcy1iYXNlNjR1cmwtdG9rZW4"
  }
}
```

> Примечание: `user_id` добавляется как top-level в data. Старый `data.user.id` удаляется. Мигрировавшие клиенты уже используют `data.device_token` + `data.user.data_version`.

**Response 401 (невалидный seed):**
```json
{
  "success": false,
  "error": "Invalid credentials"
}
```

**Response 429 (rate limit превышен):**
```json
{
  "success": false,
  "error": "Too many authentication attempts, please try again later."
}
```

### `POST /api/auth/register-auto`

**Request body:**
```json
{
  "device_id": "client-side-uuid",
  "platform": "...",
  "app_version": "1.2.3",
  "language": "ru"
}
```

**Response 201 (transitional):**
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "550e8400-...",
      "data_version": "v3"
    },
    "seed_phrase": "word1 word2 ... word12",
    "device_token": "dGVzdC0zMi1ieXRlcy1iYXNlNjR1cmwtdG9rZW4"
  }
}
```

> `seed_phrase` возвращается один раз — клиент **должен** предложить backup.
> `seed_hash` НЕ возвращается (внутреннее поле сервера).
> `data.seed_hash` в текущем коде (`auth.ts:489`) — удалить в той же правке (утечка internal hash).

**Response 409 (user already exists — крайне редкий коллизия seed_hash):**
```json
{
  "success": false,
  "error": "User already exists"
}
```

### `POST /api/auth/exchange-seed-for-token`

**Request body:**
```json
{
  "seed_phrase": "word1 ... word12",
  "device_id": "client-side-uuid",
  "platform": "web",
  "app_version": "1.2.3"
}
```

**Response 200:**
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "550e8400-...",
      "data_version": "v3"
    },
    "device_token": "dGVzdC0zMi1ieXRlcy1iYXNlNjR1cmwtdG9rZW4"
  }
}
```

> Тот же shape что `/login-with-seed`, без `seed_phrase` в response (seed уже есть у клиента).
> Вызывает `ensureLegacyCutoffSet(user_id)` после успеха (F13).

**Response 401:** — как в `/login-with-seed`.

## `device_token` формат

- 32 случайных байта (`crypto.randomBytes(32)`)
- base64url encoded → ~43 символа `[A-Za-z0-9_-]`
- Пример: `dGVzdC0zMi1ieXRlcy1iYXNlNjR1cmwtdG9rZW4`
- Сервер хранит `sha256(token)` как hex string (64 символа) в `devices.device_token_hash`

## What changed vs today

| Поле | Сегодня (`auth.ts:424,485`) | После PR1 | После cutoff cleanup |
|---|---|---|---|
| `data.user.id` | ✅ есть | ✅ остаётся (legacy) | ❌ удалено |
| `data.user.data_version` | только register-auto | все endpoints | все endpoints |
| `data.device_token` | ❌ нет | ✅ добавлено | ✅ |
| `data.seed_phrase` | только register-auto | только register-auto | только register-auto |
| `data.seed_hash` | только register-auto | ❌ **удалить** (internal leak) | ❌ |

## Client-side decoding

```typescript
// TypeScript
interface AuthResponse {
  success: boolean;
  data?: {
    user: { id?: string; data_version?: string };
    seed_phrase?: string;
    device_token?: string;
  };
  error?: string;
}

// Migration logic
if (response.success && response.data?.device_token) {
  localStorage.setItem('device_token', response.data.device_token);
  if (response.data.seed_phrase) {
    // only register-auto case
    localStorage.setItem('seed_phrase', response.data.seed_phrase);
  }
  // seed_phrase НЕ удаляем из localStorage после успешной миграции
  // (spec F18.1, N4.1): нужен для Settings QR и lost-token recovery.
  // Удаляется только при явном logout().
}
```

```swift
// Swift (iOS native)
struct AuthResponse: Decodable {
  let success: Bool
  let data: Data?
  struct Data: Decodable {
    let user: User?
    let seedPhrase: String?      // register-auto only
    let deviceToken: String?     // NEW
  }
  struct User: Decodable {
    let id: String?
    let dataVersion: String?
  }
}
```

## Backward compatibility

- **Старый клиент (без device_token support)**: игнорирует `data.device_token`, продолжает работать на `data.user.id` + `x-user-id` header. Работает до истечения cutoff.
- **Новый клиент (post-PR1)**: читает `data.device_token`, сохраняет в secure store, использует Bearer. Игнорирует `data.user.id` (но tolerance: если `device_token` отсутствует в response — fallback на старый behavior).
- **Post-cutoff cleanup**: `data.user.id` удаляется из response. Это синхронизировано с удалением `socket.on('auth')` и `x-user-id` middleware — одна точка cutoff, три cleanup actions.
