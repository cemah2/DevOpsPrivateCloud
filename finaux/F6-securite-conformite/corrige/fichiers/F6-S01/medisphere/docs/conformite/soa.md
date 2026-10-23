# Déclaration d'applicabilité (SoA)

> SEC-3601 (F6-S01) — **version 1.0 du 2026-11-06**. Référentiel : **ISO/IEC 27001:2022**, annexe A (93 mesures), et exigences du **référentiel de certification HDS** (arrêté du 26 avril 2024) pour les activités 2 à 6. Périmètre : [`perimetre.md`](perimetre.md).
> Rédaction : Plateforme ; validation : Sophie Laurent (RSSI) ; approbation : direction générale. Révision à chaque changement de périmètre et au moins une fois par an.
> Les intitulés des mesures sont des traductions de travail : le texte de la norme (version française NF EN ISO/IEC 27001) fait foi.

## Lecture

- **Applicable** : `Oui` (la mesure est retenue) ou `Non` (exclue, avec la raison). Une mesure assurée par un fournisseur reste **applicable** : elle est mise en œuvre par le contrat et le suivi du fournisseur (5.19 à 5.22).
- **Justification** : pourquoi la mesure est retenue (risque, exigence légale ou contractuelle, exigence HDS) ou pourquoi elle est exclue.
- **Mise en œuvre** : où et comment, chez nous. **Preuve** : ce qu'on montre à l'auditeur (identifiants `P-…` du [catalogue des preuves](preuves.md), documents, outils). « Écart » renvoie au [rapport d'écarts](audit-2026/rapport-ecarts.md).
- Bilan : **92 mesures applicables, 1 exclue** (8.23). Abréviations : R = risque identifié, L = exigence légale ou réglementaire, C = exigence contractuelle, H = exigence HDS.

## 1. Mesures organisationnelles (5.1 à 5.37)

| Mesure | Intitulé | Applicable | Justification | Mise en œuvre | Preuve |
|---|---|---|---|---|---|
| 5.1 | Politiques de sécurité de l'information | Oui | R, H : cadre exigé par la norme et le référentiel | politique générale + politiques thématiques dans `docs/` (changement, accès, sauvegarde, durcissement) | documents approuvés, revue annuelle |
| 5.2 | Fonctions et responsabilités | Oui | R, H | RSSI (Sophie Laurent), DPO (Thomas Renaud), responsable infrastructure (Claire Morel), propriétaires par composant | organigramme, fiches de rôle, CODEOWNERS des dépôts |
| 5.3 | Séparation des tâches | Oui | R : administrer et contrôler ne doivent pas être la même personne | MR relues par un autre que l'auteur, approbation des changements, contrôle final des départs par une autre personne | règles d'approbation GitLab, fiches CHG |
| 5.4 | Responsabilités de la direction | Oui | R, H | revue de direction semestrielle, budget sécurité | comptes rendus de revue |
| 5.5 | Relations avec les autorités | Oui | L : CNIL, ANS, CERT Santé | DPO pour la CNIL ; clients pour le signalement des incidents graves (CSP) ; contacts tenus à jour | annuaire des contacts, RB-360 |
| 5.6 | Relations avec des groupes d'intérêt | Oui | R : veille | abonnements aux avis (CERT-FR, CERT Santé, éditeurs), groupe hébergeurs HDS | liste de diffusion, notes de veille |
| 5.7 | Renseignement sur les menaces | Oui | R : nouveauté 2022 | veille CVE des composants (Harbor, Trivy, listes des projets amont), modèle de menace (M26-E02) | modèle de menace, tickets SEC- issus de la veille |
| 5.8 | Sécurité de l'information dans la gestion de projet | Oui | R | revue de sécurité à l'ADR, Sophie relectrice des MR de sécurité | ADR, MR |
| 5.9 | Inventaire des informations et autres actifs | Oui | R, H | NetBox (matériel, VM, adresses), dépôts de code (tout le reste), catalogue Backstage | NetBox, inventaire Ansible, catalogue |
| 5.10 | Utilisation correcte des actifs | Oui | R | charte d'administration signée, règles « tout par le code » | chartes signées |
| 5.11 | Restitution des actifs | Oui | R : départs, prestataires | procédure de départ (F2-S12), restitution des postes et jetons matériels | `docs/accueil/departs/` |
| 5.12 | Classification des informations | Oui | R, H : données de santé | quatre niveaux (`perimetre.md` § 3) | `perimetre.md` |
| 5.13 | Marquage des informations | Oui | R | étiquettes d'espaces et de compartiments, en-têtes des documents | étiquettes Kubernetes `medisphere.internal/…` |
| 5.14 | Transfert des informations | Oui | R, H : flux entre sites et vers les clients | TLS partout (PKI interne), WireGuard entre sites, exports chiffrés | matrice des flux, `transferts-hors-eee.md` |
| 5.15 | Contrôle d'accès | Oui | R, H | moindre privilège par groupe (FreeIPA → Keycloak → services), RBAC, HBAC | P-IAM-01, P-IAM-04, revue des accès |
| 5.16 | Gestion des identités | Oui | R, H | une identité par personne (FreeIPA), identités de machines déclarées, prestataires datés | P-IAM-01, `comptes-declares.yaml` |
| 5.17 | Informations d'authentification | Oui | R, H | MFA obligatoire pour les administrateurs, secrets dans OpenBao, rotation | P-IAM-02, P-SEC-01 |
| 5.18 | Droits d'accès | Oui | R, H | attribution par MR (équipe en code), revue mensuelle (privilèges) et trimestrielle | `revue-acces/AAAA-MM.md`, P-IAM-06 ; **écart ECA-3604** |
| 5.19 | Sécurité dans les relations avec les fournisseurs | Oui | R, H : DataCampus (activité 1), prestataires | évaluation avant contrat, clauses de sécurité | registre des fournisseurs, RB-329 |
| 5.20 | La sécurité dans les accords avec les fournisseurs | Oui | R, H, C | clauses : confidentialité, localisation, incident, audit, restitution | contrats |
| 5.21 | Gestion de la sécurité dans la chaîne d'approvisionnement TIC | Oui | R : logiciels amont | images et charts recopiés, vérifiés (signatures, empreintes épinglées), SBOM | Harbor, `charts-miroir`, rôle `outils_supply_chain` |
| 5.22 | Surveillance, revue et gestion des changements des services fournisseurs | Oui | R, H | revue annuelle de DataCampus (certificat, rapports), suivi des fins de support | comptes rendus de revue fournisseur |
| 5.23 | Sécurité de l'information dans l'utilisation de services en nuage | Oui | R : MédiSphère **fournit** un nuage privé et **consomme** peu de services en nuage | règles d'usage des services en nuage, inventaire (`transferts-hors-eee.md`) | cartographie des transferts |
| 5.24 | Planification et préparation de la gestion des incidents | Oui | R, H, L | gestion d'incident (F3), RB-360 (réponse à incident de sécurité) | RB-360 ; **écart ECA-3605** |
| 5.25 | Évaluation des événements et décision | Oui | R | grille de gravité, astreinte, alertes Falco et audit | P-SUP-01, main courante |
| 5.26 | Réponse aux incidents | Oui | R, L | confinement (quarantaine réseau), communication, notification | RB-360, RB-361, dossiers `docs/securite/incidents/` |
| 5.27 | Tirer des enseignements des incidents | Oui | R | post-mortems sans recherche de coupable, actions suivies | post-mortems, tickets d'action |
| 5.28 | Recueil des preuves | Oui | R, L : enquête, juridique | collecte forensique (RB-361), preuves inaltérables (compartiment verrouillé) | RB-361, `preuves.md` ; **écart ECA-3605** |
| 5.29 | Sécurité de l'information durant une perturbation | Oui | R, H | les contrôles de sécurité restent actifs en PRA (PAR2 : mêmes politiques, mêmes secrets) | `docs/pra/`, exercice F5 |
| 5.30 | Préparation des TIC pour la continuité d'activité | Oui | R, H, C : RTO/RPO | site de repli PAR2, RTO/RPO par application, exercice annuel | `docs/pra/objectifs.md`, rapport d'exercice |
| 5.31 | Exigences légales, statutaires, réglementaires et contractuelles | Oui | L, H | registre des exigences (CSP, RGPD, HDS, contrats) | `perimetre.md` § 5, ce document |
| 5.32 | Droits de propriété intellectuelle | Oui | L : licences logicielles | revue des licences des composants (ex. Teleport, Liquibase, Vault BUSL écartés ou suivis) | ADR concernés |
| 5.33 | Protection des enregistrements | Oui | L, H : journaux, preuves | rétention par catégorie, archive inaltérable | `preuves.md` ; **écart ECA-3601** |
| 5.34 | Protection de la vie privée et des données à caractère personnel | Oui | L : RGPD | DPO, registre des traitements (sous-traitant), minimisation, pseudonymisation (Data) | registre, analyses d'impact des clients |
| 5.35 | Revue indépendante de la sécurité de l'information | Oui | R, H | audit à blanc (Auditia Santé), test d'intrusion annuel, audits de certification | rapports d'audit |
| 5.36 | Conformité aux politiques, règles et normes | Oui | R | contrôles automatiques (OpenSCAP, kube-bench, kubescape, Kyverno), registre des dérogations | P-DUR-01, P-VUL-02, `exceptions.md` |
| 5.37 | Procédures d'exploitation documentées | Oui | R, H | runbooks versionnés (`docs/*/runbooks/`) | runbooks RB-… |

## 2. Mesures liées aux personnes (6.1 à 6.8)

| Mesure | Intitulé | Applicable | Justification | Mise en œuvre | Preuve |
|---|---|---|---|---|---|
| 6.1 | Sélection des candidats | Oui | R : accès aux données de santé | vérifications proportionnées au poste, dans le respect du droit du travail | procédure RH (hors SI) |
| 6.2 | Conditions générales d'embauche | Oui | R, L | clause de confidentialité, secret professionnel des hébergeurs | contrats de travail |
| 6.3 | Sensibilisation, enseignement et formation | Oui | R, H | sensibilisation annuelle, formation des administrateurs (ce workbook) | registre des formations |
| 6.4 | Processus disciplinaire | Oui | R, L | règlement intérieur, charte d'administration | règlement intérieur |
| 6.5 | Responsabilités consécutives à la fin ou à la modification d'un emploi | Oui | R, H | départ par MR (désactivation, jetons, clés), contrôle final par un tiers | `docs/accueil/departs/`, P-IAM-01 |
| 6.6 | Engagements de confidentialité ou de non-divulgation | Oui | R, L, C | engagements des salariés et des prestataires | engagements signés |
| 6.7 | Travail à distance | Oui | R : administration à distance | VPN WireGuard, SSO + MFA, certificats SSH de 16 h, aucune donnée de santé sur les postes | configuration VPN, P-IAM-02 |
| 6.8 | Déclaration des événements de sécurité de l'information | Oui | R, L | adresse et canal de signalement, astreinte | procédure, main courante |

## 3. Mesures physiques (7.1 à 7.14)

| Mesure | Intitulé | Applicable | Justification | Mise en œuvre | Preuve |
|---|---|---|---|---|---|
| 7.1 | Périmètres de sécurité physique | Oui | R, H : assurée par DataCampus (activité 1) | contrat et certificat HDS du fournisseur ; baies fermées à clé dans des cages privatives | certificat DataCampus, contrat |
| 7.2 | Les entrées physiques | Oui | R, H : DataCampus + MédiSphère | badges nominatifs, liste des personnes autorisées tenue par MédiSphère, revue trimestrielle | liste d'accès, journaux de badge fournis par DataCampus |
| 7.3 | Sécurisation des bureaux, des salles et des équipements | Oui | R : cages et baies | cages privatives, baies à clé | rapport de visite |
| 7.4 | Surveillance de la sécurité physique | Oui | R, H : DataCampus | vidéosurveillance et gardiennage du fournisseur, alerte d'ouverture de baie | certificat et rapports DataCampus |
| 7.5 | Protection contre les menaces physiques et environnementales | Oui | R, H : DataCampus | détection et extinction d'incendie, climatisation ; deux sites distincts (PAR1, PAR2) | certificat DataCampus, `docs/pra/` |
| 7.6 | Travail dans les zones sécurisées | Oui | R | interventions annoncées, à deux pour les opérations sensibles, registre | registre d'intervention |
| 7.7 | Bureau propre et écran vide | Oui | R : écrans d'administration | verrouillage automatique des postes d'administration, aucune impression de données de santé | politique, configuration des postes |
| 7.8 | Emplacement et protection du matériel | Oui | R, H (activité 2) | serveurs en baies fermées, alimentation redondée par le fournisseur | inventaire NetBox (emplacement) |
| 7.9 | Sécurité des actifs hors des locaux | Oui | R : portables des administrateurs | chiffrement des disques des portables, aucune donnée de santé sur les postes | politique des postes |
| 7.10 | Supports de stockage | Oui | R, H (activité 2) | disques chiffrés ou effacés avant sortie, inventaire des supports | procès-verbaux d'effacement |
| 7.11 | Services généraux | Oui | R, H : électricité, climatisation (DataCampus) | engagements de disponibilité du fournisseur ; onduleur de baie | contrat DataCampus |
| 7.12 | Sécurité du câblage | Oui | R : câblage de baie (MédiSphère) et du bâtiment (DataCampus) | câblage étiqueté, liens inter-sites chiffrés (WireGuard) | NetBox (câbles), matrice des flux |
| 7.13 | Maintenance du matériel | Oui | R, H (activité 2) | contrats de maintenance, intervention sous escorte, disques conservés | contrats, fiches CHG |
| 7.14 | Mise au rebut ou réutilisation sécurisée du matériel | Oui | R, H, L | effacement certifié ou destruction des disques, procès-verbal | procès-verbaux de destruction (ex. migration des photos de `hp01`, M00) |

## 4. Mesures technologiques (8.1 à 8.34)

| Mesure | Intitulé | Applicable | Justification | Mise en œuvre | Preuve |
|---|---|---|---|---|---|
| 8.1 | Terminaux finaux des utilisateurs | Oui | R : postes d'administration et de développement qui accèdent à la plateforme | postes gérés, disque chiffré, accès par VPN + SSO + MFA ; `adm01` comme bastion | politique des postes, configuration VPN |
| 8.2 | Droits d'accès privilégiés | Oui | R, H | groupe `plateforme-admins`, MFA, bris de glace sous enveloppe, journalisés | P-IAM-03/04/05, revue des accès § 5 |
| 8.3 | Restriction d'accès aux informations | Oui | R, H | locataires Capsule, RBAC par espace, politiques OpenBao par équipe, CiliumNetworkPolicy | P-IAM-04, P-SEC-01 |
| 8.4 | Accès aux codes source | Oui | R | groupes GitLab, branches protégées, revue obligatoire | P-IAM-03, règles de projet |
| 8.5 | Authentification sécurisée | Oui | R, H | SSO Keycloak, OTP obligatoire pour les administrateurs, certificats SSH courts | P-IAM-02 |
| 8.6 | Dimensionnement | Oui | R, H | supervision de capacité (M21), bilans de capacité par module, quotas | tableaux Grafana, `ms-capacite-*` |
| 8.7 | Protection contre les programmes malveillants | Oui | R | images minimales signées, admission Kyverno, détection à l'exécution (Falco, Tetragon), AIDE sur les VM | P-VUL-02, alertes Falco |
| 8.8 | Gestion des vulnérabilités techniques | Oui | R, H | analyse Trivy (Harbor), correctifs automatiques de sécurité, montées planifiées | P-VUL-01, P-DUR-01 ; **écart ECA-3602** |
| 8.9 | Gestion des configurations | Oui | R : nouveauté 2022 | tout par le code (OpenTofu, Ansible, GitOps), durcissement CIS/ANSSI, dérive détectée | P-DUR-01, P-RES-01, Argo CD |
| 8.10 | Suppression des informations | Oui | L : RGPD, fin de contrat | effacement par l'API de Loki (M22-E13), purge applicative, réversibilité puis destruction | RB-221, procès-verbaux |
| 8.11 | Masquage des données | Oui | L, R | pseudonymisation des extractions de l'équipe Data, recette sans données réelles | code de l'extraction (F2-S09) |
| 8.12 | Prévention de la fuite de données | Oui | R | sorties réseau filtrées (bordure, CiliumNetworkPolicy), alerte sur flux sortant inattendu (Tetragon), politique Kyverno contre les identifiants en clair | règles Falco/Tetragon, politiques |
| 8.13 | Sauvegarde des informations | Oui | R, H (activité 6) | PBS, Velero, CloudNativePG, copies à PAR2, restaurations éprouvées | P-SAV-01, P-SAV-02 ; **écart ECA-3603** |
| 8.14 | Redondance des moyens de traitement de l'information | Oui | R, H, C | grappes (Ceph, OpenBao, Kubernetes), deux passerelles, site PAR2 | `docs/pra/`, P-SAV-02 |
| 8.15 | Journalisation | Oui | R, H, L | audit de l'API Kubernetes, d'OpenBao, de Keycloak ; Loki locataire `audit` (1 an) | configuration d'audit ; **écart ECA-3601** |
| 8.16 | Activités de surveillance | Oui | R : nouveauté 2022 | règles d'alerte d'audit (ruler de Loki), Falco, Tetragon, Alertmanager | P-SUP-01 |
| 8.17 | Synchronisation des horloges | Oui | R : corrélation des journaux, valeur probante | chrony sur `gw01`/`gw02` (référence), toutes les VM et nœuds synchronisés | supervision NTP (M21) |
| 8.18 | Utilisation de programmes utilitaires à privilèges | Oui | R | sudo limité par groupe (FreeIPA), `admin.conf` en bris de glace, alerte à son usage | règles sudo, alerte `AuditBrisDeGlace` |
| 8.19 | Installation de logiciels sur des systèmes en exploitation | Oui | R | uniquement par le code et les dépôts épinglés, images signées obligatoires en recette et prod | Kyverno, P-VUL-02 |
| 8.20 | Sécurité des réseaux | Oui | R, H | bordure nftables (code), VLAN, chiffrement WireGuard entre nœuds | P-RES-01, matrice des flux |
| 8.21 | Sécurité des services réseau | Oui | R | TLS (PKI interne), DNS faisant autorité interne, répartiteurs durcis | configuration, ssh-audit (S05) |
| 8.22 | Cloisonnement des réseaux | Oui | R, H | VLAN par fonction, politiques réseau par espace, quarantaine | matrice des flux, CiliumNetworkPolicy |
| 8.23 | Filtrage web | **Non** | Exclusion : aucune navigation web depuis les systèmes du périmètre ; les serveurs ne sortent vers Internet que vers une **liste fermée** de destinations (dépôts de paquets, registres amont) par la bordure, ce qui relève de 8.20 et 8.22 ; la navigation des postes est hors périmètre (SI interne). *À rediscuter avec l'auditrice : `adm01` sort-il librement ?* | — | matrice des flux (sorties) |
| 8.24 | Utilisation de la cryptographie | Oui | R, H, L | politique cryptographique, PKI interne, OpenBao `transit`, chiffrement des disques Ceph sensibles et d'etcd | P-SEC-01, ADR-0250/0251 |
| 8.25 | Cycle de vie de développement sécurisé | Oui | R : applications hébergées | composant CI `securite` (SAST, secrets, SBOM, signature) | pipelines, composant `securite` |
| 8.26 | Exigences de sécurité des applications | Oui | R, C | exigences dans les tickets DEV-, revue de sécurité des API | tickets, ADR |
| 8.27 | Principes d'ingénierie et d'architecture des systèmes sécurisés | Oui | R | défense en profondeur, moindre privilège, ADR relus par la RSSI | ADR |
| 8.28 | Codage sécurisé | Oui | R : nouveauté 2022 | règles Semgrep, revue de code, dépendances suivies | pipelines |
| 8.29 | Tests de sécurité dans le développement et l'acceptation | Oui | R, C | tests en CI, recette, test d'intrusion annuel | rapports |
| 8.30 | Développement externalisé | Oui | R : AxiomDev (F2) | accès borné, revue de tout code externe, clauses contractuelles | `docs/accueil/`, RB-329 |
| 8.31 | Séparation des environnements de développement, de test et opérationnels | Oui | R, H | espaces `-dev`, `-recette`, `-prod`, identités distinctes, aucune donnée réelle hors prod | locataires, politiques |
| 8.32 | Gestion des changements | Oui | R, H | processus F4, fiches CHG, mesure de l'interruption | P-CHG-01 |
| 8.33 | Informations de test | Oui | R, L | données fictives ou pseudonymisées en recette, jamais de copie de prod | revue des jeux de recette |
| 8.34 | Protection des systèmes d'information pendant les tests d'audit | Oui | R | audits outillés planifiés, comptes de lecture, hors heures de pointe, accord préalable | ce dossier d'audit, F6-S05 |

## 5. Exigences du référentiel HDS (activités 2 à 6)

Le référentiel HDS s'appuie sur la certification ISO/IEC 27001 du périmètre et y **ajoute** des exigences propres à l'hébergement de données de santé. Celles que MédiSphère doit démontrer, et où :

| Exigence HDS (thème) | Ce qu'on démontre | Où |
|---|---|---|
| Périmètre et activités certifiées | activités 2 à 6 exercées, activité 1 couverte par un hébergeur certifié | `perimetre.md` § 1 |
| **Localisation** des données dans l'EEE (souveraineté ; exigences 28 à 31 du référentiel, à relire dans le texte) | données et copies à PAR1 et PAR2 (France) | `perimetre.md` § 4, inventaire NetBox |
| **Transparence** : accès depuis un pays tiers, soumission à une loi extra-européenne, **cartographie des transferts publiée** | inventaire des fournisseurs et accès, publication | `transferts-hors-eee.md` ; **écart ECA-3606** |
| **Contrat** d'hébergement (CSP, art. R.1111-11) : prestations, localisation, sous-traitants, réversibilité, information du client | contrat type revu par le DPO | modèle de contrat |
| Information du client en cas d'**incident** | délai contractuel, procédure, modèles de message | RB-360 ; **écart ECA-3605** |
| **Réversibilité** et restitution des données en fin de contrat | export en format ouvert, destruction des copies | procédure de réversibilité |
| Traçabilité des **accès** aux données de santé | journaux d'accès applicatifs et d'administration conservés et protégés | Loki `audit` ; **écart ECA-3601** |
| **Sauvegarde** externalisée (activité 6) : chiffrement, restauration éprouvée | PBS, Velero, CNPG, copies PAR2 | P-SAV-01/02 ; **écart ECA-3603** |
| Gestion des **sous-traitants** de l'hébergeur | DataCampus et prestataires suivis | 5.19 à 5.22 |
| Mise en conformité au **nouveau référentiel** (hébergeurs déjà certifiés : au plus tard le 16 mai 2026) | certificat sous le référentiel de 2024 | dossier de certification |

## 6. Historique

| Version | Date | Changement | Approbation |
|---|---|---|---|
| 1.0 | 2026-11-06 | première version (préparation de l'audit à blanc) | Sophie Laurent |
