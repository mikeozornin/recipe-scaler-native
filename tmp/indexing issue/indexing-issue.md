# Core Spotlight: поиск рецептов (отладка 2026-06)

Контекст: индексация рецептов в `SpotlightIndexer.swift`, логи Xcode `indexing-1.txt` … `indexing-5.txt`, debug session `13ffd6`.

## Исходная жалоба

- По запросу **«баскский»** в Spotlight не находились все рецепты, хотя в приложении — два («Баскский чизкейк», «Баскский пирог…»).
- Отдельно: превью карточки (HTML / пустое) — правили формат `contentDescription`.

## Проверено (runtime + UX)

| ID | Утверждение | Вердикт | Доказательство |
|----|-------------|---------|----------------|
| **H5** | В коллекции два названия с «баск» | **CONFIRMED** | `spotlight_reindex_tick`: `basqueNameInCollection: 2` (indexing-1/2) |
| **H1** | Рецепт не индексируется из‑за отсутствия `peekRecipeData` | **REJECTED** | Нет `spotlight_index_skip_no_peek` для `aedc31b5…` |
| **H4** | Пирог не попадает в индекс | **REJECTED** | `spotlight_index_success` для обоих id |
| **H2** | Пустой `title` при непустом `entry.name` | **CONFIRMED (fixed)** | indexing-1: `aedc31b5` — `titleSet: ""` при полном `entryName`; indexing-2 после merge — `titleSet` = полное имя, `\|v3` |
| **H10** | Spotlight ломает **расширение префикса** у **первого** слова названия | **CONFIRMED (симптомы UX)** | «баск» находит, «баскский» — нет; «имбир» находит, «имбирное» (первое слово `displayName`) — нет; подстрока **не в начале** (напр. «имбир» в «Шоколадно-имбирное», «пирог» / «чизкейк») — ок |
| **H10b** | Заливка `keywords` / префиксов / `alternateNames` / `textContent` обходит H10 | **REJECTED** | indexing-5: `titlePrefixKeywordCount: 13` для чизкейка, v6 — пользователь всё ещё воспроизвёл баг |
| **H9** | `CSSearchQuery` в приложении отражает UI Spotlight | **INCONCLUSIVE / сломан probe** | indexing-3/4/5: `q_bundle_all: 0`, при этом UI находит «пирог» / «чизкейк» — запросы probe неверны или индекс ещё не готов |

## Исправление, которое оставляем в коде

**`RecipeCollectionMerge.merged(recipe, with: entry)`** перед установкой `attrs.title` (и `displayName` без эмодзи через `RecipeTitleEmoji.displayName`).

Причина: имя может жить только в записи коллекции, Y.Map `recipe.name` пустой → Spotlight получал `title: ""` (indexing-1).

Fingerprint reindex: `previewFormatVersion = "1"` после снятия экспериментов v2–v7.

## Что пробовали и убрали (не помогло или не подтвердилось)

- `textContent`, `contactKeywords`, `alternateNames`
- Токены названия и все префиксы 2…24 в `keywords` (v6)
- Echo токенов в `contentDescription` (v7)
- `SpotlightSearchProbe` + 12 с sleep + `AgentSyncDebugLog` (topic spotlight, H1/H2/H4/H5/H9)
- Версии fingerprint v2–v7 только ради переиндексации при экспериментах

## Гипотезы на будущее (не закрыты)

1. **Лемматизация / стемминг Spotlight (ru)** для **ведущего** токена `title` / `displayName` — публичного API нет; обход только эвристиками или отказ от системного поиска для части сценариев.
2. **Минимальная длина / порог символов** для сторонних результатов (обсуждается на Apple Forums для iOS 17+) — может влиять на короткие префиксы vs полное слово.
3. **In-app search** через `CSUserQuery` / свой индекс — если нужен предсказуемый prefix search как в списке рецептов.
4. **Повторная проверка probe** с корректным query API (`queryContext`, задержка, bundle id) — чтобы отделить баг Springboard от содержимого индекса.

## Полезные id из логов

| Рецепт | recipeId |
|--------|----------|
| Баскский чизкейк | `7daed53b-5e79-42e8-bd9a-bc74deea712d` |
| Баскский пирог (длинное имя) | `aedc31b5-7772-4a58-ad1c-01e668ef7c0d` |
| Имбирное печенье с глазурью | `0d6450f4-782d-4308-984a-334abde7b247` |
| Шоколадно-имбирное печенье | `36609320-0ed9-4d95-a6c1-26328114b79d` |

## Файлы

- Индексатор: `RecipeScalerNative/Services/SpotlightIndexer.swift`
- Merge: `RecipeScalerNative/Utils/RecipeCollectionMerge.swift`
- Логи отладки: `indexing-*.txt` в корне репозитория (можно архивировать/удалить по желанию)

## Состояние на паузу

Базовая индексация + merge имени + превью из ингредиентов/HTML. Проблема **префиксного поиска по первому слову названия** в системном Spotlight **не решена**; экспериментальные обходы сняты.