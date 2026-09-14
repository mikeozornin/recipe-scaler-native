# Research: Awake-linked hands-free scroll

**Дата**: 2026-09-14 (rev 3)  
**Для**: [spec.md](./spec.md)

## Pivot

Rev 1 (Crouton Next/Back/List на cook matrix) отменён.  
Rev 2: keep-awake на recipe detail сразу включал voice+gesture.  
Rev 3: **opt-in**. `sun.max` только idle timer. Hands-free — флажок в `Menu` справа баннера + sheet справки. Permissions не при awake.

## Decision: opt-in в баннере, не toolbar

- **Decision:** trailing `Menu` (ellipsis) в `ScreenAwakeStatusBanner`; пункты Hands-free toggle + Help.
- **Rationale:** F1.2 запрещает вторую toolbar-кнопку; баннер уже значит «я готовлю/читаю»; не сюрпризить mic/camera от sun.max.
- **Alternatives:** второй toolbar toggle (отклонено); автоматический arm с awake (rev 2, отклонено); settings-экран (лишний Tax Job).

## Decision: persist `awakeHandsFreeEnabled`

- **Decision:** `UserDefaults.standard` Bool, default `false`. Не чистить на logout. Не CRDT.
- **Rationale:** повторный keep-awake на той же кухне не должен требовать каждый раз открывать меню; это device preference.
- **Alternatives:** session-only (раздражает); per-recipe key (YAGNI).

## Decision: тонкий voice engine, не 056

- **Decision:** `AwakeScrollVoiceEngine` на `SFSpeechRecognizer` + whitelist. Не реализовывать `CookingVoiceProvider` / SpeechAnalyzer / TTS.
- **Rationale:** 056 в коде отсутствует; CookingModeView вне scope; два действия vs полный command set 056.
- **Alternatives:** сначала закрыть 056 (блокирует 075); копировать файлы 056 as-is (мертвый TTS).

## Decision: scroll probe, не caret-anchor

- **Decision:** `UIViewRepresentable` / introspect probe на **сам** detail `ScrollView` в `YDocRecipeDetailView`. `DescriptionEditorScrollAnchor.detailScrollView` оставить для caret.
- **Rationale:** caret-anchor ищет ancestor от description `WKWebView`. В read-mode host — `StepsSection`; editor может отсутствовать; nested web scroll легко спутать.
- **Alternatives:** всегда ходить в caret-anchor (хрупко); SwiftUI `scrollPosition` iOS 17 (два источника истины с keyboard caret-scroll).

## Decision: Face XOR Hand по железу

- **Decision:** TrueDepth available → Face blink; иначе Hand pose. Voice параллельно. Без пункта меню «модальность».
- **Rationale:** одна фронтальная камера; v1 без сеттинга; Help sheet объясняет, какой канал на этом устройстве.
- **Alternatives:** всегда Hand (US3 мёртв на 13 Pro); всегда Face (ломает SE); auto-switch по детекции руки (сложно, ложные переключения).

## Decision: controller view-local

- **Decision:** `@State` / `@Observable` `AwakeScrollController` владеет `YDocRecipeDetailView`. Не `AppContainer`.
- **Rationale:** сессия привязана к видимой карточке; composition-root `.shared` запрещён кроме OS-фасадов; cooking cover и assistant живут рядом и должны disarm локально.
- **Alternatives:** AppContainer singleton (утечки камеры между экранами).

## Decision: cooking cover и assistant — CoverDisarmed

- **Decision:** `ProcessTableCookingCoordinator.presentation != nil` или assistant sheet open → teardown capture/speech, pref не сбрасывать. После dismiss — re-arm по F1.1.
- **Rationale:** detail остаётся в иерархии под cover (`ProcessTableCookingRoot` в `ContentView`); `onDisappear` карточки не сработает.
- **Alternatives:** оставить камеру под матрицей (privacy + battery).

## Platform

| Need | API |
|------|-----|
| Keep awake | existing `ScreenAwakeController` / `UIApplication.isIdleTimerDisabled` |
| Scroll | UIScrollView via **detail probe** |
| Voice | `SFSpeechRecognizer` on-device, 60s re-arm |
| Hand | `VNDetectHumanHandPoseRequest` — up/down sectors from thumb vector |
| Face | ARKit blink left/right → up/down |
| Pref | UserDefaults `awakeHandsFreeEnabled` |
| Privacy | extend camera/mic usage; add `NSSpeechRecognitionUsageDescription` |

## 75% semantics

`delta = 0.75 * scrollView.bounds.height`  
`offset.y = clamp(offset.y ± delta, 0, maxOffset)`  
`maxOffset` — см. [contracts/scroll-delta.md](./contracts/scroll-delta.md).

Overlap ~25% сохраняет контекст между шагами рецепта.

## Gesture mapping (v1)

См. [contracts/gesture-mapping.md](./contracts/gesture-mapping.md) и [contracts/voice-whitelist.md](./contracts/voice-whitelist.md).

- Hand thumbs-up tip above base → up; tip below → down.
- Face: blink left → up; blink right → down.
- Voice: вверх/вниз (+ EN).
