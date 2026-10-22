# Module 25 — Palier 1 : Découverte

Avant de ranger un seul secret, il faut savoir lesquels existent, puis construire un coffre qu'on sait ouvrir, fermer et laisser sans jeton racine. Ce palier inventorie les secrets de la plateforme, installe OpenBao sur `vault01` et l'initialise pendant une cérémonie, manipule le moteur KV et ses versions par la CLI et l'API, écrit les premières politiques et observe la vie des jetons, fait entrer les personnes par le SSO de Keycloak et les machines par AppRole (dont `medictl`, qui ne garde plus son secret sur disque), puis reprend toute la configuration en OpenTofu et révoque le jeton racine. Il s'ouvre et se ferme sur un questionnaire.

Prérequis : module 24 terminé (`lab/bin/check 24 46` vert : Keycloak, royaume `medisphere`, revendication `groups`, OTP des administrateurs) ; module 06 (step-ca et ACME, PowerDNS en API, NetBox) ; module 05 (OpenTofu, état S3 chiffré, imports) ; module 04 (Ansible, Vault `critique`, pipeline protégé) ; module 02 (`medictl`). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les **règles du module**.

**Rappels du module**
- Un redémarrage d'OpenBao **scelle** le coffre : trois dépositaires pour le rouvrir jusqu'au M25-E25.
- La sortie de `bao operator init` ne s'affiche jamais ; aucun secret sur une ligne de commande, dans Git en clair ou dans un compte rendu ; tout secret local dans `~/.config/workbook/` (600).
- Le jeton racine ne sert que d'E04 à E08, puis il est révoqué, **après** qu'une connexion OIDC d'administrateur a été essayée.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| `vault01` | 1021, 10.10.20.21, Debian 13, 2 vCPU, 1 Go, 20 Go ; OpenBao **2.6.4** ; ports 8200 (TLS) et 8201 |
| Nom du service | `https://openbao.par1.medisphere.internal:8200` → 10.10.20.21 (VIP au M25-E24) ; `BAO_ADDR` sur `adm01` |
| Parts | 5, seuil 3 : `claire.morel`, `karim.benali`, `sophie.laurent`, `nadia.roussel`, `<MOI>` ; `secrets/openbao-init.yml` de `plateforme/ansible` |
| Moteur | `kv/` (KV v2, 10 versions) |
| Méthodes | `oidc/` (client Keycloak `openbao`, rôle `personne`) ; `approle/` (`wb-checks`, `medictl`) |
| Fichiers des checks | `~/.config/workbook/openbao-checks.env` (E07) ; avant, jeton de ta session |
| Projet | `plateforme/secrets` (E08) |
| Documentation | `docs/securite/secrets/` de `plateforme/medisphere` |

> **Mémoire** : `vault01` ajoute 1 Go. Le palier ne touche pas au cluster : si `pve01` manque de mémoire, arrête `k8s-par1` (procédure du M14) le temps du palier, jamais une VM du socle.

**Durée** : 15 à 19 heures. **Ordre conseillé** : celui de la carte, E01 → E09 (voir l'introduction).

---

### M25-E01 — Test de positionnement : secrets  `Q` `★★`

> **Ticket PLAT-2601** — *De : Karim Benali*
> Une heure, par écrit, sans moteur de recherche ni IA. Tout le monde a déjà rangé « un mot de passe dans un fichier chiffré » ; je veux savoir si tu sais ce qu'un `kubectl get secret` montre vraiment, pourquoi un secret retiré d'un fichier reste dans Git, et ce qu'on appelle le secret zéro. Réponds même là où tu hésites.

**Objectifs pédagogiques**
- Évaluer tes acquis sur la gestion des secrets : cycle de vie, stockage, transport, rotation, exposition.
- Repérer les notions à travailler et les exercices du module qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 14 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Les notions*

1. Parmi ces éléments de la configuration de MédiAgenda, lesquels sont des **secrets**, et pourquoi ? L'adresse de la base, le nom de l'utilisateur PostgreSQL, son mot de passe, le nom du compartiment S3 de MédiDoc, la clé d'accès S3, la clé secrète S3, le niveau de journalisation, le certificat TLS public de l'API, sa clé privée. Donne un critère simple pour trancher.

2. Qu'est-ce que la **durée de vie** d'un secret, et pourquoi un secret qui vit une heure est-il moins dangereux qu'un secret qui vit trois ans, à valeur égale ? Cite deux façons de raccourcir la durée de vie d'un mot de passe de base de données.

3. *(QCM)* Le mot de passe de la base de recette de MédiAgenda n'a jamais changé depuis l'installation. Quel est le principal risque ?
   - A. Le mot de passe finit par « s'user » et devient plus facile à deviner
   - B. Toute personne ou machine qui l'a connu un jour (ancien prestataire, poste perdu, fichier `.env` collé dans un ticket) peut encore s'en servir
   - C. PostgreSQL refuse les mots de passe de plus d'un an
   - D. Aucun, si le mot de passe est long

4. Qu'appelle-t-on le **secret zéro** ? Prends l'exemple d'un pod qui doit lire son mot de passe de base dans un coffre : de quoi a-t-il besoin pour prouver qui il est, et comment éviter que ce « quelque chose » soit lui-même un secret durable ?

*Stockage et transport*

5. Distingue le chiffrement **au repos**, **en transit** et **en usage**. Pour chacun, donne un exemple dans le lab (ce qui est déjà en place, ce qui manque).

6. *(QCM)* Tu lances `kubectl get secret mediagenda-db-app -n mediagenda-recette -o yaml`. Que vois-tu ?
   - A. Le mot de passe chiffré : seul le kubelet a la clé
   - B. Le mot de passe encodé en base64, donc lisible par toute personne qui a le droit `get` sur les Secrets de l'espace
   - C. Une empreinte du mot de passe, irréversible
   - D. Rien : les Secrets ne sont jamais renvoyés par l'API

7. Passer un secret à une application par une **variable d'environnement** ou par un **fichier** monté : compare les deux du point de vue de la fuite (journaux, `/proc`, processus enfants, vidage d'erreur, rechargement à chaud).

8. Pourquoi ne faut-il jamais passer un mot de passe en **argument** d'une commande (`mysql -p'S3cret'`, `curl -u admin:S3cret`) ? Donne deux façons correctes de faire la même chose.

*Outils et habitudes*

9. Une variable de CI GitLab est marquée « masquée ». Qu'est-ce que cela garantit, et qu'est-ce que cela ne garantit **pas** ? Donne deux façons dont un job pourrait quand même révéler la valeur.

10. *(QCM)* Ansible Vault chiffre `vault-critique.yml` avec AES-256. Quelle affirmation est vraie ?
    - A. Le fichier est protégé tant que le mot de passe du Vault est protégé ; quiconque a ce mot de passe a **tous** les secrets du fichier, et rien ne dit qui les a lus
    - B. Chaque secret du fichier a ses propres droits d'accès
    - C. Le Vault fait tourner les mots de passe automatiquement
    - D. Ansible Vault journalise chaque déchiffrement dans GitLab

11. Lucas a commité un fichier `.env` par erreur, puis l'a supprimé dans le commit suivant, sur une branche déjà poussée. Le secret est-il encore exposé ? Que faut-il faire, **dans l'ordre**, et pourquoi la réécriture de l'historique ne suffit-elle pas ?

12. Qu'est-ce qu'un secret **dynamique** ? Donne l'exemple d'un mot de passe PostgreSQL et décris ce qui se passe à la fin de sa durée de vie.

*Exploitation*

13. Un secret a fuité (le `.env` de Lucas). Énumère les étapes de la réponse, de la découverte à la clôture, et dis pour chacune ce qu'il faut pouvoir **prouver** à l'auditeur HDS.

14. Pourquoi un coffre de secrets centralisé est-il aussi une **cible** privilégiée ? Cite trois mesures qui réduisent ce risque.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 14 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 28.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour chaque secret, pose deux questions : qui peut le **lire** aujourd'hui (personnes, machines, journaux, sauvegardes), et pendant **combien de temps** il donne un pouvoir.
</details>

<details><summary>Indice 2</summary>

Pour Git, souviens-toi que chaque clone, chaque cache de runner, chaque fork et chaque sauvegarde du serveur a déjà copié l'historique.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M25-E46), sans relire le corrigé, et compare. [OWASP *Secrets Management Cheat Sheet*](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)

---

### M25-E02 — Inventaire des secrets de MédiSphère  `RED` `★★`

> **Ticket SEC-2602** — *De : Sophie Laurent* — *Copie : Claire Morel*
> Avant d'acheter un coffre, je veux savoir ce qu'on va y mettre. Fais-moi l'inventaire de **tous** les secrets de la plateforme : où chacun est aujourd'hui, qui ou quoi le lit, comment et quand il tourne, ce qu'une fuite coûterait, et où il ira. Je sais qu'il y aura des secrets qui ne peuvent pas entrer dans le coffre : je veux les voir écrits, avec la raison. Aucune valeur dans le document, évidemment.

**Objectifs pédagogiques**
- Recenser les secrets d'une plateforme réelle par plusieurs sources (code, CI, cluster, postes, VMs), sans en lire les valeurs.
- Classer par criticité et choisir pour chacun une cible de migration (statique, dynamique, identité, chiffrement, certificat, ou hors du coffre).
- Distinguer les secrets d'**amorçage** et de **bris de glace**, qui doivent rester lisibles coffre fermé.

