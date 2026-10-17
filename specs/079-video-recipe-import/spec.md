# Спецификация: импорт рецепта из видео YouTube — native

**Feature Branch**: `079-video-recipe-import`  
**Created**: 2026-10-08  
**Status**: Draft — ждёт human review. Phase 0 на сервере: A2–A5 пройдены, импорт синхронный (FR-005 не нужен), A1 (спрос) открыт  
**Канон (server / wire)**: [`recipe-scaler-web/specs/079-video-recipe-import/spec.md`](../../../recipe-scaler-web/specs/079-video-recipe-import/spec.md)  
**Input**: «Reels, Shorts, YouTube: импорт с расшифровкой речи и кадров. Каждый шаг ссылается на нужный момент видео, тапнул — посмотрел, как именно „загибать края“.» В v1 — только YouTube (обоснование в каноне).

**Зависимости**:
- [010-recipe-import](../010-recipe-import/spec.md) — `ImportRecipeSheet`, `RecipeImportAPI.importURLs`, `ImportErrorLocalizer`
- [025-share-extension](../025-share-extension/spec.md) — `ShareView`, Action Extension
- [076-clipboard-import-banner](../076-clipboard-import-banner/spec.md) — баннер принимает любой http(s)-URL, ссылка YouTube проходит без изменений
- [004-description-read-only](../004-description-read-only/spec.md) / [019](../019-recipe-description-inline-edit/spec.md) — Link mark в шагах уже рендерится и открывается (`RecipeDescriptionInlineTextView`, `.link`)

---

## Границы

**В scope:**

- Импорт ссылки YouTube через все существующие входы: Import sheet, баннер буфера, Share Extension (в том числе из приложения YouTube), Action Extension в Safari.
- Текст ожидания для видео: клиент сам распознаёт YouTube-URL и показывает «Смотрим видео, это может занять до минуты» вместо обычного «Импортируем».
- Локализация новых кодов `video_*` в `Localizable.xcstrings` (приложение) и `Shared.xcstrings` (расширения), en+ru, без fallback.
- Метки `▶ M:SS` в шагах: проверить, что они рендерятся проектным шрифтом и тап открывает YouTube (приложение или Safari) на нужном моменте. Новый код только если проверка найдёт дефект.
- Если сервер выберет асинхронную модель (канон FR-012) — состояние «импорт идёт, можно закрыть» в sheet и расширении; рецепт появляется в коллекции через обычный sync.

**Вне scope:**

- Встроенный плеер, отдельный UI-компонент метки, новый Tiptap-узел.
- Instagram, TikTok, VK, Rutube, Telegram-видео.
- Загрузка видеофайла из галереи (UTType movie в Share Extension).
- Изменения Y.Doc и yrs-моста.

---

## Контекст и мотивация

Серверная часть делает всю работу: рецепт приходит обычным v3-документом, метки — обычными ссылками в шагах. Задача native — не испортить ожидание (видео разбирается дольше сайта) и показать понятные отказы вместо сырого текста ошибки. Сейчас `ImportErrorLocalizer` для неизвестных сообщений показывает сырую строку сервера.

---

## Clarifications

### Session 2026-10-08 (предложено агентом — подтвердить на review)

- Q: Нужен ли native-компонент для метки времени? → A: Нет в v1. Link mark уже открывается. Отдельный компонент — только если ценность подтвердится.
- Q: Как клиент узнаёт, что импорт видео? → A: Тот же детектор хостов, что на сервере (watch / youtu.be / shorts / m.youtube), — только для текста ожидания. Решение о пути принимает сервер.
- Q: Что если у пользователя не открывается YouTube? → A: Ничего не делаем в v1: тап уходит в систему, рецепт самодостаточен.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Поделился роликом из YouTube → рецепт (Priority: P1)

Человек смотрит ролик в приложении YouTube, жмёт «Поделиться» → Recipe Scaler. Расширение показывает «Смотрим видео…», через ожидание — «Готово» и кнопку «Открыть». Рецепт в коллекции, у шагов метки времени.

