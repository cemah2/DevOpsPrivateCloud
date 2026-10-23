# Module 24 — Palier 3 : Production

Au palier 2, tous les services ont rejoint le SSO : GitLab, Grafana, Argo CD, Harbor, Proxmox, PBS, NetBox, le cluster, Hubble, Pyroscope, Mailpit et les VMs passent par Keycloak et par l'annuaire. C'est une réussite, et c'est un risque : `idp01` est devenu la porte d'entrée de toute la plateforme. S'il tombe, plus personne ne se connecte ; si sa base est perdue, les secrets des clients, les clés de signature et les seconds facteurs disparaissent avec elle ; si un attaquant y entre, il entre partout. Personne ne mesure encore les échecs de connexion, personne n'a essayé les comptes de secours, et la RSSI ne peut toujours pas dire à l'auditeur, en une page, qui a accès à quoi. Ce palier fait passer l'identité en **production** : haute disponibilité étudiée et tranchée, sauvegardes restaurées pour de vrai, supervision et journal d'audit, durcissement, bris de glace éprouvé, rotations de secrets et de clés, revue des accès automatisée, ADR, montée de version, et un nouveau service ouvert au SSO en temps limité.

> ⚠️ **Rappel** : à partir d'ici, chaque changement de Keycloak ou de l'annuaire peut enfermer **tout le monde** dehors, toi compris. Avant **tout** changement de `idp01`, `ipa01`, du royaume ou de la publication : (1) une session d'administration déjà ouverte dans la console (`<MOI>-admin`) que tu ne fermes pas ; (2) `kc-secours` **essayé** dans une fenêtre privée dans les dix minutes qui précèdent ; (3) `admin.conf` (Vault `critique`) et une session SSH en `admin` sur `idp01` à portée de main ; (4) un instantané ou une sauvegarde de la base de Keycloak de moins d'une heure (à partir d'E25 : `sudo systemctl start identite-sauvegarde.service`). Si la console devient inaccessible : arrêt de Keycloak, `kc.sh bootstrap-admin user` (E04), puis analyse.

**Rappels du module**
- Un accès de secours ouvert **et essayé** avant tout changement d'authentification ; jamais de modification du royaume `master` sans un second administrateur vérifié dans une autre fenêtre.
- Aucun secret sur une ligne de commande, dans Git en clair ou dans un compte rendu ; tout secret local dans `~/.config/workbook/` (600) ou dans le Vault `critique`.
- L'annuaire est la seule source des personnes ; rien à la main dans le royaume `medisphere` (OpenTofu, `plateforme/identite`) ; le royaume `master` reste hors du code (OpenTofu n'y a aucun droit) : ce que tu y changes est écrit dans `docs/securite/identite/master.md`.

