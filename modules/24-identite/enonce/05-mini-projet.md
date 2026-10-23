# Module 24 — Palier 5 : Mini-projet

Le module a donné à MédiSphère un annuaire, un fournisseur d'identité, le SSO de tous ses services, des certificats SSH de quelques heures, une authentification forte pour les administrateurs, des procédures d'arrivée et de départ, une revue des accès mensuelle et des comptes de secours éprouvés ; le palier 4 les a cassés et réparés. Il reste à le **livrer** comme une brique de la plateforme, et à le prouver devant ceux qui la financent et ceux qui l'auditeront. C'est ce que Claire Morel présentera au comité HDS sous le nom « Identité MédiSphère v1 ». Le module 25 (secrets) s'appuiera dessus dès sa première semaine : `bao login -method=oidc` par Keycloak, des politiques OpenBao tirées des groupes de l'annuaire, les secrets des clients Keycloak migrés dans OpenBao ; le module 26 (durcissement) durcira `idp01` et `ipa01` et branchera l'audit sur les mêmes identités.

---

### M24-E46 — Mini-projet : l'identité de MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-2546** — *De : Claire Morel* — *Copie : Sophie Laurent, Karim Benali, Nadia Roussel, Julien Petit*
> Comité HDS dans trois semaines. Je veux pouvoir dire, preuves à l'appui : une identité par personne, une seule source de vérité, l'authentification forte pour les administrateurs, des droits qui découlent des groupes, plus aucun compte local hors des comptes de secours, et la liste de qui a accès à quoi signée chaque mois. Et je veux le voir : pendant la revue, Sophie fera partir un prestataire en direct, et je chronomètre — tout doit être coupé en **moins de 15 minutes**, preuves comprises.
> Pendant la revue : Sophie relira le modèle d'autorisation, la revue d'accès et les comptes de secours ; Karim relira `plateforme/identite` et ouvrira devant nous l'accès d'un nouvel arrivant ; Nadia coupera Keycloak et vous demandera d'entrer dans Grafana et dans le cluster par la procédure de secours ; Julien vérifiera que son équipe a exactement les droits du modèle, ni plus ni moins. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider l'identité de la plateforme en une brique cohérente, pilotée par le code (OpenTofu, Ansible, Argo CD), sans dette provisoire.
- Prouver ce qui a été construit : SSO de bout en bout, autorisation par groupes, départ en moins de 15 minutes, bris de glace, revue d'accès.
- Livrer l'état `identite-v1` : documentation, runbooks, inventaire des comptes locaux restants, étiquette de version, et ce que les modules 25 et 26 consommeront.

