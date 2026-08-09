# Async lifecycle, teardown и testing policy

Status: normative
Applies when: план или код добавляет/меняет `Task`, callback, continuation,
stream subscription, queued operation, socket handler, observer, persisted state,
cross-process IPC slot, server contract, custom decoder/encoder или resource pipeline.
Canonical source: этот файл + `specs/_template/overrides/plan-template.md`.
Owner: arch (recipe-scaler-native).
Last verified: 2026-08-09.

Правила ниже — project-wide. Они родились из повторяющихся регрессий в
`llm/reviews/` (socket-session crossing, guard-after-await, неполный teardown,
тесты без concurrency overlap, raw cross-target literals, строковая классификация
ошибок, unknown-ID fallbacks, missing bundle resources, locale/theme drift,
backward-compat без fixtures). Исторические reviews — append-only evidence; сами
находки не копируются сюда.

## 1. Async lifecycle

Любая `Task`, callback, continuation, queued operation, stream subscription или
socket handler, способная пережить породивший scope или содержащая suspension
point, обязана:

1. Захватить immutable operation context: session/epoch ID, expected user ID,
   socket-session/client identity, resource/document key.
2. Проверять `Task.isCancelled` и identity context после каждого suspension point
   и непосредственно перед каждым external side effect (network emit, persistence,
   observable mutation, system registration).
3. Иметь явного cancellation owner, который инвалидирует context и отменяет task
   при teardown.

`Task { @MainActor … }` без capture и re-check — недостаточен; `[weak self]` не
спасает, если service живёт всё время процесса (`AppContainer.shared`).

Plan template содержит обязательную секцию **Async lifecycle** с таблицей:
операция → captured identity → re-check после await → cancellation owner →
stale-completion test.

## 2. Guards и state machines вокруг `await`

Single-flight, re-entry, dedup, in-flight, pending, epoch и `lastHandled*` guard
эквивалентны state machine и оформляются по одним правилам:

- Guard ставится до первого `await` и снимается только через `defer` в самом конце
  операции.
- Permanent dedup по последнему значению запрещён, если одно и то же действие
  допустимо в новом consume cycle; использовать bounded TTL, generation/epoch или
  явный `clear()`.
- Если state мутируют несколько сервисов, оно выносится в отдельный тип с единым
  API и одним владельцем; кросс-сервисная неявная координация через `UserDefaults`
  и комментарии запрещена.
- Regression test обязан пересекать реальный suspension point (continuation,
  actor gate или injected provider); последовательный `await a; await b` не
  считается concurrency-тестом.
- Тест подтверждает точное число external side effects (call count, persisted
  row, emitted event), а не только локальное optimistic state.

## 3. Teardown и downstream ownership

Каждый владелец account-scoped ресурса предоставляет идемпотентный teardown
(`clearForSessionEnd` / `clearForLogout` / `invalidateSession`) и вызывается
session coordinator напрямую. Запрещено полагаться только на UI callbacks,
косвенные цепочки через несколько сервисов или успешный network cleanup.

Teardown matrix в плане обязана покрывать минимум:

- explicit logout;
- account deletion;
- stale session / cold-start invalidation;
- runtime token invalidation;
- account switch;
- socket reconnect;
- partial failure;
- process restoration.

Для каждой строки: in-memory, tasks/streams, persisted state (SQLite, SwiftData,
UserDefaults, App Group, Keychain), cross-process/OS surface (widgets, Live
Activities, App Intents, notifications), downstream notification. Это расширяет
секцию **Downstream consumers**, но фокусируется на cleanup postconditions.

Перед remote wipe локально захватываются все значения, нужные для best-effort
remote cleanup; локальный last-known-good state не уничтожается до подтверждения.

## 4. Offline-first last-known-good

Ошибка недоверенного remote update не доказывает повреждение локального
last-known-good snapshot. Локальные данные удаляются только после доказанной
локальной corruption или после успешного получения и проверки canonical
replacement.

CRDT state-vector equality не считается достаточным доказательством полноты
materialized collection: для collection-like документов нужен независимый
completeness signal (high-water mark, persisted count) или проверяемый
server recovery path. Plan и тесты покрывают malformed remote update, poisoned
snapshot и recovery failure (см. `verify-plan-policy.py` — секция Teardown).

## 5. Side-effect тесты

Regression test проверяет реальный observable effect, из-за которого возник
пользовательский симптом:

- call count провайдера;
- payload, отправленный в network (через injected transport);
- persisted row или snapshot;
- emitted log/event;
- downstream delivered state;
- bundle resource availability.

Дополнительно:

- Concurrency-тест содержит controllable suspension и overlap assertion.
- Unit/integration suites по умолчанию deny external network (`NoExternalNetworkURLProtocol`,
  injected `URLProtocol`); unexpected request = test failure.
