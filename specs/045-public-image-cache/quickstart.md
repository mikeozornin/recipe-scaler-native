# Quickstart: проверка public image cache

**Дата**: 2026-06-15  
**Спека**: [spec.md](./spec.md)

## Предусловия

- Backend доступен
- Авторизованный пользователь (Discover tab виден)
- Симулятор iOS 17+

## 1. Discover grid — disk cache после restart

1. Открыть Discover → коллекцию с рецептами с фото.
2. Дождаться загрузки превью в grid.
3. Force-quit приложения.
4. Запустить снова, вернуться в ту же коллекцию.
5. **Ожидание**: превью появляются сразу (disk decode), без заметной сетевой задержки.

## 2. Hero curated recipe

1. Из коллекции открыть рецепт с фото.
2. Вернуться назад, открыть снова.
3. **Ожидание**: hero без flicker; при online — фоновый conditional GET (304 если не менялось).

## 3. Public profile — другой endpoint

1. Discover → Featured chef → профиль с рецептами.
2. Открыть рецепт с фото.
3. **Ожидание**: hero грузится через `/api/recipes/{id}/image`, не `/api/discover/…`.
4. Аватар в шапке профиля — из disk cache при повторном заходе.

## 4. Личные рецепты — migration

1. (Если есть старая установка с файлами в Caches) обновить app без удаления.
2. Открыть «Мои рецепты» offline.
3. **Ожидание**: превью на месте; файлы в Application Support:

```bash
# Симулятор — подставить container UUID
ls "$(xcrun simctl get_app_container booted ru.recipescaler.RecipeScaler data)/Library/Application Support/RecipeImages/"
```

4. **Не** должно быть новых файлов публичных URL в этой папке.

## 5. Public cache path

```bash
ls "$(xcrun simctl get_app_container booted ru.recipescaler.RecipeScaler data)/Library/Caches/PublicImages/"
```

Ожидание: файлы `{64-char-hex}.webp` после просмотра Discover.

## 6. Автоматическая verify

```bash
scripts/verify-discover-public.sh
# → VERIFIED discover-public
```

## Отладка

- DEBUG log при migration: `RecipeImageDiskCache: migrated N file(s)…`
- ETag keys: `defaults read … publicImage` (UserDefaults симулятора)
- In-flight dedup: параллельный scroll grid не должен дублировать download одного URL

## Связанные документы

- [data-model.md](./data-model.md)
- [contracts/public-image-cache.md](./contracts/public-image-cache.md)
- Личный кеш: `../003-recipe-image-offline-cache/quickstart.md` (путь обновлён на Application Support)
