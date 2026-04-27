#!/usr/bin/env bash
# Runs under rules_itest's service_test once playwright_server is up.
# itest exports the assigned port via $PORT (set in BUILD.bazel via
# `service_test(env = {"PORT": port(...)})`). itest's default health probe
# closes the held socket as soon as it's reused, so we may race ahead of
# Playwright's bind — poll for up to 5s before giving up. Successfully
# connecting proves the server bound the port itest told it to (i.e. the
# launcher's runtime $PORT override path works end-to-end).
set -euo pipefail

: "${PORT:?service_test must set PORT}"

deadline=$(( $(date +%s) + 5 ))
while (( $(date +%s) < deadline )); do
  if (exec 3<>/dev/tcp/127.0.0.1/"$PORT") 2>/dev/null; then
    exec 3<&-
    echo "OK: playwright_server listening on 127.0.0.1:$PORT"
    exit 0
  fi
  sleep 0.1
done

echo "FAIL: playwright_server never bound 127.0.0.1:$PORT within 5s" >&2
exit 1
