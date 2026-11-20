#!/usr/bin/env bash
# Regenerates the Hobs logo SVGs and every platform launcher icon.
# Needs rsvg-convert (librsvg) and magick (ImageMagick).
set -euo pipefail
cd "$(dirname "$0")/.."

AMBER='#FFAC02'
INK='#2C2C2A'
OUT=assets/logo

# The hob: an amber sprite with two ears and two eyes, on a 100x100 grid.
GLYPH="<g fill=\"$AMBER\" stroke=\"$AMBER\" stroke-width=\"6\" stroke-linejoin=\"round\"><polygon points=\"25,52 20,23 45,37\"/><polygon points=\"75,52 80,23 55,37\"/></g><rect x=\"22\" y=\"34\" width=\"56\" height=\"46\" rx=\"22\" fill=\"$AMBER\"/><circle cx=\"41\" cy=\"58\" r=\"4.2\" fill=\"$INK\"/><circle cx=\"59\" cy=\"58\" r=\"4.2\" fill=\"$INK\"/>"

svg() { echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">$1</svg>"; }

# Full-bleed square: iOS masks the corners itself.
svg "<rect width=\"100\" height=\"100\" fill=\"$INK\"/>$GLYPH" > $OUT/hobs-icon-square.svg
# Rounded: Android legacy launcher, README, web.
svg "<rect width=\"100\" height=\"100\" rx=\"22\" fill=\"$INK\"/>$GLYPH" > $OUT/hobs-icon.svg
# macOS: rounded tile inset on a transparent canvas (824/1024, per Apple's grid).
svg "<g transform=\"translate(9.77 9.77) scale(0.8047)\"><rect width=\"100\" height=\"100\" rx=\"22\" fill=\"$INK\"/>$GLYPH</g>" > $OUT/hobs-icon-macos.svg
# Bare glyph, no tile.
svg "$GLYPH" > $OUT/hobs-glyph.svg

render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

IOS=ios/Runner/Assets.xcassets/AppIcon.appiconset
for spec in 20:1 20:2 20:3 29:1 29:2 29:3 40:1 40:2 40:3 60:2 60:3 76:1 76:2 83.5:2 1024:1; do
  pt=${spec%:*}; scale=${spec#*:}
  px=$(awk "BEGIN{print $pt*$scale}")
  f="$IOS/Icon-App-${pt}x${pt}@${scale}x.png"
  render $OUT/hobs-icon-square.svg "$px" "$f"
  magick "$f" -background "$INK" -alpha remove -alpha off "$f"  # App Store rejects alpha
done

MAC=macos/Runner/Assets.xcassets/AppIcon.appiconset
for px in 16 32 64 128 256 512 1024; do
  render $OUT/hobs-icon-macos.svg $px "$MAC/app_icon_$px.png"
done

for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  render $OUT/hobs-icon.svg "${spec#*:}" "android/app/src/main/res/mipmap-${spec%:*}/ic_launcher.png"
done

# Splash: the bare glyph, 160pt, centered on ink by the native launch screens.
SPLASH=160
LAUNCH=ios/Runner/Assets.xcassets/LaunchImage.imageset
render $OUT/hobs-glyph.svg $SPLASH "$LAUNCH/LaunchImage.png"
render $OUT/hobs-glyph.svg $((SPLASH * 2)) "$LAUNCH/LaunchImage@2x.png"
render $OUT/hobs-glyph.svg $((SPLASH * 3)) "$LAUNCH/LaunchImage@3x.png"
for spec in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  px=$(awk "BEGIN{print $SPLASH*${spec#*:}}")
  render $OUT/hobs-glyph.svg "$px" "android/app/src/main/res/mipmap-${spec%:*}/launch_image.png"
done
