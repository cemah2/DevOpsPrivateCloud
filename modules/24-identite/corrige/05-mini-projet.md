# Module 24 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** : `check-E46.sh` a été lancé à blanc (sans lab : chaque contrôle passe au rouge ou est ignoré) ; la démonstration de départ n'a pas été chronométrée sur un lab réel (les durées du tableau ci-dessous sont des ordres de grandeur) ; l'attribut `disableLoginForm` de `/api/frontend/settings` de Grafana 13.2 (lu par le contrôle) et le réglage GitLab *Disable password authentication for users with an SSO identity* (`disable_password_authentication_for_users_with_sso_identities`, API des réglages d'application, présent dans les versions récentes : vérifie dans la tienne) sont à confirmer.

### M24-E46 — Mini-projet : l'identité de MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, les points de contrôle de chaque étape, la préparation des démonstrations, le sort des promesses et la **grille de revue**. Les fichiers de référence sont ceux des exercices du module ; les nouveaux sont la fiche de livraison [`identite-v1.md`](fichiers/M24-E46/medisphere/docs/securite/identite/identite-v1.md), l'entrée de Thomas Leroy dans [`personnes.yml`](fichiers/M24-E46/identite/annuaire/personnes.extrait-E46.yml) et l'outil de preuves de départ [`preuves-depart.sh`](fichiers/M24-E46/identite/outils/preuves-depart.sh) (lecture seule).

**Solution**

