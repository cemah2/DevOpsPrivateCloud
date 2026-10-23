---
chg: CHG-3404
titre: "k8s-par1 : Cilium 1.20 dernière corrective et remplacement immuable de k8s-w01 (issue no-go de CHG-3403)"
categorie: normal
statut: termine
decision: go
demandeur: Claire Morel
executant: équipe Plateforme
approbateurs: Claire Morel, Karim Benali
fenetre-debut: 2026-11-10T20:00:00+01:00
fenetre-fin: 2026-11-10T23:00:00+01:00
mesure-source: cluster
mesure-groupes: ""
mesure-debut: 2026-11-10T20:05:00+01:00
mesure-fin: 2026-11-10T22:20:00+01:00
mesure-objectif-s: 30
mesure-interruption-s: 15
---

# CHG-3404 — Cilium et remplacement immuable d'un travailleur

> Fiche de **référence** du corrigé : heures et mesures d'un lab **imaginé** pour montrer la forme.
> Remplace-les par les tiennes. Dans l'issue « go » (1.37 déclarée par toute la chaîne), les étapes 3 à 6
> deviennent : Cilium 1.21 (preflight puis Helmfile), puis le playbook `k8s-montee-version.yml`
> (M14-E25) avec `-e k8s_cible=1.37.<CORRECTIF>` ; le reste de la fiche est le même.

## 1. Résumé

CHG-3403 a conclu **no-go** pour 1.37 (Cilium 1.20 ne la déclare pas). On fait ce qui est prêt : Cilium à la dernière corrective de la 1.20, et `k8s-w01` remplacé par une VM neuve de la dernière image dorée (système à jour sans mise à jour en place), sous la sonde de continuité.

## 2. Risque

