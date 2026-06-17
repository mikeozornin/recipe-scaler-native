# Quickstart: Timer Live Activity

## Требования

- Xcode 16+, симулятор iOS 17+ (iPhone 16 Pro для Dynamic Island stub)
- Схема `RecipeScalerNative`
- Debug auto-login (см. AGENTS.md)

## Проверка на симуляторе

1. Собрать и запустить приложение.
2. Открыть v3-рецепт → запустить таймер из описания или панели.
3. Заблокировать экран (⌘L) или свайп Lock Screen.
4. Убедиться: карточка с countdown, названием шага и рецептом.
5. Pause/resume с кнопки на карточке — состояние совпадает с in-app панелью.
6. Дождаться overdue (или короткий таймер 10 с) — красный accent, без кнопки.
7. Удалить таймер в приложении — карточка исчезает.

## Light / Dark

Settings → Appearance → Light / Dark; повторить шаги 2–4. Текст и фон должны оставаться читаемыми.

## Сборка

```bash
xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  build
```

## Проверка на физическом iPhone

1. Собрать и установить через Xcode на устройство (схема `RecipeScalerNative`, не только main target).
2. Settings → Face ID & Passcode → **Live Activities** — включено глобально.
3. Settings → Recipe Scaler → **Live Activities** — включено для приложения.
4. После установки перезапустить таймер (старые сессии без extension не покажут карточку).
5. Xcode Console: фильтр `TimerLiveActivity` — при ошибке `Activity.request` будет лог.

На Personal Team App Group для pause с Lock Screen может не работать на устройстве; **отображение** карточки от App Group не зависит. Для TestFlight/App Store нужен paid Apple Developer Program.

## Troubleshooting

- Live Activity не появляется: Settings → Recipe Scaler → Live Activities (системный toggle).
- Симулятор работает, телефон нет: clean build (⇧⌘K), удалить приложение с устройства, установить заново; проверить, что `TimerLiveActivityExtension` в Embed App Extensions.
- Нет картинки рецепта: миниатюра берётся из disk cache; откройте рецепт в приложении, чтобы изображение скачалось, затем перезапустите таймер.
- Pause не работает: extension и app должны иметь один App Group entitlement.
