# Layout: Hands-free scroll при keep-awake

**Spec**: [spec.md](./spec.md)  
**Figma**: нет — минимальный chrome на существующей карточке + `ScreenAwakeStatusBanner`.  
**Аудит**: [layout-audit.json](./layout-audit.json)

> Rev 3: **нет** второй toolbar-кнопки Hands-free. Opt-in — ellipsis **внутри** баннера keep-awake + help sheet.  
> Черновик для ревью человеком перед кодом UI.

---

## Canvas

Тот же portrait (и iPad) recipe detail, что `YDocRecipeDetailView`.

| Параметр | Значение |
|----------|----------|
| Scroll host | основной `ScrollView` карточки |
| Awake control | toolbar `ScreenAwakeToggle` (`sun.max`, без изменений позиции) |
| Banner | существующий `ScreenAwakeStatusBanner` sticky top (`safeAreaInset` edge top) при awake ON |
| Banner menu | trailing ellipsis в баннере |
| Help | `.sheet` поверх detail |
| HF chrome | optional 48○ camera preview overlay, только если Hands-free armed + camera granted |

**Критично:** не добавлять вторую toolbar-кнопку Hands-free. Не менять layout матрицы 074. Preview не через `safeAreaInset`.

---

## Токены

Файл: `RecipeScalerNative/Views/AwakeScrollLayout.swift`

| Token | Значение | Зачем |
|-------|----------|--------|
| `scrollViewportFraction` | 0.75 | логика engine (дублировать в layout constants для audit) |
| `bannerAccessorySize` | 16 | ellipsis glyph в баннере |
| `bannerAccessoryHit` | 44 | минимальная hit area ellipsis (HIG), визуал 16 |
| `bannerAccessoryGap` | 8 | gap текст ↔ ellipsis |
| `bannerMaxExtraHeight` | 4 | баннер сейчас 44; после ellipsis ≤ 48 |
| `cameraPreviewDiameter` | 48 | overlay, только HF+camera |
| `cameraPreviewTrailingPad` | 16 | bottomTrailing на detail |
| `cameraPreviewBottomPad` | 16 | над home indicator |
| `helpSheetHorizontalPad` | 16 | padding body справки |
| `helpSheetSectionGap` | 16 | gap между блоками справки |
| `cooldownFlashOpacity` | 0.0 | v1 без action flash |

Шрифты баннера — как сейчас у `ScreenAwakeStatusBanner` (`.appBody()`). Справка: заголовок существующий navigation/sheet title style; body `.appBody()` / `.appFootnote()`. Не вводить `.font(.system`.

Ellipsis **не** `AppToolbarStyle.iconOnly` (это toolbar chrome). В баннере: `AppSymbol.image("ellipsis")` или эквивалент 16 pt, цвет как `bannerText` баннера.

---

## State: Awake OFF

Без изменений относительно сегодняшнего detail. Нет баннера, нет menu, нет camera preview, нет listening.

---

## State: Awake ON — Hands-free OFF (default)

### Дерево

```text
YDocRecipeDetailView
├─ toolbar: ScreenAwakeToggle (ON)          // existing, unchanged
├─ ScreenAwakeStatusBanner                  // existing sticky, height 44…48
│    └─ HStack spacing 8
│         ├─ Circle 8×8 (pulse)             // existing
│         ├─ Text common.screen-always-on   // existing, lineLimit 1, hug leading
│         ├─ Spacer minLength 0
│         └─ Menu                           // NEW
│              label: ellipsis 16×16 in 44×44 hit
│              ├─ Toggle Hands-free         // unchecked
│              └─ Button Help
├─ ScrollView (recipe)                      // existing
└─ (нет camera preview)
```

### Размеры

| Элемент | W×H | Примечание |
|---------|-----|------------|
| Banner | full width × 44 (допуск +4) | ellipsis не должен форсировать вторую строку title |
| Title | flexible, compress | `.lineLimit(1)` как сейчас; truncate если конфликт с ellipsis |
| Ellipsis visual | 16×16 | trailing, не перекрывает pulse |
| Ellipsis hit | ≥44×44 | не меньше HIG |
| Toolbar | unchanged | только один sun.max для awake |

**Критично:** title и ellipsis — соседи по HStack; ellipsis **не** в отдельной колонке, которая отнимает ширину у всего баннера через overlay-баг. Spacer между текстом и меню.

### SwiftUI notes

