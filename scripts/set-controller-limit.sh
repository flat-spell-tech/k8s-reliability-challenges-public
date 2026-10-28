#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$here/assert-context.sh"
[[ ${MEMORY_LIMIT:?} == 32Mi || $MEMORY_LIMIT == 512Mi ]] || exit 2
kubectl patch deployment helm-controller -n flux-system --type=merge \
  -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'
kubectl set resources deployment/helm-controller -n flux-system --containers=manager \
  --requests=cpu=50m,memory="$MEMORY_LIMIT" --limits=memory="$MEMORY_LIMIT"
if [[ $MEMORY_LIMIT == 512Mi ]]; then
  kubectl rollout status deployment/helm-controller -n flux-system --timeout=5m
  kubectl patch deployment helm-controller -n flux-system --type=merge \
    -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
fi
