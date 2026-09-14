# Спецификация: Hands-free прокрутка при «экран не гасить»

**Feature Branch**: `075-hands-free-cook-controls`  
**Дата**: 2026-09-14 (rev 3)  
**Статус**: Draft  
**Было (rev 1)**: Next/Back/List на `ProcessTableCookingView` — **отменено**.  
**Было (rev 2)**: keep-awake автоматически армит голос и жесты.  
**Стало**: keep-awake только не гасит экран. Hands-free (голос + жест → scroll ±75%) — **opt-in** из меню ellipsis справа в баннере keep-awake.

**Зависимости**:
- [`ScreenAwakeToggle`](../../RecipeScalerNative/Views/ScreenAwakeToggle.swift) / [`ScreenAwakeController`](../../RecipeScalerNative/Utils/ScreenAwakeController.swift)
- [`ScreenAwakeStatusBanner`](../../RecipeScalerNative/Views/ScreenAwakeStatusBanner.swift)
- [`YDocRecipeDetailView`](../../RecipeScalerNative/Views/YDocRecipeDetailView.swift) — основной вертикальный `ScrollView` + `isScreenAwakeActive`
- Voice STT-паттерны: [056](../056-cooking-voice-mode/spec.md) (переиспользуем идеи on-device listening; **код 056 в репозитории отсутствует**, `CookingModeView` не строим)
- Жесты: ARKit Face + Vision Hand Pose (как в research)

## Clarifications

### Session 2026-09-14 (rev 2)

- Q: Hands-free Next/Back/List в cook matrix? → A: **Нет.** Вместо этого: scroll up/down на карточке.
- Q: Что включает keep-awake? → A: Тот же toolbar `sun.max` (`ScreenAwakeToggle`). Отдельного Hands-free toggle в **toolbar нет**.
- Q: На сколько скроллить? → A: **75%** `visibleHeight` viewport `ScrollView` за одно действие.
- Q: Куда скроллить? → A: Основной вертикальный `ScrollView` карточки рецепта (`YDocRecipeDetailView`). Cook matrix 074 — **вне scope**.
- Q: Какие команды? → A: Только **вверх** и **вниз** (голос + жесты).

### Session 2026-09-14 (rev 3)

- Q: Когда стартовать камеру и mic? → A: **Не** при первом `sun.max`. Только когда пользователь включил флажок **Hands-free** в меню баннера.
- Q: Где управление Hands-free? → A: Справа в `ScreenAwakeStatusBanner` — `Menu` с ellipsis. Пункт 1: флажок Hands-free. Пункт 2: Справка → sheet.
- Q: Face XOR Hand без сеттинга модальности? → A: **TrueDepth → Face, иначе Hand.** Voice всегда при Hands-free ON (если speech granted). Третьего пункта меню в v1 нет.

---

## Границы

**В scope:**

- Opt-in Hands-free из меню баннера keep-awake (флажок + справка).
- Арминг hands-free scroll, пока recipe detail видима AND `isScreenAwakeActive` AND `handsFreeEnabled`.
- Voice: on-device STT + whitelist «вверх/вниз» (RU+EN).
- Gestures: Face XOR Hand → те же два действия.
- Программный scroll на `±0.75 * visibleBounds.height`, clamp к контенту.
- Teardown камеры и speech при HF OFF / awake OFF / уходе с экрана / background / cooking cover / assistant sheet.
- Permissions (mic, speech, camera) **при первом включении Hands-free**, не при keep-awake.
- Unit-тесты delta/clamp + classifier; i18n UI-строк меню, справки, privacy usage.

**Вне scope:**

- Next/Back/List, ingredients panel, cheat-sheet Crouton-style на cook matrix (rev 1).
- App Intents / Siri (можно v1.1).
- Прокрутка `ProcessTableCookingView` / горизонтальный scroll матрицы.
- Wake word, LLM voice chat.
- Web parity.
- Автоскролл к якорю шага (только relative ±75%).
- Одновременный Face+Hand на одной камере.
- Отдельный пункт меню «выбрать Face или Hand».
- Реализация 056 `CookingVoiceProvider` / `CookingModeView`.

