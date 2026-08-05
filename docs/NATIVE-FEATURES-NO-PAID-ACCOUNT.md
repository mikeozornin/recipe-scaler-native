# Нативные фичи iPhone — архив «до платного аккаунта»

**Проект:** Recipe Scaler Native  
**Статус:** **архив.** Платный Apple Developer Program **получен** (team `ZBPX4JYT24`, 2026). Актуальный чеклист портала и device smoke — [`PAID-APPLE-DEVELOPER-REQUIRED.md`](./PAID-APPLE-DEVELOPER-REQUIRED.md).  
**Дата исходника:** 2026-06-12; архивировано 2026-08-05.

## Зачем этот документ остался

Историческая подборка фич, которые можно было вести **без** платного аккаунта (симулятор / Personal Team). Многие пункты уже сделаны; то, что требовало портала, перенесено в PAID-doc.

| Было «без платного» | Статус сейчас |
|---------------------|---------------|
| Live Activities (локальные) | ✅ 044 (+ push 058 v1) |
| WidgetKit UI | ✅ 030 v1; background 030 v2 в коде |
| App Intents / Shortcuts | ✅ в продукте |
| EventKit Reminders | ✅ |
| Локальные UN | ✅ (рядом с APNs 023) |
| APNs / Share на железе / UL / TestFlight | → [PAID-doc](./PAID-APPLE-DEVELOPER-REQUIRED.md) |

## Матрица платформы (справочно)

| Фреймворк / возможность | Нужен платный portal? | Примечание |
|---|---|---|
| **ActivityKit** (локальные апдейты) | нет для симулятора | Push-updates LA — Push capability (058) |
| **WidgetKit** | App Group на железе | silent / WidgetKit push — 030 + 023 |
| **App Intents** | нет | только код |
| **VisionKit / Speech / EventKit / PDFKit / Haptics** | нет | usage-descriptions |
| **UserNotifications** локальные | нет | без APNs |
| Remote push (**APNs**) | да | spec 023 |
| Share / Action на **реальном** iPhone | да | spec 025 + Keychain Sharing |
| **App Groups** / **Keychain Sharing** на железе | да | PAID-doc |
| Universal Links (**Associated Domains**) | да | spec 059; схема `recipe-scaler://` — без portal |
| iCloud / CloudKit, Sign in with Apple, WeatherKit | да | не в текущем scope |
| **TestFlight / App Store** | да | |

> Кастомная URL-схема `recipe-scaler://` работает без Associated Domains. Universal Links (`https://recipe-scaler.ru/…`) — portal + AASA.

## Уже сделано (из исходного backlog)

Ниже — текст июня 2026; не редактировать как живой план. Актуальные спеки: `044`, `030`, `036`, `025`, `023`, `039`, `057`, `059`.

### ✅ Синхронизация списка покупок с Apple Reminders (EventKit)

Native bridge к Reminders; web shopping list остаётся source of truth через CRDT.

### ✅ Live Activities для таймеров

Lock Screen + Intent pause/resume; дальше — push updates (058) и виджет (030).

### ✅ Виджеты таймеров

Home / Lock Screen TimerWidget; background refresh — 030 v2.

### ✅ App Intents / локальные notification actions

Таймеры и shortcuts без APNs для локального пути.

## Осознанно требовало платного аккаунта

Remote push (023), Share/Action на железе (025), App Groups / Keychain на device, Universal Links (059), Watch companion distribution quirks (039), TestFlight/App Store — см. **актуальный** [`PAID-APPLE-DEVELOPER-REQUIRED.md`](./PAID-APPLE-DEVELOPER-REQUIRED.md).

## Как проверяли без платного (история)

- Схема `RecipeScalerNative`, симулятор iOS 17+.
- Live Activities / виджеты / App Intents — на симуляторе.
- Device smoke Share / APNs / UL — только после оплаты программы.
