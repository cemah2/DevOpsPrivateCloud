# ADR-0241 — Haute disponibilité de Keycloak

| | |
|---|---|
| Statut | Accepté |
| Date | <AAAA-MM-JJ> |
| Ticket | PLAT-2524 (M24-E24), demandé par Claire Morel |
| Auteur | <MOI> ; relu par Karim Benali, Nadia Roussel |
| Liens | ADR-0240 (architecture d'identité), RB-240 (bris de glace), RB-243 (restauration), RB-246 (SSO indisponible) |

## Contexte

Depuis le palier 2 du M24, tous les services de MédiSphère s'authentifient par Keycloak (`idp01`) : une indisponibilité empêche toute **nouvelle** connexion (GitLab, Grafana, Argo CD, Harbor, Proxmox, `kubectl` par kubelogin, `step ssh login`). Le lab tourne sur un seul hyperviseur (`pve01`), avec ≈ 108 Go occupés sur 128 Go. Question : faut-il deux nœuds Keycloak en permanence ?

Ce que partagent les nœuds d'une grappe Keycloak 26 : la **base PostgreSQL** (royaumes, clients, clés, sessions persistées, table de découverte `jgroups_ping`) et le transport Infinispan (TCP 7800, détection 57800, mTLS). Depuis la 26.0, les sessions des utilisateurs sont **persistées en base** par défaut : elles survivent à l'arrêt de tous les nœuds.

## Mesures (M24-E24)

Boucle `outils/mesure-disponibilite.sh` sur `adm01` (découverte + jeton `client_credentials` chaque seconde, par la VIP), `lucas.martin` connecté à la console de compte. Valeurs relevées sur le lab : <À REMPLACER PAR TES MESURES>.

| Scénario | Échecs vus par la boucle | Lucas doit-il se reconnecter ? |
|---|---|---|
| Grappe, arrêt propre d'`idp01` (`systemctl stop`) | <N> s (le temps que HAProxy retire `idp01` : `inter 2s fall 2` → 2 à 4 s ; les requêtes en vol échouent) | non (session en base et dans la grappe) |
| Grappe, arrêt d'`idp02` | <N> s | non |
| Un seul nœud, arrêt puis redémarrage d'`idp01` | <N> s (arrêt + démarrage optimisé : ≈ 15-20 s à la rédaction sur un poste de test, davantage sur une VM à 2 vCPU) | non (session persistée en base) |
| Redémarrage de PostgreSQL (`idp01`) | <N> s, **les deux nœuds** échouent | non |

## Options

| Option | Ce qu'elle protège | Ce qui reste un point unique | Coût |
|---|---|---|---|
| A. Un nœud + restauration + bris de glace | rien pendant une panne d'`idp01` ; RTO d'une restauration (RB-243 : <N> min) ou d'un redémarrage (<N> s) | `idp01`, sa base, `pve01`, `ipa01` | 3 Go ; exploitation simple |
| B. Deux nœuds sur `pve01`, base sur `idp01` | redémarrage, montée de version **compatible** ou panne d'un processus Keycloak | **la base** (sur `idp01`), `pve01`, `ipa01`, la VIP des répartiteurs | +2 Go en permanence ; PostgreSQL ouvert sur le réseau (TLS à vérifier pour de vrai) ; montées de version plus délicates (deux versions dans une grappe) |
| C. Deux nœuds sur deux hyperviseurs, PostgreSQL répliqué (Patroni ou CloudNativePG externe) | panne d'un hyperviseur | l'annuaire (pas de réplica FreeIPA), le site | second hyperviseur, base répliquée : hors de portée du lab |

## Décision

**Option A** : `idp01` reste **seul**. Raisons : (1) avec la base sur `idp01` et un seul hyperviseur, l'option B ne protège que contre la panne du **processus** Keycloak, la plus rare et la plus courte (un redémarrage = <N> s, sessions conservées) ; (2) elle coûte 2 Go permanents dans un profil à 108-111 Go ; (3) elle ouvre la base sur le réseau et complique chaque montée de version. La disponibilité réelle est portée par : la supervision (E26 : alerte en moins de 3 min), la procédure de redémarrage et de restauration (RB-243), et les **comptes de bris de glace** de chaque service (RB-240), qui ne dépendent pas de Keycloak.

## Conséquences

- Une panne d'`idp01` coupe les nouvelles connexions jusqu'au redémarrage ou à la restauration ; les sessions déjà ouvertes **dans les services** continuent jusqu'à leur expiration ; `kubectl` continue tant que le jeton en cache vit.
- La montée de version (E33) se fait avec une courte coupure annoncée, pas en continu.
- Le rôle `keycloak` sait produire une grappe (`keycloak_grappe`, base distante) : la décision se révise sans réécrire.

## Conditions de révision

Second hyperviseur à PAR1 ou PAR2 (F5), base PostgreSQL répliquée disponible, exigence contractuelle de disponibilité de l'authentification (SLO), ou plus de deux incidents d'`idp01` par trimestre.
