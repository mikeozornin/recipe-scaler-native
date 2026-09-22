# Contract: permissions and teardown

**Owner**: `AwakeScrollController`

## Когда спрашивать

Только переход **конкретного канала** `false` → `true` при `isScreenAwakeActive`.  
Не спрашивать на `play.circle.fill` ON, не спрашивать при одном открытии sheet, не спрашивать на каждом re-arm epoch, если status уже determined.

- Голос → mic, затем speech.
- Жесты или лицо → camera.
- Не запрашивать camera, если включили только голос. Не запрашивать mic, если включили только жест/лицо.

Отказ канала → snap-off pref этого канала (и disabled тумблер, пока denied). Другие каналы не трогать.

## Usage strings (смысл, не финальный маркетинговый тон)

Сохранить QR (camera) и assistant (mic). Добавить hands-free прокрутку рецепта при включённом канале.

- `NSCameraUsageDescription` — QR login **и** жесты/лицо hands-free на карточке.
- `NSMicrophoneUsageDescription` — assistant **и** голосовые вверх/вниз.
- `NSSpeechRecognitionUsageDescription` — **новый**: on-device команды прокрутки рецепта.

en+ru в `InfoPlist.xcstrings`.

## Arm

`start` только если F1.1 для этого канала. После permission await — re-check F1.1 и epoch. Denied → не start, pref false. Отказ `start()` движка при живых грантах → тот же snap-off pref канала (не permission denial, но иначе post-start `syncArmState` бесконечно reconfigure).

## Teardown (идемпотентный `stop(reason:)`)

Вызывать при: все каналы OFF / этот канал OFF, awake OFF, disappear, recipeId change, background, cooking `presentation != nil`, assistant open, deinit.

`stop` обязан:

1. `sessionEpoch += 1` до отмены задач (или эквивалент invalidate), если стопается вся сессия; для stop только speech при живой камере — не рвать capture epoch без нужды.
2. Cancel speech task + stop audio engine при stop голоса; deactivate `AVAudioSession` только если этот controller её активировал (не ломать assistant).
3. Stop capture/ARSession при stop камерного канала.
4. Не писать UserDefaults, кроме явного тумблера / XOR / denied snap-off.

## Cooking / assistant

Читать `ProcessTableCookingCoordinator.presentation` и `AssistantRecipeContext.isAssistantSheetOpen` (имена как в коде). Не polling: `onChange`.

## Open Settings

`UIApplication.openSettingsURLString`, если хотя бы mic или camera **denied** (не undetermined).

## Tests

Stale permission completion не вызывает `startRunning`.  
Denied voice → `awakeHandsFreeVoiceEnabled == false`.  
Cover present → `stopRunning` call count ≥ 1, channel prefs kept.
