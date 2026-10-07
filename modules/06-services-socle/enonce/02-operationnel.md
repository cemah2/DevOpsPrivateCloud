# Module 06 — Palier 2 : Opérationnel

Le palier 1 a posé les briques : une PKI à deux niveaux sur `ca01`, NetBox sur `nbx01` avec le socle modélisé, PowerDNS sur `dns01` à la place du DNS de dnsmasq. Chaque brique marche, mais aucune ne parle encore aux autres : NetBox décrit le socle sans savoir ce qui tourne vraiment, OpenTofu reçoit ses adresses IP d'une variable, les noms DNS s'écrivent à la main, dnsmasq distribue toujours les baux du VLAN 99, les certificats de GitLab, de `s3-01` et de NetBox sont émis à la main pour 90 jours (la CA provisoire, elle, a disparu en M06-E03) et chaque nouvelle VM t'oblige à accepter une empreinte SSH « à l'aveugle ». Ce palier relie les services entre eux et à l'automatisation : NetBox devient la source des adresses, des noms et de l'inventaire ; Kea remplace dnsmasq et publie ses baux dans le DNS ; step-ca délivre et renouvelle seul les certificats TLS et SSH ; `gw01` distribue une heure authentifiée. Tu termines par le runbook qui enchaîne tout cela pour ajouter un hôte au socle, sans geste manuel.

> **Rappels du module** (introduction) : toute nouvelle VM passe par OpenTofu, toute configuration par un rôle Ansible testé par Molecule et appliqué par le pipeline de `plateforme/ansible`, tout nouveau flux par `host_vars/gw01/pare_feu.yml`. Les vérifications se lancent depuis `adm01`. Les VMs d'essai du module sont dans la plage 2060-2069 (pool `lab`, étiquette `env-m06`).

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| NetBox | `https://nbx01.par1.medisphere.internal`, NetBox 4.6, cluster de virtualisation `pve01`, champ personnalisé `vmid` (entier) sur les VMs, étiquettes `socle`, `role-…`, `env-m06` (M06-E05) |
| Compte d'automatisation NetBox (E10) | utilisateur `svc-automatisation`, groupe `automatisation` ; jeton v2 d'écriture dans `~/.config/workbook/netbox-auto.token` ; jeton v2 de lecture pour Ansible dans `~/.config/workbook/netbox-ansible.env` (E12) |
| API PowerDNS | `http://dns01.par1.medisphere.internal:8081/api/v1/servers/localhost`, clé `vault_powerdns_api_cle` (Vault « critique », M06-E06), copie de travail dans `~/.config/workbook/powerdns-api.env` (E14) |
| step-ca | `https://ca01.par1.medisphere.internal`, provisioners `admin` (JWK, mot de passe dans `~/.config/workbook/step-admin.pass` et `vault_step_ca_mot_de_passe_admin`), `acme`, `sshpop` (M06-E02) |
| Kea | paquets `isc-kea-*` 3.0 du dépôt ISC Cloudsmith `kea-3-0`, services `isc-kea-dhcp4-server`, `isc-kea-dhcp-ddns-server`, configuration dans `/etc/kea/` |
| Molecule | instances jetables 2045-2049 du projet (M04-E24) ; ce palier utilise 2047 (`kea_dhcp4`) et 2048 (`certificats_acme`, `ssh_ca`), partagés avec les scénarios du module 04 : jamais deux scénarios du même VMID en parallèle |

---

### M06-E10 — L'API NetBox : jetons, REST et GraphQL  `LAB` `★★`

> **Ticket PLAT-720** — *De : Karim Benali*
> D'ici la fin du mois, trois outils vont écrire dans NetBox : la synchro Proxmox, OpenTofu, la génération du DNS. Je ne veux pas les voir passer avec le compte `admin`. Il nous faut un compte de service qui n'ait que les droits dont l'automatisation a besoin, avec un jeton qu'on peut tracer, restreindre et révoquer. Et avant que quelqu'un code contre l'API, qu'on sache s'en servir proprement : filtres, pagination, écritures concurrentes, GraphQL.

**Objectifs pédagogiques**
- Comprendre les jetons v2 de NetBox (clé publique, secret, *pepper*, ce qui est stocké) et leurs restrictions (écriture, adresses sources, expiration).
- Donner à un compte de service des **permissions d'objet** minimales plutôt que des droits d'administrateur.
- Interroger l'API REST efficacement : filtres, `brief`, `fields`, pagination, écritures avec contrôle de concurrence (`ETag` / `If-Match`), journal des changements.
- Écrire une requête GraphQL et savoir quand la préférer à REST.

**Prérequis** : M06-E04 (NetBox, jeton des checks), M06-E05 (modélisation).
**Durée indicative** : 2 h.

