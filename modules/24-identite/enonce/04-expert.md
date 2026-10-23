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
| Variables de `lab/lab.env` | `WB_M24_IDP`, `WB_M24_IPA`, `WB_M24_CP` (nœuds de contrôle), `WB_M24_LB` (répartiteurs), `WB_M24_MON01`, `WB_M24_KC_ADMIN_FILE` (secret de `svc-tofu-keycloak`, défaut `~/.config/workbook/keycloak-tofu.env`), `WB_M24_ARRIVEE` (défaut `emma.durand`), `WB_M24_VM_SSSD` (défaut `nbx01`) ; les chemins des fichiers sur les VMs ont aussi leur variable (liste dans `lab/lab.env.example`) si ton lab diffère du corrigé |

> **Mémoire** : aucune VM temporaire dans ce palier ; le profil reste celui du module (≈ 107 Go). M24-E44 lance seulement des outils sur `adm01`.

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

### M24-E40 — Panne : SSH et sudo refusés sur les VMs  `BF` `★★★`

> **Ticket INC-5140** — *De : Nadia Roussel, Lucas Martin ou Karim Benali*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, une personne n'entre plus sur certaines VMs alors que son certificat est valable, ou elle entre mais `sudo` lui est refusé partout, ou une seule VM ne connaît plus personne, ou plus aucun certificat issu du SSO n'est accepté.)* Le compte local `admin` passe toujours.

