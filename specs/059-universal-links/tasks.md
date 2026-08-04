# Tasks: 059-universal-links

## Phase 1 — Spec & docs

- [x] T001 Создать `spec.md` / `plan.md` / `contracts/aasa.md` / `tasks.md`
- [x] T002 Обновить `docs/PAID-APPLE-DEVELOPER-REQUIRED.md` (Associated Domains + AASA curl)
- [x] T003 Обновить `docs/NATIVE-FEATURES-NO-PAID-ACCOUNT.md` (ссылка на 059)

## Phase 2 — Web AASA

- [x] T010 Создать `server/src/routes/apple-app-site-association.ts`
- [x] T011 Mount в `server/src/app.ts` на `/.well-known`
- [x] T012 Unit test route
- [x] T013 Deploy на prod + smoke `curl`

## Phase 3 — Native

- [x] T020 Associated Domains в Release + Debug entitlements
- [x] T021 `DeepLink` cases + HTTPS parse в `DeepLinkRouter`
- [x] T022 `AppShellCoordinator` → Discover
- [x] T023 `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`
- [x] T024 Unit tests UL matrix
- [x] T025 `xcodebuild` build / tests
