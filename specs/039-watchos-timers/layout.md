# Layout: watchOS TimerListView

**Spec**: [spec.md](./spec.md)
**Figma**: `rVzFwMDS5SECfIq4HRLHya` · node `132:635`

> Черновик для **ревью человеком** перед реализацией view. После согласования — источник истины для приёмки и `layout-audit.json`.

---

## Canvas

watchOS 10+ покрывает прямоугольные дисплеи aspect ratio ~9:11 (НЕ квадратные).

| Параметр | Min (40mm SE 3) | Max (49mm Ultra 3) |
|----------|-----------------|--------------------|
| Screen | 162 × 197 pt | 211 × 257 pt |
| Content area | 130 × 165 pt | 179 × 225 pt |
| Padding | 16 pt | 16 pt |
| Corner radius | 37 pt | 40 pt |

Все размеры ниже — **адаптивные**, никаких fixed frame:

- `.frame(maxWidth: .infinity)` — горизонталь.
- `.frame(minHeight: 44)` — tap target HIG.
- Список скроллится Digital Crown + свайпом.

---

## Токены

Один файл: `RecipeScalerNativeWatch/Views/WatchTimerLayout.swift`

| Token | Значение | Назначение |
|-------|----------|------------|
| `padding` | 16 pt | content padding от края экрана |
| `rowMinHeight` | 44 pt | HIG tap target minimum |
| `topRowHeight` | 24 pt | action icon + progress + time полоса |
| `actionIconSize` | 19 × 24 pt | SF Symbol 20pt medium |
| `actionToProgressSpacing` | 8 pt | gap между action icon и progress |
| `progressHeight` | 2 pt | linear track + fill |
| `timeWidth` | 40 pt | Martian Mono 15pt, trailing aligned |
| `timeLineHeight` | 16 pt | line height для time |
| `progressTrackOpacity` | 0.4 | opacity для track (fill — акцентом) |
| `nameLineHeight` | 18 pt | line height для recipe name |
| `nameFontSize` | 15 pt | Martian Grotesk |
| `nameMaxLines` | 2 | lineLimit, после — ellipsis |
| `nameTracking` | −0.1 | kern |
| `stateIconSize` | 48 pt | SF Symbol для Empty/Error/NotAuthorized |
| `stateSquareMinSide` | `contentWidth` | сторона квадрата icon+text |
| `settingsHeight` | 44 pt | Settings button minimum |
| `spacingRowTopToName` | 0 pt | name идёт сразу под top |
| `spacingRowToRow` | 16 pt | вертикальный gap между rows |

### Шрифты

Переиспользуем проектные Martian (user preference: всегда Martian, не системный). На watchOS требуется bundle Martian ttf в watch target.

| Где | Шрифт | Size | Weight |
|-----|-------|------|--------|
| Action icon (List row) | SF Symbol medium | 20 pt | medium |
| State icon (Empty/Error/NotAuth) | SF Symbol | 48 pt | **medium** (Figma: SF Pro Medium 510) |
| Time | Martian Mono Nr Lt | 15 pt | light |
| Recipe name | Martian Grotesk Nr Lt | 15 pt | light |
| Empty/Error/NotAuth title | Martian Grotesk Nr Lt | 15 pt, centered | light |
| NotAuth subtitle | Martian Grotesk Nr Lt | 15 pt, centered | light |
| Settings label | Martian Grotesk (системный label) | по умолчанию | — |

### Цвета палитры

Реализуется в `RecipeScalerCore/TimerViews/TimerPalette.swift` (без WidgetKit):

| Состояние | Цвет | Условие |
|-----------|------|---------|
| `normal` | `Color.primary` (semantic) | remaining ≥ 10% duration |
| `soon` | `Color(red: 1.0, green: 0.553, blue: 0.157)` = `#ff8d28` | remaining < duration/10 и remaining ≥ 0 |
| `exceeded` | `Color(red: 0.98, green: 0.153, blue: 0.188)` | remaining < 0 |