**Objectifs pédagogiques**
- Découper une connexion SSH par certificat en étapes et savoir laquelle refuse : signature du certificat (step-ca), principal (sshd, `AuthorizedPrincipalsCommand`), compte (NSS, SSSD), accès (PAM *account*, HBAC), élévation (sudo, règles de l'annuaire).
- Diagnostiquer **sans le mot de passe** de la personne concernée : `ipa hbactest`, `sssctl user-checks`, `sudo -l -U`, `step ssh inspect`, `sshd -T`, journal de sshd et de SSSD.
- Corriger à la source (annuaire en code, rôle Ansible, configuration de step-ca) et rendre la panne visible la prochaine fois.

**Prérequis** : M24-E19, M24-E20, M24-E21 ; `lab/bin/check 24 40` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique**
- Chaîne d'une connexion (M24-E20) : `step ssh login` (SSO + OTP) → certificat d'utilisateur de 16 h signé par le provisioner `keycloak` de step-ca (`ca01`, `/etc/step-ca/config/ca.json`, rôle `step_ca`, variables `group_vars/role_pki/step_ca.yml`) → sshd de la VM vérifie la CA d'utilisateurs, puis les principaux (`/etc/ssh/principaux/%u`, puis `/usr/local/sbin/principaux-annuaire %u`) → PAM : `pam_sss` (SSSD, HBAC) à l'étape *account* → session (`mkhomedir`) → `sudo` lit ses règles dans l'annuaire par SSSD (`sudoers: files sss`).
- Règles de l'annuaire (M24-E19, `annuaire/hbac.yml` et `annuaire/sudo.yml` de `plateforme/identite`) : `hbac-plateforme` (plateforme-admins, plateforme → tous les hôtes), `hbac-support` (support → `mon01`, `nbx01`), `allow_all` **désactivée** ; `sudo-plateforme-admins` (tout), `sudo-plateforme` (journaux et état des services, groupe `systemd-journal`, tous les hôtes).
- SSSD garde un cache : une règle modifiée dans l'annuaire peut mettre plusieurs minutes à s'appliquer sur une VM, et une VM peut continuer à « marcher » sur son cache. `sss_cache -E` l'invalide (sans danger) ; `sssctl` (paquet `sssd-tools`) lit l'état de SSSD.
- Ton accès de secours pendant toute la panne : le compte local `admin` (clé d'`adm01`) et le certificat `ms-ssh-cert` (RB-240). Tu ne connais pas le mot de passe des autres personnes : tout le diagnostic se fait **pour** elles, pas **en tant que** elles.

**Injection** : `lab/bin/break 24 40` (4 variantes).

**Travail demandé**
1. Reformule le symptôme en une phrase précise : qui, sur quelles VMs, à quelle étape (« refus avant le mot de passe », « connexion fermée juste après », « entre mais pas sudo »…). Relève l'heure.
2. Sur une VM concernée, en `admin`, lis ce que sshd et PAM ont dit (`journalctl -u ssh`, `journalctl -u sssd` ou `/var/log/sssd/`) au moment de l'échec ; repère l'étape qui refuse.
3. Teste chaque étape **pour la personne**, de la plus extérieure à la plus intérieure : le certificat (que contient-il ? demande à la personne `step ssh inspect` ou fais le tien), le principal attendu par la VM, la résolution du compte (`getent`), la décision d'accès (`sssctl user-checks`, puis `ipa hbactest` sur `ipa01`), les droits sudo (`sudo -l -U`). Note le résultat de chaque test dans ton journal.
4. Trouve la cause racine et son origine (journal de l'annuaire, historique de `plateforme/identite`, fichiers et dates sur la VM ou sur `ca01`). Corrige au bon endroit : l'annuaire **par le code** (`annuaire:appliquer`), la VM **par son rôle**, step-ca **par son rôle** ; vérifie qu'un second passage ne change plus rien.
5. Vérifie le retour avec la personne qui a ouvert le ticket (ou par les mêmes tests), puis clos la panne (`--annuler`).
6. Préviens : ce qui aurait dû alerter (dérive de l'annuaire par rapport au code, SSSD arrêté, configuration de step-ca modifiée hors Ansible) ; mets en place au moins le contrôle de dérive de l'annuaire (le pipeline planifié de M24-E35 lance déjà `annuaire:verifier`, qui ne fait pas échouer le pipeline sur un écart). Complète **RB-246** avec la section `## 6. SSH ou sudo refusé sur les VMs` : un tableau « symptôme → étape → commande de preuve → cause fréquente ».

**Critères de réussite**
- [ ] `allow_all` désactivée ; `hbac-plateforme`, `hbac-support` et `sudo-plateforme` actives, conformes à `annuaire/` sur `main` ; `sudo-plateforme` vaut pour tous les hôtes.
- [ ] Sur `nbx01` : SSSD actif, `/etc/sssd/sssd.conf` à root en `0600`, les personnes de l'annuaire résolues, la règle sudo de Lucas visible ; sur `mon01`, la décision HBAC pour `nadia.roussel` est « accepté ».
- [ ] Le provisioner `keycloak` de step-ca émet le seul principal `preferred_username` ; RB-246 contient sa section ; ton journal contient la preuve de la cause ; la panne est close.

**Vérification** : `lab/bin/check 24 40`

<details><summary>Indice 1</summary>

« `Permission denied (publickey)` » avant toute question : le certificat ou le principal (côté sshd, `journalctl -u ssh` dit lequel). « `Connection closed` » juste après : PAM, donc le compte ou HBAC. Connexion réussie mais `sudo` refusé : les règles sudo. Rien ne se résout sur **une** VM seulement : cette VM-là.
</details>

<details><summary>Indice 2</summary>

`ipa hbactest --user=<IDENTIFIANT> --host=<FQDN> --service=sshd` (sur `ipa01`, après `kinit`) dit ce que l'annuaire décide et quelles règles ont été évaluées ; `sudo sssctl user-checks -a acct -s sshd <IDENTIFIANT>` dit ce que **la VM** décide. Si les deux divergent, regarde SSSD (`systemctl status sssd`, `sssctl domain-status`). Pour sudo : `sudo -l -U <IDENTIFIANT>` sur la VM et `ipa sudorule-show <RÈGLE>` sur `ipa01`. Pour step-ca : la liste publique des provisioners (`curl https://ca01…/provisioners`) montre le gabarit en service.
</details>

<details><summary>Indice 3</summary>

L'annuaire garde la date de dernière modification de chaque entrée (`ipa hbacrule-show … --all --raw`, attribut `modifyTimestamp`) et le journal d'accès de 389-ds (`/var/log/dirsrv/slapd-*/access`, aussi dans Loki `audit`) dit qui l'a modifiée. Sur une VM, `stat` d'un fichier de configuration donne sa date de modification ; SSSD refuse de démarrer si sa configuration est lisible par d'autres que root.
</details>

**Pour aller plus loin** (facultatif) : un job planifié de `plateforme/identite` qui joue `annuaire.yml --check --diff` chaque nuit et échoue sur une dérive ; une alerte quand `sssd` n'est pas actif sur un hôte inscrit (collecteur `systemd` de node_exporter, M21). [FreeIPA : *Host-based access control*](https://freeipa.readthedocs.io/en/latest/designs/hbac.html) · [SSSD : *Troubleshooting*](https://sssd.io/troubleshooting/basics.html) · [Smallstep : *OIDC provisioner*](https://smallstep.com/docs/step-ca/provisioners/#oauthoidc-single-sign-on)

---

### M24-E41 — Panne : boucle de redirection derrière OAuth2 Proxy  `BF` `★★`

> **Ticket INC-5141** — *De : Nadia Roussel*
> *(Le détail s'affiche à l'injection : selon le cas, l'interface de Mailpit sur `mon01:8443` renvoie au SSO puis finit sur « Login Failed », en boucle, ou s'arrête sur une page d'erreur de Keycloak, ou envoie sur une autre interface.)* Hubble et Pyroscope, derrière le même SSO, marchent. Je n'ai plus les courriels d'alerte de l'astreinte.

**Objectifs pédagogiques**
- Suivre un flux OAuth2 Proxy ↔ Keycloak requête par requête : `/oauth2/start` (cookie de CSRF, `state`, PKCE), autorisation, `/oauth2/callback` (vérification du CSRF, échange du code), cookie de session, retour à la page demandée.
- Lire les en-têtes `Location` et `Set-Cookie` avec `curl -D -` et les outils de développement du navigateur ; connaître les règles des cookies préfixés `__Host-` et l'URI de retour **exacte** d'OAuth 2.0.
- Savoir quel côté corriger (le mandataire, ou le client dans Keycloak) quand le symptôme s'affiche chez l'autre.

**Prérequis** : M24-E18, M24-E34 ; `lab/bin/check 24 41` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique**
- Instance de `mon01` (M24-E18) : unité `oauth2-proxy-mailpit`, fichiers `/etc/oauth2-proxy/mailpit/oauth2-proxy.cfg` (options générales, cookies, `redirect_url`) et `alpha.yaml` (serveur TLS 8443, amont, fournisseur), posés par le rôle `oauth2_proxy` de `plateforme/ansible` (`host_vars/mon01/oauth2_proxy.yml`). Cookie `__Host-oauth2-mailpit`, cookie de CSRF du même nom suivi de `_csrf`.
- Client Keycloak **unique** `oauth2-proxy` (`tofu/clients-oauth2-proxy.tf`) pour toutes les instances, URI de retour listées une à une : Hubble, Pyroscope, Pyrra (E34), `mon01:8443`.
- OAuth2 Proxy journalise chaque échec d'authentification avec sa raison (`journalctl -u oauth2-proxy-mailpit`) ; les instances du cluster, dans les journaux de leurs pods.
- Pour reproduire sans navigateur : `curl -s -o /dev/null -D - https://mon01.par1.medisphere.internal:8443/` montre la première redirection et les cookies posés, sans rien envoyer à Keycloak.

**Injection** : `lab/bin/break 24 41` (3 variantes).

**Travail demandé**
1. Reproduis dans une fenêtre privée avec les outils de développement ouverts (onglet Réseau, « conserver le journal ») : note chaque requête de la chaîne, son code, son en-tête `Location`, les cookies posés **et ceux que le navigateur a refusés** (l'onglet le signale).
2. Reproduis la première étape avec `curl -D -` depuis `adm01` ; compare l'URI de retour annoncée et les attributs des cookies à ce qu'exige le préfixe `__Host-` et à ce que Keycloak a enregistré pour le client (`keycloak_api` ou la console, en lecture).
3. Lis le journal de l'instance et, côté Keycloak, les événements du client `oauth2-proxy` (locataire `audit` de Loki, `service="keycloak"`). Où la chaîne casse-t-elle, et chez qui le symptôme s'affiche-t-il ?
4. Trouve la cause racine et son origine (fichier modifié sur `mon01` et sa date, ou client modifié dans Keycloak : `tofu plan` de `plateforme/identite` montre une dérive). Corrige au bon endroit : rôle Ansible rejoué (`--check --diff` d'abord), ou `tofu apply` par le pipeline. Vérifie le retour, puis `--annuler`.
5. Prévention : une assertion dans le rôle `oauth2_proxy` qui refuse une configuration incohérente (cookie `__Host-` avec un domaine, `redirect_url` qui n'est pas celle de l'instance) ; et la réponse écrite à la question : un client par instance aurait-il changé quelque chose à l'une des variantes ?
6. Complète **RB-246** avec la section `## 7. OAuth2 Proxy : boucle ou « Login Failed »`.

**Critères de réussite**
- [ ] Le client `oauth2-proxy` porte l'URI de retour exacte de `mon01` (sans joker) et Keycloak l'accepte ; une visite sans session sur `mon01:8443` est renvoyée vers Keycloak avec **cette** URI de retour.
- [ ] Le cookie posé par l'instance est `Secure`, `Path=/`, **sans** `Domain` ; la configuration de `mon01` est celle du rôle (aucune modification manuelle restante).
- [ ] RB-246 contient sa section OAuth2 Proxy ; l'assertion de prévention est fusionnée dans `plateforme/ansible`.

**Vérification** : `lab/bin/check 24 41`

<details><summary>Indice 1</summary>

Trois familles : Keycloak refuse **avant** le formulaire (le client ou l'URI de retour) ; Keycloak accepte, mais le retour arrive au mauvais endroit (l'URI de retour est valable… pour quelqu'un d'autre) ; tout arrive au bon endroit mais le mandataire ne retrouve pas ce qu'il avait posé (cookie). Le paramètre `redirect_uri` de l'URL d'autorisation, dans la barre d'adresse, tranche entre les deux premières.
</details>

<details><summary>Indice 2</summary>

Un cookie dont le nom commence par `__Host-` n'est accepté par le navigateur que s'il est `Secure`, `Path=/` et **sans** `Domain` (RFC 6265bis, *cookie prefixes*). `curl` ne vérifie pas ces règles : il faut les lire dans `Set-Cookie`. Dans la configuration d'OAuth2 Proxy, cherche les options qui fixent le domaine ou l'URI de retour et compare au gabarit du rôle.
</details>

**Pour aller plus loin** (facultatif) : deux pannes classiques ne sont pas injectées ici parce qu'elles ne se reproduisent pas de façon fiable dans le lab : le **cookie trop gros** (groupes nombreux, jetons longs : OAuth2 Proxy le découpe en `_0`, `_1`…, et c'est un mandataire en amont qui finit par répondre `431`) et les **en-têtes `X-Forwarded-*`** non crus derrière la Gateway. Décris pour chacun le symptôme, la preuve et le correctif (`session_store_type = "redis"`, `trusted_proxy_ips`). [OAuth2 Proxy : *Configuration*](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview) · [MDN : *Cookie prefixes*](https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies#cookie_prefixes)

---

### M24-E42 — Panne : le fournisseur d'identité ne répond plus comme avant  `BF` `★★`

> **Ticket INC-5142** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection : selon le cas, tous les services refusent les connexions et le navigateur part vers une adresse qui ne répond pas, ou `sso` répond `503` à tout le monde, ou le SSO devient lent avec des erreurs internes par moments.)* Lucas a « optimisé » quelque chose sur `idp01` ou sur les répartiteurs hier soir.

**Objectifs pédagogiques**
- Diagnostiquer couche par couche le fournisseur lui-même : publication (VIP, HAProxy, contrôle de santé), TLS entre répartiteur et Keycloak, configuration de Keycloak (nom public, mandataires), base de données (connexions).
- Distinguer « Keycloak est arrêté », « Keycloak répond mais personne ne le joint », « Keycloak répond mais **autre chose** » et « Keycloak est saturé », par les sondes, les métriques et les journaux d'E26.
- Garder la main pendant que le SSO est indisponible : accès de secours (RB-240), communication, retour arrière.

**Prérequis** : M24-E04, M24-E24, M24-E26, M24-E28 ; `lab/bin/check 24 42` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Contexte technique**
- Publication (M24-E04) : `sso.par1.medisphere.internal` → VIP 10.10.70.200 (`lb01`/`lb02`, keepalived) → frontend de HAProxy → backend `be_sso` → `idp01:8443` en TLS **vérifié** (racine MédiSphère, `verifyhost idp01.par1.medisphere.internal`), contrôle de santé `GET /health/ready` sur l'interface de gestion **9000** (`check-ssl`). Journaux de HAProxy : `journalctl -u haproxy` sur le répartiteur actif ; état des serveurs : socket d'administration si ton rôle l'a ouverte, sinon le journal (`Server be_sso/idp01 is DOWN, reason: …`).
- Keycloak (rôle `keycloak`) : `/opt/keycloak/conf/keycloak.conf` (`hostname`, `proxy-headers`, `proxy-trusted-addresses`, certificats), certificat ACME `/etc/keycloak/tls/keycloak.{crt,key}` renouvelé par `cert-renewer@keycloak` ; base PostgreSQL 17 locale (`/etc/postgresql/17/main/`, répertoire `conf.d/` inclus).
- Supervision (M24-E26) : `KeycloakIndisponible` (collecte de `idp01:9000`), sonde `https_2xx` de `sso` depuis le témoin de `mon01`, journaux de Keycloak dans Loki `audit`. Les **checks** du workbook passent eux aussi par `sso` : pendant une partie de cette panne, ils ne liront plus Keycloak.
- Toute modification passe par le rôle concerné (`keycloak`, `haproxy`, `certificats_acme`) ; un redémarrage de Keycloak coupe le SSO 30 à 60 secondes.

> ⚠️ **Attention** : avant de toucher à `idp01` ou aux répartiteurs, vérifie que tes accès de secours ne dépendent pas de `sso` : session SSH `admin` ouverte sur `idp01` et sur `lb01`, `admin.conf` à portée, `root@pam` pour la console de Proxmox. Les répartiteurs se modifient **un à la fois** (`--limit lb02`, contrôle, puis `lb01`) ; avant de recharger HAProxy, `haproxy -c -f` ; retour arrière : le fichier précédent (le rôle en garde une copie) et `systemctl reload haproxy`.

**Injection** : `lab/bin/break 24 42` (4 variantes).

**Travail demandé**
1. **Premier diagnostic, en cinq minutes**, du plus extérieur au plus intérieur : la découverte (`curl -s -o /dev/null -w '%{http_code}'` puis le contenu : `issuer`, points de terminaison), le résultat de la sonde du témoin, `up{job="keycloak"}`, `systemctl status keycloak` et `/health/ready` **sur `idp01`** (`curl -k https://127.0.0.1:9000/health/ready`), l'état du serveur dans HAProxy. Écris dans ton journal laquelle des quatre situations des objectifs tu vois.
2. Envoie un premier message à l'équipe (ce qui marche, ce qui ne marche pas, l'accès de secours, prochain point dans 30 min).
3. Descends la couche en cause : configuration effective de Keycloak (`kc.sh show-config` sur `idp01`, en `keycloak`), certificat présenté (`openssl s_client -connect idp01.par1.medisphere.internal:8443` **depuis un répartiteur**, avec la racine MédiSphère), journal de HAProxy, connexions de PostgreSQL (`pg_stat_activity`, `SHOW max_connections` et d'où vient la valeur : `pg_settings.sourcefile`), journal de Keycloak.
4. Trouve la cause racine, son origine et sa date ; corrige par le rôle concerné (jamais seulement à la main) et vérifie le retour de **chaque** service (un ou deux par famille : Grafana, kubectl, `step ssh login`).
5. **Détection** : pourquoi l'alerte a sonné, ou pas ? Complète ce qui manque (MR dans `plateforme/observabilite`, tests `promtool`) : une alerte sur le serveur `be_sso` hors service vu par HAProxy, une sur l'attente de connexions à la base dans Keycloak, et une sonde du témoin qui vérifie **l'émetteur** annoncé, pas seulement le code 200.
6. Complète **RB-246** avec la section `## 8. Le fournisseur d'identité répond mal` : l'arbre de décision des cinq premières minutes, avec la commande qui prouve chaque branche.

**Critères de réussite**
- [ ] La découverte publique annonce l'émetteur `https://sso.par1.medisphere.internal/realms/medisphere` et des points de terminaison sous lui ; `hostname` de `keycloak.conf` est l'URL publique sans port.
- [ ] Le certificat de Keycloak est émis par la PKI MédiSphère au nom d'`idp01` ; `be_sso` est contrôlé sur le port 9000 sur **les deux** répartiteurs ; PostgreSQL accepte au moins 50 connexions et Keycloak n'a plus de refus depuis 15 minutes.
- [ ] Les alertes de détection sont chargées avec leurs tests ; RB-246 contient sa section ; ton journal contient les communications.

**Vérification** : `lab/bin/check 24 42`

<details><summary>Indice 1</summary>

`503` de HAProxy = aucun serveur disponible pour ce backend : c'est le **contrôle de santé** qui décide, pas le trafic. Regarde la raison donnée par le journal de HAProxy (`Layer4`, `Layer6` pour TLS, `Layer7 wrong status` pour une réponse HTTP inattendue). Un `200` avec un émetteur différent : Keycloak répond, avec un autre nom ; un `200` lent avec des erreurs : la base.
</details>

<details><summary>Indice 2</summary>

`kc.sh show-config` affiche la valeur effective de chaque option et **d'où elle vient** (fichier, variable d'environnement). Pour TLS : `openssl s_client … -CAfile <RACINE> -verify_hostname idp01.par1.medisphere.internal` et `openssl x509 -noout -issuer -subject -ext subjectAltName`. Pour PostgreSQL : `SELECT name, setting, sourcefile FROM pg_settings WHERE name = 'max_connections'`.
</details>

<details><summary>Indice 3</summary>

Un fichier sur un hôte géré par Ansible qui n'a pas été écrit par Ansible : `ansible-playbook … --check --diff --limit <HÔTE>` le montre (sauf un fichier que le rôle ne connaît pas : il faut alors le chercher par date, `find /etc -newer …`).
</details>

**Pour aller plus loin** (facultatif) : une sonde *synthétique* sur le témoin qui joue un flux complet de `client_credentials` sur un client dédié et vérifie la signature du jeton obtenu (M24-E44) : elle détecte les quatre variantes, et aussi une clé de signature désactivée. [Keycloak : *Configuring the hostname (v2)*](https://www.keycloak.org/server/hostname) · [Keycloak : *Configuring a reverse proxy*](https://www.keycloak.org/server/reverseproxy) · [HAProxy : *Health checks*](https://docs.haproxy.org/3.2/configuration.html#5.2-check)

---

### M24-E43 — Astreinte : la matinée où personne ne pouvait se connecter  `BF` `★★★★`

> **Ticket INC-5143** — *De : Nadia Roussel (responsable astreinte)* — priorité P1
> Tu es d'astreinte. Lundi, 7 h 50 : le support croule sous les appels (le détail s'affiche à l'injection). Les rendez-vous des patients passent, mais l'équipe ne peut plus ni déployer, ni diagnostiquer, ni lire les alertes. Claire veut un point à 8 h 30, puis toutes les 30 minutes. Ensuite : post-mortem et runbook.

**Objectifs pédagogiques**
- Gérer un incident d'identité à causes multiples : trier par **rayon d'action** (le fournisseur, puis l'annuaire, puis un service), sans confondre symptôme commun et cause commune.
- Utiliser les accès de secours selon RB-240, en traçant chaque ouverture et chaque fermeture.
- Communiquer pendant l'incident ; rédiger un post-mortem sans recherche de coupable et un runbook « SSO indisponible » utilisable par quelqu'un d'autre que toi.

**Prérequis** : M24-E35 à M24-E42 (au moins une variante de chacun) ; M24-E44 conseillé (ses gestes de mesure servent ici) ; RB-240 éprouvé (E28).
**Durée indicative** : 1 h 30 de rétablissement + 45 min de post-mortem et runbook.

**Contexte technique** : le script tire **trois** pannes distinctes parmi celles de M24-E35 à M24-E42 (jamais E36 avec E38, jamais E35 avec E39), une variante au hasard pour chacune, et les injecte ensemble, celle du fournisseur (E42) en dernier ; l'injection prend **5 à 15 minutes** (redémarrages possibles de Keycloak ou de PostgreSQL). Les symptômes se recouvrent : un fournisseur indisponible masque tout le reste, un mappeur de groupes faux ressemble à un RBAC faux. `--variante N` (1 à 44) force le trio, pas les variantes ; `--annuler` retire les trois. Modèle de post-mortem : [`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`](../../00-lab/ressources/M00-E46/modele-post-mortem.md).

**Injection** : `lab/bin/break 24 43`

**Travail demandé**
1. **Triage (15 min au plus)** : pour chaque symptôme, qui est touché, depuis quand, par quel service. Puis tes instruments : la découverte et `/health/ready` répondent-ils ? L'annuaire répond-il (`ldapsearch` par `wb-checks`) ? Le cluster répond-il à `admin.conf` ? Les contrôles `lab/bin/check 24 35` à `24 42` sont des sondes ciblées : lance-les (certains ne liront rien tant que `sso` est indisponible ; c'est une information). Premier message à 8 h 30.
2. **Accès de secours** : si tu en ouvres un, suis RB-240 (qui, quand, pourquoi, refermé quand) ; l'alerte de bris de glace doit sonner (E28) : vérifie qu'elle l'a fait.
3. **Diagnostic et rétablissement** dans un ordre que tu justifies ; une cause racine à la fois, corrigée par le chemin normal (MR, rôle, pipeline) ; après chaque correction, rejoue tous tes tests de départ. Communications toutes les 30 minutes dans ton journal.
4. **Clôture** : communication de fin, `lab/bin/break 24 43 --annuler`, `lab/bin/check 24 43`.
5. **Post-mortem** `docs/securite/identite/post-mortems/AAAA-MM-JJ-INC-5143.md` (MR) : chronologie horodatée, les trois causes, extraits de diagnostic, accès de secours utilisés, section **Détection** (pour chaque cause : ce qui aurait dû la signaler, pourquoi ça n'a pas marché), actions avec responsable et échéance.
6. **RB-246** « SSO indisponible ou refusé » terminé : annonce (déclenchement, rôles, modèles de messages), premier diagnostic en cinq minutes, arbre par couche (publication, Keycloak, base, annuaire, client, service), accès de secours par service (renvoi à RB-240), modèles de messages, retour à la normale et ce qu'il faut vérifier après (sessions, jetons en cache, comptes de secours refermés).

**Critères de réussite**
- [ ] Toutes les vérifications de M24-E35 à M24-E42 sont vertes (le contrôle les rejoue) et aucune panne M24 n'est encore marquée active.
- [ ] Le post-mortem est sur `main` avec chronologie, causes, détection, actions, extraits de diagnostic, au moins quatre communications horodatées, les accès de secours utilisés (ou « aucun ») et aucun jeton ni secret.
- [ ] RB-246 est sur `main` et couvre la découverte, les répartiteurs, le bris de glace et la communication.

**Vérification** : `lab/bin/check 24 43`

<details><summary>Indice 1</summary>

Si `sso` lui-même va mal, commence par là : tant qu'il est indisponible, tu ne peux ni voir ni réparer les pannes des clients, et les checks qui passent par `keycloak_api` ne disent rien. Ensuite, ce qui touche **le plus de personnes** (annuaire, mappeur commun, fichier d'authentification du cluster), puis ce qui touche un service.
</details>

<details><summary>Indice 2</summary>

« Personne ne peut se connecter à X » a trois lectures : personne n'arrive **jusqu'au** formulaire (publication, client, URI de retour), personne n'en **revient** (secret, émetteur, horloge, cookie), on en revient **sans droits** (groupes, RBAC). Classe chaque symptôme ainsi avant de chercher.
</details>

**Pour aller plus loin** : refais l'astreinte en ne t'autorisant **aucun** contrôle `lab/bin/check` avant la clôture ; puis compare ton temps jusqu'au premier diagnostic juste avec celui de ton astreinte du M21 (M21-E43).

---

### M24-E44 — Sous le capot : signatures, JWKS, sessions et rotation des clés  `LAB` `★★★★`

> **Ticket PLAT-2544** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Pendant les pannes, on a dit « le jeton est signé », « kube-apiserver a les clés en cache », « la session Keycloak est dans un cookie » comme on dirait « c'est magique ». Je veux que tu vérifies une signature **à la main**, que tu montres quelle clé l'a faite et qui la garde en mémoire, ce que Keycloak pose dans le navigateur, et ce qu'il envoie à un service quand quelqu'un se déconnecte. Un compte rendu pour les prochains arrivants, et un petit outil qui vérifie un jeton sans bibliothèque.

**Objectifs pédagogiques**
- Vérifier une signature RS256 avec `openssl` seul : en-tête et charge en base64url, entrée signée, clé publique tirée du JWKS (`kid`, `x5c`), et constater qu'un octet changé suffit à la refuser.
- Expliquer ce que les services gardent en cache (JWKS) et quand ils le rechargent ; le lire dans les métriques de kube-apiserver.
- Identifier les cookies de Keycloak (`AUTH_SESSION_ID`, `KC_RESTART`, `KEYCLOAK_IDENTITY`, `KEYCLOAK_SESSION`…), ce qu'ils contiennent et à quoi ils servent ; relier session SSO, session de client et revendication `sid`.
- Observer une déconnexion par canal arrière (*back-channel logout*) : le `logout_token`, sa signature, ses revendications.

**Prérequis** : M24-E07, M24-E16, M24-E27, M24-E29 ; M24-E08 (pipeline de `plateforme/identite`).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Travail sur `adm01` dans `~/m24/e44/` (700) ; tout fichier qui contient un jeton y reste, et disparaît en fin d'exercice. Un jeton d'accès vaut 5 minutes, un code une minute (E27) : prépare les commandes avant d'ouvrir le navigateur.
- Client d'essai **temporaire** `essai-capot` créé **par le code** (`tofu/clients-essai-capot.tf`, MR) : confidentiel, flux standard seul, PKCE `S256`, redirection `http://localhost:8765/rappel` (comme E07), déconnexion par canal arrière vers `http://127.0.0.1:18081/deconnexion` (une adresse **de `idp01` vue par Keycloak** : c'est Keycloak qui l'appelle, depuis `idp01`), déconnexion par canal avant désactivée ; son secret dans `~/m24/e44/essai-capot.secret` (600). Supprimé par une seconde MR à la fin.
- Un récepteur de déconnexion **temporaire** sur `idp01`, à l'écoute de `127.0.0.1:18081` seulement, lancé par toi en `admin` dans une session `tmux` : un script Python de la bibliothèque standard qui affiche le corps des `POST` reçus et répond `200`. Arrêté à la fin (le contrôle le vérifie).
- Clés du royaume après E29 : `rsa-2026-10` (RS256, 4096 bits, priorité 200, active) ; `rsa-generated` d'origine désactivée ; plus d'autres fournisseurs que Keycloak crée lui-même (HMAC, AES, chiffrement RSA-OAEP). Le JWKS publie une clé RSA avec son certificat autosigné (`x5c`).
- Métriques de kube-apiserver 1.36 sur l'authentification JWT : `apiserver_authentication_jwt_authenticator_jwks_fetch_last_timestamp_seconds` et `apiserver_authentication_jwt_authenticator_jwks_fetch_last_key_set_info` (une empreinte du JWKS chargé, par émetteur) ; lisibles par `kubectl get --raw /metrics` avec `admin.conf`, sur chaque nœud de contrôle.

**Travail demandé**

*A. La signature à la main*
1. MR `tofu/clients-essai-capot.tf`, pipeline, `apply`. Range le secret sans l'afficher (`outils/ranger-secret-client.sh` ne convient pas : il écrit dans le Vault ; fais un fichier 600 dans `~/m24/e44/`).
2. Obtiens un ID token et un jeton d'accès pour `lucas.martin` par le flux de code avec PKCE (E07). Découpe le jeton d'accès : en-tête (`alg`, `kid`, `typ`), charge, signature. Quelle est exactement l'**entrée signée** ?
3. Récupère le JWKS, choisis la clé par son `kid`, et tire la clé publique de son `x5c` (`openssl x509 -pubkey`). Compare son module au champ `n` (même clé ?). Vérifie la signature : signature base64url décodée en binaire, `openssl dgst -sha256 -verify … -signature …`. Modifie **un** caractère de la charge, recommence : que répond `openssl` ?
4. Écris `outils/verifier-jeton.sh` dans `plateforme/identite` (MR) : il lit un jeton sur l'entrée standard (jamais en argument), trouve la clé par `kid` dans le JWKS de l'émetteur, vérifie la signature RS256 avec `openssl`, puis `iss`, `exp` et, si on le lui demande, `aud` ; il refuse tout autre algorithme que RS256 ; il n'affiche jamais le jeton. `shellcheck` propre.

*B. Qui garde les clés*
5. Sur chaque nœud de contrôle, lis les deux métriques JWKS de kube-apiserver. Quand le JWKS a-t-il été chargé ? L'empreinte est-elle la même sur les trois ? Relis ce qui s'est passé en E29 (rotation) : qu'est-ce qui oblige un service à recharger le JWKS, et que se passe-t-il pour un jeton signé par une clé que le service ne connaît pas encore ? par une clé **désactivée** ?

*C. Les sessions*
6. Fenêtre privée, outils de développement ouverts sur `sso.par1.medisphere.internal` : connecte-toi à la console de compte (`/realms/medisphere/account`) en `lucas.martin`. Relève **pendant** le formulaire puis **après** la connexion le nom, les attributs (`HttpOnly`, `Secure`, `SameSite`, `Path`, expiration) et la forme de chaque cookie de Keycloak. Décode la charge de `KEYCLOAK_IDENTITY` (sans chercher à vérifier sa signature : avec quel algorithme, quelle clé ?) ; compare `KEYCLOAK_SESSION` à l'identifiant de session que montre l'API d'administration (`users/<ID>/sessions`, en lecture par `wb-checks`) : quelle relation ?
7. Relie : session SSO (navigateur ↔ Keycloak), session de client (Keycloak ↔ un service), revendication `sid` de l'ID token, cookie de session du service (Grafana, OAuth2 Proxy). Qu'est-ce qu'une déconnexion de Keycloak coupe, et qu'est-ce qu'elle ne coupe pas ?

*D. La déconnexion par canal arrière*
8. Lance le récepteur sur `idp01`, refais une connexion par `essai-capot`, puis déconnecte la session (point `end_session` avec `id_token_hint`, ou la console de compte, ou l'API d'administration). Relève le `logout_token` reçu : décode-le, vérifie sa signature avec ton outil, liste ses revendications (`iss`, `aud`, `iat`, `jti`, `sid`, `sub`, `events`) et celles qui en sont **absentes** par rapport à un ID token. Qu'est-ce qu'un service doit vérifier avant de fermer une session sur la foi de ce jeton ?
9. Lesquels de nos services savent recevoir une déconnexion par canal arrière (consulte leur documentation) ? Conséquence pour RB-242 (départs) ?

*E. Ménage et compte rendu*
10. Arrête le récepteur, supprime `essai-capot` par MR, efface tout jeton et le secret de `~/m24/e44/`.
11. Compte rendu `docs/securite/identite/analyses/oidc-sous-le-capot.md` (MR) avec `## Signature`, `## JWKS et caches`, `## Sessions et cookies`, `## Déconnexion par canal arrière`, `## Rotation des clés`, `## Réponses aux questions` ; extraits **tronqués**, aucun jeton complet.

**Questions d'analyse** (dans le compte rendu)
1. Pourquoi une bibliothèque qui choisit l'algorithme d'après l'en-tête `alg` du jeton est-elle dangereuse (`none`, HS256 avec la clé publique RSA comme secret) ? Que fait ton outil, et que font kube-apiserver et OAuth2 Proxy ?
2. Pourquoi Keycloak publie-t-il plusieurs clés, et pourquoi une clé passive reste-t-elle dans le JWKS ?
3. Combien de temps, au plus, un jeton d'accès volé reste-t-il utilisable chez un service qui ne fait que vérifier la signature ? Et un jeton de rafraîchissement, avec notre rotation (E27) ?
4. Que se passe-t-il si un service ne recharge **jamais** son JWKS, et si un service le recharge **à chaque requête** ?
5. Pourquoi `KEYCLOAK_SESSION` n'est-il pas `HttpOnly`, et pourquoi n'a-t-il pas besoin d'être secret ?
6. Pourquoi les cookies de session de Keycloak sont-ils `SameSite=None` alors que nos services posent les leurs en `Lax` ?
7. Un `logout_token` a-t-il une durée de vie ? Comment un service empêche-t-il qu'on lui rejoue le même ?
8. À la rotation de clés d'E29, quel service a mis le plus de temps à accepter la nouvelle clé, et pourquoi ?

**Critères de réussite**
- [ ] Le compte rendu est sur `main` avec ses sections, cite RS256, `kid`, `x5c`, la vérification par `openssl`, les cookies relevés, le `logout_token` (`sid`, événement `backchannel-logout`) et les métriques `jwks_fetch` ; aucun jeton complet.
- [ ] `outils/verifier-jeton.sh` est sur `main` de `plateforme/identite`, pipeline vert.
- [ ] `essai-capot` n'existe plus (Keycloak et code), plus rien n'écoute sur le port 18081 d'`idp01`, aucun jeton ne reste dans `~/m24/e44/`.

**Vérification** : `lab/bin/check 24 44`

<details><summary>Indice 1</summary>

L'entrée signée est la chaîne ASCII `base64url(en-tête) + "." + base64url(charge)`, **telle quelle** (on ne la décode pas). La signature est un bloc binaire de la taille du module (512 octets pour une clé de 4096 bits) : `tr '_-' '/+'`, rembourrage `=` jusqu'à un multiple de 4, `base64 -d`. Le `x5c` contient un certificat **DER en base64 standard** : entoure-le de `-----BEGIN CERTIFICATE-----` et coupe-le à 64 caractères (`fold -w 64`).
</details>

<details><summary>Indice 2</summary>

Le récepteur : `http.server.BaseHTTPRequestHandler` avec une méthode `do_POST` qui lit `Content-Length` octets, les écrit sur la sortie standard et répond `200` ; `HTTPServer(("127.0.0.1", 18081), …)`. Le corps est un formulaire `logout_token=…`. Dans `tofu`, cherche les attributs du client qui portent sur la déconnexion (`backchannel_logout_url`, `frontchannel_logout_enabled`, `backchannel_logout_session_required`) dans la documentation du fournisseur `keycloak/keycloak`.
</details>

<details><summary>Indice 3</summary>

Pour les cookies : l'onglet *Application* (ou *Stockage*) liste les cookies du site avec leurs attributs ; l'onglet *Réseau* montre les `Set-Cookie` de chaque réponse, y compris ceux qui expirent un cookie. Pour l'API : `keycloak_api "users?username=lucas.martin&exact=true"` donne l'identifiant, puis `users/<ID>/sessions`.
</details>

**Pour aller plus loin** (facultatif) : refais la partie A avec un jeton signé par une clé de type ECDSA (ajoute une clé `ecdsa-generated` passive au royaume d'essai `idp-resto` d'E25, jamais en production) et explique pourquoi la signature ECDSA d'un JWT n'a pas le format DER qu'attend `openssl dgst`. [RFC 7515 (JWS)](https://www.rfc-editor.org/rfc/rfc7515) · [RFC 7517 (JWK)](https://www.rfc-editor.org/rfc/rfc7517) · [OpenID Connect Back-Channel Logout 1.0](https://openid.net/specs/openid-connect-backchannel-1_0.html) · [Kubernetes : *Structured authentication configuration*](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#using-authentication-configuration)

---

### M24-E45 — Questions expert : attaques sur OIDC et défenses  `Q` `★★★`

> **Ticket SEC-2545** — *De : Sophie Laurent*
> L'auditeur HDS veut savoir si l'équipe connaît les attaques **connues** contre OAuth et OIDC, et surtout comment notre configuration s'en protège. Je ne veux pas de cours : pour chaque question, le mécanisme en deux phrases, la défense, et **où** elle est chez nous (fichier, réglage, commande qui le prouve). Pas de recherche pendant la première passe ; ensuite, la RFC 9700 et la spécification OpenID Connect Core, et tu te corriges en couleur.

**Objectifs pédagogiques**
- Connaître les classes d'attaques documentées contre OAuth 2.0 et OpenID Connect au niveau du **mécanisme**, et les contre-mesures que recommande la RFC 9700 (*OAuth 2.0 Security Best Current Practice*).
- Rattacher chaque contre-mesure à un réglage **vérifiable** de la plateforme MédiSphère, et repérer ce qui manque.

**Prérequis** : paliers 1 à 3 du module, M24-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Pourquoi la RFC 9700 déconseille-t-elle le flux implicite et le flux par mot de passe (*Resource Owner Password Credentials*) ? Où vois-tu qu'ils sont fermés chez nous, et quel client intégré de Keycloak garde un flux direct (E21, E27) ?
2. Interception du code d'autorisation : quel est le scénario contre lequel PKCE a été conçu, et pourquoi la RFC 9700 le recommande-t-elle **aussi** pour les clients confidentiels ? Quels clients de MédiSphère l'imposent, lesquels ne l'utilisent pas (E13), et pourquoi est-ce acceptable ou non ?
3. QCM — Une application enregistre comme URI de retour `https://*.apps.par1.medisphere.internal/*`. Quel est le risque principal ?
   a) aucun, le joker est limité au domaine interne ; b) un code ou un jeton peut être envoyé à **n'importe quelle** application du domaine, ou à une page qui redirige ailleurs (*open redirector*), et y être capturé ; c) Keycloak refuse ce motif de toute façon ; d) le risque ne concerne que le flux implicite.
4. À quoi servent `state` et `nonce` ? Contre quelle attaque chacun protège-t-il, et qui doit les vérifier (le client, Keycloak) ? Comment OAuth2 Proxy les gère-t-il (E41) ?
5. Attaque par mélange de fournisseurs (*mix-up*) : décris le mécanisme. Pourquoi nous concerne-t-elle peu aujourd'hui ? Quelle défense la RFC 9207 ajoute-t-elle (paramètre `iss` dans la réponse d'autorisation), et Keycloak l'envoie-t-il (E07) ?
6. Confusion d'audience : un jeton émis pour le client `grafana` est présenté à kube-apiserver. Qu'est-ce qui le refuse, exactement, chez nous (E16) ? Et si on avait mis `audiences: [account]` ? Pourquoi un jeton d'accès Keycloak porte-t-il souvent `aud: account` ?
7. QCM — Un service reçoit un **ID token** dans l'en-tête `Authorization: Bearer` d'un appel d'API. Que doit-il faire ?
   a) l'accepter s'il est signé par le royaume ; b) le refuser : un ID token prouve une authentification **au client** qui l'a demandé, ce n'est pas un droit d'accès à une API (substitution de jeton) ; c) l'accepter si `aud` contient son nom ; d) l'échanger contre un jeton d'accès.
   (Explique aussi pourquoi la réponse c) reste fragile.)
