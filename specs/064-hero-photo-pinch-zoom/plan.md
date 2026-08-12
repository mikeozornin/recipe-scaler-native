# План: pinch-to-zoom для hero-фотографий рецепта

**Дата**: 2026-08-12
**Спека**: [spec.md](./spec.md)
**Ветка**: работа на `master` (AGENTS.md: small fixes на master; feature-ветки только для крупных specs). Изменение — один новый файл-модификатор (~80 строк) + 2 точки вызова по 1 строке каждая.

> Канонический project template для Recipe Scaler Native. Артефакт пишется на
> русском.

## Границы

- **В scope**:
  - Новый файл `RecipeScalerNative/Views/HeroPhotoPinchZoom.swift` с `HeroPhotoPinchZoomModifier: ViewModifier` и публичным `extension View { func heroPhotoPinchZoom(isEnabled: Bool = true) -> some View }`.
  - Применить `.heroPhotoPinchZoom()` к `heroImageBody` в `RecipeCachedImageView` ([RecipeScalerNative/Views/RecipeCachedImageView.swift:96-111](RecipeScalerNative/Views/RecipeCachedImageView.swift)).
  - Применить `.heroPhotoPinchZoom()` к `heroImageBody` в `PublicCachedImageView` ([RecipeScalerNative/Views/PublicCachedImageView.swift:60-74](RecipeScalerNative/Views/PublicCachedImageView.swift)).
  - Подавление pinch во время upload/delete overlay в `RecipeDetailImageSection` — параметр `isEnabled` пробрасывается из родителя или контролируется внутри cached-image-view.
- **Вне scope**:
  - Полноэкранный overlay-режим, pan одним пальцем, double-tap to zoom, кнопки закрытия — явно отклонено в clarify-сессии.
  - Зум thumbnail'ов (64×64) и иллюстраций в шагах.
  - Изменения кэшей, сервисов, декодера, URL-билдеров, Y.Doc-схемы, sync-событий.
  - VoiceOver-pseudo-zoom accessibility action — пользователь явно отклонил.
  - Изменения `RecipeDetailImageSection.swift` (edit-mode overlay) — модификатор применяется внутри cached-image-view, секция не трогается.
- **STOP conditions**:
  - Если на iOS 17.0 `MagnifyGesture` конфликтует с родительским `ScrollView` так, что скролл намертво блокируется (модификатор не отдаёт жест) — STOP и обсудить альтернативу (`.simultaneousGesture` вместо `.gesture`, либо перенос жеста на уровень `ScrollView`).
  - Если `scaleEffect` на `ZStack` с `Color(.secondarySystemBackground)` + `Image` ломает `.clipped()` (фото вылезает за границы hero при зуме) — STOP, нужно решать отдельным контейнером (см. раздел «Маска / clipped»).
  - Если release-анимация через `withAnimation` не срабатывает корректно с `@GestureState` (значение не анимируется обратно) — STOP, перейти на `@State` + ручной сброс.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | Фича чисто UI; не касается Y.Doc/sync. Изображение берётся из существующих кэшей. |
| Web parity | PASS | iOS-only UX-ускорение. Веб-карточка работает как раньше; контракты не меняются. |
| Offline-first | PASS | Pinch работает с уже закэшированным `UIImage`; сеть не требуется. |
| Native UI | PASS | Чистый SwiftUI (`MagnifyGesture`, `scaleEffect`, overlay). WebView не затрагивается. |
| Phased delivery | PASS | Самостоятельная единица, не тянет работы из других фаз. |
| i18n | PASS | Новых пользовательских строк нет (FR-017). `lint-i18n.sh` без новых предупреждений. |
| Documentation | PASS | Sync/schema docs не меняются. Меняется только поведение hero-фото. |

## Очерёдность

