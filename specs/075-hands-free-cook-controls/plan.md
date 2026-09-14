# План: Hands-free прокрутка при keep-awake

**Дата**: 2026-09-14 (rev 3)  
**Спека**: [spec.md](./spec.md)  
**Research**: [research.md](./research.md)  
**Layout**: [layout.md](./layout.md) · аудит: `bash scripts/audit-ui-layout.sh specs/075-hands-free-cook-controls`  
**Data model**: [data-model.md](./data-model.md)  
**Contracts**: [contracts/](./contracts/)  
**Quickstart**: [quickstart.md](./quickstart.md)  
**Ветка**: текущая рабочая (small/medium; отдельная ветка не требуется, пока не попросят).

> Канонический project template для Recipe Scaler Native.

## Границы

- **В scope**:
  - Opt-in Hands-free: ellipsis-меню в `ScreenAwakeStatusBanner` (флажок + help sheet).
  - `±75%` вертикальный scroll основного `ScrollView` карточки при F1.1.
  - Voice whitelist RU/EN; Hand XOR Face по TrueDepth; общий cooldown.
  - Probe UIScrollView; view-local `AwakeScrollController`.
  - Permissions при первом Hands-free ON; teardown на HF OFF / awake OFF / leave / background / cooking cover / assistant.
  - i18n меню/справки; расширить privacy usage strings; unit tests.
- **Вне scope**:
  - Cook matrix Next/Back/List; App Intents; 056 CookingModeView / TTS / SpeechAnalyzer.
  - Web parity; wake word; отдельный выбор Face vs Hand в меню.
  - Вторая toolbar-кнопка Hands-free.
- **STOP conditions**:
  - **STOP до SwiftUI chrome** (banner Menu, help sheet, camera preview), пока человек не принял [layout.md](./layout.md) (не static audit). Engine + unit tests без view — можно параллельно.
  - Если probe не находит host ScrollView на живой карточке (read и edit) — STOP: no-op + `AppLog`, не изобретать `scrollTo` id.
  - Если keep-awake без HF начинает запрашивать mic/camera — STOP, это регресс rev 3.
  - Не чинить 074 cooking UI из этой спеки.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | Нет записи в Y.Doc. Pref — UserDefaults. |
| Web parity | N/A | Native-only hands-free; web не имеет этого chrome. |
| Offline-first | PASS | On-device Speech/Vision/ARKit. |
| Native UI | PASS | SwiftUI detail + banner; WKWebView только существующее описание. |
| Phased delivery | PASS | Foundation engine → US0 menu (после layout) → voice → hand → face → teardown. |
| i18n | PASS | `recipe.awake-scroll.*` + privacy InfoPlist strings. |
| Documentation | PASS | spec, layout, research, data-model, contracts, tasks, этот план. |

Post-design: gates без изменений. Complexity: native-only + opt-in banner — принято в spec rev 3.

## Очерёдность

