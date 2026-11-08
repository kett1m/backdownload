#!/bin/sh
# Build the module zip from src/.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
prop="$root/src/module.prop"

version=$(sed -n 's/^version=//p' "$prop" | head -n 1)
[ -n "$version" ] || { echo "build.sh: no version in $prop" >&2; exit 1; }
version=${version#v}
out="$root/backdownload-v$version-arm64.zip"

rm -f "$out"
(
  cd "$root/src"
  find . -type f | sed 's|^\./||' | sort | zip -q -X "$out" -@
)
echo "$out"
