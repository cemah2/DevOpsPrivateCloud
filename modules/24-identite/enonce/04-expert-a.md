# Module 24 — Palier 4 : Expert

L'identité de MédiSphère est en production : un annuaire FreeIPA source unique des personnes, Keycloak 26.8.1 sur `idp01` publié par `lb01`/`lb02`, un royaume `medisphere` entièrement en code, tous les services en SSO, l'OTP obligatoire pour les administrateurs, des sauvegardes restaurées, des alertes, des comptes de secours éprouvés. Nadia Roussel connaît la suite : « Avant, quand GitLab cassait, seul GitLab cassait. Maintenant, quand Keycloak tousse, tout le monde est dehors, et c'est moi qu'on appelle. » Une panne d'identité est rarement franche. Elle se présente comme un service qui refuse **une** personne, un groupe qui ne donne plus ses droits, un jeton « expiré » à peine né, un nouvel arrivant fantôme, ou pire, des droits **trop larges** dont personne ne se plaint. Karim Benali a préparé huit pannes de ce genre, et une astreinte qui en combine plusieurs. Puis tu ouvriras le capot (signatures, JWKS, sessions) et tu passeras les questions d'entretien sur les attaques.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres à l'identité :
- **Suis le jeton.** Une connexion SSO est une chaîne de maillons qui ont chacun leur journal : redirection vers le point d'autorisation (client, URI de redirection), formulaire (annuaire, mot de passe, OTP), retour du code, échange du code contre des jetons (secret du client, PKCE), vérification du jeton par le service (signature, émetteur, audience, `exp` et horloges), lecture des revendications (`groups`, `preferred_username`), puis **autorisation** dans le service (politique, RBAC, rôle). Pour chaque panne, situe le maillon qui casse avant de chercher pourquoi : l'événement de Keycloak (`LOGIN_ERROR`, `CODE_TO_TOKEN_ERROR`…), le journal du service, le jeton décodé (comme en M24-E07).
- **Authentification ou autorisation ?** `401 Unauthorized`, « Login failed », « Invalid parameter » disent que la personne n'est **pas reconnue** ; `403 Forbidden`, « permission denied », une interface vide disent qu'elle est reconnue mais **sans droit**. Ce ne sont pas les mêmes maillons, ni les mêmes journaux.
- **Le code fait foi, la dérive se mesure.** Le royaume est en OpenTofu (`plateforme/identite`), Argo CD est installé par Helmfile (`plateforme/k8s`), les fichiers des nœuds et les VMs par Ansible (`plateforme/ansible`), l'annuaire par le job `annuaire:appliquer` et le Vault `critique`. Les pannes de ce palier ne passent **pas** par une MR : comme un clic de trop dans une console, elles changent la réalité sans changer le code. `tofu plan`, `helmfile diff` et `ansible-playbook --check --diff` sont donc tes premiers outils de diagnostic, et la correction passe, chaque fois que le code est juste, par l'outil qui l'applique, pas par une retouche à la main.

> **Rappels** : tout se lance depuis `adm01`. Fournisseur : `https://sso.par1.medisphere.internal` (découverte `…/realms/medisphere/.well-known/openid-configuration`), console d'administration réservée à MGMT et au VPN. Événements : console → *Events* (utilisateurs) et *Admin events* (qui a changé quoi, avec quel client), et Loki locataire **`audit`** (`{service="keycloak"} | json | loggerName="org.keycloak.events"`, `{service="freeipa"}`, `{job="kubernetes-audit"}`). Métriques : `keycloak_user_events_total` (M24-E26), `node_*` des VMs et des nœuds (M21). Annuaire : `ipa` sur `ipa01` après `kinit` avec **ton** compte. Cluster : ton contexte OIDC `k8s-par1` ; `admin.conf` (Vault `critique`) est un **bris de glace** (RB-240 : il déclenche `BrisDeGlaceCluster`, c'est voulu).

## Règles du jeu des pannes (M24-E35 à M24-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 24 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (ta configuration diffère de celle du corrigé, ou un objet n'a pas le nom de la fiche), le script en essaie une autre.
- **Comment les pannes agissent.** Directement, comme une erreur humaine : l'API d'administration de Keycloak avec le client d'OpenTofu `svc-tofu-keycloak` (fichier `~/.config/workbook/keycloak-tofu.env` du M24-E08 : les événements d'administration montrent donc **ce client**, et c'est un indice en soi) ; l'annuaire en root sur `ipa01` ; les ConfigMaps d'Argo CD avec `admin.conf` ; des fichiers et des horloges sur les VMs. Avant chaque modification, l'objet est exporté (JSON sur `adm01`, copie dans `/var/lib/workbook/` sur la VM), pour l'annulation.
- **Ce que les pannes ne touchent jamais** (PLAN §4.12) : le royaume `master` ; ton compte (`<MOI>`, `<MOI>-admin`) ; les comptes de bris de glace (`kc-secours`, `admin` de l'annuaire, `root` de GitLab, `root@pam`, `admin.conf`, `admin` local des VMs, `admin` d'Argo CD) ; l'horloge de `pve01` et des passerelles ; `kube-system` ; `pbs01`. Aucune donnée n'est supprimée, sauf la personne fictive qu'une panne crée elle-même dans l'annuaire et retire à l'annulation.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 24 35`) : il doit être vert. Le script refuse de casser un fournisseur qui ne va pas bien (découverte muette ou émetteur différent, pas de jeton pour `svc-tofu-keycloak`, `yq` de mikefarah absent sur `adm01`) ou une VM qu'il ne joint pas en SSH.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les VMs, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause. Les événements de Keycloak, les journaux d'accès de l'annuaire, le journal d'audit du cluster et `metadata.managedFields` sont, eux, des outils de diagnostic légitimes : ils disent qui a changé quoi, et quand.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 24 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque l'astreinte M24-E43 et le mini-projet) : l'annulation ne revient jamais sur ta réparation.
- **Tiens un journal de diagnostic** par panne dans `docs/socle/journal/` de `~/medisphere` (`AAAA-MM-JJ-M24-EXX-<sujet>.md`, publié par MR) : heure, hypothèse, commande, résultat, conclusion, et qui a fait le changement fautif. Le runbook du palier est **RB-246** (`docs/securite/identite/runbooks/RB-246-sso-indisponible.md`, « SSO indisponible ou refusé ») : tu le **commences** en M24-E35, chaque panne y ajoute sa section, M24-E43 le termine (annonce, arbre de décision, post-mortem).
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre, ou en ouvrant plus grand qu'avant, en est un.

