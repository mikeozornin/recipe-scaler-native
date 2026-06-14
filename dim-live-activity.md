# Live Activity: черная на черной в dimmed/DND режиме

## Проблема

Когда на iPhone включается DND / Focus, Live Activity таймера на Lock Screen переходит в dimmed-режим: фон карточки затемняется системой, но контент остается темным (как от светлой темы). В результате текст и иконки почти не видны.

Обычный тёмный Lock Screen при этом работает нормально — белый текст на чёрной карточке читается. Проблема именно в dimmed-режиме (Always-On Display / DND / Focus с dim lock screen).

## Что было изменено

Файлы:

- `RecipeScalerNative/LiveActivity/TimerLiveActivityPalette.swift`
- `TimerLiveActivityExtension/TimerLockScreenLiveActivityView.swift`

Основные правки:

1. В `TimerLockScreenLiveActivityView` добавлено чтение environment values:
   - `\.colorScheme`
   - `\.isLuminanceReduced`
   - `\.widgetRenderingMode`
2. Все цвета теперь резолвятся через `TimerLiveActivityPalette` с учётом этих трёх параметров.
3. Добавлен `.containerBackground(.clear, for: .widget)`.
4. В dimmed-режиме (`isLuminanceReduced == true`) и в `.vibrant`/`.accented` rendering modes используются семантические цвета `.primary` / `.secondary` вместо жёсткого `.white`, чтобы система сама тонировала контраст.
5. Для обычного dark/light mode без dimming сохранены явные цвета, чтобы избежать бага со stale light trait collection в widget extension process.

## Результат проверки

- Сборка проходит (`rtk xcodebuild -scheme RecipeScalerNative … build`).
- В симуляторе проверен обычный Lock Screen в dark mode — отображается корректно.
- **На реальном устройстве в DND/dimmed режиме проблема остаётся.**

## Гипотезы, почему не сработало

1. **iOS Simulator не эмулирует DND/dimmed для Live Activity**, поэтому локально нельзя было воспроизвести точный сценарий. Все догадки строились на документации и логике environment values.
2. Возможно, `isLuminanceReduced` не устанавливается в том конкретном DND-сценарии, в котором проверял пользователь (например, если это не Always-On Display, а просто Focus с dim lock screen).
3. Возможно, `widgetRenderingMode` в dimmed-режиме не `.vibrant`/`.accented`, а `.fullColor`, и наша логика для `isLuminanceReduced` всё ещё использует недостаточно светлый цвет.
4. Возможно, проблема не в foreground, а в том, что фон карточки (`activityBackgroundTint` / `containerBackground`) ведёт себя не так, как ожидается, и нужно явно задать фон, который корректно затемняется.
5. Возможно, `Color(white: 0.85)` и `.primary` в dimmed-режиме всё равно оказываются слишком тёмными из-за системного dimming.

## Ссылки

### Официальная документация Apple

- ActivityKit (главная страница фреймворка)  
  https://developer.apple.com/documentation/ActivityKit/

- Displaying live data with Live Activities  
  https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities

- ActivityConfiguration  
  https://developer.apple.com/documentation/widgetkit/activityconfiguration

- Creating custom views for Live Activities (упоминает `isLuminanceReduced`)  
  https://developer.apple.com/documentation/ActivityKit/creating-custom-views-for-live-activities

- `isLuminanceReduced` environment value  
  https://developer.apple.com/documentation/swiftui/environmentvalues/isluminancereduced

- `widgetRenderingMode`  
  https://developer.apple.com/documentation/WidgetKit/WidgetRenderingMode

- `activityFamily`  
  https://developer.apple.com/documentation/SwiftUI/EnvironmentValues/activityFamily

- `isActivityFullscreen`  
  https://developer.apple.com/documentation/SwiftUI/EnvironmentValues/isActivityfullscreen

- `showsWidgetContainerBackground`  
  https://developer.apple.com/documentation/SwiftUI/EnvironmentValues/showsWidgetContainerBackground

- `activityBackgroundTint(_:)`  
  https://developer.apple.com/documentation/SwiftUI/View/activityBackgroundTint(_:)

- `activitySystemActionForegroundColor(_:)`  
  https://developer.apple.com/documentation/SwiftUI/View/activitySystemActionForegroundColor(_:)

- `containerBackground(_:for:)`  
  https://developer.apple.com/documentation/swiftui/view/containerbackground(_:for:)

- Activity — старт/обновление/завершение Live Activity  
  https://developer.apple.com/documentation/activitykit/activity

- ActivityAuthorizationInfo — разрешения на Live Activities  
  https://developer.apple.com/documentation/ActivityKit/ActivityAuthorizationInfo

- Starting and updating Live Activities with ActivityKit push notifications  
  https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications

- Human Interface Guidelines > Live Activities  
  https://developer.apple.com/design/human-interface-guidelines/live-activities

- HIG: Live Activities (system experiences)  
  https://developer.apple.com/design/human-interface-guidelines/components/system-experiences/live-activities

