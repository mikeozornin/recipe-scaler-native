# Contract: permissions and teardown

**Owner**: `AwakeScrollController`

## Когда спрашивать

Только переход `handsFreeEnabled` `false` → `true` при `isScreenAwakeActive`.  
Не спрашивать на `sun.max` ON, не спрашивать на каждом re-arm epoch, если status уже determined.

Порядок v1: mic → speech → camera. Отказ одного не блокирует запрос следующего. После всех — start доступных каналов.

## Usage strings (смысл, не финальный маркетинговый тон)

Сохранить QR (camera) и assistant (mic). Добавить hands-free прокрутку рецепта при включённом Hands-free.

- `NSCameraUsageDescription` — QR login **и** жесты hands-free на карточке.
- `NSMicrophoneUsageDescription` — assistant **и** голосовые вверх/вниз.
- `NSSpeechRecognitionUsageDescription` — **новый**: on-device команды прокрутки рецепта.

en+ru в `InfoPlist.xcstrings`.

## Arm

`start` только если F1.1. После permission await — re-check F1.1 и epoch.

## Teardown (идемпотентный `stop(reason:)`)

Вызывать при: HF OFF, awake OFF, disappear, recipeId change, background, cooking `presentation != nil`, assistant open, deinit.

`stop` обязан:

1. `sessionEpoch += 1` до отмены задач (или эквивалент invalidate).
2. Cancel speech task + stop audio engine; deactivate `AVAudioSession` только если этот controller её активировал (не ломать assistant, если sheet как раз открывается — порядок: сначала HF stop, потом assistant).
3. Stop capture/ARSession.
4. Не писать UserDefaults, кроме явного toggle.

## Cooking / assistant

Читать `ProcessTableCookingCoordinator.presentation` и `AssistantRecipeContext.isAssistantSheetOpen` (имена как в коде). Не polling: `onChange`.

## Tests

Stale permission completion не вызывает `startRunning`.  
Cover present → `stopRunning` call count ≥ 1, pref всё ещё true.
