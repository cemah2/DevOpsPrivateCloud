# Module 25 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné : `infra/` pour `plateforme/infra`, `ansible/` pour `plateforme/ansible`, `identite/` pour `plateforme/identite`, `secrets/` pour `plateforme/secrets`, `outils/` pour `plateforme/outils`, `medisphere/` pour la documentation. Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie : `M25-E02/` (inventaire), `M25-E03/` (VM, rôles `openbao` et `outils_openbao`, outil des parts, garde des parts), `M25-E04/` (conventions KV), `M25-E05/` (modèle d'accès), `M25-E06/` (client Keycloak), `M25-E07/` (`medictl`), `M25-E08/` (projet `plateforme/secrets` complet, dont les **politiques** écrites en E05 et E07, dans leur version finale).

**Ce qui a été vérifié à la rédaction** :
- **OpenBao 2.6.4 réel** (paquet `openbao_2.6.4_linux_amd64.deb` de la publication, empreinte comparée à `checksums.txt`) : contenu du paquet (`openbao.hcl` d'exemple en stockage `file`, unité `Type=notify`, `ProtectSystem=full`, `MemorySwapMax=0`, `ExecReload` par `SIGHUP` ; `preinst` en `useradd --system --user-group`, `postinst` qui génère un certificat auto-signé dans `/opt/openbao/tls`) ; serveur lancé avec la configuration rendue par le rôle (Raft, TLS par une hiérarchie de test racine EC → feuille aux deux noms) ; `bao operator validate-config` (0 succès, 2 avertissement, 1 échec) ; **`disable_mlock` ignoré avec un avertissement** (« unknown or unsupported field ») au démarrage, donc **refusé** par la validation du rôle (code 2) ;
- **l'initialisation complète d'E03** par `outils/openbao-parts.sh` : `bao operator init -format=json` → chiffrement `age` des cinq parts et du jeton racine → `ansible-vault encrypt` lisant l'entrée standard ; `resume` ; descellement par trois dépositaires (refus clair avec la mauvaise identité) ; `jeton-racine` vers `~/.vault-token` ; redémarrage → scellé (`bao status` code 2, `sys/health` 503, toute requête « Vault is sealed ») ; contenu de `/var/lib/openbao` (chemins internes lisibles, valeurs chiffrées, la valeur d'un secret introuvable dans les fichiers) ;
- **E04 à E07 contre ce serveur** : KV v2 (versions, `delete`/`undelete`/`destroy`, CAS, métadonnées, `kv patch` des métadonnées, valeur par l'entrée standard, API par `curl -K`) ; politiques et `bao token capabilities` (dont la **priorité entre motifs** qui masque une écriture, `sudo` exigé pour `sys/auth/*` et `sys/audit` mais pas pour `sys/mounts/*`, une liste qui vise le chemin à barre finale, `*` qui couvre la chaîne vide) ; jetons (TTL, période, orphelin refusé sans sudo, révocation en cascade par accessor, `generate-root -status` avec une politique sur `sys/generate-root-token/*`) ; **OIDC contre un Keycloak 26.7.5** (royaume, portée `groupes`, client confidentiel PKCE S256) : flux complet scripté, OpenBao envoie bien `code_challenge_method=S256`, groupes externes → `identity_policies`, la configuration relue ne contient pas le secret ; **AppRole** (`secret_id_ttl` ramené à 768 h, jetons *batch* liés à une adresse, sans `default`) ; `bao_api` de `check-lib.sh` avec la politique `wb-checks`, refus de `kv/data` ;
- **`medictl`** : `coffre.py` et `config.py` sur la base du M02-E20 : 115 tests verts (`pytest`), `ruff check` et `ruff format` propres ; lecture réelle d'un secret avec l'AppRole `medictl`, et refus propre (« 403 : 1 error occurred: * permission denied ») hors de son chemin ;
- **E08 de bout en bout** avec OpenTofu 1.13.2 et `hashicorp/vault` 5.13.0 : import des 23 objets créés à la main (plan `23 to import, 14 to change`), apply, **plan vide** ; ressource éphémère + `oidc_client_secret_wo` (le secret n'est ni dans l'état ni dans le plan ; connexion OIDC toujours fonctionnelle après l'apply) ; plan et apply avec le **jeton OIDC** d'un administrateur (jeton enfant du fournisseur) ; client Keycloak `openbao` créé par `clients-openbao.tf` et secret envoyé dans `kv` par `tofu output -raw … | bao kv put … client_secret=-` ;
- rôles Ansible `openbao` et `outils_openbao` : `ansible-lint` 26 (profil `production`) sans erreur, gabarits rendus et validés par `bao operator validate-config` ;
- **tous les checks** (`check-E03.sh` à `check-E08.sh`) exécutés contre ce serveur avec des doublures de GitLab, NetBox et SSH, dans les deux modes d'accès (AppRole `wb-checks` et jeton de session), et chaque contrôle sensible mis en échec volontairement (jeton d'essai oublié, politique modifiée à la main, politique en trop, jeton racine vivant) ; `shellcheck -x` et `bash -n` sur tous les scripts.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- la **VM** `vault01` et le rôle sur une vraie Debian 13 (tâches `apt deb:`, `systemd`, surcharge, `certificats_acme` avec un défi HTTP-01 pour deux noms, rechargement par `SIGHUP` au renouvellement) ; la signature GPG de `checksums.txt` (la clé de signature d'OpenBao n'a pas été relevée ici : prends-la sur la page de téléchargement officielle et recoupe son empreinte avec une seconde source) ;
- l'**interface web** (chemin de rappel `/ui/vault/auth/oidc/oidc/callback`, OTP de Keycloak dans le flux) et `bao login -method=oidc` à travers un tunnel SSH (le flux a été vérifié par l'API, pas par la CLI interactive) ;
- les **identités `age` protégées par phrase de passe** (`age -p`, puis `age -d -i fichier.age` qui demande la phrase) : testé avec des identités en clair seulement ;
- la **liaison d'adresse** des AppRole à 10.10.10.10 : elle suppose que `vault01` voit l'adresse réelle d'`adm01` (pas de traduction d'adresse entre VLAN, M07) ;
- l'effet de la **réappartenance à un groupe** pendant la vie d'un jeton OIDC (E06, étape 8) : décrit d'après la documentation de l'identité, non chronométré ;
- la synchronisation NetBox du M06 avec le secret lu dans le coffre (unité non relancée ici) ;
- le comportement du fournisseur OpenTofu avec le **jeton racine** : un échec (`lookup-self` 403 sur le jeton enfant) a été vu à la rédaction, mais la relecture n'a pas pu le reproduire (plan et apply acceptés avec la racine contre un serveur `-dev` 2.6.4) ; on ne s'en sert de toute façon jamais avec la racine.

**Ce qui reste promis** (modules précédents) : le M02-E19 annonçait que `medictl` lirait son secret dans le coffre : **tenu** en E07 pour les jetons Proxmox (le jeton NetBox et la clé PowerDNS de `medictl` suivent le même chemin, laissé en « Pour aller plus loin » et repris au mini-projet M25-E46). Le M04 annonçait que le mot de passe d'Ansible Vault sortirait du disque d'`adm01` : c'est M25-E11. Le registre des secrets du M01 (`docs/socle/registre-secrets.md`) est complété, pas remplacé, par l'inventaire d'E02. Le client `openbao` annoncé par le M24 est créé en E06.

---

### M25-E01 — Test de positionnement : secrets

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 28. En dessous de 14, relis les « Concepts clés » de l'introduction avant E03 ; les questions 2 à 4 et 12 sont reprises en E07 et M25-E14, 5 à 8 en E04 et M25-E12, 9 à 11 en M25-E10 et M25-E23, 13 et 14 en M25-E23 et M25-E31.

**1. Secret ou configuration.** Secrets : le mot de passe PostgreSQL, la clé **secrète** S3 (et, par prudence, la clé d'accès S3, qui n'est qu'un identifiant mais qu'on range avec son secret parce qu'elles tournent ensemble), la clé privée TLS. Configuration : l'adresse de la base, le nom d'utilisateur, le nom du compartiment, le niveau de journalisation, le certificat public. Critère : **la connaissance de la valeur donne-t-elle un pouvoir** (se connecter, déchiffrer, se faire passer pour quelqu'un) ? Si oui, c'est un secret, même si la valeur semble anodine. Un nom d'utilisateur aide un attaquant, mais ne suffit pas.

