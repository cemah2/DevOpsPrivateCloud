# Périmètre de la certification et du SMSI

> SEC-3601 (F6-S01) — version 1.0 du 2026-11-06. Rédaction : Plateforme ; validation : Sophie Laurent (RSSI), Thomas Renaud (DPO), Claire Morel ; approbation : direction générale.
> Référentiels : **ISO/IEC 27001:2022** (et son amendement 1:2024) ; **référentiel de certification HDS** issu de l'arrêté du 26 avril 2024 (JO du 16 mai 2024). Déclaration d'applicabilité : [`soa.md`](soa.md).

## 1. Ce que MédiSphère fait, vu par le référentiel HDS

MédiSphère édite des applications de santé et les **héberge pour ses clients** (cabinets médicaux, centres de santé, établissements), qui sont **responsables de traitement** des données de santé de leurs patients. MédiSphère est donc **hébergeur de données de santé** au sens de l'article L.1111-8 du code de la santé publique, et **sous-traitant** au sens du RGPD (article 28). Héberger pour soi-même ne demanderait pas la certification ; héberger pour un tiers, si.

Les six activités du référentiel (article R.1111-9 du CSP) et ce que MédiSphère en exerce **réellement** :

| Activité | Définition (résumé) | Exercée ? | Comment, chez nous | Preuve principale |
|---|---|---|---|---|
| 1 | Mise à disposition et maintien en condition opérationnelle des **sites physiques** | **Non** | Les salles PAR1 et PAR2 sont des espaces privatifs loués chez **DataCampus**, opérateur de colocation **certifié HDS pour l'activité 1** (énergie, climatisation, contrôle d'accès au bâtiment, surveillance). MédiSphère ne gère que l'intérieur de ses baies | certificat HDS de DataCampus (activité 1) en vigueur, contrat, rapports de visite annuels |
| 2 | Mise à disposition et MCO de l'**infrastructure matérielle** | **Oui** | serveurs, disques, réseau de baie de MédiSphère (`pve01` à PAR1, `hp01` à PAR2), maintenance, remplacement, destruction des supports | inventaire NetBox, fiches de changement, procès-verbaux de destruction |
| 3 | Mise à disposition et MCO de l'**infrastructure virtuelle** | **Oui** | Proxmox VE (PAR1, PAR2), Ceph, OpenStack | code `plateforme/infra`, `plateforme/ceph`, `plateforme/openstack` ; preuves P-IAM-05, P-DUR-01 |
| 4 | Mise à disposition et MCO de la **plateforme d'hébergement d'applications** | **Oui** | Kubernetes `k8s-par1` (et `k8s-par2` en secours), registre, CI/CD, secrets, bases gérées | `plateforme/k8s`, `plateforme/gitops` ; preuves P-IAM-04, P-VUL-01/02, P-SEC-01 |
| 5 | **Administration et exploitation** du SI contenant les données de santé | **Oui** | équipe Plateforme et support (Nadia Roussel) : supervision, astreinte, gestion des incidents et des changements, accès d'administration | runbooks, post-mortems, fiches CHG ; preuves P-IAM-01/03/06, P-SUP-01, P-CHG-01 |
| 6 | **Sauvegarde externalisée** des données de santé | **Oui** | sauvegardes PBS sur `hp01` (PAR2), Velero et CloudNativePG vers `s3-01` puis `s3-02` (PAR2) | preuves P-SAV-01/02, rapports de restauration, exercice de PRA (F5) |

La certification demandée porte donc sur les **activités 2 à 6**. L'activité 1 est couverte par le certificat de DataCampus : c'est une **dépendance**, pas une exclusion « par commodité » ; elle est suivie comme fournisseur (mesures 5.19 à 5.22) et ses engagements figurent au contrat.

## 2. Périmètre du SMSI (ISO/IEC 27001)

**Énoncé** : « Conception, exploitation, administration, sauvegarde et support de la plateforme de cloud privé de MédiSphère (sites PAR1 et PAR2) et des applications de santé qu'elle héberge pour ses clients : MédiAgenda, MédiDoc, MédiNotif, Legacy-RDV et MédiVisio. »