8. Rejeu d'un jeton volé : quelles défenses limitent ce que vaut un jeton d'accès volé (durée, audience, liaison à l'émetteur de la requête : *sender-constrained tokens*, mTLS, DPoP) ? Lesquelles avons-nous, lesquelles pas, et que coûterait DPoP chez nous ?
9. Jeton de rafraîchissement volé : que fait la rotation avec détection de réutilisation (E27) quand le voleur et la victime l'utilisent tous les deux ? Que se passe-t-il pour la victime, et pourquoi est-ce le comportement voulu ?
10. Redirection ouverte (*open redirect*) : où peut-elle exister dans notre chaîne (Keycloak, OAuth2 Proxy avec son paramètre `rd`, une application) ? Quelles protections avons-nous (URI exactes, liste de domaines autorisés d'OAuth2 Proxy) ?
11. CSRF sur la connexion et fixation de session : pourquoi un client qui ne vérifie pas `state` peut-il connecter la victime **au compte de l'attaquant**, et en quoi est-ce grave pour un outil d'administration ?
12. Clés et en-têtes de jeton : `alg: none`, confusion RS256/HS256, en-têtes `jku`/`x5u` qui désignent une clé ailleurs. Quelle est la règle unique qui ferme les trois, et comment le vérifier pour kube-apiserver, OAuth2 Proxy et ton outil d'E44 ?
13. Consentement abusif (*illicit consent grant*) : de quoi s'agit-il dans un fournisseur ouvert aux applications tierces ? Pourquoi le risque est-il faible chez nous, et quel réglage de Keycloak le confirmerait (inscription dynamique des clients, consentement) ?
14. Fatigue de MFA (*push bombing*) : pourquoi notre OTP par code (E21) y échappe-t-il, et quelle attaque reste possible contre un OTP (hameçonnage en temps réel par un faux site qui relaie) ? Quelle méthode y résiste, et pourquoi ?
15. Hameçonnage par le flux d'autorisation de terminal (*device authorization grant*) : mécanisme, et comment vérifier que ce flux est fermé sur tous nos clients.
16. QCM — Laquelle de ces mesures **ne** protège **pas** contre le vol de code d'autorisation ?
   a) PKCE `S256` ; b) URI de retour exacte ; c) code à usage unique, valable une minute ; d) `SameSite=Lax` sur le cookie de session du service.
