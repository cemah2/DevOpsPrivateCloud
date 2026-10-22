# ADR-0220 — Architecture des journaux : Loki multi-locataire et Alloy

| | |
|---|---|
| Statut | Accepté (2026-11-02, comité d'architecture) |
| Décideurs | Claire Morel ; consultés : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit |
| Tickets | PLAT-2317 ; essais PLAT-2310 (Fluent Bit), PLAT-2315 (OpenSearch), SEC-2313, SEC-2316 |
| Remplace | — (avant : `kubectl logs` et `journalctl` sur chaque hôte) |

## Contexte

- Volumes mesurés (M22-E13/E14, lab de référence) : ≈ 1,6 Gio/jour bruts, dont `plateforme` 62 %, `audit` 24 %, `mediagenda` 11 %, `medidoc` 3 % ; 450 flux actifs au total ; compression 5 à 6.
- Exigences : journal d'audit de l'API gardé **un an** et non effaçable (HDS, ISO 27001) ; journaux applicatifs **30 jours**, plateforme **14 jours** ; aucune donnée de santé dans les journaux et capacité d'**effacement** ciblé (RGPD art. 17) ; données sur l'infrastructure de MédiSphère (souveraineté) ; cloisonnement par équipe.
- Contraintes : profil mémoire du lab ≈ 100 Go pour toute la plateforme ; stockage objet déjà en place (RGW de `ceph-par1`, utilisé par Thanos) ; Grafana 13 et Alertmanager déjà exploités (ADR-0210) ; équipe de quatre personnes.

## Décision

1. **Loki 3.7** (chart `grafana-community/loki` 19), mode **`Monolithic`**, un pod, schéma TSDB v13, données dans le compartiment `loki-k8s-par1` du RGW, déployé par Argo CD.
2. **Multi-locataire** (`auth_enabled: true`) : `plateforme`, `mediagenda`, `medidoc`, `audit` (+ `essai`), avec rétention, limites et droit d'effacement **par locataire** dans la configuration d'exécution ; compactor unique qui applique rétention et effacement.
3. **Grafana Alloy 1.21** comme collecteur **unique** : DaemonSet (pods, journald des nœuds, audit de l'API, événements Kubernetes) et rôle Ansible `alloy` sur les VMs ; affectation des locataires et **masquage** des données personnelles à la collecte ; liste **fermée** d'étiquettes.
4. Alertes tirées des journaux par le *ruler* de Loki vers l'Alertmanager du cluster ; consultation par Grafana, le locataire `audit` dans une organisation dédiée.

## Options étudiées et écartées

| Option | Pourquoi écartée (mesures du module) |
|---|---|
| **OpenSearch** 3.9 (+ Fluent Bit ou Data Prepper) | Recherche plein texte ×10 à ×30 plus rapide, mais ×11 en disque et ×4 en mémoire pour les mêmes journaux (E15) ; trois nœuds minimum pour la haute disponibilité (12 à 24 Gio) ; mapping, ISM et réindexation à exploiter. Le besoin de recherche plein texte n'est pas quotidien |
| **Fluent Bit** 5.1 à la place d'Alloy | Plus léger (E10 : 15 Mio contre 90 Mio par nœud), mais pas d'affectation de locataire aussi souple, pas de découverte Kubernetes unifiée avec les métriques et les traces (M23), deux langages de configuration à maintenir ; Alloy porte aussi OTLP au M23 |
| **Promtail** | **Fin de vie le 2 mars 2026** : plus de correctifs de sécurité. Écarté pour cette raison seule ; `alloy convert --source-format=promtail` existe pour les configurations héritées |
| Loki **SimpleScalable** | Déprécié, supprimé en Loki 4 |
| Loki **distribué** (microservices) | Une dizaine de composants, mémoire et complexité sans rapport avec 1,6 Gio/jour |
| Service SaaS (Grafana Cloud, éditeur tiers) | Journaux hors de l'infrastructure de MédiSphère (souveraineté, HDS) |

## Conséquences

Ce qui devient facile : un seul endroit pour tous les journaux, interrogés à côté des métriques ; rétention et effacement appliqués par la configuration, relus en MR ; coût de stockage faible ; corrélation avec les traces au M23 (`trace_id` en métadonnée structurée).

Ce qui reste difficile : la recherche d'une chaîne rare sur de longues périodes sans sélecteur précis (lecture de tous les chunks) ; la discipline des étiquettes (une étiquette à forte cardinalité dégrade tout le locataire).

**Limites acceptées** :
- **un seul pod Loki** : pas de haute disponibilité. Pendant un redémarrage, Alloy garde et réessaie (quelques minutes) ; au-delà, des lignes sont perdues. Révision prévue si l'astreinte le demande (mode `Monolithic` à 3 réplicas avec réplication) ;
- **en-tête de locataire falsifiable** par qui peut joindre Loki (MGMT, Grafana) : réduit par les politiques réseau (E16), traité par la passerelle authentifiante du **M24** ;
- **pas de copie hors site** des journaux : versionnage du compartiment (7 jours) contre l'erreur humaine ; copie du locataire `audit` vers PAR2 à traiter dans le PRA (**F5**) ;
- un seul compactor : à garder unique si Loki est un jour réparti.

**Révision** de cette décision si : volume > 20 Gio/jour, plus de 10 locataires, exigence de recherche plein texte métier, ou nouvelle exigence HDS sur la conservation des journaux.
