#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Prepare OoT's shader service for the macOS builder. The prepared shader cache and
# runtime translator must use the same title-specific compiler.
# Usage: build_shader_service.sh <MacNativeGames root or games/oot> [--out <dir>]
# The earlier form <root> <d2r-mobile checkout> [out dir] is also accepted.
set -eu
title=${1:?Pass the MacNativeGames checkout or its games/oot directory}
shift
if [[ -d "$title/games/oot" ]]; then title="$title/games/oot"; fi
out=${0:A:h:h:h}/work/shader-tools/shader-service
if [[ ${1:-} == --out ]]; then
    [[ $# == 2 ]] || { print -u2 'Expected --out <directory>'; exit 2; }
    out=$2
elif (( $# >= 1 )); then
    (( $# <= 2 )) || { print -u2 'Too many arguments'; exit 2; }
    out=${2:-$out}
fi

src="$title/prebuilt/macos-arm64"
mkdir -p "$out"
stage=$(mktemp -d "$out/.oot-service.XXXXXX")
trap 'rm -rf "$stage"' EXIT
for name in oot_write_proof.dylib totk_xlate; do
    cp -p "$src/$name" "$src/$name.sha256" "$stage/"
    expected=$(awk 'NR == 1 {print $1}' "$stage/$name.sha256")
    actual=$(shasum -a 256 "$stage/$name" | awk '{print $1}')
    [[ "$actual" == "$expected" ]] || { print -u2 "Checksum mismatch for $name"; exit 1; }
done
cp "$src/"*.LICENSE "$stage/"
cp "$title/tools/totk_xlate/LICENSE" "$stage/translator.LICENSE"
cp "$title/third_party/ryujinx/LICENSE.txt" "$stage/Ryujinx.LICENSE"
# Install the executable last. Replacing the inode also works while the old service is running.
for f in "$stage/"*.LICENSE "$stage/"*.sha256 "$stage/oot_write_proof.dylib" "$stage/totk_xlate"; do
    mv -f "$f" "$out/"
done
print "Prepared OoT shader service in $out"
