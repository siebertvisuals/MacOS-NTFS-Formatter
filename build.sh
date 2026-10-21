#!/bin/bash
# Construit NTFSFormatter.app, AUTONOME (mkntfs embarqué), et NTFSFormatter.zip à distribuer.
# Réservé au mainteneur : il faut les outils Xcode et Homebrew + `brew install ntfs-3g-mac`.
# Les utilisateurs finaux n'ont rien à installer : ils téléchargent le .zip.
set -euo pipefail
cd "$(dirname "$0")"

BREW="$(command -v brew || echo /opt/homebrew/bin/brew)"
NTFS="$("$BREW" --prefix ntfs-3g-mac)"
GETTEXT="$("$BREW" --prefix gettext)"
[ -x "$NTFS/sbin/mkntfs" ] || { echo "mkntfs introuvable : brew install ntfs-3g-mac" >&2; exit 1; }

APP="NTFSFormatter.app"
RES="$APP/Contents/Resources"
rm -rf "$APP" NTFSFormatter.zip
mkdir -p "$APP/Contents/MacOS" "$RES/ntfs/bin" "$RES/ntfs/lib" "$RES/licenses"

swiftc -O -parse-as-library NTFSFormatter.swift -o "$APP/Contents/MacOS/NTFSFormatter"

# --- mkntfs + bibliothèques, rendus relocalisables -------------------------------
cp "$NTFS/sbin/mkntfs"                         "$RES/ntfs/bin/mkntfs"
cp "$NTFS/lib/libntfs-3g.91.dylib"             "$RES/ntfs/lib/"
cp "$GETTEXT/lib/libintl.8.dylib"              "$RES/ntfs/lib/"
chmod u+w "$RES/ntfs/bin/mkntfs" "$RES/ntfs/lib/"*.dylib

install_name_tool \
  -change "$(otool -L "$RES/ntfs/bin/mkntfs" | awk '/libntfs-3g/{print $1}')" "@executable_path/../lib/libntfs-3g.91.dylib" \
  -change "$(otool -L "$RES/ntfs/bin/mkntfs" | awk '/libintl/{print $1}')"    "@executable_path/../lib/libintl.8.dylib" \
  "$RES/ntfs/bin/mkntfs"
install_name_tool -id "@loader_path/libntfs-3g.91.dylib" "$RES/ntfs/lib/libntfs-3g.91.dylib"
install_name_tool -change "$(otool -L "$RES/ntfs/lib/libntfs-3g.91.dylib" | awk '/libintl/{print $1}')" \
  "@loader_path/libintl.8.dylib" "$RES/ntfs/lib/libntfs-3g.91.dylib"
install_name_tool -id "@loader_path/libintl.8.dylib" "$RES/ntfs/lib/libintl.8.dylib"

# Plus aucune dépendance Homebrew ne doit rester
if otool -L "$RES/ntfs/bin/mkntfs" "$RES/ntfs/lib/"*.dylib | grep -q -E "/opt/homebrew|/usr/local"; then
  echo "Dépendance Homebrew restante :" >&2
  otool -L "$RES/ntfs/bin/mkntfs" "$RES/ntfs/lib/"*.dylib | grep -E "/opt/homebrew|/usr/local" >&2
  exit 1
fi

# --- licences (GPL : à livrer avec le binaire) -----------------------------------------
cp "$NTFS/COPYING" "$RES/licenses/ntfs-3g-COPYING-GPLv2.txt"
cp "$GETTEXT/COPYING" "$RES/licenses/gettext-libintl-COPYING.txt" 2>/dev/null || true
cat > "$RES/licenses/LISEZMOI.txt" <<'TXT'
Cette application embarque « mkntfs » et « libntfs-3g » (projet NTFS-3G, licence GPL v2)
ainsi que « libintl » (GNU gettext, licence LGPL).
Le code source de NTFS-3G est disponible sur https://github.com/tuxera/ntfs-3g
et sur https://github.com/gromgit/homebrew-fuse (recette utilisée pour ce binaire).
TXT

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>NTFSFormatter</string>
  <key>CFBundleDisplayName</key><string>NTFS Formatter</string>
  <key>CFBundleIdentifier</key><string>io.github.ntfsformatter</string>
  <key>CFBundleExecutable</key><string>NTFSFormatter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

xattr -cr "$APP"
# Signature « ad hoc » (obligatoire sur Apple Silicon, pas une notarisation Apple)
for f in "$RES/ntfs/lib/"*.dylib "$RES/ntfs/bin/mkntfs" "$APP"; do codesign --force --sign - "$f"; done
codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent "$APP" NTFSFormatter.zip
echo "OK : $APP et NTFSFormatter.zip ($(du -h NTFSFormatter.zip | cut -f1)) — architecture : $(lipo -archs "$RES/ntfs/bin/mkntfs")"
