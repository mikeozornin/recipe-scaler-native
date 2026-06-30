# Контракт: WatchConnectivity Credentials Update (spec 041)

**Внимание**: контракт обновлён **in-place** в spec 039.

Актуальный файл: [`../../039-watchos-timers/contracts/watchconnectivity-creds.md`](../../039-watchos-timers/contracts/watchconnectivity-creds.md)

## Что добавлено в spec 041

- Поле `token` в payload (в дополнение к `userId`).
- Версионирование payload через поле `version`.
- `WatchCredentialsStore.token` на watch, `kSecAttrSynchronizable = kCFBooleanFalse`.
- Раздел "Security residual risks" — кража watch, paired backup.
- Legacy v1-payload остаётся forward-compatible.

## Причина in-place вместо нового файла

Первоначальный plan.md/tasks.md spec 041 упоминали новый файл `watchconnectivity-creds-update.md`. На ревью (L4) согласовано: обновляем существующий контракт в spec 039, stub здесь — для обратной ссылки из plan/tasks. Удалить stub можно после завершения spec 041 реализации.
