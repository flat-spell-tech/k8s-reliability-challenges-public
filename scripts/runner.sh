#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
workbook=${1:?}
action=${2:?}
[[ "$workbook" =~ ^(0[1-9]|10)-[a-z-]+$ && -d "$root/workbooks/$workbook" ]] || exit 2
base="$root/workbooks/$workbook"
cfg="$root/.lab/$workbook/connection.json"
[[ $(jq -er .workbook "$cfg") == "$workbook" ]] || exit 2
export KUBECONFIG="$root/.lab/$workbook/kubeconfig"
export LAB_PRIVATE_FQDN
LAB_PRIVATE_FQDN=$(jq -er .private_fqdn "$cfg")
az login --identity --output none
az account set --subscription "$(jq -er .subscription_id "$cfg")"
if [[ "$action" == setup ]]; then
  export LAB_AKS_VERSION
  LAB_AKS_VERSION=$(az aks show -g "$(jq -er .resource_group "$cfg")" -n "$(jq -er .cluster_name "$cfg")" --query kubernetesVersion -o tsv)
  bash "$root/scripts/install-tools.sh"
  deadline=$((SECONDS + 600))
  until az aks get-credentials -g "$(jq -er .resource_group "$cfg")" -n "$(jq -er .cluster_name "$cfg")" \
    --context "$(jq -er .cluster_name "$cfg")" --file "$KUBECONFIG" --overwrite-existing; do
    ((SECONDS < deadline)) || { echo 'AKS credential access did not propagate; inspect the scoped role.' >&2; exit 1; }
    sleep 10
  done
  kubelogin convert-kubeconfig --login azurecli --kubeconfig "$KUBECONFIG"
fi
python3 - "$cfg" "$root/.lab/$workbook/connection.tfvars.json" <<'PY'
import json,sys
with open(sys.argv[1]) as source: value=json.load(source)
with open(sys.argv[2],'w') as target: json.dump({'connection':value},target)
PY
vars="$root/.lab/$workbook/connection.tfvars.json"
export TF_PLUGIN_CACHE_DIR="$root/.lab/provider-cache"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
tf() {
  local stage=$1; shift
  terraform -chdir="$base/$stage" "$@"
}
apply_scenario() {
  tf scenario init -input=false
  tf scenario apply -input=false -auto-approve -var-file="$vars" \
    -var="kubeconfig_path=$KUBECONFIG" -var="git_ref=${LAB_REPOSITORY_REF:-main}" "$@"
}
wait_release() { bash "$root/scripts/wait-ready.sh" "helmrelease/$1" "workbook-${workbook:0:2}"; }
seed_chart() {
  local acr server
  acr=$(jq -er .acr_name "$cfg"); server=$(jq -er .acr_login_server "$cfg")
  # Helm consumes the token over stdin; do not enable shell tracing or echo it.
  az acr login --name "$acr" --expose-token --query accessToken -o tsv | \
    helm registry login "$server" --username 00000000-0000-0000-0000-000000000000 --password-stdin
  mkdir -p "$root/.lab/$workbook/charts"
  helm package "$root/fixtures/charts/workbook" --destination "$root/.lab/$workbook/charts"
  helm push "$root/.lab/$workbook/charts/workbook-0.1.0.tgz" "oci://$server/helm"
  helm registry logout "$server"
}
if [[ "$action" == setup ]]; then
  bash "$root/scripts/wait-api.sh"
  tf bootstrap init -input=false
  tf bootstrap apply -input=false -auto-approve -var-file="$vars" -var="kubeconfig_path=$KUBECONFIG"
  exit
fi
# Challenge 01 intentionally prevents this runner from resolving the API. Its
# fault verification must work without kubectl or a live Terraform K8s provider.
if [[ "$action" == verify-fault && "$workbook" == 01-* ]]; then
  getent ahostsv4 login.microsoftonline.com >/dev/null || { echo 'General DNS is broken; this is not specific fault evidence.' >&2; exit 1; }
  if getent ahostsv4 "$LAB_PRIVATE_FQDN" >/dev/null; then
    echo 'API name still resolves; fault not demonstrated (check resolver cache).' >&2; exit 1
  fi
  echo 'PASS: private API name does not resolve from the hub runner.'
  exit
fi
if [[ "$action" == inspect && "$workbook" == 01-* ]]; then
  printf 'Private API DNS: %s\n' "$LAB_PRIVATE_FQDN"
  getent ahostsv4 "$LAB_PRIVATE_FQDN" || true
  getent ahostsv4 login.microsoftonline.com
  exit
