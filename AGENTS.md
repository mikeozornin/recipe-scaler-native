

For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan:
specs/002-native-editing/plan.md

## Spec Language

Артефакты фичи в `specs/<feature>/` пишутся **на русском**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `tasks.md`, `quickstart.md`, `contracts/`.  
Чеклисты (`checklists/`) — на усмотрение автора фичи; по умолчанию русский, если не указано иное.

## iOS и стандартные компоненты

Если запрос **противоречит поведению или гайдлайнам стандартных компонентов iOS** (Human Interface Guidelines, системные компонентам iOS — **сначала уточни у пользователя**, что он действительно хочет именно это, а не обходной путь.

Примеры, когда нужно спросить:

- ручное переключение outline / `.fill` в `tabItem` вместо штатного tint активной вкладки;
- кастомный UIKit поверх SwiftUI там, где системный компонент уже решает задачу;
- поведение, которое ломает ожидаемые жесты, accessibility или внешний вид платформы.

Предложи **стандартный вариант** (кратко, почему так принято на iOS) и **альтернативу** (кастом / полная переделка), если пользователь настаивает — делай по его выбору.

## Типографика

Все текстовые стили определены в `AppTypography.swift` и `AppFonts.swift`. **Не хардкодь** шрифты и размеры в view-файлах — используй константы и extension-ы.

### Шрифты (AppFonts)

| Роль | Имя | Когда использовать |
|---|---|---|
| `sans` | Martian Grotesk Nr Lt | Body, footnote, subheadline — основной текст |
| `sansMedium` | Martian Grotesk Nr Md | Headline, title3, semibold-варианты |
| `display` | Martian Grotesk Std xBd | Заголовки (title2, large title) |
| `mono` | Martian Grotesk Nr Lt | Числа, код (`/connect`) |

### Размеры и стили (AppTypography)

| Стиль | Размер | Шрифт | lineSpacing | Использование |
|---|---|---|---|---|
| `body` | 16 pt | sans | 4 pt | Основной текст списков, строк рецептов, ингредиентов |
| `footnote` | 13 pt | sans | 2 pt | Подписи, badge-и, secondary-текст |
| `subheadline` | 15 pt | sans | — | Редко; prefer body |
| `headline` | 16 pt | sansMedium | — | Жирный body |
| `title3` | 20 pt | sansMedium | — | Подзаголовки |
| `title2` | 22 pt | display | — | Заголовки экранов |
| `compact` | 14 pt | sans | — | Секционные заголовки в списке |

### Text extensions (SwiftUI)

Используй вместо ручного `.font(...)` + `.lineSpacing(...)`:

```swift
Text("some key").appBody()       // 16 pt + lineSpacing 4
Text("some key").appFootnote()   // 13 pt + lineSpacing 2
```

**Почему:** гарантирует единый интерлиньяж везде. Если нужно добавить lineSpacing для нового стиля — добавь константу в `AppTypography` + `Text` extension.

**Ограничение:** `.appBody()` / `.appFootnote()` возвращают `some View`, а не `Text`. После них нельзя вызывать Text-specific модификаторы (`.textCase`, `.tracking`). Для таких случаев используй `.font(AppTypography.footnote)` напрямую (например, `AppSectionHeader`).

### View extension для List/Form

```swift
.appListBodyTypography()  // font(AppTypography.body) на весь List
```

Применяй к корневому view списка, чтобы все некастомные Text внутри наследовали body.

### Секционные заголовки

```swift
AppSectionHeader("key")       // footnote, .secondary, uppercase, tracking 0.8
AppSectionHeaderSpacer()      // невидимый placeholder для отступа
```

### UIKit chrome (AppChromeAppearance)

Глобально настраивает шрифты для NavigationBar, BarButtonItems, TabBar, UITextField, UISegmentedControl через `appearance()`. Вызывается один раз при старте приложения.

### Правила

1. **Text view** → используй `.appBody()` / `.appFootnote()` вместо ручного `.font()` + `.lineSpacing()`.
2. **Не-Text view** (SF Symbols, HStack, ZStack) → используй `.font(AppTypography.xxx)` напрямую.
3. **TextField** → не Text extension, используй `.font(AppTypography.body)`.
4. **Toggle label** → передавай `Text(...)` с `.appBody()` вместо строкового ключа.
5. **Новый стиль с lineSpacing** → добавь константу в `AppTypography` + `Text` extension, обнови `RecipeRowLayoutMetrics` если нужно.
6. Не создавай fallback вроде `t('key') || 'Default'` — см. правило i18n.

Прочитай и выполняй @RTK.md. Prefix shell commands with `rtk` when filtering output (see `CLAUDE.md` / `RTK.md`).

## Локализация (i18n)

Все строки — в `RecipeScalerNative/Resources/Localizable.xcstrings` (en/ru). **Не хардкодь** русский/английский текст в view; добавляй ключ в `.xcstrings`.

### Смена языка в рантайме

Язык переключается **внутри приложения** (Профиль → Язык) без перезапуска.

**Стандартный механизм SwiftUI — `\.environment(\.locale)`.** `ContentView` прокидывает `.environment(\.locale, appLanguage.locale)` ([ContentView.swift](RecipeScalerNative/ContentView.swift)) и слушает `UserDefaults.didChangeNotification`, мутируя `appLanguage` → дерево перерисовывается. Этого **достаточно для всех `Text("key")` / `LocalizedStringKey`** — они резолвятся по locale из окружения, без свизла и без рестарта. Это и есть нативный путь Apple.

**Чего `\.locale` НЕ закрывает (и зачем нужен свизл `Bundle+Language.swift`):** у Apple нет стандартного API, чтобы переключить Foundation-строки без рестарта. Три дыры:

1. **`String(localized:)` / `NSLocalizedString`** — это Foundation, окружение SwiftUI они не читают. В проекте ~194 вызова `String(localized:)`, поэтому `Bundle+Language.swift` свизлит `localizedString(forKey:value:table:)` и редиректит их в выбранный языковой бандл (`AppLanguagePreference.setLanguageOverride`). ⚠️ Сам `String(localized:)` при этом всё равно может резолвиться **мимо** свизла и отдать язык разработки (англ) — поэтому для строки, которая обязана отражать выбранный язык прямо сейчас (особенно в UIKit-мосте), бери `Bundle.currentLocalizedString("key")`, а не `String(localized:)`.
2. **UIKit-мост** (navigation bar, toolbar, `UINavigationItem`) — UIKit не видит SwiftUI environment. Отсюда «залипшие» заголовки.
3. **Runtime-строка в `Text(переменная)`** — компилятор берёт `StringProtocol`-инициализатор и не локализует. Оборачивай: `Text(LocalizedStringKey(key))`.

> Альтернатива свизлу — миграция всех `String(localized:)` на `Text` или на хелпер `localized(_:locale:)` c явным `.lproj`-бандлом. Дорого (37 файлов), поэтому свизл оставлен сознательно как обходка отсутствующего у Apple API. Не убирай свизл без явной задачи на эту миграцию.

### Правила

1. **Текст в UI** → `Text("key")` (литерал → `LocalizedStringKey`, резолвится по `\.locale`). Никакого хардкода строк.
2. **Runtime-строка** (ключ из конфига/сервера) → `Text(LocalizedStringKey(key))`, иначе локализации не будет.
3. **Не делай fallback** вроде `t('key') || 'Default'` или `String(localized: "key", defaultValue: "...")` с человекочитаемым дефолтом — отсутствующий перевод должен быть виден, а не замаскирован.
4. **Заголовок экрана (`navigationTitle`)** → используй `.localizedNavigationTitle("key")` (см. `Utils/LocalizedNavigationTitle.swift`), **не** `.navigationTitle("key")` и **не** `.navigationTitle(Text("key"))`.

   **Почему:** `.navigationTitle(Text("key"))` хранит *ключ*, а не строку. При смене языка новый title равен старому (`Text("key") == Text("key")`), SwiftUI не отдаёт обновление в UIKit — заголовок «залипает» на старом языке, пока вью не пересоздадут. `.localizedNavigationTitle` резолвит строку заранее через `Bundle.currentLocalizedString` в `Text(verbatim:)` (значение реально меняется) и читает `\.locale` (форсит ре-эвал при переключении). **Не** лечи это через `.id(locale)` — он пересоздаёт всё поддерево, сбрасывает scroll/search/navigation state и провоцирует тяжёлый ре-рендер (см. ниже).
5. **Любая строка в UIKit-мост** (toolbar title, `UINavigationItem` и т.п.): если не обновляется при смене языка — резолвь заранее через `Text(verbatim: Bundle.currentLocalizedString("key"))`.
6. **Форматирование** (`String(format:locale:)`, числа, даты) → передавай актуальный locale.
7. Тесты на согласованность ключей — `RecipeScalerNativeTests/LocalizationConsistencyTests.swift`. При добавлении ключей убедись, что en и ru заполнены.

### Известный шум в консоли при смене языка

При переключении видны предупреждения вида `Background task still not ended … CABackingStoreCollect` / `_UIRemoteKeyboard XPC disconnection`. Это **системные** task'и UIKit (Core Animation собирает backing store, отключается служба клавиатуры), приложение их не создаёт — `endBackgroundTask` со своей стороны звать бесполезно. Появляются из-за тяжёлого синхронного ре-рендера дерева на смене locale; на симуляторе это безобидный шум, не баг и не повод «чинить background task». Снизить — делать переключение легче: не пересоздавать `NavigationStack`/тяжёлые вью (`.id(locale)` уже убран) и снимать фокус с текстового поля перед сменой языка. Единственный app-owned background task — в `TimerManager` (`BGProcessingTask`), он корректно спарен `begin`/`end` и к языку отношения не имеет.

## Agent loop (чинить до зелёного)

Для задач «почини», «доделай», «пока не работает» — **сначала прочитай и выполни** skill `.agents/skills/fix-until-green/SKILL.md` (триггеры: `/fix-until-green`, «дочини», «пока не заработает»).

Кратко:

1. **Claim** — одна проверяемая формулировка: условие + как измерить + порог (не «стало лучше»).
2. **Цикл** (до 5 итераций): правка → проверка агентом → при провале снова правка. **Не** писать «готово», пока claim не подтверждён локально.
3. **Проверки** (по возрастанию, что реально доступно в сессии):
   - обязательно: `rtk xcodebuild … build` (см. ниже);
   - если есть тест под область: `rtk xcodebuild … test` с нужным `-only-testing:…`;
   - если уже есть `scripts/verify-<feature>.sh` под эту фичу — запустить (готовый shortcut, **новый скрипт не обязателен**);
   - баг без автотеста: `/debug` + логи симулятора (`Library/Application Support/debug-session.ndjson`) или XCTest, не «проверь на телефоне».
4. **Вердикт** в конце: `VERIFIED` / `NOT VERIFIED` / `INCONCLUSIVE` + одна строка evidence (команда, exit code, метрика).
5. **Физический iPhone** — агент не может замкнуть UI-loop без тебя; для UX-багов приоритет — симулятор или XCTest.

Отдельные skills: `debug` (root cause по логам), `verify-this` (оформление claim/evidence), `check-work` (опциональный второй проход по diff).

## Сборка после правок

После завершения изменений в Swift/Xcode **агент обязан сам прогнать сборку** и убедиться, что проект компилируется, прежде чем считать задачу выполненной. Не проси пользователя проверить compile, если сборку можно запустить локально.

```bash
rtk xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  build
```

`<UDID>` — из `xcrun simctl list devices available` (например iPhone 16, OS 18.6). Имя без OS часто не резолвится — предпочитай `id=`. При ошибках — исправить и пересобрать. После build — проверки из раздела «Agent loop» (тесты / существующий `scripts/verify-*.sh`, если есть).

## Learned User Preferences

- UX/UI parity with the **mobile web** layout in `../recipe-scaler-web/recipe-scaler` (same hierarchy and behavior; pixel-perfect match not required).
- Run builds, simulator checks, and reproduction steps yourself when possible — do not ask the user to verify what the agent can run locally. After code changes, run the **build** from раздела «Сборка после правок» (см. выше).
- For bugs, find root cause from logs/crash reports first (`/debug`); avoid speculative fixes.
- Agent debug ingest to Mac `localhost` does not work on a physical iPhone — use Xcode console, on-device logs, or prod-safe instrumentation.
- Spec Kit task order is flexible; closing remaining polish tasks in any order is fine.
- Capture durable UX requirements in `specs/<feature>/` so follow-up work does not lose constraints.
- Match web behavior for shared UI (e.g. masked `userId`, ingredient rows without unit labels, component-level nutrition editing).

## Learned Workspace Facts

- Monorepo layout: native app here; web sources in `../recipe-scaler-web`; production API host `https://recipe-scaler.ru`.
- Debug builds auto-login the configured prod debug user — do not rely on manual seed entry in routine testing. But in case you need seed phrase use: `mass layer gossip slight bachelor broken spend story rabbit biology tower blast`
- Offline-first app, app must work in offline except some features like discover section.
- Recipes **v1/v2** are read-only on iOS with a legacy banner; **v3** editing and v1/v2→v3 migration happen on web app only.
- Feature verification scripts: `scripts/verify-<feature>.sh` and `scripts/verify-all.sh`.
- Grok Build session transcripts: `~/.grok/sessions/%2FUsers%2F...%2Frecipe-scaler-native/<session-id>/` (`updates.jsonl`, `summary.json`).

