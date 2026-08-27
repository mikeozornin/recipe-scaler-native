#!/usr/bin/env bash
# Fixuje iOS-релиз как якорь для release notes:
#   1) annotated git tag ios/<version> на --commit (по умолчанию HEAD)
#   2) запись в store/releases.yaml
#
# Запускать ПОСЛЕ того, как сборка реально ушла/одобрена в App Store.
# Тег НЕ пушится автоматически. Повторный запуск добирает недостающую
# половину (тег без записи или запись без тега), так что сбой между
# шагами чинится просто повтором команды.
#
# Примеры:
#   bash scripts/mark-ios-release.sh 1.0.8
#   bash scripts/mark-ios-release.sh 1.0.8 --commit 04cd4458
#   bash scripts/mark-ios-release.sh 1.0.9 --notes-file store/drafts/whats-new-1.0.9.txt
#   bash scripts/mark-ios-release.sh 1.0.9 --dry-run


set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d'
  exit "${1:-0}"
}

die() { echo "mark-ios-release: $*" >&2; exit 1; }

VERSION=""
COMMIT="HEAD"
NOTES_FILE=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --commit) [[ $# -ge 2 ]] || die "--commit требует SHA"; COMMIT="$2"; shift 2 ;;
    --notes-file) [[ $# -ge 2 ]] || die "--notes-file требует путь"; NOTES_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) die "неизвестный флаг: $1 (см. --help)" ;;
    *) 
      [[ -z "$VERSION" ]] || die "версия указана дважды: '$VERSION' и '$1'"
      VERSION="$1"; shift ;;
  esac
done

[[ -n "$VERSION" ]] || usage 1
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "версия '$VERSION' не в формате X.Y.Z"
[[ "$COMMIT" != -* ]] || die "коммит '${COMMIT}' не может начинаться с '-'"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TAG="ios/${VERSION}"
RELEASES_YAML="store/releases.yaml"
YAML_TMP="$(mktemp "${TMPDIR:-/tmp}/releases.yaml.XXXXXX")"
trap 'rm -f "$YAML_TMP"' EXIT

HAS_TAG=0
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  HAS_TAG=1
fi

HAS_ENTRY=0
if grep -q "version: \"${VERSION}\"" "$RELEASES_YAML"; then
  HAS_ENTRY=1
fi

if [[ "$HAS_TAG" == "1" && "$HAS_ENTRY" == "1" ]]; then
  die "тег ${TAG} уже существует и запись ${VERSION} уже есть в ${RELEASES_YAML} — релиз уже зафиксирован?"
fi

if ! git rev-parse -q --verify "${COMMIT}^{commit}" >/dev/null; then
  die "коммит '${COMMIT}' не найден в этом репозитории"
fi

SHORT_SHA="$(git rev-parse --short "${COMMIT}")"
COMMIT_SUBJECT="$(git log -1 --format=%s "${COMMIT}")"
DATE="$(TZ=UTC date +%Y-%m-%d)"

if [[ "$HAS_ENTRY" != "1" ]]; then
  # Literal block scalar: контент с отступом 4, табы расширяются (иначе парсер падает).
  # Собираем простым присваиванием: command substitution съел бы переводы строк.
  NOTES_BLOCK=""
  if [[ -n "$NOTES_FILE" ]]; then
    [[ -f "$NOTES_FILE" ]] || die "notes-файл не найден: ${NOTES_FILE}"
    while IFS= read -r line || [[ -n "$line" ]]; do
      NOTES_BLOCK="${NOTES_BLOCK}$(sed -e 's/\t/    /g' -e 's/^/    /' <<< "$line")
"
    done < "$NOTES_FILE"
  fi

  YAML_ENTRY="$(cat <<EOF
  - version: "${VERSION}"
    tag: ${TAG}
    commit: ${SHORT_SHA}
    date: "${DATE}"
EOF
)"
  if [[ -n "$NOTES_FILE" ]]; then
    YAML_ENTRY+="
    notes: |
${NOTES_BLOCK}"
  else
    YAML_ENTRY+="
    notes: \"\""
  fi

  echo "Версия:      ${VERSION}"
  echo "Тег:         ${TAG} → ${SHORT_SHA} (${COMMIT_SUBJECT})"
  echo "Дата:        ${DATE}"
  echo "Реестр:      ${RELEASES_YAML}"
  if [[ -n "$NOTES_FILE" ]]; then echo "Notes:       ${NOTES_FILE}"; fi
else
  echo "Запись ${VERSION} уже есть в ${RELEASES_YAML}; добираю только тег."
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo
  echo "[dry-run] tag и запись в yaml не созданы."
  exit 0
fi

if [[ "$HAS_TAG" != "1" ]]; then
  git tag -a "${TAG}" -m "iOS App Store release ${VERSION}" "${COMMIT}"
fi

if [[ "$HAS_ENTRY" != "1" ]]; then
  # Атомарная запись: сперва в temp, затем mv.
  cat "$RELEASES_YAML" > "$YAML_TMP"
  printf '\n%s\n' "$YAML_ENTRY" >> "$YAML_TMP"
  mv "$YAML_TMP" "$RELEASES_YAML"
  trap - EXIT
fi

echo
echo "OK: тег ${TAG} создан, запись добавлена в ${RELEASES_YAML}."
echo "Напоминание: git push origin ${TAG}   # реестр пушится обычным коммитом"
