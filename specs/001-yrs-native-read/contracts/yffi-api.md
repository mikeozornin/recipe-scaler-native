# yrs C API Contract

**Date**: 2026-06-01
**Reference**: [y-crdt/yffi](https://github.com/y-crdt/y-crdt/blob/main/yffi) — `libyrs.h`

## Scope

Только функции, необходимые для Phase 2 (read-only Y.Doc access). Мутации будут добавлены в Phase 3.

## Required Functions

### Document Lifecycle

| Function | Signature | Phase 2 Usage |
|----------|-----------|---------------|
| `ydoc_new` | `YDoc *ydoc_new(void)` | Создание нового Y.Doc для collection/recipe |
| `ydoc_new_with_options` | `YDoc *ydoc_new_with_options(YOptions)` | Создание с custom client ID (опционально) |
| `ydoc_destroy` | `void ydoc_destroy(YDoc *)` | Освобождение ресурсов документа |
| `ydoc_id` | `uint64_t ydoc_id(YDoc *)` | Получение client ID документа |

### Transactions

| Function | Signature | Phase 2 Usage |
|----------|-----------|---------------|
| `ydoc_read_transaction` | `YTransaction *ydoc_read_transaction(YDoc *)` | Все операции чтения |
| `ytransaction_commit` | `void ytransaction_commit(YTransaction *)` | Завершение read transaction |

### Shared Type Accessors

| Function | Signature | Phase 2 Usage |
|----------|-----------|---------------|
| `yarray` | `Branch *yarray(YDoc *, const char *name)` | Доступ к `Y.Array('recipes')` в collection |
| `ymap` | `Branch *ymap(YDoc *, const char *name)` | Доступ к `Y.Map('recipe')` в recipe doc |
| `yxmlfragment` | `Branch *yxmlfragment(YDoc *, const char *)` | Доступ к v3 description (Phase 2: skip) |

### Y.Map Read

| Function | Signature | Phase 2 Usage |
|----------|-----------|---------------|
| `ymap_len` | `uint32_t ymap_len(const Branch *, const YTransaction *)` | Проверка количества записей |
| `ymap_get` | `YOutput *ymap_get(const Branch *, const YTransaction *, const char *)` | Чтение значения по ключу |
| `ymap_iter` | `YMapIter *ymap_iter(const Branch *, const YTransaction *)` | Итерация по всем записям |
| `ymap_iter_next` | `YMapEntry *ymap_iter_next(YMapIter *)` | Следующая запись |
| `ymap_iter_destroy` | `void ymap_iter_destroy(YMapIter *)` | Освобождение итератора |

### Y.Array Read

| Function | Signature | Phase 2 Usage |
|----------|-----------|---------------|
| `yarray_len` | `uint32_t yarray_len(const Branch *)` | Количество элементов |
| `yarray_get` | `YOutput *yarray_get(const Branch *, const YTransaction *, uint32_t)` | Элемент по индексу |
| `yarray_iter` | `YArrayIter *yarray_iter(const Branch *, YTransaction *)` | Итератор |
| `yarray_iter_next` | `YOutput *yarray_iter_next(YArrayIter *)` | Следующий элемент |
| `yarray_iter_destroy` | `void yarray_iter_destroy(YArrayIter *)` | Освобождение итератора |

### Y.Text Read

| Function | Signature | Phase 2 Usage |
|----------|-----------|---------------|
| `ytext_string` | `char *ytext_string(const Branch *, const YTransaction *)` | v2 description как текст |

### Value Decoding (YOutput → Swift)

| Function | Signature | Returns |
|----------|-----------|---------|
| `youtput_read_string` | `char *youtput_read_string(const YOutput *)` | String (or NULL) |
| `youtput_read_bool` | `const uint8_t *youtput_read_bool(const YOutput *)` | Boolean pointer |
| `youtput_read_float` | `const double *youtput_read_float(const YOutput *)` | Double pointer |
| `youtput_read_long` | `const int64_t *youtput_read_long(const YOutput *)` | Int64 pointer |
| `youtput_read_yarray` | `Branch *youtput_read_yarray(const YOutput *)` | Nested Y.Array |
| `youtput_read_ymap` | `Branch *youtput_read_ymap(const YOutput *)` | Nested Y.Map |
| `youtput_read_ytext` | `Branch *youtput_read_ytext(const YOutput *)` | Nested Y.Text |
| `youtput_destroy` | `void youtput_destroy(YOutput *)` | Free output |

### Binary Sync

| Function | Signature | Phase 2 Usage |
|----------|-----------|---------------|
| `ytransaction_apply` | `uint8_t ytransaction_apply(YTransaction *, const char *, uint32_t)` | Применение обновления от сервера |
| `ytransaction_state_vector_v1` | `char *ytransaction_state_vector_v1(const YTransaction *, uint32_t *)` | Получение state vector |
| `ytransaction_state_diff_v1` | `char *ytransaction_state_diff_v1(const YTransaction *, const char *, uint32_t, uint32_t *)` | Diff since state vector |

### Observers

| Function | Signature | Phase 2 Usage |
|----------|-----------|---------------|
| `yobserve_deep` | `YSubscription *yobserve_deep(Branch *, void *, void (*)(void*, ...))` | Глубокий наблюдатель для реактивности |
| `ydoc_observe_updates_v1` | `YSubscription *ydoc_observe_updates_v1(YDoc *, void *, void (*)(...))` | Наблюдение за обновлениями документа |
| `yunobserve` | `void yunobserve(YSubscription *)` | Отписка |

### Cleanup

| Function | Phase 2 Usage |
|----------|---------------|
| `ystring_destroy` | Освобождение строк, возвращённых из yrs |
| `ybinary_destroy` | Освобождение бинарных данных |
| `youtput_destroy` | Освобождение YOutput |
| `ymap_entry_destroy` | Освобождение YMapEntry |

## Type Tags (YOutput.tag)

| Constant | Value | Meaning |
|----------|-------|---------|
| `Y_ARRAY` | 1 | Nested Y.Array |
| `Y_MAP` | 2 | Nested Y.Map |
| `Y_TEXT` | 3 | Nested Y.Text |
| `Y_XML_ELEMENT` | 4 | XmlElement |
| `Y_XML_TEXT` | 5 | XmlText |
| `Y_JSON_STR` | -5 | JSON string value |
| `Y_JSON_NUM` | -7 | JSON number value |
| `Y_JSON_BOOL` | -8 | JSON boolean value |
| `Y_JSON_INT` | -6 | JSON integer value |
| `Y_JSON_NULL` | -9 | JSON null |

## Error Handling Contract

| C Return | Meaning | Swift Action |
|----------|---------|-------------|
| `NULL` pointer | Operation failed or value not found | Return nil / throw YrsError.nullPointer |
| `0` return from `ytransaction_apply` | Success | Continue |
| Non-zero return from `ytransaction_apply` | Failure | Log error, re-fetch document from server |

## Memory Ownership Rules

1. **Strings**: `youtput_read_string`, `ytext_string` → caller must `ystring_destroy`
2. **Binary**: `ytransaction_state_vector_v1`, `ytransaction_state_diff_v1` → caller must `ybinary_destroy`
3. **YOutput**: `ymap_get`, `yarray_get` → caller must `youtput_destroy`
4. **YMapEntry**: `ymap_iter_next` → caller must `ymap_entry_destroy`
5. **Iterators**: `ymap_iter`, `yarray_iter` → caller must destroy via respective destroy function
6. **Documents**: `ydoc_new` → caller must `ydoc_destroy`
7. **Subscriptions**: `yobserve_deep` → caller must `yunobserve`

## Not In Scope (Phase 3+)

- `ymap_set`, `yarray_insert`, `yarray_push` — write mutations
- `ydoc_write_transaction` — write transactions
- `ytransaction_merge_updates_v1` — merge debounced updates
- XmlFragment write operations
