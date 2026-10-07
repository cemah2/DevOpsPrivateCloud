<!-- EXTRAIT (M05-E02) — section à AJOUTER à la fin du CONTRIBUTING.md commun (copié de
     plateforme/outils) dans plateforme/infra. Le reste du guide est inchangé. -->

## 10. Règles propres à `plateforme/infra`

Ce dépôt ne publie pas de version : il **décrit** l'infrastructure, et une fusion dans `main`
est une demande de changement **réel**. D'où des règles en plus.

- **Le plan est la pièce principale de la MR.** La description contient la sortie de
  `tofu plan` (ou, à partir de M05-E26, le plan produit par le pipeline) et une phrase par
  ressource détruite ou remplacée : pourquoi, et ce qu'on perd. Un plan qui détruit sans
  explication est refusé (raison : `-/+` sur une VM, c'est un disque qui disparaît).
- **On applique ce qui est sur `main`.** Après fusion : `git switch main && git pull`, puis
  `tofu plan` (il doit montrer exactement ce que la MR annonçait), puis `tofu apply`.
  Exception tolérée : la mise au point sur les VMs d'environnement (VMID 2xxx) depuis une
  branche, à condition qu'un `tofu plan` depuis `main` soit vide une fois la MR fusionnée.
- **Un seul `apply` à la fois par état.** Tant que l'état est local (jusqu'à M05-E11), on
  n'applique que depuis `adm01`, dans le clone `~/src/infra`.
- **Pas de modification à la main** (interface web, `qm set`) d'une ressource décrite ici : elle
  serait annulée au prochain `apply`, ou pire, ferait recréer la ressource. Une urgence corrigée
  à la main est reportée dans le code le jour même (raison : la dérive).
- **L'état ne se modifie jamais à la main** (éditeur, `jq`) : uniquement par les commandes
  `tofu state …`, `tofu import`, ou les blocs `import`, `moved`, `removed`, après une copie de
  sauvegarde de l'état (raison : un état corrompu, c'est une infrastructure qu'on ne sait plus
  gérer).
- **Versions** : OpenTofu `~> 1.13.0`, provider `bpg/proxmox` `~> 0.115.0`, et
  `.terraform.lock.hcl` versionné. Une montée de version (même un correctif du provider) est une
  MR à elle seule, avec le plan avant/après.
- **Commits** : portée = la configuration touchée (`feat(lab-m05): …`, `fix(socle): …`).
- **Secrets** : jamais dans une variable versionnée ; les accès viennent de l'environnement
  (`PROXMOX_VE_*`). Une valeur marquée `sensitive` reste en clair dans l'état : l'état est un
  secret (raison : M05-E09, E27).
