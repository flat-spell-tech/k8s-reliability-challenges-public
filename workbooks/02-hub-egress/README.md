# 02 — Flux source fetch fails behind the hub firewall

## Scenario and learning goal

Existing application pods remain up, but Flux stops advancing Git artifacts. A higher-priority firewall application deny blocks GitHub HTTPS from the spoke, while the hub runner retains access.

AKS and the management runner are deliberately on different traffic paths. The baseline permits web egress; injection denies the repository host for nodes/Flux, not every Azure dependency.

## Deploy the isolated Azure lab

From this repository's root, follow [deployment prerequisites](../../docs/deployment.md).
This creates a complete private AKS/hub/spoke/firewall/runner environment, not a
namespace in an existing cluster. Azure charges apply throughout the exercise;
03/04 also use ACR Premium. Review regional costs and quota before applying.

```bash
cp workbooks/02-hub-egress/infra/terraform.tfvars.example \
   workbooks/02-hub-egress/infra/terraform.tfvars
# Edit subscription, public SSH key, location, and an available supported AKS patch.
# For an unmerged PR: export LAB_REPOSITORY_REF=THE_PR_BRANCH
bash scripts/lab.sh 02-hub-egress deploy
```

The three Terraform roots are independent: `infra/` uses Azure ARM from your
workstation; `bootstrap/` installs Flux from the private runner; `scenario/` applies
only after the Flux APIs exist. Keep their state and the per-lab kubeconfig until
cleanup. See [state and access boundaries](../../docs/deployment.md#permissions-and-assumptions).

## Recreate the failure

`infra/main.tf` sets `block_git_egress=true`. The actual `GitRepository` attempts a new fetch, which must fail before the workbook can claim reproduction.

```bash
bash scripts/lab.sh 02-hub-egress inject
bash scripts/lab.sh 02-hub-egress verify-fault
```

A failing verifier means the expected evidence was not observed. Diagnose it;
do not record a reproduced incident based only on Terraform completing. On Azure,
allow for DNS, role-assignment, image-pull backoff, and controller intervals.

## Investigate from the private runner

```bash
bash scripts/lab.sh 02-hub-egress inspect
```

Use the [approved runner access](../../docs/deployment.md#3-inject-collect-evidence-and-repair)
and its per-workbook kubeconfig. These are diagnostic observations, not permission
to change a shared production system.

- Inspect `kubectl get gitrepository workbook-02 -n flux-system -o yaml` and source-controller logs.
- Compare the artifact revision/time with the branch head. A previously ready HelmRelease or running Deployment may still use the cached artifact.
- Inspect the firewall deny collection from Azure ARM; its priority is ahead of the wildcard lab web allow.
- A successful `git fetch` on the hub runner is not a successful test from a Flux pod in the spoke.

## Repair and prove recovery

`repair` removes the scoped deny, then applies/reconciles the healthy scenario. `verify-healthy` requires the HelmRelease current generation to be ready.

```bash
bash scripts/lab.sh 02-hub-egress repair
bash scripts/lab.sh 02-hub-egress verify-healthy
```

## Enterprise constraints and common pitfalls

If InfoSec will not approve broad egress, provide the precise repository/auth/artifact destinations and response evidence for a scoped review. Preserve the cached running service while the deployment path is repaired.

Artifact caching can make the application look healthy after the Git source fails. There is no controller outage required. The lab recreates restricted-egress behavior, not every proxy/TLS-interception cause in the historical report.

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
bash scripts/lab.sh 02-hub-egress destroy
```

This restores access or controller prerequisites when needed, destroys the
scenario before Flux, then destroys Azure infrastructure. Verify the lab RG,
managed node RG, registry/private endpoint (where present), and firewall are gone.
Stopping AKS alone does not stop all charges. Do not delete the runner/state first.

## Reported basis and reproduction boundary

[Primary report or documentation](https://github.com/fluxcd/source-controller/issues/1485). Historical reports demonstrate a
failure class, not that the same defect remains in every current version. This
workbook's specific mechanism and limits are described above. No Azure deployment
or incident outcome is claimed from authoring or credential-free CI.
