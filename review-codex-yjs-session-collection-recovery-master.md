# Code Review: master

## Summary

Проверены native sync/session boundaries, outbox/debouncer, collection
handshake/recovery, server collection loading and shared sync protocol. В
исходной реализации были найдены и исправлены риски stale-session writes,
неполного удаления outbox при recovery, продолжения после ошибки загрузки
recipe rows и принятия stale collection response.

## Исправления

1. Все delayed callbacks/tasks и `DocumentManager` mutation paths используют
   захваченный immutable `(userId, sessionId, docKey)` context и проверяют его
   после `await`.
2. `UpdateDebouncer` и offline outbox теперь scoped по account/session;
   in-flight ack удаляет только подтверждённую batch и не теряет tracking при
   reconnect.
3. Collection recovery очищает debouncer, in-flight/queue/snapshot и memory
   document, после чего запускает empty-state-vector handshake. Collection gate
   остаётся закрытым до валидного ответа.
4. Server collection summary не маскирует ошибку чтения `recipes` как пустую
   коллекцию. Native отвергает malformed present summary, а отсутствие
   additive summary оставляет backward-compatible non-destructive path.
5. Recovery `sync_step1` получил opaque `requestId`, который server echoes;
   native принимает `sync_step2` только с совпадающим ID. Legacy
   `document_loaded` fallback разрешается только после timeout probe.

## Verification

- Native focused XCTest: **25 passed, 0 failed** — `SyncEventHandlerSyncStep2Tests`,
  `YjsOfflineOutboxTests`, `YjsSessionIsolationTests`.
- `xcodebuild build -scheme RecipeScalerNative ...`: **BUILD SUCCEEDED**.
- Server focused suite: **19 passed, 0 failed**.
- `bun run build` в `recipe-scaler-web/server`: **exit 0**.

## Recommendation

**Approved after fixes.** Полный live E2E с production server не запускался;
проверка ограничена focused regression suites и compile/build evidence.
