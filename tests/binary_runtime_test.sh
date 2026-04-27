#!/usr/bin/env bash
# Runs `playwright_binary --version` and asserts the output matches the
# version pinned in private/versions.bzl. Exercises the launcher's `binary`
# mode end-to-end (cli.js resolution, host node, runfiles).
set -euo pipefail

bin="$1"
expected="$2"

actual=$("$bin" --version 2>&1)
if [[ "$actual" != *"Version $expected"* ]]; then
  echo "FAIL: expected '... Version $expected ...', got: $actual" >&2
  exit 1
fi
echo "OK: $actual"