**Prérequis** : M24-E01 à M24-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`).
**Durée indicative** : 8 à 12 h, plus 30 min de revue.

**Contexte technique**
- Faits figés du module (introduction et PLAN §4.12) : `ipa01` (1031, 10.10.20.31, FreeIPA 4.13), `idp01` (1030, 10.10.20.30, Keycloak 26.8.1 depuis E33, PostgreSQL 17), `sso.par1.medisphere.internal` publié par `lb01`/`lb02` ; royaume `medisphere` en OpenTofu (`plateforme/identite/tofu/`), annuaire en Ansible (`plateforme/identite/annuaire/`).
- Personne fictive de la démonstration de départ : **Thomas Leroy**, prestataire InfoGér (`thomas.leroy`, groupe `plateforme`), arrivé par RB-241 **avant** la revue avec tous les accès qu'un membre de `plateforme` peut avoir (SSO de chaque service, un jeton personnel GitLab, un certificat SSH, une session `kubectl`). Variable `WB_M24_DEPART` de `lab/lab.env` si tu choisis un autre identifiant.
- Le contrôle global `lab/bin/check 24 46` rejoue les contrôles clés des paliers 1 à 3 (fédération, GitLab, Argo CD, cluster, VMs, SSH, MFA, bris de glace, revue des accès) puis vérifie les clients, les comptes locaux, l'absence de provisoire, la démonstration de départ, la documentation et l'étiquette. Il prend quelques minutes.

**État livré `identite-v1`** — ce que les modules suivants trouveront, tel que les exercices du module l'ont construit. Rien de ce tableau ne doit manquer, rien ne doit porter un autre nom.

| Élément | État attendu à la livraison |
|---|---|
| Annuaire | `ipa01` sain (`ipactl status`), CA subordonnée chaînée à la racine MédiSphère ; personnes, groupes (`plateforme-admins`, `plateforme`, `mediagenda`, `medidoc`, `securite`, `support`, `direction`), politiques, HBAC, sudo **en code** (`annuaire/`), job `annuaire:appliquer` protégé et vérification de dérive planifiée ; sauvegarde `ipa-backup` et PBS |
| Fournisseur | Keycloak 26.8.1 sur `idp01`, une instance (ADR-0241) ; royaume `medisphere` entièrement en OpenTofu (`tofu plan` vide), état chiffré ; fédération `ipa01` en `READ_ONLY` ; portée `groupes` ; flux `navigateur-medisphere` (OTP pour `plateforme-admins` et `securite`) ; durées et force brute d'E27 ; clés `rsa-2026-10` ; `master` : `<MOI>-admin` (OTP) et `kc-secours` seulement |
| Clients | `gitlab`, `grafana`, `argocd`, `argocd-cli`, `harbor`, `proxmox`, `pbs`, `netbox`, `kubernetes`, `oauth2-proxy`, `step-ca`, `wb-checks`, `revue-acces` (et `svc-tofu-keycloak` dans `master`) : URI de retour exactes, ni flux implicite ni *Direct Access Grants*, PKCE là où le service l'envoie, secrets au Vault `critique` ; aucun client d'essai |
| Services | GitLab, Grafana, Argo CD, Harbor, Proxmox VE, PBS, NetBox en SSO ; Hubble, Pyroscope, Pyrra (cluster) et Mailpit (`mon01:8443`) derrière OAuth2 Proxy ; `kubectl` par OIDC (authentification structurée, kubelogin) et RBAC `oidc:*` ; SSH par certificats de 16 h (provisioner `keycloak` de step-ca), SSSD, HBAC, sudo sur toutes les VMs inscrites |
| Comptes locaux | seulement les comptes de secours de RB-240 (`kc-secours`, `admin` de l'annuaire, `root` de GitLab, `admin` d'Argo CD désactivé, `admin` de Grafana et de Harbor, `root@pam`, superutilisateur de NetBox, `admin.conf`, `admin` des VMs) et les comptes de **service** inventoriés (robots Harbor, `ci-lecture`, `wb-checks`…) ; chaque exception écrite et justifiée |
| Exploitation | sauvegardes chiffrées et restauration éprouvée (RB-243), supervision et journal d'audit (E26), alertes de bris de glace (E28), rotations (RB-244), montée de version (RB-245), revue des accès mensuelle signée (`docs/securite/identite/revue-acces/`), RB-246 |
| Documentation | `docs/securite/identite/` : `modele-autorisation.md`, `ceremonie-ca.md`, `master.md`, ADR-0240 et ADR-0241, RB-240 à RB-246, `analyses/`, `post-mortems/`, **`identite-v1.md`** (fiche de livraison) ; matrice des flux à jour ; étiquette **`identite-v1`** sur `plateforme/medisphere` |

**Travail demandé**
1. **Rien de provisoire.** Aucune panne `M24` ouverte, aucune VM d'essai du module (2241, 2242), aucun client d'essai, aucun récepteur ou fichier de jetons laissé, aucun compte de secours resté ouvert, aucune modification du royaume ou de l'annuaire hors du code (`tofu plan` vide, annuaire sans dérive).
2. **Tout en SSO.** Chaque service du tableau accepte le SSO et refuse ce qu'il doit refuser ; les comptes locaux restants sont exactement ceux de l'inventaire, chacun avec son rangement, son usage et son alerte.
3. **Des droits qui découlent des groupes.** Pour chaque groupe, la matrice du modèle d'autorisation est vérifiée **service par service** (une preuve par case : décision de l'autorisateur, rôle effectif, refus constaté) ; les écarts sont corrigés ou acceptés nommément (`ecarts-acceptes.yml`, E30).
4. **Le départ en moins de 15 minutes.** Thomas Leroy arrive par RB-241 (avant la revue), utilise réellement chaque accès, puis part par RB-242 en direct : chronomètre, preuve de chaque coupure (connexion SSO refusée, jeton GitLab révoqué, certificat SSH refusé à l'étape *account*, `kubectl` refusé au rafraîchissement, sessions des services fermées ou leur durée résiduelle écrite), et la revue des accès relancée sans lui. Répète-la avant la revue.
5. **Le SSO coupé.** La démonstration de Nadia (Keycloak arrêté par la procédure de RB-246, entrée dans Grafana et dans le cluster par RB-240, alertes reçues, comptes refermés, retour à la normale) est répétée et chronométrée.
6. **Ce que le M24 avait promis.** Reprends les promesses des modules précédents envers l'identité (introduction du module, ADR-0210 du M21, durcissement de GitLab du M01, tableau de bord de Ceph, Proxmox) : tenue, ou reportée avec la raison et le module qui la reprend.
7. **Documentation.** `identite-v1.md` : architecture, ce qui est couvert, **limites assumées**, inventaire des comptes locaux restants, résultat chronométré de la démonstration de départ, ce que le **M25** consommera (client `openbao` à créer, groupes → politiques, secrets des clients à migrer) et ce que le **M26** consommera (durcissement d'`idp01` et `ipa01`, audit, console d'administration sous un autre nom).
8. **Livraison.** Tout est fusionné, les pipelines de `main` sont verts, l'étiquette **`identite-v1`** est posée sur `plateforme/medisphere`.
9. **La revue.** 10 minutes de présentation (architecture, choix, limites), les démonstrations de Sophie (départ) et de Nadia (SSO coupé), l'arrivée d'une personne par Karim (RB-241, moins de 30 minutes jusqu'au premier accès réussi), la vérification de Julien, les questions.

**Contraintes**
- Tout passe par le code (OpenTofu, Ansible, Argo CD) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Aucun secret dans un dépôt, un ticket, un compte rendu ou une démonstration : des **emplacements**, jamais des valeurs ; aucun jeton complet dans la documentation.
- Un compte de secours ouvert pour une démonstration est tracé, refermé, et son alerte vérifiée.
- Jamais deux VMs temporaires à la fois ; la démonstration de départ ne touche que la personne fictive.

**Critères de réussite**
- [ ] `lab/bin/check 24 46` est entièrement vert.
- [ ] Démonstration de Sophie : toutes les coupures de RB-242 prouvées en moins de 15 minutes, preuve écrite dans `identite-v1.md` (heures, commande ou capture par service, aucune valeur de jeton).
- [ ] Démonstration de Nadia : entrée par les comptes de secours dans Grafana et dans le cluster, alertes `BrisDeGlace*` reçues, comptes refermés, SSO rétabli, sans intervention hors RB-240 et RB-246.
- [ ] `identite-v1.md` dit ce qui n'est **pas** couvert, ce que les modules 25 et 26 trouveront, et le sort de chaque promesse ; la revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 24 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 24 46` dès le début : la liste des points rouges est ton plan de travail. `lab/bin/check 24 43` rejoue d'un coup les contrôles du palier 4, qui sont aussi des contrôles de santé de toute la chaîne d'identité. La revue des accès d'E30, lancée à la main, donne la liste des comptes locaux et des écarts.
</details>

