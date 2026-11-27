#!/usr/bin/env bash
# Build against the user's PZ 42.22 Java classes, never package game classes.
set -eu
cd "$(dirname "$0")"
: "${PZ_CLASSPATH:?Set PZ_CLASSPATH to the Project Zomboid Java classes and jars}"
command -v javac >/dev/null
command -v jar >/dev/null
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
javac --release 17 -cp "$PZ_CLASSPATH" -d "$tmp" src/main/java/me/refri/mlos/ModFiles.java
out=../Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/java/client
mkdir -p "$out"
jar cf "$out/MLOSBridge.jar" -C "$tmp" me/refri/mlos
printf 'Built %s/MLOSBridge.jar\n' "$out"
