# RB-081 — Ajouter (ou retirer) un nœud du cluster `ceph-par1`

| | |
|---|---|
| Service | Stockage distribué `ceph-par1` |
| Public | Équipe Plateforme (changement planifié, jamais en astreinte) |
| Déclencheur | Politique de stockage : occupation brute ≥ 40 %, demande d'allocation qui ne tient pas, renouvellement de matériel |
| Durée | 1 h de gestes + rééquilibrage (≈ 1/6 des données stockées par nœud ajouté dans une baie existante) |
| Version | 1.0 — `<DATE>` — `<MOI>` (CHG-928, M08-E18) — joué sur `ceph04` (ajout E18, retrait E46) |

> Ce runbook est générique : remplace `<NOEUD>` (ex. `ceph05`), `<VMID>`, `<IP-PUB>` (10.10.30.x),
> `<IP-CLU>` (10.10.31.x) et `<BAIE>` (`par1-baie-a|b|c`). Une **fiche de changement** (modèle : CHG-928)
> est obligatoire : elle porte les valeurs, l'estimation et le résultat.

## 0. Préalables

- [ ] `ceph -s` : `HEALTH_OK`, tous les PG `active+clean`, aucun drapeau (`noout`, `norebalance`…).
- [ ] Marge mémoire de l'hyperviseur (6 Go par nœud au lab).
- [ ] Spécification OSD par étiquette (`placement: label: osd`, `specs/osd.yaml`) : le nouveau nœud sera couvert dès l'étiquette posée.
- [ ] Estimation dans la fiche : part de la capacité de la baie apportée par le nœud. Domaine de panne `rack` : chaque baie porte **une** copie de chaque PG ; un nœud ajouté dans une baie de `n` nœuds identiques reçoit `1/(n+1)` des copies de cette baie.
- [ ] Débit de récupération mesuré récemment (`ceph -s` pendant un *backfill*, ou E29) → durée estimée.

## 1. La machine, par le code

1. MR sur `plateforme/infra` (état `ceph`, variable `noeuds_ceph` du module `vm-noeud`) : VMID, deux cartes (VLAN 30 et 31, MTU 9000), disques OSD avec numéros de série `<NOEUD>-ssd1`, `-ssd2`, `-hdd1`. Pipeline, puis `apply`.
2. NetBox et DNS par le même code : `dig +short <NOEUD>.par1.medisphere.internal` → `<IP-PUB>`.
3. Rôle `ceph_noeud` (playbook `ceph-noeuds.yml --limit <NOEUD>`) : dépôt et paquets de la **version du cluster** (`ceph_noeud_version`), Podman, chrony, LVM, clé publique de l'orchestrateur pour le compte `cephadm`.
4. Contrôles, sur le nœud :
   ```
   [admin@<NOEUD> ~]$ ping -c 2 -M do -s 8972 10.10.30.51 && ping -c 2 -M do -s 8972 10.10.31.51
   [admin@<NOEUD> ~]$ lsblk -o NAME,SIZE,ROTA,SERIAL      # disques OSD vides, ROTA 0 pour les SSD
   [admin@ceph01 ~]$ sudo ceph cephadm check-host <NOEUD> <IP-PUB>
   ```

## 2. Entrée dans le cluster

1. Limiter l'impact (optionnel, recommandé hors lab) :
   ```
   [admin@ceph01 ~]$ sudo ceph config set osd osd_crush_initial_weight 0
   ```
2. MR sur `plateforme/ceph` : document `<NOEUD>` dans `specs/hosts.yaml` (`addr: <IP-PUB>`, étiquette `osd`, `location: {rack: <BAIE>}`) et ajout de l'hôte dans la hiérarchie attendue de `config/cluster.yaml`. Pipeline vert, fusion.
3. Sur `adm01` : `outils/appliquer.sh specs/hosts.yaml` (relire le `--dry-run`, répondre « oui »).
4. Suivi : `ceph orch host ls`, `ceph orch ps <NOEUD>`, `ceph osd tree` (OSD sous `<BAIE>` → `<NOEUD>`).
5. Si poids initial nul : `ceph osd crush reweight osd.<ID> <POIDS>` par paliers (la moitié, puis la taille en Tio, ≈ 0,0625 pour 64 Gio), `HEALTH_OK` entre deux paliers. Puis :
   ```
   [admin@ceph01 ~]$ sudo ceph config rm osd osd_crush_initial_weight
   ```

## 3. Fin

- [ ] `<NOEUD>` dans `<BAIE>`, ses OSD `up`/`in` avec leur poids normal, `HEALTH_OK`.
- [ ] Réglages temporaires retirés (`ceph config dump | grep -E 'crush_initial_weight|mclock_profile'` vide).
- [ ] Nombre d'OSD attendu mis à jour dans la sonde (`MS_CEPH_OSDS` de `ms-verif-ceph.conf`, MR `plateforme/outils`).
- [ ] Dérive : `outils/derive.sh` et `outils/config-cluster.sh --verifier` sans écart. Fiche fermée.

## 4. Retirer un nœud

1. Préalables : `HEALTH_OK` ; la capacité restante absorbe les données du nœud (`ceph osd df tree` : occupation des autres nœuds de la **même baie** après report) ; le nœud ne porte ni MON ni `_admin` (sinon, changer d'abord les spécifications).
2. Vider :
   ```
   [admin@ceph01 ~]$ sudo ceph orch host drain <NOEUD>
   [admin@ceph01 ~]$ sudo ceph orch osd rm status          # répéter jusqu'à liste vide ; HEALTH_OK
   [admin@ceph01 ~]$ sudo ceph orch ps <NOEUD>              # plus aucun démon
   ```
3. Retirer : `sudo ceph orch host rm <NOEUD>`, puis `sudo ceph osd crush rm <NOEUD>` si le seau d'hôte vide reste dans la carte.
4. Le code : MR `plateforme/ceph` (document retiré de `hosts.yaml`, hiérarchie de `config/cluster.yaml`), MR `plateforme/infra` (VM détruite, NetBox et DNS retirés par le même code), `MS_CEPH_OSDS` de la sonde.
5. Contrôle : `ceph osd tree` sans `<NOEUD>`, `HEALTH_OK`, dérive sans écart.

## 5. Retour arrière

- Avant toute donnée sur le nœud (poids 0) : `ceph orch host drain`, `ceph orch host rm`, MR de retrait. Aucun mouvement de données.
- Après remplissage : poids à 0 (`ceph osd crush reweight`), attendre `HEALTH_OK` (les données reviennent), puis comme ci-dessus.

## Interdits

`ceph osd purge` ou `ceph orch osd rm --zap` sur un OSD non vidé ; retirer deux nœuds d'une même baie à la suite ; ajouter un nœud pendant une récupération ; entrer un nœud dans la mauvaise baie (corriger avec `ceph osd crush move` = second mouvement de données : vérifier `location` **avant** d'appliquer).