**Chemin imposé** (introduction du module) : VMs par `plateforme/infra` (OpenTofu ; la VM temporaire du palier dans l'état **`envs/m24`**) et `plateforme/ansible` (rôles `keycloak`, `freeipa_serveur`, `alloy`, `haproxy`, `pare_feu`, `pare_feu_local`, et le nouveau rôle `sauvegarde_identite`) ; royaume `medisphere` par `plateforme/identite/tofu/` ; supervision par `plateforme/observabilite` (`scrape/`, `regles/`, `loki/regles/`) et le témoin de `mon01` ; cluster par `plateforme/gitops` (Argo CD) ; documentation dans `docs/securite/identite/` de `plateforme/medisphere` (`adr/`, `runbooks/`). Tout passe par une MR relue.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Keycloak | **26.7.5** sur `idp01` jusqu'à E33, puis **26.8.1** (`keycloak-quarkus-dist-26.8.1.tar.gz`, SHA-256 `4e2740b181faa2ea623a1c2ecf00855935311e546046e2f857615a47ed24cbe8`) ; rôle `keycloak` : `keycloak_grappe` (E24), `keycloak_options` (dictionnaire d'options de `keycloak.conf`, E26, E27) ; une option de construction changée = reconstruction (le rôle la fait) |
| VM temporaire | **`idp02`** : VMID **2241**, **10.10.20.42**, Debian 13, 2 vCPU, **2 Go**, VNet `vinfra`, étiquettes `env-m24`, `role-idp` ; état OpenTofu **`envs/m24`** de `plateforme/infra` ; détruite en fin d'E24. **`idp-resto`** : VMID **2242**, VNet `vsandbox`, **10.10.99.42**, Debian 13, 2 Go, état `envs/m24`, restauration d'essai d'E25, détruite. Jamais les deux à la fois |
| Grappe d'essai | cache Infinispan distribué, pile **`jdbc-ping`** (découverte par la table `jgroups_ping` de la base partagée), TCP **7800** (données) et **57800** (détection de pannes), chiffrés par défaut ; base PostgreSQL de `idp01` ouverte à **10.10.20.42 seulement** le temps de l'essai |
| Sauvegardes | rôle **`sauvegarde_identite`** (`/usr/local/sbin/identite-sauvegarde`, unité et minuterie `identite-sauvegarde`) sur `idp01` (`pg_dump -Fc`) et `ipa01` (`ipa-backup`) ; chiffrement **age** vers une clé publique (privée au Vault `critique` et sur papier) ; envoi par `rclone` vers `s3-01`, compartiment **`identite-sauvegardes`** (versionné), identité S3 **`identite-sauvegardes`** (écriture et lecture, pas de suppression) ; trace `/var/lib/identite-sauvegarde/dernier-succes`. VMs 1030 et 1031 : stockage Proxmox **`pbs-par2-identite`** (datastore `ds-lab`, espace de noms **`par1/identite`**), tâche **`identite-nuit`** |
| Supervision | ScrapeConfig **`keycloak`** (`plateforme/observabilite/scrape/keycloak.yaml`, `https://idp01…:9000/metrics`) ; règles **`regles/identite.yaml`** (`KeycloakIndisponible`, `KeycloakEchecsConnexion`) ; règles du ruler de Loki **`loki/regles/audit/identite.yaml`** (`FederationLdapEnEchec`, puis en E28 les alertes de bris de glace) ; journaux de Keycloak et de FreeIPA dans Loki, locataire **`audit`**, étiquette **`service`** (`keycloak`, `freeipa`) ; sonde `https_2xx` de `sso` sur le témoin de `mon01` |
| Documentation | `docs/securite/identite/` : `master.md` (E27), `adr/ADR-0240-architecture-identite.md` (E31), `adr/ADR-0241-haute-disponibilite-keycloak.md` (E24), `runbooks/RB-240-bris-de-glace.md` (E28), `RB-243-restauration-identite.md` (E25), `RB-244-rotation-cles-et-secrets.md` (E29), `RB-245-montee-de-version-identite.md` (E33) ; `revue-acces/` (rapports mensuels, E30) ; journaux dans `docs/socle/journal/` |
| Comptes de bris de glace | `kc-secours` (Keycloak `master`), `admin` (FreeIPA), `root` (GitLab), `admin` (Argo CD, désactivé, réactivable), `admin` (Grafana), `admin` (Harbor, base locale), `root@pam` (Proxmox VE, PBS), superutilisateur local de NetBox, `admin.conf` (cluster), compte local `admin` des VMs : tous au Vault `critique` et au coffre |
| Tickets | PLAT-25xx, SEC-25xx, CHG-25xx (xx = exercice) |

> **Mémoire** : `idp02` (E24) puis `idp-resto` (E25) ajoutent 2 Go chacun, **jamais en même temps**. Vérifie la marge de `pve01` (`free -g`) avant chacun ; si elle manque, arrête `ceph-par1` pendant E24 et E25 (ils ne touchent pas au stockage), jamais une VM du socle.

**Ordre conseillé** : E24 → E25 → E26 → E27 → E28 → E29 → E33 → E30 → E31 → E32 → E34. La haute disponibilité (E24) vient d'abord parce qu'elle décide de l'architecture que tout le reste sauvegarde, supervise et durcit ; la sauvegarde (E25) précède **toute** modification risquée ; la supervision (E26) précède le durcissement pour voir tout de suite ce qu'il casse ; le bris de glace (E28) s'appuie sur les alertes d'E26 ; la montée de version (E33) vient après les rotations pour qu'on la fasse sur un royaume durci et sauvegardé ; la revue des accès (E30) et l'ADR (E31) décrivent l'état final ; le chronométré (E34) se fait en dernier, sans aide. **Durée totale indicative** : 22 à 27 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 24 XX`). Variables facultatives de `lab/lab.env` : `WB_M24_IPA`, `WB_M24_IDP` (introduction du module), `WB_M21_TEMOIN_URL` (témoin de `mon01`, M21), `WB_LOKI_URL`, `WB_PROM_URL`.

---

### M24-E24 — Keycloak en haute disponibilité : essai à deux nœuds  `LAB` `★★★`

> **Ticket PLAT-2524** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> Depuis que tout passe par Keycloak, Nadia me demande à chaque comité : « et si `idp01` tombe ? ». Je ne veux pas une réponse de principe. Monte un second nœud pour de vrai, fais-le tourner avec le premier, coupe-en un pendant qu'on se connecte, et mesure ce que voient les utilisateurs. Puis écris-moi la décision : deux nœuds en permanence, ou un seul et une procédure. On n'a pas la mémoire pour tout garder, alors je veux les chiffres.

**Objectifs pédagogiques**
- Comprendre comment Keycloak forme une grappe : cache Infinispan distribué, découverte `jdbc-ping` par la base, transport chiffré, sessions persistantes en base.
- Faire partager une base PostgreSQL à deux nœuds sans l'ouvrir au reste du réseau.
- Répartir la charge sur deux nœuds avec HAProxy, provoquer une panne et **mesurer** son effet.
- Conclure par une décision chiffrée (ADR) et revenir proprement à l'état mononœud.

**Prérequis** : M24-E04 (rôle `keycloak`, publication), palier 2 terminé ; M05-E30 (états d'environnement OpenTofu) ; M07 (HAProxy, une passerelle de répartition à la fois).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VM | `idp02`, VMID 2241, 10.10.20.42, Debian 13, 2 vCPU, 2 Go, `local-nvme` ; état OpenTofu `envs/m24` de `plateforme/infra` (catalogue `hotes.tf` : `idp02`, puis `idp-resto` en E25 ; modules `vm-noeud` et `enregistrement-dns`, sur le modèle de `envs/m20`) ; groupe Ansible `role_idp` (le garde-fou du playbook `identite.yml` l'accepte déjà) |
| Base | PostgreSQL 17 de `idp01` : écoute ajoutée sur 10.10.20.30, `pg_hba.conf` : `hostssl` pour la seule adresse 10.10.20.42, méthode `scram-sha-256` ; `idp02` n'a **pas** de PostgreSQL |
| Grappe | `cache=ispn`, `cache-stack=jdbc-ping`, adresse de liaison = adresse de l'hôte ; flux 7800 et 57800 entre `idp01` et `idp02` (même VLAN : `pare_feu_local` seulement) ; mTLS du transport par défaut |
| Certificats | `idp02` obtient son certificat ACME (`idp02.par1.medisphere.internal`) comme `idp01` ; `hostname` reste `https://sso.par1.medisphere.internal` sur les deux nœuds |
| Publication | `be_sso` de `lb01`/`lb02` : second serveur `idp02` (même vérification TLS, même contrôle de santé), le temps de l'essai |
| Mesures | une boucle sur `adm01` qui, chaque seconde, demande un jeton (`client_credentials` de `wb-checks`) et la découverte, et note l'heure et le code de retour ; une personne connectée dans la console de compte pendant la bascule |

**Travail demandé**

*A. Lire avant de construire*

1. Lis les guides *Configuring distributed caches* et *Configuring the database* de Keycloak, et la section sur les sessions persistantes (*persistent user sessions*). Note dans `~/m24/e24/notes.md` : ce qui est en cache local, ce qui est distribué, ce qui est en base ; ce que fait `jdbc-ping` ; les ports du transport ; ce que deviennent les sessions SSO quand un nœud s'arrête, puis quand **tous** s'arrêtent. Quelle est la seule ressource que les deux nœuds partagent, et qu'en déduis-tu sur la disponibilité de l'ensemble ?

*B. Le second nœud*

2. Avant toute chose, une sauvegarde de la base de Keycloak (si E25 n'est pas encore fait : `sudo -u postgres pg_dump -Fc keycloak` sur `idp01` vers un fichier en 600 de `/var/backups/`).
3. Étends le rôle `keycloak` pour qu'il sache : se connecter à une base **distante** (variable d'hôte de la base), ne pas installer PostgreSQL sur un nœud qui n'en a pas, ouvrir la base de `idp01` à une liste d'adresses en TLS, et produire la configuration de grappe quand `keycloak_grappe` est vrai (adresse de liaison, pile). Relis la liste des options de construction : lesquelles de tes nouvelles options en sont ?
4. Crée `idp02` (`envs/m24/`, groupe `idp02`), MR, apply. Applique les rôles communs, puis `identite.yml` sur `idp01` **d'abord** (grappe vraie, base ouverte à 10.10.20.42), puis sur `idp02`.
   > ⚠️ **Attention** : passer `idp01` de `cache=local` à `cache=ispn` le reconstruit et le redémarre : quelques dizaines de secondes sans SSO. Fais-le hors des heures de connexion, avec les accès de secours du rappel en tête de palier. Retour arrière : `keycloak_grappe: false` dans `host_vars/idp01/`, rejouer le playbook.
5. Prouve que la grappe est formée : dans le journal de Keycloak des deux nœuds, la vue de la grappe (`ISPN000094` : liste des membres) ; dans la base, la table de découverte. Combien de lignes contient-elle, et que deviennent-elles quand un nœud s'arrête ?

*C. La répartition et la bascule*

6. Ajoute `idp02` à `be_sso` (`lb02`, contrôle, puis `lb01`). Vérifie avec `show servers state be_sso` que les deux sont `UP`.
7. Lance la boucle de mesure (contexte technique) dans un terminal, connecte-toi à la console de compte en `lucas.martin` dans un navigateur. Puis, sur `idp01` : `sudo systemctl stop keycloak`. Observe : combien de secondes d'erreurs dans la boucle ? Lucas doit-il se reconnecter ? Redémarre `idp01`, puis arrête `idp02` de la même façon.
8. Dernière mesure, sans grappe : arrête **les deux** nœuds puis redémarre `idp01` seul. Combien de temps entre l'arrêt et le premier jeton délivré ? Lucas est-il toujours connecté après le redémarrage ? Pourquoi ?

*D. La décision et le retour à un nœud*

9. Écris `docs/securite/identite/adr/ADR-0241-haute-disponibilite-keycloak.md` : contexte, options (un nœud + restauration, deux nœuds sur `pve01`, deux nœuds sur deux hyperviseurs, et ce qui reste un point unique dans chaque cas : base, hyperviseur, annuaire), tes **mesures**, le coût en mémoire et en exploitation, la décision, et ce qui la ferait réviser.
10. Reviens à l'état mononœud dans l'ordre inverse : `idp02` hors de `be_sso` (deux répartiteurs), `keycloak_grappe: false` et base refermée sur `idp01` (playbook), puis `tofu destroy` de `envs/m24`. Vérifie qu'il ne reste rien : VM, DNS, NetBox, ligne de `pg_hba.conf`, écoute de PostgreSQL, ligne de la table de découverte.

**Critères de réussite**
- [ ] L'ADR-0241 est sur `main` de `plateforme/medisphere`, avec au moins trois mesures chiffrées (secondes d'indisponibilité vues par la boucle dans chaque scénario) et une décision argumentée.
- [ ] Le rôle `keycloak` sait produire une grappe (base distante, `cache=ispn`, `jdbc-ping`) et revient à `cache=local` quand `keycloak_grappe` est faux ; c'est sur `main` de `plateforme/ansible`.
- [ ] `idp02` n'existe plus (ni VM 2241, ni DNS, ni NetBox) ; `be_sso` ne contient que `idp01` ; PostgreSQL de `idp01` n'écoute que sur la boucle locale ; `idp01` est en `cache=local`.

**Vérification** : `lab/bin/check 24 24`

<details><summary>Indice 1</summary>

Sur PostgreSQL de Debian, `listen_addresses` se règle dans `/etc/postgresql/17/main/postgresql.conf` (ou un fichier de `conf.d/`), et une ligne de `pg_hba.conf` du type `hostssl base rôle adresse/32 scram-sha-256` n'ouvre qu'à une adresse. Debian active déjà TLS dans PostgreSQL (certificat auto-signé *snakeoil*) : côté Keycloak, `db-url-properties` permet de demander TLS au pilote JDBC ; demande-toi ce que vaut un TLS dont on ne vérifie pas le certificat.
</details>

<details><summary>Indice 2</summary>

Keycloak choisit seul une adresse de liaison « locale au site » ; sur une VM à une interface, c'est la bonne, mais écris-la (`cache-embedded-network-bind-address`) pour ne pas dépendre d'un choix automatique. La vue de la grappe apparaît dans le journal sous la forme `ISPN000094: Received new cluster view for channel ISPN: [idp01-…|1] (2) [idp01-…, idp02-…]`.
</details>

<details><summary>Indice 3</summary>

Depuis Keycloak 26, les sessions des utilisateurs sont **persistées en base** par défaut : un redémarrage complet ne les perd plus. Ce que la grappe apporte vraiment, c'est la continuité de service pendant l'arrêt d'**un** nœud ; compare avec la durée d'un redémarrage à froid de `idp01` seul.
</details>

**Pour aller plus loin** (facultatif) : les options `cache-embedded-cluster-name` et `cache-embedded-node-name` arrivent en 26.8 (E33) ; lis leur rôle. Lis aussi le guide *Multi-site* (v2, sans Infinispan externe) et dis ce qu'il faudrait pour un second nœud à PAR2. [Keycloak : *Configuring distributed caches*](https://www.keycloak.org/server/caching) · [*Configuring the database*](https://www.keycloak.org/server/db) · [*Configuring Keycloak for production*](https://www.keycloak.org/server/configuration-production)

---

### M24-E25 — Sauvegarder et restaurer l'identité  `LAB` `★★★`

> **Ticket PLAT-2525** — *De : Nadia Roussel* — *Copie : Sophie Laurent*
> Si on perd la base de Keycloak, on perd quoi exactement ? Et l'annuaire ? Je veux une sauvegarde **quotidienne** des deux, chiffrée, hors des VMs, et surtout une restauration qu'on a **faite** et chronométrée, pas une restauration « qui devrait marcher ». Sophie ajoute une condition : une sauvegarde de l'identité contient tous nos secrets, elle ne doit être lisible que par ceux qui ont le Vault `critique`.

**Objectifs pédagogiques**
- Identifier ce que contiennent la base de Keycloak et l'annuaire, et les secrets qui y dorment (clés de signature, secrets des clients, seconds facteurs, empreintes des comptes de `master`).
- Sauvegarder de façon cohérente et chiffrée côté client (`pg_dump`, export partiel du royaume, `ipa-backup`, `age`), hors de la VM, en plus de la sauvegarde de VM.
- Restaurer Keycloak sur une VM jetable isolée, mesurer le RTO, prouver le résultat, et tout effacer.
- Écrire le runbook de restauration.

**Prérequis** : M24-E24 (`idp02` détruite) ; M14-E24 (modèle `etcd_instantane` : age, rclone, identité S3 sans suppression) ; M06-E28 (sauvegardes du socle, restauration isolée) ; M00 (PBS, tâches de sauvegarde).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Rôle | `sauvegarde_identite` (nouveau, `plateforme/ansible`), appliqué par le playbook `identite.yml` (`idp01`) et `annuaire-serveur.yml` (`ipa01`) ; script `/usr/local/sbin/identite-sauvegarde`, unité `identite-sauvegarde.service`, minuterie `identite-sauvegarde.timer` (`idp01` 01:20, `ipa01` 01:30) |
| Contenu | `idp01` : `pg_dump -Fc` de la base `keycloak` ; `ipa01` : `ipa-backup` des **données** de l'annuaire, en ligne (une sauvegarde complète, configuration et CA comprises, arrête les services : lis `ipa-backup(1)` et décide quand la faire) |
| Chiffrement | `age` vers la clé **publique** `identite_age_destinataire` ; la clé privée est générée sur `adm01`, rangée au Vault `critique` (`secrets/identite-sauvegardes.yml` de `plateforme/ansible`) et imprimée, jamais copiée sur une VM du socle |
| Destination | `s3-01`, compartiment `identite-sauvegardes` (versionné, politique sans `DeleteObject`, cycle de vie : 35 jours) ; préfixes `idp01/` et `ipa01/` ; identité S3 `identite-sauvegardes` (Vault `critique`) |
| VMs | stockage Proxmox `pbs-par2-identite` (datastore `ds-lab` de `pbs01`, espace de noms `par1/identite`) ; tâche `identite-nuit` (VMs 1030 et 1031, 01:45, mode instantané) ; ces deux VMs sortent de la tâche `lab-nuit` |
| Restauration d'essai | `idp-resto` (2242, `vsandbox`, 10.10.99.42, 2 Go, état `envs/m24`) ; filtrage d'entrée local **avant** toute copie de secret ; certificat auto-signé local pour l'essai |
| Runbook | `docs/securite/identite/runbooks/RB-243-restauration-identite.md` |

**Travail demandé**

*A. Ce qu'on sauvegarde*

1. Dresse dans `~/m24/e25/notes.md` l'inventaire de ce qui fait l'état de l'identité : pour Keycloak (tables qui portent les clés du royaume, les secrets des clients, les identifiants OTP et WebAuthn, les sessions, les comptes de `master`) et pour FreeIPA (annuaire, Kerberos, CA Dogtag et sa clé, configuration). Pour chaque élément : est-il reconstructible depuis Git (OpenTofu, Ansible), depuis l'annuaire, ou **seulement** depuis une sauvegarde ? Que se passe-t-il pour les utilisateurs si on reconstruit Keycloak depuis le code au lieu de restaurer la base ?
2. Lis la page `ipa-backup(1)` et la documentation de l'export de Keycloak (*Importing and exporting realms*, et l'export partiel de l'API d'administration). Pourquoi l'export complet (`kc.sh export`) ne remplace-t-il pas `pg_dump` chez nous, et pourquoi ne se lance-t-il pas sur `idp01` en marche ? Quel droit l'export partiel exige-t-il, et le donnerais-tu à une minuterie ?

