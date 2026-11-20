#!/usr/bin/env bash
# Regenerates the Hobs logo SVGs and every platform launcher icon.
# Needs rsvg-convert (librsvg) and magick (ImageMagick).
set -euo pipefail
cd "$(dirname "$0")/.."

AMBER='#FFAC02'      # the cap
AMBER_DARK='#D88F00' # the cap's brim
CREAM='#FBEBC8'      # the pompom
SKIN='#F2C98A'       # face and ears
INK='#2C2C2A'        # eyes
MOSS='#2F6B4A'       # the tile and splash background, the app's primary color
OUT=assets/logo

# The hob: a little elf in a pointed cap with a bent tip, pointed ears and two
# eyes, on a 100x100 grid. Keep in sync with HobGlyphPainter in
# lib/ui/splash_screen.dart.
GLYPH="<path d=\"M22 66 L8 54 L30 60 Z\" fill=\"$SKIN\"/><path d=\"M78 66 L92 54 L70 60 Z\" fill=\"$SKIN\"/><circle cx=\"50\" cy=\"66\" r=\"22\" fill=\"$SKIN\"/><path d=\"M22 58 C26 36 40 20 56 14 C68 10 80 16 84 26 C76 22 68 24 64 32 C70 40 76 50 78 58 Z\" fill=\"$AMBER\"/><circle cx=\"84\" cy=\"27\" r=\"5\" fill=\"$CREAM\"/><rect x=\"20\" y=\"52\" width=\"60\" height=\"11\" rx=\"5.5\" fill=\"$AMBER_DARK\"/><circle cx=\"42\" cy=\"71\" r=\"3.8\" fill=\"$INK\"/><circle cx=\"58\" cy=\"71\" r=\"3.8\" fill=\"$INK\"/>"

svg() { echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">$1</svg>"; }

# Full-bleed square: iOS masks the corners itself.
svg "<rect width=\"100\" height=\"100\" fill=\"$MOSS\"/>$GLYPH" > $OUT/hobs-icon-square.svg
# Rounded: Android legacy launcher, README, web.
svg "<rect width=\"100\" height=\"100\" rx=\"22\" fill=\"$MOSS\"/>$GLYPH" > $OUT/hobs-icon.svg
# macOS: rounded tile inset on a transparent canvas (824/1024, per Apple's grid).
svg "<g transform=\"translate(9.77 9.77) scale(0.8047)\"><rect width=\"100\" height=\"100\" rx=\"22\" fill=\"$MOSS\"/>$GLYPH</g>" > $OUT/hobs-icon-macos.svg
# Bare glyph, no tile.
svg "$GLYPH" > $OUT/hobs-glyph.svg

render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

IOS=ios/Runner/Assets.xcassets/AppIcon.appiconset
for spec in 20:1 20:2 20:3 29:1 29:2 29:3 40:1 40:2 40:3 60:2 60:3 76:1 76:2 83.5:2 1024:1; do
  pt=${spec%:*}; scale=${spec#*:}
  px=$(awk "BEGIN{print $pt*$scale}")
  f="$IOS/Icon-App-${pt}x${pt}@${scale}x.png"
  render $OUT/hobs-icon-square.svg "$px" "$f"
  magick "$f" -background "$MOSS" -alpha remove -alpha off "$f"  # App Store rejects alpha
done

MAC=macos/Runner/Assets.xcassets/AppIcon.appiconset
for px in 16 32 64 128 256 512 1024; do
  render $OUT/hobs-icon-macos.svg $px "$MAC/app_icon_$px.png"
done

for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  render $OUT/hobs-icon.svg "${spec#*:}" "android/app/src/main/res/mipmap-${spec%:*}/ic_launcher.png"
done

# Splash: the bare glyph, 160pt, centered on moss by the native launch screens.
SPLASH=160
LAUNCH=ios/Runner/Assets.xcassets/LaunchImage.imageset
render $OUT/hobs-glyph.svg $SPLASH "$LAUNCH/LaunchImage.png"
render $OUT/hobs-glyph.svg $((SPLASH * 2)) "$LAUNCH/LaunchImage@2x.png"
render $OUT/hobs-glyph.svg $((SPLASH * 3)) "$LAUNCH/LaunchImage@3x.png"
for spec in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  px=$(awk "BEGIN{print $SPLASH*${spec#*:}}")
  render $OUT/hobs-glyph.svg "$px" "android/app/src/main/res/mipmap-${spec%:*}/launch_image.png"
done
