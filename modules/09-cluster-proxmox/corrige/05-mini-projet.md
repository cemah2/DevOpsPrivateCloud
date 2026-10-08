# Module 09 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M09-E46 — Mini-projet : virtualisation MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, une procédure de reconstruction de référence, les mesures attendues, la **grille de revue** et la grille du nettoyage d'après-recette. Les fichiers de référence sont ceux des exercices du module (`corrige/fichiers/M09-EXX/`) ; nouveaux ici : [`infra/hv/Taskfile.yml`](fichiers/M09-E46/infra/hv/Taskfile.yml) (reconstruction chronométrée) et le modèle [`docs/virtualisation/hv-par1.md`](fichiers/M09-E46/medisphere/docs/virtualisation/hv-par1.md).

**Points non testés en conditions réelles** : durée totale d'une reconstruction (estimée, voir ci-dessous). Le Taskfile appelle les playbooks des exercices (`hv.yml`, `hv-cluster.yml`, `hv-certificats.yml`) et quatre playbooks **à écrire pendant le mini-projet** pour ce que les exercices ont fait à la main (`hv-formation.yml`, `hv-ceph.yml`, `hv-securite.yml`, `hv-services.yml`) : c'est le cœur de l'étape 1.

**Solution**

*Plan de travail recommandé*

