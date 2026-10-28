#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$here/assert-context.sh"
flux install --version="${FLUX_VERSION:?}" --namespace=flux-system \
  --components=source-controller,kustomize-controller,helm-controller --timeout=5m
kubectl label namespace flux-system reliability.flatspell.io/lab=true --overwrite
if [[ -n "${FLUX_CLIENT_ID:-}" ]]; then
  kubectl annotate serviceaccount source-controller -n flux-system \
    "azure.workload.identity/client-id=$FLUX_CLIENT_ID" --overwrite
  kubectl patch deployment source-controller -n flux-system --type=merge \
    -p '{"spec":{"template":{"metadata":{"labels":{"azure.workload.identity/use":"true"}}}}}'
  kubectl rollout status deployment/source-controller -n flux-system --timeout=5m
fi
for controller in source-controller kustomize-controller helm-controller; do
  kubectl rollout status deployment/"$controller" -n flux-system --timeout=5m
done
