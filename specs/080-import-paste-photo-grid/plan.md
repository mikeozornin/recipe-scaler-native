# План: импорт — «Вставить», подсказка про «Поделиться» и сетка фото

**Дата**: 2026-10-08  
**Спека**: [spec.md](./spec.md)

## Границы

- **В scope**: вкладки «Текст» и «Фото» в `ImportRecipeSheet`; новые view в `Views/Import/`; PhotoKit/AVFoundation-обёртки в `Utils/`; строки в `Localizable.xcstrings` и `InfoPlist.xcstrings`; ключи `NSPhotoLibraryUsageDescription` и `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` в `Info.plist`.
- **Вне scope**: вкладка «Файл», серверный API, Share Extension, баннер буфера в списке рецептов (076), сохранение снимков в медиатеку, переименование вкладки «Текст».
- **STOP conditions**: системный алерт вставки при открытии вкладки «Текст»; запрос доступа к камере без тапа по ячейке камеры; потеря выбора или снимка после закрытия камеры; сервер отклоняет фото из сетки по формату.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | Рецепт создаётся тем же `RecipeImportAPI` и сохраняется прежним путём; новых документов нет. |
| Web parity | N/A | Меняется только нативный способ выбрать вход для импорта; формат запроса `importImages` прежний. |
| Offline-first | PASS | Вкладки «Текст»/«Фото» и раньше отключались офлайн; логика `isOnline` → `.file` не тронута. |
| Native UI | PASS | Системные `PasteButton`, `PhotosPicker`, `UIImagePickerController`, PhotoKit; Martian через `AppTypography`. |
| Phased delivery | PASS | Три независимых части: баннер, карточка «Поделиться», сетка фото. |
| i18n | PASS | Все строки — ключи `import.*` в xcstrings (en + ru); `lint-i18n.sh`. |
| Documentation | PASS | spec.md + этот план. |

## Очерёдность

