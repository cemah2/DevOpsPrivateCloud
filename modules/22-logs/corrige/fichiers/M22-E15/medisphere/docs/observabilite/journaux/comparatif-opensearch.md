# Comparatif Loki / OpenSearch pour les journaux de MédiSphère

> Exemple de livrable de M22-E15 (PLAT-2315). Mesures d'un lab de référence, **remplace-les par les tiennes**. Essai du 2026-10-30, 14 h - 16 h : OpenSearch 3.9.0 (un nœud, tas 1 Gio, sécurité active) alimenté par Fluent Bit 5.1.3, Loki 3.7.9 alimenté par Alloy 1.21, mêmes sources (pods `mediagenda-*`), même heure de comparaison (15 h - 16 h).

## 1. Ce que chacun indexe

| | Loki | OpenSearch |
|---|---|---|
| Index | les **étiquettes** des flux (TSDB, quelques Mo par jour) | **tout le texte** et chaque champ (index inversé Lucene, doc values) |
| Chercher un mot | lecture et décompression des chunks des flux sélectionnés, puis filtre | recherche dans l'index inversé |
| Schéma | aucun à l'écriture (analyse à la lecture : `json`, `logfmt`, `pattern`) | mapping par index (dynamique par défaut : conflits de types possibles) |
| Stockage | objets dans le RGW (chunks compressés + index) | disques locaux des nœuds (ici un PVC `ceph-rbd`) |

## 2. Mesures (même heure, mêmes journaux : 41 300 lignes, 12,4 Mio bruts)

| Mesure | Loki | OpenSearch | Commentaire |
|---|---|---|---|
| R1 mot rare (`request_id`) | 0,35 s (12 Mio lus) | 0,012 s | OpenSearch ×30 : c'est son terrain |
| R2 mot fréquent (`requête`) | 0,40 s | 0,05 s (+ 10 000 premiers résultats seulement) | Loki renvoie le flux trié dans le temps |
| R3 champ `code = 500` | 0,42 s (`| json`) | 0,008 s | champ indexé contre analyse à la lecture |
| R4 agrégation par `code`, 5 min | 0,45 s | 0,03 s | |
| R5 regex sur le chemin | 0,41 s | 0,9 s (champ `text`) / 0,05 s (`keyword`) | dépend du mapping ; la regex sur `text` est coûteuse |
| Disque pour l'heure | 2,1 Mio (chunks snappy + part d'index) | 23,6 Mio (index, sans réplica) | ×11 |
| Mémoire au repos | `loki-0` ≈ 420 Mio (tous locataires) | 1,6 Gio (tas 1 Gio + hors tas) pour un seul flux d'essai | |
| CPU moyen pendant la collecte | 40 m | 180 m (indexation) | |
| Réglages touchés pour la première ligne indexée | 0 (déjà en place) | 14 (certificats, sécurité, mapping, ISM absent, `Suppress_Type_Name`, PKCS#8…) | |

Extrapolation à 30 jours pour les seules applications (ordre de grandeur) : Loki ≈ 1,5 Gio dans le RGW ; OpenSearch ≈ 17 Gio sur disques locaux, **×2 avec un réplica** — indispensable dès qu'il y a plus d'un nœud.

## 3. Ce qu'OpenSearch fait mieux

- Recherche d'une chaîne rare sur une longue période dans tous les espaces (investigation sécurité, support).
- Agrégations rapides sur des champs (tableaux de bord métier), Dashboards riches, alerting et détection d'anomalies intégrés.
- Langages familiers des équipes (DSL, SQL, PPL).

## 4. Ce que Loki fait mieux

- Coût : un ordre de grandeur de moins en disque et en mémoire ; stockage objet partagé, sans disque local à dimensionner.
- Exploitation : pas de mapping, pas de rotation d'index (rétention par locataire, E13), pas de cluster à équilibrer ; montées de version d'un seul binaire.
- Intégration : mêmes étiquettes que Prometheus, même Grafana, corrélation avec les traces (M23) ; multi-locataire natif.

## 5. Coût d'exploitation d'OpenSearch (ce que la proposition d'InfoGér ne dit pas)

- Au moins 3 nœuds pour la haute disponibilité, 4 à 8 Gio de mémoire chacun : 12 à 24 Gio, impossible dans le profil de 100 Go du lab, cher en production.
- Gestion du cycle de vie des index (ISM), des mappings et de leurs conflits, des réplicas et des fragments, des montées de version majeures (réindexation possible).
- Sécurité à configurer entièrement (certificats, comptes internes, rôles) ; la configuration de démonstration ne doit jamais partir en production.

## 6. Recommandation

**Loki** reste la solution de MédiSphère pour tous les journaux (ADR-0220). La recherche plein texte rapide n'est pas un besoin quotidien de l'exploitation ; le besoin ponctuel d'investigation se traite par des requêtes Loki bien bornées (sélecteur + filtre, fenêtre courte, `logcli --parallel-*`). OpenSearch serait à reconsidérer pour un **besoin métier** (recherche dans les documents de MédiDoc, par exemple), pas pour les journaux techniques. L'essai est retiré (espace, volumes, émetteur) ; les deux charts sont retirés du miroir.
