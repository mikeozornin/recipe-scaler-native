# Quickstart: TimerWidget

**Spec**: [030-timer-widget](./spec.md)
**Дата**: 2026-06-17

## Сборка

```bash
# Симулятор (без платного аккаунта)
xcodebuild \
  -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

После успешной сборки:

```bash
# Открыть симулятор и установить
open -a Simulator
xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

## Ручная проверка на симуляторе

### 1. Home Screen виджет

1. Запустить app на симуляторе: `Cmd+R` в Xcode.
2. Создать таймер из app (через рецепт или timer panel).
3. Выйти на Home Screen симулятора (`Cmd+Shift+H`).
4. Long-press на пустом месте → `+` кнопка → найти **Recipe Scaler** в галерее.
5. Выбрать **TimerWidget** в `systemSmall`.
6. Проверить:
   - Живой отсчёт работает (без rebuild).
   - Empty state: удалить все таймеры в app → виджет показывает «Таймеров нет».
   - 1/2/3/4 таймера: создать несколько → виджет обновляет layout.

### 2. Lock Screen accessory

1. На симуляторе: `Cmd+Shift+H` дважды → Settings → Wallpaper → Customize Lock Screen.
2. Добавить виджет в зону под часами:
   - `accessoryCircular` (круг с цифрой).
   - `accessoryRectangular` (имя + countdown).
3. Запустить активный таймер → Lock Screen (`Cmd+L`) → проверить живой отсчёт.
4. Проверить монохром: цветные акценты (orange/red) **не должны** появляться — всё одного цвета в vibrancy.

### 3. StandBy

1. На симуляторе iPhone 16 Pro: положить телефон горизонтально (в Xcode → Device → Rotate).
2. Включить StandBy в Settings → StandBy.
3. Запустить активный таймер → проверить accessory rendering.

### 4. Dark / Light режимы

1. Settings → Developer → Dark Appearance (или `Cmd+Shift+D` в Simulator menu).
2. Home Screen виджет должен адаптировать фон/текст.
3. Accessory families — монохром в обоих режимах.

### 5. Deep link

1. Тап на Home Screen `systemSmall` виджет → app открывается на вкладке `.recipes`.
2. Не должно быть ошибки или неоткрытого экрана.

## Автоматическая проверка

```bash
bash scripts/verify-timer-widget.sh
```

Скрипт:
- Собирает `RecipeScalerNative` схему с `HomeWidgetExtension`.
- Проверяет наличие `HomeWidgetExtension.appex` в `Products/`.
- Проверяет `NSExtensionPointIdentifier`, App Group и bundle id в бинарнике.

Повторная проверка без пересборки (после успешного `xcodebuild`):

```bash
SKIP_BUILD=1 DERIVED_DATA=~/Library/Developer/Xcode/DerivedData/RecipeScalerNative-diymkplxrwchdvgvqkoehouiygur bash scripts/verify-timer-widget.sh
```

### Seed snapshot на симуляторе (без UI)

Чтобы виджет сразу показал данные, не создавая таймеры вручную:

```bash
SIM_UDID=$(xcrun simctl list devices booted -j | python3 -c "import sys,json; d=json.load(sys.stdin); print(next(i['udid'] for r in d['devices'].values() for i in r if i.get('state')=='Booted'))")
python3 scripts/seed-timer-snapshot.py "$SIM_UDID" four   # 4 таймера
python3 scripts/seed-timer-snapshot.py "$SIM_UDID" empty   # empty state
python3 scripts/seed-timer-snapshot.py "$SIM_UDID" one    # 1 таймер
```

После seed: перезапустить app или добавить виджет на Home Screen — `TimerWidgetProvider` прочитает snapshot из App Group.

## Дебаг

- **Виджет не появляется в галерее**: проверить `HomeWidgetBundle` имеет `@main`, target membership Info.plist правильный, симулятор iOS 17+.
- **Виджет пустой / не обновляется**: проверить `TimerSnapshotStore.load()` читает из того же App Group; в main app `TimerManager` вызывает `save` на мутациях.
- **Цвета не меняются на `soon`/`exceeded`**: проверить `WidgetTimerAccent.resolve(remainingSeconds: totalDuration:)` логику в Provider.
- **Accessory всё цветное**: проверить `.widgetAccentable()` на всех элементах accessory view.

## Известные ограничения (без платного аккаунта)

- **На реальном iPhone** App Group нестабилен с бесплатным Apple ID → виджет может не получать snapshot. Симулятор работает корректно.
- **TestFlight / App Store**: недоступно.
- **Remote push для виджета**: отложено (нужен платный аккаунт + spec 023).

Подробнее: [PAID-APPLE-DEVELOPER-REQUIRED.md](../../docs/PAID-APPLE-DEVELOPER-REQUIRED.md).
