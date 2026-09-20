# Layout: Hands-free scroll при keep-awake

**Spec**: [spec.md](./spec.md)  
**Figma**: `rVzFwMDS5SECfIq4HRLHya` · секция [Hand free `404:4872`](https://www.figma.com/design/rVzFwMDS5SECfIq4HRLHya/recipe-scaler-files?node-id=404-4872)  
**Аудит**: [layout-audit.json](./layout-audit.json)

> Rev 4: единый sheet настроек+справки; иконки каналов в баннере; без `Menu` из двух пунктов.  
> Шрифты макета — SF Pro из UI Kit. **Не копировать**: только Martian через `.appBody()` / `.appHeadline()` / `.appFootnote()` / `.localizedNavigationTitle`.  
> Черновик для **ревью человеком** перед правками banner/sheet.

---

## Canvas

Тот же portrait (и iPad) recipe detail, что `YDocRecipeDetailView`. Sheet — системный large detent поверх карточки.

| Параметр | Значение | Figma |
|----------|----------|-------|
| Scroll host | основной `ScrollView` карточки | — |
| Awake control | toolbar `ScreenAwakeToggle` (`play.circle.fill`) | без изменений |
| Banner | sticky top `ScreenAwakeStatusBanner`, height 44 (допуск +4) | не в этой секции Figma |
| Banner trailing | ellipsis **кнопка** → sheet | spec F1.3–F1.4 |
| Banner channel icons | после title, до ellipsis | spec F1.7 |
| Sheet | `.sheet` large detent, grabber 60×4, top radius системный | `404:3351` и варианты |
| Sheet content width | full; horizontal pad **16** | все кадры |
| HF chrome | optional 48○ camera preview overlay | не в Figma 404; оставить как rev 3 |

**Критично:** не добавлять вторую toolbar-кнопку. Keep-awake — `play.circle.fill`. Не `Menu` Hands-free + Help. Preview не через `safeAreaInset`. Title баннера и иконки каналов — соседи по HStack, не overlay-колонка на весь баннер.

### Figma frames (sheet)

| Node | Имя / роль |
|------|------------|
| `404:4872` | секция «Hand free» (все состояния) |
| `404:3351` | все каналы OFF |
| `404:3179` | голос+лицо idle |
| `404:3270` | голос+жесты idle |
| `404:3818` | голос live (чип «вверх») |
| `404:3923` | жесты live (like) |
| `404:3713` | лицо live (правый глаз) |
| `404:4092` | permissions denied + «Открыть параметры» |

---

## Токены

Файл: `RecipeScalerNative/Views/AwakeScrollLayout.swift`

| Token | Значение | Зачем |
|-------|----------|--------|
| `scrollViewportFraction` | 0.75 | engine |
| `bannerAccessorySize` | 16 | ellipsis glyph |
| `bannerAccessoryHit` | 44 | hit ellipsis |
| `bannerAccessoryGap` | 8 | pulse ↔ текст, ellipsis |
| `bannerTitleIconGap` | 6 | текст баннера ↔ иконки каналов |
| `bannerChannelIconSize` | 16 | waveform / hand / face в баннере |
| `bannerChannelPulseScale` | 1.8 | scale при fire канала |
| `bannerChannelPulseDuration` | 0.5 s | easeInOut туда и обратно |
| `cameraPreviewDiameter` | 48 | overlay |
| `cameraPreviewTrailingPad` | 16 | bottomTrailing |
| `cameraPreviewBottomPad` | 16 | над home indicator |
| `helpSheetHorizontalPad` | 16 | Figma content inset |
| `helpSheetSectionGap` | 8 | gap между intro / toggle-секциями |
| `helpSheetTopPad` | 16 | content ниже toolbar |
| `helpIntroRowMinHeight` | 66 | intro + energy |
| `helpToggleRowHeight` | 52 | Regular row |
| `helpDeniedRowMinHeight` | 68 | Tall row (title + subtitle) |
| `helpEnergyGlyphSize` | 22 | декоративный switch в energy hint |
| `helpChipHeight` | 34 | голосовые чипы |
| `helpChipHorizontalPad` | 11 | inset текста чипа |
| `helpChipGap` | 8 | wrap gap |
| `helpTryHintHeight` | 22 | «Попробуйте сказать/показать» |
| `helpGestureIconSize` | 64 | like/dislike и глаза |
| `helpGestureRowHeight` | 96 | 16 + 64 + 16 |
| `helpDebugFiredDuration` | 0.8 | длительность accent live |

Шрифты:

| Роль Figma | В приложении |
|------------|----------------|
| Title3/Emphasized 20 sheet title | `Text` + `AppTypography.title3`, wrap |
| Body/Regular intro | `.appBody()` |
| Headline/Regular toggle title | `.appHeadline()` |
| Body try-hint | `.appBody()` |
| Chip label | `.appFootnote()` |
| Subheadline denied | `.appFootnote()` + orange |
| Settings button | `.appBody()` + tint `accent` |

Цвета live: idle chip — tertiary fill (`Color.secondary.opacity(0.12)` ≈ Figma chip); fired chip — `Color.green` fill, белый текст; fired glyph — `Color.green`; denied subtitle — `Color.orange`. Toggle ON — системный green switch, не кастомный tint баннера.

Ellipsis **не** `AppToolbarStyle.iconOnly`. В баннере: `AppSymbol.image("ellipsis")` 16 pt, цвет `bannerText`.

---

## State: Awake OFF

Без изменений. Нет баннера, нет sheet, нет preview.

---

## State: Awake ON — каналы OFF (default)

### Дерево

```text
YDocRecipeDetailView
├─ toolbar: ScreenAwakeToggle (ON)
├─ ScreenAwakeStatusBanner                  // height 44…48
│    └─ HStack spacing bannerAccessoryGap (8)
│         ├─ Circle 8×8 (pulse)
│         ├─ HStack spacing 6
│         │    └─ Text recipe.awake-scroll.banner
│         ├─ Spacer minLength 0
│         └─ Button ellipsis
├─ ScrollView (recipe)
└─ (нет camera preview)
```

### Размеры

| Элемент | W×H | Примечание |
|---------|-----|------------|
| Banner | full × 44 (+4) | иконки каналов не форсируют wrap title |
| Title | flexible, compress | `.lineLimit(1)` |
| Ellipsis visual | 16×16 | trailing |
| Ellipsis hit | ≥44×44 | HIG |

---

## State: Awake ON — каналы ON

То же дерево, плюс:

```text
HStack spacing 8
├─ pulse 8×8
├─ HStack spacing 6 (hug)
│    ├─ Text recipe.awake-scroll.banner
│    ├─ waveform 16×16                 // если voice ON
│    ├─ hand glyph 16×16               // если hand ON
│    └─ face.smiling 16×16             // если face ON
├─ Spacer
└─ Button ellipsis
overlay bottomTrailing: CameraPreview 48○
```

Порядок иконок фиксирован: голос → жесты → лицо; выключенные **пропускать** (не пустые слоты). Цвет = `bannerText`.

---

## State: Permission denied (баннер)

Баннер как Awake ON. Иконок канала нет (snap-off pref). Preview нет. Sheet объясняет отказ.

---

## State: Help / settings sheet

Системный `.sheet`, large detent, grabber. Заголовок `recipe.awake-scroll.help.title` — **в контенте**, Martian title3 20, перенос строк, без обрезки. Navbar и Close нет; dismiss — grabber / swipe.

Типографика: **не** SF. Sheet скроллится при XXXL / длинных RU.

### Дерево (канон `404:3351` + условные секции)

```text
Sheet
├─ grabber 60×4
└─ ScrollView
     └─ VStack alignment leading, spacing 8, pad H 16, top 16
          ├─ Text title                         // title3 20, wrap, .isHeader
          ├─ Text intro                         // minHeight 66, .appBody()
          ├─ HStack spacing 8                   // energy, minHeight 66
          │    ├─ AppSymbol switch.2 22×22      // декоративный, не интерактивный
          │    └─ Text energy hint              // .appBody() / footnote, wrap
          ├─ channel Voice
          │    ├─ HStack toggle row 52
          │    │    ├─ Text title .appHeadline()
          │    │    └─ Toggle
          │    ├─ (denied) Text orange footnote // row → min 68
          │    └─ (ON && granted) live voice block
          │         ├─ Text try-hint 22
          │         └─ Wrapping chips 34h, gap 8
          ├─ channel Hand                       // то же
          │    └─ (ON && granted) live hand block
          │         ├─ Text try-hint
          │         └─ HStack 2× 64 icons, row 96, equal width
          ├─ channel Face                       // скрыть, если нет TrueDepth
          │    └─ (ON && granted) live face block — два глаза 64
          └─ (если ≥1 permission denied)
               Button settings                  // 52h, leading, accent
```

**Критично:** live-блоки **не** соседи, делящие ширину с тумблером. Тумблер — полная ширина row 52; live — **следующий** блок на всю ширину контента (Figma: чипы и иконки ниже switch). Energy glyph **не** наследует ширину intro-текста.

### Чипы голоса

RU (locale): `вверх` · `выше` · `прокрути вверх` · `вниз` · `ниже` · `прокрути вниз`  
EN: `up` · `higher` · `scroll up` · `down` · `lower` · `scroll down`

Idle: нейтральный fill, primary label. Fired 0.8 s: green fill, white label, только совпавший чип (Figma `404:3818`).

### Жесты / лицо live

Idle: primary/label fill. Fired: `Color.green` на **одной** иконке (`404:3923` like; `404:3713` глаз). Сосед остаётся idle. Лицо: слева вверх, справа вниз.

Sheet **не** teardown: проверка идёт при открытом sheet.

### Denied `404:4092`

- Toggle OFF (snap-off).
- Figma: `isEnabled=False` — **disabled**, пока permission этого канала denied. После grant в Settings тумблер снова enabled и OFF; пользователь включает сам.
- Orange subtitle под title (mic vs camera).
- «Открыть параметры» если denied хотя бы mic **или** camera.
- Face-ряд на non-TrueDepth не показывать даже в denied (нет тумблера).

### SwiftUI notes

- `Toggle` системный, не кастомный switch.
- Чипы: `FlowLayout` / wrap; не горизонтальный scroll, который прячет «прокрути вниз».
- Не `.font(.system`.
- Не `List` insetGrouped с серыми карточками: Figma — плоский белый sheet, 16 pt insets, без separators-обязательности. Допустимы скрытые separators.

---

## Примитивы

| Примитив | Файл | Ответственность |
|----------|------|-----------------|
| `AwakeScrollLayout` | `AwakeScrollLayout.swift` | токены |
| Banner chrome | `ScreenAwakeStatusBanner` | pulse, title, channel icons, ellipsis Button |
| `AwakeScrollHelpSheet` | `AwakeScrollHelpSheet.swift` | intro, 3 тумблера, live, denied, settings |
| Voice chips | тот же sheet / маленькая View | wrap + fired color |
| Gesture/face icons | тот же sheet | 64 pt, fired color |
| `AwakeScrollCameraPreview` | optional | 48○ overlay |
| `DetailScrollViewProbe` | рядом | weak UIScrollView host |

---

## Матрица приёмки

| State | Light | Dark | Edge |
|-------|-------|------|------|
| Awake off | ☐ | ☐ | нет баннера, нет preview |
| Awake on, каналы off | ☐ | ☐ | ellipsis; нет иконок каналов; нет camera dot |
| Voice ON | ☐ | ☐ | `waveform` в баннере; чипы на sheet |
| Voice live chip | ☐ | ☐ | только совпавший чип зелёный 0.8s |
| Hand ON | ☐ | ☐ | banner hand glyph; 64 like/dislike |
| Face ON (TrueDepth) | ☐ | ☐ | `face.smiling`; два глаза |
| Нет TrueDepth | ☐ | ☐ | нет ряда «лицо» |
| XOR hand→face | ☐ | ☐ | hand OFF, face ON, одна камера |
| Camera preview | ☐ | ☐ | 48○, SE home indicator clear |
| Denied | ☐ | ☐ | orange captions, disabled OFF, Settings |
| XXXL sheet | ☐ | ☐ | scroll, чипы wrap |
| Cooking cover | ☐ | ☐ | нет preview поверх матрицы |

---

## Falsifiable claims

1. **Claim:** Один voice/gesture down сдвигает contentOffset на 0.75×`bounds.height` (±1 pt) пока не clamp.  
2. **Claim:** При awake ON и всех каналах OFF нет AVCapture session (нет green camera dot). Voice-only — тоже нет camera dot.  
3. **Claim:** Camera preview 48 pt overlay; высота ScrollView не меняется.  
4. **Claim:** Нет новой toolbar button кроме `play.circle.fill`.  
5. **Claim:** Ellipsis в баннере справа; высота баннера ≤ 48 pt; это Button, не двухпунктный Menu.  
6. **Claim:** Sheet открывается ellipsis, не toolbar.  
7. **Claim:** После title баннера видны только иконки каналов с pref true, порядок voice→hand→face, 16 pt.  
8. **Claim:** Live: меняется цвет одного чипа или одной 64 pt иконки, не всего ряда.  
9. **Claim:** Denied: тумблер OFF+disabled, orange caption, Settings если ≥1 denied.  
10. **Claim:** Sheet и баннер без `.font(.system`.  
11. **Claim:** Face-ряд отсутствует, если TrueDepth unsupported.

---

## Platform constraints

- UIScrollView через probe.  
- Front camera green dot пока Hand/Face armed.  
- Face XOR Hand — пользовательские тумблеры, не auto TrueDepth.  
- `hand.thumbsdown.hand.thumbsup.filled` есть в SF Symbols 8, **не** гарантирован на iOS 17. Канон баннера: этот symbol, если `UIImage(systemName:)` ≠ nil; иначе fallback `hand.thumbsup.fill` (один глиф, не пустой слот). Sheet like/dislike: `hand.thumbsup.fill` / `hand.thumbsdown.fill` (iOS 17).  
- Banner VoiceOver: ellipsis `recipe.awake-scroll.menu`; иконки каналов — accessibility elements с существующими `help.icon.*` или отдельными banner keys.  
- Sheet VoiceOver: каждый тумблер + Settings button.

---

## Stub data

Long recipe (20+ steps) для 75% verification.  
Banner SE: длинная RU `common.screen-always-on` + 3 иконки + ellipsis.  
Sheet previews: all-off; voice+hand idle; voice fired chip; hand fired; face fired; denied; Dynamic Type accessibility5.

---

## Changelog

| Дата | Изменение |
|------|-----------|
| 2026-09-14 | Rev 1 cook-matrix HF chrome |
| 2026-09-14 | Rev 2 pivot: awake-linked scroll ±75% |
| 2026-09-19 | Rev 3 help debug icons |
| 2026-09-19 | Rev 4 Figma `404:4872`: settings+help sheet, banner channel icons |
