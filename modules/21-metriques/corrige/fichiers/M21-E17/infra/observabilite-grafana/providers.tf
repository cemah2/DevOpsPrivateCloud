# observabilite-grafana/providers.tf — M21-E17.
# Jeton d'un compte de service Grafana (rôle Admin) : jamais dans le code ni dans l'état.
# TLS : le certificat de grafana.apps… est émis par cert-manager (step-ca) ; la racine MédiSphère
# est dans le magasin de adm01 (M06) : aucune option d'insécurité.
provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_jeton
}
