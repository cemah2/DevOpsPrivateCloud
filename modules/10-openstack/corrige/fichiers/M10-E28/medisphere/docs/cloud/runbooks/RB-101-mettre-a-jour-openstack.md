# RB-101 — Mettre à jour OpenStack (au sein d'une série)

| | |
|---|---|
| Portée | Mise à jour de Kolla-Ansible et des images **dans la série 2026.1** (correctifs). Pas une montée de série (voir §7). |
| Durée | Préparation 1 h (sans interruption) ; fenêtre 1 h ; interruption des API ≈ 10 min avec un contrôleur |
| Qui | Équipe Plateforme (astreinte : exécution possible avec ce document seul) |
| Prérequis | Sauvegarde Mariabackup du jour **vérifiée** (`preparer-sauvegarde.sh verifier`) ; `HEALTH_OK` de `ceph-par1` ; fiche de changement validée |
| Historique | 2026-10-22, CHG-1154, première exécution (voir §8) |

## 1. Ce qui change dans une mise à jour au sein d'une série

- **Kolla-Ansible** (paquet Python du projet `uv` de `plateforme/openstack`) : rôles, gabarits de configuration, valeurs par défaut. Correctifs publiés en versions 22.x.
- **Collections Ansible** de Kolla (`kolla-ansible install-deps`).
- **Images** : l'étiquette `2026.1-debian-trixie` est **mobile** ; les images sont reconstruites depuis la branche stable (correctifs OpenStack et Debian). Seule l'empreinte dit ce qui tourne.

Procédure officielle (*Operating Kolla*) pour une mise à jour au sein d'une série : mettre à jour le paquet `kolla-ansible`, télécharger les images, puis **`deploy`** (pas `upgrade`, réservé au passage d'une série à l'autre : migrations de schémas, ordre de montée des services).

## 2. Préparation (hors fenêtre, sans interruption)

```
admin@adm01:~/src/openstack$ git switch -c conf/maj-kolla-22.x
admin@adm01:~/src/openstack$ uv lock --upgrade-package kolla-ansible        # garde ansible-core < 2.21 (contrainte du projet)
admin@adm01:~/src/openstack$ uv sync --frozen && uv run kolla-ansible --version
admin@adm01:~/src/openstack$ uv run kolla-ansible install-deps
admin@adm01:~/src/openstack$ diff -u inventaire/multinode .venv/share/kolla-ansible/ansible/inventory/multinode | less
admin@adm01:~/src/openstack$ diff -u <(grep -v '^#' etc/kolla/globals.yml | grep .) \
                               <(grep -v '^#' .venv/share/kolla-ansible/etc_examples/kolla/globals.yml | grep .) | less
```