**Why this priority**: основной вход для видео — Share из YouTube.

**Independent Test**: Share из YouTube-приложения на устройстве → рецепт открыт, тап по `▶ M:SS` открывает YouTube на моменте шага.

**Acceptance Scenarios**:

1. **Если** расширение получило YouTube-URL, **Когда** идёт импорт, **Тогда** текст ожидания — видео-вариант, не общий.
2. **Если** импорт успешен, **Когда** пользователь жмёт «Открыть», **Тогда** открывается рецепт, как после любого URL-импорта.
3. **Если** сервер вернул код `video_*`, **Когда** показывается ошибка, **Тогда** текст локализован и есть «Повторить» (кроме `video_too_long` и `video_daily_limit` — повтор бесполезен).

---

### User Story 2 — Скопировал ссылку → баннер → рецепт (Priority: P1)

Работает без изменений 076: баннер, Import sheet, авто-submit. Отличие — текст ожидания и ошибки.

**Acceptance Scenarios**:

1. **Если** в буфере ссылка YouTube, **Когда** пользователь жмёт кнопку баннера, **Тогда** Import sheet показывает видео-вариант ожидания.

---

### User Story 3 — Тап по метке шага (Priority: P1)

В шаге рецепта — `▶ 2:15`. Тап открывает YouTube на 2:15.

**Acceptance Scenarios**:

1. **Если** шаг содержит Link mark на `youtube.com/watch?v=ID&t=135s`, **Когда** пользователь тапает метку, **Тогда** система открывает YouTube на этом моменте.
2. **Если** открыт режим редактирования описания, **Когда** пользователь удаляет метку, **Тогда** она удаляется как обычная ссылка, синхронизация не ломается.
3. **Если** включён режим «экран не гасить» / hands-free, **Когда** пользователь листает шаги, **Тогда** метки не мешают жестам и голосу.

---

### Edge Cases

- Ожидание дольше клиентского таймаута (`APIClient.llmRequestTimeout` = 180 с) — сервер обязан ответить раньше (канон FR-012); клиент показывает обычную ошибку таймаута.
- Расширение закрыто во время ожидания — при синхронной модели импорт может завершиться на сервере, рецепт появится после sync; дублей не создаём повторным запросом сами.
- Ссылка YouTube + другие URL в буфере или sheet — сервер отвечает 400; клиент показывает локализованное «видео импортируется по одной ссылке».
- Пользователь офлайн — как сейчас: URL-импорт недоступен.
- Смена языка в Профиле — тексты ожидания и ошибок на новом языке.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Import sheet, `ShareView` (Share и Action Extension) MUST показывать видео-вариант текста ожидания, если единственный URL — YouTube (тот же набор хостов, что в каноне FR-001).
- **FR-002**: `ImportErrorLocalizer` MUST переводить `video_unavailable`, `video_too_long`, `video_no_recipe`, `video_import_failed`, `video_daily_limit` и ошибку «видео вместе с другими ссылками» в ключи `Localizable.xcstrings` и `Shared.xcstrings` (en+ru). Сырые коды и сообщения провайдера пользователю не показываются.
- **FR-003**: Для `video_too_long` и `video_daily_limit` кнопка «Повторить» MUST NOT показываться.
- **FR-004**: Link mark с YouTube-URL в шаге MUST рендериться шрифтом Martian и открываться системой. Если проверка покажет иное поведение — исправить в рамках этой спеки.
- **FR-005**: Если канон выберет асинхронную модель, sheet и расширение MUST показывать «импорт идёт, рецепт появится в коллекции» и позволять закрыться без отмены импорта. Детали — в plan после Phase 0.

### Key Entities

- **Video URL hint**: клиентская классификация «единственный URL — YouTube»; влияет только на текст ожидания.

---

## Success Criteria *(mandatory)*

