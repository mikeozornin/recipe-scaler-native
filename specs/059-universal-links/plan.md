# Plan: Universal Links для публичных share-URL

**Date**: 2026-08-04 | **Spec**: [spec.md](./spec.md)

## Очерёдность

1. **AASA на web** — без файла на домене UL не заработают
2. **Entitlements + portal doc** (в параллель с 1)
3. **DeepLinkRouter + AppShellCoordinator + entry points** (после контракта paths)
4. **Тесты + build** (после 3)
5. **Деплой AASA + smoke curl** (после 1)

## 1. AASA (recipe-scaler-web)

### Изменения

| Файл | Действие |
|------|----------|
| `server/src/routes/apple-app-site-association.ts` | Создан |
| `server/src/app.ts` | Mount `/.well-known` AASA |
| `server/src/__tests__/apple-app-site-association.test.ts` | Создан |

### Downstream consumers

- [x] **Nginx** — уже `proxy_pass` `/.well-known` → Node; OAuth well-known рядом
- [x] **iOS CDN / device** — читает AASA при первой установке / периодически
- [x] **MCP OAuth** — не пересекается (`/oauth-authorization-server` vs AASA path)

### Positive invariants

- OAuth `/.well-known/oauth-*` по-прежнему 200
- AASA не редиректит; `Content-Type: application/json`

## 2. Native entitlements + docs

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/RecipeScalerNative.entitlements` | Associated Domains |
| `RecipeScalerNative/RecipeScalerNativeDebug.entitlements` | То же |
| `docs/PAID-APPLE-DEVELOPER-REQUIRED.md` | Чеклист Associated Domains + AASA curl |
| `docs/NATIVE-FEATURES-NO-PAID-ACCOUNT.md` | UL больше не «отложено навсегда» — ссылка на 059 |

## 3. Router + shell

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Routing/DeepLinkRouter.swift` | HTTPS parse + cases |
| `RecipeScalerNative/Routing/AppShellCoordinator.swift` | Discover navigation |
| `RecipeScalerNative/RecipeScalerNativeApp.swift` | `NSUserActivityTypeBrowsingWeb` |
| `RecipeScalerNativeTests/DeepLinkRouterTests.swift` | UL cases |

### Downstream consumers

- [x] **SwiftUI** — `AppShellView` `onChange(pending)` → `handleDeepLink`
- [x] **Cross-process** — Share/Action outbound URLs не меняем
- [x] **PublicURLBuilder** — формат без изменений (уже `/public/@/…`)
- [x] **recipe-scaler://** — отдельные cases, без пересечения с Discover

### Positive invariants

- `recipe-scaler://recipe/{id}` → My Recipes
- `https://…/public/@/…` → Discover
- Legacy `/public/{uuid}` и shopping-list → не `pending`

## 4. Verify

- Unit tests DeepLinkRouter
- `xcodebuild` build
- `curl` AASA на prod после деплоя
