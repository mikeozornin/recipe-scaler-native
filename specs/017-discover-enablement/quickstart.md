# Quickstart: Discover enablement (iOS vs web @390px)

**Связанные спецификации**: 011-discover-public, 017-discover-enablement
**Цель**: кратное сравнение iOS-реализации Discover с мобильным вебом (390px), для визуальной и поведенческой проверки паритета.

## Архитектура экранов

| Маршрут (web) | Экран iOS | Файл |
|---|---|---|
| `/discover` | `DiscoverRootView` | `RecipeScalerNative/Views/DiscoverRootView.swift` |
| `/discover/collection/:slug` | `DiscoverCollectionView` | `RecipeScalerNative/Views/Discover/DiscoverCollectionView.swift` |
| `/discover/recipe/:id` | `DiscoverRecipeView` | `RecipeScalerNative/Views/Discover/DiscoverRecipeView.swift` |
| `/public/@/:username` | `DiscoverPublicProfileView` | `RecipeScalerNative/Views/Discover/DiscoverPublicProfileView.swift` |

Все экраны — внутри одного `NavigationStack(path: $discoverPath)` в `DiscoverRootView`. Роутинг через `DiscoverRoute` enum.

## Веб-паттерн → iOS-адаптация

| Веб (390px) | iOS-адаптация | Комментарий |
|---|---|---|
| Sticky `PublicProfileHeader` с breadcrumb (avatar + back + parent-link) | Стандартный `NavigationStack` back-button + `navigationTitle` | Соответствует HIG: iOS back-button уже телеграфирует иерархию. Breadcrumb parent-link — не нужен (см. решение в spec.md). |
| CSS grid 5 columns адаптивный | `LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))])` | Адаптируется под iPhone и iPad. |
| `<Input>` для поиска с clear-button | `.searchable(text:, placement: .navigationBarDrawer(.automatic), prompt:)` | Нативный iOS search bar; правила фильтрации через `DiscoverSearch` (NFKD + AND-tokenization). |
| `<ContentUnavailable>` для empty/error/loading | `ContentUnavailableView` (iOS 17+) | Нативный паттерн Apple с SF Symbol + текстом. |
| Toast после clone (`sonner`) | `TransientStatusBanner` через `NotificationCenter.default.publisher(for: .shoppingStatusMessage)` | Переиспользуется существующий в `AppShellView` компонент. |
| `dangerouslySetInnerHTML` для HTML description | `DiscoverDescriptionText.htmlToPlainText` + `AttributedString(markdown:)` | Curated recipes приходят с сервера как HTML; iOS конвертирует в plain text → markdown (параграфы через `\n\n`, списки через `\n`). |
| `ViewOnlyIngredientsBlock` с `Stepper` | `Stepper(value: $scaleFactor, in: 0.25...50, step: 1)` + per-row `formattedAmount(amount * scaleFactor)` | Логика идентична вебу; UI — нативный `Stepper`. |
| Share-mode badge (`one_by_one` / `all` / `with_images_and_steps`) | `ShareModeBadge` (Capsule с secondary background) | Без изменения функциональности — только индикатор. |
| Hero image (responsive, max-h-[600px]) | `AsyncImage(url:).scaledToFit().clipShape(RoundedRectangle)` | URLCache дефолтный, без persistent disk cache. |

## Визуальные отличия от веба

- **Нет** кастомного sticky header на detail-экранах — используется стандартный `navigationTitle` + системный back-button. Это экономит код и соответствует iOS-конвенциям.
- **Картинки в гриде** — без progressive loading skeleton, только `AsyncImage` с placeholder (SF Symbol `photo` + tinted background из `recipe.color`).
- **Аватары** — circular, 40pt в списке и 56pt в шапке профиля.
- **Servings scaler** — Stepper в inline-режиме (только кнопки `−`/`+` справа от заголовка «Ingredients»), без текстовой надписи.
- **Recipe description** — плоский markdown-рендеринг (без Tiptap-стилей), читабельность приоритетнее визуального паритета с веб-статьями.

## Тестирование (на симуляторе)

```bash
# Smoke (билд + launch с открытым Discover-табом + скриншот)
scripts/verify-discover-public.sh

# Regression (все экраны, чтобы убедиться что ничего не сломалось)
scripts/verify-all.sh
```

Launch args для дебага: `-OpenTab=discover` (открывает Discover-таб сразу), `-SkipSplash=1` (пропускает сплэш).

## i18n

Все строки — в `RecipeScalerNative/Resources/Localizable.xcstrings`, namespace `discover.*`. Прогон `scripts/typograf-xcstrings` обязателен после редактирования русских строк (типографика кавычек, неразрывные пробелы).

Smoke-тест ключей — `RecipeScalerNativeTests/LocalizationConsistencyTests.swift::testCriticalKeysResolveInBothLanguages()`.

## Что НЕ сделано (вне scope 017)

- Universal links / deep links на `/discover/*` и `/public/@/*` → спека 012.
- Редактирование своего public profile → спеки 013/020.
- PDF cookbook export → отложено.
- Persistent offline-first кэш Discover images → URLCache достаточно.
- Аутентичный Tiptap-рендеринг HTML description → используется plain-text fallback.
