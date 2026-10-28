#!/usr/bin/env bash
set -euo pipefail
resource=${1:?resource/name}
namespace=${2:?namespace}
timeout=${VERIFY_TIMEOUT_SECONDS:-600}
[[ "$timeout" =~ ^[0-9]+$ && $timeout -ge 10 && $timeout -le 1800 ]] || exit 2
end=$((SECONDS + timeout))
until kubectl get "$resource" -n "$namespace" -o json | jq -e '
  .status.observedGeneration == .metadata.generation and
  any(.status.conditions[]?; .type == "Ready" and .status == "True")' >/dev/null; do
  if ((SECONDS >= end)); then
    kubectl get "$resource" -n "$namespace" -o json | jq '{metadata:{name:.metadata.name,generation:.metadata.generation},status}'
    exit 1
  fi
  sleep 5
done
