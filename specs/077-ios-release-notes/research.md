# Research: 077 iOS release notes

## Каталог в бинарнике

- Decision: статический Swift-массив `IOSReleaseNotesCatalog.notes`, не JSON/plist codegen.
- Rationale: ревью в PR; пустой title ловится глазами и в `prepare-ios-release`; нет лишнего пайплайна.
- Alternatives considered: xcstrings для нот (смешает хром и контент); бандл JSON (лишний парсер).

## Persistence lastViewed

- Decision: `UserDefaults.standard`, ключ `releaseNotes.lastViewedVersion`, не App Group.
- Rationale: спека запрещает кросс-процесс; logout не должен трогать маркер.
- Alternatives considered: Keychain (избыточно); сервер (вне scope); App Group (виджеты вне scope).

## Seed vs пустой каталог 077

- Decision: missing key + непустой каталог → seed `max`, баннера нет. Missing key + пустой каталог → записать `0`, баннера нет.
- Rationale: иначе сборка 077 с пустым каталогом оставит ключ пустым, а первая нота в следующей сборке будет засижена как «ключа нет».
- Alternatives considered: placeholder-нота version 1 в 077 (появится строка архива без смысла); не писать ключ (ломает «баннер со следующей сборки»).

## UI слоты

- Decision: отдельные `ReleaseNotesChrome` / `ReleaseNotesListRow` сразу **под** `SystemBannerChrome` / `SystemBannerListRow` во всех ветках Recipes (list, empty, loading, collections list/grid). Не расширять `SystemBannerView`.
- Rationale: FR-002 запрещает канал 061; порядок DatabaseInitFailed → 061 → новости.
- Alternatives considered: один композитный chrome (смешает каналы); sticky header (запрещён спекой).

## Sheet presentation

- Decision: `ReleaseNotesStore.isSheetPresented` + `expandedVersions` считаются в `presentSheet()` до `markViewed(max)`.
- Rationale: один sheet с баннера и Профиля; FR-009.
- Alternatives considered: локальный `@State` в каждом view (два источника правды).

## Visual

- Decision: карточка как `SystemBannerView` (padding 12, radius 10, secondarySystemBackground, `.appHeadline` / `.appFootnote`). Метка обновлений footnote secondary, title — headline. Тело баннера тапабельно; крестик — отдельная кнопка.
- Rationale: assumption спеки; layout.md не нужен.
- Alternatives considered: жёлтая веб-полоска (запрещена).
