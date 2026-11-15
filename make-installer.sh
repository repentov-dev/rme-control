#!/bin/bash
# Собирает установщик .pkg из уже собранного build/Release/RME Control.app.
#   ./make-installer.sh
#
# Что делает установщик:
#   * закрывает запущенную копию и удаляет старый бандл из /Applications;
#   * кладёт новую версию в /Applications;
#   * снимает с неё com.apple.quarantine (postinstall).
#
# Важно: если .pkg не подписан Developer ID Installer и не нотаризован, macOS
# всё равно попросит один раз разрешить его: System Settings → Privacy &
# Security → Open Anyway. После этого приложение уже запускается без карантина.
#
# Для полностью бесшовной раздачи задайте перед сборкой:
#   APP_IDENTITY="Developer ID Application: ..."      (переподписать приложение)
#   INSTALLER_IDENTITY="Developer ID Installer: ..."  (подписать .pkg)
#   NOTARY_PROFILE="rme-notary"                       (профиль notarytool)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Release/RME Control.app"
VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "RME Control.xcodeproj/project.pbxproj" | head -1)
OUT="build/RME-Control-$VERSION.pkg"

if [ ! -d "$APP" ]; then
  echo "No $APP. Run ./build.sh first." >&2
  exit 1
fi
if [ -z "$VERSION" ]; then
  echo "MARKETING_VERSION not found." >&2
  exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/payload"
ditto "$APP" "$WORK/payload/RME Control.app"

# Необязательная переподпись приложения Developer ID (нужна для нотаризации).
if [ -n "${APP_IDENTITY:-}" ]; then
  echo "    signing app with: $APP_IDENTITY"
  codesign --force --deep --options runtime --timestamp \
    --sign "$APP_IDENTITY" "$WORK/payload/RME Control.app"
fi

echo "    building component package"
pkgbuild \
  --root "$WORK/payload" \
  --scripts installer \
  --identifier "com.rme.volumes.installer" \
  --version "$VERSION" \
  --install-location "/Applications" \
  --ownership recommended \
  "$WORK/component.pkg"

IDENTITY="${INSTALLER_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p basic 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' | head -1 || true)
fi

rm -f "$OUT"
if [ -n "$IDENTITY" ]; then
  echo "    signing installer with: $IDENTITY"
  productbuild --package "$WORK/component.pkg" \
    --identifier "com.rme.volumes.installer" --version "$VERSION" \
    --sign "$IDENTITY" "$OUT"
else
  echo "    no Developer ID Installer identity: package will be unsigned"
  productbuild --package "$WORK/component.pkg" \
    --identifier "com.rme.volumes.installer" --version "$VERSION" "$OUT"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "    notarizing (this can take a few minutes)"
  xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT"
fi

echo
echo "    Built: $PWD/$OUT"
echo "    Quarantine is removed from the installed app by the postinstall script."
