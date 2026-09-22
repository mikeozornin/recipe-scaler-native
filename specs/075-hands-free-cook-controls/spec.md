# Спецификация: Hands-free прокрутка при «экран не гасить»

**Feature Branch**: `075-hands-free-cook-controls`  
**Дата**: 2026-09-19 (rev 4)  
**Статус**: Draft  
**Figma (sheet)**: [Hand free](https://www.figma.com/design/rVzFwMDS5SECfIq4HRLHya/recipe-scaler-files?node-id=404-4872) — file `rVzFwMDS5SECfIq4HRLHya`, node `404:4872`. Шрифты в макете из UI Kit — **игнорировать**; в приложении только проектный гротеск (Martian / `.appBody()` / `.appFootnote()`).

**Было (rev 1)**: Next/Back/List на `ProcessTableCookingView` — **отменено**.  
**Было (rev 2)**: keep-awake автоматически армит голос и жесты.  
**Было (rev 3)**: один флажок Hands-free в `Menu` баннера + отдельный пункт «Как это работает»; Face XOR Hand выбирался **автоматически** (TrueDepth → Face, иначе Hand).  
**Стало (rev 4)**: keep-awake только не гасит экран. Ellipsis баннера открывает **один sheet** «Управление без рук» — это и настройки каналов, и «как работает». Голос / жесты / лицо включаются **отдельными тумблерами**. Жесты и лицо взаимно исключаются. В баннере после «Не гасить экран включено» — иконки включённых каналов.

**Зависимости**:
- [`ScreenAwakeToggle`](../../RecipeScalerNative/Views/ScreenAwakeToggle.swift) / [`ScreenAwakeController`](../../RecipeScalerNative/Utils/ScreenAwakeController.swift)
- [`ScreenAwakeStatusBanner`](../../RecipeScalerNative/Views/ScreenAwakeStatusBanner.swift)
- [`YDocRecipeDetailView`](../../RecipeScalerNative/Views/YDocRecipeDetailView.swift) — основной вертикальный `ScrollView` + `isScreenAwakeActive`
- Voice STT-паттерны: [056](../056-cooking-voice-mode/spec.md) (переиспользуем идеи on-device listening; **код 056 в репозитории отсутствует**, `CookingModeView` не строим)
- Жесты: ARKit Face + Vision Hand Pose (как в research)

## Clarifications

### Session 2026-09-14 (rev 2)

- Q: Hands-free Next/Back/List в cook matrix? → A: **Нет.** Вместо этого: scroll up/down на карточке.
- Q: Что включает keep-awake? → A: Тот же toolbar `play.circle.fill` (`ScreenAwakeToggle`). Отдельного Hands-free toggle в **toolbar нет**.
- Q: На сколько скроллить? → A: **75%** `visibleHeight` viewport `ScrollView` за одно действие.
- Q: Куда скроллить? → A: Основной вертикальный `ScrollView` карточки рецепта (`YDocRecipeDetailView`). Cook matrix 074 — **вне scope**.
- Q: Какие команды? → A: Только **вверх** и **вниз** (голос + жесты).

### Session 2026-09-14 (rev 3)

- Q: Когда стартовать камеру и mic? → A: **Не** при первом `play.circle.fill`. Только когда пользователь включает hands-free канал.
- Q: Где управление Hands-free? → A: Справа в `ScreenAwakeStatusBanner` — ellipsis. *(rev 4 уточняет: ellipsis открывает sheet, а не `Menu` с двумя пунктами.)*

### Session 2026-09-19 (rev 4)

- Q: Один флажок Hands-free + отдельная справка? → A: **Нет.** «Hands-free» и «Как это работает» — **один экран** (sheet «Управление без рук»).
- Q: Как включать каналы? → A: Три тумблера на этом экране: голос, жесты, лицо. Первая строка макета — включение секций.
- Q: Можно ли лицо и жесты одновременно? → A: **Нет.** Включение одного **выключает** другой. Голос независим и может быть вместе с любым камерным каналом.
- Q: Автовыбор Face/Hand по TrueDepth? → A: **Снят.** Пользователь сам выбирает канал. Тумблер «Управление лицом» **скрыт**, если TrueDepth нет.
- Q: Что в баннере после «Не гасить экран включено»? → A: Иконки **включённых** каналов: `waveform` (голос), `hand.thumbsdown.hand.thumbsup.filled` (жесты), `face.smiling` (лицо). Порядок: голос → жесты → лицо. Выключенный канал иконки не показывает.
- Q: Вторая строка макета? → A: Live-проверка: менять цвет чипов распознанных слов и иконок жеста/глаза, когда канал сработал.
- Q: Третья строка макета? → A: Состояние после запроса mic/camera, если разрешение не дали. Кнопка «Открыть параметры», если нет **хотя бы одного** нужного разрешения.
- Q: Тумблер после deny? → A: **Snap-off** (pref false), как на макете. После grant в Settings канал сам не включается.
- Q: Лицо без TrueDepth? → A: Тумблер «Управление лицом» **скрыть**. Остаются голос и жесты.
- Q: Шрифты макета? → A: SF из UI Kit не брать; только шрифты приложения.

---

## Границы

**В scope:**

- Opt-in hands-free **по каналам** из единого sheet, открываемого ellipsis баннера keep-awake.
- Иконки включённых каналов в `ScreenAwakeStatusBanner` после текста keep-awake.
- Арминг канала, пока recipe detail видима AND `isScreenAwakeActive` AND канал включён AND permissions канала granted AND не показан cooking cover AND assistant sheet закрыт.
- Voice: on-device STT + whitelist «вверх/вниз» (RU+EN).
- Gestures: Face XOR Hand по **выбору пользователя** → те же два действия.
- Программный scroll на `±0.75 * visibleBounds.height`, clamp к контенту.
- Live-фидбек на sheet: цвет чипов фраз и иконок жеста/глаза при распознавании.
- Denied-состояние sheet + «Открыть параметры».
- Teardown камеры и speech, когда соответствующий канал OFF / awake OFF / уход с экрана / background / cooking cover / assistant sheet.
- Permissions (mic, speech, camera) **при включении соответствующего канала**, не при keep-awake и не при одном лишь открытии sheet.
- Unit-тесты delta/clamp + classifier + XOR тумблеров + arm predicate; i18n UI-строк sheet, баннера, privacy usage.

**Вне scope:**

- Next/Back/List, ingredients panel, cheat-sheet Crouton-style на cook matrix (rev 1).
- App Intents / Siri (можно v1.1).
- Прокрутка `ProcessTableCookingView` / горизонтальный scroll матрицы.
- Wake word, LLM voice chat.
- Web parity.
- Автоскролл к якорю шага (только relative ±75%).
- Одновременный Face+Hand на одной камере.
- Мастер-флажок «Hands-free» в `Menu` баннера (rev 3) и отдельный пункт «Как это работает».
- Автовыбор Face vs Hand по наличию TrueDepth (rev 3).
- Реализация 056 `CookingVoiceProvider` / `CookingModeView`.

---

## Контекст и мотивация

Keep-awake на карточке значит «я читаю рецепт с экрана». Hands-free листание — следующий шаг, но камера и микрофон не должны включаться сюрпризом от `play.circle.fill`.

Один экран настроек снимает Tax Job «сначала включить Hands-free, потом искать справку»: человек сразу видит, *чем* управлять, *как* проверить, что канал живой, и *куда* идти, если система отказала в доступе. Три тумблера, а не один, позволяют включить только голос (без камеры) — это прямо следует из предупреждения про батарею.

Жесты и лицо делят фронтальную камеру, поэтому XOR остаётся; теперь это явный выбор, а не скрытое правило телефона.

75% viewport — крупный шаг: меньше команд на длинный рецепт, чем постраничный «экран», но с перекрытием контекста (~25% остаётся в кадре).

---

## Цель v1

1. Awake ON → экран не гаснет; каналы hands-free по умолчанию OFF, без камеры и mic.
2. Ellipsis → sheet «Управление без рук». Пользователь включает нужные каналы.
3. Включённый канал скроллит рецепт вверх/вниз (голос и/или жест/лицо).
4. Каждый жест/команда сдвигает offset на **75% видимой высоты** ScrollView.
5. Канал OFF или awake OFF → соответствующий mic/camera полностью off.
6. Без Foundation Models; on-device Speech + системные Vision/ARKit.

---

## User stories

### US0. Открыл управление без рук из баннера

Пользователь включает `play.circle.fill`. В зелёном баннере текст keep-awake; справа ellipsis. Нажатие ellipsis открывает sheet «Управление без рук» (не `Menu` с двумя пунктами). На экране: intro про грязные руки, предупреждение про энергию, три тумблера. Пока все OFF — нет блоков «попробуйте сказать / показать». Закрыл sheet — keep-awake на месте, каналы не менялись.

### US1. Включил голосовое управление

В sheet включает «Голосовое управление». Если mic/speech ещё не определены — система запрашивает их. После grant: голос армится (при F1.1), под тумблером появляется блок «Попробуйте сказать» с чипами фраз, в баннере появляется `waveform`. Говорит whitelist-фразу — контент скроллится на 75%, соответствующий чип подсвечивается. Выключил тумблер — speech stop, иконка из баннера пропадает, блок «попробуйте» скрывается.

### US2. Включил управление жестами

В sheet включает «Управление жестами». Если камера не определена — запрос. После grant: Hand-сессия, блок «Попробуйте показать…» с иконками like/dislike, в баннере `hand.thumbsdown.hand.thumbsup.filled`. Thumbs-up вверх/вниз → scroll. Если «Управление лицом» было ON — оно выключается в том же жесте (XOR).

### US3. Включил управление лицом

На устройстве с TrueDepth в sheet включает «Управление лицом». Запрос камеры при необходимости. Face-сессия, блок с двумя глазами, в баннере `face.smiling`. Левый глаз → up, правый → down. Если жесты были ON — жесты выключаются. Без TrueDepth строки «Управление лицом» нет.

### US4. Выключил канал или awake

Снял тумблер канала → сразу stop этого ресурса; остальные каналы и idle timer не трогать. Выключил `play.circle.fill` → баннер исчезает, все hands-free сессии teardown (prefs каналов **не** сбрасываем). Повторный ON awake при pref канала true — arm снова, permission только если ещё не granted.

### US5. Отказ в permission

Пользователь включил канал, система спросила доступ, доступ не дали. Pref канала **сразу false** (тумблер snap-off и **disabled**, как кадр `404:4092`). Канал не армится. Под заголовком канала — оранжевая подпись: для голоса «доступ к микрофону запрещён»; для жестов и лица «доступ к камере запрещён». Кнопка «Открыть параметры» видна, если **хотя бы одно** из нужных разрешений (mic и/или camera) не granted. Карточка рецепта не блокируется. Keep-awake остаётся. После grant в системных параметрах тумблер сам не включается — пользователь включает канал снова.

### US6. Ушёл с карточки / background / cooking / assistant

Teardown capture + speech как при всех каналах OFF. Не слушать mic на других табах, под cooking cover 074 и под assistant sheet. Foreground: resume только если awake всё ещё ON **и** хотя бы один канал pref ON **и** detail снова видима (не cover). Текущий keep-awake на background уже зовёт `deactivateScreenAwake()` — awake станет OFF; Hands-free не должен оставить камеру.

### US7. Проверил, что канал слышит / видит (live на sheet)

Sheet открыт, канал armed. Распознанная фраза подсвечивает свой чип. Распознанный жест подсвечивает соответствующую иконку (like или dislike). Распознанное моргание подсвечивает соответствующий глаз. Подсветка держится короткий импульс и возвращается к idle. Скролл рецепта за sheet при этом тоже происходит (справка не teardown).

---

## Требования

### Функциональные

#### F1. Арминг и chrome

- **F1.1.** Канал armed iff recipe detail visible AND `isScreenAwakeActive` AND pref канала true AND permission канала granted AND не показан cooking cover AND assistant sheet закрыт. Для Face дополнительно TrueDepth available. Для Hand — камера granted (TrueDepth не обязателен). Voice требует mic **и** speech.
- **F1.2.** Нет отдельной кнопки Hands-free в **toolbar**. `play.circle.fill` не дублировать второй кнопкой.
- **F1.3.** Справа в `ScreenAwakeStatusBanner` — кнопка ellipsis (не двухпунктный `Menu`). Не увеличивать высоту баннера больше чем на 4 pt.
- **F1.4.** Ellipsis открывает `.sheet` `AwakeScrollHelpSheet` — единый экран настроек и справки. Заголовок: `recipe.awake-scroll.help.title` (copy: «Управление без рук» / EN-эквивалент). Отдельного пункта меню «Hands-free» и «Как это работает» **нет**.
- **F1.5.** Prefs каналов persist в UserDefaults, default все `false`. Пишет пользовательский тумблер, XOR-выключение парного камерного канала и **snap-off при denied permission**. Teardown awake prefs **не** чистит.
  - голос: `awakeHandsFreeVoiceEnabled`
  - жесты: `awakeHandsFreeHandEnabled`
  - лицо: `awakeHandsFreeFaceEnabled`
- **F1.6.** Опциональный camera preview 48 pt overlay (bottomTrailing) только если Hand или Face armed и camera granted. Не `safeAreaInset` (не сжимать ScrollView).
- **F1.7.** После текста `recipe.awake-scroll.banner` («Режим готовки включён») — иконки включённых каналов (pref true), **вплотную к тексту** (не у правого края), ellipsis остаётся trailing:
  - голос: SF Symbol `waveform`
  - жесты: `hand.thumbsdown.hand.thumbsup.filled`
  - лицо: `face.smiling`
  - порядок слева направо: голос, жесты, лицо; отсутствующие пропускать (не дырки).
  - цвет как `bannerText`. Если ни один канал не включён — иконок нет. Spacer только между группой «текст+иконки» и ellipsis.
  - При fire канала соответствующая иконка в баннере: scale 1.8, `easeInOut` 0.5 s, затем обратно 0.5 s. Reduce Motion — без анимации.
- **F1.8.** XOR: запись `awakeHandsFreeHandEnabled = true` **обязана** записать `awakeHandsFreeFaceEnabled = false` в том же пользовательском жесте, и наоборот. Голос XOR не затрагивает.
- **F1.9.** Миграция rev 3: если существует старый ключ `awakeHandsFreeEnabled == true` и новые ключи ещё не создавались — включить **голос** и камерный канал по старому правилу (TrueDepth → лицо, иначе жесты), затем перестать читать старый ключ как source of truth. Если старый ключ false/отсутствует — все новые false.

#### F8. Sheet «Управление без рук»

Макет: Figma `404:4872`. Состояния (node id):

| Состояние | Node | Что видно |
|-----------|------|-----------|
| Все OFF | `404:3351` | intro + energy + 3 тумблера OFF, без live-блоков |
| Голос+лицо idle | `404:3179` | чипы фраз idle + глаза idle |
| Голос+жесты idle | `404:3270` | чипы + like/dislike idle |
| Голос live | `404:3818` | чип распознанного слова акцентный |
| Жесты live | `404:3923` | иконка распознанного жеста акцентная |
| Лицо live | `404:3713` | иконка распознанного глаза акцентная |
| Permissions denied | `404:4092` | оранжевые подписи + «Открыть параметры» |

- **F8.1.** Структура сверху вниз:
  1. Intro: не касаться экрана грязными руками — голос или камера.
  2. Energy hint с glyph тумблера: включать только то, чем будешь пользоваться.
  3. Тумблер «Голосовое управление». Если ON и permission ok — блок «Попробуйте сказать» + чипы фраз текущей UI-локали (RU: «вверх», «выше», «прокрути вверх», «вниз», «ниже», «прокрути вниз»; EN: «up», «higher», «scroll up», «down», «lower», «scroll down»). Classifier по-прежнему принимает **оба** языка.
  4. Тумблер «Управление жестами». Если ON и camera ok — «Попробуйте показать…» + две иконки (thumbs up / thumbs down).
  5. Тумблер «Управление лицом» — **только если TrueDepth available**. Если ON и camera ok — «Попробуйте поморгать…» + два глаза.
  6. Если нет хотя бы одного нужного permission (mic/speech denied при попытке голоса и/или camera denied при попытке жестов/лица) — кнопка «Открыть параметры» (`UIApplication.openSettingsURLString`).
- **F8.2.** Live-реакция (вторая строка макета): idle-чип/иконка нейтральные; при fire канала соответствующий чип или иконка меняет цвет на акцентный (зелёный макета) на `helpDebugFiredDuration` (~0.8 s), затем idle. Неподсвеченные соседи не меняются.
- **F8.3.** Denied (третья строка): после отказа permission pref канала = false (snap-off). Тумблер **disabled**, пока permission этого канала denied (Figma `404:4092` `isEnabled=False`). Оранжевая подпись остаётся. После grant в Settings тумблер снова enabled и OFF — пользователь включает сам. Кнопка параметров — если **хотя бы одно** из {mic, camera, speech} denied (не undetermined). Undetermined без запроса — кнопки нет, подписей denied нет.
- **F8.4.** Sheet не teardown'ит armed каналы: пользователь проверяет жесты/фразы, пока sheet открыт.
- **F8.5.** Типографика: `.appBody()` / `.appFootnote()` / существующие toolbar text styles. Запрет `.font(.system` и SF из UI Kit макета.
- **F8.6.** Dismiss: системный grabber / swipe. Кнопки Close нет. Заголовок sheet — в контенте, с переносом, без обрезки.
- **F8.7.** Запрос permission: в момент перехода тумблера false → true. Открытие sheet само по себе permissions не спрашивает.

#### F2. Действия

```swift
enum AwakeScrollAction: Equatable {
    case up    // к началу документа (contentOffset.y уменьшается)
    case down  // к концу документа (contentOffset.y увеличивается)
}
```

- **F2.1.** Delta = `0.75 * scrollView.bounds.height` (visible layout height viewport).
- **F2.2.** Новый offset = clamp(current ± delta, minOffset...maxOffset), где `minOffset = -adjustedContentInset.top`, `maxOffset = contentSize.height - bounds.height + adjustedContentInset.bottom` (как UIKit, **без** прибавления top). Точная формула в [contracts/scroll-delta.md](./contracts/scroll-delta.md).
- **F2.3.** Анимация: `setContentOffset(_:animated: true)` на UIScrollView, найденном **probe'ом** на detail `ScrollView`. `DescriptionEditorScrollAnchor.detailScrollView` — только caret-scroll редактора, не единственный источник для Hands-free.
- **F2.4.** Cooldown 0.5–0.8 s после fire (voice и gesture делят один cooldown).
- **F2.5.** Ручной пальцевый scroll не блокировать (`isScrollEnabled` остаётся true).

#### F3. Voice

- **F3.1.** On-device `SFSpeechRecognizer`, armed только при voice-канале. Не тащить 056 `CookingVoiceProvider`.
- **F3.2.** Classifier whitelist — [contracts/voice-whitelist.md](./contracts/voice-whitelist.md).
- **F3.3.** Partial results не fire; только final (или debounce stable partial ≥ N ms, N в data-model).
- **F3.4.** 60s re-arm как идея 056.
- **F3.5.** Live на sheet: fire `.up`/`.down` подсвечивает чип той фразы, которая совпала (если совпала EN-фраза при RU UI — подсветить смысловой близнец: `up` → «вверх», `higher` → «выше», `scroll up` → «прокрути вверх», и наоборот).
- **F3.6.** Локаль `SFSpeechRecognizer` = язык приложения (`en` → `en_US`, `ru` → `ru_RU`). Чипы на sheet следуют UI-локали; whitelist по-прежнему принимает оба языка. Смена языка при armed voice → re-arm STT.

#### F4. Hand (Vision)

- **F4.1.** `VNDetectHumanHandPoseRequest`, front camera, max 1 hand.
- **F4.2.** Pose thumbs-up; сектор по углу большого пальца — [contracts/gesture-mapping.md](./contracts/gesture-mapping.md).
- **F4.3.** Hold ~250 ms, fire once, cooldown.
- **F4.4.** Используется iff F1.1 для hand-канала (pref ON, camera granted, Face pref OFF из-за XOR).
- **F4.5.** Live: `.up` → thumbs-up icon accent; `.down` → thumbs-down icon accent.

#### F5. Face (ARKit)

- **F5.1.** Если TrueDepth: **мой** левый глаз → `.up`, мой правый → `.down` (edge + debounce). ARKit `eyeBlinkLeft`/`Right` на `.userFacing` зеркальны — un-mirror до классификатора. На sheet: слева вверх, справа вниз.
- **F5.2.** `jawOpen` в v1 **не** используем.
- **F5.3.** Используется iff F1.1 для face-канала AND TrueDepth available.
- **F5.4.** Live: `.up` → левый глаз accent; `.down` → правый глаз accent.
- **F5.5.** Нет TrueDepth: тумблер и live-блок лица **не рендерить**. Pref лица игнорировать (не армить, не стартовать камеру). XOR с жестами на таком устройстве не нужен — жесты единственный камерный канал.

#### F6. Permissions & privacy

- Camera / mic / speech usage strings: существующие цели (QR login, assistant dictation) **сохранить** и **добавить** hands-free scroll. Новый ключ `NSSpeechRecognitionUsageDescription`.
- Запрос: при **первом** переходе соответствующего канала false → true, пока awake ON. Не при `play.circle.fill`. Не при открытии sheet. Голос → mic + speech. Жесты или лицо → camera. Не запрашивать camera, если включили только голос.
- Denied → US5: snap-off pref, карточка не блокируется.

#### F7. Lifecycle

- Все каналы OFF / awake OFF / onDisappear detail / background / cooking presentation / assistant sheet → teardown capture + speech.
- Выключение только голоса при живых жестах/лице — stop speech, камеру не трогать.
- Выключение камерного канала при живом голосе — stop camera, speech не трогать.
- Single-flight start; `sessionEpoch`.
- Cooking cover 074: `ProcessTableCookingCoordinator.presentation != nil` → disarm HF resources; после dismiss — re-arm если F1.1 снова true для какого-либо канала.
- Assistant sheet: то же.
- Logout / account switch: teardown; UserDefaults prefs каналов **не** чистить (это UI-предпочтение устройства, не account CRDT).

### Нефункциональные

- N1. On-device STT default.
- N2. Swift 6; Vision off MainActor.
- N3. Не регрессить обычный scroll жестом пальца и keep-awake без каналов.
- N4. Battery: ≤15 fps hand pose; stop when not armed. Не держать камеру, если оба камерных тумблера OFF.
- N5. Controller view-local у `YDocRecipeDetailView`, не `AppContainer` / не `.shared`.
- N6. Sheet и баннер — проектный шрифт, не SF UI Kit.
- N7. Thermal response: при `thermalState` `.serious`/`.critical` камерная семплинг-частота падает до 6 fps (и Vision, и ARKit-face), при возврате к `.nominal`/`.fair` — обратно 15 fps. Voice-канал не трогать.

---

## Assumptions

1. Ellipsis — **кнопка**, сразу sheet; не `Menu` с одним пунктом.
2. Тумблер при denied **snap-off** (pref false) и **disabled**, как кадр `404:4092`. Оранжевая подпись остаётся. После Settings пользователь включает канал снова.
3. На устройстве без TrueDepth тумблер «Управление лицом» **скрыт**. Жесты — единственный камерный канал.
4. Чипы фраз на sheet — только текущая UI-локаль; whitelist классификатора по-прежнему RU+EN.
5. «Открыть параметры» смотрит на фактический status mic/camera/speech (denied), а не на то, какие тумблеры сейчас ON. Если mic denied и camera granted — кнопка всё равно видна. То же для speech denied при granted mic.
6. Иконки в баннере завязаны на **pref ON**. После snap-off из-за denied иконка канала из баннера пропадает.
7. Миграция `awakeHandsFreeEnabled` (F1.9) нужна, чтобы уже включенный в rev 3 Hands-free не исчез молча.

---

## Конституционная проверка

| Gate | Статус | Evidence |
|------|--------|----------|
| CRDT-first | N/A | Только scroll UI + UserDefaults prefs |
| Web parity | N/A | Native-only |
| Offline-first | PASS | On-device |
| Native UI | PASS | Detail ScrollView + banner + sheet |
| Phased delivery | PASS | opt-in каналы → engine → voice → hand → face |
| i18n | PASS | banner/sheet/privacy в xcstrings; без хардкода copy из Figma |
| Documentation | PASS | spec/plan/layout/tasks/contracts |

---

## Downstream consumers

- **SwiftUI**: `YDocRecipeDetailView`, `ScreenAwakeStatusBanner`, `AwakeScrollHelpSheet`
- **Cross-process**: N/A (App Intents вне scope)
- **Sync**: N/A
- **Persisted**: UserDefaults `awakeHandsFreeVoiceEnabled`, `awakeHandsFreeHandEnabled`, `awakeHandsFreeFaceEnabled` (+ одноразовая миграция `awakeHandsFreeEnabled`)
- **Tests**: `AwakeScroll*Tests`

---

## Positive invariants

| Effect | Invariant | Test |
|--------|-----------|------|
| action `.down`, visibleH=400, y=0 | y → 300 | `test_down_scrolls_75_percent` |
| action `.down`, y near end | clamp maxOffset | `test_down_clamps_end` |
| «вниз» transcript | `.down` | `test_ru_vniz` |
| awake → false | sessions stopped | `test_awake_off_teardown` |
| voice → false, hand true, awake true | speech stopped, camera still on, idle timer still disabled | `test_voice_off_keeps_hand` |
| hand → true while face true | face pref false, modality `.hand` | `test_hand_xor_disables_face` |
| face → true while hand true | hand pref false, modality `.face` | `test_face_xor_disables_hand` |
| thumb up-sector hold | one `.up` | `test_hand_up_once` |
| play.circle.fill ON, all channel prefs false | no capture session | `test_awake_only_no_camera` |
| voice ON, camera prefs false | speech may start, no capture | `test_voice_only_no_camera` |
| mic denied after voice ON | voice pref false, not armed, settings button eligible | `test_mic_denied_snaps_voice_off` |

---

## Async lifecycle

| Op | Identity | Re-check | Cancel owner | Stale test |
|----|----------|----------|--------------|------------|
| permission | epoch | F1.1 still true for that channel | AwakeScrollController | stale epoch ignored |
| vision frame | epoch | epoch match | same | stale frame dropped |
| speech re-arm | voiceSessionId | id match + F1.1 voice | voice engine | inherit 056 pattern |
| start capture | epoch | F1.1 hand or face | controller | cooking cover mid-start → stop |

---

## Teardown / resource inventory

| Path | Postcondition |
|------|----------------|
| all channels OFF | no camera indicator, speech stopped; banner stays if awake |
| voice OFF, camera channel ON | speech stopped; camera stays |
| camera channels OFF, voice ON | camera stopped; speech stays |
| awake OFF | banner gone; camera+speech stopped |
| leave detail | same as awake OFF path for resources |
| background | same; existing `deactivateScreenAwake()` |
| cooking cover | camera+speech stopped; after dismiss re-arm if F1.1 |
| assistant sheet | same as cover |
| logout | resources stopped; channel prefs kept |

---

## Verification

- Unit delta/clamp/classifier/XOR prefs/arm predicate.
- Manual: iPhone 13 Pro, long recipe, awake ON without каналов → нет green camera dot; voice-only → нет camera dot; hand or face → camera; ~¾ screen per command; иконки в баннере совпадают с тумблерами; live-цвет на sheet; denied → «Открыть параметры».
- Layout: human review обновлённого `layout.md` **до** правок banner/sheet. Figma `404:4872`. Шрифты приложения, не UI Kit.

---

## Риски

| Риск | Митигация |
|------|-----------|
| SwiftUI ScrollView без UIScrollView handle в read-mode | `DetailScrollViewProbe` на сам ScrollView карточки, не caret-anchor |
| Ложные «up» из речи на кухне | узкий whitelist + cooldown |
| Mirror camera left/right | для up/down секторов критичен pitch, не yaw |
| Permission сюрприз от play.circle.fill | запрос только с тумблера канала |
| 056 ещё не в коде | тонкий SFSpeechRecognizer, явная граница |
| Баннер не влезает с 3 иконками + ellipsis на SE | title `lineLimit 1` truncate; иконки hug, не wrap баннера |
| SF Symbol `hand.thumbsdown.hand.thumbsup.filled` нет на deployment target | проверить availability; если нет — два глифа или ближайший канонический symbol, зафиксировать в layout.md |

---

## Связь с 056 / 074

| Спека | Связь |
|-------|--------|
| 056 | Паттерны on-device listening и 60s re-arm; не строим CookingModeView |
| 074 | Не трогаем matrix cook UI; **disarm** HF пока cooking cover presented |

---

*Rev 4: единый sheet настроек+справки; три канала; Face XOR Hand выбирает пользователь; иконки каналов в баннере; live-фидбек и denied+Settings.*
