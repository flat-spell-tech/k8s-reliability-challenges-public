#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$here/assert-context.sh"
timeout=${VERIFY_TIMEOUT_SECONDS:-600}
[[ "$timeout" =~ ^[0-9]+$ && $timeout -ge 10 && $timeout -le 1800 ]] || exit 2
end=$((SECONDS + timeout))
until getent ahostsv4 "$LAB_PRIVATE_FQDN" >/dev/null && \
  kubectl get namespace kube-system --request-timeout=15s >/dev/null 2>&1; do
  ((SECONDS < end)) || {
    echo 'Private API DNS/access did not become ready. Inspect DNS and scoped AKS roles; this is not a reproduced scenario fault.' >&2
    exit 1
  }
  sleep 5
done
