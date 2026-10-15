# registre/providers.tf — M13-E03.
# url, username et password viennent de HARBOR_URL, HARBOR_USERNAME, HARBOR_PASSWORD.
# ⚠️ insecure vaut TRUE par défaut dans ce fournisseur (certificat non vérifié) : on l'écrit à false.
# Le certificat de Harbor est émis par la PKI MédiSphère, de confiance sur runner01 et adm01.
provider "harbor" {
  insecure = false
}
