# Catalogue des preuves de conformité

> PLAT-3602 (F6-S02) — propriétaire : Sophie Laurent (RSSI) ; outillage : équipe Plateforme.
> Révisé à chaque ajout de preuve (MR relue par Sophie) et au moins une fois par an avant l'audit de surveillance.

## 1. Principe

Une preuve n'a de valeur que si l'on peut montrer **quand** elle a été produite, **par quoi**, et qu'elle **n'a pas été retouchée** depuis. Chez MédiSphère :

- les preuves **techniques** sont produites **automatiquement** par `ms-preuves` (projet `plateforme/outils`), lancé par des pipelines planifiés : personne ne les fabrique à la main la veille d'un audit ;
- chaque collecte forme un **lot** : les fichiers de preuve, leur journal, un `lot.json` (horodatage UTC, pipeline, commit de l'outil, empreinte du catalogue), un manifeste `MANIFESTE.sha256` **signé** par la clé `transit/preuves-conformite` d'OpenBao (Cosign) ;
- le lot est déposé dans le compartiment RGW **`preuves-conformite`** (`https://rgw.par1.medisphere.internal`), créé avec le **verrouillage d'objets** : versionné, rétention par défaut en mode `COMPLIANCE` ;
- les preuves **documentaires** (politiques, procédures, comptes rendus, rapports) vivent dans `plateforme/medisphere` : l'historique Git (MR relues et approuvées) est leur preuve d'existence et de date ; leur état à la date de l'audit est figé par l'étiquette posée à chaque audit.

## 2. Stockage et rétention

| Élément | Valeur | Pourquoi |
|---|---|---|
| Compartiment | `preuves-conformite`, RGW de `ceph-par1` | stockage objet de la plateforme, déjà sauvegardé et supervisé |
| Verrouillage | activé à la création ; versionnage automatique, qui ne peut plus être suspendu | aucun objet n'a jamais existé sans protection ; une écriture crée une version, n'écrase rien |
| Rétention par défaut | **COMPLIANCE 400 jours** (après une phase d'essai en GOVERNANCE 1 jour) | couvre l'année entre deux audits de surveillance, plus une marge pour l'audit lui-même ; en COMPLIANCE personne, administrateur compris, ne raccourcit ni ne supprime |
| Identités | `preuves` (propriétaire, écriture par la collecte, quota 20 Go), `preuves-lecture` (lecture : auditeurs, contrôles) | séparation écriture / lecture ; en `COMPLIANCE`, aucune identité S3 ne peut supprimer une version avant l'échéance |
| Chemin d'un lot | `lots/AAAA/MM/JJ/<AAAAMMJJTHHMMSSZ>-<fréquence>/` | tri chronologique, un lot = un dossier |
| Clé de signature | `transit/preuves-conformite` (ECDSA P-256, non exportable) ; clé publique : [`cle-preuves.pub`](cle-preuves.pub) | distincte de la clé des images ; remise à l'auditeur |

**Limites connues, écrites** :
- Un administrateur de **Ceph** (accès à `radosgw-admin` ou aux pools) peut détruire des données sous le niveau S3 : le verrouillage protège contre les identités S3, pas contre la destruction du stockage. Compensation : la copie de `preuves-conformite` vers `s3-02` (PAR2, F5) et les sauvegardes de `ceph-par1` ; séparation des rôles (l'administration de Ceph n'est pas celle qui produit les preuves). *À confirmer sur le lab* : comportement de `radosgw-admin object rm` et de `bucket rm --purge-objects` sur un objet en COMPLIANCE.
- La signature est faite **sans journal de transparence** (configuration de signature « sans service » de MédiSphère) : elle prouve **qui** a signé, pas **quand**. La date de confiance est celle du dépôt dans le compartiment verrouillé (date de dernière modification et échéance de rétention fixées par le serveur). Une autorité d'horodatage RFC 3161 est une amélioration envisagée.
- La **rétention par défaut** est un réglage du compartiment : son propriétaire (`preuves`, l'identité de la collecte) peut la modifier, et un objet écrit en `GOVERNANCE` peut être supprimé par une identité qui a le droit de contournement (le propriétaire, dans RGW). Le mode et l'échéance de **chaque** objet sont donc relevés au dépôt (`DEPOT.json`), la rétention en cours est vérifiée chaque jour (`preuves:verification`) et le réglage `COMPLIANCE` du compartiment est contrôlé ; les objets déjà écrits en `COMPLIANCE` ne sont pas touchés par un changement de réglage.
- Une preuve en **échec** de collecte est déposée quand même (lot « partiel ») : l'absence de preuve est un fait à conserver.

## 3. Preuves automatiques (collectées par `ms-preuves`)

Collecteurs en lecture seule, identités de lecture lues dans OpenBao (`kv/plateforme/preuves/*`) par le jeton du job (rôle JWT `ci-preuves`). Pipelines planifiés de `plateforme/outils` : quotidien 02:05, hebdomadaire le dimanche 05:35 (après l'analyse OpenSCAP), mensuel le 1er à 06:05 ; contrôle d'intégrité du dernier lot chaque jour (`preuves:verification`).

| ID | Preuve | Mesures ISO 27001:2022 | Activités HDS | Fréquence | Source |
|---|---|---|---|---|---|
| P-IAM-01 | Comptes de personnes (état, expiration, groupes) et groupes de l'annuaire | 5.16, 5.18, 6.5 | 5 | quotidienne | FreeIPA (`ipa01`) |
| P-IAM-02 | Réglages de sécurité, flux et clients du royaume `medisphere` | 5.17, 8.5 | 4, 5 | hebdomadaire | Keycloak (`idp01`) |
| P-IAM-03 | Comptes GitLab (état, administrateurs, externes, second facteur) | 5.18, 8.2, 8.4 | 5 | quotidienne | GitLab (`git01`) |
| P-IAM-04 | Liaisons RBAC de `k8s-par1` | 5.15, 8.2, 8.3 | 3, 4 | quotidienne | Kubernetes |
| P-IAM-05 | Utilisateurs, jetons et ACL de Proxmox VE | 5.18, 8.2 | 2, 3 | hebdomadaire | `pve01` |
| P-IAM-06 | État brut de la revue des accès (`ms-revue-acces --json`) | 5.18, 5.15, 6.5 | 5 | mensuelle | neuf systèmes (F6-S03) |
| P-VUL-01 | Analyse des images **en service** (Harbor, Trivy) | 8.8, 8.19 | 4 | hebdomadaire | Harbor + Kubernetes |
| P-VUL-02 | Dérogations Kyverno (échéance, ticket, registre) | 5.36, 8.8, 8.9 | 4 | quotidienne | `kyverno-exceptions` |
| P-SAV-01 | Planifications et sauvegardes Velero (14 jours) | 8.13 | 6 | quotidienne | Velero |
| P-SAV-02 | Sauvegardes et archivage continu CloudNativePG | 8.13, 8.14 | 6 | quotidienne | CNPG |
| P-DUR-01 | Scores OpenSCAP (CIS, ANSSI) par hôte | 8.9, 8.8 | 2, 3, 5 | hebdomadaire | Prometheus (M26-E24) |
| P-RES-01 | Règles actives de la bordure et empreinte de la configuration persistée | 8.20, 8.22, 8.9 | 2, 5 | quotidienne | `gw01`, `gw02` (compte `preuves`) |
| P-SEC-01 | Méthodes, moteurs et politiques d'OpenBao (métadonnées) | 8.24, 5.17, 8.2 | 4, 5 | hebdomadaire | OpenBao |
| P-SUP-01 | Silences et alertes en cours | 8.16, 5.25 | 5 | quotidienne | Alertmanager |
| P-CHG-01 | Fiches de changement et décisions | 8.32 | 5 | mensuelle | `plateforme/medisphere` |

## 4. Preuves documentaires et autres sources

| Preuve | Mesures | Où | Propriétaire |
|---|---|---|---|
| Politique de sécurité, rôles, SoA, périmètre | 5.1, 5.2, 5.4 | `docs/conformite/` (`perimetre.md`, `soa.md`) | Sophie Laurent |
| Revue des accès mensuelle (décisions) | 5.18 | `docs/conformite/revue-acces/AAAA-MM.md` | Sophie Laurent, Claire Morel |
| Registre des dérogations de durcissement | 5.36, 8.9 | `docs/securite/durcissement/exceptions.md` (M26) | Sophie Laurent |
| Fiches de changement, revues du trimestre | 8.32 | `docs/changements/` (F4) | Claire Morel |
| Post-mortems et main courante | 5.24-5.27 | `docs/exploitation/`, `docs/securite/incidents/` | Nadia Roussel |
| Exercice de PRA et rapport | 5.29, 5.30, 8.14 | `docs/pra/` (F5) | Claire Morel |
| Rapports OpenSCAP complets (ARF) | 8.9 | `s3-01`, compartiment `conformite` (M26-E24) | Plateforme |
| Journaux d'audit (Kubernetes, OpenBao…) | 8.15, 8.16 | Loki, locataire `audit` (1 an) ; archive inaltérable (F6-S08) | Plateforme |
| Départs et arrivées (preuves de retrait d'accès) | 5.18, 6.5 | `docs/accueil/departs/` (F2) | Julien Petit / Plateforme |

## 5. Vérifier une preuve (procédure pour l'auditeur)

1. Recevoir la clé publique `cle-preuves.pub` (par MR relue, empreinte annoncée oralement) et l'identité `preuves-lecture`.
2. Lister les lots : `ms-preuves lister --depuis AAAA-MM-JJ`.
3. Vérifier un lot : `ms-preuves verifier s3://preuves-conformite/lots/AAAA/MM/JJ/<LOT>/` — empreintes recalculées, aucun fichier hors manifeste, signature vérifiée, rétention en cours sur chaque objet.
4. Pour une preuve isolée : `aws s3api get-object-retention` et `list-object-versions` montrent l'échéance et l'absence de version antérieure.

Un échec de `preuves:verification` ou un lot manquant (aucun lot depuis 48 h) ouvre un ticket `SEC-` au nom de la RSSI.

## 6. Ajouter une preuve

MR sur `plateforme/outils` (collecteur en lecture seule + ligne du catalogue + test) **et** sur ce document (même identifiant). Un collecteur ne sort jamais de secret : `ms-preuves` refuse la preuve s'il en détecte un (motifs de mots de passe, clés, jetons) — un faux positif se corrige dans le collecteur (champ retiré), jamais en désactivant le contrôle.
