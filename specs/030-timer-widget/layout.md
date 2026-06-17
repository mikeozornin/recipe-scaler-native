# Layout: TimerWidget (Home Screen + accessory)

**Spec**: [spec.md](./spec.md)  
**Figma**: `rVzFwMDS5SECfIq4HRLHya` · `107:207` light · `107:266` dark · `107:332` monochrome (accessory)

---

## Canvas (`systemSmall`)

| Параметр | Значение |
|----------|----------|
| Widget | 169×169 pt |
| Padding | 16 pt |
| Content area | **137×137** pt |
| Grid gap (между ячейками / рядами) | 12 pt |

---

## Токены

Файл: `HomeWidgetExtension/Views/WidgetTimerLayout.swift`

| Token | Значение | Figma |
|-------|----------|-------|
| `contentSize` | 137 | 169 − 2×16 |
| `gridGap` | 12 | gap |
| `ringTrackSize` | 56 | path diameter |
| `ringStrokeWidth` | 6 | stroke centered on path |
| `linearBarMaxWidth` | 89 | 137 − 8 − 40 |
| `linearBarToTimeGap` | 8 | bar → time |
| `linearTimeWidth` | 40 | time column |
| `linearTimeOffsetY` | −7.5 | time above 4pt bar |
| `linearNameLineHeight` | 18 | label line |
| `linearNameMaxLines` | 3 | label |
| `twoTimerLabelHeight` | 54 | 3×18 |
| `twoTimerRowHeight` | 62 | 4 + 4 + 54 |
| `trackOpacity` | 0.24 | linear/ring track |

Шрифты: `HomeWidgetExtension/Views/WidgetFonts.swift` — Martian, tracking −0.1.

---

## State: 1 timer (Figma `107:238`)

| Элемент | Размер | Примечание |
|---------|--------|------------|
| Ring | 56 pt path, 6 pt stroke | track + arc **один диаметр** |
| Label block | 137×54 | top-aligned под кольцом, gap 12 |

```text
VStack (137×137, topLeading)
├─ Ring 56×56 row
└─ Label 137×54 (recipeNameText + fixedSize + frame)
```

---

## State: 2 timers (Figma `107:318`)

| Элемент | Размер | Примечание |
|---------|--------|------------|
| Row | 137×62 | два ряда + gap 12 = 136 ≤ 137 |
| Bar | 89×4 | только левая колонка |
| Time | 40 pt | **overlay** top-trailing, offset −7.5 |
| Label | **137×54** | под bar, **полная ширина под time** |

```text
Row (137×62) — Color.clear anchor
├─ overlay topLeading: bar 89×4
├─ overlay topLeading + pad-top 8: label 137×54
└─ overlay topTrailing: time 40pt
```

**Критично:** label **не** в одной колонке с bar (не 89pt). Текст переносится на **137pt**.

### SwiftUI / WidgetKit

- Label: `WidgetFonts.recipeNameText` + `.fixedSize(horizontal: false, vertical: true)` + `.frame(width: 137, height: 54)` — как `singleTimerState`.
- **Запрещено:** `UIViewRepresentable` / `UILabel` в extension (WidgetKit не рендерит).
- **Запрещено:** `ZStack` bar+label без overlay — ломает wrap.
- **Запрещено:** `maxHeight: .infinity` на row.

---

## State: 3–4 timers (Figma `107:208` / `107:221`)

Grid 2×2, ring 56 path, digit 15 pt, gap 12.

---

## Accessory (Figma `107:332`)

Monochrome: `.primary`, `widgetAccentable`, track скрыт, vibrant clear background.

---

## Примитивы

| Примитив | Файл |
|----------|------|
| `WidgetTimerLayout` | tokens |
| `WidgetTimerPalette` | color/mono |
| `WidgetTimerRing` | 1/3/4 timers |
| `WidgetTimerLinearRow` | 2 timers |
| `WidgetTimerFormatting` | compact time |

---

## Матрица приёмки

| State | Light | Dark | Mono | Edge data |
|-------|-------|------|------|-----------|
| 0 empty | ☐ | ☐ | ☐ | — |
| 1 ring | ☐ | ☐ | ☐ | длинное имя 3 строки |
| 2 linear | ☐ | ☐ | ☐ | exceeded + running, **одинаковый wrap** |
| 3 rings | ☐ | ☐ | ☐ | soon/exceeded |
| 4 rings | ☐ | ☐ | ☐ | — |
| accessory circular | — | — | ☐ | |
| accessory rectangular | — | — | ☐ | |
| accessory inline | — | — | ☐ | |

---

## Falsifiable claims

1. **2 timers, long names:** оба ряда переносят на **2 строки** на ширине 137pt, **без** `…`; первая строка уходит **под** time (`-16m` / `9h`).
2. **Ring:** track и progress на **одном** диаметре 56pt, stroke 6pt.
3. **Exceeded:** красный accent, отрицательное время (`-Nm` / `-Ns`).
4. **Hours:** при h>0 только `Nh` (без `Nm`), если не влезает.
5. **Mono accessory:** без цветных track, только `.primary`.

---

## Stub data

| Сценарий | Данные | Где |
|----------|--------|-----|
| wrap regression | «10 минут длинное название» + «10 часов длинное название» | `TimerWidgetEntry.placeholderTwo`, `seed-timer-snapshot.py --two` |
| exceeded | −16m… | stub-1 exceeded |

---

## Changelog

| Дата | Изменение |
|------|-----------|
| 2026-06-17 | Черновик по итогам реализации 030 |
