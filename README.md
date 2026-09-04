# smart-education-gitops

Declarative desired state for the **Smart Education Portal** running on
GKE cluster `prod-gke` (project `smart-education-assignment`, region
`me-central1`).

- Application repo: <https://github.com/maldajh00/smart-education-assessment>
- **This repo**:     <https://github.com/maldajh00/smart-education-gitops>

Nothing in this repo is applied by developers or CI. It is applied
**only** by ArgoCD, which continuously reconciles what is in git against
what is running in the cluster. Every deployment is a git commit.

---

## 1. Purpose

A GitOps repository is the single source of truth for what the cluster
*should* look like. ArgoCD is the only actor that changes cluster state,
and it only changes state to match this repo. Consequences:

- Every production change is a reviewable git commit.
- Manual `kubectl edit` is reverted automatically (`selfHeal: true`).
- Rollback is `git revert`.
- Auditing "what was deployed on date X" = `git log`.

## 2. Repository structure

```
smart-education-gitops/
├── README.md
└── k8s/
    ├── base/
    │   ├── namespace.yaml
    │   ├── configmap.yaml
    │   ├── backend-serviceaccount.yaml
    │   ├── backend-deployment.yaml
    │   ├── backend-service.yaml
    │   ├── backend-hpa.yaml
    │   ├── backend-pdb.yaml
    │   ├── frontend-deployment.yaml
    │   ├── frontend-service.yaml
    │   ├── frontend-hpa.yaml
    │   ├── frontend-pdb.yaml
    │   ├── migration-job.yaml
    │   ├── network-policy.yaml
    │   ├── kustomization.yaml
    │   └── postgres/
    │       ├── statefulset.yaml
    │       ├── service.yaml
    │       └── kustomization.yaml
    ├── overlays/
    │   └── prod/
    │       └── kustomization.yaml   ← pins backend + frontend image SHAs
    └── argocd/
        ├── app-project.yaml
        ├── application.yaml
        ├── kustomization.yaml
        └── values-argocd.yaml       ← Helm values that pin ArgoCD itself
                                       to the management node pool
```

Notably absent from `k8s/base/`:

- **No `secret.yaml`** — the database credentials are populated by Vault
  (see §8). ArgoCD does not manage that Secret.
- **No `ingress.yaml`** — Ingress + Google Managed Certificate +
  FrontendConfig are deferred to the Ingress/TLS phase so that syncing
  this repo does not immediately provision a Google Cloud Load Balancer.

## 3. Application repo vs GitOps repo

| | Application repo | GitOps repo |
|---|---|---|
| Name | `maldajh00/smart-education-assessment` | `maldajh00/smart-education-gitops` (this repo) |
| Contains | React frontend, FastAPI backend, Dockerfiles, tests, CI workflow, Phase-1 `k8s/` (the pre-move source) | Kubernetes manifests + Kustomize overlays + ArgoCD Application/AppProject |
| Written by | Developers | CI (image SHA bumps) + occasional PR (structural manifest change) |
| Consumed by | GitHub Actions | ArgoCD |
| Result of a commit | New image in Artifact Registry | Cluster reconciliation |

The two repos are joined by exactly two artifacts: an Artifact Registry
image digest and a commit in this repo that references it.

## 4. CI vs CD separation

| Concern | Tool | Repo | Trigger |
|---|---|---|---|
| CI: tests, build, push image | GitHub Actions | app repo | push (publish only from `main`) |
| CD: reconcile manifests into cluster | ArgoCD | this repo | git commit + poll |

CI never runs `kubectl apply`. CD never builds images.

## 5. Artifact Registry

Images live at:

- `me-central1-docker.pkg.dev/smart-education-assignment/prod-gke-repo/smart-education-backend`
- `me-central1-docker.pkg.dev/smart-education-assignment/prod-gke-repo/smart-education-frontend`

CI authenticates via Workload Identity Federation (no JSON keys) and
pushes tagged with `:${GITHUB_SHA}`. Tags are immutable — a pushed SHA
never moves.

## 6. Immutable image SHA strategy

`k8s/overlays/prod/kustomization.yaml` contains an `images:` block that
pins both images. CI keeps it up to date:

```bash
# runs inside the app-repo workflow after `docker push` succeeds on main
git clone https://x-access-token:${GH_TOKEN}@github.com/maldajh00/smart-education-gitops.git
cd smart-education-gitops/k8s/overlays/prod
kustomize edit set image \
  me-central1-docker.pkg.dev/smart-education-assignment/prod-gke-repo/smart-education-backend=\
me-central1-docker.pkg.dev/smart-education-assignment/prod-gke-repo/smart-education-backend:${GITHUB_SHA}
kustomize edit set image \
  me-central1-docker.pkg.dev/smart-education-assignment/prod-gke-repo/smart-education-frontend=\
me-central1-docker.pkg.dev/smart-education-assignment/prod-gke-repo/smart-education-frontend:${GITHUB_SHA}
git commit -am "prod: bump to ${GITHUB_SHA::7}"
git push
```

