# App Store (screenshots + listing metadata)

Скриншоты, fixtures и master-тексты listing'а для App Store Connect.

## Listing metadata (ASC API)

Мастер-копия description, subtitle, keywords и прочих текстов из ASC — для переводов и последующей загрузки локализаций.

| Путь | Содержимое |
|------|------------|
| [`manifest.json`](manifest.json) | app id, bundle id, primary locale, дата последнего pull |
| [`listing/app-info/{locale}.json`](listing/app-info/) | name, subtitle, privacy URLs |
| [`listing/versions/{version}/{locale}.json`](listing/versions/) | description, keywords, promotional text, What's New, URLs |
| [`versions-index.json`](versions-index.json) | версии в ASC (id, state, platform) |
| [`releases.yaml`](releases.yaml) | реестр shipped-релизов (теги, commit, notes) |
| [`asc.env.example`](asc.env.example) | шаблон credentials для ASC API |
| `asc.env.local` | Key ID / Issuer ID / путь к `.p8` (**gitignored**) |

### Credentials (ASC API)

Скрипты `asc-pull-app-store-metadata.py` и `asc-iap-inventory.sh` читают **`store/asc.env.local`**, если файл есть. Явный `export` в shell имеет приоритет.

| Переменная | Что это | Секрет? |
|------------|---------|---------|
| `ASC_KEY_ID` | Key ID из [Integrations → Keys](https://appstoreconnect.apple.com/access/integrations/api) | идентификатор |
| `ASC_ISSUER_ID` | Issuer ID (UUID на той же странице) | идентификатор |
| `ASC_P8_PATH` | Абсолютный путь к `.p8` private key | **да — не коммитить** |

Bootstrap: `cp store/asc.env.example store/asc.env.local` → заполнить значения.

### Pull / translate / push

```bash
python3 scripts/asc-pull-app-store-metadata.py   # read-only sync из ASC → store/listing/
bash scripts/asc-iap-inventory.sh                # read-only IAP inventory
```

What's New с 1.0.9 пишем сразу на двух языках: `store/drafts/whats-new-<version>-ru.txt` и `-en.txt` (сводка — `whats-new-<version>.md`).

Workflow перевода listing: добавить `listing/app-info/ru.json`, `listing/versions/{version}/ru.json` рядом с master (`en-GB`). Push: `python3 scripts/asc-push-app-store-version-metadata.py`.

Новые тексты listing'а пишем в `store/listing-drafts/<version>/{locale}.json`: name, subtitle, privacyPolicyUrl, description, keywords, promotionalText, marketingUrl, supportUrl. Папка в git, в отличие от `store/drafts/`. `store/listing/` остаётся зеркалом ASC и перезаписывается pull'ом.

```bash
python3 scripts/asc-push-app-store-version-metadata.py --listing store/listing-drafts/1.0.15 --check
python3 scripts/asc-push-app-store-version-metadata.py --version 1.0.15 --listing store/listing-drafts/1.0.15 \
  --whats-new ru=store/drafts/whats-new-1.0.15-ru.txt --dry-run
```

`--check` работает без ASC: проверяет лимиты (name и subtitle — 30, keywords — 100, promotional text — 170, description — 4000), запятые без пробелов и повторы в keywords. Слово, которое уже есть в name или subtitle, в keywords считается ошибкой: App Store индексирует его и так, а символы тратятся впустую. Name и subtitle меняются только после того, как версия создана в ASC; до этого скрипт останавливается с ошибкой. Новую локаль (например, `en-US`) скрипт создаёт сам. Скриншоты для неё не нужны: без своих кадров стор показывает кадры основной локали.

---

## Screenshots

Сырые кадры iPhone 6.9″ и iPad 13″ (без рамок) для App Store Connect. Спека: [`specs/060-app-store-screenshots/`](../specs/060-app-store-screenshots/spec.md).

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
| `ru` | скриншоты RU | `recipes-ru.zip`, discover shot = публичный профиль store-юзера (`@mikeozornin-ru-scr`) |
| `en` | скриншоты EN | `recipes-en.zip`, discover shot = публичный профиль store-юзера (`@mikeozornin-en-scr`) |
| `app-store-review` | отдать Apple в ASC | копия EN-библиотеки, отдельный seed |

Не использовать shared debug-user (`f088233a-…`). Capture больше не вызывает `register-auto`.

`prepare-discover` после `login` должен получать тот же Bearer (`--token`): повторный `login-with-seed` ротирует device token и симулятор стартует с уже мёртвым Bearer.

## Снять кадры

```bash
bash scripts/capture-app-store-screenshots.sh
bash scripts/capture-app-store-screenshots.sh --locale ru --appearance light
bash scripts/capture-app-store-screenshots.sh --shot 09-nutrition
bash scripts/validate-app-store-screenshots.sh
```

`validate` без `--device` проверяет оба набора, iPhone и iPad 13″; если набора iPad нет совсем, это ошибка (ASC нужны оба). Только iPhone — `--device iphone-6.9`.

Нужен симулятор **iPhone Air** или **iPhone 17 Pro Max** и доступ к `https://recipe-scaler.ru` (login-with-seed + Discover). Если сима нет, скрипт создаёт iPhone Air на свежем iOS runtime.

**Не запускайте два capture параллельно** — скрипт берёт mkdir-lock `.capture-screenshots.lock.d` (Home/Lock/таймеры конфликтуют).

Скрипт сам:
- переключает **локаль ОС** (`AppleLanguages` / `AppleLocale` + bounce SpringBoard), чтобы lock-screen дата и относительное время пуша были `сейчас`/`now` по языку кадра;
- после Lock **тапает экран**, чтобы Live Activity снималась с секундами (`MM:SS`), а не в AOD-compact (`44m`);
- для пуша ждёт короткий таймер (по умолчанию 6 с), без минутных опросов.

Выход: `store/screenshots/iphone-6.9/{ru,en}/{light,dark}/0N-*.png`  
Размер PNG: `1260×2736` (Air) или `1320×2868` (Pro Max). PNG в git не коммитим.

### iPad 13″ (spec 081)

```bash
bash scripts/capture-app-store-screenshots.sh --device ipad-13
bash scripts/capture-app-store-screenshots.sh --device ipad-13 --locale ru --shot 09-nutrition
bash scripts/validate-app-store-screenshots.sh --device ipad-13
```

Store-набор iPad — **только альбомная светлая** тема, RU и EN. Это значения по умолчанию для `--device ipad-13`; `--orientation portrait` и `--appearance dark` снимают запасные кадры, но в набор для ASC они не входят. Прогон не на весь набор (одна локаль, `--shot`, книжная или тёмная) валидацию не запускает.

Нужен симулятор «iPad Pro 13-inch (M4)» (берётся самый свежий runtime, `Scrapp…` пропускаются) или `CAPTURE_SIM_ID=<udid>`. Те же store-юзеры и fixtures, что у iPhone. Повернуть симулятор `simctl` не умеет, поэтому ориентацию держит UI-тест `StoreScreenshotOrientationSpec`: скрипт собирает его (`build-for-testing`), запускает в фоне на каждый проход, и приложение запускает сам тест (XCUIDevice поворачивает только приложение, запущенное XCTest; после `simctl launch` оно остаётся в той ориентации, в которой стартовало). Долго работающий симулятор иногда перестаёт поворачивать приложения; тогда скрипт один раз перезагружает его и повторяет запуск. Логи — `tmp/store-capture/`.

Скрипт сам:
- переводит iPad в режим многозадачности **Full Screen Apps** (Settings → Multitasking & Gestures; ключи SpringBoard `SBMedusaMultitaskingEnabled` / `SBChamoisWindowingEnabled`), иначе в углу окна виден маркер изменения размера. Прежний режим возвращается в конце, в том числе при ошибке или Ctrl-C;
- прячет баннер «импорт из буфера»: симулятор подтягивает буфер обмена Mac, и ссылка в нём давала баннер на кадре. Под флагом съёмки приложение буфер не проверяет, буфер Mac трогать не нужно;
- ждёт загрузки фото рецепта (`screenshot_media_ready`) и картинок карточек (`screenshot_discover_ready`) и перезапускает кадр, если их нет.

Кадры: `01-recipes` (список + открытый рецепт), `02-cooking`, `03-discover`, `04-shopping`, `05-assistant` (ассистент рядом с рецептом), `09-nutrition` (блок КБЖУ рядом с ингредиентами). Lock screen, виджет и пуш (`06`–`08`) на iPad не снимаем, импорт (`10`) в набор не входит.

Открытый рецепт и таймер на iPad берутся из `ipadRecipeName` / `ipadTimerName` в [`manifest.yaml`](screenshots/manifest.yaml) («Печенье с шоколадом» / «Chocolate Cookies»), рецепт ищется по названию. iPhone по-прежнему открывает `primaryRecipeName`. Чат ассистента на iPad `05` — тоже про печенье (`-ScreenshotAssistantTopic=cookies`; вопрос и ответ берутся из fixture `AssistantSessionModel.applyScreenshotAssistantFixture`, не из manifest); на iPhone остаётся чат про соус.

КБЖУ на `09` видны, только если в профиле store-аккаунта (RU и EN) включены КБЖУ: на iPad приложение сразу после запуска применяет настройку аккаунта с сервера, и съёмка её не переопределяет.

Выход: `store/screenshots/ipad-13/{ru,en}/light/landscape/0N-*.png` — 6 PNG на локаль, 12 всего  
Размер PNG: `2752×2064` (альбомная, с боковой панелью). Запасные книжные кадры — `2064×2752`, папка `portrait/`. `validate --device ipad-13` ждёт ровно 12 файлов набора; лишние PNG в `ipad-13/` (старые кадры, `portrait/`, `dark/`) считаются ошибкой — уберите их из папки перед загрузкой. PNG в git не коммитим.

Часы (два кадра: три таймера и пустой список), размер Ultra 3 `422×514`:

```bash
bash scripts/capture-watch-screenshots.sh
bash scripts/capture-watch-screenshots.sh --locale ru --appearance light --shot timers
```

Выход: `store/screenshots/watch/{ru,en}/{light}/01-timers.png` и `02-empty.png`. Тот же размер для всех локалей. PNG в git не коммитим.

## Загрузка в App Store Connect

1. Media Manager → **iPhone 6.9" Display** (не 6.5″). 6.5″ нужен только если 6.9″ нет.
2. На каждую локаль listing (`Russian`, `English`) — 8 PNG из `light/` (по умолчанию). Dark — запасной набор рядом.
3. Порядок файлов = номер префикса `01`…`08`.
4. Виджет на Springboard симулятор сам не ставит: кадр `06-widget` свайпает **вправо до последней страницы** Springboard (не Today слева). Виджет нужно добавить вручную один раз именно туда.
5. App Review: в ASC Demo Account укажите seed из `users.yaml` → `app-store-review` (вход по seed phrase).
6. Media Manager → **iPad 13" Display**: 6 PNG на локаль из `store/screenshots/ipad-13/{locale}/light/landscape/` (`2752×2064`). Порядок — по номеру префикса: `01`…`05`, затем `09-nutrition`.
7. Media Manager → **Apple Watch**: два PNG `01-timers` и `02-empty` из `store/screenshots/watch/{locale}/light/`, размер `422×514` (Ultra 3). Один и тот же размер для всех локалей.

## Гейты релиза

- **iPhone + iPad:** с spec 081 у main app `TARGETED_DEVICE_FAMILY = "1,2"` (`validate-app-store-screenshots.sh` проверяет). ASC требует кадры **iPad 13″** рядом с iPhone 6.9″ — см. «iPad 13″» выше. Расширения (Share, Action, HomeWidget, TimerLiveActivity) и ShareExtensionUI — тоже `"1,2"`, RecipeScalerCore — `"1,2,4"` (spec 081 T004).
- **Watch:** companion `RecipeScalerNativeWatch` входит в архив схемы `RecipeScalerNative` (`Watch/RecipeScalerNativeWatch.app`). ASC потребует скриншоты Apple Watch отдельно от кадров iPhone 6.9″.
- **Debug chrome:** на кадрах нет seed, splash, DB-init banner, feature-adoption оверлеев.

## Чеклист кадра

- Status bar 9:41, полный заряд
- Нет seed phrase / debug smoke UI
- EN-кадры без русских названий, ингредиентов и шагов
- Кадр `01-recipes`: плоский список, не пустой, без системных алертов
- Кадр `02-cooking`: развёрнутая панель таймера + баннер «не гасить экран» + scale ≠ 1
- Кадр `07-live-activity`: lock screen awake, LA видна (не `44 : --`); дата ОС на языке кадра. Крупные цифры часов на Lock Screen у текущего runtime сима часто игнорируют `status_bar override` (wall clock) — ограничение Simulator.
- Кадр `08-push`: баннер виден; относительное время `сейчас` (ru) / `now` (en)
