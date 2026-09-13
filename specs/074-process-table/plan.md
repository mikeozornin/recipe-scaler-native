# План: Таблица процесса — native

**Дата**: 2026-09-12  
**Спека**: [spec.md](./spec.md)  
**Layout**: [layout.md](./layout.md) · аудит: `bash scripts/audit-ui-layout.sh specs/074-process-table`  
**Канон wire**: [`../../../recipe-scaler-web/specs/074-process-table/spec.md`](../../../recipe-scaler-web/specs/074-process-table/spec.md)  
**Ветка**: `master` (small/medium feature; отдельная ветка не требуется, пока не попросят).

> Канонический project template для Recipe Scaler Native.

## Границы

- **В scope**:
  - Decode `Y.Map('recipe').processTable`, Do-No-Harm на write, порт `sourceHash`.
  - Кнопка «Начать готовить» справа от заголовка шагов; системный iOS landscape на iPhone; iPad без forced rotate.
  - Матрица: prep-стек, merge consecutive, sticky 25%, scaled amounts, локальные чекбоксы, таймеры по `stepIndex`.
  - Stale-баннер + `POST /api/recipes/:id/rebuild-process-table`.
  - i18n `recipe.process-table.*`, тесты hash/merge/preserve, layout primitives.
- **Вне scope**:
  - Сервер / web UI / backfill / редактор маппинга / голос 056 / web split 1/3+2/3.
- **STOP conditions**:
  - **STOP до SwiftUI экранов**, пока человек не принял [layout.md](./layout.md) (не static audit). Decode/hash/tests без view — можно параллельно.
  - Если `requestGeometryUpdate` на iOS 17 не крутит окно — STOP: оставить cover в текущей ориентации. **Не** чинить 90° `rotationEffect`.
  - Если какой-то recipe writer делает `clear()` recipe map — STOP, чинить preserve до UI.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | PASS | Ключ в Y.Doc. Чекбоксы сознательно не CRDT (как web sessionStorage). |
| Web parity | PASS | Schema/hash/merge = web. Chrome — iOS HIG, не web overlay. |
| Offline-first | PASS | Матрица с локального снимка; rebuild только online. |
| Native UI | PASS | SwiftUI; WKWebView не для матрицы. |
| Phased delivery | PASS | P1 decode+hash+preserve (+ layout review); P2 cooking UI; P3 stale/rebuild + checks/timers. |
| i18n | PASS | Только `recipe.process-table.*` + существующие `common.close` / `time.short`. |
| Documentation | PASS | spec, layout, этот план, contracts, `docs/YJS-SCHEMA.md` уже содержит ключ. |

Post-design: без изменений gates. Complexity: cooking chrome ≠ web overlay — принято в spec.

## Очерёдность

