#!/usr/bin/env bash
# scripts/bootstrap-vault.sh
#
# One-time, out-of-band bootstrap for the Vault server that runs in the
# `vault` namespace. Runs against an already-initialized and unsealed
# Vault. NOTHING in this script writes secrets to disk or into Git; every
# sensitive value comes from stdin or an environment variable.
#
# =============================================================================
# PRE-REQS the operator handles manually BEFORE running this script:
# =============================================================================
#
#   # 1. Ensure the ArgoCD Application smart-education-vault has synced so
#   #    the Vault pod is Running (may be sealed/uninitialized).
#
#   # 2. Initialize Vault (once per lifetime of the file-storage volume):
#   kubectl -n vault exec vault-0 -- \
#     vault operator init -key-shares=5 -key-threshold=3
#
#   # OUTPUT includes 5 unseal keys + 1 initial root token.
#   # >>> Copy them into a password manager / sealed envelope / KMS.
#   # >>> DO NOT paste them into a file inside this repo.
#   # >>> DO NOT paste them into a Kubernetes Secret.
#   # >>> DO NOT commit them anywhere in Git.
#
#   # 3. Unseal (3 of 5 keys):
#   kubectl -n vault exec vault-0 -- vault operator unseal <key-1>
#   kubectl -n vault exec vault-0 -- vault operator unseal <key-2>
#   kubectl -n vault exec vault-0 -- vault operator unseal <key-3>
#
#   # 4. Export operator credentials for this shell session (never persisted):
#   export VAULT_ADDR='http://127.0.0.1:8200'          # if using port-forward
#   export VAULT_TOKEN='<initial-root-token>'          # paste here, don't store
#
#   # 5. Port-forward to reach Vault from your workstation:
#   kubectl -n vault port-forward svc/vault 8200:8200 &
#
# =============================================================================
# USAGE:
#   ./scripts/bootstrap-vault.sh
#
# The script will:
#   1. verify the operator token works
#   2. enable the KV v2 secret engine at `secret/`
#   3. enable Kubernetes auth
#   4. configure Kubernetes auth to talk to kubernetes.default.svc
#   5. load the smart-education-db-read policy
#   6. create the smart-education-db-reader role
#   7. prompt for or generate the database password
#   8. write DATABASE_USER + DATABASE_PASSWORD to secret/smart-education/database
#   9. enable a file audit device inside the pod
#
# The script does NOT revoke the root token. Root-token handling is a
# deliberate operator decision:
#
#   - For a real deployment: create an admin user/OIDC binding, then
#     `vault token revoke -self`. Losing the root token before creating an
#     alternate admin path leaves Vault unmanageable except by unseal-key
#     regeneration.
#   - For the free-trial demo: keep the root token in a password manager
#     and revoke when done, or leave it and rely on the operator's
#     workstation being trusted.
#
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POLICY_FILE="${REPO_ROOT}/k8s/base/vault-integration/policies/smart-education-db-read.hcl"

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $1" >&2
        exit 1
    }
}

require vault
require openssl

# ---- 0. sanity ----
: "${VAULT_ADDR:?VAULT_ADDR is not set (e.g. http://127.0.0.1:8200)}"
: "${VAULT_TOKEN:?VAULT_TOKEN is not set (paste operator token; NEVER commit it)}"

echo "==> Verifying Vault reachability + token"
vault status >/dev/null
vault token lookup >/dev/null

# ---- 1. enable secret engine (idempotent) ----
echo "==> Ensuring KV v2 engine at secret/"
if ! vault secrets list -format=json | grep -q '"secret/"'; then
    vault secrets enable -path=secret -version=2 kv
else
    echo "    (already enabled)"
fi

# ---- 2. enable kubernetes auth (idempotent) ----
echo "==> Ensuring auth/kubernetes"
if ! vault auth list -format=json | grep -q '"kubernetes/"'; then
    vault auth enable kubernetes
else
    echo "    (already enabled)"
fi

# ---- 3. configure kubernetes auth ----
echo "==> Configuring auth/kubernetes to talk to the cluster API"
# Vault, when running IN the cluster, uses its own SA token to call
# TokenReview. `token_reviewer_jwt` and `kubernetes_ca_cert` default to
# the values Vault reads from its projected volume, so we only pin the
# API host explicitly. `disable_iss_validation=true` is required in
# clusters where the SA issuer differs from what Vault detects.
vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc" \
    disable_iss_validation="true"

# ---- 4. load policy ----
[ -r "${POLICY_FILE}" ] || {
    echo "ERROR: policy file missing: ${POLICY_FILE}" >&2
    exit 1
}
echo "==> Loading policy smart-education-db-read from ${POLICY_FILE}"
vault policy write smart-education-db-read "${POLICY_FILE}"

# ---- 5. create role ----
echo "==> Creating role smart-education-db-reader"
vault write auth/kubernetes/role/smart-education-db-reader \
    bound_service_account_names="external-secrets-sa" \
    bound_service_account_namespaces="smart-education" \
    audience="vault" \
    token_policies="smart-education-db-read" \
    token_ttl="1h" \
    token_max_ttl="24h"

# ---- 6. seed the DB credential ----
echo "==> Seeding database credential at secret/smart-education/database"
DB_USER="${DB_USER:-smart_education}"

if [ -z "${DB_PASSWORD:-}" ]; then
    if [ -t 0 ]; then
        # Interactive: prompt without echo. Nothing hits disk.
        read -rsp "Enter DATABASE_PASSWORD (leave blank to generate one): " DB_PASSWORD
        echo
    fi
fi
if [ -z "${DB_PASSWORD:-}" ]; then
    DB_PASSWORD="$(openssl rand -base64 24 | tr -d '\n=+/' | cut -c1-24)"
    echo "    generated random password (24 chars); NOT printed."
fi

vault kv put secret/smart-education/database \
    DATABASE_USER="${DB_USER}" \
    DATABASE_PASSWORD="${DB_PASSWORD}"

# Scrub the variable from this shell asap.
unset DB_PASSWORD

# ---- 7. audit device (best-effort; safe if already enabled) ----
echo "==> Enabling file audit device at /vault/audit/audit.log"
if ! vault audit list -format=json | grep -q '"file/"'; then
    vault audit enable file file_path=/vault/audit/audit.log \
        || echo "    WARN: audit enable failed; check /vault/audit is writable"
else
    echo "    (already enabled)"
fi

echo
echo "==> Done. Next steps (operator, out-of-band):"
echo "    - Confirm ESO can read the secret:"
echo "        kubectl -n smart-education get externalsecret backend-secret"
echo "        kubectl -n smart-education get secret backend-secret"
echo "    - When happy, decide about root-token retention (see header)."
