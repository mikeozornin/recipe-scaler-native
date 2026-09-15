# Data model: 077 iOS release notes

## IOSReleaseNote

| Field | Type | Rules |
|-------|------|--------|
| version | Int | монотонный, ≥ 1 для реальных нот; уникален в каталоге |
| date | Date | календарная дата ноты (без времени); формат в UI — locale интерфейса |
| titleEn / titleRu | String | непустые на этапе добавления человеком |
| bodyEn / bodyRu | String | непустые; plain text, многострочный; без HTML |

Runtime: `title(for languageCode)` / `body(for:)` выбирают ru vs en. Нет fallback на другой язык как «перевод» — если код не ru, берём en.

## lastViewed

| State | Meaning |
|-------|---------|
| ключ отсутствует или value не Int | missing → seed |
| 0 | sentinel после пустого каталога; баннер когда max ≥ 1 |
| N ≥ 1 | пользователь закрыл/открыл лист при max ≥ N |

Баннер: `catalog.maxVersion > lastViewed && !catalog.isEmpty`.

## ReleaseNotesStore (observable)

| Field | Role |
|-------|------|
| lastViewed | зеркало диска после seed |
| showsBanner | derived |
| latestNote | note with max version |
| hasArchiveRow | `!catalog.isEmpty` |
| isSheetPresented | sheet binding |
| expandedVersions | snapshot unread at present |

Mutations: `seedIfNeeded()` (init), `dismissBanner()`, `presentSheet()`, `dismissSheet()`. Нет `clearForLogout()`.
