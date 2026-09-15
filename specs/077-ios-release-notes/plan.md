# План: in-app новости релиза на iOS

**Дата**: 2026-09-15  
**Спека**: [spec.md](./spec.md)

> Канонический project template для Recipe Scaler Native. Артефакт пишется на
> русском. Для завершённых исторических планов обратная миграция не требуется.

## Границы

- **В scope**: каталог нот в бинарнике; `lastViewed` на устройстве (UserDefaults приложения, не App Group); баннер в слотах 061 (ниже системного баннера); sheet архива; строка в Профиле под освоением; unit-тесты стора; шаг DRAFT in-app ноты в `prepare-ios-release`.
- **Вне scope**: веб-каталог, сервер / `last_viewed_release_version`, диплинки, HTML, пуши, виджеты, What’s New в ASC, показ баннера в сборке, которая только вводит механизм.
- **STOP conditions**: нельзя грузить каталог или маркер с сети; нельзя использовать `SystemBanner` как канал; нельзя сбрасывать `lastViewed` на logout; нельзя хардкодить хром; нельзя класть ноту в каталог без явной проверки человеком.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | Рецепты / Y.Doc не трогаем |
| Web parity | PASS (осознанно частичный) | UX баннер+лист как на вебе; каталог и persistence намеренно локальные |
| Offline-first | PASS | Каталог и маркер локальны; сеть не нужна |
| Native UI | PASS | SwiftUI баннер + sheet, без WebView |
| Phased delivery | PASS | Один срез: каталог → seed → баннер → sheet → Профиль → skill |
| i18n | PASS | Хром в `Localizable.xcstrings`; title/body — `Text(verbatim:)` по `AppLanguagePreference` |
| Documentation | PASS | spec/plan/tasks; skill `prepare-ios-release`; `docs/RELEASES.md` |

## Очерёдность

