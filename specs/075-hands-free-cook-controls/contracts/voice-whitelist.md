# Contract: voice whitelist

**Owner**: `AwakeScrollVoiceClassifier`  
**Input**: final (или stable partial) transcript, locale hint не обязателен — один набор RU+EN.

## Нормализация

1. Trim.
2. Lowercase (`Locale.identity` / `en` folding достаточно; ё → е не обязателен в v1, но «вверх» без ё).
3. Сжать внутренние пробелы до одного.
4. Убрать wrapping punctuation `.!?…`.

Prefix / contains match **запрещён** (кроме явных фраз из таблицы, совпадающих целиком).

## `.up` (exact after normalize)

- `вверх`
- `выше`
- `наверх`
- `прокрути вверх`
- `up`
- `scroll up`

`top` **не** в v1 (коллизия с «stop» / «toppings» / «stop it»).

## `.down`

- `вниз`
- `ниже`
- `прокрути вниз`
- `down`
- `scroll down`

## Игнор (примеры для тестов)

`стоп`, `stop`, `следующий`, `next`, `list`, `top`, пустая строка, `вверх пожалуйста` (лишние слова → nil).

## Fire policy

- Partial: не fire.
- Stable partial: опционально ≥ 300 ms одинакового текста — только если текст **уже** exact whitelist (не «вве»).
- После fire — общий cooldown сессии.

## Логи

Английский `AppLog`; не логировать полный сырой transcript в release, если политика privacy ужесточится — в v1 debug-only.
