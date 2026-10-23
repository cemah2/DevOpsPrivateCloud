# ADR-0371 — Clés de chiffrement dédiées au GHSV

| | |
|---|---|
| Statut | **Accepté** (<DATE>) — points marqués « à confirmer » levés en F7-S07 |
| Décideurs | Sophie Laurent (RSSI), Karim Benali, Thomas Renaud (DPO), Claire Morel |
| Ticket | PLAT-3704 (F7-S04) |
| Exigences | ESC-06, ESC-07, ERV-04 ; réponse R-14 |
| Complète | ADR-0250 (OpenBao, scellement `transit` par `kms01`, M25), ADR-0251 (chiffrement d'etcd) |

## Contexte

ESC-06 exige que les données de santé du GHSV (base, pièces jointes, **sauvegardes**) soient chiffrées au repos avec des clés **dédiées**, avec rotation au moins annuelle et révocation possible. R-14 précise : le GHSV veut pouvoir rendre ses données **définitivement illisibles** et en obtenir la preuve ; il ne veut pas détenir les clés. ERV-04 exige la destruction de toutes ses données, sauvegardes et copies de PAR2 comprises, sous 30 jours.

Aujourd'hui, la plateforme chiffre au repos de façon **mutualisée** : chiffrement des disques par l'hébergeur ou Ceph (selon la configuration), `secretbox` pour etcd (ADR-0251), sauvegardes PBS chiffrées par une clé de la plateforme, chiffrement côté serveur des compartiments du F6. Une clé partagée ne se détruit pas pour un seul client. La question qui décide : **si on détruit la clé du GHSV, qu'est-ce qui devient illisible ?** Tout ce qui ne l'est pas devra être effacé une copie à la fois, sauvegardes comprises : c'est ce qu'on ne sait pas prouver.

## Décision

Clés **gérées par MédiSphère** dans OpenBao (moteur `transit`), **une par usage**, utilisables seulement par les identités du locataire `ghsv` :

| Clé | Ce qu'elle protège | Mécanisme |
|---|---|---|
| `transit/ghsv-donnees` (cible de production, pas dans le lab) | champs identifiants des rendez-vous (patient, contact du rappel, motif) dans la base, **et donc** dans ses sauvegardes, ses WAL archivés, son réplica de PAR2 et les exports | chiffrement **applicatif** par MédiAgenda (chiffrement d'enveloppe : une clé de données par enregistrement ou par lot, chiffrée par `transit`) — développement DEV-3707 |
| `transit/ghsv-sauvegardes` | pièces jointes et sauvegardes de la base dans le stockage objet | chiffrement côté serveur du stockage objet avec un KMS externe (Ceph RGW SSE-KMS avec OpenBao en moteur `transit` : compatibilité **à confirmer**) ; à défaut, chiffrement côté client par l'application avant dépôt |
| `transit/ghsv-exports` | exports de réversibilité et restitutions de journaux | chiffrement d'enveloppe de l'archive livrée (clé de données à usage unique ; remise au GHSV par un canal séparé) |
| `transit/ghsv-signature` (signature, pas chiffrement) | manifestes des exports | le GHSV vérifie l'origine et l'intégrité de l'export avec la clé publique |

Règles :
- **Non exportables**, sans sauvegarde en clair, **suppression interdite par défaut** (`deletion_allowed` à faux : l'autoriser est un changement relu, préalable à toute destruction).
- **Rotation** automatique annuelle (`auto_rotate_period`, ESC-06), anciennes versions conservées pour déchiffrer ; ré-chiffrement des données au fil de l'eau (`rewrap`) ; preuve : métadonnées de la clé dans le rapport mensuel (NF-18).
- **Accès** : politiques OpenBao par identité de charge de travail (`kubernetes`, rôle du locataire `ghsv`) ; aucune personne n'a `transit/decrypt` sur ces clés ; administration (rotation, configuration) par le groupe `plateforme-admins`, journalisée (audit OpenBao).
- **Destruction** (R-14, ERV-04) : procédure à **deux personnes** (RSSI + responsable infrastructure), autorisation de suppression de la clé, suppression dans OpenBao, **instantanés Raft d'OpenBao** qui contiennent encore la clé : purgés ou laissés expirer selon leur rétention (à documenter : c'est là que la clé survit), procès-verbal remis au GHSV avec les horodatages de l'audit. Les données chiffrées par ces clés, partout (sauvegardes, PAR2, copies hors site), deviennent illisibles : c'est la **destruction cryptographique**.
- **Ce qui n'est pas couvert** par ces clés et doit être détruit autrement : métadonnées non chiffrées (identifiants de rendez-vous, praticiens, horaires), journaux (pseudonymisés, ADR-0374), comptes des patients dans Keycloak (suppression du royaume `ghsv-patients` et de ses sauvegardes de base). Écrit dans le plan de réversibilité.

## Options étudiées

| Option | Pour | Contre | Décision |
|---|---|---|---|
| Chiffrement des volumes seulement (LUKS par volume, clé dans un KMS) | transparent pour l'application | ne couvre ni les sauvegardes logiques (WAL, base backups), ni le réplica de PAR2, ni les exports : la destruction de la clé ne rend illisible que des volumes qu'on peut de toute façon effacer | **écartée** comme mécanisme principal ; conservée comme défense en profondeur si la plateforme l'offre |
| **Chiffrement applicatif par `transit` + SSE-KMS pour les objets** | la clé suit la donnée partout (sauvegardes, PAR2, exports) ; destruction prouvable | développement dans MédiAgenda ; recherches sur les champs chiffrés impossibles (on ne cherche pas par nom de patient : le DPI fournit l'identifiant) | **retenue** |
| Clés fournies par le GHSV (BYOK) ou détenues par lui (HYOK, HSM chez lui) | contrôle total du client | R-14 : le GHSV ne le veut pas et n'a pas de HSM ; HYOK rend notre disponibilité dépendante de son infrastructure | **écartée** ; révision si un client l'exige |
| HSM matériel chez MédiSphère | racine de confiance matérielle, certifiable | coût (deux appareils par site), OpenBao ne s'intègre à un HSM (PKCS#11) que pour le scellement selon les versions : à étudier | **écartée en v1** ; à étudier pour la certification |

## Conséquences

- Développement : DEV-3707 (chiffrement d'enveloppe dans MédiAgenda, migration des données existantes, tests), estimé à 10 jours.
- Disponibilité : OpenBao devient une dépendance **en lecture et en écriture** de la prise de rendez-vous (avant : seulement au démarrage, pour les secrets). Cache local des clés de données déchiffrées (durée courte) et supervision d'OpenBao comme composant critique ; PRA : `bao-par2` doit être restauré **avant** la reprise du GHSV (ordre du F5).
- Performance : un appel `transit` par lot d'écritures ; à mesurer en F7-S07 (impact sur le p95).
- Preuves : démonstration de destruction dans le lab (clé de recette détruite → sauvegarde de recette illisible) en F7-S07 ou S10.

## Révision

À réexaminer : si la compatibilité RGW ↔ OpenBao (`transit`) n'est pas confirmée ; si l'impact sur le p95 dépasse 20 ms ; à la demande d'un client pour du BYOK.
