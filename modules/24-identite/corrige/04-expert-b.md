**Points non testés en conditions réelles (M24-E40 à M24-E45)** — signale-les si ton comportement diffère :
- **Aucune injection de panne n'a été jouée sur un lab réel.** Les scripts `break-E40.sh` à `break-E43.sh` et les contrôles `check-E40.sh` à `check-E44.sh` ont passé `bash -n` et `shellcheck -x` ; les contrôles ont été lancés à blanc (sans lab : chaque contrôle passe au rouge ou est ignoré, aucun ne passe sur une absence de réponse) ; les transformations ont été jouées sur des fichiers d'exemple conformes aux corrigés des paliers 1 à 3 : filtre `jq` du gabarit de step-ca (aller et retour identiques), `sed` de `haproxy.cfg` et de `keycloak.conf`, code Python de l'annuaire compilé.
- E40 v2 : comportement de `sudorule_mod(hostcategory=None)` puis `sudorule_add_host` dans le cadre Python de FreeIPA 4.13 (attendu : comme `ipa sudorule-mod --hostcat=` puis `ipa sudorule-add-host`) ; délai réel de prise en compte par SSSD 2.10 (le script invalide le cache sur `nbx01` ; sur les autres VMs, jusqu'au rafraîchissement suivant : `ldap_sudo_smart_refresh_interval`, 15 min par défaut).
- E40 v3 : SSSD 2.10 refuse un `sssd.conf` lisible par « les autres » (lu dans `src/util/sss_ini.c` au tag 2.10.2 : `Unexpected access to '…' by other users`) ; si ta version l'accepte, le script se replie sur l'arrêt du service (le symptôme est le même, la cause plus banale).
- E40 v4 : `step-ca` 0.30 redémarré avec un gabarit modifié ; message exact de sshd 10.0 pour un principal absent.
- E41 v1 : OAuth2 Proxy 7.15.5 ne valide pas la cohérence entre le préfixe `__Host-` et `cookie_domains` (lu dans `pkg/validation/cookie.go` au tag) : il démarre et pose un cookie que le navigateur rejette ; le message « Login Failed: Unable to find a valid CSRF token » est celui du code (`oauthproxy.go`). Le refus par le navigateur (Firefox, Chromium) n'a pas été observé ici.
- E42 v4 : PostgreSQL 17 démarre avec `max_connections = 6` (3 réservées aux superutilisateurs) ; nombre exact de connexions que Keycloak 26.8 ouvre au démarrage ; texte exact des refus (`sorry, too many clients already`, `remaining connection slots are reserved for roles with the SUPERUSER attribute`) dans le journal JSON de Keycloak.
- E42 : métrique `agroal_awaiting_count` de Keycloak (seule `agroal_active_count` est citée par la documentation 26.8 ; vérifie `/metrics` sur le port 9000) et étiquette `state` de `haproxy_server_status` (exportateur natif de HAProxy 3.2).
- E44 : `verifier-jeton.sh` a été joué contre un émetteur d'essai local (découverte et JWKS servis en HTTPS, jeton RS256 signé par `openssl`) : jeton valide accepté, charge altérée, `alg: none` et mauvaise audience refusés. Noms et attributs des cookies relus dans le code de Keycloak 26.8.1 (`CookieType`, `CookieScope`, `AuthenticationManager.createLoginCookie` : `KEYCLOAK_SESSION` = empreinte SHA-384 de l'identifiant de session) ; métriques JWKS de kube-apiserver relues dans le code 1.36.0 (`plugin/pkg/authenticator/token/oidc/metrics.go`) ; attributs `backchannel_logout_url`, `frontchannel_logout_enabled` relus dans le fournisseur `keycloak/keycloak` 5.10.0. Le flux complet (récepteur, `logout_token`) n'a pas été joué.
- E45 : prise en charge de DPoP par Keycloak 26.8 (fonction disponible depuis la 26.4 selon les notes de version : vérifie `kc.sh show-config` et la documentation de ta version) ; réglage GitLab de la question 1 du mini-projet.

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
