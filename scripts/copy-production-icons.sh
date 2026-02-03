#!/usr/bin/env bash
# Копирует production-иконки из tmp/icons/production (в корне репозитория) в AppIcon.appiconset.
# Если в папке только apple-touch-icon-1024.png — из него генерируются все размеры через sips.
# Иначе ожидаются файлы icon-20x20@2x.png, icon-1024x1024.png и т.д.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."
SRC="${1:-$REPO_ROOT/tmp/icons/production}"
APPSET="$SCRIPT_DIR/../RecipeScalerNative/Assets.xcassets/AppIcon.appiconset"

if [[ ! -d "$SRC" ]]; then
  echo "Папка не найдена: $SRC"
  echo "Использование: $0 [путь_к_иконкам]"
  echo "По умолчанию: tmp/icons/production (от корня репозитория)"
  exit 1
fi

# Список: имя_файла размер_в_пикселях
ICONS="icon-20x20@1x.png 20
icon-20x20@2x.png 40
icon-20x20@3x.png 60
icon-29x29@1x.png 29
icon-29x29@2x.png 58
icon-29x29@3x.png 87
icon-40x40@1x.png 40
icon-40x40@2x.png 80
icon-40x40@3x.png 120
icon-60x60@2x.png 120
icon-60x60@3x.png 180
icon-76x76@1x.png 76
icon-76x76@2x.png 152
icon-83.5x83.5@2x.png 167
icon-1024x1024.png 1024"

SOURCE_1024=""
for name in apple-touch-icon-1024.png icon-1024x1024.png; do
  if [[ -f "$SRC/$name" ]]; then
    SOURCE_1024="$SRC/$name"
    break
  fi
done

if [[ -n "$SOURCE_1024" ]]; then
  echo "Генерация размеров из $(basename "$SOURCE_1024")..."
  while read -r f size; do
    sips -z "$size" "$size" "$SOURCE_1024" --out "$APPSET/$f"
    echo "  $f (${size}x${size})"
  done <<< "$ICONS"
else
  echo "Копирование готовых иконок из $SRC..."
  MISSING=""
  while read -r f _; do
    if [[ -f "$SRC/$f" ]]; then
      cp -v "$SRC/$f" "$APPSET/$f"
    else
      MISSING="$MISSING $f"
    fi
  done <<< "$ICONS"
  if [[ -n "$MISSING" ]]; then
    echo "Нет в источнике:$MISSING"
    echo "Положи apple-touch-icon-1024.png в $SRC — скрипт сгенерирует все размеры."
    exit 1
  fi
fi

echo "Готово: production-иконки установлены в AppIcon.appiconset"