| Risque | Probabilité | Gravité | Réduction | Signal |
|---|---|---|---|---|
| Agent Cilium qui ne revient pas sur un nœud | faible | forte (pods du nœud sans réseau) | corrective dans la même mineure ; roulement du DaemonSet ; `cilium status --wait` entre deux étapes | sonde, `cilium status` |
| Drain bloqué (PDB, webhook) | moyenne | moyenne (fenêtre dépassée) | `outils/controles-montee.sh noeud k8s-w01` avant | drain qui ne finit pas (INC-6006) |
| Bascule du primaire `mediagenda-db` prod pendant le drain | certaine si le primaire est sur `k8s-w01` | faible (quelques secondes, pooler) | bascule voulue par le cordon (CNPG), mesurée | 5xx prod, sonde |
| Nouvelle VM qui ne rejoint pas (jeton, inscription FreeIPA, certificats du kubelet) | moyenne | moyenne (capacité réduite d'un tiers) | répétition du M14-E17 ; jeton de jonction court | `task noeuds`, CSR en attente |
| Mémoire : un nœud de moins pendant 40 min | certaine | faible | bilan des *requests* avant (deux travailleurs suffisent, M27-M29) | pods `Pending` |

Niveau global : **moyen**.

## 3. Impact attendu

- Cabinets et patients : rien (MédiAgenda prod : bascule de base de quelques secondes possible, absorbée par le pooler et les relances du client).
- Recette : quelques erreurs possibles au remplacement des pods.
- Pas touchés : `ceph-par1`, le socle, OpenStack (arrêté).

## 4. Fenêtre

Mardi 10/11/2026, 20 h-23 h. Hors gel. Aucun autre changement sur le cluster ce soir-là. Durée estimée : Cilium 20 min, drain 10 min, remplacement 40 min, retour en service 15 min ; retour arrière compris.

## 5. Préparation

- [x] Notes de version de chaque corrective Cilium entre 1.20.3 et la cible ; aucun changement de valeurs.
- [x] Image dorée `tpl-debian13` reconstruite par le pipeline de `plateforme/images` (date, empreinte de l'image source notées) ; essai de clonage sur une VM jetable `vsandbox`.
- [x] Instantané etcd de moins d'une heure (`task etcd:instantane`) ; sauvegarde PBS `par1/k8s` de la nuit vérifiée ; sauvegarde `mediagenda-db` de moins de 24 h (`Completed`).
- [x] MR `plateforme/k8s` (version Cilium) prête, pipeline vert ; MR `plateforme/images` fusionnée.
- [x] `outils/controles-montee.sh avant` vert ; capacité : *requests* des travailleurs < 2/3 de l'allouable.
- [x] Sonde lancée à 19 h 30 (RB-340), objectif 30 s.
- [x] Annonce J-2 à Julien Petit, Nadia Roussel, Inès Garnier.

## 6. Étapes

| # | Étape | Commande, MR ou playbook | Durée prévue | Contrôle de passage | Heure réelle |
|---|---|---|---|---|---|
| 1 | Go/no-go | ligne de base 30 min à 0 s, `controles-montee.sh avant` | 10 min | tout vert | 20 h 00 |
| 2 | Cilium (corrective) | fusion de la MR, `helmfile -e par1 -l composant=cilium apply` | 20 min | `cilium status --wait`, DaemonSet à jour, Hubble sain | 20 h 05 → 20 h 24 |
| 3 | Contrôle du nœud | `outils/controles-montee.sh noeud k8s-w01` | 2 min | aucun KO | 20 h 26 |
| 4 | Cordon et drain | `kubectl cordon k8s-w01` (bascule CNPG si primaire), `kubectl drain k8s-w01 --ignore-daemonsets --delete-emptydir-data --timeout=15m` | 10 min | drain terminé, primaire ailleurs, pooler sain | 20 h 27 → 20 h 36 |
| 5 | Retrait | `kubectl delete node k8s-w01` ; `tofu -chdir=envs/k8s apply -replace=<ADRESSE-DE-LA-VM-k8s-w01>` (adresse lue par `tofu state list`) | 15 min | VM 2144 recréée, même MAC et adresses | 20 h 38 → 20 h 51 |
| 6 | Préparation et jonction | `task noeuds -- --limit k8s-w01,k8s-cp01` ; inscription FreeIPA ; `task etiquettes` | 25 min | nœud `Ready`, CSR du kubelet approuvée, carte VLAN 30, étiquettes de zone | 20 h 52 → 21 h 20 |
| 7 | Remise en service | `kubectl uncordon k8s-w01` (si la jonction l'a laissé cordonné) ; rôles transverses (`durcissement`, `node_exporter`, `alloy`) | 15 min | pods revenus, `controles-montee.sh avant` vert | 21 h 21 → 21 h 50 |
| 8 | Mesure « après » | 30 min de sonde | 30 min | 0 s | 21 h 50 → 22 h 20 |

## 7. Critères de go/no-go et d'abandon

- **Go** : ligne de base à 0 s sur 30 min ; tous les contrôles verts ; Karim présent.
- **Abandon** : > 60 s d'erreur cumulées à un instant quelconque ; une sonde rouge > 2 min ; un agent Cilium non prêt 10 min après son redémarrage ; drain non terminé en 15 min (→ INC, diagnostic, pas de forçage).

## 8. Retour arrière

- Cilium : `helmfile apply` de la version précédente (même mineure, sans changement de valeurs) — **testé** sur `m15-essai` au M15 pour une corrective ; revert de la MR.
- Remplacement : jusqu'à l'étape 4, `kubectl uncordon` ; après l'étape 5, pas de retour à l'ancienne VM (détruite) : on **répare en avant** (la VM neuve rejoint) ; filet : sauvegarde PBS `par1/k8s` de la nuit de `k8s-w01` (restauration testée au F1).
- Point de non-retour : `tofu apply -replace` (étape 5).

## 9. Communication

| Quand | Qui | Message | Canal |
|---|---|---|---|
| 08/11 | Julien, Nadia, Inès | fenêtre, impact nul attendu, bascule de base possible | courriel `plateforme@` |
| 20 h 00 | astreinte | « CHG-3404 commence » | courriel + journal |
| 22 h 25 | mêmes | « terminé, 15 s d'erreur cumulées (objectif 30 s) » | courriel |

## 10. Mesure de l'interruption

| Moment | Fenêtre | Secondes d'erreur cumulées | Requêtes en erreur (k6) | p95 MédiAgenda prod | Remarques |
|---|---|---|---|---|---|
| avant | 19 h 35 → 20 h 05 | 0 | 0 | 41 ms | ligne de base |
| pendant | 20 h 05 → 22 h 20 | 15 | 6 | 58 ms | une rafale à 20 h 29 (bascule du primaire `mediagenda-db` prod : 4 requêtes en 503 côté sonde, un échantillon) |
| après | 22 h 20 → 22 h 50 | 0 | 0 | 40 ms | |

## 11. Journal d'exécution

20 h 05 : Cilium 1.20.x appliqué, roulement de 6 agents en 17 min, aucune erreur. 20 h 27 : cordon, CNPG bascule le primaire prod de `mediagenda-db-2` (sur `k8s-w01`) vers `mediagenda-db-1` en 6 s. 20 h 36 : drain terminé (RabbitMQ : le pré-arrêt de `rabbitmq-server-1` attend le quorum + 1, 3 min). 21 h 20 : `k8s-w01` `Ready`, noyau et paquets de l'image du 09/11. 21 h 50 : contrôles verts.

## 12. Clôture et revue

Réussi. 15 s ≤ 30 s. Écart : drain plus long que prévu (pré-arrêt RabbitMQ) → durée réestimée dans RB-341. Action : PLAT-3404-1 « remplacer les deux autres travailleurs au fil de l'eau, un par fenêtre standard ».
