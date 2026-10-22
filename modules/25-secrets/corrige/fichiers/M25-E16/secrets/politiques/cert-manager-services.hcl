# politiques/cert-manager-services.hcl — plateforme/secrets (M25-E16, SEC-2616)
# ClusterIssuer « openbao-services » de cert-manager (compte cert-manager/openbao-emetteur, méthode
# k8s-par1) : faire SIGNER une CSR par le rôle services-k8s. Pas « issue » (la clé serait générée
# par OpenBao et transiterait) : avec « sign », la clé privée naît dans le cluster et n'en sort pas.
# Rien d'autre sur pki-services/ : ni révocation, ni configuration, ni autre rôle.
path "pki-services/sign/services-k8s" {
  capabilities = ["create", "update"]
}