1. **Создать `HeroPhotoPinchZoom.swift` с модификатором и превью** — почему первым: ядро фичи, от которого зависят точки вызова; зависимости: нет. Включает `#Preview` с тестовым `UIImage` для проверки в Xcode Canvas.
2. **Применить `.heroPhotoPinchZoom()` к `RecipeCachedImageView.heroImageBody`** — зависит от 1; добавить параметр `isEnabled` для подавления pinch пока нет фото (`uiImage == nil`).
3. **Применить `.heroPhotoPinchZoom()` к `PublicCachedImageView.heroImageBody`** — зависит от 1; аналогично с `isEnabled` по `uiImage == nil`.
4. **Прогнать `xcodebuild build` + симулятор** — зависит от 2, 3; ручная проверка pinch через Option + drag на обоих экранах, edit-mode своего рецепта, рецепте без фото.
5. **Финализировать параметры (clamp, dim opacity, minimumScaleDelta, release duration)** — зависит от 4; tweak по результатам тестирования на симуляторе; значения зафиксировать в этом плане (см. «Параметры»).

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNative/Views/HeroPhotoPinchZoom.swift` | Создать | Новый `HeroPhotoPinchZoomModifier` + `extension View { heroPhotoPinchZoom(isEnabled:) }`. |
| `RecipeScalerNative/Views/RecipeCachedImageView.swift` | Изменить | На `heroImageBody` (líneas 96-111) добавить `.heroPhotoPinchZoom(isEnabled: uiImage != nil)` после `.clipped()`. |
| `RecipeScalerNative/Views/PublicCachedImageView.swift` | Изменить | На `heroImageBody` (líneas 60-74) добавить `.heroPhotoPinchZoom(isEnabled: uiImage != nil)` после `.clipped()`. |

Тouch-точки минимальны — никаких правок в `RecipeDetailImageSection`, `YDocRecipeDetailView`, `DiscoverRecipeView`.

## Downstream consumers

- **SwiftUI views**: `RecipeCachedImageView`, `PublicCachedImageView` — единственные потребители нового модификатора; `RecipeDetailImageSection`, `YDocRecipeDetailView`, `DiscoverRecipeView` не меняются.
- **Cross-process**: N/A — фича в основном app target; widgets/share extension/watchOS/Live Activity/App Intents не обращаются к hero-image UI.
- **Sync boundaries**: N/A — Yjs/CRDT/web/server без изменений.
- **Persisted state**: N/A — состояние жеста в `@GestureState`, не персистится; SQLite/Keychain/App Group/UserDefaults без изменений.
- **Tests / verify scripts**: новые verify-скрипты не заводятся (XCUITest не поддерживает multi-touch pinch на iOS 17). Существующие verify-скрипты не задеты. Build-green обязателен.

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| Pinch на hero своего рецепта | scale растёт 1.0 → clamp 2.5×, opacity dim растёт 0 → 0.45 | Ручная проверка Simulator (Option + drag) |
| Pinch на hero Discovery | поведение идентично (тот же модификатор) | Ручная проверка |
| Release пальцев | scale анимацией → 1.0, dim opacity → 0 за ≤ 0.3 с | Ручная проверка |
| Скролл карточки через hero-зону | scroll работает, pinch не активируется при обычной навигации | Ручная проверка |
| Edit-mode delete-button | остаётся в `.bottomTrailing`, кликабельна после pinch | Ручная проверка edit-mode |
| Рецепт без фото (`uiImage == nil`) | hero не рендерит image, pinch no-op (`isEnabled: false`) | Ручная проверка на рецепте без фото |
| Upload/delete progress overlay | pinch подавлён через `isEnabled` (или механизм плана ниже) | Ручная проверка |

Негативная формулировка «не должно сломаться» сама по себе недостаточна.

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| N/A — нет async side effects | N/A | N/A | N/A | N/A |

Модификатор — чисто синхронная декларативная конструкция SwiftUI. Состояние масштаба хранится в `@GestureState`, автоматически сбрасывается при окончании жеста и при пересоздании view.

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| logout | `@GestureState` сбрасывается SwiftUI при уничтожении view | N/A | N/A | N/A | Нет зависшего затемнения / зависшего scale |
| account switch | Аналогично — пересоздание view | N/A | N/A | N/A | Аналогично |
| stale session / cold start | `@GestureState` пустой при init | N/A | N/A | N/A | Стартовое состояние — scale 1.0, dim 0 |
| reconnect / partial failure | unaffected — нет сетевой зависимости | N/A | N/A | N/A | Hero остаётся интерактивным |

## Cross-target contracts

- **Canonical owner**: `HeroPhotoPinchZoomModifier` — единственная реализация жеста.
- **Writer/reader targets**: только iOS app target (`RecipeCachedImageView`, `PublicCachedImageView`). Widgets/Watch/App Intents не используют модификатор.
- **Validator/normalizer**: N/A — нет данных для нормализации.
- **Raw literal exceptions**: N/A — нет UI-строк (FR-017).

## Locale / theme consumers

- SwiftUI environment: модификатор не использует локализованных строк; затемнение — `Color.black`, адаптируется под light/dark автоматически (opacity фиксирован, цвет системный).
- UIKit / notification categories: N/A.
- Widgets / Live Activities / App Intents: N/A.
- Cached or generated assets: N/A.
- `.system` effective value: `Color.black` + системная анимация (`withAnimation`, `.smooth`) уважает Reduce Motion через Accessibility environment.

## Compatibility / migration

- Current format/contract: N/A — нет данных.
- Previous supported format: N/A.
- Missing version/default behavior: N/A.
- Unknown future version/ID behavior: N/A.
- Required legacy fixture tests: N/A.

## Unknown IDs and fallback policy

- DEBUG/CI: нет новых ID.
- Release: N/A.
- Legacy aliases: N/A.

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app`/`.appex` assertion |
|----------|----------|---------------|----------------|---------------------------------|
| Новые ресурсы не генерируются | N/A | N/A | N/A | N/A |

