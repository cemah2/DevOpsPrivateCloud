# providers.tf — authentification par APPLICATION CREDENTIAL du projet mediagenda-dev, rôle
# member, sans aucun secret ici. Variables d'environnement (CI : variables protégées et masquées
# du projet GitLab ; poste : fichier 600 hors dépôt) :
#   OS_AUTH_TYPE=v3applicationcredential
#   OS_AUTH_URL=https://openstack.par1.medisphere.internal:5000/v3
#   OS_APPLICATION_CREDENTIAL_ID=<ID>
#   OS_APPLICATION_CREDENTIAL_SECRET=<SECRET>            (masquée)
#   OS_CACERT=/usr/local/share/ca-certificates/medisphere-root-ca.crt
#   OS_REGION_NAME=RegionOne
provider "openstack" {
  # Jamais « insecure » : la racine MédiSphère est fournie par OS_CACERT.
  insecure = false
}
