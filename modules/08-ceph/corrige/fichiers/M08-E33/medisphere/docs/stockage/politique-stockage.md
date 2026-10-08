# Politique de stockage de MédiSphère

| | |
|---|---|
| Version | 1.0 |
| Propriétaire | Claire Morel (responsable infrastructure) ; sécurité : Sophie Laurent (RSSI) |
| Approuvée | 2026-10-XX (PLAT-959) |
| Prochaine revue | 2027-04 (semestrielle) ou à tout changement de cluster, de version majeure ou de site |

## 1. Objet et périmètre

Cette politique dit quel stockage la Plateforme propose aux équipes, à quelles conditions et avec quelles garanties. Elle s'applique au cluster **`ceph-par1`** : bloc (RBD), fichier (CephFS) et objet (RGW S3).

Hors périmètre : `s3-01` (stockage de la plateforme elle-même : état OpenTofu, artefacts — aucune donnée métier, ADR-0080) ; disques locaux des hyperviseurs ; sauvegardes PBS (politique de sauvegarde du socle) ; bases de données managées (M27).

Les procédures (comment faire) sont dans les runbooks ; ce document dit **ce qui est garanti**, et chaque garantie renvoie au mécanisme qui la rend vraie.

## 2. Classes de service

| Classe | Support (mécanisme) | Redondance garantie | Usages autorisés | Usages **interdits** | Performance indicative (lab, E28) | Sauvegarde |
|---|---|---|---|---|---|---|
| **Bloc performant** | RBD, pools sur la règle `ssd-baie` (classe `ssd`, réplication 3, domaine de panne `rack` : une baie par nœud) : `rbd-equipes`, `volumes`, `vms`, `images`, `k8s-rbd` | perte d'un OSD ou d'un hôte sans perte de données ni d'accès ; perte de deux hôtes : données intactes, **écritures bloquées** (`min_size=2`) | bases de données, disques de VM, volumes Kubernetes | données sans propriétaire ; volumes partagés entre équipes | `<IOPS>` en 4 Kio aléatoire, p99 `<ms>` (lab) | sur désignation par l'équipe (métadonnée, E25), RPO 24 h |
| **Bloc capacitif** | RBD sur la règle `hdd-baie` (classe `hdd`) : `backups` | idem | sauvegardes de volumes (Cinder Backup), archives froides | bases de données, tout ce qui demande de la latence | `<Mio/s>` séquentiel (lab) | non (c'est déjà une copie) |
| **Fichier partagé** | CephFS `cephfs`, un groupe de sous-volumes par équipe, sous-volumes isolés (espace de noms RADOS) | idem bloc performant ; MDS actif + attente | partages d'exports, modèles, fichiers échangés entre services d'une même équipe | bases de données ; partage entre équipes | `<…>` | non en v1 (instantanés de sous-volume seulement) |
| **Objet** | RGW S3, `https://rgw.par1.medisphere.internal` (2 démons + ingress), un compte RGW par application | idem bloc performant ; perte d'un démon RGW ou de la VIP active sans interruption au-delà de la bascule | documents (MédiDoc), archives applicatives, artefacts d'application | état d'infrastructure (OpenTofu : `s3-01`) ; hébergement public | `<…>` | non en v1 (ADR-0080, action F5) |

**Codes d'effacement** (E15) : non proposés en v1. Avec 3 hôtes, un profil `k=2, m=1` ne tolère qu'une panne pour un gain de capacité de 33 % sur la réplication, et coûte en latence et en CPU ; ils seront proposés pour l'objet capacitif quand le cluster aura au moins 6 hôtes.

## 3. Données de santé

Les données de santé (au sens HDS) ne peuvent être stockées que dans les classes **bloc performant**, **fichier partagé** et **objet**, et seulement si :
1. chiffrement en transit : TLS pour S3 (certificat de la PKI interne), msgr2 `secure` entre clients et démons (`ms_mode=secure` côté noyau) — **E27** ;
2. chiffrement au repos : OSD chiffrés (LUKS, `encrypted: true` dans `specs/osd.yaml`) — **E27, E46** ;
3. cloisonnement : identité dédiée à l'application, limitée à son espace de noms, son groupe de sous-volumes ou son compte RGW — **E31** ;
4. sauvegarde hors site désignée (bloc) ou plan de sauvegarde validé (objet : action ouverte, ADR-0080) ;
5. traçabilité des accès : à la charge de l'application (qui a lu quel document) ; Ceph fournit la traçabilité technique (journaux RGW, sessions cephx), pas la traçabilité métier.

Une donnée de santé dans une classe qui ne remplit pas ces conditions est un incident de sécurité (ticket SEC).

## 4. Capacité

| Seuil | Valeur | Mécanisme | Conséquence |
|---|---|---|---|
| Occupation brute d'alerte | 40 % | `ms-verif-ceph` (E24) | ticket d'extension (RB-081) ; aucune nouvelle allocation sans extension |
| `nearfull_ratio` | 0,75 (M08-E20, `config/cluster.yaml`) | Ceph (`OSD_NEARFULL`) | alerte ; réaction sous 24 h |
| `backfillfull_ratio` | 0,85 (M08-E20) | Ceph | la récupération s'arrête vers les OSD concernés |
| `full_ratio` | 0,95 (M08-E20) | Ceph (`OSD_FULL`) | **écritures refusées** sur tout le cluster |
| Remplissage d'un pool | 80 % | `ms-verif-ceph` | revue du quota avec l'équipe |

**Pourquoi 40 %** : avec 3 nœuds (une baie chacun) et 2 OSD SSD par nœud, la perte d'un OSD SSD reporte ses données sur l'**autre** OSD SSD du même nœud (domaine `rack`, un seul nœud par baie) ; celui-ci doit pouvoir doubler sans atteindre `backfillfull` (85 %). La perte d'un hôte entier, elle, ne déclenche aucune reconstruction (plus d'hôte disponible pour une troisième copie) : le cluster reste dégradé jusqu'au retour de l'hôte.

