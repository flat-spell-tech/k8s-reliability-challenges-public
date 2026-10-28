#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
workbook=${1:?workbook directory name}
action=${2:?setup, baseline, inject, repair, verify-fault, verify-healthy, or destroy}
[[ "$workbook" =~ ^(0[1-9]|10)-[a-z-]+$ && -d "$root/workbooks/$workbook" ]] || exit 2
case "$action" in setup|baseline|inject|inspect|repair|verify-fault|verify-healthy|destroy) ;; *) exit 2 ;; esac
ref=${LAB_REPOSITORY_REF:-main}
[[ "$ref" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ && "$ref" != *..* ]] || { echo 'Invalid repository ref.' >&2; exit 2; }
verify_timeout=${VERIFY_TIMEOUT_SECONDS:-600}
[[ "$verify_timeout" =~ ^[0-9]+$ && $verify_timeout -ge 10 && $verify_timeout -le 1800 ]] || exit 2
mkdir -p "$root/.lab/$workbook"
chmod 700 "$root/.lab"
terraform -chdir="$root/workbooks/$workbook/infra" output -json connection > "$root/.lab/$workbook/connection.json"
config="$root/.lab/$workbook/connection.json"
payload=$(base64 < "$config" | tr -d '\n')
group=$(jq -er .resource_group "$config")
runner=$(jq -er .runner_name "$config")
# Values interpolated into the remote shell are either base64 or constrained
# tokens above. No credentials, kubeconfigs, or SAS tokens cross this channel.
remote="set -eu
cloud-init status --wait
repo=/opt/k8s-reliability-challenges-public
if [ ! -d \"\$repo/.git\" ]; then
  git clone --branch '$ref' https://github.com/flat-spell-tech/k8s-reliability-challenges-public.git \"\$repo\"
fi
cd \"\$repo\"
if [ -n \"\$(git status --porcelain)\" ]; then echo 'Preserve runner edits before changing revisions.' >&2; exit 1; fi
git fetch origin '$ref'
git checkout --detach FETCH_HEAD
mkdir -p '.lab/$workbook'
chmod 700 .lab '.lab/$workbook'
printf '%s' '$payload' | base64 -d > '.lab/$workbook/connection.json'
export LAB_REPOSITORY_REF='$ref'
export VERIFY_TIMEOUT_SECONDS='$verify_timeout'
bash scripts/runner.sh '$workbook' '$action'
printf '\\nLAB_ACTION_OK:$workbook:$action\\n' >&2"
reply=$(mktemp)
trap 'rm -f "$reply"' EXIT
az vm run-command invoke --resource-group "$group" --name "$runner" \
  --command-id RunShellScript --scripts "$remote" -o json > "$reply"
python3 - "$reply" "$workbook" "$action" <<'PY'
import json,sys
with open(sys.argv[1]) as source: response=json.load(source)
messages=[v.get('message','') for v in response.get('value',[])]
for message in messages: print(message)
sentinel=f'LAB_ACTION_OK:{sys.argv[2]}:{sys.argv[3]}'
if not any(sentinel in message.splitlines() for message in messages):
    raise SystemExit('Remote action failed or output was truncated; inspect Run Command and runner logs. No success sentinel received.')
PY
