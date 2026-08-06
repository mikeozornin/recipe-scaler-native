# App Store screenshots

Сырые кадры 6.9″ (без рамок) для App Store Connect. Спека: [`specs/060-app-store-screenshots/`](../specs/060-app-store-screenshots/spec.md).

## Собрать fixtures

```bash
python3 scripts/curate-store-fixtures.py \
  --input ~/Downloads/recipe-scaler-2026-08-05T11-55-40-294Z.zip
```

Пишет `store/fixtures/recipes-ru.zip` и `recipes-en.zip` (11 рецептов с фото, metadata v1.4). В EN-zip имена, ингредиенты **и шаги** на английском. Папки из исходного export не переносим: в zip нет membership рецепт→папка.

## Постоянные аккаунты

Один юзер на локаль съёмки + копия EN для App Review. Seed-фразы: [`store/fixtures/users.yaml`](fixtures/users.yaml).

```bash
python3 scripts/store_users.py provision          # один раз (или --force)
python3 scripts/store_users.py show
bash scripts/bootstrap-store-libraries.sh         # импорт zip + shopping на этих юзеров
```

| Ключ | Назначение | Контент |
|------|------------|---------|
| `ru` | скриншоты RU | `recipes-ru.zip`, публичный профиль `@mikeozornin-ru-scr` |
| `en` | скриншоты EN | `recipes-en.zip`, публичный профиль `@mikeozornin-en-scr` |
| `app-store-review` | отдать Apple в ASC | копия EN-библиотеки, отдельный seed |

Не использовать shared debug-user (`f088233a-…`). Capture больше не вызывает `register-auto`.

## Снять кадры

```bash
bash scripts/capture-app-store-screenshots.sh
bash scripts/capture-app-store-screenshots.sh --locale ru --appearance light
bash scripts/capture-app-store-screenshots.sh --shot 07 --shot 08 --skip-build
bash scripts/validate-app-store-screenshots.sh
```

Нужен симулятор **iPhone Air** или **iPhone 17 Pro Max** и доступ к `https://recipe-scaler.ru` (login-with-seed + Discover). Если сима нет, скрипт создаёт iPhone Air на свежем iOS runtime.

**Не запускайте два capture параллельно** — скрипт берёт mkdir-lock `.capture-screenshots.lock.d` (Home/Lock/таймеры конфликтуют).

Скрипт сам:
- переключает **локаль ОС** (`AppleLanguages` / `AppleLocale` + bounce SpringBoard), чтобы lock-screen дата и относительное время пуша были `сейчас`/`now` по языку кадра;
- после Lock **тапает экран**, чтобы Live Activity снималась с секундами (`MM:SS`), а не в AOD-compact (`44m`);
- для пуша ждёт короткий таймер (по умолчанию 6 с), без минутных опросов.

Выход: `store/screenshots/iphone-6.9/{ru,en}/{light,dark}/0N-*.png`  
Размер PNG: `1260×2736` (Air) или `1320×2868` (Pro Max). PNG в git не коммитим.

## Загрузка в App Store Connect

1. Media Manager → **iPhone 6.9" Display** (не 6.5″). 6.5″ нужен только если 6.9″ нет.
2. На каждую локаль listing (`Russian`, `English`) — 8 PNG из `light/` (по умолчанию). Dark — запасной набор рядом.
3. Порядок файлов = номер префикса `01`…`08`.
4. Виджет на Springboard симулятор сам не ставит: кадр `06-widget` свайпает **вправо до последней страницы** Springboard (не Today слева). Виджет нужно добавить вручную один раз именно туда.
5. App Review: в ASC Demo Account укажите seed из `users.yaml` → `app-store-review` (вход по seed phrase).

## Гейты релиза

- **iPhone-only:** `TARGETED_DEVICE_FAMILY = 1` у main app / iOS extensions. Иначе ASC потребует iPad-скрины.
- **Watch v1:** не шипим companion. Перед Archive снимите Embed Watch App у `RecipeScalerNative`. Local Debug dual-sim может оставить embed.
- **Debug chrome:** на кадрах нет seed, splash, DB-init banner, feature-adoption оверлеев.

## Чеклист кадра

- Status bar 9:41, полный заряд
- Нет seed phrase / debug smoke UI
- EN-кадры без русских названий, ингредиентов и шагов
- Кадр `01-recipes`: плоский список, не пустой, без системных алертов
- Кадр `02-cooking`: развёрнутая панель таймера + баннер «не гасить экран» + scale ≠ 1
- Кадр `07-live-activity`: lock screen awake, LA видна (не `44 : --`); дата ОС на языке кадра. Крупные цифры часов на Lock Screen у текущего runtime сима часто игнорируют `status_bar override` (wall clock) — ограничение Simulator.
- Кадр `08-push`: баннер виден; относительное время `сейчас` (ru) / `now` (en)
