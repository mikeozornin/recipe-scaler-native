# Спецификация: скриншоты App Store

**Дата**: 2026-08-05  
**Статус**: пайплайн готов (кадры снимаются локально, PNG не в git)  
**Зависимости**: 029 (native import), 011 (Discover), 015/021 (assistant), 030 (widget), 044 (Live Activity), 023 (push)

## Контекст

Нужен воспроизводимый набор сырых (без рамок и капшенов) скриншотов для App Store Connect под сюжет [recipe-scaler.ru/about](https://recipe-scaler.ru/about) и native-фишки (виджет, Live Activity, пуш).

Источник контента: curated export только с фото (`store/fixtures/recipes-{ru,en}.zip`). Live debug-user (`f088233a-…`) для съёмки **не** использовать.

## Цель

8 кадров × `ru`/`en` × `light`/`dark` с симулятора 6.9″ (iPhone Air или 17 Pro Max). Chrome и контент на одном языке.

## Кадры

Порядок = порядок в магазине (первый кадр решает CTR).

| # | Slug | About-фича | Где снимаем |
|---|------|------------|-------------|
| 1 | `recipes` | sync / «рецепты всегда с собой» | Tab Рецепты, библиотека с фото |
| 2 | `cooking` | cooking (+ scale незаметно) | Деталка Штрудель/Strudel: wake-lock, раскрытые таймеры, **scale ≠ 1** |
| 3 | `discover` | discover | Открытая публичная коллекция (не пустой каталог) |
| 4 | `shopping` | shopping-list | Несколько позиций, часть отмечена купленной |
| 5 | `assistant` | assistant | Фикстура troubleshooting («соус свернулся»), не live LLM |
| 6 | `widget` | native | Springboard + Home Widget таймера (виджет ставится вручную один раз) |
| 7 | `live-activity` | native | Lock Screen / Dynamic Island с активным таймером (после Lock — tap wake для `MM:SS`; на AOD — compact `44m`) |
| 8 | `push` | native + cooking | Баннер уведомления о завершении таймера (OS locale = язык кадра → `сейчас`/`now`) |

**В listing copy, не на скринах:** Telegram-бот, Chrome extension, MCP, privacy/seed, PDF cookbook.

## Локали и темы

| Ось | Значения |
|-----|----------|
| Locale | `ru`, `en` |
| Appearance | `light`, `dark` |
| Итого | 8 × 2 × 2 = **32 PNG** |

Chrome (`AppLanguagePreference` + **OS** `AppleLanguages`/`AppleLocale` на симе) ≠ контент рецептов. Capture переписывает `.GlobalPreferences.plist` и баунсит SpringBoard при смене локали, иначе lock-screen дата и относительное время пуша (`сейчас`/`now`) остаются от предыдущего языка. Между `ru` и `en` — **постоянные аккаунты** (`store/fixtures/users.yaml`), не `register-auto` и не debug-user. Light/dark шарят юзера локали. Третий аккаунт `app-store-review` — копия EN-библиотеки для Apple Review.

ASC не имеет слота dark: в Connect грузим один набор на локаль (по умолчанию `light/`). Dark лежит рядом как запас.

Primary рецепт: Штрудель / Strudel (`5928ae97-2e6e-4f86-8bbc-6f0380e4ac42` в zip; после import id ремапится — открывать по имени).

## Требования

- Слот ASC: **iPhone 6.9" Display** (`1260×2736` Air или `1320×2868` Pro Max; допустим также `1290×2796`).
- Status bar: 9:41, полный заряд, Wi‑Fi.
- Seed phrase не попадает на кадры.
- PNG без alpha, &lt; 10 MB.
- Кадр #2: видны таймер, cooking banner и пересчитанные количества.
- EN-кадры без русских названий рецептов/ингредиентов на видимых экранах.

## Гейты до съёмки / первого релиза

### G1 — iPhone-only в бинарнике

`TARGETED_DEVICE_FAMILY = 1` у main app и iOS-расширений. Значение `"1,2"` заставит ASC требовать iPad-скрины неадаптированного UI.

### G2 — Watch не в v1 store

Companion (039) есть, device QA нет. В список кадров Watch не входит. **Store-архив v1 не должен эмбедить** `RecipeScalerNativeWatch`. Local Debug dual-sim по-прежнему может эмбедить Watch для QA.

Перед Archive в ASC: снять Embed Watch App у `RecipeScalerNative` (или собрать store-схему без watch). Проверка: в `.ipa`/`.xcarchive` нет `Watch/RecipeScalerNativeWatch.app`.

### G3 — Debug chrome checklist

Снимаем Debug (launch-args живут в `#if DEBUG`), но на кадре не должно быть:

- [ ] seed phrase / debug user id
- [ ] splash (используем `-SkipSplash=1`)
- [ ] banner «database init failed»
- [ ] feature-adoption бейджи / онбординг-оверлеи
- [ ] пустые плейсхолдеры загрузки вместо контента
- [ ] XCTest / `ui-testing` chrome
- [ ] debug smoke shopping UI
- [ ] системный попап разрешения уведомлений
- [ ] режим коллекций вместо плоского списка рецептов

Скрипт передаёт `-ScreenshotCapture=1` — view-код прячет перечисленный debug chrome.

## Вне scope

Рамки/капшены, App Preview video, iPad-скрины, Watch-скрины, автозаливка в ASC.

## Артефакты

- `store/fixtures/recipes-{ru,en}.zip`
- `store/fixtures/users.yaml` (seed phrases: `ru`, `en`, `app-store-review`)
- `scripts/store_users.py` / `scripts/bootstrap-store-libraries.sh`
- `store/screenshots/manifest.yaml`
- `scripts/curate-store-fixtures.py`
- `scripts/capture-app-store-screenshots.sh`
- `scripts/validate-app-store-screenshots.sh`
- `store/README.md`

## Критерии успеха

- **SC-001**: RU zip — ровно 11 рецептов с `full.webp`, metadata v1.4.
- **SC-002**: EN zip — все 11 имён, ингредиентов и description/шагов на EN (включая timer names); без кириллицы в тексте рецептов.
- **SC-003**: PNG 1260×2736 или 1320×2868 (или 1290×2796).
- **SC-004**: main app `TARGETED_DEVICE_FAMILY = 1`.
- **SC-005**: `store/README.md` описывает заливку в ASC 6.9″.
