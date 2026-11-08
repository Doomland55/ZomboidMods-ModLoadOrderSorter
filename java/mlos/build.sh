#!/bin/sh
# Build with any JDK 8+; the annotation is provided by PZ at runtime, not bundled.
set -eu
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
javac -source 8 -target 8 -d "$tmp" stubs/se/krka/kahlua/integration/annotations/LuaMethod.java src/me/refri/mlos/ModFilesBridge.java
mkdir -p ../../Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/java/client
jar cf ../../Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/java/client/MLOSBridge.jar -C "$tmp" me/refri/mlos
