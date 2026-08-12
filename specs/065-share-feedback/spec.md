# Спецификация: Share your feedback (native)

**Ветка**: работа на `master` (AGENTS.md: small fixes на master)
**Дата**: 2026-08-13
**Статус**: Draft
**Canonical API spec**: [`../recipe-scaler-web/specs/065-share-feedback/spec.md`](../../../recipe-scaler-web/specs/065-share-feedback/spec.md) — wire-контракт `POST /api/feedback`, Telegram, rate limit, отсутствие хранения/модерации. Здесь — native UI, клиент и i18n.
**Зависимости**: секция Support Recipe Scaler ([AccountTipsSection.swift](../../RecipeScalerNative/Views/AccountTipsSection.swift)), `APIClient.uploadMultipart`, `TransientStatusBanner` / `ShoppingFeedback.postStatus`, auth (`requireUserId` на сервере), ops Telegram (`MODERATION_ABUSE_ALERT_CHAT_ID`, spec 063).

## Контекст и мотивация

В профиле уже есть секция **Support Recipe Scaler** с одним пунктом «Send a tip». Нужен второй пункт — отправить отзыв с текстом и файлами (скриншоты, логи, что угодно). Отзыв уходит на сервер и сразу в тот же Telegram-чат, куда приходят алерты модерации. Файлы не хранятся и не прогоняются через защиту изображений.

## Цель

1. Второй ряд в секции Support Recipe Scaler: **Share your feedback**.
2. Вложенный экран (NavigationLink, не sheet): textarea + аттачи (галерея / файлы) + Send.
3. Успешная отправка: форма очищается, экран остаётся открытым, зелёный тост «спасибо».
4. Клиент шлёт `POST /api/feedback` (multipart). Сервер форвардит в Telegram и отбрасывает буферы.

## Non-goals

- Web-форма (чаевые тоже iOS-only).
- Камера (только Photo Library и Files).
- Хранение отзывов в БД / S3 / диске.
- OpenAI moderation и `moderationAbuseService` на аттачах.
- Автоприкрепление debug-логов.
- Watch, Share Extension, widgets, Live Activity, App Intents.

---

## Clarifications

### Session 2026-08-13

- Q: iOS + API или ещё web-форма? → A: **iOS + API**. Web-форму не делаем.
- Q: Какие аттачи? → A: **фото и файлы**, без камеры. Сначала `confirmationDialog` с двумя опциями: Photo Library / Files.
- Q: Rate limit? → A: **1 запрос в минуту на пользователя** (не 5/час).
- Q: Что после успеха? → A: **очистить форму + зелёный тост**. Без alert и без pop.

---

## Границы (Scope)

**Входит:**

- Второй `NavigationLink` в той же `Section`, что «Send a tip».
- Экран `AccountFeedbackView`: `TextEditor`, Attach, список выбранных файлов с удалением, Send в toolbar.
- Attach → `confirmationDialog`: Photo Library (`PhotosPicker`) и Files (`.fileImporter`).
- Лимиты на клиенте зеркалят сервер: текст 1–4000 символов; до 5 файлов; до 10 MB каждый.
- Send disabled: пустой текст (после trim), офлайн, идёт отправка, нет сессии.
- Успех: очистка текста и аттачей; зелёный `TransientStatusBanner` с иконкой checkmark (shopping оставляет корзину).
- Ошибка: локализованное сообщение на экране (dot-key), форма не очищается — можно повторить.
- i18n `account.feedback.*` (en+ru), a11y identifiers, page object.

**Не входит:** см. Non-goals.

---

## Пользовательские сценарии и тестирование *(обязательно)*

### User Story 1 — Написать отзыв без файлов (P1)

Пользователь открывает Profile → Support Recipe Scaler → Share your feedback. Пишет текст, нажимает Send. После успеха поля пустые, виден зелёный тост, он остаётся на том же экране и может написать ещё один отзыв позже.

**Почему приоритет**: основной путь; аттачи опциональны.

**Независимое тестирование**: открыть экран, ввести текст, отправить (онлайн, авторизован) — тост + пустая форма.

**Acceptance Scenarios**:

1. **Given** секция Support Recipe Scaler, **When** пользователь смотрит список, **Then** видит два пункта: Send a tip и Share your feedback.
2. **Given** Share your feedback, **When** тап по ряду, **Then** открывается вложенный экран с полем текста, кнопкой Attach и Send.
3. **Given** непустой текст и онлайн, **When** Send, **Then** запрос уходит, после 2xx форма пустая, зелёный тост, экран не закрывается.
4. **Given** пустой или whitespace-only текст, **When** пользователь смотрит Send, **Then** Send disabled, запроса нет.

---

### User Story 2 — Приложить скриншоты и файлы (P1)

