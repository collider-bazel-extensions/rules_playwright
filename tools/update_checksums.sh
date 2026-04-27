#!/usr/bin/env bash
# tools/update_checksums.sh <playwright-version> [<playwright-version>...]
#
# For each requested Playwright version:
#   1. Fetch playwright-core@<ver> from npm.
#   2. Read browsers.json to get the chromium revision.
#   3. For each (platform) we support, derive the bundle URL and sha256.
#   4. Rewrite private/versions.bzl in place.
#
# v0.1.0 only refreshes chromium. Firefox + webkit join the table when those
# channels are added to the repo rule.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${REPO_ROOT}/private/versions.bzl"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <playwright-version> [<playwright-version>...]" >&2
  exit 2
fi

python3 "${REPO_ROOT}/tools/update_checksums.py" "$@" --manifest "$MANIFEST" --workdir "$WORK"
