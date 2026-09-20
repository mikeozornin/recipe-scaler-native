# Contract: voice whitelist

**Owner**: `AwakeScrollVoiceClassifier`  
**Input**: final (или stable partial) transcript. Classifier — один набор RU+EN. Локаль STT — язык приложения (`en_US` / `ru_RU`), иначе английские чипы на экране не распознаются.

## Нормализация

1. Trim.
2. Lowercase (`Locale.identity` / `en` folding достаточно; ё → е не обязателен в v1, но «вверх» без ё).
3. Сжать внутренние пробелы до одного.
4. Убрать wrapping punctuation `.!?…`.

Prefix / contains match **запрещён**, кроме:

- хвоста из 2–3 токенов, целиком совпадающего с фразой таблицы (`scroll down`, `прокрути вниз`) — continuous STT копит слова в одной сессии;
- последнего токена из однозначных RU/EN-синонимов: `вверх` / `выше` / `наверх` / `вниз` / `ниже` / `higher` / `lower`.

Английские `up` / `down` — **только** вся фраза целиком (`calm down`, `hands up` → nil).

## `.up` (exact after normalize)

- `вверх`
- `выше`
- `наверх`
- `прокрути вверх`
- `up`
- `higher`
- `scroll up`

`top` **не** в v1 (коллизия с «stop» / «toppings» / «stop it»).

## `.down`

- `вниз`
- `ниже`
- `прокрути вниз`
- `down`
- `lower`
- `scroll down`

## Игнор (примеры для тестов)

`стоп`, `stop`, `следующий`, `next`, `list`, `top`, пустая строка, `вверх пожалуйста` (лишние слова → nil).

## Fire policy

- RU singleton и фразы из 2+ слов: fire на первом matching partial (слово уже полное).
- English `up` / `down` целиком: Partial не fire; stable partial ≥ 300 ms или final (иначе префикс `update` → `up`).
- После fire — общий cooldown сессии; повтор той же команды в continuous-транскрипте — когда число токенов выросло.

## Логи

Английский `AppLog`; не логировать полный сырой transcript в release, если политика privacy ужесточится — в v1 debug-only.
