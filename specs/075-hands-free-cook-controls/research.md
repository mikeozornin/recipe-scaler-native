# Research: Awake-linked hands-free scroll

**Дата**: 2026-09-19 (rev 4)  
**Для**: [spec.md](./spec.md)

## Pivot

Rev 1 (Crouton Next/Back/List на cook matrix) отменён.  
Rev 2: keep-awake на recipe detail сразу включал voice+gesture.  
Rev 3: один флажок Hands-free в `Menu` баннера + отдельная справка; Face XOR Hand по TrueDepth автоматически.  
Rev 4: **каналы**. Ellipsis открывает один sheet настроек+справки. Голос / жесты / лицо — тумблеры. Жесты XOR лицо выбирает пользователь. Иконки включённых каналов в баннере.

## Decision: ellipsis → sheet, не Menu

- **Decision:** trailing Button `ellipsis` в `ScreenAwakeStatusBanner` открывает `AwakeScrollHelpSheet`. Тумблеры каналов только на sheet.
- **Rationale:** Figma `404:4872`; снимает Tax Job «включить Hands-free, потом искать справку»; F1.2 запрещает toolbar-кнопку.
- **Alternatives:** rev 3 Menu из двух пунктов (отклонено макетом); второй toolbar toggle (отклонено); settings в профиле (лишний уход с карточки).

## Decision: три prefs, не один Bool

- **Decision:** `awakeHandsFreeVoiceEnabled` / `Hand` / `Face`. Миграция со старого `awakeHandsFreeEnabled`. Не чистить на logout. Не CRDT.
- **Rationale:** можно включить только голос без камеры (батарея). XOR hand/face должен быть persist.
- **Alternatives:** один мастер + picker модальности (лишний уровень); session-only (раздражает).

## Decision: Face XOR Hand — пользователь, не железо

- **Decision:** тумблер лица скрыт без TrueDepth. На TrueDepth пользователь выбирает лицо или жесты. Включение одного пишет false другому.
- **Rationale:** одна фронтальная камера; макет явно даёт оба тумблера; auto-TrueDepth (rev 3) прятал выбор.
- **Alternatives:** всегда Hand; всегда Face; auto-switch по детекции руки.

## Decision: denied → snap-off + disabled

- **Decision:** отказ permission пишет pref false и disable тумблер, пока status denied. «Открыть параметры», если ≥1 denied.
- **Rationale:** кадр `404:4092`; не оставлять «включённый» канал, который молча no-op.
- **Alternatives:** держать ON (отклонено); retry toggle без Settings (бесполезный цикл).

## Decision: тонкий voice engine, не 056

- **Decision:** `AwakeScrollVoiceEngine` на `SFSpeechRecognizer` + whitelist. Не реализовывать `CookingVoiceProvider` / SpeechAnalyzer / TTS.
- **Rationale:** 056 в коде отсутствует; CookingModeView вне scope.
- **Alternatives:** сначала закрыть 056 (блокирует 075).

## Decision: scroll probe, не caret-anchor

- **Decision:** probe на **сам** detail `ScrollView`. Caret-anchor оставить для caret.
- **Rationale:** read-mode host — не editor WKWebView.
- **Alternatives:** SwiftUI `scrollPosition` как единственный источник (ломает caret-scroll).

## Decision: controller view-local

- **Decision:** `AwakeScrollController` владеет `YDocRecipeDetailView`. Не `AppContainer`.
- **Rationale:** сессия карточки; cooking cover / assistant disarm локально.
- **Alternatives:** AppContainer singleton.

## Decision: cooking cover и assistant — CoverDisarmed

- **Decision:** presentation или assistant sheet → teardown capture/speech, prefs каналов не сбрасывать.
- **Rationale:** detail остаётся под cover; `onDisappear` не сработает.
- **Alternatives:** камера под матрицей (privacy).

## Platform

| Need | API |
|------|-----|
| Keep awake | existing `ScreenAwakeController` |
| Scroll | UIScrollView via **detail probe** |
| Voice | `SFSpeechRecognizer` on-device, 60s re-arm |
| Hand | `VNDetectHumanHandPoseRequest` |
| Face | ARKit blink; скрыть UI без TrueDepth |
| Pref | UserDefaults три ключа + миграция |
| Privacy | extend camera/mic; `NSSpeechRecognitionUsageDescription` |

## 75% semantics

`delta = 0.75 * scrollView.bounds.height` — [contracts/scroll-delta.md](./contracts/scroll-delta.md).

## Gesture mapping (v1)

[contracts/gesture-mapping.md](./contracts/gesture-mapping.md), [contracts/voice-whitelist.md](./contracts/voice-whitelist.md).
