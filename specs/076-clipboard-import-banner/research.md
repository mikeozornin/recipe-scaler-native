# Research: баннер импорта ссылки из буфера

**Дата**: 2026-09-14  
**Для**: [spec.md](./spec.md)

## Decision: detect URL cheaply, classify URL-only after read

- **Decision:** Сначала `UIPasteboard.detectPatterns` / `hasURLs` (iOS 17+). Если вероятного web URL нет — **не** читать `.string`. Если паттерн есть — прочитать строку один раз и прогнать через существующий `ImportContentClassifier` (`isUrlOnly`, лимит 25).
- **Rationale:** URL-only нельзя доказать без текста; чтение `.string` может показать системное «вставлено из …». Не читать буфер без URL-паттерна режет ложные срабатывания на рецептном тексте.
- **Alternatives:** Всегда `.string` (лишний paste-chrome); только `hasURLs` без классификатора (смесь «посмотри https://…» показывала бы баннер); серверная эвристика «это рецепт?» (out of scope, сеть до согласия).

## Decision: candidate = нормализованный набор URL

- **Decision:** Ключ сессии — упорядоченный дедуп-список http(s) из классификатора, не сырая строка буфера. Dismiss/consumed сравнивают этот список.
- **Rationale:** Пробелы/перевод строки не должны заново показывать ту же ссылку. Несколько URL без текста — один candidate (batch как в 010).
- **Alternatives:** Хэш всей pasteboard string (ломается от trailing newline); только первый URL (теряем batch).

## Decision: память процесса, не диск

- **Decision:** `dismissed` / `consumed` только in-memory в store. Logout чистит. Process death — пусто.
- **Rationale:** Продуктовое решение 2026-09-14. UserDefaults создал бы «навсегда скрыл эту ссылку».
- **Alternatives:** Персист URL (отклонено); dismiss любых ссылок до kill процесса (нельзя предложить новую ссылку в той же сессии).

## Decision: facade своих Copy

- **Decision:** Один хелпер записи в pasteboard (`AppPasteboard` или эквивалент), который выставляет `changeCount` как «своя запись». Существующие Copy в app target перевести на него. Store игнорирует evaluate с этим changeCount.
- **Rationale:** FR-009. Разрозненные `UIPasteboard.general.string =` иначе покажут баннер на share-URL рецепта / списке покупок / seed.
- **Alternatives:** Heuristic по host recipe-scaler.ru (ложные отрицания на публичный рецепт из Safari); не трогать call sites (регресс Copy).

## Decision: ImportPresentation несёт seed + autoSubmit

- **Decision:** Расширить `ImportPresentation`: `seedText` (URL через `\n`) и `autoSubmit`. `presentImport()` без аргументов — как сейчас (пусто, ручной Import tab). Баннер зовёт `presentImport(seedText:autoSubmit: true)`.
- **Rationale:** Один `.sheet(item:)`. Не второй pipeline. `ImportRecipeSheet.onAppear` сегодня зовёт `resetState()` — **сначала reset, потом seed, потом auto-submit**. Иначе seed сотрут.
- **Alternatives:** Тихий `RecipeImportAPI.importURLs` без sheet (отклонено: нужен видимый прогресс); отдельный sheet (дубль UX).

## Decision: store в AppContainer, не .shared

- **Decision:** `@MainActor @Observable ClipboardImportStore` в `AppContainer`, inject через `.environment`, `clearForLogout()` из `stopForLogout` / wipe. Pasteboard OS-фасад можно тестировать протоколом.
- **Rationale:** Composition root. Сессия пользователя. Не AppIntents.
- **Alternatives:** View-local store на AppShell (сложнее logout/epoch); `.shared`.

## Decision: evaluate на .active и pasteboard change, не polling

- **Decision:** `scenePhase == .active` + `UIPasteboard.changedNotification`. Каждому evaluate — `generation` / epoch. In-flight `detectPatterns` после logout отбрасывается.
- **Rationale:** Clipboard меняется в фоне; polling батарея и лишние чтения.
- **Alternatives:** Только cold start (пропустит copy через app switcher); Timer 1s.

## Decision: layout не блокер кода

- **Decision:** [layout.md](./layout.md) есть; pixel-perfect и `layout-acceptance.json` — позже, по явному «разберёмся». Реализацию баннера не стопать на human hash.
- **Rationale:** Владелец продукта 2026-09-14. Static audit до view ожидаемо FAIL.
- **Alternatives:** Жёсткий STOP до acceptance (блокирует фичу без макета Figma).