fi
bash "$root/scripts/assert-context.sh"
case "$action" in baseline|repair|destroy) bash "$root/scripts/wait-api.sh" ;; esac
case "$action" in
  inspect)
    kubectl get gitrepositories,ocirepositories,kustomizations,helmreleases -A
    kubectl get pods -n "workbook-${workbook:0:2}" -o wide
    kubectl get events -n "workbook-${workbook:0:2}" --sort-by=.metadata.creationTimestamp | tail -25
    kubectl logs deployment/source-controller -n flux-system --tail=15 || true
    kubectl logs deployment/helm-controller -n flux-system --tail=15 || true
    case "$workbook" in
      06-*) kubectl get crd widgets.reliability.flatspell.io --ignore-not-found ;;
      07-*) kubectl get crd schemarecords.schema.reliability.flatspell.io -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.mode.enum}'; echo ;;
      08-*) helm history pending-lab -n workbook-08 ;;
      09-*) kubectl get cleanuptask example -n workbook-09 -o yaml ;;
      10-*) kubectl get pods -n flux-system -l app=helm-controller -o json | jq '.items[] | {name:.metadata.name,containers:.status.containerStatuses}' ;;
    esac
    ;;
  baseline)
    case "$workbook" in
      03-*) echo 'Image-pull test is deferred until after DNS fault injection to avoid a warm image cache.' ;;
      04-*) seed_chart; apply_scenario -var=fault_enabled=false; wait_release workbook-04 ;;
      06-*) echo 'CRD producer remains undeployed until the missing-CRD exercise starts.' ;;
      07-*|08-*) apply_scenario -var=phase=baseline; wait_release "$([[ $workbook == 07-* ]] && echo schema-lab || echo pending-lab)" ;;
      09-*) apply_scenario -var=fault_enabled=false; bash "$root/scripts/verify.sh" "$workbook" healthy ;;
      10-*) apply_scenario -var=fault_enabled=false; bash "$root/scripts/verify.sh" "$workbook" healthy ;;
      *) apply_scenario -var=fault_enabled=false; wait_release "workbook-${workbook:0:2}" ;;
    esac
    ;;
  inject)
    case "$workbook" in
      01-*) echo 'The infrastructure DNS fault is injected from the workstation; run verify-fault.' ;;
      02-*) kubectl annotate gitrepository workbook-02 -n flux-system "reconcile.fluxcd.io/requestedAt=$(date +%s)" --overwrite ;;
      04-*) kubectl rollout restart deployment/source-controller -n flux-system; kubectl rollout status deployment/source-controller -n flux-system --timeout=5m ;;
      07-*) apply_scenario -var=phase=upgrade; wait_release schema-lab; apply_scenario -var=phase=rollback ;;
      08-*) apply_scenario -var=phase=interrupt ;;
      09-*)
        apply_scenario -var=operator_off=true -var=fault_enabled=false
        bash "$root/scripts/wait-ready.sh" kustomization/workbook-09-operator flux-system
        deadline=$((SECONDS + 180))
        until [[ -z $(kubectl get deployment cleanup-operator -n workbook-09 --ignore-not-found -o name) ]] && \
          kubectl get pods -n workbook-09 -l app=cleanup-operator -o json | jq -e '.items | length == 0' >/dev/null; do
          ((SECONDS < deadline)) || { echo 'Operator is still running; refusing to race cleanup.' >&2; exit 1; }
          sleep 5
        done
        apply_scenario -var=fault_enabled=true
        ;;
      *) apply_scenario -var=fault_enabled=true ;;
    esac
    ;;
  repair)
    case "$workbook" in
      07-*) apply_scenario -var=phase=repair; wait_release schema-lab ;;
      08-*) apply_scenario -var=phase=recover; apply_scenario -var=phase=baseline; wait_release pending-lab ;;
      *) apply_scenario -var=fault_enabled=false ;;
    esac
    ;;
  verify-fault) bash "$root/scripts/verify.sh" "$workbook" fault ;;
  verify-healthy) bash "$root/scripts/verify.sh" "$workbook" healthy ;;
  destroy)
    # Keep the finalizer controller alive until its custom resources are gone.
    # Keep helm-controller healthy until it can uninstall managed releases.
    case "$workbook" in
      08-*)
        status=$(helm status pending-lab -n workbook-08 -o json 2>/dev/null | jq -r '.info.status' || true)
        if [[ $status == pending-* ]]; then apply_scenario -var=phase=recover; fi
        apply_scenario -var=phase=baseline
        wait_release pending-lab
        ;;
      09-*|10-*) apply_scenario -var=fault_enabled=false; bash "$root/scripts/verify.sh" "$workbook" healthy ;;
    esac
    if [[ -f "$base/scenario/terraform.tfstate" ]]; then
      tf scenario destroy -input=false -auto-approve -var-file="$vars" -var="kubeconfig_path=$KUBECONFIG" -var="git_ref=${LAB_REPOSITORY_REF:-main}"
    fi
    tf bootstrap destroy -input=false -auto-approve -var-file="$vars" -var="kubeconfig_path=$KUBECONFIG"
    ;;
  *) exit 2 ;;
esac
