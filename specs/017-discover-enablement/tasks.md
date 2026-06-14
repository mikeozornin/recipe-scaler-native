# Tasks: 017-discover-enablement

**Ветка**: `017-discover-enablement`
**Зависимости**: `007-app-shell-navigation`, `011-discover-public`

## FR-017-001 — Включение вкладки

- [x] Раскомментировать `DiscoverRootView` в `AppShellView.tabView`.
- [x] Убрать `else if tab == .discover { selectedTab = .recipes }` из `openDebugTabIfNeeded`.
- [x] Проверить, что `discoverPath` reset по повторному tap работает (`resetNestedNavigation(for: .discover)`).

## FR-017-002 — Public profile screen

- [x] Расширить `DiscoverAPI` новыми DTO: `PublicProfileDTO`, `PublicRecipePreviewDTO`, `PublicProfileResponseDTO`, `PublicProfileShareMode`.
- [x] Реализовать `DiscoverAPI.fetchPublicProfile(username:)` → `GET /api/users/public/:username`.
- [x] Создать `DiscoverPublicProfileView` с avatar + name + description + share-mode badge + grid + search.
- [x] Заменить стаб `Text("Public profile (read-only)")` в `DiscoverRootView.navigationDestination` на `DiscoverPublicProfileView(username:)`.

## FR-017-003 — REST only, офлайн

- [x] Все Discover API endpoints используют `APIClient.shared.requestJSON` (URLSession.shared с дефолтным URLCache).
- [x] Preview images через `AsyncImage(url:)` (URLCache автоматически возвращает последний ответ при offline).
- [x] **Без** persistent disk cache (`RecipeImageService` НЕ задействован).

## FR-017-004 — i18n

- [x] Добавить в `Localizable.xcstrings` все ключи namespace `discover.*` (en + ru).
- [x] Снять `extractionState: "stale"` с `discover.nav.*` (теперь используются).
- [x] Расширить `LocalizationConsistencyTests.testCriticalKeysResolveInBothLanguages()` новыми ключами.
- [x] Прогнать `scripts/typograf-xcstrings` (если есть неразрывные пробелы в русских строках).

## Паритет с вебом (доп. требования)

- [x] `DiscoverCollectionView` — грид + `.searchable` + author badge + preview images.
- [x] `DiscoverRecipeView` — hero image + servings scaler + read-only ingredients + clone UX с переходом в My Recipes.
- [x] `DiscoverRootView` — грид карточек (не List) с preview images collections + profiles.
- [x] Tokenized search с NFKD-нормализацией и quoted-phrase поддержкой (`DiscoverSearch` → `RecipeSearchUtils`).
- [x] Toast после clone через `ShoppingFeedback.postStatus`.

## Технические работы

- [x] Создать новые файлы: `Utils/DiscoverSearch.swift`, `Views/Discover/{DiscoverCollectionView, DiscoverPublicProfileView, DiscoverRecipeView, DiscoverRecipePreviewImage}.swift`.
- [x] Обновить `scripts/add-swift-sources-to-pbxproj.py` (исправлен regex для Sources phase + сохранение относительного пути).
- [x] Зарегистрировать файлы в `project.pbxproj` через скрипт + вручную добавить subgroup `Discover` (4 файла) и `DiscoverSearch.swift` в существующую Utils.
- [x] Расширить `AccessibilityIdentifiers` новыми ID для Discover.

## Acceptance criteria (по спеке 017)

- [x] **SC-001**: Discover-таб видим первым, переключается без потери sync — `verify-app-shell.sh` прошёл.
- [x] **SC-002**: Открытие `@username` открывает grid рецептов (не `Text(…)` стаб) — реализовано в `DiscoverPublicProfileView`.
- [x] **SC-003**: Clone curated/public рецепта → появляется в My Recipes (через `DeepLinkRouter.handle(.openRecipe)` + `syncService.loadRecipe`).
- [x] **SC-004**: VoiceOver объявляет все 5 табов (`tabItem` + `accessibilityIdentifier` уже настроены).
- [x] **SC-005**: Все UI-строки — из `Localizable.xcstrings`, нет хардкода.
- [x] **SC-006**: Поиск на коллекции и профиле поддерживает diacritics + multi-token AND (через `RecipeSearchUtils`).

## Verify (fix-until-green)

- [x] `rtk xcodebuild … build` → `** BUILD SUCCEEDED **` (exit 0).
- [x] `scripts/verify-discover-public.sh` → `VERIFIED discover-public` (exit 0).
- [x] `scripts/verify-all.sh` → `All 13 verifiers passed` (exit 0).

## Documentation

- [x] `specs/017-discover-enablement/contracts/discover-api.md` — API контракт.
- [x] `specs/017-discover-enablement/quickstart.md` — сравнение iOS vs web @390px.
- [ ] `specs/017-discover-enablement/tasks.md` — этот файл (done).
- [x] Обновить `specs/017-discover-enablement/spec.md` статус Draft → Done.

## Out of scope (явно не сделано в этой итерации)

- Universal links / deep links на `/discover/*` и `/public/@/*` — отдельная спека 012.
- Редактирование своего public profile — спеки 013/020.
- PDF cookbook export public profile — out of scope по 011/017.
- Persistent offline-first кэш Discover images — REST + URLCache достаточно по 017.
- Share-sheet / social sharing кнопок на discover-рецептах — не в 017.
- Аутентичный Tiptap-рендеринг HTML description — используется plain-text fallback.
