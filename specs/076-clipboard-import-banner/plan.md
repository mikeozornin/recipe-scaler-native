# План: баннер импорта ссылки из буфера

**Дата**: 2026-09-14  
**Спека**: [spec.md](./spec.md)  
**Research**: [research.md](./research.md)  
**Layout**: [layout.md](./layout.md) · аудит: `bash scripts/audit-ui-layout.sh specs/076-clipboard-import-banner`  
**Data model**: [data-model.md](./data-model.md)  
**Contracts**: [contracts/](./contracts/)  
**Quickstart**: [quickstart.md](./quickstart.md)  
**Ветка**: `076-clipboard-import-banner`

> Канонический project template для Recipe Scaler Native.

## Границы

- **В scope**:
  - In-memory `ClipboardImportStore` + evaluate pasteboard (URL-only ≤25).
  - Нижний баннер по [layout.md](./layout.md): сообщение, `import.lets-go`, свайп вниз.
  - Prefill + auto-submit существующего `ImportRecipeSheet` через расширенный `ImportPresentation`.
  - Игнор своих Copy (`AppPasteboard` + существующие call sites в app target).
  - Teardown на logout; гейты sheet / offline / pending Share / тост.
  - i18n `import.clipboard-banner.message`; unit-тесты классификатора/памяти/гейтов.
- **Вне scope**:
  - Web; персист dismissed URL; тихий импорт без sheet; показ URL; Share/Action код.
  - Pixel-perfect / `layout-acceptance.json` в этом заходе (продукт: «потом разберёмся»).
- **STOP conditions**:
  - Не читать `.string`, если нет вероятного web URL.
  - Не писать dismissed на диск.
  - Не обходить `ImportRecipeSheet.submit()` новым API-клиентом.
  - Если `resetState()` снова стирает seed — чинить порядок, не костылить второй sheet.
  - Не класть store в `.shared`.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | Импорт как 010 через сервер; Y.Doc не трогаем |
| Web parity | N/A | Native-only clipboard UX; REST импорта не меняется |
| Offline-first | PASS | Баннер скрыт, когда Text-импорт недоступен |
| Native UI | PASS | SwiftUI overlay + существующий sheet |
| Phased delivery | PASS | classifier/store → presentation seed → banner chrome → copy facade → tests |
| i18n | PASS | xcstrings, без fallback, `import.lets-go` reuse |
| Documentation | PASS | spec, layout, research, data-model, contracts, quickstart, этот план |

Post-design: gates без изменений. Native-only — Complexity tracking.

## Очерёдность

