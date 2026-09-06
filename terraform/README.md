# Terraform — Smart Education infrastructure

This directory represents the GCP infrastructure that was already
provisioned for the Smart Education assessment (project
`smart-education-assignment`, region `me-central1`): the VPC/subnet/
Cloud NAT, the `prod-gke` GKE cluster and its two node pools, the
`prod-gke-repo` Artifact Registry repository, and the GitHub Actions
Workload Identity Federation setup used by both this repo's own
Terraform CI and the application repo's image-build CI.

It was written to **match already-running infrastructure**, then
verified against the real cluster with `terraform import` + `terraform
plan` (not written first and applied blind). See §6 below for exactly
how, and what had to be corrected along the way.

## 1. Structure

```
terraform/
├── versions.tf, providers.tf, variables.tf, locals.tf, outputs.tf
│     Shared root-module files. environments/prod symlinks the first
│     four (versions/providers/variables/locals) rather than duplicating
│     them — the only environment today is prod, but a second one only
│     needs its own main.tf + backend.tf, not a re-declaration of
│     provider requirements.
├── modules/
│   ├── network/                VPC, subnet, Cloud Router, Cloud NAT
│   ├── gke/                    GKE cluster + management/application node pools
│   ├── artifact-registry/      Docker repo + repo-scoped IAM
│   ├── ci-identity/            WIF pool + provider + GSA for the app repo's image CI
│   └── terraform-ci-identity/  A second WIF provider (same pool) + plan/apply GSAs for THIS repo's own Terraform CI
├── environments/
│   └── prod/               The only root module actually `init`/`plan`/`apply`'d.
│       ├── main.tf, outputs.tf, backend.tf, terraform.tfvars.example
│       └── versions.tf, providers.tf, variables.tf, locals.tf  (symlinks)
└── bootstrap/              One-time: creates the GCS state bucket. See its own README.
```

## 2. Remote state