*B. La chaîne de sauvegarde*

3. Prépare le stockage : identité S3 `identite-sauvegardes` et compartiment versionné par le rôle `seaweedfs` (MR), politique sans suppression et cycle de vie avec l'identité d'administration (comme M14-E24). Génère la paire de clés age sur `adm01`, imprime la clé privée, range-la au Vault `critique`, ne garde sur disque que la clé publique.
4. Écris le rôle `sauvegarde_identite`. Exigences : un seul script pour les deux hôtes (le contenu dépend d'une variable), refus de s'exécuter si le fichier de secrets S3 n'est pas `root:root 600`, aucun secret en argument, copie claire **jamais** laissée sur disque, contrôle de chaque archive avant envoi (`pg_restore --list`, liste du contenu de l'archive d'`ipa-backup`), contrôle de la taille de l'objet relu, trace du dernier succès, alerte en cas d'échec (`OnFailure=ms-alerte@%n.service`, comme les autres minuteries du socle). Applique sur `idp01` puis `ipa01`, lance une première fois à la main.
5. Côté Proxmox : crée le stockage `pbs-par2-identite` (même datastore, espace de noms `par1/identite`, à créer sur `pbs01` d'abord) et la tâche `identite-nuit` ; retire 1030 et 1031 de `lab-nuit`. Lance la tâche une fois.

*C. La restauration d'essai*

6. Crée `idp-resto` (`envs/m24`). **Avant** d'y copier quoi que ce soit, ferme-la : filtrage d'entrée local qui n'accepte que `adm01` en SSH, et aucune route vers `ipa01` (la fédération n'a rien à y joindre). Pourquoi est-ce indispensable, sachant ce que contient la sauvegarde ?
7. Sur `adm01`, récupère la dernière archive de `idp01/`, déchiffre-la **en mémoire** vers `idp-resto` (la clé privée ne quitte pas `adm01`), puis installe Keycloak **de la même version** sur `idp-resto` avec le rôle (inventaire d'essai, certificat auto-signé local, `keycloak_verifier: false`), restaure la base **avant** le premier démarrage, démarre. Chronomètre chaque étape.
8. Prouve la restauration : `/health/ready` ; la découverte du royaume `medisphere` servie par `idp-resto` (même émetteur que la production) ; le `kid` de la clé de signature **identique** à celui de la production ; le nombre de personnes fédérées, de clients et de comptes de `master` identique. Qu'en déduis-tu pour les jetons déjà délivrés par la production ?
9. Pour l'annuaire, fais au moins : déchiffrement de l'archive d'`ipa-backup` sur `adm01` en mémoire, liste de son contenu (fichier d'en-tête, archive des données ; `ipa-full` n'apparaît que dans une sauvegarde complète), et la procédure complète de restauration écrite (réinstallation de `ipa01` au même nom, `ipa-restore`, contrôles). Explique pourquoi on ne la joue pas sur une VM jetable du lab.
10. Détruis `idp-resto` (`tofu destroy`), efface sur `adm01` tout fichier déchiffré, écris **RB-243** (sauvegardes, emplacements, clés et qui peut les ouvrir, restauration pas à pas de Keycloak et de FreeIPA, RTO mesuré, RPO, contrôles, nettoyage).

**Critères de réussite**
- [ ] Sur `idp01` et `ipa01`, la minuterie `identite-sauvegarde.timer` est active et le dernier succès date de moins de 26 h ; le fichier de secrets S3 est `root:root 600` ; aucune archive claire ne traîne dans `/var/backups`.
- [ ] Le stockage `pbs-par2-identite` (espace de noms `par1/identite`) contient une sauvegarde de 1030 et de 1031 de moins de 48 h ; la tâche `identite-nuit` existe ; `lab-nuit` ne sauvegarde plus ces deux VMs.
- [ ] RB-243 est sur `main` avec un RTO mesuré pour Keycloak et la preuve de la restauration (`kid`, comptes) ; `idp-resto` n'existe plus.

**Vérification** : `lab/bin/check 24 25`

<details><summary>Indice 1</summary>

Les clés privées de signature du royaume sont dans la table `component_config` (fournisseurs de clés `rsa-generated`, `hmac-generated`…), les secrets des clients dans `client`, les OTP dans `credential` : une base restaurée signe avec les **mêmes** clés et présente les mêmes secrets. Un royaume reconstruit depuis OpenTofu aurait de nouvelles clés (tous les jetons en cours refusés), de nouveaux secrets (tous les services à reconfigurer) et aucun OTP (chaque administrateur à réinscrire).
</details>

<details><summary>Indice 2</summary>

`pg_dump -Fc … | age -r <clé> | rclone rcat distant:compartiment/clé` n'écrit rien de clair sur le disque ; mais tu ne contrôles alors pas l'archive avant de l'envoyer. Un fichier temporaire dans un dossier `root 700`, effacé par un `trap`, est un compromis acceptable ; un `pg_restore --list` sur ce fichier prouve qu'il est lisible. Côté restauration : `age -d -i <(…clé…) | ssh idp-resto 'cat > …'` garde la clé sur `adm01`.
</details>

<details><summary>Indice 3</summary>

Dans Proxmox, l'espace de noms PBS est une propriété du **stockage** : un second stockage sur le même datastore, avec `--namespace par1/identite`, et une tâche de sauvegarde qui l'utilise. L'espace de noms doit exister sur `pbs01` (`proxmox-backup-client namespace create`, M01-E28) et le jeton de `pve01` doit y avoir `DatastoreBackup`.
</details>

**Pour aller plus loin** (facultatif) : restaure aussi `ipa01` depuis PBS sur un VMID libre, **carte réseau débranchée**, et vérifie `ipactl status` en console ; ou mesure l'effet d'une restauration de Keycloak vieille de 24 h (personnes arrivées depuis, OTP enregistrés depuis, rotations faites depuis). [Keycloak : *Importing and exporting realms*](https://www.keycloak.org/server/importExport) · [FreeIPA : *Backup and restore*](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/planning_identity_management/backing-up-and-restoring-idm) · [age](https://age-encryption.org)

---

### M24-E26 — Superviser l'identité : santé, métriques, événements  `LAB` `★★★`

> **Ticket PLAT-2526** — *De : Nadia Roussel*
> Lundi, des collègues n'arrivaient plus à se connecter à Grafana depuis vingt minutes quand on l'a appris… par la messagerie. Je veux que l'astreinte le sache **avant** les utilisateurs : Keycloak qui ne répond plus, une vague d'échecs de connexion, l'annuaire qui ne répond plus à Keycloak. Et Sophie veut les connexions et les actions d'administration dans le journal d'audit, pas dans le journal général que tout le monde lit.

**Objectifs pédagogiques**
- Collecter les métriques de Keycloak (interface de gestion) et activer les métriques d'événements utilisateurs.
- Écrire des alertes qui parlent du symptôme (indisponibilité, échecs de connexion, fédération en échec) et les tester.
- Router les événements de connexion et d'administration de Keycloak, et les journaux de FreeIPA, vers le locataire `audit` de Loki, et **seulement** là.
- Ajouter une sonde « vue de l'utilisateur » au témoin.

**Prérequis** : M24-E25 ; M21-E10 (ScrapeConfig hors cluster), M21-E15 (règles d'alerte), M21-E11 (témoin et sondes) ; M22-E05 et E09 (rôle `alloy`), M22-E08 (ruler, locataire `audit`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Métriques | `https://idp01.par1.medisphere.internal:9000/metrics` (sans authentification : filtrée par `pare_feu_local`) ; option **`event-metrics-user-enabled=true`** (option de construction ; la fonction `user-event-metrics` est active par défaut) : compteur `keycloak_user_events_total` (étiquettes `realm`, `event`, `error`) |
| Événements dans le journal | écouteur `jboss-logging` (actif par défaut sur chaque royaume) : niveau des succès relevé à `info`, des erreurs à `warn` (`spi-events-listener--jboss-logging--success-level`, `…--error-level`) ; journaux JSON (`log-console-output=json`, E04) ; événements stockés en base (`events_enabled`, 30 jours) et événements d'administration avec détails, par OpenTofu (`keycloak_realm_events`) |
| Collecte | ScrapeConfig `keycloak` (job `keycloak`) ; flux `K8S_TRAV` → `idp01` 9000 (bordure et `pare_feu_local`) |
| Règles | `regles/identite.yaml` (PrometheusRule) : `KeycloakIndisponible`, `KeycloakEchecsConnexion` ; `loki/regles/audit/identite.yaml` (ruler, locataire `audit`) : `FederationLdapEnEchec` |
| Journaux | rôle `alloy` étendu : sur `idp01`, l'unité `keycloak.service` va au locataire **`audit`** (étiquette `service="keycloak"`) et **plus** au locataire `plateforme` ; sur `ipa01` (Rocky 10), `/var/log/dirsrv/slapd-PAR1-MEDISPHERE-INTERNAL/access`, `/var/log/krb5kdc.log`, `/var/log/httpd/error_log` au locataire `audit` (étiquette `service="freeipa"`) |
| Témoin | sonde `https_2xx` de `https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration` (groupe `https` de `supervision_temoin_sondes`, M21-E11) |

**Travail demandé**

1. Lis la page *Gaining insights with metrics* et *Monitoring user activities with event metrics* de Keycloak. Sur `idp01`, liste ce que publie `/metrics` (familles `http_server_requests_seconds`, `agroal_*`, `jvm_*`, `vendor_cache_*`, `keycloak_*`) et note celles qui disent « Keycloak sert » et celles qui disent « Keycloak va mal ».
2. Ajoute à `host_vars/idp01/keycloak.yml` (dictionnaire `keycloak_options`) l'activation des métriques d'événements et le niveau des événements dans le journal. Applique (reconstruction). Provoque deux échecs de connexion dans une fenêtre privée (`lucas.martin`, mauvais mot de passe) et retrouve-les dans `/metrics` et dans `journalctl -u keycloak` sur `idp01`. Quel est le nom du *logger* des événements ? Que contient la ligne, et qu'est-ce qu'elle **ne** doit **pas** contenir ?
3. Dans `plateforme/identite`, décris par OpenTofu le stockage des événements et des événements d'administration du royaume `medisphere` (`tofu/evenements.tf`). Fais une modification anodine par une MR (une description de portée) et retrouve l'événement d'administration correspondant dans la console.
4. Écris `scrape/keycloak.yaml` (TLS vérifié avec la racine, `instance="idp01"`) et ouvre le flux. Puis `regles/identite.yaml` : 
   - `KeycloakIndisponible` : la collecte échoue ou la santé n'est plus là depuis 2 minutes (critique) ;
   - `KeycloakEchecsConnexion` : plus de 20 échecs de connexion en 5 minutes sur le royaume `medisphere` (avertissement) — quelles erreurs comptes-tu, et lesquelles écartes-tu ?
   Écris le test de chaque règle (`promtool test rules`) dans `tests/`, comme au M21.
5. Étends le rôle `alloy` : une liste d'**unités** et une liste de **fichiers** à envoyer au locataire `audit` avec une étiquette `service`, et l'exclusion de ces unités du flux général. Prends en charge Rocky Linux 10 pour `ipa01` (paquets, groupes, lecture des journaux protégés de 389-ds et du KDC : choisis entre l'appartenance à des groupes et une capacité de lecture, et justifie). Applique sur `idp01` puis `ipa01`.
6. Écris `loki/regles/audit/identite.yaml` avec `FederationLdapEnEchec` : des erreurs de la fédération LDAP dans le journal de Keycloak sur 10 minutes. Pour trouver le bon filtre, regarde ce que Keycloak écrit quand la fédération échoue : dans la console, *User federation* → `ipa01` → *Test connection* avec une **URL de connexion fausse** saisie dans le formulaire **sans enregistrer**, et lis le journal.
7. Ajoute la sonde de `sso` au témoin. Puis éprouve la chaîne d'alerte : `sudo systemctl stop keycloak` sur `idp01` (avec les précautions du rappel), attends l'alerte dans Mailpit (cluster **et** témoin), redémarre. Combien de temps entre l'arrêt et le courriel ?

**Critères de réussite**
- [ ] `up{job="keycloak"}` vaut 1 et `keycloak_user_events_total` existe dans Prometheus ; les règles `KeycloakIndisponible` et `KeycloakEchecsConnexion` sont chargées, avec leurs tests sur `main`.
- [ ] Le ruler de Loki (locataire `audit`) porte `FederationLdapEnEchec`.
- [ ] Le locataire `audit` reçoit les journaux de Keycloak (`service="keycloak"`) et de FreeIPA (`service="freeipa"`) ; le locataire `plateforme` ne reçoit plus le journal de `keycloak.service`.
- [ ] Le témoin de `mon01` sonde `sso` et la sonde réussit ; les événements et les événements d'administration du royaume sont activés par le code.

**Vérification** : `lab/bin/check 24 26`

<details><summary>Indice 1</summary>

Le compteur des événements porte une étiquette `error` **vide** pour les succès. Pour les échecs, `error!=""` ; écarte les erreurs qui ne disent rien d'une attaque ou d'une panne (par exemple `resolve_required_actions`, une action requise en attente) et regarde surtout `invalid_user_credentials` et `user_not_found`.
</details>

<details><summary>Indice 2</summary>

`loki.source.journal` accepte `matches` (syntaxe des correspondances de `journalctl`, par exemple `_SYSTEMD_UNIT=keycloak.service`) : une seconde source dédiée à l'audit, et un `stage.drop` sur l'unité dans le flux général. Un `loki.write` par locataire. Pour les fichiers, `local.file_match` puis `loki.source.file`.
</details>

<details><summary>Indice 3</summary>

Sur Rocky 10, les journaux d'accès de 389-ds appartiennent à `dirsrv` et celui du KDC à `root` en 600 : un groupe ne suffit pas pour le second. `AmbientCapabilities=CAP_DAC_READ_SEARCH` donne une lecture de tous les fichiers sans autre pouvoir ; c'est un choix à écrire, limité à cet hôte.
</details>

**Pour aller plus loin** (facultatif) : un tableau Grafana « Identité » (connexions par minute, échecs par type, latence des points de terminaison de jeton, pool de connexions à la base) ; la fonction `ldap-metrics` de la 26.8 (désactivée par défaut) et ce qu'elle apporterait à `FederationLdapEnEchec`. [Keycloak : *Gaining insights with metrics*](https://www.keycloak.org/observability/configuration-metrics) · [*Event metrics*](https://www.keycloak.org/observability/event-metrics) · [Alloy : `loki.source.journal`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/)

---

### M24-E27 — Durcir Keycloak : sessions, jetons, force brute, administration  `LAB` `★★★`

> **Ticket SEC-2527** — *De : Sophie Laurent* — *Copie : Karim Benali*
> J'ai relu le royaume avec la grille ANSSI. Les durées sont celles de l'installation, la force brute n'est pas détectée, un jeton de rafraîchissement volé sert indéfiniment, les en-têtes de sécurité sont ceux par défaut, et rien n'empêche un administrateur de se faire passer pour un utilisateur. Et le royaume `master`, lui, n'est même pas dans le code. Je veux un royaume durci, chaque valeur justifiée, et la preuve que rien n'a cassé.

**Objectifs pédagogiques**
- Choisir et justifier les durées de jetons et de sessions, et la rotation des jetons de rafraîchissement.
- Régler la détection de force brute en tenant compte du verrouillage de l'annuaire.
- Réduire la surface : en-têtes de sécurité, fonctions désactivées, flux et clients inutiles, console d'administration.
- Durcir `master` hors du code et l'écrire.

**Prérequis** : M24-E26 (alertes et journal d'audit : ils te montreront ce que le durcissement casse) ; M24-E21 (OTP) ; M24-E03 (politique de mot de passe de l'annuaire).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Royaume `medisphere` | par OpenTofu (`tofu/royaume.tf`, `tofu/evenements.tf`) : jeton d'accès **5 min**, session SSO inactive **30 min** / maximale **10 h**, sessions client alignées, rotation des jetons de rafraîchissement (`revoke_refresh_token`, réutilisation 0), détection de force brute **temporaire**, en-têtes de sécurité, politique de mot de passe des comptes **locaux** (le royaume n'en a pas, mais il ne doit pas en accepter de faibles) |
| Annuaire | verrouillage après 6 échecs (E03), compteur remis à zéro après 60 s par défaut (`krbPwdFailureCountInterval`, à relire dans ta politique) |
| `idp01` | `keycloak_options` : fonction `impersonation` désactivée (`features-disabled`) |
| Royaume `master` | hors du code (OpenTofu n'y a aucun droit) : modifications à la main par `<MOI>-admin`, écrites dans `docs/securite/identite/master.md` (valeur, raison, date) |
| Clients | aucun client avec flux implicite, *Direct Access Grants* ou redirection joker (contrôle sur tout le royaume) |

**Travail demandé**

1. Relis les guides *Server Administration* (sections *Sessions and tokens*, *Brute force detection*, *Headers*) et la note de la 26.8 sur le plafonnement de l'expiration des jetons de rafraîchissement (`annexes/versions-bloc-F.md`). Relève les valeurs actuelles du royaume (`tofu -chdir=tofu state show keycloak_realm.medisphere`, ou l'API) et fais un tableau « valeur actuelle → valeur cible → raison ».
2. **Force brute.** Un attaquant qui essaie 6 mots de passe sur `julien.petit` par le formulaire de Keycloak verrouille son compte **dans l'annuaire** : il bloque Julien partout (SSH, sudo, tous les services). Choisis les réglages de Keycloak (nombre d'échecs, attente, attente maximale, remise à zéro, verrouillage temporaire ou permanent) pour que Keycloak bloque **avant** l'annuaire, et explique pourquoi un verrouillage **permanent** est une mauvaise idée avec une fédération `READ_ONLY`.
3. Écris les changements dans `tofu/royaume.tf` (bloc `security_defenses`, durées, rotation des jetons de rafraîchissement, politique de mot de passe). MR, plan relu ligne à ligne, apply.
   > ⚠️ **Attention** : une session SSO maximale plus courte déconnecte immédiatement les sessions plus anciennes ; un jeton d'accès plus court peut faire échouer un client qui le rafraîchit mal (`refreshTokenThreshold` d'Argo CD). Garde ta session de console ouverte, essaie `kc-secours` avant l'apply. Retour arrière : `git revert` de la MR et apply.
4. Éprouve : 5 échecs puis le bon mot de passe pour `lucas.martin` (refus, message, durée) ; vérifie dans l'annuaire (`ipa user-status lucas.martin`) que son compteur n'a pas atteint 6. Rafraîchis deux fois un même jeton de rafraîchissement (flux d'E07 avec un client d'essai temporaire, ou la console de compte) : que répond Keycloak la seconde fois ? Que devient la session ?
5. Sur `idp01`, désactive la fonction `impersonation` (`keycloak_options`), applique. Vérifie qu'aucun utilisateur de `master` ne voit plus *Impersonate*.
6. Passe en revue tous les clients du royaume (API, client `wb-checks`) : flux implicite, *Direct Access Grants*, redirections avec joker, `full_scope_allowed`, clients publics sans PKCE. Corrige ce qui doit l'être dans `tofu/clients-*.tf`.
7. Dans `master`, à la main (console, en `<MOI>-admin`) : détection de force brute temporaire, politique de mot de passe (longueur 16, historique, pas l'identifiant), durée de session d'administration ; écris chaque valeur dans `docs/securite/identite/master.md`.
   > ⚠️ **Attention** : une politique de mot de passe plus stricte ne touche pas les mots de passe existants, mais une **force brute** mal réglée peut verrouiller `kc-secours`. Essaie `kc-secours` juste après, dans une fenêtre privée.
8. Contrôle la non-régression : connexion à Grafana, Argo CD (navigateur et CLI), `kubectl` par kubelogin, `step ssh login` ; aucune alerte d'E26 ne s'est déclenchée.

**Critères de réussite**
- [ ] Le royaume `medisphere` a : rotation des jetons de rafraîchissement (réutilisation 0), détection de force brute temporaire avec au plus 5 échecs, une politique de mot de passe d'au moins 12 caractères, événements et événements d'administration actifs, jeton d'accès 300 s, session inactive 1800 s, maximale 36000 s ; durées et en-têtes de sécurité **écrits** dans `tofu/royaume.tf` (même quand ils valent la valeur par défaut), sur `main`.
- [ ] Aucun client du royaume n'a le flux implicite, les *Direct Access Grants* ou une redirection avec `*`.
- [ ] `master` a la détection de force brute active et une politique de mot de passe ; `master.md` est sur `main`.
- [ ] La fonction `impersonation` est désactivée sur `idp01`.

**Vérification** : `lab/bin/check 24 27`

<details><summary>Indice 1</summary>

Dans le fournisseur `keycloak/keycloak`, `security_defenses` contient deux blocs : `headers` et `brute_force_detection` (`max_login_failures`, `wait_increment_seconds`, `max_failure_wait_seconds`, `failure_reset_time_seconds`, `permanent_lockout`…). Les durées du royaume s'écrivent en chaînes de durée (`"5m"`, `"30m"`, `"10h"`).
</details>

<details><summary>Indice 2</summary>

Keycloak qui verrouille temporairement un compte **ne tente plus** la liaison LDAP : le compteur de l'annuaire ne monte plus. Il faut donc que Keycloak verrouille strictement avant 6 échecs, et que sa remise à zéro ne soit pas plus courte que celle de l'annuaire.
</details>

**Pour aller plus loin** (facultatif) : servir la console d'administration sous un nom distinct (`hostname-admin`, `sso-admin.par1…`, joignable en MGMT seulement) et retirer le filtrage par chemin de HAProxy ; mesurer avec un analyseur d'en-têtes ce que la page de connexion envoie. [Keycloak : *Server Administration Guide*](https://www.keycloak.org/docs/latest/server_admin/) · [ANSSI : *Recommandations relatives à l'authentification multifacteur et aux mots de passe*](https://cyber.gouv.fr/publications/recommandations-relatives-lauthentification-multifacteur-et-aux-mots-de-passe)

---

### M24-E28 — Bris de glace : comptes de secours et procédure éprouvée  `LAB` `★★`

> **Ticket SEC-2528** — *De : Sophie Laurent* — *Copie : Nadia Roussel, Claire Morel*
> Le jour où Keycloak tombera, Nadia aura besoin d'entrer quelque part. Je veux, pour **chaque** service, le compte de secours, où il est rangé, qui peut l'ouvrir, comment s'en servir, et la preuve qu'on l'a essayé ce trimestre. Et chaque usage d'un compte de secours doit me réveiller : un compte de secours qu'on utilise sans que je le sache, c'est un compte partagé.

**Objectifs pédagogiques**
- Inventorier les accès de secours de tous les services et les ranger selon une règle unique.
- Éprouver chacun en conditions réelles, sans laisser de trace exploitable.
- Rendre chaque usage visible : journaux, alertes, procès-verbal.
- Écrire le runbook de bris de glace.

**Prérequis** : M24-E26 (locataire `audit`, ruler), M24-E27 ; palier 2 (comptes locaux restants de chaque service).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Service | Compte de secours | Rangement | Remarque |
|---|---|---|---|
| Keycloak | `kc-secours` (`master`) | Vault `critique`, coffre | pas d'OTP (E04) |
| FreeIPA | `admin` | Vault `critique` | aussi l'automatisation de l'annuaire (E03) |
| GitLab | `root` | gestionnaire de mots de passe, coffre | connexion par mot de passe réservée à `root` (palier 2) |
| Argo CD | `admin` désactivé | — | réactivation par les valeurs Helmfile de la release `argocd` (palier 2) |
| Grafana | `admin` | Vault `critique` (Secret `grafana-admin`) | formulaire désactivé ; API par authentification basique |
| Harbor | `admin` (base locale) | Vault `critique` | connexion « par la base locale » en mode OIDC |
| Proxmox VE, PBS | `root@pam` | coffre | |
| NetBox | superutilisateur local (M06) | Vault `critique` | |
| Cluster | `admin.conf` | Vault `critique` (`plateforme/k8s`) | identité `kubernetes-admin`, groupe `kubeadm:cluster-admins` |
| VMs | compte local `admin` (clé SSH d'`adm01`), console Proxmox | — | |

**Travail demandé**

1. Complète le tableau ci-dessus pour **ton** lab (palier 2 a pu changer des détails) : pour chaque service, comment on **ouvre** le compte (où est le secret, combien de personnes faut-il), comment on s'en **sert** quand le SSO est en panne, comment on **referme** (changement du secret après usage, désactivation), et ce qui **trace** l'usage.
2. Écris les alertes d'usage dans `loki/regles/audit/identite.yaml` (locataire `audit`) : connexion de `kc-secours` (événement `LOGIN` du royaume `master`), authentification d'`admin` sur l'annuaire (ticket Kerberos délivré par le KDC, ou liaison LDAP dans le journal d'accès de 389-ds), requêtes du cluster faites par `kubernetes-admin` hors des contrôleurs (journal d'audit de l'API, M22). Pour chacune : gravité, destinataires (Sophie **et** l'astreinte), et le faux positif que tu acceptes.
3. Éprouve chaque compte, **un par un**, en notant l'heure, le résultat et l'alerte reçue :
   - `kc-secours` : connexion à la console, lecture d'un écran, déconnexion ;
   - `admin` de FreeIPA : `kinit admin` sur `ipa01` et `ipa user-show lucas.martin`, `kdestroy` ;
   - `root` de GitLab, `admin` de Harbor (« par la base locale »), superutilisateur de NetBox, `root@pam` sur Proxmox VE et PBS : connexion et déconnexion ;
   - Grafana : `GET /api/org` en authentification basique avec `admin` (identifiants par `-K`, jamais en argument) ;
   - Argo CD : **lis** la procédure de réactivation sans la jouer (une MR qui réactive `admin` est un changement de production ; tu la joueras en E43) ;
   - `admin.conf` : `kubectl --kubeconfig <(…) auth whoami` depuis le Vault, sans fichier clair.
   > ⚠️ **Attention** : un essai raté qui verrouille un compte de secours le rend inutilisable le jour où il sert. Un essai à la fois, mot de passe copié depuis le Vault (jamais retapé), et si un essai échoue deux fois : arrête et cherche pourquoi. Après chaque essai, **referme** : session fermée, aucun fichier clair, ticket ou cache Kerberos détruit.
4. Écris `docs/securite/identite/runbooks/RB-240-bris-de-glace.md` : quand déclarer le bris de glace (critères), qui décide, tableau par service (ouvrir, utiliser, refermer, tracer), procès-verbal d'usage à remplir, calendrier d'essai (trimestriel), et le **procès-verbal de ton essai** en annexe.
5. Qu'est-ce qui, dans ton lab, reste un **compte partagé** non nominatif et sans alerte ? Liste-les en fin de RB-240 avec l'action prévue (et le module qui la porte).

**Critères de réussite**
- [ ] RB-240 est sur `main` : un tableau par service (au moins dix lignes), critères de déclenchement, procès-verbal d'essai daté.
- [ ] Le ruler du locataire `audit` porte au moins trois alertes de bris de glace, dont une sur `kc-secours`.
- [ ] Une connexion de `kc-secours` de moins de 31 jours figure dans le locataire `audit` ; `kc-secours` est actif et n'a pas d'OTP.

**Vérification** : `lab/bin/check 24 28`

<details><summary>Indice 1</summary>

L'écouteur `jboss-logging` journalise aussi les événements du royaume `master`, même sans stockage des événements de ce royaume : une ligne `type="LOGIN", realmName="master", …, username="kc-secours"` arrive dans Loki. Une requête `| json | loggerName="org.keycloak.events" |= "realmName=\"master\"" |= "username=\"kc-secours\""` la retrouve.
</details>

<details><summary>Indice 2</summary>

`admin` s'authentifie presque toujours par **Kerberos**, y compris quand on se connecte à l'interface web avec son mot de passe ou quand les modules `freeipa.ansible_freeipa` du pipeline de l'annuaire travaillent sur `ipa01` : le KDC écrit alors dans `krb5kdc.log` une ligne `AS_REQ … ISSUE: … admin@PAR1.MEDISPHERE.INTERNAL for krbtgt/…`. Une liaison LDAP simple, plus rare, se lit dans le journal d'accès de 389-ds (`BIND dn="uid=admin,…"` puis `RESULT err=0 tag=97` sur la même connexion `conn=`). Chaque exécution du job `annuaire:appliquer` est donc un usage d'`admin` : c'est ton faux positif accepté, à rapprocher du journal du pipeline.
</details>

**Pour aller plus loin** (facultatif) : une clé FIDO2 au coffre pour `kc-secours` (second facteur matériel sans téléphone personnel) ; le partage de secret de Shamir pour que deux personnes soient nécessaires à l'ouverture. [NIST SP 800-53, AC-2 (*account management*)](https://csrc.nist.gov/projects/cprt/catalog#/cprt/framework/version/SP_800_53_5_1_1/home?element=AC-2) · [Keycloak : *Bootstrapping and recovering an admin account*](https://www.keycloak.org/server/bootstrap-admin-recovery)

---

### M24-E29 — Rotation des secrets des clients et des clés de signature  `LAB` `★★★`

> **Ticket SEC-2529** — *De : Sophie Laurent*
> Le secret du client `grafana` a été affiché en clair dans un journal de pipeline la semaine dernière (masqué depuis). Il faut le changer, sans couper Grafana en pleine journée. Et tant qu'on y est : nos clés de signature ont l'âge du royaume. Je veux une rotation des clés **sans** que personne ne soit déconnecté, et une procédure qu'on refera chaque année.

**Objectifs pédagogiques**
- Faire tourner le secret d'un client confidentiel, du coffre jusqu'au service, en mesurant la fenêtre d'indisponibilité.
- Comprendre la rotation des clés de signature d'un royaume : clé active, passive, désactivée ; publication dans le JWKS ; caches de clés des services.
- Écrire et suivre un runbook de rotation.

**Prérequis** : M24-E27 ; M24-E12 (Grafana, Secret `grafana-oidc`), M24-E16 (kube-apiserver), M24-E18 (OAuth2 Proxy) ; M24-E07 (JWKS, `kid`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Secret de `grafana` | Vault `critique` `secrets/identite.yml` de `plateforme/ansible` (`keycloak_secrets_clients.grafana`) → Secret `grafana-oidc` (`plateforme/k8s/outils/secrets-k8s.sh`) ; côté Keycloak, imposé par OpenTofu : argument en écriture seule **`client_secret_wo`** et **`client_secret_wo_version`** (variable éphémère `secrets_clients`, map) |
| Version | Keycloak 26.7.5 : la rotation des secrets avec double secret (*client secret rotation*) est une fonction **en préversion désactivée** ; elle est active par défaut à partir de la 26.8 (E33) |
| Clés du royaume | fournisseur `rsa-generated` d'origine (priorité 100) ; nouvelle clé par **`keycloak_realm_keystore_rsa_generated`** (`tofu/cles.tf`), nommée `rsa-<AAAA-MM>`, priorité supérieure ; `active` (signe) / `enabled` (publiée dans le JWKS) |
| Caches de clés | kube-apiserver (authentification structurée : relit le JWKS quand il voit un `kid` inconnu), Argo CD, Grafana, OAuth2 Proxy (vérifient l'ID token à la connexion) |
| Runbook | `docs/securite/identite/runbooks/RB-244-rotation-cles-et-secrets.md` |

**Travail demandé**

*A. Le secret d'un client*

1. Vérifie ce que ta version permet : `GET /admin/serverinfo` (en `<MOI>-admin`, ou la console *Server info* → *Features*) : la fonction `CLIENT_SECRET_ROTATION` est-elle active ? Conclus : rotation à double secret ou fenêtre courte ?
2. Prépare la rotation : nouveau secret généré sur `adm01` (`openssl rand`), écrit dans le Vault (jamais affiché), variable `secrets_clients` et `client_secret_wo_version` du client `grafana` incrémentée dans le code, charge de la variable par `outils/charger-acces.sh` et en variable protégée de CI. Relis le plan : que montre-t-il, et que ne montre-t-il pas ?
3. Joue la rotation dans l'ordre qui minimise la fenêtre (à toi de le trouver : Keycloak d'abord ou Grafana d'abord ?), en mesurant : une boucle qui tente une connexion OIDC complète à Grafana toutes les 10 s (ou un navigateur et un chronomètre). Combien de temps les **nouvelles** connexions ont-elles échoué ? Les sessions déjà ouvertes ont-elles été coupées ?
4. Prouve que l'ancien secret est mort : un échange `client_credentials`… impossible, `grafana` n'a pas de compte de service ; trouve une autre preuve (indice 1).

*B. Les clés de signature*

5. Relève le JWKS du royaume et le `kid` des jetons actuels (E07). Ajoute dans `tofu/cles.tf` une clé `rsa-<AAAA-MM>` RS256, 4096 bits, **priorité supérieure**, active. Après l'apply : combien de clés RS256 dans le JWKS ? Quel `kid` signe un **nouveau** jeton ? Un jeton émis **avant** est-il toujours accepté par `kubectl` (kubelogin le garde en cache jusqu'à expiration) et par l'introspection ?
6. Laisse l'ancienne clé **passive** au moins le temps de vie maximal d'un jeton qu'elle a signé (jeton d'accès, ID token, jeton de rafraîchissement : lequel vit le plus longtemps ?). Puis désactive-la (`enabled = false` en important le fournisseur d'origine dans le code, ou par la console **et** une ligne dans le journal). Vérifie : JWKS à une seule clé RS256, connexions et `kubectl` toujours bons.
   > ⚠️ **Attention** : désactiver l'ancienne clé **avant** l'expiration des jetons qu'elle a signés déconnecte tout le monde et peut bloquer les jetons de rafraîchissement de la console de compte et des CLI. Retour arrière : la réactiver (`enabled = true`) ; elle n'est pas détruite.
7. Écris RB-244 : secrets de clients (inventaire des clients confidentiels, ordre des opérations, fenêtre mesurée, procédure à double secret à partir de la 26.8), clés de signature (calendrier annuel, étapes, durées d'attente calculées), mot de passe de `svc-keycloak` (`svc_keycloak_version_mot_de_passe`, E08), contrôles, retour arrière.

**Critères de réussite**
- [ ] Le JWKS du royaume publie une clé RS256 active issue d'un fournisseur `rsa-<AAAA-MM>` décrit dans `tofu/cles.tf` ; l'ancienne clé est désactivée (une seule clé RS256 publiée).
- [ ] Le client `grafana` est décrit avec `client_secret_wo` et `client_secret_wo_version` ≥ 2 ; aucun secret littéral dans le code ; la connexion à Grafana par le SSO fonctionne.
- [ ] RB-244 est sur `main`, avec la fenêtre mesurée et les durées d'attente calculées.

**Vérification** : `lab/bin/check 24 29`

<details><summary>Indice 1</summary>

Un client confidentiel prouve son identité à l'**échange du code** et à l'**introspection** : `POST …/token/introspect` avec l'ancien secret répond `401 unauthorized_client` (ou `invalid_client`), avec le nouveau `200`. N'importe quel jeton (même expiré) suffit à faire le test, puisque c'est l'authentification du client qui est refusée.
</details>

<details><summary>Indice 2</summary>

Grafana lit son secret au démarrage (variable d'environnement venue du Secret) : changer le Secret ne suffit pas, il faut redémarrer le pod. Keycloak change de secret à l'apply. Entre les deux, les nouvelles connexions échouent. Prépare tout, puis enchaîne les deux en moins d'une minute.
</details>

<details><summary>Indice 3</summary>

Keycloak signe avec la clé **active** de plus haute priorité ; une clé **passive** ne signe plus mais reste publiée et vérifie ; une clé **désactivée** disparaît du JWKS. La durée d'attente avant désactivation se calcule avec la plus longue durée de vie d'un jeton signé : la session SSO maximale borne les jetons de rafraîchissement.
</details>

**Pour aller plus loin** (facultatif) : après E33, refais la rotation du secret de `grafana` avec le double secret de la 26.8 (politique de clients avec l'exécuteur de rotation) et compare la fenêtre ; signe en ES256 pour un nouveau client et mesure la taille des jetons. [Keycloak : *Managing realm keys*](https://www.keycloak.org/docs/latest/server_admin/#realm_keys) · [*Client secret rotation*](https://www.keycloak.org/docs/latest/server_admin/#_secret_rotation)

---

### M24-E30 — Revue des accès automatisée : qui a accès à quoi  `LIBRE` `★★★`

> **Ticket SEC-2530** — *De : Sophie Laurent* — *Copie : Claire Morel*
> L'auditeur HDS vient dans deux mois. Il me demandera la liste de qui a accès à quoi, à une date donnée, et la preuve qu'on la relit. Je ne veux pas d'un tableur fait à la main la veille. Je veux un rapport produit chaque mois par un pipeline, qui part des faits (l'annuaire, Keycloak, chaque service), qui me signale les écarts, et que je reçois par courriel. Je signerai la revue dans le dépôt.

**Objectifs pédagogiques**
- Concevoir un outil qui croise des sources hétérogènes (LDAP, API d'administration, RBAC Kubernetes) en lecture seule, avec des identités dédiées.
- Produire un rapport lisible par une RSSI et exploitable par une machine, avec des **écarts** plutôt qu'un inventaire brut.
- L'exécuter chaque mois en CI, le transmettre et l'archiver, sans secret exposé.

**Prérequis** : palier 2 (tous les services en SSO, modèle d'autorisation d'E10) ; M24-E28 (comptes de secours) ; M02 (scripts Python avec uv) ; M19 (pipelines planifiés, variables protégées).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Emplacement | `plateforme/identite`, dossier `outils/revue-acces/` ; rapports versionnés dans `docs/securite/identite/revue-acces/AAAA-MM.md` de `plateforme/medisphere` |
| Sources minimales | annuaire (personnes actives et désactivées, groupes, HBAC, sudo), Keycloak (`medisphere` : personnes, groupes, clients ; `master` : administrateurs), GitLab (membres des groupes et projets, administrateurs, jetons personnels actifs), Argo CD (`policy.csv`, comptes locaux), Grafana (utilisateurs, rôles, organisations), Proxmox VE (ACL, utilisateurs hors royaume `medisphere`), Kubernetes (liaisons vers `oidc:*` et vers des utilisateurs ou groupes hors `oidc:`), comptes de secours (E28) |
| Référence | le modèle d'autorisation d'E10 (`modele-autorisation.md`) : ce qui **devrait** être |
| Envoi | `securite@medisphere.internal`, par `smtp.par1.medisphere.internal` (Mailpit, M19) |
| Contraintes | lecture seule partout, avec des identités **dédiées** et minimales (pas celles des checks du workbook, pas un administrateur) ; aucun secret dans le dépôt, ni dans le journal du job, ni dans le rapport ; pipeline planifié **mensuel** sur `main` (runner protégé) ; le rapport ne contient aucune donnée personnelle au-delà de l'identifiant et des groupes |

**Travail demandé**

Conçois et livre l'outil. Exigences :
1. Le rapport donne, à une date : pour chaque personne de l'annuaire, son état et ses accès effectifs par service ; pour chaque service, les comptes qui **ne** viennent **pas** du SSO (locaux, de service, de secours) avec leur justification attendue ; et une section **Écarts** en tête : personne désactivée qui garde un accès quelque part, compte local inconnu, droit qui ne correspond pas au modèle d'E10, jeton personnel sans expiration, liaison RBAC hors `oidc:` non répertoriée, administrateur de `master` hors liste.
2. Il produit aussi une version machine (JSON) qui permet de comparer deux mois (ce qui est apparu, ce qui a disparu).
3. Un écart **connu et accepté** se déclare dans un fichier versionné (avec qui l'a accepté et jusqu'à quand) et n'est plus signalé comme nouveau ; un écart accepté expiré redevient un écart.
4. Le pipeline mensuel produit le rapport, l'envoie, l'archive comme artefact, et ouvre une MR sur `plateforme/medisphere` avec le rapport ; Sophie « signe » en approuvant la MR.
5. Tu prouves que l'outil détecte : crée un écart volontaire (par exemple un utilisateur local `essai-revue` dans Grafana, ou une personne désactivée qui garde un jeton GitLab), lance le pipeline à la main, constate l'écart dans le rapport, supprime l'écart.
6. Une page `outils/revue-acces/README.md` : sources, identités utilisées et leurs droits, ce que l'outil ne voit pas (et pourquoi).

**Critères de réussite**
- [ ] `outils/revue-acces/` existe sur `main` de `plateforme/identite`, avec son README ; un pipeline planifié mensuel est actif sur `main` et sa dernière exécution a réussi.
- [ ] Un rapport `docs/securite/identite/revue-acces/AAAA-MM.md` est sur `main` de `plateforme/medisphere` (MR approuvée), avec une section **Écarts** ; il ne contient aucun secret.
- [ ] Le courriel « Revue des accès » est arrivé à `securite@medisphere.internal` (Mailpit).
- [ ] L'écart volontaire a été détecté puis supprimé (il apparaît dans un rapport d'essai, pas dans le dernier).

**Vérification** : `lab/bin/check 24 30`

<details><summary>Indice 1</summary>

Commence par la question de l'auditeur, pas par les API : « montrez-moi que les personnes parties n'ont plus d'accès ». La jointure se fait sur l'identifiant de l'annuaire, que chaque service reçoit par `preferred_username` ; les comptes qui ne joignent pas sont précisément ceux qui intéressent Sophie.
</details>

<details><summary>Indice 2</summary>

Une identité par source, chacune avec le droit de **lire** et rien d'autre : un compte système de l'annuaire, un client à compte de service dans Keycloak (`view-users`, `view-clients`, et pour `master`… réfléchis : faut-il lire `master` par l'API, ou suffit-il de comparer avec RB-240 ?), un jeton GitLab `read_api` d'un compte de service, un compte de service Grafana en lecture d'administration, un jeton Proxmox `PVEAuditor`, une ClusterRole de lecture des liaisons dans le cluster.
</details>

**Pour aller plus loin** (facultatif) : un tableau de bord des écarts dans Grafana (métrique exposée par le pipeline) ; la même revue pour les comptes de service et leurs secrets (âge du dernier changement). [ANSSI : *Guide d'hygiène informatique*, mesures sur les comptes](https://cyber.gouv.fr/publications/guide-dhygiene-informatique) · [GitLab : *Pipeline schedules*](https://docs.gitlab.com/ci/pipelines/schedules/)

---

### M24-E31 — ADR : l'architecture d'identité de MédiSphère  `RED` `★★`

> **Ticket PLAT-2531** — *De : Claire Morel*
> Le comité d'architecture veut une seule page qui explique pourquoi nous avons FreeIPA, Keycloak, OIDC partout, des certificats SSH courts, et pas autre chose. Pas un cours : nos choix, ce qu'ils nous coûtent, ce qu'on a écarté et pourquoi, ce qu'on sait être fragile. Le M25 et le M26 s'appuieront dessus.

**Objectifs pédagogiques**
- Écrire un ADR d'architecture qui relie des décisions prises au fil du module.
- Formuler les conséquences négatives et les risques acceptés avec leurs mesures compensatoires.

**Prérequis** : M24-E01 à E30 (en particulier E10, E24, E25, E28).
**Durée indicative** : 1 h 30.

**Travail demandé**

Écris `docs/securite/identite/adr/ADR-0240-architecture-identite.md` (gabarit des ADR du dépôt) :
1. **Contexte** : exigences (HDS, une identité par personne, MFA des administrateurs, révocation rapide, preuve des accès), contraintes du lab (mémoire, un hyperviseur, pas de second site).
2. **Décisions**, chacune avec ses options écartées : annuaire (FreeIPA, contre Samba AD et OpenLDAP) ; fournisseur d'identité (Keycloak, contre Authentik, Zitadel, Dex) ; fédération en `READ_ONLY` plutôt que synchronisation ; OIDC pour tous les services (SAML gardé pour les partenaires) ; `kubectl` par authentification structurée et kubelogin (contre Pinniped, certificats) ; SSH par certificats courts de step-ca (contre clés et contre Teleport) ; OAuth2 Proxy pour ce qui ne sait pas faire d'OIDC ; MFA par OTP, WebAuthn en option ; un seul nœud Keycloak (ADR-0241) ; IdP hors du cluster qu'il authentifie.
3. **Conséquences** positives, négatives avec leur action (point unique `idp01` et `ipa01`, compte `admin` de FreeIPA utilisé par l'automatisation, comptes locaux de secours, secrets des clients dans l'état OpenTofu, GitLab CE sans groupes OIDC, Grafana OSS sans synchronisation d'équipes, PBS sans groupes).
4. **Risques acceptés** et mesures compensatoires (avec le runbook ou l'exercice qui les porte).
5. **Ce que consomment les modules suivants** : M25 (client `openbao`, groupes → politiques, secrets des clients migrés dans OpenBao), M26 (durcissement de `idp01` et `ipa01`, politiques d'admission fondées sur les groupes), F3/F5 (astreinte, PRA de l'identité).
6. **Conditions de révision**.

**Critères de réussite**
- [ ] L'ADR est sur `main` de `plateforme/medisphere` (MR relue) et tient en deux pages environ.
- [ ] Chaque décision a au moins une option écartée avec la raison ; au moins cinq conséquences négatives ont une action ou un risque accepté explicite.
- [ ] La section « modules suivants » cite le client `openbao`, les groupes de l'annuaire et la migration des secrets des clients.

<details><summary>Indice 1</summary>

Reprends tes notes : E01 et E09 (pourquoi OIDC), E10 (modèle d'autorisation), E14 (Harbor), E24 (mesures de HA), E25 (RTO), E28 (comptes partagés restants). Un ADR cite, il ne répète pas.
</details>

<details><summary>Indice 2</summary>

Pour les options écartées, une ligne chacune suffit si elle donne la **raison décisive** : licence (Teleport CE au-delà de 100 salariés), fonctionnalité (Samba AD sans HBAC ni CA intégrée), maturité ou exploitation.
</details>

**Pour aller plus loin** (facultatif) : un schéma de l'architecture (flux d'une connexion, flux de révocation) dans le même dossier. [ADR de Michael Nygard](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)

---

### M24-E32 — Questions de production : Teleport, Pinniped, fédération, licences  `Q` `★★★`

> **Ticket PLAT-2532** — *De : Karim Benali*
> On me pose ces questions en comité à chaque fois. Réponds par écrit, avec nos chiffres et nos contraintes ; je recopierai les meilleures réponses dans la FAQ de l'équipe.

**Objectifs pédagogiques**
- Argumenter des choix d'outils et de licences dans le contexte de MédiSphère.
- Situer les standards voisins (SCIM, SAML fédéré, comptes de service) et leurs limites.

**Prérequis** : paliers 1 à 3 du module.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds aux 10 questions.

1. Teleport offrirait l'enregistrement des sessions SSH et Kubernetes, l'accès juste-à-temps et un seul outil. Pourquoi MédiSphère ne peut-elle pas installer les binaires Community Edition ? Quelles sont les deux voies légales, et ce que chacune coûte ?
2. *(QCM)* Pinniped, comparé à notre authentification structurée de kube-apiserver avec kubelogin :
   - A. remplace Keycloak
   - B. permet d'authentifier par OIDC sur des clusters dont on ne peut pas modifier les options de kube-apiserver (clusters gérés), en échangeant l'identité contre un certificat court ou un jeton
   - C. est obligatoire depuis Kubernetes 1.34
   - D. ne fonctionne qu'avec LDAP
3. Un centre hospitalier partenaire veut que ses médecins se connectent à MédiAgenda avec leur compte de l'hôpital, qui expose un IdP SAML 2.0. Décris l'architecture dans Keycloak (fournisseur d'identité, *first broker login*, mappeurs, groupes), les métadonnées et certificats à échanger, et ce que tu **refuses** de faire avec leurs attributs.
4. Keycloak, Authentik, Zitadel : donne pour chacun une force et une raison pour laquelle il n'a pas été retenu (ou le serait dans un autre contexte).
5. FreeIPA, Samba AD et OpenLDAP : lequel choisirais-tu si MédiSphère avait 300 postes Windows à gérer ? Et si elle n'avait aucun serveur Linux ? Justifie.
6. *(QCM)* Le compte de service `svc-synchro-identite` (GitLab, E11) :
   - A. doit avoir l'OTP comme toute personne
   - B. est un compte non humain : pas de mot de passe de connexion interactive, un jeton à portée et durée limitées, un propriétaire humain nommé, une rotation, et il apparaît dans la revue des accès
   - C. peut être partagé par l'équipe puisqu'il n'appartient à personne
   - D. doit être désactivé hors des heures ouvrées
7. Qu'est-ce que SCIM ? Qu'apporterait-il entre Keycloak (API SCIM activée par défaut en 26.8) et GitLab ou Grafana, et pourquoi ne remplace-t-il pas la revue des accès ?
8. Un auditeur demande : « si Keycloak est compromis, qu'est-ce que l'attaquant obtient ? ». Réponds service par service, en distinguant ce que le SSO lui ouvre et ce qui reste protégé (comptes de secours locaux, certificats SSH déjà émis, `admin.conf`, OpenBao au M25).
9. *(QCM)* Pour un accès d'urgence d'un prestataire pendant 4 heures, la meilleure option est :
   - A. lui donner le mot de passe de `kc-secours`
   - B. lui créer un compte dans l'annuaire, dans un groupe dédié aux droits minimaux, avec une date d'expiration, OTP obligatoire, et une désactivation planifiée tracée
   - C. lui créer un utilisateur local dans chaque service
   - D. partager la session d'un membre de l'équipe par écran partagé et lui laisser le clavier
10. Comment prouverais-tu à l'auditeur, avec ce que tu as construit, qu'un départ coupe **tout** en moins de 15 minutes ? Quelles preuves, et quelles limites (sessions déjà ouvertes, jetons en cache, certificats SSH émis) ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 10 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse (0, 1 ou 2 points) et calculé ton score sur 20.

<details><summary>Indice 1</summary>

Pour Teleport, relis `annexes/versions-bloc-F.md` (licence des binaires depuis la 16, seuils) ; pour SCIM, demande-toi ce qui **provisionne** un compte et ce qui **autorise**.
</details>

<details><summary>Indice 2</summary>

Pour la question 8, repars des jetons : un attaquant maître de Keycloak peut signer n'importe quel jeton pour n'importe quel client. Qui fait confiance à cette signature, et qui ne la regarde pas ?
</details>

**Pour aller plus loin** (facultatif) : lis la RFC 7644 (SCIM) et la documentation de la fédération SAML de Keycloak (*Identity Brokering*). [Teleport : licences](https://goteleport.com/pricing/) · [Pinniped](https://pinniped.dev/docs/) · [RFC 7644](https://www.rfc-editor.org/rfc/rfc7644)

---

### M24-E33 — Monter de version Keycloak et FreeIPA  `LAB` `★★★`

> **Ticket CHG-2533** — *De : Karim Benali* — *Copie : Sophie Laurent, Nadia Roussel*
> Keycloak 26.8.1 corrige plusieurs failles (échange de jetons, SAML, Kerberos), et la 26.8 change des comportements qu'on utilise (lecture des secrets de clients, noms de groupes dans les politiques). On passe de 26.7.5 à 26.8.1, après essai sur une copie, avec un retour arrière qu'on sait faire. Et l'annuaire a des correctifs en attente : même discipline. Fenêtre de changement mardi 7 h – 8 h, je veux le plan avant.

**Objectifs pédagogiques**
- Préparer une montée de version : notes de version, ruptures, essai sur une copie, plan de retour arrière.
- Comprendre la migration automatique du schéma de la base de Keycloak et pourquoi elle rend le retour arrière **destructif** sans restauration.
- Appliquer les correctifs de FreeIPA par `dnf` et contrôler la mise à niveau des données (`ipa-server-upgrade`).

**Prérequis** : M24-E25 (sauvegarde, restauration d'essai), M24-E26 (supervision), M24-E29 ; module 14 (montées de version en fenêtre).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Keycloak cible | **26.8.1**, archive `keycloak-quarkus-dist-26.8.1.tar.gz` (Maven Central), SHA-256 `4e2740b181faa2ea623a1c2ecf00855935311e546046e2f857615a47ed24cbe8` ; installée à côté (`/opt/keycloak-26.8.1`), bascule du lien `/opt/keycloak` par le rôle |
| Ruptures 26.8 | `annexes/versions-bloc-F.md` : lecture du secret d'un client par `manage-clients` seulement ; mappeurs d'IdP sans rôles d'administration ; nom de groupe nu = groupe de premier niveau dans les politiques ; client désactivé absent de `aud` ; jeton de rafraîchissement plafonné par l'inactivité de session ; échecs de connexion stockés en base ; rotation des secrets clients et API SCIM actives par défaut ; nouvelles options `cache-embedded-cluster-name`, `cache-embedded-node-name` |
| Migration | au premier démarrage, Keycloak met à jour le schéma (Liquibase, table `databasechangelog`) et migre les royaumes (« migrated realm … to 26.8.0 » dans le journal) |
| Essai | sur `idp-resto` (E25 : restauration de la sauvegarde de la nuit, 26.7.5), puis montée en 26.8.1 sur la copie |
| FreeIPA | correctifs de la mineure 4.13 par `dnf` (dépôts AppStream et BaseOS de Rocky 10) ; `ipa-server-upgrade` est lancé par le paquet |
| Runbook | `docs/securite/identite/runbooks/RB-245-montee-de-version-identite.md` |

**Travail demandé**

*A. Préparer*

1. Lis les notes de version et le guide de montée de version (*Upgrading Guide*) de 26.8.0 et 26.8.1. Pour chaque rupture, cherche dans **ton** royaume et **ton** code si elle te touche (client `wb-checks` qui lisait des secrets ? politiques qui citent des groupes ? fournisseur OpenTofu ?) et écris le résultat dans le plan de changement `~/m24/e33/plan.md` (étapes, durées, critères d'arrêt, retour arrière, communication).
2. Essai sur une copie : recrée `idp-resto`, restaure la sauvegarde de la nuit (procédure RB-243, chronométrée une seconde fois), puis passe-la en 26.8.1 avec le rôle (inventaire d'essai). Lis le journal du premier démarrage : combien de temps a pris la migration ? Contrôle sur la copie : découverte, `kid` inchangé, nombre de personnes et de clients, et, avec l'API d'administration de la copie (jeton de `wb-checks`, restauré avec la base), ce que ce client peut encore lire (secret d'un client ? rôles de son compte de service ?). Le fournisseur OpenTofu 5.10 n'a pas de compatibilité 26.8 documentée : note ce que tu devras surveiller au premier `tofu plan` du jour J.
3. Détruis `idp-resto`.

*B. Le changement*

4. Le jour J, dans l'ordre : annonce (Mattermost/courriel de l'astreinte), sauvegarde **à la main** juste avant (`identite-sauvegarde.service`) et contrôle de l'objet envoyé, `host_vars/idp01/keycloak.yml` (version et empreinte) par MR, application du playbook.
   > ⚠️ **Attention** : à partir du premier démarrage en 26.8.1, la base est migrée : remettre le lien sur 26.7.5 **ne suffit pas** à revenir en arrière (l'ancienne version refuse ou corrompt un schéma plus récent). Le seul retour arrière est : arrêt, **restauration de la sauvegarde d'avant le changement**, lien sur 26.7.5, démarrage. Garde l'ancienne version installée jusqu'à la clôture du changement.
5. Contrôles après le changement : `/health/ready`, version (console *Server info* ou `kc.sh --version`), alertes d'E26 muettes, connexion de chaque personnage type (`lucas.martin`, toi avec OTP), `kubectl` par kubelogin, Argo CD par la CLI, un `tofu plan` vide dans `plateforme/identite`, `lab/bin/check 24 05` (le client `wb-checks` lit-il encore ce qu'il doit lire ?).
6. FreeIPA : sur `ipa01`, sauvegarde (`identite-sauvegarde.service`), `dnf check-update`, lecture des paquets concernés, application des correctifs **de la mineure seulement**, puis `ipactl status`, journal de `ipa-server-upgrade` (`/var/log/ipaupgrade.log`), `ipa-healthcheck`, connexion d'un personnage à Keycloak (la fédération passe par LDAPS), `kinit` et `ssh` sur une VM inscrite.
7. Écris RB-245 (montée de version de Keycloak et de FreeIPA : préparation, essai sur copie, fenêtre, contrôles, retour arrière par restauration, durée mesurée) et clos le changement : retire `/opt/keycloak-26.7.5` (par le rôle ou à la main, noté) **après** une semaine sans incident, ou explique pourquoi tu le gardes.

**Critères de réussite**
- [ ] `idp01` exécute Keycloak 26.8.1 (`/opt/keycloak` → `/opt/keycloak-26.8.1`), en `start --optimized` ; la base porte les migrations 26.8.0 ; la santé est bonne.
- [ ] `ipa01` n'a plus de mise à jour en attente pour `ipa-server` et `ipactl status` est entièrement en marche.
- [ ] RB-245 est sur `main`, avec la durée mesurée de la migration et la procédure de retour arrière par restauration ; `idp-resto` n'existe plus.

**Vérification** : `lab/bin/check 24 33`

<details><summary>Indice 1</summary>

Le rôle installe la nouvelle version dans son propre dossier, la construit (le témoin de construction vit dans le dossier de la version), bascule le lien et redémarre : l'ancienne version reste sur le disque. La base, elle, n'a qu'une version.
</details>

<details><summary>Indice 2</summary>

Pour savoir si une rupture te touche, cherche dans le code (`grep -rn` sur `tofu/`) et interroge l'API : liste des politiques d'autorisation, rôles du compte de service `wb-checks` (`view-clients` ne lit plus les secrets en 26.8 : est-ce un problème pour un check en lecture seule ?).
</details>

**Pour aller plus loin** (facultatif) : la stratégie de mise à jour progressive (*rolling updates*, `kc.sh update-compatibility`) qui dirait si deux versions peuvent tourner ensemble dans une grappe ; elle n'a de sens qu'à deux nœuds (E24). [Keycloak : *Upgrading Guide*](https://www.keycloak.org/docs/latest/upgrading/) · [Notes de version](https://www.keycloak.org/docs/latest/release_notes/) · [*Update compatibility*](https://www.keycloak.org/server/update-compatibility)

---

### M24-E34 — Ouvrir un nouveau service au SSO en temps limité  `CHRONO` `★★★`

> **Ticket PLAT-2534** — *De : Claire Morel*
> Le comité de direction veut consulter les SLO de MédiAgenda dans Pyrra (`https://slo.apps.par1.medisphere.internal`). Aujourd'hui, Pyrra est ouvert à quiconque joint la Gateway, sans authentification : c'est une limite qu'on a acceptée au M21 « jusqu'au M24 ». On y est. Je veux Pyrra derrière le SSO, réservé à la plateforme, au support et à la direction, d'ici une heure, et la preuve que plus personne n'y entre sans se connecter.

**Objectifs pédagogiques**
- Ouvrir un service sans OIDC natif au SSO de bout en bout, sous contrainte de temps, avec la chaîne complète (Keycloak en code, OAuth2 Proxy par Argo CD, publication, filtrage).
- Prouver l'effet (refus, autorisation par groupe, absence de contournement).

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé. Tes fichiers des exercices précédents (E18 en particulier), tes runbooks et la documentation officielle sont permis.
- **Chemin imposé** : client et redirections par OpenTofu (`plateforme/identite`), instance d'OAuth2 Proxy par Argo CD (sur le modèle exact d'E18), secrets hors Git (Vault `critique` et `secrets-k8s.sh`), MR pour chaque dépôt. Aucun `kubectl apply`, aucun clic dans le royaume `medisphere`.
- Durée : **60 min** du début de la lecture à la preuve écrite ; 15 min de plus pour le journal.

**Prérequis** : M24-E18 (OAuth2 Proxy), M24-E10 (modèle d'autorisation) ; M21-E26 (Pyrra : `pyrra/` de `plateforme/observabilite`, Application `pyrra`, HTTPRoute `pyrra`, CNP `pyrra-api-entree`).
**Durée** : 1 h chronométrée + 15 min de journal + 30 min de retour d'expérience.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Pyrra | interface `pyrra-api` (Service `pyrra-api:9099`, espace `supervision`), publiée aujourd'hui par l'HTTPRoute `pyrra` (`slo.apps.par1.medisphere.internal`) sur la Gateway `gw-par1` ; CNP `pyrra-api-entree` : depuis la Gateway (`ingress`) et Prometheus |
| OAuth2 Proxy | chart `oauth2-proxy/oauth2-proxy` 10.7.x (OAuth2 Proxy 7.15.5) recopié dans Harbor ; client Keycloak **`oauth2-proxy`** partagé par les instances (redirections listées une à une) ; nouvelle instance **`oauth2-proxy-pyrra`** dans l'espace `oauth2-proxy` |
| Groupes autorisés | `plateforme-admins`, `plateforme`, `support`, `direction` |
| Journal | `docs/socle/journal/<AAAA-MM-JJ>-M24-E34-pyrra-sso.md` de `plateforme/medisphere` (heure de début, étapes horodatées, preuves, ce qui t'a ralenti) |

**Critères de réussite**
- [ ] Une requête anonyme sur `https://slo.apps.par1.medisphere.internal/` est redirigée vers `https://sso.par1.medisphere.internal/realms/medisphere/…` ; Pyrra n'est plus joignable par la Gateway sans passer par OAuth2 Proxy.
- [ ] Le client `oauth2-proxy` porte la redirection `https://slo.apps.par1.medisphere.internal/oauth2/callback`, décrite dans `plateforme/identite` (aucune redirection joker).
- [ ] `claire.morel` (groupe `direction`) voit Pyrra ; `julien.petit` (groupe `mediagenda`) est refusé (403) ; le journal le prouve (heures, codes).
- [ ] La CNP `pyrra-api-entree` n'accepte plus la Gateway directement ; le journal est sur `main` et le temps total est noté.

**Vérification** : `lab/bin/check 24 34` (à lancer à la fin)

**Pour aller plus loin** (facultatif) : refais l'exercice pour Thanos Query et Alertmanager (limite acceptée au M21-E29 : « proxy d'authentification devant les trois interfaces au M24 »), en visant 30 minutes, et décide comment les sondes du témoin de `mon01` continuent de les interroger.
