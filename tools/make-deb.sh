#!/bin/sh
# make-deb.sh BASE_DEB PROGRAM QMLDIR OUTDIR VERSION REV
# Builds OUTDIR/maeshare_VERSION-REV_armel.deb: the release package of the author (BASE_DEB: the helper `probe`, alias word lists, icons, menu entry, sharing plugin)
# with our program and our QML files (CSSU tree in /opt/maeshare, stock Qt 4.7 tree in /opt/maeshare/qml47: the same files with `import Qt 4.7`).
# Needs dpkg-deb; the files of the deb belong to root (--root-owner-group). No ImageMagick: the control file has no Application Manager icon.
set -eu
[ $# -eq 6 ] || { sed -n '2,5p' "$0"; exit 2; }
BASE=$1; PROG=$2; QML=$3; OUT=$4; VERSION=$5; REV=$6
STAGE=$OUT/stage
rm -rf "$STAGE"; mkdir -p "$STAGE"
dpkg-deb -x "$BASE" "$STAGE"
dpkg-deb -e "$BASE" "$STAGE/DEBIAN"
M=$STAGE/opt/maeshare
install -m 755 "$PROG" "$M/maeshare"
cp "$QML"/*.qml "$QML/i18n.js" "$QML"/*.png "$M/"
rm -rf "$M/icons" "$M/qml47"; mkdir -p "$M/qml47"
cp -r "$QML/icons" "$M/icons"
for f in "$M"/*.qml; do sed 's/^import QtQuick 1\.0$/import Qt 4.7/' "$f" > "$M/qml47/$(basename "$f")"; done
cp "$M/i18n.js" "$M"/*.png "$M/qml47/"; cp -r "$M/icons" "$M/qml47/icons"
grep -q '^import Qt 4.7$' "$M/qml47/Main.qml" || { echo "qml47/Main.qml has no 'import Qt 4.7'" >&2; exit 1; }
SIZE=$(du -sk "$STAGE" | cut -f1)
# the control file of the author with our version and size (everything else, Depends included, stays)
sed -e "s/^Version: .*/Version: $VERSION-$REV/" -e "s/^Installed-Size: .*/Installed-Size: $SIZE/" "$STAGE/DEBIAN/control" > "$STAGE/DEBIAN/control.new"
mv "$STAGE/DEBIAN/control.new" "$STAGE/DEBIAN/control"
chmod -R u+rwX,go+rX,go-w "$STAGE"
DEB=$OUT/maeshare_$VERSION-${REV}_armel.deb
dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB"
dpkg-deb -I "$DEB" | head -12
ls -l "$DEB"
