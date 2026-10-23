# Module 24 — Palier 2 : Opérationnel

Le palier 1 a construit les fondations : l'annuaire FreeIPA de `ipa01` et sa CA subordonnée, les personnes et les groupes en code, Keycloak publié en `https://sso.par1.medisphere.internal`, le royaume `medisphere` fédéré à l'annuaire et repris dans OpenTofu, un flux OIDC déroulé à la main. Aucun service ne s'en sert encore. Ce palier traite les **tickets du quotidien** d'une équipe qui branche une identité centrale : écrire d'abord le **modèle d'autorisation** (qui a droit à quoi, par quel groupe), puis brancher en SSO un service après l'autre (GitLab, Grafana, Argo CD, Harbor, Proxmox VE, PBS, NetBox, le cluster par `kubectl`), mettre **OAuth2 Proxy** devant les interfaces qui ne savent pas le faire, inscrire les VMs dans l'annuaire (SSSD, HBAC, sudo), remplacer les clés SSH éternelles par des certificats de 16 h, imposer l'**OTP** aux administrateurs, relire la configuration d'un stagiaire et écrire les procédures d'arrivée et de départ. À chaque service, la même discipline : son compte de bris de glace essayé **avant**, le client OIDC en code, les droits par groupe, les comptes locaux des personnes retirés **après** le test.

