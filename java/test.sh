#!/usr/bin/env bash
# Tests use minimal game API stubs, not the proprietary game classes.
set -eu
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
javac --release 17 -d "$tmp" $(find tests/stubs src/main/java tests/me -name '*.java')
java -cp "$tmp" me.refri.mlos.ModFilesTest
