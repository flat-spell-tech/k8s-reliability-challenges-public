#!/usr/bin/env bash
set -euo pipefail
: "${LAB_PRIVATE_FQDN:?Missing expected private AKS hostname}"
: "${KUBECONFIG:?Use the lab-specific kubeconfig}"
server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
if [[ "$server" != "https://${LAB_PRIVATE_FQDN}" && "$server" != "https://${LAB_PRIVATE_FQDN}:443" ]]; then
  echo 'Refusing to operate: kubeconfig does not target this workbook cluster.' >&2
  exit 1
fi