Пользователь прикладывает фото из галереи и/или файлы из Files (до 5 суммарно), пишет текст, отправляет. В Telegram у ops приходит текст с метаданными пользователя и те же файлы. На сервере файлов после ответа нет.

**Почему приоритет**: без аттачей сложно разобрать баг по скриншоту.

**Независимое тестирование**: Attach → Photo Library (1–2 фото) и/или Files; список показывает имена; удаление убирает пункт; Send с текстом — тост + пустой список.

**Acceptance Scenarios**:

1. **Given** экран отзыва, **When** Attach, **Then** диалог с двумя опциями: Photo Library и Files (камеры нет).
2. **Given** выбранные файлы, **When** пользователь смотрит список, **Then** видны имена; крестик удаляет файл из набора.
3. **Given** уже 5 файлов, **When** пользователь пытается добавить ещё, **Then** добавление не происходит (остаток слотов = 0).
4. **Given** файл > 10 MB, **When** пользователь его выбирает, **Then** файл не добавляется, показывается локализованная ошибка размера.
5. **Given** текст + 1..5 файлов, **When** Send успешен, **Then** список аттачей пуст вместе с текстом.

---

### User Story 3 — Ошибка сети / лимит / Telegram (P2)

Отправка не прошла. Пользователь видит понятную ошибку, текст и файлы на месте, может нажать Send снова.

**Почему приоритет**: без сохранения черновика потеря отзыва недопустима.

**Независимое тестирование**: офлайн — Send disabled; 429 / 502 — ошибка на экране, форма цела.

**Acceptance Scenarios**:

1. **Given** нет сети, **When** экран открыт, **Then** Send disabled.
2. **Given** сервер отвечает 429 (второй запрос в ту же минуту), **When** Send, **Then** локализованная ошибка rate limit, форма не очищается.
3. **Given** сервер отвечает 502 (Telegram недоступен), **When** Send, **Then** локализованная ошибка отправки, форма не очищается.
4. **Given** идёт отправка, **When** пользователь жмёт Send повторно, **Then** второй запрос не стартует (single-flight).

---

### Edge Cases

- **Не авторизован**: ряд можно показать (секция tips всегда на профиле), Send disabled; запроса нет.
- **Уход с экрана во время Send**: Task отменяется; поздний 2xx не очищает уже другой экран и не показывает тост чужому состоянию (re-check identity после await).
- **Logout / смена аккаунта во время Send**: результат отбрасывается; in-memory аттачи не переживают teardown.
- **Пустые аттачи**: валидно; уходит только текст.
- **Имя файла с не-ASCII / очень длинное**: клиент передаёт исходное имя; сервер санитизирует для Telegram, содержимое не меняет.
- **PhotosPicker security-scoped / Files copy**: файлы копируются в память до Send; после успеха буферы сбрасываются вместе с формой.
- **Reduce Motion**: тост использует существующую анимацию `TransientStatusBanner` — без новой кривой.

---

## Требования *(обязательно)*

### Конституционная проверка

- **I. CRDT-First** — N/A: отзыв не в Y.Doc.
- **II. Web Parity** — PASS с оговоркой: UI iOS-only (как StoreKit tips). Новый REST — auxiliary, как auth/images; web-форму сознательно не делаем в этом заходе. Контракт API общий, веб сможет подключить позже.
- **III. Offline-First** — PASS: экран доступен офлайн (набрать текст, выбрать файлы); Send disabled без сети, черновик живёт в памяти экрана (не в очереди SQLite — отзыв не CRDT-мутация).
- **IV. Native UI** — PASS: SwiftUI Form/List, без WebView.
- **V. Phased delivery** — PASS: самостоятельная единица.

### Функциональные требования

- **FR-001**: В секции Support Recipe Scaler ДОЛЖЕН быть второй пункт Share your feedback (`account.feedback.menu`), первым остаётся Send a tip.
- **FR-002**: Пункт ДОЛЖЕН открывать вложенный экран через NavigationLink (не sheet).
- **FR-003**: Экран ДОЛЖЕН содержать многострочное поле текста с плейсхолдером (`account.feedback.placeholder`).
- **FR-004**: Attach ДОЛЖЕН открывать `confirmationDialog` с Photo Library и Files; камеры нет.
- **FR-005**: Пользователь ДОЛЖЕН иметь возможность приложить до 5 файлов суммарно (фото + документы), каждый ≤ 10 MB.
- **FR-006**: Список аттачей ДОЛЖЕН показывать имя файла и давать удалить пункт до отправки.
- **FR-007**: Send ДОЛЖЕН быть disabled, если текст после trim пустой, нет сети, идёт отправка, или нет auth-сессии.
- **FR-008**: Успешный Send ДОЛЖЕН очистить текст и аттачи, оставить экран открытым и показать зелёный тост (`account.feedback.sent`) через существующий `TransientStatusBanner`. Иконка тоста для отзыва — checkmark; shopping не меняет корзину.
- **FR-009**: Неуспешный Send НЕ ДОЛЖЕН очищать форму.
- **FR-010**: Клиент ДОЛЖЕН отправлять `POST /api/feedback` multipart: поле `message` + файлы `files` (0..5), с Bearer-сессией.
- **FR-011**: Клиент ДОЛЖЕН передать `X-App-Language` и версию приложения (`X-App-Version` = `CFBundleShortVersionString`), чтобы ops видели контекст.
- **FR-012**: Все пользовательские строки — ключи `account.feedback.*` в `Localizable.xcstrings` (en+ru), без hardcoded UI-текста и без fallback.
- **FR-013**: Ошибки сервера — dot-keys (`account.feedback.send-failed`, `account.feedback.rate-limited`, `account.feedback.invalid`, `account.feedback.too-large`) через `ServerErrorCode` / `userFacingMessage()`.
- **FR-014**: Submit — single-flight: guard до первого await, снятие через `defer`; после await — re-check, что экран/сессия те же.
- **FR-015**: Аттачи на клиенте живут только в памяти экрана; после успеха, teardown или logout буферы отбрасываются.

