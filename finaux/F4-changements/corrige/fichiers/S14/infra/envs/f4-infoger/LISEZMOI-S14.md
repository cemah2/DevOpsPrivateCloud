# envs/f4-infoger après le décommissionnement de legacy-rdv01 (F4-S14, CHG-3414)

Changements de code (une MR, relue par Karim) **après** l'étape `effacer` et **avant** l'étape `detruire` de `decommissionner-legacy-rdv01.sh` :

1. `infoger.tf` : l'entrée `"legacy-rdv01"` disparaît de `local.vms_infoger` (les deux autres restent).
2. La VM ne doit **pas** être détruite par OpenTofu (`prevent_destroy = true` sur la ressource, qui protège les deux autres VMs) : on la retire de l'état **sans** la détruire, geste tracé dans CHG-3414 :
   ```
   admin@adm01:~/src/infra/envs/f4-infoger$ tofu state rm 'proxmox_virtual_environment_vm.infoger["legacy-rdv01"]'
   ```
   (Un bloc `removed` ne peut pas viser une seule instance d'un `for_each` : à vérifier sur ta version d'OpenTofu.)
3. `tofu plan` montre alors **seulement** la destruction des objets NetBox (`netbox_*.infoger["legacy-rdv01"]`) et DNS (`module.dns_infoger["legacy-rdv01"]`) : `tofu apply`, puis plan vide.
4. Le bloc `import` (sur `local.vms_infoger`) suit tout seul. L'enregistrement `rdv` (CNAME) reste : il sert les cabinets (Kubernetes).

Autres dépôts : `group_vars/role_lb/legacy-rdv.yml` (cible `vm` retirée, `legacy_rdv_cible: k8s` seule), `group_vars/env_f4/infoger.yml` (flux de legacy-rdv01 retirés), sonde blackbox de `legacy-rdv01` retirée de `plateforme/observabilite`, travail PBS `f4-infoger` réduit à 3402,3403, exceptions EXC-H-034 (pour 3401) et EXC-H-035 **closes** au registre.