Dark mode: система адаптирует `Color.primary`. Для `soon`/`exceeded` можно использовать слегка скорректированные варианты (parity с виджетом: `#ff8d28` light / `#ff9230` dark), но в v1 — одинаковые цвета для простоты.

---

## State: List (Figma `132:40`, `132:636`, `132:686`)

### Размеры блоков (на примере 137pt content width)

| Элемент | W×H | Примечание |
|---------|-----|------------|
| Row (2 строки имени) | full × 60 pt (24 + 36) | пример с `до золотой корочки` |
| Row (1 строка имени) | full × 42 pt (24 + 18) | пример с `выпекайте` |
| Row **minHeight** | full × **44 pt** | HIG override — если контент 42, добиваем до 44 |
| top | full × 24 pt | icon + spacer + progress + time |
| action icon | 19 × 24 pt | SF Symbol 20pt medium |
| spacer | 8 × 24 pt | фиксированный gap |
| progress | **flex-1** × 2 pt | track + fill, **не** fixed 70pt |
| time | 40 × 16 pt | Martian Mono 15pt trailing |
| recipe name | full × 18-36 pt | 1-2 строки, ellipsis |
| Settings button | full × 44 pt | внизу списка |

### Дерево (DOM)

```text
List (full content area, .listStyle(.plain) или системный)
├─ Section (implicit, без header)
│   └─ ForEach(timers) { timer in
│       TimerRow (full × min(top+name, 44))
│       ├── top (full × 24)
│       │   ├── HStack(spacing: 8)
│       │   │   ├── Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
│       │   │   │   .frame(width: 19, height: 24)
│       │   │   │   .font(.system(size: 20, weight: .medium))
│       │   │   │   .foregroundStyle(palette.color(for: timer))
│       │   │   ├── ProgressView(value: timer.progress)
│       │   │   │   .frame(maxWidth: .infinity)  // FLEX
│       │   │   │   .tint(palette.color(for: timer))
│       │   │   └── Text(timer.remaining)  // или Text(timerInterval:) для живого
│       │   │       .frame(width: 40, alignment: .trailing)
│       │   │       .font(.custom("Martian Mono Nr Lt", size: 15))
│       │   │       .monospacedDigit()
│       │   │       .foregroundStyle(palette.color(for: timer))
│       │   └── .frame(height: 24)
│       ├── Text(timer.name)
│       │   .font(.custom("Martian Grotesk Nr Lt", size: 15))
│       │   .lineLimit(2)
│       │   .truncationMode(.tail)
│       │   .frame(maxWidth: .infinity, alignment: .leading)
│       │   .foregroundStyle(palette.color(for: timer))
│       └── .frame(minHeight: 44, alignment: .topLeading)  // HIG
│           .swipeActions(edge: .leading) { Button(...) tint blue }
│           .swipeActions(edge: .trailing) { Button(role: .destructive) }
│   }
└── SettingsRow (full × 44)
    └── Button { WatchHaptics.click() } label: {
        Label("Settings", systemImage: "gear")
    }
```

### Живой countdown

Для running таймеров используем `Text(timerInterval:)`:

```swift
if let endDate = timer.endDate, !timer.isPaused {
    Text(timerInterval: Date()...endDate, countsDown: true)
        .monospacedDigit()
        .frame(width: 40, alignment: .trailing)
}
```

Для paused — статичная строка `WidgetTimerFormatting.shortClock(remaining)`.

### SwiftUI / platform notes

- `List` на watchOS автоматически даёт Digital Crown scroll и swipe-to-delete/pause.
- `.listRowInsets(.init())` для full-bleed строк (если хочется как в макете).
- **Запрещено**: `Timer.publish(every: 1)` для обновления UI — батарея. Только `Text(timerInterval:)`.
- **Запрещено**: fixed frame на progress (`width: 70` из макета) — должно быть `maxWidth: .infinity`.
- **Запрещено**: row высотой < 44pt.
- Swipe action tint: `.tint(.blue)` для leading, `role: .destructive` для trailing.

