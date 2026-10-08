# main.tf — environnement de recette de MédiAgenda (M10-E31). Ce dépôt ne contient QUE des
# valeurs : la logique est dans le module de la plateforme, référencé par une ÉTIQUETTE (la
# montée de version du module est une MR de ce dépôt, relue par l'équipe).
module "recette" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//openstack-env-app?ref=v1.5.0"

  prefixe          = "agenda-recette"
  cidr             = "172.20.10.0/24"
  nombre_instances = 2
  gabarit          = "m1.petit"
  cle_publique_ssh = var.cle_publique_ssh
  volume_taille    = 5
  page_titre       = "MédiAgenda — recette"
  acces_admin      = var.acces_admin
  etiquettes       = ["mediagenda", "recette"]
}