1. **Scroll engine + clamp tests** — чистая функция, без permissions. Layout review не блокирует.
2. **Detail ScrollView probe** — иначе voice/жесты некуда применять. Не ломать caret-anchor.
3. **AwakeScrollController arm predicate + epoch teardown** — F1.1 / cooking cover / scenePhase. Зависимости: 1–2.
4. **Human review `layout.md`** — STOP для banner Menu / sheet / preview.
5. **Banner Menu + Help sheet + i18n** — после 4. Pref UserDefaults.
6. **Voice classifier + SF listening** — зависит от 3; UI индикация от 5.
7. **Hand classifier + capture** — XOR: только без TrueDepth.
8. **Face blink + TrueDepth gate**.
9. **Permissions strings + denied paths + verify/build**.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNative/Services/Cooking/AwakeScrollAction.swift` | Создать | `.up` / `.down` |
| `RecipeScalerNative/Services/Cooking/AwakeScrollEngine.swift` | Создать | delta 0.75, clamp |
| `RecipeScalerNative/Services/Cooking/AwakeScrollController.swift` | Создать | arm/epoch/cooldown |
| `RecipeScalerNative/Services/Cooking/AwakeHandsFreeStorage.swift` | Создать | UserDefaults pref |
| `RecipeScalerNative/Services/Cooking/AwakeScrollVoiceClassifier.swift` | Создать | whitelist |
| `RecipeScalerNative/Services/Cooking/AwakeScrollVoiceEngine.swift` | Создать | SFSpeechRecognizer |
| `RecipeScalerNative/Services/Cooking/AwakeScrollHandClassifier.swift` | Создать | thumb sectors |
| `RecipeScalerNative/Services/Cooking/AwakeScrollFaceClassifier.swift` | Создать | blink L/R |
| `RecipeScalerNative/Services/Cooking/AwakeScrollCaptureSession.swift` | Создать | Face XOR Hand + teardown |
| `RecipeScalerNative/Views/DetailScrollViewProbe.swift` | Создать | weak UIScrollView |
| `RecipeScalerNative/Views/AwakeScrollLayout.swift` | Создать | токены |
| `RecipeScalerNative/Views/AwakeScrollHelpSheet.swift` | Создать | справка |
| `RecipeScalerNative/Views/AwakeScrollCameraPreview.swift` | Создать | 48○ overlay, optional |
| `RecipeScalerNative/Views/ScreenAwakeStatusBanner.swift` | Изменить | Menu ellipsis |
| `RecipeScalerNative/Views/YDocRecipeDetailView.swift` | Изменить | probe + controller wire |
| `RecipeScalerNative/Views/YDocRecipeDetailScrollSupport.swift` | Не менять caret API | Hands-free не через editor ancestor |
| `RecipeScalerNative/AccessibilityIdentifiers.swift` | Изменить | menu / toggle / help |
| `RecipeScalerNative/Info.plist` | Изменить | speech usage; расширить camera/mic |
| `RecipeScalerNative/Resources/InfoPlist.xcstrings` | Изменить | en+ru privacy |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменить | `recipe.awake-scroll.*` |
| `RecipeScalerNativeTests/AwakeScrollEngineTests.swift` | Создать | 75% + clamp |
| `RecipeScalerNativeTests/AwakeScrollVoiceClassifierTests.swift` | Создать | whitelist |
| `RecipeScalerNativeTests/AwakeScrollHandClassifierTests.swift` | Создать | sectors |
| `RecipeScalerNativeTests/AwakeScrollFaceClassifierTests.swift` | Создать | blink map |
| `RecipeScalerNativeTests/AwakeScrollControllerTests.swift` | Создать | F1.1 + teardown |
| `scripts/verify-075-hands-free-cook-controls.sh` | Создать по желанию | иначе unit + manual quickstart |

`AppContainer` — **не** добавлять сервис.

## Downstream consumers

- **SwiftUI views**: `YDocRecipeDetailView`, `ScreenAwakeStatusBanner`, `AwakeScrollHelpSheet`, optional preview. `ProcessTableCookingView` не показывает HF chrome, но **disarm** когда cover presented.
- **Cross-process**: widgets, extensions, watchOS, Live Activity, App Intents — N/A, фича не выходит за процесс приложения.
- **Sync boundaries**: Yjs/CRDT, web, серверный contract — N/A.
- **Persisted state**: UserDefaults `awakeHandsFreeEnabled`. Не SQLite, не Keychain, не App Group.
- **Tests / verify scripts**: `AwakeScroll*Tests`; `lint-i18n.sh`; `audit-ui-layout.sh specs/075-hands-free-cook-controls` (до view ожидаем FAIL по missing files).

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| `.down` при y=0, bounds.height=400 | y → 300 | `AwakeScrollEngineTests.test_down_scrolls_75_percent` |
| `.down` у конца | y == maxOffset | `test_down_clamps_end` |
| `.up` при y=0 | y == 0 | `test_up_clamps_start` |
| transcript «вниз» | `.down` | `AwakeScrollVoiceClassifierTests.test_ru_vniz` |
| «stop» / «toppings» | nil (не fire) | `test_rejects_near_miss` |
| thumb up-sector hold | один `.up` | `AwakeScrollHandClassifierTests.test_hand_up_once` |
| blink left | `.up` | `AwakeScrollFaceClassifierTests.test_left_up` |
| F1.1 false после armed | capture+speech stop | `AwakeScrollControllerTests.test_predicate_false_teardown` |
| HF off, awake on | idle timer disabled, нет session | `test_hands_free_off_keeps_awake` |
| awake on, HF pref false | нет AVCapture | `test_awake_only_no_camera` |
| cooking presentation set | teardown, pref не сброшен | `test_cooking_cover_disarm` |

Негатив «не должно сломаться» недостаточен — каждый teardown имеет положительный postcondition в таблице Teardown.

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| `requestPermissions` | `sessionEpoch` + `recipeId` | F1.1; тот же epoch | `AwakeScrollController.stop()` | stale epoch → не start capture |
| `startVoice` | `epoch` + `voiceSessionId` | F1.1 + id | controller / voice engine | re-arm с новым id; старый task discarded |
| speech 60s re-arm | `voiceSessionId` | id match | voice engine | inherit: late result ignored |
| vision/ARKit frame | `epoch` | epoch match | capture session | stale frame dropped, 0 scroll |
| `setContentOffset` | `epoch` | F1.1; scrollView === probe | MainActor controller | no-op если probe nil |
| start capture | `epoch` | F1.1 после configuration await | controller | cooking cover mid-start → stop |

N/A для чистого `AwakeScrollEngine.apply` (sync).

Single-flight: `isStarting` до первого `await` permission/session, `defer` снимает. Новый epoch инвалидирует in-flight start.

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| HF toggle OFF | epoch++; modality idle | speech task cancel; capture stop | pref = false | camera indicator off | idle timer всё ещё disabled если awake |
| awake OFF / `deactivateScreenAwake` | epoch++; controller idle | same | pref **kept** | camera off; idle timer enabled | баннер скрыт |
| leave detail / recipeId change | controller deinit/stop | same | pref kept | camera off | нет listening на другом рецепте |
| background (`scenePhase`) | существующий awake off | same | pref kept | camera off | как сегодня keep-awake |
| cooking cover present | CoverDisarmed | same | pref kept | camera off | матрица без green dot от HF |
| cooking dismiss | re-arm если F1.1 | start если нужно | pref | camera on только если HF | |
| assistant sheet open | как cover | same | pref kept | camera off | |
| logout / account switch | stop | same | pref kept (device) | camera off | нет чужой сессии STT |
| stale / cold start | не restore capture | N/A | pref читается | N/A | HF не стартует пока нет visible detail+awake |
| reconnect / partial permission fail | каналы по snapshot | failed engine stopped | pref may stay true | no capture if denied | карточка usable |
| permission denied both | armed no-op | no streams | pref | no camera | keep-awake работает |

## Cross-target contracts

- **Canonical owner**: этот spec + [contracts/](./contracts/).
- **Writer/reader targets**: только native UI. Web не читает pref.
- **Validator/normalizer**: `AwakeScrollVoiceClassifier` / hand / face — единственные адаптеры whitelist и blink map. Не размазывать литералы по view.
- **Raw literal exceptions**: системные SF Symbol `"ellipsis"`, `"sun.max"` — OS names, не user-facing copy. Voice phrases живут в classifier (не UI); UI copy только xcstrings.

## Locale / theme consumers

- SwiftUI environment: `Text("recipe.awake-scroll.*")`, `common.screen-always-on`, `common.close`; `.appBody()` / `.appFootnote()`; баннер semantic green как сейчас; help sheet light/dark system background.
- UIKit / notification categories / scheduled content: N/A.
- Widgets / Live Activities / App Intents: N/A.
- Cached or generated assets: N/A.
- `.system` effective value: banner colors уже от `colorScheme`; preview не форсирует light.

Privacy usage — `InfoPlist.xcstrings` (системный диалог, не `\.locale` приложения). en+ru заполнить.

## Compatibility / migration

- Current format/contract: pref Bool `awakeHandsFreeEnabled`.
- Previous supported format: ключа нет.
- Missing version/default behavior: nil → `false` (Hands-free OFF).
- Unknown future version/ID behavior: N/A (нет versioned blob). Неизвестный transcript → nil action, не «умный» prefix match.
- Required legacy fixture tests: classifier rejects empty / unrelated speech; engine clamp на height 0.

## Unknown IDs and fallback policy

- DEBUG/CI: неизвестный accessibility route не нужен. Неизвестный modality raw, если появится — hard fail в тестах.
- Release: unknown transcript → ignore + optional debug log (English). Camera/speech unavailable → US5 safe UI, `AppLog`.
- Legacy aliases: нет. Не маппить «ввер» prefix на `.up`.

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app`/`.appex` assertion |
|----------|----------|---------------|----------------|---------------------------------|
| N/A | нет новых catalog assets | — | — | — |

