# RB-343 — Mettre à jour ceph-par1 sous charge (corrective ou système des hôtes)

| | |
|---|---|
| Complète | RB-082 (mise à jour de Ceph par cephadm, M08-E26) |
| Fiche type | CHG-3407 |
| Prérequis | `HEALTH_OK`, deux mgr, trois mon, sauvegarde PBS `par1/ceph` vérifiée, sonde active (RB-340) avec le groupe `continuite-rgw` |

## 1. Choisir la variante

- **ceph-orch** : une corrective Tentacle plus récente que celle en service existe (notes de version, avis de sécurité, étapes « critiques » éventuelles). → §2.
- **systeme** : pas de corrective, mais des mises à jour Rocky Linux 10 en attente (`dnf check-update` sur chaque hôte). → §3.

## 2. Variante ceph-orch (sous charge)

RB-082 §2 à §5, avec en plus : la sonde tourne pendant toute l'opération ; image tirée d'avance sur **chaque** hôte ; `ceph osd pool set noautoscale` pendant, `unset` après ; mise à jour **échelonnée** (`--daemon-types mgr` d'abord) ; une pause volontaire au milieu des OSD pour lire la sonde ; MR `ceph_image`/`ceph_noeud_version` fusionnée après.

## 3. Variante systeme (un hôte à la fois)

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/ceph-roulement-systeme.yml --limit ceph03
```

Ce que fait le playbook pour chaque hôte : `HEALTH_OK` → bascule du mgr actif s'il est sur l'hôte → `ceph orch host maintenance enter` (cephadm vérifie que l'arrêt est sans danger, pose `noout` sur l'hôte, arrête ses démons) → `dnf` (sauf `cephadm`, `ceph-common`) → redémarrage → `maintenance exit` → attente de `HEALTH_OK`. Un hôte à la fois, jamais le suivant tant que le précédent n'est pas revenu.

Équivalent à la main, pour comprendre : `ceph osd set noout` (ou `ceph osd set-group noout <hôte>`), arrêt propre de l'hôte, mise à jour, redémarrage, `ceph osd unset noout`, attente de `HEALTH_OK` ; sans `noout`, au bout de `mon_osd_down_out_interval` (10 min par défaut) les OSD sont marqués *out* et Ceph recopie des données pour rien.

## 4. Mesurer

Sonde (RB-340) ; en plus : `ceph -s` toutes les minutes dans le journal ; erreurs d'écriture de Loki et de Thanos ; latence des PVC (`ceph osd perf`).

## 5. Si ça coince

- `maintenance enter` refusé : lire le message (ok-to-stop d'un mon ou d'un OSD, mgr actif) ; ne pas forcer (`--force`) sous charge.
- Hôte qui ne revient pas : console série (`qm terminal <VMID>` sur `pve01`), noyau précédent ; le cluster tient sur deux hôtes, mais **aucune autre maintenance** tant que le troisième n'est pas revenu.
- `HEALTH_OK` qui ne revient pas : `ceph health detail`, `ceph pg dump_stuck` ; drapeaux restés posés (`ceph osd dump | grep flags`) ; hôte resté en maintenance (`ceph orch host ls`).

## 6. Après

`ceph orch host ls` (aucune maintenance), aucun drapeau `noout`/`norebalance`, autoscaler actif, mesure dans la fiche, `lab/bin/check F4 7`.