**Quotas** : chaque pool a un quota en octets stockés ; chaque équipe a un plafond par ressource (registre des allocations). Dans le lab, la somme des quotas dépasse la capacité sûre (surallocation assumée, surveillée) ; en production, la somme des quotas des pools d'une classe ne dépasse pas la capacité sûre de cette classe.

**Extension** : déclenchée à 40 % d'occupation brute ou quand une demande ne tient pas sous ce seuil ; délai d'ajout d'un nœud (RB-081) : 2 semaines en production, 1 jour dans le lab.

## 5. Demandes et cycle de vie

1. **Demande** : ticket DEV, puis MR de l'équipe Plateforme sur `allocations.yaml` (`plateforme/ceph`) et `allocations.md` ; validation par Claire (capacité) et Sophie si données de santé.
2. **Délai** : 2 jours ouvrés pour une équipe existante, 1 semaine pour une nouvelle équipe (identités, Vault, sauvegarde, supervision). Objectif d'outillage : livraison en moins de 30 minutes (E34).
3. **Extension** d'un plafond : même chemin ; refusée si elle franchit les seuils du §4.
4. **Libre-service** dans son périmètre : l'équipe crée, agrandit, prend des instantanés et supprime ses images et sous-volumes sans ticket, dans son plafond.
5. **Restitution** : ticket ; l'équipe confirme que les données sont migrées ou à détruire.
6. **Effacement** : suppression des images (et de **leurs instantanés**, y compris `sauv-*`), des sous-volumes, des objets et compartiments ; retrait de l'identité ; les sauvegardes PBS expirent selon la rétention (14 jours quotidiens, 8 semaines) — l'effacement définitif est donc acquis à J+8 semaines, et c'est ce délai qui est annoncé. Preuve : sortie de `ceph-allocations verifier` et listes vides jointes au ticket. Le chiffrement des OSD garantit qu'un disque retiré ne livre rien.
7. **Conservation** : la Plateforme ne garantit aucune durée de conservation légale ; l'application la porte (versionnage, verrouillage d'objets à venir).

## 6. Accès

- Une identité cephx par équipe (`client.<équipe>`), droits calculés par l'outil d'allocation : espace de noms RBD, chemin CephFS, espaces de noms RADOS de ses sous-volumes ; jamais `allow *`.
- Objet : un compte RGW par application ; l'équipe gère ses utilisateurs IAM avec l'utilisateur racine du compte.
- Remise des clés : par Vault uniquement (emplacement au registre des secrets) ; jamais par messagerie ou ticket.
- Renouvellement : au moins annuel, et immédiat en cas de départ ou de fuite (`ceph auth rotate`) ; type de clé `aes256k` dès que le client le permet (E27).
- L'équipe Plateforme peut **techniquement** lire toutes les données (administrateurs du cluster) : c'est écrit ici, tracé (sessions d'administration, `ceph log last`), et compensé par la séparation des rôles (M24) et le chiffrement applicatif pour les données les plus sensibles.

## 7. Exploitation

| Engagement | Mécanisme | Limite honnête |
|---|---|---|
| Détection d'une anomalie en moins de 10 minutes | `ms-verif-ceph` toutes les 5 minutes, `ms-alerte` | sonde sur un seul hôte (`adm01`) |
| Mises à jour mineures sans interruption | RB-082 (E26), mesuré : 0 échec client | une version majeure n'a pas encore été pratiquée |
| Sauvegarde bloc RPO 24 h, RTO mesuré `<RTO>` pour 1 Gio | E25, `tests/restauration-ceph.md` | objet et fichier non sauvegardés hors site en v1 |
| Disponibilité | aucune garantie chiffrée en v1 | **un seul site, un seul hyperviseur physique (`pve01`), un seul SSD physique** dans le lab : la perte de `pve01` arrête tout |

## 8. Exceptions et gestion du document

Une exception (usage interdit, dépassement de seuil, classe sans chiffrement pour des données de santé) est décidée par Claire, avec l'avis de Sophie si la sécurité est concernée, tracée par un ticket avec une **date de fin**, et listée ci-dessous.

| Exception | Ticket | Fin |
|---|---|---|
| Clés cephx de l'ancien type pour les clients qui ne savent pas encore utiliser `aes256k` (sourdine temporaire) | SEC-953 | `<date>` |

| Version | Date | Auteur | Changement |
|---|---|---|---|
| 1.0 | 2026-10-XX | `<MOI>` | création (PLAT-959) |