- **SC-001**: Share из YouTube-приложения до открытого рецепта — без ручного ввода, тем же числом тапов, что импорт сайта.
- **SC-002**: Ни одна ошибка видео-импорта не показывает сырой текст сервера ни в приложении, ни в расширениях.
- **SC-003**: Тап по метке открывает YouTube в пределах ±10 с от момента, указанного в метке (с учётом поведения YouTube-приложения).

---

## Assumptions

- Серверная часть и Phase 0 — в каноне. Native не начинает работу до прохождения Phase 0.
- Приложение YouTube шарит `public.url`; Share Extension уже принимает WebURL.
- Тексты ключей — в плане; черновик: `import.video-waiting` — «Смотрим видео, это может занять до минуты» / «Watching the video, this can take up to a minute».

---

## Конституционная проверка

| Gate | Статус | Evidence |
|------|--------|----------|
| CRDT-first | N/A | Рецепт создаёт сервер; native читает обычный v3 Y.Doc |
| Web parity | PASS | Метки — Link mark, которую рендерят оба клиента; коды ошибок общие |
| Offline-first | PASS | Как URL-импорт: офлайн недоступен, приложение usable |
| Native UI | PASS | Существующие sheet и ShareView |
| Phased delivery | PASS | Phase 0 (server) → server v1 → native тексты и ошибки |
| i18n | PASS | Новые ключи в обоих каталогах, en+ru |
| Documentation | PASS | spec → plan → tasks |

---

## Downstream consumers

- **SwiftUI**: `ImportRecipeSheet` (текст ожидания, ошибки), `ShareView` (расширения).
- **Core**: `ImportErrorLocalizer`, детектор YouTube-хостов в `RecipeScalerCore/Import`.
- **Strings**: `Localizable.xcstrings`, `Shared.xcstrings`.
- **Sync / Y.Doc**: N/A.
- **Tests**: детектор хостов, маппинг кодов в обоих bundle, отсутствие «Повторить» для двух кодов.

---

## Positive invariants

| Effect | Invariant | Test |
|--------|-----------|------|
| `https://youtu.be/ID` единственный URL | видео-вариант ожидания | `test_youtu_be_is_video_hint` |
| `/shorts/ID` | видео-вариант | `test_shorts_is_video_hint` |
| YouTube + сайт | не видео-вариант (сервер вернёт 400) | `test_mixed_urls_not_video_hint` |
| сайт рецептов | общий текст | `test_site_url_not_video_hint` |
| ошибка `video_too_long` | локализованный текст, без «Повторить» | `test_video_too_long_no_retry` |
| каждый `video_*` код в `.main` и `.module` | ключ найден, не сырая строка | `test_video_codes_localized_both_bundles` |

---

## Async lifecycle

| Op | Identity | Re-check | Cancel owner | Stale test |
|----|----------|----------|--------------|------------|
| Video URL import (sync) | существующий `importTask` sheet / ShareView | как в 010/025 | sheet / ShareView | повторный тап не запускает второй импорт |
| Async-модель (если выбрана) | id задачи от сервера + userId | userId не сменился | сервер; клиент не отменяет при закрытии | logout во время ожидания не показывает чужой рецепт |

Правила: [docs/agents/ASYNC-LIFECYCLE.md](../../docs/agents/ASYNC-LIFECYCLE.md).

---

## Teardown / resource inventory

| Path | Postcondition |
|------|----------------|
| Успех | как 010/025 |
| Ошибка | локализованный текст; «Повторить» по FR-003 |
| Закрыто расширение во время ожидания | клиент ничего не держит; результат придёт через sync |
| Logout | как 010 |

---

## Verification

- Unit: детектор, локализация кодов в двух bundle, правило «Повторить».
- Device: Share из YouTube-приложения; Action Extension в Safari на `youtube.com/watch`; баннер буфера; тап по метке открывает YouTube на моменте.
- Регрессия: импорт сайта, текста, фото не меняется; `LocalizationConsistencyTests` зелёный; `scripts/lint-i18n.sh`.
- Если меняется UI ожидания заметнее текста — `layout.md` + human review.