---

## State: Empty (Figma `132:758`, `132:918`)

### Размеры блоков

| Элемент | W×H | Примечание |
|---------|-----|------------|
| Квадрат icon+text | `contentWidth × contentWidth` | например 155×155 на 42mm, 179×179 на 49mm |
| Icon | full × 48 pt | SF Symbol, weight `.medium` (Figma: SF Pro Medium, weight 510) |
| Title | full × 18 pt | 1 строка centered («Таймеров нет») |
| Settings button | full × min 44 pt | sibling ниже квадрата, НЕ overlay |

### Дерево (DOM)

```text
GeometryReader { geo in
    VStack(spacing: 16) {
        Spacer(minLength: 0)
        VStack(spacing: 8) {                          // КВАДРАТ contentWidth × contentWidth
            Image(systemName: "timer")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.secondary)
            Text("watch.timer.empty.title")           // «Таймеров нет»
                .font(.custom("Martian Grotesk Nr Lt", size: 15))
                .multilineTextAlignment(.center)
        }
        .frame(width: geo.size.width, height: geo.size.width)
        Spacer(minLength: 0)
        SettingsRow()
    }
    .frame(width: geo.size.width)
}
```

**Критично**: квадрат = `geo.size.width × geo.size.width`, **не** `min(W,H)`. Ширина всегда меньше высоты на watchOS, поэтому `contentWidth` определяет сторону. Settings button — sibling в родительском VStack, не отдельный `Section` поверх квадрата.

---

## State: Error (Figma `132:922`, `132:928`, `132:934`)

### Размеры блоков

| Элемент | W×H | Примечание |
|---------|-----|------------|
| Квадрат icon+text | `contentWidth × contentWidth` | как Empty |
| Icon | full × 48 pt | SF Symbol `iphone.gen2.slash`, weight `.medium` |
| Title | full × 18 pt | 1 строка centered («Не подключено к телефону») |
| Settings button | full × min 44 pt | sibling ниже квадрата |

### Дерево (DOM)

Аналогично Empty, но title без subtitle (одна строка):

```text
GeometryReader { geo in
    VStack(spacing: 16) {
        Spacer(minLength: 0)
        VStack(spacing: 8) {                          // КВАДРАТ
            Image(systemName: "iphone.gen2.slash")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.secondary)
            Text("watch.timer.error.title")           // «Не подключено к телефону»
                .font(.custom("Martian Grotesk Nr Lt", size: 15))
                .multilineTextAlignment(.center)
        }
        .frame(width: geo.size.width, height: geo.size.width)
        Spacer(minLength: 0)
        SettingsRow()
    }
    .frame(width: geo.size.width)
}
```

### Retry behavior

В v1 — нет явной retry-кнопки. Пользователь свайпает вниз или открывает app снова → `refresh()` автоматически. Settings button всегда доступна.

---

## State: Not-authorized (не нарисован в Figma)

Строится по образцу Empty/Error (Figma-иконка `iphone.gen2.slash` — для пользователя NotAuthorized и Error семантически одно и то же: «часы не могут получить данные с телефона»). 2 строки текста.

### Размеры блоков

| Элемент | W×H | Примечание |
|---------|-----|------------|
| Квадрат icon+text | `contentWidth × contentWidth` | как Empty |
| Icon | full × 48 pt | SF Symbol `iphone.gen2.slash`, weight `.medium` |
| Title | full × 18 pt | 1 строка |
| Subtitle | full × 36 pt | 2 строки |
| Settings button | full × min 44 pt | sibling ниже квадрата |

### Тексты

- `watch.timer.not-authorized.title` — «Войдите в Recipe Scaler»
- `watch.timer.not-authorized.subtitle` — «на iPhone, чтобы видеть таймеры»

---

## SettingsRow (во всех состояниях)