> **Rappels du module** (introduction) : un accès de secours ouvert **et essayé** avant tout changement d'authentification, et une session d'administration déjà ouverte qu'on ne ferme pas pendant le changement ; aucun secret sur une ligne de commande (`ps`), dans Git en clair ou dans un compte rendu ; l'annuaire est la seule source des personnes et des groupes ; plus rien à la main dans le royaume `medisphere` : tout client OIDC, toute portée, tout flux est une MR de `plateforme/identite` (`tofu/`), appliquée par le job manuel protégé. Les VMs se configurent par Ansible (`plateforme/ansible`, clone `~/src/ansible`), le cluster par Helmfile (couche de base, `plateforme/k8s`) ou Argo CD (le reste), tout flux réseau par le rôle `pare_feu` (`group_vars/role_routeur/pare_feu.yml`) et `docs/socle/matrice-flux.md`.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Émetteur OIDC | `https://sso.par1.medisphere.internal/realms/medisphere` (découverte : `…/.well-known/openid-configuration`) ; Keycloak **26.7.5** jusqu'au M24-E33 ; tout client joint `sso` par la VIP `lb` 10.10.70.200:443 (un seul émetteur pour tous) |
| Revendication de groupes | `groups`, **noms courts** (`plateforme-admins`, jamais `/plateforme-admins`), portée par défaut `groupes` du royaume : présente dans l'ID token, le jeton d'accès et userinfo de tout client créé **après** E06 ; aucun client ne demande une portée nommée `groups` (elle n'existe pas) |
| Groupes | `plateforme-admins` (`<MOI>`, Karim), `plateforme` (`<MOI>`, Karim, Lucas), `mediagenda` (Julien), `medidoc` (vide), `securite` (Sophie), `support` (Nadia), `direction` (Claire) ; droits par service : `docs/securite/identite/modele-autorisation.md` (E10) |
| Clients OIDC (`tofu/clients-<service>.tf`) | confidentiels : `gitlab` (E11), `grafana` (E12), `argocd` (E13), `harbor` (E14), `proxmox`, `pbs`, `netbox` (E15), `oauth2-proxy` (E18) ; publics avec PKCE `S256` : `argocd-cli` (E13), `kubernetes` (E16) ; `step-ca` (E20 : confidentiel ou public, c'est à toi de le décider dans l'exercice). Pour tous : flux standard seul (ni implicite, ni *Direct Access Grants*), URI de redirection **exactes** (aucun joker), `full_scope_allowed = false`, PKCE `S256` exigé dès que le service sait le faire |
| Secrets des clients | générés par Keycloak à la création, rangés **sans être affichés** par `plateforme/identite/outils/ranger-secret-client.sh <client>` dans l'Ansible Vault `critique` **`secrets/identite.yml` de `plateforme/ansible`**, clé `keycloak_secrets_clients.<client>` (tiret du nom de client remplacé par `_` : `oauth2_proxy`) ; seule source pour les VMs (Ansible), les états OpenTofu (variables éphémères) et le cluster |
| Secrets dans le cluster | composant **`identite`** de `plateforme/k8s/outils/secrets-k8s.sh` (Vault lu dans `~/src/ansible/secrets/identite.yml`, E12) : `supervision/grafana-oidc` (E12), `argocd/argocd-oidc` (E13), `oauth2-proxy/oauth2-proxy-oidc` (E18) |
| Bris de glace (à essayer avant chaque bascule) | GitLab `root` ; Grafana `admin` (basique, API) ; Argo CD `admin` désactivé, réactivable par Helmfile, et `admin.conf` ; Harbor `admin` (local, reste permis en mode OIDC) ; Proxmox `root@pam`, PBS `root@pam` ; NetBox `admin` (formulaire local conservé) ; cluster `admin.conf` (Vault `critique`) ; VMs : compte local `admin` (clé SSH d'`adm01`) ; Keycloak `kc-secours` ; annuaire `admin` |
| Cluster (E16-E17) | `/etc/kubernetes/authentification/config.yaml` (`AuthenticationConfiguration` `apiserver.config.k8s.io/v1`, audience `kubernetes`, préfixes `oidc:`) posé par le rôle **`k8s_authentification`** (`playbooks/k8s-api-fichiers.yml`), option `--authentication-config` par `cluster/kubeadm-config.yaml` et `outils/reconfigurer-apiserver.sh` (M14-E27), **un nœud de contrôle à la fois** ; kubelogin 1.36 (`kubectl oidc-login`, krew) sur `adm01`, contexte **`k8s-par1-oidc`** (utilisateur `oidc`) ; RBAC `plateforme/k8s/rbac/oidc.yaml` (E17) ; ClusterRole agrégée `wb-checks-securite` (E16) |
| OAuth2 Proxy (E18) | 7.15.5, espace `oauth2-proxy`, releases `oauth2-proxy-hubble` et `oauth2-proxy-pyroscope` (Application Argo CD `oauth2-proxy`, chart recopié dans Harbor) ; `mon01` : unité `oauth2-proxy-mailpit.service`, écoute 8443 |
| VMs (E19-E20) | rôle `freeipa_client` ; règles HBAC `hbac-plateforme`, `hbac-support`, `allow_all` désactivée ; sudo `sudo-plateforme-admins`, `sudo-plateforme` ; provisioner OIDC `keycloak` de step-ca, certificats utilisateur de 16 h |
| MFA (E21) | flux `navigateur-medisphere` : OTP obligatoire pour `plateforme-admins` et `securite`, jamais pour `kc-secours` ni les comptes de service |
| Documentation | `docs/securite/identite/` de `plateforme/medisphere` : `modele-autorisation.md` (E10), `runbooks/RB-241-arrivee.md`, `RB-242-depart-mobilite.md` (E23) ; journaux de bascule et de diagnostic dans `docs/socle/journal/AAAA-MM-JJ-M24-EXX-<sujet>.md` (VMs comme cluster : un seul endroit pour tout le module) |
| Travail personnel | `~/m24/eXX/` sur `adm01` (non versionné, **sans secret**) ; navigateur sur ton poste par le VPN ; pour les CLI qui attendent une redirection sur `localhost` (kubelogin, `argocd login --sso`), un tunnel SSH depuis ton poste (`ssh -L 8000:127.0.0.1:8000 …`) |
| Vérifications | `lab/bin/check 24 XX` : API du royaume par `wb-checks`, GitLab, Grafana (compte de service Viewer), cluster (`wb-checks`), Harbor (robot), SSH en consultation sur `pve01`, `pbs01`, `nbx01` et les nœuds de contrôle |

> 💡 **Un service à la fois, toujours dans le même ordre.** (1) Essayer le compte de bris de glace du service et garder une session d'administration ouverte ; (2) MR dans `plateforme/identite` : le client OIDC ; (3) ranger son secret ; (4) configurer le service (son propre dépôt ou outil) ; (5) tester avec **deux** personnes de groupes différents (toi et `lucas.martin`) ; (6) seulement ensuite, retirer les comptes locaux des personnes ; (7) consigner la bascule (journal, matrice de flux). Les mots de passe des personnages autres que toi et Lucas n'ont jamais été posés (E03) : leurs droits se vérifient par la configuration et par les checks, pas en se connectant à leur place.

> ⚠️ **Mémoire.** Le palier n'ajoute aucune VM. Il redémarre les serveurs d'API du cluster un par un (E16) et ajoute quelques pods (OAuth2 Proxy, E18) : vérifie `free -g` sur `pve01` avant E16, et n'enchaîne pas E16 avec une autre opération sur le plan de contrôle.

Durée indicative du palier : 40 à 46 heures (somme des durées des exercices : 43 h). Ordre conseillé :

```
E10 (le modèle d'abord : chaque branchement l'applique)
 ├─ E11 ─ E12 ─ E13 ─ E14 ─ E15   (un service à la fois ; E14 avant de créer tout compte Harbor)
 ├─ E16 ─ E17                      (authentification, puis autorisation, du cluster)
 ├─ E18                            (après E12 : même chemin du secret vers le cluster)
 └─ E19 ─ E20                      (SSSD et HBAC avant les certificats SSH)
E21 après E11 à E20 (l'OTP touche toutes les connexions : tu en mesures l'effet partout)
E22 à tout moment après E13 ; E23 en dernier (il s'appuie sur tout ce qui a été branché)
```

---

### M24-E10 — Le modèle d'autorisation : groupes, rôles et services  `RED` `★★`

> **Ticket SEC-2510** — *De : Sophie Laurent* — *Copie : Claire Morel*
> Avant que vous branchiez dix services, je veux lire **une** page qui dit qui a droit à quoi, partout, et pourquoi. Pas une liste de personnes : des groupes de l'annuaire, et pour chaque service, ce que chaque groupe y fait. Ce qui reste en compte local doit y être aussi, avec sa raison et son propriétaire. C'est cette page que je montrerai à l'auditeur HDS, et c'est contre elle que la revue d'accès du palier 3 comparera la réalité.

**Objectifs pédagogiques**
- Concevoir un modèle d'autorisation par groupes (RBAC) commun à des services hétérogènes, à partir de leurs rôles natifs.
- Appliquer le moindre privilège, la séparation des tâches, l'imputabilité (comptes nominatifs) et le bris de glace.
- Distinguer ce que le SSO résout de ce qui reste local (automatisation, secours, limites des éditions gratuites), et l'écrire.

**Prérequis** : M24-E03 (groupes), M24-E09 ; M14-E06 (RBAC du cluster), M20-E24 (RBAC d'Argo CD), M21-E17 (équipes de Grafana), M22-E16 (organisation « Sécurité »), M13-E03 (comptes et robots de Harbor).
**Durée indicative** : 3 h.

**Contexte technique**
- Rôles natifs à connaître (lis la documentation de chacun) : GitLab (Guest, Reporter, Developer, Maintainer, Owner, par groupe) ; Grafana (Viewer, Editor, Admin par organisation, *Grafana Admin* du serveur) ; Argo CD (`role:admin`, `role:readonly` intégrés, rôles de `policy.csv` du M20-E24 : `role:plateforme-admin`, `role:mediagenda-equipe`, `role:lecture`, rôles de projet `equipe`) ; Harbor (administrateur système, et par projet : `projectadmin`, `maintainer`, `developer`, `guest`, `limitedguest`) ; Proxmox VE (rôles `PVEAdmin`, `PVEAuditor`… sur des chemins `/`, `/pool/lab`) ; PBS (`Admin`, `Audit`, `DatastoreAudit`…) ; NetBox (permissions d'objets par groupe local) ; Kubernetes (ClusterRoles `cluster-admin`, `view`, `edit`, et celles du lab) ; les VMs (HBAC, sudo) ; les interfaces derrière OAuth2 Proxy (un groupe autorisé, sans rôle).
- Limites des éditions : GitLab CE ne synchronise pas les groupes OIDC (Premium) ; Grafana OSS n'a pas de *team sync* (Enterprise) ; PBS et NetBox ne reçoivent pas les groupes par le flux OIDC (voir `annexes/versions-bloc-F.md`).
- Comptes non humains existants : jetons et robots des checks (`wb-checks` partout), `ci-lecture` (Argo CD), robots de Harbor, `svc-automatisation` (NetBox), comptes `wb-*@pve` et leurs jetons, comptes de service Kubernetes, `svc-tofu-keycloak`, `svc-keycloak`.

**Livrable** : `docs/securite/identite/modele-autorisation.md` dans `plateforme/medisphere`, par MR relue par Sophie (étiquette `securite`).

**Contraintes**
1. **Principes** en tête, cinq au plus, chacun avec sa conséquence concrète (par exemple : « personne n'a de droit à titre individuel → aucun nom propre dans une politique »).
2. Une **matrice groupes × services** : en ligne les sept groupes, en colonne les services du lab (GitLab, Grafana, Argo CD, Harbor, Proxmox VE, PBS, NetBox, cluster Kubernetes, VMs du socle par SSH et sudo, interfaces derrière OAuth2 Proxy, OpenBao au M25) ; dans chaque case, le **rôle natif** et sa portée (groupe GitLab, organisation, projet, chemin, espace…), ou « — ».
3. Pour chaque service : **comment** le groupe arrive jusqu'au droit (revendication `groups` lue par le service, synchronisation par script, affectation manuelle), et où cela s'écrit (fichier, dépôt).
4. Une section **séparation des tâches** : au moins trois paires de droits que personne ne doit cumuler, ou alors sous condition (par exemple : approuver sa propre MR qui change un droit ; administrer Keycloak et l'annuaire avec le même compte ; déployer en production et changer la politique d'admission).
5. Une section **comptes qui restent locaux** : tableau compte, service, raison, propriétaire, protection (où est le secret, rotation, alerte à l'usage). Les comptes de bris de glace y figurent tous.
6. Une section **écarts et décisions** : ce que le modèle ne peut pas faire dans nos versions, et ce qu'on fait à la place.
7. Le cas de Lucas, stagiaire du groupe `plateforme`, doit être lisible en une ligne : ce qu'il peut faire, ce qu'il ne peut pas faire, et pourquoi.

**Critères de réussite**
- [ ] La matrice couvre les sept groupes et tous les services listés ; aucune case ne cite une personne.
- [ ] Chaque droit d'écriture en production est justifié ; `direction` n'écrit nulle part.
- [ ] Chaque compte local restant a une raison, un propriétaire et une protection.
- [ ] Les limites des éditions gratuites (GitLab, Grafana, PBS, NetBox) sont nommées avec leur contournement.
- [ ] Le document est sur `main` de `plateforme/medisphere`, relu en MR.

Exercice auto-évalué : relis ton document avec la grille du corrigé. Il sert de référence aux exercices E11 à E21 : si un branchement s'en écarte, c'est le document **ou** le branchement qu'on corrige, par MR.

<details><summary>Indice 1</summary>

Pars des rôles que chaque service sait déjà faire, pas d'une liste de souhaits : un rôle qu'aucun service ne connaît devra être fabriqué (politique Argo CD, ClusterRole, permission NetBox), et c'est du code à maintenir. Puis demande-toi pour chaque groupe : quelle est la **plus petite** chose dont il a besoin pour travailler un lundi normal ?
</details>

<details><summary>Indice 2</summary>

La séparation des tâches ne se règle pas toujours par un rôle : une règle d'approbation de MR, une revue par une autre personne, une alerte à l'usage d'un compte font aussi l'affaire. Écris le mécanisme, pas seulement l'intention.
</details>

**Pour aller plus loin** (facultatif) : compare ce modèle par groupes à un modèle par attributs (ABAC : rôle **et** environnement **et** horaire d'astreinte) et dis ce qu'il apporterait à l'accès à la production. [NIST SP 800-162 (ABAC)](https://csrc.nist.gov/pubs/sp/800/162/upd2/final) · [OWASP : *Authorization Cheat Sheet*](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)

---

### M24-E11 — SSO de GitLab  `LAB` `★★`

> **Ticket PLAT-2511** — *De : Karim Benali*
> GitLab d'abord : c'est par lui que tout passe. Connexion par Keycloak, et les comptes qui existent déjà doivent être **rattachés**, pas doublés : Julien ne doit pas se retrouver avec un `julien.petit2` sans ses projets. On est en CE, donc pas de groupes OIDC : les appartenances aux groupes GitLab suivront l'annuaire par un petit outil à nous, planifié, qui ne touche **que** aux personnes déclarées. Le mot de passe local reste possible pour l'instant (on le coupera au mini-projet) ; `root` reste le bris de glace.

**Objectifs pédagogiques**
- Déclarer un client OIDC confidentiel en code et en ranger le secret sans l'afficher.
- Configurer OmniAuth `openid_connect` dans `gitlab.rb` (découverte, PKCE, identifiant stable, liaison des comptes existants).
- Synchroniser des appartenances de groupes depuis l'annuaire par l'API, de façon idempotente et bornée, faute de synchronisation de groupes dans l'édition gratuite.

**Prérequis** : M24-E10 ; M24-E08 (pipeline de `plateforme/identite`) ; M01-E31 (durcissement de GitLab, `trusted-certs`).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Client Keycloak | `gitlab`, confidentiel, redirection `https://git01.par1.medisphere.internal/users/auth/openid_connect/callback`, PKCE `S256` |
| `gitlab.rb` | géré à la main sur `git01` depuis le M01 : copie datée avant modification, `gitlab-ctl reconfigure` ; libellé du bouton « SSO MédiSphère » |
| Racine de confiance | GitLab n'utilise que son propre magasin : `/etc/gitlab/trusted-certs/` (M01) |
| Outil de rangement | `outils/ranger-secret-client.sh <client>` de `plateforme/identite` (à écrire ici, resservira à chaque client) : lit le secret par l'API d'administration avec `svc-tofu-keycloak`, l'écrit dans `~/src/ansible/secrets/identite.yml` (Vault `critique`), n'affiche rien |
| Synchronisation | `outils/synchro-gitlab.py` (uv, `requests`, `pyyaml`) et sa table `outils/synchro-gitlab.yml` (groupe de l'annuaire → groupe GitLab → niveau) ; lit `annuaire/personnes.yml` et `annuaire/groupes.yml` ; compte GitLab **`svc-synchro-identite`** (membre des groupes `plateforme`, `mediagenda`, `medidoc` au rôle que tu détermineras à l'étape 7, jeton personnel `api` à expiration, variable protégée et masquée `GITLAB_SYNCHRO_JETON`) ; pipeline planifié **toutes les heures** sur `main` |

**Travail demandé**

*A. Préparer*

1. Lis la page *OpenID Connect OmniAuth provider* de GitLab : `discovery`, `uid_field`, `pkce`, `client_options`, et la page *OmniAuth* : `omniauth_allow_single_sign_on`, `omniauth_block_auto_created_users`, `omniauth_auto_link_user`. Note dans `~/m24/e11/notes.md` ce que fait chacune, et pourquoi `uid_field` ne doit pas être une valeur qu'on peut renommer.
   > ⚠️ **Attention** : avant de toucher à `gitlab.rb`, connecte-toi en `root` dans une fenêtre privée et **garde cette session ouverte** jusqu'à la fin de l'étape C. Retour arrière : la copie datée de `gitlab.rb` et `gitlab-ctl reconfigure`.
2. Vérifie que GitLab fait confiance à la racine MédiSphère pour joindre `sso` :
   ```
   admin@git01:~$ sudo ls /etc/gitlab/trusted-certs/
   admin@git01:~$ sudo /opt/gitlab/embedded/bin/curl -s -o /dev/null -w '%{http_code}\n' \
   >   https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration
   ```

*B. Le client et son secret*

3. Écris `tofu/clients-gitlab.tf` : le client selon le contexte technique et les règles des faits communs. MR, plan relu, apply par le pipeline.
4. Écris `outils/ranger-secret-client.sh` : il charge `~/.config/workbook/keycloak-tofu.env` (600), obtient un jeton de `svc-tofu-keycloak`, trouve l'identifiant interne du client, lit son secret (`GET …/clients/<id>/client-secret`), et l'écrit dans le Vault `secrets/identite.yml` de `~/src/ansible` sous `keycloak_secrets_clients.<client>`, en recréant le fichier chiffré sans jamais écrire le secret en clair sur disque ni dans une ligne de commande. Une option `--verifier` compare, par empreinte, le secret de Keycloak et celui du Vault. Puis :
   ```
   admin@adm01:~/src/identite$ outils/ranger-secret-client.sh gitlab
   admin@adm01:~/src/identite$ outils/ranger-secret-client.sh --verifier gitlab
   ```
   MR dans `plateforme/ansible` pour `secrets/identite.yml` (fichier chiffré : vérifie l'en-tête avant de pousser).

*C. GitLab*

5. Copie datée de `gitlab.rb`, puis ajoute le fournisseur `openid_connect` (secret recopié depuis le Vault par un éditeur, `sudoedit`, jamais par `echo`). `gitlab-ctl reconfigure`. Déconnecte-toi de ta session personnelle (pas de `root`), et connecte-toi par le bouton « SSO MédiSphère » en `<MOI>`. Arrives-tu sur **ton** compte (tes projets, ton statut d'administrateur) ? Dans *Edit profile* → *Account* → *Service sign-in*, que vois-tu ?
6. Fenêtre privée : `lucas.martin` par le SSO. Puis, en `root`, *Admin* → *Users* : combien de comptes `lucas.martin*` existe-t-il ? Quelle identité est liée ?

*D. Les groupes*

7. Lis la page *Roles and permissions* de GitLab (section *Group user management*) : quel rôle faut-il dans un groupe pour en gérer les membres ? Crée le compte `svc-synchro-identite` (en `root`, sans mot de passe utilisable), donne-lui ce rôle dans les trois groupes de premier niveau, son jeton `api` avec expiration, et la variable de CI protégée et masquée. Ce rôle permet bien plus que gérer des membres : quelles bornes l'outil doit-il **s'imposer** lui-même, et qu'est-ce qui contrôle qu'il les respecte ?
8. Écris `outils/synchro-gitlab.yml` à partir du modèle d'E10, puis `outils/synchro-gitlab.py`. Exigences :
   - par défaut il **affiche** les écarts sans rien changer ; `--appliquer` les corrige ;
   - il ne touche qu'aux **membres directs** des groupes cités, et seulement aux personnes de `personnes.yml` (jamais `root`, les comptes `svc-*`, les robots) ; une personne `disabled` perd ses appartenances ;
   - il ne rétrograde ni ne retire un **Owner** (il le signale) ; il signale, sans erreur, une personne qui n'existe pas encore dans GitLab ;
   - si une personne est dans plusieurs groupes de l'annuaire menant au même groupe GitLab, le niveau le plus élevé l'emporte ;
   - le jeton ne s'affiche jamais ; code de sortie non nul en cas d'erreur d'API.
   ```
   admin@adm01:~/src/identite$ ( . ~/.config/workbook/gitlab-synchro.env; uv run outils/synchro-gitlab.py )
   ```
9. Ajoute au `.gitlab-ci.yml` un job `synchro:gitlab` : aperçu sur les MR qui touchent `annuaire/` ou `outils/synchro-*`, application sur un pipeline **planifié** de `main` (variable de planification `SYNCHRO=gitlab`) ou à la demande. Crée la planification horaire. Lance-la et lis son journal.
10. Essaie : retire Lucas du groupe `plateforme` dans `groupes.yml` sur une branche, ouvre la MR : que montre l'aperçu ? Ferme la MR sans fusionner.

**Critères de réussite**
- [ ] Le client `gitlab` est confidentiel, en flux standard seul, avec une seule redirection exacte, PKCE `S256` et la portée `groupes` ; il est dans `tofu/clients-gitlab.tf` sur `main`.
- [ ] La page de connexion de GitLab propose « SSO MédiSphère » ; ta connexion par le SSO arrive sur ton compte existant, sans doublon.
- [ ] `outils/synchro-gitlab.py` est sur `main` ; le dernier pipeline **planifié** de `plateforme/identite` a réussi.
- [ ] Les membres directs des groupes GitLab correspondent à la table : Lucas est Developer de `plateforme` et absent de `mediagenda` ; Julien n'est pas membre de `plateforme`.
- [ ] `secrets/identite.yml` de `plateforme/ansible` est chiffré (identité `critique`) et contient le secret de `gitlab` (le contrôle `--verifier` passe).

**Vérification** : `lab/bin/check 24 11`

<details><summary>Indice 1</summary>

L'identité qui ne change jamais, chez Keycloak, est `sub` (l'identifiant interne de la personne, stable grâce à `ipaUniqueID`). Le rattachement d'un compte existant se fait par l'adresse de courriel : regarde ce qu'en dit la documentation d'`omniauth_auto_link_user`, et demande-toi pourquoi c'est acceptable **chez nous** (qui écrit les adresses ?) et dangereux ailleurs.
</details>

<details><summary>Indice 2</summary>

Pour le Vault : `ansible-vault view` sur la sortie standard, `yq` (mikefarah) qui pose la clé à partir d'une **variable d'environnement** (`strenv(…)`), et `ansible-vault encrypt` qui lit l'entrée standard et écrit dans un fichier temporaire, renommé ensuite. Pour l'API GitLab : les niveaux sont des entiers (Reporter 20, Developer 30, Maintainer 40, Owner 50), et `GET /groups/:id/members` ne renvoie que les membres directs.
</details>

<details><summary>Indice 3</summary>

Les variables de planification d'un pipeline se lisent comme les autres dans `rules:` (`$CI_PIPELINE_SOURCE == "schedule" && $SYNCHRO == "gitlab"`). L'aperçu sur une MR a besoin du jeton : il n'est disponible que sur les MR issues d'une branche protégée, comme pour le plan d'OpenTofu (E08).
</details>

**Pour aller plus loin** (facultatif) : liste ce que la synchronisation **ne** fait pas (bloquer le compte d'une personne partie, révoquer ses jetons personnels et ses clés SSH) et esquisse ce qu'il faudrait pour le faire sans donner l'administration de GitLab à l'outil ; tu y reviendras en E23. [GitLab : *OpenID Connect OmniAuth provider*](https://docs.gitlab.com/administration/auth/oidc/) · [*OmniAuth*](https://docs.gitlab.com/integration/omniauth/) · [API *Group and project members*](https://docs.gitlab.com/api/members/)

---

### M24-E12 — SSO de Grafana : rôles, organisations et équipes  `LAB` `★★`

> **Ticket DEV-2512** — *De : Nadia Roussel* — *Copie : Julien Petit, Sophie Laurent*
> Chaque matin, quelqu'un me demande de lui recréer son mot de passe Grafana. Je veux me connecter avec mon compte de tous les jours, et que les droits suivent les groupes : l'équipe Plateforme et le support éditent, les autres consultent, et Sophie retrouve son organisation « Sécurité » sans qu'on la lui ajoute à la main. Les équipes (pour les dossiers) restent celles du M21. Quand ce sera prouvé, plus de formulaire de connexion locale.

**Objectifs pédagogiques**
- Configurer `generic_oauth` de Grafana avec PKCE, une autorité de confiance montée dans le pod et un secret venu d'un Secret Kubernetes.
- Déduire le rôle par `role_attribute_path` (JMESPath) et les organisations par `org_mapping`, et comprendre `role_attribute_strict`.
- Faire coexister la synchronisation des rôles à la connexion et la gestion en code (OpenTofu) des équipes et des organisations, sans dérive.

**Prérequis** : M24-E11 ; M21-E17 (équipes et dossiers en OpenTofu), M21-E29 (réglages de sécurité, politiques réseau de `supervision`), M22-E16 (organisation « Sécurité »).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Client Keycloak | `grafana`, confidentiel, redirection `https://grafana.apps.par1.medisphere.internal/login/generic_oauth`, retour après déconnexion `https://grafana.apps.par1.medisphere.internal/login`, PKCE `S256` |
| Grafana | 13.2, sous-chart de `kube-prometheus-stack` (`plateforme/observabilite`, `kps/values.yaml`), espace `supervision` ; racine MédiSphère dans la ConfigMap `racine-medisphere` (clé `ca.crt`, M21-E06) |
| Secret | `supervision/grafana-oidc`, clé `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET`, créé par `secrets-k8s.sh appliquer identite` ; chargé par `grafana.envFromSecret` |
| Rôles voulus | `plateforme-admins` → *Grafana Admin* (serveur) et Admin de l'organisation principale ; `plateforme`, `support` → Editor ; tout autre membre de l'un des sept groupes → Viewer ; organisation « Sécurité » : `securite` Editor, `plateforme-admins`, `support`, `direction` Viewer |
| Équipes | `plateforme`, `mediagenda`, `medidoc` : OpenTofu, état `observabilite-grafana` de `plateforme/infra` (M21-E17), membres par adresse de courriel |
| Flux | Grafana (pod de `supervision`) → VIP 10.10.70.200:443 : la politique `refus-par-defaut-sortie` de M21-E29 le refuse aujourd'hui |

**Travail demandé**

1. Lis la documentation *Configure generic OAuth2 authentication* (et la page *Keycloak*) de Grafana 13 : `role_attribute_path`, `role_attribute_strict`, `allow_assign_grafana_admin`, `org_attribute_path`, `org_mapping`, `skip_org_role_sync`, `use_pkce`, `use_refresh_token`, `tls_client_ca`, `login_attribute_path`, `signout_redirect_url`, et `oauth_allow_insecure_email_lookup`. Dans `~/m24/e12/notes.md` : que se passe-t-il pour un compte **local** de même adresse à la première connexion par le SSO ?
   > ⚠️ **Attention** : avant la bascule, essaie le compte de bris de glace `admin` par l'API (mot de passe lu dans le Vault, passé par `-K <(…)`, jamais par `-u`), et garde une session `<MOI>` locale ouverte dans un onglet. Retour arrière : revenir sur le commit de `kps/values.yaml` (Argo CD resynchronise), le formulaire local revient.
2. `tofu/clients-grafana.tf`, MR, apply ; `outils/ranger-secret-client.sh grafana`, MR dans `plateforme/ansible`.
3. Le chemin du secret vers le cluster. `secrets-k8s.sh` lit le Vault d'un composant dans `secrets/<composant>.yml` de `plateforme/k8s` ; le Vault des clients est dans `plateforme/ansible`. Modifie le script pour qu'un composant dont le Vault n'existe pas dans `plateforme/k8s` soit lu dans `$MS_ANSIBLE_DIR/secrets/` (une seule source, pas de copie), ajoute la ligne du Secret `grafana-oidc` à `outils/secrets-k8s.conf`, puis :
   ```
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer identite && outils/secrets-k8s.sh verifier identite
   ```
4. Dans `plateforme/observabilite` : une politique `grafana-sortie` (vers la VIP 443 seulement) dans `reseau/espace-supervision.yaml`, puis dans `kps/values.yaml` : `grafana.ini` (`server.root_url` existe déjà, `auth.generic_oauth` complet, `auth.oauth_auto_login` faux), `envFromSecret`, et le montage de `racine-medisphere`. Garde `disable_login_form` à faux pour l'instant. MR, synchronisation par Argo CD.
5. Teste : `<MOI>` par le SSO (quel rôle, et es-tu *Grafana Admin* ?), puis `lucas.martin` dans une fenêtre privée (rôle ? peut-il créer un tableau ? voit-il l'organisation « Sécurité » ?). Que dit le journal de Grafana pour la connexion de Lucas (`kubectl -n supervision logs deploy/kps-grafana -c grafana | grep -i oauth`) ?
6. Les comptes. Liste les comptes locaux (API d'administration, en `admin`) : lesquels sont des personnes ? Supprime-les **sauf le tien**, que tu supprimes en dernier après t'être reconnecté par le SSO depuis une autre fenêtre. Que deviennent leurs tableaux et leurs jetons ?
7. Les équipes et l'organisation dans `observabilite-grafana` : la synchronisation de `org_mapping` réécrit les membres de l'organisation « Sécurité » à chaque connexion ; OpenTofu doit cesser de les gérer. Les équipes restent en code, mais un membre qui ne s'est **jamais** connecté n'existe pas dans Grafana et ferait échouer l'apply : filtre les membres déclarés par les utilisateurs existants (source de données `grafana_users`, qui exige l'authentification basique du fournisseur `admin_serveur` de M22-E16). Plan, MR, apply.
8. Quand toi et Lucas êtes entrés par le SSO, passe `disable_login_form` à vrai. MR, synchronisation, et vérifie que l'API reste joignable en `admin` (bris de glace).

**Critères de réussite**
- [ ] Le client `grafana` est confidentiel, en flux standard seul, redirection exacte, PKCE `S256`, portée `groupes`.
- [ ] Le Secret `grafana-oidc` existe, identique au Vault (`secrets-k8s.sh verifier identite`) ; le déploiement de Grafana le charge ; aucune valeur secrète dans `kps/values.yaml`.
- [ ] Grafana annonce le fournisseur `generic_oauth` et n'affiche plus le formulaire local ; la politique `grafana-sortie` n'ouvre que la VIP 443.
- [ ] `<MOI>` est *Grafana Admin*, Lucas Editor, et le plan d'`observabilite-grafana` est vide après tes connexions.
- [ ] Plus aucun compte local de personne ; `admin` répond encore par l'API.

**Vérification** : `lab/bin/check 24 12`

<details><summary>Indice 1</summary>

`role_attribute_path` est une expression JMESPath évaluée sur l'ID token puis userinfo : `contains(groups[*], 'plateforme-admins') && 'GrafanaAdmin' || …`. Avec `role_attribute_strict = true`, une expression qui ne donne rien (revendication absente) **refuse** la connexion au lieu de donner Viewer : c'est ce qu'on veut si la portée `groupes` disparaît un jour. Mais Grafana ne refuse que si **aucune** entrée d'`org_mapping` ne donne de rôle non plus : une entrée joker (`*:1:Viewer`) en donnerait un à tout le monde et annulerait le garde-fou. Dès qu'`org_mapping` est défini, une personne n'entre que dans les organisations qu'il lui donne : nomme l'organisation principale (`1`) pour chacun des sept groupes.
</details>

<details><summary>Indice 2</summary>

Le sous-chart Grafana accepte `envFromSecret` (le nom d'un Secret dont chaque clé devient une variable d'environnement) et `extraConfigmapMounts`. Une variable `GF_<SECTION>_<CLÉ>` remplace la clé correspondante de `grafana.ini` : le secret ne passe jamais par les valeurs du chart.
</details>

<details><summary>Indice 3</summary>

Pour qu'OpenTofu ne lutte pas contre la synchronisation de Grafana : `lifecycle { ignore_changes = [...] }` sur ce qu'il ne doit plus gérer. Pour les équipes, une expression `for … if contains(…)` sur la liste des adresses connues.
</details>

**Pour aller plus loin** (facultatif) : essaie `org_mapping` sur un groupe que tu retires à Lucas dans l'annuaire : combien de temps garde-t-il son rôle dans Grafana, et qu'est-ce qui le lui retire (sa prochaine connexion, l'expiration de sa session) ? [Grafana : *Generic OAuth*](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/) · [*Keycloak OAuth2*](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/keycloak/)

---

### M24-E13 — SSO d'Argo CD et fin des comptes locaux  `LAB` `★★`

> **Ticket SEC-2513** — *De : Sophie Laurent*
> Argo CD peut écrire partout dans le cluster et il a encore quatre comptes locaux à mots de passe. Je veux le SSO, l'interface et la CLI, les droits du M20 attribués aux **groupes** de l'annuaire, et la disparition des comptes de personnes. `ci-lecture` reste (c'est un jeton de vérification), `admin` reste désactivé. Et les tests de la politique RBAC doivent continuer à passer en CI.

**Objectifs pédagogiques**
- Configurer l'OIDC natif d'Argo CD (sans Dex) avec un client confidentiel pour l'interface et un client public PKCE pour la CLI.
- Passer une politique RBAC Casbin de comptes nominatifs à des groupes, sans perdre ses tests ni ses garde-fous.
- Retirer des comptes locaux en gardant un chemin de bris de glace documenté.

**Prérequis** : M24-E12 (chemin des secrets vers le cluster) ; M20-E24 (politique et tests), M20-E25 (durcissement, politiques réseau d'`argocd`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Clients Keycloak | `argocd` : confidentiel, redirection `https://argocd.apps.par1.medisphere.internal/auth/callback`, retour après déconnexion `https://argocd.apps.par1.medisphere.internal/` ; `argocd-cli` : **public**, PKCE `S256`, redirection `http://localhost:8085/auth/callback` |
| Release | `argocd` de `plateforme/k8s` (Helmfile, M20) : `releases/argocd.yaml.gotmpl`, `composants/argocd/values*.yaml`, `releases/argocd/policy.csv` et `rbac-tests.txt` |
| Secret | `argocd/argocd-oidc`, clé `clientSecret`, **étiquette `app.kubernetes.io/part-of: argocd`** (sans elle, Argo CD ne résout pas la référence `$argocd-oidc:clientSecret`) |
| Correspondance voulue | `plateforme-admins` → `role:plateforme-admin` ; `plateforme`, `support`, `securite` → `role:lecture` ; `mediagenda` → `role:mediagenda-equipe` ; `medidoc` → rôle de projet `medidoc/equipe` (AppProject de `plateforme/gitops`) |
| Comptes locaux | supprimés : `<MOI-ARGO>`, `karim-benali`, `julien-petit`, `nadia-roussel` ; conservés : `ci-lecture` (`apiKey`), `admin` (désactivé) |

**Travail demandé**

1. Lis la page *Keycloak* du manuel d'Argo CD 3.5 et la description d'`oidc.config` dans `argocd-cm.yaml` (dépôt amont, étiquette `v3.5.5`) : `clientSecret` par référence, `cliClientID`, `requestedScopes` (et sa valeur **par défaut**), `rootCA`, `logoutURL`, `enablePKCEAuthentication`. Pourquoi ne pas activer `enablePKCEAuthentication` avec un client `argocd` confidentiel ? Pourquoi la CLI a-t-elle son propre client ?
   > ⚠️ **Attention** : `admin` est désactivé et tu vas supprimer les comptes locaux. Avant de commencer : vérifie que ton identité de secours au cluster fonctionne (`kubectl --context k8s-par1 auth whoami` avec le certificat du M14 encore valable au moins un jour, ou `admin.conf` du Vault) et relis la procédure de réactivation d'`admin` du M20-E03 : c'est le bris de glace d'Argo CD. Garde une session `<MOI-ARGO>` ouverte dans un onglet jusqu'à l'étape 6.
2. `tofu/clients-argocd.tf` (les deux clients), MR, apply ; `ranger-secret-client.sh argocd` (le client public n'a pas de secret).
3. Le Secret `argocd-oidc` : la table de `secrets-k8s.sh` ne sait pas poser d'étiquette. Écris le module `outils/secrets-k8s.d/identite.sh` (fonctions `secrets_identite_appliquer` et `secrets_identite_verifier`, sur le modèle de `secrets-k8s.d/argocd.sh`). Applique et vérifie.
4. Ouvre le flux d'`argocd-server` vers `sso.par1.medisphere.internal:443` dans `composants/reseau/politiques/argocd.yaml`. Puis la configuration OIDC dans la release : la racine MédiSphère vient du fichier déjà lu par le gabarit (`composants/argocd/medisphere-root-ca.crt`). `helmfile -e par1 -l composant=argocd diff`, MR, `apply`.
5. Teste l'interface en `<MOI>` (bouton « LOG IN VIA SSO MÉDISPHÈRE »), puis en `lucas.martin` (que voit-il ?). Teste la CLI depuis `adm01` avec un tunnel depuis ton poste :
   ```
   toi@poste:~$ ssh -L 8085:127.0.0.1:8085 admin@adm01.par1.medisphere.internal
   admin@adm01:~$ argocd login argocd.apps.par1.medisphere.internal --grpc-web --sso --sso-launch-browser=false
   admin@adm01:~$ argocd account get-user-info
   ```
6. La politique : remplace dans `policy.csv` les lignes `g, <compte>, <rôle>` des personnes par des lignes de **groupes** selon le contexte technique (garde `ci-lecture`), et réécris `rbac-tests.txt` avec des sujets qui sont des groupes (`plateforme-admins`, `mediagenda`, `support`, `plateforme`, et un groupe inconnu). Dans `plateforme/gitops`, le rôle de projet `equipe` de `medidoc` reçoit le groupe `medidoc` (au lieu de `medisphere:medidoc-devs`) ; décide quoi faire de celui de `mediagenda` et écris pourquoi. Puis supprime les quatre comptes de personnes de `values.yaml` **et** de `values-durcissement.yaml`. MR (le job `argocd-rbac` doit passer), `apply`.
7. Contrôles : `argocd account list` (en `<MOI>` par le SSO) ; `argocd account can-i sync applications mediagenda/mediagenda-prod` pour toi ; et, avec l'outil de test du M20, le cas « `mediagenda` peut synchroniser la recette, pas la production ».

**Critères de réussite**
- [ ] `argocd` est confidentiel (redirection exacte), `argocd-cli` public avec PKCE `S256` et la seule redirection `http://localhost:8085/auth/callback` ; aucun des deux n'a de *Direct Access Grants*.
- [ ] `argocd-cm` déclare l'émetteur, `clientID: argocd`, `cliClientID: argocd-cli`, un secret par référence à `$argocd-oidc:clientSecret`, une liste de portées sans `groups` ; plus aucun compte local hors `ci-lecture` ; `admin` désactivé.
- [ ] `argocd-rbac-cm` lit `[groups]` ; `policy.csv` ne cite plus aucune personne et donne `role:plateforme-admin` au groupe `plateforme-admins` ; le job `argocd-rbac` du dernier pipeline de `main` a réussi.
- [ ] Le rôle de projet `equipe` de `medidoc` porte le groupe `medidoc`.
- [ ] `argocd-server` ne sort vers `sso` que sur 443.

**Vérification** : `lab/bin/check 24 13`

<details><summary>Indice 1</summary>

Si `requestedScopes` est absent, Argo CD demande `["openid", "profile", "email", "groups"]`. Chez nous, il n'existe pas de portée nommée `groups` (la nôtre s'appelle `groupes`, et elle est par défaut) : écris la liste toi-même.
</details>

<details><summary>Indice 2</summary>

`oidc.config` est une chaîne YAML dans `argocd-cm` : pour y mettre le PEM de la racine, le plus simple est de l'écrire dans le gabarit Helmfile (`.gotmpl`), qui sait déjà lire le fichier (`readFile … | nindent N`). Dans `policy.csv`, un sujet de ligne `g` est indifféremment un compte local ou un groupe OIDC : c'est pour cela que le M20 interdisait les comptes locaux qui porteraient le nom d'un groupe.
</details>

**Pour aller plus loin** (facultatif) : mesure la durée d'une session d'Argo CD (`users.session.duration`, M20-E25) face à celle de la session Keycloak : une personne désactivée dans l'annuaire garde-t-elle l'interface ? Lis la section *Logout* et `refreshTokenThreshold`. [Argo CD : *Keycloak*](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/keycloak/) · [*RBAC*](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)

---

### M24-E14 — Harbor en OIDC  `LAB` `★★★`

> **Ticket PLAT-2514** — *De : Karim Benali*
> Harbor maintenant. Lucas a essayé la semaine dernière, l'interface lui a répondu que le mode d'authentification « ne peut pas être modifié » et il en est resté là. Trouve pourquoi, et fais-le proprement : en code (`registre/` de `plateforme/infra`), sans casser les robots de la CI ni ceux d'Argo CD et des checks, et sans désactiver la vérification TLS « parce que ça marche mieux ». `admin` reste le bris de glace.

**Objectifs pédagogiques**
- Comprendre et lever une contrainte d'un logiciel (mode d'authentification figé dès qu'un utilisateur local existe) sans contournement dangereux.
- Transférer des droits d'utilisateurs locaux vers des groupes OIDC, puis supprimer les comptes, dans le bon ordre et en code.
- Faire confiance à une autorité interne dans une application conteneurisée installée hors Kubernetes.

**Prérequis** : M24-E11 ; M13-E03, M13-E06, M13-E10 (OpenTofu de Harbor : utilisateurs, projets, membres, robots), M13-E02 (rôle `harbor`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Client Keycloak | `harbor`, confidentiel, redirection `https://registry.par1.medisphere.internal/c/oidc/callback`, PKCE `S256` |
| Configuration | état OpenTofu **`registre`** de `plateforme/infra` (fournisseur `goharbor/harbor` `~> 3.12.0`) : `utilisateurs.tf` (quatre personnes), `projets.tf` (membres `harbor_project_member_user`), `robots.tf` |
| Réglages voulus | `auth_mode = oidc_auth`, nom affiché « SSO MédiSphère », revendication d'utilisateur `preferred_username`, groupes `groups`, groupe administrateur `plateforme-admins`, inscription automatique, vérification du certificat **activée** ; secret en argument en écriture seule (version à incrémenter à chaque rotation) |
| Membres voulus | projet `medisphere` : `plateforme-admins` `projectadmin`, `plateforme` `maintainer`, `mediagenda` `developer`, `medidoc` `developer` ; projets `plateforme`, `bibliotheque`, `charts` : `plateforme-admins` `projectadmin`, `plateforme` `developer` |
| Confiance | Harbor ajoute au magasin de ses conteneurs les fichiers montés dans `/harbor_cust_cert` ; `prepare` y copie le paquet de `storage_service.ca_bundle` de `harbor.yml` |
| Pipeline | `plateforme/infra`, variables protégées et masquées (`HARBOR_*` du M13) ; ajoute le secret du client en variable protégée et masquée |

**Travail demandé**

*A. Comprendre le refus*

1. Reproduis ce qu'a vu Lucas **sans rien changer** : essaie le changement par l'API en `admin` avec une valeur invalide pour le reste, ou lis la configuration (`GET /api/v2.0/configurations`) : que vaut `auth_mode.editable` ? Lis la documentation *Configure OIDC Provider Authentication* de Harbor 2.15 : quelle phrase l'explique ? Dans le code source de la 2.15 (`src/controller/config/controller.go`), retrouve la fonction qui décide : quels utilisateurs compte-t-elle, et lesquels ignore-t-elle ?
2. Inventorie ce qui dépend des comptes locaux : leurs appartenances aux projets (`projets.tf`), leurs secrets CLI éventuels (`docker login` fait par une personne), les robots (qui n'en dépendent pas : pourquoi ?). Écris le plan dans `~/m24/e14/plan.md` : ordre des MR, et ce qui se passe pour Lucas entre deux étapes.
   > ⚠️ **Attention** : essaie d'abord la connexion `admin` (mot de passe du Vault) dans une fenêtre privée et garde-la ouverte. Une fois en OIDC, `admin` se connecte encore par le formulaire local de Harbor (c'est le seul). Retour arrière avant l'étape 6 : revenir sur les MR ; **après** l'étape 6, revenir en `db_auth` est possible tant qu'aucune personne ne s'est inscrite par OIDC ; ensuite, la même contrainte joue dans l'autre sens.

*B. La confiance*

3. Dans le rôle `harbor`, ajoute la racine MédiSphère au paquet de confiance des conteneurs (variable du rôle, gabarit `harbor.yml.j2`). Applique sur `reg01` (fenêtre calme : `prepare` et redémarrage de Harbor), puis vérifie depuis le conteneur `harbor-core` que `https://sso.par1.medisphere.internal` se vérifie.

*C. Le client et la bascule, en trois MR*

4. `tofu/clients-harbor.tf`, MR, apply ; `ranger-secret-client.sh harbor`. Variable de CI de `plateforme/infra` pour le secret ; complète `outils/charger-acces.sh` de `plateforme/infra` pour la lire dans le Vault.
5. **MR 1 (`registre/`)** : les membres de groupes OIDC **en plus** des membres utilisateurs (`harbor_project_member_group`, type `oidc`). Les groupes sont créés dans Harbor par cette ressource : vérifie-le dans l'interface.
6. **MR 2** : suppression de `utilisateurs.tf` et des `harbor_project_member_user`. Que montre le plan pour les comptes ? Que devient un utilisateur « supprimé » dans la base de Harbor (lis `src/pkg/user/manager.go`), et pourquoi cela suffit-il à débloquer la bascule ?
7. **MR 3** : `registre/authentification.tf` avec `harbor_config_auth` selon les réglages voulus. Plan, apply. Puis l'interface : bouton « LOGIN VIA OIDC PROVIDER » ; connecte-toi en `<MOI>`, puis en `lucas.martin`.
8. Contrôles : l'utilisateur `lucas.martin` a-t-il été créé, avec quels groupes (*Administration* → *Groups*) ? Est-il `maintainer` de `medisphere` ? Comment pousse-t-il une image depuis `adm01` (secret CLI de son profil) ? Les robots `wb-checks`, de la CI et d'Argo CD fonctionnent-ils encore (`lab/bin/check 13 03`, une Application qui tire un chart) ?

**Critères de réussite**
- [ ] Le client `harbor` est confidentiel, redirection exacte, PKCE `S256`.
- [ ] Harbor est en `oidc_auth`, vérification du certificat activée, groupe administrateur `plateforme-admins`, revendication de groupes `groups`.
- [ ] Plus aucun `harbor_user` ni `harbor_project_member_user` dans `registre/` sur `main` ; les membres sont des groupes OIDC ; le secret passe par un argument en écriture seule.
- [ ] Les robots répondent toujours (le robot des checks lit encore les projets).

**Vérification** : `lab/bin/check 24 14`

<details><summary>Indice 1</summary>

La fonction qui décide compte les utilisateurs **non supprimés** en excluant l'administrateur par défaut. Harbor ne supprime jamais vraiment un compte : il le marque et renomme son identifiant, ce qui libère aussi le nom pour un futur utilisateur OIDC du même nom.
</details>

<details><summary>Indice 2</summary>

Dans le fournisseur 3.12, `harbor_config_auth` accepte `oidc_client_secret_wo` et `oidc_client_secret_wo_version` : la variable qui l'alimente peut être éphémère, comme le mot de passe de la fédération en E08. Les ressources de groupes OIDC n'ont besoin que de `group_name` et `type = "oidc"`.
</details>

<details><summary>Indice 3</summary>

`oidc_verify_cert = false` est le « contournement » que tout le monde trouve en premier sur Internet. Le paquet de confiance des conteneurs de Harbor se construit au démarrage à partir de ce que `prepare` a déposé : un changement de `harbor.yml` sans `prepare` ne fait rien.
</details>

**Pour aller plus loin** (facultatif) : active `oidc_logout` (Harbor ≥ 2.13) et observe ce qui se passe côté Keycloak à la déconnexion. [Harbor : *Configure OIDC Provider Authentication*](https://goharbor.io/docs/2.15.0/administration/configure-authentication/oidc-auth/) · [Fournisseur `goharbor/harbor`](https://search.opentofu.org/provider/goharbor/harbor/latest)

---

### M24-E15 — Proxmox VE, PBS et NetBox en SSO  `LAB` `★★`

> **Ticket SEC-2515** — *De : Sophie Laurent* — *Copie : Claire Morel*
> Trois consoles d'administration avec des comptes locaux : l'hyperviseur, les sauvegardes et la source de vérité du réseau. Proxmox sait lire les groupes, faisons-le ; PBS et NetBox ne savent pas, alors décidez et écrivez comment les droits y arrivent. `wb-admin@pve` disparaît du quotidien (désactivé), `root@pam` reste le bris de glace et ne sert plus qu'à ça. Les jetons d'automatisation ne bougent pas.

**Objectifs pédagogiques**
- Créer des royaumes OpenID Connect sur Proxmox VE et PBS, avec ou sans correspondance de groupes, sans faire passer un secret par une ligne de commande.
- Donner des ACL à des groupes venus de l'IdP (Proxmox VE) ou à des personnes (PBS), et le justifier.
- Brancher une application Django (NetBox) sur un backend `python-social-auth` par Ansible, avec la bonne autorité de confiance et le rattachement des comptes existants.

**Prérequis** : M24-E11 ; M00-E10 et M02 (comptes et jetons Proxmox), M06-E04 (rôle `netbox`), M05 (OpenTofu et `bpg/proxmox`).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Clients Keycloak | `proxmox` (redirection `https://pve01.par1.medisphere.internal:8006`), `pbs` (`https://pbs01.par2.medisphere.internal:8007`), `netbox` (`https://nbx01.par1.medisphere.internal/oauth/complete/oidc/`) : confidentiels, flux standard seul |
| Proxmox VE | royaume `medisphere` de type `openid`, identifiant `preferred_username` (valeur `username` de l'option), groupes `groups` (suffixés `-medisphere` par Proxmox), écrasement des groupes à chaque connexion, création automatique des utilisateurs ; en code : nouvelle racine OpenTofu **`acces-proxmox/`** de `plateforme/infra` (fournisseur `bpg/proxmox` de `plateforme/infra`, ressource `proxmox_realm_openid` et son argument `client_key_wo`), appliquée depuis `adm01` avec un **jeton temporaire** de `root@pam` (le jeton `wb-tofu@pve!tofu` n'a, à raison, ni `Realm.Allocate` ni `Permissions.Modify`) |
| ACL Proxmox | `plateforme-admins-medisphere` : `PVEAdmin` sur `/` ; `plateforme-medisphere`, `securite-medisphere` : `PVEAuditor` sur `/` ; `support-medisphere` : `PVEAuditor` sur `/pool/lab` |
| PBS | royaume OpenID `medisphere` sur `pbs01`, identifiant `preferred_username`, création automatique, **pas** de groupes ; droits par personne (`proxmox-backup-manager acl`) ; secret posé par l'API locale avec un jeton temporaire |
| NetBox | 4.6, rôle `netbox` : `REMOTE_AUTH_BACKEND = 'social_core.backends.open_id_connect.OpenIdConnectAuth'`, `SOCIAL_AUTH_OIDC_*` ; groupe par défaut `sso-lecture` (lecture de tout), groupe `sso-ecriture` donné à la main aux membres de `plateforme-admins` ; formulaire local conservé pour `admin` et les comptes de service |
| Flux | `pve01` et `pbs01` → VIP 10.10.70.200:443 (PLAN §4.12) ; `nbx01` (VLAN 20) → VIP 443 |

**Travail demandé**

*A. Les clients*

1. `tofu/clients-proxmox.tf`, `clients-pbs.tf`, `clients-netbox.tf`, MR, apply ; `ranger-secret-client.sh` pour les trois.
2. Vérifie sur `pve01`, `pbs01` et `nbx01` que `sso.par1.medisphere.internal` se résout et se vérifie avec le magasin système (`curl -sS -o /dev/null -w '%{http_code}\n' https://sso…/realms/medisphere/.well-known/openid-configuration`). Corrige ce qui manque (racine installée, résolveur, flux) par l'outil qui gère l'hôte, et note-le.

*B. Proxmox VE*

3. Lis `pveum realm add --help` **sur `pve01`** (options `--groups-claim`, `--groups-autocreate`, `--groups-overwrite`, `--username-claim`, `--autocreate`) et la section *OpenID Connect* du chapitre *User Management* de la documentation. Quelle option ne peut plus changer après la création du royaume, et pourquoi ?
   > ⚠️ **Attention** : garde une session `root@pam` ouverte dans l'interface **et** une console SSH `root@pve01` pendant tout le B. Ne touche jamais au royaume `pam`. Retour arrière : `pveum realm delete medisphere` (les comptes `@medisphere` créés deviennent inutilisables, rien d'autre ne change).
4. Écris `acces-proxmox/` : versions et état (`acces-proxmox/terraform.tfstate`, chiffré comme les autres), le royaume (secret par variable éphémère), les quatre groupes **déclarés** (pour pouvoir leur donner des ACL avant la première connexion), les ACL. Crée sur `pve01` un jeton de `root@pam` **sans séparation des privilèges, valable 30 minutes**, charge-le sans l'afficher, plan, MR, apply depuis `adm01`, puis **supprime le jeton**. Pourquoi ce compromis plutôt que d'augmenter les droits de `wb-tofu@pve` ?
5. Connecte-toi à `https://pve01.par1.medisphere.internal:8006` par le royaume `medisphere` en `<MOI>`, puis en `lucas.martin`. Quels utilisateurs et quelles appartenances apparaissent dans *Datacenter* → *Permissions* → *Users* ? Lucas peut-il arrêter une VM ? Désactive ensuite `wb-admin@pve` (`pveum user modify … --enable 0`) et note pourquoi on le désactive au lieu de le supprimer.

*C. PBS*

6. Sur `pbs01`, crée le royaume par l'API locale : jeton temporaire de `root@pam` (`proxmox-backup-manager user generate-token`, expiration courte, ACL limitée), secret lu dans un fichier en 600 et envoyé par `curl --data-urlencode client-key@…`, puis suppression du jeton et du fichier. Vérifie par `proxmox-backup-manager openid show medisphere`. Connecte-toi en `<MOI>` (créé automatiquement, sans droit), puis donne les ACL par personne selon le modèle d'E10 ; écris dans `docs/securite/identite/modele-autorisation.md` pourquoi PBS reste par personne.

*D. NetBox*

7. Dans le rôle `netbox` : variables et gabarit `configuration.py.j2` pour le SSO (backend, point de découverte, client, secret lu dans le Vault `secrets/identite.yml`, groupe par défaut, affichage du bouton), et la variable d'environnement qui fait utiliser à `requests` le magasin système plutôt que celui de `certifi`. Le pipeline d'authentification par défaut de NetBox crée un **second** compte si un compte local porte déjà le même identifiant : ajoute l'étape de `python-social-auth` qui rattache par adresse de courriel, et écris pourquoi c'est acceptable chez nous et pas en général. Crée les groupes `sso-lecture` et `sso-ecriture` (permissions d'objets) par l'interface en `admin`, ou par un script de `nbshell`.
8. `playbooks/netbox.yml` (qui charge le Vault `secrets/identite.yml`), `--check --diff` puis application. Connecte-toi en `<MOI>` par le SSO : retrouves-tu ton compte local et tes jetons ? Puis en `lucas.martin` : dans quel groupe est-il, que peut-il faire ? Les jetons de `wb-checks` et `svc-automatisation` fonctionnent-ils toujours (`lab/bin/check 06 04`) ?

**Critères de réussite**
- [ ] Les clients `proxmox`, `pbs` et `netbox` sont confidentiels, en flux standard seul, avec leur seule redirection exacte.
- [ ] `pve01` : royaume `medisphere` (OpenID, émetteur du royaume, client `proxmox`, identifiant `username`, groupes `groups`) ; ACL `PVEAdmin` sur `/` pour `plateforme-admins-medisphere` et `PVEAuditor` sur `/pool/lab` pour `support-medisphere` ; `wb-admin@pve` désactivé ; aucun jeton temporaire de `root@pam` restant.
- [ ] `pbs01` : royaume OpenID `medisphere` ; aucun jeton temporaire restant.
- [ ] NetBox propose la connexion par le SSO ; ton compte existant est rattaché, sans doublon.

**Vérification** : `lab/bin/check 24 15`

<details><summary>Indice 1</summary>

Proxmox VE ne donne des ACL qu'à des groupes qui existent ; avec `groups-autocreate`, ils n'existent qu'après la première connexion d'un membre. Les déclarer en code (sans membres) règle les deux problèmes : l'ACL existe avant, et seuls les groupes déclarés servent (un groupe inconnu reçu de Keycloak est ignoré si la création automatique est désactivée).
</details>

<details><summary>Indice 2</summary>

Le fournisseur `bpg/proxmox` accepte un jeton par `PROXMOX_VE_API_TOKEN` (`root@pam!<nom>=<valeur>`). Dans PBS, un jeton a ses propres ACL (l'intersection avec celles de son utilisateur) : sans ACL, il ne peut rien. Pour NetBox, regarde `SOCIAL_AUTH_PIPELINE` dans `netbox/netbox/settings.py` de la 4.6 et la liste des étapes de `social_core.pipeline.social_auth`.
</details>

**Pour aller plus loin** (facultatif) : NetBox sait aussi recevoir les groupes par en-tête derrière un mandataire (`REMOTE_AUTH_GROUP_SYNC_ENABLED`) ; compare avec OAuth2 Proxy (E18) et dis ce que tu gagnerais et perdrais. [Proxmox VE : *User Management*](https://pve.proxmox.com/pve-docs/chapter-pveum.html) · [PBS : *User Management*](https://pbs.proxmox.com/docs/user-management.html) · [NetBox : *Authentication*](https://netboxlabs.com/docs/netbox/administration/authentication/overview/)

---

### M24-E16 — `kubectl` par OIDC : authentification structurée et kubelogin  `LAB` `★★★`

> **Ticket PLAT-2516** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Les certificats personnels de sept jours du M14, on ne sait pas les révoquer : on l'a prouvé. Le cluster doit accepter les jetons de Keycloak, par l'**authentification structurée** (pas les vieux drapeaux `--oidc-*`), avec des noms préfixés pour qu'aucun groupe de l'annuaire ne se fasse passer pour un groupe système. Un nœud de contrôle à la fois, comme toujours ; et je veux voir qu'un jeton délivré pour un **autre** client est refusé. Les droits par groupe, ce sera le ticket suivant (E17).

**Objectifs pédagogiques**
- Écrire une `AuthenticationConfiguration` (`apiserver.config.k8s.io/v1`) : émetteur, audience, autorité, correspondance des revendications, règles de validation CEL.
- Reconfigurer kube-apiserver sur un cluster kubeadm sans coupure, un nœud à la fois, avec retour arrière.
- Utiliser kubelogin (code d'autorisation + PKCE) depuis un poste sans navigateur, et comprendre ce que voit le serveur d'API.

**Prérequis** : M24-E10 ; M14-E27 (`outils/reconfigurer-apiserver.sh`, `playbooks/k8s-api-fichiers.yml`), M14-E06 (identités du cluster, `wb-checks`), M14-E28 (fichier monté par dossier).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Client Keycloak | `kubernetes` : **public**, PKCE `S256`, redirections `http://localhost:8000` et `http://localhost:18000` (celles de kubelogin), flux standard seul |
| Fichier | `/etc/kubernetes/authentification/config.yaml` (root, 600) sur `k8s-cp01..03`, posé par le rôle **`k8s_authentification`** (variables `k8s_authentification_*`, `group_vars/k8s_plan_controle/authentification.yml`) joué par `playbooks/k8s-api-fichiers.yml` ; le **dossier** est monté dans le pod (rechargement à chaud) |
| Contenu voulu | émetteur `https://sso.par1.medisphere.internal/realms/medisphere`, audience `kubernetes`, racine MédiSphère en PEM dans le fichier ; utilisateur = `preferred_username`, préfixe `oidc:` ; groupes = `groups`, préfixe `oidc:` ; règles : `azp` vaut `kubernetes`, aucun utilisateur ni groupe ne commence par `system:` |
| kube-apiserver | `--authentication-config` par `apiServer.extraArgs` et `extraVolumes` de `cluster/kubeadm-config.yaml` (`plateforme/k8s`), appliqué par `outils/reconfigurer-apiserver.sh <nœud>` puis `--televerser` ; il joint `sso` par la VIP `lb` (flux `K8S_CP` → 10.10.70.200:443) |
| `adm01` | kubelogin **1.36** (`kubectl krew install oidc-login`) ; contexte `k8s-par1-oidc` (utilisateur `oidc`, même cluster que `k8s-par1`) ajouté par `outils/kubeconfig-oidc.sh` de `plateforme/k8s` ; le contexte `k8s-par1` (certificat du M14) reste le défaut jusqu'à E17 |
| Vérifications | ClusterRole agrégée **`wb-checks-securite`** (`rbac/wb-checks-securite.yaml`) pour les objets de sécurité du bloc F (ESO, Kyverno… : lecture, jamais de Secret) |

**Travail demandé**

*A. Lire et décider*

1. Lis la section *Authentication configuration from a file* de la page *Authenticating* de Kubernetes 1.36 et la page de kubelogin (*Usage*). Dans `~/m24/e16/notes.md` : pourquoi le préfixe `oidc:` ; ce que vérifie le serveur d'API sur un jeton (`iss`, `aud`, signature par le JWKS, `exp`, règles CEL) ; pourquoi la racine doit être **dans** le fichier alors que le nœud la connaît déjà ; ce qui se passe si l'on garde un `--oidc-issuer-url` dans le manifeste en ajoutant `--authentication-config` ; qui porte l'ID token, et pourquoi le serveur d'API n'appelle jamais Keycloak à chaque requête.
2. Vérifie depuis chaque nœud de contrôle que l'émetteur est joignable et se vérifie :
   ```
   admin@k8s-cp01:~$ curl -sS --max-time 5 https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration | jq -r .issuer
   ```

*B. Keycloak et le fichier*

3. `tofu/clients-kubernetes.tf`, MR, apply. Pourquoi un client public suffit-il ici, alors que Grafana a un secret ?
4. Écris le rôle `k8s_authentification` (gabarit du fichier, contrôles de cohérence, écriture atomique, dossier en 700) et ajoute-le à `playbooks/k8s-api-fichiers.yml`. Applique : le fichier est posé sur les trois nœuds, rien ne change encore pour le serveur d'API (pourquoi ?).

*C. Le serveur d'API, un nœud à la fois*

5. Dans `cluster/kubeadm-config.yaml`, ajoute l'option et le volume (en **ajoutant** aux listes existantes d'audit et de chiffrement). MR relue.
   > ⚠️ **Attention** : un serveur d'API qui ne démarre pas sur un nœud, c'est un tiers de l'API en moins ; deux, et etcd perd des écrivains. Avant de commencer : instantané etcd vérifié (RB-141), `admin.conf` du Vault et ton certificat personnel essayés (`kubectl --context k8s-par1 get nodes`), `free -g` sur `pve01`. **Un nœud, vérifié, puis le suivant.** Le script revient en arrière tout seul si `/readyz` ne répond pas ; sinon, retour arrière à la main : remettre la copie du manifeste qu'il a gardée hors de `/etc/kubernetes/manifests/`.
6. Applique sur `k8s-cp01` :
   ```
   admin@adm01:~/src/k8s$ outils/reconfigurer-apiserver.sh k8s-cp01
   ```
   Lis le `diff` affiché : seules une option et un volume doivent apparaître. Vérifie (`kubectl --context k8s-par1 -n kube-system get pod kube-apiserver-k8s-cp01 -o yaml | grep authentication-config`, journal du conteneur). Puis `k8s-cp02`, `k8s-cp03`, et `--televerser`.

*D. Côté poste*

7. Installe kubelogin, écris et lance `outils/kubeconfig-oidc.sh`. Depuis ton poste, ouvre le tunnel (`ssh -L 8000:127.0.0.1:8000 -L 18000:127.0.0.1:18000 admin@adm01.par1.medisphere.internal`), puis :
   ```
   admin@adm01:~$ kubectl --context k8s-par1-oidc auth whoami
   admin@adm01:~$ kubectl --context k8s-par1-oidc get pods -A
   ```
   Que dit `whoami` (utilisateur, groupes) ? Pourquoi `get pods` est-il refusé (`Forbidden`, pas `Unauthorized`), et quel exercice le corrigera ?
8. Prouve les refus :
   - un jeton d'**accès** (au lieu de l'ID token) du même utilisateur : ajoute un second utilisateur `oidc-acces` (option `--oidc-use-access-token` de kubelogin) et essaie `auth whoami` ; lis `aud` et `azp` du jeton (`kubectl oidc-login get-token … | jq -r .status.token`, puis décodage comme en E07, **tronqué** dans tes notes) ;
   - un jeton de `wb-checks` (`client_credentials`), présenté au serveur d'API par `curl` en en-tête lu par `-K` ;
   - dans le journal du serveur d'API d'un nœud, retrouve la raison de chaque refus.
   Puis supprime l'utilisateur `oidc-acces` de `~/.kube/config`.
9. `rbac/wb-checks-securite.yaml` (ClusterRole agrégée, étiquette `workbook.medisphere.internal/checks: "true"`), appliqué comme les autres fichiers de `rbac/` (`task appliquer`).

**Critères de réussite**
- [ ] Le client `kubernetes` est public, PKCE `S256`, avec exactement les deux redirections de kubelogin, sans *Direct Access Grants*.
- [ ] Les trois serveurs d'API ont `--authentication-config=/etc/kubernetes/authentification/config.yaml` et aucune option `--oidc-*` ; le fichier, en 600, déclare l'audience `kubernetes`, les préfixes `oidc:` et la règle contre `system:`.
- [ ] Chaque nœud de contrôle joint l'émetteur en TLS vérifié.
- [ ] `kubectl --context k8s-par1-oidc auth whoami` renvoie `oidc:<MOI>` et ses groupes `oidc:…` ; un jeton de Keycloak destiné à un autre client est refusé (401).
- [ ] `adm01` a kubelogin et le contexte `k8s-par1-oidc` (client public, sans secret) ; `wb-checks-securite` existe, agrégée, sans accès aux Secrets.

**Vérification** : `lab/bin/check 24 16`

<details><summary>Indice 1</summary>

Le conteneur de kube-apiserver n'utilise pas le magasin de certificats du nœud : `certificateAuthority` (PEM) est la seule façon fiable de lui faire vérifier `sso`. `audiences` est comparée à `aud` du jeton : l'ID token délivré au client `kubernetes` a `aud = kubernetes`, le jeton d'accès non.
</details>

<details><summary>Indice 2</summary>

`userValidationRules` s'écrivent en CEL sur `user` (`!user.username.startsWith('system:')`, `user.groups.all(g, !g.startsWith('system:'))`), `claimValidationRules` sur `claims` (`claims.azp == 'kubernetes'`). Le dossier monté (et non le fichier) est ce qui permet au serveur d'API de voir un fichier remplacé par renommage : c'est la leçon du chiffrement du M14-E28.
</details>

<details><summary>Indice 3</summary>

kubelogin écoute sur `127.0.0.1:8000` d'`adm01` et affiche une URL à ouvrir : sans navigateur sur `adm01`, l'URL s'ouvre sur ton poste, et la redirection finale vers `http://localhost:8000` doit arriver… sur `adm01`, d'où le tunnel. `--skip-open-browser` évite qu'il cherche un navigateur.
</details>

**Pour aller plus loin** (facultatif) : ajoute un second émetteur (un royaume de test) dans le même fichier et observe le rechargement à chaud (métrique `apiserver_authentication_config_controller_automatic_reload_last_timestamp_seconds`) ; compare avec Pinniped, qui fait la même chose sans toucher au serveur d'API. [Kubernetes : *Authenticating*](https://kubernetes.io/docs/reference/access-authn-authz/authentication/) · [kubelogin](https://github.com/int128/kubelogin) · [KEP-3331](https://github.com/kubernetes/enhancements/tree/master/keps/sig-auth/3331-structured-authentication-configuration)

---

### M24-E17 — RBAC Kubernetes par groupes de l'annuaire  `LAB` `★★`

> **Ticket SEC-2517** — *De : Sophie Laurent* — *Copie : Karim Benali, Julien Petit*
> Depuis E16, `kubectl` sait dire **qui** se connecte. Il ne sait pas encore ce qu'on a le droit de faire : à part toi, personne n'a de droit, et les liaisons du M14 visent toujours les groupes de vos certificats de sept jours. Je veux que les droits du cluster découlent des groupes de l'annuaire, exactement comme dans le modèle d'autorisation d'E10, sans un seul nom de personne dans le RBAC. Et je veux qu'à la fin de la semaine plus aucun certificat personnel ne donne le moindre droit : un certificat ne se révoque pas, une liaison si.

**Objectifs pédagogiques**
- Traduire un modèle d'autorisation en liaisons RBAC par groupes, préfixés, sans liaison nominative.
- Vérifier des droits sans être la personne : usurpation d'identité (`--as`, `--as-group`), `kubectl auth can-i`, `kubectl auth whoami`.
- Basculer l'exploitation quotidienne sur OIDC et retirer les droits des certificats personnels, sans s'enfermer dehors.

**Prérequis** : M24-E16 (authentification structurée, contexte `k8s-par1-oidc`), M24-E10 (modèle d'autorisation) ; M14-E06 et M14-E11 (rôles agrégés, matrice de droits).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Identités vues par kube-apiserver (E16) | utilisateur `oidc:<preferred_username>` (ex. `oidc:lucas.martin`), groupes `oidc:<groupe de l'annuaire>` (ex. `oidc:plateforme`), plus `system:authenticated` |
| RBAC existant (M14) | `plateforme/k8s/rbac/` : ClusterRoles agrégées `medisphere-lecture`, `medisphere-developpeur`, `medisphere-lecture-charges`, `medisphere-lecture-cluster`, `medisphere-secrets-edition` ; liaisons aux groupes de **certificats** `medisphere:plateforme-admins`, `medisphere:lecture`, `medisphere:mediagenda-devs`, `medisphere:medidoc-devs` ; appliqué par `task appliquer` (couche de base, hors Argo CD) |
| Fichier à écrire | `rbac/oidc.yaml` de `plateforme/k8s` ; liaisons nommées **`oidc-*`** |
| Droits attendus | `oidc:plateforme-admins` → `cluster-admin` ; `oidc:plateforme` → tout lire sauf les Secrets (y compris les objets des composants : Argo CD, supervision, Gateway…) et écrire dans `wb-essais` ; `oidc:mediagenda` → `edit` dans `mediagenda-dev`, `view` dans `mediagenda-dev`, `-recette` et `-prod` ; `oidc:medidoc` → `view` dans `medidoc-dev` et `medidoc-recette` ; `oidc:support` → lecture sans Secrets (comme `medisphere:lecture`) ; `oidc:securite` → ClusterRole `medisphere-securite` : lecture sans Secrets **et** lecture du RBAC ; `oidc:direction` → rien (modèle d'autorisation d'E10) |
| Contextes de `~/.kube/config` | `k8s-par1` (ton certificat personnel de 7 jours, M14) ; `k8s-par1-oidc` (utilisateur `oidc`, kubelogin, E16). De nombreux outils de `plateforme/k8s` (Taskfile, Helmfile, `outils/*.sh`) visent **le nom** `k8s-par1` |
| Bris de glace | `admin.conf` (Ansible Vault `critique`, M14) : groupe `kubeadm:cluster-admins`, indépendant de Keycloak et de ce fichier |
| Brouillons | `~/m24/e17/` |

**Travail demandé**

*A. Inventaire*

1. Liste toutes les liaisons qui visent un groupe ou un utilisateur **humain** (ni compte de service, ni `system:*`) :
   ```
   admin@adm01:~$ kubectl get clusterrolebindings,rolebindings -A -o json | jq -r '.items[]
   >   | . as $l | .subjects[]? | select(.kind != "ServiceAccount" and (.name | startswith("system:") | not))
   >   | "\($l.kind)\t\($l.metadata.namespace // "-")\t\($l.metadata.name)\t\(.kind)\t\(.name)\t\($l.roleRef.name)"' | column -t
   ```
   Note dans `~/m24/e17/inventaire.md` chaque liaison et la ligne du modèle d'autorisation (E10) qui lui correspond. Y a-t-il des droits du M14 que le modèle ne prévoit plus, ou l'inverse ?

*B. Les liaisons par groupes*

2. Écris `rbac/oidc.yaml` selon le contexte technique. Réutilise les ClusterRoles du M14 ; crée seulement ce qui manque (une ClusterRole agrégée pour l'équipe Plateforme, une pour la Sécurité qui ajoute la lecture du RBAC). Contraintes : aucun sujet de type `User`, aucun accès aux Secrets hors de `wb-essais` et de `mediagenda-dev`, aucun groupe sans le préfixe `oidc:`. Pourquoi lire « tous les groupes d'API sauf le cœur » ne donne-t-il pas accès aux Secrets ?
3. MR sur `plateforme/k8s`, relecture, fusion, puis application par la procédure habituelle (`task valider`, `task diff`, `task appliquer`).

*C. Vérifier sans être la personne*

4. Rejoue l'identité de quelqu'un d'autre ; regarde d'abord ce que voit kube-apiserver, puis ce qu'il autorise :
   ```
   admin@adm01:~$ kubectl auth whoami --as=oidc:julien.petit --as-group=oidc:mediagenda
   admin@adm01:~$ kubectl auth can-i --list -n mediagenda-dev --as=oidc:julien.petit --as-group=oidc:mediagenda
   admin@adm01:~$ kubectl auth can-i get secrets -n mediagenda-prod --as=oidc:julien.petit --as-group=oidc:mediagenda
   ```
   Pourquoi faut-il donner **les deux** options ? Qui a le droit d'usurper une identité, et pourquoi ce droit est-il lui-même sensible ?
5. Écris `outils/matrice-droits-oidc.sh` dans `plateforme/k8s` sur le modèle de `matrice-droits.sh` du M14-E11 : une trentaine de cas (au moins trois par groupe, dont des refus), sortie `OK`/`ÉCART`, code 1 au moindre écart, contexte en paramètre. Ajoute un cas pour un groupe nommé `system:masters` dans l'annuaire : que devient-il dans Kubernetes ?
6. Un vrai jeton, enfin. Avec **ton** identité, `kubectl --context k8s-par1-oidc auth whoami`. Puis connecte-toi comme `lucas.martin` (mot de passe d'E03) **sans toucher à ton propre cache de jetons** : copie de ton kubeconfig dans `~/m24/e17/essai.kubeconfig`, dont l'utilisateur `oidc` ajoute à ses arguments kubelogin un dossier de cache dédié (cherche l'option dans `kubectl oidc-login get-token --help`), fenêtre privée du navigateur (méthode d'E16). Avec ce fichier : `auth whoami`, `get pods -n kube-system`, `get secrets -n kube-system`, `create configmap essai -n wb-essais`. Supprime ensuite le fichier, le dossier de cache et la ConfigMap.

*D. La bascule*

> ⚠️ **Attention** : à partir de l'étape 7, ton certificat personnel ne te donne plus aucun droit. Avant de commencer : (1) `kubectl --context k8s-par1-oidc auth can-i '*' '*'` répond `yes` ; (2) le bris de glace marche **maintenant** : extrais `admin.conf` du Vault dans un fichier temporaire en 600 hors de tout dépôt, `kubectl --kubeconfig <FICHIER> auth whoami` (groupe `kubeadm:cluster-admins`), puis supprime le fichier. Retour arrière si tu perds l'accès : `admin.conf` du Vault, puis `kubectl apply` des fichiers du M14 retirés (ils restent dans l'historique Git).

7. Fais pointer le contexte **`k8s-par1`** vers l'utilisateur `oidc` (tous les outils qui visent ce nom passent ainsi à OIDC sans modification), fais de `k8s-par1-oidc` le contexte courant, et retire de `~/.kube/config` l'utilisateur à certificat (sauvegarde d'abord le fichier, en 600). Relance `task diff` et `helmfile -e par1 diff` : sous quelle identité tournent-ils maintenant ?
> ⚠️ **Attention** : l'étape 8 supprime pour de bon les liaisons `medisphere:*` du M14 (`medisphere:plateforme-admins`, `medisphere:lecture`, `medisphere:mediagenda-devs`, `medisphere:medidoc-devs`) et les scripts de certificats personnels (`outils/kubeconfig-personnel.sh`, `outils/kubeconfig-csr.sh`), du cluster **et** de `main`. Conséquences : plus aucun certificat personnel émis au M14 (le tien, celui de Julien) ne donne de droit ; et les contrôles du M14 qui décrivent cet état passent **au rouge** et y resteront : `lab/bin/check 14 06`, `14 11`, `14 12`, `14 33`, `14 41` et `14 46`. C'est attendu, pas une régression : à partir d'ici, les droits des personnes se vérifient par `lab/bin/check 24 17`. Retour arrière : `kubectl apply -f` des fichiers retirés (historique Git), avec `admin.conf`.

8. Retire les liaisons aux groupes de certificats (`medisphere:*`) : `kubectl delete -f` des fichiers concernés, **puis** leur suppression dans une MR (pourquoi dans cet ordre ? que ferait `task appliquer` seul ?). Retire aussi les scripts qui émettaient des certificats personnels. Rejoue ta matrice.
9. Mets à jour `docs/kubernetes/acces.md` de `plateforme/medisphere` : identités humaines (OIDC), groupes et droits (renvoi au modèle d'autorisation), bris de glace, ce qui a disparu.

**Critères de réussite**
- [ ] `rbac/oidc.yaml` est sur `main` de `plateforme/k8s` et appliqué ; chaque groupe de l'annuaire a exactement les droits du contexte technique (contrôlés par SubjectAccessReview).
- [ ] Aucune liaison ne vise un utilisateur nommé, ni un groupe `medisphere:*` de certificat ; toutes les liaisons des personnes s'appellent `oidc-*`.
- [ ] `outils/matrice-droits-oidc.sh` est sur `main` et passe sans écart.
- [ ] Dans ton `~/.kube/config`, le contexte courant est `k8s-par1-oidc`, le contexte `k8s-par1` utilise le même utilisateur OIDC, plus aucun utilisateur n'a de certificat client.
- [ ] `docs/kubernetes/acces.md` décrit les identités OIDC et le bris de glace.

**Vérification** : `lab/bin/check 24 17`

<details><summary>Indice 1</summary>

RBAC n'a pas de « sauf » : pour « tout sauf les Secrets », on énumère. Les Secrets sont dans le groupe d'API du cœur (`""`) ; un `*` sur une liste explicite d'autres groupes (`apps`, `argoproj.io`, `monitoring.coreos.com`…) ne les touche donc pas. C'est ce que fait déjà `wb-checks-base` (M14-E06). Une ClusterRole agrégée évite de recopier ce que `medisphere-lecture` sait déjà.
</details>

<details><summary>Indice 2</summary>

Avec `--as` seul, kube-apiserver ne connaît que l'utilisateur, sans ses groupes : tes liaisons par groupe ne s'appliquent pas, et tout est refusé. kubelogin range ses jetons dans un dossier de cache dont le nom de fichier dépend de l'émetteur et du client : deux personnes sur le même compte Unix partagent ce cache, sauf option contraire.
</details>

<details><summary>Indice 3</summary>

`task appliquer` applique ce qui est dans le dépôt ; il ne supprime pas ce qui n'y est plus (pas d'élagage). Un fichier retiré de Git laisse ses objets dans le cluster. `kubectl config set-context <NOM> --user=<UTILISATEUR>` change l'utilisateur d'un contexte existant.
</details>

**Pour aller plus loin** (facultatif) : lance la matrice dans le pipeline de `plateforme/k8s` à chaque MR qui touche `rbac/`, avec un compte de service qui n'a que le droit de créer des `SubjectAccessReview` (pas `impersonate`). [Kubernetes : *Using RBAC Authorization*](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) · [*User impersonation*](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#user-impersonation) · [`kubectl auth whoami`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_whoami/)

---

### M24-E18 — OAuth2 Proxy devant Hubble, Pyroscope et Mailpit  `LAB` `★★`

> **Ticket PLAT-2518** — *De : Karim Benali* — *Copie : Sophie Laurent, Nadia Roussel*
> Trois interfaces ne savent pas faire de SSO : Hubble UI (protégée seulement par le réseau depuis le M15), Pyroscope (pas publiée du tout, on passe par Grafana) et Mailpit (un mot de passe partagé). Mets OAuth2 Proxy devant les trois. Une seule application cliente dans Keycloak, des groupes autorisés par interface : Hubble pour la Plateforme et le support, Pyroscope en plus pour les équipes de développement, Mailpit comme Hubble. L'API de Mailpit doit rester joignable par les vérifications, en authentification basique, depuis MGMT seulement. Version 7.15.5 au moins : Sophie a lu les deux avis critiques.

**Objectifs pédagogiques**
- Placer un mandataire d'authentification (*authentication proxy*) devant une application qui n'a pas de SSO, dans le cluster et sur une VM.
- Régler un client OIDC partagé par plusieurs instances : URI de retour exactes, PKCE, portées, groupes autorisés par instance.
- Protéger les cookies de session et la confiance dans les en-têtes `X-Forwarded-*`.
- Fermer les chemins de contournement (route directe, politique réseau, port de l'application).

**Prérequis** : M24-E08 (OpenTofu), M24-E10 ; M15-E26 (Hubble UI, `gw-par1`), M20-E13 (`charts-miroir`), M23-E14 (Pyroscope), M19-E03 (Mailpit).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Version | OAuth2 Proxy **7.15.5** ; chart `oauth2-proxy/oauth2-proxy` **10.7.1** (dépôt `https://oauth2-proxy.github.io/manifests`), image `quay.io/oauth2-proxy/oauth2-proxy:v7.15.5` par le cache Harbor `registry.par1.medisphere.internal/quay` |
| Client Keycloak | `oauth2-proxy` (confidentiel, flux standard seul, PKCE `S256`), fichier `tofu/clients-oauth2-proxy.tf` ; URI de retour `https://hubble.apps.par1.medisphere.internal/oauth2/callback`, `https://pyroscope.apps.par1.medisphere.internal/oauth2/callback`, `https://mon01.par1.medisphere.internal:8443/oauth2/callback` ; secret en Vault `critique` (`secrets/identite.yml` de `plateforme/ansible`, `keycloak_secrets_clients.oauth2_proxy`, rangé par `outils/ranger-secret-client.sh`, E11) |
| Dans le cluster | espace **`oauth2-proxy`** (créé par `plateforme/k8s`, PSA `restricted`, étiquette d'exposition de `gw-par1`) ; Application Argo CD **`oauth2-proxy`** (`plateforme/gitops`) avec **deux** releases : `oauth2-proxy-hubble` (amont `hubble-ui.kube-system:80`) et `oauth2-proxy-pyroscope` (amont `pyroscope.traces:4040`) ; valeurs et manifestes dans `oauth2-proxy/` de **`plateforme/identite`** ; Secret **`oauth2-proxy-oidc`** (clés `client-id`, `client-secret`, `cookie-secret`) par `outils/secrets-k8s.sh` |
| Groupes autorisés | Hubble : `plateforme-admins`, `plateforme`, `support` ; Pyroscope : les mêmes + `mediagenda`, `medidoc` ; Mailpit : `plateforme-admins`, `plateforme`, `support` |
| Routes | `hubble.apps.par1.medisphere.internal` (route actuelle `hubble-ui` dans `passerelles`, M15-E26, à remplacer) ; `pyroscope.apps.par1.medisphere.internal` (nouvelle) ; certificat joker de `gw-par1` |
| Sur `mon01` | rôle **`oauth2_proxy`** (nouveau, `plateforme/ansible`) : binaire épinglé par empreinte, unité **`oauth2-proxy-mailpit.service`**, HTTPS sur **8443** (certificat ACME), amont l'interface de Mailpit sur 8025 (HTTPS) ; Mailpit garde son authentification basique sur 8025 (compte `wb-checks` des vérifications) |
| Flux | `K8S_TRAV` et `mon01` → VIP `lb` 10.10.70.200:443 (`sso`) : déjà dans la matrice du bloc F ; `mon01` 8443 depuis MGMT et le VPN ; `mon01` 8025 depuis MGMT seulement |
| Réseau des pods | 10.240.0.0/16 (Envoy de la Gateway Cilium compris) |

**Travail demandé**

*A. Lire avant d'installer*

1. Lis la documentation d'OAuth2 Proxy : fournisseur `keycloak-oidc`, options de session et de cookie, configuration « alpha » (structurée), et les deux avis de sécurité critiques corrigés en 7.15.5. Note dans `~/m24/e18/notes.md` : les portées que `keycloak-oidc` demande par défaut (et ce que Keycloak répondra, sachant que notre portée de groupes s'appelle `groupes`), ce que garantit le préfixe de cookie `__Host-`, le rôle de `cookie_refresh`, ce que `reverse_proxy` fait croire et pourquoi 7.15.5 ajoute une liste de mandataires de confiance.

*B. Le client et le cluster*

2. Écris `tofu/clients-oauth2-proxy.tf` ; MR, plan, apply. Range le secret du client dans le Vault (`secrets/identite.yml`), sans l'afficher.
3. Ajoute le chart à `plateforme/charts-miroir` (empreinte relevée par toi) ; crée l'espace `oauth2-proxy` dans `plateforme/k8s` ; étends le composant `oauth2-proxy` de `secrets-k8s.sh` (secret du cookie : 32 caractères aléatoires, `openssl rand -hex 16`).
4. Écris les valeurs (communes, Hubble, Pyroscope) et les manifestes (racine MédiSphère pour joindre `sso`, politique d'entrée Cilium des pods d'OAuth2 Proxy) dans `plateforme/identite/oauth2-proxy/`, et l'Application dans `plateforme/gitops` ; adapte l'AppProject `plateforme`. Exigences : options **non secrètes** dans le fichier de configuration du chart, secrets par le Secret seulement ; cookie `__Host-` ; PKCE ; groupes autorisés par release ; X-Forwarded-* crus seulement depuis le réseau des pods ; deux réplicas ; HTTPRoute rendue par le chart.
5. Synchronise. Pour Pyroscope, ajoute à la politique `traces-pyroscope` (`plateforme/observabilite`) l'entrée depuis `oauth2-proxy-pyroscope`. Essaie `https://pyroscope.apps…` dans une fenêtre privée en `lucas.martin`.
6. Pour Hubble, la route du M15 est toujours là. Que se passe-t-il quand deux HTTPRoute réclament le même nom et le même chemin ? Remplace l'accès : politique `hubble-ui-entree` qui n'accepte plus que `oauth2-proxy-hubble`, suppression de la route et du ReferenceGrant du M15 (`kubectl delete -f`, puis MR). Essaie en `lucas.martin`, puis avec une personne d'un groupe non autorisé (`julien.petit`, si tu lui as donné un mot de passe) : quel code, quelle page ?

*C. Mailpit sur `mon01`*

> ⚠️ **Attention** : tu vas retirer le compte personnel de Mailpit et fermer 8025 au VPN. Garde une session SSH ouverte sur `mon01` et vérifie **avant** que `wb-checks` lit l'API depuis `adm01` (`lab/bin/check 19 03`). Retour arrière : remettre `host_vars/mon01/mailpit.yml` et `pare_feu_local.yml` de `main~1` et rejouer `playbooks/supervision.yml`.

7. Écris le rôle `oauth2_proxy` : archive vérifiée par empreinte avant extraction, binaire non modifiable par le service, une instance = une unité systemd durcie, secrets dans des fichiers 0640 lus par OAuth2 Proxy (jamais en argument, jamais dans l'unité), configuration structurée pour le serveur TLS, l'amont et le fournisseur. Mailpit exigeant son authentification basique, OAuth2 Proxy présentera à l'amont un compte technique `sso` de Mailpit, **après** avoir authentifié et autorisé la personne : trouve dans la documentation de la configuration structurée comment injecter un en-tête dont la valeur vient d'un fichier, et comment empêcher qu'un en-tête `Authorization` envoyé par le navigateur arrive à Mailpit.
8. Inventaire de `mon01` : certificat ACME de l'instance, compte `sso` dans Mailpit (et plus de compte de personne), nom `mon01…:8443` dans les noms autorisés de Mailpit (pourquoi ?), règles de `pare_feu_local`. Applique par le pipeline protégé.
9. Contrôle depuis `adm01` :
   ```
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' https://mon01.par1.medisphere.internal:8443/ | sed 's/state=[^&]*/state=…/'
   admin@adm01:~$ lab/bin/check 19 03
   ```

**Critères de réussite**
- [ ] Le client `oauth2-proxy` est confidentiel, en flux standard seul, PKCE `S256`, avec exactement les trois URI de retour.
- [ ] Dans `oauth2-proxy`, les deux releases (7.15.5) sont disponibles, à deux réplicas, synchronisées par Argo CD ; chacune n'autorise que ses groupes.
- [ ] `https://hubble.apps…`, `https://pyroscope.apps…` et `https://mon01…:8443` renvoient tout visiteur sans session vers le royaume `medisphere` (client `oauth2-proxy`, PKCE) ; plus aucune route ne mène directement à `hubble-ui`.
- [ ] Sur `mon01`, `oauth2-proxy-mailpit.service` est actif ; l'API de Mailpit répond toujours à `wb-checks` sur 8025 depuis MGMT.

**Vérification** : `lab/bin/check 24 18`

<details><summary>Indice 1</summary>

Keycloak refuse une demande d'autorisation qui contient une portée qu'il ne connaît pas (`invalid_scope`). Une portée **par défaut** du royaume s'applique sans être demandée : il suffit de ne pas demander celle qui n'existe pas.
</details>

<details><summary>Indice 2</summary>

La configuration structurée (`--alpha-config`) décrit `server`, `upstreamConfig`, `injectRequestHeaders` et `providers` ; les options du même domaine sont alors interdites dans le fichier historique (`--config`), qui garde les cookies et le reste. Une valeur d'en-tête peut venir d'une `secretSource` (`value`, `fromEnv`, `fromFile`). Lu depuis un fichier, un secret est pris **tel quel** : pas de retour à la ligne final, pas de décodage base64.
</details>

<details><summary>Indice 3</summary>

Deux HTTPRoute en conflit sur le même nom et le même chemin : la plus ancienne l'emporte (règles de précédence de la Gateway API). Mailpit vérifie l'en-tête `Host` contre sa liste de noms autorisés ; OAuth2 Proxy transmet celui du navigateur si on le lui demande.
</details>

**Pour aller plus loin** (facultatif) : mets Prometheus et Thanos Query (M21) derrière OAuth2 Proxy et mesure ce que deviennent les accès non humains (sonde du témoin de `mon01`, Grafana) ; compare avec l'authentification externe de la Gateway (filtre `ext_authz` d'Envoy). [OAuth2 Proxy : configuration](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview) · [Keycloak OIDC](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/keycloak_oidc) · [Configuration alpha](https://oauth2-proxy.github.io/oauth2-proxy/configuration/alpha-config) · [Avis de sécurité](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories)

---

### M24-E19 — Inscrire les VMs dans FreeIPA : SSSD, HBAC et sudo  `LAB` `★★★`

> **Ticket PLAT-2519** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Sur les VMs, tout le monde est encore `admin`, avec la même clé ou le même certificat d'astreinte. Inscris les VMs du socle et les nœuds du cluster dans l'annuaire : chacun se connecte sous son nom, l'annuaire dit qui peut entrer où (HBAC) et qui peut faire quoi en root (sudo). Sophie veut la règle « tout le monde partout » de FreeIPA désactivée, mais **après** avoir prouvé que personne n'en a besoin. Le compte local `admin` reste : c'est celui d'Ansible et notre bris de glace. Pas les passerelles : la bordure garde ses comptes locaux.

**Objectifs pédagogiques**
- Inscrire des hôtes Debian dans FreeIPA par Ansible, avec un mot de passe à usage unique, sans jamais donner le mot de passe d'`admin` aux clients.
- Comprendre ce que l'inscription change sur un hôte (Kerberos, SSSD, NSS, PAM, sudo) et les conflits avec les comptes locaux.
- Décrire en code des règles HBAC et sudo par groupes ; tester avant de couper (`ipa hbactest`, `sssctl`).
- Appliquer par vagues, sans jamais perdre l'accès `admin`.

**Prérequis** : M24-E03 (annuaire en code), M24-E02 (flux vers `ipa01`) ; M04 (rôles, pipeline protégé) ; M14 (nœuds du cluster).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Client | `freeipa-client` **4.12.4** (Debian 13), SSSD 2.10 ; serveur 4.13 : client plus ancien que le serveur, cas normal *(inscription Debian 13 → 4.13 non testée à la rédaction : signale tout écart)* |
| Rôle | **`freeipa_client`** (nouveau, `plateforme/ansible`), qui s'appuie sur le rôle **`ipaclient`** de `freeipa.ansible_freeipa` 1.17.0 ; playbook `playbooks/inscription-ipa.yml` |
| Hôtes inscrits | groupes `socle` et `k8s_par1`, **sauf** `role_routeur` (`gw01`, `gw02`) et `role_annuaire` (`ipa01`, qui est le serveur) |
| Inscription | mot de passe à usage unique généré sur `ipa01` pour **chaque** hôte (`ipa host-add --random` ou module `ipahost`, option `random`) ; le mot de passe d'`admin` de l'annuaire ne quitte jamais `ipa01` et le contrôleur |
| Réglages | `--mkhomedir` (dossier créé à la première connexion), pas de NTP (chrony vers les passerelles reste), pas de SSHFP, sshd **non** reconfiguré par FreeIPA (l'authentification SSH par certificat est l'objet d'E20) |
| Compte local | `admin` (UID local, clé d'Ansible, sudo sans mot de passe) : **même nom** qu'un compte de l'annuaire (`admin` de FreeIPA) |
| HBAC (dans `plateforme/identite/annuaire/hbac.yml`) | `hbac-plateforme` : groupes `plateforme-admins`, `plateforme` → tous les hôtes, service `sshd` ; `hbac-support` : groupe `support` → `mon01`, `nbx01`, service `sshd` ; règle `allow_all` **désactivée** (pas supprimée) ; `allow_systemd-user` inchangée |
| sudo (dans `annuaire/sudo.yml`) | `sudo-plateforme-admins` : groupe `plateforme-admins`, toutes commandes, tous hôtes, comme n'importe qui ; `sudo-plateforme` : groupe `plateforme`, consultation des journaux (`journalctl`, `systemctl status`) avec le groupe local `systemd-journal`, sans changer d'utilisateur |
| Vagues | 1 : `mon01` ; 2 : INFRA sans redondance (`ca01`, `git01`, `nbx01`, `s3-01`, `runner01`, `runner02`, `reg01`, `idp01`) ; 3 : `dns01` puis `dns02` ; 4 : `lb02` puis `lb01` ; 5 : `adm01` ; 6 : nœuds K8s **un par un** (contrôle puis travailleurs) |

**Travail demandé**

*A. Comprendre*

1. Lis le `README` du rôle `ipaclient` (variables `ipaclient_use_otp`, `ipaclient_otp`, `ipaclient_mkhomedir`, `ipaclient_no_ntp`, `ipaclient_no_sshd`, `ipaclient_servers`) et le guide FreeIPA sur HBAC et sudo. Sur une VM jetable ou sur `mon01` avant inscription, relève l'état de référence : `/etc/nsswitch.conf`, `pam-auth-update --list` (ou les fichiers `common-*`), `getent passwd admin`, `id admin`.
2. Le compte local `admin` et le compte `admin` de l'annuaire portent le même nom. Après inscription, quand sshd demande à PAM si `admin` a le droit d'entrer, qui répond ? Lis l'option `filter_users` de `sssd.conf` (section `[nss]`) et décide comment garantir que SSSD ne répond **jamais** pour `admin` (ni `root`). Note ta réponse dans `~/m24/e19/notes.md` : c'est le piège qui enferme dehors.

*B. L'inscription*

3. Écris le rôle `freeipa_client`. Exigences :
   - il refuse un autre système que Debian 13, un nom complet incohérent, une horloge non synchronisée, un hôte qui ne résout pas `_ldap._tcp` du domaine ;
   - si l'hôte est déjà inscrit, il ne fait rien (et ne génère surtout pas de mot de passe) ; sinon il fait générer un mot de passe à usage unique **sur `ipa01`** puis inscrit l'hôte avec ;
   - il pose le filtrage des comptes locaux dans SSSD et vérifie que `admin` et `root` restent résolus par les fichiers locaux ;
   - contrôles finaux : `sssd` actif, une personne de l'annuaire résolue, un ticket d'hôte obtenu par le keytab.
4. Écris `playbooks/inscription-ipa.yml` (un hôte à la fois, arrêt à la première erreur). Ajoute à la matrice des flux ce qui manquerait (INFRA, MGMT, VLAN 40, DMZ → `ipa01` 88, 464, 389, 636, 443 : E02).
   > ⚠️ **Attention** : l'inscription réécrit NSS et PAM de l'hôte. Pour chaque vague : une session SSH `admin` **ouverte** sur l'hôte, la console Proxmox à portée de main ; après inscription, **nouvelle** connexion `ssh admin@<hôte>` et `sudo -n true` avant de passer à l'hôte suivant. Retour arrière sur un hôte : `sudo ipa-client-install --uninstall -U` depuis la session ouverte (ou la console), puis `ipa host-del` côté annuaire.
5. Vague 1 (`mon01`). Contrôle sur l'hôte : `getent passwd lucas.martin`, `id lucas.martin`, `getent passwd admin`, `sudo klist -k`, `sudo sssctl domain-status par1.medisphere.internal`. Puis les vagues suivantes. Pour `lb01`/`lb02` (DMZ), les flux de la bordure existent-ils ?

*C. HBAC et sudo*

6. Écris `annuaire/hbac.yml` et `annuaire/sudo.yml` dans `plateforme/identite`, et les tâches correspondantes dans `annuaire.yml` (modules `ipahbacrule`, `ipasudocmd`, `ipasudocmdgroup`, `ipasudorule`). `allow_all` reste **activée** dans cette première MR. Applique.
7. Prouve avant de couper. Sur `ipa01` (ticket `admin` dans un cache temporaire), simule l'annuaire **sans** `allow_all` :
   ```
   [admin@ipa01 ~]$ ipa hbactest --user=lucas.martin --host=git01.par1.medisphere.internal --service=sshd \
   >   --rules=hbac-plateforme --rules=hbac-support
   [admin@ipa01 ~]$ ipa hbactest --user=nadia.roussel --host=git01.par1.medisphere.internal --service=sshd \
   >   --rules=hbac-plateforme --rules=hbac-support
   ```
   Fais une table : chaque groupe × trois hôtes représentatifs, résultat attendu, résultat obtenu. Qui perdrait un accès qu'il a aujourd'hui ?
8. Seconde MR : `allow_all` désactivée. Applique, puis sur `mon01` :
   ```
   admin@mon01:~$ sudo sssctl user-checks -a acct -s sshd lucas.martin
   admin@mon01:~$ sudo sssctl user-checks -a acct -s sshd julien.petit
   admin@mon01:~$ sudo sssctl user-checks -a acct -s sshd admin
   ```
   Interprète les trois réponses. **Nouvelle** connexion `ssh admin@mon01`, `ssh admin@git01`, `ssh admin@k8s-w01` : toutes passent-elles ? Que montre `sudo -l -U lucas.martin` sur `mon01` ?

**Critères de réussite**
- [ ] Les VMs du socle (hors `gw01`, `gw02`, `ipa01`) et les six nœuds de `k8s-par1` sont inscrits (entrée d'hôte dans l'annuaire, `/etc/ipa/default.conf`, SSSD actif) ; `gw01` et `gw02` ne le sont pas.
- [ ] Sur un hôte inscrit, une personne de l'annuaire est résolue par SSSD ; `admin` et `root` ne le sont jamais par SSSD ; la connexion `admin` par clé et `sudo -n` fonctionnent toujours.
- [ ] `allow_all` est désactivée ; `hbac-plateforme` et `hbac-support` sont actives avec le contenu du contexte technique ; `julien.petit` est refusé, `lucas.martin` accepté sur `mon01`.
- [ ] `sudo-plateforme-admins` et `sudo-plateforme` existent, actives, déclarées dans `annuaire/sudo.yml` sur `main`.

**Vérification** : `lab/bin/check 24 19`

<details><summary>Indice 1</summary>

Avec `ipaclient_use_otp`, le rôle de la collection fait générer le mot de passe à usage unique en se connectant à `ipaclient_servers[0]` **sous ce nom-là**, qui doit donc être joignable par Ansible tel quel. Générer toi-même le mot de passe sur l'hôte d'inventaire `ipa01` (module `ipahost`, `random: true`, `update_password: on_create`), puis le passer au rôle par `ipaclient_otp`, évite cette dépendance.
</details>

<details><summary>Indice 2</summary>

Sur Debian, `pam-auth-update` place `pam_sss` dans `common-account` avec `[default=bad success=ok user_unknown=ignore]` : tout dépend de ce que SSSD répond pour l'utilisateur. Si SSSD connaît un `admin`, il évalue HBAC pour lui. `filter_users` (section `[nss]`) fait répondre « inconnu » ; `getent -s sss passwd admin` doit alors ne rien rendre.
</details>

<details><summary>Indice 3</summary>

`journalctl` ouvre un afficheur paginé qui sait lancer un shell : en root, c'est un shell root. systemd active de lui-même le mode sûr de l'afficheur sous sudo, mais le plus simple est de ne pas devenir root du tout : `sudo -g systemd-journal journalctl …` lit le journal avec le seul groupe qui y donne accès. Dans FreeIPA, c'est un « RunAs group » de la règle.
</details>

**Pour aller plus loin** (facultatif) : remplace la clé SSH d'Ansible par un compte de service de l'annuaire avec une règle HBAC et sudo dédiée, et liste ce que deviendrait le bris de glace. [FreeIPA : *Configuring host-based access control*](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10) · [Rôle `ipaclient`](https://github.com/freeipa/ansible-freeipa/blob/master/roles/ipaclient/README.md) · [`sssd.conf(5)`](https://manpages.debian.org/trixie/sssd-common/sssd.conf.5.en.html)

---

### M24-E20 — SSH par certificats courts après SSO  `LAB` `★★★`

> **Ticket SEC-2520** — *De : Sophie Laurent* — *Copie : Nadia Roussel*
> Les VMs savent maintenant qui est qui, mais on entre toujours par `admin` avec un certificat que `ms-ssh-cert` signe pour qui connaît le mot de passe du provisioner. Je veux l'inverse : chacun entre **sous son nom**, avec un certificat de 16 heures que step-ca ne délivre qu'après une connexion au SSO (et donc l'OTP pour les administrateurs, E21). Personne ne choisit ses principaux. Le certificat expiré ne sert plus à rien, et l'annuaire garde le dernier mot (HBAC) : un certificat valide ne suffit pas pour entrer là où on n'a rien à faire.

**Objectifs pédagogiques**
- Configurer un provisioner OIDC de step-ca et le client Keycloak correspondant.
- Imposer les principaux d'un certificat par un gabarit, à partir d'une revendication du jeton.
- Faire accepter par sshd les certificats des personnes de l'annuaire sans fichier par personne (`AuthorizedPrincipalsCommand`).
- Prouver les refus : certificat expiré, principal étranger, personne sans règle HBAC.

**Prérequis** : M24-E19 ; M06-E19 et M06-E20 (CA SSH d'hôtes et d'utilisateurs, rôle `ssh_ca_utilisateur`), M06-E27 (politique de durées de step-ca).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| step-ca | 0.30 sur `ca01`, rôle `step_ca` (`group_vars/role_pki/step_ca.yml`) ; CA SSH d'utilisateurs déjà approuvée par les hôtes (M06-E20), certificats d'utilisateur **16 h** au plus |
| Provisioner | **`keycloak`**, type OIDC, configuration de découverte de l'émetteur `https://sso.par1.medisphere.internal/realms/medisphere` ; domaine de courriel `medisphere.internal` ; **aucun administrateur** ; adresse d'écoute de la CLI `127.0.0.1:10000` ; certificats X.509 refusés |
| Client Keycloak | **`step-ca`** (`tofu/clients-step-ca.tf`), flux standard seul, PKCE `S256`, URI de retour exacte `http://127.0.0.1:10000`. Confidentiel ou public : à toi de le décider en lisant ce que publie `https://ca01.par1.medisphere.internal/provisioners` |
| Principaux | **un seul** : `preferred_username` de l'ID token (l'identifiant de l'annuaire). Attention : les principaux par défaut d'un provisioner OIDC dérivent du **courriel** |
| sshd | rôle `ssh_ca_utilisateur` : `AuthorizedPrincipalsFile /etc/ssh/principaux/%u` (comptes locaux : `admin` → `admin`, `astreinte`) ; à compléter, sur les hôtes inscrits, par une commande qui accepte pour un compte **de l'annuaire** le principal égal à son nom, et rien pour un compte local |
| Poste | `step` sur `adm01` (`step ca bootstrap` fait au M06) ; navigateur de ton poste, port 10000 d'`adm01` atteint par un tunnel SSH (comme kubelogin en E16) |
| Personnes d'essai | toi (`plateforme-admins`), `lucas.martin` (`plateforme`), `julien.petit` (`mediagenda`, aucune règle HBAC : donne-lui un mot de passe provisoire comme en E03) |

**Travail demandé**

*A. Le client et le provisioner*

1. Lis la documentation du provisioner OIDC de step-ca (`clientID`, `clientSecret`, `configurationEndpoint`, `admins`, `domains`, `listenAddress`, gabarits SSH et la variable `.Token`). Puis :
   ```
   admin@adm01:~$ curl -s https://ca01.par1.medisphere.internal/provisioners | jq '.provisioners[] | {type, name}'
   ```
   Si le provisioner `keycloak` avait un `clientSecret`, qui pourrait le lire ? Décide du type de client Keycloak et justifie-le dans `~/m24/e20/notes.md`.
2. Écris `tofu/clients-step-ca.tf` ; MR, plan, apply.
3. Ajoute le provisioner `keycloak` à `step_ca_provisioners` : durée maximale 16 h, aucun administrateur, domaine `medisphere.internal`, adresse d'écoute fixe, un **gabarit SSH** qui fixe le seul principal à `preferred_username` (et échoue explicitement si la revendication manque), et un gabarit X.509 qui refuse tout certificat. MR, pipeline. Que se passerait-il, avec les principaux par défaut, pour `lucas.martin@medisphere.internal` ?

*B. sshd*

4. Étends le rôle `ssh_ca_utilisateur` : sur les hôtes inscrits seulement (une variable), une commande `AuthorizedPrincipalsCommand` (script en lecture seule, propriété de root, exécuté par un utilisateur sans droit) qui imprime le nom du compte **si et seulement si** SSSD le résout, et rien sinon. Relis dans `sshd_config(5)` ce qui se passe quand le fichier **et** la commande sont configurés. Applique par vagues (comme E19), `sshd -T` et une **nouvelle** connexion `admin` à chaque hôte.
   > ⚠️ **Attention** : une erreur dans la configuration de sshd coupe toutes les nouvelles connexions. Le rôle valide (`sshd -t`) avant de poser ; garde une session ouverte par hôte pendant la vague. Retour arrière : variable à `false`, rejeu du rôle.
5. Sur `mon01` : `/usr/local/sbin/<TON-SCRIPT> lucas.martin`, puis `admin`, puis `root`. Que doit afficher chacun ?

*C. Les certificats*

6. Tunnel du port 10000, puis :
   ```
   admin@adm01:~$ eval "$(ssh-agent)"
   admin@adm01:~$ step ssh login <MOI>@medisphere.internal --provisioner keycloak
   admin@adm01:~$ ssh-add -L | grep cert | step ssh inspect
   admin@adm01:~$ ssh <MOI>@mon01.par1.medisphere.internal 'id; pwd'
   ```
   Relève les principaux, la validité, l'identifiant de clé. Ton dossier personnel existe-t-il ? Essaie `ssh admin@mon01` **avec ce seul certificat** (agent vidé de toute autre clé) : refusé, et c'est voulu, pourquoi ?
7. Les refus. (a) Certificat de 5 minutes (`--not-after 5m`), connexion, attente, nouvelle connexion. (b) `julien.petit` (agent vidé, nouvelle connexion au SSO dans une fenêtre privée) vers `mon01`. Pour chaque cas, relève le message côté client et la ligne correspondante dans `journalctl -u ssh` de `mon01` : à quelle étape (certificat, principal, compte PAM) le refus a-t-il lieu ?
8. `ms-ssh-cert` (M06) signe toujours, par le provisioner `admin`, des certificats `admin`/`astreinte`. Que décides-tu de lui (garder pour le bris de glace, restreindre, retirer) ? Écris la décision et sa raison dans `docs/socle/acces-ssh.md` de `plateforme/medisphere` (crée le document s'il n'existe pas : qui entre comment, durée, bris de glace).

**Critères de réussite**
- [ ] Le client `step-ca` existe (PKCE `S256`, seule URI `http://127.0.0.1:10000`, sans *Direct Access Grants*).
- [ ] `ca01` publie un provisioner OIDC `keycloak` (client `step-ca`, émetteur du royaume `medisphere`, aucun administrateur, 16 h au plus, gabarit SSH qui fixe le principal à `preferred_username`).
- [ ] Sur les hôtes inscrits, sshd consulte la commande de principaux ; elle répond le nom pour une personne de l'annuaire et rien pour `admin` ou `root`.
- [ ] Le journal de `mon01` montre une connexion par certificat sous ton nom ; `julien.petit` est refusé au compte (HBAC).
- [ ] `docs/socle/acces-ssh.md` est sur `main`.

**Vérification** : `lab/bin/check 24 20`

<details><summary>Indice 1</summary>

La CLI `step` est le client OIDC : elle lit la configuration du provisioner sur `ca01` (secret compris), ouvre le navigateur, reçoit le code sur une adresse de bouclage et l'échange elle-même. step-ca vérifie ensuite l'ID token : signature, émetteur, **audience = clientID**, `azp`. La CLI envoie un défi PKCE.
</details>

<details><summary>Indice 2</summary>

Sans gabarit, les principaux d'un certificat OIDC viennent du courriel : partie locale « nettoyée » (les points sont **retirés**), partie locale brute, courriel complet. Dans un gabarit SSH de step-ca, `.Token` contient les revendications de l'ID token, et la fonction `fail` arrête l'émission avec un message.
</details>

<details><summary>Indice 3</summary>

sshd consulte d'abord `AuthorizedPrincipalsFile`, puis, s'il n'y a rien trouvé, `AuthorizedPrincipalsCommand` ; il refuse de démarrer si la commande n'a pas d'`AuthorizedPrincipalsCommandUser`. `getent -s sss passwd <compte>` n'interroge que SSSD.
</details>

**Pour aller plus loin** (facultatif) : faites porter au certificat l'extension `permit-port-forwarding` seulement pour `plateforme-admins` (gabarit et `.Token.groups`) ; mesurez ce que change une CA SSH sous HSM. [step-ca : *OIDC provisioner*](https://smallstep.com/docs/step-ca/provisioners/#oauthoidc-single-sign-on) · [*Templates*](https://smallstep.com/docs/step-ca/templates/) · [`sshd_config(5)`](https://man.openbsd.org/sshd_config)

---

### M24-E21 — Authentification forte : OTP obligatoire, WebAuthn en option  `LAB` `★★`

> **Ticket SEC-2521** — *De : Sophie Laurent* — *Copie : Claire Morel*
> Tout ce qui administre passe désormais par le SSO : console Argo CD, Proxmox, `kubectl`, SSH. Un mot de passe volé à un membre de `plateforme-admins`, c'est la plateforme entière. Second facteur **obligatoire** pour `plateforme-admins` et `securite`, enrôlement imposé à leur prochaine connexion. Pour les autres, je ne l'impose pas encore, mais ceux qui ont une clé de sécurité doivent pouvoir l'utiliser. Ni les comptes de service ni le bris de glace ne doivent pouvoir être bloqués par ce changement.

**Objectifs pédagogiques**
- Construire en code un flux d'authentification conditionnel de Keycloak (sous-flux, conditions, exécutions, liaison au royaume).
- Rattacher une exigence de sécurité à des **groupes** de l'annuaire par un rôle.
- Mesurer l'effet d'un second facteur sur les accès en ligne de commande (kubelogin, `step ssh login`) et sur les comptes non interactifs.

**Prérequis** : M24-E08 (royaume en code), M24-E04 (administrateurs de `master`), M24-E16 (kubelogin), M24-E20 (`step ssh login`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Fichier | `tofu/flux.tf` de `plateforme/identite` |
| Flux | **`navigateur-medisphere`**, même structure que `browser` (cookie, puis formulaire), écrit exécution par exécution ; lié comme flux de navigateur du royaume `medisphere` |
| Qui | rôle de royaume `second-facteur-obligatoire`, attribué aux **groupes** `plateforme-admins` et `securite` (importés de l'annuaire) |
| OTP | TOTP, réglages par défaut du royaume (6 chiffres, 30 s) ; applications : FreeOTP, Aegis, Google Authenticator… |
| WebAuthn | second facteur **volontaire** pour les autres personnes : demandé seulement à qui a enregistré une clé (console de compte) |
| Hors champ | royaume `master` (`<MOI>-admin` a déjà son OTP, `kc-secours` n'en a pas : E04) ; comptes de service (`client_credentials`) ; *Direct Access Grants* désactivés partout |

**Travail demandé**

*A. Comprendre les flux*

1. Dans la console (lecture seule), ouvre *Authentication* → `browser` du royaume `medisphere` : dessine l'arbre (sous-flux, exigences `ALTERNATIVE`, `REQUIRED`, `CONDITIONAL`). Liste les conditions disponibles : laquelle permet de viser un **groupe** ? Comment, à défaut, viser les membres d'un groupe ?
2. Lis dans la documentation du fournisseur les ressources `keycloak_authentication_flow`, `keycloak_authentication_subflow`, `keycloak_authentication_execution` (attribut `priority`), `keycloak_authentication_execution_config`, `keycloak_authentication_bindings`, `keycloak_role`, `keycloak_group_roles`, `keycloak_required_action`. Pourquoi ne pas utiliser `copy_from` ?

*B. Le flux en code*

3. Écris `tofu/flux.tf` : le rôle et son attribution aux deux groupes ; le flux (cookie `ALTERNATIVE` ; sous-flux de formulaires `ALTERNATIVE` avec identifiant et mot de passe `REQUIRED`, un sous-flux conditionnel OTP pour les porteurs du rôle, un sous-flux conditionnel WebAuthn pour les **autres** personnes qui ont une clé) ; la liaison au royaume **après** les exécutions ; les actions requises d'enrôlement activées sans être imposées à tous.
4. MR : relis le plan ligne à ligne. Combien d'objets, et lequel change le comportement pour tout le monde ?
   > ⚠️ **Attention** : la liaison du flux s'applique à **toutes** les connexions du royaume `medisphere`, donc à tous les services. Avant l'apply : une session ouverte dans la console d'administration (royaume `master`, `<MOI>-admin`), et une fenêtre privée prête pour l'essai. Retour arrière en une minute : dans la console, *Authentication* → `browser` → *Bind flow* → *Browser flow* ; puis MR qui rétablit le code. Le pipeline n'est pas touché (compte de service).
5. Apply, puis essais dans des fenêtres privées sur la console de compte (`/realms/medisphere/account/`) : `lucas.martin` (aucun second facteur), toi (enrôlement OTP imposé, puis code demandé). Relève dans *Events* du royaume (si les événements sont enregistrés) ou dans le journal de `idp01` ce qui distingue les deux connexions.

*C. Les effets*

6. `kubectl` : `kubectl oidc-login clean`, puis `kubectl --context k8s-par1-oidc get nodes`. Où l'OTP est-il demandé ? Combien de temps dure ensuite l'accès sans nouveau code, et de quoi cela dépend-il ? Même question pour `step ssh login`.
7. WebAuthn (facultatif si tu n'as pas de clé ou d'authentificateur de plateforme) : en `lucas.martin`, enregistre une clé dans la console de compte (*Account security* → *Signing in*), déconnecte-toi, reconnecte-toi.
8. Contrôle que rien de non interactif n'est bloqué : `lab/bin/check 24 05` (client `wb-checks`), un `tofu plan` du pipeline de `plateforme/identite`, et la connexion de `kc-secours` dans le royaume `master` (fenêtre privée). Note dans `~/m24/e21/notes.md` la liste des comptes qui n'ont **pas** de second facteur et pourquoi c'est acceptable (ou pas).

**Critères de réussite**
- [ ] Le flux de navigateur du royaume `medisphere` est `navigateur-medisphere`, décrit dans `tofu/flux.tf` sur `main` (plan vide).
- [ ] Le sous-flux conditionnel exige l'OTP pour le rôle `second-facteur-obligatoire`, porté par les groupes `plateforme-admins` et `securite` (et par eux seuls).
- [ ] Ton compte du royaume `medisphere` a un OTP enregistré ; aucune personne n'a l'enrôlement imposé par défaut.
- [ ] Aucun client du royaume n'a les *Direct Access Grants* activés.

**Vérification** : `lab/bin/check 24 21`

<details><summary>Indice 1</summary>

Keycloak 26.7 propose les conditions *user role*, *user configured*, *user attribute*, *client scope*, *credential*, *sub-flow executed* et *level of authentication* : aucune ne porte sur un groupe. Un rôle de royaume attribué à un groupe est **hérité** par ses membres, et la condition *user role* tient compte de cet héritage. Les membres d'un groupe importé de l'annuaire en `READ_ONLY` ne se changent pas dans Keycloak, ses rôles si.
</details>

<details><summary>Indice 2</summary>

Dans un sous-flux `CONDITIONAL`, toutes les conditions `REQUIRED` doivent être vraies pour que les exécutions suivantes s'appliquent ; une condition se règle par une configuration d'exécution (clés `condUserRole` et `negate` pour *user role*). Quand l'OTP est `REQUIRED` et que la personne n'en a pas, Keycloak lui impose l'action *Configure OTP*.
</details>

**Pour aller plus loin** (facultatif) : codes de récupération (*Recovery Authentication Codes*) pour les administrateurs ; politique d'OTP (algorithme, fenêtre) et son effet sur les applications mobiles ; niveaux d'authentification (LoA, `acr`) pour exiger l'OTP **par service** plutôt que par personne. [Keycloak : *Conditions in conditional flows*](https://www.keycloak.org/docs/latest/server_admin/#conditions-in-conditional-flows) · [*W3C Web Authentication*](https://www.keycloak.org/docs/latest/server_admin/#webauthn_server_administration_guide)

---

### M24-E22 — Revue : la configuration Keycloak du stagiaire  `REV` `★★`

> **Ticket PLAT-2522** — *De : Karim Benali*
> Lucas a ouvert la MR !41 sur `plateforme/identite` : un royaume `medisphere-recette` pour que l'équipe de Julien teste l'authentification de MédiAgenda et de MédiStat sans toucher au royaume de production. L'idée est bonne. Le code, je n'en suis pas sûr : il m'a dit « j'ai suivi les tutoriels et tout marche sur mon Keycloak d'essai ». Fais la revue avant moi, par écrit, comme si elle partait demain en production. Ce qui marche n'est pas forcément ce qui est sûr.

**Objectifs pédagogiques**
- Relire une configuration d'IdP en code et y trouver les défauts de sécurité et de fonctionnement.
- Classer les défauts par gravité et proposer pour chacun une correction précise.
- Distinguer ce qui est dangereux de ce qui est seulement inhabituel.

**Prérequis** : M24-E05 à M24-E08, M24-E21.
**Durée indicative** : 1 h 30.

**Contexte technique** : les fichiers de la MR sont dans [`ressources/M24-E22/`](../ressources/M24-E22/) : `README.md` (description de la MR par Lucas), `royaume-recette.tf`, `clients-recette.tf`. Ils s'ajoutent à `tofu/` (même fournisseur, même état). La recette de MédiAgenda n'est pas exposée sur Internet, mais elle est joignable de tout le réseau du lab, et ses données sont des copies **anonymisées** de la production.

**Travail demandé**

1. Lis les trois fichiers sans rien exécuter. Pour chaque défaut trouvé : fichier et ligne, ce qui est faux, ce qu'un attaquant (ou un incident) en tirerait concrètement, gravité (critique, majeure, mineure), correction exacte (attribut et valeur, ou objet à ajouter ou retirer).
2. Repère aussi ce qui **manque** (ce que le royaume `medisphere` a et que celui-ci n'a pas) et ce qui est inutile mais sans danger.
3. Une question de conception : un royaume de recette qui fédère le **même** annuaire que la production est-il une bonne idée ? Propose une alternative et ses conséquences.
4. Rédige la revue dans `~/m24/e22/revue-mr41.md`, sous la forme d'un commentaire de MR : un résumé (fusionnable ou non, et pourquoi), puis les défauts du plus grave au moins grave. Facultatif : applique le code sur un Keycloak jetable (`kc.sh start-dev` sur ton poste) pour **prouver** deux défauts.

**Critères de réussite**
- [ ] Au moins 10 défauts identifiés, chacun avec une conséquence concrète et une correction précise.
- [ ] Les trois défauts critiques sont en tête et expliqués de façon qu'un stagiaire comprenne le risque.
- [ ] La revue conclut clairement (fusion refusée ou acceptée sous conditions) et répond à la question de conception.

<details><summary>Indice 1</summary>

Relis chaque attribut contre ce que tu as fait (et pourquoi) en E05-E08 et E21 : flux autorisés, URI de retour, type de client, durées, mode de la fédération, secrets dans le code. Puis regarde d'où viennent les **groupes** dans les jetons : tous les services en déduisent les droits.
</details>

<details><summary>Indice 2</summary>

Cherche aussi les défauts **par omission** : une liste de portées par défaut remplace la liste du royaume pour ce client ; un attribut que Keycloak ignore pour un type de client donne un plan qui n'est jamais vide.
</details>

**Pour aller plus loin** (facultatif) : écris une règle de lint (Conftest/OPA sur `tofu show -json`, ou un script `jq`) qui refuse en CI les trois défauts les plus graves. [Keycloak : *Server Administration Guide*, chapitres *Managing OpenID Connect clients* et *Threat model mitigation*](https://www.keycloak.org/docs/latest/server_admin/) · [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700)

---

### M24-E23 — Arrivées, mobilités et départs  `RED` `★★`

> **Ticket SEC-2523** — *De : Sophie Laurent* — *Copie : Nadia Roussel, Claire Morel*
> L'auditeur HDS nous demandera deux choses : comment une personne obtient ses accès (et qui l'a décidé), et la preuve qu'un départ coupe **tout** en moins d'une heure. Pour InfoGér, il nous a fallu trois semaines. Écris les deux runbooks : RB-241 (arrivée), RB-242 (départ et mobilité). Ils doivent pouvoir être suivis par Nadia un vendredi à 17 h, sans toi, et produire des preuves que je peux montrer.

**Objectifs pédagogiques**
- Décrire le cycle de vie d'une identité de bout en bout, de l'annuaire à chaque service.
- Distinguer ce que le SSO coupe d'un coup de ce qu'il faut couper un par un (sessions, jetons, clés, comptes locaux).
- Rédiger des procédures exécutables, chronométrées, avec preuves et retour arrière.

**Prérequis** : M24-E10 à M24-E21 (tous les services branchés au palier 2).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Fichiers | `docs/securite/identite/runbooks/RB-241-arrivee.md` et `RB-242-depart-mobilite.md` de `plateforme/medisphere` |
| Source de vérité | `annuaire/personnes.yml` et `groupes.yml` de `plateforme/identite` (MR, job manuel protégé) ; un départ = `etat: disabled`, jamais une suppression |
| Ce qui suit l'annuaire seul | connexion à tous les services en SSO (liaison LDAP à chaque connexion) ; groupes dans les jetons ; HBAC et sudo des VMs (SSSD, avec son cache) |
| Ce qui a sa vie propre | sessions SSO de Keycloak (10 h) et sessions de chaque service ; jetons de rafraîchissement (kubelogin, Argo CD, Grafana) ; jetons personnels (GitLab, Grafana, Harbor, Argo CD) ; clés SSH et certificats SSH déjà émis (16 h) ; comptes GitLab (liaison OIDC, appartenances par `synchro-gitlab.py`, E11) ; ACL par utilisateur de PBS (E15) ; comptes de robot Harbor créés par une personne ; secrets qu'elle connaissait |
| Délais | arrivée : accès prêts le premier jour à 9 h ; départ : tout coupé en **moins de 60 minutes** après l'appel des RH (cible du mini-projet : 15 min) ; mobilité : anciens droits retirés le jour du changement |
| Outils | job `annuaire:appliquer` ; console d'administration de Keycloak (royaume `medisphere` : *Users* → *Sessions*) ; API GitLab ; `kubectl` ; `ipa` sur `ipa01` ; journaux dans Loki (locataire `audit`, M22) |

**Travail demandé**

1. Pour chaque service branché au palier 2 (GitLab, Grafana, Argo CD, Harbor, Proxmox VE, PBS, NetBox, Kubernetes, Hubble, Pyroscope, Mailpit, SSH, sudo), établis dans un tableau : comment une personne y obtient ses droits (groupe, synchronisation, attribution locale), ce qui reste actif après la désactivation dans l'annuaire, combien de temps, et comment le couper.
2. Rédige **RB-241** : déclencheur (demande RH et responsable, qui valide les groupes), prérequis, étapes (MR dans `personnes.yml` et `groupes.yml`, premier mot de passe, premier accès, enrôlement OTP si groupe concerné, droits qui ne découlent pas des groupes), contrôles, preuves conservées (MR, pipeline, événements), délais.
3. Rédige **RB-242** en trois parties : **départ normal** (planifié), **départ immédiat** (licenciement, compromission : la course contre la montre, chronométrée étape par étape, dans l'ordre qui ferme d'abord ce qui donne le plus de pouvoir), **mobilité** (changement d'équipe : retirer avant d'ajouter, sessions à fermer pour que les nouveaux groupes et surtout les **anciens** disparaissent des jetons). Pour chaque étape : commande ou écran, contrôle, preuve.
4. Ajoute à RB-242 la vérification finale : comment prouves-tu, une heure après, que la personne n'a plus aucun accès (liste de contrôles, requêtes LogQL sur le locataire `audit`, revue des jetons) ? Que mets-tu dans le ticket de clôture ?
5. Fais relire mentalement chaque runbook par Nadia : chaque commande est complète, chaque valeur à adapter est notée `<EN-MAJUSCULES>`, aucun secret n'apparaît, chaque étape dit quoi faire si elle échoue.

**Critères de réussite**
- [ ] RB-241 et RB-242 sont sur `main` de `plateforme/medisphere`, au format des runbooks du workbook (déclencheur, prérequis, étapes, contrôles, retour arrière, preuves).
- [ ] RB-242 traite les trois cas, avec un ordre justifié pour le départ immédiat et un temps cible par étape (total < 60 min).
- [ ] Les accès qui survivent à la désactivation dans l'annuaire (sessions, jetons de rafraîchissement, jetons personnels, certificats SSH, ACL locales) sont tous traités un par un.
- [ ] Chaque runbook dit quelles preuves sont conservées et où.

<details><summary>Indice 1</summary>

Désactiver la personne dans l'annuaire empêche toute **nouvelle** connexion par mot de passe, partout, immédiatement. Tout ce qui a été délivré **avant** (session SSO, session d'un service, jeton de rafraîchissement, jeton personnel, certificat SSH) vit jusqu'à son expiration ou jusqu'à ce qu'on le révoque. La question à poser pour chaque service : « qu'est-ce qu'elle a encore en poche ? ».
</details>

<details><summary>Indice 2</summary>

Dans Keycloak, fermer les sessions d'une personne (*Users* → la personne → *Sessions* → *Sign out*, ou l'API d'administration) invalide ses jetons de rafraîchissement : kubelogin, Argo CD, Grafana et OAuth2 Proxy ne pourront plus rafraîchir. Un certificat SSH ne se révoque pas (pas de liste de révocation consultée par sshd chez nous) : il expire, d'où les 16 h ; mais le compte, lui, est refusé par SSSD et HBAC dès que l'annuaire le dit (cache compris : `sss_cache`).
</details>

**Pour aller plus loin** (facultatif) : automatise la partie « départ immédiat » dans un job manuel protégé de `plateforme/identite` (sessions Keycloak, jetons GitLab, sessions Argo CD), qui produit lui-même le rapport de preuve ; c'est l'objet de la démonstration du mini-projet (M24-E46). [ANSSI : *Recommandations relatives à l'administration sécurisée des SI*](https://cyber.gouv.fr/publications/recommandations-relatives-ladministration-securisee-des-systemes-dinformation) · [Keycloak : *Managing user sessions*](https://www.keycloak.org/docs/latest/server_admin/#managing-user-sessions)