- XCTest run с `0 executed` или массовым `XCTSkip` всегда красный.
- `RecipeScalerNativeUITests` и E2E infrastructure нельзя менять ради зелёного
  теста без отдельного подтверждения пользователя.

## 6. Cross-target contracts

Любой идентификатор, пересекающий process, target или platform boundary
(App Group key, notification name, route prefix, payload field, feature key,
server error code, media asset name, accessibility identifier), объявляется
один раз в минимальном общем модуле (`RecipeScalerCore` фасады: `AppGroup`,
`SharedDeviceId`, `WidgetPushTokenClient`, и т.д.). Writer и reader используют
один символ.

- Все ingress paths для одного значения применяют один validator/normalizer.
- Raw literal с известным contract prefix вне canonical declaration запрещён;
  допускается только в allow-listed fixture/test с owner/reason/expiry.
- Mirror в UI-test bundle (`Selectors.swift`) валидируется consistency-тестом.
- Malformed, empty, stale и unknown input удаляется из slot и не передаётся
  в navigation/sync/Spotlight.

## 7. Composition root

В main app, SwiftUI views и app services запрещено получать app-level dependency
через `Service.shared` или `AppContainer.shared`. Используется constructor /
`@Environment` injection либо closure/protocol, переданный composition root.

`.shared` разрешён только для:

- declaration самого compatibility shim;
- AppIntents и pre-bootstrap entry points с явным allow-list;
- документированных OS-фасадов (`SharedAuthStore`, `AppGroup`,
  `TimerSnapshotStore`, `APIClient.shared`).

Cross-service teardown выполняет injected coordinator/protocol/closure; service
не открывает соседние зависимости через global graph. Спекулятивный `.shared` без
production caller не добавляется.

## 8. Внешние и серверные контракты

External/server payload декодируется в typed code/DTO (`ServerErrorCode`,
`SyncErrorCode`). Branching по `localizedDescription`, `contains` и `hasPrefix`
для server errors разрешён только в одном явно названном legacy adapter с
exhaustive fixtures; для новых контрактов запрещён.

Unknown enum/scene/route/manifest/server ID:

- DEBUG/CI → hard failure с конкретным ID.
- Release → safe user-facing state + structured log.
- Legacy aliases → explicit map или versioned decoder.
- Prefix-based semantic fallback (любой unknown ID принимается по совпадению
  префикса и направляется в семантически другой flow) запрещён.

## 9. Backward compatibility и миграции

Любое изменение persisted/serialized контракта (Codable, cache schema, DB
migration, wire payload) требует fixture-тестов:

1. Current version roundtrip.
2. Предыдущая поддерживаемая версия.
3. Отсутствующее поле, добавленное в новой версии.
4. Отсутствующий `metadata.version` трактуется как `1.0`.
5. Unknown future version имеет явно выбранное поведение.
6. Legacy значения сохраняются; новые поля получают documented default.
7. Migration повторно запускается безопасно или явно one-shot.

Наличие `init(from:)`, `decodeIfPresent`, custom version normalization или DB
migration без legacy fixture test блокирует review.

## 10. Generated resources и bundle verification

Наличие ресурса в source tree, manifest или generation output не считается
verification. Required resource считается доставленным только после проверки
собранного `.app` / `.appex`:

1. Собрать target.
2. Получить путь build product.
3. Проверить expected resource matrix (locale × theme × variant).
4. Запретить destination collisions.
5. Проверить размер/тип каждого файла.
6. Запустить resolver против собранного bundle.
7. Fail, если required matrix пуста или неполна.

Optional/generated resources помечаются явно `optional: true`; отсутствие
required resource не может быть warning.

## 11. Runtime locale/theme

Для runtime настроек `system` означает effective environment value, а не
отдельный light/default case. Любой cached, scheduled или OS-registered
artifact, зависящий от locale/theme (notification categories, pending content,
widgets, Live Activities, App Intents snapshots, UIKit bridges, image/video
resolvers, process-local caches), либо пересоздаётся при изменении effective
value, либо документированно фиксируется на момент создания.

Plan template содержит секцию **Locale / theme consumers**; тест покрывает
explicit light, explicit dark, system + OS light, system + OS dark, change OS
appearance при открытом экране, runtime language change при существующих
surfaces.

## 12. Чего не делать

- Не превращать единичную feature-specific находку в глобальное правило; см.
  `llm/reviews/` для контекста, но не копируй точечные продуктовые решения.
- Не подменять human layout acceptance review-agent verdict.
- Не смягчать build, i18n без fallback, positive invariants, downstream
  consumers и review isolation.
- Не считать screenshot/`rg`/build зелёным доказательством поведения — см.
  `docs/TESTING.md` §5.
