# 01 — Private AKS API disappears from hub DNS

## Scenario and learning goal

An authorized hub-based operator cannot bootstrap or inspect a private cluster, while in-cluster workloads continue. The fault removes only the hub VNet link to the private API zone. The spoke link and cluster remain intact.

The public API FQDN is disabled. Peering supplies IP connectivity, not a private DNS-zone association. This workbook uses Azure-provided DNS and zone links; it does not install a corporate DNS resolver or VPN.

## Deploy the isolated Azure lab

From this repository's root, follow [deployment prerequisites](../../docs/deployment.md).
This creates a complete private AKS/hub/spoke/firewall/runner environment, not a
namespace in an existing cluster. Azure charges apply throughout the exercise;
03/04 also use ACR Premium. Review regional costs and quota before applying.

```bash
cp workbooks/01-private-api-dns/infra/terraform.tfvars.example \
   workbooks/01-private-api-dns/infra/terraform.tfvars
# Edit subscription, public SSH key, location, and an available supported AKS patch.
# For an unmerged PR: export LAB_REPOSITORY_REF=THE_PR_BRANCH
bash scripts/lab.sh 01-private-api-dns deploy
```

The three Terraform roots are independent: `infra/` uses Azure ARM from your
workstation; `bootstrap/` installs Flux from the private runner; `scenario/` applies
only after the Flux APIs exist. Keep their state and the per-lab kubeconfig until
cleanup. See [state and access boundaries](../../docs/deployment.md#permissions-and-assumptions).

## Recreate the failure

`infra/main.tf` maps `fault_enabled=true` to `link_hub_api_dns=false`. Azure ARM access remains available, so the repair is independent of the broken Kubernetes path.

```bash
bash scripts/lab.sh 01-private-api-dns inject
bash scripts/lab.sh 01-private-api-dns verify-fault
```

A failing verifier means the expected evidence was not observed. Diagnose it;
do not record a reproduced incident based only on Terraform completing. On Azure,
allow for DNS, role-assignment, image-pull backoff, and controller intervals.

## Investigate from the private runner

```bash
bash scripts/lab.sh 01-private-api-dns inspect
```

Use the [approved runner access](../../docs/deployment.md#3-inject-collect-evidence-and-repair)
and its per-workbook kubeconfig. These are diagnostic observations, not permission
to change a shared production system.

- Compare `getent ahostsv4 "$LAB_PRIVATE_FQDN"` on the runner before and after injection.
- Confirm public DNS still resolves; the verifier rejects a generic DNS failure as evidence.
- From the workstation, inspect the zone links with `az network private-dns link vnet list` using the workbook RG and zone name.
- Do not conclude that source-controller lost API access: its in-cluster path is different from this hub management path.

## Repair and prove recovery

`repair` restores the hub link from the workstation, then reconciles the scenario over the restored path. Verify API DNS and `kubectl get nodes`, not merely Terraform completion.

```bash
bash scripts/lab.sh 01-private-api-dns repair
bash scripts/lab.sh 01-private-api-dns verify-healthy
```

## Enterprise constraints and common pitfalls

An unavailable network/DNS owner should trigger the approved delegate. Sharing an AKS admin kubeconfig will not fix name resolution. Request the zone-link change at its specific scope rather than subscription-wide access.

Private DNS negative caching may delay recovery. Reusing a kubeconfig does not prove connectivity. Never enable the public cluster endpoint as a shortcut.

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
bash scripts/lab.sh 01-private-api-dns destroy
```

This restores access or controller prerequisites when needed, destroys the
scenario before Flux, then destroys Azure infrastructure. Verify the lab RG,
managed node RG, registry/private endpoint (where present), and firewall are gone.
Stopping AKS alone does not stop all charges. Do not delete the runner/state first.

## Reported basis and reproduction boundary

[Primary report or documentation](https://learn.microsoft.com/en-us/azure/aks/private-clusters). Historical reports demonstrate a
failure class, not that the same defect remains in every current version. This
workbook's specific mechanism and limits are described above. No Azure deployment
or incident outcome is claimed from authoring or credential-free CI.