1. **PhotoKit/камера-обёртки** (`ImportPhotoLibrary`, `ImportCamera`) — сетка зависит от них.
2. **`ImportPhotoGridSection`** и перевод `ImportRecipeSheet` на `[ImportPhotoPick]` — убирает старый `PhotosPicker` + полосу превью.
3. **`ImportPasteBanner`**, новый плейсхолдер, **`ImportShareHintCard`** — независимы от фото.
4. **Строки и Info.plist**, затем сборка, тесты, smoke, проверка на симуляторе.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNative/Utils/ImportPhotoLibrary.swift` | Создать | Альбомы, выборка фото, миниатюры, загрузка оригинала, перекодирование в JPEG. |
| `RecipeScalerNative/Utils/ImportCamera.swift` | Создать | Живое превью камеры в ячейке и съёмка через `UIImagePickerController`. |
| `RecipeScalerNative/Views/Import/ImportPhotoGridSection.swift` | Создать | Сетка 3 колонки, меню альбома, счётчик, нумерованный выбор, limited/denied. |
| `RecipeScalerNative/Views/Import/ImportPasteBanner.swift` | Создать | Баннер с `PasteButton` и текстом баннера 076; виден, пока в буфере ссылка и поле пустое. |
| `RecipeScalerNative/Views/Import/ImportShareHintCard.swift` | Создать | Карточка-подсказка с мини-шитом «Поделиться» и крестиком; чужие иконки серые. |
| `RecipeScalerNative/Views/ImportRecipeSheet.swift` | Изменить | Новые секции «Текст», сетка вместо `PhotosPicker`, загрузка фото при отправке. |
| `RecipeScalerNative/AccessibilityIdentifiers.swift` | Изменить | `importPasteBanner`, `importShareHint`, `importPhotoCamera`. |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменить | Ключи `import.paste-banner.*`, `import.share-hint.*`, `import.photos.*`, плейсхолдер. |
| `RecipeScalerNative/Resources/InfoPlist.xcstrings`, `Info.plist` | Изменить | Доступ к медиатеке и уточнённая причина доступа к камере. |
| `RecipeScalerNativeTests/ImportPhotoEncodingTests.swift` | Создать | Формат и имя файла фото, равенство `ImportPhotoPick`. |
| `RecipeScalerNative.xcodeproj/project.pbxproj` | Изменить | Регистрация новых файлов. |

## Downstream consumers

- **SwiftUI views**: только `ImportRecipeSheet` (вкладки «Текст» и «Фото»); остальные места открытия импорта (`-OpenTab=import`, кнопка «Добавить рецепт», seed из буфера 076) проходят через тот же sheet.
- **Cross-process**: N/A — Share Extension, виджеты и часы не читают состояние импорта; карточка лишь описывает существующий Share Extension.
- **Sync boundaries**: N/A — `RecipeImportAPI.importImages` получает те же `[ImportPhotoItem]`, валидатор `ImportPhotoValidator` прежний.
- **Persisted state**: UserDefaults `import-share-hint-dismissed` (карточка закрыта, на устройство). Выбор, снимки и альбом живут в `@State` sheet'а; в медиатеку ничего не пишется.
- **Tests / verify scripts**: `ImportPhotoEncodingTests`, `LocalizationConsistencyTests` (ключи `import.*`), `lint-i18n.sh`, `verify-ui-smoke.sh` (открытие импорта).

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| Фото в поддерживаемом формате | Уходит на сервер теми же байтами с именем по типу (`image.png`) | `RecipeScalerNativeTests/ImportPhotoEncodingTests/testSupportedFormatPassesThroughUnchanged` |
| Фото в неподдерживаемом формате | Перекодировано в JPEG (`FF D8`), имя `image.jpg` | `RecipeScalerNativeTests/ImportPhotoEncodingTests/testUnsupportedFormatIsReencodedAsJPEG` |
| Нечитаемые данные | Не попадают в запрос | `RecipeScalerNativeTests/ImportPhotoEncodingTests/testUndecodableUnsupportedDataIsDropped` |
| Выбор по ячейке | Снимок/фото опознаётся по своему id, номер в кружке — порядок выбора | `RecipeScalerNativeTests/ImportPhotoEncodingTests/testPickEqualityFollowsTheItem` + ручная проверка на симуляторе |
| Закрытие камеры | Вкладка «Фото» и выбор остаются на месте | ручная проверка на симуляторе (`-OpenTab=import -ScreenshotCapture 1`, выбор → камера → отмена) |
| Крестик на карточке «Поделиться» | Карточки нет и после перезапуска | ручная проверка на симуляторе |
| Буфер со ссылкой / без | Баннер есть / баннера нет | ручная проверка (`simctl pbcopy`) |
| Все новые строки | Есть en и ru | `bash scripts/lint-i18n.sh` |

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| `ImportPhotoLibrary.load()` (`.task(id: mode)`) | вкладка `.photo` | статус доступа перед выборкой | SwiftUI `.task` при смене вкладки / закрытии sheet | повторный вход во вкладку не дублирует observer (`observer == nil`) |
| `fetchAssets()` (detached fetch) | `albumID` на момент запуска | `albumID == id` перед присвоением `assets` | нет — результат отбрасывается при смене альбома | ручная смена альбома |
| `ImportPhotoAssets.thumbnails` (AsyncStream) | `asset.localIdentifier` | — | `.task(id:)` ячейки; `onTermination` отменяет запрос PhotoKit | прокрутка сетки |
| `ImportCameraPreview.start/stop` (serial queue) | флаг `wanted` | `wanted && running` перед `isLive = true` | `onDisappear` ячейки камеры, открытие камеры | быстрый уход с вкладки не показывает превью |
| `ImportCameraCapture` JPEG-кодирование | колбэки, снятые до dismiss | — | — (одноразовый picker, `picker == nil` guard) | повторный тап по камере игнорируется |
| `loadPhotoItems()` при отправке | `photoSelection` на момент submit | ошибка, если фото не загрузилось | `importTask?.cancel()` в `onDisappear` | закрытие sheet во время загрузки |
| `PasteButton` → `loadText` | providers одного тапа | — | — | вставка при `isProcessing` невозможна (`disabled`) |
| Проверка буфера (`.task(id: clipboardCheck)`) | номер проверки | `Task.isCancelled` перед присвоением | SwiftUI `.task`, новая проверка отменяет старую | смена буфера во время проверки |

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| logout | sheet закрыт → `@State` уходит | `.task` отменены | N/A | сессия камеры остановлена в `onDisappear` | индикатор камеры гаснет |
| account switch | как logout | как logout | N/A | как logout | как logout |
| stale session / cold start | `resetState()` чистит выбор и снимки при открытии | — | N/A | доступ к фото/камере берётся из системы | вкладка «Фото» показывает актуальный статус доступа |
| reconnect / partial failure | выбор сохраняется | `importTask` отменяем | N/A | `PHPhotoLibraryChangeObserver` снимается в `deinit` | ошибка `import.error-photo-corrupt`, выбор можно поправить и отправить снова |

## Verification

- `python3 scripts/verify-plan-policy.py specs/080-import-paste-photo-grid/plan.md` — PASS.
- `xcodebuild -scheme RecipeScalerNative -destination "platform=iOS Simulator,id=$SIM_ID" build` — BUILD SUCCEEDED.
- `bash scripts/test-fast.sh` — exit 0, включая `ImportPhotoEncodingTests`.
- `bash scripts/lint-i18n.sh` — exit 0.
- `bash scripts/verify-ui-smoke.sh` — exit 0.
- Ручная проверка на симуляторе (ru, светлая и тёмная тема): баннер в одну строку, карточка «Поделиться» с выделенной плиткой, запрос доступа к фото при первом входе во вкладку, сетка с камерой первой, номера выбора, «N / 8», камера → отмена сохраняет вкладку и выбор.
- Съёмка реального кадра — только на устройстве (камера симулятора не делает снимок).

## Rollback / maintenance

- Как откатить: revert ветки; старый `PhotosPicker` + полоса превью вернутся из `master`, ключи `import.photos.*` станут неиспользуемыми.
- Что будет взаимодействовать с изменением в будущем: смена лимитов `ImportPhotoValidator`, новые форматы на сервере (`supportedUTTypes`), редизайн `ImportRecipeSheet`.
- Временные allowlist/quarantine: нет.