**2. Durée de vie.** C'est le temps pendant lequel une valeur donne un pouvoir. À valeur égale, un secret d'une heure laisse à un voleur une heure (et une seule cible : ce qu'il a volé au moment du vol) ; un secret de trois ans sert à quiconque l'a vu un jour en trois ans : anciens collaborateurs, sauvegardes, journaux, postes perdus. Raccourcir : **rotation planifiée** (nouvelle valeur tous les 90 jours, sans coupure), et **identifiants dynamiques** (un rôle PostgreSQL créé par le coffre pour une heure, détruit ensuite, M25-E14).

**3. Réponse B.** Le risque d'un secret qui ne change jamais est l'**exposition cumulée** : tout ce qui l'a connu peut encore s'en servir (InfoGér, le `.env` de Lucas). A est faux : un mot de passe ne s'use pas, ce qui s'use, c'est sa confidentialité. C est faux : PostgreSQL n'impose rien de tel (`VALID UNTIL` existe, mais n'est pas posé par défaut). D est faux : la longueur protège de la devinette, pas de la fuite.

**4. Secret zéro.** Le premier secret qu'on doit confier à une machine pour qu'elle puisse s'authentifier auprès du coffre et obtenir les autres. Pour un pod : il lui faut une preuve d'identité. Si on lui donne un jeton OpenBao dans un Secret, ce jeton est un secret durable de plus, le problème n'a fait que reculer. La bonne réponse est une identité **fournie par la plateforme**, que personne n'a à stocker : le jeton de compte de service projeté par Kubernetes (court, signé, à audience précise), présenté à la méthode `kubernetes` d'OpenBao (M25-E12) ; de même le jeton OIDC d'un job GitLab (M25-E10). Quand il faut vraiment un secret (AppRole sur une VM, E07), on le **réduit** : lié à une adresse, court ou à usage unique, livré par enveloppement (M25-E28).

**5. Au repos, en transit, en usage.** Au repos : les données sur disque (Raft d'OpenBao chiffré par la barrière, etcd chiffré par `secretbox` au M14, sauvegardes chiffrées par `age`) ; manque : les volumes Ceph des bases ne sont pas chiffrés (ADR-0160). En transit : TLS partout (step-ca), WireGuard entre sites ; manque : le trafic entre pods n'est pas chiffré (chiffrement transparent de Cilium au M26). En usage : la donnée en mémoire pendant son traitement ; c'est le plus difficile (enclaves, confidential computing) : on se contente de limiter qui peut lire la mémoire (pas de vidage mémoire, pas de swap, processus non privilégiés), ce que fait OpenBao (E03).

**6. Réponse B.** Un Secret Kubernetes est stocké chiffré dans etcd **si** on l'a configuré (M14), mais l'API le rend **décodé du chiffrement et seulement encodé en base64** à quiconque a `get` sur les Secrets de l'espace. A est faux : la base64 n'est pas un chiffrement ; C est faux : rien n'est haché ; D est faux : l'API les rend, c'est leur raison d'être. D'où la règle des modules précédents : les rôles de lecture (`medisphere-lecture`, `wb-checks`) n'ont jamais `get` sur les Secrets.

**7. Variable ou fichier.** Variable d'environnement : héritée par **tous** les processus enfants, visible dans `/proc/<pid>/environ` (même utilisateur et root), souvent recopiée dans les traces d'erreur et les rapports de plantage, figée jusqu'au redémarrage. Fichier monté : droits par fichier, pas d'héritage automatique, peut être **remplacé à chaud** (l'application le relit, M25-E15), moins souvent journalisé. Les deux restent lisibles par root et par l'application compromise. Préférer le fichier, en mémoire (`tmpfs`) quand c'est possible.

**8. Argument de commande.** La ligne de commande est lisible par **tous les utilisateurs** de la machine (`ps aux`, `/proc/<pid>/cmdline`), écrite dans l'historique du shell, souvent dans les journaux d'audit (`auditd`, `execve`) et les traces de CI. Correct : lire depuis un fichier ou l'entrée standard (`mysql --defaults-extra-file=…`, `PGPASSFILE`, `curl -K fichier` ou `-K <(…)`, `bao kv put … champ=-`), ou une variable d'environnement si l'outil ne sait faire que cela.

**9. Variable masquée.** Garanti : GitLab remplace la valeur par `[MASKED]` quand elle apparaît **telle quelle** dans le journal du job. Pas garanti : un job qui la transforme (base64, `rev`, un caractère sur deux, une URL encodée) la fait sortir en clair ; un job qui l'écrit dans un **artefact** ou l'envoie ailleurs (un `curl` vers l'extérieur) aussi ; le masquage ne protège pas non plus contre quelqu'un qui modifie `.gitlab-ci.yml` sur une branche ayant accès à la variable (d'où « protégée »). C'est pourquoi le M25-E10 remplace les secrets durables de CI par une identité.

**10. Réponse A.** Ansible Vault est un **fichier chiffré par un mot de passe** : tout ou rien. Qui a le mot de passe d'une identité a tous les secrets de cette identité, sans trace de qui a déchiffré quoi, et la rotation d'une valeur est une MR manuelle. B est faux (aucun droit par secret) ; C est faux (aucune rotation) ; D est faux (aucun journal de lecture : GitLab voit des commits, pas des déchiffrements). C'est exactement ce qu'un coffre apporte : droits par chemin, audit par lecture, rotation.

**11. Le `.env` commité.** Oui, il est exposé : le commit qui l'ajoute est dans l'historique, donc dans chaque clone, chaque cache de runner, chaque fork, chaque sauvegarde de GitLab, et sur le serveur jusqu'au nettoyage. Ordre : (1) **révoquer ou faire tourner** chaque secret du fichier, tout de suite : c'est la seule mesure qui rend la fuite inoffensive ; (2) évaluer qui a pu le lire (journaux d'accès au dépôt, forks, clones des runners) et ce que les secrets ont permis entre-temps (journaux des services) ; (3) seulement ensuite, réécrire l'historique (`git filter-repo`), purger GitLab (nettoyage du dépôt, références de MR) ; (4) prévenir (gitleaks en pré-commit et en CI, M19). La réécriture ne suffit pas car elle n'efface pas les **copies** déjà faites ; et un secret retiré de l'historique mais pas changé reste valable.

**12. Secret dynamique.** Un secret **créé à la demande** pour un demandeur, avec un bail : par exemple OpenBao crée dans PostgreSQL un rôle `v-mediagenda-api-x7Kq…` avec un mot de passe aléatoire et les droits de l'application, valable une heure. Chaque instance de l'application a le sien. À l'expiration du bail (ou à sa révocation), OpenBao **supprime le rôle** dans PostgreSQL : le mot de passe ne vaut plus rien, même volé. L'application renouvelle son bail ou en demande un nouveau (ESO s'en charge au M25-E14).

**13. Réponse à une fuite.** (1) **Détecter et qualifier** : quel secret, depuis quand, exposé à qui (preuve : le ticket, ses journaux d'accès). (2) **Contenir** : révoquer ou faire tourner, en commençant par le plus critique (preuve : horodatage de la rotation, ancienne valeur refusée). (3) **Évaluer l'usage** : la valeur a-t-elle servi entre l'exposition et la révocation ? (preuve : journaux d'audit du service et du coffre). (4) **Éradiquer** la copie (ticket purgé, historique réécrit). (5) **Communiquer** (Sophie, direction ; notification CNIL dans les 72 h si des données personnelles ont pu être lues : RGPD). (6) **Corriger la cause** (pourquoi un `.env` existait-il ? → identités et coffre). (7) **Post-mortem** et mise à jour du runbook RB-250 (M25-E23). L'auditeur HDS veut la chronologie et les preuves de chaque étape.

**14. Le coffre, cible.** Il concentre tous les secrets : le compromettre, c'est tout compromettre, et l'arrêter, c'est arrêter tout ce qui en dépend. Mesures : (a) **réduire ce qu'un jeton peut faire** (moindre privilège, pas de racine, jetons courts) et **auditer** chaque accès ; (b) **protéger les clés** (Shamir avec plusieurs dépositaires, puis auto-descellement par un service séparé, jamais la clé à côté des données) et durcir l'hôte (pas de vidage mémoire, systemd restreint, réseau filtré) ; (c) **le rendre disponible et récupérable** (grappe, instantanés chiffrés restaurés pour de vrai, procédure de bris de glace écrite), et préférer des secrets dynamiques courts pour qu'une compromission passée vaille peu.

---

### M25-E02 — Inventaire des secrets de MédiSphère

**Solution**

Inventaire complet : [`inventaire-secrets.md`](fichiers/M25-E02/medisphere/docs/securite/secrets/inventaire-secrets.md) (37 lignes, échelle C1-C3, six cibles, constats).

Commandes du relevé, aucune ne montre une valeur :

```
admin@adm01:~/src/ansible$ find ~/src -name 'vault*.yml' -not -path '*/.git/*' | while read -r f; do
>   printf '%s : %s\n' "$f" "$(head -n 1 "$f" | cut -d';' -f4)"; done
admin@adm01:~/src/ansible$ uv run ansible-vault view inventories/lab/host_vars/idp01/vault-critique.yml | grep -o '^[a-z_]*:'
vault_keycloak_bdd_mot_de_passe:
admin@adm01:~$ for p in plateforme%2Finfra plateforme%2Fansible plateforme%2Fk8s plateforme%2Fidentite; do
>   gitlab_api() { curl -sf -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<~/.config/workbook/gitlab-admin.token)") \
>     "https://git01.par1.medisphere.internal/api/v4/$1"; }
>   gitlab_api "projects/$p/variables" | jq -r --arg p "$p" '.[] | del(.value) | "\($p) \(.key) protégée=\(.protected) masquée=\(.masked) portée=\(.environment_scope)"'
> done
admin@adm01:~$ gitlab_api "groups/plateforme/variables" | jq -r '.[] | del(.value) | "\(.key) protégée=\(.protected)"'
admin@adm01:~$ kubectl get secret -A -o custom-columns='ESPACE:.metadata.namespace,NOM:.metadata.name,TYPE:.type,GERE-PAR:.metadata.labels.app\.kubernetes\.io/managed-by' \
>   | grep -v 'kubernetes.io/service-account-token'
admin@adm01:~$ grep -v '^#' ~/src/k8s/outils/secrets-k8s.conf | awk '{print $1, $2, $3}'
admin@adm01:~$ ls -la ~/.config/workbook/ ~/.ssh/
```

Pour le cluster, il faut un compte qui a le droit de **lister** les Secrets (ton contexte d'administrateur) ; `custom-columns` n'affiche que les métadonnées. L'origine se lit dans les étiquettes (`managed-by: Helm`, `cnpg.io/cluster`, `cert-manager.io/…`) ; ce qui n'a aucune étiquette vient de `secrets-k8s.sh` ou d'une commande à la main (à corriger, M25-E13).

**Explications**

- **Plusieurs sources, parce qu'aucune n'est complète.** Le registre du M01 liste ce qu'on a pensé à y inscrire ; les variables de CI, les Secrets créés par des opérateurs (CNPG) et les fichiers de `~/.config/workbook/` y manquent souvent. L'inventaire croise le code, la CI, le cluster et les postes.
- **La criticité mesure ce qu'une fuite permet**, pas la difficulté de la valeur : le jeton `wb-automation@pve` (C1) crée et détruit des VMs ; un jeton de lecture des checks (C3) ne montre que de la configuration.
- **`AMO` n'est pas un échec.** Un coffre ne peut pas contenir ce qu'il faut pour le démarrer (ses parts), ni ce qu'il faut pour réparer la plateforme quand il est fermé (bris de glace, réseau, sauvegardes). L'erreur serait de ne pas les nommer : on les garde peu nombreux, sous scellé, et leur usage alerté.
- **Les cibles orientent le palier 2** : `ID` (E10, E12) et `DYN` (E14) **suppriment** des secrets ; `KV` les centralise ; `TR` (E17, E20) supprime la clé de l'application.

**Alternatives**

- *Un outil de découverte* (gitleaks ou trufflehog sur tous les dépôts et leur historique, `kubectl` scripté, inventaire Ansible des fichiers) pour produire l'inventaire automatiquement : utile en complément (mini-projet), mais un outil ne connaît ni le propriétaire ni la cible.
- *Tenir l'inventaire dans NetBox* (objets personnalisés) ou dans le coffre lui-même (métadonnées KV) : ce qui est dans le coffre se décrit par ses métadonnées (E04), le reste doit être écrit ailleurs ; un document versionné relu en MR reste le plus simple pour l'audit.

**Pièges classiques**

- Afficher les valeurs « pour vérifier » (`ansible-vault view` sans filtre, `kubectl get secret -o yaml`, `jq .` sur les variables de CI) : le relevé devient lui-même une fuite.
- Oublier les secrets **générés par des opérateurs** (CNPG, cert-manager, Argo CD) : ils ne sont dans aucun dépôt.
- Oublier les copies : le même secret dans un Vault, une variable de CI et un Secret Kubernetes, c'est trois lignes à faire tourner ensemble.
- Mettre au coffre les parts du coffre ou le mot de passe du Vault `critique` « pour tout centraliser » : le jour où il est fermé, plus rien ne s'ouvre.

**En production chez MédiSphère**

Inventaire revu chaque trimestre et à chaque départ, généré en partie par un job planifié (gitleaks, API GitLab, liste des Secrets du cluster, métadonnées du coffre) qui signale les écarts ; chaque nouveau secret entre dans l'inventaire par la MR qui le crée (règle de relecture) ; criticité reprise dans l'analyse de risques ISO 27001 de Sophie ; l'état de migration de chaque ligne est mis à jour au mini-projet (M25-E46).

---

### M25-E03 — Installer et initialiser OpenBao sur `vault01`

**Solution**

*A. Lire.* Notes attendues : le stockage Raft contient **tout** l'état du coffre (configuration, politiques, jetons, secrets, baux), chaque valeur chiffrée par la **barrière** (AES-256-GCM avec le trousseau) ; le trousseau est chiffré par la **clé racine** ; la clé racine n'est **pas** stockée en clair : avec Shamir, elle est découpée en parts remises aux dépositaires (OpenBao garde une version chiffrée de ce qu'il lui faut, `core/shamir-kek`, inutilisable sans les parts). `bao operator init` crée le trousseau et la clé racine, découpe celle-ci, rend les parts et un **jeton racine** une seule fois. Au redémarrage, OpenBao relit sa configuration et son stockage mais ne peut rien déchiffrer : il est **scellé**. `disable_mlock` : OpenBao a **retiré** `mlock` (2.0) ; la clé est ignorée avec un avertissement (« unknown or unsupported field disable_mlock »). Ce qui protège la mémoire : l'unité du paquet pose `MemorySwapMax=0` (le processus ne part pas en swap, cgroup v2) ; on ajoute l'interdiction des vidages mémoire (`LimitCORE=0`).

```
admin@adm01:~/m25/e03$ V=2.6.4; B=https://github.com/openbao/openbao/releases/download/v$V
admin@adm01:~/m25/e03$ curl -fsSLO $B/openbao_${V}_linux_amd64.deb -fsSLO $B/checksums.txt -fsSLO $B/checksums.txt.gpgsig
admin@adm01:~/m25/e03$ gpg --verify checksums.txt.gpgsig checksums.txt        # clé d'OpenBao importée au préalable
admin@adm01:~/m25/e03$ sha256sum -c --ignore-missing checksums.txt
openbao_2.6.4_linux_amd64.deb: OK
admin@adm01:~/m25/e03$ dpkg-deb -c openbao_2.6.4_linux_amd64.deb; dpkg-deb -e openbao_2.6.4_linux_amd64.deb ctl && cat ctl/preinst ctl/postinst
```

Le paquet installe `/usr/bin/bao`, `/etc/openbao/openbao.hcl` (exemple en stockage **`file`** dans `/opt/openbao/data`, déprécié en 2.6 et **supprimé en 2.7** : à remplacer de toute façon), `/etc/openbao/openbao.env` (vide, lu par l'unité), `/usr/lib/systemd/system/openbao.service`. `preinst` : `useradd --system --user-group --shell /bin/false openbao` (sous `set -eu` : échoue si le groupe existe). `postinst` : génère un certificat **auto-signé** RSA 4096 dans `/opt/openbao/tls` s'il n'existe pas, puis `daemon-reload` ; il ne démarre pas le service.

*B. La machine et le rôle.* [`socle/vault01.tf`](fichiers/M25-E03/infra/socle/vault01.tf) (VM, A/PTR, et `powerdns_record.openbao` de TTL 300). Rôle [`openbao`](fichiers/M25-E03/ansible/roles/openbao/) : [`defaults/main.yml`](fichiers/M25-E03/ansible/roles/openbao/defaults/main.yml), [`tasks/main.yml`](fichiers/M25-E03/ansible/roles/openbao/tasks/main.yml), [`paquet.yml`](fichiers/M25-E03/ansible/roles/openbao/tasks/paquet.yml), [`configuration.yml`](fichiers/M25-E03/ansible/roles/openbao/tasks/configuration.yml), [`service.yml`](fichiers/M25-E03/ansible/roles/openbao/tasks/service.yml), [`controles.yml`](fichiers/M25-E03/ansible/roles/openbao/tasks/controles.yml), [`handlers/main.yml`](fichiers/M25-E03/ansible/roles/openbao/handlers/main.yml), gabarits [`openbao.hcl.j2`](fichiers/M25-E03/ansible/roles/openbao/templates/openbao.hcl.j2) et [`medisphere.conf.j2`](fichiers/M25-E03/ansible/roles/openbao/templates/medisphere.conf.j2). Rôle [`outils_openbao`](fichiers/M25-E03/ansible/roles/outils_openbao/) (CLI sur `adm01`, depuis l'archive `tar.gz` de la publication, pas le `.deb` qui installerait aussi un serveur). Variables : [`group_vars/role_coffre/openbao.yml`](fichiers/M25-E03/ansible/inventories/lab/group_vars/role_coffre/openbao.yml), [`host_vars/vault01/certificats.yml`](fichiers/M25-E03/ansible/inventories/lab/host_vars/vault01/certificats.yml), [`pare_feu_local.yml`](fichiers/M25-E03/ansible/inventories/lab/host_vars/vault01/pare_feu_local.yml), [`pare_feu.yml.extrait`](fichiers/M25-E03/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; playbooks [`coffre.yml`](fichiers/M25-E03/ansible/playbooks/coffre.yml) et [`outils-openbao.yml`](fichiers/M25-E03/ansible/playbooks/outils-openbao.yml).

Les points délicats du rôle :
- **l'ordre** : le playbook appelle `openbao` avec `tasks_from: paquet` **avant** `certificats_acme` (qui donne la clé au groupe `openbao`) ; créer le groupe soi-même ferait échouer le `preinst` ;
- **la validation** : `template` avec `validate: /usr/bin/bao operator validate-config -config=%s` : une faute de syntaxe (code 1) ou une clé inconnue (code 2, par exemple `disable_mlock`) refuse le fichier avant qu'il ne remplace le bon ;
- **le redémarrage** : deux gestionnaires écoutent le même sujet ; si le service tournait **avant** le passage, l'un redémarre seulement avec `-e openbao_redemarrer=true`, l'autre affiche pourquoi il ne l'a pas fait ; à la première installation, le service démarre directement avec la bonne configuration ;
- **`force-confold`** : `openbao.hcl` est un fichier de configuration du paquet que nous remplaçons ; sans cette option, la montée de version poserait une question à `dpkg` (et un `apt` non interactif échouerait).

Le certificat porte `vault01.par1…` (utilisé par `api_addr`, `cluster_addr` et la grappe au M25-E24) et `openbao.par1…` (le nom des clients) ; le renouvellement **recharge** (`systemctl reload` = `SIGHUP`, OpenBao relit son certificat) : un `restart` scellerait le coffre à chaque renouvellement, soit tous les vingt jours.

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --limit vault01
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml
TASK [openbao : État du coffre (information)] ****
ok: [vault01] => {"msg": "vault01 : initialisé=False, scellé=True, seal=shamir. Initialisation : une fois, en cérémonie (M25-E03)."}
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/outils-openbao.yml
admin@adm01:~$ exec bash -l
admin@adm01:~$ bao status; echo "code $?"
Key                Value
---                -----
Seal Type          shamir
Initialized        false
Sealed             true
Total Shares       0
Threshold          0
Unseal Progress    0/0
Unseal Nonce       n/a
Version            2.6.4
Commit Date        2026-10-01T13:36:29Z
Storage Type       raft
HA Enabled         true
code 2
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' $BAO_ADDR/v1/sys/health
501
```

Code 2 de `bao status` : « scellé » (0 = descellé, 1 = erreur). `sys/health` encode l'état dans le code HTTP pour les répartiteurs et les sondes : **200** actif, **429** en attente (*standby*, M25-E24), **501** non initialisé, **503** scellé (les codes 472/473 de Vault, liés à sa réplication Enterprise, n'existent pas dans OpenBao) ; chaque code se règle par paramètre (`?sealedcode=…`, `?uninitcode=…`, `?standbyok=true`).

*C. Les dépositaires.* Identités créées et chiffrées d'un seul tube, aucune clé privée en clair ne touche le disque :

```
admin@adm01:~$ install -d -m 700 ~/.config/workbook/age ~/m25/e03/depositaires
admin@adm01:~$ age-keygen 2>/dev/null | age -p -a > ~/.config/workbook/age/openbao-<MOI>.age    # phrase saisie deux fois
admin@adm01:~$ for n in claire.morel karim.benali sophie.laurent nadia.roussel; do
>   echo "== $n"; age-keygen 2>/dev/null | age -p -a > ~/m25/e03/depositaires/$n.age; done
admin@adm01:~$ for n in claire.morel karim.benali sophie.laurent nadia.roussel; do
>   printf '%-15s %s\n' "$n" "$(age -d ~/m25/e03/depositaires/$n.age | age-keygen -y)"; done
admin@adm01:~$ printf '%-15s %s\n' <MOI> "$(age -d ~/.config/workbook/age/openbao-<MOI>.age | age-keygen -y)"
```

(Le résultat, dans l'ordre des parts, va dans [`pki/openbao-depositaires.txt`](fichiers/M25-E03/ansible/pki/openbao-depositaires.txt).)

Outil : [`outils/openbao-parts.sh`](fichiers/M25-E03/ansible/outils/openbao-parts.sh). Les valeurs ne circulent que dans des tubes et des variables du script : `jq` extrait une part, `age -a -r <clé publique>` la chiffre, le tout est assemblé en JSON ; au descellement, la part déchiffrée est vérifiée non vide puis envoyée à `sys/unseal` par `jq -Rc '{key: .}' | curl --data @-` (le `curl` respecte `BAO_CACERT` s'il est défini). Essai contre un serveur jetable, non initialisé, sur `adm01` (sans TLS : il n'écoute que sur la boucle locale et ne contient rien) :

```
admin@adm01:~$ install -d -m 700 ~/m25/e03/essai/donnees ~/m25/e03/essai/id
admin@adm01:~$ cat > ~/m25/e03/essai/essai.hcl <<'FIN'
storage "raft" {
  path    = "/home/admin/m25/e03/essai/donnees"
  node_id = "essai"
}
listener "tcp" {
  address     = "127.0.0.1:18200"
  tls_disable = true
}
api_addr     = "http://127.0.0.1:18200"
cluster_addr = "http://127.0.0.1:18201"
FIN
admin@adm01:~$ bao server -config=$HOME/m25/e03/essai/essai.hcl > ~/m25/e03/essai/journal 2>&1 &
admin@adm01:~$ for n in a b c d e; do age-keygen -o ~/m25/e03/essai/id/$n.txt 2>/dev/null; done
admin@adm01:~$ for n in a b c d e; do echo "$n $(age-keygen -y ~/m25/e03/essai/id/$n.txt)"; done > ~/m25/e03/essai/dest.txt
admin@adm01:~/src/ansible$ export BAO_ADDR=http://127.0.0.1:18200 PARTS_FICHIER=$HOME/m25/e03/essai/init.yml
admin@adm01:~/src/ansible$ bao operator init -format=json -key-shares=5 -key-threshold=3 \
>   | JETON_POUR=e outils/openbao-parts.sh chiffrer ~/m25/e03/essai/dest.txt \
>   | uv run ansible-vault encrypt --encrypt-vault-id critique --output "$PARTS_FICHIER" -
admin@adm01:~/src/ansible$ for i in 1 2 3; do outils/openbao-parts.sh desceller $i ~/m25/e03/essai/id/$(sed -n "${i}p" ~/m25/e03/essai/dest.txt | cut -d' ' -f1).txt; done
part acceptée : 1/3 ; scellé=true
part acceptée : 2/3 ; scellé=true
part acceptée : 0/3 ; scellé=false
admin@adm01:~/src/ansible$ kill %1; rm -rf ~/m25/e03/essai; unset PARTS_FICHIER; exec bash -l   # retour au vrai BAO_ADDR
```

(Les identités d'essai sont en clair, dans un dossier détruit aussitôt : elles ne protègent rien. Le `~/.vault-token` de l'essai disparaît au premier `bao login` suivant, ou se supprime.)

*D. La cérémonie.* Document : [`garde-des-parts.md`](fichiers/M25-E03/medisphere/docs/securite/secrets/garde-des-parts.md). Modèle de la structure chiffrée : [`openbao-init.yml.exemple`](fichiers/M25-E03/ansible/secrets/openbao-init.yml.exemple).

```
admin@adm01:~/src/ansible$ bao operator init -format=json -key-shares=5 -key-threshold=3 \
>   | JETON_POUR=<MOI> outils/openbao-parts.sh chiffrer pki/openbao-depositaires.txt \
>   | uv run ansible-vault encrypt --encrypt-vault-id critique --output secrets/openbao-init.yml -
Encryption successful
admin@adm01:~/src/ansible$ head -c 34 secrets/openbao-init.yml; echo
$ANSIBLE_VAULT;1.2;AES256;critique
admin@adm01:~/src/ansible$ outils/openbao-parts.sh resume
initialisé le 2026-10-23T09:12:44Z sur https://openbao.par1.medisphere.internal:8200 : 5 parts, seuil 3
  part 1 → claire.morel (age19npkdnynd89v…)
  part 2 → karim.benali (age1h3mvpfwfnyug…)
  part 3 → sophie.laurent (age1kwr6jnsuu2vy…)
  part 4 → nadia.roussel (age17n4k5e84v703…)
  part 5 → <MOI> (age1yccgxu0yrl34…)
  jeton racine → <MOI>
admin@adm01:~/src/ansible$ outils/openbao-parts.sh desceller 1 ~/m25/e03/depositaires/claire.morel.age
part acceptée : 1/3 ; scellé=true
admin@adm01:~/src/ansible$ outils/openbao-parts.sh desceller 2 ~/m25/e03/depositaires/sophie.laurent.age
age: error: no identity matched any of the recipients
openbao-parts : part 2 : impossible de la déchiffrer avec …/sophie.laurent.age (est-ce la bonne personne ?)
admin@adm01:~/src/ansible$ outils/openbao-parts.sh desceller 2 ~/m25/e03/depositaires/karim.benali.age
part acceptée : 2/3 ; scellé=true
admin@adm01:~/src/ansible$ outils/openbao-parts.sh desceller 5 ~/.config/workbook/age/openbao-<MOI>.age
part acceptée : 0/3 ; scellé=false
admin@adm01:~$ bao status | grep -E 'Sealed|HA Mode|Raft'
Sealed                  false
HA Mode                 active
Raft Committed Index    29
Raft Applied Index      29
```

Entre deux parts, `Unseal Progress` avance et `Unseal Nonce` identifie la tentative en cours (une part d'une autre tentative serait refusée ; `bao operator unseal -reset` recommence). Rangement : copie de `~/m25/e03/depositaires/*.age` sur `<SUPPORT>` (déjà chiffrés), vérification de chacun depuis le support (`age -d <SUPPORT>/claire.morel.age | age-keygen -y` redonne la clé publique attendue), puis `shred -u ~/m25/e03/depositaires/*.age`. MR dans `plateforme/ansible` (outil, `pki/openbao-depositaires.txt`, `secrets/openbao-init.yml`) et `plateforme/medisphere` (garde des parts avec procès-verbal rempli).

*E. La barrière.*

```
admin@vault01:~$ sudo ls -la /var/lib/openbao /var/lib/openbao/raft
-rw------- 1 openbao openbao 16801792 … vault.db
drwx------ 3 openbao openbao     4096 … raft
-rw------- 1 openbao openbao 16801792 … raft.db
drwx------ 2 openbao openbao     4096 … snapshots
admin@vault01:~$ sudo strings -n 8 /var/lib/openbao/vault.db | grep -E '^(core|sys|logical|auth)/' | head -4
core/auth/c577f5aa-5032-e989-a7dc-ab95a586d704
core/shamir-kek
logical/eb231125-…/versions/…
sys/policy/mediagenda-dev
admin@vault01:~$ sudo systemctl restart openbao
admin@adm01:~$ bao status | grep -E 'Sealed|Unseal Progress'; curl -s -o /dev/null -w '%{http_code}\n' $BAO_ADDR/v1/sys/health
Sealed             true
Unseal Progress    0/3
503
admin@adm01:~$ bao kv list -mount=kv plateforme
Error making API request.
Code: 503. Errors:
* Vault is sealed
```

`raft.db` est le journal Raft, `vault.db` la base (bbolt) qui en résulte. On y lit les **clés de stockage** (chemins internes, identifiants des montages, noms des politiques et des rôles) : c'est de la structure, pas des valeurs ; les **valeurs** sont chiffrées par la barrière (la valeur d'un secret écrit pendant l'essai n'apparaît dans aucun fichier). Conséquence pratique : une copie de `/var/lib/openbao` ou un instantané Raft ne révèle rien sans les parts, mais révèle la **forme** du coffre ; on les protège quand même (M25-E26).

```
admin@adm01:~/src/ansible$ outils/openbao-parts.sh jeton-racine ~/.config/workbook/age/openbao-<MOI>.age
jeton racine chargé dans ~/.vault-token : n'en fais que ce qu'E04 à E08 demandent, puis révoque-le (E08).
admin@adm01:~$ bao token lookup | grep -E 'display_name|policies|ttl|expire_time|orphan'
display_name        root
expire_time         <nil>
orphan              true
policies            [root]
ttl                 0s
```

Le jeton racine **n'expire jamais**, n'a pas de parent, et la politique `root` passe outre toutes les autres : c'est un compte partagé tout-puissant. Les jetons d'OpenBao commencent par `s.` (service), `b.` (*batch*), pas `hvs.` comme ceux de Vault.

**Explications**

- **Paquet amont, épinglé par empreinte.** OpenBao ne publie pas de dépôt APT ; le `.deb` de la publication, vérifié par la signature de `checksums.txt` puis par son empreinte, est l'équivalent d'un paquet signé. Le rôle épingle **version et empreinte** : changer l'une sans l'autre échoue au téléchargement.
- **Raft intégré.** Pas de base externe (Consul) à exploiter : le stockage est dans OpenBao, répliqué entre les nœuds au M25-E24 ; un nœud seul fonctionne déjà en Raft (une grappe d'un nœud), ce qui évite de migrer de stockage plus tard.
- **TLS partout, nom du service dans le certificat.** Les clients ne connaissent que `openbao.par1…` ; les nœuds se parlent par leur propre nom. Le même certificat sert aux deux.
- **Shamir et `age`.** Shamir garantit qu'aucune personne seule ne reconstitue la clé ; `age` garantit que le fichier commun ne révèle aucune part à qui n'a pas la clé privée de son dépositaire ; Ansible Vault ajoute un verrou commun et range le tout avec le reste des secrets d'amorçage. OpenBao sait chiffrer les parts lui-même pour des clés **PGP** (`-pgp-keys`) ; `age` a été préféré (déjà utilisé au M14, clés courtes, pas de trousseau GPG à gérer).
- **Les clés simulées** sont un écart assumé du lab : une seule personne a vu les cinq identités le jour de l'initialisation. En production, chaque dépositaire génère **sa** clé sur **son** poste et n'envoie que sa clé publique.

**Alternatives**

- *Conteneur* (`openbao/openbao`, Podman) sur la VM : même configuration, mise à jour par image ; le PLAN retient le paquet pour rester sur le schéma des autres services VM (systemd, Ansible).
- *Dans le cluster* (chart `openbao/openbao`) : le coffre dépendrait du cluster auquel il fournit des secrets (et de ses sauvegardes) ; on le garde dehors, comme Keycloak.
- *Initialisation PGP* (`-pgp-keys=…`, `-root-token-pgp-key=…`) : OpenBao chiffre lui-même chaque part ; mêmes garanties, outillage GPG.
- *Auto-initialisation déclarative* (*self-init*, OpenBao 2.4+) : le serveur s'initialise au premier démarrage d'après sa configuration ; pratique pour des environnements jetables, mais elle exige un seal automatique dès le départ et retire la cérémonie, que Sophie veut voir.

**Pièges classiques**

- Créer le groupe `openbao` avant le paquet : le `preinst` échoue (« group openbao exists »).
- Recopier un tutoriel de Vault avec `disable_mlock = true` : avertissement au démarrage, et refus par la validation du rôle (code 2).
- Garder le stockage `file` de l'exemple du paquet : il disparaît en 2.7 (M25-E29).
- `bao operator init` sans `-format=json` et sans tube : les parts s'affichent, restent dans le défilement du terminal, le multiplexeur, parfois un enregistrement de session.
- Un tube d'initialisation qui échoue au milieu : parts perdues ; on ne peut que détruire les données (coffre vide) et recommencer. D'où l'essai préalable.
- `recharger: systemctl restart openbao` dans le certificat : le coffre se scelle tous les vingt jours, au milieu de la nuit.
- Passer une part en argument (`bao operator unseal <part>`) : elle finit dans l'historique du shell.

**En production chez MédiSphère**

Cérémonie avec un témoin réel et des dépositaires qui génèrent leur clé eux-mêmes ; parts sur des supports séparés dans deux coffres physiques (deux sites) ; essai annuel de descellement par chaque dépositaire (sans présenter la part) ; journal d'audit actif **avant** toute écriture de secret (M25-E21) ; trois nœuds et auto-descellement (M25-E24, E25) ; supervision de `sys/health` (M25-E27).

---

### M25-E04 — Premiers pas : KV v2, versions, CLI et API

**Solution**

```
admin@adm01:~$ bao secrets enable -path=kv -version=2 -description="Secrets statiques de MédiSphère (KV v2)" kv
Success! Enabled the kv secrets engine at: kv/
admin@adm01:~$ bao write kv/config max_versions=10
admin@adm01:~$ bao read kv/config
Key                      Value
---                      -----
cas_required             false
delete_version_after     0s
max_versions             10
metadata_cas_required    false
admin@adm01:~$ for i in 1 2 3; do openssl rand -base64 24 | tr -d '\n' \
>   | bao kv put -mount=kv plateforme/essai/demo mot_de_passe=- >/dev/null; done
admin@adm01:~$ bao kv get -mount=kv -field=mot_de_passe plateforme/essai/demo | wc -c
32
admin@adm01:~$ bao kv metadata get -mount=kv plateforme/essai/demo | grep -E 'current_version|max_versions|^====== Version'
admin@adm01:~$ bao kv delete -mount=kv plateforme/essai/demo
admin@adm01:~$ bao kv get -mount=kv plateforme/essai/demo      # métadonnées seules, deletion_time renseigné, pas de données
admin@adm01:~$ bao kv undelete -mount=kv -versions=3 plateforme/essai/demo
admin@adm01:~$ bao kv destroy -mount=kv -versions=1 plateforme/essai/demo
admin@adm01:~$ bao kv get -mount=kv -version=1 plateforme/essai/demo | grep destroyed
destroyed          true
admin@adm01:~$ bao kv metadata put -mount=kv -cas-required=true -custom-metadata=proprietaire=plateforme \
>   -custom-metadata=rotation=jamais -custom-metadata=source=genere -custom-metadata=ticket=PLAT-2604 plateforme/essai/demo
admin@adm01:~$ openssl rand -base64 24 | tr -d '\n' | bao kv put -mount=kv plateforme/essai/demo mot_de_passe=-
Code: 400. Errors:
* check-and-set parameter required for this call
admin@adm01:~$ openssl rand -base64 24 | tr -d '\n' | bao kv put -mount=kv -cas=1 plateforme/essai/demo mot_de_passe=-
* check-and-set parameter did not match the current version
admin@adm01:~$ openssl rand -base64 24 | tr -d '\n' | bao kv put -mount=kv -cas=3 plateforme/essai/demo mot_de_passe=-
```

Par l'API (le jeton passe par un fichier que `curl` lit, jamais par la ligne de commande) :

```
admin@adm01:~$ H() { printf 'header = "X-Vault-Token: %s"\n' "$(bao print token)"; }
admin@adm01:~$ curl -s -K <(H) $BAO_ADDR/v1/kv/metadata/plateforme/essai/demo | jq '.data | {current_version, max_versions, cas_required}'
{ "current_version": 4, "max_versions": 0, "cas_required": true }
admin@adm01:~$ curl -s -K <(H) $BAO_ADDR/v1/kv/data/plateforme/essai/demo | jq -r '.data.data.mot_de_passe | length'
32
admin@adm01:~$ curl -s -K <(H) -X LIST $BAO_ADDR/v1/kv/metadata/plateforme | jq -c .data.keys
["essai/"]
admin@adm01:~$ bao kv get -mount=kv -output-curl-string plateforme/essai/demo
curl -H "X-Vault-Token: $(bao print token)" -H "X-Vault-Request: true" "https://openbao.par1.medisphere.internal:8200/v1/kv/data/plateforme/essai/demo"
```

`max_versions: 0` sur le secret veut dire « valeur du moteur » (10) ; `-output-curl-string` montre l'appel exact (à ne pas relancer tel quel : le jeton y passerait en argument de `curl`), et `-output-policy` la politique qu'il faudrait (utile en E05). Document : [`conventions-kv.md`](fichiers/M25-E04/medisphere/docs/securite/secrets/conventions-kv.md).

**Explications**

- **KV v2 plutôt que v1** : versions (retour à une valeur précédente après une rotation ratée), suppression réversible, CAS, métadonnées séparées des données. Les serveurs de développement montent `secret/` en KV v2 pour la démonstration ; en production on nomme le montage soi-même et on n'en garde qu'un.
- **Supprimer** (`kv/delete/…`) marque une version comme supprimée (`deletion_time`) : les données restent, `undelete` les rend. **Détruire** (`kv/destroy/…`) efface les données de la version, définitivement ; les métadonnées gardent la trace (`destroyed: true`). `kv metadata delete` efface tout le secret, versions comprises. Ces chemins distincts permettent de donner à une équipe la suppression sans la destruction (E05).
- **CAS** : un écrivain dit « je remplace la version 3 » ; si quelqu'un a écrit la version 4 entre-temps, son écriture est refusée au lieu d'écraser une rotation (un pipeline de rotation et une personne qui corrige à la main en même temps).
- **Métadonnées personnalisées** : lisibles sans la valeur, donc par les politiques de lecture et les checks ; c'est là que vivent propriétaire et rotation, jamais une valeur.

**Alternatives**

- *Un montage par application* (`kv-mediagenda/`) : isolation plus forte (réglages, quotas, désactivation séparés), mais politiques et ESO plus verbeux ; un seul `kv/` avec une arborescence stricte suffit au lab.
- *`bao kv patch`* pour modifier un champ sans réécrire les autres (exige `patch` dans la politique, ou `update` pour la méthode de repli).

**Pièges classiques**

- `bao kv put … mot_de_passe=S3cret` : la valeur est dans l'historique et `ps`.
- `bao kv get` qui affiche la valeur à l'écran pendant une démonstration ou un partage d'écran ; `-field=… | wc -c` suffit pour vérifier.
- `curl -H "X-Vault-Token: $T"` : le jeton est sur la ligne de commande.
- Confondre `delete` et `destroy` dans une politique : donner `kv/destroy/*` à une équipe, c'est lui donner la perte définitive de données.
- Croire qu'un secret supprimé est parti : il reste dans les versions tant qu'il n'est pas détruit.

**En production chez MédiSphère**

Arborescence relue en MR (création des chemins applicatifs par la plateforme), métadonnées obligatoires contrôlées par un job planifié qui liste `kv/metadata/` et signale les secrets sans propriétaire ou à rotation dépassée (M25-E33), destruction de version tracée dans un ticket et dans l'audit.

---

### M25-E05 — Politiques et jetons

**Solution**

Politiques finales (en code en E08) : [`plateforme-admin.hcl`](fichiers/M25-E08/secrets/politiques/plateforme-admin.hcl), [`plateforme-lecture.hcl`](fichiers/M25-E08/secrets/politiques/plateforme-lecture.hcl), [`securite-audit.hcl`](fichiers/M25-E08/secrets/politiques/securite-audit.hcl), [`mediagenda-dev.hcl`](fichiers/M25-E08/secrets/politiques/mediagenda-dev.hcl). Document : [`modele-acces-coffre.md`](fichiers/M25-E05/medisphere/docs/securite/secrets/modele-acces-coffre.md).

```
admin@adm01:~/m25/e05$ for p in plateforme-admin plateforme-lecture securite-audit mediagenda-dev; do
>   bao policy fmt $p.hcl && bao policy write $p $p.hcl; done
admin@adm01:~$ T=$(bao token create -policy=mediagenda-dev -ttl=15m -display-name=essai-e05-md -field=token)
admin@adm01:~$ for c in kv/data/mediagenda/dev/x kv/data/mediagenda/prod/x kv/metadata/mediagenda/ kv/destroy/mediagenda/dev/x; do
>   echo "$c : $(bao token capabilities "$T" "$c")"; done
kv/data/mediagenda/dev/x : create, delete, read, update
kv/data/mediagenda/prod/x : deny
kv/metadata/mediagenda/ : list
kv/destroy/mediagenda/dev/x : deny
```

Table de vérification de `plateforme-admin` (jeton portant aussi `plateforme-lecture`, comme pour `<MOI>` et Karim) :

| Chemin | Attendu |
|---|---|
| `sys/policies/acl/x` | create, delete, list, read, update |
| `sys/auth/x` | create, delete, read, sudo, update |
| `auth/approle/role/x` | create, delete, list, read, update |
| `identity/group/name/x` | create, delete, list, read, update |
| `kv/data/plateforme/x` | create, delete, read, update |
| `kv/data/mediagenda/prod/x` | deny |
| `sys/seal` | sudo, update |
| `sys/raw/x` | deny |

**L'étape 4** est le point de l'exercice. Une première version naïve de `plateforme-lecture` écrite avec des motifs « au plus juste » (`auth/+/role/+` en `read`, `identity/group/name/+` en `read`) donne, pour un jeton qui porte les deux politiques :

```
auth/approle/role/x : read
identity/group/name/plateforme : read
```

L'écriture de l'administration a disparu : OpenBao ne cumule pas des motifs **différents** ; il retient le plus précis (`auth/+/role/+` est plus précis que `auth/+/role/*`), avec ses seules capacités. Correction : les politiques de lecture reprennent **les mêmes chaînes** que `plateforme-admin` (`auth/+/role/*`, `identity/*`, `kv/metadata/*`…) avec des capacités de lecture ; pour une même chaîne, les capacités de toutes les politiques s'additionnent. On ne « corrige » pas en élargissant l'administration : c'est la politique de lecture qui ne doit rien masquer.

`deny` (étape 5) l'emporte toujours sur le même chemin, quelles que soient les autres politiques. `sudo` : `bao auth enable` sur `sys/auth/<chemin>` exige `sudo`, `bao secrets enable` sur `sys/mounts/<chemin>` non ; `sys/audit` (lister les dispositifs) exige `sudo` ; `sys/seal` aussi.

Jetons :

```
admin@adm01:~$ bao token create -policy=default -ttl=10m -explicit-max-ttl=30m -display-name=essai-e05-ttl -format=json \
>   | jq -r .auth.accessor > ~/m25/e05/acc-ttl
admin@adm01:~$ bao token renew -accessor -increment=10m "$(<~/m25/e05/acc-ttl)" >/dev/null
admin@adm01:~$ bao token lookup -accessor "$(<~/m25/e05/acc-ttl)" | grep -E 'ttl|expire_time|explicit'
admin@adm01:~$ bao token create -policy=default -period=1h -display-name=essai-e05-periodique -format=json | jq -c '.auth | {lease_duration, renewable}'
{"lease_duration":3600,"renewable":true}
admin@adm01:~$ printf 'path "auth/token/create" { capabilities = ["update"] }\n' | bao policy write essai-e05 -
admin@adm01:~$ P=$(bao token create -policy=essai-e05 -ttl=1h -display-name=essai-e05-parent -field=token)
admin@adm01:~$ E=$(BAO_TOKEN=$P bao token create -policy=essai-e05 -ttl=30m -display-name=essai-e05-enfant -field=token)
admin@adm01:~$ BAO_TOKEN=$E bao token create -policy=essai-e05 -ttl=20m -display-name=essai-e05-petit -format=json | jq -r .auth.accessor > ~/m25/e05/acc-petit
admin@adm01:~$ BAO_TOKEN=$P bao token create -orphan -policy=essai-e05
Code: 400. Errors:
* root or sudo privileges required to create orphan token
admin@adm01:~$ bao token create -orphan -policy=essai-e05 -ttl=1h -display-name=essai-e05-orphelin -format=json | jq -r .auth.accessor > ~/m25/e05/acc-orph
admin@adm01:~$ bao token revoke -accessor "$(bao token lookup -format=json "$P" | jq -r .data.accessor)"
admin@adm01:~$ bao token lookup -accessor "$(<~/m25/e05/acc-petit)"      # « bad token » : révoqué en cascade
admin@adm01:~$ bao token lookup -accessor "$(<~/m25/e05/acc-orph)" | grep display_name   # vivant
admin@adm01:~$ for a in $(bao list -format=json auth/token/accessors | jq -r '.[]'); do
>   n=$(bao token lookup -format=json -accessor "$a" | jq -r .data.display_name)
>   case "$n" in token-essai-e05*) bao token revoke -accessor "$a" ;; esac; done
admin@adm01:~$ bao policy delete essai-e05; unset T P E; rm -f ~/m25/e05/acc-*
```

(Un enfant ne peut pas recevoir une politique que son parent n'a pas : « child policies must be subset of parent ».)

*Batch* (`-type=batch`) : pas de stockage côté serveur (le jeton porte lui-même ses informations, chiffrées), donc ni renouvellement, ni révocation individuelle, ni accessor, ni enfants ; il meurt à son TTL ou avec son parent. Fait pour les clients nombreux et courts (checks, pods, jobs) qui n'ont besoin que de quelques minutes : aucune écriture dans le stockage à chaque connexion.

**Explications**

- **Tout est refusé par défaut** : une politique liste ce qui est permis. Les capacités correspondent aux verbes HTTP (`create` POST/PUT sur un chemin nouveau, `update` POST/PUT sur un existant, `read` GET, `delete` DELETE, `list` LIST), plus `sudo` (chemins protégés) et `deny`. `patch` existe aussi (KV v2).
- **Priorité des motifs** : quand plusieurs règles correspondent à un chemin, OpenBao choisit la plus précise selon des critères ordonnés (position du premier joker, `*` final ou non, nombre de `+`, longueur) ; seules les règles de **même chaîne** voient leurs capacités fusionnées entre politiques. C'est la source la plus fréquente des « permission denied » inexpliqués (M25-E40).
- **`*` et `+`** : `*` n'est permis qu'à la fin et couvre aussi la chaîne vide (`kv/metadata/x/dev/*` permet de lister `kv/metadata/x/dev/`) ; `+` remplace un segment, y compris au milieu (`auth/+/role/*`).
- **Jetons** : TTL (durée avant renouvellement), maximum (plafond qu'aucun renouvellement ne dépasse : `explicit_max_ttl` du jeton, puis `max_lease_ttl` de la méthode et du système), période (renouvelable indéfiniment, chaque renouvellement repart pour une période : pour un service qui tourne longtemps et prouve qu'il est vivant), parent (arbre de révocation), accessor (consulter et révoquer sans connaître le jeton : c'est ce qu'on met dans un journal ou un ticket).

**Alternatives**

- *Politiques modélisées* (`{{identity.entity.name}}`, `{{identity.entity.aliases.<accessor>.name}}`) : une seule politique qui donne à chacun son espace ; utile pour des secrets personnels.
- *Politiques par chemin dans le rôle* plutôt que par groupe : plus simple au début, ingérable dès qu'une personne change d'équipe (E06).
- *Sentinel/EGP* : propres à Vault Enterprise, absents d'OpenBao ; les *Control Groups* (approbation à plusieurs) arrivent dans OpenBao 2.7 (`annexes/versions-bloc-F.md`).

**Pièges classiques**

- Écrire la politique de lecture avec des motifs plus précis que celle d'administration : les administrateurs perdent leurs droits (étape 4).
- `path "kv/*"` « pour simplifier » : lecture **et** écriture de tous les secrets, configuration du moteur comprise.
- Oublier `kv/metadata/…` (liste, versions) ou `kv/delete/…`, `kv/undelete/…` dans une politique KV v2 : l'équipe écrit mais ne voit pas ses secrets, ou ne peut pas annuler une erreur.
- Donner `delete` sur `kv/metadata/<équipe>/*` « pour faire le ménage » : supprimer les métadonnées efface le secret **et toutes ses versions**, sans retour ; c'est une destruction déguisée (d'où son absence de `mediagenda-dev`).
- Une règle de liste sans barre finale (`auth/+/role`) : elle ne sert à rien pour `LIST auth/approle/role/`.
- Tester une politique avec le jeton racine : tout passe. Toujours avec un jeton de la politique.
- Laisser traîner des jetons d'essai périodiques ou orphelins : ils ne meurent jamais seuls.

**En production chez MédiSphère**

Politiques en code, relues par Sophie (E08) ; test automatique des politiques en CI (un serveur `-dev` jetable, les politiques chargées, une table chemin → capacités attendue vérifiée par `bao token capabilities`) ; revue trimestrielle des jetons vivants et des accessors (M25-E33) ; alerte sur toute création de jeton orphelin ou racine (audit, M25-E21).

---

### M25-E06 — Les personnes entrent par le SSO : méthode OIDC

**Solution**

*A. Client.* [`tofu/clients-openbao.tf`](fichiers/M25-E06/identite/tofu/clients-openbao.tf) dans `plateforme/identite` : client confidentiel, flux standard seul, PKCE `S256`, deux redirections exactes, sortie sensible `openbao_client_secret`. MR, plan (`1 to add`), apply par le pipeline. Puis le secret, d'un tube :

```
admin@adm01:~/src/identite$ . outils/charger-acces.sh
admin@adm01:~/src/identite$ tofu -chdir=tofu output -raw openbao_client_secret | bao kv put -mount=kv plateforme/openbao/oidc client_secret=-
admin@adm01:~$ bao kv metadata put -mount=kv -custom-metadata=proprietaire=plateforme -custom-metadata=rotation=annuelle \
>   -custom-metadata=source=keycloak -custom-metadata=ticket=PLAT-2606 plateforme/openbao/oidc
```

*B. Méthode, rôle, groupes.*

```
admin@adm01:~$ bao auth enable -description="Personnes : SSO Keycloak (royaume medisphere)" oidc
admin@adm01:~$ bao auth tune -listing-visibility=unauth -default-lease-ttl=1h -max-lease-ttl=8h oidc/
admin@adm01:~$ bao kv get -mount=kv -field=client_secret plateforme/openbao/oidc \
>   | bao write auth/oidc/config oidc_discovery_url=https://sso.par1.medisphere.internal/realms/medisphere \
>       oidc_client_id=openbao oidc_client_secret=- default_role=personne
admin@adm01:~$ bao read auth/oidc/config | grep -E 'oidc_|default_role|status'
default_role        personne
oidc_client_id      openbao
oidc_discovery_url  https://sso.par1.medisphere.internal/realms/medisphere
status              valid
admin@adm01:~$ bao write auth/oidc/role/personne role_type=oidc user_claim=preferred_username groups_claim=groups \
>   oidc_scopes=profile,email claim_mappings=email=email bound_audiences=openbao \
>   allowed_redirect_uris=https://openbao.par1.medisphere.internal:8200/ui/vault/auth/oidc/oidc/callback \
>   allowed_redirect_uris=http://localhost:8250/oidc/callback \
>   token_policies=default token_ttl=1h token_max_ttl=8h
admin@adm01:~$ ACC=$(bao auth list -format=json | jq -r '."oidc/".accessor')
admin@adm01:~$ declare -A POL=([plateforme-admins]=plateforme-admin [plateforme]=plateforme-lecture [support]=plateforme-lecture [securite]=securite-audit [mediagenda]=mediagenda-dev)
admin@adm01:~$ for g in "${!POL[@]}"; do
>   id=$(bao write -format=json identity/group name="$g" type=external policies="${POL[$g]}" metadata=source=keycloak-medisphere | jq -r .data.id)
>   bao write identity/group-alias name="$g" mount_accessor="$ACC" canonical_id="$id" >/dev/null; done
```

La configuration relue ne contient **pas** le secret (OpenBao ne renvoie jamais `oidc_client_secret`) ; `status valid` dit que la découverte a été lue. Le secret n'a été ni tapé, ni affiché, ni passé en argument : du coffre au coffre, par un tube.

*C. Connexions.*

```
toi@poste:~$ ssh -L 8250:localhost:8250 admin@adm01
admin@adm01:~$ bao login -method=oidc skip_browser=true
Complete the login via your OIDC provider. Launching browser to:
    https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/auth?client_id=openbao&code_challenge=…&code_challenge_method=S256&nonce=…&redirect_uri=http%3A%2F%2Flocalhost%3A8250%2Foidc%2Fcallback&response_type=code&scope=openid+profile+email&state=…
Waiting for OIDC authentication to complete...
Success! You are now authenticated.
admin@adm01:~$ bao token lookup | grep -E 'display_name|^policies|identity_policies|entity_id|^ttl'
display_name           oidc-<MOI>
entity_id              50952dc8-…
identity_policies      [plateforme-admin plateforme-lecture]
policies               [default]
ttl                    59m54s
admin@adm01:~$ bao token capabilities sys/policies/acl/x; bao token capabilities kv/data/mediagenda/dev/x
create, delete, list, read, update
deny
```

Les droits sont dans `identity_policies` : ils viennent de l'**entité** (la personne) par ses groupes externes, pas du jeton lui-même (`policies` ne contient que `default`, celle du rôle). Keycloak a demandé l'OTP (flux `navigateur-medisphere` du M24, membre de `plateforme-admins`). Lucas (`plateforme`) : `identity_policies [plateforme-lecture]`, la liste des secrets s'affiche, l'ouverture d'un secret est refusée ; Julien (`mediagenda`) : écriture dans `kv/mediagenda/dev/`, refus ailleurs. Retiré de `plateforme` dans l'annuaire, Lucas garde ses droits tant qu'il ne se reconnecte pas : son jeton vit jusqu'à 8 h, et un renouvellement réapplique les groupes reçus **à la connexion** (OpenBao ne redemande rien à Keycloak ; vérifié dans le code d'OpenBao 2.6.4, `RenewToken`). À la connexion suivante, la revendication `groups` ne contient plus `plateforme` : l'entité quitte le groupe externe, et comme les politiques d'identité sont relues à chaque requête, **tous** ses jetons perdent `plateforme-lecture` (un renouvellement d'un ancien jeton réappliquerait toutefois ses anciens groupes). Pour couper tout de suite : révoquer ses jetons par accessor, ou désactiver son entité. Ce qu'OpenBao a créé : une **entité** par personne (à la première connexion), avec un **alias** `oidc` à son identifiant ; les groupes externes n'ont pas de membres écrits : leur appartenance est recalculée à chaque connexion d'après la revendication `groups`.

**Explications**

- **Confidentiel plus PKCE** : OpenBao échange le code de serveur à serveur avec son secret, et envoie aussi un défi PKCE (vérifié à la rédaction) ; l'interface web et la CLI passent toutes deux par Keycloak, donc par l'OTP.
- **`bound_audiences`** : l'ID token est destiné au client `openbao` (`aud`) ; sans contrôle d'audience, un ID token obtenu par un autre client du royaume (Grafana) pourrait être présenté ici. C'est la confusion d'audience du M24-E09.
- **Groupes externes plutôt que politiques dans le rôle** : un rôle unique, des droits qui suivent l'annuaire ; ajouter quelqu'un à `securite` dans le dépôt de l'annuaire lui donne `securite-audit` à sa prochaine connexion, sans toucher à OpenBao.
- **Le tunnel de la CLI** : le serveur de rappel tourne sur `adm01` ; le navigateur, sur ton poste, est renvoyé vers `http://localhost:8250/…` : le tunnel SSH amène ce `localhost` du poste sur `adm01`.

**Alternatives**

- *Un rôle par population* (`admin` avec `max_age` court et OTP vérifié par une revendication `acr`, `lecture` sans) : plus fin, plus de configuration.
- *`bound_claims` sur `groups`* : refuser la connexion à qui n'est dans aucun groupe utile (direction, MédiDoc au palier 1) ; ici ils entrent avec `default` seulement, ce qui ne leur ouvre rien.
- *Mode `device`* de la CLI (`callbackmode=device`) : pas de tunnel, un code à saisir dans le navigateur ; exige le flux d'appareil activé sur le client Keycloak.
- *Méthode LDAP* directement sur FreeIPA : plugin externe depuis OpenBao 2.7, et pas de second facteur ; le SSO est la porte unique.

**Pièges classiques**

- Une redirection qui diffère d'un caractère (barre finale, `https` contre `http`, port) entre Keycloak et le rôle : « Invalid parameter: redirect_uri » côté Keycloak, ou refus côté OpenBao.
- Oublier le tunnel : le navigateur arrive sur `localhost:8250` du poste, où rien n'écoute.
- Mettre les politiques dans `token_policies` du rôle : tout le monde est administrateur.
- Un alias de groupe mal nommé (`/plateforme-admins`, chemin complet) : la revendication ne correspond à aucun alias, la personne n'a que `default` (M25-E40).
- Passer le secret du client en argument (`oidc_client_secret=…`) : il est dans `ps` et l'historique.

**En production chez MédiSphère**

Rôle séparé pour les administrateurs avec authentification récente exigée (`max_age`) ; revue mensuelle des entités (personnes parties : entités désactivées, M24-RB-242) ; alerte sur toute connexion d'un compte hors de l'annuaire ; secret du client tourné par le pipeline de rotation (M25-E33) avec poussée par OpenTofu (`oidc_client_secret_wo_version`).

---

### M25-E07 — Les machines : AppRole pour les checks et `medictl`

**Solution**

*A. Vérifications.* Politique [`wb-checks.hcl`](fichiers/M25-E08/secrets/politiques/wb-checks.hcl).

```
admin@adm01:~$ bao policy write wb-checks ~/m25/e07/wb-checks.hcl
admin@adm01:~$ bao auth enable -description="Machines : vérifications, medictl, pipelines Ansible" approle
admin@adm01:~$ bao write auth/approle/role/wb-checks token_policies=wb-checks token_no_default_policy=true \
>   token_type=batch token_ttl=10m token_max_ttl=10m \
>   secret_id_bound_cidrs=10.10.10.10/32 token_bound_cidrs=10.10.10.10/32 secret_id_ttl=0 secret_id_num_uses=0
admin@adm01:~$ R=$(bao read -field=role_id auth/approle/role/wb-checks/role-id)
admin@adm01:~$ ( umask 077; bao write -f -format=json auth/approle/role/wb-checks/secret-id \
>   | jq -r --arg r "$R" '"BAO_ROLE_ID=\($r | @sh)\nBAO_SECRET_ID=\(.data.secret_id | @sh)"' \
>   > ~/.config/workbook/openbao-checks.env ); unset R
admin@adm01:~$ lab/bin/check 25 04 | head -3
== M25-E04 — Premiers pas : KV v2, versions, CLI et API ==
  [OK]   Moteur KV version 2 monté en kv/
```

Preuve qu'elle ne lit aucune valeur :

```
admin@adm01:~$ J=$( ( set -a; . ~/.config/workbook/openbao-checks.env; jq -nc '{role_id: env.BAO_ROLE_ID, secret_id: env.BAO_SECRET_ID}' ) \
>   | curl -s --data @- $BAO_ADDR/v1/auth/approle/login | jq -r .auth.client_token )
admin@adm01:~$ curl -s -K <(printf 'header = "X-Vault-Token: %s"\n' "$J") $BAO_ADDR/v1/kv/data/plateforme/openbao/oidc | jq -c .errors
["1 error occurred:\n\t* permission denied\n\n"]
admin@adm01:~$ curl -s -K <(printf 'header = "X-Vault-Token: %s"\n' "$J") -X LIST $BAO_ADDR/v1/auth/approle/role/wb-checks/secret-id | jq -c .errors
["1 error occurred:\n\t* permission denied\n\n"]
admin@adm01:~$ unset J
```

Une identité de vérification qui pourrait émettre des `secret_id` pourrait se **multiplier** (et créer des identités pour d'autres rôles si le chemin était large) : elle deviendrait une identité d'administration. Limites d'un `secret_id` (rôle `essai-e07`) : usage unique → second login refusé (« invalid secret id ») ; 2 minutes → refusé après ; lié à `10.10.20.15/32` → « source address unauthorized ». Et `secret_id_ttl=2160h` : le rôle relu affiche bien 2160 h, mais chaque `secret_id` émis ne vaut que **768 h** (maximum des baux de la méthode) : c'est le `secret_id_ttl` de la **réponse** à `…/secret-id` qu'il faut relire.

*B. `medictl`.*

```
admin@adm01:~$ ( . ~/.config/workbook/pve-api.env; printf '%s' "$PVE_TOKEN_SECRET" ) \
>   | bao kv put -mount=kv plateforme/medictl/pve token_secret=-
admin@adm01:~$ ( . ~/.config/workbook/pve-lecture.env; printf '%s' "$PVE_TOKEN_SECRET" ) \
>   | bao kv put -mount=kv plateforme/medictl/pve-lecture token_secret=-
admin@adm01:~$ for s in pve pve-lecture; do bao kv metadata put -mount=kv -custom-metadata=proprietaire=plateforme \
>   -custom-metadata=rotation=annuelle -custom-metadata=source=proxmox -custom-metadata=ticket=PLAT-2607 plateforme/medictl/$s; done
admin@adm01:~$ bao policy write medictl ~/m25/e07/medictl.hcl
admin@adm01:~$ bao write auth/approle/role/medictl token_policies=medictl token_no_default_policy=true token_type=batch \
>   token_ttl=5m token_max_ttl=5m secret_id_bound_cidrs=10.10.10.10/32 token_bound_cidrs=10.10.10.10/32 secret_id_ttl=0 secret_id_num_uses=0
admin@adm01:~$ R=$(bao read -field=role_id auth/approle/role/medictl/role-id)
admin@adm01:~$ ( umask 077; bao write -f -format=json auth/approle/role/medictl/secret-id \
>   | jq -r --arg r "$R" --arg a "$BAO_ADDR" '"BAO_ADDR=\($a | @sh)\nMEDICTL_BAO_ROLE_ID=\($r | @sh)\nMEDICTL_BAO_SECRET_ID=\(.data.secret_id | @sh)"' \
>   > ~/.config/workbook/medictl-openbao.env ); unset R
```

Code (dans `plateforme/outils`) : [`src/medictl/coffre.py`](fichiers/M25-E07/outils/src/medictl/coffre.py) (accès, connexion AppRole, lecture KV v2, erreurs sans secret), [`src/medictl/config.py`](fichiers/M25-E07/outils/src/medictl/config.py) (version complète : si `PVE_TOKEN_SECRET` manque, lecture dans `kv/plateforme/medictl/pve` ou dans `MEDICTL_BAO_CHEMIN_PVE`), tests [`test_coffre.py`](fichiers/M25-E07/outils/tests/python/test_coffre.py) et [`conftest.py`](fichiers/M25-E07/outils/tests/python/conftest.py) (fixture automatique `_sans_coffre` : aucun test ne lit les vrais accès ni n'appelle le vrai coffre). Les autres fichiers de `medictl` ne changent pas.

```
admin@adm01:~/src/outils$ uv run pytest -q && uv run ruff check src tests
115 passed in 1.02s
All checks passed!
admin@adm01:~$ sed -i '/^[[:space:]]*\(export[[:space:]]\+\)\?PVE_TOKEN_SECRET=/d' ~/.config/workbook/pve-api.env ~/.config/workbook/pve-lecture.env
admin@adm01:~$ echo 'MEDICTL_BAO_CHEMIN_PVE=plateforme/medictl/pve-lecture' >> ~/.config/workbook/pve-lecture.env
admin@adm01:~$ medictl config
PVE_API_URL=https://pve01.par1.medisphere.internal:8006/api2/json   [/home/admin/.config/workbook/pve-api.env]
PVE_NODE=pve01   [/home/admin/.config/workbook/pve-api.env]
PVE_TOKEN_ID=wb-automation@pve!lab   [/home/admin/.config/workbook/pve-api.env]
PVE_TOKEN_SECRET=****   [openbao (kv/plateforme/medictl/pve)]
PVE_CACERT=…
admin@adm01:~$ sudo systemctl start medictl-netbox-sync.service && journalctl -u medictl-netbox-sync -n 5 --no-pager
```

L'unité du M06 n'a pas à changer : elle tourne sous `admin` (son `HOME` donne le chemin par défaut de `medictl-openbao.env`), lit `pve-lecture.env`, qui désigne maintenant le chemin du jeton de lecture dans le coffre.

**Explications**

- **`role_id` et `secret_id`** : le premier dit **quel** rôle, il n'est pas secret au sens strict (il est dans l'état d'OpenTofu, E08) ; le second prouve qu'on a le droit de l'utiliser. Idéalement deux canaux différents les livrent (le `role_id` par la configuration, le `secret_id` par enveloppement, M25-E28).
- **Gagné** : le jeton Proxmox n'est plus sur le disque d'`adm01` ; il ne circule que dans la mémoire de `medictl` ; chaque lecture est authentifiée, et sera **auditée** (M25-E21) ; sa rotation se fait à un seul endroit (le coffre). **Déplacé** : le `secret_id` est sur le disque, c'est le **secret zéro**. Volé, il ne vaut **que** depuis `adm01` (`secret_id_bound_cidrs`), donne des jetons de 5 minutes eux aussi liés à `adm01`, et ne lit que `kv/plateforme/medictl/*` ; il se révoque par son accessor sans toucher à Proxmox, et se refait en une commande. Un attaquant déjà root sur `adm01` lit de toute façon la mémoire de `medictl` : le coffre ne protège pas d'un poste compromis, il réduit ce qu'un **fichier** volé vaut.
- **Jetons *batch* sans `default`** : pas d'écriture dans le stockage à chaque connexion des checks (toutes les quelques secondes pendant un check), pas de *cubbyhole* ni de `lookup-self` inutiles.
- **`secret_id_ttl=0` pour ces deux rôles** : une expiration mensuelle casserait la synchronisation NetBox et les checks à date fixe. Compensations : liaison d'adresse, politique minimale, jetons courts, rotation trimestrielle inscrite dans la politique de rotation (M25-E33), enveloppement au M25-E28.

**Alternatives**

- *`medictl` qui lit ses secrets par l'**agent** OpenBao* (`bao agent` sur `adm01`, auto-authentification AppRole, gabarit vers un fichier en `tmpfs`) : l'outil ne change pas, mais un fichier en clair réapparaît (en mémoire) et un démon de plus tourne.
- *Le `secret_id` dans le trousseau de session* : impossible pour une minuterie système sans session.
- *Authentification TLS par certificat* (méthode `cert`, certificat client de step-ca pour `adm01`) : plus de `secret_id`, un certificat renouvelé automatiquement à la place ; valable, et cohérent avec la PKI du lab (piste du M25-E33).

**Pièges classiques**

- `bao write -f auth/approle/role/x/secret-id` sans `-format=json` vers un tube : le `secret_id` s'affiche.
- Un fichier d'accès créé puis `chmod 600` : il a été lisible un instant ; `umask 077` dans un sous-shell le crée directement en 600.
- `secret_id_ttl` au-delà de 768 h : ramené silencieusement ; un check qui casse « tout seul » au bout de 32 jours.
- Oublier `token_bound_cidrs` : un jeton volé (dans un journal) reste utilisable d'ailleurs pendant sa durée.
- Des tests qui lisent `~/.config/workbook/medictl-openbao.env` du développeur et appellent le vrai coffre : la fixture automatique l'empêche.
- Un message d'erreur qui recopie la réponse brute du serveur avec la requête : il ne doit jamais contenir le `secret_id` ni le jeton (test `test_refus_du_coffre_sans_fuite`).

**En production chez MédiSphère**

`secret_id` livré par enveloppement (le pipeline Ansible ne voit qu'un jeton d'enveloppe à usage unique) et tourné chaque trimestre ; alerte si un `secret_id` est utilisé depuis une autre adresse (refus visible dans l'audit) ; à terme, identité par certificat pour les machines du socle.

---

### M25-E08 — OpenBao en code avec OpenTofu

**Solution**

*A. Lire.* Imports : `vault_mount` et `vault_auth_backend` par leur chemin (`kv`, `approle`), `vault_jwt_auth_backend` aussi (`oidc`), `vault_kv_secret_backend_v2` par `kv/config`, les rôles par leur chemin complet (`auth/approle/role/<nom>`, `auth/oidc/role/<nom>`), `vault_policy` par son nom, `vault_identity_group` et `vault_identity_group_alias` par leur identifiant interne. Arguments en écriture seule utiles : `oidc_client_secret_wo` (+ `_wo_version`). Ressources à éviter contre OpenBao : `vault_namespace` (espaces de noms de Vault Enterprise : OpenBao a les siens depuis 2.3, avec une API proche, à essayer avant usage), `vault_egp_policy`, `vault_rgp_policy` (Sentinel), la réplication, les secrets de cloud. Au démarrage, le fournisseur lit le jeton (`VAULT_TOKEN`, sinon `~/.vault-token`), interroge la version du serveur, et crée un **jeton enfant** de `max_lease_ttl_seconds` (20 minutes) qu'il utilise et révoque à la fin. On ne gère ici ni les `secret_id` (`vault_approle_auth_backend_role_secret_id` les écrirait dans l'état) ni les valeurs KV (ressource `vault_kv_secret_v2` : la valeur dans le code ou dans une variable, puis dans l'état) : ce projet gère la **configuration**, les valeurs appartiennent à leurs propriétaires.

*B. Code et import.* Projet [`plateforme/secrets`](fichiers/M25-E08/secrets/) : [`README.md`](fichiers/M25-E08/secrets/README.md), [`tofu/fournisseurs.tf`](fichiers/M25-E08/secrets/tofu/fournisseurs.tf), [`chiffrement.tf`](fichiers/M25-E08/secrets/tofu/chiffrement.tf), [`variables.tf`](fichiers/M25-E08/secrets/tofu/variables.tf), [`montages.tf`](fichiers/M25-E08/secrets/tofu/montages.tf), [`methodes.tf`](fichiers/M25-E08/secrets/tofu/methodes.tf), [`oidc.tf`](fichiers/M25-E08/secrets/tofu/oidc.tf), [`approle.tf`](fichiers/M25-E08/secrets/tofu/approle.tf), [`politiques.tf`](fichiers/M25-E08/secrets/tofu/politiques.tf), [`imports.tf`](fichiers/M25-E08/secrets/tofu/imports.tf), [`.terraform.lock.hcl`](fichiers/M25-E08/secrets/tofu/.terraform.lock.hcl), [`politiques/`](fichiers/M25-E08/secrets/politiques/), [`outils/charger-acces.sh`](fichiers/M25-E08/secrets/outils/charger-acces.sh), [`outils/identifiants-openbao.sh`](fichiers/M25-E08/secrets/outils/identifiants-openbao.sh), [`.gitlab-ci.yml`](fichiers/M25-E08/secrets/.gitlab-ci.yml).

```
admin@adm01:~/src/secrets$ bao login -method=oidc skip_browser=true
admin@adm01:~/src/secrets$ outils/identifiants-openbao.sh
# Groupes d'identité : nom, identifiant du groupe, identifiant de l'alias
  plateforme-admins  type=external  groupe=4c2e4933-…  alias=cb0f48af-…
  …
admin@adm01:~/src/secrets$ . outils/charger-acces.sh
charger-acces : S3 (état), chiffrement et jeton OpenBao (oidc-<MOI>, 3526 s restantes) prêts.
admin@adm01:~/src/secrets$ tofu -chdir=tofu init && tofu -chdir=tofu plan
…
  # vault_jwt_auth_backend.oidc will be updated in-place
  # (imported from "oidc")
  ~ resource "vault_jwt_auth_backend" "oidc" {
      ~ oidc_client_secret_wo         = (write-only attribute)
      + oidc_client_secret_wo_version = 1
…
Plan: 23 to import, 0 to add, 14 to change, 0 to destroy.
```

Les 14 mises à jour du premier plan, et leur traitement :

| Écart | Cause | Décision |
|---|---|---|
| `oidc_client_secret_wo` | argument en écriture seule, jamais relu | **inévitable** : poussé une fois à l'import (la même valeur, lue dans le coffre) |
| `external_member_entity_ids`, `external_member_group_ids`, `external_policies` (`+ false`) sur les 5 groupes | attributs propres au fournisseur, absents de la réponse de l'API | laisser le plan les écrire (sans effet sur le serveur) |
| `metadata` des groupes | écrite à la main différemment | la réalité ne convient pas : le code l'emporte |
| `description` du moteur et des méthodes, `disable_remount` | descriptions écrites à la main avec d'autres mots ; attribut du fournisseur | aligner les descriptions dans le code **ou** laisser le plan les changer (ici : le code l'emporte) |
| `tune` de `oidc` (`768h` → `1h`/`8h`) | réglage oublié à la main | la réalité ne convient pas : le plan le corrige |
| `secret_id_ttl`, `token_max_ttl` d'un rôle | valeurs d'essai restées sur le serveur | le code l'emporte |

Après l'apply : `No changes. Your infrastructure matches the configuration.` Dans l'état : aucun secret de client (`oidc_client_secret` et `oidc_client_secret_wo` à `null`, la valeur introuvable par `grep -c`), mais les `role_id` des deux AppRole (attribut calculé du fournisseur) : la moitié d'un identifiant, raison de plus pour chiffrer l'état et lier les `secret_id` à une adresse. Le changement de politique par MR donne `1 to change` ; la modification à la main sur le serveur est **annulée** par le plan suivant (OpenTofu propose de réécrire la politique du dépôt) : c'est le contrôle de dérive.

*C. Fin de la racine.*

```
admin@adm01:~$ bao operator generate-root -status          # session OIDC d'administrateur
Nonce         n/a
Started       false
Progress      0/3
Complete      false
admin@adm01:~/src/ansible$ outils/openbao-parts.sh resume >/dev/null && age -d -i ~/.config/workbook/age/openbao-<MOI>.age \
>   <(uv run ansible-vault view secrets/openbao-init.yml | jq -r '.openbao_init.depositaires[4].part') >/dev/null && echo "part 5 lisible"
part 5 lisible
admin@adm01:~/src/ansible$ outils/openbao-parts.sh jeton-racine ~/.config/workbook/age/openbao-<MOI>.age
admin@adm01:~$ bao token lookup | grep -E '^policies|display_name'
display_name        root
policies            [root]
admin@adm01:~$ bao token revoke -self
Success! Revoked token (if it existed)
admin@adm01:~$ bao login -method=oidc skip_browser=true
admin@adm01:~$ lab/bin/check 25 08 | tail -3
  [OK]   Aucun jeton racine vivant (jeton initial révoqué ; nouveau jeton par generate-root si besoin)
```

Le jeton racine chiffré qui reste dans `secrets/openbao-init.yml` est révoqué, donc sans valeur ; on le laisse (le fichier est la trace de la cérémonie, réécrire un fichier `critique` pour retirer une valeur morte n'apporte rien) et on l'écrit dans le procès-verbal (« jeton racine initial révoqué le … »).

**Explications**

- **Importer plutôt que recréer** : recréer un rôle AppRole change son `role_id` (les fichiers d'accès d'E07 deviennent faux) ; recréer un groupe change son identifiant (les entités perdent leur appartenance jusqu'à la connexion suivante) ; recréer la méthode `oidc` change son accessor (tous les alias de groupe deviennent orphelins).
- **Ressource éphémère + écriture seule** (OpenTofu ≥ 1.11, fournisseur 5.x) : la valeur est lue dans le coffre au moment du plan et de l'apply, sert à l'appel d'API, puis disparaît ; ni le plan enregistré, ni l'état ne la gardent. Le nom du montage est en **littéral** : une ressource éphémère qui dépend d'une ressource en cours d'import est différée et rien ne pourrait être planifié.
- **Une identité nominative pour appliquer** : l'audit dira « `oidc-karim.benali` a changé la politique `mediagenda-dev` », pas « root ». Le jeton enfant de 20 minutes limite ce qu'un plan enregistré volé permettrait.
- **Pourquoi la racine part maintenant** : tout ce qu'elle faisait, une personne nommée le fait par le SSO, avec OTP ; la garder, c'est garder un compte partagé sans expiration. Le chemin de retour existe : `generate-root` **authentifié** (OpenBao 2.6, politique `plateforme-admin` sur `sys/generate-root-token/*`), et, si plus personne ne peut s'authentifier, la réactivation temporaire des points non authentifiés sur l'écouteur (`disable_unauthed_generate_root_endpoints = false`, désactivés par défaut depuis 2.5.3) — bris de glace à écrire au palier 3.

**Alternatives**

- *Tout créer par OpenTofu dès E04* : plus court, mais l'import est un savoir-faire (reprendre un coffre existant) et on décrit mieux ce qu'on a vu.
- *Configuration déclarative du serveur* (OpenBao 2.4+ sait déclarer certains objets dans `openbao.hcl` : audit, profils d'initialisation) : utile pour l'amorçage, pas pour la vie courante (politiques relues en MR).
- *`bao` en scripts dans le pipeline* : pas de plan, pas d'état, pas de détection de dérive.
- *Pipeline qui applique dès E08* avec un jeton stocké en variable de CI : on remplacerait la racine par un secret durable de CI, exactement ce que le M25-E10 supprime.

**Pièges classiques**

- Appliquer avec la racine « parce qu'elle marche » : l'audit perd l'auteur, et le jeton le plus puissant du coffre sert à une opération courante.
- Un `VAULT_TOKEN` oublié dans le shell (la racine d'un essai) qui passe avant la session OIDC : `charger-acces.sh` le refuse.
- `vault_kv_secret_v2` en **ressource** pour « initialiser » un secret : la valeur dans l'état.
- Liste des politiques construite à la main dans le code au lieu de `fileset()` : un fichier ajouté n'est pas appliqué, ou une politique supprimée du dépôt reste sur le serveur.
- Révoquer la racine avant d'avoir **essayé** une connexion d'administrateur par OIDC.
- `tofu state pull > etat.json` « pour regarder ».

**En production chez MédiSphère**

Pipeline authentifié par le jeton d'identité de GitLab (M25-E10), plan sur chaque MR, apply manuel protégé ; plan nocturne qui doit être vide (dérive) ; relecture obligatoire de Sophie sur `politiques/` (règle d'approbation) ; tests des politiques en CI contre un serveur jetable ; régénération de racine en cérémonie (deux personnes, durée de vie en minutes, révocation tracée, M25-E28).

---

### M25-E09 — Questions : barrière, seal, baux et chemins

**Barème** : 2 points par question, total sur 24. Une réponse juste mais sans lien avec ce que tu as observé vaut 1 point.

**1. La chaîne des clés.** Les données (tout ce qu'OpenBao écrit dans Raft) sont chiffrées par la **clé de chiffrement de la barrière** (AES-256-GCM), qui fait partie d'un **trousseau** (*keyring* : plusieurs versions de clé, la plus récente chiffre, les anciennes déchiffrent ce qu'elles ont chiffré ; `bao operator rotate` ajoute une version, M25-E44). Le trousseau est lui-même stocké chiffré par la **clé racine** (*root key*). La clé racine n'est stockée nulle part utilisable : avec Shamir, on en a remis les **parts** aux dépositaires (OpenBao garde `core/shamir-kek`, inutilisable sans elles) ; avec un seal automatique, elle est stockée chiffrée par une clé externe (transit de `kms01`). Dans `/var/lib/openbao` : le journal Raft (`raft/raft.db`), la base qui en résulte (`vault.db`), des instantanés ; on y lit les chemins de stockage (structure), jamais une valeur.

**2. Réponse B.** Un nœud redémarré connaît sa configuration et ses données, mais pas la clé racine : il est **scellé** et répond 503 à tout sauf aux points de santé et de descellement. A est faux : la clé racine n'est jamais dans la configuration (sauf seal `static`, écarté par l'ADR-0250 justement pour cette raison). C est faux : rien n'est perdu. D est faux : un nœud scellé ne sert rien, même pas une lecture.

**3. Seal.** `bao operator seal` (sudo) **efface la clé racine de la mémoire** du nœud actif et arrête le service des requêtes : le coffre se comporte comme après un redémarrage. Usage volontaire : une compromission avérée ou soupçonnée de l'hôte ou d'un jeton très privilégié, pour couper net tout accès pendant l'enquête (RB-250). Coût : **tout** ce qui dépend du coffre perd ses secrets neufs (identifiants dynamiques non renouvelés, ESO en erreur, CI sans secrets) jusqu'au descellement, qui demande trois dépositaires ou `kms01`. C'est un arrêt de production décidé.

**4. 5 et 3.** Une part unique : une personne seule (ou un seul fichier volé) ouvre le coffre, et sa perte le ferme pour toujours. 5 sur 5 : une seule absence ou perte bloque tout. 3 sur 5 tolère **deux** absences ou pertes et exige **trois** complices : un compromis entre disponibilité et séparation des pouvoirs. Avec le seal automatique (M25-E25), le démarrage n'utilise plus les parts : elles deviennent des **clés de récupération**, nécessaires pour régénérer un jeton racine, migrer le seal ou changer les clés ; même garde, usage plus rare.

**5. Baux.** Un bail associe à un secret **délivré** une durée, un renouvellement possible jusqu'à un maximum, et une révocation. Jeton de service : un bail (son TTL) ; identifiant PostgreSQL dynamique : un bail, dont la révocation **supprime le rôle** dans PostgreSQL ; secret KV v2 : pas de bail (`lease_duration` 0, `lease_id` vide : rien n'est à détruire à une échéance, la valeur vit jusqu'à ce qu'on la change). À l'expiration, OpenBao révoque le bail (et fait le ménage à la source). Révoquer par **préfixe** (`sys/leases/revoke-prefix/db-mediagenda/creds/…`, sudo) détruit d'un coup tous les identifiants émis sous ce chemin : la réponse à une fuite, ou le « ménage » qui casse une application (M25-E38).

**6. Réponse C.** Le jeton se renouvelle d'heure en heure mais jamais au-delà de sa durée maximale, ici celle de la méthode (8 h ; `explicit_max_ttl=0` = pas de plafond propre au jeton). A est faux : le renouvellement prolonge ; B est faux : seul un jeton **périodique** sans maximum vit indéfiniment ; D confond la fréquence de renouvellement et la durée.

**7. Service et *batch*.** Service : stocké dans le coffre (une écriture à la création), renouvelable, révocable individuellement, accessor, enfants possibles, porteur de baux. *Batch* : non stocké (blob chiffré porté par le client), non renouvelable, pas d'accessor, pas d'enfants, révoqué seulement avec son parent ou à l'échéance ; léger, utilisable sur les nœuds en attente. Checks et `medictl` : connexions fréquentes et courtes (une écriture Raft par connexion serait du bruit pour rien), aucune raison de renouveler. Une personne qui travaille une journée renouvelle son jeton, doit pouvoir être révoquée **tout de suite** (départ, vol) et retrouvée par son accessor : jeton de service.

**8. Réponse enveloppée.** OpenBao ne rend pas la réponse (par exemple un `secret_id`) mais la range dans le *cubbyhole* d'un **jeton d'enveloppe** à usage unique et courte durée, et rend ce jeton. Le pipeline qui livre ne voit que le jeton d'enveloppe ; la machine destinataire le **désenveloppe** (`sys/wrapping/unwrap`) et obtient le `secret_id`. Détection : si quelqu'un l'a désenveloppé avant elle, la machine reçoit une erreur (jeton déjà utilisé) : l'interception est **visible**, on révoque et on recommence. On peut aussi vérifier l'origine (`sys/wrapping/lookup` : chemin de création). M25-E28.

**9. Chemins et montages.** KV v2 sépare les **données** (`kv/data/…`, valeur d'une version) des **métadonnées** (`kv/metadata/…`, versions, dates, réglages, métadonnées personnalisées) et des opérations (`delete`, `undelete`, `destroy`) pour que les politiques donnent l'un sans l'autre (voir sans lire, supprimer sans détruire). Un second montage `kv-mediagenda/` serait un espace de chemins distinct : les politiques doivent le nommer (`kv-mediagenda/data/…`), les règles sur `kv/` ne s'y appliquent pas ; on peut le désactiver ou le régler séparément. `sys/` : administration du serveur (montages, politiques, santé, scellement, baux) ; `auth/` : méthodes d'authentification et leurs rôles ; `identity/` : entités, groupes, alias (qui est qui, à travers les méthodes) ; `cubbyhole/` : un espace privé **par jeton**, détruit avec lui (support de l'enveloppement).

**10. Réponse B.** Les deux règles correspondent ; la plus précise (`kv/data/mediagenda/prod/*`) s'applique seule, et elle refuse. Attention à la généralisation « `deny` l'emporte toujours » : c'est vrai entre règles de **même chaîne** ; avec les capacités inversées (`deny` sur `kv/data/mediagenda/*`, `read` sur `kv/data/mediagenda/prod/*`), la règle la plus précise permettrait la lecture (vérifié avec `bao token capabilities`). A est faux : seules des règles de **même chaîne** se cumulent ; C et D sont faux : l'ordre des politiques ne compte pas.

**11. `sys/`.** Utilisés : `sys/seal-status` et `sys/health` (état, sans jeton), `sys/unseal` (parts), `sys/mounts/<chemin>` (monter un moteur, pas de sudo), `sys/auth/<chemin>` (activer une méthode, **sudo**), `sys/policies/acl/<nom>` (politiques), `sys/capabilities-self`, `sys/generate-root-token/attempt` (régénération authentifiée) ; `sys/seal` et `sys/audit` exigent **sudo**. `sys/health` répond sans jeton parce qu'il sert aux répartiteurs, à keepalived et aux sondes, qui n'ont pas d'identité, et il ne révèle que l'état ; ses **codes HTTP** (200 actif, 429 en attente, 501 non initialisé, 503 scellé…) permettent de décider sans lire le corps (keepalived au M25-E24, blackbox au M25-E27).

**12. `hashicorp/vault` contre OpenBao.** OpenBao est un fork de Vault qui garde son **API HTTP** (chemins `/v1/…`, en-tête `X-Vault-Token`, formats de réponse) : un client de l'API de Vault parle à OpenBao. Limites : les fonctions propres à Vault Enterprise (Sentinel, réplication, espaces de noms à la façon de Vault, plugin KMS Kubernetes) n'existent pas ou diffèrent ; les fonctions apparues dans Vault après le fork, ou dans OpenBao seulement, ne correspondent pas forcément ; le fournisseur lit la **version** du serveur pour activer des comportements, et OpenBao 2.x n'est pas Vault 2.x. Avant chaque nouvelle ressource : un plan, un apply et un plan vide contre un serveur OpenBao jetable de la même version, et la lecture de la page de la ressource (arguments, import) ; c'est ce que dit le README de `plateforme/secrets`.

**Pour aller plus loin** : ces réponses reviennent dans l'ADR-0250 (M25-E31), dans les questions de production (M25-E32) et dans la visite « sous le capot » (M25-E44).