1. **Candidate + fake pasteboard tests** — `ImportContentClassifier` уже есть; чистый store без UI. Не зависит от layout.
2. **ImportPresentation seed + auto-submit** — иначе кнопка баннера некуда. Покрыть порядок reset → seed → submit unit/логикой sheet.
3. **Store в AppContainer + evaluate на scenePhase / pasteboard change + logout**.
4. **Баннер + overlay + FAB lift + i18n** — по layout.md; acceptance hash не блокер.
5. **AppPasteboard + перевод Copy call sites**.
6. **Гейты**: sheet open, offline, pending recipe id, toast, >25, no session.
7. **Build, lint-i18n, audit-ui-layout, quickstart**.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNative/Services/ClipboardImportStore.swift` | Создать | visible state, memory, evaluate epoch |
| `RecipeScalerNative/Utils/AppPasteboard.swift` | Создать | свои записи + changeCount |
| `RecipeScalerNative/Views/ClipboardImportBannerLayout.swift` | Создать | токены layout.md |
| `RecipeScalerNative/Views/ClipboardImportBanner.swift` | Создать | плашка, свайп, previews |
| `RecipeScalerNative/App/AppContainer.swift` | Изменить | store, `clearForLogout` |
| `RecipeScalerNative/App/AppEnvironment.swift` | Изменить | `.environment(container.clipboardImport)` |
| `RecipeScalerNative/Routing/AppShellCoordinator.swift` | Изменить | seed/autoSubmit на `ImportPresentation` |
| `RecipeScalerNative/Views/ImportRecipeSheet.swift` | Изменить | seed после reset, auto-submit |
| `RecipeScalerNative/Views/AppShellView.swift` | Изменить | overlay, evaluate, FAB padding, скрыть при тосте |
| `RecipeScalerNative/Views/RecipeDetailShareButton.swift` | Изменить | Copy через facade |
| `RecipeScalerNative/Views/ShoppingListView.swift` | Изменить | Copy через facade |
| `RecipeScalerNative/Views/AssistantMessageFooter.swift` | Изменить | Copy через facade |
| `RecipeScalerNative/Views/TelegramConnectionView.swift` | Изменить | Copy через facade |
| `RecipeScalerNative/AccessibilityIdentifiers.swift` | Изменить | banner / message / action |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменить | `import.clipboard-banner.message` en+ru |
| `RecipeScalerNative.xcodeproj/project.pbxproj` | Изменить | новые файлы в target |
| `RecipeScalerNativeTests/ClipboardImportStoreTests.swift` | Создать | invariants |
| `RecipeScalerNativeTests/ClipboardImportCandidateTests.swift` | Создать | URL-only / mixed / limit |

`UIPasteboard.general.string =` в UI-тестах можно оставить прямым (не app target).

## Downstream consumers

- **SwiftUI views**: `AppShellView`, `ClipboardImportBanner`, `ImportRecipeSheet`. Не виджеты.
- **Cross-process**: widgets, extensions, watchOS, Live Activity, App Intents — N/A. Share Extension не меняем; только гейт pending recipe id на входе.
- **Sync boundaries**: Yjs/CRDT, web, серверный contract — N/A (импорт как 010).
- **Persisted state**: ничего. Не SQLite, не UserDefaults, не App Group, не Keychain.
- **Tests / verify scripts**: `ClipboardImport*Tests`; `lint-i18n.sh`; `audit-ui-layout.sh specs/076-clipboard-import-banner`; ручной [quickstart.md](./quickstart.md). Отдельный `verify-076-*.sh` не обязателен в v1 (pasteboard на симе хрупкий); если появится — behavioral assertion, не `rg`.

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| pasteboard `https://a.example/` | candidate URL-only, banner eligible | `ClipboardImportCandidateTests.test_single_https_is_candidate` |
| «смешайте муку https://a.example/» | не candidate | `test_mixed_text_not_candidate` |
| два URL без текста | один candidate из дедупа | `test_multiple_urls_only` |
| swipe A, evaluate A | `state == .hidden` | `ClipboardImportStoreTests.test_dismiss_survives_foreground` |
| swipe A, буфер B | visible B | `test_new_url_reshows` |
| dismiss A, новый store | A снова eligible | `test_memory_clears_on_new_session` |
| `markConsumed(A)` | A hidden | `test_successful_import_consumes` |
| cancel import A | A не consumed | `test_failed_import_does_not_consume` |
| own changeCount | не eligible | `test_ignores_own_copy` |
| import sheet presented | hidden | `test_hidden_when_import_sheet_open` |
| 26 URL | не eligible | `test_over_limit_hidden` |
| logout mid-evaluate | stale generation не ставит visible | `test_stale_evaluate_after_logout` |

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| `evaluate()` (detectPatterns + optional string) | `evaluateGeneration` + `userId` | generation и userId; sheet всё ещё закрыт | store `clearForLogout` / новый evaluate bump | logout → visible не ставится |
| auto-submit `submit()` | `ImportPresentation.id` + seedText | presentation.id тот же; seed не пустой | sheet `importTask` cancel on dismiss | повторный present с новым id; старый task не completeImport |
| pasteboard changed while active | generation | не ignored changeCount | store | own Copy → 0 banner |

N/A для чистого `ImportContentClassifier.classify` (sync).

Single-flight: один in-flight evaluate; новый generation инвалидирует старый результат (`defer` снимает in-flight). Guard **до** первого `await` detectPatterns.

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| swipe | identity ∈ dismissed; hidden | N/A | нет | нет | повторный foreground A → hidden |
| successful import | identity ∈ consumed; hidden | importTask ended | нет | нет | тост 010; баннера нет |
| cancel/error import | memory без consumed | importTask cancel | нет | нет | следующий evaluate может показать |
| logout / account switch / delete | memory empty; generation++ | in-flight evaluate discarded | нет | нет | чужой буфер не всплывает |
| stale session / cold start | пустой store | N/A | нет | нет | баннер только после нового eligible evaluate |
| background | dismissed жив | нет polling | нет | нет | |
| reconnect / offline | hidden пока Text недоступен | N/A | нет | нет | online + тот же URL → можно снова visible если не dismissed |
| process death | всё пусто | — | нет | нет | та же ссылка может показаться |

