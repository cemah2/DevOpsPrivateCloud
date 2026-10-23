# Phase 4 — AxiomDev, un prestataire aux accès bornés

Julien Petit a choisi AxiomDev pour développer, en trois mois, la gestion des listes d'attente de MédiAgenda. Marc Vidal (chef de projet) et Yanis Perrin (développeur) arrivent lundi. Sophie Laurent a un souvenir précis du départ d'InfoGér (M24 : trois semaines pour retrouver des accès, deux encore actifs un an plus tard) : cette fois, chaque accès est **borné dans le temps et dans le périmètre**, se lit en un endroit, s'audite chaque mois et disparaît le dernier jour sans que personne ait à s'en souvenir.

> **Rappels** : tout se lance depuis `adm01`. Pour **jouer** AxiomDev (essais de droits), utilise un contexte `kubelogin` et une fenêtre de navigation privée à part, avec les comptes de Marc et Yanis, comme pour le compte d'essai du M28-E15 ; jamais ton propre compte, qui voit tout. Les pannes de cette phase (S11) suivent les règles de la phase 2 : `lab/bin/check F2 11` vert avant l'injection (hors livrables), `--annuler` pour clore.

---

### F2-S10 — Des accès bornés pour AxiomDev  `LIBRE` `★★★★`

> **Ticket SEC-3210** — *De : Sophie Laurent* (demande de Julien Petit)
> AxiomDev commence lundi pour trois mois. Leur périmètre, signé dans le contrat : le code de `mediagenda/api` (branches de fonctionnalité, MR relues par Julien), un espace de développement pour faire tourner leur version, rien d'autre. Pas de production, pas de recette, pas de secrets, pas de SSH sur nos machines, second facteur obligatoire. Tout s'arrête seul à la fin du contrat. Et je veux pouvoir le prouver à l'auditeur HDS : la revue d'accès mensuelle doit savoir ce qu'ils ont **le droit** d'avoir.

**Objectifs pédagogiques**
- Étendre l'équipe en code à un tiers : identité datée, authentification forte, droits par groupe, hébergement dans le locataire d'une autre équipe.
- Borner un accès GitLab (utilisateur externe, appartenance directe à un projet, expiration, branches protégées) et un accès Kubernetes (rôle sur mesure, aucun droit de cluster).
- Vérifier des droits **du point de vue du prestataire**, et faire connaître son modèle à la revue d'accès.