1. **Decode + hash + preserve tests** — без UI; ловит wipe ключа. Зависимости: schema, TS hash. Layout review не блокирует.
2. **Human review `layout.md`** — STOP для view. Зависимости: нет.
3. **Токены + примитивы + `#Preview` на stub** — после review. Зависимости: 2.
4. **Cooking assembly + geometry update + CTA в header шагов** — зависит от 3. Discover тем же CTA.
5. **Stale banner + rebuild REST** — зависит от 1; UI баннера от 3.
6. **Checks + timer chips + keep-awake restore** — зависит от 4.
7. **i18n lint, unit/UITest, `audit-ui-layout`, build** — зависит от 1–6.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNative/Models/YDoc/ProcessTableV1.swift` | Создать | decode schema |
| `RecipeScalerNative/Models/YDoc/RecipeData.swift` | Изменить | `processTableRaw` |
| `RecipeScalerNative/Services/YjsSync/RecipeYjsCodec.swift` | Изменить | читать raw string |
| `RecipeScalerNative/Services/YjsSync/RecipeYjsWriter.swift` | Изменить | не drop ключа на full write |
| hash helper (рядом с readers) | Создать | порт TS |
| `RecipeScalerNative/Views/Cooking/ProcessTableLayout.swift` | Создать | токены |
| `ProcessTableStartButton` / `StatusBanner` / `PrepStack` / `Grid` / `TimerChip` / `CookingView` | Создать | layout primitives + assembly |
| `YDocRecipeDetailView.swift` | Изменить | CTA, banner в edit, cover |
| `DiscoverRecipeView.swift` | Изменить | тот же CTA |
| `RecipeScalerCore/Networking/APIClient.swift` | Изменить | rebuild path |
| rebuild ViewModel (как nutrition, с тостом) | Создать | async lifecycle |
| `AppContainer` / env | Изменить | только если нужен новый сервис; иначе `apiClient` env |
| `Localizable.xcstrings` | Изменить | ключи spec |
| `AccessibilityIdentifiers.swift` | Изменить | start/close/grid |
| `docs/YJS-SCHEMA.md` | Сверить | ключ уже есть |
| Tests: hash, decode, merge, preserve, rebuild single-flight | Создать | positive invariants |

## Downstream consumers

- **SwiftUI views**: `YDocRecipeDetailView`, `DiscoverRecipeView`, новые `Views/Cooking/ProcessTable*`. Nutrition banner не заменяем.
- **Cross-process**: таймеры/Live Activity — существующий `TimerManager`. Widgets / Share / App Intents матрицу не показывают. N/A для нового IPC.
- **Sync boundaries**: Yjs `processTable` (server writer, native reader). REST rebuild. Hash должен совпасть с web.
- **Persisted state**: raw JSON в Y-снимке SQLite. Чекбоксы не персистить. UserDefaults не использовать для checks.
- **Tests / verify scripts**: unit + UITest CTA в строке шагов; `lint-i18n.sh`; `audit-ui-layout.sh` (до view ожидаем FAIL по missing files).

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| Sync валидной v1 | `RecipeData.processTableRaw` не nil, decode `version==1` | `ProcessTableDecodeTests` |
| Битый JSON | decode nil, raw на месте, save не `remove` ключ | `ProcessTablePreserveTests` |
| `updateIngredient` | ключ `processTable` всё ещё в map | `ProcessTablePreserveTests` |
| Rename имени | `sourceHash` тот же | `ProcessTableHashTests` |
| Смена `originalAmount` | хеш другой → stale | `ProcessTableHashTests` |
| Assignments rows 2–4 | один span, row 5 empty | `ProcessTableMergeTests` |
| Тап start, valid v1 | fullScreenCover cooking | UITest `recipe_process_table_start` |
| Host cooking 6×6 в UIWindow | grid + Close в иерархии; все frame finite; present() не dismiss после layout | `ProcessTableCookingLayoutTests` |
| Present cooking на живой UIWindowScene | `requestGeometryUpdate` без ошибки; scene landscape; host presented | `ProcessTableCookingSceneTests` |
| Rebuild 200 | после refresh баннер скрыт | unit + ручная |
| Logout mid-rebuild | нет тоста чужой сессии | stale-completion test |
| Close cooking | checks пустые | unit session teardown |

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| `rebuildProcessTable` | `recipeId` + `userId` + `rebuildGeneration` | cancelled; тот же recipeId/userId/generation | dismiss cooking/edit, logout, `onDisappear` | generation++ → нет toast, нет refresh чужого doc |
| `refreshCurrentRecipe` после 200 | тот же `recipeId` | документ всё ещё этот | cancel с rebuild Task | не применить баннер к другому recipe |
| Geometry update | cooking session token | cover ещё presented | dismiss | поздний rotate не открывает cooking заново |
| Timer start from chip | `recipeId` + chip id | cooking ещё open | dismiss | не стартовать после close |

Single-flight: `isRebuilding` до первого await, `defer` снимает.

N/A для чистого decode/hash (sync).

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| logout | CookingSession discarded; cover dismiss | rebuild cancelled | Yjs snapshots чужого user не читаем | geometry lock снят; awake restore | нет toast, нет чужой матрицы |
| account switch | то же | то же | то же | то же | то же |
| stale session / cold start | session не restore | N/A | ключ в SQLite Y snapshot | N/A | после login decode с диска |
| reconnect / partial failure | таблица с снимка | busy сброшен | ключ на месте | N/A | CTA видна; rebuild снова enabled если owner |
| dismiss cooking | checks empty | rebuild cancel если с этого экрана | N/A | orientation portrait via Close; awake restore | карточка portrait |

## Cross-target contracts

- **Canonical owner**: web spec 074 + [contracts/process-table-v1.schema.json](./contracts/process-table-v1.schema.json).
- **Writer/reader targets**: server пишет ключ; native читает. Native writer MUST preserve. Rebuild — native POST, server пишет Yjs.
- **Validator/normalizer**: native decode subset (version/required). Sanitize LLM — только server. Hash — [contracts/source-hash.md](./contracts/source-hash.md). Merge — [contracts/merge-spans.md](./contracts/merge-spans.md).
- **Raw literal exceptions**: N/A для UI. JSON ключи wire (`processTable`, `sourceHash`) — schema, не user-facing.

## Locale / theme consumers

- SwiftUI: `Text("recipe.process-table.*")`, `.appBody()` / `.appFootnote()`, `common.close`, `time.short`.
- UIKit / notification categories: N/A.
- Widgets / Live Activities / App Intents: таймерный chip стартует существующий timer (может поднять Live Activity) — не новый copy.
- Cached assets: illustration 40 pt slot, те же бандлы 043.
- `.system` effective: light/dark semantic colors; fill ячейки `secondarySystemFill`.

## Compatibility / migration

- Current: `ProcessTableV1` version 1.
- Previous: ключа нет — классика, кнопки нет.
- Missing version / non-1: как нет ключа; raw не удалять.
- Unknown future version: скрыть UI, preserve raw (не парсить extra fields в write-back).
- Legacy fixtures: рецепт без ключа; v1/v2 read-only с валидной таблицей (CTA да, rebuild нет).

## Unknown IDs and fallback policy

- DEBUG/CI: неизвестный `kind` колонки / битый schema → decode fail (тест). Не маппить prefix.
- Release: как нет таблицы + `AppLog` (английский); ключ в Yjs.
- Legacy aliases: нет. `columnId` stored = UUID, не индекс LLM.

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app` assertion |
|----------|----------|---------------|----------------|------------------------|
| N/A | нет новых asset catalog / xcresource | — | — | — |