**Prérequis** : modules 01 à 24 (le registre des secrets `docs/socle/registre-secrets.md` tenu depuis le M01).
**Durée indicative** : 1 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Livrable | `docs/securite/secrets/inventaire-secrets.md` de `plateforme/medisphere`, par MR relue par Sophie |
| Colonnes | secret, propriétaire (groupe), où aujourd'hui, qui le lit, rotation aujourd'hui, criticité (C1 à C3, à définir), cible |
| Cibles | `KV` (statique dans le coffre), `DYN` (dynamique), `ID` (supprimé, remplacé par une identité), `TR` (transit : la clé ne sort plus), `PKI` (certificat court), `AMO` (reste hors du coffre : amorçage, bris de glace) |
| Sources | `docs/socle/registre-secrets.md` ; fichiers `vault-*.yml` de `plateforme/ansible` et des autres dépôts ; variables de CI des projets et des groupes ; `plateforme/k8s/outils/secrets-k8s.conf` (M19-M24) ; Secrets du cluster ; `~/.config/workbook/` ; clés SSH, WireGuard, PBS, racine PKI |

**Travail demandé**

1. Relis `docs/socle/registre-secrets.md` : que contient-il, que ne contient-il pas (ce qui a été créé sans y être inscrit) ?
2. Recense, **sans afficher aucune valeur** :
   - les fichiers Ansible Vault de tous les dépôts (noms, identité `lab` ou `critique`), et les **noms** des variables qu'ils contiennent (`ansible-vault view … | grep -o '^[a-z_]*:'`) ;
   - les variables de CI de tous les projets et groupes (API GitLab : clés, attributs protégé, masqué, caché, portée ; jamais `value`) ;
   - les Secrets du cluster par espace, avec leur origine (Helm, opérateur, `secrets-k8s.sh`, cert-manager) ; une colonne de métadonnées suffit (`kubectl get secret -A -o custom-columns=…`) ;
   - les fichiers de `~/.config/workbook/` et les clés de `~/.ssh/` d'`adm01` ;
   - ce qui vit sur les VMs : clés WireGuard, jetons PBS, mot de passe de step-ca, clé de chiffrement d'etcd, `admin.conf`, clé `age` des instantanés.
   Note les commandes dans `~/m25/e02/releve.md` (sans valeurs).
3. Définis ton échelle de criticité (trois niveaux, avec un exemple chacun) : qu'est-ce qu'une fuite permet, à qui, et sur quelles données.
4. Écris l'inventaire. Pour chaque ligne, choisis une cible et justifie les `AMO` : de quoi le coffre a-t-il besoin pour démarrer, et de quoi a-t-on besoin quand il est fermé ?
5. Termine par une section « Constats » : secrets critiques encore hors coffre, secrets qui ne tournent jamais, ce qu'on ne sait pas dire aujourd'hui (qui a lu quoi), et une ligne pour le `.env` de Lucas.
6. MR, relecture, fusion.

**Critères de réussite**
- [ ] L'inventaire est sur `main` de `plateforme/medisphere`, sans aucune valeur, avec au moins 30 secrets couvrant Ansible Vault, CI, cluster, `adm01` et VMs.
- [ ] Chaque ligne a un propriétaire, une criticité définie par l'échelle du document, et une cible ; chaque `AMO` est justifiée.
- [ ] La section « Constats » nomme les premières migrations à faire et ce qui reste hors du coffre.

<details><summary>Indice 1</summary>

L'API GitLab liste les variables d'un projet (`/projects/:id/variables`) et d'un groupe (`/groups/:id/variables`) ; `jq 'map(del(.value))'` retire les valeurs **avant** tout affichage. Pour le cluster, `kubectl get secret -A -o custom-columns=ESPACE:.metadata.namespace,NOM:.metadata.name,TYPE:.type,GERE:.metadata.labels` ne montre aucune donnée.
</details>

<details><summary>Indice 2</summary>

Un secret d'amorçage, c'est ce qu'il faut pour **redémarrer le coffre** ou **réparer sans lui** : ses propres parts, le mot de passe du Vault `critique`, le réseau, les sauvegardes, le compte de bris de glace du cluster. S'ils étaient dans le coffre, une panne du coffre serait sans issue.
</details>

**Pour aller plus loin** (facultatif) : lance `gitleaks detect` sur l'historique complet de chaque dépôt (M19) et ajoute à l'inventaire ce qu'il trouve. [OWASP : *Secrets Management*](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)

---

### M25-E03 — Installer et initialiser OpenBao sur `vault01`  `LAB` `★★`

> **Ticket PLAT-2603** — *De : Karim Benali* — *Copie : Sophie Laurent, Claire Morel*
> OpenBao sur `vault01`, un nœud pour commencer, stockage Raft intégré, TLS par notre step-ca. Le paquet officiel, vérifié, et la configuration par Ansible comme le reste. Sophie a deux exigences pour l'initialisation : **personne ne doit pouvoir rouvrir le coffre seul**, et les parts de la clé ne doivent jamais apparaître en clair, ni à l'écran, ni sur disque. Cinq dépositaires, seuil de trois : Claire, moi, Sophie, Nadia et toi. Écris la décision et le procès-verbal.

**Objectifs pédagogiques**
- Installer OpenBao depuis la publication amont vérifiée (signature, empreinte) et le configurer par un rôle Ansible : stockage Raft, TLS ACME, unité systemd.
- Initialiser un coffre en cérémonie : découpage de Shamir, chiffrement de chaque part pour son dépositaire, jeton racine initial protégé.
- Observer la barrière : scellé, descellé, re-scellé par un redémarrage.

