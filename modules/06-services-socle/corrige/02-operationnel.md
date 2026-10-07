# Module 06 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les fichiers complets sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `fichiers/M06-EXX/ansible/…` = chemins de `plateforme/ansible`, `…/outils/…` = `plateforme/outils`, `…/tofu-modules/…` et `…/infra/…` = les deux projets OpenTofu, `…/medisphere/…` = la documentation. Comme aux modules précédents, on **superpose** les dossiers dans l'ordre (palier 1, puis E10, E11…) ; un fichier d'un exercice plus récent remplace le précédent. Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête), les `*.exemple` des modèles sans valeur réelle, les `*.rendu.json` des configurations **produites** par un rôle (pour lecture, pas à déposer).

**Ce qui a été testé, ce qui ne l'a pas été.**
- *Kea 3.0.4* (paquets ISC) : les configurations produites par les rôles `kea_dhcp4` et `kea_ddns` (versions E16 et E17) passent `kea-dhcp4 -t` et `kea-dhcp-ddns -t` ; `kea-dhcp4` lancé avec la socket HTTP : 401 sans identifiants, réponses en **liste** JSON avec, `lease4-get-all` disponible (hook chargé par son seul nom) ; socket UNIX : réponse en objet JSON ; une interface inexistante fait échouer `-t`.
- *step-ca 0.30.2 et step-cli 0.31.0* : émission ACME en mode autonome (HTTP-01) d'un certificat avec nom **et adresse IP**, chaîne feuille + intermédiaire, renouvellement d'un certificat ACME par `step ca renew` (TLS mutuel, nouveau numéro de série) ; signature d'une clé d'hôte avec le mot de passe du provisioner sur `/dev/stdin`, renouvellement SSHPOP (`step ssh renew`, principaux conservés), certificat d'utilisateur à principaux multiples, refus d'une durée supérieure au maximum ; `sshd` (OpenSSH 9.6) avec `HostCertificate`, `TrustedUserCAKeys`, `AuthorizedPrincipalsFile` : connexion par certificat, journal `ED25519-CERT … ID … (serial …) CA …`, refus « name is not a listed principal » quand le nom utilisé n'est pas un principal.
- *chrony (4.5)* : serveur et client NTS avec un certificat ACME à SAN IP : client accepté avec la racine de test, refusé (« certificate issuer is unknown ») avec une autre ; la directive `leapseclist` est propre à chrony ≥ 4.6 (Debian 13).
- *OpenTofu 1.13.1* : `tofu validate` et `tofu fmt` des modules `vm-debian` v2 et `enregistrement-dns` et de `envs/lab-m06`, avec `bpg/proxmox` 0.115.0 (contrainte des racines portée à `~> 0.116.0` depuis M05-E31 ; schéma non revalidé en 0.116.0), `e-breuninger/netbox` 5.8.0, `mmianl/powerdns` 2.5.0 (schémas lus avec `tofu providers schema`).
- *netbox.netbox 3.23.0* (`nb_inventory`) contre une **imitation** de l'API de NetBox 4.6 : en-tête `Bearer` avec le jeton en dictionnaire, groupes identiques à `proxmox.yml`, renommage de `tags`, besoin de `pytz`.
- *medictl* : 147 tests pytest (dont 33 nouveaux : synchronisations NetBox et DNS, client HTTP, CLI), ruff propre ; *Ansible* : ansible-lint 26.9 en profil `production` sur les six rôles, les playbooks et les scénarios Molecule ; *shell* : ShellCheck 0.11 et `bash -n` sur les scripts et les checks.

**Non rejoués sur un lab réel** : NetBox 4.6 lui-même (filtres GraphQL, fusion d'un `custom_fields` partiel, restrictions d'adresses des jetons), PowerDNS 5.0 (format exact de la sortie de `pdnsutil metadata get`, mises à jour RFC 2136 reçues de Kea), le DDNS de bout en bout, l'arrêt/relance de nginx dans GitLab pendant le défi ACME, les chemins des rôles `netbox` (M06-E04) et `seaweedfs` (M05-E10), les scénarios Molecule sur Proxmox, les serveurs NTS publics. Ils sont signalés « ⚠️ À vérifier sur ta version » : signale tes retours.

---

### M06-E10 — L'API NetBox : jetons, REST et GraphQL

**Solution**

Fichiers : [`essais-api.sh`](fichiers/M06-E10/essais-api.sh) (étapes 4 à 6 rejouables), [`vms-socle.graphql`](fichiers/M06-E10/vms-socle.graphql), [`registre-secrets-extrait.md`](fichiers/M06-E10/registre-secrets-extrait.md).

