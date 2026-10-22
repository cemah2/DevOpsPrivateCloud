# politiques/essai-csi.hcl — comparaison Secrets Store CSI (M25-E19, PLAT-2619, TEMPORAIRE : fichier
# supprimé en fin d'exercice, avec le rôle de tofu/essais-m25.tf).
# Le pod d'essai (compte de service essai-csi de wb-essais) lit UN secret de démonstration.
path "kv/data/plateforme/essais/csi-demo" {
  capabilities = ["read"]
}
