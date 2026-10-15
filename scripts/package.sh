#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
version="$(tr -d '\n' < "$task_root/VERSION")"
zsh "$task_root/scripts/build.sh"
app="$task_root/build/SystemPhraseBar.app"
codesign --verify --strict "$app"
archive="$task_root/build/SystemPhraseBar-$version-macos-universal.app.zip"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$archive"
cd "$task_root/build"
shasum -a 256 "${archive:t}" > SHA256SUMS.txt
printf '%s\n' "$archive"
