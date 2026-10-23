**Points non testés en conditions réelles (M25-E40 à M25-E45)** — signale tes retours, ils corrigent le workbook :
- **Validé sur banc** (OpenBao **2.7.1** officiel, serveur de développement et petite grappe Raft de deux nœuds auto-descellée par un troisième OpenBao jouant `kms01`) : règles de correspondance des politiques (`+`, `*`, `data/`, `deny` sur motif identique ou moins précis, politiques de groupe appliquées tout de suite aux jetons existants), `sys/capabilities-accessor`, renommage d'un alias de groupe externe ; refus de signature PKI (domaine, usage de l'émetteur), certificat sans `clientAuth` quand `client_flag=false`, CRL de 2 min sans reconstruction ; `bao patch` refusé (403) à une politique sans la capacité `patch` ; `min_decryption_version` (refus au-delà de `latest_version`, « disallowed by policy (too old) », retour arrière) ; démarrage d'un nœud au seal `transit` avec un jeton inconnu (le processus s'arrête : « Error configuring seal "transit" … 403 ») et avec une politique sans `decrypt` ou une version minimale relevée (le processus reste, scellé, `failed to unseal core` toutes les 5 s, et se descelle seul une fois la cause levée) ; **jeton du seal jamais renouvelé** sans `auth/token/renew-self` dans `kms-autodescellement` (`last_renewal_time` vide), renouvelé avec ; `sys/key-status` en `read`, `sys/rotate` exigeant `sudo`, `sys/rotate/config` ; contenu du stockage Raft (noms KV v2 absents, structure en clair) ; nœud en attente : lecture servie localement, écriture transmise (200), 307 avec `X-Vault-No-Request-Forwarding`, lecture périmée juste après une écriture.
- **Scripts** : `break-E40.sh` et `break-E41.sh` injectés, vérifiés et annulés (4 variantes chacun) contre ce banc, les appels Kubernetes remplacés par des bouchons ; `break-E42.sh` : parties `kms01` (politique, rotation et version minimale, jeton d'annulation) jouées sur le banc, parties « nœud » (`kms.env`, nftables, `systemctl`) **non jouées** ; `break-E43.sh` écrit sans les scripts de M25-E35 à E39 (absents à la rédaction) : il les charge s'ils existent et les écarte sinon. `tester-politiques.sh`, `sonde-crl` et `openbao-essai-kms` exécutés sur le banc ; règles d'alerte passées à `promtool` 3.5 (`check rules`, `test rules`) ; tous les scripts au vert sous `shellcheck -x` et `bash -n`. Les checks ne sont pas rejoués sur un lab ; leurs analyseurs de politiques sont testés sur les fichiers du corrigé.
- **Non vérifié** : le message exact de ghostunnel 1.11.5 quand un client présente un certificat sans `clientAuth` (Go refuse avec une erreur d'usage de clé incompatible) ; le fait que cert-manager 1.x tienne pour « prêt » un certificat émis sans un usage demandé (attendu : oui, il ne compare pas les usages du certificat obtenu) ; `cmctl renew` sur la version installée au M15 ; l'effet d'un renommage d'alias de groupe sur un jeton OIDC **renouvelé** (attendu : appartenance recalculée au renouvellement comme à la connexion) ; la métrique `certmanager_certificate_ready_status` avec l'étiquette `issuer_name` (présente dans les versions récentes de cert-manager : vérifie sur ta vue globale).

> **Écart signalé aux paliers précédents** : (1) la politique `kms-autodescellement` de `kms01` (M25-E25) ne contient pas `auth/token/renew-self` ; le jeton du seal, créé sans la politique `default`, **ne se renouvelle donc pas** et meurt au bout de sa période (168 h) ; la grappe continue de tourner, mais plus aucun nœud ne peut redémarrer. Le corrigé de M25-E42 donne la politique corrigée ([`kms01/kms-autodescellement.hcl`](fichiers/M25-E42/kms01/kms-autodescellement.hcl)) et un essai quotidien qui l'aurait montré. (2) `plateforme-admin` n'a pas la capacité `patch` : `bao patch` (modification partielle d'un rôle ou d'un émetteur PKI) répond 403 ; une mise à jour à la main par `bao write` **remplace** l'objet entier.

---

### M25-E40 — Panne : « permission denied »

**Démarche de diagnostic**

*Symptômes* : Julien reçoit `permission denied` sous `kv/mediagenda/dev/`, en CLI et dans l'interface ; il est toujours dans le groupe de l'annuaire.

*Hypothèses* : (a) la **politique** ne couvre plus le chemin réellement demandé (motif, préfixe KV v2) ; (b) une **autre** politique portée par le même jeton l'emporte (`deny`, règle plus précise) ; (c) le jeton n'a **plus** la politique (groupe externe, alias, revendication `groups`) ; (d) le chemin demandé n'est pas celui qu'on croit (montage, faute de frappe) ; (e) côté Keycloak, Julien n'a plus le groupe dans son jeton d'identité (M24).

**Étape 1 — Le jeton de Julien, par son accesseur** (jamais son jeton)

```
admin@adm01:~$ bao list -format=json auth/token/accessors | jq -r '.[]' | while read -r a; do
    bao token lookup -format=json -accessor "$a" | jq -r --arg a "$a" \
      'select(.data.display_name == "oidc-julien.petit") | [$a[0:6], .data.issue_time, (.data.policies|join(",")), ((.data.identity_policies // [])|join(","))] | @tsv'; done
4kQ2xV   2026-…T08:52:10Z   default   mediagenda-dev
admin@adm01:~$ bao write -format=json sys/capabilities-accessor accessor=<ACCESSEUR> \
    paths=kv/data/mediagenda/dev/valkey | jq -c .data
{"capabilities":["deny"],"kv/data/mediagenda/dev/valkey":["deny"]}
```

Si `identity_policies` est **vide** alors que Julien s'est connecté ce matin : le groupe n'est plus rattaché (variante 4). Sinon le refus vient du **contenu** des politiques (variantes 1 à 3). Si Julien n'a aucun jeton vivant, il se reconnecte (ou toi en fenêtre privée) : sa connexion **est** l'expérience.

**Étape 2 — L'audit** (Grafana, Loki, locataire `audit`) :

```logql
{service="openbao"} | json qui="auth.display_name", chemin="request.path", op="request.operation", erreur="error", pol="auth.identity_policies"
  | qui="oidc-julien.petit" | erreur="permission denied" | line_format "{{.op}} {{.chemin}} {{.pol}}"
```

`update kv/data/mediagenda/dev/valkey` : la CLI demande bien `kv/data/…` (préfixe KV v2 ajouté par `bao kv`), et `list kv/metadata/…` pour l'arbre de l'interface. Dans le même journal, les écritures d'hier soir sur `sys/policies/acl/mediagenda-dev`, `identity/group/name/mediagenda` ou `identity/group-alias/id/…` donnent l'heure et l'auteur (ici ton propre jeton : l'injection l'utilise). L'alerte `OpenBaoPolitiqueModifiee` (M25-E21) avait sonné pour les variantes 1 à 3.

**Étape 3 — La chaîne**

```
admin@adm01:~$ bao read -format=json identity/group/name/mediagenda | jq '.data | {type, policies, alias: {name: .alias.name, mount_accessor: .alias.mount_accessor}}'
admin@adm01:~$ bao auth list -format=json | jq -r '."oidc/".accessor'
admin@adm01:~$ bao policy read mediagenda-dev
admin@adm01:~/src/secrets$ tofu -chdir=tofu plan        # en lecture : la dérive apparaît
```

**Variante 1 — `+` à la place de `*`.**

```
path "kv/data/mediagenda/+" {
  capabilities = ["create", "read", "update", "delete"]
}
```

`+` remplace **un** segment : `kv/data/mediagenda/dev` correspond, `kv/data/mediagenda/dev/valkey` non. La « simplification » de Lucas ne donne plus rien sous `dev/` (et donnerait l'écriture sur `kv/data/mediagenda/prod` si un secret y était rangé à ce niveau). `sys/capabilities-accessor` sur `kv/data/mediagenda/dev` répond `create, delete, read, update`, sur `…/dev/valkey` `deny` : la preuve. Plan : `vault_policy.acl["mediagenda-dev.hcl"]` à mettre à jour. Correctif : apply de `main` (le dépôt a raison) ; les jetons existants retrouvent leurs droits **aussitôt** (les politiques sont relues à chaque requête).

**Variante 2 — préfixe `data/` oublié.**

```
path "kv/mediagenda/dev/*" {
```

Le motif décrit un chemin que **personne** ne demande : avec un montage KV v2, les données sont sous `kv/data/…`. La règle `kv/metadata/mediagenda/dev/*` est restée : l'interface **liste** les secrets mais refuse de les ouvrir — le symptôme le plus trompeur (« je les vois mais je ne peux pas les lire »). Correctif : apply de `main`.

**Variante 3 — `deny` d'une politique de groupe.**

```
admin@adm01:~$ bao read -format=json identity/group/name/mediagenda | jq -c .data.policies
["gel-inventaire","mediagenda-dev"]
admin@adm01:~$ bao policy read gel-inventaire
path "kv/data/mediagenda/dev/*" {
  capabilities = ["deny"]
}
```

Deux politiques, **même motif** : leurs capacités sont réunies et `deny` l'emporte sur tout. Le token lookup montre `identity_policies [gel-inventaire mediagenda-dev]` : la politique a été ajoutée au **groupe**, donc à tous ses membres, sur leurs jetons **existants**. À noter : un `deny` sur `kv/data/mediagenda/*` (motif moins précis) n'aurait rien bloqué sous `dev/` — la règle la plus précise s'applique seule ; un « gel » efficace s'écrit sur les **mêmes** motifs. Correctif : retirer `gel-inventaire` du groupe et la supprimer (apply de `main` : le groupe revient à `["mediagenda-dev"]` ; la politique, absente du dépôt, est détruite par le `for_each` sur `politiques/*.hcl`). Si le gel était voulu par Sophie : il s'écrit dans le dépôt, avec date de fin, et l'équipe est prévenue.

**Variante 4 — alias de groupe renommé.**

```
admin@adm01:~$ bao read -format=json identity/group/name/mediagenda | jq -c '.data.alias | {name, mount_accessor}'
{"name":"MediAgenda","mount_accessor":"auth_oidc_5f1c…"}
```

Keycloak envoie `groups: ["mediagenda"]` ; OpenBao rattache l'entité aux groupes externes dont **l'alias** porte exactement ce nom, sur ce montage. Plus d'alias `mediagenda` : à sa connexion de ce matin, l'entité de Julien est **sortie** du groupe ; son nouveau jeton n'a que `default` (`identity_policies` vide). Son jeton d'hier, lui, marchait encore jusqu'à sa connexion suivante. Correctif : apply de `main` (`vault_identity_group_alias.keycloak["mediagenda"]`), puis **reconnexion** de Julien (sans elle, rien ne change pour lui). Cette variante n'a déclenché **aucune** alerte : `OpenBaoPolitiqueModifiee` ne regarde que `sys/policies/acl/*`.

**Clôture commune** : `sys/capabilities-accessor` sur un jeton de Julien → `create, delete, read, update` ; Julien écrit ; `lab/bin/check 25 40` ; `lab/bin/break 25 40 --annuler` ; journal ([modèle](fichiers/M25-E40/medisphere/docs/socle/journal/AAAA-MM-JJ-INC-5240.md)).

**Prévention**
- **Test des politiques en CI** : [`outils/tester-politiques.sh`](fichiers/M25-E40/secrets/outils/tester-politiques.sh) lance un OpenBao de développement **jetable** dans le job, y charge `politiques/*.hcl` et compare `sys/capabilities` aux attendus de [`tests/politiques/capacites.tsv`](fichiers/M25-E40/secrets/tests/politiques/capacites.tsv), y compris des **combinaisons** de politiques sur un même jeton (le cas du `deny`) ; job [`politiques:tester`](fichiers/M25-E40/secrets/.gitlab-ci.yml.extrait) à l'étape `lint`. Essayé sur le banc : les variantes 1 et 3 échouent avec `attendu create,delete,read,update, obtenu deny`.
- Une règle d'audit sur les écritures `identity/group*` (le ruler de Loki, comme `OpenBaoPolitiqueModifiee`) et un `tofu plan` planifié chaque nuit qui alerte s'il n'est pas vide (la dérive se voit avant l'utilisateur).
- [Fiche réflexe](fichiers/M25-E40/medisphere/docs/securite/secrets/fiche-permission-denied.md) « permission denied » pour l'astreinte et le support.

**Explications**

À chaque requête, OpenBao réunit les politiques du jeton (`policies`, figées à l'émission) et celles de son **entité** (`identity_policies`, recalculées à chaque requête depuis les groupes), cherche pour le chemin **la** règle au motif le plus précis (les motifs identiques fusionnent), et applique ses capacités ; `deny` dans la règle retenue l'emporte sur tout le reste. L'appartenance à un groupe **externe** n'est pas stockée par un administrateur : la méthode d'authentification la constate à la connexion (et au renouvellement), par le nom de l'alias. Trois natures de panne en découlent, avec trois délais : politique (immédiat), groupe interne ou politique de groupe (immédiat), alias de groupe externe (à la prochaine connexion).

**Alternatives**
- Se connecter en `julien.petit` pour reproduire : utile une fois, en fenêtre privée, mais l'accesseur et `sys/capabilities-accessor` suffisent et ne demandent ni mot de passe ni OTP d'un autre.
- `bao token capabilities <JETON> <CHEMIN>` : même réponse, mais il faut le jeton de la personne — à proscrire.
- Politiques sans joker, chemin par chemin : plus sûr, ingérable pour des équipes qui créent leurs secrets ; le compromis est `*` **sous** le dossier de l'équipe et de l'environnement.

**Pièges classiques**
- Élargir le motif (`kv/data/mediagenda/*`) « pour que ça remarche » : l'équipe lit la prod.
- Ajouter la capacité dans une **nouvelle** politique à motif moins précis : elle ne s'applique pas.
- Croire qu'un `deny` large protège un sous-dossier qu'une autre politique ouvre plus précisément.
- Corriger l'alias et oublier que Julien doit se **reconnecter**.
- Corriger à la main sans apply : la prochaine MR remet la dérive… ou l'efface sans que personne sache pourquoi.

**En production chez MédiSphère**

Test des politiques bloquant en CI ; plan planifié qui alerte sur toute dérive ; alerte sur toute écriture de configuration (politiques, groupes, alias, rôles) faite **hors** du jeton du pipeline ; revue trimestrielle des groupes externes face aux groupes de l'annuaire (un groupe Keycloak renommé casse l'accès de toute une équipe à sa prochaine connexion).

---

### M25-E41 — Panne : les certificats de service sont refusés

**Démarche de diagnostic**

*Symptômes* : selon la variante, un `Certificate` non prêt, des appels mTLS refusés en recette, ou un contrôle `openssl verify -crl_check` en échec.

*Hypothèses* : la **signature** est refusée (rôle : domaines, IP, durée ; émetteur : usage, clé ; méthode `k8s-par1` ; politique `cert-manager-services`) ; le certificat est **émis mais inutilisable** (usages, noms, chaîne) ; la **CRL** n'est plus valable (expirée, non reconstruite, non publiée) ; le relais lui-même (ghostunnel) ou la politique réseau (M25-E37, M15).

**Étape 1 — Où ça casse ?**

```
admin@adm01:~$ kubectl get certificates -A | grep mtls
medidoc-recette      medidoc-mtls      False   medidoc-mtls      3d
mediagenda-recette   mediagenda-mtls   True    mediagenda-mtls   3d
admin@adm01:~$ kubectl -n medidoc-recette get certificaterequests -o wide
admin@adm01:~$ kubectl -n medidoc-recette describe certificaterequest <DEMANDE> | sed -n '/Conditions/,$p'
admin@adm01:~$ kubectl -n medidoc-recette logs deploy/medidoc -c relais-tls --since=30m | tail
admin@adm01:~$ curl -s https://openbao.par1.medisphere.internal:8200/v1/pki-services/crl/pem | openssl crl -noout -lastupdate -nextupdate
```

**Variante 1 — domaine retiré du rôle.**

```
Message: Vault failed to sign certificate: … subject alternate name medidoc.medidoc-recette.svc not allowed by this role
admin@adm01:~$ bao read -format=json pki-services/roles/services-k8s | jq -c '.data.allowed_domains'
["svc.cluster.local"]
```

`allow_subdomains` sur `svc.cluster.local` couvre `medidoc.medidoc-recette.svc.cluster.local`, pas `medidoc.medidoc-recette.svc` (domaine distinct, pas un sous-domaine). Le `Certificate` demande les deux noms : tout est refusé. Le certificat en place **sert encore** (48 h) : l'urgence est réelle mais pas immédiate. Reproduction à froid :

```
admin@adm01:~/m25/e41$ openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout essai.key -out essai.csr \
    -subj "/" -addext "subjectAltName=DNS:essai.wb-essais.svc,DNS:essai.wb-essais.svc.cluster.local"
admin@adm01:~/m25/e41$ bao write pki-services/sign/services-k8s csr=@essai.csr ttl=48h
* subject alternate name essai.wb-essais.svc not allowed by this role
admin@adm01:~/m25/e41$ shred -u essai.key
```

**Variante 2 — `client_flag` retiré.** `mediagenda-mtls` est **prêt**, mais :

```
admin@adm01:~$ kubectl -n mediagenda-recette get secret mediagenda-mtls -o jsonpath='{.data.tls\.crt}' | base64 -d \
    | openssl x509 -noout -ext extendedKeyUsage -dates
X509v3 Extended Key Usage:
    TLS Web Server Authentication
admin@adm01:~$ kubectl -n medidoc-recette logs deploy/medidoc -c relais-tls --since=30m | grep -i -m3 'handshake\|certificate'
```

Le relais de **MédiDoc** (serveur) vérifie le certificat du **client** avec l'usage `clientAuth` (bibliothèque TLS de Go) : un certificat sans cet usage est refusé à la poignée de main. Les usages d'un certificat signé par un rôle viennent des drapeaux du **rôle** (`server_flag`, `client_flag`), pas de la CSR : cert-manager demandait bien `client auth`. Aucune supervision ne le voit (le certificat est « prêt ») : seul l'appel de bout en bout échoue. Après correction, `cmctl renew -n mediagenda-recette mediagenda-mtls` et attendre la relecture du relais (5 min, `--timed-reload`).

**Variante 3 — émetteur privé de l'usage `issuing-certificates`.**

```
Message: Vault failed to sign certificate: … error fetching CA certificate: error while attempting to use issuer …:
  requested usage issuing-certificates for issuer [id:… / name:services-2026] but only had usage crl-signing,ocsp-signing,read-only
admin@adm01:~$ bao read -format=json pki-services/issuer/services-2026 | jq -r .data.usage
```

« Préparation de la succession de la CA » mal comprise : retirer l'usage d'émission à l'ancien émetteur ne se fait qu'**après** avoir désigné le nouveau par défaut (`config/issuers`), et l'ancien garde `crl-signing` pour signer les révocations de ce qu'il a émis. Cette panne bloque **toutes** les émissions (cert-manager de tous les espaces).

**Variante 4 — CRL périmée.**

```
admin@adm01:~$ curl -s …/v1/pki-services/crl/pem -o crl.pem && openssl crl -in crl.pem -noout -nextupdate
nextUpdate=Oct 27 03:12:45 2026 GMT                 # quelques minutes après sa construction
admin@adm01:~$ openssl verify -crl_check -CRLfile crl.pem -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt \
    -untrusted services-ca.pem medidoc.crt
error 12 at 0 depth lookup: CRL has expired
admin@adm01:~$ bao read pki-services/config/crl
expiry                       5m
auto_rebuild                 false
```

La CRL dure `expiry` ; avec `auto_rebuild`, OpenBao la reconstruit `auto_rebuild_grace_period` (12 h) avant son échéance ; sans, elle n'est reconstruite qu'à une révocation ou par `crl/rotate`. Un client qui vérifie la CRL (fail-closed) refuse **tout** certificat de la CA dès qu'elle est périmée. Correctif : apply de `main` (72 h, reconstruction automatique), puis `bao read pki-services/crl/rotate` pour ne pas attendre.

**Ce qui n'est pas une panne** : `ttl=100h` → certificat **émis**, réduit à 72 h (`max_ttl`), avec l'avertissement « TTL … is longer than permitted maxTTL ». Une durée trop longue ne refuse rien.

**Correctif commun** : la configuration du rôle, de l'émetteur (hors certificat et clé, posés en cérémonie) et de la CRL est dans [`tofu/pki-services.tf`](fichiers/M25-E16/secrets/tofu/pki-services.tf) : apply de `main`. À la main, attention : `plateforme-admin` n'a pas la capacité `patch` (`bao patch` → 403) et `bao write` **remplace** le rôle entier (tout champ omis revient à sa valeur par défaut). Puis `cmctl renew` du certificat touché, vérification `READY True`, appel de bout en bout en recette, contrôle de Sophie.

**Clôture** : `lab/bin/check 25 41`, puis `lab/bin/break 25 41 --annuler`.

**Prévention** : [`regles/pki-services.yaml`](fichiers/M25-E41/observabilite/regles/pki-services.yaml) et ses [tests](fichiers/M25-E41/observabilite/tests/pki-services.test.yaml) : `CertificatServicesNonPret` (état, pas seulement l'échéance) et `CRLServicesBientotPerimee` (seuil de 6 h, **sous** le délai de reconstruction de 12 h, sinon l'alerte sonnerait en permanence), alimentée par la sonde [`sonde_crl`](fichiers/M25-E41/ansible/roles/sonde_crl/) de `mon01` (CRL vue de l'extérieur, signature vérifiée) ; `CRLServicesSondeMuette` pour la sonde elle-même. La variante 2 reste invisible à la supervision : une **sonde mTLS** de bout en bout en recette (un appel MédiAgenda → MédiDoc toutes les 5 minutes) la verrait ; `wb-checks` lit la configuration de la PKI ([extrait](fichiers/M25-E41/secrets/politiques/wb-checks.hcl.extrait)) ; section de dépannage de [`pki-services.md`](fichiers/M25-E41/medisphere/docs/securite/secrets/pki-services.md.extrait).

**Explications**

Une émission traverse cinq objets, chacun capable de dire non : la méthode (`k8s-par1`, audience, compte), la politique (`sign/services-k8s`), le rôle (noms, IP, usages, durées), l'émetteur (usage, clé, chaîne), puis le **destinataire** du certificat (relais, client) qui applique ses propres règles (usages, nom attendu, CRL). Les trois premiers refusent bruyamment (la `CertificateRequest` porte le message) ; le dernier refuse au moment de l'**usage**, parfois des heures plus tard, dans un journal que personne ne lit.

**Alternatives** : `sign-verbatim` (usages pris dans la CSR) : plus souple, mais rend à la demande ce que le rôle devait imposer ; OCSP au lieu de CRL : réponse fraîche par certificat, mais OpenBao devient une dépendance de **chaque** poignée de main ; certificats très courts (quelques heures) sans révocation du tout : le choix de beaucoup de maillages de services.

**Pièges classiques**
- `bao write` d'un rôle avec le seul champ à changer : tout le reste revient aux valeurs par défaut.
- Retirer `issuing-certificates` d'un émetteur avant d'avoir changé l'émetteur par défaut.
- Chercher l'erreur mTLS dans le journal du **client** : c'est le serveur qui juge le certificat client.
- Une alerte de CRL à 24 h alors que la reconstruction a lieu à 12 h : alerte permanente, donc ignorée.
- Supprimer le Secret du certificat pour forcer une réémission : plus rien n'est servi pendant l'émission (`cmctl renew`).

**En production chez MédiSphère** : tests de la PKI dans la CI de `plateforme/secrets` (une CSR d'essai signée par le rôle sur le serveur jetable d'E40) ; sonde mTLS permanente en recette et en prod ; procédure écrite de succession de la Services CA (nouvel émetteur, bascule du défaut, ancien en `crl-signing` jusqu'à l'échéance de ses derniers certificats).

---

### M25-E42 — Panne : l'auto-descellement échoue

**Démarche de diagnostic**

*Symptômes* : un nœud en attente redémarré ne revient pas ; `OpenBaoScelle`, tolérance d'autopilot à zéro ; `kms01` répond depuis `adm01`.

*Hypothèses* (les quatre maillons du seal `transit`) : le **réseau** du nœud vers `kms01:8200` (pare-feu local, DNS, TLS) ; le **jeton** du seal (inconnu, révoqué, expiré faute de renouvellement) ; la **politique** du jeton (`encrypt`, `decrypt`) ; la **clé** (`min_decryption_version`, clé supprimée — interdite chez nous). Et hors seal : disque, certificat, unité (M25-E35).

**Étape 1 — Le processus tourne-t-il ?**

```
admin@adm01:~$ for n in vault01 vault02 vault03; do printf '%s %s\n' $n "$(curl -s -o /dev/null -w '%{http_code}' https://$n.par1.medisphere.internal:8200/v1/sys/health)"; done
vault01 200
vault02 429
vault03 000
root@vault03:~# systemctl status openbao --no-pager | sed -n '1,6p'
     Active: failed (Result: exit-code) …
root@vault03:~# journalctl -u openbao -b --no-pager | grep -E 'seal|start-limit' | tail -n 4
```

Deux familles (vérifiées sur banc) :
- **le processus s'arrête** au démarrage : `Error configuring seal "transit": Error making API request. URL: PUT https://kms01…/v1/transit/encrypt/autodescellement-par1 Code: 403 … permission denied` (jeton) ou `… connection refused` / `i/o timeout` (réseau) ; systemd relance trois fois (`StartLimitBurst=3`) puis `start-limit-hit` ; `sys/health` : 000 ;
- **le processus tourne, scellé** : `failed to unseal core: … fetching stored unseal keys failed: failed to decrypt keys from storage: … transit/decrypt/autodescellement-par1 Code: 403` (politique) ou `Code: 400 … ciphertext or signature version is disallowed by policy (too old)` (clé) ; nouvel essai toutes les 5 s ; `sys/health` : 503.

**Étape 2 — Le réseau, depuis le nœud.**

```
root@vault03:~# curl -s -o /dev/null -w '%{http_code}\n' https://kms01.par1.medisphere.internal:8200/v1/sys/health
000
root@vault02:~# curl -s -o /dev/null -w '%{http_code}\n' https://kms01.par1.medisphere.internal:8200/v1/sys/health
200
root@vault03:~# nft list ruleset | grep -B4 'dport 8200'
table inet durcissement_sortie {
	chain sortie {
		type filter hook output priority filter - 10; policy accept;
		ip daddr 10.10.20.24 tcp dport 8200 counter packets 9 bytes 540 reject with tcp reset comment "SEC-2642 sorties du coffre limitées (Lucas)"
```

**Variante 4.** `connection refused` fait croire que `kms01` est arrêté : le test **depuis le nœud** et le compteur qui monte prouvent le contraire. La table n'appartient pas au rôle `pare_feu_local` (dont le gabarit commence par `flush ruleset`) : rejouer le rôle la supprime. Puis `systemctl reset-failed openbao && systemctl start openbao`.

**Étape 3 — Le jeton, sans l'afficher.**

```
root@vault03:~# sha256sum /etc/openbao/kms.env ; ssh vault02 sudo sha256sum /etc/openbao/kms.env
root@vault03:~# curl -s -o /dev/null -w '%{http_code}\n' -X POST \
    -K <(printf 'header = "X-Vault-Token: %s"\n' "$(sed -n 's/^BAO_TOKEN=//p' /etc/openbao/kms.env)") \
    https://kms01.par1.medisphere.internal:8200/v1/auth/token/renew-self
403
```

**Variante 1.** Empreintes différentes, 403 : le jeton de `vault03` n'est pas celui de la grappe (révoqué ou inconnu de `kms01`). Correctif : rejouer `playbooks/coffre.yml --limit vault03` (le rôle réécrit `kms.env` depuis `vault_openbao_kms_jeton`, sans redémarrer), puis `reset-failed` et `start`. Si le **même** 403 apparaît avec le jeton des nœuds sains, c'est le jeton commun qui est mort : nouveau jeton sur `kms01` (orphelin, périodique, `-no-default-policy`), directement dans le Vault `critique`, rôle rejoué sur les trois nœuds **sans** redémarrage (les nœuds sains gardent la clé racine en mémoire), puis le nœud en panne. C'est aussi ce qui arrive au bout de 7 jours si la politique ne permet pas `renew-self` (voir plus bas).

**Étape 4 — Politique et clé, sur `kms01`** (jeton racine régénéré à trois, procédure E28, révoqué ensuite) :

```
admin@adm01:~$ export BAO_ADDR=https://kms01.par1.medisphere.internal:8200
admin@adm01:~$ bao policy read kms-autodescellement
admin@adm01:~$ bao read -format=json transit/keys/autodescellement-par1 | jq '.data | {latest_version, min_decryption_version, keys: (.keys | keys)}'
```

**Variante 2.** Le bloc `transit/decrypt/autodescellement-par1` a disparu (« revue des droits : le coffre ne fait que chiffrer ») : le chiffrement d'essai passe, le déchiffrement de la clé racine non. Correctif : réécrire la politique depuis [`kms01/kms-autodescellement.hcl`](fichiers/M25-E42/kms01/kms-autodescellement.hcl) ; `vault03` se descelle **seul** dans les 5 s (il réessaie), sans redémarrage.

**Variante 3.** `latest_version 2`, `min_decryption_version 2` : quelqu'un a fait tourner la clé puis relevé la version minimale, « pour ne plus accepter l'ancienne ». La clé racine de la grappe a été chiffrée par la version 1 : plus aucun nœud ne peut la déchiffrer au démarrage. Les nœuds **en marche** ne voient rien (clé racine en mémoire) : la panne attend le prochain redémarrage. Correctif : `bao write transit/keys/autodescellement-par1/config min_decryption_version=1` ; `vault03` revient seul. La version 2 reste (une rotation ne se défait pas) : sans effet tant que le minimum est 1. Relever le minimum ne serait sûr qu'**après** avoir réenveloppé la clé racine avec la nouvelle version (opération de seal, en cérémonie, documentée dans RB-251).

**Ce que révèle la variante 2 sur notre politique.** En relisant `kms-autodescellement`, on constate qu'elle n'autorise pas `auth/token/renew-self` : le jeton, créé sans la politique `default`, ne peut pas se renouveler. Le serveur essaie au démarrage du seal et abandonne **sans bruit** ; le jeton périodique meurt 7 jours après sa création (sur le banc : `last_renewal_time` vide, puis renseigné après ajout du droit). D'où la politique corrigée et l'essai quotidien ci-dessous, qui renouvelle le jeton et en publie la durée restante.

**Clôture** : les trois nœuds descellés, tolérance 1, `kms01` intact, jeton racine de `kms01` révoqué ; `lab/bin/check 25 42` ; `lab/bin/break 25 42 --annuler` ; journal `INC-5242`.

**Prévention**
- **Essai quotidien** sur chaque nœud : [`openbao-essai-kms`](fichiers/M25-E42/ansible/roles/openbao/files/openbao-essai-kms) (renouvelle le jeton, chiffre puis déchiffre une valeur **témoin** avec le jeton du seal, depuis le nœud), [unité](fichiers/M25-E42/ansible/roles/openbao/templates/openbao-essai-kms.service.j2) et [minuterie](fichiers/M25-E42/ansible/roles/openbao/templates/openbao-essai-kms.timer.j2) du rôle `openbao` ([tâches](fichiers/M25-E42/ansible/roles/openbao/tasks/essai-kms.yml), [variables](fichiers/M25-E42/ansible/roles/openbao/defaults/main.yml.extrait)), métriques pour node_exporter, alertes [`regles/autodescellement.yaml`](fichiers/M25-E42/observabilite/regles/autodescellement.yaml) ([tests](fichiers/M25-E42/observabilite/tests/autodescellement.test.yaml)). Il voit les variantes 1, 2 et 4 **avant** le redémarrage ; la 3 (un texte chiffré à l'instant l'est par la dernière version) se contrôle sur `kms01`, en cérémonie.
- RB-251 complété ([extrait](fichiers/M25-E42/medisphere/docs/securite/secrets/runbooks/RB-251-descellement-et-redemarrage.md.extrait)) ; politique de `kms01` corrigée et consignée.

**Explications**

Avec un seal `transit`, la clé racine est rangée dans Raft **chiffrée par `kms01`** (`core/hsm/barrier-unseal-keys`, M25-E44). Au démarrage, le serveur configure le seal (un chiffrement d'essai : réseau, TLS, jeton, droit `encrypt`) — un échec arrête le processus ; puis il descelle en demandant à `kms01` de **déchiffrer** la clé racine — un échec laisse le processus scellé, qui réessaie. Un nœud déjà descellé n'a plus besoin de `kms01` : c'est pourquoi ces pannes dorment jusqu'au prochain redémarrage, et pourquoi on ne les découvre qu'au pire moment sans un essai régulier.

**Alternatives** : Seal HA (plusieurs seals, OpenBao 2.7 : à lire avant de l'adopter) ; seal PKCS#11 avec un HSM (ADR-0250) ; garder une procédure de migration inverse vers Shamir (RB-251) comme dernier recours.

**Pièges classiques**
- Redémarrer un autre nœud « pour comparer » : la grappe perd le quorum.
- Redémarrer `kms01` : il revient scellé, et la panne devient « coffre fermé » (RB-255).
- Afficher le jeton (`cat kms.env`) pour le tester : il finit dans l'historique ou un ticket.
- Oublier `reset-failed` : la cause est corrigée mais systemd ne relance plus.
- Relever `min_decryption_version` d'une clé de seal « par hygiène ».

**En production chez MédiSphère** : essai quotidien et alerte en place ; politique de `kms01` versionnée et relue comme du code (avec le droit de renouvellement) ; rotation de `autodescellement-par1` uniquement en cérémonie, suivie du réenveloppement ; le jeton du seal tourné une fois par an (politique de rotation, E33).

---

### M25-E43 — Astreinte : la nuit où le coffre s'est fermé

**Démarche**

Trois pannes : une du coffre (E35, E39 ou E42), deux de consommateurs (E36, E37, E38, E40, E41). Chacune se traite par la démarche de son exercice ; ce qui est propre à l'astreinte, c'est l'**ordre** et la **retenue**.

**1. Triage (15 min).** D'abord l'état du coffre, brut, nœud par nœud (RB-255 § 1) : codes `sys/health`, `seal-status`, `raft list-peers`, `autopilot state`. Trois cas : coffre indisponible (aucun actif) ; coffre disponible **sans marge** (tolérance 0) ; coffre sain. Puis les consommateurs, classés par **échéance** (RB-255 § 9) : identifiants dynamiques de la prod (1 h), puis la CI (immédiat mais sans impact patient la nuit), ESO (le Secret existant reste), PKI (48 h). Première communication : ce qui ne marche pas, ce qu'on ne fera pas (aucun redémarrage en série), la prochaine heure de point.

**2. Le coffre d'abord**, car tout en dépend et car une erreur y coûte le plus : rendre au moins un nœud de marge (E35 : disque, certificat, unité ; E39 : quorum, pair retiré, horloge, 8201 ; E42 : seal). Un nœud à la fois, `autopilot state` sain avant de passer au suivant.

**3. Puis les consommateurs**, par échéance : MédiAgenda prod si les baux sont touchés (E38), la CI (E36), ESO (E37), les politiques (E40), la PKI (E41). Chaque correction par le pipeline du dépôt concerné ; chaque contrôle d'exercice rejoué (`lab/bin/check 25 <xx>`).

**4. Clôture.** `lab/bin/break 25 43 --annuler`, post-mortem (exemple : [`AAAA-MM-JJ-INC-5243.md`](fichiers/M25-E43/medisphere/docs/socle/post-mortems/AAAA-MM-JJ-INC-5243.md)), **RB-255** ([fichier](fichiers/M25-E43/medisphere/docs/securite/secrets/runbooks/RB-255-coffre-ferme.md)) : arbre de décision, gestes interdits, consommateurs pendant la fermeture, appel des dépositaires.

**Section Détection, attendus** : pour chaque cause, ce qui a sonné et ce qui aurait dû sonner — essai quotidien de l'auto-descellement (E42), test des politiques et plan planifié (E40), sonde mTLS et alerte d'état des certificats (E41), alertes d'ESO sur les ExternalSecret en erreur (E37), baux qui s'effondrent (E38), règle d'audit sur les écritures de configuration d'authentification (E36).

**Prévention** : RB-255 ; un `tofu plan` planifié de `plateforme/secrets` (toute dérive alerte) ; essais réguliers (auto-descellement, mTLS) plutôt que découverte au redémarrage.

**Pièges classiques**
- Commencer par le ticket le plus bruyant (la CI) alors que le coffre n'a plus de marge.
- Redémarrer un nœud « pour voir » pendant que la tolérance est à 0.
- Réveiller trois dépositaires alors que `kms01` est sain (le problème est dans la grappe).
- Élargir une politique ou un rôle à 3 h pour débloquer la CI.
- Rédiger le post-mortem avec des extraits qui contiennent un jeton ou un accesseur complet.

**En production chez MédiSphère** : RB-255 répété une fois par semestre sur le papier (scénario « grappe arrêtée et `kms01` scellé »), astreinte des dépositaires joignable, et un exercice de reprise complet au final F5.

---

### M25-E44 — Sous le capot : barrière, trousseau, Raft et baux

**Solution** (le compte rendu est personnel ; voici la trame, les commandes et les réponses ; modèle : [`analyses/sous-le-capot-openbao.md`](fichiers/M25-E44/medisphere/docs/securite/secrets/analyses/sous-le-capot-openbao.md)).

**0. Préalable** : [extrait de `wb-checks`](fichiers/M25-E44/secrets/politiques/wb-checks.hcl.extrait) (`sys/key-status` en lecture : vérifié, `read` suffit) par MR.

**1. Les clés.**

```
admin@adm01:~$ bao status | grep -E 'Seal Type|Recovery'
admin@adm01:~$ bao read sys/key-status
admin@adm01:~$ bao read sys/rotate/config
enabled           true
interval          0
max_operations    3865470566
```

`term` : numéro de la clé active du trousseau ; `install_time` ; `encryptions` (compteur depuis son installation). Rotation **automatique** par défaut au-delà d'environ 3,87 milliards de chiffrements, sous la limite d'usage d'une clé AES-GCM à nonce aléatoire de 96 bits (de l'ordre de 2³²) ; `interval` permet une rotation périodique (0 : désactivée).

**2. La rotation du trousseau.** Jeton racine régénéré (procédure d'E28, trois clés de récupération), puis :

```
admin@adm01:~$ bao operator rotate
Success! Rotated key

Key Term            2
Install Time        …
Encryption Count    1
admin@adm01:~$ bao token revoke -self
```

Sans `sudo` sur `sys/rotate`, 403 (vérifié) : `plateforme-admin` ne l'a pas, exprès. La boucle d'E24 ne voit rien ; rien n'est réécrit ; seul `core/keyring` change. À distinguer de `bao operator rotate-keys` (nouvelle clé racine et nouvelles parts, avec le quorum des parts actuelles ; `-target=recovery` pour les clés de récupération) et de la rotation de la clé de `kms01`.

**3. Le disque.** Sur un nœud en attente, en lecture (`ls`, `strings` filtré, comptages) : clés de stockage en clair (`core/mounts`, `core/keyring`, `core/seal-config`, `core/hsm/barrier-unseal-keys`, `sys/policy/<nom>`, `sys/token/accessor/<empreinte>`, `logical/<uuid>/…`), valeurs chiffrées ; **aucun** nom de secret KV v2 (chemins de métadonnées chiffrés par segment, versions rangées sous une empreinte : vérifié, `grep -c mediagenda` = 0), aucun jeton (empreinte salée), aucune valeur. `core/hsm/barrier-unseal-keys` est la clé racine **chiffrée par le seal** (`transit` de `kms01`).

**4. Raft.** `list-peers`, `autopilot state` (`Healthy`, `Failure Tolerance`, index par serveur), `sys/leader` (`raft_committed_index`, `raft_applied_index`).

**5. Le nœud en attente** (vérifié sur banc, en clair ; même comportement attendu en TLS) : lecture servie localement (200 ; journal : `entering read-enabled standby mode`), écriture **transmise** par 8201 (200), `X-Vault-No-Request-Forwarding: true` → **307** avec `Location` vers l'`api_addr` de l'actif ; une lecture juste après une écriture peut répondre 404 (cohérence à terme). Le journal du nœud en attente dit aussi `skipping lease restoration - standby` : les baux ne sont gérés que par l'actif.

**6. Les baux.** `bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette/` puis `bao write sys/leases/lookup lease_id=…` (`ttl`, `expire_time`, `renewable`). Le gestionnaire d'expiration du nœud **actif** révoque le rôle PostgreSQL à l'échéance ; le nouvel actif recharge les baux après une bascule.

**Réponses aux questions** (résumé ; le modèle de compte rendu les développe) : (1) deux niveaux pour changer la clé racine sans tout rechiffrer et faire tourner le trousseau sans rien réécrire ; (2) quatre rotations, quatre menaces et quatre cérémonies (tableau du modèle) ; (3) clé racine en mémoire / chiffrée par `kms01` dans Raft et les instantanés : il faut la clé `age` **et** `kms01` avec un jeton qui déchiffre ; (4) les clés de stockage servent à adresser, elles restent en clair : un voleur déduit la forme du coffre, pas son contenu ; (5) oui depuis la 2.5, cohérence à terme, `X-Vault-Index`/`X-Vault-Inconsistent` ou `disable_standby_reads` pour l'exiger ; (6) transmission transparente par 8201 en TLS mutuel, redirection qui suppose un client qui suit le 307 ; (7) un bail est la trace et la poignée de révocation, pas le secret ; échec de révocation : nouvelles tentatives, baux qui s'accumulent (`OpenBaoBauxNombreux`) ; (8) comptages sans valeur, seal `transit` à clé non exportable, restauration qui échoue sans `kms01` ; hypothèse : `kms01` et son jeton ne sont pas volés avec le disque.

**Explications** : la sécurité au repos d'OpenBao tient à une chaîne de clés dont un seul maillon sort de la machine (`kms01`) ; ce qu'on voit sur disque le confirme, et montre aussi ce qui fuit quand même (la forme). La disponibilité, elle, tient à Raft et à un seul nœud actif ; les nœuds en attente aident à lire, pas à écrire.

**Pièges classiques** : copier `vault.db` pour « l'analyser tranquillement » (une copie du coffre de plus) ; faire la rotation avec un jeton racine qu'on oublie de révoquer ; confondre `rotate` et `rotate-keys` ; conclure de 404 sur un nœud en attente qu'un secret a disparu.

**En production chez MédiSphère** : rotation annuelle du trousseau en cérémonie, inscrite à la politique de rotation ; clients qui exigent la cohérence quand ils écrivent puis lisent (`X-Vault-Index`), ou qui passent toujours par la VIP.

---

### M25-E45 — Questions expert : secrets

1. **Jeton volé.** Bornes : durée (10 min pour les rôles `ci-*`), politiques étroites (chemins exacts), absence de `default` sur certains rôles, nature *batch* ou *service*, révocation en fin de job (`revoke-self`). Retrouver sans le connaître : l'audit donne l'**accesseur** (`hmac_accessor = false` chez nous) et l'heure → `bao token revoke -accessor <ACCESSEUR>` ; en masse : `bao token revoke -mode=path auth/gitlab/login` (tous les jetons émis par la méthode) — décision RB-250. Preuve : `bao read auth/gitlab/role/ci-mediagenda-api` (`token_ttl`, `token_max_ttl`, `token_policies`) et une ligne d'audit de `revoke-self` en fin de job.
2. **Rejeu du JWT de CI.** Le JWT n'est qu'une **preuve d'identité** à échanger contre un jeton : il expire avec le job (quelques minutes), son audience est fixée (`openbao.medisphere.internal`), et le rôle exige `project_id`, `ref`, `ref_type` et `ref_protected = "true"`. Un JWT copié reste rejouable **jusqu'à son expiration**, seulement contre ce rôle ; sans `ref_protected`, n'importe quelle branche (MR d'un contributeur) obtiendrait les secrets de la branche protégée.
3. **QCM — b.** Sans contrainte d'audience, un jeton de compte de service **destiné à autre chose** (présenté légitimement à une application, à un autre service) peut être rejoué contre OpenBao : le confused deputy. a) faux : la signature prouve l'émetteur, pas le destinataire ; c) sans rapport ; d) ESO présente un jeton avec l'audience demandée, il marche dans les deux cas. Preuve : `bao read auth/k8s-par1/role/<rôle>` → `audience openbao.medisphere.internal`.
4. **Élévation par politique.** Écrire une politique `*` et se l'attacher ; ajouter une politique à un groupe dont on est membre ; créer un rôle de méthode (AppRole, JWT, Kubernetes) lié à une identité qu'on contrôle ; créer un jeton enfant avec des politiques — **refusé** si elles ne sont pas un sous-ensemble des siennes sans `sudo`. `plateforme-admin` n'a ni `sys/raw`, ni `sys/rotate`, ni `sys/rekey`, ni les données applicatives (`kv/data/mediagenda/*` en écriture seule à la livraison), et chaque écriture de politique déclenche `OpenBaoPolitiqueModifiee` ; ce qui manque encore : la même alerte sur `identity/*` et `auth/*/role/*` hors du jeton du pipeline (E40, E43).
5. **QCM — b.** La règle au motif le plus précis s'applique seule : `kv/data/mediagenda/dev/*` l'emporte sur `kv/data/mediagenda/*`, le `deny` ne joue pas (vérifié). a) faux : `deny` l'emporte **dans** la règle retenue, pas sur une règle plus précise ; c) aucune annulation entre politiques ; d) l'ordre des politiques ne compte pas. Un vrai gel s'écrit sur le **même** motif (capacités fusionnées, `deny` gagne), ou en retirant temporairement `mediagenda-dev` du groupe.
6. ***Secret sprawl***. Secret Kubernetes (lisible par qui lit les Secrets de l'espace, et dans etcd) → RBAC étroit, chiffrement d'etcd, ESO comme seule source ; variables de CI → plus aucune (JWT) ; `.env` local et tickets → interdits, détection Gitleaks et revue ; historique de shell → `champ=-`, `-K <(…)`, `HISTCONTROL` ; sauvegardes (PBS des VMs, Velero du cluster) → chiffrées, accès séparés ; journaux (une valeur affichée par un job) → masquage et purge. Les identifiants **dynamiques** changent la nature du problème : une copie qui traîne meurt avec son bail (1 h), et chaque copie a un propriétaire identifiable.
7. **Root sur `vault02`.** Immédiatement : le jeton du seal (`kms.env`), le certificat TLS du nœud, le jeton AppRole d'instantanés s'il est sur ce nœud ; sur disque : la forme du coffre, rien de déchiffrable sans `kms01` ; en mémoire du processus : la clé racine et le trousseau (le nœud est descellé), donc **tout** — c'est la limite. Défenses qui jouent contre un attaquant non root ou pour la détection : seal `transit`, unité durcie, `LimitCORE=0`, `MemorySwapMax=0`, pare-feu local, audit ; contre root sur la machine, aucune configuration logicielle ne suffit : il faut détecter (auditd, Falco au M26, connexions SSH par certificats courts) et limiter qui devient root.
8. **Mémoire.** Pour servir, le nœud déchiffre : clé racine et trousseau sont forcément en mémoire. Réductions : pas d'échange, pas de vidage, `ProtectProc`, `PrivateDevices`, hyperviseur maîtrisé (un instantané de VM **avec mémoire** contient tout). Hors de portée : un administrateur de l'hyperviseur qui lit la mémoire de la VM. Un HSM (PKCS#11) garde la clé du **seal** hors de la machine, pas la clé racine une fois descellée.
9. **Sauvegarde volée.** Instantané `age` volé : il faut la clé privée `age` (Vault `critique` et papier), puis `kms01` avec un jeton qui déchiffre, ou les clés de récupération pour migrer vers Shamir… ce qui exige encore `kms01`. PBS de `vault01` et de `kms01` ensemble : `kms01` restauré est **scellé** (parts Shamir) ; sans trois parts, rien. Séparation des pouvoirs : la clé `age`, les parts de `kms01` et l'accès aux sauvegardes ne sont pas dans les mêmes mains (ADR-0250, `garde-des-parts.md`, RB-252).
10. **Jeton du seal.** Il peut chiffrer et déchiffrer avec `autodescellement-par1`, donc, avec une copie des données Raft, déchiffrer la clé racine : c'est un secret **C1**. Il ne peut ni lire la clé, ni la faire tourner, ni rien d'autre sur `kms01`. Il lui faut aussi `auth/token/renew-self` pour rester vivant (jeton sans `default`) : sans ce droit, il meurt au bout de sa période et la grappe ne redémarre plus — un risque de **disponibilité** (E42), pas de confidentialité.
11. **Initié.** Empêchent : `plateforme-admin` sans les données applicatives, `sys/rotate`/`sys/raw` absents, OTP au SSO, politiques en code et relues. Tracent : audit (lecture de `kv/data/mediagenda/prod/*`, écriture de politique, `generate-root` qui exige trois dépositaires), alertes du ruler, connexions aux nœuds. Manque : contrôle à deux personnes sur la lecture (*Control Groups*, à évaluer avec OpenBao 2.7), revue mensuelle des accès effectifs, séparation stricte des rôles « administre le coffre » et « lit la prod ».
12. **QCM — b.** OpenBao refuse de répondre sans trace : HTTP 500 tant qu'aucun dispositif n'écrit (vérifié au M25-E21). a) faux, c'est précisément ce qu'il refuse ; c) aucune bascule automatique, il faut un second dispositif **déclaré** ; d) il ne se scelle pas. Conséquences : l'audit est une dépendance de disponibilité (surveiller `/var/log`, alerte `OpenBaoAuditEnEchec`) ; un attaquant ne peut pas agir sans trace en remplissant le disque — il rend seulement le coffre indisponible.
13. **Rotation d'une clé de transit exposée.** `rotate` crée une version nouvelle, `rewrap` réécrit les textes chiffrés avec elle ; mais tant que `min_decryption_version` n'est pas relevée, l'ancienne version **déchiffre** encore, donc qui la détient lit tout ce qui a été chiffré par elle (ou par qui garde d'anciens textes chiffrés). Relever le minimum rend illisible tout texte non réenveloppé (fichiers SOPS non réécrits, sauvegardes) : coût = inventaire et réenveloppement complet **avant**. Même réglage que la variante 3 d'E42, conséquence inverse : là, relever trop tôt ferme le coffre.
14. **Phishing OIDC.** `allowed_redirect_uris` du rôle et redirections du client Keycloak sont **exactes** : une adresse de rappel étrangère est refusée par Keycloak puis par OpenBao ; l'état (`state`), le *nonce* et PKCE lient la réponse à la demande. L'OTP ne protège pas d'un hameçonnage **en temps réel** (proxy qui relaie identifiants et OTP) : il faudrait WebAuthn/passkeys (liés à l'origine), option du M24.
15. **Défense en profondeur.** Empêcher : politiques au plus juste, liaisons (audience, `bound_claims`, CIDR), TLS 1.3, pare-feu, OTP. Limiter : durées courtes, secrets dynamiques, enveloppement, jetons *batch*, quotas. Détecter et prouver : audit, alertes du ruler, essais (auto-descellement, politiques), instantanés éprouvés. La colonne la plus faible est **détecter** (pas de SIEM, alertes par courriel, peu de corrélation) : le M26 (Falco, auditd, détection à l'exécution) et le final F6 (SIEM, revue des accès) la renforcent.

**Pour l'auto-évaluation** : une réponse juste sans **preuve** sur notre configuration vaut la moitié ; une réponse qui propose de « désactiver » un contrôle pour se défendre est fausse.
