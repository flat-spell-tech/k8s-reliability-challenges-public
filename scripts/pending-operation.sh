#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$here/assert-context.sh"
mkdir -p "${WORKBOOK_DIR:?}/.lab"
revision_file="$WORKBOOK_DIR/.lab/good-revision"
case "${1:?interrupt or recover}" in
  interrupt)
    [[ $(helm status pending-lab -n workbook-08 -o json | jq -r '.info.status') == deployed ]] || {
      echo 'Start from a deployed baseline. Recover an existing interruption first.' >&2; exit 1;
    }
    helm history pending-lab -n workbook-08 -o json | jq -er '[.[] | select(.status == "deployed")] | last | .revision' > "$revision_file"
    # SIGKILL interrupts the client while Helm has persisted pending-upgrade.
    # A real pre-upgrade Job keeps the transaction waiting; no storage Secret is forged.
    result=0
    timeout --signal=KILL 8s helm upgrade pending-lab "$here/../fixtures/charts/workbook" \
      -n workbook-08 --set blocker.enabled=true --wait --timeout=30m || result=$?
    [[ $result == 137 || $result == 124 ]] || { echo "Unexpected Helm exit: $result" >&2; exit 1; }
    status=$(helm status pending-lab -n workbook-08 -o json | jq -r '.info.status')
    [[ "$status" == pending-upgrade ]] || { echo "Expected pending-upgrade, observed $status" >&2; exit 1; }
    echo 'Confirmed genuine interrupted pending-upgrade state.'
    ;;
  recover)
    revision=$(cat "$revision_file")
    [[ "$revision" =~ ^[0-9]+$ ]] || { echo 'Missing known-good revision.' >&2; exit 1; }
    helm rollback pending-lab "$revision" -n workbook-08 --wait --timeout=5m
    kubectl delete job pending-lab-blocker -n workbook-08 --ignore-not-found
    [[ $(helm status pending-lab -n workbook-08 -o json | jq -r '.info.status') == deployed ]]
    ;;
  *) exit 2 ;;
esac
