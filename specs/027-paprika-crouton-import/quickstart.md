# Quickstart: импорт Paprika / Crouton

**Feature**: `027-paprika-crouton-import`

## Предусловия

- Debug build с auto-login (см. [docs/PROJECT.md](../../docs/PROJECT.md))
- Симулятор iOS 17+ или устройство
- Тестовый файл экспорта (см. ниже)

## Получить тестовый экспорт

### Paprika (macOS / iOS / Android)

1. Paprika → **Settings** → **Export** → **Paprika Recipe Format** (не HTML).
2. Сохранить `My Recipes.paprikarecipes`.
3. Для unit-тестов: распаковать один `.paprikarecipe` из ZIP (gzip JSON внутри).

### Crouton (iOS / macOS)

1. Crouton → **Settings** → **Export Recipes** (ZIP).
2. Внутри ZIP — файлы `*.crumb` (plain JSON).

### Синтетические fixtures (без лицензии на чужие рецепты)

```text
RecipeScalerNativeTests/Fixtures/ThirdPartyImport/
├── paprika-minimal.paprikarecipe      # gzip JSON, 1 recipe, no photo
├── paprika-three.paprikarecipes       # ZIP, 3 recipes
├── crouton-minimal.crumb              # 1 recipe, section heading
├── crouton-batch.zip                  # 3 recipes
├── crouton-with-photo.crumb           # 1 recipe, 1×1 JPEG (T058)
├── crouton-real-export.zip            # реальный Crouton ZIP с кириллицей
└── expected/                          # sidecar expected counts
```

### Encoding note (Crouton ZIP bug)

Crouton пишет имена файлов внутри ZIP как UTF-8 байты, но **не** выставляет
UTF-8 general-purpose bit flag (bit 11) в central directory. Стандартные ZIP
readers (macOS `unzip`, default `ZIPFoundation`) декодируют такие имена как
CP437 → мусор → APFS отказывается писать файл и `unzip` показывает
`write error (disk full?)` prompt.

`ThirdPartyFormatDetector.decodeEntryPath` обрабатывает этот случай: если
дефолтный (CP437) decode даёт не-ASCII символы, а повторный decode как UTF-8
валиден — берётся UTF-8 вариант. В fixture `crouton-real-export.zip` второй
entry (`Домашнее мороженое.crumb`) проверяет это поведение end-to-end.

## Ручной прогон

1. Собрать и запустить приложение.
2. Открыть вкладку **Import**.
3. Выбрать режим **File** (Paprika / Crouton).
4. **Import from Files** → выбрать `.paprikarecipes` / `.paprikarecipe` / Crouton ZIP / `.crumb`.
5. Дождаться progress «N / M».
6. **Один рецепт** → автоматический переход на detail.
7. **Batch** → toast «Imported N recipes» → список рецептов.

### Проверки на detail

- [ ] Название совпадает с источником
- [ ] Ингредиенты: строки не пустые; количества не «выдуманы»
- [ ] Шаги: ordered list, без префикса «Step 1» в тексте пункта
- [ ] `originalRecipeLink` / source — если были в экспорте
- [ ] Фото — если online и было в экспорте
- [ ] Кириллические имена файлов сохраняются (`Домашнее мороженое.crumb`)
- [ ] Метаданные: `duration` / `cookingDuration` → paragraph «N min»
- [ ] Папки: `categories` (Paprika) / `tags` (Crouton) создаются как коллекции

### Офлайн

1. Airplane mode.
2. Импорт архива **без** фото → рецепты в списке.
3. Сообщение о пропущенных фото (если были).
4. Reconnect → sync → рецепты на `https://recipe-scaler.ru` web.

### Негативные кейсы

| Файл | Ожидание |
|------|----------|
| `recipe.txt` | Localized unsupported format |
| Пустой ZIP | Error, коллекция без изменений |
| RS export v1.3 zip | Unsupported (→ spec 020, другой pipeline) |

## Unit-тесты

```bash
# Быстрый прогон (parser + detector + XmlFragment, без test host stall):
xcodebuild test-without-building \
  -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5' \
  -only-testing:RecipeScalerNativeTests/PaprikaRecipeParserTests \
  -only-testing:RecipeScalerNativeTests/CroutonRecipeParserTests \
  -only-testing:RecipeScalerNativeTests/ThirdPartyFormatDetectorTests \
  -only-testing:RecipeScalerNativeTests/DescriptionXmlFragmentWriterTests
```

## Verify script

`scripts/verify-third-party-import.sh` — собирает приложение и прогоняет:

- `PaprikaRecipeParserTests`
- `CroutonRecipeParserTests`
- `ThirdPartyFormatDetectorTests`
- `DescriptionXmlFragmentWriterTests`
- `ThirdPartyImportIntegrationTests` (помечены `XCTSkip` — виснет на test host auto-login)

Запуск:

```bash
./scripts/verify-third-party-import.sh
```

Exit non-zero на первой ошибке.

## Известные ограничения тестового окружения

- Тест-хост (RecipeScalerNative.app) при launch делает Yjs sync с prod-сервером
  (debug auto-login на симуляторе). Это блокирует запуск интеграционных тестов,
  использующих `DocumentManager`/`YjsSyncService`. Парсерные и detector-тесты
  работают стабильно — они не требуют test host network IO.
- Опция `-DisableDebugAutoLogin=1` добавлена в scheme, но xcodebuild её не
  подхватывает с CLI без `-test-iterations` / scheme UI. CI с отдельным test
  plan решит проблему.

## Ссылки

- Spec: [spec.md](./spec.md)
- Mapping contract: [contracts/third-party-recipe-formats.md](./contracts/third-party-recipe-formats.md)
- Import pipeline API: [contracts/third-party-import-service.md](./contracts/third-party-import-service.md)
- Mealie reference: [paprika.py](https://github.com/mealie-recipes/mealie/blob/mealie-next/mealie/services/migrations/paprika.py)
