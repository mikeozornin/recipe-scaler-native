# Спецификация: включение Discover и публичные профили

**Ветка**: `017-discover-enablement`  
**Дата**: 2026-06-03 (создана), 2026-06-14 (реализовано)  
**Статус**: **Done** — все FR и SC закрыты, билд и все 13 verify-скриптов зелёные.  
**Зависимости**: `007-app-shell-navigation`, `011-discover-public`  
**Эталон**: `/discover` routes, `PublicProfileHeader`, `bottom-nav.tsx`

## Решения (iOS-adaptations)

- **Breadcrumb sticky header из веба НЕ реализован.** Вместо него — стандартный `NavigationStack` back-button + `navigationTitle`. Соответствует iOS HIG: iOS back-button уже телеграфирует иерархию, дублирующий breadcrumb parent-link избыточен и визуально перегружает экран. Если позже потребуется веб-parity breadcrumb — отдельная задача.
- **Search**: используется нативный `.searchable(text:, placement: .navigationBarDrawer(.automatic), prompt:)`. Правила фильтрации — токенизированные через `RecipeSearchUtils` (NFKD + diacritics + quoted phrases + AND), переиспользуется с `RecipeListView`.
- **Preview images**: `PublicImageCacheService` + `DiscoverImageMemoryCache` — disk cache в `Caches/PublicImages/` с ETag (spec 021). Не offline-first; iOS может очистить. Личный `RecipeImageService` для Discover **не** используется.
- **HTML description** curated-рецептов: простой regex-конвертер в plain text → markdown (`AttributedString(markdown:)`). Аутентичный Tiptap-рендеринг — вне scope 017.
- **Toast после clone**: переиспользуется существующий `TransientStatusBanner` через `ShoppingFeedback.postStatus`.
- **Импорт-таб**: оставлен как 5-й равноправный таб, открывает sheet (веб-parity, по решению пользователя). Отклонение от iOS HIG осознанное.

## Контекст

REST-слой Discover (`DiscoverAPI`) и экраны (`DiscoverRootView`, `DiscoverCollectionView`, `DiscoverRecipeView`) уже написаны в рамках 011, но:

1. Вкладка Discover **закомментирована** в `AppShellView` (`AppShellView.swift:64`) — экраны недостижимы (нарушает US1 в 007: 5 вкладок).
2. Экран публичного профиля — заглушка `Text("… open on web for full parity")` (US3 в 011 не закрыт).
3. Превью-изображения curated-рецептов не загружаются в списках.

## Цель

Сделать вкладку Discover доступной и довести публичный профиль до read-only паритета с мобильным вебом.

## Пользовательские сценарии

### US1 — Вкладка Discover включена (P1)

**Когда** пользователь авторизован, **тогда** в tab bar 5 вкладок (Discover первая), переключение без потери sync, reset по повторному tap (FR-NAV-002 в 007).

### US2 — Публичный профиль (P1)

**Когда** открыт профиль `/@username`, **тогда** grid рецептов автора, поиск по списку (правила `~/.claude/rules/search-behavior.md`), индикатор share-mode (`one_by_one` | `all` | `with_images_and_steps`) — всё read-only для гостя; CTA «Скопировать к себе» → clone (как US4 в 011).

### US3 — Превью-картинки curated (P2)

**Когда** показан список collections/recipes, **тогда** превью грузятся через `DiscoverAPI.discoverImageURL` с кэшированием (URLCache), офлайн — плейсхолдер.

### US4 — VoiceOver и reset (P2)

**Тогда** VoiceOver объявляет вкладку Discover и selected state; double-tap с вложенного экрана → корень Discover.

## Требования

### FR-017-001 — Включение вкладки

Раскомментировать/восстановить `DiscoverRootView` в `AppShellView`, вернуть `AppTab.discover` в `TabView`, проверить `discoverPath` reset.

### FR-017-002 — Public profile screen

Заменить заглушку `DiscoverRoute.profile` на полноценный экран: `GET` публичного профиля (путь — в `contracts/discover-api.md`), grid + поиск + clone.

### FR-017-003 — REST only, офлайн

Без записи в пользовательский Y.Doc; кэш в URLCache; офлайн — последний кэш + сообщение.

### FR-017-004 — i18n

Все строки Discover/profile — локализованные ключи ru/en (см. 022), не литералы.

## Вне scope

- Редактирование своего public profile (013/020)
- PDF cookbook публичного профиля
- Universal links (опционально позже, см. 012)

## Критерии успеха

- **SC-001**: Вкладка Discover видна и переключается без потери sync.
- **SC-002**: Открытие `/@username` показывает grid рецептов автора (не заглушку).
- **SC-003**: Clone curated/public рецепта → появляется в «Мои рецепты» ≤ 10 с.
- **SC-004**: VoiceOver объявляет все 5 вкладок.

## Артефакты

- `contracts/discover-api.md` — API контракт (все 5 endpoints).
- `quickstart.md` — сравнение iOS vs веб @390px + визуальные отличия.
- `tasks.md` — декомпозиция задач с чекбоксами.

## Verify (2026-06-14)

- `rtk xcodebuild … build` → `** BUILD SUCCEEDED **` (exit 0).
- `scripts/verify-discover-public.sh` → `VERIFIED discover-public` (exit 0).
- `scripts/verify-all.sh` → `All 13 verifiers passed` (exit 0, 236 s) — regression чистый.
