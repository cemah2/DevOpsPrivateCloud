# Module 24 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. En identité, « j'ai recréé le client » ou « j'ai mis tout le monde admin le temps de comprendre » est presque toujours faux : le premier efface la preuve et casse les autres services du même client, le second ouvre un trou plus grave que la panne.

Les scripts d'injection sont dans `corrige/pannes/` : `_m24-commun.sh` contient les fonctions partagées (API d'administration du **seul** royaume `medisphere` avec le jeton du client `svc-tofu-keycloak`, export JSON avant chaque modification, exécution en root sur les VMs avec sauvegarde dans `/var/lib/workbook/`, cadre Python de FreeIPA sur `ipa01`, `kubectl` d'administration par `admin.conf` lu **sur** `k8s-cp01`, mesure des écarts d'horloge). L'état des pannes est gardé sur `adm01` dans `~/.local/state/workbook/M24-EXX/`, le journal des VMs dans `/var/lib/workbook/pannes.log`. Chaque annulation ne restaure un objet que s'il porte **encore** la valeur injectée : ta réparation n'est jamais défaite.

> **Remarque sur les traces** : les pannes laissent les mêmes traces qu'un humain. Côté Keycloak, l'événement d'administration montre le client **`svc-tofu-keycloak`** et l'adresse d'`adm01` : un changement fait avec le secret d'OpenTofu, hors pipeline. Côté cluster, `admin.conf` (`kubernetes-admin`) a servi : `BrisDeGlaceCluster` (M24-E28) sonne pendant l'injection de M24-E36 et M24-E39. Côté annuaire, une modification par la socket LDAPI en root (liaison automatique en *Directory Manager*). Dans le scénario, c'est Lucas ; en production, chacune de ces traces serait la **première** question du post-mortem : qui possède ce secret, pourquoi un bris de glace a-t-il servi sans être déclaré ?