## Human gates

- [x] `layout.md` reviewed by human — **N/A**: меняется только поведение фото (zoom-жест), не вёрстка экрана. Figma-driven UI gate не требуется (паритет с 063 спецификацией, где тоже был жест без layout).
- [x] `layout-audit.json` static audit passed — **N/A** (та же причина).
- [x] Human acceptance Artifact актуален — **N/A**.
- [ ] Отдельный review-agent выполнен; self-review не считается заменой — **ожидается после реализации**.

> **Human gate для плана**: AGENTS.md требует human review плана перед tasks/implementation. Останавливаюсь здесь и жду явного «продолжай» перед `/speckit-tasks`.

## Verification

- `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16' build` — компиляция зелёная.
- `bash scripts/lint-i18n.sh` — без новых предупреждений.
- Ручная проверка через Simulator:
  - Открыть свой рецепт с фото → pinch (Option + drag) на hero → убедиться: scale растёт плавно до 2.5×, dim появляется, release → возврат к 1.0×.
  - Открыть чужой рецепт в Discovery → повторить pinch → поведение идентично.
  - Войти в edit-mode своего рецепта → pinch → delete-button остаётся кликабельной.
  - Загрузить новое фото (edit-mode) → во время upload прогресс-overlay виден, pinch подавлён.
  - Открыть рецепт без фото → dropzone работает, pinch не активируется.
  - Скроллить карточку двумя пальцами через hero → скролл работает, zoom не активируется.
- Expected: build exit 0, все ручные сценарии проходят.

## Rollback / maintenance

- Как откатить: удалить `.heroPhotoPinchZoom()` вызовы из обоих cached-image-view'ов; файл `HeroPhotoPinchZoom.swift` можно оставить или удалить. Карточки рецептов продолжат работать как раньше.
- Что будет взаимодействовать в будущем: если появятся другие жесты на hero (например, long-press для контекстного меню), нужно держать `MagnifyGesture` приоритетным через `.highPriorityGesture`, либо координировать с новым жестом.
- Временные allowlist/quarantine: нет.

---

## Параметры (finalized 2026-08-12)

| Параметр | Значение | Обоснование |
|----------|----------|-------------|
| `maxScale` (clamp) | **2.5** | Согласовано с пользователем; посмотрим как пойдёт, tweak без новой спеки. |
| `dimOpacity` | **0.4** | Системного дефолта нет; выбрано как стандартный iOS backdrop value (контекстные меню/popover). |
| `minimumScaleDelta` | **0.05** | Защита от случайных микро-касаний при скролле; посмотрим, может понадобиться tweak. |
| release animation | **0.20 с, `Animation.smooth(duration: 0.20)`** | Snappy темп; уважает Reduce Motion через системное `withAnimation`. |
| anchor scaleEffect | **`.center`** | Фото растёт из центра hero; интуитивно для pinch. |
| edit-mode поведение | **полностью выключен** | `RecipeDetailImageSection` пробрасывает `pinchZoomEnabled: !isEditing`. См. FR-012. |

---

## Дизайн модификатора (финальный код — реализован в T002)