i18n — `Localizable.xcstrings` / `InfoPlist.xcstrings`, не codegen.

## Human gates

- [ ] `layout.md` reviewed by human (**блокер** banner Menu, help sheet, preview).
- [ ] `layout-audit.json` static audit passed (ожидаемо FAIL до файлов view; после impl — STATIC PASS).
- [ ] Human acceptance artifact актуален для hash `layout.md` (ещё нет).
- [ ] Отдельный review-agent после кода; self-review не замена.

## Verification

- `bash scripts/audit-ui-layout.sh specs/075-hands-free-cook-controls` — до view: FAIL missing files = ожидаемо; после view: STATIC PASS.
- `xcodebuild` build по [docs/AGENT-WORKFLOW.md](../../docs/AGENT-WORKFLOW.md) — exit 0.
- Unit `AwakeScroll*` — pass (positive invariants).
- `bash scripts/lint-i18n.sh` — exit 0 после ключей.
- Manual [quickstart.md](./quickstart.md) на iPhone 13 Pro: awake-only без camera dot; HF ON → 75% step; HF OFF → dot off.
- Expected: не считать фичу VERIFIED без human layout-acceptance и device pass по camera.

`verify-plan-state.sh` — N/A если скрипта нет под 075; не выдумывать зелёный verify без assertions.

## Rollback / maintenance

- Как откатить: удалить Menu/controller wire; `sun.max` и баннер текста остаются как сегодня; UserDefaults ключ безвреден.
- Что будет взаимодействовать: 056, если когда-то повесит STT на cooking — не делить `AVAudioSession` с detail HF (cover уже disarm). QR scanner тоже камера — HF обязан быть off вне detail.
- Временные allowlist/quarantine: нет.

## Complexity tracking

| Отступление | Почему | Альтернатива отвергнута |
|-------------|--------|-------------------------|
| Нет web parity | Hands-free native; web не в scope | Тянуть web API |
| Не 056 provider | 056 не в коде; другой command set | Блокировать 075 на 056 |
| Pref в UserDefaults | device UX, не sync | CRDT / сервер |
