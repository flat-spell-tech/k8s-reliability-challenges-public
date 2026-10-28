#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
workbook=${1:?workbook directory name}
action=${2:?deploy, inject, verify-fault, repair, verify-healthy, or destroy}
[[ "$workbook" =~ ^(0[1-9]|10)-[a-z-]+$ && -d "$root/workbooks/$workbook" ]] || exit 2
infra="$root/workbooks/$workbook/infra"
remote() { bash "$root/scripts/run-on-runner.sh" "$workbook" "$1"; }
apply_infra() { terraform -chdir="$infra" apply -var="fault_enabled=$1"; }
case "$action" in
  deploy)
    terraform -chdir="$infra" init
    apply_infra false
    if [[ $workbook == 03-* ]]; then
      config=$(terraform -chdir="$infra" output -json connection)
      az acr import --name "$(jq -r .acr_name <<< "$config")" --resource-group "$(jq -r .resource_group <<< "$config")" \
        --source mcr.microsoft.com/azuredocs/aks-helloworld:v1 --image lab/hello:v1 --force
    fi
    remote setup
    remote baseline
    ;;
  inject)
    case "$workbook" in
      01-*) apply_infra true ;; # Do not invoke a K8s provider over the intentionally broken path.
      02-*|03-*|04-*) apply_infra true; remote inject ;;
      *) remote inject ;;
    esac
    ;;
  repair)
    case "$workbook" in 01-*|02-*|03-*|04-*) apply_infra false ;; esac
    remote repair
    ;;
  verify-fault)
    case "$workbook" in
      01-*|02-*|03-*|04-*) [[ $(terraform -chdir="$infra" output -raw fault_enabled) == true ]] || { echo 'Inject the infrastructure fault first.' >&2; exit 1; } ;;
    esac
    remote verify-fault
    ;;
  inspect) remote inspect ;;
  verify-healthy)
    case "$workbook" in
      01-*|02-*|03-*|04-*) [[ $(terraform -chdir="$infra" output -raw fault_enabled) == false ]] || { echo 'Repair the infrastructure fault first.' >&2; exit 1; } ;;
    esac
    remote verify-healthy
    ;;
  destroy)
    # Restore the management path/egress/identity before in-cluster teardown.
    case "$workbook" in 01-*|02-*|03-*|04-*) apply_infra false ;; esac
    remote destroy
    terraform -chdir="$infra" destroy
    ;;
  *) echo 'Unknown action.' >&2; exit 2 ;;
esac