**Prérequis** : M24-E04 (modèle d'un hôte du socle : `vm-debian`, `certificats_acme`, `pare_feu_local`) ; M06-E18 (ACME) ; M04-E30 (Vault `critique`) ; M14 (`age`).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VM | `vault01`, VMID 1021, 10.10.20.21, Debian 13, 2 vCPU, 1 Go, 20 Go `local-nvme` ; étiquettes `socle`, `role-coffre` ; `socle/vault01.tf` de `plateforme/infra` |
| Nom du service | A `openbao.par1.medisphere.internal` → 10.10.20.21, TTL court (il passera sur la VIP 10.10.20.200 au M25-E24) |
| Paquet | `openbao_2.6.4_linux_amd64.deb` de la publication `v2.6.4` (<https://github.com/openbao/openbao/releases>), avec `checksums.txt` et sa signature `checksums.txt.gpgsig` |
| Rôles Ansible | `openbao` (nouveau) ; playbook `playbooks/coffre.yml` (groupe `role_coffre`) : paquet, `certificats_acme` (id `openbao`, `/etc/openbao/tls/cert.pem` et `key.pem`, noms `vault01…` et `openbao…`), `pare_feu_local`, configuration et service ; `outils_openbao` (nouveau, CLI `bao` sur `adm01`), playbook `playbooks/outils-openbao.yml` |
| Configuration | `/etc/openbao/openbao.hcl` : stockage `raft` dans `/var/lib/openbao`, `node_id` = nom court, `api_addr`/`cluster_addr` au nom du nœud, écoute TLS sur 8200, grappe sur 8201, interface web |
| Flux | MGMT (10.10.10.0/24) et VPN (10.255.1.0/24) → `vault01` 8200 (bordure et filtrage local) ; `ca01` → `vault01` 80 (défi ACME) |
| Parts | 5, seuil 3 ; dépositaires et clés publiques `age` dans `pki/openbao-depositaires.txt` de `plateforme/ansible` ; parts chiffrées dans `secrets/openbao-init.yml` (Vault `critique`) par `outils/openbao-parts.sh` (à écrire) |
| Clés des dépositaires | la tienne : `~/.config/workbook/age/openbao-<MOI>.age` (protégée par phrase de passe) ; celles de Claire, Karim, Sophie et Nadia : **simulées**, générées par toi, exportées chiffrées sur `<SUPPORT>`, effacées d'`adm01` |
| Documentation | `docs/securite/secrets/garde-des-parts.md` (décision, procès-verbal) |

**Travail demandé**

*A. Lire avant d'installer*

1. Lis la documentation de configuration du serveur (bloc `storage "raft"`, `listener "tcp"`, `api_addr`, `cluster_addr`) et la page sur le scellement (*seal/unseal*). Note dans `~/m25/e03/notes.md` : ce que contient le stockage, ce qui est chiffré et par quoi, ce que fait `bao operator init`, ce qui se passe au redémarrage. Cherche aussi ce qu'est devenue l'option `disable_mlock` que citent les tutoriels de Vault, et ce qui protège la mémoire du processus à la place.
2. Télécharge sur `adm01` le paquet, `checksums.txt` et `checksums.txt.gpgsig`. Récupère la clé publique de signature d'OpenBao depuis la page de téléchargement officielle, vérifie la signature de `checksums.txt` (`gpg --verify`), puis l'empreinte du paquet (`sha256sum -c --ignore-missing`). Inspecte le paquet sans l'installer (`dpkg-deb -I`, `-c`, `-e`) : que contiennent `openbao.hcl` et l'unité systemd fournis, que font les scripts `preinst` et `postinst` ?

*B. La machine et le rôle*

3. `socle/vault01.tf` (sur le modèle d'`idp01.tf`) et l'enregistrement `openbao.par1.medisphere.internal`. MR, plan relu, apply.
4. Écris le rôle `openbao`. Exigences :
   - paquet téléchargé et vérifié par empreinte **avant** installation ; une montée de version (M25-E29) ne doit pas poser de question à `dpkg` sur `openbao.hcl` ;
   - ne crée **pas** le groupe `openbao` toi-même (relis le `preinst`) : le playbook installe donc le paquet **avant** le certificat ;
   - `openbao.hcl` en 0640 `root:openbao`, **validé** par OpenBao avant d'être posé (cherche la sous-commande de `bao operator` qui le fait) ; `/var/lib/openbao` en 0700 ;
   - l'unité du paquet reste intacte ; une surcharge (`openbao.service.d/`) coupe les vidages mémoire ;
   - le rôle n'initialise ni ne descelle **jamais** ; il ne **redémarre** pas un service déjà actif sans une variable explicite (et dit pourquoi quand il ne le fait pas) ;
   - contrôles : l'API répond en TLS vérifié avec la racine, la version et le stockage sont ceux attendus, rien n'écoute en clair.
5. `host_vars/vault01/` (`certificats.yml`, `pare_feu_local.yml`), `group_vars/role_coffre/openbao.yml`, `playbooks/coffre.yml`, règles de la bordure. Le certificat porte deux noms ; le renouvellement doit **recharger** OpenBao, jamais le redémarrer : pourquoi ? Rôles communs (`site.yml --limit vault01`), puis :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/outils-openbao.yml
   admin@adm01:~$ exec bash -l                 # relit ~/.bashrc (BAO_ADDR)
   admin@adm01:~$ bao status
   ```
   `bao status` renvoie le code 2 : que signifient `Initialized false` et `Sealed true` ? Que répond `curl -s -o /dev/null -w '%{http_code}' $BAO_ADDR/v1/sys/health`, et pourquoi ce code plutôt que 200 ?

*C. Les dépositaires*

6. Génère cinq identités `age`, une par dépositaire, **chacune protégée par une phrase de passe** dès sa création (aucune clé privée en clair sur disque, même un instant). La tienne va dans `~/.config/workbook/age/openbao-<MOI>.age` (dossier 700) ; celles des quatre autres dans `~/m25/e03/depositaires/`, avec quatre phrases de passe différentes rangées dans ton gestionnaire de mots de passe. Écris `pki/openbao-depositaires.txt` (identifiant et clé **publique**, dans l'ordre des parts).
7. Écris `outils/openbao-parts.sh` dans `plateforme/ansible`, avec trois sous-commandes au moins :
   - `chiffrer DESTINATAIRES` : lit sur l'entrée standard la sortie JSON de `bao operator init`, chiffre chaque part pour **son** dépositaire et le jeton racine pour toi, écrit un document JSON (donc YAML) sur la sortie standard ; refuse si le nombre de parts et de dépositaires diffère ;
   - `desceller NUMÉRO IDENTITÉ` : déchiffre une part avec l'identité de son dépositaire et la présente à `sys/unseal`, sans l'afficher ni la passer en argument ;
   - `jeton-racine IDENTITÉ` : charge le jeton racine dans la session de la CLI (`~/.vault-token`), sans l'afficher.
   Essaie-le de bout en bout (initialisation, descellement, jeton) contre un serveur **jetable non initialisé** sur `adm01` : `bao server -config=…` avec un stockage `raft` dans `~/m25/e03/essai/`, une écoute sur `127.0.0.1:18200` sans TLS (essai local seulement), et trois identités d'essai. Un serveur `bao server -dev` ne convient pas : il est déjà initialisé.

*D. La cérémonie*

8. Écris `docs/securite/secrets/garde-des-parts.md` **avant** l'initialisation : décision (découpage, dépositaires, protection, lieu de garde, cas de l'exercice), procès-verbal à remplir, quand et comment on descend au coffre.
9. Initialise, **d'un seul tube**, sans que rien ne s'affiche ni ne touche le disque en clair :
   ```
   admin@adm01:~/src/ansible$ bao operator init -format=json -key-shares=5 -key-threshold=3 \
   >   | JETON_POUR=<MOI> outils/openbao-parts.sh chiffrer pki/openbao-depositaires.txt \
   >   | uv run ansible-vault encrypt --encrypt-vault-id critique --output secrets/openbao-init.yml -
   admin@adm01:~/src/ansible$ outils/openbao-parts.sh resume
   ```
   > ⚠️ **Attention** : la sortie de `bao operator init` n'existe qu'**une fois**. Si le tube échoue au milieu (outil manquant, Vault mal configuré), les parts sont perdues et le coffre, initialisé, est inutilisable : il faut alors détruire `/var/lib/openbao` sur `vault01` (coffre **vide** à ce stade, rien d'autre à perdre) et recommencer. Fais un essai complet du tube contre le serveur jetable de l'étape 7 juste avant, et ne lance jamais l'initialisation sans `-format=json` vers le tube.
10. Descelle avec trois parts, dont la tienne, en jouant chaque dépositaire avec sa propre identité. Observe `bao status` entre chaque part (progression, `Unseal Nonce`), puis à la fin (`HA Mode`, `Raft Applied Index`).
11. Range les identités simulées : un export par dépositaire sur `<SUPPORT>` (elles sont déjà chiffrées par leur phrase de passe), vérifie que chacune se déchiffre depuis le support, puis efface-les d'`adm01` (`shred -u`). Remplis le procès-verbal. MR dans `plateforme/ansible` (outil, clés publiques, fichier chiffré) et `plateforme/medisphere` (garde des parts).

*E. La barrière*

12. Sur `vault01`, regarde ce qui est écrit : `sudo ls -la /var/lib/openbao`, `sudo strings /var/lib/openbao/raft/raft.db | head`. Que peux-tu y lire ? Redémarre le service (`sudo systemctl restart openbao`) : que répond `bao status` ? Que répondent `/v1/sys/health` et une requête authentifiée quelconque ? Descelle de nouveau.
    > ⚠️ **Attention** : ce redémarrage est voulu et le coffre est vide. Ensuite, plus jamais de redémarrage non décidé : à partir d'E04, le coffre contient des secrets et sa réouverture demande trois dépositaires.
13. Charge le jeton racine dans ta session (`outils/openbao-parts.sh jeton-racine …`) et lis-en les métadonnées (`bao token lookup`) : politiques, durée, expiration. Qu'est-ce qui le rend si dangereux ?

**Critères de réussite**
- [ ] `vault01` existe (VMID 1021, NetBox, `role-coffre`), résout dans les deux sens ; `openbao.par1.medisphere.internal` pointe sur lui.
- [ ] OpenBao 2.6 tourne sous `openbao` (paquet amont), stockage Raft dans `/var/lib/openbao` (700), `openbao.hcl` en 640, sans `disable_mlock` ni TLS désactivé, sans vidage mémoire ni swap ; certificat valide pour les deux noms jusqu'à la racine ; renouvellement par rechargement.
- [ ] Le coffre est initialisé (5 parts, seuil 3) et descellé ; `secrets/openbao-init.yml` est chiffré (identité `critique`) et ne contient que des parts chiffrées par `age` ; `pki/openbao-depositaires.txt` liste cinq clés publiques.
- [ ] Aucune clé privée `age` en clair sur `adm01` ; la garde des parts et son procès-verbal sont sur `main`.
- [ ] La CLI `bao` est sur `adm01`, `BAO_ADDR` vise le nom du service.

**Vérification** : `lab/bin/check 25 03`

<details><summary>Indice 1</summary>

Le `preinst` du paquet fait `useradd --system --user-group openbao` : si un groupe `openbao` existe déjà, `useradd` refuse et le paquet ne s'installe pas. Pour la validation de la configuration, la liste des sous-commandes de `bao operator` en contient une dont le nom dit tout ; regarde ses codes de retour (erreur et avertissement).
</details>

<details><summary>Indice 2</summary>

`age-keygen | age -p -a > fichier.age` crée une identité et la chiffre aussitôt par phrase de passe, sans fichier intermédiaire ; `age -d -i fichier.age` sait s'en servir (il demande la phrase). `age-keygen -y` donne la clé publique d'une identité lue sur l'entrée standard.
</details>

<details><summary>Indice 3</summary>

`bao operator unseal` sans argument demande la part au clavier ; un script fait mieux en passant par l'API : `POST /v1/sys/unseal` avec `{"key": "…"}` dans le corps, corps fabriqué par `jq -Rc '{key: .}'` et donné à `curl --data @-`. Dans le script, garde la part dans une variable, jamais dans un fichier, et vérifie qu'elle n'est pas vide avant de l'envoyer.
</details>

**Pour aller plus loin** (facultatif) : lis la documentation de l'initialisation par PGP (`-pgp-keys`, `-root-token-pgp-key`) et compare avec `age` ; regarde aussi l'auto-initialisation déclarative d'OpenBao (*self-initialization*) et dis pourquoi on ne la retient pas ici. [OpenBao : *Seal/Unseal*](https://openbao.org/docs/concepts/seal/) · [*Raft storage*](https://openbao.org/docs/configuration/storage/raft/) · [`bao operator init`](https://openbao.org/docs/commands/operator/init/)

---

### M25-E04 — Premiers pas : KV v2, versions, CLI et API  `LAB` `★`

> **Ticket PLAT-2604** — *De : Karim Benali*
> Avant d'y mettre de vrais secrets, apprends l'outil : le moteur KV en version 2, ses versions, la différence entre supprimer et détruire, l'écriture conditionnelle, et la même chose par l'API avec `curl`, parce que c'est ce que feront nos scripts et nos checks. Et écris les conventions d'arborescence : je ne veux pas découvrir dans six mois quarante façons de nommer un mot de passe.

**Objectifs pédagogiques**
- Monter un moteur KV v2 et en régler les versions.
- Écrire, lire, versionner, supprimer, restaurer et détruire un secret ; poser des métadonnées ; imposer l'écriture conditionnelle (CAS).
- Faire les mêmes opérations par l'API HTTP (`curl`, en-tête de jeton) et par la CLI en sortie JSON.
- Ne jamais laisser une valeur sur la ligne de commande ni à l'écran.

**Prérequis** : M25-E03.
**Durée indicative** : 1 h 15.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Jeton | le jeton racine de ta session (E03, étape 13), jusqu'à E08 |
| Moteur | `kv/`, KV **version 2**, description « Secrets statiques de MédiSphère (KV v2) », 10 versions par secret |
| Secret d'essai | `kv/plateforme/essai/demo`, champ `mot_de_passe`, valeurs générées (`openssl rand -base64 24`) |
| Métadonnées | `proprietaire`, `rotation`, `source`, `ticket` |
| Livrable | `docs/securite/secrets/conventions-kv.md` de `plateforme/medisphere` |

**Travail demandé**

1. Monte le moteur et règle-le :
   ```
   admin@adm01:~$ bao secrets enable -path=kv -version=2 -description="Secrets statiques de MédiSphère (KV v2)" kv
   admin@adm01:~$ bao write kv/config max_versions=10
   admin@adm01:~$ bao secrets list -detailed
   ```
   Pourquoi pas le montage `secret/` qu'installent les serveurs de développement ? Que changerait `-version=1` ?
2. Écris trois versions successives de `kv/plateforme/essai/demo`, **la valeur arrivant par l'entrée standard** :
   ```
   admin@adm01:~$ openssl rand -base64 24 | tr -d '\n' | bao kv put -mount=kv plateforme/essai/demo mot_de_passe=-
   ```
   Lis la dernière version sans l'afficher (`-field=… | wc -c`), puis la première (`-version=1`). Lis les métadonnées (`bao kv metadata get`) : où sont les versions, les dates, la version courante ?
3. Supprime la version courante (`bao kv delete`), lis-la, puis restaure-la (`bao kv undelete -versions=…`). Détruis la version 1 (`bao kv destroy -versions=1`) et essaie de la relire. Quelle différence entre les deux opérations, côté stockage et côté politique (quels chemins de l'API sont appelés) ?
4. Pose les métadonnées et l'écriture conditionnelle sur ce secret :
   ```
   admin@adm01:~$ bao kv metadata put -mount=kv -cas-required=true \
   >   -custom-metadata=proprietaire=plateforme -custom-metadata=rotation=jamais plateforme/essai/demo
   ```
   Réécris sans `-cas`, puis avec un `-cas` faux, puis avec le bon. Dans quelle situation réelle le CAS évite-t-il une perte ?
5. Refais les lectures par l'API avec `curl`, le jeton passé par fichier, jamais en clair sur la ligne de commande :
   ```
   admin@adm01:~$ curl -s -K <(printf 'header = "X-Vault-Token: %s"\n' "$(bao print token)") \
   >   $BAO_ADDR/v1/kv/metadata/plateforme/essai/demo | jq '.data | {current_version, max_versions, cas_required}'
   ```
   Lis la valeur courante (`/v1/kv/data/…`) en n'affichant que sa longueur ; liste les clés sous `kv/metadata/plateforme/` (méthode `LIST`). Compare avec `bao kv get -format=json` et `bao kv list`. Que montre `bao kv get -output-curl-string` ?
6. Écris `conventions-kv.md` : moteur et réglages, arborescence (plateforme, applications par environnement, essais), regroupement des champs, métadonnées obligatoires, règles d'écriture et de lecture sans trace. MR, fusion.

**Critères de réussite**
- [ ] `kv/` est un moteur KV version 2 qui garde 10 versions ; aucun autre moteur KV.
- [ ] `kv/plateforme/essai/demo` a au moins trois versions, la version 1 détruite, la version courante lisible, l'écriture conditionnelle imposée et les métadonnées `proprietaire` et `rotation`.
- [ ] `conventions-kv.md` est sur `main` (arborescence, métadonnées obligatoires).

**Vérification** : `lab/bin/check 25 04`

<details><summary>Indice 1</summary>

En KV v2, la CLI cache les vrais chemins : `bao kv put -mount=kv plateforme/x` écrit `kv/data/plateforme/x`, `bao kv metadata` vise `kv/metadata/…`, `delete`, `undelete` et `destroy` visent `kv/delete/…`, `kv/undelete/…`, `kv/destroy/…`. Ce sont ces chemins que les politiques nomment (E05).
</details>

<details><summary>Indice 2</summary>

`curl -X LIST` fonctionne, comme `GET …?list=true`. Une liste renvoie `data.keys` ; un nom qui finit par `/` est un « dossier ».
</details>

**Pour aller plus loin** (facultatif) : essaie `bao kv patch` et `delete_version_after` (suppression automatique des anciennes versions) ; cherche ce que fait l'option `-mount` face à l'ancienne syntaxe `bao kv get kv/plateforme/essai/demo`. [OpenBao : *KV v2*](https://openbao.org/docs/secrets/kv/kv-v2/) · [API KV v2](https://openbao.org/api-docs/secret/kv/kv-v2/)

---

### M25-E05 — Politiques et jetons  `LAB` `★★`

> **Ticket SEC-2605** — *De : Sophie Laurent*
> Le jeton racine, c'est tout ou rien. Avant de faire entrer qui que ce soit, je veux les politiques par groupe : l'équipe Plateforme administre sans être root, le support et la plateforme voient sans lire les valeurs, moi j'audite sans rien pouvoir changer, et l'équipe de Julien gère ses secrets de développement et rien d'autre. Montre-moi aussi la vie d'un jeton : combien de temps il dure, ce qui se passe quand on révoque son parent, et comment on retrouve un jeton qu'on ne connaît pas.

**Objectifs pédagogiques**
- Écrire des politiques HCL : chemins exacts, `*` et `+`, capacités, `deny`, `sudo` ; savoir quelle règle s'applique quand plusieurs correspondent.
- Vérifier une politique sans la deviner (`bao token capabilities`).
- Créer et observer des jetons : TTL, durée maximale, période, orphelins, accessors, révocation en cascade.

**Prérequis** : M25-E04.
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Politiques à écrire | `plateforme-admin`, `plateforme-lecture`, `securite-audit`, `mediagenda-dev` ; brouillons dans `~/m25/e05/*.hcl`, chargées par `bao policy write` (en code en E08) |
| Intention | voir le tableau du ticket ; `plateforme-admin` : configuration (montages, méthodes, politiques, identités, rôles), `kv/plateforme/*`, scellement d'urgence, régénération de racine ; jamais `sys/raw` ni les secrets des applications |
| Appartenances | `<MOI>` et Karim sont dans `plateforme-admins` **et** dans `plateforme` (M24) |
| Jetons d'essai | nom affiché `essai-e05-…` (`-display-name`), tous révoqués en fin d'exercice ; politique d'essai `essai-e05` supprimée |
| Livrable | `docs/securite/secrets/modele-acces-coffre.md` |

**Travail demandé**

*A. Les politiques*

1. Lis la page *Policies* de la documentation : syntaxe, capacités, `*` et `+`, et surtout la **priorité** quand plusieurs règles correspondent à un chemin. Lis aussi la politique `default` (`bao policy read default`) : que donne-t-elle à tout jeton ?
2. Écris et charge `mediagenda-dev` : gérer `kv/mediagenda/dev/*` (écrire, lire, supprimer et restaurer des versions, lister), voir quels environnements existent sous `kv/metadata/mediagenda/`, rien d'autre. Vérifie avec un jeton de cette politique :
   ```
   admin@adm01:~$ T=$(bao token create -policy=mediagenda-dev -ttl=15m -display-name=essai-e05-md -field=token)
   admin@adm01:~$ for c in kv/data/mediagenda/dev/x kv/data/mediagenda/prod/x kv/metadata/mediagenda/ kv/destroy/mediagenda/dev/x; do
   >   echo "$c : $(bao token capabilities "$T" "$c")"; done
   ```
   (Le jeton est ici dans une variable du shell le temps de l'essai : il ne donne accès qu'à des chemins vides et expire dans 15 minutes. Ne fais jamais cela avec un jeton utile.)
3. Écris `plateforme-lecture`, `securite-audit` et `plateforme-admin`. Pour chacune, une table de 5 à 10 chemins sensibles et la réponse attendue de `bao token capabilities`, puis la vérification.
4. Une même personne est dans `plateforme-admins` et dans `plateforme` : son jeton portera **les deux** politiques. Crée un jeton avec `-policy=plateforme-admin -policy=plateforme-lecture` et vérifie qu'il peut toujours **écrire** un rôle (`auth/approle/role/x`, `auth/oidc/role/x`) et un groupe (`identity/group/name/x`). Si ce n'est pas le cas, explique pourquoi avec la règle de priorité, et corrige les politiques de **lecture** (pas celle d'administration).
5. Ajoute à une politique d'essai `essai-e05` une règle `deny` sur un chemin que `plateforme-admin` permet, attache les deux à un jeton : qui l'emporte ? Supprime ensuite `essai-e05`.

*B. Les jetons*

6. Crée un jeton de 10 minutes renouvelable jusqu'à 30 minutes (`-ttl`, `-explicit-max-ttl`), renouvelle-le (`bao token renew -accessor …`) et observe `ttl` et `expire_time`. Puis un jeton **périodique** (`-period=1h`) : en quoi diffère-t-il, et pour quel genre de client sert-il ?
7. Fais une chaîne parent → enfant → petit-enfant (un jeton de politique `essai-e05` qui peut appeler `auth/token/create`), puis un jeton **orphelin**. Révoque le parent **par son accessor** : qui survit ? Pourquoi un jeton ordinaire ne peut-il pas créer d'orphelin ?
8. Liste les accessors vivants (`bao list auth/token/accessors`) et lis les métadonnées de chacun (`bao token lookup -accessor`). Que peut-on faire avec un accessor, que ne peut-on **pas** faire ? Révoque tous les jetons d'essai par leurs accessors.
9. Compare un jeton *batch* (`-type=batch`) : renouvellement, révocation, enfants, accessor, taille. Pour quels clients du coffre est-il fait ?
10. Écris `modele-acces-coffre.md` : principes, table groupes → politiques (peut / ne peut pas), règles d'écriture des politiques (dont la priorité entre motifs et ce que tu as constaté à l'étape 4), types et durées de jetons par usage. MR, fusion.

**Critères de réussite**
- [ ] Les quatre politiques existent ; `mediagenda-dev` ne vise que `kv/…/mediagenda/dev/` (et la liste de `kv/metadata/mediagenda/`), sans destruction ni `sudo` ; les politiques de lecture ne lisent aucune valeur ni n'écrivent ; `plateforme-admin` n'a ni chemin global, ni `sys/raw`, ni `kv/data` des applications, et peut sceller.
- [ ] Un jeton portant `plateforme-admin` et `plateforme-lecture` garde les droits d'écriture de l'administration.
- [ ] Aucune politique ni aucun jeton d'essai ne subsiste.
- [ ] `modele-acces-coffre.md` est sur `main` et explique la priorité entre motifs.

**Vérification** : `lab/bin/check 25 05`

<details><summary>Indice 1</summary>

Entre deux politiques, les capacités ne se cumulent que pour une règle de **même chaîne**. Pour des chaînes différentes qui correspondent toutes deux, OpenBao ne garde que la plus précise (la documentation donne l'ordre exact : position du premier joker, `*` final, nombre de `+`, longueur). Une règle `auth/+/role/+` en lecture « gagne » donc sur `auth/+/role/*` en écriture.
</details>

<details><summary>Indice 2</summary>

Certaines opérations exigent `sudo` en plus de la capacité de base : la documentation des points d'API le dit (« requires sudo »). Essaie `sys/auth/<méthode>` et `sys/mounts/<moteur>` avec et sans `sudo` : les deux ne se comportent pas pareil. Pour une liste, regarde le chemin exact que la CLI demande (avec `-output-curl-string`).
</details>

<details><summary>Indice 3</summary>

Révoquer un jeton révoque ses enfants (et leurs baux) ; un orphelin n'a pas de parent, il ne disparaît qu'à sa propre expiration ou révocation. `bao token revoke -accessor <accessor>` révoque sans connaître le jeton.
</details>

**Pour aller plus loin** (facultatif) : écris une politique **modélisée** (`{{identity.entity.aliases.<accessor>.name}}`) qui donne à chaque personne un espace `kv/personnel/<identifiant>/*` ; essaie-la après E06. [OpenBao : *Policies*](https://openbao.org/docs/concepts/policies/) · [*Tokens*](https://openbao.org/docs/concepts/tokens/)

---

### M25-E06 — Les personnes entrent par le SSO : méthode OIDC  `LAB` `★★`

> **Ticket PLAT-2606** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Personne ne doit avoir de mot de passe propre au coffre. On se connecte à OpenBao comme partout ailleurs depuis le M24 : par Keycloak, avec l'OTP pour les administrateurs, et les droits viennent des groupes de l'annuaire. Le client Keycloak se crée par le code, son secret ne doit apparaître nulle part en clair. Je veux voir Karim administrer, Lucas regarder sans lire, et Julien dans ses secrets de développement.

**Objectifs pédagogiques**
- Configurer la méthode `oidc` d'OpenBao contre Keycloak : découverte, client confidentiel, rôle, audience, redirections.
- Faire porter les droits par les groupes de la revendication `groups`, au moyen de **groupes externes** et de leurs alias.
- Se connecter par le navigateur (interface web) et par la CLI depuis `adm01`, et lire ce que contient le jeton obtenu.

**Prérequis** : M25-E05 ; M24-E08 (`plateforme/identite` en code), M24-E21 (OTP des administrateurs).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Client Keycloak | `openbao`, royaume `medisphere`, confidentiel, flux standard seul, PKCE `S256`, redirections **exactes** `https://openbao.par1.medisphere.internal:8200/ui/vault/auth/oidc/oidc/callback` et `http://localhost:8250/oidc/callback` ; fichier `tofu/clients-openbao.tf` de `plateforme/identite`, par MR |
| Secret du client | `kv/plateforme/openbao/oidc`, champ `client_secret` ; lu une fois par `tofu output` et écrit par un tube |
| Méthode | `oidc/`, découverte `https://sso.par1.medisphere.internal/realms/medisphere`, client `openbao`, rôle par défaut `personne` ; visible sur la page de connexion de l'interface web |
| Rôle `personne` | `user_claim` `preferred_username`, `groups_claim` `groups`, `bound_audiences` `openbao`, portées `profile` et `email`, mêmes redirections que le client, politique `default` seule, 1 h renouvelable jusqu'à 8 h |
| Groupes externes | `plateforme-admins` → `plateforme-admin` ; `plateforme`, `support` → `plateforme-lecture` ; `securite` → `securite-audit` ; `mediagenda` → `mediagenda-dev` |
| CLI | `bao login -method=oidc skip_browser=true` sur `adm01` ; le navigateur est sur ton poste : tunnel SSH du port 8250 (`ssh -L 8250:localhost:8250 admin@adm01`) |
| Flux | `vault01` → `sso` (VIP lb 443) : la règle « VLAN 20 → sso » du M24-E04 |

**Travail demandé**

*A. Le client, en code*

1. Dans `plateforme/identite`, écris `tofu/clients-openbao.tf` (sur le modèle du client d'essai du M24-E08) et une sortie **sensible** qui expose son secret. MR, plan relu, apply par le pipeline. Vérifie dans la console que le client existe, sans afficher son secret.
2. Range le secret dans le coffre sans qu'il passe par l'écran :
   ```
   admin@adm01:~/src/identite$ . outils/charger-acces.sh
   admin@adm01:~/src/identite$ tofu -chdir=tofu output -raw openbao_client_secret \
   >   | bao kv put -mount=kv plateforme/openbao/oidc client_secret=-
   admin@adm01:~$ bao kv metadata put -mount=kv -custom-metadata=proprietaire=plateforme \
   >   -custom-metadata=rotation=annuelle -custom-metadata=source=keycloak plateforme/openbao/oidc
   ```

*B. La méthode et le rôle*

3. Active la méthode, avec une description, et rends-la visible sur la page de connexion de l'interface (`bao auth tune -listing-visibility=unauth`). Écris sa configuration : la valeur du secret arrive par l'entrée standard, depuis le coffre lui-même (`bao kv get -field=client_secret … | bao write auth/oidc/config … oidc_client_secret=-`). Relis la configuration (`bao read auth/oidc/config`) : le secret y figure-t-il ?
4. Écris le rôle `personne` selon le contexte technique. Pourquoi `bound_audiences` ? Que se passerait-il si un autre client du royaume (`grafana`) pouvait faire accepter ses ID tokens ici ?
5. Crée les cinq groupes **externes** et leurs alias (nom du groupe Keycloak, accessor de la méthode `oidc`). Pourquoi ne pas mettre les politiques dans le rôle, ou faire un rôle par groupe ?

*C. Les connexions*

> ⚠️ **Attention** : garde **ouverte** ta session racine (dans un terminal à part) jusqu'à la fin de la partie C : si la configuration OIDC est fausse, c'est elle qui la corrige. Rien ici ne retire d'accès ; la racine ne sera révoquée qu'en E08, après un essai réussi.

6. Connecte-toi dans l'interface web (`https://openbao.par1.medisphere.internal:8200/ui`), méthode OIDC, en `<MOI>` : Keycloak te demande-t-il l'OTP ? Que vois-tu dans le menu ?
7. Connecte-toi en CLI depuis `adm01`, en gardant ta session racine dans l'autre terminal :
   ```
   toi@poste:~$ ssh -L 8250:localhost:8250 admin@adm01
   admin@adm01:~$ bao login -method=oidc skip_browser=true
   admin@adm01:~$ bao token lookup
   ```
   Repère `display_name`, `policies`, `identity_policies`, `entity_id`, `ttl`. Où sont tes droits ? Vérifie avec `bao token capabilities` que tu peux écrire `sys/policies/acl/x` et pas lire `kv/data/mediagenda/dev/x`.
8. Connecte-toi (fenêtre privée, interface web) en `lucas.martin`, puis en `julien.petit` si tu as ses accès de test : vérifie que Lucas voit les métadonnées sans lire de valeur, que Julien écrit dans `kv/mediagenda/dev/` et rien ailleurs. Retire Lucas du groupe `plateforme` dans l'annuaire (par le dépôt, M24) : à quel moment perd-il ses droits dans OpenBao ? Remets-le.
9. Regarde ce qu'OpenBao a créé à ta première connexion : `bao list identity/entity/id`, `bao read identity/entity/id/<id>` (alias, métadonnées), `bao read identity/group/name/plateforme-admins` (membres). Pourquoi le groupe externe n'a-t-il aucun membre « en dur » ?

**Critères de réussite**
- [ ] `clients-openbao.tf` est sur `main` de `plateforme/identite` ; le client `openbao` est confidentiel, en flux standard seul, avec PKCE `S256` et exactement les deux redirections.
- [ ] Le secret du client est dans `kv/plateforme/openbao/oidc` ; la méthode `oidc/` vise l'émetteur du royaume `medisphere`, client `openbao`, rôle par défaut `personne` ; aucune méthode `userpass`.
- [ ] Le rôle `personne` exige l'audience `openbao`, lit `preferred_username` et `groups`, ne donne que `default`, pour 8 h au plus.
- [ ] Les cinq groupes externes portent leurs politiques par un alias sur la méthode `oidc`.
- [ ] Tu t'es connecté au moins une fois par OIDC (une entité avec un alias `oidc` à ton nom existe).

**Vérification** : `lab/bin/check 25 06`

<details><summary>Indice 1</summary>

Un groupe **externe** reçoit ses membres de la méthode d'authentification, à chaque connexion : OpenBao compare chaque valeur de la revendication `groups_claim` avec les **alias** des groupes externes de cette méthode (`bao write identity/group-alias name=<groupe> mount_accessor=<accessor> canonical_id=<id du groupe>`). L'accessor de la méthode se lit dans `bao auth list -detailed`.
</details>

<details><summary>Indice 2</summary>

`bao login -method=oidc` ouvre un petit serveur HTTP sur `localhost:8250` **d'`adm01`** et attend que Keycloak y renvoie le navigateur. Ton navigateur est sur ton poste : sans tunnel, `localhost:8250` désigne ton poste, et le retour échoue. Une redirection refusée par Keycloak (`Invalid parameter: redirect_uri`) vient d'une différence d'un caractère entre le client et le rôle.
</details>

<details><summary>Indice 3</summary>

Les droits d'un groupe ne changent qu'à la **prochaine** connexion (ou au prochain renouvellement du jeton, qui relit les groupes) : un jeton déjà délivré garde les politiques d'identité calculées pour l'entité, mises à jour quand la personne se reconnecte. C'est une raison de garder des jetons courts.
</details>

**Pour aller plus loin** (facultatif) : essaie le mode `callbackmode=device` de la CLI (flux d'appareil : pas de tunnel, un code à saisir), et dis ce qu'il faut activer côté Keycloak et côté rôle. [OpenBao : *JWT/OIDC auth*](https://openbao.org/docs/auth/jwt/) · [*Identity: entities and groups*](https://openbao.org/docs/concepts/identity/) · [Keycloak : *OIDC clients*](https://www.keycloak.org/docs/latest/server_admin/#_oidc_clients)

---

### M25-E07 — Les machines : AppRole pour les checks et `medictl`  `LAB` `★★`

> **Ticket PLAT-2607** — *De : Karim Benali*
> Deux machines d'abord. Les vérifications du workbook : elles doivent lire la configuration du coffre et **jamais** une valeur. Et `medictl` : au M02, on avait écrit « au module 25, il lira son secret dans le coffre et le fichier disparaîtra d'`adm01` ». C'est maintenant. Le jeton Proxmox sort de `pve-api.env`. Et je veux qu'un identifiant volé ne serve à rien ailleurs que sur `adm01`.

**Objectifs pédagogiques**
- Configurer AppRole : `role_id` et `secret_id`, liaison à des adresses (`secret_id_bound_cidrs`, `token_bound_cidrs`), durée et nombre d'usages d'un `secret_id`, jetons *batch*.
- Écrire une politique de **métadonnées seulement** et vérifier qu'elle refuse les valeurs.
- Modifier un outil Python pour qu'il s'authentifie et lise son secret sans jamais l'écrire nulle part.

**Prérequis** : M25-E06 (tu es connecté par OIDC, administrateur) ; M02-E19 et M02-E25 (configuration et publication de `medictl`) ; M06-E11 (synchronisation NetBox par `medictl`).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Méthode | `approle/` |
| Rôle `wb-checks` | politique `wb-checks` seule (sans `default`), jetons *batch* de 10 minutes, `secret_id` et jeton liés à `adm01` (10.10.10.10/32), `secret_id` sans expiration ni limite d'usage (compensations à justifier) |
| Politique `wb-checks` | lecture de `sys/mounts`, `sys/auth`, des politiques, de `kv/config`, de `kv/metadata/*`, des rôles et configurations des méthodes, des groupes d'identité et des alias d'entités, liste des accessors de jetons et lecture de leurs métadonnées ; **jamais** `kv/data/*`, `role-id`, `secret-id` |
| Fichier des checks | `~/.config/workbook/openbao-checks.env` (600) : `BAO_ROLE_ID=…`, `BAO_SECRET_ID=…` |
| Rôle `medictl` | politique `medictl` (lecture de `kv/data/plateforme/medictl/*`), jetons *batch* de 5 minutes, mêmes liaisons |
| Secrets de `medictl` | `kv/plateforme/medictl/pve` (champ `token_secret`, jeton `wb-automation@pve!lab`) ; `kv/plateforme/medictl/pve-lecture` (jeton de lecture de la synchronisation NetBox) |
| Accès de `medictl` | `~/.config/workbook/medictl-openbao.env` (600) : `BAO_ADDR`, `MEDICTL_BAO_ROLE_ID`, `MEDICTL_BAO_SECRET_ID` |
| Code | `plateforme/outils` : module `src/medictl/coffre.py` (nouveau), `config.py` (le secret Proxmox, absent des fichiers, est lu dans le coffre ; chemin par défaut `plateforme/medictl/pve`, ou `MEDICTL_BAO_CHEMIN_PVE` dans le fichier d'accès Proxmox), tests |

**Travail demandé**

*A. L'identité des vérifications*

1. Lis la documentation d'AppRole : à quoi servent le `role_id` (identifiant) et le `secret_id` (preuve), qui devrait connaître l'un et l'autre, ce que changent `secret_id_bound_cidrs`, `token_bound_cidrs`, `secret_id_ttl`, `secret_id_num_uses` et `token_type`.
2. Écris et charge `wb-checks` selon le contexte technique. Active AppRole et crée le rôle `wb-checks`. Crée `openbao-checks.env` **sans afficher le `secret_id`** :
   ```
   admin@adm01:~$ R=$(bao read -field=role_id auth/approle/role/wb-checks/role-id)
   admin@adm01:~$ ( umask 077; bao write -f -format=json auth/approle/role/wb-checks/secret-id \
   >   | jq -r --arg r "$R" '"BAO_ROLE_ID=\($r | @sh)\nBAO_SECRET_ID=\(.data.secret_id | @sh)"' \
   >   > ~/.config/workbook/openbao-checks.env )
   admin@adm01:~$ lab/bin/check 25 04
   ```
   La ligne « accès des vérifications : jeton de ta session » a-t-elle disparu ? Le fichier contient un `secret_id` : ne le copie nulle part (l'étape 4 montre ce que la liaison d'adresse refuse, sans déplacer ce secret).
3. Prouve que cette identité ne lit **aucune** valeur : connecte-toi avec elle (API `auth/approle/login`, corps fabriqué par `jq` depuis le fichier) et essaie de lire `kv/data/plateforme/openbao/oidc`. Essaie aussi `auth/approle/role/wb-checks/secret-id` (en `LIST`). Pourquoi est-ce important qu'une identité de vérification ne puisse pas fabriquer de nouveaux `secret_id` ?
4. Essaie les limites d'un `secret_id` sur un rôle jetable `essai-e07` : `secret_id` à usage unique (`-num_uses`… ou `secret_id_num_uses` du rôle), `secret_id` de 2 minutes, `secret_id` lié à une autre adresse. Note les messages d'erreur. Supprime le rôle.

*B. `medictl` sort son secret du disque*

5. Range les deux jetons Proxmox de `medictl` dans le coffre **depuis les fichiers existants**, sans les afficher :
   ```
   admin@adm01:~$ ( . ~/.config/workbook/pve-api.env; printf '%s' "$PVE_TOKEN_SECRET" ) \
   >   | bao kv put -mount=kv plateforme/medictl/pve token_secret=-
   ```
   (même chose pour `pve-lecture.env` vers `plateforme/medictl/pve-lecture`), avec les métadonnées de `conventions-kv.md`.
6. Écris la politique `medictl` et le rôle `medictl`. Crée `medictl-openbao.env` comme à l'étape 2.
7. Dans `plateforme/outils`, écris `src/medictl/coffre.py` : chargement des accès (fichier en 600 lu sans être exécuté, variables d'environnement prioritaires, `https://` obligatoire), connexion AppRole, lecture d'un champ d'un secret KV v2, erreurs claires **qui ne contiennent jamais** le `secret_id`, le jeton ni la valeur. Dans `config.py`, si `PVE_TOKEN_SECRET` n'est donné ni par le fichier ni par l'environnement, lis-le dans le coffre. Tests avec `responses` (aucun appel réseau), dont un test qui vérifie que les tests ne lisent jamais les vrais accès du poste. MR, publication comme au M02-E25, installation sur `adm01`.
8. Retire `PVE_TOKEN_SECRET` des deux fichiers Proxmox (ajoute `MEDICTL_BAO_CHEMIN_PVE=plateforme/medictl/pve-lecture` dans `pve-lecture.env`), puis :
   ```
   admin@adm01:~$ medictl config
   admin@adm01:~$ medictl vm list
   admin@adm01:~$ sudo systemctl start medictl-netbox-sync.service && journalctl -u medictl-netbox-sync -n 20 --no-pager
   ```
   D'où vient le secret, d'après `medictl config` ? La synchronisation du M06 (service système sous l'utilisateur `admin`, fichier `pve-lecture.env`) passe-t-elle sans modification de son unité ?
9. Qu'as-tu gagné, et qu'as-tu seulement déplacé ? Écris-le dans `~/m25/e07/notes.md` (le `secret_id` est-il un « secret zéro » ? Que vaut-il volé ? Comment le faire tourner ?).

**Critères de réussite**
- [ ] `openbao-checks.env` (600) permet aux checks de se connecter ; l'identité des checks ne lit aucune valeur.
- [ ] Les rôles `wb-checks` et `medictl` : politique seule sans `default`, `secret_id` exigé et lié à `adm01`, jetons *batch* liés à `adm01`, de 15 minutes au plus.
- [ ] La politique `wb-checks` ne vise ni `kv/data`, ni `role-id`, ni `secret-id` ; `medictl` ne lit que `kv/data/plateforme/medictl/*`.
- [ ] `kv/plateforme/medictl/pve` existe ; `pve-api.env` ne contient plus de secret ; `medictl config` indique que le secret vient d'OpenBao ; `coffre.py` est sur `main` de `plateforme/outils`.

**Vérification** : `lab/bin/check 25 07`

<details><summary>Indice 1</summary>

`@sh` de `jq` met une valeur entre apostrophes en échappant ce qu'il faut : le fichier se relit par `source` (bash) et par le lecteur de fichiers de `medictl` (qui comprend les apostrophes, M02-E19). `umask 077` dans un sous-shell crée le fichier directement en 600, sans instant où il serait lisible par d'autres.
</details>

<details><summary>Indice 2</summary>

`secret_id_ttl` est plafonné par la durée maximale des baux de la méthode (768 h par défaut) : une valeur supérieure est ramenée silencieusement, relis le résultat. `0` veut dire « sans limite ». Une liaison d'adresse refuse avec `source address unauthorized` ; elle se vérifie sur l'adresse **vue par OpenBao** (pas de traduction d'adresse entre les VLAN du lab).
</details>

<details><summary>Indice 3</summary>

Dans `medictl`, le module de configuration existe déjà : il lit le fichier, applique l'environnement, valide. Ajoute l'appel au coffre **après** la lecture du fichier et de l'environnement, seulement si le secret manque, pour qu'un essai ponctuel (`PVE_TOKEN_SECRET=… medictl …`) reste possible. Dans les tests, une fixture automatique qui pointe `MEDICTL_BAO_ENV_FILE` vers un fichier inexistant garantit qu'aucun test ne parle au vrai coffre.
</details>

**Pour aller plus loin** (facultatif) : fais de même pour le jeton NetBox et la clé API de PowerDNS de `medictl` (`netbox.py`, `powerdns.py`) ; lis la documentation de l'**enveloppement de réponse** (`-wrap-ttl`) et imagine comment Ansible livrerait un `secret_id` sans jamais le voir (M25-E28). [OpenBao : *AppRole*](https://openbao.org/docs/auth/approle/) · [*Response wrapping*](https://openbao.org/docs/concepts/response-wrapping/)

---

### M25-E08 — OpenBao en code avec OpenTofu  `LAB` `★★`

> **Ticket PLAT-2608** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Tout ce que tu as créé à la main depuis E04 passe en code, dans un nouveau projet `plateforme/secrets` : moteur, méthodes, rôles, groupes, politiques. Importé, pas recréé (les `role_id` et les identifiants des groupes ne doivent pas changer), plan vide ensuite. Le secret du client OIDC ne doit être ni dans le code, ni dans l'état. Et quand c'est fini, le jeton racine disparaît : Sophie veut le voir révoqué dans le journal, pas « rangé quelque part ».

**Objectifs pédagogiques**
- Piloter OpenBao par OpenTofu avec le fournisseur `hashicorp/vault`, et vérifier ce qui est compatible.
- Importer des objets existants et converger jusqu'à un plan vide ; garder les secrets hors du plan et de l'état (ressource éphémère, argument en écriture seule).
- S'authentifier pour appliquer avec son identité nominative, jamais avec la racine ; révoquer la racine en gardant un chemin de retour.

**Prérequis** : M25-E07 ; M24-E08 (même démarche pour Keycloak) ; M05-E11 à E27 (état S3, verrou, chiffrement de l'état).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projet | **`plateforme/secrets`** (groupe `plateforme`, `main` protégée, fusion par MR ; Sophie relit `politiques/`) |
| Fournisseur | **`hashicorp/vault` `~> 5.13`** (aucun fournisseur `openbao` publié) ; OpenTofu 1.13 |
| Code | `tofu/` : `fournisseurs.tf`, `chiffrement.tf` (identique à `plateforme/identite`), `variables.tf`, `montages.tf`, `methodes.tf`, `oidc.tf`, `approle.tf`, `politiques.tf` (une ressource par fichier de `politiques/`), `imports.tf` ; `politiques/*.hcl` (tes brouillons d'E05 et E07) ; `outils/charger-acces.sh`, `outils/identifiants-openbao.sh` |
| État | S3 `https://s3-01.par1.medisphere.internal:8333`, compartiment `tofu-state`, clé **`secrets/terraform.tfstate`**, verrou natif, chiffré côté client |
| Authentification | ton jeton OIDC (`bao login -method=oidc`, `~/.vault-token`), politique `plateforme-admin` ; jamais le jeton racine ; le fournisseur en tire un jeton enfant de 20 minutes |
| Secret du client OIDC | lu dans `kv/plateforme/openbao/oidc` par une ressource **éphémère**, poussé par `oidc_client_secret_wo` |
| Pipeline (palier 1) | `fmt`, `validate`, garde-fous sur les politiques ; plan et apply depuis `adm01` (le pipeline s'authentifiera au M25-E10) |

**Travail demandé**

*A. Lire et décider*

1. Parcours la documentation du fournisseur pour `vault_mount`, `vault_kv_secret_backend_v2`, `vault_auth_backend`, `vault_jwt_auth_backend`, `vault_jwt_auth_backend_role`, `vault_approle_auth_backend_role`, `vault_identity_group`, `vault_identity_group_alias`, `vault_policy`, et la ressource éphémère `vault_kv_secret_v2` : identifiant d'import de chacune, arguments en écriture seule disponibles. Lesquelles de ces ressources visent des fonctions qu'OpenBao n'a pas ? Que fait le fournisseur au démarrage avec le jeton qu'il trouve ?
2. Pourquoi ne pas gérer ici les `secret_id` des AppRole (`vault_approle_auth_backend_role_secret_id`), ni les valeurs des secrets KV (`vault_kv_secret_v2` en ressource) ?

*B. Le code et l'import*

3. Crée le projet et écris les fichiers de `tofu/` pour décrire **ce qui existe**. Les politiques viennent des fichiers `politiques/*.hcl` (une seule ressource à `for_each`). Écris `imports.tf` ; `outils/identifiants-openbao.sh` (lecture seule) te donne les identifiants des groupes et des alias.
4. Écris `outils/charger-acces.sh` (à sourcer) : accès S3 et phrase de chiffrement comme dans `plateforme/identite`, et **contrôle** du jeton de la session : refuse un jeton racine, un jeton sans `plateforme-admin`, une variable `VAULT_TOKEN`/`BAO_TOKEN` oubliée dans le shell. Puis :
   ```
   admin@adm01:~/src/secrets$ bao login -method=oidc skip_browser=true
   admin@adm01:~/src/secrets$ . outils/charger-acces.sh
   admin@adm01:~/src/secrets$ tofu -chdir=tofu init && tofu -chdir=tofu plan
   ```
   Fais converger jusqu'à ce que le plan n'annonce que les imports et des mises à jour que tu sais expliquer une à une (laquelle est inévitable la première fois ?). Pour chaque écart : le code se trompe, ou la réalité ne convient pas ?
5. Complète `.gitlab-ci.yml` (vérifications sans accès au coffre), versionne `.terraform.lock.hcl`. MR « import de la configuration du coffre », relecture, fusion ; apply depuis `adm01` (plan enregistré, puis plan vide). Contrôle l'état : `tofu -chdir=tofu state pull | jq '[.resources[] | .type] | unique'`, puis cherche le secret du client et les `role_id` dedans (sans les afficher : compte les occurrences).
   > ⚠️ **Attention** : `tofu state pull` affiche l'état **déchiffré**. Ne le redirige pas vers un fichier, ne le colle nulle part.
6. Change une politique par une MR (par exemple un commentaire dans `medictl.hcl`) : vérifie que seul ce changement est planifié et appliqué. Puis change-la **à la main** sur le serveur (`bao policy write`) et relance un plan : que propose OpenTofu ?

*C. La fin du jeton racine*

7. Avant de révoquer, prépare le retour : vérifie (a) que ta connexion OIDC d'administrateur fonctionne dans un second terminal, (b) que `bao operator generate-root -status` répond avec ce jeton OIDC (depuis OpenBao 2.6, régénérer une racine passe par un point d'API **authentifié**), (c) que tu sais déchiffrer trois parts (`outils/openbao-parts.sh resume`, puis un `age -d` vers `/dev/null` de ta part).
   > ⚠️ **Attention** : sans jeton racine, toute erreur de configuration se répare avec une identité nominative. Si OIDC tombe **et** qu'aucune autre identité d'administration n'existe, le retour passe par la réactivation temporaire de la régénération non authentifiée (`disable_unauthed_generate_root_endpoints = false` sur l'écouteur, donc un redémarrage qui scelle, puis trois parts) : c'est le bris de glace du coffre, à écrire dans le runbook du palier 3. Ne révoque qu'après les trois vérifications.
8. Révoque le jeton racine **par lui-même**, puis reviens à ta session OIDC :
   ```
   admin@adm01:~/src/ansible$ outils/openbao-parts.sh jeton-racine ~/.config/workbook/age/openbao-<MOI>.age
   admin@adm01:~$ bao token lookup | grep -E 'policies|display_name'
   admin@adm01:~$ bao token revoke -self
   admin@adm01:~$ bao login -method=oidc skip_browser=true
   ```
   Vérifie qu'aucun jeton racine ne vit plus (`bao list auth/token/accessors` et les métadonnées de chacun). Le jeton racine chiffré dans `secrets/openbao-init.yml` est désormais sans valeur : faut-il le retirer du fichier ?

**Critères de réussite**
- [ ] `plateforme/secrets` est sur `main` : fournisseur `hashicorp/vault` en `~> 5.13`, état `secrets/terraform.tfstate` avec verrou, chiffrement imposé, verrou des versions versionné ; dernier pipeline réussi.
- [ ] Le secret du client OIDC passe par une ressource éphémère et `oidc_client_secret_wo` ; aucun jeton ni secret littéral dans le code.
- [ ] Les six politiques sont des fichiers `politiques/*.hcl` identiques à celles du serveur, et le serveur n'en a pas d'autre (hors `default` et `root`) ; le plan est vide.
- [ ] Aucun jeton racine ne vit.

**Vérification** : `lab/bin/check 25 08`

<details><summary>Indice 1</summary>

Les montages et méthodes s'importent par leur chemin (`kv`, `oidc`, `approle`), leurs réglages KV par `kv/config`, les rôles par leur chemin complet (`auth/approle/role/<nom>`), les politiques par leur nom, les groupes et leurs alias par leur **identifiant** interne. Pour un `for_each` d'import sur des fichiers, `fileset()` sert aux deux blocs (ressource et import).
</details>

<details><summary>Indice 2</summary>

Une ressource éphémère qui dépend d'une ressource **en cours d'import** est différée (« Deferred due to pending dependencies ») : donne-lui le nom du montage en littéral. Un argument en écriture seule n'est jamais relu : OpenTofu ne le pousse que lorsque sa version (`…_wo_version`) change, et une fois à l'import.
</details>

<details><summary>Indice 3</summary>

Le fournisseur lit le jeton dans `VAULT_TOKEN` s'il existe, sinon dans `~/.vault-token`, celui que `bao login` remplit. Un `VAULT_TOKEN` oublié dans le shell (le jeton racine d'un essai) passerait **avant** ta session OIDC : c'est ce que `charger-acces.sh` doit refuser.
</details>

**Pour aller plus loin** (facultatif) : ajoute un contrôle de dérive planifié (plan nocturne qui doit être vide, alerte sinon, comme au M05-E28) ; il s'authentifiera au M25-E10. [Fournisseur `hashicorp/vault`](https://search.opentofu.org/provider/hashicorp/vault/latest) · [OpenTofu : *Ephemeral resources*](https://opentofu.org/docs/language/ephemerality/) · [OpenBao : *Generate root*](https://openbao.org/docs/commands/operator/generate-root/)

---

### M25-E09 — Questions : barrière, seal, baux et chemins  `Q` `★★`

> **Ticket PLAT-2609** — *De : Karim Benali*
> Tu as initialisé, descellé, écrit des politiques et jeté la racine. Avant d'y brancher la CI et le cluster, vérifions que le *pourquoi* est clair. Par écrit, avec tes mots, en t'appuyant sur ce que tu as observé.

**Objectifs pédagogiques**
- Expliquer le fonctionnement interne d'OpenBao à partir de ce que tu as observé : barrière, clés, scellement, stockage, baux, chemins.
- Choisir le bon type de jeton et le bon mécanisme pour un usage donné.

**Prérequis** : M25-E03 à M25-E08.
**Durée indicative** : 1 h 15.

**Travail demandé**

Réponds aux 12 questions.

1. Décris la chaîne des clés d'OpenBao : clé de chiffrement de la barrière (et son trousseau), clé racine, parts de Shamir. Laquelle chiffre quoi, laquelle est stockée où (et sous quelle forme) ? Que contient `/var/lib/openbao` que tu as regardé en E03 ?

2. *(QCM)* Un nœud OpenBao redémarre. Que se passe-t-il ?
   - A. Il relit la clé racine dans son fichier de configuration et reprend le service
   - B. Il démarre scellé : il sait où sont ses données mais ne peut pas les déchiffrer tant que la clé racine n'est pas reconstituée (parts) ou obtenue (seal automatique)
   - C. Il perd ses données : il faut restaurer un instantané
   - D. Il sert les lectures en cache mais refuse les écritures

3. *Seal* et *unseal* : que fait exactement `bao operator seal` ? Dans quelle situation l'équipe Plateforme le lancerait-elle volontairement, et que coûte cette décision ?

4. Pourquoi 5 parts et un seuil de 3 plutôt que 1 part, ou 5 parts et un seuil de 5 ? Que devient le dispositif quand le seal devient automatique (M25-E25) ?

5. Qu'est-ce qu'un **bail** (*lease*) ? Quels objets en ont un, lesquels n'en ont pas (compare un secret KV, un jeton de service, un identifiant PostgreSQL dynamique) ? Que se passe-t-il à l'expiration, et quand on révoque un bail par préfixe ?

6. *(QCM)* Un jeton a `ttl=1h`, `explicit_max_ttl=0`, et la méthode qui l'a délivré a `max_lease_ttl=8h`. Le client le renouvelle toutes les 50 minutes. Combien de temps vit-il ?
   - A. 1 heure exactement
   - B. Indéfiniment, puisqu'il est renouvelé
   - C. Au plus 8 heures, la durée maximale de la méthode
   - D. 50 minutes

7. Jeton de **service** et jeton ***batch*** : différences (stockage, renouvellement, révocation, accessor, enfants, réplication). Pourquoi les checks et `medictl` utilisent-ils des jetons *batch*, et pourquoi une personne qui travaille une journée reçoit-elle un jeton de service ?

8. Qu'est-ce qu'une **réponse enveloppée** (*response wrapping*) ? Raconte comment elle permettrait de livrer un `secret_id` à une machine sans que le pipeline qui le livre puisse s'en servir, et ce qu'elle permet de **détecter**.

9. Chemins et montages : pourquoi `kv/data/…` et `kv/metadata/…` pour un même secret ? Que se passerait-il pour les politiques si l'on montait le moteur une seconde fois en `kv-mediagenda/` ? Qu'est-ce qui distingue `sys/`, `auth/`, `identity/` et `cubbyhole/` ?

10. *(QCM)* Une personne a deux politiques. L'une contient `path "kv/data/mediagenda/*" { capabilities = ["read"] }`, l'autre `path "kv/data/mediagenda/prod/*" { capabilities = ["deny"] }`. Peut-elle lire `kv/data/mediagenda/prod/db` ?
    - A. Oui : les capacités s'additionnent
    - B. Non : la règle la plus précise s'applique, et elle refuse ; de plus `deny` l'emporte toujours
    - C. Oui : la première politique chargée l'emporte
    - D. Cela dépend de l'ordre des politiques dans le jeton

11. Dans `sys/`, cite quatre chemins que tu as utilisés dans ce palier, ce qu'ils font, et lesquels exigent `sudo`. Pourquoi l'API de santé (`sys/health`) répond-elle sans jeton, et avec des codes HTTP différents selon l'état ?

12. Le fournisseur OpenTofu s'appelle `hashicorp/vault` et fonctionne contre OpenBao. Qu'est-ce qui rend cette compatibilité possible, où s'arrête-t-elle, et comment t'en assures-tu avant chaque nouvelle ressource ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse (0, 1 ou 2 points) et calculé ton score sur 24.
- [ ] Pour chaque réponse fausse, tu as relu l'exercice du palier où tu l'as observé.

<details><summary>Indice 1</summary>

Reprends tes notes d'E03 (ce que montre `bao status` scellé, descellé, redémarré) et d'E05 (révocation en cascade, jetons *batch*) : chaque question a une observation.
</details>

<details><summary>Indice 2</summary>

Pour les baux, pense à ce qui doit se passer **à la source** quand le bail meurt : pour un secret KV, rien n'existe à détruire ; pour un identifiant PostgreSQL, un rôle doit être supprimé dans la base.
</details>

**Pour aller plus loin** (facultatif) : lis l'architecture interne (*Architecture*, *Seal/Unseal*, *Lease, renew and revoke*) et compare avec ce que tu feras au M25-E44 (sous le capot). [OpenBao : *Architecture*](https://openbao.org/docs/internals/architecture/) · [*Lease, renew, and revoke*](https://openbao.org/docs/concepts/lease/) · [*Response wrapping*](https://openbao.org/docs/concepts/response-wrapping/)