1. **État des lieux** (1-2 h) : `lab/bin/check 09 46` sur le cluster actuel, puis les contrôles détaillés rouges. Inventaire des écarts entre le réel et le code :
   ```
   root@hv01:~# find /etc/pve -newer /etc/pve/corosync.conf -type f | sort       # ce qui a bougé depuis la formation du cluster
   root@hv01:~# pvesh get /cluster/options --output-format json
   root@hv01:~# pveum acl list ; pveum user list --full 1 ; ha-manager rules config ; pvesh get /cluster/sdn/zones
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/hv.yml --check --diff            # changed=0 attendu
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/hv-cluster.yml --check --diff
   admin@adm01:~/src/infra/hv$ tofu plan                                                        # No changes attendu
   ```
   Écarts typiques à ce stade : une règle HA ou une ressource ajoutée à la main en E13/E24 ; l'identité de supervision créée avant le rôle ; un réglage SDN fait dans l'interface ; Ceph installé à la main en Squid en E10 (à décrire dans un playbook, directement en `tentacle`), cluster formé à la main en E04/E08 ; le jeton PBS ; la mise à jour de `/etc/hosts` ; une règle de pare-feu ajoutée pendant un diagnostic. Chacun devient une MR, ou une ligne « manuel assumé » dans `hv-par1.md` avec son runbook (la création des **jetons** — secret affiché une fois — est le cas typique d'un geste manuel assumé et documenté).
2. **Outillage de la reconstruction** (2-4 h) : le [Taskfile](fichiers/M09-E46/infra/hv/Taskfile.yml) enchaîne les étapes dans l'ordre et horodate chacune dans `reconstruction.log`. Ordre et raisons :
   1. VMs (OpenTofu `hv`) : le plan **se relit** en MR ; dans le lab, `APPLY_LOCAL=1` est permis et noté.
   2. Installation automatique (ISO préparée, fichier de réponse servi par `adm01`, M09-E03) : attente SSH par la clé de `adm01`.
   3. Nœuds et cluster : `hv.yml` (rôle `pve_noeud` : dépôts, NTP, chien de garde, SSH, mémoire), `hv-formation.yml` (`pvecm create` sur `hv01`, `pvecm add` sur les autres, seulement si le nœud n'est pas déjà membre), `hv-cluster.yml` (rôle `pve_cluster` : VIP, options du datacenter, supervision). Les nœuds doivent être à la **même** version de paquets avant `pvecm add`.
   4. Ceph Tentacle (MON, MGR, OSD, pool `ceph-vm`, `osd_memory_target`) et attente de `HEALTH_OK`.
   5. Sécurité : `pve_pare_feu` **après** Ceph et la VIP (il les contrôle), puis certificats (`hv-certificats.yml`, la VIP doit exister).
   6. Services : stockage `pbs-par2` (empreinte et jeton de Vault), sauvegarde de configuration, SDN (zones, VNets, EVPN, application), groupes, pools, ACL, HA (ressources et règles), réplication, `ms-verif-cluster` reconfiguré si besoin.
   7. Invités : `hv-invites` (template 199, invités sans état) et restaurations PBS (invités à état).
   8. Vérification : sonde puis `lab/bin/check 09 46`.
3. **Répétition** (une demi-journée) : la reconstruction **complète une première fois**, en notant chaque intervention ; corriger le code ; recommencer jusqu'à zéro intervention (ou des interventions toutes assumées et documentées).
4. **Sauvegardes et test de restauration** avant la destruction finale :
   ```
   root@hv01:~# vzdump 101 110 --storage pbs-par2 --mode snapshot
   root@hv01:~# qmrestore pbs-par2:backup/vm/101/<DATE> 128 --storage ceph-vm --unique 1    # VMID libre, réseau débranché
   root@hv01:~# qm set 128 --net0 virtio,bridge=vmbr1,link_down=1 ; qm start 128 ; qm guest cmd 128 ping ; qm stop 128 ; qm destroy 128 --purge
   ```
   (101 `app01`, VM HA sur `ceph-vm`, et 110 `rep01`, VM répliquée, du palier 2 ; 128 : VMID libre de test, réservé au palier 3 et inutilisé (191-197 sont aux pannes) ; `--unique 1` change les adresses MAC, `link_down=1` évite tout conflit d'adresse avec l'original.)
5. **Reconstruction de recette** chronométrée, puis **essais fonctionnels** (§ 5 de l'énoncé), consignés dans `reconstruction-hv-par1.md`.
6. **Documentation et livraison** : `hv-par1.md` (modèle), runbooks, ADR-0090, matrices des flux, registre des secrets ; pipelines verts ; étiquette `virtualisation-v1`.
7. **Nettoyage** après la recette (voir plus bas).

*Mesures attendues (lab, ordre de grandeur)*

| Étape | Durée typique | Ce qui la domine |
|---|---|---|
| T1 VMs | 2-3 min (+ pipeline) | création des disques sur `ssd-lab` |
| T2 installation automatique | 10-15 min | installation de Proxmox VE (en parallèle sur les trois nœuds) |
| T3 nœuds et cluster | 8-12 min | mises à jour de paquets, `pvecm add` successifs |
| T4 Ceph | 10-15 min | installation des paquets, création des OSD, mise en place des PG |
| T5 sécurité | 5 min | contrôles du pare-feu, émission des certificats (VIP déplacée trois fois) |
| T6 services | 5-10 min | SDN, HA, réplication initiale (complète) |
| T7 invités | 5-15 min | restaurations PBS (débit du tunnel `wg0`) |
| **Total** | **≈ 50 min à 1 h 20** | |

Une reconstruction au-delà de 2 h, ou qui demande des corrections en direct, n'est pas recettable : c'est le code qu'il faut reprendre.

*Démonstration de référence pour la revue*

| Démonstration | Pour | Preuve |
|---|---|---|
| Reconstruction (journal de la répétition et de la recette, extraits commentés) | Karim, Claire | `reconstruction.log`, MR et pipelines |
| Perte de `hv02` (`qm stop 2092` sur `pve01`) avec `mesure-coupure.sh` sur une VM HA | Nadia | RTO mesuré (≈ 2 min 30), RB-091 déroulé jusqu'au § 1 |
| Tentative de connexion à 8006 depuis `gw01`, TOTP, certificat de la VIP, registre des secrets | Sophie | refus, connexion à deux facteurs, `openssl s_client` avec la seule racine MédiSphère |
| « Je veux 4 VMs de 2 Go pour la recette » | Julien | `ms-capacite-cluster --demande 4x2048`, puis ADR-0090 : réponse argumentée (Proxmox ou OpenStack) |

**Explications**

Reconstruire depuis le code est le seul test qui prouve que le code **est** la plateforme. Tant qu'un cluster vit depuis longtemps, il accumule de l'état non décrit (un réglage d'urgence, une ACL « temporaire ») ; le jour où il faut le reconstruire (PRA, matériel neuf, nouveau site), ces écarts deviennent des heures de panne. La mesure du temps sert deux fois : elle donne un **RTO de plateforme** réaliste (utile au PRA, F5) et elle montre où investir (installation, récupération Ceph, restaurations). L'ordre des étapes n'est pas arbitraire : chaque étape consomme ce que la précédente produit (la VIP avant les certificats qui la nomment, Ceph avant un pare-feu qui vérifie sa santé, les stockages avant les restaurations).

**Alternatives**
- Pipeline de `plateforme/infra` qui fait tout (déclenché par une étiquette) au lieu d'un Taskfile lancé depuis `adm01` : meilleure traçabilité, mais le runner doit joindre les nœuds et `pve01` et disposer des identités nécessaires ; à viser pour F1.
- Image disque pré-installée des nœuds (Packer, comme les images dorées de M03) au lieu de l'installateur automatique : plus rapide (pas d'installation), mais une image de nœud Proxmox à maintenir ; l'installateur automatique est la voie supportée pour du matériel réel (PXE avec `prepare-iso --pxe` en 9.2).
- Restaurer les invités plutôt que les recréer : obligatoire pour les invités à état ; pour les autres, les recréer par le code prouve davantage.

**Pièges classiques**
- Détruire avant d'avoir **restauré** une sauvegarde au moins une fois (une sauvegarde non testée n'est qu'un espoir), ou sans avoir la clé de chiffrement hors du cluster.
- Croire que `tofu plan` « No changes » prouve l'absence d'écart : OpenTofu ne voit que ce qu'il gère (pas `/etc/pve`, pas Ceph).
- Laisser une valeur de l'ancien cluster dans le code : empreinte de certificat de nœud, `fsid` de Ceph, clé d'hôte dans un `known_hosts`, identifiant de jeton.
- Oublier `ceph01-03` démarrées depuis E12 : budget mémoire dépassé, `pve01` qui échange.
- Nettoyer `pbs01` sans consigner la commande de retour arrière, ou purger `par1/hv` sans décision écrite.

**En production chez MédiSphère**
La reconstruction complète devient un exercice semestriel (sur un environnement de test), son temps est suivi comme un indicateur, et son journal est une pièce du dossier HDS (capacité à reconstruire l'hébergement). La v1 sera reconstruite dans F1 avec le reste de la plateforme.

**Grille de revue (auto-évaluation si tu travailles seul)**

| Relecteur | Critère | Attendu |
|---|---|---|
| Claire | Contrôle global | `lab/bin/check 09 46` entièrement vert, sans contrôle ignoré |
| Claire | Reconstruction | journal complet, temps total mesuré, gestes manuels nuls ou assumés et documentés |
| Claire | Points uniques de défaillance | listés dans `hv-par1.md`, avec ce que les modules suivants traiteront |
| Karim | Code | `--check` à `changed=0` après reconstruction, `tofu plan` « No changes », ansible-lint `production`, rôles réutilisés (pas de doublon) |
| Karim | Ceph | Tentacle installé directement, `HEALTH_OK`, `size 3 / min_size 2`, `osd_memory_target` |
| Sophie | Sécurité | pare-feu (preuve depuis `gw01`), TOTP, certificats de la PKI sur nœuds et VIP, SSH sans mot de passe |
| Sophie | Secrets | registre complet (jetons PVE et PBS, clé de chiffrement, comptes ACME), aucun secret dans les dépôts ni dans `reconstruction.log` |
| Nadia | Résilience | perte de nœud mesurée (RTO), RB-090-092 à jour, runbooks du palier 4, restauration PBS testée |
| Nadia | Supervision | `ms-verif-cluster` au vert et branchée sur l'alerte ; tableau des indicateurs pour M21 |
| Julien | Usage | réponse argumentée à une demande (capacité, ADR-0090) |
| Tous | Présentation | 10 minutes : ce qui a changé, mesures, risques, ce que la suite consommera |

**Nettoyage de `pbs01`** (⚠️ serveur de sauvegarde du site : hors de la fenêtre des sauvegardes nocturnes, session SSH gardée ouverte ; retour arrière : `apt install corosync-qnetd`, inutile puisque le cluster est détruit). Le service est arrêté et désactivé, et la règle 5403 retirée, depuis M09-E08 ; il reste le paquet :

```
root@pbs01:~# systemctl is-enabled corosync-qnetd; systemctl is-active corosync-qnetd   # disabled, inactive (E08)
root@pbs01:~# apt purge corosync-qnetd && apt autoremove --purge
root@pbs01:~# ls /etc/corosync/qnetd 2>/dev/null || echo "rien"                            # base NSS de l'arbitre
root@pbs01:~# ss -tlnp | grep -c ':5403 ' ; nft list ruleset | grep -c 5403                 # 0 et 0
root@pbs01:~# proxmox-backup-manager task list --limit 3                                     # le PBS travaille toujours
```

Si la base NSS de `/etc/corosync/qnetd/` a survécu à la purge, supprime ce dossier (il ne contient que l'autorité et le certificat de l'arbitre, sans usage hors QDevice). Clos CHG-1005 par une ligne « paquet désinstallé le `<date>` (M09-E46) ».

**Grille du nettoyage d'après-recette** (auto-évaluée, pas de contrôle automatique)

| Point | Attendu | Comment le constater |
|---|---|---|
| Cluster détruit par le code | VMs 2091-2093 absentes ; objets NetBox et enregistrements DNS retirés par la même chaîne | `qm status 209N` sur `pve01` (erreur), `dig hv01.par1.medisphere.internal` (NXDOMAIN), NetBox |
| Supervision | minuterie `ms-verif-cluster` arrêtée et désactivée (ou configuration vidée, avec la raison) ; aucune alerte en boucle | `systemctl is-enabled ms-verif-cluster.timer` |
| `pbs01` | `corosync-qnetd` absent ; règle de pare-feu et port 5403 retirés ; matrice de la bordure sans flux vers 5403 | `dpkg -l corosync-qnetd` sur `pbs01` ; `ss -tlnp` ; `pare_feu.yml` |
| `par1/hv` | décision écrite dans `hv-par1.md` (§ 6) ou dans le registre des sauvegardes : par exemple « conservé, dernier instantané de chaque groupe seulement (prune `keep-last 1`), pour F1 ; clé en Vault `critique` et sur papier ; revu à la fin du bloc B » — ou « purgé le JJ/MM, plus aucune donnée » | listage de l'espace de noms sur PBS |
| Flux et code | lignes de la bordure propres au cluster conservées (le cluster sera reconstruit) mais commentées « cluster détruit depuis le … » — ou retirées, au choix, avec la raison | `pare_feu.yml` |
| Mémoire de `pve01` | revenue au profil « socle » | `free -g` sur `pve01` |

Une livraison est acceptée quand tous les critères sont remplis ; un critère manquant devient une action (responsable, échéance) dans le compte rendu de recette.
