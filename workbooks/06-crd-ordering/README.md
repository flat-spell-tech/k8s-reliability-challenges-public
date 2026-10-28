# 06 — Custom resources reconcile before the CRD producer

## Scenario and learning goal

A real Flux Kustomization attempts to apply a Widget while the Kustomization that registers its CRD is suspended. Kubernetes cannot map that API kind.

The custom resource is applied by Flux, not planned as a native Terraform custom-resource manifest. This preserves a deployable Terraform plan even when the lab's Widget API intentionally does not exist.

## Deploy the isolated Azure lab

From this repository's root, follow [deployment prerequisites](../../docs/deployment.md).
This creates a complete private AKS/hub/spoke/firewall/runner environment, not a
namespace in an existing cluster. Azure charges apply throughout the exercise;
03/04 also use ACR Premium. Review regional costs and quota before applying.

```bash
cp workbooks/06-crd-ordering/infra/terraform.tfvars.example \
   workbooks/06-crd-ordering/infra/terraform.tfvars
# Edit subscription, public SSH key, location, and an available supported AKS patch.
# For an unmerged PR: export LAB_REPOSITORY_REF=THE_PR_BRANCH
bash scripts/lab.sh 06-crd-ordering deploy
```

The three Terraform roots are independent: `infra/` uses Azure ARM from your
workstation; `bootstrap/` installs Flux from the private runner; `scenario/` applies
only after the Flux APIs exist. Keep their state and the per-lab kubeconfig until
cleanup. See [state and access boundaries](../../docs/deployment.md#permissions-and-assumptions).

## Recreate the failure

`scenario/main.tf` suspends the CRD producer and removes the consumer's Flux dependency. `deploy` intentionally defers both until injection, avoiding an already-installed CRD masking the fault.

```bash
bash scripts/lab.sh 06-crd-ordering inject
bash scripts/lab.sh 06-crd-ordering verify-fault
```

A failing verifier means the expected evidence was not observed. Diagnose it;
do not record a reproduced incident based only on Terraform completing. On Azure,
allow for DNS, role-assignment, image-pull backoff, and controller intervals.

## Investigate from the private runner

```bash
bash scripts/lab.sh 06-crd-ordering inspect
```

Use the [approved runner access](../../docs/deployment.md#3-inject-collect-evidence-and-repair)
and its per-workbook kubeconfig. These are diagnostic observations, not permission
to change a shared production system.

- Inspect `workbook-06-crds` and `workbook-06-instances` Kustomizations in `flux-system`.
- Confirm `widgets.reliability.flatspell.io` is absent, then capture the no-matches/REST-mapping failure.
- Distinguish CRD establishment from operator/webhook readiness; this fixture covers CRD availability only.
- Terraform resource ordering alone cannot guarantee asynchronous Flux controller readiness.

## Repair and prove recovery

`repair` unsuspends the producer and restores `dependsOn`. The producer waits for CRD readiness; only then can the consumer apply the Widget. Require the actual `ordered-widget` object to exist.

```bash
bash scripts/lab.sh 06-crd-ordering repair
bash scripts/lab.sh 06-crd-ordering verify-healthy
```

## Enterprise constraints and common pitfalls

If the platform/operator team owns CRDs, obtain a producer release and readiness contract instead of asking tenant teams to copy CRDs into application charts. A missing approver should remain a tracked dependency.

Use a fresh lab for fault reproduction. After repair the CRD remains installed; merely resuspending its producer will not delete it. Do not delete arbitrary shared CRDs to force a demonstration.

## Incident lifecycle and operating handoff

Use the [incident record](../../docs/incident-record.md). Capture the exact bad
state, competing hypothesis, authorized mitigation, observed recovery, and causal
fix. Link implementation/deployment evidence before marking the fix verified.
Assign an early-warning owner for this mechanism and a review date for temporary
watches. Retire a temporary watch only after replacement coverage or prevention
passes; retain normal SLO monitoring. Escalate delayed fixes and transfer ownership
explicitly if the product owner or receiving team changes.

## Cleanup

```bash
bash scripts/lab.sh 06-crd-ordering destroy
```

This restores access or controller prerequisites when needed, destroys the
scenario before Flux, then destroys Azure infrastructure. Verify the lab RG,
managed node RG, registry/private endpoint (where present), and firewall are gone.
Stopping AKS alone does not stop all charges. Do not delete the runner/state first.

## Reported basis and reproduction boundary

[Primary report or documentation](https://github.com/fluxcd/kustomize-controller/blob/main/docs/spec/v1/kustomizations.md#dependencies). Historical reports demonstrate a
failure class, not that the same defect remains in every current version. This
workbook's specific mechanism and limits are described above. No Azure deployment
or incident outcome is claimed from authoring or credential-free CI.
