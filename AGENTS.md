

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

Полное описание типографики — в [ui.md](ui.md). Кратко: шрифты и размеры определены в `AppTypography.swift` / `AppFonts.swift`, **не хардкодь** их во view-файлах; используй `.appBody()` / `.appFootnote()` и `AppSectionHeader`. Правила и подробности — там же.

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
- Match web behavior for shared UI (e.g. masked `userId`, ingredient rows without unit labels, component-level nutrition editing, recipe ellipsis menu order, ingredient qty column right-aligned to main value with compact drag handle and swipe-from-right delete only).
- Account and public-profile settings use **iOS Settings patterns** (toggles, `NavigationLink` submenus, label–value rows); no explicit Save button; avatar as centered circle with Set photo below; descriptive copy uses `.appBody()` line-height per `ui.md`.
- Apple Reminders shopping-list sync: CRDT list stays source of truth; bidirectional completion sync; completed items stay in Reminders (marked, not deleted); Reminders note text must be localized.
- Shopping list header matches Recipes: large title with sort segment in the collapsible search slot (`UISearchController` / `UISearchBar` pattern — SwiftUI has no separate API for a custom block under large title).
- Collection folder rename uses inline **Cancel / Done** toolbar, auto-focus with select-all, and hides back button and ellipsis while editing; folder color picker is a preset grid in the rename toolbar (web parity, iOS-adapted).

## Learned Workspace Facts

- Monorepo layout: native app here; web sources in `../recipe-scaler-web`; production API host `https://recipe-scaler.ru`.
- Debug builds auto-login the configured prod debug user — do not rely on manual seed entry in routine testing. But in case you need seed phrase use: `mass layer gossip slight bachelor broken spend story rabbit biology tower blast`
- Offline-first app, app must work in offline except some features like discover section.
- Recipes **v1/v2** are read-only on iOS with a legacy banner; **v3** editing and v1/v2→v3 migration happen on web app only.
- Feature verification scripts: `scripts/verify-<feature>.sh` and `scripts/verify-all.sh`.
- Paid Apple Developer Program ($99/yr): optional for simulator/dev; TestFlight, App Store, App Groups on device, extensions, APNs — see `docs/PAID-APPLE-DEVELOPER-REQUIRED.md`. Timer push toggle hidden until server-synced APNs works; production push planned after Live Activities.
- Grok Build session transcripts: `~/.grok/sessions/%2FUsers%2F...%2Frecipe-scaler-native/<session-id>/` (`updates.jsonl`, `summary.json`).
- Native collections parity guide: `../recipe-scaler-web/llm/NATIVE_APP_COLLECTIONS.md` (web-authored reference for iOS implementation).
- Share Extension + Action Extension targets exist for URL/text import (`specs/025-share-extension`); full on-device Share Sheet testing needs paid program + App Group provisioning.
- Typography tokens and rules: `ui.md` (not duplicated in AGENTS.md); Russian `Localizable.xcstrings` typograf via `scripts/typograf-xcstrings` — surgical line edits only (preserve Xcode `"key" : "value"` formatting).

