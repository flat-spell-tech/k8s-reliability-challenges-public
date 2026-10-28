# 03 — ACR login works but private image data cannot download

## Scenario and learning goal

The registry login name resolves privately, yet a new workload cannot download image layers because its regional data endpoint record is absent. ACR public network access stays disabled.

An ACR private endpoint has distinct login and data DNS records. Only the data record is removed. The kubelet retains registry-scoped AcrPull, so an authentication-role change is not the intended failure.

## Deploy the isolated Azure lab

From this repository's root, follow [deployment prerequisites](../../docs/deployment.md).
This creates a complete private AKS/hub/spoke/firewall/runner environment, not a
namespace in an existing cluster. Azure charges apply throughout the exercise;
03/04 also use ACR Premium. Review regional costs and quota before applying.

```bash
cp workbooks/03-acr-private-dns/infra/terraform.tfvars.example \
   workbooks/03-acr-private-dns/infra/terraform.tfvars
# Edit subscription, public SSH key, location, and an available supported AKS patch.
# For an unmerged PR: export LAB_REPOSITORY_REF=THE_PR_BRANCH
bash scripts/lab.sh 03-acr-private-dns deploy
```

The three Terraform roots are independent: `infra/` uses Azure ARM from your
workstation; `bootstrap/` installs Flux from the private runner; `scenario/` applies
only after the Flux APIs exist. Keep their state and the per-lab kubeconfig until
cleanup. See [state and access boundaries](../../docs/deployment.md#permissions-and-assumptions).

## Recreate the failure

`infra/main.tf` removes `acr_data` through `include_acr_data_dns=false`. `deploy` imports a benign Microsoft image but deliberately defers its first workload pull; `inject` starts the actual Helm-managed workload after the DNS fault.

```bash
bash scripts/lab.sh 03-acr-private-dns inject
bash scripts/lab.sh 03-acr-private-dns verify-fault
```

A failing verifier means the expected evidence was not observed. Diagnose it;
do not record a reproduced incident based only on Terraform completing. On Azure,
allow for DNS, role-assignment, image-pull backoff, and controller intervals.

## Investigate from the private runner

```bash
bash scripts/lab.sh 03-acr-private-dns inspect
```

Use the [approved runner access](../../docs/deployment.md#3-inject-collect-evidence-and-repair)
and its per-workbook kubeconfig. These are diagnostic observations, not permission
to change a shared production system.

- Check the login hostname and `<registry>.<region>.data.azurecr.io` separately from the runner.
- Inspect `kubectl get pods -n workbook-03` and `kubectl describe pod -n workbook-03 POD_NAME` for layer-download DNS errors.
- Verify that kubelet AcrPull still exists and public access remains disabled.
- The fault verifier requires the login name to resolve, the data name not to resolve, and an actual image-pull failure. A warm-cache Running pod does not pass.

## Repair and prove recovery

`repair` restores the regional data A record without enabling public access. Wait for negative caches to expire and observe the existing pod retry, then require the HelmRelease current generation to become ready.

```bash
bash scripts/lab.sh 03-acr-private-dns repair
bash scripts/lab.sh 03-acr-private-dns verify-healthy
```

## Enterprise constraints and common pitfalls

Use an authorized DNS operator or a scoped record change if the application team lacks network access. Do not request registry admin credentials to address an NXDOMAIN. Treat image-cache differences as evidence, not a reason to rotate secrets.

Run on a fresh lab or a node that has not cached the sample image. If repeating after successful pulls, use a fresh lab or an uncached image/digest and document the changed fixture. `imagePullPolicy: Always` alone does not force cached layers to download.

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
bash scripts/lab.sh 03-acr-private-dns destroy
```

This restores access or controller prerequisites when needed, destroys the
scenario before Flux, then destroys Azure infrastructure. Verify the lab RG,
managed node RG, registry/private endpoint (where present), and firewall are gone.
Stopping AKS alone does not stop all charges. Do not delete the runner/state first.

## Reported basis and reproduction boundary

[Primary report or documentation](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link). Historical reports demonstrate a
failure class, not that the same defect remains in every current version. This
workbook's specific mechanism and limits are described above. No Azure deployment
or incident outcome is claimed from authoring or credential-free CI.