State lives in GCS: bucket `smart-education-assignment-tfstate`
(versioned, public access blocked), prefix `prod`. Created once via
`terraform/bootstrap` — see that directory's README for why it can't be
managed by `environments/prod` itself (chicken-and-egg: this config's
state can't live in a bucket this same config creates).

No local `.tfstate` is committed — see `terraform/.gitignore`. The
provider lock file (`.terraform.lock.hcl`) **is** committed; only the
downloaded provider binaries (`.terraform/`) are ignored.

## 3. Running it

```bash
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars   # defaults already match this project
terraform init
terraform fmt -check -recursive ..
terraform validate
terraform plan
```

A plan against the current infrastructure should show **No changes**
(that's the state this repo ships in — see §6). If it doesn't, something
in the real infrastructure moved since this was last verified;
investigate the diff before applying, and never apply a plan that wants
to destroy or replace `prod-gke`, its node pools, the VPC, or the
subnet.

## 4. What's deliberately NOT in Terraform

- **Vault, ArgoCD, ESO, the application workloads** — all Kubernetes-level,
  managed by ArgoCD from `k8s/` in this same repo. Terraform provisions
  the cluster; it does not reach inside it.
- **GKE-managed firewall rules** (`gke-*`, `k8s-fw-l7-*`) — auto-created
  and continuously reconciled by GKE itself for the cluster's own
  connectivity needs. Importing them into Terraform would fight that
  reconciliation.
- **The GKE-auto-provisioned pod secondary range**
  (`gke-prod-gke-pods-<suffix>`) — created by GKE when the cluster's
  `ip_allocation_policy` doesn't name an explicit range, not by the
  subnetwork resource. The `network` module's own pre-reserved
  `gke-pods`/`gke-services` secondary ranges are unused leftovers from an
  earlier design and are represented (so Terraform doesn't try to remove
  them) but not consumed by the cluster.
- **`app-gsa`** (a second, apparently-unused service account bound to
  `default/app-service-account` via Workload Identity) — not referenced
  by anything currently in `k8s/`; left alone rather than guessed at.

## 5. CI: automated plan/apply (`.github/workflows/terraform.yaml`)

- **Every PR touching `terraform/**`**: `fmt -check` + `validate` (no
  cloud credentials), then `plan` using the **read-only** `terraform-
  plan-gsa` identity, posted as a PR comment.
- **Push to `main` touching `terraform/**`**: `apply`, using the more-
  privileged `terraform-apply-gsa` identity, gated behind the GitHub
  Environment `terraform-prod`.
- Both authenticate via **Workload Identity Federation**
  (`google-github-actions/auth`) — no service-account JSON key
  anywhere — using the `terraform-ci-identity` module's WIF provider
  (`gitops-provider`, on the same pool the app repo's CI uses, but its
  own provider with its own `attribute_condition` scoped to
  `maldajh00/smart-education-gitops` only).

### Identity setup — done, provisioned via Terraform itself

Unlike the app repo's `ci-identity` (one GSA scoped to
`roles/artifactregistry.writer` on one repository — nowhere near enough
for managing a VPC, a GKE cluster, IAM, or WIF itself), this repo's own
Terraform CI needs meaningfully broader permissions to do its job. Origin
of that gap is `modules/terraform-ci-identity`, applied this session
(see `main.tf`'s `module "terraform_ci_identity"` block):

- **`terraform-plan-gsa`**: `roles/viewer` only.
- **`terraform-apply-gsa`**: `roles/compute.networkAdmin`,
  `roles/container.admin`, `roles/artifactregistry.admin`,
  `roles/iam.serviceAccountAdmin`, `roles/iam.workloadIdentityPoolAdmin`
  — the specific resource types this config manages, not
  Editor/Owner.
- Both are restricted to impersonation from this one repo only, via the
  WIF provider's `attribute_condition`.

Repository variables `TF_WORKLOAD_IDENTITY_PROVIDER`,
`TF_PLAN_SERVICE_ACCOUNT`, `TF_APPLY_SERVICE_ACCOUNT` are set (Settings →
Secrets and variables → Actions → Variables — these aren't secrets, so
they're variables, not secrets). The `terraform-prod` GitHub Environment
exists.

**Not done, and left for a human:** the `terraform-prod` Environment has
no required-reviewer protection rule yet — GitHub's API rejected adding
one (`"Please ensure the billing plan supports the required reviewers
protection rule"` — this repo is private, and that specific protection
rule needs a paid GitHub plan for private repos). Add it manually once
the plan supports it (Settings → Environments → terraform-prod →
required reviewers), or make the repo public if that's acceptable. Until
then, `apply` runs unattended on every push to `main` that touches
`terraform/**` — treat that as a real gap, not a formality, given what
`terraform-apply-gsa` can do.

## 6. Verification performed this session

1. `gcloud compute networks/subnets/routers describe`, `gcloud container
   clusters describe`, `gcloud artifacts repositories describe`,
   `gcloud iam workload-identity-pools ... describe`, and IAM policy
   queries against the live project — this is what the module arguments
   above are drawn from, not assumption.
2. `terraform init` against the real GCS backend, then `terraform
   import` for all 12 core-infrastructure resources (network, subnet,
   router, NAT, cluster, both node pools, the Artifact Registry repo +
   its IAM binding, the app-CI WIF pool + provider, the app-CI GSA + its
   IAM binding).
3. `terraform plan` iterated to a clean **`No changes.`** — including
   catching and fixing:
   - `initial_node_count` forcing full cluster **replacement** (this
     field is create-time-only; the live value is `0` since
     `remove_default_node_pool` already ran once, long before Terraform
     existed for this cluster — the module now matches that instead of
     assuming `1`).
   - `dns_config.cluster_dns`: the live API value `KUBE_DNS` maps to the
     provider's own enum value `PLATFORM_DEFAULT`, not the string
     `"KUBE_DNS"` (which the provider rejects outright).
   - The router's `bgp` block: the live router has no real BGP peers, so
     GCP reports a zero-value block (`asn = 0`) that isn't a valid,
     settable ASN — declaring it explicitly risks the API rejecting the
     apply. `lifecycle { ignore_changes = [bgp] }` instead.
   - **The incident**: declaring `master_authorized_networks_config`
     at all — even solely to set `gcp_public_cidrs_access_enabled =
     false`, which already matched the live value — implicitly sets
     `enabled = true` on that feature. The live cluster had the feature
     off entirely (not "on with an empty allowlist"), so applying this
     block cut off every public IP's access to the API server,
     including admin kubectl/ArgoCD-CLI access, mid-verification.
     Reverted immediately with `gcloud container clusters update
     --no-enable-master-authorized-networks`; the module now omits the
     block entirely, with a comment explaining why it must never be
     declared alone again if authorized networks are ever wanted for
     real (it would need to ship together with the actual
     `cidr_blocks` allowlist in the same change).
4. Three genuinely-safe idempotent `apply`s (the management pool's
   taint, the (reverted) authorized-networks block at the time, and the
   subnet's flow-log `filter_expr`) closed the remaining gaps between
   what `terraform import` captured and what the live resources actually
   have — each confirmed via `gcloud describe` beforehand to already
   match, so applying only made Terraform's state match reality, not
   change reality.
5. `terraform-ci-identity` (WIF provider, two GSAs, their WIF bindings,
   and six project IAM role grants) applied cleanly in two passes — the
   first `google_project_iam_member` grants failed with
   `cloudresourcemanager.googleapis.com` disabled (enabled it — a free
   API activation, not a billing change — and retried after propagation
   delay). Final `terraform plan`: **`No changes.`**
