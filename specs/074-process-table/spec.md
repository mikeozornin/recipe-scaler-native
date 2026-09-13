# Спецификация: Таблица процесса — native

**Feature Branch**: `074-process-table`  
**Дата**: 2026-09-12  
**Статус**: Draft  
**Канон (wire / server)**: [`recipe-scaler-web/specs/074-process-table/spec.md`](../../../recipe-scaler-web/specs/074-process-table/spec.md)  
**Схема JSON**: [`recipe-scaler-web/specs/074-process-table/contracts/process-table-v1.schema.json`](../../../recipe-scaler-web/specs/074-process-table/contracts/process-table-v1.schema.json)  
**Хеш**: порт [`recipe-scaler-web/shared/utils/process-table-source-hash.ts`](../../../recipe-scaler-web/shared/utils/process-table-source-hash.ts)

Native — первый пользовательский клиент ключа `processTable`. Web cooking chrome скрыт флагом; сервер уже пишет ключ после импорта.

## Clarifications

### Session 2026-09-12

- Q: Как native входит в режим готовки с матрицей? → A: Кнопка «Начать готовить» + системный iOS landscape (не web overlay).
- Q: Как 074 соотносится с голосовым CookingModeView (spec 056)? → A: **074 владеет** кнопкой и экраном «Готовить». 056 позже навешивает голос на этот же экран. Двух кнопок «Готовить» нет.
- Q: Откуда UI матрицы? → A: Правила формата с web (merge consecutive, prep-стек, sticky колонка ингредиентов) + RecipeTables как модель чтения. Figma не ждём. Перед SwiftUI — `layout.md` + human review.
- Q: Как именно landscape? → A: Сначала YouTube-картинка; **уточнение (тот же день):** системный iOS landscape (`requestGeometryUpdate` + настоящие safe area / nav bar). Не web overlay и не ручной `rotationEffect` «как картинка».
- Q: Кнопка не в toolbar — где? → A: В одной строке с заголовком секции шагов, **справа**.

---

## Границы

**В scope:**

- Чтение `Y.Map('recipe').processTable` (JSON-string `ProcessTableV1`).
- Do-No-Harm: запись recipe map не дропает ключ.
- Локальный `sourceHash` vs текущий канон → stale-баннер; таблица остаётся.
- `POST /api/recipes/:id/rebuild-process-table` (owner, online, ждёт LLM).
- Кнопка «Начать готовить» на карточке (свои рецепты и Discover/public, если ключ валиден).
- Кнопка «Начать готовить» справа от заголовка шагов; системный iOS landscape fullscreen на iPhone.
- Раскладка матрицы: prep-стек, cook-колонки, merge consecutive, scaled amounts, локальные чекбоксы, таймеры по `stepIndex`.
- Keep-awake на время готовки.
- i18n ключей `recipe.process-table.*`.

**Вне scope:**

- Серверная генерация / sanitize / backfill (уже в web-репо).
- Web cooking chrome.
- Редактор маппинга ячеек.
- Голосовой wizard [056](../056-cooking-voice-mode/spec.md) (голоса нет в этом заходе; точка входа одна).
- Library-wide backfill.
- Pixel-parity с web overlay/split (web — эталон **формата**, не пикселей).
- Forced landscape на iPad (см. US2).

---

## Контекст и мотивация

