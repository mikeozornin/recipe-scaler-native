# Спецификация: подключение Алисы (навык «Книга рецептов») — нативное приложение

**Ветка**: `feature/alice-connect`
**Дата**: 2026-10-22
**Статус**: Implemented (не закоммичено)
**Канонический сервер + web**: [`recipe-scaler-web/specs/066-alice-skill`](../../../recipe-scaler-web/specs/066-alice-skill/spec.md), US11 «привязка аккаунта», и web-компонент `recipe-scaler/src/components/alice-connection.tsx`.
**Зависимости**: `013-account-settings` (`AccountView`), `020-account-telegram-export` (эталон Telegram), `031-error-i18n`, `041-auth-device-tokens` (`APIClient`)

---

## Границы (Scope)

**Входит (только native UI):**

- Секция «Алиса» в «Моё всё» (профиль): описание, получение 8-значного кода, копирование, новый код, статус «Подключена» и «Отключить».
- Клиент `AliceAPI` для `/api/alice/connect`, `/api/alice/status` и `/api/alice/disconnect`.
- i18n-ключи `alice.*` (en и ru), dot-key ошибки `alice.failed-to-*` в `ServerErrorCode`.
- Accessibility identifiers `account_alice_*`.

**Не входит:**

- Сервер, OAuth-страница входа навыка, голосовой роутер (всё в web, spec 066).
- Таймер истечения кода и автообновление по TTL (в web их тоже нет).
- Ссылка на навык в каталоге Алисы и отдельная группа «Подключения» в профиле.

## Контекст

Яндекс открывает нашу страницу входа и просит 8-значный код. Код выдаёт `POST /api/alice/connect`: одноразовый, живёт 10 минут. Пользователь вводит его на странице входа или называет Алисе. До этой спеки код можно было получить только в web.

## Поведение

1. Секция стоит после Вкусвилла: в web порядок «Подключений» такой же (Telegram → Вкусвилл → Алиса). Секция видна во всех локалях; заголовок — `alice.title`, описание `alice.benefits-description` показывается всегда.
2. При появлении и после pull-to-refresh выполняется `GET /api/alice/status` (только онлайн и с авторизованным пользователем). Ошибка статуса не показывается, как в web.
3. Не подключено: строка «Подключить» с `ProgressView` на время запроса. Успех показывает `alice.code-instructions` и код в моноширинном блоке (VoiceOver читает его по цифрам), рядом icon-only кнопки «Скопировать код подключения» и «Получить новый код подключения».
4. Пока код на экране, статус опрашивается раз в 3 секунды. Когда `connected == true`, код скрывается и показывается «Подключена» с зелёной галочкой. Опрос останавливается при уходе с экрана и возобновляется при возврате, если код ещё показан.
5. Подключено: «Отключить» без подтверждения (как в web и Telegram). Успех возвращает «Подключить».
6. Ошибки connect и disconnect показываются сноской над строкой. Если новый код получить не удалось, старый остаётся на экране. Офлайн и во время запроса кнопки неактивны.
7. Ответ статуса, отправленный до успешного connect или disconnect, не перезаписывает новое состояние (счётчик `epoch`).

## API

| Запрос | Ответ `data` | Ошибка → ключ |
|--------|--------------|---------------|
| `POST /api/alice/connect` `{}` | `{ code, expiresInMinutes, instructions }` | `alice.failed-to-get-code` |
| `GET /api/alice/status` | `{ connected, connectedAt?, lastActiveAt? }` | `alice.failed-to-get-status` |
| `POST /api/alice/disconnect` `{}` | — (`{ success, message }`) | `alice.failed-to-disconnect` |

Сервер отвечает 5xx английским текстом. `AliceAPI.withFallback` сводит `.upstreamMessage` и 5xx к ключу эндпоинта. `.unauthorized`, 4xx без тела и сетевые ошибки проходят как есть.

## Downstream consumers

- `AccountView.aliceSection` → `AliceConnectionView` → `AliceConnectionViewModel` → `AliceAPI`.
- `ServerErrorCode.allCases` проверяет `ErrorLocalizationTests`. Ключи `alice.*` есть в `LocalizationConsistencyTests`.

## Async lifecycle / teardown

- `pollTask` держит `self` слабо и завершается сам, когда код скрыт или подключение установлено. `onDisappear` вызывает `stopPolling()`.
- `.task(id: "\(isOnline)-\(refreshTick)")` перезапрашивает статус при смене сети и pull-to-refresh.

## Accessibility identifiers

`account_alice_connect`, `account_alice_disconnect`, `account_alice_status`, `account_alice_code`, `account_alice_copy`, `account_alice_refresh`.

## Verification

- `AliceConnectionTests`: DTO, маппинг ошибок, жизненный цикл view model (providers подменены).
- `LocalizationConsistencyTests`, `ErrorLocalizationTests`, `scripts/lint-i18n.sh`, `scripts/verify-translations.sh`.
- Симулятор против локального сервера: состояния «не подключено» и «код показан», светлая и тёмная тема.
