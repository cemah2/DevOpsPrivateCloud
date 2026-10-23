# Module 24 — Palier 4 : Expert — Corrigé (M24-E35 à M24-E39)

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. En identité, « j'ai recréé le client » ou « j'ai mis tout le monde admin le temps de comprendre » est presque toujours faux : le premier efface la preuve et casse les autres services du même client, le second ouvre un trou plus grave que la panne.

Les scripts d'injection sont dans `corrige/pannes/` : `_m24-commun.sh` contient les fonctions partagées (API d'administration du **seul** royaume `medisphere` avec le jeton du client `svc-tofu-keycloak`, export JSON avant chaque modification, exécution en root sur les VMs avec sauvegarde dans `/var/lib/workbook/`, cadre Python de FreeIPA sur `ipa01`, `kubectl` d'administration par `admin.conf` lu **sur** `k8s-cp01`, mesure des écarts d'horloge). L'état des pannes est gardé sur `adm01` dans `~/.local/state/workbook/M24-EXX/`, le journal des VMs dans `/var/lib/workbook/pannes.log`. Chaque annulation ne restaure un objet que s'il porte **encore** la valeur injectée : ta réparation n'est jamais défaite.

> **Remarque sur les traces** : les pannes laissent les mêmes traces qu'un humain. Côté Keycloak, l'événement d'administration montre le client **`svc-tofu-keycloak`** et l'adresse d'`adm01` : un changement fait avec le secret d'OpenTofu, hors pipeline. Côté cluster, `admin.conf` (`kubernetes-admin`) a servi : `BrisDeGlaceCluster` (M24-E28) sonne pendant l'injection de M24-E36 et M24-E39. Côté annuaire, une modification par la socket LDAPI en root (liaison automatique en *Directory Manager*). Dans le scénario, c'est Lucas ; en production, chacune de ces traces serait la **première** question du post-mortem : qui possède ce secret, pourquoi un bris de glace a-t-il servi sans être déclaré ?

Les sorties reproduites sont **représentatives** : identifiants, adresses, horodatages et formulations exactes varient selon ton lab et les versions (Keycloak 26.8.1, FreeIPA 4.13, Kubernetes 1.36, Argo CD 3.5, Grafana 13.2, chrony 4.x).

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- Les scripts de panne et les vérifications passent `bash -n` et `shellcheck -x` ; les transformations `yq`/`jq` ont été vérifiées sur des fichiers conformes aux corrigés de M24-E13, E16 et E27 ; **aucune injection n'a été jouée sur un lab réel**. Les points les plus sensibles : une mise à jour **partielle** d'un client ou du royaume par `PUT` (Keycloak ne modifie que les champs présents : vérifié dans le code de `RepresentationToModel`, pas sur un serveur 26.8.1) ; le comportement du cadre Python de FreeIPA lancé `in_server=True` en root (liaison LDAPI) pour `user_add` et pour la remise d'une **empreinte** de mot de passe (389-ds accepte une valeur déjà hachée d'une liaison *Directory Manager*).
- E35 : le texte exact des événements `jboss-logging` (`type="CODE_TO_TOKEN_ERROR", … clientId="grafana", … error="invalid_client_credentials"`) et la valeur de l'étiquette `event` de `keycloak_user_events_total` (attendue en minuscules : `code_to_token`) ; le message de Grafana pour `role_attribute_strict` est celui du code source de Grafana (`oauth.role_attribute_strict_violation`, « idP did not return a role attribute, but role_attribute_strict is set »).
- E36 : les noms des métriques (`apiserver_authentication_jwt_authenticator_latency_seconds`, `apiserver_authentication_config_controller_automatic_reloads_total`, `…_automatic_reload_last_timestamp_seconds`, `…_last_config_info`) et les messages (`oidc: expected audience in …`, `oidc: error evaluating claim validation expression`) sont ceux du code de Kubernetes 1.36.0 ; leur **collecte** par kube-prometheus-stack (métriques ALPHA, éventuellement filtrées par ses `metricRelabelings`) est à vérifier sur ton lab. Une racine de confiance fausse ou un émetteur injoignable écrits à chaud ne cassent rien : le rechargement attend que le nouvel authentificateur soit prêt, échoue, et garde l'ancien (lu dans le code, `pkg/kubeapiserver/options/authentication.go`).
- E38 v3 : l'effet exact d'un nœud de contrôle en avance de 7 minutes sur etcd et sur les jetons de comptes de service qu'il émet (borné, mais non mesuré) ; `NodeClockNotSynchronising` de kube-prometheus-stack devrait sonner (un `date -s` met le noyau en `STA_UNSYNC`).
- E39 : la relecture à chaud d'`argocd-rbac-cm` par Argo CD 3.5 (documentée) et la sortie exacte de `argocd admin settings rbac can … --namespace argocd`.

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
4. *RB-246* commencé : [`RB-246-sso-indisponible.md`](fichiers/M24-E35/medisphere/docs/securite/identite/runbooks/RB-246-sso-indisponible.md) (en-tête, méthode, sections des pannes E35 à E39 ; M24-E43 le complète).

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
