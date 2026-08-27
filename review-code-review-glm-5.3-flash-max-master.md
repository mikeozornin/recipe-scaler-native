# Code Review: master (незакоммиченные изменения)

## Summary

Ревью dev-tooling для фиксации iOS-релизов: `scripts/mark-ios-release.sh`,
`scripts/collect-ios-release-changes.sh`, `scripts/restore-066-pbxproj.py`,
реестр `store/releases.yaml`, `docs/RELEASES.md`, правки `.gitignore`/`docs/SETUP.md`,
новые skills `.agents/skills/{fix-until-green,prepare-ios-release}/`.

Области: Business Logic, Standards — субагентами (эмпирическая проверка в temp-копии
репо, bash 3.2.57, PyYAML); Performance и Architecture — пропущены (одноразовые
локальные скрипты без горячих путей и новых модульных границ).

Security-субагент дважды упал по инфраструктурной причине («connection interrupted»);
поверхность закрыта ручной проверкой координатора: инъекция через `--commit "-x"`
нейтрализуется существующей валидацией (`git rev-parse -q --verify` молча отклоняет,
`git log`/`git tag` фейлятся громко — воспроизведено на тестовом репо); YAML-breakout
из notes-файла внутрь block scalar невозможен (sed добавляет 4-пробельный префикс
даже пустым строкам), но табы в notes ломают парсинг — вошло в фикс критического
находки №1. `restore-066-pbxproj.py` пишет файл один раз в конце (нет torn write),
константы захардкожены — untrusted input отсутствует.

Вердикт: **Changes Requested** — два критических дефекта генерации YAML срабатывают
на самом первом задокументированном запуске bootstrap.

## Findings

### Critical

1. **[business-logic] `mark-ios-release.sh`: первая строка notes приклеивается к заголовку блока `notes: |`** — файл `scripts/mark-ios-release.sh:85`. `sed 's/^/    /'` добавляет 4 пробела в том числе первой строке, поэтому `printf '\n    notes: |%s'` даёт `notes: |    Первая строка`. PyYAML: `ParserError: while scanning a block scalar`. Каждый релиз с `--notes-file` тихо пишет битый реестр (exit 0).
   Impact: инвалидация `store/releases.yaml`, обнаруживается только потребителем позже.
   Recommendation: настоящий перевод строки после `|`, расширение табуляции (табы как indentation блок-скаляра тоже валидацию ломают), плюс smoke-тест парсинга записи.
   **Статус: починено в этом коммите-цикле.**

2. **[business-logic] Аппенд под seed `releases: []` даёт невалидный YAML даже без notes** — `store/releases.yaml:9` + `scripts/mark-ios-release.sh:104`: flow-sequence значение + добавляемые block-sequence элементы `  - version:` — PyYAML падает на первой же записи. Срабатывает на документированном bootstrap `docs/RELEASES.md` (`mark-ios-release.sh 1.0.8`).
   Impact: реестр нечитаем строгими парсерами сразу после первого использования.
   Recommendation: seed как `releases:` (implicit null → первый аппенд становится легитимной block sequence).
   **Статус: починено.**

### High

3. **[business-logic] Порядок «тег → yaml» оставляет невосстановимые повтором состояния** — `scripts/mark-ios-release.sh:102-104`: при сбое между шагами повторный запуск умирает на «тег уже существует», оператор вынужден вручную удалять аннотированный тег или пропускать реестр.
   Impact: ручная починка, риск расхождения тега и реестра.
   Recommendation: resume-семантика — добирать отсутствующую половину при повторном запуске; запись YAML атомарно (temp-файл + валидация + mv).
   **Статус: починено (+ атомарная запись с валидацией перед mv).**

4. **[business-logic] `collect-ios-release-changes.sh` рендерит субъекты коммитов через `printf '%b'`** — `scripts/collect-ios-release-changes.sh:121`: backslash-escape декодируются; подтверждено на живом примере `fix: newline literal \n in subject` → буллет разрезается на две строки, `\a` даёт BEL-байт; в markdown-черновик для App Store Connect попадает мусор. COUNT (строки) расходится с TOTAL (коммиты).
   Impact: тихая порча артефакта What's New.
   Recommendation: заменить все `\n`-литералы на реальные переводы строк и печатать `%s`.
   **Статус: починено.**

### Medium

5. **[business-logic] `restore-066-pbxproj.py`: `add_deep_link_url()` применяет правки непроверенными `str.replace()`** — стухший якорь тихо пропускается (half-applied результат — битый проект позже в Xcode), в отличие от цикла `CONFIG_LISTS`, который правильно делает `SystemExit`; guard идемпотентности считает «готово» любую подстроку `DeepLinkURL.swift`. Extraction терминация `extract_config_block()` зависит от точной косметики pbxproj — дрейф формата возможен в тихое переизвлечение соседних секций. Сейчас якоря совпадают (проверено), путь латентный. Recommendation: assert count==1 на каждый якорь, валидация извлечённого блока. Не чинилось (out of scope critical+high), оставить на будущее — скрипт однократный.
6. **[standards] `.gitignore` игнорирует `store/drafts/*.md`, а workflow пишет туда же `whats-new-*.txt`** — черновики notes уйдут в git незамеченными. Recommendation: правило каталога `store/drafts/*` c exception для `.gitkeep`.
7. **[security/manual] Харденинг `--commit`**: значения с ведущим `-` безопасны сегодня только благодаря каскаду валидации; явный guard `[[ "$COMMIT" != -* ]] || die` сделал бы это независимым от поведения git. Не чинилось (out of scope).

### Low

8. **[standards]** `usage()` обоих скриптов читает собственную шапку по числовым диапазонам sed — правка шапки сдвигает окно незаметно. (Починено попутно, чтобы пережить изменения шапки в фиксе №1–4: маркерная выборка до первой пустой строки.)
9. **[business-logic]** Отсутствующий/пустой `Config/Version.xcconfig`: полное прерывание сбора сырым sed-ошибкой либо заголовок `версия: .9`. Версия информационная — деградировать к `<unknown>`.
10. **[standards]** `docs/RELEASES.md` отсутствует в таблице маршрутизации AGENTS.md; опечатка `( ru` в триггере skill prepare-ios-release. Документация RELEASES.md обновлена в рамках фиксов (resume-семантика), пункт таблицы AGENTS.md — вне scope.

## Verified non-issues (эмпирически)

- `--sort=-v:refname` верно выбирает последний тег и для `1.0.10 > 1.0.9`;
- quoted-grep версии не ловится префиксными версиями (`1.0.1` vs `1.0.10`);
- классификация Conventional Commits (feat/fix/perf/refactor/excluded/junk/breaking `feat!:`) корректна на пытках из 12 коммитов;
- bash 3.2-совместимость подтверждена прогоном на 3.2.57 (`$'\n'`, process substitution, printf);
- dry-run не имеет побочных эффектов; md-links в доках валидны; exec bits консистентны с папкой scripts/;
- restore-066 идемпотентен на текущем pbxproj (27 occurrences DebugDevice → skip branch).

## Recommendation

**Changes Requested** — находки 1–4 (critical/high) исправлены в рабочем дереве,
верифицированы прогоном в temp-копии репозитория; пункты 5–7 зафиксированы как
осознанно отложенные, 10 — как мелкие улучшения вне текущего scope.
