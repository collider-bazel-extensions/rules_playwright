#!/usr/bin/env bash
# Healthy iff the deployment has at least one ready replica AND the
# port-forward is accepting connections.
set -euo pipefail

PORT="${PORT:?itest must set PORT}"

ready=$(kubectl get deployment myapp -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
[[ "${ready:-0}" -ge 1 ]] || exit 1

exec bash -c "</dev/tcp/127.0.0.1/${PORT}"
