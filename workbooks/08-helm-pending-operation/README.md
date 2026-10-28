# 08 — Interrupt a Helm upgrade during a waiting hook

## Scenario and learning goal

A genuine Helm upgrade persists `pending-upgrade` and then its client is killed while a pre-upgrade Job waits. The previous deployed revision is recorded before interruption.

Terraform suspends the lab HelmRelease before invoking the controlled interruption. No Helm Secret is forged or deleted. Suspension keeps the evidence stable; modern Flux may automatically remediate interrupted operations if later resumed.

## Deploy the isolated Azure lab

From this repository's root, follow [deployment prerequisites](../../docs/deployment.md).
This creates a complete private AKS/hub/spoke/firewall/runner environment, not a
namespace in an existing cluster. Azure charges apply throughout the exercise;
03/04 also use ACR Premium. Review regional costs and quota before applying.

```bash
cp workbooks/08-helm-pending-operation/infra/terraform.tfvars.example \
   workbooks/08-helm-pending-operation/infra/terraform.tfvars
# Edit subscription, public SSH key, location, and an available supported AKS patch.
# For an unmerged PR: export LAB_REPOSITORY_REF=THE_PR_BRANCH
bash scripts/lab.sh 08-helm-pending-operation deploy
```

The three Terraform roots are independent: `infra/` uses Azure ARM from your
workstation; `bootstrap/` installs Flux from the private runner; `scenario/` applies
only after the Flux APIs exist. Keep their state and the per-lab kubeconfig until
cleanup. See [state and access boundaries](../../docs/deployment.md#permissions-and-assumptions).

## Recreate the failure

`scenario/phases.tf` runs `scripts/pending-operation.sh`. An eight-second client interruption is accepted only if Helm actually reports pending-upgrade; an unrelated command failure makes the Terraform action fail.

```bash
bash scripts/lab.sh 08-helm-pending-operation inject
bash scripts/lab.sh 08-helm-pending-operation verify-fault
```

A failing verifier means the expected evidence was not observed. Diagnose it;
do not record a reproduced incident based only on Terraform completing. On Azure,
allow for DNS, role-assignment, image-pull backoff, and controller intervals.

## Investigate from the private runner

```bash
bash scripts/lab.sh 08-helm-pending-operation inspect
```

Use the [approved runner access](../../docs/deployment.md#3-inject-collect-evidence-and-repair)
and its per-workbook kubeconfig. These are diagnostic observations, not permission
to change a shared production system.

- Inspect `helm status pending-lab -n workbook-08 -o json` and Helm history.
- Inspect the real `pending-lab-blocker` pre-upgrade Job.
- A second manual upgrade will encounter Helm's operation guard while this state remains pending.
- Observe current Flux behavior separately; do not assume the historical indefinite-stall bug remains in the pinned controller.

## Repair and prove recovery

`repair` uses the saved known-good deployed revision for a real Helm rollback, deletes only the named fixture hook Job, then returns the HelmRelease to normal Flux reconciliation. Require deployed Helm status and current-generation Ready.

```bash
bash scripts/lab.sh 08-helm-pending-operation repair
bash scripts/lab.sh 08-helm-pending-operation verify-healthy
```

## Enterprise constraints and common pitfalls

If the release operator is unavailable, preserve history and ask the authorized backup to execute the reviewed recovery. Deleting release storage to clear a lock can discard ownership and make the next recovery harder.

Use baseline before interruption. Preserve the runner's `.lab/good-revision` record. Helm state/history may include operational metadata, so keep exports in the approved evidence boundary. Current automatic remediation is an observation, not a failed historical-bug claim.

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
bash scripts/lab.sh 08-helm-pending-operation destroy
```

This restores access or controller prerequisites when needed, destroys the
scenario before Flux, then destroys Azure infrastructure. Verify the lab RG,
managed node RG, registry/private endpoint (where present), and firewall are gone.
Stopping AKS alone does not stop all charges. Do not delete the runner/state first.

## Reported basis and reproduction boundary

[Primary report or documentation](https://github.com/fluxcd/helm-controller/issues/149). Historical reports demonstrate a
failure class, not that the same defect remains in every current version. This
workbook's specific mechanism and limits are described above. No Azure deployment
or incident outcome is claimed from authoring or credential-free CI.
