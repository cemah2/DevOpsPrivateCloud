# Final F4 — Introduction : le trimestre des changements

## Lundi, 9 h

Claire Morel a réservé la grande salle et écrit trois lignes au tableau : « InfoGér : fin du contrat dans six semaines. Audit HDS : systèmes maintenus. Cabinets : ne rien voir. » Puis elle distribue les sujets.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Le trimestre des changements
>
> Bonjour,
>
> Nous avons six semaines pour faire ce que nous avons repoussé tout l'été :
> 1. **monter** ce qui doit l'être : Kubernetes (si toute la chaîne suit), les composants de la plateforme, Ceph, OpenStack ;
> 2. **sortir les dernières VMs d'InfoGér** de leur VMware et les faire tourner chez nous ;
> 3. **sortir Legacy-RDV de sa VM** : quarante cabinets l'utilisent encore tous les jours.
>
> Une règle pour tout le trimestre : **aucun changement sans fiche, sans mesure et sans retour arrière**. Je veux pouvoir dire à l'audit, chiffres à l'appui, combien de secondes nos utilisateurs ont perdu à chaque opération. Karim construit la sonde qui les comptera. Julien et Nadia négocient les fenêtres. Et si une montée n'est pas prête, je préfère un « non » argumenté à un « oui » courageux.
>
> Claire

---

## Ce que tu construis dans ce final

À la fin de F4, MédiSphère sait **conduire un changement** et l'a prouvé sur quatorze scénarios. L'étiquette `changements-v1` de `plateforme/medisphere` est posée en F4-S14.

| Phase | Fichier | Scénarios | Ce qui en sort |
|---|---|---|---|
| 1. Gouverner | [`01-gouverner.md`](01-gouverner.md) | S01-S02 | processus de changement, modèle de fiche CHG, **sonde de continuité** |
| 2. Montées | [`02-montees.md`](02-montees.md) | S03-S08 | décision écrite sur Kubernetes, montées (cluster, composants, Ceph, OpenStack) mesurées, une panne de montée réparée |
| 3. Migrations | [`03-migrations.md`](03-migrations.md) | S09-S13 | VMs d'InfoGér sur `pve01`, Legacy-RDV sur Kubernetes, bascule de production |
| 4. Bilan | [`04-bilan.md`](04-bilan.md) | S14 | revue des changements, décommissionnement, `changements-v1` |

Un final ne réenseigne rien : il **combine** ce que tu as construit aux modules 08 (Ceph), 10 (OpenStack), 14 (montée de version de Kubernetes), 16 (stockage), 20 (GitOps), 21 (métriques, SLO), 26 (politiques), 27 (données) et 29 (k6, chaos). Les énoncés donnent objectifs, contraintes et critères ; les commandes sont dans tes runbooks.

---

## État d'entrée

| Élément | État attendu | Contrôle |
|---|---|---|
| Plateforme | étiquette **`day1-v1`** (F2) posée sur `plateforme/medisphere` : socle v5, `ceph-par1`, `k8s-par1` avec tous les services des blocs C à G, équipes MédiVisio et Data accueillies | `lab/bin/check F2 13` |
| Astreinte | F3 terminé si tu l'as fait (`astreinte-v1`) ; aucune panne active (`ls ~/.local/state/workbook/pannes-actives/` vide) | — |
| Versions | Kubernetes **1.36.5**, Cilium **1.20.3**, Ceph **20.2.4**, OpenStack **2026.1** / Kolla-Ansible **22.2.0**, Argo CD **3.5.5**, Kyverno **1.19.2**, CloudNativePG **1.30.1**, KEDA 2.21, Capsule 0.15 | `kubectl version`, `ceph versions`, `uv.lock` de `plateforme/openstack` |
| Outils | k6 1.8 et k6-operator 1.7 (M29), Prometheus témoin et blackbox sur `mon01` (M21), Pyrra (M21), composant CI/CD `validation` et paquet `schemas-crd` (M29) | `lab/bin/check 29 14`, `lab/bin/check 21 11` |
| Profil openstack | arrêté ou détruit depuis la recette `cloud-v1` ; reconstructible depuis `plateforme/openstack` (`outils/deployer.sh`) et sa sauvegarde PBS `par1/openstack` | — |

---

## Le calendrier et ses contraintes

Le contrat d'InfoGér s'arrête dans **six semaines**. Ce que Claire, Julien et Nadia ont fixé (tu en feras un calendrier écrit en S01) :

