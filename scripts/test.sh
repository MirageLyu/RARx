#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-$ROOT/build/RARx.app}"
TMP="$(mktemp -d /tmp/rarx-tests.XXXXXX)"
FAIL=0

if [[ "$APP" == "$ROOT/build/RARx.app" && ! -d "$APP" ]]; then
    "$ROOT/scripts/build-app.sh"
fi
if [[ ! -x "$ROOT/build/engine/unrar" ]]; then
    "$ROOT/scripts/build-engine.sh"
fi

cleanup() {
    pkill -x RARx 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT

echo "== Core extraction tests =="
swiftc -swift-version 5 -Onone -g -parse-as-library \
    -target "$(uname -m)-apple-macos13.0" \
    "$ROOT"/Sources/Core/*.swift \
    "$ROOT"/Tests/CoreTests.swift \
    -o "$ROOT/build/rarx-core-tests"
RARX_ENGINE="$ROOT/build/engine/unrar" \
RARX_FIXTURES="$ROOT/Tests/Fixtures" \
    "$ROOT/build/rarx-core-tests"

echo
echo "== Finder-style app tests =="
pkill -x RARx 2>/dev/null || true
sleep 0.3

run_case() {
    local label="$1"
    shift
    echo "- $label"
    if ! "$@"; then
        echo "  FAIL: $label"
        FAIL=$((FAIL + 1))
        return 1
    fi
    echo "  ok: $label"
}

wait_for_exit() {
    for _ in $(seq 1 100); do
        pgrep -x RARx >/dev/null 2>&1 || return 0
        sleep 0.1
    done
    pkill -x RARx 2>/dev/null || true
    return 1
}

assert_file() {
    [[ -f "$1" ]] || { echo "    missing file: $1"; return 1; }
}

assert_dir() {
    [[ -d "$1" ]] || { echo "    missing directory: $1"; return 1; }
}

# Normal silent extraction.
CASE="$TMP/sample"
mkdir -p "$CASE"
cp "$ROOT/Tests/Fixtures/sample.rar" "$CASE/"
run_case "double-click extracts silently" open -W -a "$APP" "$CASE/sample.rar"
assert_file "$CASE/readme.txt" || FAIL=$((FAIL+1))
assert_file "$CASE/资料 folder/中文 文档.txt" || FAIL=$((FAIL+1))
assert_file "$CASE/资料 folder/sub/random.bin" || FAIL=$((FAIL+1))
assert_dir "$CASE/empty" || FAIL=$((FAIL+1))
[[ ! -e "$CASE/readme.txt" || "$(cat "$CASE/readme.txt")" == "hello RAR" ]] || { echo "    bad content"; FAIL=$((FAIL+1)); }
wait_for_exit || { echo "    app did not exit"; FAIL=$((FAIL+1)); }
leftovers=$(find "$CASE" -maxdepth 1 -name '.rarx-*' -print -quit)
[[ -z "$leftovers" ]] || { echo "    staging leftover"; FAIL=$((FAIL+1)); }

# Safe collision handling.
run_case "same archive twice keeps both copies" open -W -a "$APP" "$CASE/sample.rar"
assert_file "$CASE/readme 2.txt" || FAIL=$((FAIL+1))
assert_file "$CASE/资料 folder/中文 文档 2.txt" || FAIL=$((FAIL+1))
wait_for_exit || { echo "    app did not exit"; FAIL=$((FAIL+1)); }

# Split-volume normalization.
CASE="$TMP/split"
mkdir -p "$CASE"
cp "$ROOT/Tests/Fixtures/split.part1.rar" "$ROOT/Tests/Fixtures/split.part2.rar" "$CASE/"
run_case "opening part 2 starts from part 1" open -W -a "$APP" "$CASE/split.part2.rar"
assert_file "$CASE/random.bin" || FAIL=$((FAIL+1))
size=$(stat -f%z "$CASE/random.bin" 2>/dev/null || echo 0)
[[ "$size" == "16384" ]] || { echo "    unexpected split output size: $size"; FAIL=$((FAIL+1)); }
wait_for_exit || { echo "    app did not exit"; FAIL=$((FAIL+1)); }

# Multiple archives in one Finder open event.
CASE_A="$TMP/batch-a"
CASE_B="$TMP/batch-b"
mkdir -p "$CASE_A" "$CASE_B"
cp "$ROOT/Tests/Fixtures/sample.rar" "$CASE_A/"
cp "$ROOT/Tests/Fixtures/folders-only.rar" "$CASE_B/"
run_case "multiple archives are queued" open -W -a "$APP" "$CASE_A/sample.rar" "$CASE_B/folders-only.rar"
assert_file "$CASE_A/readme.txt" || FAIL=$((FAIL+1))
assert_dir "$CASE_B/empty" || FAIL=$((FAIL+1))
wait_for_exit || { echo "    app did not exit"; FAIL=$((FAIL+1)); }

# Installed default handler.
if [[ "$APP" == "/Applications/RARx.app" ]]; then
    echo "- default .rar handler"
    if "$APP/Contents/MacOS/RARx" --verify-default; then
        CASE="$TMP/default"
        mkdir -p "$CASE"
        cp "$ROOT/Tests/Fixtures/sample.rar" "$CASE/"
        if open -W "$CASE/sample.rar" && [[ -f "$CASE/readme.txt" ]]; then
            echo "  ok: Finder default handler opens and extracts"
        else
            echo "  FAIL: Finder default handler"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: RARx is not the default .rar handler"
        FAIL=$((FAIL + 1))
    fi
fi

if [[ "$FAIL" -ne 0 ]]; then
    echo
    echo "$FAIL app test(s) failed" >&2
    exit 1
fi
echo
echo "All tests passed."
