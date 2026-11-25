#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: bash tools/web/build.sh GODOT_EXECUTABLE EMPTY_OUTPUT_DIRECTORY" >&2
  exit 2
fi

root=$(cd "$(dirname "$0")/../.." && pwd)
godot=$(realpath "$1")
mkdir -p "$2"
output=$(cd "$2" && pwd)
if [ -n "$(ls -A "$output")" ]; then
  echo "Output directory must be empty: $output" >&2
  exit 2
fi
version=$("$godot" --version)
case "$version" in
  4.7.2.stable.*.ed1daf0bf*) ;;
  *) echo "Expected Godot 4.7.2 stable ed1daf0bf, got: $version" >&2; exit 1 ;;
esac

# Import a fresh copy so stale editor imports cannot enter the release.
scratch=$(mktemp -d "${TMPDIR:-/tmp}/olr-web.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/project"
tar -C "$root/games/company-of-unlikely-heroes" --exclude='./.godot' -cf - . |
  tar -C "$scratch/project" -xf -
"$godot" --headless --editor --path "$scratch/project" --import
"$godot" --headless --path "$scratch/project" --export-release Web "$output/index.html"
printf 'Web export: %s\n' "$output"
du -h "$output"/*
