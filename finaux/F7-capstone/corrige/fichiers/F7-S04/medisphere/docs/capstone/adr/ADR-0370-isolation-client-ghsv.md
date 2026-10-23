# ADR-0370 — Isolation du client GHSV dans la plateforme

| | |
|---|---|
| Statut | **Accepté** (<DATE>) — révision au deuxième client hébergé ou au déclencheur ci-dessous |
| Décideurs | Claire Morel, Karim Benali, Sophie Laurent (RSSI) |
| Ticket | PLAT-3704 (F7-S04) |
| Exigences | ESC-06, ESC-08, ESC-11, ESC-13, ENF-03, ENF-11, EXP-06 |
| Complète | ADR-0320 (équipe en code, F2), ADR-0350 (site de repli PAR2, F5) |

## Contexte

Le GHSV est le premier **client externe** hébergé sur la plateforme : jusqu'ici, les locataires (`mediagenda`, `medidoc`, `medivisio`, `data`…) étaient des équipes de MédiSphère. Le cahier des charges exige des clés dédiées (ESC-06), des journaux propres et restituables (ESC-08), des accès de notre personnel tracés (ESC-11), une recette permanente sans donnée réelle (ESC-13, EXP-06) et un engagement de disponibilité pénalisé (ENF-03). Il n'exige **pas** de matériel dédié. La charge du GHSV est faible : ≈ 6 % du calcul de PAR1 (architecture, §5).

Ce qu'il faut isoler : les **données** (base, objets, sauvegardes, journaux), les **clés**, les **accès** (personnes et machines), les **ressources** (un voisin ne doit pas consommer la capacité du GHSV ni l'inverse), et les **pannes** (un changement d'un autre locataire ne doit pas casser le GHSV).

## Décision

Le GHSV est un **locataire** de la plateforme mutualisée, déclaré par l'équipe en code du F2, avec des données, des clés et des journaux **dédiés** :

1. **Déclaration** : `plateforme/equipes`, fichier `equipes/ghsv.yaml`, avec un type `client` (extension du format : contact contractuel, pas de membre GitLab développeur, environnements `recette` et `prod` seulement, synchronisation manuelle de la production) ; la MR qui le crée crée tout le reste (Capsule, quotas, AppProject Argo CD, politiques OpenBao, dossier Grafana, routage des alertes).
2. **Calcul** : locataire Capsule `ghsv`, espaces `ghsv-recette` et `ghsv-prod` dans `k8s-par1` (et `k8s-par2`), quotas garantis (`requests` = besoin calculé au §5 de l'architecture), classe de priorité `medisphere-critique` en production, politiques réseau « tout refuser sauf » (entrées depuis la Gateway seulement, sorties vers les dépendances listées), Pod Security `restricted`. Nœuds **mutualisés**.
3. **Données** : `Cluster` CloudNativePG **dédié** (pas une base dans un cluster partagé), Valkey dédié, compartiments de stockage objet dédiés (pièces jointes, sauvegardes de la base), chacun avec ses identités et ses clés (ADR-0371).
4. **Journaux** : locataire de journaux `ghsv` dans Loki (rétention 365 j), restituable seul ; tableaux et rapport mensuel dans un dossier Grafana du GHSV.
5. **Accès** : aucun membre du GHSV dans nos outils d'administration ; accès de notre personnel à `ghsv-prod` par un groupe `ghsv-exploitation` restreint (nominatif, revu chaque trimestre, ESC-11) ; Argo CD synchronise la production à la main.
6. **Code** : même image MédiAgenda que nos autres environnements ; configuration propre au client dans un overlay `ghsv` du dépôt de déploiement (marque blanche, noms, quotas).

## Options étudiées

| Option | Ce qu'elle isole en plus | Coût | Décision |
|---|---|---|---|
| Espaces de noms simples, sans locataire | rien de plus que des quotas | nul | **écartée** : pas de propriétaire, pas de politique d'ensemble, une erreur de RBAC expose le GHSV |
| **Locataire Capsule + données et clés dédiées** | données, clés, journaux, accès, quotas | faible (déjà outillé : F2) | **retenue** |
| Nœuds de travail dédiés (teinte `client=ghsv`) | calcul (voisin bruyant), noyau partagé en moins avec les autres | ≈ 2 travailleurs × 2 sites réservés pour ≈ 20 vCPU utiles : mauvaise utilisation | **écartée en v1** ; révision si un incident de voisinage est constaté ou si le GHSV l'exige |
| Cluster virtuel (vCluster OSS, M28) | API Kubernetes propre au client | une couche de plus à exploiter, sauvegarder et monter ; aucun bénéfice pour un client qui n'accède pas à Kubernetes | **écartée** |
| Cluster Kubernetes dédié par site | plan de contrôle, mises à jour, pannes de cluster | 2 clusters de plus (≥ 6 VMs de contrôle, observabilité, Argo CD, montées de version à mener deux fois de plus) | **écartée** : coût d'exploitation sans exigence qui le justifie |
| Infrastructure dédiée (hyperviseurs, baies) | tout | > 200 k€ d'investissement, équipe doublée | **écartée** |

## Conséquences

- **Ce qu'on gagne** : coût marginal faible (S05), réutilisation de tout l'outillage (F2 à F6), une seule plateforme à monter et à auditer.
- **Ce qu'on perd** : une panne de `k8s-par1` (plan de contrôle, CNI, Gateway) touche le GHSV **et** nos services ; une montée de version de Kubernetes est un changement à annoncer au GHSV (ENF-04). Mitigation : processus de changement du F4, sonde de continuité, PRA.
- **Travail pour la phase 3** : extension du format de `plateforme/equipes` (type `client`), `equipes/ghsv.yaml`, overlay du déploiement, politiques réseau, locataire de journaux (F7-S07).
- **Preuves pour le jury** : un pod d'un autre locataire ne joint ni la base ni le Valkey du GHSV ; un utilisateur de l'équipe MédiAgenda ne lit pas `ghsv-prod` ; une clé `transit/ghsv-*` n'est utilisable que par les identités du GHSV.
- **Lab** : nœuds mutualisés comme en production ; mêmes objets.
- **Preuve de concept du lab** (F7-S07) : le groupe `ghsv` rendu par `equipes/ghsv.yaml` (Julien Petit, Nadia Roussel) joue le rôle du groupe `ghsv-exploitation` (un seul fichier à tenir au lieu de deux) ; journaux applicatifs du client dans le locataire Loki `mediagenda` (sélecteur `namespace=~"ghsv-.*"`, RB-371), pas encore dans un locataire `ghsv` dédié ; données fictives en recette et en production de démonstration.

## Révision

À réexaminer : au deuxième client externe (le type `client` devient un produit) ; si le GHSV exige des nœuds dédiés ; après tout incident où un autre locataire a dégradé le GHSV.
