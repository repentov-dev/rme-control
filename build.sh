#!/bin/bash
# Сборка RME Control без Xcode — нужны только Xcode Command Line Tools.
#   ./build.sh          — собрать build/Release/RME Control.app (Apple Silicon + Intel)
#   ./build.sh --zip    — то же + архив build/RME-Control-<версия>.zip, чтобы отправить другому
#   ./build.sh --install — то же + скопировать приложение в /Applications
#   ./build.sh --no-module — собрать без движков замера (они качаются модулем)
set -e
cd "$(dirname "$0")"

# Сообщения скрипта только ASCII: в терминале без UTF-8 любые другие символы видны как «??».
step() { echo; echo "==> [$1/5] $2"; }
trap 'status=$?; if [ $status -ne 0 ]; then echo; echo "BUILD FAILED (exit code $status). Read the error above and the build errors table in README.md." >&2; fi' EXIT

MAKE_ZIP=0
INSTALL=0
NO_MODULE=0
for arg in "$@"; do
  case "$arg" in
    --zip) MAKE_ZIP=1 ;;
    --install) INSTALL=1 ;;
    --no-module) NO_MODULE=1 ;;
    *) echo "Unknown option: $arg (use --zip, --install or --no-module)" >&2; exit 1 ;;
  esac
done

step 1 "Checking tools"
if ! xcrun -f swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Install Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

APP="build/Release/RME Control.app"
# Версия берётся из проекта Xcode (MARKETING_VERSION), чтобы не задавать её в двух местах.
VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "RME Control.xcodeproj/project.pbxproj" | head -1)
if [ -z "$VERSION" ]; then
  echo "MARKETING_VERSION not found in project.pbxproj" >&2
  exit 1
fi
echo "    $(xcrun swiftc --version 2>&1 | head -1)"
echo "    RME Control version: $VERSION"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Все исходники из папок проекта (App, Models, Services, Features, Common).
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find "RME Control" -name '*.swift' -print0 | sort -z)

# Универсальный бинарник: arm64 (Apple Silicon) и x86_64 (Intel) склеиваются через lipo.
TMP=$(mktemp -d)
step 2 "Compiling (2 passes: Apple Silicon and Intel). This takes 1-5 minutes and prints nothing - it is not frozen."
for ARCH in arm64 x86_64; do
  echo "    compiling $ARCH ..."
  xcrun swiftc -O -swift-version 6 -target "$ARCH-apple-macosx14.0" \
    "${SOURCES[@]}" \
    -o "$TMP/RME Control-$ARCH"
done
xcrun lipo -create "$TMP/RME Control-arm64" "$TMP/RME Control-x86_64" -output "$APP/Contents/MacOS/RME Control"
rm -rf "$TMP"

step 3 "Copying resources and translations"

cp "RME Control/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "RME Control/Resources/RME_Control_Tray.png" "$APP/Contents/Resources/RME_Control_Tray.png"
if [ "$NO_MODULE" = 0 ] && [ ! -f "RME Control/Resources/roomeq" ]; then
  echo "    measurement engines are not in the tree: building without them."
  echo "    the app downloads the module from Settings > Modules."
  NO_MODULE=1
fi

if [ "$NO_MODULE" = 0 ]; then
  cp "RME Control/Resources/roomeq" "$APP/Contents/Resources/roomeq"
  chmod +x "$APP/Contents/Resources/roomeq"
  cp "RME Control/Resources/sotf-capture" "$APP/Contents/Resources/sotf-capture"
  chmod +x "$APP/Contents/Resources/sotf-capture"
fi
cp "RME Control/Resources/THIRD_PARTY_NOTICES.txt" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp "RME Control/Resources/GPL-3.0.txt" "$APP/Contents/Resources/GPL-3.0.txt"
cp "RME Control/Resources/Web/remote.html" "$APP/Contents/Resources/remote.html"
cp "RME Control/Resources/Web/compressor.html" "$APP/Contents/Resources/compressor.html"
cp "RME Control/Resources/Web/compressor.js" "$APP/Contents/Resources/compressor.js"
cp "RME Control/Resources/Web/eq.html" "$APP/Contents/Resources/eq.html"
cp "RME Control/Resources/Web/eq.js" "$APP/Contents/Resources/eq.js"
cp "RME Control/Resources/Web/levels.html" "$APP/Contents/Resources/levels.html"
cp "RME Control/Resources/Web/levels.js" "$APP/Contents/Resources/levels.js"
cp "RME Control/Resources/Web/react.production.min.js" "$APP/Contents/Resources/react.production.min.js"
cp "RME Control/Resources/Web/react-dom.production.min.js" "$APP/Contents/Resources/react-dom.production.min.js"
cp "RME Control/Resources/Web/window-drag.js" "$APP/Contents/Resources/window-drag.js"
cp "RME Control/Resources/Web/remote-bridge.js" "$APP/Contents/Resources/remote-bridge.js"

# Строки интерфейса: Localizable.xcstrings → <язык>.lproj/Localizable.strings.
# xcstringstool есть только в полном Xcode; без него конвертируем тем же форматом через python3.
XCSTRINGS="RME Control/Resources/Localizable.xcstrings"
if xcrun -f xcstringstool >/dev/null 2>&1; then
  xcrun xcstringstool compile "$XCSTRINGS" --output-directory "$APP/Contents/Resources"
else
  python3 - "$XCSTRINGS" "$APP/Contents/Resources" <<'PY'
import json, os, sys

src, out = sys.argv[1], sys.argv[2]
catalog = json.load(open(src, encoding="utf-8"))

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

tables = {}
for key, entry in catalog["strings"].items():
    for lang, loc in entry.get("localizations", {}).items():
        value = loc.get("stringUnit", {}).get("value")
        if value is not None:
            tables.setdefault(lang, []).append((key, value))

for lang, pairs in tables.items():
    folder = os.path.join(out, f"{lang}.lproj")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "Localizable.strings"), "w", encoding="utf-8") as f:
        for key, value in pairs:
            f.write(f'"{esc(key)}" = "{esc(value)}";\n')
PY
fi

if [ -f "/tmp/apple_touch.png" ]; then
  cp /tmp/apple_touch.png "$APP/Contents/Resources/AppIcon.png"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>RME Control</string>
	<key>CFBundleExecutable</key>
	<string>RME Control</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.rme.volumes</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>RME Control</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>RME Control records a test sweep from the selected microphone to correct Room EQ.</string>
</dict>
</plist>
PLIST

# Ad-hoc подпись: без Apple Developer ID. На чужом Mac Gatekeeper такое приложение
# из интернета блокирует — см. README, раздел «Если приложение не запускается».
step 4 "Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

step 5 "Done"
echo "    Built: $PWD/$APP"
echo "    Version $VERSION, architectures: $(lipo -archs "$APP/Contents/MacOS/RME Control")"

if [ "$MAKE_ZIP" = 1 ]; then
  # ditto сохраняет права и атрибуты бандла; .app, отправленный «как есть», часто ломается.
  ZIP="build/RME-Control-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "    Packed: $PWD/$ZIP"
fi

if [ "$INSTALL" = 1 ]; then
  pkill -x "RME Control" 2>/dev/null || true
  rm -rf "/Applications/RME Control.app"
  ditto "$APP" "/Applications/RME Control.app"
  echo "    Installed: /Applications/RME Control.app"
  open "/Applications/RME Control.app"
  echo "    Launched. Look for the RME Control icon in the menu bar (top right of the screen)."
else
  echo
  echo "To install into Applications and launch, run:  ./build.sh --install"
fi
