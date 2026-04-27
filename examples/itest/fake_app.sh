#!/usr/bin/env bash
# Trivial HTTP server that serves a single page. Stand-in for a real app.
# itest passes the allocated port via $PORT.
set -euo pipefail

PORT="${PORT:?itest must set PORT}"

cat <<'HTML' > /tmp/index.html
<!doctype html>
<html><body><h1 id="title">fake app</h1></body></html>
HTML

exec python3 -m http.server "$PORT" --directory /tmp
