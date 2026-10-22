# /etc/vault.d/vault.hcl sur bao-essai (M25-E30, PLAT-2630) — HashiCorp Vault 2.2, configuration d'un
# nœud OpenBao recopiée et adaptée. Essayé avec Vault 2.2.0 (seal transit vers un OpenBao 2.6.4).
# Différences OBLIGATOIRES relevées :
#  - disable_mlock : OBLIGATOIRE dans Vault (« disable_mlock must be configured 'true' or 'false' »,
#    refus de démarrer) ; INCONNU d'OpenBao (« unknown or unsupported field »). true ici : Raft
#    intégré, pas de swap sur la VM, et mlock d'un processus qui mappe sa base Raft en mémoire
#    gonflerait la mémoire verrouillée.
#  - audit : Vault 2.2 l'active encore par l'API (« vault audit enable file … ») ; OpenBao 2.6+ exige
#    la déclaration dans ce fichier.
disable_mlock = true
ui            = true
cluster_name  = "essai-vault"

api_addr     = "https://bao-essai.par1.medisphere.internal:8200"
cluster_addr = "https://bao-essai.par1.medisphere.internal:8201"

storage "raft" {
  path    = "/var/lib/vault"
  node_id = "bao-essai"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_cert_file   = "/etc/vault.d/tls/cert.pem"
  tls_key_file    = "/etc/vault.d/tls/key.pem"
  tls_min_version = "tls13"
}

# Seal transit contre kms01 (OpenBao) : fonctionne (API transit commune). Clé DÉDIÉE à l'essai
# (essai-vault, créée puis supprimée sur kms01 : l'essai n'a aucune raison de pouvoir déchiffrer
# avec la clé de la grappe), jeton dédié de 4 h (politique essai-vault), variable VAULT_TOKEN dans
# /etc/vault.d/kms.env (le nom de la variable change : VAULT_ et non BAO_).
seal "transit" {
  address         = "https://kms01.par1.medisphere.internal:8200"
  key_name        = "essai-vault"
  mount_path      = "transit/"
  tls_ca_cert     = "/usr/local/share/ca-certificates/medisphere-root-ca.crt"
  tls_server_name = "kms01.par1.medisphere.internal"
}
