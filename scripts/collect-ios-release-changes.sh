#!/usr/bin/env bash
# Собирает коммиты с последнего iOS-релиза (git tag ios/*) до HEAD —
# сырьё для What's New в App Store Connect и internal digest.
# Совместимо с системным bash 3.2 (macOS).
#
# Примеры:
#   bash scripts/collect-ios-release-changes.sh
#   bash scripts/collect-ios-release-changes.sh --since ios/1.0.8
#   bash scripts/collect-ios-release-changes.sh --include-all
#   bash scripts/collect-ios-release-changes.sh --out store/drafts/next-release.md

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d'
  exit "${1:-0}"
}

# Настраиваемый список игнора по типу Conventional Commits (internal noise).
EXCLUDE_TYPES="docs chore build ci style test"

# Сабжекты без conventional-типа, являющиеся служебным мусором.
JUNK_PATTERNS='^(review|Remove( .*)?|wip|WIP|bump.*|Merge .*)$'

SINCE=""
INCLUDE_ALL=0
OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --since) [ $# -ge 2 ] || { echo "--since требует rev" >&2; exit 1; }; SINCE="$2"; shift 2 ;;
    --include-all) INCLUDE_ALL=1; shift ;;
    --out) [ $# -ge 2 ] || { echo "--out требует путь" >&2; exit 1; }; OUT="$2"; shift 2 ;;
    *) echo "неизвестный аргумент: $1 (см. --help)" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LAST_TAG="$(git tag -l 'ios/*' --sort=-v:refname | head -1)"

if [ -z "$SINCE" ]; then
  if [ -z "$LAST_TAG" ]; then
    echo "Нет тегов ios/*. Сначала зафиксируйте baseline:" >&2
    echo "  bash scripts/mark-ios-release.sh <X.Y.Z> [--commit <sha>]" >&2
    exit 1
  fi
  SINCE="$LAST_TAG"
fi

if ! git rev-parse -q --verify "${SINCE}^{commit}" >/dev/null; then
  echo "baseline '${SINCE}' не найден в этом репозитории" >&2
  exit 1
fi

[ -f Config/Version.xcconfig ] || echo "warn: Config/Version.xcconfig не найден — версия в заголовке будет неполной" >&2
MARKETING="$(sed -n 's/^MARKETING_VERSION = //p' Config/Version.xcconfig 2>/dev/null | tr -d '[:space:]')"
CURRENT="$(sed -n 's/^CURRENT_PROJECT_VERSION = //p' Config/Version.xcconfig 2>/dev/null | tr -d '[:space:]')"
[ -n "$MARKETING" ] || MARKETING="<unknown>"
[ -n "$CURRENT" ] || CURRENT="<unknown>"

FEAT=""
FIX=""
PERF=""
REFACTOR=""
OTHER=""
EXCLUDED=""
TOTAL=0

CONVENTIONAL_RE='^([a-zA-Z]+)(\([^)]*\))?(!)?:[[:space:]]*(.+)$'

is_excluded_type() {
  [ "$INCLUDE_ALL" = "1" ] && return 1
  case " $EXCLUDE_TYPES " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

classify() {
  s="$1"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$s" | grep -Eq "$CONVENTIONAL_RE"; then
    t="$(printf '%s' "$s" | sed -E 's/^([a-zA-Z]+)(\([^)]*\))?(!)?:.*$/\1/' | tr '[:upper:]' '[:lower:]')"
    if is_excluded_type "$t"; then
      EXCLUDED="${EXCLUDED}${EXCLUDED:+$'\n'}${s}"
      return
    fi
    case "$t" in
      feat) FEAT="${FEAT}${FEAT:+$'\n'}${s}" ;;
      fix) FIX="${FIX}${FIX:+$'\n'}${s}" ;;
      perf) PERF="${PERF}${PERF:+$'\n'}${s}" ;;
      refactor) REFACTOR="${REFACTOR}${REFACTOR:+$'\n'}${s}" ;;
      *) OTHER="${OTHER}${OTHER:+$'\n'}${s}" ;;
    esac
    return
  fi
  if printf '%s' "$s" | grep -Eqi "$JUNK_PATTERNS"; then
    EXCLUDED="${EXCLUDED}${EXCLUDED:+$'\n'}${s}"
    return
  fi
  OTHER="${OTHER}${OTHER:+$'\n'}${s}"
}

while IFS= read -r line; do
  [ -z "$line" ] && continue
  classify "$line"
done < <(git log "${SINCE}..HEAD" --no-merges --format=%s)

render_group() {
  title="$1"
  list="${2:-}"
  out="$3"
  [ -z "$list" ] && { printf '%s' "$out"; return; }
  body="
## ${title}

"
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    body="${body}- ${item}
"
  done <<EOF_LIST
$list
EOF_LIST
  printf '%s%s' "$out" "$body"
}

OUT_BODY="# Изменения с ${SINCE} → HEAD
Текущая версия xcconfig: ${MARKETING}.${CURRENT}   |   Коммитов в диапазоне: ${TOTAL}
"

OUT_BODY=$(render_group "Новое (feat)" "$FEAT" "$OUT_BODY")
OUT_BODY=$(render_group "Исправления (fix)" "$FIX" "$OUT_BODY")
OUT_BODY=$(render_group "Производительность (perf)" "$PERF" "$OUT_BODY")
OUT_BODY=$(render_group "Рефакторинг (refactor)" "$REFACTOR" "$OUT_BODY")
if [ "$INCLUDE_ALL" = "1" ]; then
  OUT_BODY=$(render_group "Прочее (прочие типы)" "$OTHER" "$OUT_BODY")
else
  OUT_BODY=$(render_group "Прочее (без типа/нестандартное)" "$OTHER" "$OUT_BODY")
fi
OUT_BODY=$(render_group "Исключено (internal noise)" "$EXCLUDED" "$OUT_BODY")

count_lines() {
  list="${1:-}"
  [ -z "$list" ] && { echo 0; return; }
  printf '%s\n' "$list" | grep -c .
}

COUNT=$(( $(count_lines "$FEAT") + $(count_lines "$FIX") + $(count_lines "$PERF") \
  + $(count_lines "$REFACTOR") + $(count_lines "$OTHER") ))

if [ -n "$OUT" ]; then
  mkdir -p "$(dirname "$OUT")"
  printf '%s\n' "$OUT_BODY" > "$OUT"
  echo "Черновик: ${OUT}"
fi

printf '%s\n' "$OUT_BODY"

if [ "$COUNT" -eq 0 ]; then
  echo
  echo "Пользовательских изменений нет с ${SINCE} — новый App Store билд, скорее всего, не нужен."
fi
