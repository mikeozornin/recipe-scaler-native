# Quickstart: 075 hands-free scroll

Ручной прогон после кода. Автоматический VERIFIED по camera — только device.

## Подготовка

1. iPhone 13 Pro (TrueDepth) + длинный рецепт (20+ шагов / длинное описание).
2. Debug build, залогиненный пользователь, карточка рецепта.
3. Сбросить Hands-free: удалить приложение или `defaults` key `awakeHandsFreeEnabled` если проверяете first-run.

## Awake без Hands-free

1. Открыть карточку → toolbar `sun.max` ON.
2. Баннер «экран не гасится», справа ellipsis.
3. **Ожидание:** нет системного prompt mic/camera/speech; нет green camera dot.
4. Ручной скролл пальцем работает.

## Справка

1. Ellipsis → Справка.
2. **Ожидание:** sheet с голосом, рукой, лицом, XOR, permissions. Нет второй toolbar-кнопки.

## Hands-free ON — голос

1. Ellipsis → флажок Hands-free.
2. Разрешить mic + speech (камера — по диалогу).
3. Скачать offset визуально; сказать «вниз».
4. **Ожидание:** контент уезжает примерно на ¾ видимой области, ~25% overlap.
5. У конца рецепта повтор «вниз» — clamp, не прыжок наверх.
6. «Вверх» — обратно. Постороннее «стоп» — нет скролла.

## Жест

- 13 Pro: моргнуть левым (up) / правым (down). Не использовать обе сразу.
- Устройство без TrueDepth: thumbs-up кончиком вверх/вниз.
- **Ожидание:** один fire на жест, пауза cooldown.

## Выключения

1. Снять Hands-free, awake оставить: **green dot гаснет**, баннер на месте, экран не гаснет.
2. Снова Hands-free: **без** повторного permission, если granted.
3. `sun.max` OFF: баннер исчез, камера off.
4. Снова awake: если pref Hands-free true — arm снова.
5. «Начать готовить» (074): на матрице нет HF preview/dot от карточки.
6. Close cooking: если awake+HF — сессия может вернуться.
7. Home: камера off (существующий awake teardown).

## Регрессии

- Edit description + клавиатура: caret-scroll редактора жив.
- Assistант sheet: камера HF off на время sheet.

## Неуспех

Если awake ON без HF даёт permission dialog или camera dot — **FAILED**, не ship.