- `Menu` + `Toggle` (iOS 17): флажок в меню, не отдельный switch в баннере.
- Help: `.sheet` с `AwakeScrollHelpSheet`; dismiss системный grabber + Close `common.close` если в проекте так принято для informational sheets.
- Wire scroll через UIScrollView **probe**, не через лишний `ScrollViewReader` jump to id.

---

## State: Awake ON — Hands-free ON

То же дерево, плюс:

```text
└─ overlay bottomTrailing: CameraPreview 48○
       only if camera granted AND (Face or Hand) armed
       allowsHitTesting(false)
```

Toggle в меню — checked. Preview **не** inset: высота/ширина ScrollView не меняются.

---

## State: Permission denied (HF ON)

Баннер как Awake ON. Preview нет, если camera denied. Справка остаётся доступна. Опционально одна footnote-строка в баннере **не** добавлять в v1, чтобы не растить высоту: отказ объясняется в справке и системном Settings. Если всё же показывать — truncate одна строка, высота баннера всё ещё ≤ 48.

---

## State: Help sheet

### Дерево

```text
Sheet
├─ navigationTitle recipe.awake-scroll.help.title
├─ toolbar trailing: common.close (если нужен для a11y / iPad)
└─ ScrollView
     └─ VStack alignment leading, gap helpSheetSectionGap, pad 16
          ├─ section Voice: title + body (фразы RU/EN)
          ├─ section Hand: thumbs-up up/down
          ├─ section Face: blink left/right, TrueDepth
          ├─ section XOR: камера либо лицо, либо рука
          └─ section Permissions: mic/speech/camera только после Hands-free
```

Ширина: системный sheet. Не modal loop, не блокирует карточка за sheet: HF сессия может оставаться armed (справка — не teardown).

Worst-case stub: длинные RU строки Dynamic Type XXXL — sheet скроллится, баннер ellipsis не обрезается sheet'ом.

---

## Примитивы

| Примитив | Файл | Ответственность |
|----------|------|-----------------|
| `AwakeScrollLayout` | `AwakeScrollLayout.swift` | токены |
| Banner `Menu` | extend `ScreenAwakeStatusBanner` | ellipsis, toggle, help trigger |
| `AwakeScrollHelpSheet` | `AwakeScrollHelpSheet.swift` | copy справки |
| `AwakeScrollCameraPreview` | optional | 48○ overlay |
| `DetailScrollViewProbe` | рядом со scroll support | weak UIScrollView host |

---

## Матрица приёмки

| State | Light | Dark | Edge |
|-------|-------|------|------|
| Awake off | ☐ | ☐ | нет баннера, нет preview |
| Awake on, HF off | ☐ | ☐ | ellipsis виден; нет green camera dot |
| Awake on, HF on, voice | ☐ | ☐ | menu checked |
| Awake on, HF on, camera preview | ☐ | ☐ | 48○, SE home indicator clear |
| Help sheet | ☐ | ☐ | XXXL scroll |
| Camera denied | ☐ | ☐ | нет preview; scroll ручной жив |
| Cooking cover | ☐ | ☐ | нет preview поверх матрицы |

---

## Falsifiable claims

1. **Claim:** Один voice/gesture down сдвигает contentOffset на 0.75×`bounds.height` (±1 pt) пока не clamp.  
2. **Claim:** При awake ON и Hands-free OFF нет AVCapture session (нет green camera dot).  
3. **Claim:** Camera preview 48 pt overlay; scroll view frame height не меняется при появлении preview.  
4. **Claim:** Нет новой toolbar button кроме существующего sun.max.  
5. **Claim:** Ellipsis находится в баннере справа; высота баннера ≤ 48 pt.  
6. **Claim:** Справка открывается пунктом меню, не отдельной toolbar-кнопкой.

---

## Platform constraints

- UIScrollView must be reachable from SwiftUI detail via probe.  
- Front camera green dot expected while Hand/Face armed.  
- Face XOR Hand if both would need camera.  
- Banner Menu должен работать с VoiceOver: label `recipe.awake-scroll.menu`.

---

## Stub data

Long recipe (20+ steps) для manual 75% verification.  
Banner: длинная RU `common.screen-always-on` + ellipsis на SE width.  
Help sheet: полный набор секций, Dynamic Type accessibility5.

---

## Changelog

| Дата | Изменение |
|------|-----------|
| 2026-09-14 | Rev 1 cook-matrix HF chrome |
| 2026-09-14 | Rev 2 pivot: awake-linked scroll ±75%; strip cook overlays |
| 2026-09-14 | **Rev 3** opt-in: banner ellipsis (Hands-free + Help); камера не с sun.max |
