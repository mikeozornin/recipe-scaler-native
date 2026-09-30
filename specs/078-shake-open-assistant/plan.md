# План: Встряхнуть → открыть ассистента

**Дата**: 2026-09-30  
**Спека**: [spec.md](./spec.md)  
**Research**: [research.md](./research.md)  
**Ветка**: `078-shake-open-assistant`

## Границы

- **В scope**: preference default false; settings toggle; UIWindow shake + debounce; open assistant; auto-attach `visibleRecipeId`; force new chat без рецепта; auto-start voice; i18n; unit tests.
- **Вне scope**: web; Figma layout; CMMotionManager; wire protocol; Watch/widgets.
- **STOP conditions**: не коммитить release-notes stash; не push; не трогать 077 файлы.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | UI/preference only |
| Web parity | N/A | Native gesture |
| Offline-first | PASS | Используем существующий sheet offline gate |
| Native UI | PASS | List Toggle + UIKit motion |
| Phased delivery | PASS | см. очерёдность |
| i18n | PASS | xcstrings EN+RU |
| Documentation | PASS | spec/plan/research/tasks |

## Очерёдность

1. Preference + unit test default false.
2. Shake detector (UIWindow + Notification + debounce helper) + unit test.
3. Coordinator/AppShell shake open request (attachRecipeId / forceNewChat / startVoice).
4. AssistantSheet + Composer: consume request → new chat / attach / start voice.
5. Settings toggle + i18n + a11y.
6. Build + lint-i18n + tests.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNative/Utils/ShakeToOpenAssistantPreference.swift` | Создать | storage key + isEnabled |
| `RecipeScalerNative/Utils/DeviceShakeDetector.swift` | Создать | UIWindow override + Notification + debounce |
| `RecipeScalerNative/Routing/AppShellCoordinator.swift` | Изменить | `AssistantShakeOpenRequest` + pending + logout clear |
| `RecipeScalerNative/Views/AppShellView.swift` | Изменить | onReceive shake → route; pass shake request into sheet |
| `RecipeScalerNative/Views/AssistantSheet.swift` | Изменить | consume shake: new chat / auto-attach |
| `RecipeScalerNative/Views/AssistantComposer.swift` | Изменить | autoStartVoice one-shot |
| `RecipeScalerNative/Views/AccountView.swift` | Изменить | Toggle в preferencesSection |
| `RecipeScalerNative/AccessibilityIdentifiers.swift` | Изменить | toggle id |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменить | EN+RU keys |
| `RecipeScalerNative.xcodeproj/project.pbxproj` | Изменить | новые Swift files |
| `RecipeScalerNativeTests/ShakeToOpenAssistantPreferenceTests.swift` | Создать | default / debounce |
| `specs/078-shake-open-assistant/*` | Создать | Spec Kit |

## Downstream consumers

- **SwiftUI views**: `AppShellView`, `AssistantSheet`, `AssistantComposer`, `AccountView`.
- **Cross-process**: N/A.
- **Sync boundaries**: N/A.
- **Persisted state**: UserDefaults `shakeToOpenAssistantEnabled` (standard, не App Group).
- **Tests / verify scripts**: unit tests; `lint-i18n.sh`; build. Отдельный verify-078 не обязателен.

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| Нет ключа в UserDefaults | `isEnabled == false` | `test_default_disabled` |
| `save(true)` | `isEnabled == true` | `test_persists_enabled` |
| два shake < debounce | один accepted | `test_debounce_drops_second` |
| shake request recipeId R | `attachRecipeId == R`, `forceNewChat == false` | routing via request factory |
| shake request nil recipe | `forceNewChat == true` | same |

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| `startVoiceRecording()` после shake | shake `requestId` + sheet generation | requestId ещё pending/handled; sheet still presented; recorder idle | sheet dismiss / `onDisappear` cancel recorder | dismiss mid-start → no crash |
| open sheet presentation | requestId | consumed once | coordinator consume | duplicate onChange не double-fire |

N/A для sync preference read и debounce gate.

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| logout | pending shake request nil; sheet epoch bump | voice cancel via sheet | preference **сохраняется** (device UX) | N/A | нет orphaned recording после dismiss |
| account switch | same | same | preference stays | N/A | same |
| cold start | detector ready via UIWindow | N/A | default false if missing | N/A | shake ignored until user enables |
| reconnect / partial failure | N/A | N/A | N/A | N/A | N/A |

## Cross-target contracts

- **Canonical owner**: `ShakeToOpenAssistantPreference` + `DeviceShakeDetector`.
- **Writer/reader**: AccountView toggle writes; AppShellView reads on shake.
- **Validator**: `UserDefaults.bool` — missing == false.
- **Raw literal exceptions**: none.

## Locale / theme consumers

- SwiftUI: toggle label via `Text("account.shake-open-assistant.label")`.
- UIKit / notifications: N/A for copy.
- Widgets / Live Activities / App Intents: N/A.
- Cached assets: N/A.

## Compatibility / migration

- Current: no key → false.
- Previous: N/A (new feature).
- Unknown future: ignore.

## Complexity tracking

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|------------|--------------------------------------|
| UIWindow extension override | SwiftUI has no shake API; app-wide | Per-screen UIViewRepresentable first-responder — misses sheets/tabs |
| Force new chat only without recipe | Matches user wording | Always new chat — loses restore when asking about open recipe mid-session |

## Verification

- Build RecipeScalerNative (sim via `resolve-simulator.sh`)
- `bash scripts/lint-i18n.sh`
- Unit tests preference/debounce
- Manual quickstart: pref OFF shake no-op; ON list → new chat+voice; ON recipe → attach+voice
