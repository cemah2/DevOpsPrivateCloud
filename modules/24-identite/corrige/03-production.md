# Module 24 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice : `infra/` reproduit `plateforme/infra`, `ansible/` reproduit `plateforme/ansible`, `identite/` reproduit `plateforme/identite`, `observabilite/` reproduit `plateforme/observabilite`, `gitops/` reproduit `plateforme/gitops`, `k8s/` reproduit `plateforme/k8s`, `medisphere/` la documentation. Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie ; un fichier `.extrait` se fusionne dans le fichier existant du même nom. Le rôle `keycloak` complet est celui de [`M24-E04`](fichiers/M24-E04/ansible/roles/keycloak/), dont [`M24-E24`](fichiers/M24-E24/ansible/roles/keycloak/) remplace six fichiers (`defaults/main.yml`, `handlers/main.yml`, `tasks/main.yml`, `tasks/postgresql.yml`, `tasks/controles.yml`, `templates/keycloak.conf.j2`, `templates/keycloak.service.j2`) ; `distribution.yml` et `service.yml` sont inchangés.

**Ce qui a été vérifié à la rédaction** :
- **Keycloak 26.7.5 et 26.8.1 réels** (archives de Maven Central ; empreinte de la 26.8.1 `4e2740b1…cbe8` comparée au fichier `.sha256` publié), sous OpenJDK 21, contre PostgreSQL 16 : `start --help-all` des deux versions (options de cache, `cache-embedded-cluster-name` et `cache-embedded-node-name` **nouvelles en 26.8**, `event-metrics-user-*`, `features-disabled`) ; `event-metrics-user-enabled` est une option de construction, la fonction `user-event-metrics` est active par défaut ; compteur `keycloak_user_events_total{realm, event, error}` (erreur vide pour un succès) ; options `spi-events-listener--jboss-logging--success-level`/`--error-level` acceptées, événements du royaume `master` journalisés (logger `org.keycloak.events`, `type="LOGIN", realmName="master", …, username="…"`), événements d'administration (`operationType=…`) ; **sessions persistées** : une session survit à l'arrêt complet de Keycloak (jeton de rafraîchissement accepté après redémarrage) ; démarrage optimisé jusqu'au premier jeton : ≈ 17 s sur le poste de test ; table de découverte `jgroups_ping` présente dans le schéma ;
- l'API d'administration : rotation des clés (fournisseur `rsa-generated` de priorité supérieure → nouvelle clé `ACTIVE`, ancienne `PASSIVE` toujours publiée dans le JWKS, puis `DISABLED` et retirée du JWKS) ; rotation des jetons de rafraîchissement (`revokeRefreshToken`, réutilisation 0 : seconde présentation refusée, `Maximum allowed refresh token reuse exceeded`) ; détection de force brute (verrouillage temporaire, réponse `Invalid user credentials` même avec le bon mot de passe, événement `USER_DISABLED_BY_TEMPORARY_LOCKOUT`, contrôle « connexion rapide » qui verrouille dès deux échecs à moins d'une seconde d'intervalle) ; droits de `wb-checks` (`view-realm`, `view-users`, `view-clients`) : lecture du royaume, des clés et des composants **oui**, `events/config` et `partial-export` **non** (403) ; en 26.7.5 `CLIENT_SECRET_ROTATION` et `SCIM_API` sont des fonctions en préversion **désactivées**, actives par défaut en 26.8.1 ; `kc.sh export` complet contient les secrets des clients **en clair** ;
- **la migration 26.7.5 → 26.8.1** sur une copie de la base (`pg_dump`/`pg_restore`) : `Updating database`, `migrated realm medisphere to 26.8.0`, 26 changements Liquibase `jpa-changelog-26.8.0.xml`, santé `UP` ;
- **OpenTofu 1.13.2 et `keycloak/keycloak` 5.10** contre ce Keycloak : `royaume.tf` durci (E27), `evenements.tf` (E26), `cles.tf` (E29), un client avec `client_secret_wo` : apply puis **plan vide** ; le fournisseur n'accepte que 1024, 2048 ou 4096 bits pour `key_size` ; rotation par `client_secret_wo_version` : une seule modification au plan, nouveau secret en place, **aucun secret dans l'état** ;
- le script `identite-sauvegarde` (mode keycloak) de bout en bout contre PostgreSQL, age et un S3 local (moto) : archive contrôlée, chiffrée, envoyée, taille relue, trace du dernier succès, aucune copie claire restante, archive relue et déchiffrée (`pg_restore --list` : 100 tables) ;
- les règles Prometheus d'E26 (`promtool check rules` et `promtool test rules`, Prometheus 3.7) ; la configuration d'Alloy d'E26 rendue depuis le gabarit et **validée** par `alloy validate` (Alloy 1.21.1) ; le chart `oauth2-proxy` 10.7.1 rendu avec les valeurs d'E34 (`helm template` : arguments, `upstreams`, HTTPRoute vers le Service de l'instance) ; l'outil de revue d'E30 sur des données fictives (écarts attendus détectés), `ruff` propre ;
- tous les scripts : `shellcheck -x` et `bash -n` ; les YAML analysés.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- la **grappe** à deux nœuds (E24) n'a pas été formée à la rédaction (une seule machine) : options de cache relues dans `--help-all`, ports 7800/57800 et table `jgroups_ping` d'après la documentation et le schéma ; le message `ISPN000094` de vue de grappe est celui d'Infinispan ; la connexion JDBC en `sslmode=require` vers le PostgreSQL de Debian (certificat *snakeoil*) ; les durées de bascule données sont des ordres de grandeur ;
- **Rocky 10** pour `ipa01` : `age` et `rclone` dans EPEL 10, droits des journaux de 389-ds et du KDC, comportement d'Alloy sous SELinux (`unconfined_service_t` attendu), nom exact de l'instance de 389-ds (`slapd-PAR1-MEDISPHERE-INTERNAL`), `ipa-backup --data --online --quiet` et le nom des dossiers `ipa-data-*` ;
- les **filtres LogQL** du ruler (E26, E28) n'ont pas été évalués par un Loki : `FederationLdapEnEchec` dépend de ce que Keycloak écrit réellement quand la fédération échoue (l'étape 6 d'E26 te fait le constater) ; le format de la ligne du KDC (`AS_REQ … ISSUE: … admin@… for krbtgt/…`) et la ligne `RESULT … tag=97 … dn="…"` de 389-ds sont ceux des versions récentes ;
- `proxmox-backup-client namespace list` (forme de la sortie) dans `pbs-identite.sh`, et la vérification des droits par `proxmox-backup-manager user permissions` ;
- `ldappasswd` par le socket LDAPI de FreeIPA (RB-244 §4) ;
- les API de GitLab, Grafana et Proxmox appelées par l'outil de revue (E30) : champs `identities`, `authLabels`, `personal_access_tokens` lus d'après les documentations des versions de référence ;
- les noms exacts des fichiers et objets du palier 2 (instances d'OAuth2 Proxy d'E18, client `grafana` d'E12, Secret `grafana-oidc`) : adapte les extraits si ton palier 2 les a nommés autrement.

---

### M24-E24 — Keycloak en haute disponibilité : essai à deux nœuds

**Solution**

*A. Lire.* Notes attendues : **en cache local** sur chaque nœud, ce qui se relit en base (royaumes, clients, utilisateurs, clés : caches `realms`, `users`, `keys`, invalidés par la grappe quand un nœud modifie quelque chose) ; **distribués** entre les nœuds, les sessions d'authentification en cours (`authenticationSessions`), les compteurs de force brute (`loginFailures`, en base à partir de la 26.8), les jetons à usage unique (`actionTokens`, codes) ; **en base** : tout le modèle, plus, depuis la 26.0, les **sessions des utilisateurs** (fonction `persistent-user-sessions` active par défaut ; les caches `sessions` ne gardent qu'une partie en mémoire). `jdbc-ping` : chaque nœud écrit son adresse dans la table `jgroups_ping` de la base partagée et y lit celles des autres, puis ils se parlent en TCP (7800 ; 57800 pour la détection de pannes `FD_SOCK2`, décalage de 50000), chiffré par défaut (mTLS à certificats éphémères, `cache-embedded-mtls-enabled=true`). Un nœud qui s'arrête : les autres continuent, les sessions sont en base. **Tous** arrêtés : les sessions survivent (base), seules les authentifications **en cours** (formulaire ouvert, code non échangé) sont perdues. La ressource partagée est la **base** : la disponibilité de l'ensemble ne dépasse jamais celle de PostgreSQL d'`idp01`.

*B. Le second nœud.* Rôle : [`defaults/main.yml`](fichiers/M24-E24/ansible/roles/keycloak/defaults/main.yml) (`keycloak_bdd_hote`, `keycloak_bdd_url_proprietes`, `keycloak_bdd_clients_distants`, `keycloak_bdd_ecoute`, `keycloak_grappe_adresse`), [`tasks/main.yml`](fichiers/M24-E24/ansible/roles/keycloak/tasks/main.yml) (garde-fous : une base ouverte seulement par le nœud qui la porte, jamais deux nœuds sans grappe ; PostgreSQL installé seulement si la base est locale), [`tasks/postgresql.yml`](fichiers/M24-E24/ansible/roles/keycloak/tasks/postgresql.yml) (fichier `conf.d/90-keycloak-grappe.conf` pour `listen_addresses`, bloc `hostssl … /32 scram-sha-256` **en tête** de `pg_hba.conf` ; liste vide → tout est retiré : c'est le retour arrière), [`tasks/controles.yml`](fichiers/M24-E24/ansible/roles/keycloak/tasks/controles.yml), [`keycloak.conf.j2`](fichiers/M24-E24/ansible/roles/keycloak/templates/keycloak.conf.j2) (`db-url-properties`, `cache=ispn`, `cache-stack=jdbc-ping`, `cache-embedded-network-bind-address`), [`keycloak.service.j2`](fichiers/M24-E24/ansible/roles/keycloak/templates/keycloak.service.j2) (`Requires=postgresql.service` seulement pour une base locale). Options de construction parmi les nouvelles : `cache`, `cache-stack` (le rôle reconstruit de toute façon quand `keycloak.conf` change).

VM : [`envs/m24/`](fichiers/M24-E24/infra/envs/m24/) (catalogue `idp02`/`idp-resto`, validation « une seule VM à la fois »). Hôtes : [`host_vars/idp01/keycloak.yml.essai-E24`](fichiers/M24-E24/ansible/inventories/lab/host_vars/idp01/keycloak.yml.essai-E24), [`pare_feu_local.yml.extrait-E24`](fichiers/M24-E24/ansible/inventories/lab/host_vars/idp01/pare_feu_local.yml.extrait-E24), [`host_vars/idp02/`](fichiers/M24-E24/ansible/inventories/lab/host_vars/idp02/) (le mot de passe de la base est lu dans les variables d'`idp01` par `hostvars`, pas recopié), [inventaire](fichiers/M24-E24/ansible/inventories/lab/inventaire-role_idp.extrait), [bordure](fichiers/M24-E24/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait-E24) (`lb01`/`lb02` → `idp02` 8443, 9000).

```
admin@idp01:~$ sudo install -d -m 700 /var/backups/m24-e24 && sudo -u postgres pg_dump -Fc keycloak \
>   | sudo tee /var/backups/m24-e24/keycloak-avant-grappe.dump >/dev/null && sudo chmod 600 /var/backups/m24-e24/*.dump
admin@adm01:~/src/infra$ tofu -chdir=envs/m24 plan -out=plan && tofu -chdir=envs/m24 apply plan     # groupes = ["idp02"]
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --limit idp02
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/identite.yml --limit idp01   # cache=ispn, base ouverte
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/identite.yml --limit idp02
admin@idp01:~$ sudo journalctl -u keycloak --since -10min | grep -o 'ISPN000094[^"]*'
ISPN000094: Received new cluster view for channel ISPN: [idp01-12345|1] (2) [idp01-12345, idp02-67890]
admin@idp01:~$ sudo -u postgres psql -d keycloak -XtAc 'SELECT count(*) FROM jgroups_ping'
2
```

Une ligne par membre ; un nœud arrêté proprement retire la sienne ; un nœud tué la laisse, et elle est nettoyée par les autres (détection de panne) ou au redémarrage.

*C. Répartition et bascule.* [`haproxy.yml.extrait-E24`](fichiers/M24-E24/ansible/inventories/lab/group_vars/role_lb/haproxy.yml.extrait-E24) (deux serveurs, `balance roundrobin`, contrôle de santé resserré pour l'essai) ; mesure par [`outils/mesure-disponibilite.sh`](fichiers/M24-E24/identite/outils/mesure-disponibilite.sh) (découverte et jeton chaque seconde, bilan des séries d'échecs).

```
admin@adm01:~/src/identite$ outils/mesure-disponibilite.sh 300 ~/m24/e24/bascule-idp01.log
…
07:42:10  200        ok     38     OK
07:42:11  000        injoignable  3004   ÉCHEC
07:42:14  200        ok     41     OK
…
# bilan : 297 essais, 2 échecs (0 %), plus longue série d échecs : 1 s (début 07:42:11)
```

Ordres de grandeur attendus (à remplacer par tes mesures) : arrêt propre d'un nœud en grappe : 0 à 4 s d'échecs (requêtes en vol sur le nœud qui s'arrête, puis HAProxy le retire après `fall 2` × `inter 2s`) ; Lucas reste connecté. Redémarrage à froid d'un nœud seul : 20 à 40 s d'échecs sur une VM de 2 vCPU (≈ 17 s sur le poste de test) ; Lucas reste connecté (session persistée). Pendant l'arrêt de PostgreSQL : les deux nœuds échouent (`/health/ready` passe `DOWN`, HAProxy retire les deux).

*D. Décision et retour.* [`ADR-0241`](fichiers/M24-E24/medisphere/docs/securite/identite/adr/ADR-0241-haute-disponibilite-keycloak.md) : un nœud, parce que la grappe sur un seul hyperviseur, avec la base sur `idp01`, ne protège que contre la panne la plus courte. Retour, **dans cet ordre** (l'inverse de la construction) :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/repartiteurs.yml --limit lb02   # be_sso sans idp02
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/repartiteurs.yml --limit lb01
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/identite.yml --limit idp01      # grappe false, liste vide
admin@adm01:~/src/infra$ tofu -chdir=envs/m24 apply                                         # groupes = []
admin@idp01:~$ sudo ss -Hltn 'sport = :5432'; sudo grep -c 'nœuds distants' /etc/postgresql/17/main/pg_hba.conf
admin@idp01:~$ sudo -u postgres psql -d keycloak -XtAc 'SELECT count(*) FROM jgroups_ping'
```

Avec `cache=local`, Keycloak n'utilise plus la table de découverte ; une ligne laissée par `idp02` (arrêt brutal) est inoffensive mais se supprime à la main (`DELETE FROM jgroups_ping WHERE …`) si elle gêne une future grappe.

**Explications**

- **Pourquoi la base est le vrai point unique.** Une grappe Keycloak partage tout son état durable par la base ; Infinispan n'est qu'un cache et un bus d'invalidation. Deux nœuds sur une base unique protègent contre la panne d'un **processus** ou d'une **VM** Keycloak, pas contre celle de la base ni de l'hyperviseur.
- **Sessions persistées (26.0+).** Avant, les sessions vivaient seulement en mémoire (avec `owners=2`) : perdre tous les nœuds déconnectait tout le monde, d'où l'intérêt de la grappe. Aujourd'hui, un redémarrage à froid est **sans conséquence pour les personnes connectées** : il ne coûte que les secondes de démarrage.
- **TLS vers PostgreSQL.** `sslmode=require` chiffre mais ne vérifie pas l'identité du serveur : un attaquant du VLAN 20 pourrait se faire passer pour `idp01`. En production, certificat ACME pour PostgreSQL et `sslmode=verify-full&sslrootcert=<racine>`.
- **Affinité.** Keycloak 26 n'exige plus d'affinité de session au répartiteur (sessions distribuées et persistées) ; il ajoute toutefois une route au cookie `AUTH_SESSION_ID` (`spi-sticky-session-encoder-…-should-attach-route`, déprécié en 26.8 : avertissement au démarrage) qu'un répartiteur peut utiliser.

**Alternatives**

- *Cache distant* (Infinispan externe, `cache-remote-*`) : pour le multi-site ; hors de portée du lab.
- *Deux nœuds sur deux hyperviseurs + PostgreSQL répliqué* (Patroni, ou une base CloudNativePG **hors** du cluster qu'il authentifie) : la vraie haute disponibilité, l'option C de l'ADR.
- *Keycloak dans Kubernetes* (opérateur, `jdbc-ping` aussi) : écarté (ADR-0240, dépendance circulaire).
- *Basculement à froid* : un `idp02` éteint, prêt, démarré à la main sur la même base : peu de mémoire, mais un RTO humain ; la restauration d'E25 fait presque aussi bien.

**Pièges classiques**

- Démarrer `idp02` avec `cache=local` sur la même base qu'`idp01` : deux caches qui ne s'invalident pas ; une modification faite sur un nœud n'est pas vue par l'autre (le garde-fou du rôle le refuse).
- Oublier 57800 : la grappe se forme (7800), mais une panne de nœud est détectée tard (délais de suspicion), avec des erreurs pendant ce temps.
- Ouvrir `listen_addresses = '*'` et `host all all 0.0.0.0/0` « pour essayer » : la base des secrets de toute l'identité ouverte au VLAN.
- Deux versions différentes dans une grappe (la montée d'E33 sur un seul nœud) : refusé par défaut ; il faut `kc.sh update-compatibility` pour savoir si c'est permis.
- Mesurer avec un navigateur : on ne voit ni la durée ni les échecs isolés ; une boucle horodatée donne des chiffres.
- Retirer `idp02` de la grappe **avant** de le retirer de HAProxy : des requêtes partent encore vers un nœud arrêté jusqu'à ce que le contrôle de santé le retire.

**En production chez MédiSphère**

L'option C le jour où un second hyperviseur existe (F5) : deux nœuds Keycloak sur deux hôtes, PostgreSQL répliqué avec bascule automatique, TLS vérifié jusqu'à la base, montées de version progressives (`update-compatibility`), SLO de l'authentification (ratio de jetons délivrés sans erreur) dans Pyrra. En attendant : la supervision d'E26, la restauration chronométrée d'E25 et les comptes de secours d'E28.

---

### M24-E25 — Sauvegarder et restaurer l'identité

**Solution**

*A. Ce qu'on sauvegarde.* Inventaire attendu :

| Élément | Où | Reconstructible depuis |
|---|---|---|
| Configuration du royaume `medisphere` (clients, portées, flux, fédération) | base (`realm`, `client`, `component`…) | **Git** (OpenTofu), sauf les secrets générés par Keycloak |
| Clés de signature privées du royaume | `component_config` des fournisseurs `rsa-generated`, `hmac-generated`, `aes-generated` | **sauvegarde seulement** (recréées = tous les jetons en cours refusés) |
| Secrets des clients | `client.secret` | Vault `critique` si imposés (E29), sinon **sauvegarde** |
| OTP, WebAuthn des personnes | `credential` (liés à l'utilisateur importé) | **sauvegarde seulement** (sinon réinscription de chaque administrateur) |
| Personnes et groupes fédérés | copie dans `user_entity`, `user_group_membership`… | l'**annuaire** (resynchronisation) |
| Royaume `master`, `<MOI>-admin`, `kc-secours` (empreintes), `svc-tofu-keycloak` | base | **sauvegarde** (ou réamorçage à la main) |
| Sessions | `offline_user_session`, `offline_client_session` | rien (perte = reconnexion) |
| Annuaire : personnes, groupes, HBAC, sudo | 389-ds | Git (`annuaire/`), **sauf les mots de passe** des personnes et l'historique |
| Kerberos (clés des principaux d'hôtes et de services, *keytabs*) | 389-ds | **sauvegarde** (sinon réinscription de toutes les VMs) |
| CA Dogtag et sa clé | `/var/lib/pki`, NSS | **sauvegarde complète** (sinon nouvelle cérémonie et réémission de tout) |

Reconstruire Keycloak depuis le code au lieu de restaurer : nouvelles clés (tous les services rejettent les jetons en cours, kubelogin doit se reconnecter), secrets générés différents (tous les services à reconfigurer), plus aucun OTP, `master` à réamorcer.

*Exports.* `kc.sh export` produit un JSON complet (secrets des clients **en clair**, empreintes de mots de passe des comptes locaux) ; il démarre une instance de Keycloak (même base, même port de gestion : refusé ou concurrent sur `idp01` en marche ; la documentation demande d'arrêter le service) ; et il ne sauvegarde pas tout (pas les sessions). `pg_dump` est un instantané transactionnel, en ligne, complet. L'export **partiel** de l'API masque les secrets (`**********`) mais exige `manage-realm` (testé : 403 avec `view-realm`) : on ne donne pas ce droit à une minuterie ; la configuration est dans Git de toute façon.

*B. Chaîne de sauvegarde.* Stockage : [`seaweedfs.yml.extrait`](fichiers/M24-E25/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait), [secrets S3](fichiers/M24-E25/ansible/inventories/lab/group_vars/all/vault-critique-s3.yml.extrait), [politique](fichiers/M24-E25/infra/outils/s3/politique-identite-sauvegardes.json), [cycle de vie](fichiers/M24-E25/infra/outils/s3/cycle-de-vie-identite-sauvegardes.json).

```
admin@adm01:~/src/infra$ ( set -a; . ~/.config/workbook/s3-admin.env; set +a
>   aws s3api put-bucket-policy --bucket identite-sauvegardes --policy file://outils/s3/politique-identite-sauvegardes.json
>   aws s3api put-bucket-lifecycle-configuration --bucket identite-sauvegardes --lifecycle-configuration file://outils/s3/cycle-de-vie-identite-sauvegardes.json )
admin@adm01:~/src/ansible$ ( umask 077; k="$(age-keygen 2>/dev/null | grep '^AGE-SECRET-KEY-')"
>   printf 'identite_age_cle_privee: "%s"\nidentite_age_cle_publique: "%s"\n' "$k" "$(age-keygen -y <(printf '%s\n' "$k"))" \
>   | uv run ansible-vault encrypt --encrypt-vault-id critique --output secrets/identite-sauvegardes.yml - )
admin@adm01:~/src/ansible$ uv run ansible-vault view secrets/identite-sauvegardes.yml | sed -n 's/^identite_age_cle_publique: *//p'
"age1…"
```

La clé privée ne passe que par une variable du sous-shell et l'entrée standard d'`ansible-vault` ; modèle du fichier : [`identite-sauvegardes.yml.exemple`](fichiers/M24-E25/ansible/secrets/identite-sauvegardes.yml.exemple). Imprime-la (`ansible-vault view`, imprimante locale, pas de fichier) pour le coffre ; la clé **publique** va dans [`group_vars/sauvegarde_identite/`](fichiers/M24-E25/ansible/inventories/lab/group_vars/sauvegarde_identite/sauvegarde_identite.yml).

Rôle [`sauvegarde_identite`](fichiers/M24-E25/ansible/roles/sauvegarde_identite/) : script [`identite-sauvegarde.sh`](fichiers/M24-E25/ansible/roles/sauvegarde_identite/files/identite-sauvegarde.sh) (mode `keycloak` : `pg_dump -Fc` en `postgres` par le socket, contrôle des tables qui portent les secrets ; mode `freeipa` : `ipa-backup --data --online`, contrôle du fichier `header`), [tâches](fichiers/M24-E25/ansible/roles/sauvegarde_identite/tasks/main.yml), gabarits de configuration, d'unité (`OnFailure=ms-alerte@%n.service`) et de minuterie ; variables par hôte ([`idp01`](fichiers/M24-E25/ansible/inventories/lab/host_vars/idp01/sauvegarde_identite.yml), [`ipa01`](fichiers/M24-E25/ansible/inventories/lab/host_vars/ipa01/sauvegarde_identite.yml)) ; groupe d'inventaire [`sauvegarde_identite`](fichiers/M24-E25/ansible/inventories/lab/hosts.yml.extrait-E25) ; le rôle s'ajoute aux playbooks `identite.yml` et `annuaire-serveur.yml` (dernier rôle de la liste).

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/identite.yml --limit idp01 --tags sauvegarde_identite
admin@idp01:~$ sudo systemctl start identite-sauvegarde.service && sudo journalctl -u identite-sauvegarde -n 5 -o cat
identite-sauvegarde: archive prête : keycloak-idp01-20261104T071502Z.dump (1843210 octets)
identite-sauvegarde: envoyé : s3://identite-sauvegardes/idp01/keycloak-idp01-20261104T071502Z.dump.age (1843506 octets)
identite-sauvegarde: terminé en 3 s
admin@idp01:~$ sudo ls -A /var/backups/identite        # vide : le dossier de travail est effacé par le trap
```

PBS : [`pbs-identite.sh`](fichiers/M24-E25/pbs01/pbs-identite.sh) sur `pbs01`, puis sur `pve01` :

```
root@pve01:~# pvesm add pbs pbs-par2-identite --server 10.20.10.10 --datastore ds-lab --namespace par1/identite \
>   --username 'wb-backup@pbs!pve01' --fingerprint "$(pvesm config pbs-par2 | awk '/fingerprint/ {print $2}')" \
>   --password "$(cat /etc/pve/priv/storage/pbs-par2.pw)" --content backup
root@pve01:~# pvesh create /cluster/backup --id identite-nuit --schedule '01:45' --storage pbs-par2-identite \
>   --vmid 1030,1031 --mode snapshot --enabled 1 --notes-template '{{guestname}} (identité)'
root@pve01:~# pvesh set /cluster/backup/lab-nuit --exclude 1030,1031
root@pve01:~# vzdump 1030 1031 --storage pbs-par2-identite --mode snapshot
```

(`--password "$(cat …)"` reste sur la ligne de commande de `pve01` le temps de la commande : en root, sur l'hyperviseur, sans autre utilisateur, c'est acceptable ; la clé de chiffrement éventuelle du stockage `pbs-par2` se réutilise par `--encryption-key`. Si `lab-nuit` sélectionne le pool entier, `--exclude` retire les deux VMs ; sinon, retire-les de sa liste.)

*C. Restauration d'essai.* Inventaire [`essai-resto`](fichiers/M24-E25/ansible/inventories/essai-resto/) et playbook [`identite-essai-resto.yml`](fichiers/M24-E25/ansible/playbooks/identite-essai-resto.yml) (isolation nftables **avant** tout secret : entrées depuis `adm01` seulement, sorties vers tout le lab refusées sauf DNS ; preuve qu'`ipa01` est injoignable ; base vide ; certificat auto-signé couvrant `sso…` ; même rôle `keycloak`). L'isolation est indispensable : la base contient les clés de signature et les secrets des clients ; une copie joignable pourrait **émettre des jetons valables pour la production**, et sa fédération irait se lier à `ipa01` avec le compte `svc-keycloak`.

```
admin@adm01:~/src/infra$ tofu -chdir=envs/m24 apply      # groupes = ["resto"]
admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/essai-resto playbooks/identite-essai-resto.yml --tags isolation,base
admin@adm01:~/src/ansible$ cle() { uv run ansible-vault view secrets/identite-sauvegardes.yml \
>   | sed -n 's/^identite_age_cle_privee: *"\{0,1\}\(AGE-SECRET-KEY-[^"]*\)"\{0,1\}$/\1/p'; }
admin@adm01:~/src/ansible$ time ( rclone cat ids3:identite-sauvegardes/idp01/keycloak-idp01-20261104T071502Z.dump.age \
>   | age -d -i <(cle) \
>   | ssh admin@10.10.99.42 'sudo -u postgres pg_restore --no-owner --role=keycloak -d keycloak --exit-on-error' )
admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/essai-resto playbooks/identite-essai-resto.yml --tags keycloak
```

(Le distant `ids3` de `rclone` est décrit par les variables d'environnement de RB-243 §3, chargées depuis `~/.config/workbook/s3-identite.env` : [modèle](fichiers/M24-E25/adm01/s3-identite.env.exemple).)

Preuves (RB-243 §4.5) : `/health/ready` `UP` ; découverte servie par `idp-resto` avec l'émetteur `https://sso.par1.medisphere.internal/realms/medisphere` (option `hostname`) ; `kid` identiques à la production ; mêmes nombres de personnes par royaume. Conséquence : une copie restaurée **accepte et émet** des jetons indiscernables de ceux de la production — c'est pour cela qu'elle est isolée puis détruite, et qu'une sauvegarde déchiffrée vaut une compromission.

*FreeIPA.* `ipa-restore` exige le même nom d'hôte, le même royaume et la même version : la jouer sur une VM jetable du lab signifierait un second `ipa01.par1.medisphere.internal` (conflits DNS, Kerberos, inscriptions), et 4 Go de mémoire. On vérifie l'archive et on écrit la procédure (RB-243 §5) ; la restauration de VM depuis PBS (carte réseau débranchée) est l'essai réaliste (« pour aller plus loin »).

Runbook : [`RB-243`](fichiers/M24-E25/medisphere/docs/securite/identite/runbooks/RB-243-restauration-identite.md).

**Explications**

- **Chiffrement côté client vers une clé publique.** L'hôte sait chiffrer, pas déchiffrer : un `idp01` compromis ne lit pas les sauvegardes des autres jours ; un `s3-01` compromis ne lit rien. La clé privée n'existe que dans le Vault `critique` et sur papier.
- **Identité S3 sans suppression.** Un hôte compromis (ou un script fautif) ne peut pas effacer ses sauvegardes ; le cycle de vie, posé par l'administrateur, purge.
- **Contrôle avant envoi.** Une sauvegarde jamais relue est une hypothèse : `pg_restore --list` prouve que l'archive est lisible et contient les tables qui comptent ; la taille relue prouve que l'objet est complet.
- **Deux niveaux.** La sauvegarde de VM (PBS) rend un retour rapide « à l'identique » ; l'applicative est portable (autre VM, autre version de Debian) et cohérente par construction.

**Alternatives**

- *Archivage continu de PostgreSQL* (WAL, `pgBackRest`) : RPO de quelques minutes ; plus d'exploitation, utile le jour où Keycloak aura plusieurs nœuds (E24, option C).
- *Export complet `kc.sh export` hebdomadaire, service arrêté* : lisible et portable entre versions de Keycloak, mais une coupure et des secrets en clair (à chiffrer de même).
- *Réplica FreeIPA* plutôt que des sauvegardes : la bonne réponse en production (4 Go de plus) ; il réplique aussi les erreurs (suppression), la sauvegarde reste nécessaire.

**Pièges classiques**

- Démarrer Keycloak sur la base vide **avant** la restauration : il crée un royaume `master` neuf ; `pg_restore` échoue ensuite sur des objets existants, ou mélange deux bases.
- Restaurer dans une version de Keycloak **plus ancienne** que celle de la sauvegarde : schéma inconnu, refus au démarrage.
- `pg_restore` sans `--no-owner --role=keycloak` en `postgres` : objets appartenant à `postgres`, Keycloak ne peut plus modifier son schéma à la montée de version suivante.
- Déchiffrer « pour voir » dans `/tmp` sur `adm01` : une copie claire de tous les secrets de l'identité qui traîne.
- Une restauration d'essai joignable : elle répond sur `sso…` à qui la résout autrement, et sa fédération se lie à `ipa01`.
- `ipa-backup` complet chaque nuit : il **arrête** les services de l'annuaire quelques minutes (connexions refusées, SSSD en cache) ; la nuit, `--data --online`.

**En production chez MédiSphère**

Sauvegardes copiées à PAR2 (réplication du compartiment, F5), essai de restauration trimestriel inscrit au calendrier de l'astreinte, mesure du RTO suivie, alerte sur l'âge de la dernière sauvegarde (métrique tirée de `dernier-succes` par le collecteur *textfile* de node_exporter), clé privée age en partage de secret (deux personnes), réplica FreeIPA dès qu'un second hyperviseur existe.

---

### M24-E26 — Superviser l'identité : santé, métriques, événements

**Solution**

1. `/metrics` (port 9000) : `http_server_requests_seconds_*` (latence et codes par `uri` : `/realms/{realm}/protocol/openid-connect/token`…), `agroal_*` (pool JDBC : `agroal_awaiting_count` > 0 = connexions en attente), `jvm_*`, `vendor_cache_*`, `keycloak_session_expiration_task_seconds`. « Sert » : codes 2xx/3xx du point de jetons ; « va mal » : `up`, 5xx, attente du pool, GC, `/health/ready`.
2. [`host_vars/idp01/keycloak.yml`](fichiers/M24-E26/ansible/inventories/lab/host_vars/idp01/keycloak.yml) (`keycloak_options`) ; le rôle reconstruit (option de construction). Après deux échecs :
   ```
   admin@adm01:~$ curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt \
   >   https://idp01.par1.medisphere.internal:9000/metrics | grep '^keycloak_user_events_total'
   keycloak_user_events_total{error="invalid_user_credentials",event="login",realm="medisphere"} 2.0
   admin@idp01:~$ sudo journalctl -u keycloak -o cat --since -5min | jq -r 'select(.loggerName=="org.keycloak.events") | "\(.level) \(.message)"'
   WARN type="LOGIN_ERROR", realmId="…", realmName="medisphere", clientId="account-console", userId="…", ipAddress="10.255.1.2", error="invalid_user_credentials", auth_method="openid-connect", …, username="lucas.martin"
   ```
   Logger `org.keycloak.events`. La ligne contient le type, le royaume, le client, l'identifiant, l'**adresse du client** (vraie grâce à `X-Forwarded-For` nettoyé par HAProxy, E04) ; elle ne doit **jamais** contenir de mot de passe ni de jeton (Keycloak ne les écrit pas ; un niveau `DEBUG` sur d'autres catégories pourrait en écrire : on ne le règle jamais en production).
3. [`tofu/evenements.tf`](fichiers/M24-E26/identite/tofu/evenements.tf) : stockage 30 jours, événements d'administration avec détails, écouteur `jboss-logging` écrit (sinon un apply qui ne le cite pas le retirerait). Une MR qui change une description de portée apparaît dans *Events* → *Admin events* (`UPDATE`, `CLIENT_SCOPE`, auteur `service-account-svc-tofu-keycloak`).
4. [`scrape/keycloak.yaml`](fichiers/M24-E26/observabilite/scrape/keycloak.yaml), [`regles/identite.yaml`](fichiers/M24-E26/observabilite/regles/identite.yaml), [`tests/identite.test.yaml`](fichiers/M24-E26/observabilite/tests/identite.test.yaml), [listes des kustomizations](fichiers/M24-E26/observabilite/scrape-et-regles-kustomization.extrait) ; flux : [bordure](fichiers/M24-E26/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`pare_feu_local` d'idp01](fichiers/M24-E26/ansible/inventories/lab/host_vars/idp01/pare_feu_local.yml.extrait), [matrice](fichiers/M24-E26/medisphere/docs/socle/matrice-flux.md.extrait).
   ```
   admin@adm01:~/src/observabilite$ yq '.spec' regles/identite.yaml > /tmp/identite.rules.yaml && promtool test rules tests/identite.test.yaml
     SUCCESS
   ```
   `KeycloakEchecsConnexion` compte `invalid_user_credentials`, `user_not_found`, `user_disabled`, `user_temporarily_disabled` ; il écarte `resolve_required_actions` (action requise en attente, pas un échec de preuve), les erreurs de client (redirection, PKCE : un problème de **service**, que `KeycloakIndisponible` ou les alertes des services voient) et `expired_code`.
5. Rôle `alloy` : [gabarit complet](fichiers/M24-E26/ansible/roles/alloy/templates/config.alloy.j2) (source journal dédiée par unité d'audit avec `matches = "_SYSTEMD_UNIT=…"`, `stage.drop` de ces unités dans le flux général, `local.file_match` + `loki.source.file` pour les fichiers, `loki.write "audit"`), [valeurs par défaut](fichiers/M24-E26/ansible/roles/alloy/defaults/main.yml.extrait), [tâches pour Rocky 10](fichiers/M24-E26/ansible/roles/alloy/tasks/main.yml.extrait), [unité](fichiers/M24-E26/ansible/roles/alloy/templates/alloy.service.j2.extrait) ; [`host_vars/idp01/alloy.yml`](fichiers/M24-E26/ansible/inventories/lab/host_vars/idp01/alloy.yml), [`host_vars/ipa01/alloy.yml`](fichiers/M24-E26/ansible/inventories/lab/host_vars/ipa01/alloy.yml). Choix pour `krb5kdc.log` (root 600) : `CAP_DAC_READ_SEARCH` limitée à `ipa01` ; l'ajout d'Alloy au groupe `dirsrv` couvrirait 389-ds mais pas le KDC, et changer les droits du fichier du KDC serait défait par `logrotate`.
6. [`loki/regles/audit/identite.yaml`](fichiers/M24-E26/observabilite/loki/regles/audit/identite.yaml) et la [ConfigMap des règles](fichiers/M24-E26/observabilite/loki/kustomization.yaml.extrait). Le « Test connection » avec une URL fausse (`ldaps://ipa99…`) écrit une ligne `WARN`/`ERROR` qui cite LDAP et la cause (`Connection refused`, `UnknownHostException`) : c'est elle que filtre la règle. Vérifie l'expression dans Grafana (Explore, source Loki — audit) sur la fenêtre de l'essai **avant** de la fusionner.
7. Sonde : [extrait du témoin](fichiers/M24-E26/ansible/inventories/lab/host_vars/mon01/supervision_temoin.yml.extrait). Essai : arrêt de Keycloak → `KeycloakIndisponible` après 2 min de `for` + 30 s de collecte + regroupement d'Alertmanager (`group_wait`, M21) : courriel en 3 à 4 min ; la sonde du témoin (intervalle de 30 s, règle du témoin) arrive dans le même ordre de temps, **par un autre chemin** (VIP, HAProxy).

**Explications**

- **Deux locataires, deux publics.** Le locataire `plateforme` est lu par toute l'équipe et par les équipes applicatives pour leurs VMs ; les connexions des personnes (identifiants, adresses) sont des données d'audit, lues par la sécurité et l'astreinte (M22-E16). D'où l'exclusion du journal de `keycloak.service` du flux général.
- **Métriques et journaux se complètent.** Le compteur dit « combien » (alerte peu coûteuse, historique de 2 ans dans Thanos) ; le journal dit « qui, d'où » (enquête). Les étiquettes du compteur restent au royaume (pas de `clientId` : cardinalité).
- **Le témoin.** Prometheus du cluster collecte `idp01` directement ; le témoin de `mon01` passe par la VIP et HAProxy comme un utilisateur. Un HAProxy mal configuré n'est vu que par le second.

**Alternatives**

- *Métriques de la fédération* : fonction `ldap-metrics` de la 26.8 (désactivée par défaut, à évaluer après E33) ; ou une sonde `ldaps` de blackbox vers `ipa01:636` (dit « l'annuaire répond », pas « Keycloak s'y lie »).
- *Écouteur d'événements* vers un système externe (SIEM) par un SPI : à envisager avec un SIEM réel (F6).
- *Événements stockés en base seulement* : consultables, pas alertables ; et la base n'est pas un puits de journaux (taille, rétention).

**Pièges classiques**

- Oublier le niveau des succès : `jboss-logging` les écrit en `DEBUG` par défaut, on ne voit alors que les erreurs.
- `event-metrics-user-tags=realm,clientId,idp` : une série par client, par événement, par erreur : la cardinalité grimpe.
- Une règle sur `increase(...)` d'un compteur qui n'existe qu'après le premier événement : la toute première vague n'est comptée qu'à partir de la seconde collecte (acceptable ; à savoir).
- Un `stage.drop` mal écrit qui jette **tout** le journal de l'hôte (tester sur `idp01` avec `logcli`/Explore : le journal de `sshd` doit toujours arriver dans `plateforme`).
- Un filtre LogQL écrit sans avoir vu la vraie ligne d'erreur : la règle ne se déclenche jamais.

**En production chez MédiSphère**

Tableau « Identité » (connexions par minute, échecs par type, latence p95 du point de jetons, pool de connexions), SLO de l'authentification dans Pyrra, envoi du locataire `audit` vers un stockage à rétention longue (un an au moins, exigence HDS), revue hebdomadaire des événements d'administration par la sécurité.

---

### M24-E27 — Durcir Keycloak : sessions, jetons, force brute, administration

**Solution**

1. Valeurs relevées (royaume créé en 26.7.5) : jeton d'accès 300 s, session inactive 1800 s, maximale 36000 s, pas de rotation des jetons de rafraîchissement, force brute **désactivée**, aucune politique de mot de passe, en-têtes par défaut (`X-Frame-Options: SAMEORIGIN`, CSP `frame-src 'self'; frame-ancestors 'self'; object-src 'none';`, HSTS `max-age=31536000; includeSubDomains`), événements non stockés. Le durcissement porte donc surtout sur ce qui est **désactivé** par défaut ; les durées par défaut conviennent, mais on les **écrit** (une valeur par défaut peut changer à la montée de version ; le code dit ce qu'on a décidé).
2. **Force brute.** Keycloak verrouille temporairement à **5** échecs (l'annuaire à 6) : tant que Keycloak verrouille, il ne tente plus de liaison LDAP, le compteur de FreeIPA ne monte plus ; attente initiale 60 s, doublée à chaque nouveau verrouillage jusqu'à 15 min ; remise à zéro après 12 h (≥ celle de l'annuaire) ; contrôle de connexion rapide (deux échecs à moins d'une seconde → 60 s). Permanent : non — un verrouillage permanent **désactive** la personne dans Keycloak : n'importe qui connaissant l'identifiant de Julien peut le priver de tout accès (déni de service), et la réactivation se ferait dans Keycloak, alors que la source de vérité est l'annuaire. Reste la voie directe : un attaquant qui a accès au formulaire de FreeIPA (`ipa01:443`, MGMT seulement) ou au KDC (VMs inscrites) peut toujours verrouiller dans l'annuaire : filtrage réseau (E02) et surveillance des verrouillages (`BrisDeGlace*`, journal du KDC).
3. [`tofu/royaume.tf`](fichiers/M24-E27/identite/tofu/royaume.tf) (testé : apply puis plan vide avec le fournisseur 5.10). Plan attendu : `keycloak_realm.medisphere will be updated in-place` avec `revoke_refresh_token`, `password_policy`, `security_defenses`, `remember_me`, `reset_password_allowed` ; les durées n'apparaissent pas (déjà à ces valeurs).
4. Épreuve :
   ```
   lucas.martin : 5 mots de passe faux (espacés de quelques secondes), puis le bon → « Invalid username or password » (Keycloak ne dit pas qu'il a verrouillé)
   [admin@ipa01 ~]$ kinit admin && ipa user-status lucas.martin | grep -i 'failed logins'; kdestroy
     Failed logins: 0          ← l'annuaire n'a rien vu après le verrouillage de Keycloak (5 tentatives au plus)
   ```
   Dans la console : *Users* → `lucas.martin` → bandeau « temporairement verrouillé » ; événement `USER_DISABLED_BY_TEMPORARY_LOCKOUT` dans Loki. Rafraîchissement : le premier délivre de nouveaux jetons, le second (même jeton) répond `invalid_grant` / `Maximum allowed refresh token reuse exceeded` ; la session reste ouverte (observé en 26.7.5) : l'événement d'erreur signale un vol possible, à surveiller.
5. [`host_vars/idp01/keycloak.yml`](fichiers/M24-E27/ansible/inventories/lab/host_vars/idp01/keycloak.yml) : `features-disabled: impersonation` (option de construction). Après reconstruction, le bouton *Impersonate* disparaît (même pour les administrateurs de `master`) et l'API répond 404/501 sur `…/users/{id}/impersonation`.
6. Revue des clients :
   ```
   admin@adm01:~$ lab/bin/check 24 27      # contrôle tout le royaume par l'API, avec wb-checks
   ```
   L'API (`GET /admin/realms/medisphere/clients`) donne `implicitFlowEnabled`, `directAccessGrantsEnabled`, `redirectUris`, `fullScopeAllowed`, `publicClient`, `attributes."pkce.code.challenge.method"`. Attendus : aucun implicite, aucun *Direct Access Grants*, aucune redirection avec `*` ; clients publics (`argocd-cli`, `kubernetes`) avec PKCE `S256` ; `full_scope_allowed = false` sur les clients qui n'ont pas besoin de rôles du royaume dans leurs jetons (tous chez nous : on autorise par **groupes**) — à écrire dans chaque `tofu/clients-*.tf`.
7. `master` à la main (*Realm settings* → *Security defenses* → *Brute force detection* : « Lockout temporarily », 5 échecs ; *Authentication* → *Policies* → *Password policy* : `length(16)`, `notUsername`, `passwordHistory(6)` ; *Sessions* : session SSO inactive 30 min, maximale 8 h). Document : [`master.md`](fichiers/M24-E27/medisphere/docs/securite/identite/master.md). `kc-secours` essayé juste après.
8. Non-régression : Grafana, Argo CD (navigateur et `argocd login --sso`), `kubectl` (kubelogin : les jetons de rafraîchissement tournent désormais, kubelogin enregistre le nouveau à chaque fois), `step ssh login` ; aucune alerte.

**Explications**

- **Rotation des jetons de rafraîchissement.** Un jeton de rafraîchissement volé et utilisé par l'attaquant rend celui de la victime inutilisable (ou l'inverse) : le vol devient **visible** (erreur, événement) au lieu de durer des heures.
- **Des durées courtes ne suffisent pas seules** : la révocation d'une personne passe par l'annuaire (refus à la prochaine liaison) et la fermeture de ses sessions (RB-242) ; les durées bornent ce qui reste.
- **En-têtes.** HSTS force HTTPS ; `X-Frame-Options`/`frame-ancestors` empêchent l'habillage de la page de connexion (*clickjacking*) ; `SAMEORIGIN` et non `DENY`, car Keycloak s'insère lui-même dans des iframes de même origine (vérification de session de la console).
- **Impersonation.** Une fonction pratique au support, et une porte : un administrateur (ou un compte d'automatisation trop puissant) qui ouvre une session **au nom** d'une personne, MFA compris. Hors de nos besoins : désactivée.

**Alternatives**

- *Console d'administration sous un autre nom* (`hostname-admin=https://sso-admin.par1…`, joignable en MGMT seulement, un certificat de plus) : plus propre que le filtrage par chemin d'HAProxy ; à faire au M26.
- *DPoP* (jetons liés à une clé du client, pris en charge) : rend les jetons volés inutilisables ; il faut des clients qui le savent (pas encore nos outils).
- *Politiques de clients* (*client policies*) qui **imposent** PKCE, des redirections exactes et l'absence d'implicite à tout nouveau client : contrôle préventif plutôt que revue.

**Pièges classiques**

- Raccourcir la session SSO **sous** l'intervalle de rafraîchissement d'un service : déconnexions en boucle (Argo CD : `refreshTokenThreshold`).
- Un verrouillage permanent avec une fédération : des personnes désactivées dans Keycloak et actives dans l'annuaire, et des appels au support.
- Une politique de mot de passe sur `master` qui exige un changement à la prochaine connexion (`forceExpiredPasswordChange`) : `kc-secours` doit changer son mot de passe… le jour du bris de glace.
- Écrire `security_defenses` sans tous les en-têtes : le fournisseur peut remplacer les absents par une valeur vide (vérifie le plan).
- Désactiver une fonction de construction sans reconstruire : Keycloak démarre avec l'ancienne image (le rôle s'en charge par le témoin).

**En production chez MédiSphère**

Politiques de clients obligatoires, console d'administration sur un nom et un réseau séparés, clés FIDO2 pour les administrateurs de `master`, revue semestrielle des réglages contre la grille ANSSI (Sophie), test automatique des en-têtes et des durées dans la CI de `plateforme/identite` (plan + `jq` sur l'API d'une copie).

---

### M24-E28 — Bris de glace : comptes de secours et procédure éprouvée

**Solution**

1. Tableau complet : [`RB-240`](fichiers/M24-E28/medisphere/docs/securite/identite/runbooks/RB-240-bris-de-glace.md) §3 (ouvrir, utiliser, refermer, tracer par service).
2. Alertes : [`loki/regles/audit/identite.yaml`](fichiers/M24-E28/observabilite/loki/regles/audit/identite.yaml) (état E28 : `BrisDeGlaceKeycloak`, `BrisDeGlaceAnnuaire` (KDC), `BrisDeGlaceAnnuaireLiaisonLdap` (389-ds), `BrisDeGlaceCluster` (audit de l'API, utilisateur `kubernetes-admin`)). Étiquette `equipe: securite` : ajoute, si elle n'existe pas, la route d'Alertmanager correspondante (M21-E16) vers Sophie **et** l'astreinte :
   ```yaml
   # kps/values.yaml — alertmanager.config.route.routes (EXTRAIT)
   - matchers: ['equipe="securite"']
     receiver: securite-et-astreinte
     group_wait: 0s
     repeat_interval: 4h
   ```
   Faux positifs acceptés : chaque job `annuaire:appliquer` (Kerberos d'`admin`), chaque passage du rôle `k8s_plan_controle` qui utilise `admin.conf`. Ils sont rares, manuels et traçables (pipeline).
3. Essai, un compte à la fois. Commandes types, sans secret sur la ligne de commande ni fichier clair :
   ```
   [admin@ipa01 ~]$ kinit admin && ipa user-show lucas.martin --all | head -5; kdestroy
   admin@adm01:~/src/k8s$ kubectl --kubeconfig <(uv run --project ~/src/ansible ansible-vault view secrets/admin.conf) auth whoami
   ATTRIBUTE   VALUE
   Username    kubernetes-admin
   Groups      [kubeadm:cluster-admins system:authenticated]
   admin@adm01:~$ curl -s -K <(printf 'user = "admin:%s"\n' "$(cd ~/src/k8s && uv run --project ~/src/ansible ansible-vault view secrets/grafana.yml | sed -n 's/^admin_mot_de_passe: *//p')") \
   >   https://grafana.apps.par1.medisphere.internal/api/org | jq -r .name
   Main Org.
   ```
   (Les chemins des fichiers Vault de `admin.conf` et de Grafana sont ceux de tes modules 14 et 21 ; adapte-les.) Chaque alerte attendue arrive en 1 à 2 minutes (évaluation du ruler chaque minute). GitLab `root`, Harbor « LOGIN VIA LOCAL DB », NetBox, `root@pam` : connexion et déconnexion dans une fenêtre privée, sans alerte (§7 de RB-240).
4. RB-240 et son procès-verbal (annexe A).
5. Comptes partagés restants : RB-240 §7 (`root` de GitLab sans alerte, `root@pam` hors de Loki, `admin` de Grafana et de FreeIPA qui servent aussi à l'automatisation, compte local `admin` des VMs).

**Explications**

- **Trois propriétés d'un compte de secours** (E01) : indépendant de ce qui est en panne (local, sans SSO, sans téléphone personnel), protégé et rare (coffre, deux personnes), éprouvé et surveillé. Un compte de secours jamais essayé ne marche pas le jour J (mot de passe faux au coffre, compte expiré, politique qui exige un changement) ; un compte dont l'usage ne se voit pas est un compte partagé.
- **Pourquoi `kc-secours` n'a pas d'OTP** : un second facteur attaché à un téléphone personnel le rendrait inutilisable en l'absence de son porteur ; une clé FIDO2 au coffre avec le mot de passe serait le bon second facteur.
- **Alerter sur l'usage, pas sur l'échec seulement** : un usage réussi non déclaré est l'événement le plus grave.

**Alternatives**

- *Coffre de mots de passe d'équipe avec journal d'accès* (Vaultwarden, OpenBao au M25) : l'ouverture elle-même est tracée.
- *Partage de secret de Shamir* sur papier : deux personnes nécessaires.
- *Comptes de secours désactivés* et réactivés par une procédure : plus sûr pour Argo CD (déjà le cas) ; impossible pour Keycloak lui-même (il faudrait Keycloak pour le réactiver : d'où `bootstrap-admin`).

**Pièges classiques**

- Taper le mot de passe de secours à la main lors de l'essai : faute de frappe, deux essais, compte verrouillé (force brute de `master`, E27).
- Laisser un ticket Kerberos d'`admin` en cache sur `ipa01` après l'essai (`kdestroy`).
- `kubectl --kubeconfig admin.conf` avec un fichier déchiffré « le temps de l'essai », oublié dans `~`.
- Une alerte de bris de glace routée vers une équipe qui ne lit pas la nuit.
- Oublier de **changer** le secret après un bris de glace réel : il a été vu (écran, presse-papiers).

**En production chez MédiSphère**

Essai trimestriel planifié (ticket CHG récurrent), procès-verbal versionné, secrets de secours dans OpenBao avec ouverture à deux (M25), alerte sur **toute** ouverture du coffre, journaux de GitLab et des hyperviseurs dans Loki `audit` (M26, F6).

---

### M24-E29 — Rotation des secrets des clients et des clés de signature

**Solution**

*A. Le secret de `grafana`.*

1. `GET /admin/serverinfo` (console *Server info* → *Features*) : en 26.7.5, `CLIENT_SECRET_ROTATION` figure parmi les fonctions **en préversion désactivées** (vérifié). Donc : fenêtre courte. (L'activer exigerait `features=client-secret-rotation`, une reconstruction, et une fonction en préversion en production : non.)
2. Code : [`tofu/secrets-clients.tf`](fichiers/M24-E29/identite/tofu/secrets-clients.tf) (variable éphémère `secrets_clients`, versions par client), [`clients-grafana.tf.extrait`](fichiers/M24-E29/identite/tofu/clients-grafana.tf.extrait) (`client_secret_wo`, `client_secret_wo_version`), [`charger-acces.sh.extrait`](fichiers/M24-E29/identite/outils/charger-acces.sh.extrait). Le plan ne montre qu'une chose :
   ```
     ~ resource "keycloak_openid_client" "grafana" {
         ~ client_secret_wo         = (write-only attribute)
         ~ client_secret_wo_version = "1" -> "2"
   Plan: 0 to add, 1 to change, 0 to destroy.
   ```
   Il ne montre **pas** la valeur, ni avant ni après, et ne prouve donc pas que le Vault contient le bon secret : c'est le contrôle du point 4 qui le prouve. Et l'état ne contient plus le secret de `grafana` (vérifié : avec `client_secret_wo`, le fournisseur ne l'enregistre pas), contrairement aux clients dont Keycloak a généré le secret.
3. Ordre : le **service** est prêt d'abord (Secret Kubernetes mis à jour, pod pas encore redémarré), puis Keycloak (apply), puis le redémarrage du pod. Entre l'apply et la fin du redémarrage, les **nouvelles** connexions échouent (`invalid_client_credentials` côté Grafana : « Login failed ») ; les sessions déjà ouvertes dans Grafana ne sont pas touchées (Grafana ne rappelle Keycloak qu'au rafraîchissement de son jeton OAuth, et ses propres sessions durent 8 h). Fenêtre typique : 20 à 40 s (temps de démarrage de Grafana). L'ordre inverse (Grafana d'abord) donne la même fenêtre, mais la fait commencer plus tôt et durer jusqu'à l'apply, qui attend un pipeline.
4. Preuve que l'ancien est mort. Avant la rotation, garde l'ancien secret dans une variable du shell (jamais un fichier) ; après :
   ```
   admin@adm01:~$ read -rs ANCIEN     # collé depuis le Vault AVANT la rotation
   admin@adm01:~$ NOUVEAU="$(cd ~/src/ansible && uv run ansible-vault view secrets/identite.yml \
   >   | yq -r '.keycloak_secrets_clients.grafana')"
   admin@adm01:~$ for v in ANCIEN NOUVEAU; do printf '%s : ' $v; curl -s -o /dev/null -w '%{http_code}\n' \
   >   -K <(printf 'user = "grafana:%s"\n' "${!v}") \
   >   -d token=x https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/token/introspect; done
   ANCIEN : 401
   NOUVEAU : 200
   admin@adm01:~$ unset ANCIEN NOUVEAU
   ```
   (L'introspection d'un jeton bidon avec le bon secret répond `200 {"active":false}` : c'est l'authentification du **client** qui est testée.)

*B. Les clés.* [`tofu/cles.tf`](fichiers/M24-E29/identite/tofu/cles.tf) (état final : origine importée puis désactivée ; `rsa-2026-10` de priorité 200, 4096 bits — le fournisseur refuse 3072). Trois MR :

| MR | `origine` | `rsa_2026_10` | JWKS (clés RS256) | Signe |
|---|---|---|---|---|
| 1 | importée, `active = true`, `enabled = true` | créée, priorité 200 | 2 | la nouvelle (priorité) |
| 2 (même jour) | `active = false` (passive) | — | 2 | la nouvelle |
| 3 (≥ 24 h après) | `enabled = false` | — | 1 | la nouvelle |

5. Après la MR 1 : deux clés RS256 publiées ; un nouveau jeton porte le nouveau `kid` ; un jeton d'avant reste accepté (introspection `active: true`, `kubectl` fonctionne avec le jeton en cache de kubelogin) parce que l'ancienne clé est toujours publiée.
6. La plus longue durée de vie d'un jeton signé : le jeton de **rafraîchissement** (jusqu'à la session SSO maximale, 10 h) ; on attend 24 h. Après la MR 3 : une seule clé RS256 ; reconnexions normales. Les caches de clés ne gênent pas : on n'a retiré qu'une clé qui ne signait plus depuis 24 h.
7. [`RB-244`](fichiers/M24-E29/medisphere/docs/securite/identite/runbooks/RB-244-rotation-cles-et-secrets.md).

**Explications**

- **Actif, passif, désactivé** (vérifié sur 26.7.5) : `ACTIVE` signe (la plus haute priorité gagne), `PASSIVE` est publiée et vérifie, `DISABLED` disparaît du JWKS. La rotation sans coupure est « ajouter, attendre, retirer » : le principe de toute rotation de clé publique.
- **kube-apiserver** relit le JWKS de l'émetteur quand il voit un `kid` inconnu (et périodiquement) : il accepte la nouvelle clé dès le premier jeton qu'elle signe.
- **Secret imposé ou généré.** Généré par Keycloak, le secret doit être **lu** (état OpenTofu, console) pour être donné au service : il passe par plus d'endroits. Imposé par le Vault, il ne vit qu'au Vault, dans Keycloak et dans le service.

**Alternatives**

- *Double secret de la 26.8* (après E33) : politique de clients avec l'exécuteur de rotation ; Keycloak accepte l'ancien secret pendant le recouvrement : changer le service sans fenêtre.
- *Authentification des clients par JWT signé* (`client-secret-jwt`, ou mieux `private_key_jwt` : le client signe une assertion avec sa clé privée, Keycloak connaît sa clé publique ou son JWKS) : plus de secret partagé ; il faut que le service le sache (Grafana : non ; OAuth2 Proxy : oui).
- *Clés ES256* : jetons plus petits ; tous nos services les vérifient, à valider client par client.

**Pièges classiques**

- Désactiver l'ancienne clé dans la même MR que l'ajout : tous les jetons en cours refusés, CLI à reconnecter, et des rafraîchissements en échec.
- Supprimer le bloc de l'ancienne clé (destruction) au lieu de la désactiver : pas de retour arrière.
- Oublier `client_secret_wo_version` : OpenTofu ne pousse jamais le nouveau secret (argument en écriture seule, jamais relu) ; Keycloak garde l'ancien, Grafana a le nouveau : panne au prochain redémarrage de Grafana.
- Mettre le secret dans une variable non éphémère : il finit dans le plan enregistré du pipeline.
- Redémarrer Grafana **avant** d'avoir mis à jour le Secret : il relit l'ancien.

**En production chez MédiSphère**

Secrets des clients dans OpenBao (M25) avec rotation planifiée et ESO qui propage au service ; double secret activé par une politique de clients après la 26.8 ; rotation annuelle des clés en octobre, inscrite au calendrier ; supervision de l'âge de chaque secret dans la revue des accès (E30, pour aller plus loin).

---

### M24-E30 — Revue des accès automatisée : qui a accès à quoi

**Solution** (une solution possible ; `LIBRE` : d'autres choix sont valables s'ils respectent les contraintes)

Fichiers : [`outils/revue-acces/`](fichiers/M24-E30/identite/outils/revue-acces/) — [`revue_acces.py`](fichiers/M24-E30/identite/outils/revue-acces/revue_acces.py) (sources, analyse, rendus, envoi, MR), [`modele.yml`](fichiers/M24-E30/identite/outils/revue-acces/modele.yml) (le modèle d'E10 en forme machine), [`ecarts-acceptes.yml`](fichiers/M24-E30/identite/outils/revue-acces/ecarts-acceptes.yml), [`README.md`](fichiers/M24-E30/identite/outils/revue-acces/README.md) (identités et droits, ce que l'outil ne voit pas), [`pyproject.toml`](fichiers/M24-E30/identite/outils/revue-acces/pyproject.toml), [job de CI](fichiers/M24-E30/identite/.gitlab-ci.yml.extrait).

Choix de conception :

- **Partir de l'annuaire** (la liste des personnes et de leur état) et joindre chaque service par l'identifiant (`preferred_username`) : ce qui ne joint pas est soit un compte de service attendu, soit un **écart**.
- **Des écarts typés et à clé stable** (`type:service:sujet`) : comparables d'un mois à l'autre (JSON), acceptables nominativement (`ecarts-acceptes.yml` : qui, pourquoi, jusqu'à quand), et triés « nouveau / connu ».
- **Une identité par source**, en lecture (README) ; deux concessions documentées : GitLab CE n'expose `is_admin` et les jetons des autres qu'à un administrateur (jeton `read_api` à expiration), Grafana OSS n'a pas de rôle « lecture des utilisateurs » sans droit d'administration d'organisation.
- **`master` de Keycloak hors de l'outil** : lui donner un droit sur `master` pour une revue serait plus risqué que le contrôle qu'il apporterait ; RB-240 et le check d'E04 couvrent les deux comptes attendus.
- **La signature** = l'approbation de la MR par Sophie (règle d'approbation sur `docs/securite/identite/revue-acces/`), qui date et nomme le relecteur.

Épreuve de l'écart volontaire :

```
admin@adm01:~$ # en admin de Grafana (bris de glace, RB-240) : utilisateur local essai-revue, rôle Editor
GitLab : Run pipeline sur main avec REVUE_ESSAI=1 → artefact rapport/2026-11.md :
| **oui** | `compte-local-inconnu:grafana:essai-revue` | compte local, rôle Editor |
admin@adm01:~$ # suppression d'essai-revue, puis le pipeline mensuel (ou un second essai) : l'écart a disparu,
admin@adm01:~$ # et la comparaison avec le mois précédent le range dans « Résolus ».
```

**Explications**

- **L'auditeur veut des écarts et une preuve de relecture**, pas un inventaire de 400 lignes : la section « Écarts » en tête, la liste complète dessous.
- **Le modèle en code** (`modele.yml`) rend la règle vérifiable ; il doit rester **identique** à `modele-autorisation.md` (même MR pour les deux).
- **Lecture seule** : l'outil ne corrige rien. Corriger automatiquement (désactiver un compte local inconnu) serait tentant et dangereux (comptes de secours, comptes de service mal déclarés).

**Alternatives**

- *Outils de gouvernance des identités* (midPoint, open source) : provisionnement, rôles, campagnes de certification ; puissant et lourd, pour une organisation plus grande.
- *SCIM* entre Keycloak et les services : provisionnement et déprovisionnement automatiques ; la revue reste nécessaire (ce qui n'est pas passé par SCIM).
- *Rapport par service, sans croisement* : plus simple, mais ne répond pas à « cette personne partie a-t-elle encore un accès quelque part ? ».

**Pièges classiques**

- Utiliser les identités des checks du workbook ou un administrateur « parce que c'est plus simple ».
- Un secret dans le journal du job (`set -x`, `curl -H "PRIVATE-TOKEN: …"` affiché par un `echo`) : variables masquées, `-K` pour curl.
- Comparer des noms de groupes avec et sans préfixe (`oidc:plateforme` contre `plateforme`), ou des identifiants avec une casse différente.
- Un rapport qui contient des adresses de courriel, des noms complets ou des jetons : le rapport est versionné et lu largement.
- Des écarts acceptés sans date de fin : l'exception devient la règle.

**En production chez MédiSphère**

Revue mensuelle signée, trimestrielle par les responsables d'équipe pour leurs groupes (campagne de recertification), écarts suivis comme des tickets SEC avec délai de traitement, métrique « écarts ouverts » dans Grafana, sources étendues à Harbor, NetBox, PBS, OpenBao (M25) et aux applications.

---

### M24-E31 — ADR : l'architecture d'identité de MédiSphère

**Proposition de rédaction** : [`ADR-0240-architecture-identite.md`](fichiers/M24-E31/medisphere/docs/securite/identite/adr/ADR-0240-architecture-identite.md).

**Grille d'auto-évaluation**

| Critère | Attendu |
|---|---|
| Contexte | exigences (HDS, nominatif, MFA, révocation, preuve) **et** contraintes du lab (mémoire, un hyperviseur) |
| Décisions | les dix décisions, chacune avec au moins une option écartée et **sa raison décisive** (licence de Teleport CE, pas de HBAC dans Samba AD, dépendance circulaire d'un IdP dans le cluster…) |
| Conséquences | positives et au moins cinq négatives, chacune avec son action ou son module |
| Risques acceptés | écrits, avec mesure compensatoire (RB-240, RB-243) |
| Modules suivants | client `openbao`, groupes → politiques (M25), migration des secrets des clients dans OpenBao, durcissement d'`idp01` et `ipa01` (M26) |
| Forme | deux pages environ ; cite les ADR, runbooks et exercices au lieu de les répéter |

**Pièges classiques** : un ADR qui raconte le module au lieu de décider ; des options écartées « parce que c'est moins bien » ; aucune conséquence négative (personne ne le croira) ; oublier que l'ADR sera **relu au M25** (décisions sur les secrets) et que ses conditions de révision doivent être observables.

---

### M24-E32 — Questions de production : Teleport, Pinniped, fédération, licences

**Barème** : 2 points par question, total sur 20.

**1. Teleport.** Depuis la version 16, les binaires et images de Teleport **Community Edition** sont distribués sous une licence commerciale gratuite seulement pour les entreprises de **moins de 100 salariés et moins de 10 M$ de chiffre d'affaires** ; MédiSphère en a 400. Deux voies légales : (a) **compiler** Teleport depuis le code source, publié sous **AGPLv3** : légal, mais il faut construire, signer, mettre à jour soi-même un composant de sécurité critique, et respecter l'AGPL (publication des modifications si le service est offert à des tiers) ; (b) un **contrat Enterprise** : coût par utilisateur ou par ressource, support, fonctions avancées (accès juste-à-temps, SSO SAML/OIDC complet). Notre choix (ADR-0240) : certificats SSH courts de step-ca + `kubectl` par OIDC, sans enregistrement de sessions (piste F6).

**2. Réponse B.** Pinniped (Supervisor + Concierge) authentifie par OIDC, LDAP ou AD et délivre des identités de courte durée **sans toucher aux options de kube-apiserver** : indispensable sur des clusters gérés (EKS, GKE, AKS) ou nombreux. A est faux : il s'appuie sur un IdP (Keycloak) ; C est faux : l'authentification structurée (GA en 1.34) est au contraire la voie native ; D est faux : OIDC est son mode principal.

**3. Fédération SAML d'un partenaire.** Dans Keycloak : un **fournisseur d'identité** SAML (*Identity Providers* → SAML v2.0) dans un royaume **dédié aux partenaires** (pas `medisphere`), importé depuis les **métadonnées** de l'hôpital (point SSO, certificat de signature) ; on leur donne les métadonnées de notre SP (`…/realms/partenaires/broker/<alias>/endpoint/descriptor` : entité, ACS, certificat). Flux *first broker login* : création du compte local fédéré au premier passage, **sans** liaison automatique à un compte existant par adresse (prise de compte). Mappeurs : `NameID` persistant ou un attribut stable (identifiant de l'hôpital) comme identifiant, **groupe attribué en dur** par fournisseur (`partenaire-chu-x`, droits minimaux dans MédiAgenda) ; on **refuse** de dériver des droits d'un attribut envoyé par le partenaire (rôle « admin » chez eux ≠ admin chez nous), d'importer plus d'attributs que nécessaire (minimisation RGPD), et d'accepter des assertions non signées ou non chiffrées. Rotation des certificats planifiée des deux côtés.

**4. Keycloak, Authentik, Zitadel.** Keycloak : le plus complet (fédération LDAP/Kerberos, courtage SAML/OIDC, flux personnalisables, fournisseur OpenTofu, grande base d'utilisateurs) ; lourd (JVM), administration riche. Authentik : simple, flux visuels, avant-poste (*outpost*) qui fait office de mandataire d'authentification ; moins mûr pour une fédération LDAP en lecture seule à grande échelle, une partie des fonctions sous licence Enterprise. Zitadel : multi-locataire natif, API d'abord, événements (*event sourcing*), bon pour un SaaS qui authentifie ses clients ; fédération LDAP plus récente, modèle de données différent de nos besoins internes. Dans un autre contexte (application grand public multi-organisations), Zitadel serait un bon choix.

**5. Annuaires.** 300 postes **Windows** : **Samba AD** (ou Active Directory) : stratégies de groupe, jonction de domaine native, Kerberos compatible Windows ; FreeIPA ne gère pas les postes Windows (une approbation de domaine avec un AD existant, oui). Aucun serveur Linux : la question de FreeIPA (HBAC, sudo, SSSD, certificats d'hôtes) ne se pose plus ; un AD (ou un annuaire en nuage) et Keycloak devant. OpenLDAP seul n'apporte que l'annuaire : à choisir pour un besoin LDAP pur et maîtrisé.

**6. Réponse B.** Un compte de service n'est pas une personne : pas de connexion interactive, un **jeton** à portée minimale et à durée de vie limitée, un **propriétaire** humain nommé (qui répond de son usage), une rotation, et une ligne dans la revue des accès. A est faux : l'OTP suppose une personne et un appareil ; C est faux : « partagé » = non imputable, et son secret circule ; D ne règle rien (un jeton volé sert le jour) et casse les pipelines planifiés.

**7. SCIM** (RFC 7643/7644) : API standard de **provisionnement** (créer, modifier, désactiver des utilisateurs et des groupes) entre un fournisseur d'identité et des applications. Entre Keycloak et GitLab ou Grafana, il remplacerait `synchro-gitlab.py` et la gestion des équipes par OpenTofu… si ces services offraient un point SCIM dans nos éditions (GitLab : SCIM réservé à des offres payantes ; Grafana : SCIM réservé à Enterprise et Cloud). Il ne remplace pas la revue : il synchronise ce qu'on lui donne, ne voit ni les comptes locaux, ni les jetons, ni les droits accordés hors de lui, ni les erreurs de modèle.

**8. Keycloak compromis.** L'attaquant peut **signer n'importe quel jeton** pour n'importe quel client du royaume, avec les groupes de son choix : tout service qui fait confiance à Keycloak lui est ouvert (GitLab, Grafana, Argo CD en `role:admin`, Harbor, Proxmox, `kubectl` en `oidc:plateforme-admins` = `cluster-admin`, OAuth2 Proxy, certificats SSH de step-ca pour n'importe quel principal, OpenBao au M25). Il lit aussi les secrets des clients et les seconds facteurs enregistrés. Restent protégés : les comptes **locaux** de secours (mots de passe hors Keycloak), `admin.conf` (certificat de la CA du cluster), les clés SSH locales `admin` des VMs, l'annuaire lui-même (Keycloak n'y écrit pas : `READ_ONLY`, `svc-keycloak` en lecture), les parts Shamir d'OpenBao. Conséquence : Keycloak est un actif de **niveau 0** (même protection que la CA et le coffre), et la remise en état passe par la rotation des clés de signature, de tous les secrets des clients, et l'invalidation des sessions.

**9. Réponse B.** Un compte nominatif, temporaire, à droits minimaux, MFA, désactivation planifiée et tracée (RB-241/242) : imputabilité, révocation automatique, pas de secret partagé. A est le pire (secret de secours divulgué, tous les droits, aucune imputabilité) ; C multiplie les comptes locaux à oublier ; D n'est pas imputable non plus et contourne tout contrôle.

**10. Preuve d'un départ.** Démonstration chronométrée (E46) : désactivation dans l'annuaire par MR (heure), fermeture des sessions Keycloak (API `logout` de l'utilisateur), puis preuves par service : refus de connexion (événement `LOGIN_ERROR … user_disabled`/liaison refusée dans Loki `audit`), jetons GitLab révoqués (API), revue des accès relancée sans l'accès (E30), `kubectl` refusé au rafraîchissement. Limites à écrire : les **sessions déjà ouvertes** dans les services (Grafana 8 h, GitLab…) tant qu'elles ne sont pas fermées (déconnexion par canal arrière non configurée partout), les **jetons d'accès** en cache (5 min), les **certificats SSH** déjà émis (jusqu'à 16 h, pas de révocation par step-ca dans notre configuration : contrôle par l'annuaire via SSSD/HBAC sur les VMs, qui, lui, refuse la personne désactivée), les accès physiques et VPN.

---

### M24-E33 — Monter de version Keycloak et FreeIPA

**Solution**

*A. Préparer.* Relevé des ruptures de la 26.8 contre notre configuration (RB-245 §1.2) : aucune ne casse le lab ; deux à surveiller (CLI qui se reconnectent plus souvent à cause du plafonnement des jetons de rafraîchissement par l'inactivité ; fournisseur OpenTofu sans compatibilité 26.8 documentée → premier `tofu plan` du jour J relu ligne à ligne). Recherche :

```
admin@adm01:~/src/identite$ grep -rn 'group\b\|groups\s*=\|organization' tofu/ | grep -v '^tofu/portees.tf'
admin@adm01:~$ lab/bin/check 24 05     # avant : wb-checks lit le royaume, les utilisateurs, les clients
```

Essai sur la copie : `envs/m24` `groupes = ["resto"]`, restauration de la sauvegarde de la nuit en 26.7.5 (RB-243 §4, seconde mesure du RTO), puis [`keycloak.yml.essai-E33`](fichiers/M24-E33/ansible/inventories/essai-resto/host_vars/idp-resto/keycloak.yml.essai-E33) et `--tags keycloak`. Journal du premier démarrage (vérifié à la rédaction sur une copie) :

```
admin@idp-resto:~$ sudo journalctl -u keycloak -o cat | jq -r '.message' | grep -E 'Updating database|Migrating|migrated realm|started'
Updating database. Using changelog META-INF/jpa-changelog-master.xml
Migrating older model to 26.8.0
migrated realm medisphere to 26.8.0
migrated realm master to 26.8.0
Keycloak 26.8.1 on JVM (powered by Quarkus 3.40.…) started in …s.
```

La migration prend quelques secondes sur une base de cette taille (≈ 26 changements Liquibase). Sur la copie : découverte, `kid` inchangés, comptes identiques ; le jeton de `wb-checks` lit toujours le royaume, les utilisateurs et les clients (il ne lisait pas les secrets : la rupture de `manage-clients` ne le touche pas). Destruction de la copie.

*B. Le changement.* [`host_vars/idp01/keycloak.yml`](fichiers/M24-E33/ansible/inventories/lab/host_vars/idp01/keycloak.yml) (version et empreinte), RB-245 §2 :

```
admin@idp01:~$ sudo systemctl start identite-sauvegarde.service && sudo cat /var/lib/identite-sauvegarde/dernier-succes
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/identite.yml --limit idp01 --diff
admin@adm01:~/src/identite$ outils/mesure-disponibilite.sh 300 ~/m24/e33/montee.log     # dans un autre terminal
admin@idp01:~$ readlink -f /opt/keycloak; sudo -u postgres psql -d keycloak -XtAc \
>   "SELECT count(*) FROM databasechangelog WHERE filename LIKE '%26.8.0%'"
/opt/keycloak-26.8.1
26
```

Coupure attendue : arrêt + construction déjà faite avant le redémarrage (le rôle construit **avant** de redémarrer) + migration + démarrage : 30 à 60 s.

FreeIPA :

```
[admin@ipa01 ~]$ sudo dnf check-update --refresh | grep -E '^(ipa|389-ds|pki|krb5|sssd)'
[admin@ipa01 ~]$ sudo dnf upgrade 'ipa-*' '389-ds-base*' 'pki-*' 'krb5-*' 'sssd*'
[admin@ipa01 ~]$ sudo tail -n 3 /var/log/ipaupgrade.log
… The ipa-server-upgrade command was successful
[admin@ipa01 ~]$ sudo ipactl status && sudo ipa-healthcheck --failures-only
```

Runbook : [`RB-245`](fichiers/M24-E33/medisphere/docs/securite/identite/runbooks/RB-245-montee-de-version-identite.md).

**Explications**

- **Pourquoi le retour arrière est une restauration.** Keycloak migre le schéma et les données des royaumes au premier démarrage d'une version plus récente ; il n'existe pas de migration inverse. Remettre le lien sur l'ancienne version, c'est lui présenter un schéma qu'il ne connaît pas. D'où la sauvegarde **juste avant**, notée comme point de retour.
- **Pourquoi un essai sur une copie.** Il mesure la durée réelle de la migration sur **nos** données, révèle une rupture qui touche notre configuration, et entraîne la restauration (RB-243) une fois de plus.
- **FreeIPA.** Les correctifs d'une mineure (4.13.x) passent par `dnf` ; le paquet lance `ipa-server-upgrade`, qui met à jour le schéma LDAP, la configuration de Dogtag et des services. Pas de retour arrière de paquets : la sauvegarde complète d'avant et la sauvegarde de VM le sont.

**Alternatives**

- *Montée progressive* avec deux nœuds (E24) et `kc.sh update-compatibility check` : sans coupure si la nouvelle version est déclarée compatible (souvent vrai entre correctives, rarement entre mineures).
- *Nouvelle VM en 26.8.1* restaurée depuis la sauvegarde, puis bascule de HAProxy : retour arrière = rebasculer ; coûte 3 Go le temps de l'opération et une copie de plus des secrets.
- *Image de conteneur* : la version est l'étiquette de l'image ; même contrainte de base.

**Pièges classiques**

- Sauter des versions sans lire **chaque** guide de montée intermédiaire (26.7 → 26.8 ici ; 25 → 26.8 serait plusieurs lectures).
- Oublier que l'empreinte change avec la version : le rôle refuse (bien), on « corrige » en recopiant l'empreinte depuis un tutoriel au lieu de Maven Central (mal).
- Supprimer l'ancienne version le jour même : plus de retour rapide.
- `dnf upgrade` sans filtre sur `ipa01` : une montée de Rocky 10.x vers 10.y dans la même fenêtre, avec ses propres surprises.
- Ne pas relancer `tofu plan` après la montée : un écart du fournisseur avec la nouvelle API passe inaperçu jusqu'au prochain changement.

**En production chez MédiSphère**

Calendrier : correctives de sécurité de Keycloak sous 15 jours (veille des annonces de sécurité), mineures après essai sur copie et une semaine de recul ; Renovate (M17) ouvre la MR de version et d'empreinte ; essai automatique sur une copie restaurée dans un pipeline de recette ; FreeIPA mis à jour avec les correctifs mensuels de Rocky, réplica d'abord quand il existera.

---

### M24-E34 — Ouvrir un nouveau service au SSO en temps limité

**Démarche et solution de référence**

Il n'y a pas de panne à injecter : le chronométré mesure la capacité à dérouler **seul** la chaîne d'E18 sur un service nouveau, dans l'ordre, sans oublier le verrou (la politique réseau). Ordre efficace (≈ 40 min) :

1. *Lire l'existant* (5 min) : l'HTTPRoute `pyrra` et la CNP `pyrra-api-entree` de `plateforme/observabilite/pyrra/` (M21-E26) ; l'Application `oauth2-proxy` d'E18 (deux releases du même chart, valeurs dans `plateforme/identite/oauth2-proxy/`, Secret commun `oauth2-proxy-oidc`) et les redirections du client `oauth2-proxy`.
2. *Keycloak* (8 min) : [redirection exacte](fichiers/M24-E34/identite/tofu/clients-oauth2-proxy.tf.extrait) dans le client partagé ; MR, plan (1 changement), apply.
3. *Instance* (12 min) : [`oauth2-proxy/valeurs-pyrra.yaml`](fichiers/M24-E34/identite/oauth2-proxy/valeurs-pyrra.yaml) dans `plateforme/identite` (copie de `valeurs-hubble.yaml` : nom, hôte, cookie `__Host-oauth2-pyrra`, amont `pyrra-api.supervision.svc:9099`, redirection, groupes `plateforme-admins`, `plateforme`, `support`, `direction`) et une [troisième release](fichiers/M24-E34/gitops/plateforme/oauth2-proxy.yaml.extrait) dans l'Application `oauth2-proxy` de `plateforme/gitops` ; MR, synchronisation, pods prêts. Aucun nouveau secret : le Secret `oauth2-proxy-oidc` d'E18 sert (le cookie porte un nom propre à l'instance et sa signature inclut ce nom ; chaque instance revérifie ses propres groupes).
4. *Fermer la porte* (8 min) : dans `plateforme/observabilite`, [`pyrra-api.yaml`](fichiers/M24-E34/observabilite/pyrra/pyrra-api.yaml) sans HTTPRoute et [`surveillance-et-politiques.yaml`](fichiers/M24-E34/observabilite/pyrra/surveillance-et-politiques.yaml) dont la CNP n'accepte plus que les pods `app.kubernetes.io/instance=oauth2-proxy-pyrra` de l'espace `oauth2-proxy` (et Prometheus). Une seule HTTPRoute pour le nom : sinon la Gateway arbitre entre deux routes concurrentes. Ordre : l'instance **avant** le retrait de l'ancienne route (pas de trou de service), la CNP **en même temps** que le retrait (même MR).
5. *Prouver* (7 min) : requête anonyme → 302 vers `sso…/realms/medisphere/protocol/openid-connect/auth` ; `claire.morel` → Pyrra ; `julien.petit` → 403 ; HTTPRoute unique vers `oauth2-proxy-pyrra`. Journal : [modèle](fichiers/M24-E34/medisphere/docs/socle/journal/AAAA-MM-JJ-M24-E34-pyrra-sso.md).

**Ce qui fait perdre du temps** (retour d'expérience typique) : retrouver où vivent les valeurs d'E18 (`plateforme/identite`, référencées par `$identite` dans l'Application) ; une redirection avec une barre oblique finale qui ne correspond pas à la redirection enregistrée (`invalid redirect_uri`) ; l'étiquette des pods pour la CNP (`app.kubernetes.io/instance` = nom de la release) ; la Gateway qui garde deux routes pour le même nom ; oublier que `--allowed-group` compare des noms **courts** (portée `groupes`, E06).

**Pièges classiques**

- Ajouter OAuth2 Proxy **sans** retirer l'ancienne HTTPRoute ni restreindre la CNP : le SSO se contourne par le chemin d'origine.
- Une redirection joker (`https://*.apps…/oauth2/callback`) « pour aller plus vite » : refusée par la revue (E22) et par le check.
- Un cookie à domaine large (`cookie_domains = [".apps.par1…"]`) ou le **même nom** de cookie que Hubble : une session ouverte pour Hubble serait présentée à Pyrra (la vérification des groupes de l'instance la refuserait encore, mais c'est une défense de moins).
- Un `kubectl apply` pour gagner du temps : Argo CD le défait, et c'est hors règles.

**En production chez MédiSphère**

Un gabarit d'instance (ApplicationSet ou fichier de valeurs paramétré par service : nom, amont, groupes) pour qu'ouvrir un service au SSO soit une MR de cinq lignes ; puis Thanos Query et Alertmanager derrière OAuth2 Proxy (limite acceptée au M21-E29), en gardant un accès en lecture authentifié par jeton pour les sondes du témoin.

**Ce qui reste promis** : la limite écrite au M21-E29 (« proxy d'authentification devant Prometheus, Thanos Query et Alertmanager au M24 ») n'est tenue ici que pour Pyrra ; Thanos Query et Alertmanager sont proposés en « pour aller plus loin » d'E34 et dans le mini-projet (M24-E46), parce que leurs sondes du témoin de `mon01` et le ruler de Loki (qui pousse vers Alertmanager) demandent un accès par jeton qu'OAuth2 Proxy doit laisser passer (`--skip-jwt-bearer-tokens` avec des jetons de Keycloak, ou un chemin interne non publié).