| Параметр | Значение |
|----------|----------|
| Размер | full width × min 44 pt |
| Содержимое | `Label("Settings", systemImage: "gear")` |
| Скролл | скроллится вместе с List (НЕ sticky) |
| Tап | **no-op + `WKInterfaceDevice.current().play(.click)`** |
| Стиль | системный Button bordered prominent (как в макете, iOS 26 component) |

### SwiftUI

```swift
Button {
    WatchHaptics.click()  // light feedback only
} label: {
    Label(LocalizedStringKey("watch.timer.settings.label"), systemImage: "gear")
}
.buttonStyle(.borderedProminent)
.frame(maxWidth: .infinity, minHeight: 44)
.accessibilityHint(Text(LocalizedStringKey("watch.timer.settings.hint")))
.listRowInsets(.init())  // full-bleed
```

---

## Свайпы (нативный `.swipeActions`)

```swift
TimerRow(timer: timer)
    .swipeActions(edge: .leading, allowsFullSwipe: true) {
        Button {
            Task { await viewModel.toggle(timer) }
        } label: {
            Label(
                timer.isPaused
                    ? LocalizedStringKey("watch.timer.action.resume")
                    : LocalizedStringKey("watch.timer.action.pause"),
                systemImage: timer.isPaused ? "play.fill" : "pause.fill"
            )
        }
        .tint(.blue)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        Button(role: .destructive) {
            Task { await viewModel.delete(timer) }
        } label: {
            Label(LocalizedStringKey("watch.timer.action.delete"), systemImage: "trash")
        }
    }
```

| Edge | Action | Tint | Icon | Allows full swipe |
|------|--------|------|------|-------------------|
| `.leading` | toggle pause/resume | `.blue` | `pause.fill` running / `play.fill` paused | `true` |
| `.trailing` | delete | `role: .destructive` (system red) | `trash` | `true` |

**Платформа**: работает пальцем (не Digital Crown). Кнопки выезжают по мере свайпа.

---

## Haptics

| Событие | Haptic | API |
|---------|--------|-----|
| Pause (swipe) | `.click` | `WKInterfaceDevice.current().play(.click)` |
| Resume (swipe) | `.click` | то же |
| Delete (swipe) | `.success` | `WKInterfaceDevice.current().play(.success)` |
| Settings tap | `.click` (light) | то же |
| Timer expiration (foreground) | `.notification` × 3 с интервалом 0.5s | см. `WatchHaptics.timerExpired()` |

**Timer expiration в фоне** — без push не работает в v1. Документированный trade-off.

---

## Примитивы (реализовать до экранов)

| Примитив | Файл (новое место) | Источник | Ответственность |
|----------|---------------------|----------|-----------------|
| `TimerPalette` | `RecipeScalerCore/TimerViews/TimerPalette.swift` | новый (упрощённый от `WidgetTimerPalette`) | цвета `normal`/`soon`/`exceeded` для `TimerSnapshot`. Без WidgetKit. |
| `TimerFormatting` | `RecipeScalerCore/TimerViews/TimerFormatting.swift` | `HomeWidgetExtension/Views/WidgetTimerFormatting.swift` | `compactRemaining`, `shortClock`. Уже не зависит от WidgetKit. |
| `TimerFonts` | `RecipeScalerCore/TimerViews/TimerFonts.swift` | `HomeWidgetExtension/Views/WidgetFonts.swift` | Martian sans + mono. **Без UIKit** (убрать `UIFont`/`NSAttributedString`, оставить только `Font`/`Text`). |
| `TimerLinearRow` | `RecipeScalerCore/TimerViews/TimerLinearRow.swift` | `HomeWidgetExtension/Views/WidgetTimerLinearRow.swift` | строка «action icon + progress + time + name». **Без** fixed 137pt frame, `.frame(maxWidth: .infinity, minHeight: 44)`. **Без** `.widgetAccentable`. |