---

## Контекст и мотивация

Keep-awake на карточке значит «я читаю рецепт с экрана». Hands-free листание — следующий шаг, но камера и микрофон не должны включаться сюрпризом от `sun.max`. Флажок в баннере отделяет «не гасить» от «слушай и смотри». Справка в том же меню снимает Tax Job «угадать жесты».

75% viewport — крупный шаг: меньше команд на длинный рецепт, чем постраничный «экран», но с перекрытием контекста (~25% остаётся в кадре).

---

## Цель v1

1. Awake ON → экран не гаснет; Hands-free ещё OFF, без камеры и mic.
2. Hands-free ON (из баннера) → голос и жест скроллят рецепт вверх/вниз.
3. Каждый жест/команда сдвигает offset на **75% видимой высоты** ScrollView.
4. Hands-free OFF или awake OFF → камера и mic полностью off.
5. Без Foundation Models; on-device Speech + системные Vision/ARKit.

---

## User stories

### US0. Включил Hands-free из баннера

Пользователь включает `sun.max`. В зелёном баннере справа ellipsis. В меню включает флажок Hands-free — система запрашивает нужные permissions (если ещё не granted) и армит слушание/камеру. Справка из того же меню открывает sheet с жестами и фразами. Флажок запоминается (UserDefaults); при следующем awake ON, если pref true, Hands-free армится снова без повторного тыка (permissions повторно не спрашиваем, если granted).

### US1. Листаю голосом

Hands-free armed. Говорит «вниз» / «down» — контент прокручивается вниз на 75% высоты видимой области. «Вверх» / «up» — вверх. На краях — clamp, без bounce-команд по кругу.

### US2. Листаю жестом руки

Hands-free armed, нет TrueDepth (или устройство без Face): thumbs-up вверх → scroll up; thumbs-up вниз → scroll down. Hold + cooldown, один fire на жест.

### US3. Листаю лицом (TrueDepth)

Hands-free armed и TrueDepth: wink — один глаз → up, другой → down (канон: left=up, right=down). Нет TrueDepth — Face недоступен, работают Hand+Voice.

### US4. Выключил Hands-free или awake

Снял флажок Hands-free → сразу stop speech + camera; idle timer по-прежнему выключен, баннер на месте. Выключил `sun.max` → баннер исчезает, Hands-free сессия teardown (pref флажка **не** сбрасываем). Повторный ON awake при pref true — arm снова, permission только если ещё не granted.

### US5. Отказ в permission

Camera denied → только voice (если speech ok). Speech/mic denied → только жесты (если camera ok). Оба denied → keep-awake и флажок могут быть ON, но hands-free no-op; без блокировки карточки. Баннер/справка могут показать одну строку «голос недоступен» / «жесты недоступны».

### US6. Ушёл с карточки / background / cooking / assistant

Teardown capture + speech как при HF OFF. Не слушать mic на других табах, под cooking cover 074 и под assistant sheet. Foreground: resume только если awake всё ещё ON **и** Hands-free pref ON **и** detail снова видима (не cover). Текущий keep-awake на background уже зовёт `deactivateScreenAwake()` — awake станет OFF; Hands-free не должен оставить камеру.

---

## Требования

### Функциональные

#### F1. Арминг и chrome

- **F1.1.** Hands-free scroll armed iff recipe detail visible AND `isScreenAwakeActive` AND `handsFreeEnabled` AND не показан cooking cover AND assistant sheet закрыт.
- **F1.2.** Нет отдельной кнопки Hands-free в **toolbar**. `sun.max` не переименовывать и не дублировать.
- **F1.3.** Справа в `ScreenAwakeStatusBanner` — `Menu` (ellipsis). Не увеличивать высоту баннера больше чем на 4 pt.
- **F1.4.** Пункты меню:
  1. Toggle Hands-free (`Toggle` / checkmark) — ключ i18n `recipe.awake-scroll.hands-free`.
  2. Справка — ключ `recipe.awake-scroll.help` — `.sheet` с объяснением жестов, фраз, XOR и permissions.