> ⚠️ **Les gestes interdits du palier**, sauf mention explicite dans ta démarche avec sa justification : modifier le royaume `master` ; désactiver `role_attribute_strict` de Grafana, mettre une `policy.default` dans Argo CD ou un rôle large par défaut « pour débloquer » ; retirer le préfixe `oidc:` ou la règle `azp` du fichier d'authentification du cluster ; désactiver la vérification TLS (magasin de confiance de Keycloak, `tls_skip_verify_insecure`, `--insecure-skip-tls-verify`) ; changer un mot de passe de compte système ailleurs que depuis le Vault `critique` ; régler une horloge à la main (`date -s`) comme correctif ; corriger à la main un objet décrit dans le code et en rester là.

> ⚠️ **Accès de secours** : certaines variantes coupent **ton** accès (kubectl par OIDC, connexion aux services). Avant chaque panne : ta session `<MOI>-admin` ouverte dans la console d'administration, `kc-secours` essayé (RB-240), `admin.conf` disponible depuis le Vault (`kubectl --kubeconfig <(…)`, jamais en fichier clair), une session SSH en `admin` sur `idp01`. Si tu dois utiliser un compte de secours pendant le diagnostic, c'est un vrai bris de glace : note-le au procès-verbal de RB-240.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Fournisseur | Keycloak **26.8.1** sur `idp01` (10.10.20.30), `hostname=https://sso.par1.medisphere.internal`, gestion sur 9000 ; royaume `medisphere` en OpenTofu (`plateforme/identite/tofu/`, apply manuel protégé sur `main`) ; durées : jeton d'accès (et ID token) **5 min**, session SSO 30 min d'inactivité / 10 h au plus (E27) ; événements stockés 30 jours et journalisés (E26) |
| Annuaire | FreeIPA sur `ipa01` (10.10.20.31) ; fédération `ipa01` (LDAPS, `READ_ONLY`, `svc-keycloak`, filtre `(!(uid=admin))`, synchronisation des changements toutes les 15 min) ; mappeur `groupes-ipa` (7 groupes) ; mot de passe de `svc-keycloak` au Vault `critique` (`annuaire/vault-critique.yml`) et dans Keycloak (`bind_credential_wo`) |
| Revendication `groups` | portée par défaut `groupes`, mappeur `groups`, **noms courts** (`plateforme-admins`), dans l'ID token, le jeton d'accès, userinfo et l'introspection |
| Secrets des clients | Vault `critique` `secrets/identite.yml` (`keycloak_secrets_clients.<client>`) ; `grafana` imposé par `client_secret_wo` + version (E29) ; poussés dans le cluster par `secrets-k8s.sh` |
| Cluster | `/etc/kubernetes/authentification/config.yaml` sur `k8s-cp01` à `k8s-cp03` (rôle `k8s_authentification`, `playbooks/k8s-api-fichiers.yml`) : audience `kubernetes`, règle `azp`, préfixes `oidc:` ; RBAC `rbac/oidc.yaml` ; rechargement à chaud du fichier |
| Argo CD | release Helmfile `argocd` de `plateforme/k8s` (non réconciliée par Argo CD) ; `argocd-rbac-cm` : `scopes: '[groups]'`, `policy.default` vide, `policy.csv` = `releases/argocd/policy.csv` testé par `outils/argocd-rbac-tests.sh` |
| Personnes du palier | les sept personnages et toi ; une arrivée fictive **`emma.durand`** (MédiDoc) créée par la panne M24-E37 et retirée à son annulation |
| Documentation | journaux `docs/socle/journal/AAAA-MM-JJ-M24-EXX-<sujet>.md` ; **RB-246** `docs/securite/identite/runbooks/RB-246-sso-indisponible.md` ; RB-240 (bris de glace), RB-241 (arrivées), RB-244 (rotations) |
| Tickets | INC-5135 à INC-5143 (pannes), SEC-/PLAT-25xx (xx = exercice) |
| Variables de `lab/lab.env` | `WB_M24_IDP`, `WB_M24_IPA`, `WB_M24_CP` (nœuds de contrôle), `WB_M24_KC_ADMIN_FILE` (secret de `svc-tofu-keycloak`, défaut `~/.config/workbook/keycloak-tofu.env`), `WB_M24_ARRIVEE` (défaut `emma.durand`), `WB_M24_VM_SSSD` (défaut `nbx01`) |

> **Mémoire** : aucune VM temporaire dans ce palier ; le profil reste celui du module (≈ 108 Go). M24-E44 lance seulement des outils sur `adm01`.