**Критично**: `WidgetTimerPalette` остаётся в виджете как тонкая обёртка над Core-палитрой + `WidgetRenderingMode`/`WidgetFamily`. Виджет продолжает работать как раньше.

---

## Матрица приёмки

| State | Light | Dark | Edge data |
|-------|-------|------|-----------|
| List, 1 timer | ☐ | ☐ | короткое имя 1 строка |
| List, 2 timers | ☐ | ☐ | длинное имя «до золотой корочки» 2 строки |
| List, 3+ timers | ☐ | ☐ | смесь длинных и коротких, скролл Digital Crown |
| List, exceeded | ☐ | ☐ | remaining < 0, красный |
| List, soon | ☐ | ☐ | remaining < 10% duration, оранжевый |
| List, paused | ☐ | ☐ | иконка play, статичное время |
| Empty | ☐ | ☐ | «Активных таймеров нет» |
| Error | ☐ | ☐ | 2 строки, иконка |
| Not-authorized | ☐ | ☐ | после logout на iPhone |
| Settings row | ☐ | ☐ | gear + label, tap → haptic |

---

## Falsifiable claims

1. **List row minHeight 44 pt**: любая строка таймера на 40mm SE 3 (минимальный экран) имеет высоту ≥ 44pt — измерение: accessibility frame.
2. **Progress flex**: progress bar на 49mm Ultra (контент 179pt) шире, чем на 42mm (контент 155pt), разница = 24pt — измерение: accessibility frame в preview обоих размеров.
3. **Квадрат в Empty/Error**: сторона квадрата = `contentWidth` (не высота). На 42mm квадрат = 155×155, на 49mm = 179×179 — измерение: accessibility frame в preview.
4. **Recipe name ellipsis**: имя > 2 строк обрезается `…` — измерение: accessibility string.
5. **Action icon показывает действие**: на running таймере — `pause.fill`, на paused — `play.fill` — измерение: accessibility label.
6. **Swipe tint**: leading = blue, trailing = red (system destructive) — измерение: manual / accessibility.
7. **Settings tap = no-op + haptic**: тап не меняет состояние UI, не открывает экран — измерение: accessibility state.
8. **Live countdown без Timer.publish**: countdown обновляется системой через `Text(timerInterval:)` — код: grep no `Timer.publish` в `TimerListView.swift`.
9. **Martian во всём UI**: ни одна строка не использует системный `.font(.system(...))` для текста (SF Symbol разрешён для иконок) — измерение: grep.
10. **No hardcoded i18n**: ни одной русской/английской строки в view-файлах, только `LocalizedStringKey` — измерение: grep.

---

## Stub data (preview / seed)

| Сценарий | Данные | Где |
|----------|--------|-----|
| List, 5 timers | mix running/paused, длинные + короткие имена | `#Preview` в `TimerListView.swift` |
| List, exceeded | remaining < 0, красный | `#Preview` |
| List, soon | remaining = duration/20, оранжевый | `#Preview` |
| List, paused 1+ running 1 | pause.fill + play.fill рядом | `#Preview` |
| Empty | timers = [] | `#Preview` |
| Error | state = .error | `#Preview` |
| Not-authorized | userId = nil | `#Preview` |
| Worst-case wrap | «до золотой корочки» (18 символов) | `#Preview` |

---

## Платформенные ограничения

- **watchOS 10+** (покрывает Series 4+, parity с iOS 17).
- **WKExtensionDelegate** не нужен — modern watchOS app lifecycle через `@main App`.
- **WCSession** активируется в `init()` App, не в `applicationDidFinishLaunching` (его нет).
- **Digital Crown** автоматически работает с `List`.
- **Always-On Display** (watchOS 10+) димит UI автоматически — отдельной работы нет.
- **`Text(timerInterval:)`** работает в AOD, обновляется системой.
- **NavigationStack** не нужен в v1 — один экран.

---

## Changelog

| Дата | Изменение |
|------|-----------|
| 2026-06-26 | Черновик по итогам разбора Figma `132:635` |
