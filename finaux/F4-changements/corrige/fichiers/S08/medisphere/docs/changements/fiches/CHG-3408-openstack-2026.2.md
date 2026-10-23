---
chg: CHG-3408
titre: "OpenStack 2026.1 → 2026.2 (Kolla-Ansible 22.2 → 23.x), k8s-par1 arrêté"
categorie: normal
statut: termine
decision: go                   # no-go si Kolla-Ansible 23 n'est qu'en version candidate : répétition seulement
demandeur: Claire Morel
executant: équipe Plateforme
approbateurs: Claire Morel, Karim Benali, Sophie Laurent
fenetre-debut: 2026-11-21T08:00:00+01:00
fenetre-fin: 2026-11-21T14:00:00+01:00
mesure-source: temoin          # k8s-par1 arrêté : seul le Prometheus témoin de mon01 mesure
mesure-groupes: "continuite-openstack.*"
mesure-debut: 2026-11-21T09:40:00+01:00
mesure-fin: 2026-11-21T12:10:00+01:00
mesure-objectif-s: 60
mesure-interruption-s: 30
---

# CHG-3408 — OpenStack 2026.1 → 2026.2

> Fiche de **référence** (lab imaginé). Au relevé de l'annexe (23/10/2026), Kolla-Ansible 23 n'était
> qu'en version candidate (23.0.0.0rc1) ; la page des notes de version de Kolla-Ansible listait
> ensuite une 23.0.0 pour la série 2026.2 : **vérifie le jour J sur PyPI**. Si seule une rc existe :
> `decision: no-go`, la montée se **répète** sur la rc (fenêtre d'essai, mêmes étapes, puis retour en
> 2026.1 par restauration) et la production attend la stable.

## 1. Résumé

Montée de série d'OpenStack (2026.1 « Gazpacho » → 2026.2 « Hibiscus ») par la procédure officielle de Kolla-Ansible (`pull`, `prechecks`, `upgrade`), dans un nouvel environnement Python, avec une instance témoin qui doit continuer de répondre sur son IP flottante.

## 2. Contrainte du lab (mémoire)

Le profil openstack (≈ 32 Go) ne tient qu'avec `k8s-par1` **arrêté** (PLAN §4.14 : socle + `ceph-par1` + openstack ≈ 101 Go). Dans le lab, MédiAgenda et les autres services du cluster sont donc arrêtés pendant la fenêtre ; dans la fiction, ils tournent ailleurs. La mesure ne porte que sur les sondes `continuite-openstack*` (`mesure-groupes`).

## 3. Risque

| Risque | Probabilité | Gravité | Réduction | Signal |
|---|---|---|---|---|
| Migration de schéma de base qui échoue | faible | forte (API indisponibles) | sauvegarde `mariadb-backup` vérifiée **et** envoyée sur PBS `par1/openstack` juste avant ; répétition | journal d'Ansible |
| Coupure du plan de données (OVS/OVN, `nova_libvirt`) | moyenne | moyenne (instances injoignables) | fenêtre annoncée ; mesure sur l'IP flottante | sondes `continuite-openstack*` |
| ansible-core hors plage, collections incompatibles | moyenne | faible (échec avant toute action) | `uv` dans un arbre de travail séparé ; `install-deps` | `prechecks` |
| Nouveaux mots de passe manquants | moyenne | moyenne | `kolla-genpwd` + `kolla-mergepwd` (`outils/fusionner-mots-de-passe.sh`) | `prechecks` |
| Debian 13 non pris en charge par la 23.x | à vérifier | forte | matrice de prise en charge lue avant | — |

## 4. Fenêtre

Samedi 21/11/2026, 8 h-14 h. 8 h-9 h 30 : arrêt de `k8s-par1`, démarrage (ou reconstruction) du profil openstack, vérification de la 2026.1. 9 h 40-12 h 10 : montée mesurée. 12 h 10-14 h : vérifications, arrêt du profil, redémarrage de `k8s-par1`.

## 5. Préparation

