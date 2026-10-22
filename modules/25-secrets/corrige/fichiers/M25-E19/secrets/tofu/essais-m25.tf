# tofu/essais-m25.tf — objets TEMPORAIRES de la comparaison CSI (M25-E19, PLAT-2619).
# Fichier SUPPRIMÉ en fin d'exercice (avec politiques/essai-csi.hcl) : le plan annonce leur destruction.
#
# Rôle de la méthode kubernetes « k8s-par1 » (M25-E12) pour le seul compte de service essai-csi de
# wb-essais. Le fournisseur CSI demande lui-même au cluster (TokenRequest) un jeton de ce compte avec
# l'audience donnée dans la SecretProviderClass : elle doit être celle qu'exige le rôle.
resource "vault_kubernetes_auth_backend_role" "essai_csi" {
  backend   = "k8s-par1"
  role_name = "essai-csi"

  bound_service_account_names      = ["essai-csi"]
  bound_service_account_namespaces = ["wb-essais"]
  audience                         = "openbao.medisphere.internal"

  token_policies = ["essai-csi"]
  token_ttl      = 600
  token_max_ttl  = 600
}
