# Politique de sauvegarde des données de `k8s-par1`

| | |
|---|---|
| Propriétaire | Claire Morel (Plateforme) ; validation : Sophie Laurent (sécurité), Nadia Roussel (exploitation) |
| Version | 1.0 — <AAAA-MM-JJ> (PLAT-1732) |
| Revue | semestrielle, et à chaque nouvelle application avec état |
| Liens | politique de stockage (`docs/stockage/politique-stockage.md`, M08-E33), ADR-0160, RB-141, RB-161, RB-162 |

## 1. Objet et périmètre

Cette politique dit, pour chaque donnée du cluster Kubernetes `k8s-par1`, comment elle est sauvegardée, où, combien de temps, avec quels objectifs de perte (RPO) et de reprise (RTO), et comment la restauration est prouvée.

Hors périmètre : le cluster `ceph-par1` lui-même (politique de stockage, PBS `par1/ceph`), `s3-01` (VM du socle, sauvegardée par PBS), les VMs des nœuds (PBS `par1/k8s`, utile pour reconstruire un nœud, pas pour restaurer des données applicatives).

## 2. Inventaire par donnée

| Donnée | Source de vérité | Mécanisme | Fréquence | Destination | Rétention | Chiffrement | RPO | RTO mesuré | Propriétaire |
|---|---|---|---|---|---|---|---|---|---|
| Configuration de la plateforme (manifestes, values) | dépôts Git (`plateforme/k8s`, dépôts applicatifs) | Git + sauvegarde de `git01` (M01) | à chaque fusion | `git01`, PBS | celle de `git01` | transit TLS | 0 (fusionné) | reconstruction : M14-E23 (<DURÉE>) | Plateforme |
| État du cluster (etcd) | etcd | instantané `etcdctl` (M14-E24), minuterie horaire | 1 h | `s3-01` `etcd-k8s-par1` | 7 jours | chiffré (Secrets `aescbc` dans l'instantané ; compartiment privé) | 1 h | M14-E24 : <DURÉE> | Plateforme |
| Objets des espaces applicatifs | Git (déployés) + état réel | Velero, planification quotidienne (E16) | 24 h | `s3-01` `velero-k8s-par1` | 14 jours | identifiants S3 dédiés ; TLS | 24 h | E24 : <DURÉE> (espace complet) | Plateforme |
| Volumes Valkey, fichiers de MédiDoc | volumes Ceph | Velero, *data mover* CSI (Kopia) (E17) | 24 h | `s3-01` `velero-k8s-par1` | 14 jours | dépôt Kopia chiffré (mot de passe Velero) | 24 h | E24 : <DURÉE> ; E29 | équipe applicative + Plateforme |
| Bases PostgreSQL | CloudNativePG | WAL en continu + sauvegarde de base quotidienne (plugin Barman Cloud, E19) | continu (WAL : ≤ 5 min, `archive_timeout`) | `s3-01` `cnpg-k8s-par1` | 14 jours (`retentionPolicy`) | TLS ; compartiment privé (chiffrement côté serveur : non en v1) | ≤ 5 min | E19 : <DURÉE> ; E34 : <DURÉE> (récupération sélective) | équipe applicative + Plateforme |
| Secrets (clés cephx, KEK, identifiants S3, mots de passe) | Ansible Vault `critique`/`lab` dans Git | celle des dépôts | — | `git01`, PBS | celle de `git01` | Ansible Vault | 0 | recréation par les scripts `outils/` : <DURÉE> | Plateforme |

Règles :
- Les Secrets **ne se restaurent pas** depuis Velero : ils se recréent depuis leur source de vérité (Vault). Velero les contient (ils font partie des espaces) : son compartiment est donc aussi sensible que le Vault.
- Une base CloudNativePG **ne se restaure pas** par Velero : par CloudNativePG (RB-162). Velero exclut le `Cluster` et ses objets à la restauration (RB-161).
- Une nouvelle application avec état n'est mise en production qu'avec sa ligne dans ce tableau et un premier test de restauration.

## 3. Dépendances de restauration

| Pour restaurer… | il faut | dans l'ordre |
|---|---|---|
| Une base (RB-162) | opérateur + plugin, `s3-01`, identifiants `cnpg` (Vault) | 1. `s3-01` ; 2. cluster Kubernetes ; 3. opérateur ; 4. `Cluster` de récupération |
| Un espace (RB-161) | Velero, `s3-01`, identifiants `velero`, mot de passe du dépôt Kopia, classes de stockage, Ceph | 1. `s3-01` ; 2. Ceph ; 3. cluster ; 4. Velero ; 5. espace ; 6. base |
| Le cluster | instantané etcd ou reconstruction par le code ; PKI du cluster (Vault `critique`) | RB-141 / M14-E23 |

**Perte de `s3-01`** : toutes les sauvegardes du cluster sont perdues **en même temps** (etcd, Velero, CNPG). Mesures v1 : `s3-01` est sauvegardé par PBS (`pbs01`, autre site) ; RTO de `s3-01` : <DURÉE> (M05/M06). Les données vivantes restent dans Ceph. Action : réplication des compartiments vers PAR2 (F5).

## 4. Tests de restauration

| Test | Rythme | Qui | Preuve conservée | Échec si |
|---|---|---|---|---|
| Restauration d'un espace dans `wb-restauration` (RB-161) | trimestriel | Plateforme (astreinte en binôme) | `tests/restauration-espace-de-noms.md` daté | empreintes différentes, RTO > 2 h |
| PITR d'une base dans un cluster temporaire (RB-162) | mensuel | Plateforme + équipe applicative | compte rendu daté (empreinte, instant cible) | données absentes, RTO > 1 h |
| Récupération sélective chronométrée (M16-E34) | semestriel | astreinte | `tests/chrono-pitr-*.md` | > 45 min |
| Restauration etcd (RB-141) | semestriel, sur cluster d'essai | Plateforme | compte rendu | cluster non fonctionnel |

## 5. Supervision et alertes

`ms-verif-k8s-stockage` (toutes les 10 min) : BSL Velero disponible, âge de la dernière sauvegarde réussie de chaque planification < 26 h, archivage continu des WAL actif, âge de la dernière sauvegarde de base < 26 h. `ms-verif-sauvegardes` : âge des instantanés etcd. Alertes vers l'astreinte (`ms-alerte`) ; archivage des WAL bloqué = réveil.

## 6. Rétention et effacement

- Rétention : 14 jours (Velero, CNPG), 7 jours (etcd) ; plus courte que celle des sauvegardes PBS du socle (cohérent avec la politique de stockage).
- Effacement d'une donnée de patient (RGPD) : effacée dans la base de production ; elle subsiste dans les sauvegardes **jusqu'à leur expiration** (14 jours au plus), sans réinjection possible hors procédure tracée. Une restauration (RB-161, RB-162) réapplique les effacements intervenus depuis la date restaurée (registre des effacements de l'application : action DEV, à demander à l'équipe de Julien).
- Copies de restauration (`wb-restauration`, clusters temporaires) : supprimées à la fin de l'essai, preuve dans le compte rendu.

## 7. Exceptions, limites et gestion du document

- v1 : un seul site ; `s3-01` est une VM unique ; pas de copie immuable (verrouillage d'objets) ; RTO mesurés sur le lab (volumétrie de recette).
- Exceptions : demandées par ticket à Claire, tracées ici avec une date de fin.
