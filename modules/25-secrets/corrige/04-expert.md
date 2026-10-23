# Module 25 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les scripts de panne sont dans [`pannes/`](pannes/) (fonctions communes : [`_m25-commun.sh`](pannes/_m25-commun.sh)) ; les fichiers de solution dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un extrait des projets (`…/secrets/…` = `plateforme/secrets`, `…/ansible/…` = `plateforme/ansible`, `…/k8s/…` = `plateforme/k8s`, `…/gitops/…` = `plateforme/gitops`, `…/observabilite/…` = `plateforme/observabilite`, `…/medisphere/…` = la documentation, `kms01/…` = la configuration de `kms01`).

**Points non testés en conditions réelles** — signale tes retours, ils corrigent le workbook :
- **M25-E35**
  - `break-E35.sh` n'a pas été joué contre une grappe OpenBao. Il suppose que l'unité du paquet `.deb` recharge par SIGHUP (`systemctl reload openbao`, comme le rôle `certificats_acme` le fait déjà) et que ce rechargement relit le certificat **et** la clé de l'écouteur.
  - Variante 2, **mesurée à la relecture** sur une grappe d'essai OpenBao 2.7.1 (trois nœuds Raft en TLS, seal `transit`, nœud lancé sous `prlimit --nofile=64:64`) : le nœud démarre, se descelle et tient en attente avec ≈ 16 descripteurs ouverts (≈ 20 une fois actif) ; devenu actif, il a servi 120 requêtes parallèles courtes sans erreur (le serveur HTTP de Go réessaie `accept` quand les descripteurs manquent). La panne est donc **latente** : elle ne se voit que sous une charge soutenue de connexions simultanées (clients nombreux en *keep-alive*, ESO, CI). Le script accepte aussi le cas où le nœud ne démarrerait pas.
  - Les messages de `curl` cités suivent curl 8 avec OpenSSL 3 (Debian 13) ; leur libellé exact peut varier d'une version à l'autre.
