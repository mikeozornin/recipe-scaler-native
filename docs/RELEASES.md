# iOS релизы и release notes

Лёгкий workflow фиксации App Store-релизов и подготовки What's New.
Listing-тексты (description, subtitle, keywords) — git master в [`store/`](../store/) (`listing/`, `scripts/asc-pull-app-store-metadata.py`, read-only pull). Теги релизов и What's New history — без ASC API.

## Артефакты

| Артефакт | Назначение |
|----------|------------|
| git tag `ios/X.Y.Z` (annotated) | якорь «эта версия вышла в App Store» |
| [`store/`](../store/) | скриншоты, fixtures, master listing metadata из ASC (`listing/`, pull + будущий push) |
| [`store/releases.yaml`](../store/releases.yaml) | реестр релизов: version, tag, commit, date, notes |
| `store/drafts/*` | черновики digest'ов и What's New (gitignored, кроме `.gitkeep`) |
| [`scripts/mark-ios-release.sh`](../scripts/mark-ios-release.sh) | создать тег + запись реестра |
| [`scripts/collect-ios-release-changes.sh`](../scripts/collect-ios-release-changes.sh) | собрать коммиты с последнего релиза |
| [`scripts/asc-pull-app-store-metadata.py`](../scripts/asc-pull-app-store-metadata.py) | pull listing metadata из ASC в `store/` |
| `.agents/skills/prepare-ios-release/SKILL.md` | агентский skill для черновика What's New |

## Runbook

| Когда | Действие |
|-------|----------|
| Версия одобрена / ушла в App Store | `bash scripts/mark-ios-release.sh <X.Y.Z>` + `git push origin ios/<X.Y.Z>` |
| Перед Archive следующей сборки | `bash scripts/collect-ios-release-changes.sh` → черновик What's New в ASC |
| Первый раз (bootstrap) | `bash scripts/mark-ios-release.sh <X.Y.Z> --commit <sha>` (для 1.0.8 — `04cd4458`) |

### Фиксация релиза

```bash
bash scripts/mark-ios-release.sh 1.0.9 [--commit <sha>] [--notes-file <file>] [--dry-run]
```

- Создаёт annotated tag `ios/1.0.9` на `--commit` (по умолчанию HEAD).
- Дописывает запись в `store/releases.yaml`; запись атомарная (temp + mv).
- Тег **не пушится** автоматически.
- Повторный запуск безопасен: если есть только тег или только запись —
  добирает недостающую половину. Ошибка только когда зафиксировано и то и другое.
  Сбой между шагами (диск, Ctrl-C) чинится повтором команды.

### Сбор изменений

```bash
bash scripts/collect-ios-release-changes.sh \
  [--since <rev>] [--include-all] [--out store/drafts/next-release.md]
```

- Baseline — последний тег `ios/*`; можно передать любой rev явно.
- Группирует по Conventional Commits: feat / fix / perf / refactor / прочее.
- По умолчанию исключает внутренний шум (`docs`, `chore`, `build`, `ci`, `style`, `test`
  и однострочный мусор вида `review`, `Remove`) — список настраивается в шапке скрипта
  (`EXCLUDE_TYPES`, `JUNK_PATTERNS`).

## Нюанс bump-on-archive

Pre-action Archive схемы поднимает build number **до** сборки
([`scripts/bump-build-number.sh`](../scripts/bump-build-number.sh)): при `CURRENT_PROJECT_VERSION = 8`
в архив попадёт `1.0.9`. Поэтому:

- тег ставим на версию **фактически отправленную в ASC**;
- commit-якорь — коммит с зафиксированным bump (или HEAD на момент archive);
- сомневаетесь в номере — сверьтесь с Organizer/ASC (`X.Y.N` = маркетинг `X.Y`, build `N`).

## Bootstrap 2026-08-27

История до внедрения workflow: тегов нет, shipped = `1.0.8`. Якорь первого релиза —
коммит `04cd445871d3ec447d79cd5a7c5b4719d7f641f6` (последний коммит дня отправки,
2026-08-14). Зафиксирован задним числом командой:

```bash
bash scripts/mark-ios-release.sh 1.0.8 --commit 04cd445871d3ec447d79cd5a7c5b4719d7f641f6
git push origin ios/1.0.8
```

После этого `collect-ios-release-changes.sh` работает от последнего тега автоматически.
