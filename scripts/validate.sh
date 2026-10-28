#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
terraform fmt -check -recursive
for script in scripts/*.sh; do bash -n "$script"; done
python3 -B -m unittest discover -s tests -v
for chart in fixtures/charts/*; do
  helm lint "$chart"
  helm template fixture "$chart" --include-crds >/dev/null
done
for directory in fixtures/crd-order/* fixtures/finalizers/* fixtures/empty; do
  kubectl kustomize "$directory" >/dev/null
done
# Terraform's shared plugin cache is not safe for concurrent writers. Validate
# sequentially so separate roots cannot corrupt each other's provider packages.
for directory in modules/azure-lab modules/flux-app modules/flux-bootstrap workbooks/*/{infra,bootstrap,scenario}; do
  terraform -chdir="$directory" init -backend=false -input=false
  terraform -chdir="$directory" validate
done
terraform -chdir=modules/azure-lab test
