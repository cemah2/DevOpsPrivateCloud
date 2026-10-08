# MR !4 — feat(par2): cluster Ceph du site de secours (ceph21-23) et passerelle S3

**Auteur** : Lucas Martin — **Relecteur** : Karim Benali

Salut Karim,

Voici les spécifications cephadm du cluster de PAR2 (`ceph-par2`). Tout est testé sur trois VMs de
la sandbox (4 Go chacune) : `ceph orch apply -i` passe sur chaque fichier, `ceph -s` est en
HEALTH_OK, et j'ai pu envoyer un fichier en S3 avec la clé de démo.

Choix que j'ai faits :
- **deux moniteurs** seulement : sur un petit site, un troisième ne sert à rien et consomme de la
  mémoire ;
- `osd.yaml` prend **tous** les disques disponibles : comme ça, quand on ajoute un disque, il entre
  tout seul dans le cluster, pas besoin d'y penser ;
- j'ai monté `osd_memory_target` à 4 Gio pour que BlueStore ait du cache : les benchs sont bien
  meilleurs ;
- pour économiser de la place (c'est un site de secours), les pools sont en **réplication ×2** ;
- le RGW écoute directement en 443 (pas besoin de retenir un port bizarre), avec l'ingress devant
  pour la VIP ;
- j'ai mis le certificat dans `ingress.yaml` pour que le dépôt soit « complet » (c'est un certificat
  de test de toute façon) ;
- `pbs01` aura besoin de lancer des commandes `ceph` pour ses sauvegardes : je l'ai ajouté comme
  hôte avec l'étiquette `_admin`, c'est le plus simple pour qu'il ait la configuration et la clé ;
- la règle CRUSH `par2-ssd` est dans `crush-ajouts.txt` (je l'ai injectée avec `crushtool -c` puis
  `ceph osd setcrushmap`).

Pour appliquer : `pools.sh` puis `ceph orch apply -i` sur chaque fichier.

Lucas
