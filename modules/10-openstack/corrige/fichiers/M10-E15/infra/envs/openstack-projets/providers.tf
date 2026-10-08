# Aucun secret ici. Authentification par application credential, lue dans l'environnement :
#   OS_AUTH_URL=https://openstack.par1.medisphere.internal:5000/v3
#   OS_AUTH_TYPE=v3applicationcredential
#   OS_APPLICATION_CREDENTIAL_ID, OS_APPLICATION_CREDENTIAL_SECRET
#   OS_REGION_NAME=RegionOne   OS_INTERFACE=public
#   OS_CACERT=/usr/local/share/ca-certificates/medisphere-root-ca.crt
# Sur adm01 : ~/.config/workbook/openstack-tofu.env (600), chargé par outils/charger-acces.sh.
# En CI : variables protégées et masquées du projet plateforme/infra.
# L'application credential appartient à svc-tofu (domaine Default, admin sur le projet admin) : poser des
# quotas et créer des ressources pour d'autres projets sont des opérations d'administrateur.

provider "openstack" {
  region   = var.region
  insecure = false
}
