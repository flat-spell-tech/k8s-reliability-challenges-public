# 09 — Remove the operator before its finalizer finishes

## Scenario and learning goal

The baseline deploys a small cleanup controller, CRD, and CleanupTask. Injection changes operator and usage sources to an empty path. The operator disappears before the custom resource's deletion can complete.

The finalizer and Kubernetes API deletion are real. A namespaced ConfigMap models an external allocation; the controller never creates or deletes Azure resources. Marker ownership is checked by custom-resource UID before cleanup.

## Deploy the isolated Azure lab

From this repository's root, follow [deployment prerequisites](../../docs/deployment.md).
This creates a complete private AKS/hub/spoke/firewall/runner environment, not a
namespace in an existing cluster. Azure charges apply throughout the exercise;
03/04 also use ACR Premium. Review regional costs and quota before applying.

```bash
cp workbooks/09-operator-finalizers/infra/terraform.tfvars.example \
   workbooks/09-operator-finalizers/infra/terraform.tfvars
# Edit subscription, public SSH key, location, and an available supported AKS patch.
# For an unmerged PR: export LAB_REPOSITORY_REF=THE_PR_BRANCH
bash scripts/lab.sh 09-operator-finalizers deploy
```

The three Terraform roots are independent: `infra/` uses Azure ARM from your
workstation; `bootstrap/` installs Flux from the private runner; `scenario/` applies
only after the Flux APIs exist. Keep their state and the per-lab kubeconfig until
cleanup. See [state and access boundaries](../../docs/deployment.md#permissions-and-assumptions).

## Recreate the failure

`scenario/main.tf` changes the Flux paths while retaining the CRD. The helper first sets `operator_off=true` and waits for the operator Deployment and pods to disappear, then sets `fault_enabled=true` to prune the custom resource. This makes the missing-cleanup-controller state reproducible instead of racing its last reconcile. Healthy Terraform destroy has explicit reverse resource dependencies.

```bash
bash scripts/lab.sh 09-operator-finalizers inject
bash scripts/lab.sh 09-operator-finalizers verify-fault
```

A failing verifier means the expected evidence was not observed. Diagnose it;
do not record a reproduced incident based only on Terraform completing. On Azure,
allow for DNS, role-assignment, image-pull backoff, and controller intervals.

## Investigate from the private runner

```bash
bash scripts/lab.sh 09-operator-finalizers inspect
```

Use the [approved runner access](../../docs/deployment.md#3-inject-collect-evidence-and-repair)
and its per-workbook kubeconfig. These are diagnostic observations, not permission
to change a shared production system.

- Inspect `cleanuptask example -n workbook-09`: deletionTimestamp is set and the cleanup finalizer remains.
- Confirm `deployment/cleanup-operator` is gone and inspect `configmap/allocation-example`.
- Read Flux inventory and pruning events; a Kustomization's status alone is not proof external cleanup completed.
- Do not force-remove the finalizer as a shortcut: that would bypass the cleanup responsibility being demonstrated.

## Repair and prove recovery

`repair` restores the authorized controller. It deletes the owned marker, removes its own finalizer, and lets deletion finish; Flux can then recreate the healthy example. Require the controller and a non-deleting, finalized task/marker baseline.

```bash
bash scripts/lab.sh 09-operator-finalizers repair
bash scripts/lab.sh 09-operator-finalizers verify-healthy
```

## Enterprise constraints and common pitfalls

When operator and application teams have different product owners, assign one accountable teardown coordinator. Missing cleanup access or a denied capture should be recorded and escalated rather than hidden by forcing deletion.

The fixture models external cleanup without incurring an extra cloud allocation. Real controllers can orphan disks, IPs, or databases when finalizers are bypassed. Destroy scenarios before Flux/AKS so cleanup code remains available.

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
bash scripts/lab.sh 09-operator-finalizers destroy
```

This restores access or controller prerequisites when needed, destroys the
scenario before Flux, then destroys Azure infrastructure. Verify the lab RG,
managed node RG, registry/private endpoint (where present), and firewall are gone.
Stopping AKS alone does not stop all charges. Do not delete the runner/state first.

## Reported basis and reproduction boundary

[Primary report or documentation](https://github.com/fluxcd/kustomize-controller/issues/301). Historical reports demonstrate a
failure class, not that the same defect remains in every current version. This
workbook's specific mechanism and limits are described above. No Azure deployment
or incident outcome is claimed from authoring or credential-free CI.
