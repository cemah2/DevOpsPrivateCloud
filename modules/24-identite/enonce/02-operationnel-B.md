# Module 24 — Palier 2 : Opérationnel

Le palier 1 a construit les fondations : l'annuaire FreeIPA de `ipa01` et sa CA subordonnée, les personnes et les groupes en code, Keycloak publié en `https://sso.par1.medisphere.internal`, le royaume `medisphere` fédéré à l'annuaire et repris dans OpenTofu, un flux OIDC déroulé à la main. Aucun service ne s'en sert encore. Ce palier traite les **tickets du quotidien** d'une équipe qui branche une identité centrale : écrire d'abord le **modèle d'autorisation** (qui a droit à quoi, par quel groupe), puis brancher en SSO un service après l'autre (GitLab, Grafana, Argo CD, Harbor, Proxmox VE, PBS, NetBox, le cluster par `kubectl`), mettre **OAuth2 Proxy** devant les interfaces qui ne savent pas le faire, inscrire les VMs dans l'annuaire (SSSD, HBAC, sudo), remplacer les clés SSH éternelles par des certificats de 16 h, imposer l'**OTP** aux administrateurs, relire la configuration d'un stagiaire et écrire les procédures d'arrivée et de départ. À chaque service, la même discipline : son compte de bris de glace essayé **avant**, le client OIDC en code, les droits par groupe, les comptes locaux des personnes retirés **après** le test.