- **F1.5.** `handsFreeEnabled` persist: UserDefaults key `awakeHandsFreeEnabled`, default `false`. Пишет только пользовательский toggle, не teardown awake.
- **F1.6.** Опциональный camera preview 48 pt overlay (bottomTrailing) только если Hands-free armed и camera granted. Не `safeAreaInset` (не сжимать ScrollView).
- **F1.7.** Компактные mic/hand glyphs в баннере **не обязательны** в v1: ellipsis + флажок достаточны. Если добавлять — hug справа от текста, слева от ellipsis, не вытесняя title.

#### F2. Действия

```swift
enum AwakeScrollAction: Equatable {
    case up    // к началу документа (contentOffset.y уменьшается)
    case down  // к концу документа (contentOffset.y увеличивается)
}
```

- **F2.1.** Delta = `0.75 * scrollView.bounds.height` (visible layout height viewport).
- **F2.2.** Новый offset = clamp(current ± delta, 0...maxOffset), где `maxOffset = max(0, contentSize.height - bounds.height + adjustedContentInset.bottom + adjustedContentInset.top)` — точная формула в [contracts/scroll-delta.md](./contracts/scroll-delta.md).
- **F2.3.** Анимация: `setContentOffset(_:animated: true)` на UIScrollView, найденном **probe'ом** на detail `ScrollView`. `DescriptionEditorScrollAnchor.detailScrollView` — только caret-scroll редактора, не единственный источник для Hands-free.
- **F2.4.** Cooldown 0.5–0.8 s после fire (voice и gesture делят один cooldown).
- **F2.5.** Ручной пальцевый scroll не блокировать (`isScrollEnabled` остаётся true).

#### F3. Voice

- **F3.1.** On-device `SFSpeechRecognizer`, armed только при Hands-free. Не тащить 056 `CookingVoiceProvider`.
- **F3.2.** Classifier whitelist — [contracts/voice-whitelist.md](./contracts/voice-whitelist.md).
- **F3.3.** Partial results не fire; только final (или debounce stable partial ≥ N ms, N в data-model).
- **F3.4.** 60s re-arm как идея 056.

#### F4. Hand (Vision)

- **F4.1.** `VNDetectHumanHandPoseRequest`, front camera, max 1 hand.
- **F4.2.** Pose thumbs-up; сектор по углу большого пальца — [contracts/gesture-mapping.md](./contracts/gesture-mapping.md).
- **F4.3.** Hold ~200 ms, fire once, cooldown.
- **F4.4.** Используется iff Hands-free armed AND camera granted AND **нет** TrueDepth.

#### F5. Face (ARKit)

- **F5.1.** Если TrueDepth: `eyeBlinkLeft` → `.up`, `eyeBlinkRight` → `.down` (edge + debounce). Канон v1: left=up, right=down.
- **F5.2.** `jawOpen` в v1 **не** используем.
- **F5.3.** Используется iff Hands-free armed AND camera granted AND TrueDepth available.

#### F6. Permissions & privacy

- Camera / mic / speech usage strings: существующие цели (QR login, assistant dictation) **сохранить** и **добавить** hands-free scroll. Новый ключ `NSSpeechRecognitionUsageDescription`.
- Запрос: при **первом** переходе `handsFreeEnabled` false → true, пока awake ON. Не при `sun.max`.
- Denied → US5, карточка не блокируется, флажок может остаться ON (no-op каналы).

#### F7. Lifecycle

- HF OFF / awake OFF / onDisappear detail / background / cooking presentation / assistant sheet → teardown capture + speech.
- Single-flight start; `sessionEpoch`.
- Cooking cover 074: `ProcessTableCookingCoordinator.presentation != nil` → disarm HF resources; после dismiss — re-arm если F1.1 снова true.
- Assistant sheet: то же.
- Logout / account switch: teardown; UserDefaults pref **не** чистить (это UI-предпочтение устройства, не account CRDT).

### Нефункциональные