**Contexte technique**
- NetBox 4.6 : en-tête `Authorization: Bearer nbt_<clé>.<jeton>`. Le jeton en clair n'est affiché **qu'une fois**, à la création.
- Compte à créer : utilisateur `svc-automatisation` (aucune connexion à l'interface : pas de mot de passe connu), membre du groupe `automatisation`, qui porte une permission d'objet `automatisation-socle`.
- Besoins de l'automatisation (E11 à E15) : **lire** les sites, clusters, préfixes, plages d'IP, rôles IPAM, étiquettes ; **lire, créer, modifier et supprimer** les VMs, leurs interfaces, leurs disques virtuels et les adresses IP. Rien d'autre.
- Jeton d'écriture : expiration à un an, restreint aux adresses de `adm01` (10.10.10.10) et `runner01` (10.10.20.15), description explicite. Fichier `~/.config/workbook/netbox-auto.token` (600, une seule ligne : le jeton complet `nbt_…`).
- Les outils du module lisent NetBox avec le magasin de certificats du système : la racine « MédiSphère Root CA » y est depuis M06-E03.

**Travail demandé**
1. Lis la documentation des jetons (*REST API → Authentication*) et réponds dans ton journal : que contient chacune des deux parties de `nbt_<clé>.<jeton>` ? Que stocke la base de données ? À quoi sert `API_TOKEN_PEPPERS`, et que se passe-t-il si on le perd ?
2. Dans l'interface (*Admin*), crée le groupe, la permission d'objet (types d'objets, actions) et l'utilisateur. Justifie dans ton journal pourquoi tu n'as **pas** mis de contrainte (`constraints`) sur la permission, ou laquelle tu as mise.
3. Crée le jeton de `svc-automatisation` avec les restrictions demandées, puis enregistre-le :
   ```
   admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/netbox-auto.token
   admin@adm01:~$ nano ~/.config/workbook/netbox-auto.token        # colle le jeton, enregistre
   admin@adm01:~$ NB=https://nbx01.par1.medisphere.internal
   admin@adm01:~$ curl -s -H "Authorization: Bearer $(cat ~/.config/workbook/netbox-auto.token)" $NB/api/authentication-check/ | jq .username
   ```
   Inscris le jeton au registre des secrets. Puis prouve les restrictions : la même requête depuis `dns01` (avec une copie temporaire du jeton, effacée ensuite) ; une lecture de `/api/users/users/` depuis `adm01`.
4. REST, en lecture : liste les VMs du socle avec seulement leur nom, leur statut et leur IP primaire ; compte les adresses IP du préfixe INFRA ; parcours une liste avec `limit=2` en suivant les liens `next`. Note la différence entre `?brief=true` et `?fields=…`.
5. REST, en écriture, avec le jeton d'écriture : crée une étiquette `essai-api`, modifie sa description deux fois en envoyant à chaque fois l'`ETag` obtenu **avant** la première modification (`If-Match`). Note le code de la seconde réponse et explique ce qu'il protège. Retrouve tes écritures dans le journal des changements de l'API (`/api/core/object-changes/`), puis supprime l'étiquette.
6. Vérifie que le jeton **des checks** ne peut pas écrire, sans risquer de créer quoi que ce soit (lis ses propriétés par `/api/users/tokens/`).
7. GraphQL : en **une** requête, obtiens pour chaque VM étiquetée `socle` son nom, son statut, son cluster, son VMID (champ personnalisé) et l'adresse de son IP primaire. Combien de requêtes REST faudrait-il pour le même résultat ? Dans quel cas GraphQL ne convient pas (pense aux écritures) ?

**Critères de réussite**
- [ ] `svc-automatisation` s'authentifie avec son jeton depuis `adm01` et ne peut pas lire la liste des utilisateurs.
- [ ] Le jeton d'écriture expire, est limité à 10.10.10.10 et 10.10.20.15, et est refusé depuis `dns01`.
- [ ] Le fichier `netbox-auto.token` est en mode 600 et contient un jeton v2 ; il figure au registre des secrets.
- [ ] Le jeton des checks est en lecture seule.
- [ ] La requête GraphQL renvoie les VMs du socle avec leur IP primaire ; l'étiquette `essai-api` n'existe plus.
- [ ] Ton journal répond aux questions des étapes 1, 2, 5 et 7.

**Vérification** : `lab/bin/check 06 10`

<details><summary>Indice 1</summary>

Les types d'objets d'une permission se choisissent par application (`virtualization`, `ipam`, `extras`, `dcim`). Une seule permission peut porter plusieurs types et plusieurs actions ; les droits de lecture seule et d'écriture peuvent faire deux permissions distinctes, plus lisibles.
</details>

<details><summary>Indice 2</summary>

Les filtres REST sont ceux de l'interface (`?tag=socle`, `?parent=10.10.20.0/24`, `?status=active`) ; une liste renvoie `count`, `next`, `previous`, `results`. L'`ETag` est renvoyé par la lecture d'un **objet** (`/api/extras/tags/<id>/`), pas d'une liste : regarde les en-têtes (`curl -i`).
</details>

<details><summary>Indice 3</summary>

GraphQL : un seul point d'entrée `/graphql/`, une requête `POST` dont le corps JSON contient `query`. La liste des VMs s'appelle `virtual_machine_list` ; depuis NetBox 4.3, les filtres s'écrivent comme des objets (`filters: {tags: {slug: {exact: "…"}}}`). L'interface `/graphql/` de ton navigateur propose l'autocomplétion du schéma.
</details>

**Pour aller plus loin** (facultatif) : provisionne un jeton par l'API (`/api/users/tokens/provision/`) et lis ce que la documentation dit de `users.grant_token`. Lis la page *Permissions* : une contrainte comme `{"tags__slug": "env-m06"}` limiterait un compte d'essai aux seules VMs d'un module.

---

### M06-E11 — Synchroniser Proxmox vers NetBox  `LIBRE` `★★★`

> **Ticket PLAT-721** — *De : Claire Morel*
> NetBox a deux semaines et il ment déjà : `runner01` a pris deux vCPU de plus, une VM d'essai a disparu, et personne n'a pensé à le reporter. Une source de vérité qu'on tient à la main ne vaut pas mieux qu'un tableur. Je veux que ce que Proxmox sait (ce qui existe, ce qui tourne, avec quelles ressources) arrive tout seul dans NetBox, et que ce qui ne colle pas avec ce que NetBox prévoit soit **signalé**, pas écrasé. Karim et Sophie relisent avant la mise en service.

**Objectifs pédagogiques**
- Concevoir une synchronisation entre deux systèmes en décidant, champ par champ, lequel fait foi.
- Écrire un outil idempotent, avec simulation, testé sans réseau, sûr en cas d'erreur.
- L'exploiter comme un service : exécution planifiée, journal, alerte.

**Prérequis** : M06-E10 ; M02 (`medictl`, tests, CI de `plateforme/outils`) ; M02-E26 (alertes `ms-alerte@`).
**Durée indicative** : 4 h à 6 h.

**Contexte technique**
- Proxmox : jeton en **lecture** `wb-automation@pve!lecture` (`~/.config/workbook/pve-lecture.env`, M02) ; VMs visibles : celles du pool `lab`. NetBox : jeton d'écriture de `svc-automatisation` (E10).
- Périmètre : les VMs étiquetées `socle` et celles des environnements de modules (`env-mNN`) ; jamais les templates ni les instances Molecule.
- Modèle NetBox (M06-E05) : VMs dans le cluster `pve01`, champ personnalisé `vmid`. Unités : mémoire et disque en Mio dans NetBox ; octets dans `/cluster/resources` de Proxmox. Statuts NetBox des VMs : `active`, `offline`, `planned`, `staged`, `failed`, `decommissioning`, `paused`. Une VM qui a des disques virtuels dans NetBox a un champ `disk` calculé, qu'on ne peut pas écrire.
- Bientôt, OpenTofu créera des VMs dans NetBox **avant** qu'elles existent dans Proxmox (E13).

**Travail demandé**
Livre, par MR sur le projet de ton choix (justifie ce choix), un outil de synchronisation Proxmox → NetBox et sa mise en service. Contraintes :
- une **table de propriété** des champs (qui fait foi pour quoi), écrite avant le code, dans la MR ;
- un mode **simulation** qui calcule et affiche sans rien écrire ; un second passage sans changement dans Proxmox ne fait **aucune** écriture ;
- **aucune suppression** dans NetBox ; une VM présente dans NetBox mais absente de Proxmox, un renommage, une IP qui ne correspond pas à celle que voit l'agent QEMU sont des **écarts signalés** ;
- les secrets ne sont ni sur la ligne de commande, ni dans le journal, ni dans le dépôt ; TLS vérifié des deux côtés ;
- des tests automatisés qui couvrent les cas ci-dessus, sans accès réseau, exécutés par la CI ;
- une exécution planifiée (fréquence argumentée), journalisée, qui **alerte** en cas d'échec ;
- la démonstration : change les vCPU de la VM d'essai 2061 `m06-essai` (crée-la si besoin, avec `medictl vm create`), et montre la mise à jour de NetBox au passage suivant, puis un second passage vide.

**Critères de réussite**
- [ ] Pour toutes les VMs du socle, NetBox porte le bon VMID, le bon statut, les bons vCPU et la bonne mémoire.
- [ ] Une modification de ressources faite dans Proxmox apparaît dans NetBox sans intervention humaine.
- [ ] Le second passage n'écrit rien ; une VM absente de Proxmox reste dans NetBox et apparaît dans le rapport.
- [ ] Les tests passent en CI ; l'exécution planifiée est active et reliée à `ms-alerte@`.
- [ ] La table de propriété des champs est dans la MR (elle nourrira l'ADR-0060, M06-E31).

**Vérification** : `lab/bin/check 06 11`

<details><summary>Indice 1</summary>

Sépare le **calcul** des changements (une fonction pure : état Proxmox + état NetBox → liste d'actions) de leur **application** (appels HTTP). Le calcul se teste avec des dictionnaires ; l'application se teste avec un faux client.
</details>

<details><summary>Indice 2</summary>

Comment retrouver « la même VM » des deux côtés ? Par le nom (NetBox l'impose unique dans un cluster), par le VMID (champ personnalisé), ou par les deux ? Chaque choix a un cas qui le met en défaut : un renommage, un VMID réutilisé après destruction.
</details>

<details><summary>Indice 3</summary>

`PATCH` n'envoie que les champs qui changent : c'est ce qui rend un second passage silencieux, et ce qui évite d'écraser un champ modifié entre-temps par quelqu'un d'autre. Pour les champs personnalisés, lis ce que NetBox fait d'un `custom_fields` partiel.
</details>

**Pour aller plus loin** (facultatif) : NetBox Labs publie des outils de découverte (*Diode*, *Orb*) et des plugins de synchronisation Proxmox. Compare leur modèle (pousser des « intentions découvertes » dans une file à réconcilier) au tien.

---

### M06-E12 — Inventaire Ansible depuis NetBox  `LAB` `★★`

> **Ticket PLAT-722** — *De : Karim Benali*
> Aujourd'hui, ce qu'Ansible configure dépend d'une étiquette tapée dans l'interface de Proxmox, sans revue ni historique. NetBox a les deux : une intention relue et un journal des changements. Bascule l'inventaire du projet sur NetBox, mêmes groupes qu'avant pour que rien d'autre ne bouge, et garde l'inventaire Proxmox pour contrôler que les deux disent la même chose.

**Objectifs pédagogiques**
- Configurer le plugin `netbox.netbox.nb_inventory` (filtres, groupes, variables, authentification v2).
- Reproduire à l'identique les groupes d'un inventaire existant, et le prouver.
- Comparer deux sources d'inventaire et décider laquelle fait foi pour Ansible.

**Prérequis** : M04-E13 (inventaire dynamique Proxmox), M06-E10, M06-E11 (VMs à jour dans NetBox).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Collection `netbox.netbox` **3.23.0** (PLAN §6), à ajouter à `collections/requirements.yml` ; le plugin n'utilise pas `pynetbox` mais demande des modules Python à vérifier dans sa documentation.
- Groupes attendus : `socle`, `role_routeur`, `role_bastion`, `role_dns`, `role_gitlab`, `role_runner`, `role_s3`, `role_pki`, `role_netbox` (étiquettes NetBox `socle`, `role-…`), `ansible_host` = IP primaire. Les `group_vars`/`host_vars` existants ne changent pas.
- Accès : un **second** jeton v2 de `svc-automatisation`, en **lecture seule**, dans `~/.config/workbook/netbox-ansible.env` (600) sous la forme `NETBOX_TOKEN="nbt_…"` ; en CI, variable protégée et masquée du même nom.
- L'URL de NetBox n'est pas un secret : elle s'écrit dans le fichier d'inventaire.

**Travail demandé**
1. Lis la documentation du plugin : options `token`, `group_by`, `query_filters`/`vm_query_filters`, `plurals`, `keyed_groups`, `compose`, `rename_variables`. Repère comment le plugin forme l'en-tête `Authorization` selon la forme donnée à `token` : c'est le premier piège avec un jeton v2.
2. Ajoute la collection (version exacte), installe-la dans `./collections`, et ajoute au projet ce qu'il faut côté Python.
3. Écris `inventories/lab/netbox.yml` : VMs actives étiquetées `socle` seulement (pas les équipements `pve01`/`hp01`), groupes identiques à ceux de `proxmox.yml`, variable `vmid`, aucun secret dans le fichier.
4. Compare les deux inventaires (groupes, membres, `ansible_host`) avec `ansible-inventory --list` et `jq`, jusqu'à ce qu'ils ne diffèrent que par les variables propres à chaque plugin. Écris ce contrôle en script (`outils/comparer-inventaires.sh`) et ajoute-le au pipeline.
5. Fais de NetBox l'inventaire par défaut du projet ; mets à jour le pipeline (variable `NETBOX_TOKEN`), puis lance `site.yml --check` depuis la CI.
6. Expériences (note les résultats) : (a) retire l'étiquette `socle` d'une VM d'essai dans NetBox ; (b) mets un jeton faux ; (c) lance l'inventaire avec `token: "{{ … }}"` en simple chaîne au lieu de la forme que tu as retenue. Que fait Ansible dans chaque cas ? Que te protège de (b) ?

**Critères de réussite**
- [ ] `ansible-inventory --graph` (inventaire par défaut) liste les VMs du socle dans les mêmes groupes que l'inventaire Proxmox.
- [ ] `outils/comparer-inventaires.sh` sort en 0 quand les deux sources concordent, en erreur sinon, et tourne en CI.
- [ ] `netbox.yml` ne contient aucun jeton ; `netbox-ansible.env` est en 600 et son jeton est en lecture seule.
- [ ] Un passage `site.yml --check` utilise l'inventaire NetBox, en CI.

**Vérification** : `lab/bin/check 06 12`

<details><summary>Indice 1</summary>

Le plugin envoie `Authorization: Token …` (format v1) quand `token` est une simple chaîne. Lis la partie du code ou de la documentation qui traite d'un `token` donné sous forme de dictionnaire.
</details>

<details><summary>Indice 2</summary>

`plurals: false` change les noms des variables (une valeur au lieu d'une liste d'un élément). Pour les groupes, le plus simple est de reprendre exactement la recette de `proxmox.yml` : `keyed_groups` sur la liste des étiquettes, `-` remplacé par `_`. Méfie-toi d'une variable d'hôte nommée `tags` : c'est aussi un mot réservé d'Ansible.
</details>

<details><summary>Indice 3</summary>

`ansible-inventory --list` renvoie `{groupe: {hosts: […]}, …, _meta: {hostvars: …}}` : un `jq` qui produit, pour chaque groupe qui t'intéresse, la liste triée de ses hôtes, se compare avec `diff`.
</details>

**Pour aller plus loin** (facultatif) : les *config contexts* de NetBox portent des données attachées à un site, un rôle ou une étiquette (`config_context: true`). Quelles variables de `group_vars/` pourraient y vivre, et pourquoi le workbook les garde-t-il dans Git ?

---

### M06-E13 — Allouer les adresses depuis NetBox avec OpenTofu  `LAB` `★★★`

> **Ticket DEV-723** — *De : Julien Petit*
> Pour MédiAgenda, on va créer des VMs de recette à la chaîne. Aujourd'hui, à chaque fois, il faut te demander une IP, que tu vas chercher dans NetBox, que tu recopies dans une variable OpenTofu… et deux fois sur trois quelqu'un a pris la même entre-temps. Est-ce qu'OpenTofu ne peut pas demander directement une adresse libre à NetBox, et la rendre quand la VM disparaît ?

**Objectifs pédagogiques**
- Utiliser le fournisseur `e-breuninger/netbox` pour allouer une adresse dans une plage et enregistrer la VM qui l'utilise.
- Faire évoluer un module versionné (`vm-debian`) avec une rupture de compatibilité maîtrisée (version majeure).
- Comprendre l'ordre de création et de destruction entre deux fournisseurs, et la cohabitation avec la synchronisation de E11.

**Prérequis** : M05-E13, M05-E14 (module `vm-debian`, versionnage par semantic-release), M05-E26 (pipeline), M06-E10, M06-E11.
**Durée indicative** : 3 h.

**Contexte technique**
- Fournisseur `e-breuninger/netbox` `~> 5.8.0` : ressources `netbox_virtual_machine`, `netbox_interface` (interface de VM), `netbox_available_ip_address`, `netbox_ip_address`, `netbox_primary_ip` ; sources de données `netbox_cluster`, `netbox_ip_range`, `netbox_prefix`. Lis la table de compatibilité de sa documentation avec ta version de NetBox.
- Plages d'IP de NetBox (M06-E05) : dans chaque préfixe, plage « statique » .10-.49, « nœuds » .50-.99, « DHCP » .100-.199, « VIP » .200-.249 (PLAN §4.2).
- Adresses prévues par PLAN §4.5 mais pas encore utilisées : 10.10.20.21-23 (`vault01-03`, M25), 10.10.20.30 (`idp01`, M24).
- VM de l'exercice : VMID 2063, `m06-ipam01`, VNet `vsandbox`, adresse **allouée** dans la plage statique de SANDBOX (10.10.99.10-49), passerelle 10.10.99.1, étiquette `env-m06` ; environnement `plateforme/infra`, dossier `envs/lab-m06/` (état `envs/lab-m06/terraform.tfstate` sur `s3-01`).
- Accès d'OpenTofu à NetBox : jeton d'écriture de `svc-automatisation`, dans `~/.config/workbook/netbox-tofu.env` (600) sur `adm01` et en variable protégée et masquée dans la CI de `plateforme/infra`.

**Travail demandé**
1. Avant tout : dans NetBox, réserve (statut « réservé ») les adresses du tableau ci-dessus, avec leur futur nom en description. Pourquoi est-ce indispensable avant d'automatiser l'allocation ?
2. Dans `plateforme/tofu-modules`, fais évoluer `vm-debian` : l'adresse ne vient plus d'une variable mais de NetBox. La VM est d'abord enregistrée dans NetBox (VM, interface `eth0`, adresse allouée dans une plage donnée, IP primaire), puis créée dans Proxmox avec cette adresse. Les hôtes du socle, dont l'adresse est fixée par le PLAN, doivent pouvoir **imposer** leur adresse au lieu de l'allouer.
3. Décide ce que le module écrit dans NetBox et ce qu'il laisse à la synchronisation de E11 (pense au champ `vmid` et à ce que ferait le plan suivant). Écris ta décision dans le README du module.
4. Réfléchis à la configuration du fournisseur : où mettre l'URL, où mettre le jeton, et que devient le job `validate` d'une MR, qui n'a pas accès aux variables protégées ?
5. Publie la nouvelle version par MR (message de commit qui déclenche une version **majeure**) ; vérifie l'étiquette créée.
6. Dans `envs/lab-m06/`, déclare `m06-ipam01` avec le module à cette étiquette. `tofu plan`, lis-le (ordre des ressources), `tofu apply`. Vérifie dans NetBox, dans Proxmox (`ipconfig0`), puis depuis `adm01` (`ping`, `ssh`).
7. Lance la synchronisation de E11 : qu'écrit-elle ? Relance `tofu plan` : il doit être vide.
8. `tofu destroy` : dans quel ordre les ressources disparaissent-elles ? L'adresse redevient-elle libre ? Recrée la VM (elle servira en E14).

**Critères de réussite**
- [ ] Les quatre adresses futures du PLAN sont réservées dans NetBox.
- [ ] `vm-debian` v2.0.0 est publié ; `envs/lab-m06` le consomme par son étiquette.
- [ ] `m06-ipam01` a dans Proxmox l'adresse que NetBox lui a allouée, dans 10.10.99.10-49, et cette adresse est son IP primaire dans NetBox.
- [ ] Après une synchronisation (E11), `tofu plan` ne propose aucun changement.
- [ ] Après un `destroy`, aucune adresse ne reste attribuée à `m06-ipam01` dans NetBox.

**Vérification** : `lab/bin/check 06 13` (VM présente : cohérence ; VM détruite : aucune adresse orpheline)

<details><summary>Indice 1</summary>

`netbox_available_ip_address` demande une adresse libre à NetBox au moment de l'`apply` (point d'API `…/available-ips/` d'une plage ou d'un préfixe) : NetBox sérialise les demandes concurrentes, ce qu'une variable ne fera jamais. La source de données `netbox_ip_range` retrouve une plage par une adresse qu'elle **contient**.
</details>

<details><summary>Indice 2</summary>

Le fournisseur déclare l'URL et le jeton « obligatoires » : sans valeur dans le code, `tofu validate` exige les variables d'environnement. Une variable OpenTofu `sensitive` et `ephemeral` peut porter le jeton sans jamais l'écrire dans le plan ni dans l'état.
</details>

<details><summary>Indice 3</summary>

Chaque champ que deux écrivains se disputent fait osciller le plan. `lifecycle { ignore_changes = [...] }` permet au module de créer une valeur initiale (ou aucune) puis de laisser un autre outil la tenir.
</details>

**Pour aller plus loin** (facultatif) : NetBox 4.6 renvoie un `ETag` et accepte `If-Match` ; regarde si le fournisseur s'en sert. Et que se passe-t-il si deux `apply` concurrents demandent une adresse dans une plage où il n'en reste qu'une ?

---
### M06-E14 — Piloter PowerDNS par API et par OpenTofu  `LAB` `★★`

> **Ticket PLAT-724** — *De : Karim Benali*
> Julien a eu son IP automatique ; il lui faut maintenant le nom qui va avec, sans ticket. Avant de brancher OpenTofu sur PowerDNS, je veux que tu saches ce que l'API fait vraiment : comment une modification est appliquée, comment le numéro de série évolue, ce qui reste écrit dans la zone. Ensuite, le nom DNS naît avec la VM et meurt avec elle.

**Objectifs pédagogiques**
- Utiliser l'API HTTP de PowerDNS Authoritative 5.0 : zones, *rrsets*, types de changement, numéro de série.
- Créer des enregistrements A et PTR avec le fournisseur OpenTofu `mmianl/powerdns`, dans un module réutilisable.
- Marquer la propriété d'un enregistrement pour que plusieurs outils cohabitent dans une même zone.

**Prérequis** : M06-E06 (API de PowerDNS), M06-E13.
**Durée indicative** : 2 h.

**Contexte technique**
- API : `http://dns01.par1.medisphere.internal:8081/api/v1/servers/localhost`, en-tête `X-API-Key`. Le serveur web de PowerDNS ne parle pas TLS : la clé circule en clair entre `adm01` et `dns01` (écart suivi jusqu'à M06-E30) ; `webserver-allow-from` n'accepte que `adm01`, `runner01` et la boucle locale.
- Copie de travail de la clé : `~/.config/workbook/powerdns-api.env` (600), avec `PDNS_SERVER_URL`, `PDNS_API_KEY`, et la variable OpenTofu de ton choix pour la clé.
- Fournisseur `mmianl/powerdns` `~> 2.5.0` (le fournisseur historique `pan-net/powerdns` est abandonné) : ressource `powerdns_record` (`zone`, `name`, `type`, `ttl`, `records`, `comments`).
- Zones : `par1.medisphere.internal.`, inverse `10.10.in-addr.arpa.` (10.10.0.0/16).
- Rappel de M06-E06 : ton rôle `powerdns_auth` génère le contenu de certaines zones et les recharge quand ce contenu change, ou ne fait que les créer (`contenu` de chaque zone). Décide ce qu'il doit faire des zones où OpenTofu va écrire, avant le premier `apply`.

**Travail demandé**
1. Explore l'API avec `curl` et `jq` : liste des zones, leurs métadonnées (`SOA-EDIT-API`), le contenu de `par1.medisphere.internal.`. Note le numéro de série de la zone.
2. Ajoute un enregistrement TXT `essai-api.par1.medisphere.internal` par un `PATCH` (`changetype: REPLACE`), avec un commentaire. Vérifie avec `dig @10.10.20.10`, puis note le nouveau numéro de série : qui l'a changé, et selon quelle règle ? Ajoute une seconde valeur au même nom sans réécrire la première (lis les types de changement de PowerDNS 5.0), puis supprime l'enregistrement.
3. Réponds dans ton journal : pourquoi l'API travaille-t-elle par *rrset* (nom + type) et non par enregistrement ? Que se passe-t-il si deux outils font chacun un `REPLACE` sur le même *rrset* ?
4. Dans `plateforme/tofu-modules`, écris un module **à côté de** `vm-debian` (pas dedans) qui crée le A et le PTR d'un nom : entrées nom complet, adresse, TTL ; zone inverse déduite de l'adresse ; chaque enregistrement porte un commentaire qui dit qu'OpenTofu le gère. Justifie dans le README pourquoi il est séparé de `vm-debian`. Publie-le (nouvelle version mineure du dépôt).
5. Dans `envs/lab-m06/`, nomme `m06-ipam01` avec ce module, à partir des sorties de `vm-debian`. `plan`, `apply`, puis `dig` direct et inverse depuis `adm01`, et `curl` sur la zone pour voir le commentaire.
6. Modifie à la main (API) le A de `m06-ipam01` vers une autre adresse : que montre `tofu plan` ? Remets en ordre par OpenTofu.

**Critères de réussite**
- [ ] `powerdns-api.env` est en 600, inscrit au registre des secrets ; l'API répond depuis `adm01` avec la clé, refuse sans clé.
- [ ] Le module DNS est publié et consommé par étiquette ; il ne dépend pas de `vm-debian`.
- [ ] `dig @10.10.20.10 m06-ipam01.par1.medisphere.internal` et sa résolution inverse donnent l'adresse allouée par NetBox.
- [ ] Les deux *rrsets* portent un commentaire indiquant OpenTofu.
- [ ] L'enregistrement `essai-api` n'existe plus.

**Vérification** : `lab/bin/check 06 14`

<details><summary>Indice 1</summary>

`PATCH /zones/<zone>` avec `{"rrsets": [ … ]}` : chaque élément porte `name` (avec le point final), `type`, `changetype`, et pour un `REPLACE` les `records` et le `ttl`. Le contenu d'un TXT s'écrit avec ses guillemets (`"\"texte\""` en JSON).
</details>

<details><summary>Indice 2</summary>

Le nom d'un PTR se construit en lisant l'adresse à l'envers : `10.10.99.12` → `12.99.10.10.in-addr.arpa.`, dans la zone `10.10.in-addr.arpa.`. En HCL : `split`, `reverse`, `join`.
</details>

<details><summary>Indice 3</summary>

Une clé qui ne doit pas être dans le dépôt peut quand même être exigée par le fournisseur : même problème qu'en E13, même solution.
</details>

**Pour aller plus loin** (facultatif) : le fournisseur sait aussi gérer des zones (`powerdns_zone`) et leurs métadonnées. Pourquoi le workbook laisse-t-il la création des zones au rôle Ansible `powerdns_auth` ?

---

### M06-E15 — Le DNS généré depuis la source de vérité  `LAB` `★★★`

> **Ticket PLAT-725** — *De : Claire Morel*
> OpenTofu nomme ce qu'il crée, très bien. Mais le reste — `gw01`, `pve01`, `ca01`, les VIP de demain — n'existe dans le DNS que parce qu'on l'a écrit à la main au module 00, et personne ne le relira. Je veux que **tout** nom dont l'adresse est dans NetBox soit publié dans le DNS depuis NetBox, sans écraser ce que d'autres outils gèrent, et qu'un nom supprimé de NetBox disparaisse du DNS.

**Objectifs pédagogiques**
- Comparer deux approches (plugin NetBox ou outil externe) et en choisir une, argumentée.
- Générer des enregistrements à partir de l'IPAM sans détruire ceux des autres écrivains d'une même zone.
- Rendre la génération sûre : simulation, propriété des *rrsets*, conflits signalés, exécution planifiée.

**Prérequis** : M06-E11, M06-E14.
**Durée indicative** : 3 h.

**Contexte technique**
- Dans NetBox, une adresse IP a un champ `dns_name` ; la modélisation de M06-E05 l'a renseigné pour le socle, OpenTofu le renseigne pour ses VMs (E13).
- Écrivains des zones à partir de ce palier : le rôle Ansible `powerdns_auth` (SOA, NS), OpenTofu (E14), Kea (mises à jour dynamiques des baux, E17), et l'outil de cet exercice. Les enregistrements écrits au palier 1 sont, eux, sans propriétaire.
- PowerDNS conserve des **commentaires** par *rrset* (`content`, `account`).
- Proposition du corrigé : une sous-commande `medictl dns sync` dans `plateforme/outils`, qui réutilise le client NetBox de E11. Le plugin communautaire `netbox-plugin-dns` est l'autre voie sérieuse : regarde son modèle avant de choisir.

**Travail demandé**
1. Compare dans ton journal (dix lignes) un plugin NetBox qui **porte** les zones et un outil externe qui les **génère** : qui devient la source des zones, où vivent les enregistrements qui n'ont pas d'adresse dans NetBox, que devient PowerDNS en cas de panne de NetBox ? Choisis.
2. Fixe les règles de propriété : comment l'outil reconnaît-il ce qui est à lui ? Que fait-il d'un *rrset* qui existe déjà avec une autre valeur et un autre propriétaire ? D'un *rrset* qui existe avec **la même** valeur ?
3. Implémente (ou installe et configure) la génération : A et PTR des adresses actives qui ont un `dns_name` dans `par1` ou `par2`, TTL fixe, simulation, une écriture par zone, suppression de ce que l'outil possède et qui n'a plus de source, code de sortie distinct quand il y a des conflits.
4. Premier passage en simulation : lis chaque ligne. Les enregistrements écrits à la main au palier 1 vont apparaître en conflit (même nom, aucun propriétaire) ou en doublon : décide comment l'outil en prend la propriété, sans coupure de résolution, et fais-le.
5. Passage réel, puis second passage (aucun changement). Contrôle par `dig` direct et inverse sur trois hôtes du socle.
6. Expériences : (a) change le `dns_name` d'une adresse d'essai dans NetBox ; (b) mets-la au statut « réservé » ; (c) crée dans NetBox une adresse qui porte le nom d'un bail DHCP existant. Que fait l'outil dans chaque cas ?
7. Planifie l'exécution (fréquence argumentée), avec alerte en cas d'échec ou de conflit.

**Critères de réussite**
- [ ] Les VMs du socle se résolvent (A et PTR) vers l'adresse que NetBox leur donne.
- [ ] Les *rrsets* générés portent la marque de l'outil ; ceux d'OpenTofu et de Kea ne sont jamais modifiés.
- [ ] Une adresse retirée (ou passée en « réservé ») dans NetBox disparaît du DNS au passage suivant.
- [ ] Un second passage n'écrit rien ; l'exécution est planifiée et alerte.

**Vérification** : `lab/bin/check 06 15`

<details><summary>Indice 1</summary>

L'API de PowerDNS permet de lire toute une zone en une requête : calcule tout ce qui doit changer d'abord, puis envoie un seul `PATCH` par zone. Un incident au milieu ne laisse pas une zone à moitié réécrite.
</details>

<details><summary>Indice 2</summary>

La reprise de propriété des enregistrements du palier 1 n'est qu'un `REPLACE` du même contenu avec le commentaire de l'outil : la réponse DNS ne change pas pendant l'opération. Une liste de noms explicitement « adoptables », relue, vaut mieux qu'une adoption automatique de tout ce qui n'a pas de propriétaire.
</details>

<details><summary>Indice 3</summary>

`ipaddress.ip_address("10.10.20.13").reverse_pointer` (Python) donne le nom PTR. Pour savoir quelle zone inverse sert une adresse, compare-la aux réseaux 10.10.0.0/16 et 10.20.0.0/16.
</details>

**Pour aller plus loin** (facultatif) : un *webhook* NetBox (*Event Rules*) peut déclencher la génération à chaque changement d'adresse, au lieu d'attendre la minuterie. Qu'y gagne-t-on, et que faut-il garder quand même ?

---

### M06-E16 — Kea DHCPv4 remplace dnsmasq  `LAB` `★★`

> **Ticket CHG-726** — *De : Nadia Roussel*
> dnsmasq ne fait plus que le DHCP du VLAN 99 sur `dns01`, et Kea est prévu depuis le début du module. Je valide le changement pour jeudi, à une condition : que les VMs de la sandbox ne voient rien. Pas de nouveau relais, pas de nouvelle IP, pas de nouvelle plage. Et à la fin, plus une trace de dnsmasq sur `dns01`.

**Objectifs pédagogiques**
- Installer Kea 3.0 depuis le dépôt de l'ISC, avec vérification de la clé de signature.
- Écrire la configuration d'un serveur DHCPv4 qui ne sert que des sous-réseaux **relayés** (identifiant de sous-réseau, options, baux en `memfile`, sockets UDP).
- Basculer un service DHCP en production avec une interruption minimale, et retirer l'ancien proprement.

**Prérequis** : M00-E14 (relais DHCP de `gw01`), M04-E24 (Molecule), M04-E46 (rôle `dnsmasq`), M06-E08.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Dépôt ISC Cloudsmith `kea-3-0` : source `https://dl.cloudsmith.io/public/isc/kea-3-0/deb/debian`, suite `trixie`, clé publiée par le dépôt (trouve son URL et son empreinte dans le script d'installation officiel du dépôt, et vérifie-la avant de l'utiliser) ; paquets `isc-kea-dhcp4`, `isc-kea-hooks` ; service `isc-kea-dhcp4-server` (utilisateur `_kea`) ; configuration `/etc/kea/kea-dhcp4.conf`.
- Changements de Kea 3.0 qui touchent cet exercice : `id` **obligatoire** pour chaque sous-réseau ; fichiers de baux, journaux et sockets de contrôle limités à des dossiers fixés à la compilation (`/var/lib/kea`, `/var/log/kea`, `/run/kea`) ; `kea-dhcp4 -t <fichier>` valide une configuration.
- Paramètres à reprendre de M00-E14 : sous-réseau 10.10.99.0/24 (identifiant **99**), plage 10.10.99.100-199, bail 12 h, routeur 10.10.99.1, DNS 10.10.20.10, domaine `par1.medisphere.internal`, NTP 10.10.99.1. Le relais de `gw01` envoie à 10.10.20.10 avec `giaddr` 10.10.99.1 : il ne change pas, ni le pare-feu.
- Molecule : scénario `kea_dhcp4`, instance 2047.
- VM de test : 2066 `sbx66`, clone lié de l'image dorée, VNet `vsandbox`, DHCP, étiquette `env-m06` (détruite en fin d'E17).

> ⚠️ **Attention** : un second serveur DHCP actif sur un VLAN distribue des adresses en concurrence avec le premier. Ne fais **jamais** tourner Kea et dnsmasq sur `dns01` en même temps sur le port 67 (Kea refusera de démarrer, ce qui est la bonne nouvelle), et n'écris pas, pour un test Molecule, un sous-réseau qui correspondrait au VLAN de l'instance. Retour arrière : arrêter Kea, réinstaller dnsmasq par le rôle `dnsmasq` (version de M04-E46 dans l'historique Git).

**Travail demandé**
1. Relève l'état actuel : baux en cours dans dnsmasq, options envoyées (lis le fichier de configuration généré par le rôle `dnsmasq`). Décide ce qu'on fait des baux existants (reprise ou non) et écris-le dans le ticket.
2. Écris le rôle `kea_dhcp4` : dépôt vérifié par empreinte, paquets à la branche 3.0, configuration générée **comme une structure de données** puis sérialisée en JSON (pas de JSON écrit à la main dans un modèle), validée par `kea-dhcp4 -t` avant d'être posée, service actif, contrôle que le service répond sur sa socket de contrôle UNIX après redémarrage. Les sous-réseaux sont une variable (liste) : ton rôle doit pouvoir servir un autre VLAN demain.
3. Choisis le type de socket DHCP (`raw` ou `udp`) et justifie : tout le trafic arrive relayé.
4. Écris le scénario Molecule, en respectant l'avertissement ci-dessus.
5. Bascule par le pipeline : retrait de dnsmasq (arrêt, purge, rôle et `group_vars` retirés du dépôt), puis Kea. Mesure la durée pendant laquelle aucun serveur n'écoutait.
6. Crée `sbx66` et suis son premier échange avec `tcpdump` sur `gw01` (côté `ens19.20`) et sur `dns01`. Retrouve son bail dans le fichier de Kea et par `kea-shell`, ou par la socket de contrôle (`lease4-get-all` demandera un *hook* : lequel ? Il servira en E17).
7. Que se passe-t-il pour une VM qui avait un bail dnsmasq et qui le renouvelle à mi-bail ? Provoque-le sur une VM existante (ou sur `sbx66` avant la bascule) et explique avec ta capture.

**Critères de réussite**
- [ ] dnsmasq n'est plus installé sur `dns01` ; le rôle `dnsmasq` n'est plus appliqué.
- [ ] `isc-kea-dhcp4-server` est actif, écoute UDP 67, et sert le sous-réseau 99 avec la plage et les options demandées.
- [ ] `sbx66` obtient une adresse de 10.10.99.100-199 avec la passerelle 10.10.99.1 et le DNS 10.10.20.10 ; son bail est dans `/var/lib/kea`.
- [ ] Le rôle a son scénario Molecule, vert en CI.

**Vérification** : `lab/bin/check 06 16` (avec `sbx66` démarrée)

<details><summary>Indice 1</summary>

Kea choisit le sous-réseau d'un paquet relayé d'après son `giaddr` : rien à déclarer pour le relais. La liste `interfaces-config.interfaces` dit seulement sur quelle interface de `dns01` écouter. Lis la section *Raw Sockets* du chapitre sécurité de la documentation de Kea pour le choix de l'étape 3.
</details>

<details><summary>Indice 2</summary>

Une configuration générée par `to_nice_json` est toujours du JSON valide ; un modèle qui écrit le JSON à la main casse à la première virgule oubliée dans une boucle. `community.general.dict_kv` transforme une liste de chaînes en liste d'objets.
</details>

<details><summary>Indice 3</summary>

`printf '{ "command": "config-get" }' | sudo socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket` : la socket UNIX répond par un objet JSON. Le nom de la socket dans la configuration ne comporte **pas** de chemin en Kea 3.0.
</details>

**Pour aller plus loin** (facultatif) : lis la section *Host Reservations* et réserve une adresse fixe à `sbx66` par son adresse MAC. Puis réfléchis : où cette réservation devrait-elle vivre, dans Kea ou dans NetBox ?

---

### M06-E17 — Kea : API de contrôle et mise à jour dynamique du DNS  `LAB` `★★★`

> **Ticket PLAT-727** — *De : Nadia Roussel*
> En astreinte, la première question sur la sandbox est toujours « quelle IP a eu la VM machin ? ». Je veux deux choses : que le nom des VMs de la sandbox se résolve tout seul pendant la durée de leur bail, et pouvoir interroger les baux sans éditer de fichier à la main. Sophie a ajouté une condition : personne ne doit pouvoir écrire dans la zone DNS du socle en se faisant passer pour Kea.

**Objectifs pédagogiques**
- Activer la socket de contrôle HTTP intégrée à `kea-dhcp4` (Kea 3.0), avec authentification, et l'interroger.
- Configurer `kea-dhcp-ddns` pour publier les baux dans PowerDNS par mises à jour RFC 2136 signées TSIG.
- Restreindre côté PowerDNS qui peut mettre à jour une zone (adresse **et** clé), et comprendre la résolution de conflits par DHCID.

**Prérequis** : M06-E06, M06-E16.
**Durée indicative** : 3 h.

**Contexte technique**
- Kea 3.0 : les démons portent eux-mêmes des sockets de contrôle HTTP/HTTPS (`control-sockets`) ; le *Control Agent* n'est plus nécessaire (il disparaît en 3.2). Authentification « basic » : utilisateur `kea-api`, mot de passe dans un **fichier** de `/etc/kea` (paramètres `directory` et `password-file`), valeur dans `vault_kea_api_mot_de_passe` (Vault « critique »). Écoute : 127.0.0.1:8004 (l'API sert l'astreinte, par SSH sur `dns01` ; la HA de E25 changera cela).
- *Hook* libre `libdhcp_lease_cmds.so` (paquet `isc-kea-hooks`) : commandes `lease4-get`, `lease4-get-all`, `lease4-del`…
- DDNS : `kea-dhcp4` envoie chaque changement de bail à `kea-dhcp-ddns` (service `isc-kea-dhcp-ddns-server`, `/etc/kea/kea-dhcp-ddns.conf`, écoute 127.0.0.1:53001) ; celui-ci met à jour le serveur faisant autorité **local** (127.0.0.1:5300). Clé TSIG `ddns-kea`, `hmac-sha256`, secret dans `vault_kea_tsig_ddns`.
- PowerDNS 5.0 : `dnsupdate=yes` et `allow-dnsupdate-from` dans `pdns.conf` (rôle `powerdns_auth`) ; métadonnées de zone `ALLOW-DNSUPDATE-FROM` et `TSIG-ALLOW-DNSUPDATE` ; en 5.0, `pdnsutil` s'utilise par sous-commandes (`pdnsutil tsigkey …`, `pdnsutil metadata …`).
- Noms publiés : `sbxNN.par1.medisphere.internal` (le nom d'hôte que la VM envoie), A et PTR, pour le seul sous-réseau 99.

**Travail demandé**
1. API : étends le rôle `kea_dhcp4` (socket HTTP authentifiée, *hook*), applique. Depuis `dns01`, interroge l'API sans identifiants (code ?), puis avec : `version-get`, `config-get`, `lease4-get-all`. Écris dans ton journal pourquoi un mot de passe dans un fichier vaut mieux qu'un mot de passe dans `kea-dhcp4.conf`, et pourquoi l'API n'écoute pas sur 10.10.20.10.
2. Côté PowerDNS : active les mises à jour dynamiques dans le rôle `powerdns_auth`, puis, dans un nouveau rôle `kea_ddns`, importe la clé TSIG et pose les métadonnées des deux zones (`par1.medisphere.internal`, `10.10.in-addr.arpa`). Lis dans la documentation comment se combinent l'adresse autorisée et la clé.
3. Côté Kea : `kea_ddns` installe et configure `kea-dhcp-ddns` (secret TSIG dans un fichier, pas dans la configuration ; domaines direct et inverse ; serveur 127.0.0.1:5300), et `kea_dhcp4` active les mises à jour pour le sous-réseau 99 seulement. Choisis et justifie : qui fait la mise à jour (le client ou le serveur), et que faire d'un client qui n'envoie pas de nom ?
4. Ordre des rôles dans le playbook de `dns01` : justifie-le.
5. Prouve le contrôle d'accès **avant** de brancher Kea : une mise à jour `nsupdate` signée par la clé est acceptée ; la même sans clé est refusée ; une signée par une autre clé aussi.
6. Redémarre le réseau de `sbx66` (ou recrée-la) : son nom apparaît-il ? Lis les journaux de `kea-dhcp-ddns` et la zone (A, PTR, et un troisième type d'enregistrement : lequel, et à quoi sert-il ?).
7. Conflit : donne à `sbx66` le nom d'hôte `dns01` et renouvelle son bail. Que se passe-t-il dans le DNS, et pourquoi est-ce rassurant ?
8. Détruis `sbx66` : que deviennent ses enregistrements, et quand ?

**Critères de réussite**
- [ ] L'API de Kea répond 401 sans identifiants et renvoie les baux avec ; le mot de passe n'est pas dans `kea-dhcp4.conf`.
- [ ] `isc-kea-dhcp-ddns-server` est actif ; le secret TSIG est dans un fichier en 640.
- [ ] Les deux zones n'acceptent de mise à jour que signée par `ddns-kea`, depuis la boucle locale.
- [ ] `sbx66.par1.medisphere.internal` se résout (A et PTR) vers son bail.
- [ ] Un client qui prend le nom d'un hôte du socle ne modifie pas l'enregistrement du socle.

**Vérification** : `lab/bin/check 06 17` (avec `sbx66` démarrée, avant l'étape 8)

<details><summary>Indice 1</summary>

Les paramètres DDNS de `kea-dhcp4` se reconnaissent à leur préfixe `ddns-` et peuvent se poser au niveau global, du réseau partagé ou du sous-réseau ; le plus spécifique l'emporte. La section `dhcp-ddns` (sans tiret au début) dit seulement **où** joindre `kea-dhcp-ddns`.
</details>

<details><summary>Indice 2</summary>

Par défaut PowerDNS ignore les mises à jour dynamiques **sans rien journaliser** : si rien n'arrive dans la zone, regarde d'abord `dnsupdate`. `nsupdate -y hmac-sha256:ddns-kea:<secret>` signe une mise à jour comme le ferait Kea ; pense à `server 127.0.0.1 5300`.
</details>

<details><summary>Indice 3</summary>

Le troisième enregistrement est un DHCID (RFC 4701). Lis le paramètre `ddns-conflict-resolution-mode` de Kea : la valeur par défaut protège déjà le socle d'un usurpateur… à condition que les enregistrements du socle ne portent pas de DHCID.
</details>

**Pour aller plus loin** (facultatif) : passe la socket de contrôle en HTTPS avec un certificat de `ca01` (`trust-anchor`, `cert-file`, `key-file`, `cert-required`) : ce sera nécessaire quand `dns02` devra joindre l'API de `dns01` pour la haute disponibilité (E25).

---
### M06-E18 — Certificats automatiques par ACME pour GitLab et NetBox  `LAB` `★★`

> **Ticket SEC-728** — *De : Sophie Laurent*
> Les certificats de GitLab, de `s3-01` et de NetBox viennent bien de la nouvelle PKI, mais ils ont été émis à la main (M06-E03, E04) pour 90 jours, et leur renouvellement est noté… dans un tableau. Pour l'audit HDS, je veux deux choses : des certificats d'une durée courte (30 jours au plus, c'est la politique), et un renouvellement que **personne** n'a à faire. Un certificat expiré en production, c'est un incident évitable, et je ne veux plus en voir.

**Objectifs pédagogiques**
- Obtenir un certificat par ACME (défi HTTP-01) auprès de step-ca, et comprendre ce que le défi prouve.
- Renouveler automatiquement, avant l'échéance, avec rechargement du service consommateur.
- Choisir un client ACME et un mode de défi adaptés à chaque service.

**Prérequis** : M06-E02, M06-E03 (racine sur tous les hôtes, certificats émis à la main), M06-E04 (`nbx01`), M06-E08 (DNS), M01 (certificat de GitLab), M05-E10 (`s3-01`).
**Durée indicative** : 3 h.

**Contexte technique**
- Provisioner `acme` de `ca01` : certificats de 30 jours (720 h) au plus. Annuaire ACME : `https://ca01.par1.medisphere.internal/acme/acme/directory`.
- Défi HTTP-01 : `ca01` résout le nom demandé (par `dns01`) et vient chercher un jeton sur `http://<nom>:80/.well-known/acme-challenge/…`. `git01`, `nbx01` et `s3-01` sont dans le VLAN INFRA comme `ca01` : aucun flux à ouvrir. Sur `git01` et `nbx01`, nginx occupe déjà le port 80 (redirection vers HTTPS).
- Client retenu par le corrigé : `step` (paquet `step-cli` du dépôt Smallstep, celui de `ca01`) ; alternatives : `certbot`, `lego`.
- Smallstep publie des modèles d'unités systemd `cert-renewer@.service` et `cert-renewer@.timer` (dépôt `smallstep/cli`, dossier `systemd/`) qui renouvellent avec `step ca renew`.
- GitLab : certificat et clé dans `/etc/gitlab/ssl/git01.par1.medisphere.internal.crt` et `.key` (chemins par défaut, M01), rechargement de nginx par `gitlab-ctl hup nginx` sans reconfiguration. `s3-01` et `nbx01` : chemins définis par leurs rôles Ansible (M05-E10, M06-E04).

**Travail demandé**
1. Lis ce que fait l'intégration Let's Encrypt d'omnibus (`letsencrypt['…']` dans `gitlab.rb`). Peut-on la pointer sur `ca01` ? Est-ce documenté ? Décide et justifie dans ton journal.
2. À la main, une fois, sur la VM d'essai 2061 `m06-essai` : obtiens un certificat ACME pour un nom de test, et observe dans les journaux de `ca01` la commande, le défi, la validation. Puis renouvelle-le avec `step ca renew` : le défi HTTP-01 se rejoue-t-il ? Que prouve le renouvellement, et que se passerait-il après expiration ?
3. Écris le rôle `certificats_acme` : client `step` installé depuis le dépôt vérifié, confiance dans la CA établie par l'**empreinte** de la racine, émission seulement si le certificat manque ou ne se vérifie plus contre la racine MédiSphère pour son nom, port 80 libéré **le temps du défi** seulement (et rendu même en cas d'échec), droits de la clé, minuterie de renouvellement par certificat, rechargement du service après chaque renouvellement. Écris son scénario Molecule (une CA de test sur l'instance suffit : le scénario de `step_ca` en fabrique une).
4. Décris dans `host_vars` les certificats de `git01`, `nbx01` et `s3-01`, et applique par le pipeline, hôte par hôte. Pour GitLab, la reconfiguration n'est pas nécessaire : pourquoi ?
5. Contrôle depuis `adm01` avec `openssl s_client` puis `curl` sans option `-k` : émetteur, durée, chaîne complète (intermédiaire compris).
6. Force un renouvellement sur `s3-01` (`systemctl start cert-renewer@<id>` ne suffit pas tant que le certificat est jeune : pourquoi ? que faut-il faire ?) et vérifie que OpenTofu accède toujours à son état.
7. Fais le ménage des certificats émis à la main : plus aucun service du socle ne doit en présenter un, et leurs clés n'ont plus rien à faire dans Vault ni sur `adm01`. Comment le prouves-tu ? Mets à jour l'inventaire des échéances (M06-E03) et le registre des secrets.

**Critères de réussite**
- [ ] `git01`, `nbx01` et `s3-01` présentent un certificat émis par « MédiSphère Intermediate CA », de 30 jours au plus, avec la chaîne complète.
- [ ] Sur chacun, une minuterie de renouvellement est active, et son dernier passage n'est pas en échec.
- [ ] Un renouvellement forcé est pris en compte par le service sans action manuelle.
- [ ] Plus aucun service HTTPS du socle ne présente un certificat émis à la main (provisioner `admin`, 90 jours), ni de la CA provisoire retirée en M06-E03.
- [ ] Le rôle `certificats_acme` a son scénario Molecule, vert en CI.

**Vérification** : `lab/bin/check 06 18`

<details><summary>Indice 1</summary>

`step ca certificate <nom> <crt> <clé> --provisioner acme` lance son propre petit serveur HTTP sur le port 80 (mode « autonome ») ; `--webroot` dépose le jeton dans le dossier d'un serveur existant. Le renouvellement (`step ca renew`) s'authentifie par le **certificat en cours** (TLS mutuel) : plus de port 80, plus de défi.
</details>

<details><summary>Indice 2</summary>

`step certificate verify <crt> --roots <racine> --host <nom>` sort en erreur pour un certificat d'une autre CA, expiré, ou d'un autre nom : c'est le test « faut-il réémettre ? » du rôle. `step certificate needs-renewal` dit si le certificat a passé les deux tiers de sa vie.
</details>

<details><summary>Indice 3</summary>

Le modèle `cert-renewer@.service` lit `CERT_LOCATION` et `KEY_LOCATION` ; une surcharge par instance (`cert-renewer@<id>.service.d/*.conf`) change les chemins et ajoute un `ExecStartPost=` pour recharger le service. `step` réécrit les fichiers au renouvellement : vérifie leurs droits après coup.
</details>

**Pour aller plus loin** (facultatif) : le défi TLS-ALPN-01 se joue sur le port 443. Lequel des trois services pourrait l'utiliser, avec quel client, et qu'est-ce que cela changerait à l'étape 3 ?

---

### M06-E19 — Certificats SSH d'hôte : fin de la confiance aveugle  `LAB` `★★★`

> **Ticket SEC-729** — *De : Sophie Laurent*
> Depuis le module 00, chaque nouvelle VM commence par « The authenticity of host … can't be established », et tout le monde tape « yes ». C'est exactement ce qu'un attaquant au milieu attend. Je veux que nos postes et notre CI fassent confiance à **une** autorité, et que tout hôte du socle prouve son identité par un certificat qu'elle a signé. Une clé d'hôte inconnue doit redevenir une alarme.

**Objectifs pédagogiques**
- Comprendre les certificats SSH d'hôte : principaux, durée, `HostCertificate`, `@cert-authority`.
- Signer des clés d'hôte sans que la clé privée quitte l'hôte, et les renouveler de façon autonome (SSHPOP).
- Faire évoluer la confiance des clients (poste d'administration, CI, hôtes entre eux) sans couper l'accès.

**Prérequis** : M00-E15 (`~/.ssh/config` de `adm01`), M04-E11 (`ssh_durci`), M04-E27 (`known_hosts` du projet Ansible), M06-E02, M06-E18 (client `step` des hôtes).
**Durée indicative** : 3 h.

**Contexte technique**
- CA SSH de `ca01` : clé publique de la CA d'**hôte** obtenue par `step ssh config --host --roots` ; provisioner JWK `admin` (signature initiale, mot de passe dans `vault_step_ca_mot_de_passe_admin`) ; provisioner `sshpop` (renouvellement par le certificat en cours) ; durée des certificats d'hôte : 30 jours (*claims* de M06-E02).
- `~/.ssh/config` de `adm01` joint les hôtes par **adresse IP** (`HostName`, choix de M00-E15) ; l'inventaire Ansible aussi (`ansible_host`). Le projet Ansible a son propre `inventories/lab/known_hosts` (M04-E27).
- Fichiers de `sshd_config.d` déjà présents : `01-ssh-durci.conf` (M04-E11), ceux de l'image dorée (M03).
- Périmètre : les hôtes du socle gérés par Ansible (`gw01` compris). Pas `pve01` ni `pbs01`.

**Travail demandé**
1. À la main, sur la VM d'essai 2061 `m06-essai` : signe sa clé d'hôte ed25519 avec `step ssh certificate --host --sign` (sur `adm01`), dépose le certificat, ajoute `HostCertificate`. Depuis `adm01`, connecte-toi avec un `known_hosts` **temporaire** qui ne contient qu'une ligne `@cert-authority`, d'abord par le nom complet, puis par l'adresse IP. Explique l'échec du second essai, et ce qu'il impose pour nos principaux.
2. Écris le rôle `ssh_ca_hote` : la clé publique d'hôte est lue sur l'hôte, signée **sur le contrôleur** (le mot de passe du provisioner ne quitte pas le contrôleur et n'apparaît ni dans la ligne de commande ni dans le journal), le certificat est déposé ; re-signature seulement si le certificat manque, ne correspond plus à la clé ou aux principaux, ou approche de sa fin ; `sshd` présente le certificat (fichier de `sshd_config.d` validé) ; une minuterie locale renouvelle par SSHPOP ; les hôtes eux-mêmes font confiance à la CA d'hôte (`/etc/ssh/ssh_known_hosts`). Scénario Molecule.
3. Où mets-tu la clé publique de la CA d'hôte : récupérée à chaque passage sur `ca01`, ou versionnée dans l'inventaire ? Pense à la rotation de la CA et à la revue.
4. Applique au socle par le pipeline (le contrôleur de CI a besoin de `step` : ajoute-le à `runner01` par son rôle). Vérifie avec `ssh-keyscan -c`.
5. Fais confiance à la CA côté clients : `~/.ssh/known_hosts` de `adm01` et `inventories/lab/known_hosts` du projet (dans ce dernier, que deviennent les clés brutes que tu y avais vérifiées en M04-E27 ?). Retire ensuite les clés brutes du socle de `~/.ssh/known_hosts` de `adm01` (`ssh-keygen -R`) et prouve que tout fonctionne encore.
6. Expérience : sur la VM d'essai, régénère les clés d'hôte sans re-signer. Que voit `adm01` ? Comparé au module 00, en quoi est-ce mieux ?
7. Détruis la VM d'essai.

**Critères de réussite**
- [ ] Chaque hôte du socle présente un certificat d'hôte signé par la CA, de 30 jours au plus, dont les principaux comprennent son nom court, son nom complet et son adresse IP de connexion.
- [ ] `adm01` se connecte à chaque hôte du socle avec un `known_hosts` qui ne contient **que** la ligne `@cert-authority`.
- [ ] La minuterie de renouvellement est active sur chaque hôte.
- [ ] Le projet Ansible (CI comprise) vérifie les hôtes par la CA ; plus aucune clé brute du socle dans `~/.ssh/known_hosts` de `adm01`.

**Vérification** : `lab/bin/check 06 19`

<details><summary>Indice 1</summary>

Le client compare aux principaux du certificat le nom qu'il a **utilisé** pour se connecter : le `HostName` (une adresse ici) ou le `HostKeyAlias` s'il y en a un. Deux solutions : mettre les adresses dans les principaux (et dans le motif de `@cert-authority`), ou un `HostKeyAlias` par hôte dans `~/.ssh/config`. Pèse leur coût pour Ansible et pour la CI.
</details>

<details><summary>Indice 2</summary>

`step ssh certificate … --sign` écrit `<clé>-cert.pub` à côté de la clé publique. `--provisioner-password-file /dev/stdin` et le paramètre `stdin` du module `command` d'Ansible évitent le fichier de mot de passe et la ligne de commande. `ssh-keygen -L -f <certificat>` affiche principaux, validité et CA.
</details>

<details><summary>Indice 3</summary>

Une ligne `HostKey` dans `sshd_config.d` **remplace** la liste des clés d'hôte par défaut : `HostCertificate` seul suffit, sshd associe le certificat à la clé chargée qui lui correspond. `step ssh renew` (SSHPOP) n'accepte qu'un certificat encore valide.
</details>

**Pour aller plus loin** (facultatif) : `ssh -o UpdateHostKeys=yes` et `ssh-keygen -H` (hachage de `known_hosts`) : que deviennent-ils dans un monde de certificats ? Et que proposerait `step ssh config --host` sur un hôte ?

---

### M06-E20 — Certificats SSH d'utilisateur et bastion `adm01`  `LAB` `★★★`

> **Ticket SEC-730** — *De : Sophie Laurent* — *Copie : Nadia Roussel*
> Même logique dans l'autre sens. Aujourd'hui, ta clé personnelle est déposée sur toutes les machines, sans date de fin : si ton poste est volé ce soir, il faut repasser partout pour la retirer. Je veux des accès qui expirent d'eux-mêmes en fin de journée, une identité lisible dans les journaux de chaque hôte, et un seul point d'entrée vers le socle : `adm01`. Nadia veut pouvoir donner un accès d'astreinte sans toucher aux machines.

**Objectifs pédagogiques**
- Configurer `sshd` pour accepter des certificats d'utilisateur (`TrustedUserCAKeys`, `AuthorizedPrincipalsFile`) et lire ce qu'il en journalise.
- Obtenir et renouveler un certificat d'utilisateur court ; gérer l'agent SSH en conséquence.
- Garder un accès de secours qui ne dépend ni de la CA ni du réseau, et faire de `adm01` le bastion.

**Prérequis** : M04-E12, M04-E14 (comptes, compte `secours`), M04-E17 (rôle `pare_feu`), M04-E27 (clé `ansible-ci`), M06-E19.
**Durée indicative** : 3 h.

**Contexte technique**
- CA d'**utilisateur** : `step ssh config --roots`. Durée maximale des certificats d'utilisateur : 16 h (*claims* de M06-E02). Signature avec le provisioner `admin` (mot de passe dans `~/.config/workbook/step-admin.pass` sur `adm01`).
- Principaux : `admin` (accès quotidien au compte `admin`), `astreinte` (accès d'astreinte, donné à Nadia, au **même** compte `admin`).
- Clés autorisées classiques : `base_utilisateurs` / `ms_cles_admin` (rôle `base`, M04-E14) ; la clé `ansible-ci` (`from="10.10.20.15"`, M04-E27) **reste** ; une clé de **bris de glace** remplace ta clé quotidienne (clé privée chiffrée, hors de `adm01`, procédure écrite).
- `ssh_durci` : `MaxAuthTries 3`, `AllowTcpForwarding yes` sur `adm01` seulement (M04-E11).
- Flux actuels de `wg1` (VPN d'administration, M00-E16) : tout MGMT et tout INFRA.
- Outillage : script `ms-ssh-cert` à ajouter à `plateforme/outils` (`bin/`), pour obtenir le certificat du jour.

> ⚠️ **Attention** : cet exercice retire ta clé quotidienne des hôtes. Avant l'étape 5 : vérifie le compte `secours` sur la console de deux hôtes (`qm terminal`), garde une session SSH ouverte sur `dns01` et sur `gw01`, et teste la clé de bris de glace. Retour arrière : remettre ta clé dans `ms_cles_admin` et rejouer le rôle `base` depuis une session restée ouverte ou depuis la console.

**Travail demandé**
1. Écris le rôle `ssh_ca_utilisateur` : clé(s) de la CA d'utilisateur, un fichier de principaux par compte (propriété de root), fichier de `sshd_config.d` validé, contrôle sur la configuration **effective** (`sshd -T`). Scénario Molecule (le même que `ssh_ca_hote` peut porter les deux rôles). Applique au socle.
2. Écris `ms-ssh-cert` : signe `~/.ssh/id_ed25519.pub` pour 16 h avec le principal `admin` (options : autres principaux, autre clé publique, statut), puis remplace dans l'agent l'ancien certificat par le nouveau. Pourquoi faut-il **retirer** l'ancien certificat de l'agent ?
3. Prouve l'accès par certificat, avec `-o ControlPath=none`, et retrouve dans `journalctl -u ssh` de l'hôte la ligne qui donne l'identité (`ID`) et le numéro de série du certificat.
4. Astreinte : signe pour Nadia (une clé de test sur `adm01` suffit) un certificat portant **seulement** le principal `astreinte`, de 8 h. Prouve qu'il ouvre le compte `admin` et qu'un certificat portant `stagiaire` est refusé.
5. Bris de glace : génère la clé, range la clé privée chiffrée hors de `adm01` (documente où), et remplace ta clé quotidienne par elle dans `ms_cles_admin` (et `host_vars/adm01/`). Applique, puis prouve que ta clé **sans** son certificat est refusée.
6. Bastion : dans `host_vars/gw01/pare_feu.yml`, le VPN d'administration n'atteint plus en SSH que `adm01` ; il garde l'HTTPS vers INFRA (GitLab, NetBox, `ca01`). Depuis ton poste, configure `ProxyJump` par `adm01` ; pour que le saut final fonctionne, ton poste a besoin d'un certificat : fais-le signer sur `adm01` (`ms-ssh-cert --cle …`) et rapporte-le.
7. Réponds dans ton journal : qui peut obtenir un certificat aujourd'hui, et que faudrait-il pour que ce soit nominatif (pense au module 24) ? Que se passe-t-il si `ca01` est en panne un lundi matin ?

**Critères de réussite**
- [ ] Sur chaque hôte du socle, `sshd -T` montre `TrustedUserCAKeys` et `AuthorizedPrincipalsFile` du rôle ; les principaux de `admin` sont `admin` et `astreinte`.
- [ ] `~/.ssh/id_ed25519-cert.pub` de `adm01` est valide, de 16 h au plus, avec le principal `admin`, et une connexion sans multiplexage aboutit grâce à lui (journal de l'hôte à l'appui).
- [ ] Ta clé quotidienne n'est plus dans `authorized_keys` des hôtes du socle ; la clé de bris de glace et `ansible-ci` y sont.
- [ ] Depuis le VPN, seul `adm01` est joignable en SSH ; le saut par `adm01` fonctionne.

**Vérification** : `lab/bin/check 06 20`

<details><summary>Indice 1</summary>

Sans `AuthorizedPrincipalsFile`, un principal du certificat doit être **égal** au nom du compte. Avec, il doit figurer dans le fichier du compte (`%u`). Ce fichier ne doit pas être modifiable par le compte lui-même.
</details>

<details><summary>Indice 2</summary>

`ssh-add <clé>` charge aussi `<clé>-cert.pub` s'il existe ; `ssh-add -d <certificat>` retire le seul certificat. Chaque identité refusée par le serveur compte dans `MaxAuthTries`.
</details>

<details><summary>Indice 3</summary>

Dans la matrice des flux, une règle de transit sans `proto` ni `ports` laisse tout passer. Remplace-la par des règles ciblées, et vérifie avec ton poste **avant** de fermer ta session sur `gw01` : le filet anti-coupure du rôle `pare_feu` (M04-E17) ne protège que la session SSH vers `gw01` lui-même.
</details>

**Pour aller plus loin** (facultatif) : une liste de révocation de clés (`RevokedKeys`, `ssh-keygen -k`) permet de retirer un certificat avant son terme. Combien de temps vaut-il la peine d'en tenir une pour des certificats de 16 h ? Et pour ceux d'hôte, de 30 jours ?

---

### M06-E21 — Une heure de référence fiable et authentifiée  `LAB` `★★`

> **Ticket SEC-731** — *De : Sophie Laurent*
> Avec des certificats de 30 jours et des certificats SSH de 16 h, l'heure devient un composant de sécurité : une horloge qui dérive de deux jours refuse des certificats valides ou en accepte d'expirés. Or `gw01` prend l'heure sur Internet en NTP en clair, et le lab la prend chez `gw01` en clair. Je veux une chaîne de temps authentifiée de bout en bout, et des mesures pour le prouver.

**Objectifs pédagogiques**
- Configurer chrony avec NTS (*Network Time Security*) côté client et côté serveur.
- Émettre un certificat de serveur NTS par ACME, avec des adresses IP dans le certificat, et ouvrir les flux nécessaires.
- Mesurer la qualité du temps (`tracking`, `sources`, `sourcestats`, `authdata`).

**Prérequis** : M00-E31 (`gw01` serveur de temps), M04-E10 (rôle `base`, client chrony), M04-E17 (`pare_feu`), M06-E18 (`certificats_acme`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- chrony 4.6 (Debian 13) : option `nts` des directives `server`/`pool` ; `ntsservercert`, `ntsserverkey` pour servir NTS ; échange de clés NTS-KE sur **TCP 4460**, puis NTP authentifié sur UDP 123. Les fichiers de certificat doivent être lisibles par l'utilisateur `_chrony` ; chrony ne les relit **pas** à chaud.
- Le client vérifie le certificat NTS avec le magasin du système (la racine MédiSphère y est) et le **nom ou l'adresse** qu'il a utilisé dans sa directive `server`. Les clients du lab interrogent la passerelle de leur VLAN **par adresse** (PLAN §4.3 bis, rôle `base`).
- Configuration actuelle de `gw01` : `chrony.conf` de Debian (pools en clair) + `conf.d/10-serveur-lab.conf` (M00-E31), hors Ansible (`base_chrony_client: false`).
- ACME pour `gw01` : `ca01` doit joindre `gw01` sur le port 80 pour le défi HTTP-01, pour chaque nom et chaque adresse du certificat.
- Serveurs NTS publics connus : `time.cloudflare.com`, `nts.netnod.se`, `ptbtime1.ptb.de`, `ntppool1.time.nl` (vérifie qu'ils sont toujours en service).

**Travail demandé**
1. Mesure l'état de départ sur `gw01` et sur `dns01` : `chronyc tracking`, `sources -v`, `sourcestats`, `authdata`. Note le décalage, la dispersion, la strate.
2. Pare-feu de `gw01` (dans `pare_feu.yml`) : ce qu'il faut pour le défi ACME de `ca01`, et NTS-KE depuis les VLANs du lab et depuis PAR2. Rien d'autre.
3. Certificat NTS de `gw01` avec `certificats_acme` : quels noms et quelles **adresses** y mettre, et pourquoi ? Où le poser pour `chrony` (pense au profil AppArmor de `chronyd`) ? Quel rechargement après renouvellement ?
4. Écris le rôle `chrony_serveur` pour `gw01` (reprend M00-E31) : sources Internet NTS seulement, service du lab inchangé (NTP), NTS servi au lab, contrôle après redémarrage qu'au moins deux sources sont authentifiées. Retire la configuration manuelle de M00-E31.
5. Étends le rôle `base` : une variable qui ajoute `nts` à la source des clients. Déploie d'abord sur `adm01`, contrôle `chronyc authdata`, puis sur le reste du socle par le pipeline.
6. Mesure de nouveau (étape 1) et compare. Puis simule la perte d'Internet sur `gw01` (règle temporaire, ou coupe une source) et observe : que fait `gw01`, que font les clients ?
7. Réponds dans ton journal : quel est le problème de l'œuf et de la poule entre NTS et une VM restaurée dont l'horloge a un mois d'avance ? Que propose chrony (`nocerttimecheck`), et pourquoi ne l'actives-tu pas sur le socle ?

**Critères de réussite**
- [ ] `gw01` n'a que des sources NTS, dont au moins deux authentifiées (`chronyc authdata`) et sélectionnables.
- [ ] `gw01` écoute NTS-KE (TCP 4460) et présente un certificat de `ca01` valable pour ses adresses de passerelle.
- [ ] `adm01` et `dns01` synchronisent leur horloge sur leur passerelle en NTS.
- [ ] Les flux ajoutés sont dans `pare_feu.yml`, ciblés et commentés ; la configuration de chrony de `gw01` est gérée par Ansible.

**Vérification** : `lab/bin/check 06 21`

<details><summary>Indice 1</summary>

`chronyc -N authdata` : colonne *Mode* (`NTS` ou `-`), *KeyID*, *Cook* (cookies restants). `ss -ltnp 'sport = :4460'` sur `gw01` montre `chronyd` seulement si `ntsservercert` et `ntsserverkey` sont valides.
</details>

<details><summary>Indice 2</summary>

Un certificat peut contenir des adresses IP (SAN de type IP) ; step-ca les accepte en ACME si le défi HTTP-01 réussit **sur cette adresse**. Toutes les adresses .1 du lab sont celles de `gw01` : `ca01` les joint toutes en entrant par `ens19.20`.
</details>

<details><summary>Indice 3</summary>

La directive `leapseclist` du `chrony.conf` de Debian 13 est propre à chrony 4.6 : `chronyd -p -f <fichier>` valide une configuration complète avant de la poser.
</details>

**Pour aller plus loin** (facultatif) : `chronyc ntpdata` et le *Root delay* / *Root dispersion* : calcule la borne d'erreur que `adm01` peut garantir. Lis ce que la RFC 8915 dit des cookies NTS et pourquoi le serveur n'a pas d'état par client.

---
### M06-E22 — Revue de la configuration DNS du stagiaire  `REV` `★★`

> **Ticket PLAT-732** — *De : Karim Benali* — *Copie : Lucas Martin*
> Lucas prépare la maquette DNS du futur site PAR2 (`dns21`, une VM PowerDNS autonome qui servira `par2.medisphere.internal` en attendant la réplication). Il m'a envoyé sa configuration « qui marche sur sa VM » et un script pour ajouter des enregistrements par l'API. Fais-lui une vraie revue avant qu'on la déploie : chaque défaut, sa gravité, ce qu'il casserait **chez nous**, la correction.

**Objectifs pédagogiques**
- Relire une configuration DNS (serveur faisant autorité, récurseur, zone) et un script d'API comme ils s'exécuteront dans le lab.
- Repérer les défauts de sécurité (résolveur ouvert, API exposée, transferts et mises à jour non contrôlés, secret en clair) et de fonctionnement (boucle de relais, conflits de ports, zone mal formée).
- Rédiger une revue utile à son destinataire.

**Prérequis** : M06-E06 à M06-E08, M06-E14, M06-E17.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers : `ressources/M06-E22/` (`MR-lucas.md`, `pdns.conf`, `recursor.yml`, `zone-par2.txt` — sortie de `pdnsutil zone list` —, `ajouter-enregistrement.sh`). La clé d'API qu'ils contiennent est **fictive**.
- Contexte voulu par Lucas : `dns21` (adresse prévue 10.20.20.10, PAR2 INFRA), récurseur pour les clients de PAR2, autoritaire pour `par2.medisphere.internal`, l'automatisation (`runner01`) ajoute des enregistrements par l'API.
- Lucas a testé sur une VM de la sandbox, seul client, sans pare-feu.

**Travail demandé**
1. Lis tout sans rien noter. Puis réponds : que fait chaque fichier au démarrage ? Qui peut interroger ce serveur, qui peut le modifier, qui peut lire toute la zone ?
2. Rédige la revue en tableau : n°, fichier et ligne(s), défaut, catégorie (sécurité, fonctionnement, exploitation), gravité (critique, élevée, moyenne, faible), impact concret dans **notre** lab, correction.
3. Classe les défauts par ordre de traitement et justifie le premier.
4. Propose les versions corrigées de `pdns.conf` et `recursor.yml` (inutile de tout réécrire : les lignes qui changent).
5. Question de fond (dix lignes) : un serveur faisant autorité et un récurseur sur la même VM, est-ce une bonne idée pour PAR2 ? Qu'aurait apporté la réplication par transfert de zone (E24) ?
6. Trois lignes de conseils à Lucas sur sa façon de tester.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 14 défauts identifiés, dont tous les défauts critiques et élevés du corrigé.
- [ ] Chaque défaut a un impact concret et une correction précise (option, valeur).
- [ ] La question de fond reçoit une réponse argumentée.

<details><summary>Indice 1</summary>

Pour chaque directive d'écoute ou d'autorisation, demande-toi « depuis quelles adresses ? ». Pour chaque relais de zone, suis le paquet : vers quelle adresse, quel port, et qui y écoute ?
</details>

<details><summary>Indice 2</summary>

Dans la zone, lis les noms en entier : un nom sans point final est relatif à la zone. Regarde aussi ce que répond la zone pour un nom qui n'existe pas.
</details>

<details><summary>Indice 3</summary>

Dans le script, suis la clé d'API (où est-elle écrite, où passe-t-elle, qui la voit) et l'erreur (que se passe-t-il si l'API répond 422 ?).
</details>

**Pour aller plus loin** (facultatif) : écris le test (Molecule ou script `dig`) qui aurait attrapé les trois défauts les plus graves avant la MR.

---

### M06-E23 — Runbook : ajouter un hôte au socle  `RED` `★★`

> **Ticket CHG-733** — *De : Nadia Roussel*
> Au module 07 vont arriver de nouveaux hôtes permanents, et l'astreinte devra savoir en ajouter un, ou en reconstruire un, sans toi. Écris **RB-060** : de la réservation de l'adresse dans NetBox jusqu'au premier passage vert de la supervision, dans l'ordre où les outils dépendent les uns des autres, avec le contrôle de chaque étape et le retour arrière. Je le jouerai en ajoutant une VM d'essai.

**Objectifs pédagogiques**
- Enchaîner les services du socle (NetBox, OpenTofu, PowerDNS, Proxmox, Ansible, step-ca, pare-feu, sauvegardes) en une procédure exécutable par quelqu'un d'autre.
- Rendre chaque étape vérifiable et réversible.
- Rendre visibles les dépendances entre outils (ce qui doit exister avant quoi).

**Prérequis** : M06-E10 à M06-E21.
**Durée indicative** : 2 h.

**Contexte technique**
- Emplacement : `docs/socle/runbooks/RB-060-ajouter-un-hote-au-socle.md` dans `plateforme/medisphere`, sur le modèle de RB-040 (M04-E22).
- L'hôte à ajouter a un rôle propre (un rôle Ansible existe ou est à écrire), une adresse fixée par le PLAN ou allouée par NetBox, et peut avoir besoin d'un certificat TLS et de flux réseau nouveaux.
- Le runbook remplace la procédure « ajout d'un hôte permanent » des modules précédents (`host-record` dnsmasq, alias SSH, `inventaire.md`) : signale ce qui disparaît.

**Travail demandé**
Rédige RB-060 avec au moins : quand l'utiliser (création, reconstruction à l'identique, et ce qui n'en relève pas), prérequis (accès, secrets, outils, droits), schéma ou liste des dépendances entre étapes, étapes numérotées avec pour chacune la commande ou l'écran, le résultat attendu et quoi faire sinon (NetBox, OpenTofu et DNS, Proxmox, synchronisation, inventaire Ansible, certificats SSH d'hôte, configuration par le pipeline, certificat TLS, pare-feu, sauvegardes, supervision, documentation), contrôle final, retour arrière par étape (et l'ordre inverse pour une suppression), pièges connus. Joue-le toi-même avec la VM d'essai 2061, corrige chaque hésitation, puis fais-le relire par MR (Nadia et Karim).

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Quelqu'un qui n'a pas fait le module l'exécute sans question ; chaque étape a son contrôle.
- [ ] L'ordre respecte les dépendances (adresse avant VM, nom avant certificat, inventaire avant configuration, flux avant service).
- [ ] Le retour arrière ne laisse ni adresse réservée, ni nom, ni certificat valide, ni règle de pare-feu orphelins.
- [ ] Les gestes manuels des modules précédents sont explicitement retirés.

**Pour aller plus loin** (facultatif) : identifie les étapes qui demandent encore une décision humaine et celles qu'un pipeline pourrait enchaîner seul ; esquisse ce pipeline.
