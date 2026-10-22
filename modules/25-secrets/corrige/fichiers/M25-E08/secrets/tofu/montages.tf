# tofu/montages.tf — moteurs de secrets (M25-E04, importés en E08).

# KV version 2 : secrets statiques versionnés. kv/plateforme/<composant>/<secret>,
# kv/<application>/<env>/<secret> (PLAN §4.12).
resource "vault_mount" "kv" {
  path        = "kv"
  type        = "kv"
  options     = { version = "2" }
  description = "Secrets statiques de MédiSphère (KV v2)"
}

# Réglages du moteur (chemin kv/config) : 10 versions gardées par secret. cas_required reste à
# false au niveau du moteur : on l'impose secret par secret quand deux écrivains peuvent se croiser.
resource "vault_kv_secret_backend_v2" "kv" {
  mount        = vault_mount.kv.path
  max_versions = 10
  cas_required = false
}
