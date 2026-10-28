# 05 — A chart crosses the tenant service account boundary

## Scenario and learning goal

A namespaced Helm delivery account can deploy the baseline application. The fault asks that account to create a ClusterRole; Kubernetes rejects the cluster-scoped action.

Flux's trusted controller impersonates `tenant-deployer`. That account has a Role/RoleBinding only in `workbook-05`. The lab operator has separate bootstrap permissions; the tenant never receives cluster-admin.

## Deploy the isolated Azure lab

From this repository's root, follow [deployment prerequisites](../../docs/deployment.md).
This creates a complete private AKS/hub/spoke/firewall/runner environment, not a
namespace in an existing cluster. Azure charges apply throughout the exercise;
03/04 also use ACR Premium. Review regional costs and quota before applying.

```bash
cp workbooks/05-helm-rbac/infra/terraform.tfvars.example \
   workbooks/05-helm-rbac/infra/terraform.tfvars
# Edit subscription, public SSH key, location, and an available supported AKS patch.
# For an unmerged PR: export LAB_REPOSITORY_REF=THE_PR_BRANCH
bash scripts/lab.sh 05-helm-rbac deploy
```

The three Terraform roots are independent: `infra/` uses Azure ARM from your
workstation; `bootstrap/` installs Flux from the private runner; `scenario/` applies
only after the Flux APIs exist. Keep their state and the per-lab kubeconfig until
cleanup. See [state and access boundaries](../../docs/deployment.md#permissions-and-assumptions).

## Recreate the failure

`scenario/rbac.tf` and `main.tf` toggle chart-owned cluster RBAC versus platform-owned RBAC. The faulty values enable the chart ClusterRole and remove the separate platform fixture.

```bash
bash scripts/lab.sh 05-helm-rbac inject
bash scripts/lab.sh 05-helm-rbac verify-fault
```

A failing verifier means the expected evidence was not observed. Diagnose it;
do not record a reproduced incident based only on Terraform completing. On Azure,
allow for DNS, role-assignment, image-pull backoff, and controller intervals.

## Investigate from the private runner

```bash
bash scripts/lab.sh 05-helm-rbac inspect
```

Use the [approved runner access](../../docs/deployment.md#3-inject-collect-evidence-and-repair)
and its per-workbook kubeconfig. These are diagnostic observations, not permission
to change a shared production system.

- Inspect HelmRelease conditions and the exact `system:serviceaccount:workbook-05:tenant-deployer` forbidden message.
- Compare rendered values and `kubectl auth can-i --as=system:serviceaccount:workbook-05:tenant-deployer create clusterroles`.
- Inspect the namespace Role and the platform-owned ClusterRole separately.
- The denied action is expected. Do not grant an unrelated Azure management role; this is Kubernetes authorization.

## Repair and prove recovery

`repair` moves cluster-scoped ownership back to the platform Terraform resource and leaves the tenant chart namespaced. Confirm the HelmRelease succeeds while the tenant still cannot create ClusterRoles.

```bash
bash scripts/lab.sh 05-helm-rbac repair
bash scripts/lab.sh 05-helm-rbac verify-healthy
```

## Enterprise constraints and common pitfalls

An application product owner can prioritize a chart upgrade but cannot authorize new cluster-wide RBAC. Have the platform owner review shared resources. If the platform team is absent, hold the privileged part instead of widening the tenant account.

This is a minimal chart fixture, not a full Kyverno/operator installation. Least privilege must account for Helm storage and normal workload operations; arbitrary broad cluster grants conceal the failure boundary.

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
bash scripts/lab.sh 05-helm-rbac destroy
```

This restores access or controller prerequisites when needed, destroys the
scenario before Flux, then destroys Azure infrastructure. Verify the lab RG,
managed node RG, registry/private endpoint (where present), and firewall are gone.
Stopping AKS alone does not stop all charges. Do not delete the runner/state first.

## Reported basis and reproduction boundary

[Primary report or documentation](https://github.com/fluxcd/helm-controller/issues/317). Historical reports demonstrate a
failure class, not that the same defect remains in every current version. This
workbook's specific mechanism and limits are described above. No Azure deployment
or incident outcome is claimed from authoring or credential-free CI.
