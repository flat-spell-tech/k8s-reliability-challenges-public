#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$here/assert-context.sh"
label=$(kubectl get namespace flux-system -o jsonpath='{.metadata.labels.reliability\.flatspell\.io/lab}')
[[ "$label" == true ]] || { echo 'Missing lab ownership label; refusing Flux uninstall.' >&2; exit 1; }
flux uninstall --namespace=flux-system --silent