Placeholder `PLACEHOLDER_SHA` currently sits in the overlay so the file
is structurally complete. **Do not apply the overlay while any image
still points at `PLACEHOLDER_SHA`.** CI's first successful run replaces
both entries.

`:latest` is banned. So is any moving tag like `1.0.0` used as a
deployment mechanism — the human-readable `1.0.0` may exist in AR
alongside the SHA tag, but ArgoCD deploys the SHA.

## 7. ArgoCD reconciliation

`k8s/argocd/application.yaml`:

```yaml
source:
  repoURL: https://github.com/maldajh00/smart-education-gitops.git
  targetRevision: main
  path: k8s/overlays/prod
destination:
  server: https://kubernetes.default.svc
  namespace: smart-education
syncPolicy:
  automated: { prune: true, selfHeal: true, allowEmpty: false }
  syncOptions:
    - ServerSideApply=true
    - PruneLast=true
    - CreateNamespace=false
    - RespectIgnoreDifferences=true
    - ApplyOutOfSyncOnly=true
```

Sync order:

1. **PreSync**: `migration-job.yaml` runs (annotation
   `argocd.argoproj.io/hook: PreSync`,
   `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation`). The
   previous Job is deleted first so the new image's migration always
   runs.
2. **Sync**: overlays/prod manifests apply via server-side apply.
3. **PruneLast**: any resources removed from git are deleted after all
   Applies succeed.

Failures retry five times with 30 s → 5 min backoff.

## 8. Vault secret strategy

The application consumes:

- `envFrom.secretRef: backend-secret` — backend Deployment
- `secretKeyRef.name: backend-secret` — Postgres StatefulSet (same keys)

`backend-secret` is deliberately **not** in this repo. It is provisioned
out-of-band by HashiCorp Vault. Two candidate integrations (Phase 3
picks one):

- **Vault Agent Injector** — pod annotations mount rendered secrets as
  files. The manifests would gain annotations but keep their current env
  wiring by consuming a Vault-rendered `env` file.
- **External Secrets Operator (ESO)** — a `SecretStore` +
  `ExternalSecret` synthesizes a native `Secret` named `backend-secret`
  in the `smart-education` namespace. The app manifests stay identical.

Whichever is chosen, the app manifests in this repo do not need to
change. Postgres reuses the same Secret keys the backend consumes, so
Vault only has to populate one place.

## 9. Application node vs management node separation

| Workload | Node pool | Enforcement in this repo |
|---|---|---|
| backend, frontend, migration Job, postgres | `workload=application` | `nodeSelector: {workload: application}` on the pod spec, no toleration for the management taint |
| ArgoCD (all components), Vault (later), Prometheus (later) | `workload=management` | `nodeSelector: {workload: management}` **plus** `toleration: {key: workload, value: management, effect: NoSchedule}` — see `k8s/argocd/values-argocd.yaml` |

The management node's `NoSchedule` taint means application pods cannot
land there even during scaling events.

## 10. Rollback

Preferred (GitOps-native):

```bash
git -C smart-education-gitops revert <commit>
git push
# ArgoCD picks up the revert within the next sync interval and
# applies the previous manifests.
```

Faster in an incident (ArgoCD-native, out-of-band from git):

```bash
argocd app rollback smart-education-prod <revision>   # uses revisionHistoryLimit: 10
```

Always follow an ArgoCD-native rollback with a matching `git revert`,
otherwise the next sync will re-apply the bad revision.

Kubernetes-native fallback (only if ArgoCD itself is down):

```bash
kubectl -n smart-education rollout undo deployment/backend
```

This is transient; `selfHeal` will revert it once ArgoCD is back unless
you also revert the git commit.

---

## Bootstrap sequence (for the ArgoCD install phase — not this phase)

```bash
# 1. Install ArgoCD onto the management node
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd \
  -n argocd --create-namespace \
  -f k8s/argocd/values-argocd.yaml

# 2. Register the AppProject + Application
kubectl apply -k k8s/argocd/

# 3. Watch it reconcile
argocd app get smart-education-prod
```

Prerequisites (must happen before the first sync succeeds):

- Phase 3 (Vault) has created `backend-secret` in the `smart-education`
  namespace.
- CI has replaced `PLACEHOLDER_SHA` in `k8s/overlays/prod/kustomization.yaml`
  with a real Git SHA.