1. **Каталог + стор + seed** — без этого UI врёт; зависимости: UserDefaults, состав нот.
2. **Unit-тесты инвариантов** — TDD по таблице Positive invariants; зависимости: стор с инжектом defaults/catalog.
3. **Баннер в слотах 061** — Recipes list / empty / loading / collections; зависимости: стор, визуал 061.
4. **Sheet** — раскрытие непрочитанных до записи max; зависимости: стор.
5. **Профиль** — строка под освоением; зависимости: sheet + непустой каталог.
6. **i18n + skill + docs** — хром, DRAFT in-app отдельно от What’s New.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNative/Models/IOSReleaseNote.swift` | Создать | Запись каталога |
| `RecipeScalerNative/Services/IOSReleaseNotesCatalog.swift` | Создать | Каталог в бинарнике (077: пустой массив) |
| `RecipeScalerNative/Services/ReleaseNotesStore.swift` | Создать | Seed, banner, mark viewed, expand-before-write |
| `RecipeScalerNative/Views/ReleaseNotesBannerView.swift` | Создать | Карточка как 061 + метка + title max |
| `RecipeScalerNative/Views/ReleaseNotesChrome.swift` | Создать | Слоты + screenshot hide + List row |
| `RecipeScalerNative/Views/ReleaseNotesSheet.swift` | Создать | Архив, DisclosureGroup |
| `RecipeScalerNative/Views/RecipeListView.swift` | Изменить | Хром после 061 во всех ветках |
| `RecipeScalerNative/Views/CollectionsRootView.swift` | Изменить | То же |
| `RecipeScalerNative/Views/AccountView.swift` | Изменить | Строка под освоением + sheet |
| `RecipeScalerNative/App/AppContainer.swift` | Изменить | Стор в composition root; **не** clear на logout |
| `RecipeScalerNative/App/AppEnvironment.swift` | Изменить | `.environment(container.releaseNotes)` |
| `RecipeScalerNative/AccessibilityIdentifiers.swift` | Изменить | Banner / dismiss / account row / sheet |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменить | Хром en+ru |
| `RecipeScalerNativeTests/ReleaseNotesStoreTests.swift` | Создать | Positive invariants |
| `RecipeScalerNativeTests/LocalizationConsistencyTests.swift` | Изменить | Новые ключи |
| `RecipeScalerNative.xcodeproj/project.pbxproj` | Изменить | Новые файлы в targets |
| `.agents/skills/prepare-ios-release/SKILL.md` | Изменить | DRAFT in-app отдельно от стора |
| `docs/RELEASES.md` | Изменить | Упомянуть in-app каталог |

## Downstream consumers

- **SwiftUI views**: `RecipeListView`, `CollectionsRootView` (слоты после 061), `AccountView.featureAdoptionSection`, новый banner/sheet.
- **Cross-process**: N/A — не App Group, не виджеты, не Watch.
- **Sync boundaries**: N/A — сервер и Y.Doc не участвуют.
- **Persisted state**: `UserDefaults.standard` ключ `releaseNotes.lastViewedVersion` (Int). Logout / account switch **не** чистят.
- **Tests / verify scripts**: `ReleaseNotesStoreTests`; `LocalizationConsistencyTests`; отдельный `verify-077-*.sh` не обязателен.

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| нет ключа, max = 3 | lastViewed = 3, `showsBanner == false` | `test_missing_key_seeds_max_no_banner` |
| ключ 3, max 3 | `showsBanner == false` | `test_caught_up_hides_banner` |
| ключ 3, max 4 | баннер, title ноты 4 | `test_higher_max_shows_banner` |
| dismiss при max 4 | ключ 4, баннера нет | `test_dismiss_writes_max` |
| open sheet, ключ 3, max 4 | ключ 4 | `test_open_sheet_writes_max` |
| open sheet, ключ 2, ноты 1…4 | раскрыты 3 и 4; расчёт до записи | `test_unread_expanded_before_mark` |
| пустой каталог | нет баннера, `hasArchiveRow == false`; missing key → sentinel 0 | `test_empty_catalog_hides_surfaces` |
| logout при ключе 4 | ключ остаётся 4 | `test_logout_does_not_reset_last_viewed` |
| screenshot-capture | chrome не рендерит баннер | DEBUG-ветка как у 061 в `ReleaseNotesChrome` |
| жест на пустом каталоге | не пишет 0 поверх «ключа нет», если seed уже 0 — no-op | `test_empty_catalog_gesture_does_not_invent_notes` |

## Async lifecycle

N/A — нет async side effects. Seed и mark viewed синхронны в init / жесте. Сети нет.

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| Seed if missing | однократный init store | ключ всё ещё отсутствует | store | повторный init не затирает уже записанный lastViewed меньшим max |
| Mark viewed = max | user gesture dismiss/open | max каталога этой сборки | UI / store | жест не пишет маркер нот, которых нет (пустой каталог) |

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| logout | sheet закрыть в UI | нет | lastViewed **на месте** | N/A | ключ не сброшен |
| account switch | как logout | нет | lastViewed на месте | N/A | баннер не «оживает» от смены аккаунта |
| stale session / cold start | store re-seed только если ключа нет | нет | lastViewed переживает процесс | N/A | dismiss переживает cold start |
| reconnect / partial failure | N/A | нет | N/A | N/A | офлайн не меняет поведение |

## Cross-target contracts

- **Canonical owner**: `IOSReleaseNotesCatalog` (бинарь iOS) + `ReleaseNotesStore` (маркер устройства).
- **Writer/reader targets**: только основное приложение. Extensions / Watch не читают.
- **Validator/normalizer**: человек в `prepare-ios-release` (пустой title/body запрещён); рантайм не подставляет fallback-строки.
- **Raw literal exceptions**: title/body нот — контент каталога, `Text(verbatim:)`.

## Locale / theme consumers

- SwiftUI environment: `\.locale` + `AppLanguagePreference.current` для выбора ru/en полей ноты; хром через `Text("key")`.
- UIKit / notification categories / scheduled content: N/A.
- Widgets / Live Activities / App Intents: N/A.
- Cached or generated assets: N/A.
- `.system` effective value: язык ноты следует in-app override, не CFBundle.

## Compatibility / migration

- Current format/contract: Int `releaseNotes.lastViewedVersion` в UserDefaults приложения.
- Previous supported format: ключа нет.
- Missing version/default behavior: «ключа нет». Непустой каталог → seed max, баннера нет. Пустой каталог → записать sentinel `0`, баннера нет (чтобы **следующая** сборка с max ≥ 1 показала баннер, а не повторно засидела новые ноты).
- Unknown future version/ID behavior: неизвестный/битый value трактовать как «ключа нет» и seed заново.
- Required legacy fixture tests: `test_missing_key_seeds_max_no_banner`, `test_empty_catalog_hides_surfaces`.

## Unknown IDs and fallback policy

- DEBUG/CI: битый ключ → seed как missing (не crash).
- Release: то же; баннер не показываем на seed.
- Legacy aliases: нет.

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app`/`.appex` assertion |
|----------|----------|---------------|----------------|---------------------------------|
| N/A | — | — | — | Каталог — Swift-источник, не codegen |

## Human gates

- [x] `layout.md` не требуется — визуал копирует 061 (assumption спеки).
- [x] `layout-audit.json` не требуется.
- [ ] Отдельный review-agent после кода — по запросу пользователя.

## Verification

- `xcodebuild … build` — схема `RecipeScalerNative`, simulator `id=` из `scripts/resolve-simulator.sh`.
- `xcodebuild … test` — `-only-testing:RecipeScalerNativeTests/ReleaseNotesStoreTests` и `LocalizationConsistencyTests`.
- Отдельный `verify-077-*.sh` не обязателен.
- `bash scripts/lint-i18n.sh` — после правок view.
- Expected evidence: тесты зелёные; сборка 077 с пустым каталогом не показывает баннер.

## Rollback / maintenance

- Как откатить: удалить хром из слотов и стор из контейнера; ключ в UserDefaults безвреден.
- Что будет взаимодействовать: каждая App Store-сборка добавляет ноту с `version` > предыдущего max **после** human review.
- Временные allowlist: нет.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Пустой каталог пишет sentinel 0 | Иначе первая нота в следующей сборке снова попадёт под «ключа нет → seed» и баннер не появится | Placeholder-нота в 077 создала бы пустой архив в Профиле |
