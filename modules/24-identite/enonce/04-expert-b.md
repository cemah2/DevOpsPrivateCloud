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

**Prérequis** : M24-E35 à M24-E42 (au moins une variante de chacun) ; RB-240 éprouvé (E28).
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
