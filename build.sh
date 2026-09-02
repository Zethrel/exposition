#!/bin/sh
# Packages Exposition for release.
#
# GitHub's own source archives unpack as "exposition-<tag>/", which the game
# will not load: the folder has to be named "Exposition", matching the .toc.
# This script produces a zip that unpacks straight into the AddOns folder.
#
#   ./build.sh            package the version named in the .toc
#   ./build.sh 1.2.0      package that version, failing if the .toc disagrees
set -e
cd "$(dirname "$0")"

TOC_VERSION=$(sed -n 's/^## Version:[[:space:]]*//p' Exposition.toc | tr -d '\r')
VERSION="${1:-$TOC_VERSION}"

if [ -z "$TOC_VERSION" ]; then
	echo "build: no '## Version:' line in Exposition.toc" >&2
	exit 1
fi
if [ "$VERSION" != "$TOC_VERSION" ]; then
	echo "build: asked for $VERSION but Exposition.toc says $TOC_VERSION" >&2
	echo "build: bump the .toc first so the game reports the right version" >&2
	exit 1
fi

OUT=dist
STAGE="$OUT/Exposition"
ZIP="Exposition-$VERSION.zip"

rm -rf "$OUT"
mkdir -p "$STAGE/Core" "$STAGE/UI"

# Only what the client needs, plus the notices that must travel with it.
cp Exposition.toc Exposition.lua LICENSE README.md "$STAGE/"
cp Core/Splitter.lua Core/Config.lua Core/Sender.lua "$STAGE/Core/"
cp UI/MainFrame.lua "$STAGE/UI/"

(cd "$OUT" && zip -rq "$ZIP" Exposition -x '*.DS_Store')

# The archive is only correct if it unpacks into a folder the game will load,
# so check the real thing rather than the staging directory: one top level
# folder named Exposition, containing every file the .toc asks the client to
# load.
VERIFY=$(mktemp -d)
trap 'rm -rf "$VERIFY"' EXIT
unzip -q "$OUT/$ZIP" -d "$VERIFY"

if unzip -Z1 "$OUT/$ZIP" | grep -qv '^Exposition/'; then
	echo "build: archive contains paths outside Exposition/" >&2
	unzip -Z1 "$OUT/$ZIP" | grep -v '^Exposition/' >&2
	exit 1
fi

TOC_FILES=$(grep -E '^[^#[:space:]].*\.lua[[:space:]]*$' Exposition.toc | tr -d '\r' | tr '\\' '/')
if [ -z "$TOC_FILES" ]; then
	echo "build: Exposition.toc lists no files to load" >&2
	exit 1
fi

MISSING=
for path in $TOC_FILES; do
	[ -f "$VERIFY/Exposition/$path" ] || MISSING="$MISSING $path"
done
if [ -n "$MISSING" ]; then
	echo "build: .toc loads files that are not in the package:$MISSING" >&2
	exit 1
fi

if [ ! -f "$VERIFY/Exposition/LICENSE" ]; then
	echo "build: LICENSE must ship with the addon" >&2
	exit 1
fi

echo "built $OUT/$ZIP"
unzip -Z1 "$OUT/$ZIP" | sort
