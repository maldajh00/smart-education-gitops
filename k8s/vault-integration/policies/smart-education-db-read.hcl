# Vault policy: smart-education-db-read
#
# Least-privilege read of a single KV v2 entry that holds the
# smart-education database credentials. This policy is bound to the
# `smart-education-db-reader` Kubernetes auth role, which is in turn
# bound only to the `external-secrets-sa` ServiceAccount in the
# smart-education namespace.
#
# Capabilities are strictly `read`. No write, no list, no delete, no
# sudo, no wildcards. The metadata path is included so ESO can read
# version metadata without granting broader access.
#
# Loaded by scripts/bootstrap-vault.sh:
#   vault policy write smart-education-db-read - <<< "$(cat this-file)"

path "secret/data/smart-education/database" {
  capabilities = ["read"]
}

path "secret/metadata/smart-education/database" {
  capabilities = ["read"]
}
