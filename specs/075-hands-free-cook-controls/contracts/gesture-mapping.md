# Contract: gesture mapping

**Owner**: `AwakeScrollHandClassifier`, `AwakeScrollFaceClassifier`  
**XOR**: [data-model.md](../data-model.md) `AwakeScrollCameraModality`.

## Hand (Vision)

- Request: `VNDetectHumanHandPoseRequest`, `maximumHandCount = 1`, front camera.
- FPS ≤ 20.
- Joints: thumb tip vs thumb CMC (base). Если joint confidence < 0.3 → ignore.
- Thumbs-up gate: большой палец разогнут относительно кулака (tip дальше от wrist чем CMC по оси пальца). Если не thumbs-up → ignore (не маппить open palm).
- Сектор:
  - `tip.y < base.y - deadZone` → `.up` (в Vision/UIKit: уточнить в тесте с фикстурой точек; канон **tip выше base на экране пользователя** = scroll к началу документа).
  - `tip.y > base.y + deadZone` → `.down`.
  - иначе dead-zone (влево/вправо) → ignore.
- `deadZone`: 0.08 в нормализованных координатах vision (подкрутить только тестом, одно место).
- Hold 200 ms в том же секторе → один `.up`/`.down`, затем cooldown сессии.
- Mirror: классифицировать в координатах, согласованных с тем, что видит пользователь в preview; не путать yaw с pitch.

## Face (ARKit)

- Только если TrueDepth (`ARFaceTrackingConfiguration.isSupported`).
- `eyeBlinkLeft` rising edge ≥ 0.6 → `.up`.
- `eyeBlinkRight` rising edge ≥ 0.6 → `.down`.
- Оба глаза за один кадр / 100 ms → ignore.
- `jawOpen` игнорировать.
- Debounce: повтор того же глаза не раньше cooldown сессии.

## Camera session

- Одна `AVCaptureSession` на epoch.
- Face: ARSession с `.userFacing`.
- Hand: AVCapture + Vision (не ARFace).
- Stop → `session.stopRunning()` на background queue; green dot должен погаснуть до возврата в UI тест/quickstart.

## Preview

48 pt overlay, `allowsHitTesting(false)`, только modality ≠ `.none`.