> **Rappels du module** (introduction) : un accès de secours ouvert **et essayé** avant tout changement d'authentification, et une session d'administration déjà ouverte qu'on ne ferme pas pendant le changement ; aucun secret sur une ligne de commande (`ps`), dans Git en clair ou dans un compte rendu ; l'annuaire est la seule source des personnes et des groupes ; plus rien à la main dans le royaume `medisphere` : tout client OIDC, toute portée, tout flux est une MR de `plateforme/identite` (`tofu/`), appliquée par le job manuel protégé. Les VMs se configurent par Ansible (`plateforme/ansible`, clone `~/src/ansible`), le cluster par Helmfile (couche de base, `plateforme/k8s`) ou Argo CD (le reste), tout flux réseau par le rôle `pare_feu` (`group_vars/role_routeur/pare_feu.yml`) et `docs/socle/matrice-flux.md`.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Émetteur OIDC | `https://sso.par1.medisphere.internal/realms/medisphere` (découverte : `…/.well-known/openid-configuration`) ; Keycloak **26.7.5** jusqu'au M24-E33 ; tout client joint `sso` par la VIP `lb` 10.10.70.200:443 (un seul émetteur pour tous) |
| Revendication de groupes | `groups`, **noms courts** (`plateforme-admins`, jamais `/plateforme-admins`), portée par défaut `groupes` du royaume : présente dans l'ID token, le jeton d'accès et userinfo de tout client créé **après** E06 ; aucun client ne demande une portée nommée `groups` (elle n'existe pas) |
| Groupes | `plateforme-admins` (`<MOI>`, Karim), `plateforme` (`<MOI>`, Karim, Lucas), `mediagenda` (Julien), `medidoc` (vide), `securite` (Sophie), `support` (Nadia), `direction` (Claire) ; droits par service : `docs/securite/identite/modele-autorisation.md` (E10) |
| Clients OIDC (`tofu/clients-<service>.tf`) | confidentiels : `gitlab` (E11), `grafana` (E12), `argocd` (E13), `harbor` (E14), `proxmox`, `pbs`, `netbox` (E15), `oauth2-proxy` (E18), `step-ca` (E20) ; publics avec PKCE `S256` : `argocd-cli` (E13), `kubernetes` (E16). Pour tous : flux standard seul (ni implicite, ni *Direct Access Grants*), URI de redirection **exactes** (aucun joker), `full_scope_allowed = false`, PKCE `S256` exigé dès que le service sait le faire |
| Secrets des clients | générés par Keycloak à la création, rangés **sans être affichés** par `plateforme/identite/outils/ranger-secret-client.sh <client>` dans l'Ansible Vault `critique` **`secrets/identite.yml` de `plateforme/ansible`**, clé `keycloak_secrets_clients.<client>` (tiret du nom de client remplacé par `_` : `oauth2_proxy`, `step_ca`) ; seule source pour les VMs (Ansible), les états OpenTofu (variables éphémères) et le cluster |
| Secrets dans le cluster | composant **`identite`** de `plateforme/k8s/outils/secrets-k8s.sh` (Vault lu dans `~/src/ansible/secrets/identite.yml`, E12) : `supervision/grafana-oidc` (E12), `argocd/argocd-oidc` (E13), `oauth2-proxy/oauth2-proxy-oidc` (E18) |
| Bris de glace (à essayer avant chaque bascule) | GitLab `root` ; Grafana `admin` (basique, API) ; Argo CD `admin` désactivé, réactivable par Helmfile, et `admin.conf` ; Harbor `admin` (local, reste permis en mode OIDC) ; Proxmox `root@pam`, PBS `root@pam` ; NetBox `admin` (formulaire local conservé) ; cluster `admin.conf` (Vault `critique`) ; VMs : compte local `admin` (clé SSH d'`adm01`) ; Keycloak `kc-secours` ; annuaire `admin` |
| Cluster (E16-E17) | `/etc/kubernetes/authentification/config.yaml` (`AuthenticationConfiguration` `apiserver.config.k8s.io/v1`, audience `kubernetes`, préfixes `oidc:`) posé par le rôle **`k8s_authentification`** (`playbooks/k8s-api-fichiers.yml`), option `--authentication-config` par `cluster/kubeadm-config.yaml` et `outils/reconfigurer-apiserver.sh` (M14-E27), **un nœud de contrôle à la fois** ; kubelogin 1.36 (`kubectl oidc-login`, krew) sur `adm01`, contexte **`k8s-par1-oidc`** (utilisateur `oidc`) ; RBAC `plateforme/k8s/rbac/oidc.yaml` (E17) ; ClusterRole agrégée `wb-checks-securite` (E16) |
| OAuth2 Proxy (E18) | 7.15.5, espace `oauth2-proxy`, releases `oauth2-proxy-hubble` et `oauth2-proxy-pyroscope` (Application Argo CD `oauth2-proxy`, chart recopié dans Harbor) ; `mon01` : unité `oauth2-proxy-mailpit.service`, écoute 8443 |
| VMs (E19-E20) | rôle `freeipa_client` ; règles HBAC `hbac-plateforme`, `hbac-support`, `allow_all` désactivée ; sudo `sudo-plateforme-admins`, `sudo-plateforme` ; provisioner OIDC `keycloak` de step-ca, certificats utilisateur de 16 h |
| MFA (E21) | flux `navigateur-medisphere` : OTP obligatoire pour `plateforme-admins` et `securite`, jamais pour `kc-secours` ni les comptes de service |
| Documentation | `docs/securite/identite/` de `plateforme/medisphere` : `modele-autorisation.md` (E10), `runbooks/RB-241-arrivee.md`, `RB-242-depart-mobilite.md` (E23) ; journaux de bascule dans `docs/socle/journal/` (VMs) ou `docs/kubernetes/journal/` (cluster) |
| Travail personnel | `~/m24/eXX/` sur `adm01` (non versionné, **sans secret**) ; navigateur sur ton poste par le VPN ; pour les CLI qui attendent une redirection sur `localhost` (kubelogin, `argocd login --sso`), un tunnel SSH depuis ton poste (`ssh -L 8000:127.0.0.1:8000 …`) |
| Vérifications | `lab/bin/check 24 XX` : API du royaume par `wb-checks`, GitLab, Grafana (compte de service Viewer), cluster (`wb-checks`), Harbor (robot), SSH en consultation sur `pve01`, `pbs01`, `nbx01` et les nœuds de contrôle |

> 💡 **Un service à la fois, toujours dans le même ordre.** (1) Essayer le compte de bris de glace du service et garder une session d'administration ouverte ; (2) MR dans `plateforme/identite` : le client OIDC ; (3) ranger son secret ; (4) configurer le service (son propre dépôt ou outil) ; (5) tester avec **deux** personnes de groupes différents (toi et `lucas.martin`) ; (6) seulement ensuite, retirer les comptes locaux des personnes ; (7) consigner la bascule (journal, matrice de flux). Les mots de passe des personnages autres que toi et Lucas n'ont jamais été posés (E03) : leurs droits se vérifient par la configuration et par les checks, pas en se connectant à leur place.

> ⚠️ **Mémoire.** Le palier n'ajoute aucune VM. Il redémarre les serveurs d'API du cluster un par un (E16) et ajoute quelques pods (OAuth2 Proxy, E18) : vérifie `free -g` sur `pve01` avant E16, et n'enchaîne pas E16 avec une autre opération sur le plan de contrôle.

Durée indicative du palier : 30 à 36 heures. Ordre conseillé :

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
| Rôles voulus | `plateforme-admins` → *Grafana Admin* (serveur) et Admin de l'organisation principale ; `plateforme`, `support` → Editor ; toute autre personne de l'annuaire → Viewer ; organisation « Sécurité » : `securite` Editor, `plateforme-admins`, `support`, `direction` Viewer |
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

`role_attribute_path` est une expression JMESPath évaluée sur l'ID token puis userinfo : `contains(groups[*], 'plateforme-admins') && 'GrafanaAdmin' || …`. Avec `role_attribute_strict = true`, une expression qui ne donne rien (revendication absente) **refuse** la connexion au lieu de donner Viewer : c'est ce qu'on veut si la portée `groupes` disparaît un jour.
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
