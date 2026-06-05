# Типографика

Все текстовые стили определены в `AppTypography.swift` и `AppFonts.swift`. **Не хардкодь** шрифты и размеры в view-файлах — используй константы и extension-ы.

## Шрифты (AppFonts)

| Роль | Имя | Когда использовать |
|---|---|---|
| `sans` | Martian Grotesk Nr Lt | Body, footnote, subheadline — основной текст |
| `sansMedium` | Martian Grotesk Nr Md | Headline, title3, semibold-варианты |
| `display` | Martian Grotesk Std xBd | Заголовки (title2, large title) |
| `mono` | Martian Grotesk Nr Lt | Числа, код (`/connect`) |

## Размеры и стили (AppTypography)

| Стиль | Размер | Шрифт | lineSpacing | Использование |
|---|---|---|---|---|
| `body` | 16 pt | sans | 4 pt | Основной текст списков, строк рецептов, ингредиентов |
| `footnote` | 13 pt | sans | 2 pt | Подписи, badge-и, secondary-текст |
| `subheadline` | 15 pt | sans | — | Редко; prefer body |
| `headline` | 16 pt | sansMedium | — | Жирный body |
| `title3` | 20 pt | sansMedium | — | Подзаголовки |
| `title2` | 22 pt | display | — | Заголовки экранов |
| `compact` | 14 pt | sans | — | Секционные заголовки в списке |

## Text extensions (SwiftUI)

Используй вместо ручного `.font(...)` + `.lineSpacing(...)`:

```swift
Text("some key").appBody()       // 16 pt + lineSpacing 4
Text("some key").appFootnote()   // 13 pt + lineSpacing 2
```

**Почему:** гарантирует единый интерлиньяж везде. Если нужно добавить lineSpacing для нового стиля — добавь константу в `AppTypography` + `Text` extension.

**Ограничение:** `.appBody()` / `.appFootnote()` возвращают `some View`, а не `Text`. После них нельзя вызывать Text-specific модификаторы (`.textCase`, `.tracking`). Для таких случаев используй `.font(AppTypography.footnote)` напрямую (например, `AppSectionHeader`).

## View extension для List/Form

```swift
.appListBodyTypography()  // font(AppTypography.body) на весь List
```

Применяй к корневому view списка, чтобы все некастомные Text внутри наследовали body.

## Секционные заголовки

```swift
AppSectionHeader("key")       // footnote, .secondary, uppercase, tracking 0.8
AppSectionHeaderSpacer()      // невидимый placeholder для отступа
```

## UIKit chrome (AppChromeAppearance)

Глобально настраивает шрифты для NavigationBar, BarButtonItems, TabBar, UITextField, UISegmentedControl через `appearance()`. Вызывается один раз при старте приложения.

## Правила

1. **Text view** → используй `.appBody()` / `.appFootnote()` вместо ручного `.font()` + `.lineSpacing()`.
2. **Не-Text view** (SF Symbols, HStack, ZStack) → используй `.font(AppTypography.xxx)` напрямую.
3. **TextField** → не Text extension, используй `.font(AppTypography.body)`.
4. **Toggle label** → передавай `Text(...)` с `.appBody()` вместо строкового ключа.
5. **Новый стиль с lineSpacing** → добавь константу в `AppTypography` + `Text` extension, обнови `RecipeRowLayoutMetrics` если нужно.
6. Не создавай fallback вроде `t('key') || 'Default'` — см. правило i18n в `AGENTS.md`.