(Le chemin des exemples dans l'environnement virtuel est celui de la documentation *Operating Kolla* ; vérifie-le dans `.venv/share/kolla-ansible/`.)

Lire les notes de version (https://docs.openstack.org/releasenotes/kolla-ansible/2026.1.html) de la version installée à la cible : sections *Upgrade Notes*, *Bug Fixes*, *Security Issues*. Tout changement de défaut qui nous concerne → ligne dans la fiche de changement.

```
admin@adm01:~/src/openstack$ outils/photographier-images.sh ~/medisphere/docs/cloud/changements/CHG-<N>-avant.tsv
admin@adm01:~/src/openstack$ uv run kolla-ansible prechecks -i inventaire/multinode --configdir etc/kolla
admin@adm01:~/src/openstack$ uv run kolla-ansible pull -i inventaire/multinode --configdir etc/kolla
admin@adm01:~/src/openstack$ outils/photographier-images.sh --perimes      # liste ce que la fenêtre va recréer
```

MR relue (Karim), pipeline vert, **non fusionnée** avant la fenêtre.

## 3. Avant la fenêtre (T-15 min)

1. Message aux équipes (canal plateforme) : début, durée, effets (API et Horizon indisponibles par moments, instances non touchées).
2. Sauvegarde : `systemctl start wb-openstack-mariabackup.service` sur `adm01`, puis `preparer-sauvegarde.sh verifier` sur `osctl01` → « restaurable ».
3. `ms-snapshot --prefix avant-maj 2101 2102 2103` (instantanés **conservés** jusqu'à la clôture).
4. Mesures de continuité : instance `maj-essai01` avec IP flottante, `outils/mesure-continuite.sh lancer -d /tmp/chg -f <IP> -p <IP-PRIVÉE-D'UNE-AUTRE-INSTANCE>`.

## 4. Fenêtre

```
admin@adm01:~/src/openstack$ git switch main && git merge --ff-only conf/maj-kolla-22.x   # ou fusion de la MR
admin@adm01:~/src/openstack$ uv sync --frozen
admin@adm01:~/src/openstack$ time uv run kolla-ansible deploy -i inventaire/multinode --configdir etc/kolla 2>&1 | tee /tmp/chg/deploy.log
```

Noter l'heure du redémarrage de `mariadb` et de `rabbitmq` (`grep -niE 'restart (mariadb|rabbitmq)' /tmp/chg/deploy.log`) : ce sont les deux coupures des API.

**Critères d'abandon** (on passe au §6) : `deploy` en échec sur MariaDB ou RabbitMQ et non résolu en 15 min ; API indisponibles plus de 20 min ; une instance de production arrêtée ; `HEALTH_ERR` sur Ceph.

## 5. Vérifications

```
admin@adm01:~/src/openstack$ outils/photographier-images.sh ~/medisphere/docs/cloud/changements/CHG-<N>-apres.tsv
admin@adm01:~/src/openstack$ outils/photographier-images.sh --comparer …-avant.tsv …-apres.tsv
admin@adm01:~/src/openstack$ outils/photographier-images.sh --perimes          # doit répondre 0 conteneur
admin@adm01:~$ ms-verif-openstack                                               # tout OK
admin@adm01:~$ openstack --os-cloud medisphere-plateforme server create --flavor m1.petit --image debian-13 \
                 --network reseau-plateforme --wait maj-essai02                # création, puis volume attaché, LB OVN, Horizon
admin@adm01:~/src/openstack$ outils/mesure-continuite.sh arreter -d /tmp/chg && outils/mesure-continuite.sh analyser -d /tmp/chg
```

Clôture : fiche de changement complétée (durées, mesures), instances `maj-essai*` supprimées, message de fin aux équipes.

## 6. Retour arrière

| Situation | Action |
|---|---|
| Un service seul en échec, cause comprise | corriger la configuration et relancer `deploy` (idempotent) |
| `deploy` cassé par la nouvelle version de Kolla-Ansible | revenir au commit précédent (`uv.lock`), `uv sync`, `deploy` : les **images** restent les nouvelles (étiquette mobile) ; si elles sont la cause, voir ligne suivante |
| Nouvelles images défectueuses | les anciennes sont encore sur les nœuds (pas de `prune-images` avant clôture) mais l'étiquette pointe sur les nouvelles : retagger les anciennes (`docker tag <id-avant> <dépôt>:2026.1-debian-trixie` sur chaque nœud, identifiants dans `CHG-<N>-avant.tsv`) puis `deploy-containers` — ou, plus simple et plus sûr, retour aux instantanés |
| État incohérent, base touchée | retour aux instantanés `avant-maj` des **trois** nœuds (`qm rollback` sur chacun, VMs arrêtées) ; Ceph n'y revient pas : vérifier les orphelins (sauvegarde-restauration.md §6) |

## 7. Montée de série (2026.1 → 2026.2) : ce qui change

Non exécutée tant que Kolla-Ansible 2026.2 (23.x) n'est pas publié en version finale. Différences avec ce runbook : lire les notes de version de **chaque** service ; monter `kolla-ansible` à la série 23.x **et** ansible-core à la plage qu'elle exige ; fusionner `passwords.yml` (`kolla-genpwd` sur l'exemple + `kolla-mergepwd`) ; comparer `globals.yml` aux nouveaux défauts ; `pull`, `prechecks`, puis **`kolla-ansible upgrade`** (migrations de bases, ordre des services) ; RabbitMQ : pas plus d'une version majeure à la fois (procédure SLURP de Kolla si on saute une série) ; tests sur un environnement de recette d'abord.

## 8. Historique des exécutions

| Date | Changement | De → à | Interruption API | Plan de données | Remarques |
|---|---|---|---|---|---|
| 2026-10-22 | CHG-1154 | Kolla-Ansible 22.1.0 → 22.2.0 ; 31 images reconstruites | 2 × ≈ 2 min (MariaDB, RabbitMQ) + latences, 9 min au total | aucune coupure | `prune-images` reporté à J+7 (clôture) |
