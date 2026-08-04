# Account List: эксперимент с отступами секций (2026-08-04)

**Статус:** отклонено, код откатан к `.listSectionSpacing(12)`.

Связанные экраны: `AccountView`, `AccountProfileEditView` (`insetGrouped` List).

## Предложение

Унифицировать серый зазор между соседними секциями до **~30 pt**, измеряя:

- снизу от **footer** верхней секции (или от низа карточки, если footer нет);
- сверху до **заголовка** нижней (или до верха карточки, если заголовка нет).

Дополнения к базовому 30:

| Случай | Идея |
|---|---|
| Нижняя секция с `AppSectionHeader` | Компенсировать top-inset слота заголовка ~**6 pt** (`(28 − 15.6) / 2`) — spacing 24 или `padding.top(-6)` на тексте, чтобы глифы тоже сидели ~30 pt ниже предыдущего блока |
| Оффлайн-баннер (первая секция) | Над карточкой половина стандарта: **15 pt** |
| Footer | Тоже посчитать inset «глиф ↔ блок» (см. замеры ниже) |

Не выравнивать зазоры невидимым `AppSectionHeaderSpacer` «ради ритма» и не оставлять пустые `Section` / `Group` в List.

## Что проверили (симулятор, AX + пиксели)

| Finding | Detail |
|---|---|
| `listSectionSpacing(30)` честен на headerless | Пары card→card и footer→card дают **ровно 30** |
| Заголовок *добавляется* к spacing | Card → header.top = 30, высота header ≈ 30, header.bot вплотную к следующей карточке → **card→card ≈ 60**. Визуально «огромный» зазор над titled-секциями (пример: Данные → Опасная зона) |
| Footer асимметричен | Footnote footer: ~**10 pt** card→верх глифов, ~**6 pt** низ глифов→низ frame. От низа глифов до следующей секции ≈ spacing + 6 |
| Per-section 24 vs 30 не работает | Соседние `listSectionSpacing` **смешиваются (~среднее)** → ~27 pt; 24 на titled-секции ужимает и зазор *после* неё |
| Spacer + большой spacing | Невидимый header-слот + `listSectionSpacing(30)` раздувает пустоту; пустая/`Group` Section всё равно резервирует chrome |
| Offline top inset | Clear `Section` header перелетает цель; `contentMargins` под large title **аддитивен** (~9 system + margin) |

## Решение

Оставить дефолт профиля: `.listSectionSpacing(12)`, `AppSectionHeader` / `AppSectionHeaderSpacer` как раньше. Кастомные 30 / компенсацию глифов / offline `contentMargins` не шипить.

Имеет смысл возвращаться только с другой моделью (например near-zero spacing + ритм за счёт header, или явное принятие card→card ≠ константа).

## Код после отката

- `AccountView` / `AccountProfileEditView`: `.listSectionSpacing(12)`
- Нет `AppListMetrics`
- `AppSectionHeader` без отрицательного `padding.top`
