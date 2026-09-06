# Terraform — Smart Education infrastructure

This directory represents the GCP infrastructure that was already
provisioned for the Smart Education assessment (project
`smart-education-assignment`, region `me-central1`): the VPC/subnet/
Cloud NAT, the `prod-gke` GKE cluster and its two node pools, the
`prod-gke-repo` Artifact Registry repository, and the GitHub Actions
Workload Identity Federation setup used by the application repo's CI.

It was written to **match already-running infrastructure**, then
verified against the real cluster with `terraform import` + `terraform
plan` (not written first and applied blind). See §Verification below for
exactly how, and what had to be corrected along the way.

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
│   ├── network/            VPC, subnet, Cloud Router, Cloud NAT
│   ├── gke/                GKE cluster + management/application node pools
│   ├── artifact-registry/  Docker repo + repo-scoped IAM
│   └── ci-identity/        WIF pool/provider + GitHub Actions GSA
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
(that's the state this repo ships in — see §Verification). If it
doesn't, something in the real infrastructure moved since this was last
verified; investigate the diff before applying, and never apply a plan
that wants to destroy or replace `prod-gke`, its node pools, the VPC, or
the subnet.

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
  cloud credentials), then `plan` using a **read-only** identity,
  posted as a PR comment.
- **Push to `main` touching `terraform/**`**: `apply`, gated behind the
  GitHub Environment `terraform-prod`. Set that Environment's required
  reviewers in *Settings → Environments* — the workflow file can request
  the gate but can't create the protection rule itself.
- Both jobs authenticate via **Workload Identity Federation** (`google-
  github-actions/auth`) — no service-account JSON key anywhere.

### One-time setup this workflow needs (not yet provisioned)

The `ci-identity` module's WIF provider is scoped, by
`attribute_condition`, to exactly one repo:
`maldajh00/smart-education-assessment` (the application repo, which
pushes images). **This** repo (`smart-education-gitops`) needs its own
WIF provider and its own service account(s) before `terraform.yaml` can
run — reusing `github-actions-gsa` would violate least privilege, since
that identity is deliberately scoped to nothing but
`roles/artifactregistry.writer` on one repository.

Deliberately not auto-created by this session: granting a CI identity
project-level `roles/container.admin` /
`roles/compute.networkAdmin` / `roles/artifactregistry.admin` /
`roles/iam.serviceAccountAdmin` (needed for the `apply` identity to
actually manage these resources) is a meaningfully bigger, more
sensitive grant than anything else in this repo, and this session
already caused one real (quickly-reverted) production lockout by
under-scoping a `master_authorized_networks_config` block — see the
comment in `modules/gke/main.tf`. That's exactly the kind of change a
human should knowingly approve, not something to provision silently.

To wire it up:

```bash
# 1. A second WIF provider, scoped to this repo (reuse the existing pool):
gcloud iam workload-identity-pools providers create-oidc gitops-provider \
  --location=global \
  --workload-identity-pool=github-actions-pool \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository == 'maldajh00/smart-education-gitops'"

# 2. Two GSAs — plan (read-only) and apply (the roles Terraform actually needs):
gcloud iam service-accounts create terraform-plan-gsa \
  --display-name="Terraform plan (read-only)"
gcloud iam service-accounts create terraform-apply-gsa \
  --display-name="Terraform apply"

# roles/viewer is enough for `plan` to read every resource type here.
gcloud projects add-iam-policy-binding smart-education-assignment \
  --member="serviceAccount:terraform-plan-gsa@smart-education-assignment.iam.gserviceaccount.com" \
  --role="roles/viewer"

# `apply` needs to create/update the specific resource types this repo
# manages — grant these four, not Editor/Owner:
for role in roles/compute.networkAdmin roles/container.admin \
            roles/artifactregistry.admin roles/iam.serviceAccountAdmin; do
  gcloud projects add-iam-policy-binding smart-education-assignment \
    --member="serviceAccount:terraform-apply-gsa@smart-education-assignment.iam.gserviceaccount.com" \
    --role="$role"
done

# 3. Let each GSA be impersonated only via the gitops repo's WIF provider:
for sa in terraform-plan-gsa terraform-apply-gsa; do
  gcloud iam service-accounts add-iam-policy-binding \
    "${sa}@smart-education-assignment.iam.gserviceaccount.com" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/940549323188/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/maldajh00/smart-education-gitops"
done
```

Then set these as repository **variables** (Settings → Secrets and
variables → Actions → Variables — not secrets, these aren't sensitive):
`TF_WORKLOAD_IDENTITY_PROVIDER` (the gitops-provider resource name from
step 1), `TF_PLAN_SERVICE_ACCOUNT`, `TF_APPLY_SERVICE_ACCOUNT`. Finally,
create the `terraform-prod` Environment with at least one required
reviewer.

## 6. Verification performed this session

1. `gcloud compute networks/subnets/routers describe`, `gcloud container
   clusters describe`, `gcloud artifacts repositories describe`,
   `gcloud iam workload-identity-pools ... describe`, and IAM policy
   queries against the live project — this is what the module arguments
   above are drawn from, not assumption.
2. `terraform init` against the real GCS backend, then `terraform
   import` for all 12 resources (network, subnet, router, NAT, cluster,
   both node pools, the Artifact Registry repo + its IAM binding, the
   WIF pool + provider, the GSA + its IAM binding).
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