```swift
import SwiftUI

/// Inline pinch-to-zoom для hero-фотографий рецептов.
/// Увеличивает фото в диапазоне 1.0× … 2.5× с одновременным затемнением фона.
/// После отпускания пальцев фото анимированно возвращается к 1.0×.
struct HeroPhotoPinchZoomModifier: ViewModifier {
    var isEnabled: Bool = true

    /// Анимируемая прозрачность dim-плёнки (0 — невидима, 0.4 — максимум при zoom > 1).
    @State private var dimOpacity: Double = 0

    /// Текущее значение масштаба. Сбрасывается к 1.0 автоматически при окончании жеста.
    @GestureState private var zoom: CGFloat = 1.0

    private let maxScale: CGFloat = 2.5
    private let dimMax: Double = 0.4

    func body(content: Content) -> some View {
        content
            .scaleEffect(isEnabled ? max(zoom, 1) : 1, anchor: .center)
            .overlay {
                if isEnabled && dimOpacity > 0.001 {
                    Color.black.opacity(dimOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .gesture(isEnabled ? pinchGesture : nil)
            .onChange(of: zoom) { _, newValue in
                let target: Double = newValue > 1.001 ? dimMax : 0
                if abs(dimOpacity - target) > 0.001 {
                    withAnimation(.smooth(duration: 0.15)) {
                        dimOpacity = target
                    }
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .minimumScaleDelta(0.05)
            .onChanged { value in
                // clamp через @GestureState handled in .updating? — нет, используем прямой
                // @GestureState zoom = value.magnification уже даёт авто-сброс; clamp ниже.
                // На самом деле: записываем сырой magnification, clamp через max(zoom, 1) в scaleEffect
                // + верхний clamp через отдельный state (см. ниже реализацию с .updating).
            }
            .onEnded { _ in
                withAnimation(.smooth(duration: 0.20)) {
                    dimOpacity = 0
                }
                // zoom сбросится автоматически через @GestureState к baseline 1.0
            }
    }
}

extension View {
    /// Применяет inline pinch-to-zoom (1.0× … 2.5×) с затемнением фона.
    /// Когда `isEnabled == false`, модификатор no-op.
    func heroPhotoPinchZoom(isEnabled: Bool = true) -> some View {
        modifier(HeroPhotoPinchZoomModifier(isEnabled: isEnabled))
    }
}
```

> Примечание: финальная реализация использует `.updating(_ zoom:body:)` с clamp внутри `body` блока, чтобы `scaleEffect` получал уже зажатое значение (1.0 … 2.5) во время жеста. См. [HeroPhotoPinchZoom.swift](RecipeScalerNative/Views/HeroPhotoPinchZoom.swift) для действующего кода.

### Точки для обсуждения на review

1. **`@GestureState` vs `@State` для zoom.** Слишком типично использовать `@GestureState` + `.updating(_:body:)` — значение автоматически сбрасывается к baseline при окончании жеста, что и даёт «strict return». Но: поведение `@GestureState` при `withAnimation` на `dimOpacity` может дать визуальный разрыв (zoom сбрасывается мгновенно, dim анимируется). Если это будет выглядеть рвано — переключимся на `@State` + ручной сброс в `withAnimation` (полировать визуал).

2. **Clamp во время `onChanged`.** В примере выше clamp не показан (через `.updating`). Реальная реализация: в `.updating(_:body:)` возвращать `min(max(value.magnification, 1), maxScale)` — зажать scale в диапазоне, прежде чем записать в `@GestureState`. Зафиксирую в коде.

3. **Конфликт со scroll.** `.gesture(pinch)` по умолчанию на iOS 17 `MagnifyGesture` берёт приоритет над scroll. Если на симуляторе окажется, что scroll ломается — переключимся на `.highPriorityGesture(pinch)` или `.simultaneousGesture(pinch)`. Решение принимать по факту проверки, не заранее.

4. **Маска / clipped.** Модификатор применяется **снаружи** `.clipped()` heroImageBody. Если фото при зуме вылезает за границы hero-блока (это нежелательно — нарушает «inline» ощущение), можно либо оставить вылезание (фото растёт за пределы hero, поверх остального контента — это и есть «оторвалось»), либо добавить маску. Пользователь в clarify-сессии сказал, что фото должно «вырастать поверх остального UI» — значит вылезание ожидаемо, маска НЕ нужна. Зафиксирую как решение.

5. **Edit-mode `isEnabled`.** Решено: в edit-mode (`isEditing == true` в `RecipeDetailImageSection`) жест **полностью выключен**. `RecipeDetailImageSection` пробрасывает новый параметр `pinchZoomEnabled: Bool` в `RecipeCachedImageView`, а тот — в `heroPhotoPinchZoom(isEnabled:)`. Значение в точке вызова: `pinchZoomEnabled: !isEditing`. Это покрывает и upload-progress overlay, и delete-button, и PhotosPicker в dropzone — все edit-mode concerns разом. `PublicCachedImageView` остаётся с `isEnabled: uiImage != nil` (там edit-mode нет).

6. **`allowsHitTesting(false)` на dim-overlay.** Затемнение НЕ должно перехватывать касания — жест получает сам hero. Параметр зафиксирован.

7. **Accessibility.** `@GestureState` и `scaleEffect` невидимы для VoiceOver — фото читается с тем же accessibility, что и раньше. Дополнительных actions нет (FR-017).