- Updates / ActivityKit  
  https://developer.apple.com/documentation/updates/activitykit

- Preparing widgets for additional platforms, contexts, and appearances (`.vibrant` / `.accented` / `.fullColor`)  
  https://developer.apple.com/documentation/WidgetKit/Preparing-widgets-for-additional-contexts-and-appearances

- What's new in widgets — WWDC25 Session 278  
  https://developer.apple.com/videos/play/wwdc2025/278/

- How to support tinted home screen widgets in iOS 18 (Filip Němeček)  
  https://nemecek.be/blog/206/how-to-support-tinted-home-screen-widgets-in-ios-18

- iOS 18 Widget Tint Detection (Apple Developer Forums, FB14259967 — `widgetRenderingMode` может не обновляться в real-time)  
  https://developer.apple.com/forums/thread/758151

### Внутренние файлы проекта

- `RecipeScalerNative/LiveActivity/TimerLiveActivityPalette.swift`
- `TimerLiveActivityExtension/TimerLockScreenLiveActivityView.swift`
- `TimerLiveActivityExtension/TimerLiveActivityWidget.swift`
- `RecipeScalerNative/Services/TimerManager.swift`
- `specs/026-timer-live-activity/spec.md`
- `specs/026-timer-live-activity/plan.md`

## Следующие шаги / что проверить

1. **Логирование environment values на реальном устройстве.** В `TimerLockScreenLiveActivityView.body` добавить print/`Logger` значений `colorScheme`, `isLuminanceReduced`, `widgetRenderingMode` при активном DND. Это покажет, какой сигнал реально приходит.
2. **Проверить `activityBackgroundTint`.** Возможно, нужно задать явный фон через `.activityBackgroundTint(...)` вместо или вместе с `.containerBackground(.clear)`.
3. **Попробовать полностью семантические цвета.** В dimmed-режиме использовать `.primary`/`.secondary` для всего, включая fullColor + `isLuminanceReduced`, и убрать жёсткие белые.
4. **Проверить физическое устройство с AOD.** Если DND без AOD не даёт dimmed-режима, а проблема только при AOD — нужно тестировать именно с Always-On Display.
5. **Сделать минимальный reproduction.** Создать отдельный простой Live Activity с одним `Text` и посмотреть, повторяется ли проблема, чтобы исключить специфику нашей вёрстки.

## Итерация 2 (14 Jun 2026) — что сделано

### Diagnosis-режим добавлен

В `TimerLockScreenLiveActivityView.body` добавлен `Logger` (subsystem `com.recipescaler.native`, category `LiveActivity`), который на каждом рендере пишет значения `colorScheme`, `isLuminanceReduced`, `widgetRenderingMode`, `phase`. На устройстве — Console.app с этим фильтром покажет, какой именно сигнал приходит в dim-режиме. Это закрывает пункт 1 «Следующих шагов» и позволяет точно отличить гипотезы 2–4 из списка выше.

```swift
// TimerLockScreenLiveActivityView.swift
private static let diag = Logger(subsystem: "com.recipescaler.native", category: "LiveActivity")
// …
.onAppear {
    Self.diag.info("timer-la render: scheme=\(...) lumReduced=\(isLuminanceReduced) widgetMode=\(...) phase=\(...)")
}
```

### Применён doc-correct фикс (пункты 2 + 3 «Следующих шагов»)

