# 07 — A desired-chart rollback leaves an incompatible CRD

## Scenario and learning goal

The baseline chart accepts `legacy`; the upgrade installs a schema accepting only `modern`. A Git-style rollback requests the original chart while explicitly skipping CRD replacement, so the old custom resource is rejected.

This models chart/schema skew with a small real CRD and real Helm actions. It is not a full operator data-conversion test, and the rollback phase is a desired-chart downgrade through Flux rather than a native `helm rollback` command.

## Deploy the isolated Azure lab

From this repository's root, follow [deployment prerequisites](../../docs/deployment.md).
This creates a complete private AKS/hub/spoke/firewall/runner environment, not a
namespace in an existing cluster. Azure charges apply throughout the exercise;
03/04 also use ACR Premium. Review regional costs and quota before applying.

```bash
cp workbooks/07-crd-lifecycle/infra/terraform.tfvars.example \
   workbooks/07-crd-lifecycle/infra/terraform.tfvars
# Edit subscription, public SSH key, location, and an available supported AKS patch.
# For an unmerged PR: export LAB_REPOSITORY_REF=THE_PR_BRANCH
bash scripts/lab.sh 07-crd-lifecycle deploy
```

The three Terraform roots are independent: `infra/` uses Azure ARM from your
workstation; `bootstrap/` installs Flux from the private runner; `scenario/` applies
only after the Flux APIs exist. Keep their state and the per-lab kubeconfig until
cleanup. See [state and access boundaries](../../docs/deployment.md#permissions-and-assumptions).

## Recreate the failure

`scenario/phases.tf` selects baseline, upgrade, rollback, or repair chart paths and an explicit CRD policy. `inject` waits for the upgrade's observed generation before applying the rollback, so a stale Ready condition cannot skip the transition.

```bash
bash scripts/lab.sh 07-crd-lifecycle inject
bash scripts/lab.sh 07-crd-lifecycle verify-fault
```

A failing verifier means the expected evidence was not observed. Diagnose it;
do not record a reproduced incident based only on Terraform completing. On Azure,
allow for DNS, role-assignment, image-pull backoff, and controller intervals.

## Investigate from the private runner

```bash
bash scripts/lab.sh 07-crd-lifecycle inspect
```

Use the [approved runner access](../../docs/deployment.md#3-inject-collect-evidence-and-repair)
and its per-workbook kubeconfig. These are diagnostic observations, not permission
to change a shared production system.

- Read the HelmRelease conditions, attempted chart revision, and CRD enum.
- Inspect `schemarecord example -n workbook-07`: after the upgrade its mode is `modern`.
- During failure, the CRD still accepts only `modern` while the old chart requests `legacy`.
- Check the actual Flux release's CRD policy; defaults differ across versions. Do not infer schema rollback from a chart rollback.

## Repair and prove recovery

`repair` deploys a compatibility chart whose CRD accepts both forms and whose example uses `legacy`. Require both Helm readiness and the actual stored mode. Production migrations also need storage-version/conversion and backup review beyond this fixture.

```bash
bash scripts/lab.sh 07-crd-lifecycle repair
bash scripts/lab.sh 07-crd-lifecycle verify-healthy
```

## Enterprise constraints and common pitfalls

The operator owner, data owner, and product risk authority must agree compatibility and reconciliation. An urgent launch decision cannot make irreversible writes reversible. Retain the temporary feature/intake restriction while a compatible fix is tested.

Follow the full baseline → upgrade → rollback → repair sequence. This is an explicit lifecycle-policy exercise, not a claim that every Flux release skips CRD upgrades or that schemas should always be automatically downgraded.

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
bash scripts/lab.sh 07-crd-lifecycle destroy
```

This restores access or controller prerequisites when needed, destroys the
scenario before Flux, then destroys Azure infrastructure. Verify the lab RG,
managed node RG, registry/private endpoint (where present), and firewall are gone.
Stopping AKS alone does not stop all charges. Do not delete the runner/state first.

## Reported basis and reproduction boundary

[Primary report or documentation](https://github.com/fluxcd/helm-controller/issues/1524). Historical reports demonstrate a
failure class, not that the same defect remains in every current version. This
workbook's specific mechanism and limits are described above. No Azure deployment
or incident outcome is claimed from authoring or credential-free CI.