**Ordre conseillé** : E35 → E38 → E37 → E39 → E36 → E40 → E41 → E42 → E44 → E43 → E45. On commence par un seul client (E35) et par le temps (E38), qui touchent tous les services de la même façon ; puis l'annuaire (E37) et les groupes (E39), qui ne touchent que certaines personnes ; puis le cluster (E36), les VMs (E40), OAuth2 Proxy (E41) et le fournisseur lui-même (E42). Le passage sous le capot (E44) précède l'astreinte (E43) parce qu'il donne les gestes de mesure dont l'astreinte a besoin ; les questions (E45) ferment le palier, avant le mini-projet. **Durée totale indicative** : 12 à 15 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 24 XX`).

---

### M24-E35 — Panne : plus personne n'entre dans Grafana  `BF` `★★`

> **Ticket INC-5135** — *De : Julien Petit*
> Plus personne n'entre dans Grafana par le SSO depuis ce matin : ni moi, ni Nadia, ni Karim. *(Le détail de ce qu'on voit à l'écran s'affiche à l'injection.)* Hier tout marchait. Lucas dit avoir « juste regardé » la console de Keycloak. Les tableaux répondent toujours aux vérifications (compte de service `wb-checks`).

**Objectifs pédagogiques**
- Situer une connexion refusée sur la chaîne du SSO : redirection refusée **avant** le formulaire, échange du code refusé **après** le formulaire, ou connexion refusée **par le service** après un échange réussi.
- Lire les bons témoins : événements de Keycloak (`LOGIN_ERROR`, `CODE_TO_TOKEN_ERROR` et leur champ `error`), événements d'administration, journal de Grafana, configuration du client comparée au code.
- Comprendre pourquoi `tofu plan` voit certaines dérives et pas d'autres (arguments en écriture seule), et réparer par le code.
- Prévenir : alerte sur les erreurs de client dans le locataire `audit`, contrôle de dérive planifié du royaume.

**Prérequis** : M24-E12 (Grafana), M24-E26 (événements dans Loki), M24-E29 (secret imposé de `grafana`) ; `lab/bin/check 24 35` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : le client `grafana` est confidentiel, PKCE S256, une seule URI de redirection exacte (`https://grafana.apps.par1.medisphere.internal/login/generic_oauth`), portées par défaut `local.portees_clients_oidc` (dont `groupes`) ; son secret est **imposé** par OpenTofu depuis le Vault (`client_secret_wo`, `client_secret_wo_version`, E29) : ni l'état ni le plan ne le contiennent. Grafana lit `role_attribute_path` sur la revendication `groups` avec `role_attribute_strict: true` (E12). Les événements de Keycloak arrivent dans Loki, locataire `audit` ; ceux d'administration sont aussi dans la console (*Events* → *Admin events*).

**Injection** : `lab/bin/break 24 35` (3 variantes).

**Travail demandé**
1. Reproduis le symptôme dans une fenêtre privée, sans toucher à rien : à quel moment la connexion s'arrête-t-elle (avant le formulaire de Keycloak, après, ou dans Grafana) ? Note l'URL et le message exacts.
2. Trouve le maillon : l'événement de Keycloak correspondant à ta tentative (type, `clientId`, `error`) dans Loki ou dans la console ; le journal du pod Grafana (`logger=oauth…`, `authn…`) au même instant. Si Keycloak n'a rien refusé, décode le jeton qu'il a émis pour Grafana (*Clients* → `grafana` → *Client scopes* → *Evaluate*, avec une personne de l'annuaire) et compare ses revendications à ce que Grafana attend.
3. Trouve **qui** a changé **quoi** : *Admin events* (opération, chemin de la ressource, client utilisé, adresse IP, heure). Qu'est-ce que le client utilisé t'apprend sur la façon dont le changement a été fait ? Écris-le dans ton journal pour Sophie.
4. Corrige par le code : `tofu plan` de `plateforme/identite` montre-t-il la dérive ? Si oui, fais-la disparaître par le pipeline (pas dans la console). Si non, explique pourquoi dans ton journal et trouve la façon **prévue par RB-244** de remettre dans Keycloak la valeur qui fait foi. Prouve le retour : une connexion SSO réussie à Grafana, avec le bon rôle.
5. Préviens : (a) une alerte du ruler de Loki (locataire `audit`, `loki/regles/audit/identite.yaml`) sur les erreurs de **client** des services en SSO (secret refusé, redirection refusée), avec `gravite`, `equipe`, `runbook_url` ; (b) un **contrôle de dérive** planifié de `plateforme/identite` : un job qui lance `tofu plan` en mode code de sortie détaillé chaque nuit et échoue s'il y a une différence ; (c) commence **RB-246** avec la section « Un service refuse le retour du SSO ».

**Critères de réussite**
- [ ] Le client `grafana` a exactement son URI de redirection, la portée par défaut `groupes`, et Keycloak accepte la redirection ; le mappeur `groups` donne des noms courts.
- [ ] Une connexion SSO à Grafana a réussi (événement `CODE_TO_TOKEN` du client `grafana`) **après** la dernière erreur de ce client.
- [ ] L'alerte sur les erreurs de client est chargée par le ruler du locataire `audit` ; `.gitlab-ci.yml` de `plateforme/identite` contient le contrôle de dérive et un pipeline planifié a tourné sur `main` ; RB-246 contient sa section ; ton journal est publié ; la panne est close.

**Vérification** : `lab/bin/check 24 35`

<details><summary>Indice 1</summary>