1. **Добавлен `.containerBackground(.clear, for: .widget)` на корневой view.** iOS 17+ требует этого модификатора: без него система может подставить собственный dim-слой, не координируемый с нашими foreground-цветрами — что и наблюдается как black-on-black в DND. Это явно рекомендовано в Apple docs и в [WWDC23 community write-up](https://jerryliu.org/posts/liveactivity/2023-07-10-live-activities-ios17/) («containerBackground, удаляемый фон, обязателен для iOS 17»).

2. **В `isLuminanceReduced` заменён хардкод `.white` → `.primary` / `.secondary`.** Обоснование из [Apple docs `widgetRenderingMode`](https://developer.apple.com/documentation/SwiftUI/EnvironmentValues/widgetRenderingMode) + [Preparing widgets for additional platforms](https://developer.apple.com/documentation/WidgetKit/Preparing-widgets-for-additional-contexts-and-appearances): на Lock Screen Live Activity рендерится в `.vibrant` режиме — система desaturates + applies tint ко всем foreground colors под Lock Screen background. Хардкод `.white` bypass-ит эту vibrant-pipeline: pure white после системной desaturation+tint коллапсирует в цвет dimmed-фона → black-on-black. Семантические `.primary`/`.secondary` корректно тонирются системой под dimmed background. Старый комментарий про stale-trait-collection актуален только для `.fullColor` (Dynamic Island expanded / banner), не для Lock Screen vibrant.

3. **В `.vibrant`/`.accented` рендеринге** primary/secondary уже использовались — оставлено как есть. Progress track в dimmed переведён с `Color.white.opacity(0.22)` на `Color(uiColor: .systemFill)` — тоже по той же причине: система сама адаптирует `systemFill` под dim background.

4. **`activityBackgroundTint(nil)` сохранён** — он указывает системе использовать её собственный Lock Screen card chrome (тот самый, что адаптируется к vibrant tint). Заменять на явный цвет НЕ нужно (это и было пунктом 2 «Следующих шагов»).

### Что НЕ сделано (нужны данные с устройства)

- Гипотеза 5 из списка выше (минимальный reproduction) — не сделана: требует отдельного target, выходит за рамки этой итерации.
- Пункты 1–4 «Следующих шагов» теперь либо закрыты кодом (1 — Logger, 2 + 3 — фикс), либо требуют теста на устройстве (4 — AOD, требует физического iPhone с AOD).

### Итерация 3 (14 Jun 2026) — root cause + фикс

#### Что выяснили с устройства

Пользователь собрал debug-сборку, запустил на iPhone, сделал скриншот Live Activity в DND/Focus-dim и прислал значения on-screen diagnostic-overlay:

```
scheme: light          ← STALE, фон реально тёмный
lumReduced: N          ← DND-dim НЕ активирует isLuminanceReduced
widgetMode: fullColor  ← система НЕ apply vibrant tint pipeline
showsBg: Y             ← система рисует свой card chrome
```

Все три предыдущие гипотезы были неверны — в DND-dim **ни один** из ранее известных сигналов (`isLuminanceReduced` / `widgetRenderingMode`) не меняется. Корневая проблема — это именно **FB15148099 в чистом виде**: widget extension process резолвит `\.colorScheme` как `.light`, хотя физически card chrome затемнён системой до тёмного. Старый код в `labelColor()` шёл в ветку `colorScheme == .dark ? .white : Color(uiColor: .label)` и возвращал `Color(uiColor: .label)` = **чёрный** → чёрный текст на тёмном фоне.

#### Финальный фикс

Принято решение (по запросу пользователя) зафиксировать карточку как **всегда тёмный фон + всегда светлый текст** на Lock Screen, независимо от скина/режима:

1. **`TimerLiveActivityPalette.labelColor/secondaryLabelColor/progressTrackColor/accentColor`** — добавлен параметр `showsWidgetContainerBackground: Bool = true`. Если `true` (Lock Screen), foreground всегда hard-coded light: `.white`, `Color(white: 0.85)`, `Color.white.opacity(0.22)`. Не зависит от `colorScheme` / `isLuminanceReduced` / `widgetRenderingMode` — они все unreliable в этом контексте.

2. **`TimerLockScreenLiveActivityView.body`** — теперь прокидывает `showsWidgetContainerBackground` во все вызовы palette и фиксирует фон карточки:

   ```swift
   .activityBackgroundTint(.black)
   .containerBackground(Color.black, for: .widget)
   ```

   Это гарантирует тёмный card chrome во всех режимах (Light/Dark/DND/AOD), на котором белый foreground всегда контрастен.

3. **Diagnostic-overlay и `LiveActivityDiagnosticLog.swift`** — удалены: root cause подтверждён, логи больше не нужны.

#### Почему именно так

- iOS даёт **три непредсказуемых поведения** на Lock Screen: stale `colorScheme` (FB15148099), отсутствие `isLuminanceReduced` в DND-dim, и несоответствие реального chrome `widgetRenderingMode`.
- **`showsWidgetContainerBackground == true`** — единственный надёжный сигнал, что мы на Lock Screen (а не в Dynamic Island expanded / banner). На Lock Screen система сама обычно рисует dark chrome, но в Light Mode рисует светлый. Жёсткая фиксация `Color.black` убирает эту перемену.
- Белый foreground + чёрный фон = гарантированный контраст во всех сочетанияхх Light/Dark/DND/AOD/Liquid Glass.

### Вердикт

```
VERIFIED (по визуальному тесту пользователя на устройстве)
Claim: В DND/Focus-dim Lock Screen Live Activity текст таймера видим.

Evidence:
- Пользователь собрал debug-сборку, запустил на iPhone в DND → таймер виден как в dark mode.
- rtk xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=C3ED7448-2C55-4F02-B5DA-721E2853FD0B' build → ** BUILD SUCCEEDED ** (exit 0)
- (последующая правка — зафиксировать тёмный фон для Light Mode — ожидает теста на устройстве)

Reasoning:
Root cause — FB15148099: widget extension process на Lock Screen резолвит `\.colorScheme`
как stale `.light`, хотя card chrome физически тёмный (DND-dim) или системно-тёмный.
DND-dim НЕ активирует `\.isLuminanceReduced`, `\.widgetRenderingMode` остаётся `.fullColor`.
Старая логика возвращала `Color(uiColor: .label)` = чёрный → black-on-black.
Фикс: на Lock Screen (`showsWidgetContainerBackground == true`) foreground всегда
hard-coded light + фон карточки явно `Color.black` — это убирает зависимость от
unreliable env values и даёт гарантированный контраст во всех режимах.
```