**Prérequis** : S02 (équipe en code, champs « prestataire » du format) ; M24-E11 (synchronisation GitLab), E17 (RBAC par groupes), E19 (HBAC), E20 (certificats SSH), E21 (OTP conditionnel), E23 (arrivées, départs), E30 (revue d'accès) ; M28-E05 et E15 (locataires, isolation).
**Durée indicative** : 6 à 9 h.

**Contexte technique**
- Personnes : **`marc.vidal`** (responsable chez AxiomDev), **`yanis.perrin`** (développeur) ; adresses `@axiomdev.example`. Groupe de l'annuaire **`ext-axiomdev`** ; responsable interne : Julien Petit.
- Durée : trois mois à partir de ta date de début. Les checks attendent des expirations **dans le futur et à 100 jours au plus** (`WB_F2_EXPIRATION_MAX_JOURS`).
- Espace de travail : **`mediagenda-axiomdev`**, dans le **locataire `mediagenda`** (environnement de développement, sans donnée réelle). Les propriétaires d'un locataire ont `view` sur ses environnements (M28-E05).
- GitLab CE : un utilisateur **externe** ne voit que les projets dont il est membre et ne crée ni groupe ni projet ; une appartenance de projet peut porter une **date d'expiration** ; la synchronisation des groupes OIDC est réservée aux éditions payantes (M24-E11). Un Developer ne voit pas les variables CI du projet.
- FreeIPA : un principal Kerberos peut porter une **date d'expiration** (`krbPrincipalExpiration`), distincte de la désactivation du compte (`nsAccountLock`) ; à partir de FreeIPA 4.0, une liaison LDAP par mot de passe d'un principal expiré est refusée (Keycloak se connecte à l'annuaire par liaison LDAP).
- Revue d'accès : `plateforme/identite`, `outils/revue-acces/` (`modele.yml`, M24-E30) ; runbook à écrire : **RB-329** (`docs/accueil/runbooks/`).
- Accès réseau d'AxiomDev : depuis ses postes, par le VPN d'administration (un pair WireGuard par personne sur `wg1`, M00/M07) ; à toi de borner ce que ces adresses atteignent.

**Travail demandé**
1. **Décrire AxiomDev dans l'équipe en code** : personnes, dates, OTP, comptes GitLab externes, et ce que le format ne sait pas encore dire (hébergement dans le locataire `mediagenda`, rôle limité, accès direct à un projet). Étends le format **et** le générateur plutôt que d'écrire à la main dans un dépôt cible ; la relecture de Sophie est obligatoire pour les fichiers des prestataires.
2. **Identité** : principaux datés, OTP imposé au premier login, **aucune** règle HBAC (SSH refusé partout, vérifié avec `ipa hbactest`), aucun chemin OpenBao, aucun accès Argo CD.
3. **GitLab** : membres directs de `mediagenda/api` seulement (niveau Developer, date d'expiration), utilisateurs externes, aucun groupe GitLab de MédiSphère ; `main` de `mediagenda/api` protégée (poussée et fusion réservées aux Maintainers) ; leurs MR passent par Julien.
4. **Kubernetes** : l'espace `mediagenda-axiomdev` (quota serré, limites, Pod Security), un rôle sur mesure lié au seul groupe `oidc:ext-axiomdev` (ni Secrets, ni RBAC, ni `exec`, ni joker), aucune autre liaison ; prouver les droits avec le compte de Yanis (ce qu'il peut, ce qu'il ne peut pas, en particulier sur `mediagenda-prod` et `mediagenda-recette`).
5. **Réseau** : les pairs VPN d'AxiomDev n'atteignent que GitLab et le SSO (VIP `lb`) et l'API Kubernetes ; règle dans la matrice des flux.
6. **Revue et procédure** : le périmètre attendu d'AxiomDev dans `modele.yml` de la revue d'accès (et ce que la revue doit signaler) ; RB-329 « accueillir et faire partir un prestataire ».

**Contraintes**
- Rien à la main dans l'annuaire, Keycloak, GitLab ou le cluster : chaque droit vient d'un fichier relu.
- Aucun droit par héritage : ni groupe GitLab qui contient des projets de MédiSphère, ni groupe interne de l'annuaire, ni liaison de cluster.
- Une seule date de fin, déclarée une fois, qui se propage à tout ce qui sait expirer.

**Critères de réussite**
- [ ] `marc.vidal` et `yanis.perrin` sont dans `ext-axiomdev` et dans aucun autre groupe de l'annuaire ; leur principal expire dans le futur, à 100 jours au plus.
- [ ] Le groupe `ext-axiomdev` porte le rôle Keycloak `second-facteur-obligatoire` ; aucune règle HBAC active ne les admet (ni `allow_all`, ni règle à leur nom ou à leur groupe).
- [ ] Dans GitLab : utilisateurs externes, membres d'aucun groupe autre que le leur, Developer de `mediagenda/api` avec une date d'expiration ; `main` de `mediagenda/api` protégée (poussée et fusion Maintainer).
- [ ] `mediagenda-axiomdev` existe dans le locataire `mediagenda`, avec un quota ; `oidc:ext-axiomdev` y est lié à un rôle sans Secrets, RBAC ni joker ; aucune autre liaison RBAC (cluster ou espace) pour AxiomDev.
- [ ] OpenBao ne donne aucune politique à `ext-axiomdev` ; `modele.yml` de la revue d'accès décrit `ext-axiomdev` ; RB-329 publié.

**Vérification** : `lab/bin/check F2 10`

<details><summary>Indice 1</summary>

Le format de l'équipe en code connaît déjà `type: prestataire`, `expiration`, `otp_obligatoire` et `gitlab.externe` (S02). Ce qui manque est un **hébergement** : un espace dans un locataire qui n'est pas le sien, et des projets GitLab précis. Ajoute un bloc au schéma, un gabarit, une règle de validation, et un rendu pour la synchronisation GitLab.
</details>

<details><summary>Indice 2</summary>

`edit` est trop large pour un tiers : il lit les Secrets de l'espace et permet `exec`. Écris le rôle verbe par verbe. Pour vérifier : `kubectl auth can-i --list -n mediagenda-axiomdev --as=oidc:yanis.perrin --as-group=oidc:ext-axiomdev` (en administrateur), puis la même chose sur `mediagenda-prod`, puis pour de vrai avec le contexte de Yanis.
</details>

<details><summary>Indice 3</summary>

Côté GitLab, l'API des appartenances d'un utilisateur (`GET /users/:id/memberships`, administrateur) distingue les groupes (`Namespace`) et les projets (`Project`) : c'est elle que la revue d'accès et ton contrôle doivent lire. `expires_at` se pose à l'ajout d'un membre ou par sa mise à jour.
</details>

**Pour aller plus loin** (facultatif) : une alerte sept jours avant l'expiration d'un prestataire (règle sur une métrique exportée par la revue d'accès, ou tâche planifiée qui lit les fichiers d'équipe) envoyée à son responsable interne.

---

### F2-S11 — Panne : le prestataire voit trop de choses  `BF` `★★★`

> **Ticket SEC-3211** — *De : Sophie Laurent*
> *(Le détail s'affiche à l'injection : la revue d'accès montre qu'un compte d'AxiomDev voit des choses hors de son périmètre.)*

**Injection** : `lab/bin/break F2 11` (depuis `adm01` ; tire une cause au hasard parmi trois).
**Temps cible** : 45 min.

**Objectifs pédagogiques**
- Retrouver par où un droit est arrivé (groupe GitLab, liaison RBAC, appartenance dans l'annuaire) en partant du symptôme « il voit trop ».
- Retirer le droit par la bonne source, sans casser le périmètre légitime, et dater l'exposition (depuis quand, ce qui a pu être vu).
- Rendre la récidive impossible ou immédiatement visible (admission, revue d'accès).

**Prérequis** : S10 ; `lab/bin/check F2 11` vert avant l'injection, sauf les lignes qui portent sur tes livrables (politique d'admission, `modele.yml`).

**Contexte technique**
- La panne agit sur un seul des trois plans : GitLab (jeton d'administration `WB_GITLAB_ADMIN_TOKEN_FILE`), Kubernetes (`admin.conf` d'un nœud de contrôle, ou `WB_K8S_ADMIN_KUBECONFIG`), annuaire (`ipa01`). Elle ne touche ni la production, ni tes comptes, ni les données. Une dérive « à la main » est effacée par le prochain passage de l'outil qui gère la source… si cet outil gère cette source.
- Un jeton OIDC déjà délivré garde ses groupes jusqu'à son expiration ; une appartenance GitLab héritée ne se voit pas dans la liste des membres du projet.
- Journal de diagnostic : `docs/accueil/journal/AAAA-MM-JJ-F2-S11-<sujet>.md`.

**Travail demandé**
1. Diagnostique en partant de ce que Marc voit ; note chaque commande et ce qu'elle t'apprend dans le journal.
2. Retire l'accès en trop à sa source (et seulement lui) ; vérifie avec les comptes d'AxiomDev ; date l'exposition (journaux d'audit de GitLab, de l'API Kubernetes, de Keycloak) et liste ce qui a pu être vu.
3. Prévention : une politique d'admission qui refuse toute liaison RBAC d'un groupe `oidc:ext-*` hors de son espace (et toute liaison de cluster) ; la revue d'accès compare AxiomDev à son modèle ; RB-329 complété (§ « le prestataire voit trop »).
4. Réponds à Sophie dans le journal : cause, durée d'exposition, ce qui a été vu, ce qui empêche la récidive. Clos la panne (`--annuler`).

**Critères de réussite**
- [ ] Aucune personne d'AxiomDev n'est membre d'un groupe GitLab autre que le sien, ni d'un groupe de l'annuaire autre que `ext-axiomdev`.
- [ ] Aucune liaison RBAC d'AxiomDev hors de `mediagenda-axiomdev`.
- [ ] Une politique d'admission refuse les liaisons RBAC de `oidc:ext-*` hors des espaces prévus ; `modele.yml` décrit le périmètre d'AxiomDev.
- [ ] Journal publié ; la panne est close.

**Vérification** : `lab/bin/check F2 11` · Abandon : `lab/bin/break F2 11 --annuler`.

<details><summary>Indice 1</summary>

« Voir » dépend de l'outil : dans GitLab, l'héritage d'un groupe parent ; dans Kubernetes, une liaison (d'espace ou de cluster) vers un groupe ou une personne ; partout ailleurs (Argo CD, Grafana, Capsule, GitLab synchronisé), l'appartenance à un groupe de l'annuaire. Commence par lister ce que la personne **est**, avant ce qu'elle **peut**.
</details>

<details><summary>Indice 2</summary>

`GET /users/:id/memberships` ; `kubectl get clusterrolebindings,rolebindings -A -o json | jq '…subjects…'` ; `ipa user-show <identifiant>` (ligne *Member of groups*). Une appartenance à un groupe de l'annuaire se répercute sur Capsule, Argo CD, Grafana et, au prochain passage de la synchronisation, sur GitLab.
</details>

**Pour aller plus loin** (facultatif) : faire tourner la revue d'accès **chaque nuit** pour les seuls groupes `ext-*`, avec une alerte au premier écart.

---

### F2-S12 — Le départ d'AxiomDev  `LIBRE` `★★★`

> **Ticket SEC-3212** — *De : Julien Petit*
> AxiomDev a livré (merci Yanis !), la fonctionnalité est en recette. Le contrat se termine vendredi : on coupe tout proprement, et Sophie veut la preuve. Leur code reste chez nous, évidemment.

**Objectifs pédagogiques**
- Faire partir une équipe externe **par le code**, puis couper ce que le code ne voit pas (sessions, jetons, clés, certificats déjà émis).
- Produire une preuve de départ contrôlée par une autre personne.

**Prérequis** : S10, S11 (panne close) ; M24-E23 (RB-242), M24-E46 (preuves de départ).
**Durée indicative** : 2 à 3 h.

**Contexte technique**
- Ce qui ne disparaît pas avec la désactivation dans l'annuaire : sessions Keycloak et jetons de rafraîchissement, jetons personnels et clés SSH de GitLab, appartenances GitLab, certificats SSH déjà émis par step-ca (16 h, non révocables sans liste de révocation).
- L'espace `mediagenda-axiomdev` ne contient que la version de développement d'AxiomDev : il doit disparaître **par le code**. Les espaces des équipes internes, eux, sont protégés de l'élagage (S02) : décide et écris pourquoi celui-ci ne l'est pas.
- Preuve : **`docs/accueil/departs/axiomdev.md`**.

**Travail demandé**
1. Départ par l'équipe en code (une MR), relu par Sophie ; vérifie ce que la propagation a fait et pas fait.
2. Coupe le reste (sessions, jetons, clés, appartenances GitLab, pairs VPN) avec un outil versionné qui écrit des lignes de preuve sans secret ; comptes GitLab **bloqués**, jamais supprimés (leurs MR et commits restent attribués).
3. Retire le périmètre d'AxiomDev de la revue d'accès (le groupe reste déclaré, vide).
4. Rédige la preuve : périmètre avant et après, chronologie réelle, sortie de l'outil, contrôle final par une autre personne (Karim), ce qui reste et pourquoi.

**Critères de réussite**
- [ ] `marc.vidal` et `yanis.perrin` sont désactivés (`nsAccountLock`), pas supprimés, et dans aucun groupe ; `ext-axiomdev` est vide.
- [ ] Leurs comptes GitLab sont bloqués, sans jeton personnel actif ni clé SSH ; aucune session Keycloak ouverte.
- [ ] `mediagenda-axiomdev` n'existe plus ; aucune liaison RBAC ne vise AxiomDev.
- [ ] `docs/accueil/departs/axiomdev.md` publié (au moins quatre sections : annuaire, GitLab, Keycloak, SSH, espace).

**Vérification** : `lab/bin/check F2 12` (après le départ, `lab/bin/check F2 10` ne vérifie plus que l'absence de liaison).

<details><summary>Indice 1</summary>

Range les gestes en deux familles : ce que la propagation de l'équipe en code fait (annuaire, groupes, espace, rendus) et ce qui a été **délivré** avant (sessions, jetons, clés). RB-242 donne l'ordre pour une personne ; ici, c'est une équipe entière.
</details>

<details><summary>Indice 2</summary>

Keycloak : `POST /admin/realms/medisphere/users/{id}/logout` ; GitLab : `GET /personal_access_tokens?user_id=…&state=active` puis révocation, `GET /users/:id/keys`, `POST /users/:id/block`. Un utilisateur GitLab qui n'a jamais été créé (pas de première connexion) n'a rien à révoquer : dis-le dans la preuve.
</details>

**Pour aller plus loin** (facultatif) : déployer une liste de révocation de clés et certificats SSH (KRL produite par `ssh-keygen -k`, directive `RevokedKeys` de sshd, distribuée par Ansible) et mesurer ce qu'elle change au délai de coupure.
