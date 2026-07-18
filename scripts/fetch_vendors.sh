#!/usr/bin/env sh
# ---------------------------------------------------------------------------
# Fetch vendored 3rd-party libs into vendor/.
#
#   dobby     — prebuilt iOS static lib from jmpews/Dobby releases,
#               universal (arm64 + arm64e). Powers the JAILED build path.
#   fishhook  — 2 source files + LICENSE from facebook/fishhook@main.
#               C-symbol rebinding, always compiled into the tweak.
#
# Idempotent — each library is skipped when already present. Force a
# re-fetch with FORCE=1.
# ---------------------------------------------------------------------------

set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)

fetch_dobby() {
    vendor="$ROOT/vendor/dobby"
    lib="$vendor/lib/libdobby.a"
    if [ -f "$lib" ] && [ -z "$FORCE" ]; then
        echo "dobby: $lib already present (FORCE=1 to re-fetch)"
        return 0
    fi

    url="https://github.com/jmpews/Dobby/releases/download/latest/dobby-iphoneos-all.tar.gz"
    tmp=$(mktemp -d)

    echo "dobby: downloading $url"
    curl -fsSL "$url" -o "$tmp/dobby.tar.gz"

    echo "dobby: extracting into $vendor"
    tar xzf "$tmp/dobby.tar.gz" -C "$tmp"

    mkdir -p "$vendor/include" "$vendor/lib"
    cp "$tmp/build/iphoneos/dobby.h"              "$vendor/include/dobby.h"
    cp "$tmp/build/iphoneos/universal/libdobby.a" "$vendor/lib/libdobby.a"

    rm -rf "$tmp"
    echo "dobby: installed (universal arm64+arm64e)"
}

fetch_fishhook() {
    vendor="$ROOT/vendor/fishhook"
    if [ -f "$vendor/fishhook.c" ] && [ -z "$FORCE" ]; then
        echo "fishhook: $vendor/fishhook.c already present (FORCE=1 to re-fetch)"
        return 0
    fi

    base="https://raw.githubusercontent.com/facebook/fishhook/main"
    mkdir -p "$vendor"
    for f in fishhook.h fishhook.c LICENSE; do
        echo "fishhook: downloading $f"
        curl -fsSL "$base/$f" -o "$vendor/$f"
    done
    echo "fishhook: installed"
}

fetch_dobby
fetch_fishhook