17. Keycloak compromis (E32, question 8) : quelles traces resteraient dans nos journaux (E26), et quelles actions de RB-244 faut-il enchaîner, dans quel ordre ?
18. Pour finir : choisis **trois** contre-mesures de la RFC 9700 que MédiSphère n'applique pas encore ; pour chacune, le risque résiduel, le coût, et ta recommandation (à faire, à surveiller, à refuser) avec un ticket.

**Critères de réussite**
- [ ] Les 18 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses) ; chaque défense citée est rattachée à un fichier, un réglage ou une commande de notre plateforme.
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 11 : [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700) sections 2 (recommandations) et 4 (attaques et contre-mesures), [RFC 7636 (PKCE)](https://www.rfc-editor.org/rfc/rfc7636), [RFC 9207](https://www.rfc-editor.org/rfc/rfc9207), [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html) (validation de l'ID token, `nonce`). Reprends tes comptes rendus d'E07 et d'E44.
</details>

<details><summary>Indice 2</summary>

Pour 12 à 18 : [RFC 8725 (JWT BCP)](https://www.rfc-editor.org/rfc/rfc8725), [RFC 9449 (DPoP)](https://www.rfc-editor.org/rfc/rfc9449), [RFC 8628 (*device grant*)](https://www.rfc-editor.org/rfc/rfc8628), la documentation de Keycloak (*Server Administration Guide* : clients, sessions, *Client Policies*) et ton travail d'E21, E27, E29 et E32.
</details>

**Pour aller plus loin** : choisis deux questions et transforme chacune en **contrôle automatique** (un contrôle de CI sur `plateforme/identite`, ou une requête sur l'API d'administration lancée par la revue des accès d'E30) qui échouerait si la défense disparaissait.
