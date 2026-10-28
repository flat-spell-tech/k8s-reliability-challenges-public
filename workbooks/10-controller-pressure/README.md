# 10 — CRD-heavy reconciliation under an inadequate memory limit

## Scenario and learning goal

The baseline creates bounded synthetic CRD schemas and zero-replica Helm releases. Injection lowers helm-controller's memory to 32 MiB and uses a Recreate strategy so a healthy old replica cannot mask the failure.

This deliberately recreates controller OOM and reconciliation impact. It does **not** claim the historical Helm SDK memory regression is still present. Defaults are 30 CRDs with 32 KiB descriptions and 12 releases; validation caps the exercise.

## Deploy the isolated Azure lab

From this repository's root, follow [deployment prerequisites](../../docs/deployment.md).
This creates a complete private AKS/hub/spoke/firewall/runner environment, not a
namespace in an existing cluster. Azure charges apply throughout the exercise;
03/04 also use ACR Premium. Review regional costs and quota before applying.

```bash
cp workbooks/10-controller-pressure/infra/terraform.tfvars.example \
   workbooks/10-controller-pressure/infra/terraform.tfvars
# Edit subscription, public SSH key, location, and an available supported AKS patch.
# For an unmerged PR: export LAB_REPOSITORY_REF=THE_PR_BRANCH
bash scripts/lab.sh 10-controller-pressure deploy
```

The three Terraform roots are independent: `infra/` uses Azure ARM from your
workstation; `bootstrap/` installs Flux from the private runner; `scenario/` applies
only after the Flux APIs exist. Keep their state and the per-lab kubeconfig until
cleanup. See [state and access boundaries](../../docs/deployment.md#permissions-and-assumptions).

## Recreate the failure

`scenario/main.tf` manages the synthetic APIs/releases. `scripts/set-controller-limit.sh` changes only the lab-owned controller. The fault must show an actual OOMKilled reason to pass verification.

```bash
bash scripts/lab.sh 10-controller-pressure inject
bash scripts/lab.sh 10-controller-pressure verify-fault
```

A failing verifier means the expected evidence was not observed. Diagnose it;
do not record a reproduced incident based only on Terraform completing. On Azure,
allow for DNS, role-assignment, image-pull backoff, and controller intervals.

## Investigate from the private runner

```bash
bash scripts/lab.sh 10-controller-pressure inspect
```

Use the [approved runner access](../../docs/deployment.md#3-inject-collect-evidence-and-repair)
and its per-workbook kubeconfig. These are diagnostic observations, not permission
to change a shared production system.

- Inspect controller container last termination reason, restart count, requests/limits, and Deployment availability.
- Inspect HelmRelease readiness and observed generations; old Ready conditions are not proof a new revision reconciled.
- Compare discovery/schema load and resource constraints without inferring an exponential leak from one snapshot.
- The zero-replica fixture releases avoid consuming an application-pod fleet while exercising chart reconciliation.

## Repair and prove recovery

`repair` restores 512 MiB, waits for controller availability, and restores a rolling update strategy. Require every fixture HelmRelease's current generation to become Ready. Real production sizing must be measured; 512 MiB is a lab recovery value, not a universal recommendation.

```bash
bash scripts/lab.sh 10-controller-pressure repair
bash scripts/lab.sh 10-controller-pressure verify-healthy
```

## Enterprise constraints and common pitfalls

Raise a bounded resource request with platform ownership and measured evidence. A product team can prioritize the fix but cannot silently remove all resource constraints across the cluster. Keep the temporary controller-availability watch until recovery is proven.

Recreate is deliberately used to expose the failure, not recommended as a general production rollout strategy. Synthetic descriptions plus an explicit low cap model pressure, not the exact allocation profile from the 2024 report.

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
bash scripts/lab.sh 10-controller-pressure destroy
```

This restores access or controller prerequisites when needed, destroys the
scenario before Flux, then destroys Azure infrastructure. Verify the lab RG,
managed node RG, registry/private endpoint (where present), and firewall are gone.
Stopping AKS alone does not stop all charges. Do not delete the runner/state first.

## Reported basis and reproduction boundary

[Primary report or documentation](https://github.com/fluxcd/helm-controller/issues/923). Historical reports demonstrate a
failure class, not that the same defect remains in every current version. This
workbook's specific mechanism and limits are described above. No Azure deployment
or incident outcome is claimed from authoring or credential-free CI.