*Plan de travail recommandé* (on prouve d'abord, on nettoie ensuite, on documente à la fin)

1. **État des lieux** (1 h) : `lab/bin/check 24 46`, `lab/bin/check 24 43` ; `tofu -chdir=tofu plan` (doit être vide) et `annuaire.yml --check --diff` (aucun changement) dans `plateforme/identite` ; `ls ~/.local/state/workbook/pannes-actives/` ; `pvesh get /cluster/resources --type vm` (ni 2241 ni 2242) ; revue des accès d'E30 lancée à la main (pipeline `REVUE_ESSAI=1`) : sa section « Écarts » est la liste des comptes locaux en trop.
2. **Comptes locaux** (2 h) : un tableau service par service (compte, type secours/service/personne, rangement, usage, alerte) ; tout compte de **personne** restant est supprimé ou désactivé ; GitLab : réglage *Disable password authentication for users with an SSO identity* (les personnes liées au SSO n'ont plus de mot de passe utilisable, `root` garde le sien) plutôt que `password_authentication_enabled_for_web: false`, qui fermerait aussi `root` (promesse de M24-E11 et du M01) ; Grafana `disable_login_form` (E12), Argo CD `admin.enabled: false` (E13), Harbor en `oidc_auth` (E14), `wb-admin@pve` désactivé (E15).
3. **Matrice des droits** (2 h) : pour chaque groupe et chaque service, une preuve. Cluster : `outils/matrice-droits-oidc.sh` (E17). Argo CD : `argocd admin settings rbac can … --policy-file` (E13). Grafana : rôle effectif d'une personne de chaque groupe (`/api/users/lookup`, en admin de secours, tracé). Harbor : appartenance des groupes OIDC aux projets. Proxmox : `pveum acl list`. VMs : `ipa hbactest` et `sudo -l -U`. Les écarts vont dans la revue (acceptés nommément ou corrigés).
4. **Démonstrations, répétition** (2 h) : voir plus bas ; faites **avant** le nettoyage final.
5. **Promesses** (1 h) : tableau ci-dessous, reporté dans `identite-v1.md`.
6. **Nettoyage** (30 min) : pannes closes, Thomas Leroy désactivé (pas supprimé), comptes de secours refermés, fichiers de jetons effacés.
7. **Documentation et livraison** (2 h) : `identite-v1.md`, matrice des flux, MR, pipelines verts, étiquette `identite-v1`.

*Démonstration de Sophie — Thomas Leroy part* (préparée par RB-241 la veille : personne en code, groupe `plateforme`, OTP non requis pour ce groupe ; Thomas s'est connecté à GitLab, Grafana, Argo CD, Harbor, a un jeton personnel GitLab, un certificat SSH, un `kubectl` par OIDC)

| T | Étape (RB-242) | Preuve |
|---|---|---|
| T0 | MR `etat: disabled` + retrait de `plateforme` dans `personnes.yml`/`groupes.yml` (préparée, relue), fusion, job `annuaire:appliquer` | job vert ; `ipa user-show thomas.leroy` : *Account disabled: True* |
| T0 + 3 min | Sessions Keycloak : `POST /admin/realms/medisphere/users/<ID>/logout` (avec ton compte d'administration, pas `wb-checks`) | `users/<ID>/sessions` vide |
| T0 + 5 min | Jetons GitLab révoqués (API, jeton d'administration), sessions Grafana fermées (`/api/admin/users/:id/logout`), utilisateur Harbor supprimé, jetons Proxmox/NetBox (aucun pour Thomas : le dire) | listes vides |
| T0 + 8 min | Preuves de refus : connexion SSO (`LOGIN_ERROR` dans Loki `audit`), `ssh thomas.leroy@mon01` avec son certificat **encore valable** → `pam_sss … Access denied` (compte verrouillé), `kubectl` après expiration du jeton d'accès (5 min) → le rafraîchissement échoue | lignes de journal, codes de retour |
| T0 + 10 min | Revue des accès relancée : Thomas n'apparaît plus qu'en « désactivé » | artefact du pipeline |
| T0 + 12 min | Rapport : `outils/preuves-depart.sh thomas.leroy` écrit le tableau (sans aucune valeur de jeton) | tableau collé dans `identite-v1.md` |

Ce qui **ne** se coupe **pas** en 15 minutes, et doit être dit : une session Grafana ou Argo CD déjà ouverte dans un navigateur, si elle n'a pas été fermée par l'API du service (aucun de nos services ne reçoit de déconnexion par canal arrière, M24-E44) ; le certificat SSH de Thomas reste **valable** jusqu'à 16 h, mais ne sert plus à rien (SSSD refuse le compte verrouillé à l'étape *account*) ; un jeton d'accès déjà émis vaut encore jusqu'à 5 minutes chez un service qui ne fait que vérifier la signature.

*Démonstration de Nadia — le SSO coupé* : CHG annoncé ; coupure volontaire annoncée selon RB-246 (§A) : `sudo systemctl stop keycloak` sur `idp01` (session `admin` ouverte) ; Grafana par le compte `admin` (Vault `critique`, API en authentification basique, formulaire fermé : l'entrée se fait par l'API ou par la réactivation temporaire décrite dans RB-240), cluster par `admin.conf` ; les alertes `KeycloakIndisponible` (2 min), sonde du témoin, `BrisDeGlaceCluster` et l'alerte Grafana arrivent ; comptes refermés (mot de passe de secours changé et rangé si le protocole de RB-240 le prévoit après usage) ; `systemctl start keycloak` ; contrôle `lab/bin/check 24 42` ; heures dans le journal. Questions à préparer : « Et si `idp01` est détruit ? » (RB-243 : restauration, ordre de grandeur mesuré en E25) ; « Qui a vu passer les ouvertures de secours ? » (Sophie, par l'alerte, avec l'heure).

*Arrivée par Karim* : il nomme une personne fictive ; MR sur `personnes.yml` et `groupes.yml`, approbation, `annuaire:appliquer`, synchronisation de la fédération (15 min, ou déclenchée), première connexion avec enrôlement OTP si le groupe l'exige, droits vérifiés par la matrice. Objectif : moins de 30 minutes jusqu'au premier accès réussi ; ce qui le ralentit (synchronisation périodique) est une donnée de RB-241.

*Promesses des modules précédents* (à reporter dans `identite-v1.md`)

| Promesse | Origine | Sort |
|---|---|---|
| SSO de GitLab, connexion par mot de passe réservée à `root` | M01-E31, M24-E11 | tenue (E11 + réglage de l'étape 2) |
| Comptes nominatifs Proxmox par le fournisseur, `root@pam` en secours, TOTP par l'IdP | M09 | tenue (E15, E21) |
| Hubble derrière OIDC | M15 | tenue (E18) |
| Grafana en SSO, équipes et dossiers par les groupes | M21 | tenue (E12) |
| Authentification devant Prometheus, Thanos Query, Alertmanager | M21-E29, ADR-0210 | **partielle** : Pyrra (E34) ; Thanos Query et Alertmanager reportés (accès par jeton à prévoir pour le témoin et le ruler de Loki) → « pour aller plus loin » d'E46, sinon M26 |
| `kubectl` par OIDC, fin des certificats personnels | M14 | tenue (E16, E17) |
| Certificats SSH nominatifs par OIDC, principaux de l'annuaire | M06 | tenue (E20) ; CA d'utilisateurs **sous HSM** : non tenue (pas de HSM dans le lab) → limite écrite, F6 |
| Tableau de bord de Ceph derrière le SSO | M08 | non tenue → `identite-v1.md`, M26 (OAuth2 Proxy devant le *mgmt-gateway*, ou OIDC natif du tableau de bord) |
| Fédération Keystone ↔ Keycloak | M10 | non tenue (OpenStack hors du profil de lab) → limite écrite |

*Grille de revue*

| Relecteur | Points | Attendu |
|---|---|---|
| Sophie | modèle d'autorisation, revue d'accès, comptes de secours, départ | matrice prouvée case par case ; revue mensuelle signée ; inventaire des comptes locaux sans compte de personne ; départ en moins de 15 min, avec ce qui reste ouvert écrit et borné |
| Karim | `plateforme/identite`, rôles Ansible | `tofu plan` vide, annuaire sans dérive, état chiffré ; aucune configuration à la main ; arrivée en moins de 30 min ; vérification de dérive planifiée (E40, E41) |
| Nadia | astreinte, secours | SSO coupé : entrée par RB-240, alertes reçues, comptes refermés ; RB-246 utilisable à 4 h du matin ; alertes du palier 4 chargées et testées |
| Julien | droits de son équipe | `mediagenda` : lecture en recette et production, écriture en `mediagenda-dev`, Argo CD de son projet, Grafana de son équipe, **pas** de SSH ; rien de plus |
| Claire | ensemble | limites assumées, promesses tenues ou reportées avec leur module ; ce que M25 et M26 consomment |

**Explications**

Le contrôle global vérifie l'**état de livraison** (clients propres, comptes locaux réduits, rien de provisoire, départ démontré, documentation, étiquette) et rejoue les contrôles qui cassent le plus souvent en silence ; il ne prouve pas qu'un humain peut entrer ou être mis dehors à temps : ce sont les démonstrations. Le départ est le vrai test d'une identité centralisée : il montre à la fois ce que la centralisation coupe d'un coup (tout ce qui repasse par l'annuaire ou Keycloak) et ce qu'elle ne coupe pas (ce qui a été délivré avant : sessions des services, jetons, certificats), qui doit être inventorié et borné.

**Alternatives**

Désactiver Thomas **dans Keycloak** plutôt que dans l'annuaire : plus rapide (pas de job), mais l'annuaire reste la source de vérité et SSSD ne voit pas Keycloak : SSH resterait ouvert. Démonstration de Nadia par une coupure de `be_sso` dans HAProxy plutôt qu'un arrêt de Keycloak : plus proche d'une panne de publication (M24-E42), mais elle touche les répartiteurs partagés ; l'arrêt de Keycloak est local et réversible.

**Pièges classiques**
- Supprimer Thomas au lieu de le désactiver : son identifiant redevient disponible et les journaux perdent leur sens (RB-242).
- Oublier les sessions **des services** dans le chronomètre et annoncer « coupé » à T0 + 3 min.
- Couper `password_authentication_enabled_for_web` dans GitLab : `root` ne peut plus entrer le jour où le SSO tombe.
- Laisser `kc-secours` ou `admin` de Grafana avec le mot de passe montré pendant la démonstration.
- Poser l'étiquette `identite-v1` avant que les pipelines de `main` soient verts.

**En production chez MédiSphère**

La livraison `identite-v1` devient la référence des changements d'identité (fiches `CHG-25xx`) ; le départ automatisé (job protégé) devient la seule procédure ; la démonstration de coupure du SSO devient un exercice trimestriel avec l'essai des comptes de secours (RB-240) ; tout nouveau service entre en production avec son client en code, sa ligne dans le modèle d'autorisation, sa source dans la revue d'accès, son compte de secours et sa durée de session dans RB-242, sinon il n'entre pas.