- [x] Notes de version 2026.2 de Kolla-Ansible (*Upgrade Notes*) et de chaque service déployé (Nova, Neutron/OVN, Cinder, Glance, Keystone, Heat, Horizon, Octavia) ; matrice de prise en charge (Debian 13 hôte et images).
- [x] Plage d'ansible-core de la 23.x : « Operating Kolla » 2026.2 donne `ansible-core>=2.20,<2.21.99`.
- [x] Arbre de travail `~/src/openstack-2026.2` (branche `serie-2026.2`) : `pyproject.toml` (kolla-ansible 23.x, ansible-core), `uv lock`, `uv sync`, `install-deps` ; `globals.yml` comparé aux défauts 23.x ; inventaire comparé à l'exemple `multinode` ; `passwords.yml` fusionné ; pipeline vert ; MR **non fusionnée**.
- [x] Répétition sur la rc (fenêtre d'essai du 14/11, puis retour en 2026.1 par restauration : testé).
- [x] Instance `sonde-fip01` + groupes `continuite-openstack*` sur `mon01` ; objectif 60 s (un seul contrôleur, une seule passerelle).

## 6. Étapes

| # | Étape | Commande | Contrôle de passage | Heure réelle |
|---|---|---|---|---|
| 1 | Arrêt de `k8s-par1` | `root@pve01:~# ./profil-k8s.sh arreter` | 6 VMs arrêtées | 8 h 00 → 8 h 12 |
| 2 | Profil openstack | `qm start 2101..2103` (ou `tofu apply` de `envs/openstack` + `outils/deployer.sh deploy` s'il a été détruit) ; `ceph-par1` `HEALTH_OK` | services `up`, instance `sonde-fip01` répond | 8 h 15 → 9 h 05 |
| 3 | Sauvegarde | `uv run kolla-ansible mariadb-backup … --full`, envoi PBS `par1/openstack`, `catalog dump` | sauvegarde de moins d'1 h, lisible | 9 h 05 → 9 h 25 |
| 4 | Go/no-go | ligne de base 15 min (sondes `continuite-openstack*`) | 0 s | 9 h 40 |
| 5 | Images | `cd ~/src/openstack-2026.2 && uv run kolla-ansible pull -i inventaire/multinode --configdir etc/kolla` | images 2026.2 présentes | 9 h 45 → 10 h 20 |
| 6 | Contrôles préalables | `uv run kolla-ansible prechecks …` | aucun échec | 10 h 25 |
| 7 | Montée | fusion de la MR, puis depuis le `main` à jour : `outils/deployer.sh upgrade` | play terminée sans échec ; étiquette `deploye-*` | 10 h 30 → 11 h 45 |
| 8 | Vérifications | services, agents, volume attaché, répartiteur OVN, Horizon, instance neuve | tout `up` | 11 h 45 → 12 h 10 |
| 9 | Retour du cluster | arrêt du profil openstack, `./profil-k8s.sh demarrer` | nœuds `Ready`, `lab/bin/check F4 2` vert | 12 h 15 → 13 h 00 |

## 7. Critères d'abandon

`prechecks` en échec non expliqué ; migration de schéma en échec ; plus de 120 s d'erreur cumulées sur l'IP flottante ; API indisponibles plus de 30 min après la fin de la play.

## 8. Retour arrière

Avant l'étape 7 : rien à défaire (l'arbre 2026.1 est intact). Après : pas de retour de série par Kolla ; retour = restauration de la base (sauvegarde de l'étape 3, procédure `sauvegarde-restauration.md` §3 du M10), images 2026.1 (encore présentes : pas de `prune-images` avant la clôture), `deploy-containers` depuis `~/src/openstack` (2026.1). **Testé** pendant la répétition du 14/11.

## 9. Communication

J-3 : Julien (`mediagenda/recette-infra` sur OpenStack indisponible pendant la fenêtre), Nadia, Claire.

## 10. Mesure de l'interruption

| Moment | Fenêtre | Secondes d'erreur cumulées (sondes `continuite-openstack*`) | Remarques |
|---|---|---|---|
| avant | 9 h 25 → 9 h 40 | 0 | |
| pendant | 9 h 40 → 12 h 10 | 30 | ping perdu ≈ 10 s et HTTP 20 s au redémarrage d'`openvswitch_vswitchd` et des conteneurs OVN de `osctl01` |
| après | 12 h 10 → 12 h 15 | 0 | courte (le profil s'arrête ensuite) |

Commande : `outils/mesurer-interruption.sh 2026-11-21T09:40:00+01:00 2026-11-21T12:10:00+01:00 temoin 'continuite-openstack.*'`.

## 11. Journal

Voir journal d'Ansible archivé avec l'étiquette `deploye-20261121-1030`.

## 12. Clôture et revue

Réussi, 30 s ≤ 60 s. `prune-images` après une semaine sans retour arrière (PLAT-3408-1). RB-344 mis à jour.
