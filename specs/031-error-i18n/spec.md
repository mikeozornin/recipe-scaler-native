# Спецификация: локализация error-типов (AuthError, APIError, YrsError)

**Ветка**: `031-error-i18n`
**Дата**: 2026-06-17
**Статус**: ✅ Реализовано
**Зависимости**: `022-i18n-new-views` (паттерн), `028-app-logging` (AppLog фасад)
**Эталон**: `RecipeEditError` (`RecipeEditPolicy.swift:1-21`), `ImportPhotoValidator.ValidationError` (`RecipeScalerCore/Import/ImportPhotoValidator.swift:26-73`), `ImportErrorLocalizer` (`RecipeScalerNative/Utils/ImportErrorLocalizer.swift`)
**Ревью**: находка №11 в `review-kilo-glm-5.2-recipe-scaler-native.md` (Critical)

## Контекст

Три error-типа (`AuthError`, `APIError`, `YrsError`) возвращают захардкоженный английский через `errorDescription`, который через `error.localizedDescription` попадает в ~50 UI-сайтов. Дополнительно в `APIError.serverError(message:)` 30 throw-сайтов смешивают 4 формата: сырой английский (~18), dot-key (~8), `String(localized:)` (2), гибрид (1).

Это нарушает AGENTS.md правило: *«строки только в `Localizable.xcstrings`; не хардкодь текст в view; без fallback на дефолтные строки»* и делает ошибки непереведёнными на ru-локали.

## Цель

Единый паттерн локализации для `AuthError`, `APIError`, `YrsError`: фиксированные кейсы локализуются inline через `Bundle.currentLocalizedString`, серверные сообщения (`serverError(message:)`) — только dot-key контракту с fallback на generic при несоответствии.

## Не-цели

- Архитектурный рефакторинг god-объектов (`YjsSyncService`, `DocumentManager`) — отдельные находки №9, №10.
- Исправление безопасности аутентификации (нахождение №1) — отдельная задача.
- Серверный код не правится (другой репо), создаётся только контракт-документ.

## Пользовательские сценарии

### US1 — Ошибка аутентификации на ru-локали (P1)

**Дано** язык = ru, **когда** пользователь вводит неверную seed-фразу, **тогда** видит локализованное сообщение («Неверная сид-фраза»), а не английский литерал.

### US2 — Сетевая ошибка на ru-локали (P1)

**Дано** язык = ru, **когда** профиль не загрузился с сервера, **тогда** видит generic локализованное сообщение, а не английский fallback «Profile load failed».

### US3 — Техническая ошибка CRDT (P2)

**Дано** язык = ru, **когда** yrs-транзакция не удалась, **тогда** видит осмысленное сообщение о технической ошибке, а не стек-трейс yrs.

### US4 — Серверный dot-key (P1)

**Дано** сервер возвращает `response.error = "assistant.threads.create.failed"`, **когда** iOS резолвит через `APIError.userFacingMessage()`, **тогда** пользователь видит локализованное сообщение по ключу `assistant.threads.create.failed`.

### US5 — Старый сервер без dot-key (P1)

**Дано** сервер возвращает `response.error = "Profile load failed"` (сырой английский, контракт ещё не мигрирован), **когда** iOS пытается резолвить, **тогда** строка детектится как не-dot-key и показывается generic локализованное сообщение.

## Требования

### FR-031-001 — `AuthError` локализация

Inline-паттерн `RecipeEditError`: `errorDescription` каждого кейса возвращает `Bundle.currentLocalizedString("auth.error.<case>")`. Для `apiError(statusCode:message:)` — dot-key детекция + generic fallback.

### FR-031-002 — `APIError` dot-key errorDescription

Core не имеет доступа к Native xcstrings. `errorDescription` возвращает dot-key строку (без перевода). Native-extension `APIError+Localization.swift` добавляет `userFacingMessage()` с резолвом через `Bundle.currentLocalizedString`.

### FR-031-003 — `YrsError` локализация + удаление dead-code

Локализовать живые кейсы (`nullPointer`, `applyFailed`, `transactionError`) через `Bundle.currentLocalizedString`. Удалить dead-code `invalidState`, `corruptedState`. Контекст (`context: String`) сохраняется в associated value для логов, **не** интерполируется в `errorDescription`.

### FR-031-004 — Унификация throw-сайтов

30 throw-сайтов `APIError.serverError(message:)` мигрируют на dot-key контракту. Все `response.error ?? "English fallback"` заменяются на `response.error ?? "dot.key"`.

### FR-031-005 — Миграция view-сайтов

~50 view-сайтов с `error.localizedDescription` заменяются на типизированный catch с вызовом localizer-метода (`error.userFacingMessage()` для APIError, `error.errorDescription` для AuthError/YrsError).

### FR-031-006 — Каталог `Localizable.xcstrings`

~40 новых ключей в `en` + `ru` (по образцу `edit.error.*`, `extractionState: manual`).

### FR-031-007 — Контракт для бэкенда

Создать `specs/031-error-i18n/server-error-keys.md` — таблица dot-key → HTTP endpoint → текущий английский → новый dot-key. Создать `schema.json` для валидации.

### FR-031-008 — Логирование

Yrs-сайты создания ошибок (`YrsDocument.swift:85,128,169,177`) добавляют `AppLog.error(.document, "yrs_*", data: ["context": ...])` для отладки. Контекст не утекает в UI.

### FR-031-009 — Тесты

- `LocalizationConsistencyTests` — проверка наличия всех новых ключей в en + ru.
- `AuthErrorLocalizationTests` — `errorDescription` не равен захардкоженному английскому литералу.
- `APIErrorUserLocalizerTests` — dot-key распознаётся; гибрид резолвится; сырой английский → generic.
- `YrsErrorLocalizationTests` — `errorDescription` всех живых кейсов локализован.

## Вне scope

- Перевод пользовательских данных (контент рецептов).
- Рефакторинг архитектуры сервисов.
- Правки серверного кода (другой репо).

## Критерии успеха

- **SC-001**: В ru-локали на AuthView, YDocRecipeDetailView, Discover, Telegram, Account нет английских error-сообщений.
- **SC-002**: Все 30 throw-сайтов `APIError.serverError(message:)` используют dot-key контракту.
- **SC-003**: `Localizable.xcstrings` содержит ru+en для всех новых ключей.
- **SC-004**: `xcodebuild test` зелёный, включая новые localizer-тесты.
- **SC-005**: Dead-code кейсы `YrsError.invalidState`, `YrsError.corruptedState`, `AuthError.userNotFound`, `AuthError.seedPhraseGenerationFailed` удалены.

## Артефакты

- `specs/031-error-i18n/spec.md` — этот документ
- `specs/031-error-i18n/plan.md` — план реализации
- `specs/031-error-i18n/server-error-keys.md` — контракт для бэкенда
- `specs/031-error-i18n/schema.json` — JSON-схема валидации