| Dans le périmètre | Hors périmètre (et pourquoi) |
|---|---|
| Sites PAR1 et PAR2 : baies, matériel, réseau de baie, liens inter-sites | Bâtiments, énergie et accès aux salles : DataCampus (activité 1, certifié) |
| Socle (`gw01/02`, `adm01`, DNS, PKI, GitLab, NetBox, S3, supervision, annuaire, fournisseur d'identité, coffre) | SI interne : messagerie, bureautique, RH, comptabilité (aucune donnée de santé ; SI séparé, autre prestataire) |
| Plateformes : Proxmox VE, Ceph, OpenStack, Kubernetes, registre, CI/CD, GitOps | Postes de travail des salariés **en tant que tels** ; leurs **accès** à la plateforme (VPN, SSO, MFA, certificats SSH), eux, sont dans le périmètre (mesures 8.1, 8.5) |
| Applications hébergées et leurs données, toutes les copies (bases, sauvegardes, exports, réplicas de PAR2) | Équipe **Data** : ses traitements ne reçoivent que des extractions **pseudonymisées** ; l'extraction et la pseudonymisation sont dans le périmètre, l'analyse non |
| Processus : changements, incidents, accès, sauvegardes, continuité, fournisseurs, développement des applications hébergées (chaîne de livraison) | Développement **chez les clients** de leurs propres logiciels |
| Personnes : Plateforme, support, sécurité, développeurs des applications hébergées, prestataires ayant un accès (AxiomDev pendant sa mission) | — |

**Interfaces** : clients (responsables de traitement : contrat d'hébergement, information en cas d'incident, réversibilité) ; DataCampus (activité 1) ; fournisseurs de logiciels et de registres publics (aucune donnée de santé ne leur est transmise) ; prestataires de développement (accès borné, F2) ; autorités (CNIL, ANS / CERT Santé par l'intermédiaire des clients).

## 3. Données et classification

| Catégorie | Exemples | Où | Classification |
|---|---|---|---|
| Données de santé identifiantes | rendez-vous, motifs, documents patients | bases de MédiAgenda, compartiments de MédiDoc, sauvegardes | **Santé — confidentiel** |
| Données personnelles non médicales | comptes des professionnels, contacts, journaux d'accès | Keycloak, journaux | Confidentiel |
| Données pseudonymisées | extractions de l'équipe Data | `data-extractions`, `statistiques-db` | Interne (re-identification interdite contractuellement) |
| Secrets techniques | clés, mots de passe de service | OpenBao, `kms01`, enveloppe de reprise | Secret |
| Données de recette | jeux fictifs (règle : jamais de copie de production) | espaces `*-recette` | Interne — **à vérifier par la revue** |

## 4. Localisation

Toutes les données de santé et leurs copies sont hébergées **dans l'EEE**, à PAR1 et PAR2 (France). Les accès depuis un pays tiers et les dépendances à des fournisseurs soumis à une loi extra-européenne sont recensés dans [`transferts-hors-eee.md`](transferts-hors-eee.md) (F6-S07) ; la synthèse est publiée sur le site de MédiSphère, comme l'exige le référentiel HDS.

## 5. Parties intéressées et exigences

| Partie | Ce qu'elle exige | Où c'est traité |
|---|---|---|
| Clients (cabinets, établissements) | disponibilité, confidentialité, information sous 24 h d'un incident les concernant, réversibilité | contrats, RB-360 (réponse à incident), `docs/pra/` |
| Patients | confidentialité, droits RGPD (exercés auprès des clients) | DPO, procédure d'effacement (M22-E13) |
| ANS / organisme certificateur | conformité HDS v2, cartographie des transferts publiée | `soa.md`, `transferts-hors-eee.md` |
| CNIL | RGPD (art. 28, 32, 33) ; registre des violations | DPO |
| Deux grands clients | certificat ISO/IEC 27001 | ce SMSI |
| Direction | continuité, maîtrise des coûts | revue de direction |

## 6. Révision

Ce document est revu à chaque changement de périmètre (nouveau site, nouvelle application, nouvelle activité HDS) et au moins une fois par an, avant l'audit de surveillance.
