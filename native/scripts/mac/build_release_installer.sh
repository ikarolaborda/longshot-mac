#!/bin/sh
# Build the distributable on a Mac from the native source tree in a Git commit.
set -eu
tree=${1:?usage: build_release_installer.sh Git-tree output-executable [release-tag]}
output=${2:?missing output executable}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tag=${3:-}
if [ -n "$tag" ]; then
    printf '%s\n' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+-(mac|metal-experimental)\.[1-9][0-9]*$' || exit 2
fi
git archive --format=tar.gz -o "$tmp/source.tar.gz" "$tree" -- . ':(exclude)assets/saves'
tar -xOf "$tmp/source.tar.gz" scripts/mac/release_installer.m > "$tmp/installer.m"
xcrun clang "-DLONGSHOT_RELEASE_TAG=\"$tag\"" -arch arm64 -fobjc-arc -framework AppKit "$tmp/installer.m" \
    -Wl,-sectcreate,__DATA_CONST,__builder,"$tmp/source.tar.gz" -o "$output"
codesign --force --sign - "$output"
codesign --verify --strict "$output"
