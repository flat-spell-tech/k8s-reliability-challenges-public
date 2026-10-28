#!/usr/bin/env bash
set -euo pipefail
workbook=${1:?}
mode=${2:?fault or healthy}
[[ $mode == fault || $mode == healthy ]] || exit 2
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bash "$root/scripts/assert-context.sh"
kubectl get namespace flux-system --request-timeout=15s >/dev/null # An API/RBAC outage must not pass as an application fault.
timeout=${VERIFY_TIMEOUT_SECONDS:-600}
[[ "$timeout" =~ ^[0-9]+$ && $timeout -ge 10 && $timeout -le 1800 ]] || exit 2
ns="workbook-${workbook:0:2}"
ready() {
  kubectl get "$1" -n "$2" -o json | jq -e '
    .status.observedGeneration == .metadata.generation and
    any(.status.conditions[]?; .type == "Ready" and .status == "True")' >/dev/null
}
not_ready() {
  kubectl get "$1" -n "$2" -o json | jq -e --arg pattern "$3" '
    any(.status.conditions[]?; .type == "Ready" and .status == "False" and
      (.message | test($pattern; "i")))' >/dev/null
}
check() {
  case "$workbook:$mode" in
    01-*:healthy) getent ahostsv4 "$LAB_PRIVATE_FQDN" >/dev/null && kubectl get nodes >/dev/null ;;
    02-*:fault) not_ready gitrepository/workbook-02 flux-system 'clone|fetch|timeout|failed|denied' ;;
    03-*:fault)
      getent ahostsv4 "$(jq -r .acr_login_server "$root/.lab/$workbook/connection.json")" >/dev/null || return 1
      local acr location
      acr=$(jq -r .acr_name "$root/.lab/$workbook/connection.json")
      location=$(jq -r .location "$root/.lab/$workbook/connection.json")
      if getent ahostsv4 "$acr.$location.data.azurecr.io" >/dev/null; then return 1; fi
      kubectl get pods -n "$ns" -o json | jq -e 'any(.items[].status.containerStatuses[]?; .state.waiting.reason == "ImagePullBackOff" or .state.waiting.reason == "ErrImagePull")' >/dev/null
      ;;
    04-*:fault) not_ready ocirepository/workbook-04 flux-system '401|403|denied|unauthori|credential|authentication' ;;
    05-*:fault) not_ready helmrelease/workbook-05 "$ns" 'forbidden|cannot.*clusterrole' ;;
    06-*:fault)
      [[ -z $(kubectl get crd widgets.reliability.flatspell.io --ignore-not-found -o name) ]] &&
        not_ready kustomization/workbook-06-instances flux-system 'no matches|not found|failed to get restmapping'
      ;;
    06-*:healthy)
      ready kustomization/workbook-06-instances flux-system &&
        kubectl get widgets.reliability.flatspell.io ordered-widget -n "$ns" >/dev/null
      ;;
    07-*:fault)
      kubectl get crd schemarecords.schema.reliability.flatspell.io -o json | \
        jq -e '.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.mode.enum == ["modern"]' >/dev/null &&
        not_ready helmrelease/schema-lab "$ns" 'Unsupported value|not supported|invalid|legacy'
      ;;
    07-*:healthy)
      ready helmrelease/schema-lab "$ns" && kubectl get schemarecord example -n "$ns" -o json | jq -e '.spec.mode == "legacy"' >/dev/null
      ;;
    08-*:fault) [[ $(helm status pending-lab -n "$ns" -o json | jq -r '.info.status') == pending-upgrade ]] ;;
    08-*:healthy) ready helmrelease/pending-lab "$ns" && [[ $(helm status pending-lab -n "$ns" -o json | jq -r '.info.status') == deployed ]] ;;
    09-*:fault)
      [[ -z $(kubectl get deployment cleanup-operator -n "$ns" --ignore-not-found -o name) ]] &&
        kubectl get cleanuptask example -n "$ns" -o json | jq -e '
          .metadata.deletionTimestamp != null and
          (.metadata.finalizers | index("cleanup.reliability.flatspell.io/allocation")) != null' >/dev/null
      ;;
    09-*:healthy)
      ready kustomization/workbook-09-operator flux-system &&
        kubectl get cleanuptask example -n "$ns" -o json | jq -e '
          .metadata.deletionTimestamp == null and
          (.metadata.finalizers | index("cleanup.reliability.flatspell.io/allocation")) != null' >/dev/null &&
        [[ $(kubectl get configmap allocation-example -n "$ns" -o jsonpath='{.metadata.labels.allocation-owner}') == \
           "$(kubectl get cleanuptask example -n "$ns" -o jsonpath='{.metadata.uid}')" ]]
      ;;
    10-*:fault)
      kubectl get pods -n flux-system -l app=helm-controller -o json | jq -e '
        any(.items[].status.containerStatuses[]?; .lastState.terminated.reason == "OOMKilled" or .state.terminated.reason == "OOMKilled")' >/dev/null
      ;;
    10-*:healthy)
      kubectl get deployment helm-controller -n flux-system -o json | jq -e '.status.availableReplicas >= 1' >/dev/null &&
        kubectl get helmreleases -n "$ns" -o json | jq -e '.items | length > 0 and all(.[]; .status.observedGeneration == .metadata.generation and any(.status.conditions[]?; .type=="Ready" and .status=="True"))' >/dev/null
      ;;
    *:healthy) ready "helmrelease/workbook-${workbook:0:2}" "$ns" ;;
    *) echo 'Unknown verification case.' >&2; return 2 ;;
  esac
}
end=$((SECONDS + timeout))
until check; do
  if ((SECONDS >= end)); then
    echo "FAIL: expected $mode evidence was not observed; do not treat an unverified fault as reproduced." >&2
    kubectl get pods -n "$ns" -o wide || true
    kubectl get helmreleases,kustomizations,gitrepositories,ocirepositories -A || true
    exit 1
  fi
  sleep 5
done
echo "PASS: $workbook $mode evidence observed."
