

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

Прочитай и выполняй @RTK.md. Prefix shell commands with `rtk` when filtering output (see `CLAUDE.md` / `RTK.md`).

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

