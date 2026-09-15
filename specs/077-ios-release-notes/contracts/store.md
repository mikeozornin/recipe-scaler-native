# Contract: ReleaseNotesStore

Инъекция: `init(defaults: UserDefaults, catalog: [IOSReleaseNote])`.
Продакшен: `UserDefaults.standard`, `IOSReleaseNotesCatalog.notes`.

Стор **не** знает про screenshot-capture. Скрытие баннера в DEBUG — chrome-инвариант
(`ReleaseNotesChrome` / `DebugLaunchOptions.screenshotCapture`), как у `SystemBannerChrome`.
`showsBanner` остаётся чистым сравнением max каталога и `lastViewed`.

## Seed

1. Прочитать Int по ключу `releaseNotes.lastViewedVersion`.
2. Если нет валидного Int:
   - если `catalog.max != nil` → записать max;
   - иначе записать `0`.
3. `showsBanner` после seed: false, если ключа не было (только что засидили) **или** lastViewed ≥ max **или** каталог пуст.
   После seed missing-ключа баннер всегда скрыт в этом запуске? Нет: seed выполняется один раз на жизнь ключа. В том же процессе после seed lastViewed == max (или 0 при пустом каталоге) → баннера нет.

Повторный init с уже записанным ключом **не** уменьшает lastViewed, даже если тестовый каталог меньше.

## Dismiss / presentSheet

- Пустой каталог: no-op на диск для «изобретения» нот; sheet не открывать из баннера (баннера нет).
- Непустой: вычислить `unread = versions > lastViewed` (для sheet), затем записать max, `showsBanner = false`.
- `presentSheet` выставляет `expandedVersions = unread` **до** записи, затем `isSheetPresented = true`.

## Logout

Store не подписан на logout. `AppContainer.performLogoutTeardown` **не** вызывает ничего на этом сторе.
