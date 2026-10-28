# Deploy, diagnose, repair, and destroy

Run these commands from the repository root. The examples use workbook 01;
substitute the directory from the selected workbook README.

## 1. Establish the Azure scope before deployment

```bash
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
az aks get-versions --location eastus -o table
cp workbooks/01-private-api-dns/infra/terraform.tfvars.example \
   workbooks/01-private-api-dns/infra/terraform.tfvars
```

Edit the ignored `terraform.tfvars`: subscription ID, public SSH key, region,
available supported Kubernetes patch, sizes/counts, and optional prefix/CIDRs.
Supply a public key you control; do not paste its private key. The VM has no
public SSH endpoint: the key meets Azure VM provisioning requirements, while
the helper uses Run Command. Use only an isolated subscription/resource scope.

Select an available SKU and enough quota for a node and runner before applying.
If Azure Policy blocks a location, network, role assignment, or registry setting,
request the approved exception or choose an allowed configuration. The scripts
do not bypass policy. Register the required providers through your organization's
normal process if the identity cannot register them automatically.

For an unmerged branch:

```bash
export LAB_REPOSITORY_REF=YOUR_PUBLIC_BRANCH_NAME
```

Use the same branch for subsequent commands. `GitRepository` references use a
branch, not a commit hash or a tag. Forks require updating repository URLs and
the runner helper; the supplied defaults publish and execute only this repository.

## 2. Review the infrastructure plan and deploy

```bash
terraform -chdir=workbooks/01-private-api-dns/infra init
terraform -chdir=workbooks/01-private-api-dns/infra plan -var=fault_enabled=false
bash scripts/lab.sh 01-private-api-dns deploy
```

Infrastructure operations retain Terraform's local confirmation prompt. The
explicitly requested runner actions use noninteractive Terraform applies after
private access is established. `deploy` creates infrastructure, waits for the
runner's cloud-init, installs verified tools, obtains an Entra kubeconfig using
managed identity, installs Flux, and applies the workbook baseline. Workbooks 03
and 06 defer their specific test workload until fault injection to avoid cached
images and already-installed CRDs masking the exercise.

Expect Azure firewall/cluster provisioning to take many minutes. Role assignments
and DNS can take additional time to propagate. A failed stage is not proof of
the intended fault. Check the Azure deployment error and the runner's cloud-init
before proceeding. You can rerun `deploy` after correcting provisioning or access;
it preserves existing Terraform state. Do not run two actions on the same runner
concurrently: Azure Run Command and Terraform state require serialization.

The Run Command helper checks an explicit end-of-action success marker. A successful
Azure transport response alone does not count as a successful remote command.
Output is limited by Azure; a missing marker fails closed. Inspect approved runner
logs through Run Command or your existing private access when troubleshooting.

## 3. Inject, collect evidence, and repair

```bash
bash scripts/lab.sh 01-private-api-dns inject
bash scripts/lab.sh 01-private-api-dns verify-fault
bash scripts/lab.sh 01-private-api-dns inspect
bash scripts/lab.sh 01-private-api-dns repair
bash scripts/lab.sh 01-private-api-dns verify-healthy
```

Infrastructure faults 01–04 are applied from the workstation through Azure's
management API. In particular, 01 does not require the broken private API path
to repair itself. Other fault phases run on the private runner. Each workbook
documents what actually changes and where to look. `verify-fault` must observe
the specific bad state, not merely any command failure. Capture its outputs and
diagnostic queries using the incident record; they are not automatically sent
to Slack or a marketing service.

On the runner, scripts use a per-workbook kubeconfig and check the expected AKS
hostname before writes. `inspect` executes a bounded set of read-only diagnostic
commands through Run Command. For additional queries, use an authorized Run
Command with `KUBECONFIG=/opt/k8s-reliability-challenges-public/.lab/WORKBOOK/kubeconfig`
and the same managed-identity Azure CLI login. The supplied NSG denies inbound
management; interactive SSH/Bastion requires a separately approved private access
change. Raw status/manifest exports can contain operational metadata; do not post
them without review.

Verification polls for up to 600 seconds by default. From the workstation,
`VERIFY_TIMEOUT_SECONDS=1200 bash scripts/lab.sh WORKBOOK verify-fault` can
allow additional Azure propagation time. It is a diagnostic allowance, not a
reason to accept an unobserved fault. Workbooks 07 and 08 require their documented
phase sequence; do not jump directly to rollback/interruption before a baseline.

## 4. Destroy in reverse dependency order

```bash
bash scripts/lab.sh 01-private-api-dns destroy
```

The helper restores management connectivity for 01–04, repairs pending Helm or
controller/finalizer failures when needed, destroys scenario resources while
their controllers still run, uninstalls Flux, then prompts for Azure infra destroy.
Do not force-remove finalizers or delete Helm history to make cleanup appear fast.
Those operations can orphan resources in a real platform.

Preserve local infra state and the private runner's bootstrap/scenario state until
this completes. Losing the runner disk loses its local Kubernetes Terraform state.
If lost, use the recorded resource group and an authorized recovery operator to
inspect remaining objects; the whole AKS cluster is disposable, but independently
created external resources would require explicit reconciliation. Never import or
delete resources by a broad subscription-wide search.

Verify the workbook resource group is absent, the AKS-managed node resource group
has been removed, and no related registry/private-endpoint/firewall resources
remain. Then remove ignored local connection metadata if no longer needed. Remote
state is recommended for shared exercises; configure a protected backend separately
for **each root**, including the private runner roots, rather than sharing one state.

## Permissions and assumptions

- The operator creates isolated RG resources and scoped role assignments and can
  invoke Run Command on that runner. Subscription Contributor plus an approved
  role-assignment authority is one possible arrangement; do not request Owner
  merely to avoid identifying the required permissions.
- The runner receives Reader on its lab RG, AKS Cluster User and AKS RBAC Cluster
  Admin on its lab cluster, plus AcrPush on its own registry in 03/04. This is a
  lab bootstrap boundary. It is intentionally distinct from the limited tenant
  account and Flux registry-pull identity used by the scenarios.
- Registries are private-only with admin credentials disabled and classic registry
  RBAC mode explicitly selected. Workbook 03 seeds a benign Microsoft sample image
  through ARM import; trusted Azure services bypass is enabled for that operation.
- Peering is not DNS forwarding. The supplied networks use Azure-provided DNS and
  explicit private-zone links. They model the missing-link failure; they do not
  claim to deploy an enterprise DNS Private Resolver or an on-premises VPN.