## Cross-target contracts

- **Canonical owner**: этот план + [contracts/clipboard-candidate.md](./contracts/clipboard-candidate.md) + [contracts/import-presentation.md](./contracts/import-presentation.md).
- **Writer/reader targets**: только native app target. Extensions не читают store.
- **Validator/normalizer**: только `ImportContentClassifier` для URL-only. Не дублировать regex в store.
- **Raw literal exceptions**: `http`/`https` уже в классификаторе; SF Symbol если появится в баннере v1 — **не** добавлять без правки layout.md. User copy только xcstrings.

## Locale / theme consumers

- SwiftUI environment: `Text("import.clipboard-banner.message")`, `Text("import.lets-go")`, `.appBody()`, light/dark material/glass из layout.md; `\.locale` как остальные ключи.
- UIKit / notification categories / scheduled content: N/A.
- Widgets / Live Activities / App Intents: N/A.
- Cached or generated assets: N/A.
- `.system` effective value: colorScheme для material; не форсить light в проде. Preview light/dark отдельные.

## Compatibility / migration

- Current format/contract: нет persisted format.
- Previous supported format: N/A.
- Missing version/default behavior: нет ключа → нет баннера до evaluate.
- Unknown future version/ID behavior: N/A. Неизвестный pasteboard тип → hidden.
- Required legacy fixture tests: mixed text, empty, >25 URL.

## Unknown IDs and fallback policy

- DEBUG/CI: неизвестный accessibility id в тестах — hard fail если тест его ждёт.
- Release: нет candidate → hidden + нет user-facing ошибки. `AppLog` на английском при evaluate fail.
- Legacy aliases: нет. Prefix match URL запрещён — только классификатор.

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app`/`.appex` assertion |
|----------|----------|---------------|----------------|---------------------------------|
| N/A | нет новых catalog assets | — | — | — |

i18n — `Localizable.xcstrings`, не codegen.

## Human gates

- [x] `layout.md` существует; продукт разрешил идти без pixel-lock (2026-09-14, «потом разберёмся»).
- [ ] `layout-audit.json` static audit: до view ожидаем FAIL missing files; после impl — STATIC PASS.
- [ ] `layout-acceptance.json` — **не блокер** этого плана; завести когда будете править вёрстку.
- [ ] Отдельный review-agent после кода; self-review не замена.

## Verification

- `SPECIFY_FEATURE_DIRECTORY=specs/076-clipboard-import-banner bash scripts/verify-plan-state.sh` — печатает `PLAN STATE: specs/076-clipboard-import-banner`, exit 0.
- `bash scripts/audit-ui-layout.sh specs/076-clipboard-import-banner` — до view: FAIL missing Swift = ожидаемо; после view: STATIC PASS, acceptance pending.
- `xcodebuild` build по [docs/AGENT-WORKFLOW.md](../../docs/AGENT-WORKFLOW.md) — exit 0 после кода.
- Unit `ClipboardImport*` — pass (таблица invariants).
- `bash scripts/lint-i18n.sh` — exit 0 после ключа.
- Manual [quickstart.md](./quickstart.md): показ / импорт / свайп / негатив Copy.
- Device pasteboard: `INCONCLUSIVE`, если нет доступа к симулятору; не выдавать VERIFIED за один build.

## Rollback / maintenance

- Как откатить: убрать overlay и store из AppContainer; `presentImport()` без seed остаётся; facade Copy можно оставить (безвреден).
- Что будет взаимодействовать: 010 sheet `resetState`; 025 pending recipe id; 066 offline gating Text; FAB/timer chrome; любые новые `UIPasteboard.general.string =` без facade снова включат баннер на своих Copy.
- Временные allowlist/quarantine: нет.

## Complexity tracking

| Отступление | Почему | Альтернатива отвергнута |
|-------------|--------|-------------------------|
| Нет web parity | Другая модель clipboard в браузере | Тянуть web banner |
| Нет layout-acceptance | Продукт отложил pixel | STOP до Figma |
| Нет verify-076.sh в v1 | OS pasteboard плохо автоматизируется | Фейковый VERIFIED по `rg` |
