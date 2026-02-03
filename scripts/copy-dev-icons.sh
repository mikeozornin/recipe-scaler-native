#!/usr/bin/env bash
# Копирует иконки из /tmp/icons в AppIcon-Dev.appiconset.
# Имена файлов должны совпадать с AppIcon (icon-20x20@2x.png, icon-1024x1024.png и т.д.).
set -e
SRC="${1:-/tmp/icons}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPSET="$SCRIPT_DIR/../RecipeScalerNative/Assets.xcassets/AppIcon-Dev.appiconset"
if [[ ! -d "$SRC" ]]; then
  echo "Папка не найдена: $SRC"
  echo "Использование: $0 [путь_к_иконкам]"
  exit 1
fi
cp -v "$SRC"/*.png "$APPSET/"
echo "Готово: иконки скопированы в AppIcon-Dev.appiconset"