- N1. On-device STT default.
- N2. Swift 6; Vision off MainActor.
- N3. Не регрессить обычный scroll жестом пальца и keep-awake без Hands-free.
- N4. Battery: ≤15–20 fps hand pose; stop when not armed.
- N5. Controller view-local у `YDocRecipeDetailView`, не `AppContainer` / не `.shared`.

---

## Конституционная проверка

| Gate | Статус | Evidence |
|------|--------|----------|
| CRDT-first | N/A | Только scroll UI + UserDefaults pref |
| Web parity | N/A | Native-only |
| Offline-first | PASS | On-device |
| Native UI | PASS | Detail ScrollView + banner Menu |
| Phased delivery | PASS | opt-in → engine → voice → hand → face |
| i18n | PASS | banner/menu/help/privacy в xcstrings |
| Documentation | PASS | spec/plan/layout/tasks/contracts |

---

## Downstream consumers

- **SwiftUI**: `YDocRecipeDetailView`, `ScreenAwakeStatusBanner`, новый help sheet
- **Cross-process**: N/A (App Intents вне scope)
- **Sync**: N/A
- **Persisted**: UserDefaults `awakeHandsFreeEnabled`
- **Tests**: `AwakeScroll*Tests`

---

## Positive invariants

| Effect | Invariant | Test |
|--------|-----------|------|
| action `.down`, visibleH=400, y=0 | y → 300 | `test_down_scrolls_75_percent` |
| action `.down`, y near end | clamp maxOffset | `test_down_clamps_end` |
| «вниз» transcript | `.down` | `test_ru_vniz` |
| awake → false | sessions stopped | `test_awake_off_teardown` |
| HF → false, awake true | camera+speech stopped, idle timer still disabled | `test_hands_free_off_keeps_awake` |
| thumb up-sector hold | one `.up` | `test_hand_up_once` |
| sun.max ON, HF pref false | no capture session | `test_awake_only_no_camera` |

---

## Async lifecycle

| Op | Identity | Re-check | Cancel owner | Stale test |
|----|----------|----------|--------------|------------|
| permission | epoch | F1.1 still true | AwakeScrollController | stale epoch ignored |
| vision frame | epoch | epoch match | same | stale frame dropped |
| speech re-arm | voiceSessionId | id match + F1.1 | voice engine | inherit 056 pattern |
| start capture | epoch | F1.1 | controller | cooking cover mid-start → stop |

---

## Teardown / resource inventory

| Path | Postcondition |
|------|----------------|
| HF OFF | no camera indicator, speech stopped; banner stays if awake |
| awake OFF | banner gone; camera+speech stopped |
| leave detail | same as awake OFF path for resources |
| background | same; existing `deactivateScreenAwake()` |
| cooking cover | camera+speech stopped; after dismiss re-arm if F1.1 |
| assistant sheet | same as cover |
| logout | resources stopped; pref kept |

---

## Verification

- Unit delta/clamp/classifier/arm predicate.
- Manual: iPhone 13 Pro, long recipe, awake ON without HF → нет green camera dot; HF ON → voice + face/hand; ~¾ screen per command; camera off after HF OFF.
- Layout: human review `layout.md` до banner Menu / sheet / preview.

---

## Риски

| Риск | Митигация |
|------|-----------|
| SwiftUI ScrollView без UIScrollView handle в read-mode | `DetailScrollViewProbe` на сам ScrollView карточки, не caret-anchor |
| Ложные «up» из речи на кухне | узкий whitelist + cooldown |
| Mirror camera left/right | для up/down секторов критичен pitch, не yaw |
| Permission сюрприз от sun.max | rev 3: запрос только с Hands-free |
| 056 ещё не в коде | тонкий SFSpeechRecognizer, явная граница |

---

## Связь с 056 / 074

| Спека | Связь |
|-------|--------|
| 056 | Паттерны on-device listening и 60s re-arm; не строим CookingModeView |
| 074 | Не трогаем matrix cook UI; **disarm** HF пока cooking cover presented |

---

*Rev 3: Hands-free opt-in из ellipsis баннера; keep-awake больше не армит камеру/mic.*