Les sorties reproduites sont **représentatives** : identifiants, adresses, horodatages et formulations exactes varient selon ton lab et les versions (Keycloak 26.8.1, FreeIPA 4.13, Kubernetes 1.36, Argo CD 3.5, Grafana 13.2, chrony 4.x).

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- **Aucune injection de panne n'a été jouée sur un lab réel.** Les scripts `break-E35.sh` à `break-E43.sh` et les contrôles `check-E35.sh` à `check-E46.sh` passent `bash -n` et `shellcheck -x` ; les contrôles d'E40 à E44 ont été lancés à blanc (sans lab : chaque contrôle passe au rouge ou est ignoré, aucun ne passe sur une absence de réponse) ; les transformations ont été jouées sur des fichiers d'exemple conformes aux corrigés des paliers 1 à 3 : `yq`/`jq` sur les fichiers de M24-E13, E16 et E27, filtre `jq` du gabarit de step-ca (aller et retour identiques), `sed` de `haproxy.cfg` et de `keycloak.conf`, code Python de l'annuaire compilé. Les points les plus sensibles : une mise à jour **partielle** d'un client ou du royaume par `PUT` (Keycloak ne modifie que les champs présents : vérifié dans le code de `RepresentationToModel`, pas sur un serveur 26.8.1) ; le comportement du cadre Python de FreeIPA lancé `in_server=True` en root (liaison LDAPI) pour `user_add` et pour la remise d'une **empreinte** de mot de passe (389-ds accepte une valeur déjà hachée d'une liaison *Directory Manager*).
- E35 : le texte exact des événements `jboss-logging` (`type="CODE_TO_TOKEN_ERROR", … clientId="grafana", … error="invalid_client_credentials"`) et la valeur de l'étiquette `event` de `keycloak_user_events_total` (attendue en minuscules : `code_to_token`) ; le message de Grafana pour `role_attribute_strict` est celui du code source de Grafana (`oauth.role_attribute_strict_violation`, « idP did not return a role attribute, but role_attribute_strict is set »).
- E36 : les noms des métriques (`apiserver_authentication_jwt_authenticator_latency_seconds`, `apiserver_authentication_config_controller_automatic_reloads_total`, `…_automatic_reload_last_timestamp_seconds`, `…_last_config_info`) et les messages (`oidc: expected audience in …`, `oidc: error evaluating claim validation expression`) sont ceux du code de Kubernetes 1.36.0 ; leur **collecte** par kube-prometheus-stack (métriques ALPHA, éventuellement filtrées par ses `metricRelabelings`) est à vérifier sur ton lab. Une racine de confiance fausse ou un émetteur injoignable écrits à chaud ne cassent rien : le rechargement attend que le nouvel authentificateur soit prêt, échoue, et garde l'ancien (lu dans le code, `pkg/kubeapiserver/options/authentication.go`).
- E38 v3 : l'effet exact d'un nœud de contrôle en avance de 7 minutes sur etcd et sur les jetons de comptes de service qu'il émet (borné, mais non mesuré) ; `NodeClockNotSynchronising` de kube-prometheus-stack devrait sonner (un `date -s` met le noyau en `STA_UNSYNC`).
- E39 : la relecture à chaud d'`argocd-rbac-cm` par Argo CD 3.5 (documentée) et la sortie exacte de `argocd admin settings rbac can … --namespace argocd`.
- E40 v2 : comportement de `sudorule_mod(hostcategory=None)` puis `sudorule_add_host` dans le cadre Python de FreeIPA 4.13 (attendu : comme `ipa sudorule-mod --hostcat=` puis `ipa sudorule-add-host`) ; délai réel de prise en compte par SSSD 2.10 (le script invalide le cache sur `nbx01` ; sur les autres VMs, jusqu'au rafraîchissement suivant : `ldap_sudo_smart_refresh_interval`, 15 min par défaut).
- E40 v3 : SSSD 2.10 refuse un `sssd.conf` lisible par « les autres » (lu dans `src/util/sss_ini.c` au tag 2.10.2 : `Unexpected access to '…' by other users`) ; si ta version l'accepte, le script se replie sur l'arrêt du service (le symptôme est le même, la cause plus banale).
- E40 v4 : `step-ca` 0.30 redémarré avec un gabarit modifié ; message exact de sshd 10.0 pour un principal absent.
- E41 v1 : OAuth2 Proxy 7.15.5 ne valide pas la cohérence entre le préfixe `__Host-` et `cookie_domains` (lu dans `pkg/validation/cookie.go` au tag) : il démarre et pose un cookie que le navigateur rejette ; le message « Login Failed: Unable to find a valid CSRF token » est celui du code (`oauthproxy.go`). Le refus par le navigateur (Firefox, Chromium) n'a pas été observé ici.
- E42 v4 : PostgreSQL 17 démarre avec `max_connections = 6` (3 réservées aux superutilisateurs) ; nombre exact de connexions que Keycloak 26.8 ouvre au démarrage ; texte exact des refus (`sorry, too many clients already`, `remaining connection slots are reserved for roles with the SUPERUSER attribute`) dans le journal JSON de Keycloak.
- E42 : métrique `agroal_awaiting_count` de Keycloak (seule `agroal_active_count` est citée par la documentation 26.8 ; vérifie `/metrics` sur le port 9000) et étiquette `state` de `haproxy_server_status` (exportateur natif de HAProxy 3.2).
- E44 : `verifier-jeton.sh` a été joué contre un émetteur d'essai local (découverte et JWKS servis en HTTPS, jeton RS256 signé par `openssl`) : jeton valide accepté, charge altérée, `alg: none` et mauvaise audience refusés. Noms et attributs des cookies relus dans le code de Keycloak 26.8.1 (`CookieType`, `CookieScope`, `AuthenticationManager.createLoginCookie` : `KEYCLOAK_SESSION` = empreinte SHA-384 de l'identifiant de session) ; métriques JWKS de kube-apiserver relues dans le code 1.36.0 (`plugin/pkg/authenticator/token/oidc/metrics.go`) ; attributs `backchannel_logout_url`, `frontchannel_logout_enabled` relus dans le fournisseur `keycloak/keycloak` 5.10.0. Le flux complet (récepteur, `logout_token`) n'a pas été joué.
- E45 : prise en charge de DPoP par Keycloak 26.8 (fonction disponible depuis la 26.4 selon les notes de version : vérifie `kc.sh show-config` et la documentation de ta version) ; réglage GitLab de la question 1 du mini-projet.

---

### M24-E35 — Panne : plus personne n'entre dans Grafana

**Démarche de diagnostic**

*Symptômes* : connexion SSO à Grafana refusée pour tout le monde ; le compte de service `wb-checks` (jeton d'API) fonctionne : Grafana lui-même va bien.

*Hypothèses*, dans l'ordre de la chaîne : Keycloak refuse la **demande d'autorisation** (client désactivé ou inconnu, URI de redirection) ; Keycloak refuse l'**échange du code** (secret, PKCE, code expiré, horloge) ; Keycloak accepte tout mais Grafana **refuse la personne** (revendication manquante, rôle introuvable, organisation) ; Grafana ne joint plus Keycloak (réseau, TLS : « context deadline exceeded », M24-E12).

**Étape 1 — Où s'arrête la connexion ?** Dans une fenêtre privée, « SSO MédiSphère » :
- page d'erreur de Keycloak **sans** formulaire, « Invalid parameter: redirect_uri » : variante 2 ;
- formulaire, OTP, puis retour sur Grafana avec « Login failed » : variantes 1 ou 3.

**Étape 2 — L'événement de Keycloak.** Dans Grafana → *Explore* → source Loki **audit** (ou `logcli` avec `--org-id=audit`) :

```
{service="keycloak"} | json | loggerName="org.keycloak.events" |~ "grafana"
```

| Variante | Ligne trouvée (extrait de `message`) |
|---|---|
| 1 | `type="CODE_TO_TOKEN_ERROR", realmName="medisphere", clientId="grafana", userId="…", ipAddress="10.10.41.…", error="invalid_client_credentials", grant_type="authorization_code"` |
| 2 | `type="LOGIN_ERROR", realmName="medisphere", clientId="grafana", userId="null", error="invalid_redirect_uri", redirect_uri="https://grafana.apps.par1.medisphere.internal/login/generic_oauth"` |
| 3 | `type="LOGIN", … clientId="grafana", username="julien.petit"` puis `type="CODE_TO_TOKEN", … clientId="grafana"` : **aucune erreur** côté Keycloak |

L'adresse de la variante 1 est celle d'un nœud (le pod Grafana fait l'échange de serveur à serveur), celle de la 2 est celle du navigateur. Les compteurs le disent aussi : `increase(keycloak_user_events_total{realm="medisphere",error="invalid_client_credentials"}[15m])` monte en variante 1.

**Étape 3 — Le journal de Grafana** (variantes 1 et 3) :

```
admin@adm01:~$ kubectl -n supervision logs deploy/kps-grafana -c grafana --since=15m | grep -E 'oauth|authn' | tail -n 3
```
- variante 1 : `logger=authn.service … error="… oauth2: \"unauthorized_client\" \"Invalid client or Invalid client credentials\""` ;
- variante 3 : `logger=authn.service … error="[oauth.role_attribute_strict_violation] idP did not return a role attribute, but role_attribute_strict is set"`.

Pour la variante 3, *Clients* → `grafana` → *Client scopes* → *Evaluate*, utilisateur `julien.petit` → *Generated ID token* : pas de revendication `groups`. L'onglet *Client scopes* du client : `groupes` n'est plus dans la liste des portées **par défaut**. `role_attribute_path` commence par `contains(groups[*], …)` : sans `groups`, l'expression échoue, et `role_attribute_strict` transforme l'échec en refus (M24-E12, c'est le garde-fou voulu : sans lui, tout le monde serait entré en `Viewer` et personne n'aurait rien vu).

**Étape 4 — Qui, quoi, quand.** Console → *Events* → *Admin events* (ou `GET /admin/realms/medisphere/admin-events?max=20`) :

| Variante | Opération | Ressource |
|---|---|---|
| 1 | `UPDATE` | `CLIENT`, `clients/<id>` (représentation : `secret` changé) |
| 2 | `UPDATE` | `CLIENT`, `clients/<id>` (`redirectUris` : `…/login/oauth`) |
| 3 | `DELETE` | `clients/<id>/default-client-scopes/<id de groupes>` |

*Auth* : royaume `master`, client **`svc-tofu-keycloak`**, adresse d'`adm01`. Ce client ne devrait parler à Keycloak que depuis `runner01` (pipeline) ou depuis ton poste pendant un `tofu plan` : quelqu'un a utilisé le secret d'OpenTofu à la main. Dans le journal, pour Sophie : « changement manuel avec l'identité de l'automate ; le secret de `svc-tofu-keycloak` est à faire tourner et son usage hors `runner01` à alerter ». (Dans le lab, c'est le script de panne qui lit ton `keycloak-tofu.env`.)

**Étape 5 — Le code voit-il la dérive ?**

```
admin@adm01:~/src/identite$ . outils/charger-acces.sh && tofu -chdir=tofu plan
```
- variante 2 :
  ```
    ~ resource "keycloak_openid_client" "grafana" {
        ~ valid_redirect_uris = [
            - "https://grafana.apps.par1.medisphere.internal/login/oauth",
            + "https://grafana.apps.par1.medisphere.internal/login/generic_oauth",
          ]
  Plan: 0 to add, 1 to change, 0 to destroy.
  ```
- variante 3 : `~ resource "keycloak_openid_client_default_scopes" "grafana"` avec `+ "groupes"` ;
- variante 1 : **No changes.** Le secret est un argument en écriture seule (`client_secret_wo`, E29) : le fournisseur ne le relit jamais, donc ne peut pas voir qu'il a changé. C'est le prix de « le secret n'est ni dans l'état ni dans le plan ».

**Cause racine et correctif, par variante.**

*Variante 1 — secret du client remplacé dans Keycloak.* Grafana a gardé le secret du Vault (Secret `supervision/grafana-oidc`) ; Keycloak en a un autre. Preuve, sans afficher aucun secret (méthode d'E29) :
```
admin@adm01:~/src/k8s$ outils/secrets-k8s.sh verifier identite
[OK] supervision/grafana-oidc : GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET identique à sa source
admin@adm01:~$ VAULT="$(cd ~/src/ansible && uv run ansible-vault view secrets/identite.yml | yq -r '.keycloak_secrets_clients.grafana')"
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' -K <(printf 'user = "grafana:%s"\n' "$VAULT") \
>   -d token=x https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/token/introspect; unset VAULT
401
```
Le Vault et Grafana sont d'accord, Keycloak non : c'est Keycloak qui a dérivé. La valeur qui fait foi est celle du Vault ; ce qui la pousse vers Keycloak, c'est la **version** (RB-244 §2) : MR qui passe `versions_secrets_clients.grafana` de 2 à 3 (« remise du secret du Vault après changement manuel, INC-5135 »), pipeline, `tofu:apply`. Le plan montre `~ client_secret_wo_version = "2" -> "3"` et rien d'autre. Après l'apply, la même introspection répond `200` et la connexion passe ; Grafana n'a pas besoin d'être redémarré (il n'a jamais changé de secret).
À ne pas faire : *Credentials* → *Regenerate* dans la console (un troisième secret, que ni le Vault ni Grafana ne connaissent), ou recopier dans le Vault le secret que Keycloak a maintenant (le Vault deviendrait le suiveur d'un changement non autorisé).

*Variante 2 — URI de redirection « nettoyée ».* Grafana envoie toujours `…/login/generic_oauth` (c'est son chemin pour `auth.generic_oauth`) ; Keycloak n'accepte plus que `…/login/oauth`, qui ne correspond à aucun fournisseur de Grafana. Keycloak refuse **avant** le formulaire, par sécurité : renvoyer un code vers une adresse non enregistrée, c'est l'*open redirect* qui donne le code à un tiers (M24-E45). Correctif : le code est juste, la réalité a dérivé ; nouveau pipeline sur `main` (*Build* → *Pipelines* → *Run pipeline*), relis `tofu:plan` (une seule ligne changée), lance `tofu:apply`. Aucune MR n'est nécessaire, et c'est voulu : le dépôt n'a rien de faux.

*Variante 3 — portée `groupes` retirée du client.* Keycloak émet un jeton valide **sans** `groups` ; Grafana refuse. Correctif : pipeline sur `main`, `tofu:apply` (la ressource `keycloak_openid_client_default_scopes.grafana` remet la liste complète). Une personne déjà connectée garde sa session Grafana : seules les nouvelles connexions échouaient.

**Vérification commune** : fenêtre privée, connexion de Julien (rôle `Viewer` : `mediagenda` n'a pas de rôle plus élevé, M24-E12) et de toi (`Grafana Admin`) ; dans Loki, un `CODE_TO_TOKEN` du client `grafana` **après** la dernière erreur ; `tofu plan` vide ; `lab/bin/check 24 35` ; puis `lab/bin/break 24 35 --annuler` pour clore.

**Prévention.**
1. *Alerte sur les erreurs de client* (variantes 1 et 2, et toute rotation ratée d'un autre service) : [`loki/regles/audit/identite.yaml.extrait-E35`](fichiers/M24-E35/observabilite/loki/regles/audit/identite.yaml.extrait-E35), alerte `ClientSsoEnEchec` : plus de deux erreurs `invalid_client_credentials`, `invalid_client` ou `invalid_redirect_uri` en 10 minutes pour un même client, gravité `critique` (un service entier est fermé). Le compteur `keycloak_user_events_total` voit le volume mais pas le client (étiquette retirée pour la cardinalité, E26) : le journal donne le **nom** du service touché.
2. *Contrôle de dérive planifié* (variantes 2 et 3, et toute dérive du royaume) : job `tofu:derive` dans [`.gitlab-ci.yml.extrait-E35`](fichiers/M24-E35/identite/.gitlab-ci.yml.extrait-E35), planifié chaque nuit (*Build* → *Pipeline schedules*, variable `DERIVE_NUIT=1`) : `tofu plan -detailed-exitcode -lock=false`, échec sur le code 2, plan en artefact ; un pipeline planifié en échec envoie un courriel à son propriétaire. Il ne voit **pas** la variante 1 (écriture seule) : c'est pour elle qu'existe l'alerte du point 1. Bonus : le job `annuaire:verifier` (`--check --diff`) tourne aussi dans ce pipeline et signale une dérive de l'annuaire.
3. *Le secret d'OpenTofu* : RB-244 ajoute `svc-tofu-keycloak` aux secrets à faire tourner après tout usage hors pipeline ; une alerte d'usage de ce client depuis une autre adresse que `runner01` et MGMT est une bonne idée (pour aller plus loin).
4. *RB-246* commencé : [`RB-246-sso-indisponible.md`](fichiers/M24-E35/medisphere/docs/securite/identite/runbooks/RB-246-sso-indisponible.md) (état intermédiaire après M24-E39 : en-tête, méthode, sections des pannes E35 à E39). La version de référence, complète, est celle de M24-E43 : [`RB-246-sso-indisponible.md`](fichiers/M24-E43/medisphere/docs/securite/identite/runbooks/RB-246-sso-indisponible.md) ; les sections 0 à 5 y sont identiques.

**Explications**

Une connexion OIDC à Grafana traverse trois juges : Keycloak juge la **demande** (le client existe, est actif, l'URI de redirection est enregistrée **exactement**), puis l'**échange** (le client prouve son identité par son secret, le vérificateur PKCE correspond au défi) ; Grafana juge enfin la **personne** (revendications, `role_attribute_path`, `org_mapping`). Chaque juge a son journal : les événements de Keycloak pour les deux premiers, Grafana pour le troisième. Un « Login failed » de Grafana ne dit pas lequel a refusé : il faut aller lire. Les événements d'administration (stockés grâce à E26) transforment « Lucas a juste regardé » en une liste de faits datés.

**Alternatives**

- Comparer l'export du client (*Action* → *Export*) à celui d'hier (sauvegarde E25) : utile quand le code n'est pas encore à jour ; ici, `tofu plan` fait la même chose en mieux.
- Pour la variante 1, la rotation complète (nouveau secret au Vault, `secrets-k8s.sh`, version + 1, redémarrage de Grafana) : correcte aussi, plus longue, avec une fenêtre ; à choisir si l'on soupçonne que l'ancien secret a fui.
- Rotation à double secret de la 26.8 (politique de clients) : l'ancien secret resterait accepté pendant le recouvrement, et la variante 1 n'aurait rien coupé… tant que le recouvrement dure.

**Pièges classiques**

- Recréer le client `grafana` : nouvel identifiant interne, nouveau secret, portées à refaire, et les jetons en cours invalidés ; le code (import, état) ne correspond plus.
- Ajouter `…/login/oauth` **en plus** dans le code pour « accepter les deux » : une redirection inutile de plus à surveiller.
- Désactiver `role_attribute_strict` : tout le monde entre en `Viewer`, la panne devient invisible, et un vrai incident de groupes le serait aussi.
- Chercher la variante 1 dans `tofu plan` et conclure « rien n'a changé ».
- Afficher un secret pour le comparer (`echo`, `ansible-vault view` à l'écran, capture dans le journal) : on compare par introspection, sans jamais l'afficher.

**En production chez MédiSphère**

`ClientSsoEnEchec` va à l'astreinte ; le contrôle de dérive nocturne couvre les trois racines OpenTofu de l'identité (royaume, `acces-proxmox`, `observabilite-grafana`) ; les droits de la console d'administration du royaume `medisphere` sont réduits à la lecture pour les humains (`view-*`), l'écriture passe par OpenTofu ; l'usage du client `svc-tofu-keycloak` depuis une autre adresse que `runner01` déclenche une alerte de sécurité.

---

### M24-E36 — Panne : `kubectl` refuse les jetons

**Démarche de diagnostic**

*Symptômes* : `kubectl` par OIDC répond `Unauthorized` (401) ou `Forbidden` (403), pour tout le monde ou pour certains ; `admin.conf` passe.

*Hypothèses* : jeton refusé (signature/JWKS, émetteur, audience, `exp`, règles CEL de revendications ou d'utilisateur) ; jeton accepté mais identité qui ne correspond plus au RBAC (préfixes, revendication des groupes, liaisons) ; serveur d'API qui ne joint plus l'émetteur (flux, TLS) ; panne de kubelogin côté poste (cache, client).

**Étape 1 — Classer.**
```
admin@adm01:~$ kubectl auth whoami
```
- 401 pour toi **et** Karim, pour tout le monde : variante 1 (ou un problème de signature, d'émetteur, d'horloge : M24-E38) ;
- réponse avec `Groups [oidc-plateforme-admins oidc-plateforme system:authenticated]` puis `Forbidden` partout : variante 2 ;
- 401 pour Julien, Nadia et Sophie, mais toi et Karim passez : variante 3 (un refus **sélectif**, donc une règle qui regarde les revendications).

Si ton propre accès est coupé, la suite se fait par SSH sur les nœuds (compte local `admin`), et par la vue globale de Prometheus pour les métriques ; `admin.conf` seulement si un objet doit être lu, en le déclarant (RB-240).

**Étape 2 — Ce que voit kube-apiserver.**
```
admin@adm01:~$ ssh k8s-cp01 'sudo crictl logs --since 30m $(sudo crictl ps --name kube-apiserver -q) 2>&1 | grep -E "authentication config|Unable to authenticate" | tail -n 4'
I1027 09:12:41.508 … "reloaded authentication config"
E1027 09:14:02.117 … "Unable to authenticate the request" err="[invalid bearer token, oidc: verify token: oidc: expected audience in [\"kubernetes-par1\"] got [\"kubernetes\"]]"
```
Variante 3 : `err="[invalid bearer token, oidc: error evaluating claim validation expression: … kubectl réservé à l équipe Plateforme pendant l audit (SEC-2536, Lucas)]"`. Variante 2 : aucune erreur d'authentification (le jeton est accepté).

Dans la vue globale (kube-prometheus-stack collecte les trois serveurs d'API) :
```
sum by (instance, result) (rate(apiserver_authentication_jwt_authenticator_latency_seconds_count[5m]))
apiserver_authentication_config_controller_automatic_reload_last_timestamp_seconds{status="success"}
count by (hash) (apiserver_authentication_config_controller_last_config_info)
```
`result="failure"` qui monte sur les trois instances (variantes 1 et 3) ; un rechargement réussi à la même minute sur les trois ; trois empreintes `hash` (le gabarit du rôle écrit le nom du nœud en commentaire : elles diffèrent toujours d'un nœud à l'autre), **toutes** différentes de celles d'hier (`… offset 1d`) : le fichier a changé partout, à la même minute.

**Étape 3 — Le fichier, comparé au code.**
```
admin@adm01:~$ for n in k8s-cp01 k8s-cp02 k8s-cp03; do echo "$n $(ssh $n sudo stat -c "'%y inode %i'" /etc/kubernetes/authentification/config.yaml)"
>   ssh $n sudo cat /etc/kubernetes/authentification/config.yaml | yq -o=json '.' | sha256sum; done
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-api-fichiers.yml --check --diff
TASK [k8s_authentification : AuthenticationConfiguration] ***
--- before: /etc/kubernetes/authentification/config.yaml
+++ after: /home/admin/.ansible/tmp/…/config.yaml.j2
@@ -6,7 +6,7 @@
       audiences:
-        - kubernetes-par1
+        - kubernetes
changed: [k8s-cp01]  (idem cp02, cp03)
```
Même contenu (sans les commentaires, que `yq` ne garde pas en JSON) sur les trois nœuds, date de modification identique à quelques secondes près, et aucune exécution du playbook à cette heure-là (journal des pipelines, historique du shell d'`adm01`) : une modification à la main, nœud par nœud. `/var/lib/workbook/pannes.log` sur le nœud contient l'aveu, à lire **après** avoir trouvé. Le journal d'audit ne montre rien : un fichier d'un nœud n'est pas un objet de l'API. Ce qui l'est, ce sont les lectures de `/metrics` faites juste après avec `kubernetes-admin` (`BrisDeGlaceCluster` a dû sonner à cette heure-là, si ta politique d'audit journalise les URL hors ressources comme `/metrics`) : quelqu'un a modifié, puis vérifié avec le bris de glace.

**Cause racine et correctif, par variante.**

*Variante 1 — audience attendue changée* (`kubernetes` → `kubernetes-par1`, « pour préparer le second cluster »). Les ID tokens du client `kubernetes` portent `aud: kubernetes` : tous refusés. Correctif : le rôle.

*Variante 2 — préfixe des groupes changé* (`oidc:` → `oidc-`). L'authentification réussit (le préfixe du **nom** est resté `oidc:`), mais les liaisons de `rbac/oidc.yaml` citent `oidc:plateforme-admins`, `oidc:mediagenda`… : plus rien ne correspond, `Forbidden` partout sauf `auth whoami` et `auth can-i` (permis à `system:authenticated`). Le piège : « réparer » en ajoutant des liaisons pour `oidc-…` ; on remettrait en cohérence un fichier faux, et le préfixe choisi en E16 (`oidc:`, séparateur du cluster) serait perdu.

*Variante 3 — règle de validation ajoutée* (`claims.groups.exists(g, g.startsWith('plateforme'))`, message « réservé à l'équipe Plateforme pendant l'audit »). Un refus **d'authentification** (401) pour qui n'a aucun groupe commençant par `plateforme` : Julien (`mediagenda`), Nadia (`support`), Sophie (`securite`). Restreindre un accès pendant un audit est une décision d'**autorisation** : elle se prend dans le RBAC, par une MR relue, pas par une règle d'authentification posée à la main qui rend les refus muets (401 sans raison pour l'utilisateur).

*Correctif commun* : le rôle, qui écrit le fichier par renommage (le **dossier** est monté, M24-E16 : le pod voit le nouveau fichier) :
```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-api-fichiers.yml --diff
changed: [k8s-cp01] … changed: [k8s-cp02] … changed: [k8s-cp03]
```
Puis, une minute plus tard, `reloaded authentication config` dans le journal des **trois** kube-apiserver et un nouveau `…_automatic_reload_last_timestamp_seconds{status="success"}` ; pas de redémarrage de pod. Contrôle par profil :
```
admin@adm01:~$ kubectl auth whoami                                  # toi : Groups [oidc:plateforme-admins …]
admin@adm01:~$ kubectl auth can-i list pods -n mediagenda-dev --as=oidc:julien.petit --as-group=oidc:mediagenda
yes
admin@adm01:~$ kubectl auth can-i get secrets -n mediagenda-prod --as=oidc:nadia.roussel --as-group=oidc:support
no
```
(`--as` évalue le RBAC, pas l'authentification : demande aussi à Julien un vrai `kubectl get pods -n mediagenda-dev`.) `lab/bin/check 24 36`, puis `--annuler`.

**Prévention.** Une dérive identique sur les trois nœuds ne se voit pas en comparant les nœuds entre eux ; elle se voit en comparant au **code**, ou par ses **effets**. Règles : [`regles/identite.yaml.extrait-E36`](fichiers/M24-E36/observabilite/regles/identite.yaml.extrait-E36) :
- `KubeApiJetonsOidcRefuses` : plus de 50 % d'échecs de l'authentificateur JWT sur 10 minutes avec un minimum de tentatives (variantes 1 et 3, et l'horloge d'E38) ;
- `KubeApiAuthentificationRechargementEchoue` : un rechargement refusé (fichier invalide qui ne prend **pas** effet : la prochaine réparation ne prendrait pas effet non plus).

Pas d'alerte « les nœuds n'ont pas la même empreinte » : l'empreinte couvre les commentaires, et le gabarit y écrit le nom du nœud (une piste d'amélioration du rôle : retirer `inventory_hostname` du commentaire, et l'empreinte devient comparable).

La variante 2 (403) n'a pas d'effet sur ces métriques : elle relève de l'audit (`{job="kubernetes-audit"} | user=~"oidc:.+" | code="403"`, dont un pic est une alerte du locataire `audit` défendable) et d'un **contrôle `--check` planifié** du playbook du plan de contrôle depuis `adm01` (minuterie systemd de l'utilisateur `admin`, sortie en échec si `changed>0`), qui voit toutes les variantes. RB-246, section « kubectl refuse les jetons ».

**Explications**

Le serveur d'API applique, dans l'ordre : signature et `kid` (JWKS en cache), `iss`, `aud` (une des `audiences`), `exp`/`nbf`, les `claimValidationRules`, la correspondance (`claimMappings` : nom et groupes avec leur préfixe), les `userValidationRules`. Tout échec jusque-là est un **401** dont la raison ne quitte jamais le serveur (un attaquant n'apprend rien). Après, c'est l'autorisation : RBAC sur le nom et les groupes **préfixés**. Le rechargement à chaud est une force (pas de redémarrage du plan de contrôle) et un risque (une main sur un nœud agit en une minute, sans trace dans l'API).

**Alternatives**

- Restaurer le fichier depuis `/var/lib/workbook/` ou une sauvegarde : il redeviendrait juste, mais par un chemin que personne ne relit ; le rôle est la source.
- Redémarrer kube-apiserver « pour être sûr » : inutile (rechargement), et un nœud de moins pendant le redémarrage.

**Pièges classiques**

- Se reconnecter, vider le cache de kubelogin, changer de navigateur : le jeton n'a rien.
- Conclure « Keycloak est en panne » sur un 401 : `admin.conf` passe, la découverte répond, les autres services marchent.
- Corriger un seul nœud et tester : deux requêtes sur trois échouent encore.
- Modifier le fichier avec `sed -i` : il écrit un fichier neuf et renomme ; c'est sans danger ici parce que le dossier est monté, mais c'est encore une main hors du code.

**En production chez MédiSphère**

Les fichiers du plan de contrôle (authentification, audit, chiffrement, admission) sont rejoués en `--check` chaque nuit ; leurs droits sont `0600 root` et toute modification hors Ansible est signalée par l'agent de détection (Falco/Tetragon au M26, règle sur l'écriture dans `/etc/kubernetes/`) ; l'usage d'`admin.conf` reste un bris de glace alerté.

---

### M24-E37 — Panne : les nouveaux arrivants n'existent pas

**Démarche de diagnostic**

*Symptômes* : Emma Durand est dans l'annuaire avec le groupe `medidoc` ; les services ne la connaissent pas, ou ne lui donnent aucun droit.

*Hypothèses*, le long du chemin annuaire → jeton : la fédération ne se **lie** plus (compte `svc-keycloak`, TLS, réseau) ; elle se lie mais ne **trouve** pas la personne (base, portée, filtre) ; elle la trouve mais ne lui donne pas ses **groupes** (mappeur, filtre de groupes) ; elle n'est pas encore **synchronisée** (15 min) ; la personne est désactivée ou n'a pas de mot de passe (cas normal d'une arrivée : premier mot de passe à définir, RB-241).

**Étape 1 — L'annuaire a-t-il raison ?**
```
admin@adm01:~$ ssh ipa01
[admin@ipa01 ~]$ kinit <MOI> && ipa user-show emma.durand --all | grep -Ei 'createtimestamp|member of|account disabled|title'
  Member of groups: ipausers, medidoc
  Account disabled: False
  createtimestamp: 20261027091904Z
  Job Title: Développeuse MédiDoc (arrivée, M24-E37)
```

**Étape 2 — Keycloak la voit-il ?** *Users* → recherche `emma` : rien (variantes 1 et 2), ou `emma.durand` présente avec, dans *Groups*, **aucun** groupe (variante 3).

**Étape 3 — L'étendue réelle** (avant de réparer : on doit pouvoir dire à Nadia qui est touché) :
- connexion de Lucas à `https://sso.par1.medisphere.internal/realms/medisphere/account` en fenêtre privée : **refusée** en variante 1 (« Invalid username or password » ou une erreur inattendue), normale sinon. En variante 1, **toutes** les personnes de l'annuaire sont touchées pour les **nouvelles** connexions : Keycloak relit la personne dans l'annuaire avec `svc-keycloak` avant de vérifier son mot de passe. Personne ne s'est plaint parce que les sessions ouvertes (30 min d'inactivité, 10 h au plus) et les jetons déjà émis continuaient ;
- *Evaluate* pour `julien.petit`, puis pour un membre de MédiDoc : en variante 3, **tous** les membres de `medidoc` ont perdu le groupe dans leurs jetons (le mappeur relit les groupes dans l'annuaire, avec le filtre), pas seulement Emma ;
- `FederationLdapEnEchec` (M24-E26) : **firing** en variante 1 depuis l'injection ; muette en variantes 2 et 3 (rien n'échoue : la recherche réussit, elle renvoie juste moins).

**Étape 4 — Le maillon.** *User federation* → `ipa01` :
- *Test authentication* : `Error when trying to connect to LDAP: AuthenticationFailure` en variante 1 ; journal de Keycloak : `LDAP: error code 49 - Invalid Credentials`. Sur `ipa01` :
  ```
  [admin@ipa01 ~]$ sudo grep -A1 'BIND dn="uid=svc-keycloak' /var/log/dirsrv/slapd-PAR1-MEDISPHERE-INTERNAL/access | tail -n 2
  [27/Oct/2026:09:20:11 +0100] conn=4127 op=0 BIND dn="uid=svc-keycloak,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal" method=128 version=3
  [27/Oct/2026:09:20:11 +0100] conn=4127 op=0 RESULT err=49 tag=97 nentries=0 … - Invalid credentials
  ```
- *Custom user LDAP filter* : `(&(!(uid=admin))(createTimestamp<=20261027071904Z))` en variante 2 (une date **deux heures avant** l'injection : un « gel » de l'import). La recherche de Keycloak dans le journal d'accès porte ce filtre ; rejouée avec ton compte :
  ```
  [admin@ipa01 ~]$ ldapsearch -LLL -Y GSSAPI -H ldaps://ipa01.par1.medisphere.internal -b cn=users,cn=accounts,dc=par1,dc=medisphere,dc=internal \
  >   '(&(!(uid=admin))(createTimestamp<=20261027071904Z))' uid | grep -c '^uid:'
  9
  ```
  … et `emma.durand` n'y est pas : elle a été créée après la date. Toutes les personnes existantes passent : la panne ne touche **que** les arrivées postérieures (Emma, et celle de lundi).
- *Mappers* → `groupes-ipa` → *LDAP Filter* : `(|(cn=plateforme-admins)(cn=plateforme)(cn=mediagenda)(cn=securite)(cn=support)(cn=direction))` en variante 3 : `(cn=medidoc)` a disparu (« un groupe vide », selon Lucas, qui confondait avec le groupe Keycloak sans membres locaux : en `READ_ONLY`, les membres sont lus dans l'annuaire, jamais stockés).

**Étape 5 — Qui.** Variantes 2 et 3 : *Admin events*, `UPDATE` sur `components/<id>` par `svc-tofu-keycloak`. Variante 1 : rien dans Keycloak ; dans l'annuaire (`{service="freeipa", fichier="access"}` dans Loki ou le fichier) :
```
conn=4098 op=0 BIND dn="" method=sasl version=3 mech=EXTERNAL
conn=4098 op=0 RESULT err=0 tag=97 nentries=0 … dn="cn=directory manager"
conn=4098 op=2 MOD dn="uid=svc-keycloak,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal"
```
Une liaison automatique de **root** sur `ipa01` par la socket LDAPI, qui modifie le mot de passe du compte système : quelqu'un a commencé une rotation (RB-244 §4, étape 1) sans faire l'étape 2 (Keycloak), et sans passer par le Vault. Aucune alerte de bris de glace : `BrisDeGlaceAnnuaire*` surveille `admin`, pas *Directory Manager* par LDAPI (une piste de plus pour Sophie).

**Cause racine et correctif, par variante.**

*Variante 1 — mot de passe de `svc-keycloak` changé dans l'annuaire seul.* La valeur qui fait foi est au Vault `critique` (`annuaire/vault-critique.yml`) et dans Keycloak (`bind_credential_wo`, posé depuis le Vault) : c'est l'annuaire qui a dérivé. On y remet la valeur du Vault, par la procédure de RB-244 §4 (LDAPI en root, mot de passe sur un descripteur, jamais en argument) :
```
admin@adm01:~/src/identite$ ssh ipa01 'sudo ldappasswd -H ldapi://%2Frun%2Fslapd-PAR1-MEDISPHERE-INTERNAL.socket -Y EXTERNAL \
>   -T /dev/stdin uid=svc-keycloak,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal' \
>   < <(cd ~/src/identite && uv run ansible-vault view annuaire/vault-critique.yml | yq -r '.vault_annuaire_svc_keycloak_mot_de_passe' | tr -d '\n')
```
(Le nom de la clé est celui de ton `vault-critique.yml`, E03.) *Test authentication* passe, l'alerte se résout en 10 minutes. Si l'on soupçonne que quelqu'un connaît le nouveau mot de passe, ou l'ancien, on fait la rotation **complète** (nouveau mot de passe au Vault, annuaire, `svc_keycloak_version_mot_de_passe` + 1, apply) au lieu de remettre l'ancien.

*Variante 2 — filtre des personnes « gelé ».* Dérive du code : `tofu plan` montre `~ custom_user_search_filter = "(&(!(uid=admin))(createTimestamp<=…))" -> "(!(uid=admin))"` ; pipeline sur `main`, `tofu:apply`.

*Variante 3 — groupe retiré du filtre du mappeur.* `tofu plan` : `~ groups_ldap_filter` ; pipeline, apply.

*Après le correctif* : *User federation* → `ipa01` → *Action* → *Sync changed users* (ou attendre 15 min) ; Emma apparaît ; *Evaluate* pour elle : `"groups": ["medidoc"]` ; Lucas se connecte. `lab/bin/check 24 37` (il compare **toutes** les personnes actives de l'annuaire à Keycloak), puis `--annuler` (qui retire Emma de l'annuaire et de Keycloak).

**Prévention.**
- Variante 1 : `FederationLdapEnEchec` **a** sonné ; si personne n'a réagi, c'est son routage (critique → astreinte ?) qui est à revoir, pas la règle. Ajouter à RB-244 §4 : « l'étape 1 sans l'étape 2 dans la minute est une panne : les deux se font dans la même session, ou pas du tout ».
- Variantes 2 et 3 : le contrôle de dérive nocturne de M24-E35 les voit **le lendemain matin** ; une arrivée faite dans la journée tombe dedans. D'où l'ajout à RB-241 : [`RB-241-arrivee.md.extrait-E37`](fichiers/M24-E37/medisphere/docs/securite/identite/runbooks/RB-241-arrivee.md.extrait-E37), étape « vérifier dans Keycloak » (synchronisation des changements, présence, groupes dans un jeton évalué) **avant** d'annoncer l'arrivée prête.
- Le journal de diagnostic modèle : [`AAAA-MM-JJ-M24-E37-arrivee-invisible.md`](fichiers/M24-E37/medisphere/docs/socle/journal/AAAA-MM-JJ-M24-E37-arrivee-invisible.md). RB-246, section « Une personne de l'annuaire n'existe pas dans Keycloak ».

**Explications**

La fédération a trois maillons et trois boutons : la **liaison** (compte de service, *Test authentication*), la **recherche** (base, portée, classes d'objets, filtre : ce que Keycloak considère comme « une personne »), le **mappeur** (ce que Keycloak considère comme « ses groupes »). En mode import, une personne déjà importée garde son identifiant local, mais Keycloak relit l'annuaire à chaque connexion (existence, mot de passe par liaison, groupes) : c'est pour cela qu'un mot de passe de service cassé coupe **toutes** les nouvelles connexions, et qu'un filtre de groupes coupe **tous** les membres du groupe, pas seulement l'arrivée qui a déclenché le ticket.

**Alternatives**

- Créer Emma à la main dans Keycloak : un compte local, sans lien avec l'annuaire, que RB-242 (départ) n'atteindra jamais. Jamais.
- Pour la variante 1, changer le mot de passe dans Keycloak pour celui que l'annuaire a maintenant : on ne le connaît pas (il n'est nulle part), et il faudrait le changer encore pour le mettre au Vault.
- *Sync all users* : inutile pour la variante 2 (même filtre) et lourd ; la synchronisation des changements suffit une fois la cause corrigée.

**Pièges classiques**

- Croire que la panne ne concerne qu'Emma parce que le ticket ne parle que d'elle.
- Lire `createTimestamp` dans `ipa user-show` sans `--all` : il n'apparaît pas.
- Tester la recherche avec `wb-checks` ou `admin` : ce n'est pas la même identité que `svc-keycloak` (droits de lecture différents) ; rejouer le **filtre**, c'est ce qui compte.
- Supprimer et recréer la fédération : identifiants internes, liens `federationLink`, OTP stockés des personnes… tout est perdu.

**En production chez MédiSphère**

L'outil de revue des accès (E30) tourne une partie « écarts annuaire ↔ Keycloak » chaque nuit ; `FederationLdapEnEchec` est critique ; un second serveur d'annuaire (réplica FreeIPA) dans l'URL de la fédération ; les comptes système de l'annuaire ont leur propre alerte d'usage et de modification (MOD sur `cn=sysaccounts`).

---

### M24-E38 — Panne : « jeton expiré » à la première connexion

**Démarche de diagnostic**

*Symptômes* : « token expired », boucles de redirection, codes OTP refusés, ou `kubectl` qui échoue une fois sur trois ; rien de déployé.

*Hypothèses* : horloge de l'**émetteur** (jetons nés vieux, OTP faux) ; horloge d'un **vérificateur** (un service, un serveur d'API sur trois) ; durée de vie mal réglée dans le royaume ; cache de kubelogin ou cookie corrompu (Karim l'a déjà écarté).

**Étape 1 — Décoder un jeton.** Avec le contexte `oidc` (options de `~/.kube/config`) :
```
admin@adm01:~$ kubectl oidc-login get-token --oidc-issuer-url=https://sso.par1.medisphere.internal/realms/medisphere \
>   --oidc-client-id=kubernetes | jq -r .status.token | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null \
>   | jq '{iat, exp, duree: (.exp - .iat), maintenant: now | floor}'
```
- variante 1 : `iat` ≈ maintenant − 600, `exp` ≈ maintenant − 300 : jeton **né expiré** ;
- variante 2 : `duree: 10` ;
- variante 3 : jeton normal (`duree: 300`, `iat` ≈ maintenant).

(Le décodage base64url peut demander un remplissage `=` : la méthode d'E07 fonctionne aussi.)

**Étape 2 — Selon le cas.**

*Variante 1 — horloge d'`idp01` reculée de 10 minutes.*
```
admin@adm01:~$ for h in adm01 idp01 k8s-cp01 k8s-cp02 k8s-cp03; do printf '%-9s %s\n' $h "$(ssh $h date +%s)"; done
adm01     1793092812
idp01     1793092212
…
admin@adm01:~$ ssh idp01 'timedatectl; chronyc tracking'
               Local time: …
System clock synchronized: no
              NTP service: inactive
506 Cannot talk to daemon
admin@adm01:~$ ssh idp01 'sudo journalctl -u chrony --since -2h --no-pager | tail -n 3'
… systemd[1]: Stopping chrony.service - chrony, an NTP client/server…
… systemd[1]: chrony.service: Deactivated successfully.
```
Et dans la vue globale : `node_time_seconds{instance=~"idp01.*"} - timestamp(node_time_seconds{instance=~"idp01.*"})` ≈ −600. Effets : chaque jeton a `exp` dans le passé pour **tout** vérificateur à l'heure (Argo CD : `oidc: token is expired`, kube-apiserver : 401, step-ca refuse le jeton de `step ssh login`) ; l'OTP est calculé par Keycloak pour une heure fausse de 10 min : « Invalid authenticator code » (TOTP, pas de 30 s, fenêtre de tolérance d'un ou deux pas). Selon le service, la connexion peut **sembler** réussir puis échouer à la première requête (Grafana se fie à `expires_in`, relatif, pour sa propre session, mais rafraîchit aussitôt).

*Variante 2 — jeton d'accès à 10 secondes.* Royaume → *Realm settings* → *Tokens* → *Access Token Lifespan* : `10 seconds` ; *Admin events* : `UPDATE` sur `REALM` par `svc-tofu-keycloak`. L'ID token suit la même durée : Argo CD (qui garde l'ID token dans son cookie et rafraîchit 2 min avant l'échéance, `refreshTokenThreshold: 2m`) rafraîchit en permanence ou renvoie au SSO ; kubelogin rafraîchit à chaque commande ; une session SSO existe, donc pas de formulaire : une **boucle** silencieuse. `tofu plan` : `~ access_token_lifespan = "10s" -> "5m"` (ou en secondes selon le fournisseur).

*Variante 3 — horloge du dernier nœud de contrôle avancée de 7 minutes.* Interroger chaque serveur d'API directement :
```
admin@adm01:~$ CA=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
admin@adm01:~$ for n in k8s-cp01 k8s-cp02 k8s-cp03; do printf '%s : ' $n
>   kubectl --server "https://$n.par1.medisphere.internal:6443" --certificate-authority=<(base64 -d <<<"$CA") auth whoami -o jsonpath='{.status.userInfo.username}{"\n"}' 2>&1 | tail -n 1; done
k8s-cp01 : oidc:karim.benali
k8s-cp02 : oidc:karim.benali
k8s-cp03 : error: You must be logged in to the server (Unauthorized)
admin@adm01:~$ ssh k8s-cp03 'sudo crictl logs --since 10m $(sudo crictl ps --name kube-apiserver -q) 2>&1 | grep -m1 "token is expired"'
… err="[invalid bearer token, oidc: verify token: oidc: token is expired (Token Expiry: 2026-10-27 09:31:12 +0000 UTC)]"
```
`k8s-cp03` vit 7 minutes plus tard : un jeton de 5 minutes y est expiré dès sa naissance. Les interfaces web vont bien (elles ne passent pas par ce nœud). kube-prometheus-stack a pu lever `NodeClockNotSynchronising` pour ce nœud au bout de 10 minutes (gravité `warning`, vers `plateforme@`).

**Correctif.**
- Variantes 1 et 3, sur la machine concernée :
  ```
  admin@adm01:~$ ssh idp01 'sudo systemctl enable --now chrony && sleep 2 && sudo chronyc -a makestep && chronyc tracking | grep -E "Reference|System time|Leap"'
  200 OK
  Reference ID    : 0A0A0001 (gw01.par1.medisphere.internal)
  System time     : 0.000012 seconds fast of NTP time
  Leap status     : Normal
  ```
  (Rocky : `chronyd`.) Le démarrage suffit en principe : la configuration du lab (`makestep 1 3`, M04) autorise un **pas** (saut) aux trois premières mesures **après le démarrage** de chrony ; `chronyc -a makestep` l'impose tout de suite et sert surtout quand chrony tournait déjà au moment où l'heure a été changée (il corrigerait sinon en ralentissant ou accélérant l'horloge, des heures pour 10 minutes). Puis le rôle `base` (M04-E15, tâche « Chrony démarré et activé ») en `--check --diff` sur la machine : il signale le service arrêté et, rejoué, l'aurait remis ; c'est sa **fréquence** qui manque, pas son contenu. Pour `k8s-cp03`, reculer de 7 minutes est sans danger pour etcd et le kubelet sur une durée aussi courte ; ne pas attendre.
- Variante 2 : pipeline de `plateforme/identite` sur `main`, `tofu:apply` (le code dit 5 min).

**Ce que deviennent les jetons et sessions émis pendant la panne.** Variante 1 : des sessions SSO datées de 10 minutes plus tôt (elles expireront 10 min plus tôt que prévu, sans gravité) ; des jetons déjà expirés, que personne n'acceptait. Variante 2 : rien à faire, ils expirent seuls. Variante 3 : des jetons de **comptes de service** émis par `k8s-cp03` pendant la panne portent un `iat`/`nbf` dans le futur pour les deux autres nœuds (au-delà de la tolérance d'une minute) : un pod créé pendant la panne a pu voir des appels refusés quelques minutes ; kubelet renouvelle ces jetons, rien à faire sinon le noter.

Vérification : nouveau jeton (`duree: 300`, `iat` ≈ maintenant), code OTP accepté, `for i in $(seq 10); do kubectl auth whoami >/dev/null && echo ok; done` : dix `ok`. `lab/bin/check 24 38`, puis `--annuler`.

**Prévention.** [`regles/temps.yaml`](fichiers/M24-E38/observabilite/regles/temps.yaml) et ses tests [`tests/temps.test.yaml`](fichiers/M24-E38/observabilite/tests/temps.test.yaml) (dans `plateforme/observabilite`, ajoutés à la kustomisation des règles) :
- `HorlogeDecalee` : `abs(node_time_seconds - timestamp(node_time_seconds)) > 30` pendant 2 min, sur toutes les cibles node_exporter (VMs **et** nœuds) ; `critique` pour `idp01`, `ipa01` et les nœuds de contrôle (l'identité et le plan de contrôle), `avertissement` ailleurs ;
- `HorlogeNonSynchronisee` : `min_over_time(node_timex_sync_status[5m]) == 0` pendant 10 min (service de temps arrêté, avant même que l'écart grandisse).

Le rôle `base` garantit déjà le service démarré et activé (M04-E15) : `HorlogeNonSynchronisee` dit **quand** le rejouer, et un passage planifié du rôle en `--check` (comme pour le plan de contrôle en M24-E36) dit qu'il **faut** le rejouer. Pour `ipa01` (Rocky, `chronyd`), vérifie que ton rôle traite aussi ce nom d'unité. RB-246, section « Jeton expiré dès l'émission ».

**Explications**

Un jeton porte des **dates absolues** (`iat`, `exp`, parfois `nbf`) écrites avec l'horloge de l'émetteur et lues avec celle du vérificateur : les deux doivent être d'accord, à la tolérance près (souvent nulle sur `exp` : la bibliothèque `go-oidc` de kube-apiserver et d'Argo CD n'en accorde pas). Avec des jetons de 5 minutes, un écart de 5 minutes suffit à tout casser. L'OTP est encore plus strict : 30 secondes. Une durée de vie courte est une bonne pratique **parce qu'**elle suppose des horloges justes ; la supervision du temps fait partie de la sécurité de l'identité.

**Alternatives**

- Allonger la durée des jetons pour « absorber » les écarts : on affaiblit la sécurité pour cacher une panne d'infrastructure.
- `date -s` à la main : l'heure est juste une minute, le service reste arrêté, la dérive recommence.
- Supprimer `makestep` de la configuration « pour ne jamais faire de saut » : après un arrêt, chrony rattraperait 10 minutes en ralentissant l'horloge, des heures de panne ; le saut au démarrage est voulu.

**Pièges classiques**

- Chercher dans Keycloak (durées, sessions) une panne qui est dans le système d'exploitation.
- Mesurer l'heure sur une seule machine, ou la comparer à ta montre : compare-les **entre elles** et à la source (`gw01`).
- Oublier que la variante 3 ne touche qu'un nœud : un test qui passe ne prouve rien, dix tests de suite si.
- Toucher à l'heure de `pve01` ou des passerelles : ce sont les sources du lab.

**En production chez MédiSphère**

Deux sources de temps internes (`gw01`, `gw02`) et une supervision de leur propre écart à leurs sources externes ; `HorlogeDecalee` en critique pour l'identité et le plan de contrôle ; les machines virtuelles ne prennent jamais l'heure de l'hyperviseur sans chrony ; RB-246 commence par « vérifier les horloges » dès qu'un message parle d'expiration.

---

### M24-E39 — Panne : les droits d'Argo CD sont faux

**Démarche de diagnostic**

*Symptômes* : selon la variante, plus personne ne voit rien (Julien), les administrateurs n'ont plus que la lecture (Karim), ou **le support a un bouton Supprimer** sur la production (Sophie) ; ou encore Argo CD et Grafana voient les droits baisser en même temps.

*Hypothèses* : la revendication `groups` a changé (Keycloak, portée, mappeur : tous les services touchés) ; la politique d'Argo CD a changé (`scopes`, `policy.default`, `policy.csv`) ; un rôle de projet a changé (AppProject) ; un compte local porte le nom d'un groupe.

**Étape 1 — Ce qu'Argo CD lit dans le jeton.**
```
admin@adm01:~$ argocd account get-user-info
Logged In: true
Username: karim.benali@medisphere.internal
Issuer: https://sso.par1.medisphere.internal/realms/medisphere
Groups: plateforme-admins,plateforme
```
Variante 4 : `Groups: /plateforme-admins,/plateforme` : la forme a changé, donc **le jeton** ; tous les services qui comparent des noms de groupes sont touchés (Grafana retombe sur `Viewer` puisque `contains(groups[*], 'plateforme-admins')` est faux mais que la revendication existe ; `kubectl auth whoami` montre `oidc:/plateforme-admins` et le RBAC ne correspond plus ; OAuth2 Proxy refuse ; Harbor ne voit plus `plateforme-admins`). Variantes 1 à 3 : les groupes sont justes, c'est la **politique**.

**Étape 2 — La décision, en place et dans le dépôt.**
```
admin@adm01:~$ argocd account can-i sync applications 'mediagenda/mediagenda-prod'
no
admin@adm01:~/src/k8s$ for g in plateforme-admins plateforme support mediagenda; do printf '%-18s en place: %-4s dépôt: %s\n' $g \
>   "$(argocd admin settings rbac can $g delete applications 'mediagenda/mediagenda-prod' --namespace argocd 2>/dev/null)" \
>   "$(argocd admin settings rbac can $g delete applications 'mediagenda/mediagenda-prod' --policy-file releases/argocd/policy.csv --default-role '' --scopes groups 2>/dev/null)"; done
```
(Le nom de la clé de la politique et la forme exacte de la sortie, `Yes`/`No`, varient selon la version : `argocd admin settings rbac can --help`.)

| Variante | `kubectl -n argocd get cm argocd-rbac-cm -o yaml` | En place contre dépôt |
|---|---|---|
| 1 | `scopes: '[email]'` | `can` évalue un **sujet** donné : il ne voit pas la différence de `scopes` ; seul `get-user-info` + `can-i` d'une vraie personne montre « non » partout |
| 2 | `policy.default: role:admin` | en place : `support delete … Yes`, dépôt : `No` |
| 3 | `g, plateforme-admin, role:plateforme-admin` | en place : `plateforme-admins sync … No` |

`outils/argocd-rbac-tests.sh` passe **au vert** dans les trois cas : il teste le fichier du dépôt, qui est juste. C'est la limite d'un test de politique : il prouve le code, pas ce qui tourne.

**Étape 3 — L'origine.**
```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff
argocd, argocd-rbac-cm, ConfigMap (v1) has changed:
-   policy.default: role:admin
+   policy.default: ""
admin@adm01:~$ kubectl -n argocd get cm argocd-rbac-cm -o yaml --show-managed-fields | yq '.metadata.managedFields[] | [.manager, .operation, .time]'
- [helm, Update, 2026-10-20T…]
- [kubectl-patch, Update, 2026-10-26T17:42:…]
```
Journal d'audit (Loki `audit`) :
```
{job="kubernetes-audit"} | object_ns="argocd" | object_name="argocd-rbac-cm" | verb=~"patch|update"
```
→ `user="kubernetes-admin"` (métadonnées structurées de l'audit, M22-E07), adresse de `k8s-cp01`, la veille à 17 h 42 ; `BrisDeGlaceCluster` a sonné à cette heure-là, et personne n'a ouvert de procès-verbal (RB-240). Variante 4 : rien dans le cluster ; *Admin events* de Keycloak : `UPDATE` sur `client-scopes/<id de groupes>/protocol-mappers/models/<id>` par `svc-tofu-keycloak`.

**Cause racine et correctif, par variante.**

*Variante 1 — `scopes: '[email]'`.* Argo CD cherche les sujets des lignes `g` dans la revendication `email` : `karim.benali@medisphere.internal` ne correspond à aucune ligne, et `policy.default` est vide : aucun droit. (Le compte local `ci-lecture` fonctionne encore : un compte local est évalué par son nom, quel que soit `scopes`.)

*Variante 2 — `policy.default: role:admin`.* « Pour débloquer Julien » : **toute** personne authentifiée de l'annuaire, y compris `direction` et `support`, est administratrice d'Argo CD : synchroniser, supprimer, modifier les projets et les dépôts. Personne ne s'en plaint : c'est la panne la plus grave du lot, et elle n'a été vue que parce que Nadia a été honnête.

*Variante 3 — `g, plateforme-admin, …`.* Un « s » de moins : la ligne ne correspond plus au groupe, les administrateurs retombent sur ce que leur donne leur autre groupe (`plateforme` → `role:lecture`).

*Correctif des variantes 1 à 3* : la release est la source :
```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff     # seule la ConfigMap revient
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd apply
```
Argo CD relit `argocd-rbac-cm` à chaud ; `argocd account can-i …` redonne les réponses attendues ; `helmfile diff` vide.

*Variante 4 — chemin complet dans le mappeur `groups`.* `tofu plan` : `~ full_path = true -> false` sur `keycloak_openid_group_membership_protocol_mapper.groups` ; pipeline sur `main`, `tofu:apply`. Les nouveaux jetons ont des noms courts ; chaque personne doit se **reconnecter** (Argo CD et Grafana gardent les groupes de la connexion), ou attendre le rafraîchissement.

**Après une variante 2 : l'enquête.** La fenêtre va de l'écriture (`managedFields`, audit) à ton `helmfile apply`. Pendant cette fenêtre, qui a fait quoi dans Argo CD ?
```
admin@adm01:~$ for a in $(argocd app list -o name); do argocd app history "$a" | awk -v a="$a" 'NR>1 {print a, $0}'; done | sort -k3
admin@adm01:~$ kubectl -n argocd get events --field-selector involvedObject.kind=Application --sort-by=.lastTimestamp
```
et dans l'audit du cluster, les écritures sur `applications.argoproj.io`, `appprojects.argoproj.io` et les Secrets de dépôts d'`argocd` faites par le compte de service d'`argocd-server` pendant la fenêtre (une action d'interface devient une écriture de ce compte) ; le journal d'`argocd-server` (Loki, `namespace="argocd"`) donne la personne derrière chaque action. Conclusion écrite pour Sophie : fenêtre, personnes connectées pendant la fenêtre (événements `LOGIN` du client `argocd` dans Keycloak), actions faites, actions **à risque** (suppression, synchronisation de production, modification de projet ou de dépôt) ; si une seule action anormale existe, c'est un incident de sécurité, pas une panne.

**Prévention.**
- [`loki/regles/audit/identite.yaml.extrait-E39`](fichiers/M24-E39/observabilite/loki/regles/audit/identite.yaml.extrait-E39) : `ConfigurationArgoCDModifiee` : toute écriture (`create|update|patch|delete`) dans `argocd-cm`, `argocd-rbac-cm` ou `argocd-cmd-params-cm` ; gravité `avertissement`, `equipe: securite` (route `equipe="securite"`, M24-E28) : un `helmfile apply` annoncé est un faux positif accepté, le reste est une question.
- Contrôle de dérive de la configuration d'Argo CD : [`.gitlab-ci.yml.extrait-E39`](fichiers/M24-E39/k8s/.gitlab-ci.yml.extrait-E39) et [`outils/argocd-derive.sh`](fichiers/M24-E39/k8s/outils/argocd-derive.sh) pour `plateforme/k8s` : chaque nuit, le pipeline planifié **rend** la release (`helmfile template`, sans accès au cluster) et compare les clés de `argocd-cm` et `argocd-rbac-cm` à celles du cluster, lues par un compte de service qui n'a que `get` sur ces deux ConfigMaps. Un `helmfile diff --detailed-exitcode` (M17-E10) ferait mieux (toute la release), mais Helm lit l'historique de la release dans des **Secrets** d'`argocd` : il faudrait donner à la CI la lecture des Secrets d'Argo CD, ce qu'on refuse.
- `rbac-tests.txt` contient déjà `non support sync applications mediagenda/mediagenda-prod` et `oui plateforme-admins sync applications mediagenda/mediagenda-prod` : ils sont **verts** pendant les variantes 1 à 3, parce que la faute n'est pas dans le dépôt. C'est l'enseignement : le test protège la MR ; l'alerte et le contrôle de dérive protègent la production.
- RB-246, section « Droits faux dans un service ».

**Explications**

Argo CD décide en trois temps : il vérifie le jeton (émetteur, signature, audience), il construit la liste des **sujets** (le nom du compte, puis les valeurs des revendications listées dans `scopes`), puis Casbin évalue `policy.csv` pour chaque sujet, et `policy.default` pour tout le monde. `scopes` et `policy.default` sont donc les deux leviers les plus puissants du fichier : le premier peut retirer tous les droits d'un coup, le second en donner à tout le monde. Et la revendication `groups`, elle, est fabriquée **une fois** par Keycloak pour tous les services : la changer change tous les droits partout.

**Alternatives**

- `kubectl -n argocd edit cm argocd-rbac-cm` pour corriger : immédiat, mais c'est refaire le geste fautif dans l'autre sens ; on ne le fait qu'en urgence, suivi de `helmfile diff` (qui doit être vide) et d'une ligne dans le journal.
- Gérer Argo CD par lui-même (Application `argocd` en *self-heal*) : la dérive serait défaite en secondes ; choix écarté en M20 (ADR-0200 : ne pas faire dépendre Argo CD de lui-même). Une Application en synchronisation **manuelle** qui ne fait que **montrer** la dérive est un compromis.

**Pièges classiques**

- Ajouter `g, /plateforme-admins, …` dans `policy.csv` (variante 4) : Argo CD « remarche », Grafana, Harbor, Kubernetes et OAuth2 Proxy restent cassés, et la politique a deux formes de noms.
- Retirer `policy.default` sans regarder ce qui a été fait pendant la fenêtre (variante 2).
- Se fier au vert de `argocd-rbac-tests.sh` : il teste le dépôt.
- Corriger en ajoutant des personnes dans `policy.csv` : on revient aux comptes nominatifs que M24-E13 a supprimés.

**En production chez MédiSphère**

Toute écriture dans la configuration d'Argo CD hors `helmfile apply` déclenche une alerte de sécurité ; le contrôle de dérive des releases de la couche de base tourne chaque nuit ; l'usage d'`admin.conf` sans procès-verbal est un incident ; `policy.default` est vérifiée par la revue des accès (E30) chaque mois.

---

### M24-E40 — Panne : SSH et sudo refusés sur les VMs

**Démarche de diagnostic**

*Symptômes* : une personne de l'annuaire n'entre plus (ou n'a plus `sudo`) sur une partie des VMs ; le compte local `admin` passe. Rien n'a été « déployé ».

*Hypothèses*, de l'extérieur vers l'intérieur : (1) le **certificat** (expiré, mauvaise CA, mauvais principal) ; (2) le **principal** n'est pas accepté par sshd pour ce compte ; (3) le **compte** n'existe pas sur la VM (NSS, SSSD) ; (4) l'**accès** est refusé (PAM *account*, HBAC) ; (5) l'**élévation** est refusée (règles sudo).

**Étape 1 — Où ça casse.** Sur une VM concernée, en `admin` :

```
admin@mon01:~$ sudo journalctl -u ssh --since -30min | grep -E 'nadia|lucas|karim|principal|pam_sss' | tail
admin@mon01:~$ sudo journalctl -u sssd --since -30min --no-pager | tail
```

| Ce que dit sshd | Étape | Variante probable |
|---|---|---|
| `pam_sss(sshd:account): Access denied for user nadia.roussel: 6 (Permission denied)` | HBAC | 1 |
| connexion acceptée, puis `sudo: … is not allowed to run sudo on …` dans `journalctl -t sudo` | sudo | 2 |
| `Invalid user karim.benali from …` ou `error: AuthorizedPrincipalsCommand …` | compte (NSS) | 3 |
| `error: Certificate does not contain an authorized principal` | principal | 4 |

**Variante 1 — règle HBAC `hbac-support` désactivée.**

```
admin@mon01:~$ sudo sssctl user-checks -a acct -s sshd nadia.roussel | tail -n 2
pam_acct_mgmt: Permission denied
[admin@ipa01 ~]$ kinit admin   # ou ton compte, membre de plateforme-admins
[admin@ipa01 ~]$ ipa hbactest --user=nadia.roussel --host=mon01.par1.medisphere.internal --service=sshd
---------------------
Access granted: False
---------------------
  Not matched rules: hbac-plateforme
[admin@ipa01 ~]$ ipa hbacrule-show hbac-support --all --raw | grep -E 'ipaenabledflag|modifytimestamp|modifiersname'
  ipaenabledflag: FALSE
  modifytimestamp: 20261027215412Z
```

`hbactest` n'évalue que les règles **actives** : `hbac-support` n'apparaît même pas dans « Not matched ». `ipa hbacrule-find` la montre désactivée ; le journal d'accès de 389-ds (Loki `audit`, `{service="freeipa", fichier=~".*access"} |= "hbac-support"`) dit quand et par quelle liaison. Correctif : `annuaire/hbac.yml` est juste (la règle y est décrite active) : relancer le job `annuaire:appliquer` de `plateforme/identite` suffit à la réactiver (le module `ipahbacrule` remet `state: enabled`), et c'est la preuve que le code fait foi. Vérifie : `hbactest` à `True`, `sssctl user-checks` à `Success` (après `sudo sss_cache -E` si tu ne veux pas attendre le cache).

**Variante 2 — règle sudo restreinte à `ipa01`.**

```
admin@nbx01:~$ sudo -l -U lucas.martin
User lucas.martin is not allowed to run sudo on nbx01.
[admin@ipa01 ~]$ ipa sudorule-show sudo-plateforme
  Rule name: sudo-plateforme
  Enabled: TRUE
  User Groups: plateforme
  Hosts: ipa01.par1.medisphere.internal
  Sudo Allow Command Groups: consultation-journaux
  RunAs External Group: systemd-journal
```

« Host category: all » a disparu au profit d'un hôte nommé (sur lequel personne ne se connecte). Correctif : `annuaire:appliquer` (le module `ipasudorule` remet `hostcategory: all` et retire l'hôte) ; sur les VMs, le changement arrive au rafraîchissement suivant de SSSD, ou tout de suite avec `sudo sss_cache -R` (règles sudo) ; `sudo -l -U lucas.martin` reliste `journalctl` et `systemctl status *`. Attention : le module refuse de poser `hostcategory: all` tant qu'un hôte est nommé dans la règle ; c'est lui qui gère l'ordre, pas toi à la main.

**Variante 3 — SSSD ne démarre plus sur `nbx01`.**

```
admin@nbx01:~$ systemctl status sssd --no-pager | head -n 5
× sssd.service - System Security Services Daemon
     Active: failed (Result: exit-code) since …
admin@nbx01:~$ sudo journalctl -u sssd -b --no-pager | grep -i -m3 'permission\|access'
… Unexpected access to '/etc/sssd/sssd.conf' by other users
admin@nbx01:~$ sudo stat -c '%U:%G %a %y' /etc/sssd/sssd.conf
root:root 644 2026-10-27 22:03:11.000000000 +0100
admin@nbx01:~$ getent -s sss passwd karim.benali; echo $?
2
```

Personne de l'annuaire n'existe plus sur la VM : sshd refuse le compte avant même de regarder le certificat (`Invalid user`), la commande de principaux ne répond rien. Le compte local `admin` n'est pas concerné (`filter_users`, M24-E19) : c'est ce qui te permet de réparer. Cause : un fichier de configuration lisible par tous (une copie « pour regarder », un `chmod` maladroit). Correctif : rejouer le rôle `freeipa_client` sur `nbx01` (`--check --diff` d'abord : il signale le mode du fichier si la tâche le fixe ; sinon c'est une **prévention** à ajouter : `mode: "0600"` explicite sur `sssd.conf`), puis `sudo systemctl restart sssd`, `sudo sssctl domain-status par1.medisphere.internal` (« Online »), `getent -s sss passwd karim.benali`. Si SSSD avait simplement été arrêté (repli du script), le diagnostic est le même sans la ligne de permission : `systemctl start sssd` et la question « pourquoi était-il arrêté, et pourquoi personne ne l'a vu ? ».

**Variante 4 — principal du certificat changé par step-ca.**

```
admin@adm01:~$ step ssh login <MOI>@medisphere.internal --provisioner keycloak
admin@adm01:~$ ssh-add -L | grep cert | step ssh inspect | sed -n '/Principals/,/Critical/p'
        Principals:
                <MOI>@medisphere.internal
admin@mon01:~$ /usr/local/sbin/principaux-annuaire <MOI>
<MOI>
admin@adm01:~$ curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://ca01.par1.medisphere.internal/provisioners \
>   | jq -r '.provisioners[] | select(.name == "keycloak") | .options.ssh.template' | grep principals
  "principals": [{{ toJson .Token.email }}],
admin@ca01:~$ sudo ls -l --time-style=+%F_%T /etc/step-ca/config/ca.json; sudo journalctl -u step-ca --since -1d | grep -i -m2 'start'
```

Le certificat est valable, signé par la bonne CA, mais il porte l'**adresse** au lieu de l'identifiant : sshd cherche ce principal pour le compte `<MOI>` et ne le trouve ni dans `/etc/ssh/principaux/<MOI>` ni dans la sortie de `principaux-annuaire`. Tout le monde est touché, `ms-ssh-cert` (provisioner `admin`, principaux `admin`) ne l'est pas. `ca.json` a été modifié hors Ansible (date du fichier, redémarrage de step-ca). Correctif : rejouer le rôle `step_ca` sur `ca01` (`--check --diff --limit ca01` montre l'écart du gabarit ; le rôle redémarre step-ca et vérifie `/health`), puis un **nouveau** `step ssh login` (les certificats déjà émis avec le courriel restent inutilisables jusqu'à leur expiration : `ssh-add -D`).

**Clôture commune** : les tests de l'étape 1 repassent, la personne du ticket confirme, `lab/bin/check 24 40`, puis `lab/bin/break 24 40 --annuler` (qui ne revient jamais sur ta réparation).

**Prévention et détection** (section `## 6. SSH ou sudo refusé sur les VMs` de [RB-246](fichiers/M24-E43/medisphere/docs/securite/identite/runbooks/RB-246-sso-indisponible.md)) :
- dérive de l'annuaire : le pipeline planifié de M24-E35 lance déjà `annuaire:verifier`, mais ce job **affiche** l'écart sans échouer ; on lui ajoute `annuaire:derive` ([extrait de CI](fichiers/M24-E40/identite/.gitlab-ci.yml.extrait-E40)), qui échoue quand le `--check` annonce un changement ; il aurait trouvé les variantes 1 et 2 dans la nuit ;
- SSSD arrêté : `node_systemd_unit_state{name="sssd.service",state="active"} == 0` sur les hôtes inscrits (collecteur `systemd` de node_exporter, si ton rôle l'active ; sinon une sonde `textfile`), [règle](fichiers/M24-E40/observabilite/regles/acces-vms.yaml) ;
- `ca.json` modifié hors Ansible : le rôle `step_ca` joué en `--check` par une CI planifiée, ou une empreinte de `ca.json` relevée par le collecteur `textfile` ; la liste publique des provisioners comparée à `group_vars` (c'est ce que fait le contrôle).

**Explications**

Une connexion par certificat franchit **cinq** contrôles indépendants, chacun avec son propre journal : sshd vérifie la signature (CA d'utilisateurs) puis le principal ; NSS doit connaître le compte ; PAM *account* (SSSD) applique HBAC ; `sudo` applique ses propres règles, lues elles aussi par SSSD. Le compte local `admin` court-circuite les trois derniers (fichiers locaux, `filter_users`) et un autre provisioner pour les deux premiers : c'est voulu, c'est le bris de glace. `ipa hbactest` donne la décision **de l'annuaire**, `sssctl user-checks` celle **de la VM** (avec son cache) : quand elles divergent, le problème est sur la VM. Le cache de SSSD explique les symptômes « intermittents » après un changement : une VM peut appliquer l'ancienne règle quelques minutes, une autre la nouvelle.

**Alternatives**

`ipa hbacrule-enable` ou `ipa sudorule-mod` à la main corrigent en dix secondes, mais l'annuaire est en code (M24-E03) : une correction à la main laisse le code et la réalité égaux par hasard, et la dérive suivante passera aussi inaperçue. Faire `sss_cache -E` partout par Ansible accélère la propagation d'une règle ; c'est un geste d'incident, pas une configuration.

**Pièges classiques**
- Tester avec **son** compte (membre de `plateforme-admins`, qui passe partout) et conclure « chez moi ça marche ».
- Chercher dans le certificat une panne de HBAC (ou l'inverse) faute d'avoir lu le journal de sshd.
- Réactiver `allow_all` « pour débloquer » : tout le monde entre partout, la panne est masquée, et c'est un incident de sécurité (RB-240).
- Oublier le cache de SSSD et croire que la correction n'a pas marché.
- Variante 4 : redemander un certificat avant la correction de step-ca, puis oublier de le retirer de l'agent.

**En production chez MédiSphère**

Dérive de l'annuaire vérifiée chaque nuit, alerte sur SSSD arrêté, `ca.json` sous contrôle d'intégrité, revue de toute modification des règles HBAC et sudo par Sophie (règle d'approbation sur `annuaire/hbac.yml` et `annuaire/sudo.yml`), et RB-240 qui rappelle que `allow_all` ne se réactive jamais comme correctif.

---

### M24-E41 — Panne : boucle de redirection derrière OAuth2 Proxy

**Démarche de diagnostic**

*Symptômes* : l'interface de Mailpit ne s'ouvre plus par le SSO ; les autres instances d'OAuth2 Proxy (Hubble, Pyroscope, Pyrra) marchent. La panne est donc propre à l'instance de `mon01`, ou à **son** URI de retour dans le client commun.

*Hypothèses* : Keycloak refuse la demande (client, URI de retour) ; Keycloak accepte mais renvoie ailleurs (URI de retour d'une autre instance) ; le retour arrive au bon endroit mais le mandataire ne retrouve pas son cookie (attributs du cookie, horloge, secret de cookie changé entre deux requêtes) ; l'échange du code échoue (secret du client, PKCE).

**Étape 1 — La chaîne, sans navigateur.**

```
admin@adm01:~$ curl -s -o /dev/null -D - https://mon01.par1.medisphere.internal:8443/ | grep -iE '^(HTTP|location|set-cookie)' | sed 's/state=[^&]*/state=…/; s/=[A-Za-z0-9_-]\{20,\}/=…/'
HTTP/2 302
location: https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/auth?client_id=oauth2-proxy&code_challenge=…&code_challenge_method=S256&redirect_uri=https%3A%2F%2Fmon01.par1.medisphere.internal%3A8443%2Foauth2%2Fcallback&response_type=code&scope=openid+email+profile&state=…
set-cookie: __Host-oauth2-mailpit_csrf=…; Path=/; Expires=…; HttpOnly; Secure; SameSite=Lax
```

C'est l'état **sain** : à comparer à ce que tu vois pendant la panne.

**Variante 1 — `cookie_domains` posé sur un cookie `__Host-`.**

```
set-cookie: __Host-oauth2-mailpit_csrf=…; Path=/; Domain=par1.medisphere.internal; Expires=…; HttpOnly; Secure; SameSite=Lax
admin@mon01:~$ sudo journalctl -u oauth2-proxy-mailpit --since -15min | grep -m2 -i csrf
… [AuthFailure] Invalid authentication via OAuth2: unable to obtain CSRF cookie: CSRF cookie with name '__Host-oauth2-mailpit_csrf' was not found
admin@mon01:~$ sudo grep -n cookie_domains /etc/oauth2-proxy/mailpit/oauth2-proxy.cfg
24:cookie_domains = [".par1.medisphere.internal"] # M24-E41 Lucas : session commune avec Hubble
```

Le navigateur **refuse** un cookie `__Host-` qui porte un `Domain` (l'onglet Réseau le marque « bloqué ») : le cookie de CSRF n'existe pas au retour de Keycloak, OAuth2 Proxy répond 403 « Login Failed: Unable to find a valid CSRF token », la personne clique, Keycloak a déjà une session (pas de formulaire), et la boucle recommence. Keycloak n'y est pour rien : ses événements montrent des `LOGIN` réussis pour `oauth2-proxy`, puis **aucun** `CODE_TO_TOKEN` (le mandataire n'a jamais échangé le code). L'intention de Lucas (partager la session avec Hubble) est d'ailleurs impossible : chaque instance chiffre ses cookies avec **son** secret. Correctif : rejouer le rôle `oauth2_proxy` sur `mon01` (`--check --diff --limit mon01` montre la ligne en trop) ; il réécrit le fichier et redémarre l'instance.

**Variante 2 — l'URI de retour de `mon01` retirée du client.**

```
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' -G --data-urlencode client_id=oauth2-proxy \
>   --data-urlencode redirect_uri=https://mon01.par1.medisphere.internal:8443/oauth2/callback --data-urlencode response_type=code \
>   --data-urlencode scope=openid https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/auth
400
admin@adm01:~/src/identite$ tofu -chdir=tofu plan | grep -A4 valid_redirect_uris
      ~ valid_redirect_uris = [
          - "https://mon01.par1.medisphere.internal/oauth2/callback",
          + "https://mon01.par1.medisphere.internal:8443/oauth2/callback",
```

Keycloak compare l'URI de retour **exactement** (RFC 9700 : pas de correspondance partielle) : la même sans le port est une autre URI. La page d'erreur s'affiche **chez Keycloak**, mais la panne est dans le client ; l'événement `LOGIN_ERROR` porte `error=invalid_redirect_uri` (Loki `audit`). Correctif : `tofu plan` montre la dérive, le pipeline (`apply` manuel protégé) remet le code ; aucune modification à la main dans la console. Détection : le contrôle de dérive nocturne `tofu:derive` de M24-E35 l'aurait signalée au plus tard le lendemain matin, avant Nadia si la panne date de la veille.

**Variante 3 — `redirect_url` de l'instance remplacée par celle de Hubble.**

```
location: https://sso…/auth?client_id=oauth2-proxy&…&redirect_uri=https%3A%2F%2Fhubble.apps.par1.medisphere.internal%2Foauth2%2Fcallback&…
admin@adm01:~$ kubectl -n oauth2-proxy logs deploy/oauth2-proxy-hubble --since=15m | grep -m1 -i csrf
… Invalid authentication via OAuth2: unable to obtain CSRF cookie …
```

Keycloak **accepte** : cette URI est enregistrée pour le client `oauth2-proxy` (pour une **autre** instance). La personne se connecte, Keycloak envoie le code à l'instance de Hubble, qui ne connaît ni le cookie de CSRF posé par `mon01` (autre hôte : un cookie `__Host-` ne part que vers l'hôte qui l'a posé) ni son vérificateur PKCE ; elle répond « Login Failed ». C'est l'illustration d'un **compromis** d'E18 : un client commun à plusieurs instances accepte n'importe laquelle de leurs URI de retour. Ici, la protection a tenu (CSRF, PKCE, cookie `__Host-` : le code n'a servi à rien chez Hubble) ; avec un client par instance, Keycloak aurait refusé dès la première étape (symptôme de la variante 2, diagnostic plus rapide). Correctif : rôle `oauth2_proxy` rejoué sur `mon01`.

**Clôture** : la chaîne saine de l'étape 1, connexion réelle de Nadia, `lab/bin/check 24 41`, `lab/bin/break 24 41 --annuler`.

**Prévention** : le gabarit du rôle `oauth2_proxy` ne permet déjà ni domaine de cookie ni `redirect_url` libre (elle est **calculée** à partir de `url_publique`) ; ce qui manquait, c'est de voir une modification **à la main** : deux assertions de plus dans les contrôles du rôle ([extrait de `controles.yml`](fichiers/M24-E41/ansible/roles/oauth2_proxy/tasks/controles.extrait-E41.yml)) lisent `Location` et `Set-Cookie` comme le check, y compris lors d'un passage `--check` planifié. Section `## 7. OAuth2 Proxy : boucle ou « Login Failed »` de [RB-246](fichiers/M24-E43/medisphere/docs/securite/identite/runbooks/RB-246-sso-indisponible.md).

**Explications**

OAuth2 Proxy relie la requête de départ et le retour par un cookie de CSRF (qui porte aussi le vérificateur PKCE et le `nonce`) : sans lui, il refuse le code, à raison (sinon n'importe qui pourrait lui faire échanger un code obtenu ailleurs, M24-E45 question 11). Un cookie préfixé `__Host-` doit être `Secure`, `Path=/` et **sans** `Domain` : le navigateur garantit ainsi qu'il a été posé par cet hôte exact en HTTPS et qu'il n'est envoyé qu'à lui. Le serveur ne voit jamais qu'un cookie a été refusé : seul le navigateur le sait, d'où l'intérêt des outils de développement. Les trois variantes ont le même symptôme vu de loin (« on tourne en rond ») et trois endroits différents à corriger : le mandataire, le fournisseur, encore le mandataire.

**Alternatives**

Un client Keycloak par instance (`oauth2-proxy-mailpit`, `oauth2-proxy-hubble`…) : variante 3 impossible, révocation et rotation fines, au prix d'un secret par instance (RB-244). Une instance d'OAuth2 Proxy unique avec `--whitelist-domain` et un cookie de domaine (`.apps.par1…`) : une seule session pour toutes les interfaces, mais un cookie qui part vers **tous** les sous-domaines (et un domaine différent pour `mon01`) ; c'est ce que Lucas voulait, et c'est un choix d'architecture, pas un réglage à poser en passant.

**Pièges classiques**
- Corriger la variante 2 dans la console de Keycloak : le prochain `tofu apply` remet… la valeur du code (juste), mais la dérive suivante ne sera pas vue avant la panne.
- Effacer les cookies du navigateur et conclure « c'était un problème de cache » quand la boucle disparaît pendant cinq minutes.
- Chercher dans les journaux de Keycloak une panne qui n'y laisse que des connexions **réussies** (variantes 1 et 3).

**En production chez MédiSphère**

`tofu:derive` (E35) et le rôle `oauth2_proxy` en `--check` planifiés chaque nuit ; un client par instance quand les instances se multiplient (décision à consigner dans ADR-0240 à sa prochaine révision) ; le contrôle de bout en bout d'E46 (une visite sans session vérifie `Location` et `Set-Cookie`) joué par le témoin de `mon01`.

**Écart à la fiche du module** : « cookie trop gros (groupes nombreux) » et « en-têtes `X-Forwarded-*` de la Gateway » ne sont pas injectés : le premier exige des jetons de plusieurs dizaines de kilooctets pour qu'un mandataire réponde `431` (OAuth2 Proxy découpe lui-même un cookie de plus de 4 Ko en `_0`, `_1`…), le second exige de modifier la Gateway commune ou des valeurs gérées par Argo CD (`selfHeal` défait la panne en quelques secondes). Diagnostic attendu, pour mémoire : cookie trop gros → `Set-Cookie` multiples, `431 Request Header Fields Too Large` chez le mandataire en amont, correctif `session_store_type = "redis"` (la session côté serveur, le cookie ne porte qu'un identifiant) ou portées réduites ; `X-Forwarded-*` → `trusted_proxy_ips` qui ne contient plus la plage de l'Envoy, adresse cliente et schéma faux dans les journaux, règles fondées sur l'IP qui se trompent.

---

### M24-E42 — Panne : le fournisseur d'identité ne répond plus comme avant

**Démarche de diagnostic**

*Symptômes* : tous les services sont touchés en même temps ; donc le fournisseur ou sa publication, pas un client.

*Hypothèses* (les quatre situations) : Keycloak **arrêté** ou en échec ; Keycloak **injoignable** par la publication (HAProxy, TLS, contrôle de santé) ; Keycloak répond **autre chose** (nom public, émetteur, certificat) ; Keycloak **saturé** (base, mémoire).

**Étape 1 — Les cinq premières minutes.**

```
admin@adm01:~$ E=https://sso.par1.medisphere.internal/realms/medisphere
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' $E/.well-known/openid-configuration
admin@adm01:~$ curl -s $E/.well-known/openid-configuration | jq -r '.issuer, .authorization_endpoint'
admin@adm01:~$ ssh idp01 'systemctl is-active keycloak; curl -sk https://127.0.0.1:9000/health/ready'
admin@adm01:~$ ssh lb01 'sudo journalctl -u haproxy --since -30min | grep -i "be_sso" | tail -n 3'
```

| Découverte | `/health/ready` sur `idp01` | HAProxy | Situation | Variante |
|---|---|---|---|---|
| `200`, émetteur `https://sso…:8443/realms/medisphere` | `UP` | serveur UP | répond autre chose | 1 |
| `503` | `UP` | `is DOWN, reason: Layer6 invalid response, info: "SSL handshake failure"` | injoignable (TLS) | 2 |
| `503` | `UP` | `is DOWN, reason: Layer7 wrong status, code: 404` | injoignable (contrôle de santé) | 3 |
| `200` lent, ou `500` par moments | `UP` ou `DOWN` (base) par moments | UP, parfois DOWN | saturé | 4 |

Premier message (modèle de RB-246) : « SSO dégradé depuis HH:MM pour tous les services ; accès de secours disponibles (RB-240) ; diagnostic en cours ; prochain point HH:MM. »

**Variante 1 — `hostname` avec le port 8443.**

```
admin@idp01:~$ sudo -u keycloak /opt/keycloak/bin/kc.sh show-config | grep -E 'hostname|proxy'
  kc.hostname =  https://sso.par1.medisphere.internal:8443 (keycloak.conf)
  kc.proxy-headers =  xforwarded (keycloak.conf)
admin@idp01:~$ sudo grep -n -B1 '^hostname=' /opt/keycloak/conf/keycloak.conf
admin@idp01:~$ sudo ls -l --time-style=+%F_%T /opt/keycloak/conf/keycloak.conf; journalctl -u keycloak --since -1d | grep -m1 'started in'
```

Keycloak n'a qu'**un** nom public (options *hostname v2*) : il le met dans l'émetteur (`iss`) de chaque jeton, dans la découverte, et dans chaque URL qu'il fait suivre au navigateur (formulaires, redirections). Avec `:8443`, les services refusent les jetons (émetteur différent de celui configuré : Grafana « Login failed », kube-apiserver `Unauthorized`, OAuth2 Proxy refuse même de démarrer s'il redémarre : la découverte ne correspond plus à `oidc_issuer_url`) et le navigateur part vers `sso…:8443`, que la VIP ne publie pas. Correctif : rejouer le rôle `keycloak` sur `idp01` (`--check --diff` : la ligne `hostname` diffère ; le rôle redémarre Keycloak). Les sessions SSO survivent au redémarrage (base), les jetons émis pendant la panne sont inutilisables (mauvais `iss`) : chaque service redemande.

**Variante 2 — certificat autosigné au nom public.**

```
admin@lb01:~$ openssl s_client -connect idp01.par1.medisphere.internal:8443 -servername idp01.par1.medisphere.internal \
>   -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt -verify_hostname idp01.par1.medisphere.internal </dev/null 2>&1 \
>   | grep -E 'subject=|issuer=|Verify return'
subject=O=M24-E42, CN=sso.par1.medisphere.internal
issuer=O=M24-E42, CN=sso.par1.medisphere.internal
Verify return code: 18 (self-signed certificate)
admin@idp01:~$ sudo journalctl -u cert-renewer@keycloak --since -1d --no-pager | tail -n 3
```

Deux défauts : émetteur inconnu (autosigné) **et** mauvais nom (HAProxy vérifie `idp01…`, M24-E04 : le nom public `sso` est porté par le certificat des **répartiteurs**, TLS terminé chez eux). Le contrôle de santé (`check-ssl`) échoue pour la même raison : serveur DOWN, `503`. Le renouvellement automatique échoue aussi (`step ca renew` exige un certificat signé par la CA) : c'est un indice, et la raison pour laquelle le correctif n'est pas « attendre la minuterie ». Correctif : rejouer le rôle `certificats_acme` sur `idp01` (il redemande un certificat ACME pour `idp01` quand le certificat présent n'est pas valable pour ses noms ; sinon : retirer les deux fichiers et rejouer), puis redémarrer Keycloak (ou attendre `https-certificates-reload-period`) ; vérifier depuis **un répartiteur**.

**Variante 3 — contrôle de santé sur le port du trafic.**

```
admin@lb01:~$ sudo grep -nE 'backend be_sso|server idp0' /etc/haproxy/haproxy.cfg
admin@lb01:~$ curl -sk -o /dev/null -w '%{http_code}\n' https://idp01.par1.medisphere.internal:8443/health/ready
404
admin@lb01:~$ curl -s -o /dev/null -w '%{http_code}\n' --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://idp01.par1.medisphere.internal:9000/health/ready
200
```

Avec `http-management-port`, les points `/health` et `/metrics` ne sont servis **que** sur 9000 ; sur 8443, `404`. HAProxy déclare le serveur DOWN alors que Keycloak va bien : la publication est cassée, pas le fournisseur. Les deux répartiteurs ont la même modification : une bascule de la VIP ne sert à rien. Correctif : rôle `haproxy` rejoué, **un répartiteur à la fois** (`--limit lb02`, contrôle, puis `lb01`) ; le rôle valide (`haproxy -c`) avant de recharger.

**Variante 4 — PostgreSQL limité à 6 connexions.**

```
admin@idp01:~$ sudo journalctl -u keycloak --since -30min -o cat | grep -m2 -Ei 'too many clients|connection slots'
… FATAL: remaining connection slots are reserved for roles with the SUPERUSER attribute
admin@idp01:~$ sudo -u postgres psql -XAtc "SELECT name, setting, sourcefile FROM pg_settings WHERE name = 'max_connections'"
max_connections|6|/etc/postgresql/17/main/conf.d/90-reglage-memoire.conf
admin@idp01:~$ sudo -u postgres psql -XAtc "SELECT usename, state, count(*) FROM pg_stat_activity GROUP BY 1, 2"
```

Keycloak garde une réserve de connexions (Agroal, jusqu'à 100 par défaut) ; PostgreSQL en accepte 6, dont 3 réservées aux superutilisateurs : au-delà de trois requêtes simultanées, les suivantes **attendent** une connexion libre, puis échouent après le délai d'acquisition ; `/health/ready` passe à `DOWN` quand le contrôle de la base échoue, et HAProxy retire le serveur par moments. D'où « lent, puis erreur, puis ça repart ». Le fichier n'appartient à aucun rôle : `--check --diff` ne le voit pas ; c'est `pg_settings.sourcefile` qui le trouve. Correctif : retirer le fichier (et, si l'intention de Lucas était légitime, porter un réglage **dimensionné** dans `keycloak_pg_conf` du rôle, par MR : `max_connections` ≥ taille maximale de la réserve de Keycloak + sauvegardes + supervision + marge), redémarrer PostgreSQL **puis** Keycloak (réserve de connexions cassées). Le dimensionnement juste se lit dans `agroal_max_used_count`/`agroal_active_count` de Keycloak sur une semaine (port 9000).

**Clôture commune** : découverte saine, un service de chaque famille vérifié (Grafana, kubectl après `kubectl oidc-login clean`, `step ssh login`), communication de fin, `lab/bin/check 24 42`, `lab/bin/break 24 42 --annuler`.

**Détection** (MR dans `plateforme/observabilite`, [règles](fichiers/M24-E42/observabilite/regles/identite.extrait-E42.yaml) et [tests](fichiers/M24-E42/observabilite/tests/identite-E42.test.yaml)) :
- variante 2 : `KeycloakIndisponible` **a sonné** (la collecte de `idp01:9000` vérifie elle aussi le certificat) ; la sonde du témoin aussi ;
- variante 3 : la collecte de `idp01:9000` va bien, `KeycloakIndisponible` ne dit rien ; seule la sonde de `sso` depuis `mon01` sonne ; ajout : `SsoSansServeur` sur `haproxy_server_status{proxy="be_sso",state="UP"}` (somme nulle pendant 1 min) ;
- variante 1 : **rien** n'a sonné (`200` partout) ; ajout : la sonde du témoin vérifie le **corps** de la découverte (nouveau module blackbox `oidc_emetteur` avec `fail_if_body_not_matches_regexp` sur l'émetteur exact : [gabarit](fichiers/M24-E42/ansible/roles/supervision_temoin/templates/blackbox.yml.extrait-E42.j2) et [groupe de sondes de `mon01`](fichiers/M24-E42/ansible/inventories/lab/host_vars/mon01/supervision_temoin.yml.extrait-E42)) ;
- variante 4 : `KeycloakBaseSaturee` sur `agroal_awaiting_count > 0` pendant 2 min (à vérifier sur `/metrics` de ta version, voir « Points non testés »).

Section `## 8. Le fournisseur d'identité répond mal` de [RB-246](fichiers/M24-E43/medisphere/docs/securite/identite/runbooks/RB-246-sso-indisponible.md) : le tableau des cinq premières minutes ci-dessus, avec la commande de preuve de chaque ligne.

**Explications**

La découverte OIDC est le contrat entre le fournisseur et tous les services : un émetteur, des points de terminaison, des clés. Les services comparent **à la lettre** l'émetteur des jetons à celui qu'ils ont configuré ; le moindre écart (port, barre finale, schéma) et tout est refusé, sans que Keycloak voie la moindre erreur. HAProxy, lui, ne juge Keycloak **que** par son contrôle de santé : un contrôle mal dirigé (port, chemin, TLS) retire un serveur sain, et inversement un contrôle trop laxiste garde un serveur malade. La base, enfin, est la dépendance silencieuse : Keycloak garde en cache le royaume et les clients, les connexions déjà ouvertes passent, et ce sont les écritures (sessions, événements) qui échouent en premier.

**Alternatives**

`hostname-admin` distinct (console sous un autre nom, M24-E27 « pour aller plus loin ») limite l'effet d'un nom faux sur l'administration. Un contrôle de santé HAProxy sur `/health/live` plutôt que `/health/ready` garderait un Keycloak sans base dans le pool : mieux pour servir la page d'erreur de Keycloak, pire pour la clarté du symptôme ; nous gardons `ready`. Un PgBouncer devant PostgreSQL : utile à plusieurs nœuds (E24), superflu à un.

**Pièges classiques**
- Redémarrer Keycloak « pour voir » : variante 3 inchangée, variante 1 inchangée (la configuration est relue telle quelle), variante 4 améliorée cinq minutes.
- Tester TLS depuis `adm01` avec `curl -k` : ce n'est ni le chemin ni la vérification de HAProxy.
- Corriger un seul répartiteur (variante 3) et conclure à une panne intermittente.
- Remonter `max_connections` à 1000 sans regarder ce que Keycloak, les sauvegardes et la mémoire d'`idp01` demandent.

**En production chez MédiSphère**

Sonde synthétique complète depuis le témoin (`client_credentials` sur un client dédié, émetteur et signature vérifiés, M24-E44) ; alerte sur le pool de connexions et sur l'état des serveurs de chaque backend ; rôle `keycloak` en `--check` planifié ; toute modification d'`idp01` ou des répartiteurs par MR avec un deuxième relecteur, fenêtre annoncée, RB-246 ouvert à côté.

---

### M24-E43 — Astreinte : la matinée où personne ne pouvait se connecter

**Démarche** (il n'y a pas de solution unique : trois pannes parmi huit, chacune avec ses variantes)

1. **Triage (15 min).** Instruments d'abord, chacun avec ce qu'il ne dépend **pas** de `sso` : la découverte et `/health/ready` sur `idp01` (en `admin`) ; l'annuaire par `ldapsearch` (`wb-checks`) et `ipa ping` sur `ipa01` ; le cluster par `admin.conf` (bris de glace : tracé selon RB-240) ; Mailpit par son API 8025 (authentification basique, MGMT) si l'interface 8443 est en panne. Puis les contrôles `lab/bin/check 24 35` à `24 42` comme sondes : un contrôle qui ne lit plus rien est un symptôme du fournisseur, pas de l'exercice.
2. **Ordre par rayon d'action.** (a) Le fournisseur et sa publication (E42), (b) l'horloge d'`idp01` (E38 v1) qui invalide tous les jetons, (c) ce qui touche **toutes** les personnes d'un coup : fédération (E37 v1, v2), mappeur commun (E39 v4), fichier d'authentification du cluster (E36), (d) un service : Grafana (E35), Argo CD (E39 v1-v3), OAuth2 Proxy (E41), les VMs (E40), (e) ce qui ne touche qu'une partie des personnes ou des requêtes (E37 v3, E38 v3). Justifie chaque écart à cet ordre dans le journal.
3. **Accès de secours** : les ouvrir **seulement** pour réparer ce que le SSO empêche de réparer (exemple : `admin.conf` pour lire les objets d'Argo CD quand kubectl par OIDC est cassé) ; chaque ouverture = une ligne du journal (qui, quoi, pourquoi, fermé quand) ; vérifier que l'alerte `BrisDeGlace*` a sonné (E28). Pas d'ouverture « par confort ».
4. **Communications** toutes les 30 min : symptômes, impact, ce qui est réparé, ce qui reste, prochain point ; la fin d'incident dit aussi ce que les personnes doivent faire (se reconnecter, `kubectl oidc-login clean`, nouveau `step ssh login`).
5. **Clôture** : `lab/bin/break 24 43 --annuler`, `lab/bin/check 24 43`, post-mortem et RB-246 par MR.

**Post-mortem d'exemple** : [`2026-11-09-INC-5143.md`](fichiers/M24-E43/medisphere/docs/securite/identite/post-mortems/2026-11-09-INC-5143.md) (trio E42 v3 + E37 v1 + E39 v2). Ce qu'on attend de la section **Détection** : pour chaque cause, l'alerte qui aurait dû exister, pourquoi elle n'existait pas, et l'action ; et la réflexion transverse : **une dérive du code n'est vue par personne** (annuaire, client Keycloak, ConfigMap d'Argo CD, fichier d'un hôte) tant qu'aucune vérification planifiée ne compare le code et la réalité.

**Runbook** : [`RB-246-sso-indisponible.md`](fichiers/M24-E43/medisphere/docs/securite/identite/runbooks/RB-246-sso-indisponible.md), état final : sections 1 à 5 nées d'E35 à E39, 6 à 8 d'E40 à E42, puis l'annonce, l'arbre des cinq premières minutes et le retour à la normale (E43).

**Pièges classiques**
- Commencer par le service le plus bruyant (Grafana) alors que le fournisseur est en `503`.
- Réparer la fédération pendant que l'horloge d'`idp01` est fausse, puis croire que la réparation n'a pas marché.
- Ouvrir `kc-secours` « pour aller plus vite » et oublier de le noter : l'alerte de Sophie sonne, sans explication.
- Réparer trois pannes et oublier `--annuler` (qui clôt les trois et ne défait aucune réparation).
- Recopier un jeton ou un extrait de `keycloak.conf` (qui contient le mot de passe de la base) dans le post-mortem.

---

### M24-E44 — Sous le capot : signatures, JWKS, sessions et rotation des clés

**Solution**

Fichiers : client d'essai [`tofu/clients-essai-capot.tf`](fichiers/M24-E44/identite/tofu/clients-essai-capot.tf), outil [`outils/verifier-jeton.sh`](fichiers/M24-E44/identite/outils/verifier-jeton.sh), récepteur [`recepteur-deconnexion.py`](fichiers/M24-E44/adm01/recepteur-deconnexion.py), compte rendu [`oidc-sous-le-capot.md`](fichiers/M24-E44/medisphere/docs/securite/identite/analyses/oidc-sous-le-capot.md).

*A. La signature à la main* (après le flux de code d'E07 avec `essai-capot` ; `jetons.json` dans `~/m24/e44/`)

```
admin@adm01:~/m24/e44$ AT="$(jq -r .access_token jetons.json)"
admin@adm01:~/m24/e44$ b64d() { local s="${1//-/+}"; s="${s//_//}"; while (( ${#s} % 4 )); do s+="="; done; printf '%s' "$s" | base64 -d; }
admin@adm01:~/m24/e44$ b64d "$(cut -d. -f1 <<<"$AT")" | jq .
{ "alg": "RS256", "typ": "JWT", "kid": "q3Xr…" }
admin@adm01:~/m24/e44$ printf '%s' "$(cut -d. -f1,2 <<<"$AT")" > entree-signee.txt      # « en-tête.charge », tel quel
admin@adm01:~/m24/e44$ b64d "$(cut -d. -f3 <<<"$AT")" > signature.bin; stat -c %s signature.bin
512
admin@adm01:~/m24/e44$ E=https://sso.par1.medisphere.internal/realms/medisphere
admin@adm01:~/m24/e44$ KID="$(b64d "$(cut -d. -f1 <<<"$AT")" | jq -r .kid)"
admin@adm01:~/m24/e44$ curl -s $E/protocol/openid-connect/certs | jq -r --arg k "$KID" '.keys[] | select(.kid == $k) | .x5c[0]' \
>   | fold -w 64 | sed '1i -----BEGIN CERTIFICATE-----' | sed '$a -----END CERTIFICATE-----' > cle.crt
admin@adm01:~/m24/e44$ openssl x509 -in cle.crt -noout -subject -enddate; openssl x509 -in cle.crt -pubkey -noout > cle.pub
subject=CN=medisphere
admin@adm01:~/m24/e44$ openssl dgst -sha256 -verify cle.pub -signature signature.bin entree-signee.txt
Verified OK
admin@adm01:~/m24/e44$ sed 's/./X/40' entree-signee.txt > alteree.txt && openssl dgst -sha256 -verify cle.pub -signature signature.bin alteree.txt
Verification failure
```

Le module de la clé (`openssl rsa -pubin -in cle.pub -noout -modulus`) est égal à `n` du JWKS décodé en hexadécimal : le `x5c` n'est qu'un certificat **autosigné** qui transporte la même clé (Keycloak le génère avec le fournisseur `rsa-generated` ; aucun service ne vérifie sa chaîne, il sert de format). RS256 = signature PKCS#1 v1.5 sur l'empreinte SHA-256 de l'entrée signée ; 512 octets pour une clé de 4096 bits (`rsa-2026-10`, E29).

L'outil [`verifier-jeton.sh`](fichiers/M24-E44/identite/outils/verifier-jeton.sh) fait la même chose proprement : jeton sur l'entrée standard, algorithme **imposé** (RS256, jamais lu dans l'en-tête pour choisir), clé choisie par `kid` dans le JWKS de l'émetteur **attendu** (jamais une URL tirée du jeton), puis `iss`, `exp`, `nbf` et `aud` si demandé ; fichiers temporaires dans un dossier 700 effacé à la sortie.

*B. Qui garde les clés*

```
admin@adm01:~$ for n in k8s-cp01 k8s-cp02 k8s-cp03; do ssh $n "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get --raw /metrics \
>   --server https://\$(hostname -I | cut -d' ' -f1):6443" | grep -E '^apiserver_authentication_jwt_authenticator_jwks_fetch_last'; done
apiserver_authentication_jwt_authenticator_jwks_fetch_last_key_set_info{apiserver_id_hash="sha256:…",hash="sha256:8c1…",jwt_issuer_hash="sha256:41e…"} 1
apiserver_authentication_jwt_authenticator_jwks_fetch_last_timestamp_seconds{apiserver_id_hash="sha256:…",jwt_issuer_hash="sha256:41e…",result="success"} 1.79…e+09
```

L'empreinte est la même sur les trois nœuds (même JWKS) ; l'horodatage dit quand chacun l'a chargé. kube-apiserver (comme OAuth2 Proxy et Argo CD, qui utilisent la même famille de bibliothèques, `go-oidc`) garde le JWKS en mémoire et le **recharge quand un jeton porte un `kid` inconnu** (avec une limitation de fréquence) : une nouvelle clé active est donc adoptée au premier jeton qu'elle signe. Une clé **désactivée** disparaît du JWKS : les jetons qu'elle a signés sont refusés dès le rechargement suivant. Ce qui casse : un service qui ne recharge jamais (clé neuve inconnue jusqu'au redémarrage) ou une clé désactivée **avant** l'expiration des jetons qu'elle a signés (d'où l'attente de 24 h d'E29).

*C. Les sessions* (relevé représentatif)

| Cookie | Quand | Attributs | Contenu, rôle |
|---|---|---|---|
| `AUTH_SESSION_ID` | pendant le formulaire | `HttpOnly`, `Secure`, `SameSite=None`, session | identifiant de la session **d'authentification** (le formulaire en cours, ses étapes : mot de passe, OTP) ; suffixe de nœud en grappe |
| `KC_RESTART` | pendant le formulaire | `HttpOnly`, `Secure`, `SameSite=None` | jeton chiffré qui permet de recommencer la connexion si la session d'authentification a expiré |
| `KC_AUTH_SESSION_HASH` | pendant le formulaire | **non** `HttpOnly`, 60 s | empreinte de la session d'authentification, lue par le JavaScript de la page (détection d'une connexion faite dans un autre onglet) |
| `KEYCLOAK_IDENTITY` | après connexion | `HttpOnly`, `Secure`, `SameSite=None` | **jeton signé** (algorithme HMAC interne du royaume, clé `hmac-generated`, jamais publiée) qui désigne la session SSO et la personne : c'est **lui** qui fait le SSO |
| `KEYCLOAK_SESSION` | après connexion | **non** `HttpOnly`, `Secure`, `SameSite=None`, durée = session SSO max | empreinte SHA-384 (base64url) de l'identifiant de session : lu par l'iframe de vérification de session (*session management*) des applications JavaScript |

`users/<ID>/sessions` (API, en lecture) donne l'identifiant de la session SSO : son SHA-384 est la valeur de `KEYCLOAK_SESSION` ; le même identifiant est la revendication `sid` de l'ID token et de chaque jeton (E07). Session SSO (navigateur ↔ Keycloak, cookie `KEYCLOAK_IDENTITY`), sessions de client (une par service où la personne s'est connectée, dans la session SSO), cookie **du service** (Grafana, OAuth2 Proxy : sa propre session, que Keycloak ne voit pas). Une déconnexion de Keycloak supprime la session SSO et ses sessions de client (plus de rafraîchissement possible, plus de SSO) ; elle ne ferme **pas** la session propre d'un service, sauf s'il reçoit une déconnexion (canal avant ou arrière) ou s'il rafraîchit souvent (OAuth2 Proxy toutes les 5 min, E18).

*D. La déconnexion par canal arrière*

```
admin@idp01:~$ tmux new -s capot 'python3 -I ~/recepteur-deconnexion.py'
admin@adm01:~/m24/e44$ curl -s -o /dev/null -w '%{http_code}\n' -K <(printf 'user = "essai-capot:%s"\n' "$(<essai-capot.secret)") \
>   -d "refresh_token=$(jq -r .refresh_token jetons.json)" $E/protocol/openid-connect/logout
204
(idp01, fenêtre tmux) POST /deconnexion — 1012 octets : logout_token=eyJhbGciOiJSUzI1NiIs…
```

Charge décodée (représentative) : `iss` (émetteur), `aud` (`essai-capot`), `iat` (et `exp` si ta version en met un : regarde), `jti` (identifiant unique), `sub`, `sid` (la session), `typ: Logout`, `events: {"http://schemas.openid.net/event/backchannel-logout": {}}` ; **pas** de `nonce` (interdit par la spécification : un `logout_token` ne répond à aucune requête du client). Signature vérifiée par `verifier-jeton.sh` avec la même clé que les autres jetons. Le service doit vérifier signature, `iss`, `aud` (lui-même), l'événement, la présence de `sid` ou `sub`, l'absence de `nonce`, et refuser un `jti` déjà vu (rejeu) avant de fermer les sessions correspondantes.

Parmi nos services : GitLab, Grafana, Argo CD, Harbor, Proxmox, NetBox et OAuth2 Proxy (7.15) ne **reçoivent pas** de déconnexion par canal arrière (vérifié dans leur documentation au moment de la rédaction : à revoir à chaque montée de version). Conséquence pour RB-242 : la désactivation dans l'annuaire et la fermeture des sessions Keycloak ne suffisent pas ; il faut fermer les sessions des services un par un (étape 4 de RB-242) ou attendre leur expiration, et les durées de session de chaque service sont une donnée du runbook.

*E. Ménage* : `tmux kill-session -t capot` sur `idp01`, MR qui supprime `clients-essai-capot.tf` (le pipeline détruit le client), `shred -u` des fichiers de `~/m24/e44/` qui contiennent un jeton ou le secret.

**Réponses aux questions d'analyse**
1. Choisir l'algorithme d'après l'en-tête laisse l'**attaquant** le choisir : `none` (aucune signature) ou HS256 avec, comme secret HMAC, la clé **publique** RSA (que tout le monde connaît) : un jeton forgé passe. Règle : la liste des algorithmes acceptés est **configurée**, jamais lue dans le jeton. Ton outil n'accepte que RS256 ; kube-apiserver accepte une liste fixe d'algorithmes asymétriques (pas `none`, pas HMAC) ; OAuth2 Proxy (go-oidc) ne retient que les algorithmes annoncés par la découverte et jamais `none`.
2. Pour la **rotation** : une clé active signe, une clé passive ne signe plus mais vérifie encore ce qu'elle a signé tant que ces jetons vivent ; et pour des algorithmes différents (RS256 pour les jetons, RSA-OAEP pour le chiffrement éventuel). Retirer une clé passive trop tôt invalide des jetons encore valables.
3. Jeton d'accès : jusqu'à son `exp`, 5 minutes (E27), quoi qu'il arrive à la session (le service ne demande rien à Keycloak) ; jeton de rafraîchissement : jusqu'à son premier usage par l'un ou l'autre (rotation) et au plus la session SSO (30 min d'inactivité, 10 h) ; rejoué après usage, il est refusé (E45, question 9).
4. Jamais : une nouvelle clé est inconnue jusqu'au redémarrage du service (tout le monde refusé après la rotation) et une clé compromise désactivée reste acceptée. À chaque requête : une charge et une dépendance de disponibilité inutiles (Keycloak lent = service lent), et un moyen pour un attaquant de faire travailler le service. Le bon comportement : cache, rechargement sur `kid` inconnu, limitation de fréquence.
5. Il est lu par du JavaScript (iframe de session) pour savoir si la session a changé ; il n'ouvre rien : c'est une empreinte, et c'est `KEYCLOAK_IDENTITY` (`HttpOnly`) qui authentifie.
6. Les cookies de Keycloak doivent être envoyés quand une **autre** application redirige vers Keycloak ou l'intègre dans une iframe (vérification de session, déconnexion par canal avant) : contexte « intersite », d'où `None` (avec `Secure` obligatoire). Nos services ne sont jamais intégrés ailleurs : `Lax` suffit (et `Strict` casserait le retour du SSO, M21-E29).
7. La spécification exige `iat` et laisse `exp` facultatif (relève ce que met ta version) ; le service refuse un jeton trop vieux (`iat` hors d'une tolérance courte) et garde les `jti` vus pendant la durée de validité pour refuser un rejeu.
8. Celui qui recharge le moins : un service qui met en cache la découverte et le JWKS au démarrage sans rechargement sur `kid` inconnu ; dans notre lab, à vérifier dans ton journal d'E29 (les métriques `jwks_fetch` de kube-apiserver donnent l'heure exacte du rechargement de chaque nœud).

**Explications**

Un JWT n'est qu'une chaîne `en-tête.charge.signature` en base64url : rien n'est chiffré, tout est lisible, et seule la signature fait foi. La vérifier, c'est (1) choisir la clé par `kid` dans un JWKS obtenu **de l'émetteur attendu**, (2) imposer l'algorithme, (3) vérifier la signature sur l'entrée exacte, (4) seulement ensuite lire les revendications (`iss`, `aud`, `exp`). Les sessions, elles, ne sont pas dans les jetons : elles vivent dans Keycloak (base et cache) et dans des cookies **propres à chaque partie** ; c'est pour cela qu'une déconnexion ne se propage pas d'elle-même.

**Alternatives**

`step crypto jwt verify --jwks …` (CLI `step`, déjà sur `adm01`) ou une bibliothèque (PyJWT, `jwcrypto`) font la vérification en une ligne : à préférer en outillage ; l'exercice à la main sert à comprendre ce qu'elles font. Introspection (E07) au lieu de vérifier localement : réponse « en direct » (session fermée = jeton inactif), au prix d'un appel à Keycloak par requête.

**Pièges classiques**
- Décoder la signature avec `base64 -d` sans transformer `-_` ni rembourrer : erreur ou signature tronquée.
- Signer/vérifier l'entrée **décodée** au lieu de la chaîne base64url.
- Prendre la clé dans un `jku` ou un `x5u` du jeton (c'est la faille, pas la méthode).
- Laisser le récepteur à l'écoute, ou `essai-capot` dans le royaume.
- Copier `KEYCLOAK_IDENTITY` dans le compte rendu : c'est une session vivante.

**En production chez MédiSphère**

L'outil sert dans les runbooks (E43) et dans la sonde synthétique du témoin (E42) ; la vérification des services pendant une rotation de clés (RB-244) s'appuie sur les métriques `jwks_fetch` ; la déconnexion par canal arrière est un critère de choix de tout nouveau service, faute de quoi ses durées de session entrent dans RB-242.

---

### M24-E45 — Questions expert : attaques sur OIDC et défenses

1. Le flux **implicite** renvoie le jeton d'accès dans l'URL (fragment) : il fuit par l'historique, les en-têtes `Referer`, les journaux, et il ne peut être lié ni au client ni au navigateur (RFC 9700 §2.1.2). Le flux par **mot de passe** fait saisir le mot de passe au client lui-même (qui le voit, peut le garder), contourne le flux du fournisseur (pas d'OTP, pas de WebAuthn, pas de détection de force brute contextuelle) et habitue les personnes à taper leur mot de passe ailleurs que chez le fournisseur (§2.4). Chez nous : `implicit_flow_enabled = false` et `direct_access_grants_enabled = false` sur chaque client (`tofu/clients-*.tf`, contrôle d'E46 sur l'API) ; `admin-cli` (client intégré) garde les *Direct Access Grants* : M24-E21 l'a noté, M24-E27 l'a traité (son flux exige l'OTP de qui en a un ; dans `master`, réservé aux réseaux d'administration par HAProxy).
2. Un code d'autorisation qui transite par le navigateur peut être capturé (application malveillante qui enregistre le même schéma d'URI sur un mobile, journal de mandataire, extension, `Referer`) ; sans PKCE, quiconque a le code **et** peut s'authentifier comme le client (ou un client public) obtient les jetons. PKCE lie le code au `code_verifier` que seul le client qui a commencé le flux connaît. La RFC 9700 (§2.1.1) le recommande aussi pour les clients confidentiels parce qu'il protège contre l'**injection** de code (un attaquant qui fait échanger par un client légitime un code volé ailleurs) que le secret du client n'empêche pas. Chez nous : `pkce_code_challenge_method = "S256"` sur `oauth2-proxy`, `kubernetes`, `step-ca`, `argocd-cli`, `grafana` et les autres où le service l'envoie ; Argo CD (client `argocd`, confidentiel) sans PKCE (addendum du palier 2) : acceptable parce que le `state` et le secret sont vérifiés côté serveur, mais c'est un écart à la recommandation, à lever quand la version d'Argo CD le permet avec un client confidentiel (à consigner dans ADR-0240).
3. **b**. Le joker permet d'envoyer le code ou le jeton à n'importe quelle page du domaine, y compris une application compromise ou une page qui **redirige** ailleurs (redirection ouverte) : la RFC 9700 (§2.1, §4.1) impose la comparaison **exacte**. **a** : « interne » ne veut pas dire « de confiance » (n'importe quelle application de `apps.par1…`, dont les applications des équipes) ; **c** : Keycloak accepte les jokers (c'est le défaut d'E22) ; **d** : le flux de code est aussi concerné (le code est le butin).
4. `state` lie la réponse d'autorisation à la requête **du même navigateur** : il protège le client contre le CSRF de connexion (question 11) ; c'est le client qui le crée, le garde (cookie) et le compare. `nonce` lie l'ID token à la requête : il protège contre le rejeu ou l'injection d'un ID token ; Keycloak le recopie dans l'ID token, le client le compare. OAuth2 Proxy met les deux (et le vérificateur PKCE) dans son cookie de CSRF et les vérifie au retour : c'est ce qui a refusé le code dans E41 v1 et v3.
5. *Mix-up* : un client qui parle à **plusieurs** fournisseurs est amené à envoyer un code obtenu chez le fournisseur honnête au point de jetons d'un fournisseur malveillant (ou l'inverse), qui récupère ainsi le code ou les jetons (RFC 9700 §4.4). Nous n'avons **qu'un** fournisseur par client : le scénario n'a pas de prise. Défense générale : le client retient chez quel émetteur il a envoyé la personne et vérifie le paramètre `iss` de la réponse d'autorisation (RFC 9207), ou utilise des URI de retour distinctes par fournisseur. Keycloak envoie `iss` dans la réponse d'autorisation (observé en E07, barre d'adresse).
6. Le fichier d'authentification structurée (E16) : `audiences: [kubernetes]` (le jeton doit contenir `kubernetes` dans `aud`) **et** la règle CEL `claims.azp == "kubernetes"` (le jeton doit avoir été délivré **au client** `kubernetes`). Un jeton de `grafana` n'a ni l'un ni l'autre : `401`. Avec `audiences: [account]`, beaucoup de jetons d'accès du royaume pourraient passer : par défaut, Keycloak ajoute `account` à `aud` dès que le jeton porte des rôles du client `account` (`manage-account`, `view-profile`, hérités de `default-roles-medisphere`) ; nos clients sont en `full_scope_allowed = false`, ce qui limite ce cas (vérifie l'`aud` de tes jetons d'E07 et d'E44), mais tout client créé un jour avec la portée complète fournirait des jetons acceptés par le cluster. D'où la règle sur `azp`, plus robuste qu'une audience partagée.
7. **b**. L'ID token est destiné **au client** (son `aud` est l'identifiant du client) et dit « cette personne s'est authentifiée chez moi pour toi » ; ce n'est pas un droit d'accès à une API. L'accepter comme `Bearer`, c'est permettre à n'importe quel client du royaume qui a reçu un ID token de l'utiliser ailleurs (substitution). **a** : signé ne veut pas dire destiné ; **c** : mieux, mais un ID token n'a pas de portées ni de durée adaptées à l'accès, et certains services vérifient mal le type (`typ: ID` contre `Bearer` chez Keycloak) ; **d** : l'échange de jetons existe (RFC 8693) mais c'est le fournisseur qui décide, pas le service.
8. Durée courte (5 min, E27), audience restreinte (question 6), TLS partout (pas de vol sur le réseau). Nous n'avons **pas** de jetons liés à l'émetteur de la requête : un jeton d'accès copié (journal, poste compromis) est utilisable par n'importe qui pendant 5 minutes. mTLS (RFC 8705) lie le jeton à un certificat client ; DPoP (RFC 9449) à une clé tenue par le client, prouvée à chaque requête. Keycloak sait émettre des jetons DPoP (à vérifier dans la version 26.8, voir « Points non testés ») ; mais il faudrait que **chaque** service vérifie la preuve DPoP : kube-apiserver, Grafana, Argo CD ne le font pas aujourd'hui. Coût : nul côté fournisseur, impossible côté services : à surveiller, pas à faire.
9. Chaque rafraîchissement délivre un nouveau jeton de rafraîchissement et invalide l'ancien ; présenter un jeton déjà utilisé (`refresh_token_max_reuse = 0`) est refusé (`invalid_grant`, « Maximum allowed refresh token reuse exceeded », ou « Stale token » ; événement `REFRESH_TOKEN_ERROR`). Le premier des deux qui rafraîchit garde la session ; le second est refusé. Si c'est la **victime** qui est refusée, son service la renvoie au SSO : elle se reconnecte (avec OTP) et s'en aperçoit, ou ne s'en aperçoit pas (cookie SSO encore valable). C'est pour cela que la RFC 9700 (§4.14) demande en plus de **révoquer** la session sur réutilisation : relis le code ou la documentation de ta version pour savoir si Keycloak le fait ; sinon, une alerte sur `REFRESH_TOKEN_ERROR` avec cette raison (Loki `audit`, E26) et la fermeture de la session par l'astreinte en tiennent lieu. Voulu : on préfère une reconnexion à un voleur qui garde l'accès pendant 10 h.
10. Keycloak : URI de retour exactes (aucune redirection libre possible par le flux) ; OAuth2 Proxy : le paramètre `rd` (page de retour après connexion) est accepté seulement s'il est relatif ou dans `whitelist_domains` (vide chez nous : relatif seulement) ; une application qui a un paramètre « retour » libre devient un relais pour voler un code si une URI de retour y pointe avec un joker (question 3). Défense chez nous : pas de joker, PKCE, et des applications d'équipe qui ne sont jamais des URI de retour du royaume.
11. Sans vérification de `state`, l'attaquant obtient un code **pour son propre compte**, puis fait charger à la victime l'URL de retour avec ce code : le client connecte la victime **en tant que l'attaquant**. Pour un outil d'administration, la victime travaille alors dans le compte de l'attaquant (secrets saisis, jetons créés, configuration enregistrée chez lui) sans le savoir. Défense : `state` (et PKCE, qui lie aussi le code à la session du client) ; tous nos services les utilisent (vérifié pour OAuth2 Proxy en E41).
12. **Règle unique** : le vérificateur fixe lui-même l'algorithme accepté **et** l'origine des clés (JWKS de l'émetteur configuré) ; il ignore `alg: none`, ne fait jamais de HMAC avec une clé publique, et n'utilise **jamais** `jku`, `x5u` ou une clé contenue dans le jeton (RFC 8725 §3.1, §3.2). kube-apiserver : JWKS de l'émetteur du fichier d'authentification, algorithmes asymétriques seulement ; OAuth2 Proxy (go-oidc) : JWKS de la découverte, algorithmes annoncés ; ton outil : RS256 seulement, JWKS de l'émetteur passé en paramètre. Preuve : un jeton à en-tête modifié (`alg` changé) est refusé par chacun.
13. Une application tierce demande des droits étendus (lecture des courriels, des fichiers) et la personne **consent** : l'application obtient un accès légitime aux yeux du fournisseur, sans mot de passe volé. Chez nous : pas d'applications tierces, pas d'inscription dynamique des clients (*Client Registration* : politiques d'enregistrement anonyme et authentifié à vérifier dans *Clients → Client registration*, aucun jeton d'accès initial émis), clients tous créés par OpenTofu en MR, `consent_required = false` parce que **nous** sommes l'organisation qui décide. Le risque se déplacerait si on ouvrait le royaume à des partenaires (M24-E32, fédération).
14. La fatigue de MFA vise les notifications à accepter d'un geste : l'attaquant, qui a le mot de passe, déclenche des demandes jusqu'à ce que la personne accepte. Un OTP par code exige que la personne **tape** un code : pas de bombardement possible. Reste l'hameçonnage en temps réel : un faux site relaie mot de passe et code à la vraie page et récupère la session (le code vaut 30 s, c'est assez). WebAuthn/passkeys y résistent : la signature du facteur est liée à l'**origine** (le nom du site) ; un faux site ne peut pas obtenir une signature valable pour `sso.par1.medisphere.internal`. D'où la cible « passkeys pour les administrateurs » (E21, en production).
15. Le flux de terminal (RFC 8628) affiche un code court à saisir sur une page du fournisseur : un attaquant démarre le flux lui-même et envoie le code à la victime (« saisis ce code pour valider ton accès ») ; la victime s'authentifie et **c'est l'attaquant** qui reçoit les jetons. Vérification : l'attribut `oauth2.device.authorization.grant.enabled` de chaque client (API d'administration, `attributes`) vaut `false`, et aucun de nos fichiers `tofu/clients-*.tf` ne l'active (`oauth2_device_authorization_grant_enabled` du fournisseur) ; à ajouter au contrôle de la revue d'accès (E30).
16. **d**. `SameSite` concerne les cookies **du service** envoyés lors de requêtes intersites ; il ne protège en rien un code qui transite dans une URL. **a** rend un code volé inutilisable sans le vérificateur ; **b** empêche d'envoyer le code ailleurs ; **c** réduit la fenêtre et empêche le second usage (et Keycloak révoque les jetons déjà émis si un code est rejoué).
17. Traces : événements d'administration du royaume (création ou modification de clé, de client, de mappeur, de flux) et de connexion dans Loki `audit` (E26), connexions à `master` (`kc-secours`, `<MOI>-admin`, alertes de bris de glace d'E28), requêtes inhabituelles à l'API d'administration dans le journal d'accès de HAProxy (réseaux d'administration seulement). Actions (RB-244, M24-E32 question 8) : isoler (couper la publication de l'administration, garder le SSO si possible), **nouvelle clé de signature** active et **désactivation immédiate** de toutes les anciennes (pas d'attente de 24 h : un jeton forgé ne doit plus passer, au prix de reconnexions générales), rotation de **tous** les secrets des clients et des comptes de service, invalidation de toutes les sessions (`logout-all` du royaume), rotation du mot de passe de `svc-keycloak`, révision des seconds facteurs, analyse, puis restauration éventuelle depuis une sauvegarde antérieure (RB-243) si l'intégrité de la base est en doute.
18. Exemples attendus (d'autres sont valables s'ils sont argumentés) : **jetons liés à l'émetteur** (DPoP, mTLS) — risque : jeton volé utilisable 5 min ; coût : services incompatibles ; recommandation : à surveiller (revoir à chaque montée de version des services). **PKCE sur tous les clients confidentiels** (Argo CD) — risque : injection de code ; coût : faible si la version le permet ; recommandation : à faire (ticket SEC). **Politiques de clients de Keycloak** (*Client Policies*, profils FAPI ou un profil maison qui refuse joker, flux implicite, *Direct Access Grants*, client public sans PKCE) — risque : un client mal créé un jour (E22) ; coût : quelques heures, tests en CI ; recommandation : à faire, c'est la prévention de toute la famille des questions 1 à 3. Pour chacune : un ticket `SEC-25xx`, un responsable, une échéance.

**Pièges classiques** : répondre par des noms d'attaques sans le mécanisme ; citer une défense « en général » sans dire où elle est chez nous ; présenter DPoP ou les passkeys comme faits alors qu'ils ne le sont pas ; oublier les clients intégrés de Keycloak (`admin-cli`, `account-console`) dans les réponses sur les flux.
