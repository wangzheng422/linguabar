#!/bin/zsh
set -euo pipefail

# Rebuild standard macOS icon representations from the transparent master.
script_dir="${0:A:h}"
project_root="${script_dir:h}"
cd "${project_root}"
for icon_size in 16 32 128 256 512; do
  sips -z "$icon_size" "$icon_size" Resources/AppIcon.png \
    --out "Resources/AppIcon.iconset/icon_${icon_size}x${icon_size}.png"
  retina_size=$((icon_size * 2))
  sips -z "$retina_size" "$retina_size" Resources/AppIcon.png \
    --out "Resources/AppIcon.iconset/icon_${icon_size}x${icon_size}@2x.png"
done
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
sips -g hasAlpha -g pixelWidth -g pixelHeight Resources/AppIcon.png
