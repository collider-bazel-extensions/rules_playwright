#!/usr/bin/env bash
# Apply the manifests, wait for ready, then port-forward on $PORT.
# itest exports KUBECONFIG from the kind_cluster service.
set -euo pipefail

PORT="${PORT:?itest must set PORT}"

kubectl apply -f "${BUILD_WORKSPACE_DIRECTORY:-$PWD}/examples/kind/app.yaml"
kubectl wait --for=condition=available --timeout=120s deployment/myapp

# Port-forward stays in foreground; SIGTERM from itest tears it down.
exec kubectl port-forward svc/myapp "${PORT}:80"
