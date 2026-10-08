# envs/openstack-projets

Socle des projets d'équipe sur OpenStack PAR1 (M10-E15, PLAT-1125) : quotas (calcul, volumes, réseau), réseau `<projet>-net`, sous-réseau `<projet>-sousreseau`, routeur `<projet>-routeur` relié à `ext-net`, groupe `<projet>-admin` (SSH depuis MGMT). Étiquettes `tofu`, `openstack-projets`.

| | |
|---|---|
| Clé d'état | `envs/openstack-projets/terraform.tfstate` (s3-01, chiffré, verrouillé) |
| Identité | application credential `tofu-openstack-projets` de `svc-tofu` (domaine `Default`, `admin` sur le projet `admin`), 90 jours ; créée par `adm01/creer-identite-tofu.sh` |
| Secrets | `~/.config/workbook/openstack-tofu.env` (adm01) ; variables protégées et masquées en CI |
| Hors périmètre | création des projets, groupes, rôles et comptes (code d'identité `plateforme/openstack`, RB-100) ; ressources des équipes (leurs propres états) |
| Jobs | `plan:openstack-projets` (MR et main), `apply:openstack-projets` (main, manuel) |

Ajouter une équipe : une entrée dans `terraform.tfvars` (après RB-100, étapes 1 à 3), MR, plan relu, apply.
Retirer une équipe : supprimer ses ressources dans son projet, retirer l'entrée, MR. Les quotas ne sont pas remis à zéro par un `destroy` (suppression sans effet côté OpenStack) : RB-100 les remet à 0 à la main avant la suppression du projet.