Карточка рецепта — два списка (ингредиенты и шаги). Шаг «смешайте сухие» не раскладывает муку, соду и соль по строкам. Сервер после импорта пишет матрицу ингредиент × шаг. Native должен её показать на кухне: телефон лежит ландшафтом, как шпаргалка, в духе [RecipeTables](https://recipetables.com).

## Цель

1. Ключ доезжает по sync и **не стирается** нативным save.
2. Пользователь с валидной таблицей одним тапом входит в готовку: iOS крутит окно в landscape, матрица на весь экран.
3. Stale не прячет таблицу: баннер + пересчёт у owner online.

---

## Контракт (кратко)

Канон хранения и генерации — web spec § Native contract. Здесь native-якоря.

| Что | Native |
|---|---|
| Decode | JSON-string → `version == 1` и валидные `columns` / `assignments` / `sourceHash`. Иначе как будто ключа нет; ключ не удалять |
| Preserve | `DocumentManager` / recipe writes MUST не дропать неизвестные ключи recipe map (в т.ч. `processTable`) |
| Merge | Подряд идущие `assignments` в cook-колонке → один span; текст — `cellTitles` первой строки span, иначе `columns[].title` |
| Строки | `rowOrder` (first-use); недостающие id — document order без сепараторов. Illustration + scaled `originalAmount` в левой колонке |
| Stale | Локальный SHA-256 канона (`id` + `originalAmount` + `unit` + plain steps) ≠ `sourceHash` → баннер, таблица остаётся. Имена не входят. Scale factor не входит |
| Rebuild | `POST /api/recipes/:id/rebuild-process-table` (Bearer, как `calculate-nutrition`). **Ждёт** LLM. `200` → баннер гаснет после sync. `404`/`500` — тост |
| Checks | Только локально, не Yjs. Живут, пока открыт экран готовки; выход / kill сбрасывает |
| Timers | `timer-reference` в HTML шагов → первая cook-колонка с тем же `stepIndex`; остальные — leftover chips. Тап стартует существующий таймер |
| Scale | Scaled amount только в строке ингредиента, не внутри cook-ячейки |

Импорт на сервере планирует `buildProcessTable` fire-and-forget. После sync ключ появляется без отдельного REST read.

Хеш шагов — с **живого** HTML описания (v1 string / v2 `Y.Text` / v3 XmlFragment→HTML): `<li>`, иначе `<p>`. Не с опустошённого `descriptionText`.

---

## Пользовательские сценарии и тестирование *(обязательно)*

### User Story 1 — Ключ доезжает по sync (Priority: P1)

Пользователь импортировал рецепт (web или native). Сервер позже записал `processTable`. После sync native открывает рецепт — таблица декодируется. Битый JSON / не v1 — классический рецепт, ключ на месте.

**Почему приоритет**: без decode и preserve UI строить нельзя; save не должен уничтожить артефакт.

**Независимое тестирование**: fixture Y.Doc с валидной v1-строкой → decode успешен; битая строка → UI как без ключа, write не стирает поле.

**Acceptance Scenarios**:

1. **Given** импорт записал валидный `processTable`, **When** native открывает рецепт после sync, **Then** ключ декодируется как v1.
2. **Given** битый JSON или `version !== 1`, **When** открыта карточка, **Then** кнопки готовки нет, ключ в Y.Doc остаётся.
3. **Given** валидный `processTable`, **When** пользователь правит имя / ингредиенты / шаги (v3), **Then** ключ остаётся в Y.Doc.

---

### User Story 2 — Начать готовить в системном landscape (Priority: P1)

На карточке с валидной таблицей кнопка «Начать готовить» стоит **справа от заголовка шагов** (та же строка). Тап открывает полноэкранную готовку: iOS крутит окно в landscape (настоящие safe area и navigation bar). Close возвращает карточку в portrait. На iPad forced landscape нет.

**Почему приоритет**: ценность ключа; web-телефон (только landscape без кнопки) на кухне неудобен. Chrome — iOS, не копия web overlay.

**Независимое тестирование**: валидная таблица → CTA справа от заголовка шагов → тап → системный landscape; Close → карточка portrait.

**Acceptance Scenarios**:

1. **Given** валидный `processTable` и карточка не в edit, **When** пользователь смотрит деталку (свои или Discover/public), **Then** видит «Начать готовить» в одной строке с заголовком шагов, справа.
2. **Given** ключа нет / JSON битый / `version !== 1` / edit mode, **When** карточка открыта, **Then** кнопки нет; заголовок шагов на месте.
3. **Given** iPhone и валидная таблица, **When** тап «Начать готовить», **Then** `fullScreenCover` с системным nav bar; окно в landscape через geometry update, без ручного поворота view на 90°.
4. **Given** режим готовки, **When** Close, **Then** возврат на карточку в portrait; чекбоксы этой сессии сброшены.
5. **Given** режим готовки на iPhone, **When** пользователь поворачивает устройство в portrait, **Then** окно остаётся landscape; готовка не закрывается.
6. **Given** iPad, **When** тап «Начать готовить», **Then** fullscreen в текущей ориентации.
7. **Given** режим готовки, **When** экран открыт, **Then** keep-awake включён; выход снимает auto-lock этой сессии (ручной toggle на карточке не ломаем).

---

### User Story 3 — Матрица читается как RecipeTables (Priority: P1)

Prep — ряды над гридом. Cook — колонки. Подряд заполненные ячейки в колонке слиты в один span. Пустых «смесей» справа без assignment нет. Слева ингредиент + scaled количество. Горизонтальный скролл, колонка ингредиентов липкая.

**Почему приоритет**: без merge матрица врёт относительно эталона.

**Независимое тестирование**: fixture с assignments на строках 2–4 одной колонки → один span; строка 5 пустая.

**Acceptance Scenarios**:

1. **Given** assignments на строках 2–4 подряд в cook-колонке и нет на 5, **When** таблица нарисована, **Then** один span на 2–4; строка 5 пустая.
2. **Given** `kind: prep`, **When** таблица нарисована, **Then** prep — полные ряды **над** матрицей (стек в порядке `columns[]`), не колонки грида.
3. **Given** `cellTitles` на первой строке span, **When** span показан, **Then** текст действия из `cellTitles`, иначе `columns[].title`. Шапка колонки без длинного title.
4. **Given** scale factor ≠ 1, **When** строка ингредиента видна, **Then** scaled `originalAmount` в левой колонке, не внутри cook-ячейки.
5. **Given** новый ингредиент без assignment / исчезнувший id, **When** таблица нарисована, **Then** новая строка с пустыми ячейками; пропавший id не рисуется. Колонки из сохранённой таблицы, не из новых `<li>`.

---

### User Story 4 — Stale + пересчёт (Priority: P2)

Правка шагов/amount/unit разъезжает хеш. Таблица остаётся. Owner online видит баннер и может пересчитать. Public / offline / чужой рецепт — только текст, без кнопки. Пересчёт ждёт LLM.

**Почему приоритет**: как КБЖУ: устаревшая шпаргалка лучше пустоты.

**Независимое тестирование**: изменить `originalAmount` → stale; rename имени при том же id → не stale; rebuild 200 → баннер гаснет.

**Acceptance Scenarios**:

1. **Given** валидная v1 и `sourceHash !==` локальный хеш, **When** пользователь в готовке или в edit, **Then** баннер `recipe.process-table.may-be-outdated`; матрица на месте.
2. **Given** owner, online, баннер, **When** тап пересчёта, **Then** `POST /api/recipes/:id/rebuild-process-table`, кнопка disabled на время запроса; после 200 и sync баннер гаснет.
3. **Given** 404 или 500, **When** пересчёт завершился, **Then** тост с ошибкой, баннер остаётся, таблица на месте.
4. **Given** offline / не owner / Discover, **When** таблица stale, **Then** текст баннера без кнопки пересчёта.
5. **Given** edit, ключа ещё нет, owner online, **When** карточка в edit, **Then** баннер `recipe.process-table.not-built` и действие `recipe.process-table.build` (тот же POST).
6. **Given** classic view вне edit, **When** таблица stale, **Then** баннер на классике не дублируем (как web); кнопка «Начать готовить» остаётся, баннер — внутри готовки.
7. **Given** только rename имени ингредиента, **When** хеш пересчитан, **Then** stale нет.

---

### User Story 5 — Чекбоксы и таймеры на кухне (Priority: P2)

«Отмерял» на строке и «шаг сделан» на непустой ячейке — только этот экран, этот телефон. Таймеры из HTML шагов — чипы на первой cook-колонке с тем же `stepIndex`.

**Почему приоритет**: кухня: отметить отмеренное и запустить таймер, не синкать прогресс на web.

**Независимое тестирование**: отметить ячейку → другое устройство / новый вход в готовку без отметок; чип таймера стартует тот же `TimerManager`, что шаги карточки.

**Acceptance Scenarios**:

1. **Given** режим готовки, **When** тап чекбокса строки или непустой ячейки, **Then** отметка локальная; другой девайс / повторный вход после Close — пусто.
2. **Given** `timer-reference` в шаге N, **When** матрица нарисована, **Then** первая cook-колонка с `stepIndex == N` несёт чипы в шапке; остальные таймеры этого рецепта — leftover chips.
3. **Given** чип, **When** тап, **Then** стартует существующий таймер с прежним именем; на чипе короткая длительность (`time.short`), `aria-label` — имя + полная форма.

---

### Edge Cases

- **Нет сети при открытии карточки**: ключ из локального Y-снимка показывается; rebuild disabled.
- **Ключ приехал mid-session**: после sync кнопка «Начать готовить» появляется без перезапуска приложения.
- **Logout / смена аккаунта во время rebuild**: ответ отбрасывается; тост не чужой сессии; чекбоксы сброшены.
- **v1/v2 рецепт**: таблица read-only как и рецепт; rebuild нет (нельзя править → баннер build в edit не показываем; stale в готовке без кнопки, если хеш разъехался с web).
- **Телефон уже в landscape** при тапе: тот же cover, без лишнего geometry fight.
- **Поворот в portrait во время готовки (iPhone)**: интерфейс остаётся landscape, пока пользователь не нажмёт Close (как полноэкранное видео). Не dismiss и не вёрстка матрицы в portrait.
- **Несколько prep**: стек рядов, не колонки.
- **Пустой `rowOrder`**: document order non-separator.
- **Rebuild повторный тап**: single-flight, второй POST не стартует.
- **Уход с экрана во время LLM**: Task отменяется или результат re-check identity; поздний 200 не пишет UI чужому `recipeId`.
- **Copy-to-my-recipes / полная копия Y.Doc**: ключ сохраняется (Do-No-Harm).
- **Reduce Motion**: системная анимация ориентации, без своей кривой.

---

## Требования *(обязательно)*

### Конституционная проверка

- **I. CRDT-First** — PASS: `processTable` живёт в Y.Doc; чекбоксы намеренно не в CRDT.
- **II. Web Parity** — PASS: wire/schema/hash/merge = web canon. Cooking chrome — iOS HIG (не web overlay), web UI скрыт.
- **III. Offline-First** — PASS: матрица с локального снимка; rebuild только online.
- **IV. Native UI** — PASS: SwiftUI, без WebView-оболочки матрицы.
- **V. Phased delivery** — PASS: P1 decode+preserve+вход+матрица; P2 stale/rebuild + checks/timers.

### Функциональные требования

- **FR-001**: Клиент MUST декодировать `processTable` как JSON `ProcessTableV1` (`version === 1`). Иначе ключ игнорировать и не удалять.
- **FR-002**: Любая запись `Y.Map('recipe')` MUST сохранять неизвестные ключи, включая `processTable` (Do-No-Harm). Не `clear()` + rewrite известных полей.
- **FR-003**: Локальный `sourceHash` MUST считаться портом `computeProcessTableSourceHash` / `hashProcessTableFromRecipe`: document order без сепараторов; `originalAmount` + `unit`; имена вне хеша; шаги — plain text из живого HTML (`<li>` иначе `<p>`).
- **FR-004**: `sourceHash !== currentHash` MUST не прятать таблицу.
- **FR-005**: Кнопка «Начать готовить» (`recipe.process-table.toggle.start`) MUST быть на деталке своих рецептов и на Discover/public, если decode v1 успешен и карточка не в edit: **в одной строке с заголовком шагов, справа**, не в toolbar.
- **FR-006**: Тап на iPhone MUST открыть `fullScreenCover` с системным navigation bar и запросить landscape через `requestGeometryUpdate`. Запрещён ручной `rotationEffect` корня как замена ориентации. Close MUST вернуть карточку в portrait.
- **FR-007**: На iPhone пока открыта готовка MUST держать системный landscape (`supportedInterfaceOrientations` = landscapeLeft+Right + повторный `requestGeometryUpdate(.landscape)`). Поворот устройства в portrait MUST NOT закрывать готовку и MUST NOT перевёрстывать матрицу в portrait. Выход — только Close (или исчезновение валидной таблицы). Close MUST вернуть карточку в portrait.
- **FR-008**: На iPad MUST открывать fullscreen матрицу в текущей ориентации без forced landscape.
- **FR-009**: Prep-колонки MUST рендериться стеком рядов над гридом; cook — колонки матрицы.
- **FR-010**: Подряд заполненные ячейки одной cook-колонки MUST сливаться в один span; без assignment ячейка пустая.
- **FR-011**: Текст span MUST браться из `cellTitles` первой строки span, иначе `columns[].title`.
- **FR-012**: Левая колонка ингредиентов MUST быть sticky; ширина ~25% видимой матрицы; горизонтальный скролл cook-колонок.
- **FR-013**: Scaled amounts MUST только в левой колонке; `scaleFactor` не в хеше.
- **FR-014**: Owner + online: баннер stale/not-built MUST давать icon-only refresh (`recipe.process-table.recalculate` / `.build`). Иначе только текст.
- **FR-015**: Refresh MUST вызывать `POST /api/recipes/:id/rebuild-process-table` с Bearer, ждать ответа, single-flight; 404/500 — локализованный тост; 200 — дождаться обновления Y.Doc и снять баннер.
- **FR-016**: Чекбоксы строки и непустой ячейки MUST быть локальными (не Yjs) и сбрасываться при выходе из готовки.
- **FR-017**: Таймеры MUST маппиться с `timer-reference` на первую cook-колонку с тем же `stepIndex`; leftover — отдельные chips; старт через существующий timer stack.
- **FR-018**: На время готовки MUST включить keep-awake; выход MUST снять auto-lock этой сессии.
- **FR-019**: Все пользовательские строки — ключи `recipe.process-table.*` (+ существующие `common.close`, `time.short`, `common.screen-always-on` при необходимости) в `Localizable.xcstrings` (en+ru), без hardcoded UI и без fallback.
- **FR-020**: Голосовой режим 056 MUST не получать отдельную кнопку «Готовить» в этом заходе; будущий голос вешается на этот же экран.
- **FR-021**: Перед реализацией view MUST быть `layout.md` + `layout-audit.json` и human review `layout.md` (формат матрицы с web/RecipeTables; chrome iOS-native). Static audit ≠ acceptance.

### Ключевые сущности

- **ProcessTableV1**: `version`, `sourceHash`, `columns[]` (`id`, `title`, `kind` prep|cook, `stepIndex`), `assignments[]` (`ingredientId`, `columnId`), опционально `rowOrder`, `cellTitles[]`.
- **ProcessTableColumn / Assignment / CellTitle**: как JSON schema v1.
- **CookingSession** (in-memory): `recipeId`, локальные `checkedIngredientIds`, `checkedCells` (`{startIngredientId}:{columnId}`), keep-awake flag. Не переживает Close / teardown / logout.
- **StaleState**: `sourceHash` vs `currentHash`; `canRebuild` = owner ∧ online ∧ не read-only public.

---

## Критерии успеха *(обязательно)*

- **SC-001**: После импорта и sync пользователь открывает готовку с матрицей без отдельной загрузки таблицы.
- **SC-002**: Правка рецепта на телефоне не уничтожает таблицу.
- **SC-003**: Пользователь понимает группировку шага (один span на смесь) без чтения длинного HTML.
- **SC-004**: Тап «Начать готовить» на iPhone открывает шпаргалку в системном landscape с нативным nav bar.
- **SC-005**: Устаревшая таблица остаётся usable; owner online обновляет её с того же баннера.
- **SC-006**: Отметки «отмерял / сделал» не появляются на другом устройстве.
- **SC-007**: `lint-i18n.sh` зелёный; UI-текст только из xcstrings; шрифт Martian (`.appBody()` / `.appFootnote()`).

---

## Допущения

- Сервер уже пишет ключ после импорта/Wand; native не генерирует матрицу.
- Web UI скрыт — native chrome: системный nav bar + `requestGeometryUpdate`, не split/overlay и не 90° «картинка».
- RecipeTables и web `process-table.tsx` — эталон **формата матрицы** (merge, prep, sticky 25%), не пикселей chrome.
- CTA на карточке — справа от заголовка шагов, не в toolbar.
- Figma нет; `layout.md` пишем сами и останавливаемся на human review до view.
- Чекбоксы как web `sessionStorage`: сессия готовки, не UserDefaults.
- Classic view вне edit не дублирует stale-баннер (как web); nutrition-баннер на карточке не трогаем.
- Discover/public: матрица read-only, rebuild нет.
- Rebuild может длиться десятки секунд (LLM) — busy на кнопке, без блокировки всего приложения тостом «ждём».
- Существующий `ScreenAwakeToggle` на карточке остаётся; готовка включает awake сама.
- Таймеры — текущий `TimerManager` / Live Activity, новый schema field не нужен.
- 056 не зашиплен (`CookingModeView` нет в дереве) — 074 занимает имя точки входа.

---

## i18n (новые ключи)

Минимум (RU/EN), как web:

- `recipe.process-table.toggle.start` — видимый текст кнопки на карточке
- `recipe.process-table.toggle.classic` — tooltip/aria Close / «к классике», если нужен icon-only
- `recipe.process-table.measured` — aria чекбокса ингредиента
- `recipe.process-table.column-done` — aria чекбокса ячейки
- `recipe.process-table.prep` — если нужен префикс prep-ряда
- `recipe.process-table.may-be-outdated`
- `recipe.process-table.not-built`
- `recipe.process-table.build`
- `recipe.process-table.recalculate`

Close — существующий `common.close`. Длительность чипа — `time.short`.

---

## Downstream consumers *(для плана)*

- **SwiftUI views**: `YDocRecipeDetailView`, `DiscoverRecipeView`, новый cooking/matrix view; баннер по образцу nutrition.
- **Cross-process**: таймеры/Live Activity — существующий stack; widgets не показывают матрицу.
- **Sync boundaries**: Yjs key `processTable`; REST rebuild; hash должен совпасть с web/server.
- **Persisted state**: ключ в Y-снимке SQLite; чекбоксы не персистить.
- **Tests**: decode/hash/merge unit; Do-No-Harm write; UITest кнопки и fullscreen; `lint-i18n.sh`.

---

## Code anchors (ожидаемые)

- `RecipeScalerNative/Services/YjsSync/DocumentManager.swift` — read string key, preserve on write
- `RecipeScalerNative/Services/YjsSync/RecipeYjsCodec.swift` / readers — decode
- `RecipeScalerCore/Networking/APIClient.swift` — rebuild рядом с `calculateNutrition`
- Parser/hash рядом с recipe Yjs readers (порт `process-table-source-hash.ts`)
- Cooking UI — отдельный view; не плодить вторую кнопку «Готовить» под 056
- `docs/YJS-SCHEMA.md` — ключ уже описан; сверить при расхождении

## Related

- Web canon: [`../../../recipe-scaler-web/specs/074-process-table/spec.md`](../../../recipe-scaler-web/specs/074-process-table/spec.md)
- Yjs mapping: [`../../docs/YJS-SCHEMA.md`](../../docs/YJS-SCHEMA.md)
- Voice (позже): [`../056-cooking-voice-mode/spec.md`](../056-cooking-voice-mode/spec.md)
- Layout (до view): [`layout.md`](./layout.md) · [`layout-audit.json`](./layout-audit.json) — human review обязателен
- План: [`plan.md`](./plan.md)
- Nutrition rebuild UX: `RecipeNutritionRecalculationModel`