i18n — `Localizable.xcstrings`, не generated codegen.

## Human gates

- [x] `layout.md` reviewed by human (**блокер view**).
- [ ] `layout-audit.json` static audit passed (ожидаемо FAIL до файлов view; после impl — STATIC PASS).
- [x] Human acceptance `layout-acceptance.json` с hash `layout.md` (`2ebe2366ef4d62bd`, 2026-09-12).
- [ ] Отдельный review-agent после кода; self-review не замена.

## Verification

- `bash scripts/audit-ui-layout.sh specs/074-process-table` — после view: exit 0 STATIC PASS (без `--strict` пока нет human acceptance).
- `xcodebuild` build (workflow simulator) — exit 0.
- Unit: hash / decode / merge / preserve / rebuild single-flight — pass.
- `bash scripts/lint-i18n.sh` — exit 0.
- UITest: CTA появляется на fixture с ключом; отсутствует без ключа.
- Expected: не считать фичу VERIFIED без human layout-acceptance.

## Rollback / maintenance

- Откат UI: убрать CTA/cover; ключ в Yjs безобиден для старых сборок.
- Decode оставить, если UI откатываем — иначе следующий save теоретически опасен без preserve tests.
- Будущее: 056 вешает голос на `ProcessTableCookingView`, не вторую кнопку.
- Web flag `PROCESS_TABLE_WEB_UI_ENABLED` не включать из этой native работы.

## Complexity tracking

| Отступление | Почему | Альтернатива отвергнута |
|-------------|--------|-------------------------|
| Cooking chrome ≠ web overlay/split | iOS nav bar + geometry update | Копировать web-phone или 90° картинку |
