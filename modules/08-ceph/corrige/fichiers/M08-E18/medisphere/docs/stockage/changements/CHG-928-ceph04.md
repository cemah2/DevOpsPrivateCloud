# CHG-928 — Ajout du nœud de stockage `ceph04` au cluster `ceph-par1`

| | |
|---|---|
| Demandeur | Claire Morel (ticket CHG-928) |
| Exécutant | `<MOI>` — relecture : Karim Benali |
| Fenêtre | `<DATE>`, 14 h – 17 h (hors sauvegardes nocturnes) |
| Risque | Moyen : mouvement de données, latence client accrue pendant le rééquilibrage |
| État | Fermé — `<DATE>` |

## Objectif
Ajouter `ceph04` (VMID 2084, 10.10.30.54 / 10.10.31.54) dans la baie `par1-baie-a`, avec ses trois OSD
(deux `ssd`, un `hdd`), sans interruption de service.

## Prérequis (contrôlés avant de commencer)
- [ ] `ceph -s` : `HEALTH_OK`, aucun PG non `active+clean`.
- [ ] Marge mémoire sur `pve01` ≥ 8 Go (`free -g`).
- [ ] Spécification OSD : placement par étiquette `osd` (couvre `ceph04` dès l'étiquette posée).
- [ ] Instantané non nécessaire (aucun hôte du socle touché) ; matrice des flux inchangée (VLAN 30/31).

## Estimation
- Capacité ajoutée : 2 SSD sur 8 (+33 % de SSD), 1 HDD sur 4.
- Domaine de panne `rack` : la baie A reçoit toujours **une** copie de chaque PG ; elle sera répartie
  entre `ceph01` et `ceph04` → environ **la moitié des copies de la baie A** migre vers `ceph04`, soit
  ~1/6 des données stockées du cluster (`ceph df` : `<STOCKÉ>` Gio → ~`<STOCKÉ/6>` Gio à déplacer).
- Débit de *backfill* au lab : `<MESURÉ>` Mio/s (profil mClock `balanced`) → durée estimée `<N>` min.

## Étapes
1. VM par le pipeline de `plateforme/infra` (état `ceph`) ; NetBox (VM, `ens18`/`ens19`, deux adresses) ;
   DNS : `dig +short ceph04.par1.medisphere.internal` → 10.10.30.54.
2. Rôle de préparation des nœuds (Podman, chrony, LVM, clé publique de l'orchestrateur pour le compte `cephadm`).
   Contrôle : `ping -M do -s 8972` vers `ceph01` sur 10.10.30.51 **et** 10.10.31.51.
3. `ceph config set osd osd_crush_initial_weight 0` ; `ceph config set osd osd_mclock_profile balanced`.
4. `hosts.yaml` (document `ceph04`, `location: {rack: par1-baie-a}`) : `--dry-run`, puis application.
5. Contrôle : `ceph orch host ls`, `ceph osd tree` (3 OSD sous `ceph04`, poids 0).
6. Poids en deux paliers (0,03125 puis 0,0625) pour `osd.9`, `osd.10`, `osd.11`, `HEALTH_OK` entre deux.
7. `ceph config rm osd osd_crush_initial_weight` ; `ceph config rm osd osd_mclock_profile`.

## Retour arrière
- Avant l'étape 6 (OSD à poids 0, aucune donnée) : `ceph orch host drain ceph04`, puis
  `ceph orch host rm ceph04`, puis retrait de la VM (MR) et de NetBox. Aucun mouvement de données.
- Après l'étape 6 : remettre les poids à 0 (les données reviennent sur `ceph01`), attendre `HEALTH_OK`,
  puis comme ci-dessus.

## Critères de fin
`ceph04` dans `par1-baie-a`, trois OSD `up`/`in` de poids ≈ 0,0625, `HEALTH_OK`, réglages temporaires
retirés, `specs/hosts.yaml` à jour dans `plateforme/ceph`.

## Résultat
- Début du rééquilibrage : `<HEURE>` ; fin : `<HEURE>` ; volume déplacé : `<Gio>` ; écart à l'estimation : `<…>`.
- Écarts / incidents : `<aucun | …>`.
- Suite : la baie A a désormais deux fois plus de SSD que les baies B et C ; la capacité utile reste celle
  des petites baies (M08-E20). À reprendre dans la politique de stockage (baies équilibrées).