<details><summary>Indice 2</summary>

Le départ en 15 minutes se joue **avant** la revue : RB-242 suppose des commandes prêtes (identifiants, appels d'API) et des preuves qu'on sait produire vite. Un script de preuves en **lecture** (il interroge chaque service et écrit le tableau de résultats) vaut mieux que dix captures d'écran. Ce qui ne peut pas être coupé en 15 minutes (une session déjà ouverte dans un service qui ne reçoit pas de déconnexion, un certificat SSH déjà émis) doit être **écrit**, avec la durée résiduelle et ce qui la borne (SSSD, HBAC).
</details>

<details><summary>Indice 3</summary>

« Ce qui n'est pas couvert » : un seul nœud Keycloak (ADR-0241), l'annuaire sans réplica, `idp01` niveau 0 sans HSM, pas de déconnexion par canal arrière vers les services, des jetons non liés à l'émetteur de la requête, la CA SSH d'utilisateurs hors HSM, les secrets des clients encore dans Ansible Vault. Pour chacun : le risque, ce qui le détecte (ou rien), et le module ou le final qui le traite.
</details>

**Pour aller plus loin** (facultatif) : transforme le départ en **job** manuel protégé de `plateforme/identite` qui fait les étapes de RB-242 et produit lui-même le rapport de preuves ; ajoute OAuth2 Proxy devant Thanos Query et Alertmanager (promesse du M21, avec un accès par jeton pour les sondes du témoin et le ruler de Loki) ; ou prépare le M25 : le client `openbao` en code, sans l'appliquer, relu par Sophie.