- Les montées passent **avant** la migration : on n'accueille pas Legacy-RDV sur une plateforme qu'on s'apprête à remuer.
- **Fenêtres** : mardi et jeudi de 20 h à 23 h ; samedi de 8 h à 14 h pour ce qui est long (OpenStack, migration des VMs). Jamais deux changements sur un même domaine (cluster, stockage, cloud, réseau) dans la même fenêtre : la sonde doit pouvoir attribuer une interruption à **un** changement.
- **Gel** : 48 h après la bascule de Legacy-RDV (la VM d'origine doit rester prête pour un retour arrière) ; du 18 décembre au 4 janvier.
- Nadia prévient les quarante cabinets de Legacy-RDV **une semaine** avant la bascule.

---

## Les règles du changement (valables pour chaque scénario)

1. **Une fiche avant d'agir.** Chaque changement a sa fiche `docs/changements/fiches/CHG-34xx-<sujet>.md`, ouverte par MR **avant** la fenêtre, complétée après. Son en-tête suit le modèle que tu écris en S01 : les checks des scénarios suivants le lisent (voir « Conventions » ci-dessous).
2. **Une mesure, toujours.** La sonde de continuité (S02) tourne pendant toute fenêtre ; l'objectif d'interruption est écrit **avant** le go et ne se corrige jamais après coup.
3. **Un retour arrière testé**, ou une limite écrite (« une montée de plan de contrôle ne se défait que par restauration d'etcd »).
4. **Tout par le code et la CI.** Versions, valeurs et inventaires changent par MR (`plateforme/k8s`, `plateforme/gitops`, `plateforme/charts-miroir`, `plateforme/ansible`, `plateforme/openstack`, `plateforme/infra`). Les MR qui décrivent l'état **d'après** sont fusionnées **après** le changement, quand le code décrit la réalité (règle du M08 et du M14). Un geste à la main n'existe que s'il est écrit comme exception dans la fiche.
5. **La chaîne d'abord.** On ne monte pas un composant que quelque chose qui en dépend ne déclare pas compatible. Si la chaîne n'est pas prête, **la décision no-go est la bonne réponse**, et l'on fait ce qui est prêt.

> ⚠️ **Attention** : ce final touche la **production** du lab (cluster, Ceph, OpenStack). Avant chaque fenêtre : sauvegardes **vérifiées** (instantané etcd, PBS, CNPG `Completed`, base d'OpenStack), aucune panne active, aucune expérience de chaos en cours (`plateforme/resilience/outils/chaos-arret.sh`). Les pannes injectées par ce final (`lab/bin/break F4 …`) ne s'injectent que si le lab est sain et se lèvent par `--annuler`.

---

## Mémoire : les profils de F4

| Moment | Profil | Mémoire approx. |
|---|---|---|
| S01 à S07, S12 à S14 | socle v5 + `ceph-par1` + `k8s-par1` (profil de travail des blocs F et G) | ≈ 111 Go |
| S08 (OpenStack) | socle v5 + `ceph-par1` + profil **openstack**, **`k8s-par1` arrêté** (ordre d'arrêt de `lab/topologie.md` : travailleurs 2146, 2145, 2144, puis nœuds de contrôle 2143, 2142, 2141 ; démarrage dans l'ordre inverse, `ceph-par1` en `HEALTH_OK` d'abord) | ≈ 101 Go |
| S09 à S11 | profil de travail + VMs migrées d'InfoGér (≤ 4 Go en tout) | ≈ 115 Go |

Arrêter `k8s-par1` arrête, **dans le lab**, MédiAgenda et les autres services du cluster. C'est une contrainte de mémoire du lab, pas un choix de la fiction : la fiche de S08 le dit, et sa mesure ne porte que sur ce qu'OpenStack sert.

---

## Hôtes, objets et versions cibles

| Élément | Valeur | Scénarios |
|---|---|---|
| `legacy-rdv01` | VMID **3401**, `vinfra`, **10.10.20.44** (chez InfoGér : `192.168.50.21`) | S09-S14 |
| `ftp-part01` | VMID **3402**, **10.10.20.45** (`192.168.50.30`) | S09-S11 |
| `stats01` | VMID **3403**, **10.10.20.46** (`192.168.50.40`) | S09-S11 |
| Étiquette Proxmox des VMs du final | `env-f4` ; plage VMID 3400-3499 | S09-S14 |
| Legacy-RDV sur Kubernetes | locataire Capsule `legacy`, espaces `legacy-rdv-recette`, `legacy-rdv-prod`, `legacy-rdv.apps.par1.medisphere.internal` ; mariadb-operator 26.6 dans `mariadb-system` | S12, S13 |
| Instance témoin OpenStack | `sonde-fip01` (projet `plateforme`), IP flottante `<FIP-SONDE>` dans 10.10.52.200-249 | S08 |

Versions cibles : [`annexes/versions-finaux-F1-F4.md`](../../../annexes/versions-finaux-F1-F4.md). Elles ont été relevées le 23/10/2026 ; tu feras F4 plus tard, et la règle est de viser **la mineure suivante, ou la dernière corrective, que toute la chaîne déclare compatible** — et de l'écrire dans la fiche. Au relevé :

| Composant | Installé | Cible | Remarque au relevé |
|---|---|---|---|
| Kubernetes | 1.36.5 | 1.37.x | **bloquée** : Cilium 1.20 ne teste que 1.33 à 1.36 ; Cilium 1.21 (1.34 à 1.37) en développement |
| Cilium | 1.20.3 | dernière 1.20, puis 1.21.x | toujours **avant** Kubernetes |
| Argo CD, Kyverno, CloudNativePG | 3.5.5, 1.19.2, 1.30.1 | 3.6, 1.20, 1.31 si publiées | Kyverno 1.20 supprime `ClusterPolicy`, CNPG 1.31 supprime `barmanObjectStore` |
| Ceph | 20.2.4 | dernière corrective Tentacle (≥ 20.2.5) | à défaut : système Rocky Linux 10 des hôtes en roulement |
| OpenStack / Kolla-Ansible | 2026.1 / 22.2.0 | 2026.2 / 23.x stable | Kolla 23 en version candidate au relevé : vérifie la stable |
| mariadb-operator / MariaDB | — | 26.6 / 11.8 | migration de Legacy-RDV (S12-S13) |

---

## Conventions du final

**Documentation** (dépôt `plateforme/medisphere`, par MR) :

| Chemin | Contenu |
|---|---|
| `docs/changements/processus.md` | processus de changement (S01) |
| `docs/changements/fiches/modele.md` | modèle de fiche (S01) |
| `docs/changements/fiches/CHG-34xx-<sujet>.md` | une fiche par changement (`xx` = numéro du scénario : CHG-3404 pour S04…) |
| `docs/changements/sonde-continuite.md` | la sonde (S02) |
| `docs/changements/matrices/compatibilite-kubernetes-<mineure>.md` | matrice de compatibilité (S03) |
| `docs/changements/runbooks/RB-340…` | runbooks du final (RB-340 sonde, RB-341 Kubernetes, RB-342 composants, RB-343 Ceph, RB-344 OpenStack ; la phase 3 continue la série) |
| `docs/changements/post-mortems/INC-60xx-<sujet>.md` | post-mortems des pannes du final |
| `docs/changements/adr/ADR-0340…` | décisions d'architecture du final |

**Tickets** : `CHG-34xx`, `PLAT-34xx`, `INC-60xx` (`xx` = numéro du scénario).

**En-tête des fiches** : un bloc YAML entre deux lignes `---` en tête du fichier. Les checks du final y lisent au moins : `decision` (`go` ou `no-go`), `mesure-source` (`cluster` ou `temoin`), `mesure-groupes` (facultatif), `mesure-debut`, `mesure-fin` (ISO 8601 avec fuseau, ex. `2026-11-10T20:05:00+01:00`), `mesure-objectif-s` et `mesure-interruption-s` (secondes). Ton modèle (S01) peut en avoir d'autres ; il ne doit pas renommer celles-ci. Les checks **recalculent** la mesure à partir de Prometheus sur la fenêtre déclarée et la comparent à ce que tu as noté.

---

## Variables de `lab/lab.env`

Toutes facultatives : les défauts conviennent au lab. Pose-les seulement si tes valeurs diffèrent.

| Variable | Défaut | Utilisée par |
|---|---|---|
| `WB_F4_DOC` | `docs/changements` | tous les checks |
| `WB_F4_PROJET_DOC` | `plateforme/medisphere` | tous les checks |
| `WB_F4_PROJET_RESILIENCE` | `plateforme/resilience` | S02 |
| `WB_F4_PROJET_OBSERVABILITE` | `plateforme/observabilite` | S02 |
| `WB_F4_PROM_TEMOIN_URL` | `http://mon01.par1.medisphere.internal:9090` | S02, S08 (mesure sans le cluster) |
| `WB_F4_TABLEAU_UID` | `f4-changement-en-cours` | S02 |
| `WB_F4_TOLERANCE_S` | `30` | écart admis entre l'interruption notée et celle recalculée |
| `WB_F4_COUVERTURE_MIN` | `0.9` | part minimale de la fenêtre couverte par la mesure |
| `WB_F4_K8S_CIBLE` | `1.37` | S04 (issue « go ») |
| `WB_F4_CILIUM_REFERENCE` | `1.20.3` | S04 |
| `WB_F4_S05_SEUIL` | `3` | S05 (nombre de composants montés) |
| `WB_F4_PROJET_DEPLOIEMENT` | `mediagenda/deploiement` | S06 |
| `WB_F4_FICHIER_KUSTO_RECETTE` | `overlays/recette/kustomization.yaml` | S06 (panne) |
| `WB_F4_CEPH_REFERENCE` | `20.2.4` | S07 |
| `WB_F4_KOLLA_SERIE` | `23` | S08 |
| `WB_F4_OPENSTACK_SERIE` | `2026.2` | S08 |
| `WB_F4_ANSIBLE_CORE_RE` | `^2\.(20\|21)\.` | S08 |

Les checks relisent aussi `WB_PROM_URL`, `WB_GRAFANA_*`, `WB_GITLAB_*`, `WB_K8S_KUBECONFIG`, `WB_CEPH_ADMIN`, `WB_SRC`, `WB_OS_CLOUD`, `WB_TIMEOUT`, et la panne `WB_K8S_ADMIN_KUBECONFIG` et `WB_GITLAB_ADMIN_TOKEN_FILE`. Les phases 3 et 4 ajoutent leurs variables dans [`03-migrations.md`](03-migrations.md).

---

## Pour commencer

Lis [`01-gouverner.md`](01-gouverner.md). Les deux premiers scénarios ne touchent à rien de ce qui tourne : ils fabriquent les règles et l'instrument qui jugeront tout le reste.