- **M25-E36**
  - **Validé sur banc** (OpenBao **2.7.1** officiel en serveur de développement, méthode `jwt` montée en `gitlab/` sur une découverte OIDC simulée, jetons signés localement) : `break-E36.sh` injecté, constaté et annulé pour les quatre variantes, connexion d'essai après chaque étape. Constats : la mise à jour d'un rôle `jwt` garde les champs absents **sauf** `role_type` (absent = `oidc`, d'où le refus « 'allowed_redirect_uris' must be set… ») et `bound_claims_type` (absent = `string`) : le script les renvoie donc à chaque écriture ; `PATCH` n'est pas pris en charge sur les rôles ; un booléen dans `bound_claims` en type `glob` est refusé (`claim is not a string: true`) ; une `jwks_url` qui ne répond pas est refusée (`error checking jwks URL`), et seulement signalée en avertissement avec `skip_jwks_validation=true`. Messages relevés : v1 `invalid audience (aud) claim: audience claim does not match any expected audience` ; v2 `claim "ref_protected" does not match any associated bound claim values` ; v3 `error verifying token signature: fetching keys oidc: get keys failed Get "…/oauth/discovery/jwks.json": …` (la fin dépend de la réponse de `git01`, ici 404).
  - Non joué sur un lab : le pipeline réel de `mediagenda/api` et le composant `securite` (le message est celui de la CLI `bao` dans le job).
- **M25-E37**
  - **Vérifié dans le code d'ESO v2.13.0** (dépôt `external-secrets/external-secrets`, étiquette `v2.13.0`) : cache des clients OpenBao indexé par nom, espace, type **et `resourceVersion` du magasin** (`providers/v1/vault/provider.go`) ; réutilisation du jeton tant que `auth/token/lookup-self` le dit valide, sinon nouvelle connexion (`auth.go`) ; message générique « could not get secret data from provider » dans la condition, erreur complète dans l'événement `UpdateFailed` ; refus « SecretStore "openbao" is not ready » quand le magasin n'est pas prêt (`assertStoreIsUsable`) ; synchronisation relancée par tout changement d'annotation ou d'étiquette (empreinte des métadonnées) ; messages `cannot request Kubernetes service account token for service account "…"` et `cannot read secret data from Vault` ; métriques `externalsecret_status_condition` et `secretstore_status_condition` (étiquettes `name`, `namespace`, `condition`, `status`) ; `serviceMonitor.honorLabels: false` par défaut dans le chart. Règles d'alerte passées à `promtool` 3.15 (`check rules`, `test rules`).
  - **Script** : `break-E37.sh` exécuté avec des bouchons à la place de `kubectl` et d'OpenBao (enchaînement injection → constat → annulation de la variante 1) ; `bash -n` et `shellcheck -x` propres. Variantes 2 à 4 non jouées sur un cluster.
  - **Non vérifié** : le texte exact du refus d'audience d'OpenBao 2.7 pour la méthode `kubernetes` (attendu : « invalid audience (aud) claim… ») et son code HTTP ; le fait qu'une connexion TCP **établie** survive à l'ajout d'un `egressDeny` Cilium (le script recrée le pod du contrôleur pour ne pas en dépendre) ; le libellé de Hubble pour un refus par politique de refus ; le délai de reprise du magasin après correction (nouvel essai à intervalle croissant de controller-runtime, plafonné vers 16 min).
- **M25-E38**
  - **Validé sur banc** (OpenBao **2.6.4** officiel en serveur de développement, PostgreSQL 16 local avec les rôles `openbao` et `mediagenda_api` de M25-E14) : `max_ttl` inférieur à `default_ttl` accepté par le rôle, bail émis à 600 s ; mise à jour **partielle** d'un rôle et d'une connexion (seuls les champs envoyés changent ; `verify_connection` joue avec le nouveau mot de passe) ; `revoke-prefix` sur `db-mediagenda/creds/mediagenda-api-recette` (sans `/` final) ne touche que ce rôle, comptes supprimés de `pg_roles`, baux de prod intacts ; un changement du mot de passe d'`openbao` **n'est pas vu** tant qu'une connexion du pool d'OpenBao reste ouverte (identifiants délivrés, `rotate-root` réussi), puis, sessions coupées, `password authentication failed for user "openbao"` sur `creds` comme sur `rotate-root` ; révocations en échec réessayées (`failed to revoke lease … attempts=N next_attempt=…`) puis réussies une fois la connexion rendue ; reprise par [`reprise-openbao.sql`](fichiers/M25-E38/k8s/espaces/mediagenda-recette/sql/reprise-openbao.sql) (mot de passe tiré dans PostgreSQL, tube, `rotate-root`) ; `bao write … password=-` **garde** le saut de ligne final (d'où `tr -d '\r\n'`).
  - **Scripts** : `break-E38.sh` injecté, vérifié et annulé pour les variantes 1 à 3 contre ce banc (`kubectl` remplacé par un bouchon qui joue le SQL sur la base locale) ; variante 4 : seul le chemin « panne non constatée → annulation » est joué (pas de Cilium sur le banc). `check-E38.sh` joué avec des réponses simulées (état sain, variantes 1 et 4). `shellcheck -x` et `bash -n` propres.
  - **Non vérifié** : l'effet d'une `ingressDeny` Cilium sur un flux arrivé par le LoadBalancer `externalTrafficPolicy: Local` (attendu : la source 10.10.20.2x est conservée, et la documentation de Cilium donne le refus prioritaire sur toute autorisation) ; le texte exact des événements d'ESO 2.13 quand le générateur échoue (attendu : l'erreur d'OpenBao recopiée) et le maintien du Secret existant en cas d'échec ; les trois règles du ruler de Loki, écrites sur le modèle de celles de M25-E21 (vérifiées sur Loki 3.7.9) mais pas évaluées ; PostgreSQL 18 (CNPG) au lieu de 16 pour `VALID UNTIL`, `gen_random_uuid()` et `sha256()` (inchangés depuis la 13).
- **M25-E39**
  - **Vérifié dans le code d'OpenBao** (tag v2.4.1, `physical/raft/raft.go`, `vault/ha.go`, `http/handler.go`) et la documentation : récupération par `<chemin de données>/raft/peers.json` (lecture à l'ouverture du stockage Raft, journal `raft recovery initiated` / `found new config` / `deleted peers.json`, fichier supprimé ensuite) ; un nœud en attente lit l'actif dans le verrou HA de **sa copie locale** de l'état Raft (`RaftLock.Value`, « TODO: how to tell if held? ») ; une requête transmise sans actif connu répond 500 `local node not active but active cluster node not found`.
  - **Validé sur une grappe d'essai** (OpenBao **2.7.1**, trois nœuds Raft en TLS auto-descellés par un quatrième jouant `kms01`, relecture de la revue) pour la variante 1 et le retour du quorum : l'actif renonce en ≈ 4 s (`failed to contact quorum of nodes, stepping down`, `leadership lost, stopping active operation`), puis élections en boucle (`entering candidate state`, `failed to make requestVote RPC … connect: connection refused`) ; le survivant répond **429**, `sys/leader` sans adresse ; `list-peers` et les lectures servis localement (trois `follower`), `autopilot state` et les écritures en 500 `local node not active but active cluster node not found` ; un nœud relancé : actif en ≈ 3 s, tolérance 0, puis 1 avec le troisième.
  - **Non joué** : le script de panne contre une grappe (`bash -n` et `shellcheck -x` propres, syntaxe de la table nftables validée par `nft -c`) ; les variantes 2 et 3 (filtrage : `i/o timeout` attendu au lieu de `connection refused`, `sys/leader` d'un nœud isolé).
- **M25-E40 à M25-E45**
  - **Validé sur banc** (OpenBao **2.7.1** officiel, serveur de développement et petite grappe Raft de deux nœuds auto-descellée par un troisième OpenBao jouant `kms01`) : règles de correspondance des politiques (`+`, `*`, `data/`, `deny` sur motif identique ou moins précis, politiques de groupe appliquées tout de suite aux jetons existants), `sys/capabilities-accessor`, renommage d'un alias de groupe externe ; refus de signature PKI (domaine, usage de l'émetteur), certificat sans `clientAuth` quand `client_flag=false`, CRL de 2 min sans reconstruction ; `bao patch` refusé (403) à une politique sans la capacité `patch` ; `min_decryption_version` (refus au-delà de `latest_version`, « disallowed by policy (too old) », retour arrière) ; démarrage d'un nœud au seal `transit` avec un jeton inconnu (le processus s'arrête : « Error configuring seal "transit" … 403 ») et avec une politique sans `decrypt` ou une version minimale relevée (le processus reste, scellé, `failed to unseal core` toutes les 5 s, et se descelle seul une fois la cause levée) ; **jeton du seal jamais renouvelé** sans `auth/token/renew-self` dans `kms-autodescellement` (`last_renewal_time` vide), renouvelé avec ; `sys/key-status` en `read`, `sys/rotate` exigeant `sudo`, `sys/rotate/config` ; contenu du stockage Raft (noms KV v2 absents, structure en clair) ; nœud en attente : lecture servie localement, écriture transmise (200), 307 avec `X-Vault-No-Request-Forwarding`, lecture périmée juste après une écriture.
  - **Scripts** : `break-E40.sh` et `break-E41.sh` injectés, vérifiés et annulés (4 variantes chacun) contre ce banc, les appels Kubernetes remplacés par des bouchons ; `break-E42.sh` : parties `kms01` (politique, rotation et version minimale, jeton d'annulation) jouées sur le banc, parties « nœud » (`kms.env`, nftables, `systemctl`) **non jouées** ; `break-E43.sh` charge les scripts de M25-E35 à E42 en mode bibliothèque (`WB_PANNES_LIB=1`, tous présents ; un script absent serait écarté du tirage) : l'enchaînement des trois pannes n'a pas été joué sur un lab. `tester-politiques.sh`, `sonde-crl` et `openbao-essai-kms` exécutés sur le banc ; règles d'alerte passées à `promtool` 3.5 (`check rules`, `test rules`) ; tous les scripts au vert sous `shellcheck -x` et `bash -n`. Les checks ne sont pas rejoués sur un lab ; leurs analyseurs de politiques sont testés sur les fichiers du corrigé.
  - **Non vérifié** : le message exact de ghostunnel 1.11.5 quand un client présente un certificat sans `clientAuth` (Go refuse avec une erreur d'usage de clé incompatible) ; le fait que cert-manager 1.x tienne pour « prêt » un certificat émis sans un usage demandé (attendu : oui, il ne compare pas les usages du certificat obtenu) ; `cmctl renew` sur la version installée au M15 ; l'effet d'un renommage d'alias de groupe sur un jeton OIDC **renouvelé** (attendu : appartenance recalculée au renouvellement comme à la connexion) ; la métrique `certmanager_certificate_ready_status` avec l'étiquette `issuer_name` (présente dans les versions récentes de cert-manager : vérifie sur ta vue globale).

**Journaux et post-mortems** : un journal de diagnostic par panne, `docs/socle/journal/AAAA-MM-JJ-INC-52XX.md` de `plateforme/medisphere` (publié par MR), et le post-mortem de l'astreinte dans `docs/socle/post-mortems/AAAA-MM-JJ-INC-5243.md` ; les modèles de ce corrigé portent ces noms.

---

### M25-E35 — Panne : le coffre est scellé après un redémarrage

**Démarche de diagnostic**

*Symptômes* : un nœud sur trois ne répond plus au contrôle de Nadia, `OpenBaoScelle` a sonné pour ce nœud ; la VIP répond. Variante 2 (si le nœud a démarré) : tout est vert, seul l'aveu de Lucas signale un problème.

*Hypothèses*, de la plus grave à la plus fine : (a) le nœud est **scellé** (seal `transit`, `kms01`, jeton de `kms.env`) ; (b) le processus est **arrêté** ou redémarre en boucle ; (c) le nœud tourne mais est **injoignable** sur 8200 (écoute, pare-feu local) ; (d) il répond mais est **refusé** (certificat : nom, échéance, autorité) ; (e) il est **bridé** (limites de ressources) ; (f) il est **sorti de Raft**. Une seule observation sépare déjà (a) des autres : un nœud scellé **répond**, avec un 503 et `"sealed": true`.

**Étape 1 — Observer depuis les clients (adm01).** Le code seul ne suffit pas : il faut le message.

```
admin@adm01:~$ for n in vault01 vault02 vault03 openbao; do
    printf '%-8s ' "$n"
    curl -s -o /dev/null --max-time 5 -w '%{http_code} %{errormsg}\n' \
      "https://$n.par1.medisphere.internal:8200/v1/sys/health"
  done
vault01  429
vault02  200
vault03  000 Failed to connect to vault03.par1.medisphere.internal port 8200 after 1 ms: Couldn't connect to server
openbao  200
```

Trois familles de réponses. `Couldn't connect` (refus immédiat) : rien n'écoute à cette adresse, ou le processus est arrêté (variantes 1, et 2 si le nœud n'a pas démarré). `SSL: no alternative certificate subject name matches target host name 'vault03.par1.medisphere.internal'` : le nœud répond, mais sous une autre identité (variante 3). `429` partout : rien à voir de l'extérieur (variante 2 latente). Aucun 503 : l'hypothèse (a) est déjà très affaiblie.

D'où vient « une requête sur trois » ? Du contrôle de Nadia, qui interroge **chaque nœud par son nom**. Les clients réels (CI, ESO, cert-manager, Ansible) passent par la VIP, donc par l'actif : ils ne voient **rien**. Et `OpenBaoScelle` ? Son expression est `vault_core_unsealed == 0` **ou** `up == 0` : Prometheus n'arrive plus à lire le nœud (`up == 0`), l'alerte sonne avec le titre « scellé ou ne répond pas ». Nadia a lu « scellé ». Dans l'interface de Prometheus, la cible `vault03` donne la raison exacte (`connection refused` ou `x509: certificate is valid for vault01…, not vault03…`).

**Étape 2 — Mesurer depuis le nœud.** On l'interroge comme keepalived le fait : sous son nom, par la boucle locale.

```
admin@vault03:~$ systemctl status openbao --no-pager | head -4
admin@vault03:~$ sudo journalctl -u openbao --since today --no-pager | grep -Ei 'error|warn|reload|too many' | tail -20
admin@vault03:~$ curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt \
    --resolve vault03.par1.medisphere.internal:8200:127.0.0.1 \
    https://vault03.par1.medisphere.internal:8200/v1/sys/seal-status | jq '{sealed, type}'
{ "sealed": false, "type": "transit" }
admin@vault03:~$ sudo ss -ltn 'sport = :8200 or sport = :8201'
admin@vault03:~$ systemctl show openbao -p LimitNOFILE -p DropInPaths -p NRestarts
admin@vault03:~$ pid=$(systemctl show -p MainPID --value openbao)
admin@vault03:~$ sudo grep 'open files' /proc/$pid/limits; sudo ls /proc/$pid/fd | wc -l
admin@adm01:~$ openssl s_client -connect vault03.par1.medisphere.internal:8200 \
    -servername vault03.par1.medisphere.internal </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -ext subjectAltName -enddate
admin@adm01:~$ bao operator raft list-peers
admin@adm01:~$ bao operator raft autopilot state
```

Le nœud est **descellé** : (a) écartée. Raft le compte parmi les trois `voter`, autopilot le dit sain : (f) écartée. C'est attendu : Raft et le transfert de requêtes passent par **8201** (`cluster_address`), pas par l'écouteur API. La grappe peut être parfaitement saine pendant qu'un de ses nœuds est invisible de tous ses clients. Ce qui différencie les variantes, ce sont les trois lignes suivantes : `ss`, les limites et le certificat présenté.

**Étape 3 — Comparer avec Git.**

```
admin@adm01:~/src/ansible$ git switch main && git pull
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml --limit vault03 --check --diff
admin@vault03:~$ systemctl cat openbao | grep -E '^# /|LimitNOFILE'
admin@vault01:~$ systemctl cat openbao | grep -E '^# /|LimitNOFILE'      # un nœud sain, pour comparer
```

Ansible compare ce qu'il **gère** : le gabarit `openbao.hcl`, la surcharge `medisphere.conf`, le certificat (par `step certificate verify --host`). Ce qu'il ne gère pas, il ne le voit pas. `systemctl cat` montre au contraire tout ce que systemd applique, dans l'ordre.

**Variante 1 — écouteur limité à la boucle locale.**

```
admin@vault03:~$ sudo ss -ltn 'sport = :8200 or sport = :8201'
State  Recv-Q Send-Q Local Address:Port  Peer Address:Port
LISTEN 0      4096       127.0.0.1:8200       0.0.0.0:*
LISTEN 0      4096     10.10.20.23:8201       0.0.0.0:*
```

et dans le `--check --diff` :

```
-  address         = "127.0.0.1:8200"
+  address         = "0.0.0.0:8200"
```

Le nœud a redémarré avec un écouteur API qui n'accepte que la boucle locale. Pour lui-même, tout va bien : `chk_openbao_actif` l'interroge par `127.0.0.1`. Pour Prometheus, `adm01` et les autres nœuds, il n'existe plus. `api_addr` annonce toujours `https://vault03…:8200`, une adresse qui ne répond plus. C'est l'écart le plus simple à voir dans Git, parce que le fichier est géré par le rôle. Cause : modification à la main de `openbao.hcl`, prise en compte au redémarrage de la maintenance (un changement d'adresse d'écouteur demande un redémarrage, pas un SIGHUP).

Correctif : le rôle, sur ce seul nœud, redémarrage autorisé. Le nœud est **en attente** (vérifie-le d'abord : `sys/health` local = 429). Il se descelle seul par `kms01`.

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml --limit vault03 -e openbao_redemarrer=true
```

**Variante 2 — limite de descripteurs écrasée par une surcharge oubliée.**

```
admin@vault03:~$ systemctl cat openbao | grep -E '^# /|LimitNOFILE'
# /usr/lib/systemd/system/openbao.service
# /etc/systemd/system/openbao.service.d/medisphere.conf
LimitNOFILE=65536
# /etc/systemd/system/openbao.service.d/override.conf
LimitNOFILE=64
admin@vault03:~$ sudo grep 'open files' /proc/$pid/limits
Max open files            64                   64                   files
```

`override.conf` est le fichier que crée `systemctl edit openbao` : Lucas l'a utilisé pour un « essai de charge » et l'a oublié. systemd lit les surcharges par **ordre alphabétique** de nom de fichier, et pour un réglage à valeur unique comme `LimitNOFILE`, la dernière valeur l'emporte : `override.conf` passe après `medisphere.conf`. `LimitNOFILE` fixe les limites **souple et dure**. Le runtime Go relève de lui-même la limite souple jusqu'à la limite dure, mais pas au-delà : 64 descripteurs pour tout le processus. Chaque connexion cliente, chaque connexion Raft, chaque fichier ouvert en consomme un. Sur une grappe d'essai, 64 suffisent pour démarrer et tenir en attente (≈ 16 descripteurs), où il ne reçoit presque rien. Le jour où il devient actif, toute la charge arrive sur lui : au-delà d'une quarantaine de connexions simultanées, `accept: too many open files` (le serveur réessaie), délais, refus.

Le `--check --diff` n'affiche **rien** : le rôle ne connaît pas `override.conf`. C'est l'écart le plus sournois des trois, et la raison de la prévention ci-dessous.

Correctif, le nœud étant en attente (ou arrêté) : retirer le fichier, **recharger systemd**, redémarrer. Puis corriger le rôle par une MR ([extrait](fichiers/M25-E35/ansible/roles/openbao/tasks/configuration.yml.extrait), [variable](fichiers/M25-E35/ansible/roles/openbao/defaults/main.yml.extrait)) pour que la prochaine fois le `--check` le montre et que l'application le retire.

```
admin@vault03:~$ sudo rm /etc/systemd/system/openbao.service.d/override.conf
admin@vault03:~$ sudo systemctl daemon-reload
admin@vault03:~$ sudo systemctl restart openbao
admin@vault03:~$ sudo grep 'open files' /proc/$(systemctl show -p MainPID --value openbao)/limits
Max open files            65536                65536                files
```

Sans `daemon-reload`, `systemctl restart` relance le service avec l'**ancienne** configuration chargée (systemd le signale par un avertissement « unit file … changed on disk »).

**Variante 3 — le nœud se présente sous un autre nom.**

```
admin@adm01:~$ openssl s_client -connect vault03.par1.medisphere.internal:8200 \
    -servername vault03.par1.medisphere.internal </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -ext subjectAltName -enddate
subject=CN=vault01.par1.medisphere.internal
X509v3 Subject Alternative Name:
    DNS:vault01.par1.medisphere.internal, DNS:openbao.par1.medisphere.internal
notAfter=…
```

Le certificat est **valide** : bonne racine, pas expiré, et sa clé correspond (le nœud a rechargé sans erreur). Seulement, il a été émis pour `vault01`. Quelqu'un a recopié le certificat et la clé de `vault01` sur `vault03`, puis rechargé le service (SIGHUP). Tout client qui joint `vault03` **par son nom** le refuse : Prometheus, ton `curl`, et `chk_openbao_actif` du nœud lui-même. Un client qui le joindrait par le nom du service l'accepterait, puisque `openbao.par1.medisphere.internal` figure dans le certificat. Le `--check --diff` est trompeur : on voit `included: …/emettre.yml for vault03` (le rôle a vu que le certificat ne se vérifie pas pour `vault03`), mais les tâches `command` sont sautées en simulation et le récapitulatif annonce `changed=0`.

Correctif : réémettre le certificat **du nœud** par le rôle (ACME, défi HTTP-01 relayé par HAProxy, puis SIGHUP, sans redémarrage).

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml --limit vault03
```

Ni `step ca renew` (il renouvellerait l'identité de `vault01`, par TLS mutuel avec ce certificat), ni une nouvelle copie depuis un autre nœud. Une clé privée qui a voyagé entre deux machines n'est plus propre à aucune des deux. Note-le dans le journal : la clé de `vault01` a été exposée sur `vault03` (dans le lab, c'est le script de panne qui l'a copiée ; en production, on réémettrait aussi le certificat de `vault01`).

**Réponse à Nadia : et si l'actif redémarre cet après-midi ?** Les deux nœuds en attente se disputent l'élection : le nœud malade a environ une chance sur deux de prendre la main.

| Cause | Le nœud malade devient actif | Effet pour les clients |
|---|---|---|
| Écouteur sur 127.0.0.1 | `chk_openbao_actif` passe (boucle locale, 200) : keepalived lui donne la VIP | les requêtes arrivent sur 10.10.20.200:8200, où rien n'écoute : **tout** tombe |
| `LimitNOFILE=64` | la VIP le suit tant que son contrôle passe | rien au début (≈ 20 descripteurs utilisés) ; sous une charge soutenue de connexions simultanées, descripteurs épuisés : délais, refus, contrôle qui échoue par moments, VIP instable |
| Certificat d'un autre nœud | `chk_openbao_actif` échoue (nom du nœud) : le nœud reste en FAULT | personne ne porte la VIP : **tout** tombe, alors que le coffre est descellé et que Raft est sain |

Réponse écrite : « oui, un risque sur deux de coupure totale ; la maintenance de Lucas attend la réparation de `vault03` ». C'est aussi pour cela que l'avertissement de l'énoncé interdit le `step-down` « pour voir ».

**Clôture commune** : boucle `curl` de l'étape 1 (trois codes 200/429, aucun message d'erreur), `lab/bin/check 25 35`, puis `lab/bin/break 25 35 --annuler` et journal ([modèle](fichiers/M25-E35/medisphere/docs/socle/journal/AAAA-MM-JJ-INC-5235.md)).

**Prévention**
- **Dérive détectée par Ansible en mode vérification.** Le job `derive` de `plateforme/ansible` (M04-E29, `site.yml --check --diff` chaque nuit) voit la variante 1 telle quelle, à condition que `site.yml` importe `coffre.yml` et que ses tâches ne soient pas exclues par une étiquette : vérifie-le. Pour les deux autres, il faut d'abord que le rôle les **voie**. [Le rôle `openbao`](fichiers/M25-E35/ansible/roles/openbao/tasks/configuration.yml.extrait) liste le dossier de surcharge et retire tout fichier non déclaré (`openbao_surcharges_declarees`). En `--check`, chaque fichier en trop apparaît en `changed`. [Le rôle `certificats_acme`](fichiers/M25-E35/ansible/roles/certificats_acme/tasks/main.yml.extrait) compte un certificat à réémettre comme un changement, visible en simulation. Après toute maintenance manuelle, on lance soi-même le `--check --diff` du groupe touché, avant de rendre la main.
- **Alerte qui dit ce qu'elle a vu.** [`OpenBaoScelle` est scindée](fichiers/M25-E35/observabilite/regles/secrets.yaml.extrait) : `vault_core_unsealed == 0` pour un nœud qui répond et se dit scellé ; `OpenBaoInjoignable` pour `up == 0`, avec dans la description « ne pas desceller, vérifier depuis le nœud, pas de bascule avant réparation ». Les [tests unitaires](fichiers/M25-E35/observabilite/tests/secrets.test.yaml.extrait) de la règle sont mis à jour dans la même MR. Bonus : un avertissement sur l'écart entre la limite et l'usage des descripteurs, si l'exportateur expose `process_max_fds` (à vérifier sur ta version).
- **Revue de MR.** Toute modification des nœuds du coffre passe par une MR de `plateforme/ansible`, relue par un second membre de `plateforme-admins`. Le gabarit de MR du groupe `role_coffre` demande le `--check --diff` d'un nœud, l'ordre de passage (en attente d'abord) et le retour arrière. Une maintenance de nuit sans MR se termine par un `--check --diff` vert, collé dans le ticket de changement.

**Explications**

Un nœud OpenBao empile trois couches indépendantes. La **barrière** est scellée ou non : c'est ce que disent `sys/seal-status` et `vault_core_unsealed`. **Raft** parle sur 8201 avec ses propres certificats internes, et autopilot y mesure la santé. L'**écouteur API** sur 8200 porte le TLS du nœud, et c'est par lui que passent les clients, la supervision et keepalived. Une panne d'une couche laisse les autres intactes. Toute la difficulté est de ne pas conclure d'une couche à l'autre : « Raft le voit sain » ne dit rien de l'API, et « l'API ne répond pas » ne dit rien de la barrière.

La configuration **effective** n'est pas le fichier que l'on croit. Un écouteur se lit avec `ss`, une limite dans `/proc/<PID>/limits`, une unité avec `systemctl cat`, un certificat dans ce que le serveur **présente**. Les trois variantes ont un point commun : le fichier de référence (gabarit, `medisphere.conf`, demande ACME) n'a pas changé ou n'est pas en cause, mais ce qui tourne a changé.

Enfin, le contrôle de santé de la VIP regarde le nœud **depuis lui-même**. C'est voulu, la décision appartient au nœud qui porte la VIP. Mais ce contrôle ne garantit pas que les clients le joignent. D'où un contrôle complémentaire **depuis l'extérieur**, par nom (la supervision), avec une alerte qui ne confond pas « scellé » et « injoignable ».

**Alternatives**
- Comparer les trois nœuds d'un coup : `ansible role_coffre -b -m ansible.builtin.command -a 'systemctl show openbao -p LimitNOFILE -p DropInPaths'` ou `diff <(ssh vault01 sudo cat /etc/openbao/openbao.hcl) <(ssh vault03 sudo cat /etc/openbao/openbao.hcl)` (les noms et l'adresse de grappe diffèrent normalement).
- `bao status` avec `BAO_ADDR=https://vault03…:8200` : même information que `sys/health`, avec le message d'erreur du client Go (`dial tcp … connection refused`, `x509: certificate is valid for …`).
- Réparer la variante 2 en remettant `LimitNOFILE=65536` **dans** `override.conf` : ça remarche, mais un fichier non géré reste, et le prochain essai le réécrira.

**Pièges classiques**
- Croire le titre de l'alerte et partir sur `kms01`, le jeton du seal ou les dépositaires, alors que le nœud répond descellé par la boucle locale.
- Faire un `step-down` ou redémarrer l'actif « pour voir » : le nœud malade peut prendre la main (tableau ci-dessus).
- Redémarrer un nœud sans vérifier qu'il est **en attente**.
- Variante 1 : corriger le fichier par `sed` sans repasser le rôle, puis oublier le redémarrage (un changement d'adresse d'écouteur n'est pas relu par SIGHUP).
- Variante 2 : relever `LimitNOFILE` dans `medisphere.conf`, qui l'est déjà, ou oublier `daemon-reload`.
- Variante 3 : conclure « certificat expiré » sans lire le sujet et les noms ; lancer `step ca renew`, qui renouvelle la mauvaise identité.

**En production chez MédiSphère**

Une maintenance des nœuds du coffre suit un ticket de changement : MR relue, un nœud en attente à la fois, `--check --diff` vert du groupe avant et après, contrôle externe par nom des trois nœuds, puis seulement le nœud actif (passage de témoin). Un réglage d'essai se fait sur la VM jetable (`bao-essai`), jamais sur la grappe. La dérive nocturne couvre le coffre et ouvre un ticket. `OpenBaoInjoignable` et `OpenBaoScelle` renvoient à deux sections distinctes du RB-251.

---

### M25-E36 — Panne : la CI ne lit plus ses secrets

**Démarche de diagnostic**

*Symptômes* : `securite:verification` (le job du composant qui passe par `.openbao-connexion` avec le rôle `ci-mediagenda-api` pour lire le robot Harbor) échoue sur `main` de `mediagenda/api`, à l'étape OpenBao. Le dépôt et le composant n'ont pas changé.

*Hypothèses*, dans l'ordre de la chaîne : (a) coffre scellé ou injoignable ; (b) la méthode ne peut plus vérifier la **signature** (source des clés, autorité TLS, `git01`) ; (c) l'**émetteur** ou l'**audience** ne correspondent plus ; (d) une **revendication liée** ne correspond plus (projet, protection, référence, ou type de la valeur) ; (e) la connexion réussit mais le jeton n'a plus la bonne **politique** ; (f) côté GitLab, `main` n'est plus protégée ou l'`id_tokens` a changé.

**Étape 1 — Le journal du job.** Le message vient de la CLI `bao` lancée par `.openbao-connexion` :

```
Error writing data to auth/gitlab/login: Error making API request.
URL: PUT https://openbao.par1.medisphere.internal:8200/v1/auth/gitlab/login
Code: 400. Errors:
* error validating claims: claim "ref_protected" does not match any associated bound claim values
OpenBao refuse le rôle ci-mediagenda-api pour mediagenda/api@main (référence protégée ? projet lié au rôle ?)
```

Trois familles de messages possibles. Une erreur sur la **signature** ou les **clés** désigne la méthode (variante 3). Un code **400** `error validating claims` / `audience` désigne le rôle (variantes 1 et 2). Une ligne `OpenBao : connecté au rôle ci-mediagenda-api (default)` suivie d'un `Code: 403 … permission denied` sur `kv/data/plateforme/harbor/robot-ci` désigne les politiques (variante 4) : la connexion a **réussi**.

**Étape 2 — Délimiter.**

```
admin@adm01:~$ curl -s https://openbao.par1.medisphere.internal:8200/v1/sys/health | jq '{sealed, standby}'
```

Regarde ensuite le dernier pipeline de `medidoc/medidoc` et relance `tofu:plan` sur `main` de `plateforme/secrets`. S'ils se connectent, la méthode fonctionne et la panne est dans **le rôle** de MédiAgenda. Si **tous** échouent avec un message de clés, c'est **la méthode**, et le pipeline de `plateforme/secrets` est hors jeu lui aussi. Dans `mediagenda/api`, Paramètres > Dépôt > Branches protégées : `main` toujours protégée (hypothèse f écartée).

**Étape 3 — Configuration, au format JSON.**

```
admin@adm01:~$ bao read -format=json auth/gitlab/config | jq '.data | {oidc_discovery_url, jwks_url, bound_issuer, ca: (.oidc_discovery_ca_pem // .jwks_ca_pem | length > 0)}'
admin@adm01:~$ bao read -format=json auth/gitlab/role/ci-mediagenda-api \
    | jq '.data | {bound_audiences, bound_claims_type, bound_claims, token_policies, user_claim}'
admin@adm01:~/src/secrets$ tofu -chdir=tofu plan        # en lecture : la ressource qui dérive
```

**Étape 4 — L'audit** (Grafana, Loki, locataire `audit`) : d'abord les refus, puis l'écriture fautive.

```logql
{service="openbao"} | json chemin="request.path", op="request.operation", erreur="error"
  | chemin=~"auth/gitlab/(login|config|role/.*)" | line_format "{{.op}} {{.chemin}} {{.erreur}}"
```

Les `update auth/gitlab/login` portent l'erreur vue dans le job. Plus tôt, une écriture `update auth/gitlab/role/ci-mediagenda-api` ou `update auth/gitlab/config` donne l'heure et l'auteur (`auth.display_name` : ici ton jeton OIDC). `OpenBaoPolitiqueModifiee` (M25-E21) n'a **pas** sonné : elle ne regarde que `sys/policies/acl/*`. Un rôle ou une méthode modifiés passent sous son radar.

**Variante 1 — audience changée.**

```json
"bound_audiences": ["openbao.par1.medisphere.internal"]
```

Le job demande toujours un jeton d'identité d'audience `openbao.medisphere.internal` (`id_tokens:` du composant). OpenBao exige qu'**une** des audiences du jeton figure dans `bound_audiences` : aucune ne correspond, d'où un 400 : `error validating token: invalid audience (aud) claim: audience claim does not match any expected audience` (relevé sur OpenBao 2.7.1). L'« harmonisation » sur le nom DNS du service confond deux choses. L'audience n'est pas une adresse : c'est le nom **convenu** du destinataire, fixé au M19-E25 et inscrit dans chaque `id_tokens`. La changer d'un côté sans l'autre casse tous les jobs du rôle. Plan : `vault_jwt_auth_backend_role.ci["ci-mediagenda-api"]`. Correctif : apply de `main` par le pipeline de `plateforme/secrets`, qui n'est pas touché.

**Variante 2 — booléen contre chaîne.**

```
admin@adm01:~$ bao read auth/gitlab/role/ci-mediagenda-api | grep bound_claims
bound_claims         map[project_id:[4] ref:[main v*] ref_protected:true ref_type:[branch tag]]
bound_claims_type    string
admin@adm01:~$ bao read -format=json auth/gitlab/role/ci-mediagenda-api | jq -c '.data.bound_claims.ref_protected'
true
```

En tableau, rien ne distingue `true` de `"true"`. En JSON, la valeur liée est le **booléen** `true`. Or GitLab émet `"ref_protected": "true"`, une chaîne (relevé au M19-E25, rappelé par l'indice 1 d'E10). La comparaison est **typée** : un booléen n'égale jamais une chaîne, d'où `claim "ref_protected" does not match any associated bound claim values`. Le type est aussi passé à `string`, sans quoi OpenBao aurait refusé d'enregistrer un booléen. Ce second écart casse **en plus** les étiquettes, car `v*` devient un littéral. Le pipeline de `main` ne le montre pas, la prochaine release le montrerait. Correctif : apply de `main`. Le plan remet les deux champs.

**Variante 3 — clés introuvables.**

```
admin@adm01:~$ bao read -format=json auth/gitlab/config | jq -c '.data | {oidc_discovery_url, jwks_url}'
{"oidc_discovery_url":"","jwks_url":"https://git01.par1.medisphere.internal/oauth/discovery/jwks.json"}
admin@vault01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://git01.par1.medisphere.internal/oauth/discovery/jwks.json
404
admin@vault01:~$ curl -s https://git01.par1.medisphere.internal/.well-known/openid-configuration | jq -r .jwks_uri
https://git01.par1.medisphere.internal/oauth/discovery/keys
```

La méthode ne suit plus la découverte : elle va chercher les clés à une URL fixe, qui n'existe pas. Chaque connexion échoue **avant** toute comparaison de revendication, pour **tous** les rôles, y compris `ci-plateforme-secrets`. L'écriture n'a pu passer que parce que la validation a été sautée (`skip_jwks_validation=true`). Sans cette option, OpenBao aurait refusé d'enregistrer une URL de clés qui ne répond pas. Une option qui fait taire un refus est un signal d'alerte à la relecture.

Le pipeline de `plateforme/secrets` ne peut pas réparer la méthode qui l'authentifie. On passe donc au **bris de glace d'E10** : `tofu apply` depuis `adm01` avec ta session `plateforme-admin` et les copies locales des accès à l'état (`~/.config/workbook/`, palier 1) :

```
admin@adm01:~$ bao token lookup -format=json | jq -r '.data.ttl'       # au moins 20 min
admin@adm01:~/src/secrets$ git switch main && git pull
admin@adm01:~/src/secrets$ tofu -chdir=tofu plan -out=plan.tfplan     # seule vault_jwt_auth_backend.gitlab change
admin@adm01:~/src/secrets$ tofu -chdir=tofu apply plan.tfplan
```

Relance ensuite un `tofu:plan` dans le pipeline : il doit se connecter et ne rien proposer. Note le bris de glace dans le journal : un apply hors pipeline se justifie par écrit.

**Variante 4 — la politique retirée du rôle.**

```
OpenBao : connecté au rôle ci-mediagenda-api (default)
Error reading kv/data/plateforme/harbor/robot-ci: Error making API request.
Code: 403. Errors:
* permission denied
```

La connexion a réussi : signature, audience et revendications sont bonnes. Le jeton émis ne porte que `default`, car `token_policies` vaut `["default"]` au lieu de `["ci-mediagenda-api"]`. Chercher du côté du contenu de la politique `ci-mediagenda-api` serait une fausse piste : elle est intacte, elle n'est simplement plus **attribuée**. À la différence d'une politique de groupe (M25-E40), les politiques d'un rôle sont copiées dans le jeton **à son émission**. Une réparation ne profite qu'aux jetons suivants, ce qui ne pose aucun problème ici : chaque job se reconnecte. Correctif : apply de `main` par le pipeline.

**Clôture commune** : relance du pipeline de `main` de `mediagenda/api` jusqu'au vert, `lab/bin/check 25 36`, puis `lab/bin/break 25 36 --annuler` et journal ([modèle](fichiers/M25-E36/medisphere/docs/socle/journal/AAAA-MM-JJ-INC-5236.md)).

**Prévention**
- **Contrôle de dérive** : [`outils/verifier-roles-ci.sh`](fichiers/M25-E36/secrets/outils/verifier-roles-ci.sh) lit la méthode et **chaque** rôle `ci-*` sur le coffre réel, avec l'identité du pipeline. Il vérifie la découverte (et que `git01` sert ses clés), l'audience exacte, le type `glob`, des valeurs liées **toutes textuelles**, `ref_protected = "true"`, au moins une politique utile et existante. Il explique chaque écart en clair. Job [`roles-ci:verifier`](fichiers/M25-E36/secrets/.gitlab-ci.yml.extrait) après chaque apply et chaque nuit (pipeline planifié). Si c'est la méthode elle-même qui casse, ce job échoue à la connexion : c'est déjà l'alerte.
- **Audit** : une règle du ruler de Loki, sur le modèle d'`OpenBaoPolitiqueModifiee`, pour toute écriture sur `auth/+/config` ou `auth/+/role/*` faite par un autre jeton que celui du pipeline (`auth.metadata.project_path != "plateforme/secrets"`).
- Dans la relecture des MR de `plateforme/secrets`, tout `skip_jwks_validation`, tout changement d'audience et tout `bound_claims_type` autre que `glob` demandent deux relecteurs, comme les méthodes d'authentification (garde-fou du `tofu:plan`).

**Explications**

À chaque connexion, la méthode `jwt` déroule toujours la même chaîne. Elle vérifie d'abord la **signature** avec les clés publiées par l'émetteur (découverte OIDC, `jwks_url` ou clés recopiées : une seule source). Viennent ensuite les champs standard (`iss` contre `bound_issuer`, `aud` contre `bound_audiences`, `exp`, `nbf`), puis chaque `bound_claims`, comparé **avec son type** (`string` : égalité exacte ; `glob` : motif, valeurs textuelles seulement). Le jeton émis reçoit enfin les `token_policies` **du rôle**, figées à l'émission.

Chaque maillon a son message, et sa portée : les clés touchent la **méthode**, donc tous les rôles ; l'audience et les revendications touchent **un rôle** ; les politiques laissent passer la connexion et refusent la lecture. Lire le message du job, puis vérifier si les autres projets passent, suffit à situer la panne avant d'ouvrir la configuration.

**Alternatives**
- Diagnostiquer en rejouant la connexion à la main avec un jeton d'identité copié depuis un job : possible en théorie (le jeton vit 5 min), à proscrire en pratique (un jeton d'identité est une preuve d'identité, et il finit dans un historique ou un ticket). Le journal du job, la configuration en JSON et l'audit suffisent.
- `jwks_url` au lieu de la découverte : équivalent pour la signature quand l'URL est la bonne (`/oauth/discovery/keys`), mais un réglage de plus à maintenir. La découverte suit d'elle-même l'URL annoncée par GitLab.
- `bound_claims_type = "string"` avec la liste exacte des références : possible, mais il faut énumérer les étiquettes. `glob` est le choix d'E10. Dans les deux cas, les valeurs sont des **chaînes**.

**Pièges classiques**
- Lire le rôle en tableau et conclure « `ref_protected` vaut `true`, c'est bon ».
- Retirer `ref_protected` du rôle « pour débloquer la recette » : n'importe quelle branche non protégée lirait le robot Harbor.
- Ajouter la bonne audience **à côté** de la mauvaise : ça remarche, mais la dérive reste et le plan ne sera jamais vide.
- Activer `CI_DEBUG_TRACE` pour voir le jeton : il est alors dans le journal du job, pour tout le projet.
- Variante 3 : attendre le pipeline de `plateforme/secrets` pour réparer, alors qu'il ne peut pas se connecter non plus.
- Variante 4 : modifier la **politique** `ci-mediagenda-api` alors que c'est son **attribution** qui manque.

**En production chez MédiSphère**

La configuration des méthodes d'authentification est traitée comme du code critique : modifications par MR seulement, relecture à deux, contrôle de dérive nocturne qui ouvre un incident, alerte d'audit sur toute écriture hors pipeline. Le bris de glace (apply depuis un poste d'administration) est prévu, testé une fois par trimestre, et chaque usage est justifié dans le journal. Un canari par projet critique (un job planifié qui se connecte et lit un secret témoin sans valeur) montre la panne avant le premier développeur du matin.

---

### M25-E37 — Panne : un ExternalSecret en erreur

**Démarche de diagnostic**

*Symptômes* : `harbor-pull` en `SecretSyncedError`, application Argo CD `mediagenda-recette` *Degraded* (contrôle de santé intégré des ExternalSecret), Secret figé sur sa dernière valeur.

*Hypothèses*, du plus proche au plus loin : (a) l'**ExternalSecret** lui-même (clé, propriété : exclu si l'overlay n'a pas changé — à vérifier dans l'historique Git et dans Argo CD) ; (b) le **chemin** que le magasin fait lire (moteur, version KV) ; (c) la **connexion** du magasin (compte de service, rôle, audience, liaison `auth-delegator`) ; (d) le **réseau** entre le contrôleur et la VIP ; (e) le **coffre** (scellé, sans leader : M25-E35, E39) ; (f) la **politique** `eso-mediagenda-recette`.

**Étape 1 — La portée**

```
admin@adm01:~$ kubectl -n mediagenda-recette get externalsecrets
NAME                      STORETYPE     STORE     REFRESH INTERVAL   STATUS              READY
harbor-pull               SecretStore   openbao   1h                 SecretSyncedError   False
mediagenda-db-api         …                       30m                SecretSynced        True
mediagenda-db-migrateur   …                       30m                SecretSynced        True
admin@adm01:~$ kubectl get secretstores -A ; kubectl get clustersecretstores
admin@adm01:~$ kubectl -n mediagenda-recette get externalsecret harbor-pull -o jsonpath='{.status.refreshTime}{"\n"}'
```

Les deux identifiants dynamiques passent par des **générateurs** (`VaultDynamicSecret`), qui ont leur propre configuration de fournisseur : ils ne dépendent pas du SecretStore. Qu'ils restent sains alors que `harbor-pull` échoue désigne le magasin (variantes 1 et 4) ; s'ils échouent à leur tour à leur rafraîchissement suivant, la cause est commune au rôle ou au réseau (variantes 2 et 3). **Tous** les magasins du cluster en erreur : réseau ou coffre (variante 3), jamais l'overlay.

**Étape 2 — Le message**

```
admin@adm01:~$ kubectl -n mediagenda-recette describe externalsecret harbor-pull | sed -n '/^Events:/,$p'
admin@adm01:~$ kubectl -n mediagenda-recette describe secretstore openbao | sed -n '/^Status:/,$p'
admin@adm01:~$ kubectl -n external-secrets logs deploy/external-secrets --since=30m | grep mediagenda-recette | tail -5
```

La condition `Ready` dit seulement « could not get secret data from provider » : ESO 2.13 ne recopie pas une erreur de fournisseur dans le statut (elle pourrait contenir une valeur). L'événement `UpdateFailed` porte l'erreur complète. « SecretStore "openbao" is not ready » renvoie aux événements **du magasin** (`InvalidProviderConfig`).

**Étape 3 — Les écarts aux dépôts**

```
admin@adm01:~/src/k8s$ git switch main && git pull && task diff            # magasin et compte (plateforme/k8s)
admin@adm01:~/src/secrets$ tofu -chdir=tofu plan                             # rôle (lecture seule)
admin@adm01:~$ kubectl -n external-secrets get ciliumnetworkpolicies         # face à manifestes/external-secrets/
admin@adm01:~$ bao read -format=json auth/k8s-par1/role/eso-mediagenda-recette | jq '.data | {audience, bound_service_account_names, bound_service_account_namespaces, token_policies}'
```

**Variante 1 — `version: v1` dans le magasin.**

```
Warning  UpdateFailed  …  cannot read secret data from Vault: Error making API request.
URL: GET https://openbao.par1.medisphere.internal:8200/v1/kv/mediagenda/recette/harbor-pull
Code: 403. Errors:
* 1 error occurred:
	* permission denied
```

Le magasin est `Valid` : la connexion réussit, c'est la **lecture** qui est refusée. L'URL n'a pas de `data/` : en `v1`, ESO lit `<path>/<clé>` ; en `v2`, `<path>/data/<clé>`. La politique `eso-mediagenda-recette` n'ouvre que `kv/data/mediagenda/recette/*` : OpenBao refuse avant même de router la requête vers le moteur. L'audit le confirme :

```logql
{service="openbao"} | json role="auth.metadata.role", chemin="request.path", erreur="error"
  | role="eso-mediagenda-recette" | erreur="permission denied" | line_format "{{.chemin}}"
```

`task diff` montre `version: v1` → `v2`. Correctif : `task appliquer` depuis `main` (le dépôt a raison ; `--force-conflicts` reprend le champ posé par un autre gestionnaire). Le changement de `resourceVersion` du magasin vide l'entrée du cache : la correction prend effet dès la synchronisation suivante. Le piège voisin, `path: kv/data` (ESO ajoute `data/` : `kv/data/data/…`), donne le même 403 (M25-E12).

**Variante 2 — audience du rôle changée dans le coffre.**

```
Warning  InvalidProviderConfig  …  … auth/k8s-par1/login … invalid audience (aud) claim …
```

Le magasin envoie un jeton projeté d'audience `openbao.medisphere.internal` (`serviceAccountRef.audiences`) ; le rôle attend désormais `openbao.par1.medisphere.internal` (une « harmonisation avec le nom du service »). `tofu plan` : `vault_kubernetes_auth_backend_role.eso_espace["mediagenda-recette"]` à mettre à jour, `audience`. L'audit donne l'heure et l'auteur de l'écriture sur `auth/k8s-par1/role/eso-mediagenda-recette` (ici ton jeton : l'injection l'utilise), et la révocation des jetons d'ESO de ce rôle juste après. **Sans** cette révocation, rien ne se serait vu pendant au plus 15 min : ESO garde son jeton tant qu'il est valide (cache), et l'erreur serait apparue « toute seule », loin du changement. Correctif : relancer le pipeline de `main` de `plateforme/secrets` (apply) ; ESO se reconnecte au premier essai suivant. Les générateurs de recette, qui utilisent le même rôle, échouaient aussi à leur rafraîchissement : vérifier qu'ils ont repris avant la fin des baux en cours.

**Variante 3 — une politique de refus en sortie d'ESO.**

```
Warning  InvalidProviderConfig  …  dial tcp 10.10.20.200:8200: i/o timeout
admin@adm01:~$ kubectl -n external-secrets get cnp
NAME                         AGE
external-secrets-sorties     41d
external-secrets-telemetrie  12m
admin@adm01:~$ kubectl -n external-secrets get cnp external-secrets-telemetrie -o yaml | yq '.spec'
admin@adm01:~$ hubble observe -n external-secrets --to-ip 10.10.20.200 --last 20
```

Tous les magasins sont en erreur (y compris le ClusterSecretStore), le coffre répond aux autres clients, le pod du contrôleur a été recréé récemment. `external-secrets-telemetrie` n'existe pas dans `plateforme/gitops` : Argo CD ne l'affiche pas, faute de la gérer (le nom anodin et l'annotation `OBS-2637` n'en font pas un objet légitime). Son `egressDeny` vise `10.10.20.192/26`, soit `.192` à `.255` : la VIP `.200` en fait partie. Un refus l'emporte sur l'autorisation explicite d'`external-secrets-sorties`, **quelle que soit** la politique qui la porte. Correctif : supprimer l'objet (espace de plateforme, changement d'urgence tracé) ; si une règle de télémétrie est voulue, elle passe par une MR de `plateforme/gitops` et s'écrit en autorisation, sans refus large. Les ExternalSecret de **tout** le cluster sont touchés : après correction, vérifier `kubectl get es -A`.

**Variante 4 — compte de service inexistant.**

```
Warning  InvalidProviderConfig  …  cannot request Kubernetes service account token for service account "external-secrets": …
  serviceaccounts "external-secrets" not found
```

Le magasin demande à l'API un jeton projeté pour `external-secrets` (le compte du **contrôleur**, dans **son** espace, celui du ClusterSecretStore) ; un SecretStore ne peut demander qu'un compte de **son** espace, et seul `eso` y existe (et lui seul est lié à `system:auth-delegator` et au rôle). `task diff` montre `serviceAccountRef.name`. Correctif : `task appliquer`. Créer un compte `external-secrets` dans l'espace « pour que ça marche » serait faux deux fois : le rôle ne l'accepte pas (`bound_service_account_names = ["eso"]`) et l'objet sortirait du dépôt.

**Clôture commune**

```
admin@adm01:~$ kubectl -n mediagenda-recette annotate externalsecret harbor-pull force-sync="$(date +%s)" --overwrite
admin@adm01:~$ kubectl -n mediagenda-recette get secretstore openbao ; kubectl -n mediagenda-recette get es
admin@adm01:~$ argocd app get mediagenda-recette --refresh | sed -n '1,12p'
```

L'annotation est une métadonnée : elle change l'empreinte des métadonnées et déclenche une synchronisation, sans toucher la spec (Argo CD ne la compte pas comme une dérive). Un magasin resté `InvalidProviderConfig` après la correction (variantes 2 et 3) se revalide au prochain essai du contrôleur ; une modification de métadonnée du magasin le fait tout de suite. Puis `lab/bin/check 25 37` ; `lab/bin/break 25 37 --annuler` ; journal ([modèle, variante 3](fichiers/M25-E37/medisphere/docs/socle/journal/AAAA-MM-JJ-INC-5237.md)) ; Julien relance sa rotation.

**Prévention**
- [Alertes](fichiers/M25-E37/observabilite/regles/external-secrets.yaml) `ExternalSecretEnErreur` (15 min), `MagasinSecretsEnErreur` (10 min) et `MagasinsSecretsTousEnErreur` (cause commune), avec leurs [tests](fichiers/M25-E37/observabilite/tests/external-secrets.test.yaml) (`yq '.spec' regles/external-secrets.yaml > build/regles/external-secrets.yml && cd tests && promtool test rules external-secrets.test.yaml`) et l'[ajout à la kustomization](fichiers/M25-E37/observabilite/regles/kustomization.yaml.extrait). L'espace de l'objet est lu dans `exported_namespace` **ou** `namespace` : avec le ServiceMonitor du chart (`honorLabels: false`), `namespace` vaut `external-secrets` pour toutes les séries.
- `task derive` de `plateforme/k8s` planifiée (dérive du magasin), plan nocturne de `plateforme/secrets` (dérive du rôle, comme au M25-E40), et recherche des objets **hors Git** dans les espaces de plateforme (une CNP qu'aucune Application ne suit).
- [Fiche réflexe](fichiers/M25-E37/medisphere/docs/securite/secrets/fiche-externalsecret-en-erreur.md) « ExternalSecret en erreur » pour l'astreinte.

**Explications**

ESO ne parle au coffre que par le **magasin** : à chaque synchronisation, il prend (ou réutilise) un client OpenBao pour ce magasin, se connecte par la méthode `k8s-par1` avec un jeton projeté du compte désigné, puis lit le chemin construit à partir de `path`, `version` et de la clé de l'ExternalSecret. Le cache de clients est indexé par la `resourceVersion` du magasin : modifier le magasin crée un nouveau client (effet immédiat), modifier le **rôle** dans le coffre ne se voit qu'à la reconnexion suivante (jeton expiré). Un magasin est revalidé par son propre contrôleur (statut `Ready`) ; tant qu'il n'est pas prêt, les ExternalSecret qui l'utilisent ne tentent même plus de lire. Un ExternalSecret en échec garde son Secret intact et réessaie à intervalle croissant : la panne est silencieuse jusqu'à ce qu'une **nouvelle** valeur doive passer, d'où l'intérêt de l'alerte.

**Alternatives**
- Lire la valeur du Secret et la comparer au coffre pour « voir si c'est à jour » : expose un secret pour rien ; `refreshTime`, `syncedResourceVersion` et l'annotation d'empreinte des données du Secret (`reconcile.external-secrets.io/data-hash`) suffisent.
- Désactiver le cache de jetons pour des erreurs immédiates : une connexion par synchronisation et un audit bien plus bruyant ; on garde le cache et on connaît le délai.
- Redémarrer ESO « pour voir » : vide le cache et masque la chronologie ; utile seulement pour prouver qu'une connexion établie survivait à une politique réseau.

**Pièges classiques**
- S'arrêter à la condition (« could not get secret data from provider ») sans lire les événements.
- Élargir la politique `eso-mediagenda-recette` (`kv/mediagenda/*`) parce que le message dit « permission denied » : la cause était le chemin (variante 1), et l'espace lirait autre chose que sa recette.
- Corriger le magasin par `kubectl edit` : marche, mais le dépôt et `task diff` ne disent plus rien ; ou modifier l'ExternalSecret à la main : Argo CD le remet.
- Chercher la politique réseau dans Argo CD : il ne montre que ce qu'il gère.
- Conclure trop vite qu'un changement de rôle est « sans effet » : le cache de jetons retarde l'erreur d'un quart d'heure.
- Oublier les identifiants dynamiques : `harbor-pull` peut attendre, pas un bail d'une heure qui n'est plus renouvelé.

**En production chez MédiSphère**

Alertes sur les ExternalSecret et les magasins routées vers l'équipe propriétaire de l'espace **et** la plateforme ; Kyverno (M26) interdit aux équipes `SecretStore`, `ClusterSecretStore`, générateurs et CiliumNetworkPolicy dans les espaces de plateforme ; toute écriture sur `auth/*/role/*` hors du jeton du pipeline de `plateforme/secrets` remonte comme `OpenBaoPolitiqueModifiee` (M25-E21) ; dérive Kubernetes et OpenBao vérifiée chaque nuit, objets hors Git listés chaque semaine.

---

### M25-E38 — Panne : MédiAgenda perd sa base

**Démarche de diagnostic**

*Symptômes* : en recette, l'API répond 500 (`/pret` 503) par périodes ; `password authentication failed for user "v-…"` dans ses journaux ; la base répond à d'autres comptes.

*Hypothèses* : (a) le compte de l'API **meurt trop tôt** (durée du rôle, plafond du montage) ; (b) il a été **supprimé** avant l'heure (révocation) ; (c) le coffre **ne délivre plus** de compte : connexion d'administration refusée (mot de passe d'`openbao`), base injoignable (réseau, Service, primaire), ou ESO qui ne s'authentifie plus au coffre (M25-E37) ; (d) le compte est délivré mais l'application ne le **reprend** pas (Reloader, annotation du Rollout, E15) ; (e) côté base : rôle de groupe `mediagenda_api` ou option ADMIN d'`openbao` perdus (CNPG `inRoles`, M25-E14). La clé est la **chronologie** : quand le compte est né, quand il devait mourir, quand il a cessé de marcher.

**Étape 1 — Le compte refusé, et son âge**

```
admin@adm01:~$ kubectl -n mediagenda-recette logs -l app.kubernetes.io/name=mediagenda -c api --since=1h --timestamps \
    | grep -m3 'password authentication failed'
admin@adm01:~$ kubectl -n mediagenda-recette get secret mediagenda-db-api -o jsonpath='{.data.username}' | base64 -d; echo
v-k8s-par1-mediagen-Xb2…-1792…
admin@adm01:~$ kubectl -n mediagenda-recette get es mediagenda-db-api \
    -o jsonpath='{.status.refreshTime}{"  "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
admin@adm01:~$ kubectl -n mediagenda-recette describe es mediagenda-db-api | sed -n '/Events/,$p'
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -c \
    "SELECT r.rolname, r.rolvaliduntil FROM pg_roles r JOIN pg_auth_members m ON m.member = r.oid
      JOIN pg_roles g ON g.oid = m.roleid WHERE g.rolname = 'mediagenda_api' AND r.rolname LIKE 'v-%' ORDER BY 2"
```

Le nom du compte vient de la clé `username` (jamais `uri`, qui contient le mot de passe). Le gabarit de nom du greffon tronque le nom du rôle à 8 caractères (`mediagen`) : comptes `api` et `migrateur` se distinguent par leur rôle de groupe, d'où la jointure. Trois lectures possibles : compte **présent, `VALID UNTIL` déjà passé** et ExternalSecret à l'heure (durée trop courte : variante 1) ; compte **absent** alors qu'il devait vivre encore (supprimé : variante 2) ; ExternalSecret **en erreur**, compte présent mais bientôt expiré, comptes expirés qui s'accumulent (le coffre ne délivre plus et ne révoque plus : variantes 3 et 4).

**Étape 2 — Le coffre**

```
admin@adm01:~$ bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette
admin@adm01:~$ bao lease lookup db-mediagenda/creds/mediagenda-api-recette/<BAIL>    # issue_time, expire_time, ttl
admin@adm01:~$ bao read db-mediagenda/roles/mediagenda-api-recette
admin@adm01:~$ bao read db-mediagenda/config/mediagenda-recette                       # jamais de mot de passe affiché
admin@vault01:~$ sudo journalctl -u openbao --since -2h | grep -E 'failed to revoke|mediagenda' | tail
```

Audit (Grafana, Loki, locataire `audit`) — ce qui a été demandé ou modifié sur le moteur et sur les baux :

```logql
{service="openbao"} | json type="type", chemin="request.path", op="request.operation", qui="auth.display_name", erreur="error"
  | type="response" | chemin=~"db-mediagenda/.+|sys/leases/revoke.*"
  | line_format "{{.op}} {{.chemin}} {{.qui}} {{.erreur}}"
```

Un identifiant d'essai, **révoqué aussitôt** : `bao read -format=json db-mediagenda/creds/mediagenda-api-recette | jq -r .lease_id`, puis `bao lease revoke <BAIL>` (ne jamais afficher la réponse complète : elle contient le mot de passe).

**Étape 3 — La base et le réseau** (si le coffre ne délivre plus)

```
admin@vault01:~$ timeout 5 bash -c '</dev/tcp/10.10.41.64/5432' && echo ouvert || echo fermé     # sur le nœud ACTIF
admin@adm01:~$ kubectl -n mediagenda-recette get svc mediagenda-db-openbao -o wide
admin@adm01:~$ kubectl -n mediagenda-recette get ciliumnetworkpolicies
admin@adm01:~$ hubble observe --namespace mediagenda-recette --port 5432 --verdict DROPPED --last 20
admin@adm01:~$ kubectl -n mediagenda-recette get cluster mediagenda-db -o jsonpath='{.spec.managed.roles[?(@.name=="openbao")]}'; echo
```

**Variante 1 — `max_ttl` du rôle ramené à 10 min.**

```
admin@adm01:~$ bao read -format=json db-mediagenda/roles/mediagenda-api-recette | jq -c '.data | {default_ttl, max_ttl}'
{"default_ttl":3600,"max_ttl":600}
```

Un bail dure le plus petit de `default_ttl` et `max_ttl` (lui-même plafonné par le montage, 24 h) : 10 min. `VALID UNTIL` suit (`{{expiration}}`), et OpenBao fait `DROP ROLE` à la fin du bail. ESO ne redemande qu'au bout de 30 min : chaque cycle laisse **20 min** sans compte valable, puis l'API remarche 10 min après le redémarrage par Reloader. C'est le « toutes les heures environ » du ticket : **périodique**, sans aucune erreur côté coffre. Audit : `update db-mediagenda/roles/mediagenda-api-recette` par un jeton de personne ; `tofu plan` de `plateforme/secrets` : `vault_database_secret_backend_role.mediagenda["mediagenda-api-recette"]`, `max_ttl 600 -> 86400`. Correctif : apply de `main` par le pipeline (le dépôt a raison), puis rafraîchissement forcé :

```
admin@adm01:~$ kubectl -n mediagenda-recette annotate es mediagenda-db-api force-sync=$(date +%s) --overwrite
admin@adm01:~$ kubectl argo rollouts get rollout mediagenda -n mediagenda-recette --watch
```

Les comptes déjà délivrés gardent leur bail de 10 min (la durée est fixée à l'émission) : seul un nouveau compte vit 1 h. Prod : même effet si l'on touche `mediagenda-api-prod`.

**Variante 2 — baux révoqués « par ménage ».**

```
admin@adm01:~$ bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette
No value found at sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette
```

Plus aucun bail, et le compte du Secret est **absent** de `pg_roles` alors qu'il devait vivre encore une demi-heure. Audit : `update sys/leases/revoke-prefix/db-mediagenda/creds/mediagenda-api-recette` (ou une série de `sys/leases/revoke`). La révocation a fait `DROP ROLE` de tous les comptes en service : les sessions ouvertes cessent de fonctionner, les nouvelles connexions sont refusées. ESO ne le sait pas : le Secret garde un compte mort jusqu'au rafraîchissement suivant (≤ 30 min), puis tout repart seul — panne **unique**, qui « revient seule ». Redémarrer les pods ne sert à rien (ils relisent le même Secret). Correctif : rafraîchissement forcé tout de suite (commande ci-dessus). Le « ménage » n'avait aucun objet : un bail expiré est révoqué par OpenBao lui-même, et `revoke-prefix` est un geste d'incident (RB-250). Remarque pour le post-mortem : `plateforme-admin` porte `sys/leases/revoke-prefix/*` (M25-E23), donc **aussi** sur `db-mediagenda/creds/mediagenda-api-prod` ; en prod, la même commande coupe la prod pour ≤ 30 min.

**Variante 3 — mot de passe d'`openbao` changé dans PostgreSQL.**

```
admin@adm01:~$ kubectl -n mediagenda-recette describe es mediagenda-db-api | sed -n '/Events/,$p'
  Warning  …  … password authentication failed for user "openbao" …
admin@vault01:~$ sudo journalctl -u openbao --since -1h | grep 'failed to revoke lease' | tail -1
… failed to revoke lease: lease_id=db-mediagenda/creds/mediagenda-api-recette/… error="… password authentication failed for user \"openbao\" …" attempts=2 …
```

Le coffre ne peut plus **ni créer ni supprimer** de compte. ESO passe en erreur et **garde** l'ancien Secret : l'API tient jusqu'au `VALID UNTIL` de son compte (≤ 1 h), puis chaque nouvelle connexion est refusée : panne **permanente**, qui ne revient pas seule. Les comptes expirés non supprimés s'accumulent dans `pg_roles`. Qui a changé le mot de passe ? Deux pistes : `passwordSecret` revenu dans `managed.roles` du Cluster (CNPG réapplique alors le mot de passe de ce Secret, M25-E14), ou un `ALTER ROLE` à la main (PostgreSQL ne le journalise pas par défaut : question pour le post-mortem). `rotate-root` échoue, puisqu'OpenBao doit d'abord se connecter. Reprise par le superutilisateur de CNPG ([`reprise-openbao.sql`](fichiers/M25-E38/k8s/espaces/mediagenda-recette/sql/reprise-openbao.sql)) :

> ⚠️ **Attention** : ouvre d'abord une session de secours (`kubectl cnpg psql mediagenda-db -n mediagenda-recette`) et garde-la jusqu'à la fin. Le mot de passe provisoire est tiré **dans** PostgreSQL et ne passe que par le tube ; s'il échoue en route, rejoue simplement la commande.

```
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -X -qAt -d mediagenda -f - \
    < ~/src/k8s/espaces/mediagenda-recette/sql/reprise-openbao.sql | tr -d '\r\n' \
    | bao write db-mediagenda/config/mediagenda-recette password=-
Success! Data written to: db-mediagenda/config/mediagenda-recette
admin@adm01:~$ bao write -f db-mediagenda/rotate-root/mediagenda-recette
admin@adm01:~$ kubectl -n mediagenda-recette annotate es mediagenda-db-api force-sync=$(date +%s) --overwrite
```

L'écriture n'envoie que `password` : le reste de la connexion est conservé, et `verify_connection` refuse un mot de passe faux. Après `rotate-root`, plus personne ne connaît le mot de passe. OpenBao réessaie seul les révocations en échec ; un bail abandonné après trop d'échecs (« irrévocable ») laisse un compte `v-…` expiré à supprimer (`identifiants-dynamiques.md` § 6). Le code ne change pas (`tofu plan` vide : le mot de passe n'est pas dans l'état). Prod : même mécanique, l'API de prod tombe dans l'heure.

**Variante 4 — politique réseau qui refuse le coffre.**

```
admin@vault01:~$ timeout 5 bash -c '</dev/tcp/10.10.41.64/5432' && echo ouvert || echo fermé
fermé
admin@adm01:~$ hubble observe --namespace mediagenda-recette --port 5432 --verdict DROPPED --last 5
… 10.10.20.21:… -> mediagenda-recette/mediagenda-db-1:5432 … DROPPED (Policy denied by denylist)
admin@adm01:~$ kubectl -n mediagenda-recette get cnp mediagenda-db-quarantaine -o yaml | sed -n '/annotations/,$p'
```

ESO en erreur avec un délai dépassé (et non une authentification refusée), révocations en échec, puis même chronologie que la variante 3. La politique `mediagenda-db-quarantaine` (« durcissement SEC-2638 ») pose `ingressDeny` depuis `10.10.20.0/24` vers 5432 : un **refus** l'emporte sur toute autorisation, y compris `mediagenda-db-depuis-openbao`. Elle n'est pas dans `plateforme/k8s` (objet créé à la main). Elle était de surcroît **inutile** : les instances sont déjà en refus par défaut, seules 10.10.20.21-23 sont autorisées ; un « durcissement » s'écrit en resserrant les autorisations, pas en ajoutant un refus large. Correctif : avec l'accord de l'auteur du ticket SEC-2638 (annotation), suppression de l'objet hors Git, consignée dans le journal et le ticket (`kubectl -n mediagenda-recette delete cnp mediagenda-db-quarantaine`) ; si une exigence demeure, MR `plateforme/k8s`. Puis rafraîchissement forcé. OpenBao se reconnecte seul à la requête suivante.

**Pourquoi la panne n'apparaît pas à l'instant du changement (variantes 3 et 4).** Le greffon PostgreSQL d'OpenBao garde un pool de connexions ouvertes (`max_open_connections` 4) : un changement de mot de passe ou une nouvelle politique Cilium ne touchent pas une connexion déjà établie. La panne se révèle à la **prochaine** connexion : bascule du primaire CNPG, changement de leader d'OpenBao, redémarrage d'un nœud — souvent la nuit, sans lien apparent. L'injection coupe les sessions d'`openbao` pour que tu la voies tout de suite.

**Clôture commune** : boucle `curl` sur `/pret` pendant le redémarrage (aucun 503), `pg_stat_activity` montre le nouveau compte, `lab/bin/check 25 38`, `lab/bin/break 25 38 --annuler`, journal ([modèle](fichiers/M25-E38/medisphere/docs/socle/journal/AAAA-MM-JJ-INC-5238.md)).

**Prévention**
- **Audit** : trois règles ajoutées au ruler de Loki ([extrait](fichiers/M25-E38/observabilite/loki/regles/audit/openbao.yaml.extrait)) : `IdentifiantsDynamiquesEnEchec` (demandes `creds` en erreur depuis 5 min : variantes 3 et 4, **avant** que l'application tombe), `OpenBaoBauxRevoquesEnMasse` (variante 2), `MoteurDatabaseModifie` (variante 1, à rapprocher d'une MR).
- **Règle de durée** : vie d'un identifiant ≥ 2 cycles d'ESO, écrite dans [`identifiants-dynamiques.md` § 6](fichiers/M25-E38/medisphere/docs/securite/secrets/identifiants-dynamiques.md.extrait) avec la démarche en quatre questions ; le plan planifié de `plateforme/secrets` (M25-E40) signale toute dérive du rôle.
- **Base et réseau** : `passwordSecret` ne revient jamais dans le rôle `openbao` (relecture des MR du Cluster) ; politiques réseau des bases uniquement dans Git, relues par l'équipe Plateforme.

**Explications**

| Variante | Côté coffre | Côté base | Forme du symptôme | La prod |
|---|---|---|---|---|
| 1. `max_ttl` 10 min | baux de 10 min, aucune erreur | comptes expirés puis supprimés à 10 min | **périodique** : 20 min de panne par cycle de 30 | idem si son rôle est touché |
| 2. révocation | plus aucun bail | comptes supprimés d'un coup | **unique**, ≤ 30 min, guérit seule | ≤ 30 min de coupure |
| 3. mot de passe d'`openbao` | `creds` et révocations en erreur (authentification) | comptes expirés qui s'accumulent | **permanente**, après ≤ 1 h | tombe dans l'heure |
| 4. `ingressDeny` | `creds` et révocations en erreur (délai) | idem | **permanente**, après ≤ 1 h | tombe dans l'heure |

La marge du montage E14/E15 vient de trois horloges : bail 1 h, cycle d'ESO 30 min, redémarrage par Reloader ≈ 2 min. Tant que le bail dure au moins deux cycles, un rafraîchissement raté ne coupe rien. ESO ne renouvelle **pas** les baux et ne révoque pas les anciens : il redemande. `VALID UNTIL` n'est contrôlé qu'à l'authentification : une session ouverte survit à l'expiration du mot de passe, pas à `DROP ROLE`.

**Alternatives**
- Raccourcir `refreshInterval` (10 min) : plus de marge, trois fois plus de comptes et de révocations ; ne dispense pas de la règle de durée.
- Application qui relit un fichier monté et reconnecte son pool à l'erreur d'authentification (E15, « Pour aller plus loin ») : plus de redémarrage, mais la panne de délivrance (3, 4) reste.
- Rôle **statique** (`static-roles`) pour l'API : un seul compte, mot de passe tourné par OpenBao ; supprime les révocations, garde la dépendance à la connexion `openbao`.
- Variante 3 : redonner un mot de passe **connu** puis l'écrire à la main dans OpenBao : marche, mais un humain l'a vu ; le tube + `rotate-root` évite qu'il existe hors du coffre.

**Pièges classiques**
- Redémarrer les pods de l'API : ils relisent le même Secret, avec le même compte mort.
- Lancer `rotate-root` pour « réparer » la variante 3 : il échoue (il lui faut une connexion) — la reprise passe par la base.
- Supprimer l'ExternalSecret pour forcer : Argo CD le recrée, et l'on perd l'historique des événements ; `force-sync` suffit.
- « Faire le ménage » des comptes `v-…` par `revoke-prefix` ou `DROP ROLE` : on coupe les comptes en service.
- Recopier `uri` du Secret, ou la réponse complète de `bao read …/creds/…`, dans le journal ou le ticket.
- Se croire tiré d'affaire parce que l'API répond encore en variante 3 ou 4 : elle tombe au `VALID UNTIL` de son compte.
- Toucher à la prod « pour comparer » : `force-sync` et `rotate-root` y ont les mêmes effets.

**En production chez MédiSphère**

`IdentifiantsDynamiquesEnEchec` est **critique** pour la prod (l'astreinte a moins d'une heure) ; `OpenBaoBauxRevoquesEnMasse` exige un numéro d'incident ; le plan planifié de `plateforme/secrets` et la règle de durée sont relus à chaque MR du moteur ; la procédure de reprise de la connexion est répétée une fois par semestre en recette (bascule du primaire puis vérification que le coffre délivre encore).

---

### M25-E39 — Panne : la grappe n'a plus de leader

**Démarche de diagnostic**

*Symptômes* : VIP muette (connexion impossible : keepalived l'a retirée, aucun nœud ne passe son script de suivi), `OpenBaoSansLeader` puis, selon la variante, `OpenBaoScelle` pour les nœuds dont le processus est arrêté (`up == 0`). Consommateurs en échec : CI, ESO, baux de MédiAgenda qui ne se renouvellent plus.

*Hypothèses* : (a) nœuds **scellés** (seal `transit`, `kms01`) ; (b) nœuds **arrêtés** ; (c) nœuds vivants mais qui ne **se parlent** plus sur le 8201 (pare-feu, réseau, certificat de grappe) ; (d) **configuration Raft** amputée (pair retiré : exclu dès que `list-peers` répond de nouveau avec trois pairs) ; (e) un actif élu mais qui ne prend pas le verrou (audit, montage, horloge) ; (f) seulement la **VIP** (keepalived) alors qu'un nœud répond 200.

**Étape 1 — Constater, sans jeton et sans rien changer**

```
admin@adm01:~$ ~/src/secrets/outils/etat-grappe.sh
NŒUD     CODE  SCELLÉ  LEADER (vu par le nœud)
vault01  429   false   - self=false
vault02  000   ?       -
vault03  000   ?       -
openbao  000   ?       -
```

([`outils/etat-grappe.sh`](fichiers/M25-E39/outils/etat-grappe.sh), lecture seule, à ranger dans `plateforme/secrets/outils/`.) Aucun 200 : il n'y a **pas d'actif**. Aucun 503 : ce n'est **pas** le seal ; `kms01` répond 200 : on ne le touche pas. L'hypothèse (f) tombe (aucun nœud à 200, la VIP a raison de ne pas exister).

```
admin@adm01:~$ export BAO_ADDR=https://vault01.par1.medisphere.internal:8200
admin@adm01:~$ bao operator raft list-peers
Node       Address                                  State       Voter
----       -------                                  -----       -----
vault01    vault01.par1.medisphere.internal:8201    follower    true
vault02    vault02.par1.medisphere.internal:8201    follower    true
vault03    vault03.par1.medisphere.internal:8201    follower    true
admin@adm01:~$ bao operator raft autopilot state
Error checking autopilot state: Error making API request.
Code: 500. Errors:
* local node not active but active cluster node not found
admin@adm01:~$ bao kv put -mount=kv wb-essais/inc-5239 essai=1       # même erreur 500
```

Observé sur une grappe d'essai OpenBao 2.7.1 (variante 1). Depuis la 2.5, un nœud en attente **sert lui-même les lectures** depuis sa copie locale de l'état (M25-E44) : `list-peers`, `bao secrets list`, `bao kv get` répondent, mais avec une copie figée au moment de la perte de majorité — ici trois `follower` et **aucun** `leader`, ce qui est déjà le diagnostic. Tout ce qui écrit ou exige l'actif (`autopilot state`, une connexion, qui crée un jeton, une écriture, une révocation) est **transmis** à l'actif, et il n'y en a pas : 500 `local node not active but active cluster node not found`. `sys/leader` lit le verrou d'actif dans la copie locale : sur l'ancien actif, qui a renoncé proprement, `leader_address` est vide (observé) ; sur un nœud **isolé** (variantes 2 et 3), la copie peut encore désigner l'ancien actif, que personne n'a pu effacer. Ne jamais conclure sur ce seul champ.

**Étape 2 — Les nœuds** (SSH `admin`, consultation)

```
admin@vault02:~$ systemctl status openbao --no-pager | head -n 4
admin@vault01:~$ sudo journalctl -u openbao --since "today 00:00" --no-pager | grep -Ei 'raft|quorum|election|candidate|leader|active' | tail -n 30
admin@vault01:~$ sudo nft list ruleset
admin@vault01:~$ sudo ss -tlnp 'sport = :8201'
admin@vault01:~$ for p in vault02 vault03; do timeout 3 bash -c "</dev/tcp/$p.par1.medisphere.internal/8201" && echo "$p ouvert" || echo "$p KO"; done
```

Ce qu'on lit sur l'ancien actif : `failed to contact quorum of nodes, stepping down`, puis des élections en boucle (`entering candidate state`, `failed to make requestVote RPC`) avec, pour chaque pair, la **raison** réseau :
- `connect: connection refused` : la machine répond mais rien n'écoute sur 8201 → **service arrêté** (à confirmer par `systemctl status` : `inactive (dead)`, `Stopped openbao.service` à l'heure de la maintenance, aucune erreur : arrêt volontaire) ;
- `i/o timeout` : rien ne revient → **filtrage** (ou réseau) ; sur le nœud concerné, `nft list ruleset` montre une seconde table, hors du rôle :

```
table inet maintenance {
	chain entree {
		type filter hook input priority -10; policy accept;
		tcp dport 8201 drop
		tcp sport 8201 drop
	}
}
```

Priorité `-10` : elle passe **avant** `filtre_local`, et un `drop` dans n'importe quelle chaîne de base est définitif — l'`accept` de `filtre_local` pour 8200-8201 n'y peut rien. Les deux règles coupent les deux sens : `dport 8201` refuse les connexions reçues, `sport 8201` jette les **réponses** aux connexions que le nœud ouvre lui-même vers le 8201 des autres. Le nœud est seul au monde sur le port de grappe, alors que 8200, SSH et VRRP passent.

**Étape 3 — Raisonner** (dans le journal, avant le premier geste)

Raft n'élit un leader qu'avec la **majorité des électeurs** de la configuration : ⌊3/2⌋ + 1 = 2. Une écriture n'est validée que lorsqu'elle est dans le journal d'une majorité : c'est pour cela qu'**aucune écriture acceptée n'a pu être perdue** — pendant la panne, aucune n'a été acceptée. Un nœud seul, même descellé et parfaitement à jour, ne peut ni être élu, ni rester leader (il renonce dès qu'il ne joint plus la majorité pendant son bail), donc ne peut pas prendre le verrou d'actif d'OpenBao, qui est lui-même stocké dans Raft. Il répond 429 (« en attente »), mais personne ne l'attend.

Ce qu'il faut donc : **deux** électeurs vivants qui se parlent sur 8201. Le geste le plus sûr est celui qui **rend** à la grappe un nœud tel qu'il était, sans toucher aux données ni à la configuration Raft.

**Variante 1 — deux services arrêtés.** Les deux nœuds en attente ont été arrêtés l'un après l'autre (le premier arrêt passe inaperçu : tolérance 0, alerte `OpenBaoToleranceNulle` au bout de 10 min… si l'actif l'a émise avant de tomber à son tour). Correctif, un nœud à la fois :

```
admin@vault02:~$ sudo systemctl start openbao
admin@adm01:~$ ~/src/secrets/outils/etat-grappe.sh      # vault02 429 descellé (seal transit), puis vault01 ou vault02 à 200, VIP 200
admin@vault03:~$ sudo systemctl start openbao
admin@adm01:~$ bao operator raft autopilot state | grep -Ei 'healthy|tolerance'
```

Après le premier `start`, `vault02` se descelle seul par `kms01`, rejoint la configuration Raft qu'il connaît déjà, et l'élection aboutit en quelques secondes : le **service** revient. La **marge** ne revient qu'avec `vault03`. Vérifie `systemctl is-enabled openbao` : un service seulement arrêté redémarre au prochain démarrage de la VM ; un service désactivé, non.

**Variante 2 — 8201 filtré sur deux nœuds.** Tous les processus tournent, tous descellés, aucun service arrêté, et pourtant aucun actif : chaque nœud est isolé (les deux filtrés n'échangent avec personne ; le troisième ne joint qu'eux). Journaux : uniquement des `i/o timeout`. Correctif sur un nœud, puis l'autre :

```
admin@vault02:~$ sudo nft list table inet maintenance        # preuve pour le journal
admin@vault02:~$ sudo nft delete table inet maintenance
```

Puis rejoue le rôle pour être sûr que l'état des nœuds est celui de Git :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml --check --diff
```

`--check` sans différence attendu : la table parasite était **à côté** de `filtre_local`, qu'elle ne modifiait pas, et le rôle ne compare que son fichier `/etc/nftables.conf`. Elle aurait disparu au prochain rechargement de ce fichier (`flush ruleset` en tête) ou au redémarrage du nœud : un filtrage à la main n'a ni trace dans Git ni durée de vie prévisible.

**Variante 3 — un arrêté, un isolé.** Le piège : `systemctl start openbao` sur le nœud arrêté **rend le service** (deux électeurs joignables) et la VIP revient ; beaucoup s'arrêtent là. `autopilot state` dit pourtant `Healthy: false`, `Failure Tolerance: 0`, et le troisième nœud a un dernier contact de plusieurs heures. On cherche alors **pourquoi** il est vivant mais absent : `i/o timeout` dans les journaux, table `inet maintenance`. On la retire ; le nœud rattrape par Raft (journaux ou instantané envoyé par le leader) en quelques secondes ; tolérance 1.

**Clôture commune** : trois nœuds descellés, un actif, deux en attente, VIP sur l'actif ; `list-peers` montre toujours les **trois** électeurs ; écriture et lecture par la VIP :

```
admin@adm01:~$ bao kv put -mount=kv wb-essais/inc-5239 etat=ok && bao kv get -mount=kv -field=etat wb-essais/inc-5239
admin@adm01:~$ kubectl -n wb-essais annotate externalsecret premier-secret force-sync="$(date +%s)" --overwrite
```

Puis un pipeline relancé, `lab/bin/check 25 39`, `lab/bin/break 25 39 --annuler` (idempotent, ne fait rien si tout est réparé), journal ([modèle](fichiers/M25-E39/medisphere/docs/socle/journal/AAAA-MM-JJ-INC-5239.md)).

*Les alertes.* `OpenBaoSansLeader` a sonné au bon moment (`absent(vault_core_active…)` couvre aussi le cas où aucun nœud n'émet). `OpenBaoScelle` a sonné pour les nœuds **arrêtés** (`up == 0`), pas pour les nœuds isolés (vivants, descellés) : en variante 2, seule `OpenBaoSansLeader` parle. `OpenBaoToleranceNulle` reste **muette** pendant la panne : `vault_autopilot_*` n'est émis que par l'actif, et il n'y en a plus ; elle aurait pu sonner **avant**, entre les deux gestes de Lucas, si l'écart avait duré plus de ses 10 minutes de `for`.

**Étape 4 — Pourquoi ne pas « réparer plus fort »**

- `bao operator raft remove-peer vault02` : sans actif, la commande échoue (elle est transmise) ; avec un actif retrouvé, elle retire un électeur sain qui ne pourra plus voter à son retour — la grappe passe à deux électeurs, quorum de **deux sur deux**, plus aucune tolérance. Autopilot ne l'aurait jamais fait (`min_quorum = 3`) : c'est voulu.
- `bao operator init`, effacer `/var/lib/openbao` d'un nœud « pour qu'il rejoigne propre » : on détruit une copie saine des données pour un problème qui n'en a perdu aucune ; effacer **deux** nœuds sans quorum perd tout ce que le troisième n'avait pas.
- Restaurer un instantané : retour arrière jusqu'à une heure d'écritures (baux, rotations, émissions PKI), pour une panne qui se réparait par un `start`.
- Redémarrer le survivant ou `kms01` : le premier ne trouvera pas plus de majorité ; le second reviendrait **scellé** (trois dépositaires), et plus aucun nœud ne pourrait se desceller.

**Étape 5 — Le dernier recours : `peers.json`** (question 6)

Légitime seulement si la majorité est **définitivement** perdue (ici : `vault02` et `vault03` détruits sans sauvegarde utilisable). Différence avec aujourd'hui : aujourd'hui, les pairs absents pouvaient **revenir** ; un `peers.json` écrit alors qu'ils peuvent revenir crée deux grappes qui divergent.

1. Arrêter openbao sur tous les nœuds restants (ici `vault01`).
2. Sur chacun d'eux, `/var/lib/openbao/raft/peers.json` (propriétaire `openbao`, 0600), **identique** partout, ne listant que les survivants ; `id` = identifiant Raft du nœud (`node_id` de la configuration, ou fichier `node-id` du dossier de données), `address` = nom et **port de grappe** :
   ```json
   [
     { "id": "vault01", "address": "vault01.par1.medisphere.internal:8201", "non_voter": false }
   ]
   ```
3. Démarrer : à l'ouverture du stockage Raft, OpenBao lit le fichier, remplace la configuration de grappe (`raft recovery initiated`, `raft recovery found new config`), **supprime** le fichier (`raft recovery deleted peers.json`), se descelle par `kms01`, s'élit seul et prend le verrou d'actif.
4. `list-peers` (un pair), lecture d'un secret ; puis reconstruire `vault02` et `vault03` **vides** (OpenTofu, rôle `openbao`) : `retry_join` les fait rejoindre, ils rattrapent par Raft ; autopilot les rend électeurs après 10 s de stabilité.
5. Risques, dans le post-mortem : les écritures que `vault01` n'avait pas reçues sont perdues ; la récupération **valide d'office** les entrées de son journal Raft qui ne l'étaient pas (une écriture qui avait échoué côté client peut réapparaître). Décision avec Karim, instantané vérifié d'abord, jamais automatisé, jamais seul la nuit.

**Prévention**
- [Fiche « maintenance de la grappe »](fichiers/M25-E39/medisphere/docs/securite/secrets/maintenance-grappe.md) : `autopilot state` sain et tolérance ≥ 1 **avant chaque** geste sur un nœud, un nœud à la fois, en attente d'abord, l'actif après `step-down` ; gestes interdits ; `peers.json` en dernier recours. Elle sera reprise dans RB-255 § 4 (M25-E43).
- Aucun filtrage à la main sur un nœud du coffre : tout passe par `pare_feu_local` (Git, MR, matrice des flux).
- Lire `OpenBaoToleranceNulle` comme un **arrêt de maintenance** ; la planifier dans la fenêtre de maintenance avec le canal de l'astreinte.

**Explications**

OpenBao confie à Raft deux choses : les **données** (chiffrées par la barrière) et le **verrou d'actif** (clé `core/lock`). Raft élit un leader à la majorité des électeurs et ne valide une écriture qu'une fois répliquée sur une majorité ; un leader qui ne joint plus la majorité pendant la durée de son bail (`LeaderLeaseTimeout`, multiplié par `performance_multiplier`) **renonce** de lui-même, précisément pour qu'une partition ne laisse pas deux leaders écrire chacun de son côté. Le nœud actif d'OpenBao perd alors son verrou, repasse en attente, et la grappe ne sert plus rien d'utile : depuis la 2.5, un nœud en attente sert certaines lectures depuis sa copie locale (cohérence à terme, M25-E44), mais les connexions, les écritures, les baux et l'administration exigent l'actif, et keepalived a retiré la VIP que visent tous les clients. C'est le prix de la cohérence : le coffre préfère se taire que répondre une valeur périmée ou accepter une écriture qui pourrait disparaître. Les données, elles, sont intactes sur chaque nœud : dès que deux électeurs se reparlent, l'élection reprend, le nouveau leader confirme son journal, le nœud actif reprend le verrou et reconstruit son état (montages, baux).

**Alternatives**
- Diagnostiquer par la métrique (`vault_raft_*`, `up`, `vault_core_active` dans Grafana) plutôt que par les nœuds : utile pour la chronologie, mais muet sur la **cause** (un processus arrêté et un nœud isolé se ressemblent dans les métriques de grappe).
- Cinq électeurs : tolérance de deux pannes, mais sur un seul hyperviseur, le domaine de panne reste `pve01` (M25-E24, corrigé) ; plus de mémoire, écritures un peu plus lentes.
- Un nœud non électeur supplémentaire : copie des données, aucune voix ; il ne sauve pas le quorum.

**Pièges classiques**
- Croire `sys/leader` d'un nœud en attente et chercher la panne sur l'« actif » qu'il désigne.
- Redémarrer le survivant (ou les trois) en série : rien ne change, et chaque redémarrage dépend de `kms01`.
- Rendre le service et oublier la marge (variante 3) : la grappe reste à tolérance 0 jusqu'au prochain geste de maintenance.
- `remove-peer` « pour que les deux qui restent fassent une majorité » : fausse bonne idée (étape 4).
- Retirer la table parasite sur un nœud et oublier de chercher la même chose sur les deux autres.
- Écrire `peers.json` alors que les pairs absents sont seulement arrêtés : deux grappes divergentes à leur retour.

**En production chez MédiSphère**

Maintenance des nœuds du coffre dans une fenêtre annoncée, un nœud à la fois, avec la vérification d'autopilot avant chaque geste et la fiche ouverte ; aucun `nft` à la main sur un nœud du coffre ; `OpenBaoToleranceNulle` routée à l'astreinte comme un « ne touche plus à rien » ; la procédure `peers.json` répétée **sur une grappe jetable** (comme la restauration de RB-252), jamais découverte un jour de panne.

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

**Ce que la relecture de la politique doit aussi vérifier.** Le bloc `auth/token/renew-self` (M25-E25) : le jeton, créé sans la politique `default`, ne peut pas se renouveler sans lui. Le serveur essaie et abandonne **sans bruit** ; le jeton périodique meurt 7 jours après son dernier renouvellement (sur le banc : `last_renewal_time` vide sans ce bloc, renseigné avec). Une politique réécrite à la main d'après une ancienne copie peut l'avoir perdu : la panne se déclarerait une semaine plus tard, au premier redémarrage. D'où la comparaison au fichier consigné, et l'essai quotidien ci-dessous, qui renouvelle le jeton et en publie la durée restante.

**Clôture** : les trois nœuds descellés, tolérance 1, `kms01` intact, jeton racine de `kms01` révoqué ; `lab/bin/check 25 42` ; `lab/bin/break 25 42 --annuler` ; journal `INC-5242`.

**Prévention**
- **Essai quotidien** sur chaque nœud : [`openbao-essai-kms`](fichiers/M25-E42/ansible/roles/openbao/files/openbao-essai-kms) (renouvelle le jeton, chiffre puis déchiffre une valeur **témoin** avec le jeton du seal, depuis le nœud), [unité](fichiers/M25-E42/ansible/roles/openbao/templates/openbao-essai-kms.service.j2) et [minuterie](fichiers/M25-E42/ansible/roles/openbao/templates/openbao-essai-kms.timer.j2) du rôle `openbao` ([tâches](fichiers/M25-E42/ansible/roles/openbao/tasks/essai-kms.yml), [variables](fichiers/M25-E42/ansible/roles/openbao/defaults/main.yml.extrait)), métriques pour node_exporter, alertes [`regles/autodescellement.yaml`](fichiers/M25-E42/observabilite/regles/autodescellement.yaml) ([tests](fichiers/M25-E42/observabilite/tests/autodescellement.test.yaml)). Il voit les variantes 1, 2 et 4 **avant** le redémarrage ; la 3 (un texte chiffré à l'instant l'est par la dernière version) se contrôle sur `kms01`, en cérémonie.
- RB-251 complété ([extrait](fichiers/M25-E42/medisphere/docs/securite/secrets/runbooks/RB-251-descellement-et-redemarrage.md.extrait)) ; politique de `kms01` rétablie et comparée à [`kms01/kms-autodescellement.hcl`](fichiers/M25-E42/kms01/kms-autodescellement.hcl).

**Explications**

Avec un seal `transit`, la clé racine est rangée dans Raft **chiffrée par `kms01`** (`core/hsm/barrier-unseal-keys`, M25-E44). Au démarrage, le serveur configure le seal (un chiffrement d'essai : réseau, TLS, jeton, droit `encrypt`) — un échec arrête le processus ; puis il descelle en demandant à `kms01` de **déchiffrer** la clé racine — un échec laisse le processus scellé, qui réessaie. Un nœud déjà descellé n'a plus besoin de `kms01` : c'est pourquoi ces pannes dorment jusqu'au prochain redémarrage, et pourquoi on ne les découvre qu'au pire moment sans un essai régulier.

**Alternatives** : plusieurs seals actifs (*Seal HA*) : fonction de Vault Enterprise, refusée par OpenBao 2.7.1 (« two seals provided but neither is disabled ») ; seal PKCS#11 avec un HSM (ADR-0250) ; garder une procédure de migration inverse vers Shamir (RB-251) comme dernier recours.

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

**2. Le coffre d'abord**, car tout en dépend et car une erreur y coûte le plus : rendre au moins un nœud de marge (E35 : écoute, limites ou certificat du nœud ; E39 : nœuds arrêtés, 8201 filtré, ou un arrêté et un isolé ; E42 : seal). Un nœud à la fois, `autopilot state` sain avant de passer au suivant.

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
