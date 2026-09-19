# Quickstart: 075 hands-free scroll

Ручной прогон после кода. Автоматический VERIFIED по camera — только device.

## Подготовка

1. iPhone 13 Pro (TrueDepth) + длинный рецепт (20+ шагов / длинное описание).
2. Debug build, залогиненный пользователь, карточка рецепта.
3. First-run: удалить приложение или сбросить `awakeHandsFreeVoiceEnabled` / `Hand` / `Face` (и старый `awakeHandsFreeEnabled`).

## Awake без каналов

1. Открыть карточку → toolbar `play.circle.fill` ON.
2. Баннер keep-awake, справа ellipsis, **без** иконок каналов.
3. **Ожидание:** нет системного prompt mic/camera/speech; нет green camera dot.
4. Ручной скролл пальцем работает.

## Sheet

1. Ellipsis → sheet «Управление без рук» (не Menu из двух пунктов).
2. **Ожидание:** intro, energy, три тумблера OFF. На 13 Pro есть «лицо». Нет второй toolbar-кнопки.
3. Шрифты — Martian, не SF.

## Голос

1. Включить «Голосовое управление», разрешить mic + speech.
2. **Ожидание:** в баннере `waveform`; под тумблером чипы; **нет** camera dot.
3. Сказать «вниз» — ~¾ экрана; чип «вниз» зелёный коротко.
4. У конца — clamp. «Стоп» — нет скролла.

## Жесты XOR лицо

1. Включить жесты (камера). **Ожидание:** лицо выключилось; banner hand glyph; like/dislike 64.
2. Thumbs-up вверх/вниз — один fire, иконка зелёная.
3. Включить лицо: жесты OFF; `face.smiling`; моргнуть левым (up) / правым (down).
4. На устройстве без TrueDepth: ряда «лицо» нет; жесты доступны.

## Denied

1. Запретить mic, включить голос.
2. **Ожидание:** тумблер OFF и disabled, оранжевая подпись, «Открыть параметры». Нет listening.
3. Settings → grant → вернуться: тумблер enabled OFF; включить снова — работает.

## Выключения

1. Снять голос, жесты оставить: speech off, camera жива, баннер на месте.
2. `play.circle.fill` OFF: баннер исчез, камера off, prefs каналов **kept**.
3. Снова awake: иконки каналов и arm по prefs, без лишнего prompt если granted.
4. «Начать готовить» (074): на матрице нет HF preview/dot.
5. Home: камера off.

## Регрессии

- Edit description + клавиатура: caret-scroll жив.
- Assistant sheet: камера HF off на время sheet.

## Неуспех

Если awake ON без каналов даёт permission dialog или camera dot — **FAILED**, не ship.