### Ключевые сущности

- **FeedbackDraft** (in-memory, экран): `message: String`, `attachments: [FeedbackAttachment]`.
- **FeedbackAttachment**: `id`, `fileName`, `mimeType`, `data: Data`, `byteCount`.
- **Сервер** не персистит сущности — см. web spec.

---

## Downstream consumers

- **SwiftUI views**: `AccountTipsSection` (второй ряд), новый `AccountFeedbackView`; `TransientStatusBanner` / `AppShellView` (иконка тоста).
- **Cross-process**: N/A — только основной app target.
- **Sync boundaries**: новый REST `POST /api/feedback` (web server). Yjs/CRDT не меняются.
- **Persisted state**: N/A — черновик не пишется в SQLite/UserDefaults/Keychain.
- **Tests / verify scripts**: unit на клиентский submit (single-flight, empty disabled); UITest на наличие ряда и экрана; серверные тесты — в web spec. `lint-i18n.sh`.

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| Открыть Support Recipe Scaler | Видны два ряда: tip и feedback | UITest page object |
| Send с текстом, 2xx | Форма пустая, зелёный тост с checkmark, экран открыт | UITest / ручная проверка |
| Send офлайн | Send disabled, запроса нет | unit / ручная |
| Второй Send в ту же минуту | 429, форма цела, локализованная ошибка | server test + ручная |
| 5 файлов уже выбрано | шестой не добавляется | unit |
| Logout во время Send | буферы и Task не переживают teardown | teardown invariant |

## Async lifecycle / Teardown

Submit — единственный async путь: `Task` на Send, captured `userId` + generation/epoch экрана, cancel on `onDisappear`, re-check после await перед clear/toast. Single-flight до await, `defer` снимает busy.

| Entry path | In-memory | Tasks | Persisted | Cross-process | Positive postcondition |
|------------|-----------|-------|-----------|---------------|------------------------|
| logout | draft + attachments = empty | submit cancelled | N/A | N/A | нет тоста чужой сессии |
| account switch | то же | то же | N/A | N/A | то же |
| stale session / cold start | экран не восстановлен | N/A | N/A | N/A | пустой draft |
| reconnect / partial failure | draft сохранён в `@State` | busy сброшен | N/A | N/A | форма цела, можно Send |

---

## Критерии успеха *(обязательно)*

- **SC-001**: Пользователь находит Share your feedback в Support Recipe Scaler и открывает форму за один тап.
- **SC-002**: Пользователь отправляет текстовый отзыв и сразу видит подтверждение (зелёный тост), не теряя экран.
- **SC-003**: Пользователь может приложить скриншоты и файлы (суммарно до 5) к тому же отзыву.
- **SC-004**: При ошибке отправки текст и файлы остаются, пользователь может повторить.
- **SC-005**: Ops получает отзыв в том же Telegram-чате, что алерты модерации, с текстом и вложениями; файлы на сервере не сохраняются.
- **SC-006**: `lint-i18n.sh` зелёный; UI-текст только из xcstrings.

## Допущения

- Пользователь в production почти всегда авторизован (debug auto-login). Ряд не прячем, Send без сессии disabled.
- Черновик не переживает уход с экрана — отдельный persist не просили.
- Существующий зелёный тост (`TransientStatusBanner`) — канонический success-chrome; параметризуем только SF Symbol.
- Лимиты 4000 символов / 5 файлов / 10 MB согласованы с Telegram Bot API (message 4096, document 50 MB) с запасом на метаданные и память multer.
- Получатель Telegram — тот же numeric chat id, что spec 063 (`MODERATION_ABUSE_ALERT_CHAT_ID`).
- Figma нет — `layout.md` не пишем; экран в стиле nested account (List + `.appBody()`).
