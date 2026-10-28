# 04 — Kubelet pulls images while Flux cannot pull OCI charts

## Scenario and learning goal

Flux cannot fetch its OCI Helm chart even though the node identity still has AcrPull. A separate Entra workload identity is federated to source-controller; injection removes only that principal's ACR pull role.

The private registry, DNS, federated issuer/subject, and kubelet role stay healthy. The runner has a distinct scoped push identity for seeding the chart. A valid token is not the same as authorization to pull the artifact.

## Deploy the isolated Azure lab

From this repository's root, follow [deployment prerequisites](../../docs/deployment.md).
This creates a complete private AKS/hub/spoke/firewall/runner environment, not a
namespace in an existing cluster. Azure charges apply throughout the exercise;
03/04 also use ACR Premium. Review regional costs and quota before applying.

```bash
cp workbooks/04-flux-azure-identity/infra/terraform.tfvars.example \
   workbooks/04-flux-azure-identity/infra/terraform.tfvars
# Edit subscription, public SSH key, location, and an available supported AKS patch.
# For an unmerged PR: export LAB_REPOSITORY_REF=THE_PR_BRANCH
bash scripts/lab.sh 04-flux-azure-identity deploy
```

The three Terraform roots are independent: `infra/` uses Azure ARM from your
workstation; `bootstrap/` installs Flux from the private runner; `scenario/` applies
only after the Flux APIs exist. Keep their state and the per-lab kubeconfig until
cleanup. See [state and access boundaries](../../docs/deployment.md#permissions-and-assumptions).

## Recreate the failure

`infra/main.tf` maps the fault to `grant_flux_acr_pull=false`. The helper restarts source-controller to clear local cached credentials; Azure role/token propagation can still take additional time.

```bash
bash scripts/lab.sh 04-flux-azure-identity inject
bash scripts/lab.sh 04-flux-azure-identity verify-fault
```

A failing verifier means the expected evidence was not observed. Diagnose it;
do not record a reproduced incident based only on Terraform completing. On Azure,
allow for DNS, role-assignment, image-pull backoff, and controller intervals.

## Investigate from the private runner

```bash
bash scripts/lab.sh 04-flux-azure-identity inspect
```

Use the [approved runner access](../../docs/deployment.md#3-inject-collect-evidence-and-repair)
and its per-workbook kubeconfig. These are diagnostic observations, not permission
to change a shared production system.

- Inspect `OCIRepository/workbook-04` in `flux-system` for the precise authentication/authorization error.
- Compare the source-controller ServiceAccount client-ID annotation and pod workload-identity label with the federated credential subject.
- Compare kubelet, runner, and Flux principals; they are not interchangeable.
- An AADSTS issuer/subject/audience error is a different failure from the intended missing registry role. If that occurs during baseline, correct federation before attempting this lab.

## Repair and prove recovery

`repair` restores AcrPull only at this registry for the Flux identity. Reconcile after propagation; require OCI retrieval and current-generation Helm readiness. Do not repair it with subscription Contributor or registry admin passwords.

```bash
bash scripts/lab.sh 04-flux-azure-identity repair
bash scripts/lab.sh 04-flux-azure-identity verify-healthy
```

## Enterprise constraints and common pitfalls

Ask the identity owner for the exact principal/scope/role change. If the owner is unreachable, use an approved delegate and preserve the running workload. A SAS/password workaround would change the trust model and is not the documented fix.

Azure role changes and cached registry credentials are eventually visible. Do not claim reproduction until a real source failure is observed; a missing role in Terraform alone is insufficient. This workbook does not reproduce every SDK credential-chain bug in the linked reports.

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
bash scripts/lab.sh 04-flux-azure-identity destroy
```

This restores access or controller prerequisites when needed, destroys the
scenario before Flux, then destroys Azure infrastructure. Verify the lab RG,
managed node RG, registry/private endpoint (where present), and firewall are gone.
Stopping AKS alone does not stop all charges. Do not delete the runner/state first.

## Reported basis and reproduction boundary

[Primary report or documentation](https://github.com/fluxcd/source-controller/issues/898). Historical reports demonstrate a
failure class, not that the same defect remains in every current version. This
workbook's specific mechanism and limits are described above. No Azure deployment
or incident outcome is claimed from authoring or credential-free CI.