Une page d'erreur de Keycloak **sans formulaire** : Keycloak a refusé la requête d'autorisation elle-même (client, URI de redirection, type de réponse). Un « Login failed » de Grafana **après** le formulaire : l'échange du code (secret, PKCE, code expiré) ou la lecture des revendications a échoué. Les événements de Keycloak tranchent : `{service="keycloak"} | json | loggerName="org.keycloak.events" |~ "grafana"` sur les dix dernières minutes.
</details>

<details><summary>Indice 2</summary>

`tofu plan` compare l'état et la réalité **pour ce qu'il sait lire**. Un argument `…_wo` n'est jamais relu (c'est le principe de l'écriture seule) : une dérive de ce secret est invisible au plan. Relis RB-244 §2 : ce qui pousse le secret du Vault vers Keycloak, c'est le changement de version. Et vérifie avant tout que le Vault et Grafana ont **la même** valeur (introspection d'un jeton bidon, comme en E29).
</details>

<details><summary>Indice 3</summary>

Le journal de Grafana dit `role_attribute_strict` quand la revendication attendue manque. Dans *Evaluate*, regarde l'onglet *Generated ID token* : la revendication `groups` est-elle là ? Puis *Client scopes* du client : une portée par défaut aurait-elle disparu ?
</details>

**Pour aller plus loin** : la 26.8 propose la **rotation des secrets de clients** (double secret pendant un recouvrement, par une politique de clients) : écris dans RB-244 ce qu'elle changerait à la variante « secret » de cette panne, et à quelle condition tu l'activerais. [Keycloak : *Client secret rotation*](https://www.keycloak.org/docs/latest/server_admin/#_client_secret_rotation) · [Keycloak : *Auditing and events*](https://www.keycloak.org/docs/latest/server_admin/#auditing-and-events) · [OpenTofu : *Ephemeral values and write-only arguments*](https://opentofu.org/docs/language/ephemeral/)

---

### M24-E36 — Panne : `kubectl` refuse les jetons  `BF` `★★★`

> **Ticket INC-5136** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection : selon le cas, `kubectl` répond « Unauthorized » ou « Forbidden », pour tout le monde ou pour certains seulement.)* Rien n'a changé de notre côté. Je dois livrer en recette avant midi.

**Objectifs pédagogiques**
- Distinguer, côté serveur d'API, un jeton **refusé** (401 : signature, émetteur, audience, règles de validation des revendications) d'une identité **sans droit** (403 : noms et groupes après correspondance, RBAC).
- Lire ce que voit kube-apiserver : `kubectl auth whoami`, journal de kube-apiserver, métriques `apiserver_authentication_jwt_authenticator_latency_seconds` et `apiserver_authentication_config_controller_*` ; comparer le fichier d'authentification aux trois nœuds et au rôle Ansible.
- Réparer **par le rôle**, sans redémarrer kube-apiserver, et prévenir la dérive des fichiers du plan de contrôle.

**Prérequis** : M24-E16, M24-E17 ; M14 (pods statiques, journal d'audit) ; `lab/bin/check 24 36` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : `--authentication-config=/etc/kubernetes/authentification/config.yaml` sur les trois nœuds de contrôle ; le **dossier** est monté dans le pod statique et kube-apiserver relit le fichier de lui-même (environ une minute). Un fichier refusé au rechargement (YAML ou CEL invalide, émetteur injoignable) laisse **l'ancienne** configuration active et s'inscrit dans le journal et dans `apiserver_authentication_config_controller_automatic_reloads_total{status="failure"}`. Un 401 ne dit **jamais** au client pourquoi : la raison n'est que dans le journal de kube-apiserver. `admin.conf` ne passe pas par OIDC.

**Injection** : `lab/bin/break 24 36` (3 variantes).

> ⚠️ **Attention** : selon la variante, **ton** `kubectl` par OIDC peut être refusé aussi. Le diagnostic côté serveur passe alors par SSH sur les nœuds de contrôle (compte local `admin`) et, si une lecture d'objet est indispensable, par `admin.conf` depuis le Vault : c'est un bris de glace (RB-240), `BrisDeGlaceCluster` sonnera, consigne-le.

**Travail demandé**
1. Classe le refus : `kubectl auth whoami` répond-il (authentifié) ou non (401) ? Pour qui : toi, Karim (`plateforme-admins`), Julien (`mediagenda`), Nadia (`support`) ? Une personne qui passe et une qui ne passe pas, c'est une information.
2. Lis le refus côté serveur : journal de kube-apiserver sur un nœud (`crictl logs` ou `/var/log/pods/…`), à la recherche de `Unable to authenticate the request` et de la raison ; métriques de rechargement et de l'authentificateur JWT de chaque serveur d'API dans la vue globale (kube-prometheus-stack collecte les trois kube-apiserver : pas besoin d'`admin.conf` pour les lire).
3. Compare le fichier des trois nœuds entre eux, et avec ce que produit le rôle (`--check --diff`). Qui a modifié le fichier, quand (date de modification, journal de la VM, journal d'audit) ?
4. Corrige par le rôle `k8s_authentification` (playbook `k8s-api-fichiers.yml`), constate le rechargement sur les **trois** nœuds (journal et métrique), puis l'accès de chacun des quatre profils (toi, Karim, Julien, Nadia) avec `kubectl auth can-i` ou leurs commandes habituelles.
5. Préviens : comment cette dérive aurait-elle été vue avant Julien ? Propose et mets en place **un** moyen (contrôle `--check` planifié du playbook sur le plan de contrôle, alerte sur `apiserver_authentication_config_controller_last_config_info` différent entre nœuds, ou alerte sur un taux d'échec de `apiserver_authentication_jwt_authenticator_latency_seconds_count{result="failure"}`). Complète **RB-246** avec la section « kubectl refuse les jetons ».

**Critères de réussite**
- [ ] Sur les trois nœuds de contrôle, le fichier d'authentification est **identique**, attend l'audience `kubernetes`, n'a que la règle `azp` comme règle de revendication, et préfixe utilisateurs et groupes par `oidc:` ; l'émetteur est joignable depuis chaque nœud.
- [ ] Les liaisons RBAC des groupes de l'annuaire visent toujours `oidc:<groupe>` (aucune « réparation » par le RBAC).
- [ ] RB-246 contient sa section ; ton journal est publié et cite la ligne du journal de kube-apiserver qui donne la raison ; la panne est close.

**Vérification** : `lab/bin/check 24 36`

<details><summary>Indice 1</summary>

`Forbidden` avec un nom d'utilisateur affiché (`User "oidc:julien.petit" cannot list …`) : l'authentification a réussi. Regarde les **groupes** que voit le serveur (`kubectl auth whoami`) et ceux que citent les liaisons (`kubectl get clusterrolebindings,rolebindings -A -o wide | grep oidc`). `Unauthorized` : la raison est dans le journal de kube-apiserver, pas chez toi.
</details>

<details><summary>Indice 2</summary>

Sur un nœud : `sudo crictl ps --name kube-apiserver -q` puis `sudo crictl logs --since 30m <ID> 2>&1 | grep -E 'authentication config|Unable to authenticate'`. Les métriques : `sum by (instance, result) (rate(apiserver_authentication_jwt_authenticator_latency_seconds_count[5m]))`, `apiserver_authentication_config_controller_automatic_reload_last_timestamp_seconds` et `apiserver_authentication_config_controller_last_config_info` (une empreinte `hash` par serveur) dans `http://prometheus.apps.par1.medisphere.internal:9090`. `sudo sha256sum /etc/kubernetes/authentification/config.yaml` sur les trois nœuds compare en une ligne.
</details>

<details><summary>Indice 3</summary>

`uv run ansible-playbook playbooks/k8s-api-fichiers.yml --check --diff` montre, nœud par nœud, ce que le rôle remettrait. Chaque règle de validation du fichier (sur les revendications ou sur l'utilisateur) est évaluée pour **chaque** jeton : quand elle échoue, ou quand son expression ne peut pas s'évaluer, le jeton est refusé et son `message` part dans le journal de kube-apiserver.
</details>

**Pour aller plus loin** : le fichier d'authentification accepte plusieurs émetteurs. Écris (sans l'appliquer) la configuration qui accepterait aussi les jetons d'un second royaume `medisphere-recette`, et liste ce qui doit **différer** entre les deux entrées pour qu'un jeton de recette ne devienne jamais administrateur de la production. [Kubernetes : *Structured authentication configuration*](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#using-authentication-configuration) · [Kubernetes : métriques du serveur d'API](https://kubernetes.io/docs/reference/instrumentation/metrics/)

---

### M24-E37 — Panne : les nouveaux arrivants n'existent pas  `BF` `★★`

> **Ticket INC-5137** — *De : Nadia Roussel*
> Emma Durand (`emma.durand`) arrive aujourd'hui dans l'équipe MédiDoc. Sa fiche est dans l'annuaire (groupe `medidoc`), j'ai vérifié. Mais elle ne peut rien faire : « elle n'existe pas » côté services, et je ne la trouve pas comme il faut dans Keycloak. Le prochain arrivant, c'est lundi. Les comptes des autres semblent marcher… je crois. Je n'ai pas tout essayé.

**Objectifs pédagogiques**
- Suivre une personne de l'annuaire jusqu'à un jeton : entrée LDAP (sous `cn=users,cn=accounts`), filtre de la fédération, liaison du compte `svc-keycloak`, synchronisation (périodique ou à la connexion), import, mappeur de groupes, revendication `groups`.
- Lire les deux côtés : journal de Keycloak et alerte `FederationLdapEnEchec` ; journal d'accès de 389-ds sur `ipa01` (liaisons, recherches, filtres, résultats `err=`).
- Mesurer l'étendue réelle d'une panne qu'on croit limitée à une personne.
- Réparer depuis la source de vérité (Vault `critique`, code OpenTofu), jamais en créant la personne à la main dans Keycloak.

**Prérequis** : M24-E03, M24-E06, M24-E23 (RB-241), M24-E26, M24-E29 (RB-244 §4) ; `lab/bin/check 24 37` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Contexte technique** : la fédération `ipa01` importe les personnes (*Import users*) et vérifie leur mot de passe par une liaison LDAP à chaque connexion ; la synchronisation des changements tourne toutes les 15 min, la complète une fois par jour ; les groupes sont **lus dans l'annuaire** à la demande (mappeur `groupes-ipa` en `READ_ONLY`, filtre des 7 groupes). Le journal d'accès de 389-ds est `/var/log/dirsrv/slapd-PAR1-MEDISPHERE-INTERNAL/access` (mis en tampon : quelques secondes de retard) et part aussi dans Loki (`{service="freeipa", fichier="access"}`). L'arrivée d'Emma est un raccourci du workbook : la panne l'a créée directement dans l'annuaire (titre « M24-E37 »), et l'annulation la retire.

**Injection** : `lab/bin/break 24 37` (3 variantes).

**Travail demandé**
1. Vérifie ce que dit Nadia, côté annuaire : `ipa user-show emma.durand --all` (date de création, groupes). Puis côté Keycloak : la console (*Users*, recherche) et l'API la trouvent-elles ? Avec quels groupes ?
2. Mesure l'étendue avant de réparer : une personne **ancienne** (Lucas, Julien) peut-elle encore se connecter (console de compte, fenêtre privée) ? Les membres de MédiDoc ont-ils encore leur groupe dans leurs jetons (*Client scopes* → *Evaluate*) ? `FederationLdapEnEchec` a-t-elle sonné ? Écris dans ton journal qui est **réellement** touché.
3. Trouve le maillon : *User federation* → `ipa01` (*Test connection*, *Test authentication*, filtre des personnes) et son mappeur `groupes-ipa` (filtre des groupes) ; le journal de Keycloak ; le journal d'accès de 389-ds (la liaison de `svc-keycloak` et son `err=`, ou la recherche que fait Keycloak et son filtre exact). Rejoue la recherche de Keycloak **avec ton propre compte** (`ldapsearch -Y GSSAPI` après `kinit`) pour prouver ce qu'elle renvoie.
4. Trouve qui a changé quoi (*Admin events* de Keycloak ; dans le journal d'accès de l'annuaire, une modification `MOD` d'un compte système et l'identité de la connexion qui l'a faite).
5. Corrige depuis la source : `tofu plan` pour ce que Keycloak a dérivé ; le Vault `critique` et la procédure de RB-244 §4 pour un mot de passe de compte système (jamais un nouveau mot de passe inventé dans la console). Puis une synchronisation des changements, et la preuve : Emma présente dans Keycloak, avec `medidoc` dans un jeton évalué ; une personne ancienne se connecte.
6. Préviens : quel contrôle d'arrivée manquait à RB-241 (une étape « vérifier dans Keycloak, avec ses groupes ») ? Le contrôle de dérive de M24-E35 aurait-il vu cette panne, et en combien de temps ? Complète **RB-246** avec la section « Une personne de l'annuaire n'existe pas dans Keycloak ».

**Critères de réussite**
- [ ] La fédération `ipa01` a le filtre des personnes et le filtre des groupes du code ; aucune erreur LDAP de Keycloak dans les 10 dernières minutes.
- [ ] Chaque personne active de l'annuaire créée depuis plus de 20 minutes existe dans Keycloak, avec les mêmes groupes (parmi les 7) que dans l'annuaire.
- [ ] RB-241 et RB-246 contiennent leur ajout ; ton journal est publié ; la panne est close.

**Vérification** : `lab/bin/check 24 37`

<details><summary>Indice 1</summary>

*Test authentication* échoue : c'est la liaison du compte de service. Il passe mais la personne reste introuvable : c'est la **recherche** (base, portée, filtre). La personne est là mais sans groupe : c'est le **mappeur**. Trois maillons, trois boutons de la console.
</details>

<details><summary>Indice 2</summary>

Sur `ipa01` : `sudo grep -E 'BIND dn="uid=svc-keycloak' …/access | tail` puis la ligne `RESULT` de la même connexion (`conn=` et `op=`) ; `err=49` = identifiants refusés. Les recherches de Keycloak sont des `SRCH base="cn=users,cn=accounts,…"` suivies de leur `filter=` : copie le filtre exact et rejoue-le avec `ldapsearch -Y GSSAPI -H ldaps://ipa01.par1.medisphere.internal -b cn=users,cn=accounts,dc=par1,dc=medisphere,dc=internal '<filtre>' uid createTimestamp`.
</details>

<details><summary>Indice 3</summary>

Une recherche de personne dans Keycloak va aussi chercher dans l'annuaire, avec le filtre de la fédération ; une personne déjà importée garde son identifiant local, mais ses groupes sont relus à chaque fois. Un attribut opérationnel (`createTimestamp`) ne s'affiche que si on le demande, mais il se filtre.
</details>

**Pour aller plus loin** : ajoute à l'outil de revue des accès (M24-E30) une section « écarts annuaire ↔ Keycloak » (personnes de l'annuaire absentes de Keycloak, personnes de Keycloak sans lien de fédération, groupes différents), et fais-la tourner chaque nuit plutôt que chaque mois. [Keycloak : *LDAP and Active Directory*](https://www.keycloak.org/docs/latest/server_admin/#_ldap) · [389 Directory Server : *Access log reference*](https://www.port389.org/docs/389ds/design/access-log-content.html)

---

### M24-E38 — Panne : « jeton expiré » à la première connexion  `BF` `★★`

> **Ticket INC-5138** — *De : Karim Benali*
> *(Le détail s'affiche à l'injection : selon le cas, tout est « expiré » dès la connexion, l'interface d'Argo CD renvoie au SSO en boucle, ou `kubectl` ne marche qu'une fois sur trois.)* Personne n'a rien déployé depuis hier soir. J'ai vidé mes cookies et le cache de kubelogin : pareil.

**Objectifs pédagogiques**
- Lire les dates d'un jeton (`iat`, `exp`, `auth_time`) et les comparer à l'horloge de **celui qui l'émet** et de **celui qui le vérifie**.
- Diagnostiquer une horloge décalée : `timedatectl`, `chronyc tracking`/`sources`, état du service de temps, métriques `node_time_seconds` et `node_timex_sync_status` ; comprendre l'effet sur l'OTP (TOTP) et sur un service derrière une répartition (une requête sur trois).
- Distinguer un problème d'horloge d'une durée de vie de jeton mal réglée.
- Prévenir : alerte d'horloge sur toutes les machines, service de temps garanti par Ansible.

**Prérequis** : M24-E07, M24-E16, M24-E27 ; M06 (chrony, passerelles source de temps) ; M21 (node_exporter des VMs) ; `lab/bin/check 24 38` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : `gw01`/`gw02` sont les sources de temps du lab (M06) ; chaque VM et chaque nœud les suit par chrony (`chrony` sur Debian, `chronyd` sur Rocky). Un jeton du royaume vit **5 minutes** (E27) ; un vérificateur tolère au plus une minute d'écart (souvent moins, parfois aucun). Le code OTP change toutes les 30 secondes et Keycloak n'accepte qu'une fenêtre étroite autour de **son** heure. La VIP de l'API du cluster répartit les requêtes entre les trois kube-apiserver. Les VMs et les nœuds exposent `node_time_seconds` et `node_timex_*` (collecteurs `time` et `timex` de node_exporter, actifs par défaut).

**Injection** : `lab/bin/break 24 38` (3 variantes).

**Travail demandé**
1. Récupère un jeton récent (connexion au compte, ou `kubectl oidc-login get-token` avec tes options du contexte `oidc`) et décode-le : `iat`, `exp`, `exp − iat`. Compare `iat` à l'heure d'`adm01` au moment de la connexion.
2. Selon ce que tu trouves : `exp − iat` anormal → réglages du royaume (et qui les a changés) ; `iat` décalé → horloge de l'**émetteur** ; jeton normal mais refusé par un seul vérificateur → horloge de **ce** vérificateur. Pour `kubectl`, interroge chaque serveur d'API directement (`kubectl --server https://<nœud>:6443 auth whoami`, avec l'autorité du cluster) et regarde le journal de celui qui refuse.
3. Mesure les horloges sans te fier à une seule machine : `date +%s` simultané sur `adm01`, `idp01` et les trois nœuds de contrôle ; `timedatectl` et `chronyc tracking` sur celle qui dérive ; dans la vue globale, `node_time_seconds - timestamp(node_time_seconds)` par instance. Le service de temps tourne-t-il ? Depuis quand est-il arrêté (`journalctl -u chrony`) ?
4. Corrige à la racine : relance la synchronisation (service démarré **et** activé ; lis la directive `makestep` de ta configuration pour savoir si l'heure fera un saut ou sera rattrapée lentement, et ce que `chronyc makestep` change), ou remets la durée du code (pipeline de `plateforme/identite`). Vérifie un nouveau jeton, un code OTP, `kubectl` dix fois de suite. Que deviennent les sessions et les jetons émis pendant la panne ?
5. Préviens : une règle d'alerte dans `plateforme/observabilite/regles/` sur l'écart d'horloge **et** sur la perte de synchronisation, pour les VMs **et** les nœuds (avec ses tests `promtool`), et la façon dont le rôle Ansible `base` (qui garantit déjà le service de temps) sera rejoué ou contrôlé régulièrement. Complète **RB-246** avec la section « Jeton expiré dès l'émission ».

**Critères de réussite**
- [ ] `idp01` et les trois nœuds de contrôle sont à moins de 5 s d'`adm01`, leur service de temps est actif et synchronisé.
- [ ] Le jeton d'accès du royaume vit 5 minutes.
- [ ] Une alerte chargée surveille l'écart d'horloge ou la synchronisation des machines ; RB-246 contient sa section ; ton journal est publié ; la panne est close.

**Vérification** : `lab/bin/check 24 38`

<details><summary>Indice 1</summary>

Un jeton dont `exp` est **déjà** dans le passé au moment où tu le reçois a été émis par une machine en retard. Un jeton dont `exp − iat` vaut quelques secondes a été émis avec un mauvais réglage. Un jeton normal refusé « une fois sur trois » est vérifié par une machine en avance.
</details>

<details><summary>Indice 2</summary>

`timedatectl` : `System clock synchronized: no` et `NTP service: inactive`. `chronyc tracking` répond `506 Cannot talk to daemon` quand le service est arrêté. Dans la vue globale : `abs(node_time_seconds - timestamp(node_time_seconds)) > 30` ; et `min_over_time(node_timex_sync_status[5m]) == 0`.
</details>

**Pour aller plus loin** : kube-prometheus-stack fournit déjà `NodeClockNotSynchronising` et `NodeClockSkewDetected` pour les nœuds du cluster : ont-elles sonné pendant la variante qui touche un nœud de contrôle, au bout de combien de temps, et vers qui ? Pourquoi ne couvrent-elles pas `idp01` ? [chrony : *chronyc*](https://chrony-project.org/doc/latest/chronyc.html) · [RFC 6238 (TOTP)](https://datatracker.ietf.org/doc/html/rfc6238) · [RFC 7519 §4.1.4 (`exp`)](https://datatracker.ietf.org/doc/html/rfc7519#section-4.1.4)

---

### M24-E39 — Panne : les droits d'Argo CD sont faux  `BF` `★★★`

> **Ticket INC-5139** — *De : Julien Petit, Sophie Laurent ou Karim Benali*
> *(Le détail s'affiche à l'injection : selon le cas, quelqu'un ne voit plus rien, ou au contraire quelqu'un voit un bouton qu'il ne devrait pas voir.)* Lucas a « aidé » quelqu'un sur Argo CD hier en fin de journée.

**Objectifs pédagogiques**
- Remonter une décision d'autorisation d'Argo CD : revendication `groups` du jeton, `scopes` de la politique, lignes `g` et `p` de `policy.csv`, `policy.default`, rôles de projet.
- Tester une décision sans la personne : `argocd account get-user-info`, `argocd account can-i`, `argocd admin settings rbac can … --namespace argocd` sur la configuration **en place** contre `--policy-file` sur celle du dépôt.
- Mesurer une dérive de la couche de base (`helmfile diff`, `managedFields`, journal d'audit) et, quand elle a donné **trop** de droits, ce qu'il faut vérifier après coup.
- Distinguer une panne d'Argo CD d'une panne de la revendication `groups` qui touche **tous** les services.

**Prérequis** : M24-E13, M24-E17 ; M20-E24 (politique RBAC et ses tests), M20-E03 (Helmfile d'Argo CD) ; M24-E28 (alerte `BrisDeGlaceCluster`) ; `lab/bin/check 24 39` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : Argo CD n'est pas réconcilié par lui-même : sa configuration vient de la release Helmfile `argocd` (`plateforme/k8s`), et une modification à la main de `argocd-cm` ou `argocd-rbac-cm` reste en place jusqu'au prochain `helmfile apply` ; Argo CD relit `argocd-rbac-cm` à chaud. `scopes` dit **quelles revendications** du jeton servent de sujets pour les lignes `g` ; `policy.default` est le rôle de **tout** utilisateur authentifié. La revendication `groups` est fabriquée par le mappeur `groups` de la portée `groupes`, partagée par tous les clients du royaume.

**Injection** : `lab/bin/break 24 39` (4 variantes).

**Travail demandé**
1. Reproduis avec les personnes concernées (ou avec toi si tu es concerné) : `argocd account get-user-info` (groupes vus par Argo CD), `argocd account can-i <action> applications <projet>/<application>`. Le problème est-il « trop peu » ou « trop » de droits ? Pour qui ?
2. Rejoue la décision pour chaque groupe, d'abord avec la configuration **en place** (`argocd admin settings rbac can <groupe> … --namespace argocd`), puis avec celle du dépôt (`--policy-file releases/argocd/policy.csv`, `--default-role`, `--scopes`) : où divergent-elles ? Lance aussi `outils/argocd-rbac-tests.sh` : qu'est-ce qu'il voit, qu'est-ce qu'il ne voit pas ?
3. Si la configuration d'Argo CD est identique au dépôt, remonte au jeton : les groupes ont-ils la forme attendue ? D'autres services (Grafana, `kubectl auth whoami`) voient-ils la même chose ?
4. Trouve l'origine : `helmfile -e par1 -l composant=argocd diff`, `metadata.managedFields` de la ConfigMap (gestionnaire, heure), journal d'audit du cluster (`{job="kubernetes-audit"}` : utilisateur, verbe, objet), `BrisDeGlaceCluster` ; ou *Admin events* de Keycloak.
5. Corrige par le code (`helmfile apply` après `diff`, ou pipeline de `plateforme/identite`). Si des droits ont été **trop larges**, établis la fenêtre (début, fin) et ce qui a été fait pendant : opérations d'Argo CD sur les Applications (historique, événements), par qui. Écris-le pour Sophie.
6. Préviens : une alerte du ruler du locataire `audit` sur toute écriture dans `argocd-cm` ou `argocd-rbac-cm` (le seul chemin légitime est `helmfile apply`, rare et annoncé), un contrôle de dérive planifié de la release `argocd` (`helmfile diff --detailed-exitcode`, M17-E10), et un cas de plus dans `rbac-tests.txt` si la variante le justifie. Complète **RB-246** avec la section « Droits faux dans un service ».

**Critères de réussite**
- [ ] `argocd-rbac-cm` : `scopes` contient `groups`, `policy.default` est vide, `policy.csv` est identique (hors commentaires et lignes vides) à `releases/argocd/policy.csv` de `main`, et seul `role:plateforme-admin` hérite de `role:admin`.
- [ ] Le mappeur `groups` de la portée `groupes` donne des noms courts.
- [ ] Une alerte du locataire `audit` surveille les écritures dans la configuration d'Argo CD ; le dernier pipeline de `main` de `plateforme/k8s` est vert ; RB-246 contient sa section ; ton journal est publié ; la panne est close.

**Vérification** : `lab/bin/check 24 39`

<details><summary>Indice 1</summary>

`argocd account get-user-info` affiche les groupes **tels qu'Argo CD les a lus dans le jeton**. Si les groupes sont justes et les droits faux, c'est la politique ; si les groupes ont une forme inattendue, c'est le jeton, donc Keycloak, donc probablement tous les services.
</details>

<details><summary>Indice 2</summary>

`kubectl -n argocd get cm argocd-rbac-cm -o yaml --show-managed-fields` : un gestionnaire `kubectl-patch` ou `kubectl-edit` à côté de `helm` dit qu'une main est passée après Helmfile, et à quelle heure. Le journal d'audit dit avec quelle identité.
</details>

<details><summary>Indice 3</summary>

`argocd admin settings rbac can` accepte `--policy-file`, `--default-role` et `--scopes` pour évaluer une politique **hors** du cluster, et `--namespace argocd` pour évaluer celle qui est **en place** : la même question posée aux deux dit si la panne est une dérive. Pour un excès de droits, l'historique de chaque Application (`argocd app history`) et les événements `kubectl -n argocd get events --field-selector involvedObject.kind=Application` disent qui a synchronisé ou supprimé quoi.
</details>

**Pour aller plus loin** : `policy.matchMode: glob` (défaut) contre `regex` : écris une ligne `g` qui, mal écrite, donnerait des droits à des groupes que tu n'avais pas prévus, et le test de `rbac-tests.txt` qui l'attraperait. [Argo CD : *RBAC Configuration*](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/) · [Argo CD : `argocd admin settings rbac can`](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd_admin_settings_rbac_can/)

---
