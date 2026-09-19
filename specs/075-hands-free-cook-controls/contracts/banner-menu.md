# Contract: banner chrome + settings sheet UI

**Owner**: `ScreenAwakeStatusBanner`, `AwakeScrollHelpSheet`  
**Layout**: [layout.md](../layout.md)  
**Figma**: `404:4872`

## Visibility

Баннер как сейчас: только `isScreenAwakeActive`. Ellipsis живёт только в баннере.

## Ellipsis

- Label: SF Symbol `ellipsis`, 16 pt, цвет `bannerText`.
- Это **Button**, не `Menu`.
- Action: `showingHelp = true` → sheet.
- a11y label: `recipe.awake-scroll.menu`
- a11y id: `screen_awake_banner_menu`

Запрещено: `Toggle` Hands-free в баннере/меню; `Button` Hands-free в toolbar; второй `play.circle.fill`.

## Channel icons (баннер)

После `recipe.awake-scroll.banner`, **сразу после текста** (не справа у ellipsis), hug, 16 pt, цвет `bannerText`. Только pref ON:

| Канал | Symbol | a11y |
|-------|--------|------|
| voice | `waveform` | `recipe.awake-scroll.help.icon.voice` |
| hand | `hand.thumbsdown.hand.thumbsup.filled` если доступен, иначе `hand.thumbsup.fill` | `recipe.awake-scroll.help.icon.hand` |
| face | `face.smiling` | `recipe.awake-scroll.help.icon.face` |

Порядок voice → hand → face. Пропуск выключенных без пустых слотов. При fire — scale 1.8, easeInOut 0.5 s, затем обратно.

## Sheet

- Title: `recipe.awake-scroll.help.title` — copy «Управление без рук» / EN-эквивалент. В контенте, перенос, не navbar.
- Intro + energy hint (декоративный `switch.2`, не интерактивный).
- Три тумблера (лицо скрыть без TrueDepth).
- Live-блоки только при ON && granted.
- Denied: OFF + disabled + orange subtitle; Settings button если ≥1 denied.
- Close нет: swipe / grabber.

### Copy keys (смысл; точные строки в xcstrings)

| Key | Содержание |
|-----|------------|
| `recipe.awake-scroll.help.title` | заголовок sheet |
| `recipe.awake-scroll.help.intro` | руки в тесте / голос или жесты |
| `recipe.awake-scroll.help.energy` | включать только то, чем будете пользоваться; камера ест заряд сильнее микрофона |
| `recipe.awake-scroll.voice` | «Голосовое управление» |
| `recipe.awake-scroll.hand` | «Управление жестами» |
| `recipe.awake-scroll.face` | «Управление лицом» |
| `recipe.awake-scroll.help.try-voice` | «Попробуйте сказать:» |
| `recipe.awake-scroll.help.try-hand` | показать жесты в камеру |
| `recipe.awake-scroll.help.try-face` | поморгать левым/правым |
| `recipe.awake-scroll.help.chip.up` | локаль: вверх / up |
| `recipe.awake-scroll.help.chip.higher` | выше / higher |
| `recipe.awake-scroll.help.chip.scroll-up` | прокрути вверх / scroll up |
| `recipe.awake-scroll.help.chip.down` | вниз / down |
| `recipe.awake-scroll.help.chip.lower` | ниже / lower |
| `recipe.awake-scroll.help.chip.scroll-down` | прокрути вниз / scroll down |
| `recipe.awake-scroll.help.denied.mic` | доступ к микрофону запрещён |
| `recipe.awake-scroll.help.denied.speech` | доступ к распознаванию речи запрещён |
| `recipe.awake-scroll.help.denied.camera` | доступ к камере запрещён |
| `recipe.awake-scroll.help.open-settings` | Открыть параметры |
| `recipe.awake-scroll.menu` | a11y ellipsis |

Устаревшие ключи rev 3 (`help.voice` длинный абзац, `help.camera` про auto-XOR, `hands-free` пункт меню) — не показывать в UI; удалять только отдельным i18n-таском, не в том же PR если lint требует наличие.

## Binding ownership

`isScreenAwakeActive` остаётся у `YDocRecipeDetailView`.  
Prefs каналов — `AwakeHandsFreeStorage` (три ключа). Не дублировать строковые ключи в view.