1. **Jetons v2.** `nbt_<clé>.<jeton>` : la **clé** (la partie qui suit `nbt_`, avant le point) est un identifiant public, stocké en clair, qui permet de retrouver le jeton sans parcourir la table et de le citer dans un ticket sans rien divulguer ; le **jeton** (la partie secrète) n'est jamais stocké : NetBox conserve un HMAC-SHA256 du secret calculé avec un *pepper* tiré de `API_TOKEN_PEPPERS` (`configuration.py`, Vault « critique » depuis M06-E04). Une fuite de la base ne donne donc aucun jeton utilisable, et même un attaquant qui la lit ne peut pas tester des secrets hors ligne sans le *pepper*. Perdre le *pepper* (ou en changer sans garder l'ancien) rend **tous** les jetons v2 invalides : il se sauvegarde avec la configuration (M06-E28) et sa rotation se fait en ajoutant une entrée au dictionnaire (identifiants de *pepper*), pas en remplaçant l'unique valeur.
2. **Compte de service.** *Admin → Authentication → Groups* : `automatisation`. *Permissions* : deux permissions lisibles plutôt qu'une :

   | Permission | Types d'objets | Actions |
   |---|---|---|
   | `automatisation-socle` | `virtualization | virtual machine`, `virtualization | interface`, `virtualization | virtual disk`, `ipam | IP address` | view, add, change, delete |
   | `automatisation-referentiel` | `dcim | site`, `virtualization | cluster`, `ipam | prefix`, `ipam | IP range`, `ipam | role`, `extras | tag` | view |

   Utilisateur `svc-automatisation`, sans mot de passe utilisable (case *active*, mot de passe aléatoire jeté : personne ne se connecte à l'interface avec ce compte), membre du groupe. **Contraintes** : aucune dans le corrigé, parce que tout le périmètre du compte est le socle et ses environnements ; une contrainte (`{"tags__slug__in": ["socle", "env-m06"]}`) empêcherait OpenTofu de **créer** une VM avant de lui avoir posé l'étiquette dans la même requête, et compliquerait le diagnostic pour un gain faible. Elle aurait du sens pour un compte d'équipe (MédiAgenda ne touche que ses VMs).
3. **Jeton.** *Admin → API Tokens → Add* : utilisateur `svc-automatisation`, *Write enabled*, *Expires* à un an, *Allowed IPs* `10.10.10.10/32, 10.10.20.15/32`, description « automatisation du socle (synchro, OpenTofu, DNS) — PLAT-720 ». Le jeton n'est affiché **qu'une fois**. Contrôles :
   ```
   admin@adm01:~$ curl -s -H "Authorization: Bearer $(cat ~/.config/workbook/netbox-auto.token)" $NB/api/authentication-check/ | jq .username
   "svc-automatisation"
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat ~/.config/workbook/netbox-auto.token)" $NB/api/users/users/
   403
   admin@dns01:~$ curl -s -H "Authorization: Bearer $(cat /tmp/jeton)" https://nbx01.par1.medisphere.internal/api/status/ ; rm -f /tmp/jeton
   {"detail": "…"}                         # refus : adresse source hors des « allowed IPs »
   ```
   (Le libellé exact du refus et son code — 403 ou 401 — sont à lire sur ta version.) Les commandes ci-dessus mettent le jeton sur la ligne de commande de `curl`, visible dans `ps` le temps de l'appel : acceptable pour un essai interactif sur `adm01`, pas dans un script. `essais-api.sh` passe l'en-tête par l'entrée standard (`-H @-`).
4. **REST en lecture.**
   ```
   admin@adm01:~$ ./essais-api.sh
   == qui suis-je
   svc-automatisation
   == VMs du socle : nom, statut, IP primaire (fields=)
   gw01      active  10.10.10.1/24
   adm01     active  10.10.10.10/24
   …
   == adresses du préfixe INFRA
   12
   == pagination : limit=2, en suivant next
   adm01
   ca01
   dns01
   …
   ```
   `?brief=true` renvoie la représentation **minimale** de chaque objet (identifiant, URL, nom, description) : parfait pour une liste de choix ; `?fields=name,status,primary_ip4` choisit **exactement** les champs, y compris des objets liés : c'est ce qu'il faut à un outil. La pagination : `limit` (50 par défaut, plafonné par `MAX_PAGE_SIZE`), `next`/`previous` absolus, `count` total ; NetBox 4.6 ajoute `start` (pagination par identifiant, sans le coût d'un `offset` élevé).
5. **Écritures et concurrence.** L'`ETag` d'un objet (`W/"<horodatage de dernière modification>"`) est renvoyé par la lecture de l'objet. Premier `PATCH` avec `If-Match` : **200** ; second avec le **même** `ETag` : **412 Precondition Failed**, car l'objet a changé depuis la lecture. C'est le verrou optimiste de NetBox 4.6 : deux outils (la synchro et un humain) qui lisent puis écrivent ne s'écrasent plus en silence ; celui qui perd relit et recommence. Le journal : `GET /api/core/object-changes/?user_name=svc-automatisation` (création, deux modifications, avec l'`X-Request-ID` de chaque requête), puis `DELETE`.
6. **Jeton des checks** : `GET /api/users/tokens/` avec ce jeton ne renvoie que **ses** jetons (permission par défaut de chaque utilisateur) ; `write_enabled: false`. Un `POST` d'essai aurait prouvé la même chose… en créant l'objet si la protection manquait : on ne teste pas un garde-fou par l'action qu'il doit empêcher.
7. **GraphQL** :
   ```
   admin@adm01:~$ jq -Rs '{query: .}' vms-socle.graphql | curl -s -H "Authorization: Bearer $(cat ~/.config/workbook/netbox-checks.token)" \
       -H 'Content-Type: application/json' --data @- $NB/graphql/ | jq -c '.data.virtual_machine_list[]'
   {"name":"gw01","status":"…","cluster":{"name":"pve01"},"custom_fields":{"vmid":1000},"primary_ip4":{"address":"10.10.10.1/24","dns_name":"gw01.par1.medisphere.internal"}}
   …
   ```
   En REST, `primary_ip4` arrive déjà imbriqué (représentation brève) mais pas son `dns_name` : il faudrait une requête par adresse, ou une seconde liste `ipam/ip-addresses/?virtual_machine_id=…` à recouper, plus la pagination. GraphQL fait tout en une requête et ne renvoie que les champs demandés. Il ne convient pas aux écritures (l'API GraphQL de NetBox est en **lecture seule**), ni aux requêtes très profondes (limite `GRAPHQL_MAX_QUERY_DEPTH` de 4.6), ni quand on a besoin de l'`ETag` d'un objet.

**Explications**

NetBox applique les mêmes permissions à l'interface et à l'API : un jeton ne donne jamais plus que son utilisateur, et peut donner moins (lecture seule, adresses). Les permissions d'objet (*ObjectPermission*) combinent types d'objets, actions et, éventuellement, une contrainte qui est un filtre Django évalué sur chaque objet. La traçabilité vient du journal des changements, attribué au **compte** : un compte de service par usage rend ce journal lisible (« qui a changé cette IP ? la synchro, à 14 h 15 »).

**Alternatives**
- *Un compte par outil* (`svc-synchro`, `svc-opentofu`, `svc-dns`) : journal encore plus précis, révocation ciblée ; trois jetons à faire tourner. Raisonnable dès qu'une équipe tierce consomme l'API.
- *Jetons v1* : encore acceptés en 4.6 (dépréciés, retirés en 5.0), stockés de façon réversible jusqu'en 4.4 : à ne plus créer.
- *pynetbox* (bibliothèque Python officielle) plutôt que `requests` : pagination et objets pratiques, une dépendance de plus ; `medictl` (E11) reste sur `requests`, déjà là.

**Pièges classiques**
- `Authorization: Token nbt_…` : un jeton v2 s'annonce par `Bearer` ; `Token` est le format v1 : refus (403).
- Oublier `allowed_ips` pour la CI : le jeton marche depuis `adm01`… et échoue dans le pipeline (`runner01`), ou l'inverse.
- `?fields=` sur un champ inexistant : NetBox l'ignore en silence (vérifie le résultat, pas seulement le code 200).
- Filtres GraphQL antérieurs à 4.3 (`filters: {tag: "socle"}`) recopiés d'un tutoriel : erreur de schéma. ⚠️ À vérifier sur ta version : dans le schéma 4.6, le statut se filtre par `status: {exact: STATUS_ACTIVE}` (objet de recherche) ; la documentation montre aussi la forme courte `status: STATUS_ACTIVE`.
- Tester les droits d'un jeton par un `POST` « qui doit échouer » : s'il réussit, l'objet existe.

**En production chez MédiSphère**
Un compte de service par consommateur, jetons à durée d'un an avec alerte d'expiration (M06-E29), adresses sources restreintes, *pepper* sauvegardé et documenté, revue trimestrielle des jetons (`/api/users/tokens/` avec un compte d'audit), journal des changements exporté vers la journalisation centrale (M22).

---

### M06-E11 — Synchroniser Proxmox vers NetBox

**Solution** (une solution possible, celle du corrigé)

Fichiers : [`outils/src/medictl/netbox.py`](fichiers/M06-E11/outils/src/medictl/netbox.py) (client NetBox), [`synchro_netbox.py`](fichiers/M06-E11/outils/src/medictl/synchro_netbox.py) (calcul), [`cli_netbox.py`](fichiers/M06-E11/outils/src/medictl/cli_netbox.py) (sous-commande), [`cli.py.extrait`](fichiers/M06-E11/outils/src/medictl/cli.py.extrait), tests [`test_synchro_netbox.py`](fichiers/M06-E11/outils/tests/python/test_synchro_netbox.py), [`test_netbox_http.py`](fichiers/M06-E11/outils/tests/python/test_netbox_http.py), [`test_cli_netbox.py`](fichiers/M06-E11/outils/tests/python/test_cli_netbox.py), unités [`medictl-netbox-sync.service`](fichiers/M06-E11/outils/systemd/medictl-netbox-sync.service) et [`.timer`](fichiers/M06-E11/outils/systemd/medictl-netbox-sync.timer).

**Où ?** Dans `medictl` (`plateforme/outils`) : le client Proxmox, la configuration sûre des secrets, la journalisation masquée, les codes de sortie, la CI et la publication existent déjà (M02). Un script séparé aurait dupliqué tout cela.

**Table de propriété** (dans la MR, reprise par l'ADR-0060) :

| Champ NetBox | Source qui fait foi | Action de la synchro |
|---|---|---|
| existence de la VM | Proxmox | crée si absente ; **signale** si absente de Proxmox (jamais de suppression) |
| `vmid` (champ personnalisé) | Proxmox | écrit |
| statut | Proxmox (`running` → `active`, `stopped` → `offline`, `paused` → `paused`) | écrit |
| vCPU, mémoire, disque | Proxmox (Mio ; disque ignoré si la VM a des disques virtuels NetBox) | écrit |
| démarrage automatique (`start_on_boot`) | Proxmox (`onboot`) | écrit |
| cluster | Proxmox (`pve01`) | écrit |
| nom | NetBox (intention) | renommage **signalé** (même VMID sous un autre nom) |
| étiquettes, rôle | NetBox | posées à la **création** seulement (copie des étiquettes Proxmox existantes dans NetBox), jamais retirées |
| adresses IP, IP primaire | NetBox | écart avec l'agent QEMU **signalé** |

**Fonctionnement.** `planifier()` reçoit `(ressource, configuration, adresses de l'agent)` pour chaque VM de Proxmox et la liste des VMs NetBox du cluster ; il renvoie des `Changement` (`creer`, `modifier` avec **seulement** les champs différents, `signaler`), triés par VMID. `appliquer()` fait un `POST` ou un `PATCH` par changement ; les écarts ne produisent aucune écriture. Exemple :
```
admin@adm01:~$ MEDICTL_ENV_FILE=~/.config/workbook/pve-lecture.env medictl netbox sync --dry-run
[modifier] runner01 (VMID 1007) : vcpus
[écart]    nbx01 : IP primaire NetBox 10.10.20.13, l'agent QEMU voit 10.10.20.13, 172.17.0.1
[creer]    m06-essai (VMID 2061) : cluster, custom_fields, disk, memory, name, start_on_boot, status, tags, vcpus
[écart]    vault01 : présente dans NetBox (socle), absente de Proxmox : décision humaine
simulation : 2 écriture(s) prévue(s), 2 écart(s) signalé(s)
admin@adm01:~$ MEDICTL_ENV_FILE=~/.config/workbook/pve-lecture.env medictl netbox sync
…
NetBox à jour : 1 création(s), 1 modification(s), 2 écart(s) signalé(s)
admin@adm01:~$ MEDICTL_ENV_FILE=~/.config/workbook/pve-lecture.env medictl netbox sync --dry-run
[écart]    …
simulation : 0 écriture(s) prévue(s), 2 écart(s) signalé(s)
```
(Ici, `vault01` est une VM future que quelqu'un a déclarée trop tôt : c'est exactement le genre d'écart qu'on veut voir. Le second écart montre une limite de la comparaison d'adresses : l'agent voit aussi les adresses d'interfaces virtuelles ; le code ne signale que si l'IP primaire est **absente** de la liste.)

**Démonstration.** `medictl vm create m06-essai --vmid 2061 --tags "env-m06" --cores 1` ; passage de la synchro ; `qm set 2061 --cores 2` sur `pve01` ; au passage suivant de la minuterie, NetBox affiche 2 vCPU ; passage suivant : aucune écriture.

**Mise en service.** Les deux unités sur `adm01` (déposées par le rôle Ansible de `adm01`, ou à la main en attendant), minuterie toutes les 15 minutes, `OnFailure=ms-alerte@%n.service` (M02-E26), journal dans `journalctl -u medictl-netbox-sync`. Le jeton Proxmox est celui **en lecture** : la synchronisation n'a aucune raison de pouvoir modifier une VM.

**Explications**

- *Deux clés de rapprochement.* Le nom (unique dans un cluster NetBox) sert à retrouver la VM ; le VMID sert à détecter le renommage. Rapprocher par le seul VMID aurait fait « suivre » un VMID réutilisé après destruction (2061 aujourd'hui `m06-essai`, demain une autre VM) ; par le seul nom, un renommage aurait créé un doublon.
- *Idempotence par différence.* `differences()` compare valeur par valeur (les champs à choix de NetBox arrivent en `{value, label}`, les vCPU en décimal) et ne garde que l'écart : le `PATCH` est minimal, un second passage est vide, et un champ modifié entre-temps par quelqu'un d'autre n'est pas réécrit avec une valeur périmée.
- *`custom_fields` partiel.* Le `PATCH` n'envoie que `{"vmid": …}` : NetBox fusionne avec les autres champs personnalisés de l'objet (⚠️ à vérifier sur ta version : c'est le comportement des sérialiseurs de NetBox 4.x ; si ce n'était pas le cas, il faudrait renvoyer le dictionnaire complet lu juste avant).
- *Pourquoi ne jamais supprimer.* NetBox porte aussi l'intention : une VM peut y exister avant Proxmox (OpenTofu, E13) ou après (VM arrêtée volontairement puis détruite pour être reconstruite). La suppression est une décision humaine, prise sur un écart signalé.
- *Unités.* Proxmox donne `maxmem`/`maxdisk` en octets ; NetBox stocke la mémoire et le disque en Mio (affichés en unités IEC depuis 4.5) : division par 1 048 576.

**Alternatives**
- *Plugin ou outil de découverte* (NetBox Labs *Diode*/*Orb*, plugins communautaires Proxmox) : découverte plus large (disques, interfaces, MAC), modèle de réconciliation par file ; dépendances et cycle de mise à jour en plus, règles de propriété moins visibles.
- *Webhook Proxmox → NetBox* : Proxmox n'émet pas d'évènements de configuration exploitables simplement ; la scrutation reste la voie robuste.
- *Synchro dans la CI* (pipeline planifié de `plateforme/outils`) plutôt qu'une minuterie : historique dans GitLab, exécution sur `runner01` ; le jeton NetBox l'autorise déjà (10.10.20.15). Les deux sont acceptables : le check reconnaît l'un ou l'autre.

**Pièges classiques**
- Écrire `disk` sur une VM qui a des disques virtuels NetBox : 400 (champ calculé). Le code le saute dans ce cas.
- Comparer `vcpus` (`2.0` dans NetBox) à `maxcpu` (`2` dans Proxmox) en chaînes : écart perpétuel, un `PATCH` à chaque passage.
- Étiquette Proxmox qui n'existe pas dans NetBox : la création échoue entière (étiquette inconnue). Le code ne pose que celles qui existent et signale les autres.
- Jeton Proxmox d'**automatisation** au lieu du jeton de lecture : la synchro pourrait, par un bug, modifier une VM.
- `next` de la pagination qui pointe ailleurs (NetBox derrière un mandataire mal réglé) : suivre le lien enverrait le jeton à un autre hôte. Le client refuse.

**En production chez MédiSphère**
Métriques de la synchro (nombre d'écarts, durée) exposées à Prometheus (M21), écarts transformés en tickets s'ils persistent plus de 24 h, synchronisation des disques et interfaces (MAC) pour l'inventaire de conformité, et la même logique pour les hyperviseurs du cluster imbriqué (M09).

---

### M06-E12 — Inventaire Ansible depuis NetBox

**Solution**

Fichiers : [`inventories/lab/netbox.yml`](fichiers/M06-E12/ansible/inventories/lab/netbox.yml), [`collections/requirements.yml`](fichiers/M06-E12/ansible/collections/requirements.yml), [`pyproject.toml.extrait`](fichiers/M06-E12/ansible/pyproject.toml.extrait), [`ansible.cfg.extrait`](fichiers/M06-E12/ansible/ansible.cfg.extrait), [`outils/comparer-inventaires.sh`](fichiers/M06-E12/ansible/outils/comparer-inventaires.sh), [`gitlab-ci.yml.extrait`](fichiers/M06-E12/ansible/gitlab-ci.yml.extrait), [`netbox-ansible.env.exemple`](fichiers/M06-E12/netbox-ansible.env.exemple).

1. **Le piège de l'authentification.** Dans le code du plugin (`_set_authorization`), un `token` **chaîne** produit `Authorization: Token <valeur>` (format v1) ; un `token` **dictionnaire** `{type, value}` produit `Authorization: <Type> <valeur>`. Avec un jeton v2, seule la seconde forme marche : `token: {type: Bearer, value: "{{ lookup('ansible.builtin.env', 'NETBOX_TOKEN') }}"}`. La variable d'environnement `NETBOX_TOKEN`, lue directement par l'option quand `token` est absent, donnerait elle aussi `Token …` : d'où le `lookup` explicite. Autre voie qui marche : `NETBOX_HEADERS='{"Authorization": "Bearer nbt_…"}'` (option `headers`).
2. **Collection et Python.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible-galaxy collection install -r collections/requirements.yml -p collections
   admin@adm01:~/src/ansible$ uv add 'pytz>=2025.2' && uv sync
   ```
   Le plugin importe `pytz` au chargement (option de groupement par fuseau horaire) : sans lui, « pytz must be installed to use this plugin », et avec `unparsed_is_failed = True` (M04-E13), plus d'inventaire du tout. `packaging`, l'autre dépendance, vient avec ansible-core.
3. **`netbox.yml`** (essentiel) :
   ```yaml
   plugin: netbox.netbox.nb_inventory
   api_endpoint: https://nbx01.par1.medisphere.internal
   validate_certs: true
   token: {type: Bearer, value: "{{ lookup('ansible.builtin.env', 'NETBOX_TOKEN') }}"}
   plurals: false
   racks: false
   services: false
   interfaces: false
   query_filters: [{tag: socle}]
   vm_query_filters: [{status: active}]
   rename_variables: [{pattern: "^tags$", repl: netbox_etiquettes}]
   keyed_groups:
     - key: netbox_etiquettes | map('replace', '-', '_') | list
       prefix: ""
       separator: ""
   compose: {vmid: custom_fields.vmid}
   ```
   - `api_endpoint` n'est **pas** évalué par Jinja dans ce plugin (une expression y est prise littéralement : « unknown url type: {{ … »), alors que `token` l'est : l'URL s'écrit en dur, ce qui convient (elle n'est pas secrète).
   - `query_filters` s'applique aux équipements **et** aux VMs ; les filtres de clés différentes se combinent en ET (`?tag=socle&status=active`).
   - `ansible_host` est posé par le plugin depuis l'IP primaire (sans le masque) ; `primary_ip4` aussi.
   - Le plugin crée une variable `tags` (liste des étiquettes) : Ansible avertit à chaque exécution (« Found variable using reserved name 'tags' »). `rename_variables` la renomme **avant** que `keyed_groups` ne la lise.
   ```
   admin@adm01:~/src/ansible$ set -a; . ~/.config/workbook/netbox-ansible.env; set +a
   admin@adm01:~/src/ansible$ uv run ansible-inventory -i inventories/lab/netbox.yml --graph
   @all:
     |--@ungrouped:
     |--@socle:
     |  |--adm01
     |  |--ca01
     |  |--dns01
     …
     |--@role_dns:
     |  |--dns01
     …
   ```
4. **Comparaison.** `comparer-inventaires.sh` réduit chaque inventaire à `{groupes socle/role_* → hôtes triés, hôte → ansible_host}` puis `diff`. Deux détails : ansible-core ≥ 2.19 peut écrire certaines valeurs sous la forme `{"__ansible_unsafe": "…"}` dans `--list` (le script les ramène à leur valeur) ; et un inventaire **vide** est une erreur (code 2), pas une égalité.
   ```
   admin@adm01:~/src/ansible$ outils/comparer-inventaires.sh
   OK : NetBox et Proxmox décrivent le même socle (8 hôtes).
   ```
5. **Inventaire par défaut** : `inventory = inventories/lab/netbox.yml` ; variable CI `NETBOX_TOKEN` (protégée, masquée, cachée) ; job `inventaires` sur `main` et dans le pipeline planifié de dérive (M04-E29) ; `check-socle` tourne désormais sur l'inventaire NetBox.
6. **Expériences.**
   (a) Étiquette `socle` retirée dans NetBox : l'hôte disparaît de `socle` **et** de son `role_…` (le filtre `tag=socle` l'exclut entièrement) ; le garde-fou de `site.yml` (M04-E39, nombre d'hôtes attendu) arrête tout ; la comparaison échoue. Le changement est dans le journal de NetBox, avec son auteur : c'est ce qu'apporte la bascule.
   (b) Jeton faux : 403 sur `/api/status/` → l'inventaire ne se lit pas → `[ERROR]: No inventory was parsed` et code 1, grâce à `unparsed_is_failed`.
   (c) `token: "{{ … }}"` en chaîne : `Authorization: Token nbt_…` → 403, même effet que (b) : c'est le premier diagnostic à faire quand « l'inventaire NetBox ne renvoie plus rien » (M06-E40).

**Explications**

Le plugin interroge NetBox (statut, schéma OpenAPI pour connaître les filtres autorisés, sites, clusters, rôles… puis équipements et VMs), puis applique les options communes des plugins « construits » (`compose`, `keyed_groups`, `strict`). Les `group_vars`/`host_vars` voisins s'appliquent comme pour `proxmox.yml` : rien ne change pour les rôles. NetBox devient la source de **ce qu'on veut configurer** ; Proxmox reste la preuve de **ce qui existe**, et la comparaison en CI attrape les dérives des deux côtés.

**Alternatives**
- *Garder Proxmox par défaut* et NetBox en contrôle : moins de dépendances au démarrage du socle (NetBox est une VM du socle !), mais l'intention ne vient pas de la source relue. Le corrigé choisit NetBox, avec `proxmox.yml` en secours documenté (`-i`).
- *`group_by: [tags]`* au lieu de `keyed_groups` : groupes nommés `tag_socle`, `tag_role-dns` (ou sans préfixe avec `group_names_raw`), tirets à transformer : les `group_vars/role_*` ne s'appliqueraient plus.
- *`config_context`* : des variables portées par NetBox. Puissant, mais elles échappent à la revue Git du projet Ansible ; réservé aux données d'**inventaire** (rack, contact), pas de configuration.

**Pièges classiques**
- `plurals: true` (défaut) : variables en listes d'un élément (`sites: ["PAR1"]`), groupes au pluriel.
- `services: true` (défaut) : une requête de plus, et des erreurs sur certaines versions ; inutile ici.
- L'inventaire NetBox en défaut… alors que NetBox dépend du socle qu'Ansible configure : pour reconstruire `nbx01` lui-même, utiliser `-i inventories/lab/proxmox.yml` (RB-040).
- Cache de schéma : le plugin garde l'OpenAPI dans un fichier temporaire (`netbox_api_dump.json`) ; après une montée de version de NetBox, un filtre nouveau peut être refusé tant que le cache n'est pas renouvelé.

**En production chez MédiSphère**
Cache d'inventaire (`cache: true`, quelques minutes) pour les pipelines, jeton de lecture dédié par contrôleur, et l'inventaire NetBox comme unique point d'entrée des outils d'exploitation (Ansible, supervision, sauvegardes) : une VM absente de NetBox n'est ni configurée, ni supervisée, ni sauvegardée par politique… ce qui rend la synchronisation de E11 et ses écarts indispensables.

---
### M06-E13 — Allouer les adresses depuis NetBox avec OpenTofu

**Solution**

Fichiers : module [`tofu-modules/vm-debian/`](fichiers/M06-E13/tofu-modules/vm-debian/) v2 ([`versions.tf`](fichiers/M06-E13/tofu-modules/vm-debian/versions.tf), [`variables.tf`](fichiers/M06-E13/tofu-modules/vm-debian/variables.tf), [`netbox.tf`](fichiers/M06-E13/tofu-modules/vm-debian/netbox.tf), [`main.tf`](fichiers/M06-E13/tofu-modules/vm-debian/main.tf), [`outputs.tf`](fichiers/M06-E13/tofu-modules/vm-debian/outputs.tf), [`README.md`](fichiers/M06-E13/tofu-modules/vm-debian/README.md)), environnement [`infra/envs/lab-m06/`](fichiers/M06-E13/infra/envs/lab-m06/), [`netbox-tofu.env.exemple`](fichiers/M06-E13/netbox-tofu.env.exemple).

1. **Réserver d'abord.** Une allocation automatique prend « la première adresse libre » : sans réservation, `10.10.20.21` partirait à la première VM d'essai d'INFRA, et `vault01` (M25) n'aurait plus son adresse du PLAN. *IPAM → IP Addresses → Add* (ou `POST /api/ipam/ip-addresses/`) : `10.10.20.21/24` … `10.10.20.23/24`, `10.10.20.30/24`, statut `reserved`, description « vault01 (M25) »… NetBox ne donne jamais une adresse existante, quel que soit son statut.
2. **Le module v2** (`netbox.tf`) : `data "netbox_cluster"` (par nom), `data "netbox_ip_range"` (par une adresse **contenue** : `plage_adresses = "10.10.99.10"` désigne la plage statique de SANDBOX), puis `netbox_virtual_machine` → `netbox_interface` (`eth0`) → `netbox_available_ip_address` (`ip_range_id`, `virtual_machine_interface_id`, `dns_name`) **ou** `netbox_ip_address` si `ipv4_imposee` est renseignée (hôtes du socle) → `netbox_primary_ip`. `main.tf` (la VM Proxmox) reçoit `local.ipv4_cidr` (l'adresse **avec** son masque, telle que NetBox la renvoie) et la passerelle `cidrhost(reseau_prefixe, 1)`. Un bloc `check` vérifie que l'adresse obtenue est bien dans le préfixe annoncé (une erreur de plage ne passe pas en silence).
3. **Partage avec la synchro** : le module écrit l'intention (nom, cluster, statut, vCPU, mémoire, disque, étiquettes, IP) ; la synchronisation de E11 écrit le `vmid`. D'où `lifecycle { ignore_changes = [custom_fields] }` sur `netbox_virtual_machine` : sinon chaque plan proposerait d'effacer le `vmid` écrit par la synchro, et chaque synchro le remettrait. Les autres champs que la synchro écrit (statut, vCPU, mémoire) ont **la même valeur** des deux côtés tant que Proxmox et le code concordent : pas d'oscillation ; s'ils divergent, c'est une dérive que le plan **doit** montrer.
   ⚠️ Le fournisseur envoie les champs personnalisés en chaînes (`custom_fields` est une table de chaînes) : écrire un entier (`vmid`) par ce biais risque un refus de NetBox (« doit être un entier ») ; raison de plus pour laisser `vmid` à la synchro.
4. **Configuration du fournisseur.** URL en clair dans le code (`server_url = var.netbox_url`, non secrète) ; jeton dans une variable `sensitive` et **`ephemeral`** (`netbox_api_token`), fournie par `TF_VAR_netbox_api_token` (fichier `netbox-tofu.env` sur `adm01`, variable protégée et masquée en CI). Pourquoi pas `NETBOX_API_TOKEN` ? Le fournisseur déclare `server_url` et `api_token` **obligatoires** : `tofu validate` échoue s'ils n'ont de valeur ni dans le code ni dans l'environnement… et le job `validate` d'une MR ne reçoit pas les variables protégées :
   ```
   admin@adm01:~/src/infra/envs/lab-m06$ env -u NETBOX_API_TOKEN tofu validate      # avec api_token absent du code
   Error: Missing required argument — The argument "api_token" is required, but no definition was found.
   ```
   Une variable sans valeur, elle, se valide. Et une variable éphémère (OpenTofu ≥ 1.11) n'est écrite ni dans le plan sauvegardé, ni dans l'état.
5. **Publication.** Commit `feat(vm-debian)!: adresse allouée par NetBox` avec `BREAKING CHANGE:` dans le corps (les appelants doivent configurer le fournisseur `netbox`, et `ipv4`/`passerelle` disparaissent) → semantic-release pose **v2.0.0**. Les consommateurs de v1 (socle importé, M05) ne bougent pas tant qu'ils restent sur leur étiquette.
6. **Application.**
   ```
   admin@adm01:~/src/infra/envs/lab-m06$ set -a; . ~/.config/workbook/pve-tofu.env; . ~/.config/workbook/s3-tofu.env; . ~/.config/workbook/netbox-tofu.env; set +a
   admin@adm01:~/src/infra/envs/lab-m06$ tofu init && tofu plan -out plan.bin
     # module.ipam01.netbox_virtual_machine.vm will be created
     # module.ipam01.netbox_interface.eth0 will be created
     # module.ipam01.netbox_available_ip_address.ip[0] will be created
         + ip_address = (known after apply)
     # module.ipam01.netbox_primary_ip.ip will be created
     # module.ipam01.proxmox_virtual_environment_vm.vm will be created
         + initialization { + ip_config { + ipv4 { + address = (known after apply) + gateway = "10.10.99.1" } } }
   Plan: 5 to add, 0 to change, 0 to destroy.
   admin@adm01:~/src/infra/envs/lab-m06$ tofu apply plan.bin
   Outputs:
   ipam01 = { fqdn = "m06-ipam01.par1.medisphere.internal", ipv4 = "10.10.99.10/24", vmid = 2063 }
   root@pve01:~# qm config 2063 | grep ipconfig0
   ipconfig0: gw=10.10.99.1,ip=10.10.99.10/24
   ```
   L'adresse est « known after apply » : NetBox ne la donne qu'au moment de la création ; c'est la raison d'être de la ressource.
7. **Synchronisation** : elle écrit `vmid = 2063` (et rien d'autre). `tofu plan` : *No changes*.
8. **Destruction.** Ordre inverse des dépendances : VM Proxmox, puis IP primaire, adresse, interface, VM NetBox. L'adresse redevient libre (un nouvel `apply` peut reprendre la même ou une autre). Recrée la VM pour E14.

**Explications**

`netbox_available_ip_address` appelle `POST /api/ipam/ip-ranges/<id>/available-ips/` : NetBox calcule l'adresse libre et la crée **dans la même transaction** (verrou sur la plage), ce qui règle le problème des deux personnes qui « prennent la même ». Ensuite l'adresse est une ressource ordinaire de l'état : elle reste stable d'un plan à l'autre et disparaît au `destroy`. Les deux fournisseurs ne se connaissent pas : c'est le graphe des références (`local.ipv4_cidr` utilisé dans la VM Proxmox) qui impose l'ordre.

**Alternatives**
- *Allouer dans le préfixe* (`prefix_id`) plutôt que dans une plage : simple, mais NetBox renverrait .2 ou .3 (réservées VRRP) si personne ne les a déclarées ; les plages encodent la convention du PLAN.
- *Source de données `netbox_available_prefix`/script d'allocation hors OpenTofu* : l'IP devient une entrée calculée avant le plan ; plus de pièces mobiles.
- *Allocation par la VM elle-même (DHCP + réservation)* : adapté aux VMs jetables (sandbox, E16), pas aux hôtes dont le nom doit exister avant le premier démarrage.

**Pièges classiques**
- Oublier la réservation des adresses futures (étape 1).
- `disk_size_mb` d'une VM qui a des disques virtuels dans NetBox : refusé (champ calculé). Le module ne crée pas de disques virtuels.
- Étiquette du module (`etiquettes`) absente de NetBox : la création de la VM NetBox échoue. NetBox est la référence : on crée l'étiquette dans NetBox d'abord.
- Avertissement de version au `plan` (« NetBox version … not supported ») : la table de compatibilité du fournisseur 5.8 s'arrête à NetBox 4.6.5 ; l'avertissement n'est pas bloquant, mais il se lit à chaque montée de version (⚠️ à vérifier sur ta version de NetBox 4.6.x).
- Deux `apply` concurrents qui allouent dans une plage presque pleine : le second échoue (« no available IPs ») ; le verrou d'état (M05) évite le cas sur un même état, pas entre deux environnements.

**En production chez MédiSphère**
Un compte NetBox par environnement OpenTofu (jetons à périmètre limité par une contrainte), plages dédiées par équipe, supervision du taux de remplissage des plages (NetBox `utilization`), et une politique : aucune adresse statique hors NetBox.

---

### M06-E14 — Piloter PowerDNS par API et par OpenTofu

**Solution**

Fichiers : module [`tofu-modules/enregistrement-dns/`](fichiers/M06-E14/tofu-modules/enregistrement-dns/), [`infra/envs/lab-m06/dns.tf`](fichiers/M06-E14/infra/envs/lab-m06/dns.tf), [`providers-powerdns.tf`](fichiers/M06-E14/infra/envs/lab-m06/providers-powerdns.tf), [`versions.tf.extrait`](fichiers/M06-E14/infra/envs/lab-m06/versions.tf.extrait), [`powerdns-api.env.exemple`](fichiers/M06-E14/powerdns-api.env.exemple), [extrait de `group_vars/role_dns/powerdns_auth.yml`](fichiers/M06-E14/ansible/inventories/lab/group_vars/role_dns/powerdns_auth.yml.extrait).

0. **Avant tout écrivain par l'API.** Le rôle `powerdns_auth` (M06-E06) **recharge entièrement** une zone générée (`contenu: fichier`, le défaut) dès que son contenu change : le jour où quelqu'un modifie `dns_hotes`, tout ce qu'OpenTofu (et bientôt Kea, E17) a écrit dans la zone disparaît. Les zones où OpenTofu écrit (`par1.medisphere.internal`, `10.10.in-addr.arpa`) passent donc en `contenu: api` ([extrait](fichiers/M06-E14/ansible/inventories/lab/group_vars/role_dns/powerdns_auth.yml.extrait)), par MR et pipeline, **avant** le premier `apply` : le rôle les crée si elles manquent et n'y touche plus. Leur contenu du palier 1 reste en place, sans propriétaire (E15 le reprend).
1. **Exploration.**
   ```
   admin@adm01:~$ set -a; . ~/.config/workbook/powerdns-api.env; set +a
   admin@adm01:~$ API="$PDNS_SERVER_URL/api/v1/servers/localhost"
   admin@adm01:~$ curl -s -H "X-API-Key: $PDNS_API_KEY" $API/zones | jq -r '.[] | [.name, .kind, .serial] | @tsv'
   10.10.in-addr.arpa.        Native  2026100701
   20.10.in-addr.arpa.        Native  2026100701
   par1.medisphere.internal.  Native  2026100703
   par2.medisphere.internal.  Native  2026100701
   admin@adm01:~$ curl -s -H "X-API-Key: $PDNS_API_KEY" $API/zones/par1.medisphere.internal./metadata | jq -c '.[]'
   {"kind":"SOA-EDIT-API","metadata":["DEFAULT"],"type":"Metadata"}
   ```
   (Type de zone et numéros : ceux que tu as choisis en M06-E06 ; `Master` si la zone a déjà un secondaire, E24.)
2. **Écritures.**
   ```
   admin@adm01:~$ curl -s -X PATCH -H "X-API-Key: $PDNS_API_KEY" -H 'Content-Type: application/json' $API/zones/par1.medisphere.internal. \
       --data '{"rrsets":[{"name":"essai-api.par1.medisphere.internal.","type":"TXT","ttl":60,"changetype":"REPLACE",
                "records":[{"content":"\"premier\"","disabled":false}],"comments":[{"content":"essai M06-E14","account":"moi"}]}]}' -w '%{http_code}\n'
   204
   admin@adm01:~$ dig +short @10.10.20.10 essai-api.par1.medisphere.internal TXT
   "premier"
   ```
   Le numéro de série a augmenté : c'est la métadonnée `SOA-EDIT-API` (posée à `DEFAULT` à la création de la zone par l'API) qui demande à PowerDNS de le recalculer à **chaque** modification faite par l'API ; `DEFAULT` = format date `AAAAMMJJnn`. Sans elle, un secondaire (E24) ne verrait jamais les changements. Ajout d'une seconde valeur sans réécrire la première : `"changetype":"EXTEND"` (nouveau en PowerDNS 5.0, avec `PRUNE` pour retirer une valeur) ; suppression : `"changetype":"DELETE"` sur `name` + `type`.
3. **Pourquoi des *rrsets*.** Le DNS lui-même raisonne par ensemble (nom, classe, type) : une réponse contient tout l'ensemble, le TTL est commun, DNSSEC signe l'ensemble. `REPLACE` remplace donc l'ensemble entier : deux outils qui font chacun un `REPLACE` du même *rrset* s'écrasent, le dernier gagne, sans erreur. D'où la règle de E15 : un *rrset* n'a qu'un propriétaire.
4. **Module `enregistrement-dns`** : A (`zone`, `name` avec point final, `records = [ipv4]`) et PTR (zone inverse déduite des deux premiers octets, nom `reverse(split(".", ipv4))` + `.in-addr.arpa.`), TTL 300, `comments = ["gere-par=opentofu (plateforme/infra)"]`. Module séparé : il nomme aussi ce qui n'est pas une VM (adresse virtuelle, service), `vm-debian` n'exige pas un fournisseur de plus, et chacun évolue à son rythme. Publication : `feat(enregistrement-dns): …` → **v2.1.0** (version mineure du dépôt de modules).
5. **Dans l'environnement** : `module "dns_ipam01"` reçoit `module.ipam01.fqdn` et `module.ipam01.ipv4`. Fournisseur : `server_url` en clair (HTTP, port 8081), `api_key` en variable éphémère (`TF_VAR_pdns_api_key`), même raisonnement qu'en E13.
   ```
   admin@adm01:~$ dig +short @10.10.20.10 m06-ipam01.par1.medisphere.internal ; dig +short @10.10.20.10 -x 10.10.99.10
   10.10.99.10
   m06-ipam01.par1.medisphere.internal.
   admin@adm01:~$ curl -s -H "X-API-Key: $PDNS_API_KEY" $API/zones/par1.medisphere.internal. \
       | jq -c '.rrsets[] | select(.name | startswith("m06-ipam01")) | {name, type, comments}'
   {"name":"m06-ipam01.par1.medisphere.internal.","type":"A","comments":[{"account":"","content":"gere-par=opentofu (plateforme/infra)","modified_at":…}]}
   ```
6. **Dérive.** Après une modification manuelle par l'API, `tofu plan` montre `~ records = ["10.10.99.10"] -> …` sur `powerdns_record.a` : OpenTofu relit le *rrset* et le remet. C'est le comportement voulu pour un enregistrement **qu'il possède**.

**Explications**

L'API de PowerDNS n'a pas de notion d'« enregistrement » isolé : on lit une zone entière (`GET /zones/<zone>`), on la modifie par `PATCH` d'une liste de *rrsets*, appliquée en une transaction. Le fournisseur `mmianl/powerdns` fait exactement cela : une ressource `powerdns_record` = un *rrset* ; son identifiant est `nom:::type`. Les commentaires sont un attribut du *rrset* dans PowerDNS : c'est l'endroit naturel pour dire qui le gère.

**Alternatives**
- *`powerdns_ptr_record`* (ressource dédiée du même fournisseur) : calcule le nom PTR pour toi ; `powerdns_record` en type PTR montre mieux ce qui est écrit.
- *Enregistrements DNS dans NetBox seulement* (E15) : une seule source, mais la VM n'a son nom qu'au passage suivant de la génération (minutes).
- *RFC 2136 (`nsupdate`, fournisseur `hashicorp/dns`)* : indépendant de PowerDNS, signé TSIG ; c'est la voie de Kea (E17), moins pratique pour lire l'état.

**Pièges classiques**
- Oublier le **point final** des noms dans l'API (`name` et contenu des PTR/CNAME) : 422 « not canonical ».
- Contenu TXT sans guillemets (`"records":[{"content":"premier"}]`) : refusé, le contenu d'un TXT est une chaîne DNS.
- Zone sans `SOA-EDIT-API` : modifications invisibles pour les secondaires (numéro inchangé).
- Laisser `par1` en zone générée par Ansible : tout fonctionne… jusqu'au prochain changement de `dns_hotes`, qui recharge la zone et efface sans bruit les enregistrements d'OpenTofu et de Kea.
- `server_url` en `https://` alors que le serveur web de PowerDNS ne parle que HTTP : erreur TLS du fournisseur.
- Mettre la clé dans `terraform.tfvars` « parce qu'il est dans le `.gitignore` » : elle finit dans un plan sauvegardé, un artefact de CI, une sauvegarde de poste.

**En production chez MédiSphère**
L'API de PowerDNS derrière un mandataire TLS avec authentification par certificat client (M06-E30), une clé d'API par consommateur (PowerDNS 5 n'en gère qu'une : le mandataire fait le tri), et une revue des enregistrements « sans propriétaire » chaque trimestre.

---

### M06-E15 — Le DNS généré depuis la source de vérité

**Solution**

Fichiers : [`outils/src/medictl/powerdns.py`](fichiers/M06-E15/outils/src/medictl/powerdns.py) (client), [`synchro_dns.py`](fichiers/M06-E15/outils/src/medictl/synchro_dns.py) (calcul), [`cli_dns.py`](fichiers/M06-E15/outils/src/medictl/cli_dns.py), [`cli.py.extrait`](fichiers/M06-E15/outils/src/medictl/cli.py.extrait), tests [`test_synchro_dns.py`](fichiers/M06-E15/outils/tests/python/test_synchro_dns.py), unités [`medictl-dns-sync.service`](fichiers/M06-E15/outils/systemd/medictl-dns-sync.service) et [`.timer`](fichiers/M06-E15/outils/systemd/medictl-dns-sync.timer).

1. **Plugin ou générateur ?** Un plugin comme `netbox-plugin-dns` fait de NetBox **le** serveur de zones (zones, *rrsets*, SOA modélisés dans NetBox, poussés ensuite vers PowerDNS) : tout le DNS, y compris ce qui n'a pas d'adresse (CNAME, SRV, TXT), devient des objets NetBox ; mais il faut une seconde synchronisation (plugin → PowerDNS), et NetBox devient indispensable pour **modifier** le DNS. Un générateur externe ne publie que ce que NetBox sait déjà (adresses et leur `dns_name`) et laisse PowerDNS seul maître de ses zones : si NetBox tombe, le DNS continue de servir et reste modifiable (API, OpenTofu). Le corrigé choisit le générateur, plus simple et sans dépendance nouvelle ; le plugin devient intéressant quand la gestion du DNS passe à d'autres équipes par l'interface de NetBox.
2. **Propriété.** L'outil marque ses *rrsets* d'un commentaire au **compte** `medictl-dns` ; il crée, met à jour et supprime **uniquement** ceux-là. Un *rrset* d'un autre propriétaire (OpenTofu, commentaire `gere-par=opentofu` ; Kea, aucun commentaire mais un DHCID ; humain) : s'il porte déjà la valeur voulue, rien à faire ; sinon, **conflit signalé** (code de sortie 4), jamais d'écriture. Un *rrset* **sans** propriétaire n'est adopté que si son nom figure dans `--adopter`.
3. **Implémentation** (`synchro_dns.py`) : `voulus()` transforme les adresses actives de NetBox en *rrsets* attendus (A par nom, plusieurs adresses possibles ; un seul PTR par adresse, anomalie signalée si NetBox donne deux noms à une adresse) ; `planifier()` les compare aux zones lues (un `GET` par zone) et produit un `PATCH` par zone (`REPLACE` avec le commentaire de l'outil, `DELETE` de ce qu'il possède et que plus rien ne justifie).
4. **Reprise des enregistrements du palier 1.** Simulation :
   ```
   admin@adm01:~$ medictl dns sync --dry-run
   simulation : 0 changement(s) prévu(s)
   ```
   Rien à faire, et c'est trompeur : pour chaque hôte du socle, le A et le PTR du palier 1 ont **la même valeur** que NetBox, sans propriétaire ; l'outil n'y touche pas (aucune écriture, aucun conflit)… et ne les **suivrait** pas si NetBox changeait l'adresse (ce serait alors un conflit). Pour les prendre en charge, on liste explicitement les noms (relus) :
   ```
   admin@adm01:~$ medictl dns sync --dry-run $(printf -- '--adopter %s.par1.medisphere.internal ' gw01 adm01 dns01 ca01 git01 nbx01 s3-01 runner01)
   [adopter]   gw01.par1.medisphere.internal. A 10.10.10.1
   [adopter]   1.10.10.10.in-addr.arpa. PTR gw01.par1.medisphere.internal.
   …
   admin@adm01:~$ medictl dns sync $(printf -- '--adopter %s.par1.medisphere.internal ' gw01 adm01 dns01 ca01 git01 nbx01 s3-01 runner01)
   DNS à jour : 16 changement(s)
   ```
   L'adoption est un `REPLACE` du même contenu avec le commentaire de l'outil : la réponse DNS ne change à aucun moment. Même chose pour `pbs01.par2.medisphere.internal` (et son PTR dans `20.10.in-addr.arpa`). Dès lors, `par2` et `20.10.in-addr.arpa` passent elles aussi en `contenu: api` et la liste `dns_hotes` de M06-E06 n'a plus de lecteur : elle quitte l'inventaire ([extrait](fichiers/M06-E15/ansible/inventories/lab/group_vars/role_dns/powerdns_auth.yml.extrait)) ; seule la zone parente `medisphere.internal` reste générée par Ansible. Les PTR des **autres** passerelles (`10.10.20.1`, `10.10.99.1`… vers `gw01`, M00-E13) n'ont pas d'adresse dans NetBox (seule `10.10.10.1` est l'IP primaire de `gw01`) : ils restent tels quels, sans propriétaire. Si tu veux qu'ils soient générés aussi, modélise les interfaces de `gw01` et leurs adresses dans NetBox (M06-E05) : c'est l'intérêt de la source de vérité.
5. **Contrôle** : `dig` direct et inverse sur trois hôtes ; second passage : `DNS à jour : 0 changement(s)`.
6. **Expériences.** (a) `dns_name` changé : `[écrire]` du nouveau nom, `[supprimer]` de l'ancien A et `REPLACE` du PTR ; (b) adresse en `reserved` : ses A et PTR **possédés** sont supprimés (seules les adresses actives sont publiées) ; (c) adresse NetBox portant le nom d'un bail DHCP : conflit (le *rrset* appartient à Kea) — c'est le bon comportement : deux sources revendiquent un nom, un humain tranche.
7. **Planification** : minuterie de 5 minutes (TTL 300 s : un changement est visible en 10 minutes au pire), `OnFailure=ms-alerte@`, et un code 4 qui fait échouer l'unité en cas de conflit (alerte). Ordre conseillé : après la synchronisation Proxmox → NetBox (`After=`).

**Explications**

La difficulté n'est pas de générer des enregistrements, c'est de **cohabiter** : SOA/NS (rôle Ansible), OpenTofu, Kea, l'outil et des humains écrivent dans les mêmes zones. Sans règle de propriété, un générateur naïf « remet la zone d'équerre » et efface les baux de Kea toutes les cinq minutes. La règle retenue — un propriétaire par *rrset*, marqué dans PowerDNS, adoption explicite, conflit signalé — se vérifie en lisant la zone, et c'est elle qu'il faut écrire dans l'ADR-0060.

**Alternatives**
- *`netbox-plugin-dns`* (voir étape 1), éventuellement avec son synchroniseur vers PowerDNS.
- *Zones entières générées et chargées par AXFR/fichier* (backend `bind`) : simple et atomique, mais incompatible avec le DDNS de Kea et l'API.
- *Déclencher la génération par un *webhook* NetBox* (*Event Rules*) : publication en secondes ; garder la minuterie comme rattrapage (un webhook perdu).

**Pièges classiques**
- Supprimer « tout ce qui n'est pas dans NetBox » : les baux DHCP, les enregistrements d'OpenTofu, le SOA disparaissent.
- Un `PATCH` par enregistrement : des dizaines d'incréments du numéro de série, et une zone à moitié écrite si l'outil s'arrête au milieu.
- `dns_name` saisi avec une majuscule ou un point final dans NetBox : comparer en minuscules, normaliser le point.
- Oublier les zones inverses : `dig -x` répond par le PTR du palier 1, ou rien.

**En production chez MédiSphère**
Génération déclenchée par évènement + rattrapage périodique, métrique « conflits DNS » en alerte, export quotidien des zones dans le dépôt de documentation (preuve d'audit), et un compte NetBox de lecture propre à l'outil.

---

### M06-E16 — Kea DHCPv4 remplace dnsmasq

**Solution**

Fichiers : rôle [`roles/kea_dhcp4/`](fichiers/M06-E16/ansible/roles/kea_dhcp4/) ([`defaults`](fichiers/M06-E16/ansible/roles/kea_dhcp4/defaults/main.yml), [`tasks/main.yml`](fichiers/M06-E16/ansible/roles/kea_dhcp4/tasks/main.yml), [`tasks/depot.yml`](fichiers/M06-E16/ansible/roles/kea_dhcp4/tasks/depot.yml), [`templates/kea-dhcp4.conf.j2`](fichiers/M06-E16/ansible/roles/kea_dhcp4/templates/kea-dhcp4.conf.j2), [`meta/argument_specs.yml`](fichiers/M06-E16/ansible/roles/kea_dhcp4/meta/argument_specs.yml)), scénario [`molecule/kea_dhcp4/`](fichiers/M06-E16/ansible/molecule/kea_dhcp4/), [`group_vars/role_dns/kea.yml`](fichiers/M06-E16/ansible/inventories/lab/group_vars/role_dns/kea.yml), [`playbooks/dns01.yml`](fichiers/M06-E16/ansible/playbooks/dns01.yml), [`playbooks/retirer-dnsmasq.yml`](fichiers/M06-E16/ansible/playbooks/retirer-dnsmasq.yml), configuration produite [`kea-dhcp4.conf.rendu.json`](fichiers/M06-E16/kea-dhcp4.conf.rendu.json). Le rôle contient déjà les interrupteurs de E17 (`kea_dhcp4_api`, `kea_dhcp4_ddns`), inactifs par défaut.

1. **État des lieux** : `sudo cat /var/lib/misc/dnsmasq.leases`, options dans le fichier généré par le rôle `dnsmasq` (M04-E46). Décision du corrigé : **pas de reprise des baux**. Kea est `authoritative` : il répond NAK à une demande de bail qu'il ne connaît pas, le client repart aussitôt en DISCOVER et obtient un nouveau bail (souvent une autre adresse). Pour des VMs jetables, c'est acceptable ; on peut sinon importer les baux (format CSV de Kea, `lease4-add` par l'API en E17).
2. **Le rôle.** Dépôt : script d'installation du dépôt Cloudsmith → URL de la clé `https://dl.cloudsmith.io/public/isc/kea-3-0/gpg.B16C44CD45514C3C.key`, empreinte `9DA5 70BB 1922 1188 5E4E B280 B16C 44CD 4551 4C3C` (vérifiée par `gpg --show-keys` avant usage, comme le dépôt Smallstep de M06-E02), source deb822 `Suites: trixie`. Paquets `isc-kea-dhcp4=3.0.*` et `isc-kea-hooks=3.0.*` (le joker garde la branche 3.0). Configuration construite comme une **structure** Jinja puis `to_nice_json` : le JSON est valide par construction, quelle que soit la liste de sous-réseaux. `validate: kea-dhcp4 -t %s` : un fichier refusé n'est jamais posé (et `-t` vérifie aussi que les interfaces existent et que les *hooks* se chargent). Contrôle après redémarrage par la socket UNIX (`config-hash-get`, `result` 0) et l'écoute UDP 67.
   Extrait de la configuration produite :
   ```json
   "interfaces-config": { "dhcp-socket-type": "udp", "interfaces": ["ens18"] },
   "control-sockets": [ { "socket-name": "kea4-ctrl-socket", "socket-type": "unix" } ],
   "lease-database": { "lfc-interval": 3600, "name": "kea-leases4.csv", "persist": true, "type": "memfile" },
   "valid-lifetime": 43200, "renew-timer": 21600, "rebind-timer": 37800, "authoritative": true,
   "subnet4": [ { "id": 99, "subnet": "10.10.99.0/24", "pools": [ { "pool": "10.10.99.100 - 10.10.99.199" } ],
                  "option-data": [ { "name": "routers", "data": "10.10.99.1" }, { "name": "ntp-servers", "data": "10.10.99.1" } ] } ]
   ```
   Kea 3.0 refuse un chemin hors de `/var/lib/kea` pour les baux et hors de `/run/kea` pour la socket : d'où des **noms seuls**.
3. **`udp` plutôt que `raw`** : tout arrive relayé (unicast de `gw01` vers 10.10.20.10:67) ; les sockets brutes ne servent qu'aux clients **directement** connectés (source 0.0.0.0). Avec `udp`, Kea n'a besoin que d'une socket ordinaire, et le pare-feu local de `dns01` (M06-E30) s'appliquera ; avec `raw`, Kea contourne nftables (paquets lus au niveau 2), et demande `CAP_NET_RAW`.
4. **Molecule** : instance 2047 ; sous-réseau `192.0.2.0/24` (TEST-NET-1), qui ne correspond ni à l'interface de l'instance ni à aucun relais : Kea ne trouve aucun sous-réseau pour un client de `vsandbox` et ne répond à personne. `verify.yml` : service actif, API (E17) 401 sans identifiants, `config-get` avec, `lease4-get-all` (hook chargé), droits du fichier.
5. **Bascule** (pipeline, `dns01` seul) : `playbooks/retirer-dnsmasq.yml` (copie des baux, arrêt, purge), MR qui retire le rôle `dnsmasq`, son scénario et `group_vars/role_dns/dnsmasq.yml`, puis `dns01.yml` avec `kea_dhcp4`. Interruption mesurée : quelques secondes entre l'arrêt de dnsmasq et le démarrage de Kea (installation des paquets faite avant), sans conséquence pour des clients qui ne renouvellent qu'à T1 (6 h).
6. **Premier échange de `sbx66`** :
   ```
   root@gw01:~# tcpdump -ni ens19.20 -v port 67
   10.10.20.1.67 > 10.10.20.10.67: BOOTP/DHCP, Request from bc:24:11:…, hops 1, … Gateway-IP 10.10.99.1 … DHCP-Message (53): Discover
   10.10.20.10.67 > 10.10.99.1.67: BOOTP/DHCP, Reply, … Your-IP 10.10.99.100 … DHCP-Message (53): Offer, Server-ID (54): 10.10.20.10
   admin@dns01:~$ sudo grep 10.10.99.100 /var/lib/kea/kea-leases4.csv
   10.10.99.100,bc:24:11:…,…,43200,…,99,0,0,sbx66,0,,0
   admin@dns01:~$ printf '{ "command": "lease4-get-all" }' | sudo socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket
   { "result": 2, "text": "'lease4-get-all' command not supported." }
   ```
   La commande demande le *hook* `libdhcp_lease_cmds.so` (paquet `isc-kea-hooks`) : activé en E17. Le relais et le pare-feu n'ont pas changé : même `giaddr`, même serveur.
7. **Renouvellement d'un ancien bail dnsmasq** : à T1, le client envoie un REQUEST **unicast** à 10.10.20.10 (le *server identifier* qu'il connaît, routé par `gw01`) ; Kea, autoritaire, ne connaît pas ce bail : DHCPNAK ; le client recommence (DISCOVER diffusé, relayé). On le voit dans la capture : `REQUEST` unicast de 10.10.99.1xx, `NAK`, puis le cycle complet.

**Explications**

Kea sépare ce que dnsmasq mélangeait : un démon par protocole (`kea-dhcp4`, `kea-dhcp6`, `kea-dhcp-ddns`), une configuration JSON rechargeable par API, des baux dans un fichier CSV (`memfile`, compacté par `kea-lfc` toutes les heures) ou une base. Le choix du sous-réseau pour un paquet relayé se fait par le `giaddr` ; l'identifiant (`id`), obligatoire en Kea 3.0, est stocké dans chaque bail : le changer, c'est rendre orphelins tous les baux du sous-réseau. D'où `id = 99`, le numéro du VLAN, stable et lisible.

**Alternatives**
- *Kea 2.6 de Debian 13* : fin de vie (pas de correctifs de sécurité au-delà de 2026) ; les *hooks* utiles y étaient en partie payants.
- *Base de baux PostgreSQL* (`isc-kea-pgsql`) : utile pour la HA à plusieurs serveurs actifs ou des volumes importants ; `memfile` suffit à un sous-réseau de 100 adresses et à la HA en *hot-standby* (E25).
- *Stork* (console de l'ISC) : supervision et API graphique de Kea ; un service de plus.

**Pièges classiques**
- Laisser le paquet démarrer avec sa configuration d'exemple : sans danger ici (aucune interface déclarée), mais ne jamais laisser tourner ce qu'on n'a pas écrit ; le rôle pose sa configuration avant tout contrôle.
- `"name": "/var/lib/kea/…"` recopié d'une doc 2.x, ou `/tmp/…` d'un tutoriel : refus au démarrage en 3.0 (c'est la panne M06-E36).
- `interfaces: ["*"]` : Kea écoute partout, y compris une future patte sur un autre VLAN.
- Oublier `id` : refus de la configuration.
- dnsmasq encore installé : « Address already in use » sur le port 67, Kea ne démarre pas.

**En production chez MédiSphère**
Deux serveurs en HA (E25), base de baux sauvegardée (M06-E28), supervision du taux d'occupation des plages (`stat-lease4-get`), réservations décrites dans NetBox et poussées par l'API (`host_cmds`), journal légal des baux (*legal log*) si la RSSI l'exige.

---

### M06-E17 — Kea : API de contrôle et mise à jour dynamique du DNS

**Solution**

Fichiers : rôle [`roles/kea_ddns/`](fichiers/M06-E17/ansible/roles/kea_ddns/), [`group_vars/role_dns/kea.yml`](fichiers/M06-E17/ansible/inventories/lab/group_vars/role_dns/kea.yml) (version E17), [`vault-critique.yml.extrait`](fichiers/M06-E17/ansible/inventories/lab/group_vars/role_dns/vault-critique.yml.extrait), [`playbooks/dns01.yml`](fichiers/M06-E17/ansible/playbooks/dns01.yml), extraits du rôle `powerdns_auth` ([`defaults`](fichiers/M06-E17/ansible/roles/powerdns_auth/defaults/main.yml.extrait), [`medisphere.conf.j2`](fichiers/M06-E17/ansible/roles/powerdns_auth/templates/medisphere.conf.j2.extrait), [`host_vars/dns01/powerdns_auth.yml`](fichiers/M06-E17/ansible/inventories/lab/host_vars/dns01/powerdns_auth.yml.extrait) ; état complet du rôle en M06-E24), configurations produites [`kea-dhcp4.conf.rendu.json`](fichiers/M06-E17/kea-dhcp4.conf.rendu.json), [`kea-dhcp-ddns.conf.rendu.json`](fichiers/M06-E17/kea-dhcp-ddns.conf.rendu.json).

1. **API.** `kea_dhcp4_api: true` ajoute à `control-sockets` une socket `http` sur 127.0.0.1:8004 avec `"authentication": {"type": "basic", "realm": "kea-dhcpv4-server", "directory": "/etc/kea", "clients": [{"user": "kea-api", "password-file": "kea-api-mdp"}]}` ; `kea_dhcp4_hooks: [libdhcp_lease_cmds.so]` (nom seul : Kea 3.0 ne charge les *hooks* que depuis son dossier).
   ```
   admin@dns01:~$ curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' -d '{"command":"version-get"}' http://127.0.0.1:8004/
   401
   admin@dns01:~$ printf 'user = "kea-api:%s"\n' "$(sudo cat /etc/kea/kea-api-mdp)" | curl -s -K - -X POST -H 'Content-Type: application/json' \
       -d '{"command":"lease4-get-all"}' http://127.0.0.1:8004/ | jq '.[0] | {result, text}'
   { "result": 0, "text": "1 IPv4 lease(s) found." }
   ```
   La socket HTTP répond par une **liste** (une réponse par service, héritage du *Control Agent*), la socket UNIX par un objet. Mot de passe dans un fichier (640, `root:_kea`) : `kea-dhcp4.conf` peut être lu, sauvegardé, affiché par `config-get` sans divulguer le secret, et la rotation ne touche pas la configuration. L'API n'écoute que sur la boucle locale : l'astreinte s'en sert depuis `dns01` (SSH, certificats E20) ; l'exposer sur 10.10.20.10 en HTTP enverrait le mot de passe en clair sur le VLAN, pour un besoin qui n'existera qu'avec la HA (E25, en HTTPS).
   Le `curl -K -` lit les identifiants sur l'entrée standard : ni le mot de passe ni `-u` n'apparaissent dans `ps`.
2. **PowerDNS.** Rôle `powerdns_auth` : `powerdns_auth_dnsupdate: true` sur `dns01` → `dnsupdate=yes`, `allow-dnsupdate-from=127.0.0.1`. Rôle `kea_ddns`, côté PowerDNS : `pdnsutil tsigkey import ddns-kea hmac-sha256 <secret>` (si la clé manque ou si le secret a changé), puis, pour chaque zone :
   ```
   admin@dns01:~$ sudo -u pdns pdnsutil metadata set par1.medisphere.internal TSIG-ALLOW-DNSUPDATE ddns-kea
   admin@dns01:~$ sudo -u pdns pdnsutil metadata set par1.medisphere.internal ALLOW-DNSUPDATE-FROM 127.0.0.1/32
   ```
   Règle de PowerDNS 5.0 : une mise à jour doit être autorisée **par adresse** (réglage global `allow-dnsupdate-from` **ou** métadonnée `ALLOW-DNSUPDATE-FROM` de la zone), **et**, si la zone a une métadonnée `TSIG-ALLOW-DNSUPDATE`, être signée par l'une de ces clés. Ici : boucle locale ET clé `ddns-kea`. Rappel : sans `dnsupdate=yes`, PowerDNS ignore les mises à jour **sans rien journaliser**.
   (Dans `pdnsutil` 5.0 : `tsigkey import`, `metadata set` ; les anciennes formes `import-tsig-key`, `set-meta` des tutoriels sont celles d'avant 5.0. `pdnsutil` tourne sous le compte `pdns`, propriétaire de la base SQLite, comme dans M06-E06.)
3. **Kea.** `kea-dhcp-ddns.conf` : écoute 127.0.0.1:53001, clé `{"name": "ddns-kea", "algorithm": "HMAC-SHA256", "secret-file": "/etc/kea/tsig-ddns-kea.secret"}` (le secret n'est jamais dans la configuration), domaines `par1.medisphere.internal.` et `10.10.in-addr.arpa.` vers 127.0.0.1:5300. `kea-dhcp4` : `"dhcp-ddns": {"enable-updates": true, …}`, `"ddns-send-updates": false` au niveau global et `true` dans le sous-réseau 99 seulement, `ddns-qualifying-suffix` = `par1.medisphere.internal.`, `ddns-override-client-update: true` (le **serveur** fait les mises à jour, même si le client demande à les faire lui-même : un client de la sandbox n'a ni clé ni droit sur la zone), `ddns-replace-client-name: when-not-present` + `ddns-generated-prefix: dhcp` (un client sans nom reçoit `dhcp-10-10-99-150`), `hostname-char-set` pour assainir les noms.
4. **Ordre** : `powerdns_auth` (la zone accepte les mises à jour), `kea_ddns` (D2 écoute et la clé existe des deux côtés ; le rôle prouve qu'une mise à jour signée passe), **puis** `kea_dhcp4` (qui commence à envoyer). Dans l'autre sens, les premiers baux partiraient vers un D2 absent ou une zone qui les refuse.
5. **Contrôle d'accès** (à la main, avec un nom d'essai) :
   ```
   admin@dns01:~$ k=$(mktemp) && sudo sh -c 'printf "key \"ddns-kea\" { algorithm hmac-sha256; secret \"%s\"; };\n" "$(cat /etc/kea/tsig-ddns-kea.secret)"' > "$k"
   admin@dns01:~$ printf 'server 127.0.0.1 5300\nzone par1.medisphere.internal\nupdate add essai-ddns.par1.medisphere.internal 60 A 10.10.99.250\nsend\n' \
       | nsupdate -k "$k"                                                                             # accepté
   admin@dns01:~$ printf 'server 127.0.0.1 5300\nzone par1.medisphere.internal\nupdate add essai2.par1.medisphere.internal 60 A 10.10.99.251\nsend\n' | nsupdate
   update failed: REFUSED                                                                             # sans clé
   admin@dns01:~$ a=$(mktemp) && printf 'key "autre" { algorithm hmac-sha256; secret "%s"; };\n' "$(openssl rand -base64 32)" > "$a"; … | nsupdate -k "$a"
   ; TSIG error with server: tsig verify failure                                                      # mauvaise clé
   ```
   (Puis supprime `essai-ddns` avec la clé, et efface les deux fichiers de clé : `rm -f "$k" "$a"`.) `mktemp` crée le fichier en 600 ; `printf` est une commande interne du shell : le secret ne passe ni dans `ps` ni dans l'historique (au contraire de `nsupdate -y`, dont l'argument est visible de tous les utilisateurs de l'hôte). Le rôle `kea_ddns` rejoue ce test positif à chaque passage (`nsupdate -k` d'un TXT de sonde avec un fichier de clé temporaire, puis retrait).
6. **`sbx66`** : après `networkctl renew` (ou un redémarrage), le journal de D2 montre l'ajout direct et inverse :
   ```
   admin@dns01:~$ journalctl -u isc-kea-dhcp-ddns-server -n 5 -o cat
   INFO  DHCP_DDNS_ADD_SUCCEEDED DHCP_DDNS Request ID … successfully added the DNS mapping addition for this request: … fqdn: [sbx66.par1.medisphere.internal.] ip_address: [10.10.99.100] …
   admin@adm01:~$ dig +short @10.10.20.10 sbx66.par1.medisphere.internal ; dig +short @10.10.20.10 sbx66.par1.medisphere.internal DHCID
   10.10.99.100
   AAIBy2/AuCccgoJbsaxcQc9TUapptP69lOjxfNuVAA2kjEA=
   ```
   (Libellés indicatifs : lis les tiens.) Le DHCID (RFC 4701) est une empreinte de l'identité du client : il marque le nom comme « posé par le DHCP pour ce client ».
7. **Conflit** : `sbx66` se renomme `dns01`. D2, en mode `check-with-dhcid` (défaut), tente d'ajouter `dns01.par1…` avec la condition « le nom n'existe pas » ; il existe (A du socle, **sans** DHCID) → il tente « le nom existe avec MON DHCID » → refus. Le journal de D2 signale un conflit (`DHCP_DDNS_ADD_FAILED`/`…_CONFLICT`, selon la version) et `dns01` reste à 10.10.20.10. Rassurant : un client de la sandbox ne peut pas détourner un nom du socle, ni le nom d'un autre client.
8. **Destruction** : rien ne se passe tout de suite ; à l'**expiration** du bail (12 h, ou `lease4-del` par l'API), Kea « récupère » le bail et D2 retire A, PTR et DHCID. Un arrêt propre envoie parfois un RELEASE, qui retire les noms aussitôt.

**Explications**

Trois démons, trois responsabilités : `kea-dhcp4` décide des baux ; il envoie des *NameChangeRequests* (JSON sur UDP, local) à `kea-dhcp-ddns`, qui les traduit en mises à jour DNS (RFC 2136) signées TSIG (RFC 8945) ; PowerDNS les applique s'il les autorise. Le mécanisme DHCID (RFC 4703) rend les mises à jour sûres entre clients : seul celui dont l'empreinte est sur le nom peut le modifier ; les enregistrements sans DHCID (le socle) ne sont jamais modifiés par Kea.

**Alternatives**
- *Mises à jour faites par les clients* (option 81) : chaque client aurait besoin d'une clé ; ingérable et dangereux.
- *Sous-zone dédiée* (`dhcp.par1.medisphere.internal`) : isole totalement les noms dynamiques des noms statiques (et des générateurs, E15) ; noms plus longs. Bonne option en production.
- *Control Agent* (`kea-ctrl-agent`) : nécessaire avant 2.7.2, encore livré en 3.0, retiré en 3.2 : ne plus l'introduire.

**Pièges classiques**
- `dnsupdate` resté à `no` : les mises à jour disparaissent sans trace côté PowerDNS ; D2 journalise un échec (REFUSED ou délai).
- Nom de clé différent entre Kea et PowerDNS (`ddns-kea` vs `ddns-kea.`) ou algorithme différent : `tsig verify failure`.
- Zone inverse oubliée dans D2 : le A apparaît, pas le PTR.
- Suffixe sans point final (`ddns-qualifying-suffix`) : noms construits de travers selon les versions.
- Mot de passe de l'API dans `kea-dhcp4.conf` « pour tester » : il part dans les sauvegardes et dans `config-get`.

**En production chez MédiSphère**
API en HTTPS avec certificat client (E25), deux comptes (lecture pour la supervision, écriture pour l'automatisation), rotation annuelle de la clé TSIG avec période de recouvrement (deux clés dans `TSIG-ALLOW-DNSUPDATE`), DDNS dans une sous-zone dédiée, alerte sur les conflits DHCID répétés (signe d'un client mal configuré ou malveillant).

---
### M06-E18 — Certificats automatiques par ACME pour GitLab et NetBox

**Solution**

Fichiers : rôle [`certificats_acme`](fichiers/M06-E18/ansible/roles/certificats_acme/) et son scénario [Molecule](fichiers/M06-E18/ansible/molecule/certificats_acme/), [`host_vars/*/certificats.yml`](fichiers/M06-E18/ansible/inventories/lab/host_vars/) de `git01`, `nbx01`, `s3-01`, [`playbooks/certificats.yml`](fichiers/M06-E18/ansible/playbooks/certificats.yml), [`site.yml.extrait`](fichiers/M06-E18/ansible/playbooks/site.yml.extrait).

1. **Let's Encrypt d'omnibus.** L'intégration (`letsencrypt['enable']`, `letsencrypt['auto_renew']`…) obtient le certificat pendant `gitlab-ctl reconfigure` et le renouvelle par une tâche planifiée qui relance une partie de la reconfiguration. Selon les versions, le modèle de `gitlab.rb` expose aussi des clés d'annuaire ACME (cherche-les : `sudo grep -n acme /opt/gitlab/etc/gitlab.rb.template`), mais la documentation de GitLab ne décrit que Let's Encrypt, et le client embarqué devrait en plus faire confiance à la racine MédiSphère (`/etc/gitlab/trusted-certs`). Décision du corrigé : **ne pas l'utiliser**. Un seul outil pour les trois services (et pour `gw01` en E21), un renouvellement qui ne passe pas par `reconfigure`, la même supervision partout. ⚠️ À vérifier sur ta version : si la documentation de ta version d'omnibus décrit une CA ACME privée, l'option se défend pour GitLab seul.
2. **À la main** (VM d'essai, nom `essai-acme.par1.medisphere.internal` enregistré dans le DNS) :
   ```
   admin@essai:~$ sudo step ca certificate essai-acme.par1.medisphere.internal /tmp/e.crt /tmp/e.key --provisioner acme
   ✔ Provisioner: acme (ACME)
   Using Standalone Mode HTTP challenge to validate essai-acme.par1.medisphere.internal .. done!
   Waiting for Order to be 'ready' for finalization .. done!
   Finalizing Order .. done!
   ✔ Certificate: /tmp/e.crt
   admin@ca01:~$ sudo journalctl -u step-ca --since -5min -o cat | grep -oE '"(path|method)":"[^"]*"' | paste - - | sort -u
   ```
   On y lit, dans l'ordre : `new-order`, l'autorisation, le défi (`challenge`, puis la requête de `ca01` vers `http://essai-acme…/.well-known/acme-challenge/…`), `finalize`, le téléchargement du certificat (libellés indicatifs : lis les tiens). Le défi prouve que le demandeur **contrôle ce qui répond sur le port 80 de l'adresse que le DNS donne pour ce nom**, rien de plus : quiconque peut modifier le DNS (E17 : pourquoi les mises à jour sont si verrouillées) ou détourner le trafic du VLAN peut obtenir un certificat.
   `sudo step ca renew --force /tmp/e.crt /tmp/e.key` : nouveau certificat (nouveau numéro de série, même nom), **sans** défi : le client s'authentifie en TLS mutuel avec le certificat en cours et sa clé. Le renouvellement prouve « je détiens la clé d'un certificat encore valide que tu as émis ». Après expiration, `step-ca` refuse (sauf réglage `allowRenewalAfterExpiry`, que nous n'activons pas) : il faut une nouvelle émission ACME, port 80 compris. C'est pour cela que le rôle vérifie la validité et sait réémettre.
3. **Rôle `certificats_acme`.**
   - `tasks/client.yml` : dépôt Smallstep par les tâches `depot.yml` du rôle `step_ca` (même dépôt et même clé vérifiée que `ca01`), `step-cli` figé (`step_ca_cli_paquet_version`), puis `step ca bootstrap --ca-url … --fingerprint <empreinte de la racine installée par ca_lab>` dans `STEPPATH=/etc/step` : la confiance dans la CA vient de l'empreinte de **notre** racine, pas d'un premier contact accepté à l'aveugle. Ce fichier sert aussi aux rôles `ssh_ca_hote` et `chrony_serveur`.
   - `tasks/main.yml` : pour chaque entrée de `certificats_acme_certificats`, `step certificate verify <crt> --roots <racine MédiSphère> --host <nom>`, plus un contrôle de durée (`certificats_acme_duree_max_h`, 720 h) ; seules les entrées en échec (fichier absent, autre CA, expiré, autre nom, ou certificat de 90 jours émis à la main en M06-E03/E04 — il se vérifie, mais son renouvellement garderait ses 90 jours) passent par `tasks/emettre.yml`. Second passage : rien ne change.
   - `tasks/emettre.yml` : `block` / `always` : `avant_emission` libère le port 80, `step ca certificate … --provisioner acme --san=…` (mode autonome), et `apres_emission` rend le port **même si l'émission échoue**. Puis droits (certificat 644, clé 640 `root:<groupe>`) et rechargement.
   - Modèles `cert-renewer@.service` / `.timer` de Smallstep, adaptés (`STEPPATH` du client, `OnFailure=ms-alerte@%n.service`), et une surcharge par certificat (`cert-renewer@<id>.service.d/medisphere.conf`) : chemins, `chown`/`chmod` après coup (`step` réécrit les fichiers), puis commande de rechargement.
   - Molecule : le `prepare.yml` du scénario `step_ca` fabrique une CA de test sur l'instance (VMID 2048) ; `verify.yml` vérifie le certificat contre la racine de test, les droits de la clé, **force un renouvellement** par le même chemin que la minuterie et compare les numéros de série, puis lance `cert-renewer@essai.service` (sauté par `ExecCondition`, sans échec).
4. **`host_vars`.** `git01` : chemins par défaut d'omnibus (`/etc/gitlab/ssl/git01.par1.medisphere.internal.crt` et `.key`), port 80 libéré par `gitlab-ctl stop nginx` / `start nginx` (à la **première** émission seulement), rechargement `gitlab-ctl hup nginx`. Pas de `reconfigure` : `gitlab.rb` ne change pas (mêmes chemins), seuls les **fichiers** changent, et nginx les relit sur HUP. `nbx01` : nginx du rôle `netbox` (arrêt pendant le défi, `systemctl reload nginx`). `s3-01` : rien sur le port 80, groupe du service, `systemctl try-restart` (SeaweedFS ne relit pas son certificat à chaud). ⚠️ Les chemins de `nbx01` et `s3-01` et le nom du service SeaweedFS sont ceux supposés pour tes rôles de M06-E04 et M05-E10 : adapte. Application : `playbooks/certificats.yml` (`serial: 1`), en CI, `--limit` hôte par hôte au premier passage.
5. **Contrôle.**
   ```
   admin@adm01:~$ openssl s_client -connect git01.par1.medisphere.internal:443 -showcerts </dev/null 2>/dev/null | grep -E '^ *[0-9] s:|^ *i:'
    0 s:CN=git01.par1.medisphere.internal
      i:O=MédiSphère, CN=MédiSphère Intermediate CA
    1 s:O=MédiSphère, CN=MédiSphère Intermediate CA
      i:O=MédiSphère, CN=MédiSphère Root CA
   admin@adm01:~$ curl -sS -o /dev/null -w '%{http_code}\n' https://git01.par1.medisphere.internal/users/sign_in
   200
   ```
   (Libellés des sujets indicatifs.) Deux certificats envoyés : feuille + intermédiaire ; la racine, le client l'a. `openssl x509 -noout -dates` : 30 jours d'écart. Même chose pour `nbx01:443` et `s3-01:8333`.
6. **Renouvellement forcé sur `s3-01`.** `systemctl start cert-renewer@s3` ne fait rien : `ExecCondition=step certificate needs-renewal …` répond « pas encore » (moins des deux tiers de la vie écoulés) et le service est **sauté** (ni succès d'un renouvellement, ni échec). Pour forcer en passant par **toute** la chaîne (droits, redémarrage du service) :
   ```
   admin@s3-01:~$ sudo systemctl edit --runtime cert-renewer@s3.service      # contenu :
   [Service]
   ExecCondition=
   ExecCondition=/bin/true
   admin@s3-01:~$ sudo systemctl start cert-renewer@s3.service && sudo systemctl revert cert-renewer@s3.service
   ```
   (La ligne vide remet à zéro la liste des `ExecCondition` ; `--runtime` écrit sous `/run`, et `revert` retire la surcharge.) Numéro de série changé (`openssl s_client … | openssl x509 -noout -serial`), service redémarré, et `tofu plan` dans `envs/lab` lit toujours son état (le client S3 d'OpenTofu valide le nouveau certificat avec la même racine). Un `step ca renew --force` lancé à la main renouvellerait aussi, mais sans les `chown`/`chmod` ni le redémarrage : c'est exactement ce que la surcharge évite d'oublier.
7. **Ménage des certificats émis à la main.** La CA provisoire a quitté les magasins en M06-E03 ; restent les certificats de 90 jours émis avec le provisioner `admin` (M06-E03 pour `git01` et `s3-01`, M06-E04 pour `nbx01`). Preuve qu'aucun n'est plus en service : `lab/bin/check 06 18` interroge `git01:443`, `nbx01:443`, `s3-01:8333` (émetteur, durée ≤ 30 jours) et `ca01:443` ; à la main, `openssl s_client … | openssl x509 -noout -issuer -dates` sur chacun. Puis : retrait de `vault_netbox_tls_cle` (Vault `critique`, M06-E04) et des certificats `.crt` émis à la main du dépôt Ansible (la clé est désormais générée **sur l'hôte** par `step` et ne le quitte plus), suppression des copies de travail sur `adm01`, lignes correspondantes du registre des secrets passées à « retiré », inventaire des échéances de M06-E03 remplacé par la phrase « renouvellement automatique (cert-renewer@), supervision en M06-E29 ». Les certificats émis à la main restent valides jusqu'à leur échéance : on ne les révoque pas (leurs clés n'ont pas fuité), on les laisse expirer.

**Explications**

ACME découple deux preuves : l'**émission** prouve le contrôle d'un nom (défi), le **renouvellement** prouve la possession de la clé d'un certificat encore valide. D'où l'architecture : une seule fenêtre délicate (le port 80, au premier passage), puis un renouvellement sans secret ni port ouvert, aux deux tiers de la vie (20 jours sur 30), qui laisse dix jours pour réagir à une alerte. Des certificats courts rendent la révocation presque inutile : un certificat volé meurt seul en quelques jours. Le prix : l'automatisation **doit** fonctionner, d'où le test de renouvellement en Molecule et l'alerte `OnFailure`.

**Alternatives**
- *`certbot` ou `lego`* avec `--server <annuaire>` : clients ACME génériques, très répandus ; `certbot` a ses crochets (`--deploy-hook`) et son plugin `--webroot` (pas d'arrêt de nginx). Ils renouvellent par une **nouvelle commande ACME** (défi rejoué), donc le port 80 doit rester accessible en permanence.
- *Défi `--webroot`* avec le nginx de GitLab : pas de coupure, mais configuration nginx supplémentaire (`nginx['custom_gitlab_server_config']`) pour servir `/.well-known/acme-challenge/` en HTTP.
- *TLS-ALPN-01* (pour aller plus loin) : défi sur le port 443 ; utile pour `s3-01` (qui n'a pas de port 80) avec `lego --tls` ; impossible tant que nginx tient le 443 sans module dédié.
- *Provisioner JWK avec jeton* (`step ca token`) : pas de défi du tout, mais un secret à distribuer à chaque hôte.

**Pièges classiques**
- Nom non résolu ou résolu vers une autre adresse par **`ca01`** (pas par l'hôte) : le défi échoue. C'est le DNS vu de `ca01` qui compte.
- Arrêter nginx et ne pas le relancer après un échec : d'où `block` / `always`.
- Clé réécrite par le renouvellement en `600 root:root` : le service, qui tourne sous son utilisateur, ne la lit plus et tombe au **redémarrage suivant**, des jours après.
- Chaîne incomplète (feuille seule) : `curl` sur `adm01` refuse, alors qu'un navigateur qui a l'intermédiaire en cache accepte. `step` écrit la chaîne complète dans le `.crt` ; certains logiciels la veulent en deux fichiers.
- Oublier `--san` pour les noms secondaires : seul le premier nom est certifié.

**En production chez MédiSphère**
Les mêmes certificats courts, le renouvellement surveillé (date d'expiration de chaque certificat présenté, sonde externe à E32/M14), une politique de noms autorisés côté CA (`policy` de step-ca : seulement `*.medisphere.internal`), et la séparation des CA par usage (serveurs, clients, appareils médicaux).

---

### M06-E19 — Certificats SSH d'hôte : fin de la confiance aveugle

**Solution**

Fichiers : rôle [`ssh_ca_hote`](fichiers/M06-E19/ansible/roles/ssh_ca_hote/), scénario [Molecule `ssh_ca`](fichiers/M06-E19/ansible/molecule/ssh_ca/), [`group_vars/all/ssh_ca.yml`](fichiers/M06-E19/ansible/inventories/lab/group_vars/all/ssh_ca.yml), [`inventories/lab/known_hosts`](fichiers/M06-E19/ansible/inventories/lab/known_hosts), [`playbooks/ssh-ca.yml`](fichiers/M06-E19/ansible/playbooks/ssh-ca.yml), [`roles/gitlab_runner/tasks/step.yml`](fichiers/M06-E19/ansible/roles/gitlab_runner/tasks/step.yml), [`known_hosts-adm01.extrait`](fichiers/M06-E19/known_hosts-adm01.extrait).

1. **À la main.**
   ```
   admin@adm01:~$ scp essai:/etc/ssh/ssh_host_ed25519_key.pub /tmp/essai.pub
   admin@adm01:~$ step ssh certificate essai.par1.medisphere.internal /tmp/essai.pub --host --sign \
       --principal essai --principal essai.par1.medisphere.internal --provisioner admin \
       --provisioner-password-file ~/.config/workbook/step-admin.pass
   ✔ Certificate: /tmp/essai-cert.pub
   admin@adm01:~$ scp /tmp/essai-cert.pub essai:/tmp/ && ssh essai 'sudo install -m 644 /tmp/essai-cert.pub /etc/ssh/ssh_host_ed25519_key-cert.pub
       echo "HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub" | sudo tee /etc/ssh/sshd_config.d/02-ssh-ca-hote.conf; sudo sshd -t && sudo systemctl reload ssh'
   admin@adm01:~$ echo "@cert-authority *.par1.medisphere.internal,10.10.* $(step ssh config --host --roots)" > /tmp/kh
   admin@adm01:~$ ssh -o UserKnownHostsFile=/tmp/kh -o GlobalKnownHostsFile=/dev/null essai.par1.medisphere.internal true && echo OK
   OK
   admin@adm01:~$ ssh -o UserKnownHostsFile=/tmp/kh -o GlobalKnownHostsFile=/dev/null 10.10.99.x true
   Certificate invalid: name is not a listed principal
   Host key verification failed.
   ```
   (Sans le motif `10.10.*`, l'adresse ne correspondrait à aucune ligne `@cert-authority` : ssh traiterait l'hôte comme inconnu et proposerait d'accepter sa clé.) Le client compare au certificat le nom **qu'il a utilisé** (`HostName`, ou `HostKeyAlias`). Nos alias de `adm01` (M00-E15) et l'inventaire Ansible (`ansible_host`) joignent les hôtes par **adresse** : les principaux doivent contenir nom court, nom complet **et adresse de connexion**, et le motif `@cert-authority` couvrir les adresses (`10.10.*,10.20.*`). L'autre voie, un `HostKeyAlias` par hôte, devrait être répétée dans `~/.ssh/config`, dans `ansible.cfg` et dans la CI : plus fragile.
2. **Rôle `ssh_ca_hote`.** Lecture de la clé publique (`slurp`), état du certificat actuel (`ssh-keygen -L`, `step ssh needs-renewal --expires-in 75%`), comparaison des principaux et de l'empreinte de la clé certifiée ; si l'un diffère, signature **sur le contrôleur** (`delegate_to: localhost`, `--provisioner-password-file /dev/stdin` + paramètre `stdin` du module `command`, `no_log: true`), dossier temporaire effacé dans un `always`, dépôt du certificat. `02-ssh-ca-hote.conf` ne contient que `HostCertificate` (validé par `sshd -t -f`) : pas de `HostKey`, qui remplacerait la liste par défaut. `/etc/ssh/ssh_known_hosts` reçoit le bloc `@cert-authority` (les hôtes se font confiance entre eux : `runner01` vers le socle, `adm01` vers tous). Minuterie quotidienne `ssh-cert-hote.timer` : `ExecCondition=step ssh needs-renewal`, `step ssh renew --force` (SSHPOP, authentifié par le certificat en cours et la clé d'hôte), `sshd -t`, `reload`. Contrôle final : `ssh-keyscan -c` depuis le contrôleur. Molecule (VMID 2047, partagé) : une CA de test, connexion de vérification avec un `known_hosts` réduit à `@cert-authority`, renouvellement SSHPOP.
3. **Clé de la CA d'hôte versionnée** dans `group_vars/all/ssh_ca.yml`. La récupérer à chaque passage sur `ca01` ferait d'une compromission ou d'une erreur de `ca01` une modification silencieuse de la confiance de tout le parc ; versionnée, elle passe en revue, elle a un historique, et une **rotation** de CA est une MR qui ajoute la nouvelle clé à côté de l'ancienne (période de recouvrement : les deux sont acceptées), puis une seconde MR qui retire l'ancienne. Le rôle accepte donc une **liste**.
4. **Application.** `runner01` reçoit `step-cli` par son rôle (`gitlab_runner/tasks/step.yml`) et la configuration du client (`step ca bootstrap`, même empreinte). Pipeline, `serial: 2`. Contrôle :
   ```
   admin@adm01:~$ ssh-keyscan -c -t ed25519 10.10.20.10 2>/dev/null | awk '{print $1}'
   ssh-ed25519-cert-v01@openssh.com
   admin@adm01:~$ ssh dns01 'ssh-keygen -L -f /etc/ssh/ssh_host_ed25519_key-cert.pub' | sed -n '/Type/p;/Valid/p;/Principals/,/Critical/p'
           Type: ssh-ed25519-cert-v01@openssh.com host certificate
           Valid: from 2026-10-07T09:12:00 to 2026-11-06T09:13:00
           Principals:
                   dns01
                   dns01.par1.medisphere.internal
                   10.10.20.10
   ```
5. **Confiance côté clients.** Ajout de la ligne `@cert-authority *.par1.medisphere.internal,10.10.*,10.20.* <clé>` dans `~/.ssh/known_hosts` de `adm01` ; `inventories/lab/known_hosts` du projet **remplacé** par cette seule ligne : les clés brutes vérifiées en M04-E27 sont retirées, car une clé brute acceptée court-circuite la CA (une régénération ou un remplacement de VM ne serait plus détecté par la CA, mais par une alerte « key changed » que l'on finit toujours par contourner). Puis `ssh-keygen -R <adresse>` et `-R <nom>` pour chaque hôte du socle (pas pour `pve01` ni `pbs01`), et `lab/bin/check 06 19` (qui se connecte avec un `known_hosts` temporaire ne contenant que la ligne de la CA) ; une connexion à chaque alias de `adm01` et un `ansible all -m ping` passent sans question.
6. **Clés régénérées sans re-signature** : `sshd` présente la nouvelle clé, non certifiée (l'ancien certificat ne correspond plus à aucune clé chargée : sshd l'ignore et le signale dans son journal). Côté `adm01`, aucune clé brute connue et pas de certificat valide : en mode interactif, ssh traite l'hôte comme **inconnu** et propose d'accepter la clé (réponds **non**) ; en `BatchMode` (Ansible, CI, `lab/bin/check`), la connexion échoue : `Host key verification failed`. ⚠️ Le libellé exact dépend de ta version d'OpenSSH. Comparé au module 00, une question « yes/no » sur un hôte du socle est désormais **anormale en elle-même** : tout hôte légitime présente un certificat. Pour en faire un refus, ajoute `StrictHostKeyChecking yes` dans le bloc des hôtes du socle de `~/.ssh/config` (les nouveaux hôtes passent par RB-060, donc par la CA). Le remède est connu : rejouer `ssh_ca_hote`, qui voit l'empreinte différente et re-signe.
7. Destruction de la VM d'essai (`qm destroy`, enregistrement DNS d'essai retiré).

**Explications**

Un `known_hosts` classique est une liste de confiances individuelles, établies au premier contact (TOFU) ; un certificat d'hôte remplace N décisions par une seule (« la CA d'hôte MédiSphère »), vérifiable et renouvelable. L'asymétrie est importante : la CA ne voit jamais les clés privées ; elle signe une clé publique pour des principaux et une durée. SSHPOP permet ensuite à l'hôte de se renouveler seul, sans secret : il prouve détenir la clé d'un certificat encore valide. Un certificat expiré (VM éteinte plus de 30 jours) ne peut plus se renouveler ainsi : Ansible le re-signe au passage suivant.

**Alternatives**
- *`HostKeyAlias`* par hôte au lieu des adresses dans les principaux (voir étape 1).
- *Enregistrements SSHFP* dans le DNS (avec DNSSEC, E26) et `VerifyHostKeyDNS yes` : la confiance passe par le DNS signé ; ne gère pas la rotation aussi proprement et dépend de la validation DNSSEC du client.
- *Signature sur l'hôte* avec un jeton à usage unique (`step ca token --ssh --host`) : pas de mot de passe du provisioner sur le contrôleur, mais un jeton par hôte à transporter.
- *`step ssh config --host`* sur chaque hôte : génère la configuration de `sshd` et du client ; nous préférons nos fichiers versionnés.

**Pièges classiques**
- Confondre CA d'**hôte** et CA d'**utilisateur** (deux clés différentes) : `@cert-authority` avec la clé d'utilisateur échoue (c'est la panne de M06-E38).
- `HostKey` dans le fichier de `sshd_config.d` : seules les clés listées sont chargées.
- Oublier l'adresse dans les principaux : Ansible et les alias tombent dès que la clé brute est retirée de `known_hosts`.
- Mot de passe du provisioner passé en argument (visible dans `ps` et dans le journal d'Ansible si `no_log` manque).
- Retirer les clés brutes **avant** d'avoir vérifié la CA côté CI : pipeline rouge pour tous.

**En production chez MédiSphère**
Certificats d'hôte émis à la création de la VM (cloud-init, jeton à usage unique), CA d'hôte et CA d'utilisateur distinctes et sous HSM (M24), clés publiques de CA diffusées par la gestion de configuration et par les postes gérés, alerte quand un certificat d'hôte a moins de sept jours.

---

### M06-E20 — Certificats SSH d'utilisateur et bastion `adm01`

**Solution**

Fichiers : rôle [`ssh_ca_utilisateur`](fichiers/M06-E20/ansible/roles/ssh_ca_utilisateur/), [`group_vars/all/ssh_ca.yml`](fichiers/M06-E20/ansible/inventories/lab/group_vars/all/ssh_ca.yml), [`group_vars/all/main.yml.extrait`](fichiers/M06-E20/ansible/inventories/lab/group_vars/all/main.yml.extrait), [`host_vars/adm01/base.yml.extrait`](fichiers/M06-E20/ansible/inventories/lab/host_vars/adm01/base.yml.extrait), [`host_vars/gw01/pare_feu.yml.extrait`](fichiers/M06-E20/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait), [`playbooks/ssh-ca.yml`](fichiers/M06-E20/ansible/playbooks/ssh-ca.yml), [`outils/bin/ms-ssh-cert`](fichiers/M06-E20/outils/bin/ms-ssh-cert), [`ssh-config-poste.extrait`](fichiers/M06-E20/ssh-config-poste.extrait).

1. **Rôle `ssh_ca_utilisateur`.** `/etc/ssh/ca-utilisateurs.pub` (clé(s) de `step ssh config --roots`, versionnées comme celles d'hôte), `/etc/ssh/principaux/admin` (`admin`, `astreinte`), propriété de root en 644 dans un dossier 755 de root : le compte `admin` ne peut pas s'ajouter de principal. `03-ssh-ca-utilisateur.conf` : `TrustedUserCAKeys` et `AuthorizedPrincipalsFile /etc/ssh/principaux/%u`, validé par `sshd -t -f`. Après rechargement, `sshd -T` doit montrer **ces** valeurs : sshd retient la **première** valeur lue dans l'ordre alphabétique des fichiers, et un fichier plus ancien qui les fixerait gagnerait en silence. Le playbook `ssh-ca.yml` enchaîne `ssh_ca_hote` puis `ssh_ca_utilisateur` ; le scénario Molecule `ssh_ca` porte les deux rôles.
2. **`ms-ssh-cert`.** Signe `~/.ssh/id_ed25519.pub` (identité `admin@adm01`, principal `admin`, 16 h, provisioner `admin`, mot de passe lu dans `~/.config/workbook/step-admin.pass`, mode 600 exigé), écrit `id_ed25519-cert.pub`, puis `ssh-add -d <certificat>` et `ssh-add <clé>` (qui recharge la clé **et** son nouveau certificat). Options `--principal`, `--cle`, `--duree`, `--statut`. Pourquoi retirer l'ancien : l'agent garde le certificat qu'on lui a donné, même expiré ; ssh le présente parmi les identités, sshd le refuse, et chaque refus compte dans `MaxAuthTries 3`. Avec la clé nue, le certificat périmé et une clé de plus, on atteint la limite avant d'essayer le bon : « Too many authentication failures ».
3. **Preuve.**
   ```
   admin@adm01:~$ ms-ssh-cert
   Valid: from 2026-10-07T08:01:00 to 2026-10-08T00:02:00
   admin@adm01:~$ ssh -o ControlPath=none dns01 'sudo journalctl -u ssh -n 20 -o cat | grep Accepted | tail -n 1'
   Accepted publickey for admin from 10.10.10.10 port 51234 ssh2: ED25519-CERT SHA256:… ID admin@adm01 (serial 7313…) CA ECDSA SHA256:…
   ```
   `ID` (*Key ID* du certificat) et `serial` relient la session à une émission précise de `ca01`, dont le journal dit qui l'a demandée. `-o ControlPath=none` : sinon la connexion réutilise une session multiplexée ouverte avant le certificat et ne prouve rien.
4. **Astreinte.**
   ```
   admin@adm01:~$ ssh-keygen -t ed25519 -N '' -C nadia-test -f /tmp/nadia
   admin@adm01:~$ ms-ssh-cert --cle /tmp/nadia.pub --principal astreinte --duree 8h
   admin@adm01:~$ ssh -o ControlPath=none -o IdentitiesOnly=yes -i /tmp/nadia admin@10.10.20.10 id -un
   admin
   admin@adm01:~$ ms-ssh-cert --cle /tmp/nadia.pub --principal stagiaire --duree 1h
   admin@adm01:~$ ssh -o ControlPath=none -o IdentitiesOnly=yes -i /tmp/nadia admin@10.10.20.10 true
   admin@10.10.20.10: Permission denied (publickey).
   ```
   Côté `dns01`, le journal de sshd signale un certificat sans principal autorisé (libellé indicatif : « Certificate does not contain an authorized principal »). `ssh -i /tmp/nadia` charge `/tmp/nadia-cert.pub` à côté de la clé ; `IdentitiesOnly` évite que l'agent présente d'abord ton certificat. Nadia reçoit l'accès sans qu'aucun hôte soit modifié : le principal `astreinte` est déjà dans le fichier du compte. Effacer ensuite `/tmp/nadia*`.
5. **Bris de glace.** `ssh-keygen -t ed25519 -C bris-de-glace@medisphere -f bris-de-glace` **hors de `adm01`** (poste, phrase de passe longue), clé privée rangée chiffrée (coffre de l'équipe, copie papier de la phrase de passe sous enveloppe, emplacement dans le registre des secrets). `ms_cles_admin` (`group_vars/all/main.yml`) : bris de glace avec `from="10.10.10.10,<IP-PVE01>"` et `ansible-ci` (`from="10.10.20.15"`) ; plus aucune clé quotidienne. `host_vars/adm01/base.yml` : en plus, la clé de **ton poste** (point d'entrée du bastion). Application par le pipeline, sessions de secours ouvertes. Preuve :
   ```
   admin@adm01:~$ ssh-add -D ; ssh -o ControlPath=none -o IdentitiesOnly=yes -o CertificateFile=none -i ~/.ssh/id_ed25519 dns01 true
   admin@dns01: Permission denied (publickey).
   admin@adm01:~$ ssh-add ~/.ssh/id_ed25519 && ssh -o ControlPath=none dns01 true && echo "certificat : OK"
   certificat : OK
   ```
6. **Bastion.** Dans `pare_feu_transit` de `gw01`, la règle « VPN d'admin vers MGMT et INFRA » (sans port) devient : VPN → `adm01` en TCP 22, VPN → INFRA en TCP 443 (GitLab, NetBox, `ca01`). Les autres règles du VPN (DNS, `pve01`, PAR2 MGMT) ne changent pas. Ordre : poser la règle, tester depuis le poste **avant** de fermer quoi que ce soit (`ssh adm01`, `ssh -J adm01 dns01`, `curl https://git01…`), puis vérifier que `ssh 10.10.20.10` direct échoue. Poste : `~/.ssh/config` de l'extrait (`ProxyJump adm01`, `CertificateFile`) ; la clé publique du poste est copiée sur `adm01`, signée par `ms-ssh-cert --cle ~/poste.pub`, et `~/poste-cert.pub` rapporté sur le poste en `~/.ssh/id_ed25519-cert.pub`. Le saut final part du poste (la connexion à `dns01` est chiffrée de bout en bout à travers `adm01`) : c'est le poste qui doit présenter le certificat ; `AllowTcpForwarding yes` sur `adm01` (M04-E11) le permet. Mise à jour de `docs/socle/matrice-flux.md`.
7. **Journal.** Aujourd'hui, quiconque connaît le mot de passe du provisioner `admin` (toi, la CI qui en a besoin pour les clés d'hôte) peut signer **n'importe quel** principal, pour **n'importe quelle** identité : l'`ID` du certificat est déclaratif (`admin@adm01` pour tous les certificats émis par `ms-ssh-cert`). Pour un accès nominatif : un provisioner OIDC (module 24, annuaire), qui fixe le principal et l'identité d'après le jeton de la personne, et un provisioner distinct pour l'automatisation. `ca01` en panne un lundi matin : les certificats en cours valent jusqu'au soir ; ensuite plus personne n'en obtient de nouveau ; restent la clé de bris de glace (depuis `adm01` ou la console de `pve01`) et `ansible-ci`. D'où le runbook de `ca01` (E33) et l'objectif de reprise de `ca01` (sauvegarde, E28).

**Explications**

Le certificat d'utilisateur inverse la gestion des accès : au lieu de déposer une clé sur chaque hôte (et de devoir la retirer partout), les hôtes font confiance à une CA et à une liste de **rôles** (principaux) par compte ; donner ou retirer un accès se fait à la CA, et l'accès expire de lui-même. `AuthorizedPrincipalsFile` découple le principal (le rôle : `admin`, `astreinte`) du compte Unix. Le bastion concentre les entrées : un seul hôte exposé au VPN, un seul journal à surveiller, et des certificats demandés depuis une seule machine.

**Alternatives**
- *`AuthorizedPrincipalsCommand`* : principaux calculés (annuaire, NetBox) au lieu d'un fichier.
- *`TrustedUserCAKeys` sans fichier de principaux* : le principal doit être égal au nom du compte ; plus simple, mais on perd le principal `astreinte`.
- *Teleport, Boundary* : bastions et CA intégrés, sessions enregistrées ; plus lourds, à évaluer en M24.
- *`ProxyCommand ssh -W`* : équivalent ancien de `ProxyJump`.

**Pièges classiques**
- Retirer la clé quotidienne avant d'avoir prouvé l'accès par certificat sur **tous** les hôtes : session gardée ouverte et console testée, sinon c'est la console de chaque VM.
- Fichier de principaux modifiable par l'utilisateur, ou dossier non possédé par root : sshd l'ignore (`StrictModes`) ou, pire, l'utilisateur s'ajoute des rôles.
- Certificat périmé resté dans l'agent : « Too many authentication failures ».
- `from=` oublié sur la clé de bris de glace : elle devient une clé personnelle de plus, utilisable de partout.
- Fermer le transit VPN → INFRA sans garder le 443 : plus d'accès à GitLab depuis le poste.

**En production chez MédiSphère**
Certificats nominatifs par OIDC (M24), durée de quelques heures, principaux tirés des groupes de l'annuaire, bastion redondant avec enregistrement de session, alerte sur toute utilisation de la clé de bris de glace (journal de sshd → SIEM), et liste de révocation des clés (`RevokedKeys`) réservée aux certificats d'hôte et aux clés de machine.

---

### M06-E21 — Une heure de référence fiable et authentifiée

**Solution**

Fichiers : rôle [`chrony_serveur`](fichiers/M06-E21/ansible/roles/chrony_serveur/), [`host_vars/gw01/certificats.yml`](fichiers/M06-E21/ansible/inventories/lab/host_vars/gw01/certificats.yml), [`host_vars/gw01/pare_feu.yml.extrait`](fichiers/M06-E21/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait), [`playbooks/gw01-temps.yml`](fichiers/M06-E21/ansible/playbooks/gw01-temps.yml), [`roles/base/…extrait`](fichiers/M06-E21/ansible/roles/base/), [`group_vars/all/temps.yml`](fichiers/M06-E21/ansible/inventories/lab/group_vars/all/temps.yml).

1. **État de départ.** `chronyc tracking` (strate, *System time*, *RMS offset*, *Root dispersion*), `sources -v`, `sourcestats` (dérive, écart type), `authdata` (colonne *Mode* : `-` partout : rien n'est authentifié). Sur `dns01`, une seule source (10.10.20.1), strate de `gw01` + 1. Note les valeurs dans ton journal.
2. **Pare-feu de `gw01`.** Définition `CA01` (10.10.20.11) ; entrée TCP 4460 depuis `$LAB_IFS` (NTS-KE des VLANs du lab), entrée TCP 4460 depuis PAR2 par `wg0` ; entrée TCP 80 depuis `ca01` **seulement** (défi HTTP-01, toutes les adresses de `gw01` puisque `ca01` y entre par `ens19.20`). Pas de règle de sortie (chaîne `output` en `accept`). NTP UDP 123 existait déjà (M00-E31).
3. **Certificat NTS.** `certificats_acme` avec l'id `chrony`, noms : `gw01.par1.medisphere.internal` et **chaque adresse de passerelle** (.1 des VLANs routés), puisque les clients écrivent `server 10.10.x.1 nts` et que chrony vérifie l'adresse contre les SAN de type IP. Fichiers sous `/etc/chrony/nts/` : le profil AppArmor de `chronyd` autorise la lecture sous `/etc/chrony/` (ailleurs, refus même avec les bons droits). Groupe `_chrony`, clé 640 : chronyd lit le certificat **après** avoir abandonné les droits root. Après renouvellement : `systemctl try-restart chrony` (pas de relecture à chaud) ; les clients gardent leurs cookies (`ntsdumpdir`, clés du serveur conservées). Le défi : rien n'écoute sur le port 80 de `gw01`, le serveur autonome de `step` y répond pour chaque adresse.
4. **Rôle `chrony_serveur`.** Gabarit complet de `chrony.conf` (validé par `chronyd -p -f`) : quatre `server … iburst nts`, `minsources 2`, `allow` PAR1 et PAR2, `local stratum 10`, `ntsservercert`/`ntsserverkey`, `ntsdumpdir`, `leapseclist` ; refus de configurer NTS si le certificat manque ; suppression de `conf.d/10-serveur-lab.conf` ; après redémarrage, `chronyc waitsync` puis au moins deux lignes `NTS` dans `authdata`. `playbooks/gw01-temps.yml` : `certificats_acme` puis `chrony_serveur`. Le `chrony.conf` de Debian (pools en clair) est **remplacé**, pas complété : un `pool` en clair laissé à côté rendrait l'authentification inutile.
5. **Rôle `base`.** `base_ntp_nts` (faux par défaut, pour Molecule et les hôtes sans racine MédiSphère) ajoute `nts` aux sources. D'abord `host_vars/adm01` :
   ```
   admin@adm01:~$ chronyc -N authdata
   Name/IP address             Mode KeyID Type KLen Last Atmp  NAK Cook CLen
   =========================================================================
   10.10.10.1                   NTS     1   15  256   12    0    0    8  100
   ```
   (Valeurs indicatives.) Puis `group_vars/all/temps.yml` pour tout le socle, par le pipeline.
6. **Mesures et perte d'Internet.** Après coup : *Root dispersion* comparable, strate inchangée, mais la colonne *Mode* dit `NTS` partout. Perte d'Internet (règle temporaire qui rejette le trafic sortant 4460/123 de `gw01`, ou sources coupées) : `gw01` perd ses sources (`sources` : `?` puis `x`), garde son horloge libre corrigée de la dérive mémorisée et continue de servir le lab en strate 10 (`local stratum 10`) : le lab reste cohérent avec lui-même, sa dispersion augmente. Les clients restent synchronisés sur `gw01` (strate 11). Au retour d'Internet, `gw01` se recale progressivement (pas de saut au-delà de `makestep 1 3`). Retirer la règle temporaire.
7. **Œuf et poule.** Une VM restaurée dont l'horloge a un mois d'avance voit le certificat NTS de `gw01` comme **expiré** (ou pas encore valide dans l'autre sens) ; elle refuse NTS, donc ne peut pas corriger son horloge, donc continue de refuser. `nocerttimecheck <n>` désactive la vérification des dates des certificats pour les `n` premières mises à jour de l'horloge : utile pour des matériels sans horloge sauvegardée, mais il ouvre précisément la fenêtre où un attaquant pourrait présenter un certificat expiré (volé) et imposer une heure fausse. Nos VMs ont une horloge virtuelle tenue par l'hyperviseur (`pve01` est lui-même synchronisé) : la dérive au démarrage est faible ; on garde la vérification, et le runbook de restauration (E28) contrôle l'heure (`chronyc tracking`) avant de remettre une VM en service.

**Explications**

NTS (RFC 8915) ajoute à NTP une phase TLS (NTS-KE, TCP 4460) qui authentifie le serveur par son certificat et établit des clés ; les paquets NTP sont ensuite authentifiés par des cookies que le serveur peut déchiffrer sans garder d'état par client. Sans NTS, n'importe qui sur le chemin peut décaler l'heure, et avec elle la validité de tous nos certificats (30 jours, 16 h). La chaîne devient : sources publiques NTS → `gw01` → clients NTS, authentifiée de bout en bout par des certificats que **nous** émettons pour le dernier maillon.

**Alternatives**
- *Clés symétriques NTP* (`keyfile`, `key` sur chaque `server`) : authentifie aussi, mais une clé partagée à distribuer et à faire tourner sur chaque client.
- *Ne servir que du NTP en clair* dans le lab, NTS seulement vers Internet : protège la référence, pas le dernier saut.
- *PTP* (`ptp4l`) : précision submicroseconde, sans intérêt pour nos besoins et sans authentification simple.
- *Serveurs de temps internes dédiés* avec GPS : en production, en plus des sources NTS publiques.

**Pièges classiques**
- Certificat posé hors de `/etc/chrony` : AppArmor refuse en silence (journal du noyau : `apparmor="DENIED"`).
- Clé illisible par `_chrony` : NTS-KE n'écoute pas (rien sur 4460), le reste de chrony fonctionne : panne discrète.
- Certificat sans les **adresses** : les clients refusent (« certificate … not valid for … ») et, si `nts` est l'unique source, n'ont plus d'heure.
- Pas de redémarrage après renouvellement : chrony sert l'ancien certificat jusqu'à son expiration, puis les clients décrochent tous le même jour.
- Tester NTS avec un dossier `ntsdumpdir` qui contient des cookies d'une configuration précédente : le client semble « authentifié » sans refaire NTS-KE ; tester avec un état vierge.
- `leapseclist` sur une version de chrony antérieure à 4.6 : `chronyd -p` échoue.

**En production chez MédiSphère**
Deux serveurs de temps internes au moins (un par site), sources NTS publiques diversifiées plus un récepteur GPS, supervision du décalage de chaque hôte (alerte au-delà de 100 ms), et l'heure contrôlée dans les runbooks de restauration.

---

### M06-E22 — Revue de la configuration DNS du stagiaire

**Réponses à l'étape 1.** Au démarrage : `pdns` (base SQLite dans `/tmp`, écoute 53 sur toutes les adresses) et le Recursor (écoute 53 sur toutes les adresses) se disputent le port 53 : un seul des deux démarre, selon l'ordre ; le test de Lucas a interrogé celui qui avait gagné. **Interroger** : le monde entier (`allow_from 0.0.0.0/0`). **Modifier** : toute machine de PAR1 et de PAR2, sans clé (`dnsupdate`), plus quiconque a la clé d'API, publiée dans la MR et dans le script, sur une API ouverte à tous. **Lire toute la zone** : tout le monde (`allow-axfr-ips=0.0.0.0/0`).

**Revue** (ordre de traitement ; gravité dans **notre** lab)

| N° | Fichier : ligne(s) | Défaut | Cat. | Gravité | Impact chez nous | Correction |
|---|---|---|---|---|---|---|
| 1 | `pdns.conf` : 21 ; `ajouter-enregistrement.sh` : 6 ; MR | Clé d'API en clair, dans Git (historique) et dans le script | Sécu. | Critique | Quiconque lit le dépôt contrôle la zone (avec 2) ; la clé reste dans l'historique même après correction | Clé **changée** (celle-ci est brûlée) ; valeur dans le Vault (`vault_powerdns_api_cle`), posée par le gabarit du rôle `powerdns_auth`, `pdns.conf` en 640 `root:pdns` ; le script la lit dans une variable d'environnement de la CI (variable masquée et protégée) |
| 2 | `pdns.conf` : 22-25 | API et serveur web sur `0.0.0.0`, `webserver-allow-from=0.0.0.0/0`, en HTTP | Sécu. | Critique | Toute machine joignant `dns21` (lab, VPN, sandbox) peut tenter la clé ; les requêtes passent en clair sur le VLAN | `webserver-address=10.20.20.10`, `webserver-allow-from=127.0.0.1,10.10.20.15` (`runner01`), flux 8081 ouvert sur `gw01` pour `runner01` seulement (comme `dns01`, PLAN §4.8) ; HTTPS par un mandataire si l'API sort du VLAN |
| 3 | `pdns.conf` : 16-17 | `dnsupdate=yes` ouvert à 10.10.0.0/16 et 10.20.0.0/16 **sans** TSIG | Sécu. | Critique | N'importe quelle VM (la sandbox comprise) remplace `pbs01.par2…` par sa propre adresse : détournement des sauvegardes, faux certificats ACME (E18) | `dnsupdate=no` tant qu'aucun DHCP de PAR2 n'en a besoin ; sinon comme `dns01` (E17) : `allow-dnsupdate-from=127.0.0.1`, métadonnées `TSIG-ALLOW-DNSUPDATE` et `ALLOW-DNSUPDATE-FROM` par zone |
| 4 | `recursor.yml` : 2-6 | Résolveur ouvert (`allow_from: 0.0.0.0/0`, écoute sur toutes les interfaces) | Sécu. | Critique | Amplification DDoS et empoisonnement possibles dès qu'une interface est joignable de l'extérieur ; en interne, n'importe quel réseau l'utilise | `listen: [127.0.0.1, 10.20.20.10]`, `allow_from: [127.0.0.0/8, 10.20.0.0/16]` (PAR2 seulement ; PAR1 a `dns01`) |
| 5 | `pdns.conf` : 7-8 et `recursor.yml` : 3-4 | Les deux démons écoutent `0.0.0.0:53` | Fonct. | Élevée | Un seul démarre ; au redémarrage, l'autre peut gagner : résolution Internet ou zone `par2` perdue au hasard | Modèle de `dns01` (PLAN §4.8) : autoritaire sur `127.0.0.1:5300` (et `10.20.20.10:5300` s'il doit être interrogé par un secondaire), récurseur sur 53 |
| 6 | `recursor.yml` : 10-12 | `par2` relayée vers `10.20.20.10` (port 53) = **le récurseur lui-même** | Fonct. | Élevée | Boucle : chaque requête de `par2` se relaie vers elle-même jusqu'à l'échec (SERVFAIL, charge) | `forwarders: [127.0.0.1:5300]` |
| 7 | `pdns.conf` : 12 | `allow-axfr-ips=0.0.0.0/0` | Sécu. | Élevée | Inventaire complet de PAR2 (noms, adresses, iLO) pour quiconque le demande | `allow-axfr-ips=` vide tant qu'il n'y a pas de secondaire ; ensuite l'adresse du secondaire et une clé TSIG (E24) ; `also-notify=10.20.20.11` retiré (adresse attribuée à aucun hôte du PLAN) |
| 8 | `recursor.yml` : 21-22 | `validation: "off"` pour contourner un SERVFAIL | Sécu. | Élevée | Plus aucune protection DNSSEC pour les noms d'Internet (mises à jour, dépôts de paquets) | `validation: validate` et ancres négatives pour `medisphere.internal` et les zones inverses, comme le rôle `powerdns_recursor` de `dns01` (E07). Le SERVFAIL venait de ce que la racine **prouve** que `internal.` n'existe pas |
| 9 | `pdns.conf` : 3 | Base SQLite dans `/tmp` | Fonct. | Élevée | Zone perdue au redémarrage ; de plus l'unité `pdns.service` livrée isole `/tmp` (`PrivateTmp`, à vérifier : `systemctl show pdns -p PrivateTmp`) : `pdnsutil` et le service ne voient pas le même fichier | `/var/lib/powerdns/pdns.sqlite3`, propriété de `pdns`, sauvegardée (E28) |
| 10 | `ajouter-enregistrement.sh` : 9-10 | Aucune gestion d'erreur : `curl -s` sans `-f`, pas de mode strict, « OK » affiché dans tous les cas | Expl. | Élevée | La CI est verte alors que l'API a répondu 401 ou 422 : enregistrement absent, découvert au premier incident | `set -euo pipefail`, `curl -fsS`, code HTTP contrôlé, message d'erreur de l'API affiché, code retour non nul |
| 11 | `ajouter-enregistrement.sh` : 4-5, 9 | Arguments non validés, JSON construit par concaténation, variables non protégées | Sécu./Fonct. | Élevée | Un `NOM` contenant `"` modifie la requête (autre type, autre nom) ; un nom déjà qualifié donne `pbs01.par2….par2…` (ligne 11 de la zone) | Validation (`[[ $NOM =~ ^[a-z0-9-]+$ ]]`, adresse vérifiée), JSON produit par `jq -n --arg`, guillemets partout ; mieux : passer par le module `enregistrement-dns` ou `medictl dns` (E14, E15) |
| 12 | `zone-par2.txt` : 4 | `NS` avec une **adresse** (`10.20.20.10`) | Fonct. | Élevée | Un NS doit être un nom : délégation et notifications cassées, secondaire impossible ; certains résolveurs rejettent la zone | `NS dns21.par2.medisphere.internal.` (le A de `dns21` existe) |
| 13 | `zone-par2.txt` : 6 ; MR | Joker `*.par2.medisphere.internal` | Fonct. | Moyenne | Une faute de frappe répond `dns21` au lieu de NXDOMAIN : erreurs masquées ; avec un domaine de recherche, des noms externes peuvent être capturés ; un défi ACME pour un nom inexistant viserait `dns21` | Supprimer : NXDOMAIN est la bonne réponse à un nom faux |
| 14 | `zone-par2.txt` : 9 | `hp01 CNAME pbs01` : cible non qualifiée (enregistrée comme `pbs01.`, à la racine) | Fonct. | Moyenne | `hp01` ne se résout pas | `hp01 … CNAME pbs01.par2.medisphere.internal.` (ou un A) ; les noms de l'API sont toujours absolus |
| 15 | `zone-par2.txt` : 11 | `pbs01.par2.medisphere.internal.par2.medisphere.internal` | Fonct. | Faible | Enregistrement parasite, symptôme du défaut 11 | Supprimer |
| 16 | `pdns.conf` : 28-29 ; `zone-par2.txt` : 3 ; MR | TTL 60 et SOA `60 60 60 60` (expire = 60 s), numéro de série 1 qui ne bouge pas | Fonct. | Moyenne | Un secondaire **cesserait de servir la zone une minute** après avoir perdu `dns21` : l'inverse du but ; série fixe : les secondaires ne voient pas les changements ; TTL 60 multiplie les requêtes sans gain réel | `default-soa-content=dns21.par2.medisphere.internal. hostmaster.@ 0 10800 3600 1209600 300`, TTL 3600 (300 pour les noms qui bougent), `SOA-EDIT-API` à `DEFAULT` (métadonnée) pour que l'API incrémente la série |
| 17 | `recursor.yml` : 13-15 | `par1` relayée vers `10.10.20.10:5300` ; zones inverses absentes | Fonct. | Moyenne | Le flux PAR2 → `dns01:5300` n'est pas ouvert sur `gw01` (seul 53 l'est) : `par1` en échec depuis PAR2 ; pas de PTR (`10.10.in-addr.arpa`, `20.10.in-addr.arpa`) | Relais **récursif** (`forward_zones_recurse`) de `par1.medisphere.internal` et des zones inverses vers `10.10.20.10` (port 53, flux existant), ou ouverture explicite et documentée de 5300 |
| 18 | `recursor.yml` : 16-19 ; MR | Tout Internet relayé vers 8.8.8.8 | Sécu. | Moyenne | Les requêtes des clients de PAR2 (donc l'activité des postes) partent chez Google : contraire à la politique de souveraineté HDS ; dépendance à un tiers | Récursion complète depuis la racine (pas de `forward_zones_recurse` pour `.`), ou relais vers `dns01` pour une politique unique |
| 19 | `pdns.conf` : 32-33 ; MR | `loglevel=9` et `log-dns-queries=yes` en service | Expl. | Moyenne | Journal saturé (chaque requête), perte de performance, données de navigation conservées sans durée définie | `loglevel=4`, `log-dns-queries=no` ; journal de requêtes activé ponctuellement pour un diagnostic, puis retiré |
| 20 | `ajouter-enregistrement.sh` : 7, 9 | `-k` sur une URL HTTP, clé en argument de `curl` | Sécu. | Faible | `-k` est inutile ici et désactiverait la vérification le jour où l'API passe en HTTPS ; la clé est visible dans `ps` sur `runner01` | Retirer `-k` ; en-tête passé par l'entrée standard (`-H @-`), comme `essais-api.sh` (E10) |
| 21 | `ajouter-enregistrement.sh` : 9 | `REPLACE` aveugle, sans commentaire de propriété | Fonct. | Faible | Écrase un enregistrement existant de même nom (`dns21` compris) sans avertissement ; aucune trace de qui l'a posé | Lire d'abord, refuser d'écraser un enregistrement d'un autre propriétaire, poser un commentaire (règles d'E15) |
| 22 | `zone-par2.txt` : 10 | `ilo` : interface de gestion hors bande publiée sous un nom générique | Expl. | Faible | Nom ambigu (iLO de quel serveur ?), cible privilégiée publiée dans la zone générale | `hp01-ilo.par2…`, ou zone de gestion dédiée |

Défauts mineurs acceptés ici : `gsqlite3-dnssec=yes` sans zone signée (sans effet), l'A sur l'apex `par2.medisphere.internal` (inutile).

**Premier traité : n° 1**, parce qu'il est **déjà** effectif (la clé est dans l'historique de la MR, lisible par tous ceux qui ont accès au projet) et qu'il conditionne les n° 2 et 10 : la corriger dans les fichiers ne suffit pas, il faut changer la clé. Viennent ensuite les ouvertures (3, 4, 2, 7), puis ce qui empêche le service de fonctionner (5, 6, 9, 12).

**Versions corrigées (lignes qui changent)**
```
# pdns.conf
gsqlite3-database=/var/lib/powerdns/pdns.sqlite3
local-address=127.0.0.1:5300, 10.20.20.10:5300
allow-axfr-ips=
dnsupdate=no
api-key=<posé par le gabarit depuis le Vault>
webserver-address=10.20.20.10
webserver-allow-from=127.0.0.1, 10.10.20.15
default-ttl=3600
default-soa-content=dns21.par2.medisphere.internal. hostmaster.@ 0 10800 3600 1209600 300
loglevel=4
log-dns-queries=no
# (supprimés : local-port, also-notify)
```
```yaml
# recursor.yml
incoming:
  listen: [127.0.0.1, 10.20.20.10]
  allow_from: [127.0.0.0/8, 10.20.0.0/16]
recursor:
  forward_zones:
    - {zone: par2.medisphere.internal, forwarders: ["127.0.0.1:5300"]}
  forward_zones_recurse:
    - {zone: par1.medisphere.internal, forwarders: [10.10.20.10]}
    - {zone: 10.10.in-addr.arpa, forwarders: [10.10.20.10]}
    - {zone: 20.10.in-addr.arpa, forwarders: [10.10.20.10]}
dnssec:
  validation: validate
  negative_trustanchors:
    - {name: medisphere.internal, reason: "zone interne non déléguée depuis la racine"}
    - {name: 10.10.in-addr.arpa, reason: "zone inverse privée"}
    - {name: 20.10.in-addr.arpa, reason: "zone inverse privée"}
```
(La zone inverse de PAR2, `20.10.in-addr.arpa`, figure dans le PLAN sur `dns01` ; si `dns21` doit la servir, elle passe en `forward_zones` vers `127.0.0.1:5300`.)

**Question de fond.** Autoritaire et récurseur sur la même VM, séparés par le port (comme `dns01`), c'est défendable pour un petit site : une VM de moins, et la séparation des rôles est conservée (deux démons, deux configurations, l'autoritaire n'écoute pas sur 53). Les risques sont ailleurs : PAR2 n'aurait **qu'une** source de vérité pour `par2`, modifiable localement, divergente de celle de PAR1 (deux bases, deux API, deux automatisations), et sa perte ferait disparaître les noms de PAR2 pour tout le monde. La réplication par transfert de zone (E24) apporte l'inverse : un seul primaire (`dns01`), des secondaires en lecture seule qui servent la zone même si le lien entre sites tombe (jusqu'à l'*expire* du SOA, d'où l'importance du n° 16), une seule automatisation, et des transferts authentifiés par TSIG. Pour PAR2, un récurseur local plus un **secondaire** de `par1` et `par2` est la bonne cible.

**Conseils à Lucas.** Teste dans les conditions de la cible (adresse, pare-feu, autres services de la VM) : « ça marche sur ma VM » n'a rien prouvé pour `dns21`. Teste aussi ce qui doit **échouer** : une requête depuis un réseau non autorisé, une mise à jour sans clé, un AXFR depuis ton poste. Quand tu désactives une sécurité pour faire passer un test (DNSSEC), cherche pourquoi elle échouait : c'est souvent là qu'est le vrai défaut.

**Grille d'auto-évaluation** (Karim relit comme une MR ; 2 points par ligne, 20 au total, acceptable à 14)

| Critère | 0 | 1 | 2 |
|---|---|---|---|
| Défauts critiques (1 à 4) | un oublié | tous, impact vague | tous, impact concret chez nous |
| Défauts élevés (5 à 12) | moins de 5 | 5 à 7 | les 8 |
| Boucle du n° 6 expliquée (qui écoute où) | non | constatée | expliquée et corrigée |
| Le n° 1 traité par un **changement** de clé | non | clé déplacée | clé changée et déplacée |
| Corrections précises (option, valeur) | rares | la plupart | toutes |
| Défauts de la zone (12 à 16) | moins de 2 | 2 à 3 | 4 ou 5 |
| Défauts du script (10, 11, 20, 21) | moins de 2 | 2 à 3 | 4 |
| Ordre de traitement justifié | absent | sans justification | justifié |
| Question de fond | absente | avis | argumentée (secondaire, TSIG, panne d'un site) |
| Ton de la revue | jugement de la personne | neutre | utile : explique et propose |

---

### M06-E23 — Runbook : ajouter un hôte au socle

**Solution**

Fichier : [`RB-060-ajouter-un-hote-au-socle.md`](fichiers/M06-E23/medisphere/docs/socle/runbooks/RB-060-ajouter-un-hote-au-socle.md). Points structurants :
- **Ordre des dépendances** (section 3 du runbook) : adresse dans NetBox → VM et enregistrements DNS par OpenTofu (modules `vm-debian` v2 et `enregistrement-dns`) → contrôles immédiats (VM démarrée, `dig` direct et inverse) → NetBox à jour (synchronisation) → inventaire Ansible (étiquettes et rôle) → identité SSH de l'hôte (avant toute configuration : sinon Ansible ne fait pas confiance à l'hôte) → configuration par le pipeline → certificat TLS (le nom doit résoudre **depuis `ca01`**) → flux réseau → sauvegardes et supervision → documentation.
- **Chaque étape** a sa commande, son résultat attendu et quoi faire sinon ; le contrôle final se connecte sans multiplexage (certificats d'hôte et d'utilisateur vus par `sshd -T`) et exige que `medictl netbox sync --dry-run` et `medictl dns sync --dry-run` ne voient aucun écart pour l'hôte.
- **Retour arrière dans l'ordre inverse**, en ne défaisant que ce qui a été fait : revert de la MR de pare-feu, **révocation** du certificat TLS (`step ca revoke`), certificat SSH d'hôte laissé à expirer (révoqué si l'hôte est compromis), revert de la MR de `plateforme/infra` (OpenTofu détruit la VM, puis rend l'adresse et retire A et PTR), adresse remise en `reserved` ou supprimée. Contrôle : `dig` en NXDOMAIN, aucune adresse `active` pour l'hôte dans NetBox, synchronisation sans écart, `qm status` inexistant.
- **Ce qui disparaît** (en-tête du runbook) : `host-record` de dnsmasq (retiré en E16), ligne de `docs/socle/inventaire.md` (NetBox fait foi), alias SSH ajouté à la main, empreinte SSH acceptée à l'aveugle.
- **Pièges connus** : adresse réservée à la main puis imposée par le module (doublon), étiquette de rôle absente de NetBox (hôte configuré à moitié), adresse absente des principaux SSH, défi ACME avant le DNS, port 80 occupé, ancienne clé brute dans `known_hosts` après une reconstruction, adresse fixe dans une plage DHCP de Kea.

**Grille d'auto-évaluation** (Nadia joue le runbook ; 2 points par ligne, 20 au total, acceptable à 14, aucun 0 sur les lignes marquées *)

| Critère | 0 | 1 | 2 |
|---|---|---|---|
| Champ d'application (création, reconstruction, hors champ) * | absent | partiel | complet |
| Prérequis (accès, secrets, outils, droits) | absents | liste | liste vérifiable (commande de contrôle) |
| Dépendances explicites (schéma ou liste) * | absentes | implicites | explicites et respectées par les étapes |
| Chaque étape a son contrôle * | moins de la moitié | la plupart | toutes |
| Chaque étape dit quoi faire en cas d'échec | jamais | parfois | toujours |
| Identité SSH avant configuration, nom avant certificat | non | l'un des deux | les deux |
| Flux, sauvegardes, supervision | oubliés | mentionnés | étapes contrôlées |
| Retour arrière sans orphelin (adresse, nom, certificat, règle) * | absent | partiel | complet, ordre inverse |
| Gestes anciens retirés (dnsmasq, `inventaire.md`, TOFU SSH) | non | en partie | tous, explicitement |
| Joué sur une VM d'essai et relu par MR | non | joué | joué, corrigé, relu |
