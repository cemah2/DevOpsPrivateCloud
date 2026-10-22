# Module 25 — Palier 3 : Production

Au palier 2, OpenBao est devenu le cœur de la plateforme : la CI s'y authentifie par ses jetons d'identité, Ansible y lit le mot de passe de ses Vaults, ESO y prend les Secrets de tout le cluster, MédiAgenda y reçoit des identifiants PostgreSQL d'une heure, cert-manager y fait signer les certificats de service, Cosign y signe sans voir la clé. Et tout cela tient sur **une seule VM**, `vault01`, qui à chaque redémarrage attend que trois personnes viennent taper leur part de clé. Si `vault01` s'arrête un dimanche, MédiAgenda perd sa base dans l'heure, la CI ne livre plus, et il faut réveiller trois dépositaires. Personne n'a jamais restauré le coffre, personne ne le supervise, son jeton racine traîne dans un historique, et il tourne avec l'unité systemd du paquet. Ce palier le met en **production** : grappe Raft de trois nœuds derrière une VIP, auto-descellement par un second OpenBao (`kms01`), instantanés chiffrés et restauration éprouvée, supervision, durcissement, montée de version sans coupure, comparaison avec HashiCorp Vault, puis les décisions écrites, une politique de rotation automatisée et une rotation d'urgence chronométrée.

> ⚠️ **Rappel** : à partir d'ici, une erreur sur le coffre arrête **toute** la plateforme, et une erreur sur ses clés peut la rendre **définitivement** illisible. Avant tout changement de `vault01-03` ou de `kms01` : (1) un instantané Raft de moins d'une heure, copié hors du nœud (avant E26 : `bao operator raft snapshot save` à la main, voir E24) ; (2) les parts Shamir (puis les clés de récupération) et les clés `age` des dépositaires **vérifiées présentes** dans `secrets/openbao-init.yml` (Vault `critique`) et sur le support hors ligne ; (3) une session `bao` ouverte avec un jeton `plateforme-admin` valide au moins une heure (`bao token lookup`) ; (4) un nœud à la fois, et `bao operator raft list-peers` vert avant de passer au suivant. On ne détruit **jamais** le dossier `/var/lib/openbao` d'un nœud pour « repartir propre » sans avoir lu RB-251.

**Rappels du module**
- Aucun secret sur une ligne de commande (visible par `ps` et dans l'historique), dans Git en clair, dans un ticket ou dans un compte rendu : les jetons et parts passent par des fichiers 600, l'entrée standard, ou `bao login` ; les sorties de `bao operator init`, `generate-root`, `token create` vont **directement** dans un fichier ou dans `ansible-vault`, jamais à l'écran.
- Toute configuration d'OpenBao (montages, politiques, méthodes, rôles, quotas) passe par **`plateforme/secrets`** (OpenTofu, fournisseur `hashicorp/vault`, MR, `plan` relu) ; les VMs par `plateforme/infra` (OpenTofu, état `socle`, et état **`envs/m25`** pour les VMs temporaires) et `plateforme/ansible` (rôles `openbao`, `openbao_kms`, `keepalived`, `haproxy`, `pare_feu`, `pare_feu_local`, `alloy`) ; la supervision par `plateforme/observabilite` ; la documentation dans `docs/securite/secrets/` de `plateforme/medisphere`.
- Travail personnel dans `~/m25/eXX/` sur `adm01`. `BAO_ADDR=https://openbao.par1.medisphere.internal:8200` est dans ton `~/.bashrc` ; pour parler à un nœud précis : `BAO_ADDR=https://vault02.par1.medisphere.internal:8200 bao …`.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Grappe | `vault01` (1021, 10.10.20.21), `vault02` (1022, 10.10.20.22), `vault03` (1023, 10.10.20.23) : Debian 13, 2 vCPU, 1 Go, 20 Go, VNet `vinfra`, étiquettes `socle`, `role-coffre` (groupe Ansible `role_coffre`) ; API **8200**, grappe **8201** ; stockage Raft `/var/lib/openbao`, `node_id` = nom court de l'hôte ; `api_addr` = `https://<hôte>.par1.medisphere.internal:8200`, `cluster_addr` = `https://<hôte>.par1.medisphere.internal:8201` |
| VIP | **10.10.20.200** `openbao.par1.medisphere.internal` (A dans PowerDNS par OpenTofu ; avant E24 le nom pointe sur 10.10.20.21) ; keepalived **VRID 120**, VRRP v3 unicast sur `eth0`, rôle `keepalived` du M07 ; la VIP suit le **nœud actif** (`/v1/sys/health` : 200 = actif, 429 = en attente, 503 = scellé, 501 = non initialisé) |
| `kms01` | 1024, **10.10.20.24**, Debian 13, 1 vCPU, 1 Go, 16 Go, étiquettes `socle`, `role-kms` (groupe `role_kms`) ; OpenBao mononœud (Raft), **scellé par Shamir** (5 parts, seuil 3, dépositaires du palier 1, fichier `secrets/kms01-init.yml` du Vault `critique`) ; moteur `transit/`, clé **`autodescellement-par1`**, politique **`kms-autodescellement`** ; rôle Ansible `openbao_kms` |
| Seal de la grappe | **`transit`** vers `https://kms01.par1.medisphere.internal:8200` (à partir d'E25) ; jeton **orphelin et périodique** dans **`/etc/openbao/kms.env`** (`BAO_TOKEN=…`, root, 600), lu par l'unité par une surcharge `/etc/systemd/system/openbao.service.d/medisphere.conf` ; les anciennes parts Shamir deviennent des **clés de récupération** |
| Fichiers d'un nœud | `/etc/openbao/openbao.hcl` (gabarit du rôle `openbao`), `/etc/openbao/tls/{cert,key}.pem` (ACME step-ca, `cert-renewer@openbao`, noms `openbao.par1…` puis le nom de l'hôte), `/var/log/openbao/audit.log` (dispositif d'audit déclaré dans la configuration, E21) ; unité `openbao.service` du paquet `.deb` amont |
| Versions | OpenBao **2.6.4** au début du palier (paquet `openbao_2.6.4_linux_amd64.deb`, SHA-256 `09e0b4ced4cfa2f04a3573c5ec05c94ecd4f858d580d76c7422c51b99b74cce1`), **2.7.1** après E29 (`openbao_2.7.1_linux_amd64.deb`, SHA-256 `aa5dd78f590a89256dffae7c7f8664b11e4380478da86454d8030020f6af0add`) ; HashiCorp Vault **2.2.x** (E30 seulement) |
| Instantanés (E26) | minuterie **`openbao-instantane.timer`** (horaire) sur les trois nœuds, script **`/usr/local/sbin/openbao-instantane`** (ne travaille que sur le nœud actif), AppRole **`openbao-instantanes`** (politique du même nom), chiffrement **age** vers la clé publique de restauration, envoi par `rclone` vers `s3-01`, compartiment **`openbao-instantanes`**, identité S3 **`openbao-instantanes`** (`/etc/openbao/s3.env`), rétention 30 jours par cycle de vie ; trace `/var/lib/openbao-instantane/dernier-succes` |
| VMs temporaires | **`bao-restauration`** : VMID **2252**, VNet `vsandbox`, **10.10.99.52**, Debian 13, 1 vCPU, 1 Go (E26) ; **`bao-essai`** : VMID **2251**, `vsandbox`, **10.10.99.51** (adresse fixe : le flux temporaire vers `kms01` vise une adresse), 2 vCPU, 2 Go (E30) ; état OpenTofu **`envs/m25`**, étiquette `env-m25` ; détruites à la fin de leur exercice, **jamais les deux à la fois** |
| Supervision (E27) | ScrapeConfig **`openbao`** (`plateforme/observabilite/scrape/openbao.yaml`), règles **`regles/secrets.yaml`** (`OpenBaoScelle`, `OpenBaoSansLeader`, `OpenBaoAuditEnEchec`, `OpenBaoBauxNombreux`, `CertificatServicesExpireBientot`), tableau **`tableaux/plateforme/openbao.json`**, sonde de `/v1/sys/health` depuis `mon01` |
| Documentation | `docs/securite/secrets/` : `adr/ADR-0250-coffre.md`, `adr/ADR-0251-chiffrement-etcd.md` (E31), `runbooks/RB-251-descellement-et-redemarrage.md` (E25), `RB-252-sauvegarde-restauration-openbao.md` (E26), `RB-253-montee-de-version-openbao.md` (E29), `RB-254-rotation.md` (E33), `politique-rotation.md` (E33), `comparatif-vault.md` (E30) ; journaux d'incident dans `docs/kubernetes/journal/` |
| Tickets | PLAT-26xx, SEC-26xx, CHG-26xx, INC-52xx (xx = exercice) |

> **Mémoire** : `vault02`, `vault03` et `kms01` sont des VMs **permanentes** déjà comptées dans le profil du bloc F (≈ 111 Go). `bao-restauration` (1 Go, E26) et `bao-essai` (2 Go, E30) s'ajoutent le temps de leur exercice, **jamais en même temps**. Vérifie la marge de `pve01` (`free -g`) avant de les créer ; si elle manque, arrête `ceph-par1` le temps d'E30 (Vault n'y touche pas), jamais une VM du socle ni un nœud de la grappe.

**Ordre conseillé** : E24 → E25 → E26 → E27 → E28 → E29 → E30 → E31 → E32 → E33 → E34. La grappe (E24) précède tout : le seal se migre nœud par nœud (E25), et c'est la grappe qu'on sauvegarde (E26). La sauvegarde précède **toute** autre modification risquée ; la supervision (E27) précède le durcissement (E28) pour voir tout de suite ce qu'il casse ; la montée de version (E29) s'appuie sur les instantanés, les alertes et l'unité durcie ; la comparaison (E30) nourrit l'ADR (E31) ; la rotation automatisée (E33) précède la rotation d'urgence chronométrée (E34), faite en dernier, sans aide. **Durée totale indicative** : 22 à 27 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 25 XX`). Elles lisent OpenBao avec l'AppRole `wb-checks` (métadonnées seulement), les nœuds en SSH (`admin`, commandes de consultation en `sudo -n`), Prometheus, Loki (locataire `audit`), GitLab et `s3-01` en lecture. Variables facultatives de `lab/lab.env` : `WB_OPENBAO_URL`, `WB_M25_NOEUDS` (défaut `vault01 vault02 vault03`), `WB_M25_KMS` (défaut `kms01`), `WB_M25_S3_INSTANTANES_FILE` (défaut `~/.config/workbook/s3-openbao-instantanes.env`), `WB_M25_S3_URL` (défaut `https://s3-01.par1.medisphere.internal:8333`).

---

### M25-E24 — Grappe Raft à trois nœuds et VIP  `LAB` `★★★`

> **Ticket PLAT-2624** — *De : Claire Morel* — *Copie : Karim Benali, Nadia Roussel*
> Jeudi, `vault01` a redémarré pour une mise à jour du noyau : vingt-cinq minutes sans coffre, trois pipelines en échec, MédiAgenda recette sans base au bout de l'heure. Le coffre est maintenant aussi critique que GitLab. Je veux trois nœuds, une adresse unique qui suit celui qui travaille, et la preuve qu'on peut en perdre un à n'importe quel moment sans que les écritures s'arrêtent plus de quelques secondes.

**Objectifs pédagogiques**
- Construire une grappe OpenBao à stockage **Raft intégré** : `retry_join` en TLS, rôles *leader* / *follower*, électeurs et non-électeurs, quorum, *autopilot*.
- Distinguer le **nœud actif** d'OpenBao (qui sert les requêtes) du **leader Raft**, et comprendre ce que fait un nœud **en attente** (*standby*) d'une requête qu'il reçoit (*request forwarding*).
- Faire suivre le nœud actif par une VIP keepalived pilotée par `sys/health`, et obtenir des certificats ACME pour un nom porté par trois machines.
- Mesurer une bascule (passage de témoin, arrêt du service, arrêt brutal de la VM) et la lire dans les journaux.

**Prérequis** : M25-E03 (rôle `openbao`, `vault01`), M25-E08 (`plateforme/secrets`), M07-E12 (keepalived et relais du défi ACME sur `lb01`/`lb02`), M06-E18 (rôle `certificats_acme`), M05 (module `vm-debian`, état `socle`).
**Durée indicative** : 3 h 30.

**Contexte technique**
- **Lecture obligatoire** : [stockage Raft](https://openbao.org/docs/configuration/storage/raft/) (`retry_join`, `leader_api_addr`, `leader_ca_cert_file`, `leader_tls_servername`), [`bao operator raft`](https://openbao.org/docs/commands/operator/raft/) (dont `autopilot`), [haute disponibilité](https://openbao.org/docs/concepts/ha/), [`/sys/health`](https://openbao.org/api-docs/system/health/).
- **État de départ** : `vault01` seul, scellé par **Shamir** (5 parts, seuil 3), stockage Raft. Tant que le seal reste Shamir (jusqu'à E25), **chaque** nœud qui démarre ou rejoint la grappe doit être descellé avec trois parts : prévois les dépositaires (simulés) et le support hors ligne.
- **Certificats** : le rôle `certificats_acme` émet par le défi HTTP-01 ; `ca01` vient chercher le jeton sur `http://openbao.par1.medisphere.internal/` — donc, une fois la VIP en place, sur le nœud **actif**, qui n'est pas forcément celui qui demande. C'est exactement le problème de `lb01`/`lb02` au M07-E12 ; le renouvellement, lui, se fait par TLS mutuel (`step ca renew`), sans défi. Flux nécessaires : `ca01` → 10.10.20.200, 10.10.20.21-23 TCP 80 ; `vault01-03` → `ca01` TCP 443.
- **keepalived** : instance `VI_OPENBAO`, VRID **120**, `eth0`, VRRP v3 **unicast** (pairs calculés depuis le groupe `role_coffre`, comme `role_lb` au M07), état initial `BACKUP` partout, **sans préemption**, script de suivi sur `/v1/sys/health` du nœud local. Le certificat du nœud ne porte pas `127.0.0.1` : pense à `curl --resolve`.
- **Flux** : entre `vault01-03` (même VLAN) : 8200-8201 et VRRP (protocole 112) par le pare-feu local ; la VIP 10.10.20.200:8200 reprend les flux déjà ouverts vers `openbao` (PLAN §4.12) ; MGMT joint tout le lab.
- **Données** : la grappe hérite des données de `vault01` (les nouveaux nœuds rejoignent, ils ne sont pas initialisés). Un nœud qui rejoint ne doit **jamais** avoir été initialisé seul.

> ⚠️ **Attention** : (1) le changement de l'enregistrement `openbao` (10.10.20.21 → 10.10.20.200) touche tous les clients (CI, ESO, Ansible, cert-manager) : fais-le **après** avoir vérifié que la VIP est portée par `vault01` et répond, et garde la durée de vie DNS de l'enregistrement courte le temps du changement ; (2) n'arrête jamais deux nœuds en même temps : à trois, la grappe tolère **une** panne ; (3) prends un instantané à la main avant de commencer : `bao operator raft snapshot save ~/m25/e24/avant.snap` avec ton jeton `plateforme-admin`, puis `age -R <destinataires>` et copie hors de `adm01` ; (4) retour arrière : arrêter `openbao` sur `vault02`/`vault03`, `bao operator raft remove-peer vault02` puis `vault03` depuis `vault01`, remettre l'enregistrement DNS sur 10.10.20.21.

**Travail demandé**
1. **VMs.** Dans `plateforme/infra` (état `socle`), crée `vault02` et `vault03` sur le modèle de `vault01` (une seule ressource itérée, pas de copier-coller), leurs enregistrements A/PTR, la VIP dans NetBox (`role = vip`, nom `openbao.par1.medisphere.internal`, sans interface) ; **ne change pas encore** l'enregistrement `openbao`. `tofu plan` relu, MR.
2. **Configuration Raft.** Étends le gabarit du rôle `openbao` : un bloc `retry_join` **par nœud du groupe** (calculé), vérification TLS du leader par la racine MédiSphère. Lis la documentation : que fait un nœud qui démarre avec des `retry_join` alors qu'il n'est ni initialisé ni membre ? Et un nœud déjà membre ? Pourquoi `vault01` peut-il recevoir la même liste sans risque ?
3. **Certificats.** Donne aux trois nœuds un certificat portant `openbao.par1.medisphere.internal` **et** leur propre nom, obtenu par ACME malgré la VIP. Inspire-toi du M07-E12 ; explique dans ton journal pourquoi le renouvellement n'a pas ce problème.
4. **Rejoindre.** Applique le rôle à `vault02` (un seul hôte), descelle-le (trois parts, sur son adresse propre), puis observe :
   ```
   admin@adm01:~$ bao operator raft list-peers
   admin@adm01:~$ bao operator raft autopilot state
   ```
   Pourquoi le nouveau nœud apparaît-il d'abord **non électeur** ? Au bout de combien de temps devient-il électeur, et quel paramètre le règle ? Recommence avec `vault03`.
5. **Autopilot.** Lis `bao operator raft autopilot get-config` puis règle `cleanup_dead_servers`, `dead_server_last_contact_threshold` et `min_quorum` (valeurs à justifier dans ton journal ; que fait réellement le nettoyage avec `min_quorum = 3` dans une grappe de trois ?). Où ce réglage est-il stocké, et comment le mettre en code (vérifie si le fournisseur `hashicorp/vault` sait le gérer contre OpenBao) ?
6. **VIP.** Rôle `keepalived` sur le groupe `role_coffre` (instance, script de suivi). Vérifie qu'**une seule** VIP existe et qu'elle est sur le nœud actif (`ip -br addr` sur les trois). Puis seulement, change l'enregistrement `openbao` vers 10.10.20.200 et vérifie depuis `adm01`, la CI (un pipeline qui lit un secret) et ESO (un `ExternalSecret` qui se rafraîchit).
7. **Bascules mesurées.** Pendant chaque épreuve, une boucle sur `adm01` écrit un secret toutes les 250 ms **par la VIP** et note l'heure et le résultat (`kv/wb-essais/bascule`, chemin autorisé à ta politique) :
   - passage de témoin : `bao operator step-down` sur le nœud actif ;
   - arrêt propre : `sudo systemctl stop openbao` sur le nœud actif ;
   - arrêt brutal : `qm stop <VMID>` du nœud actif sur `pve01`.
   Pour chacun : durée sans écriture, nombre d'échecs, nouveau nœud actif, nouveau leader Raft, porteur de la VIP. Lis ce qui s'est passé dans `journalctl -u openbao` (nœud qui prend la main : lignes d'élection et d'activation) et `journalctl -t keepalived-transition`. Remets les nœuds en place entre deux épreuves.
8. **Documentation.** Dans `docs/securite/secrets/` : un schéma de la grappe (nœuds, ports, VIP, flux) et un tableau des mesures. Mets à jour la matrice des flux.

**Critères de réussite**
- [ ] Trois pairs électeurs, un leader, autopilot sain avec une tolérance d'au moins une panne ; `cleanup_dead_servers` activé et `min_quorum` à 3.
- [ ] Exactement un nœud répond 200 à `/v1/sys/health`, les deux autres 429 ; la VIP n'est portée que par celui-là ; `openbao.par1.medisphere.internal` résout en 10.10.20.200 et `sys/leader` lu par la VIP désigne le nœud qui la porte.
- [ ] Les trois certificats portent les deux noms et se vérifient contre la racine MédiSphère.
- [ ] `~/m25/e24/mesures.md` donne, pour les trois épreuves, la durée d'indisponibilité en écriture mesurée.

**Vérification** : `lab/bin/check 25 24`

<details><summary>Indice 1</summary>

Un nœud en attente répond à presque tout : il **transmet** la requête au nœud actif par le port de grappe (8201). C'est pour cela que la boucle peut écrire par n'importe quel nom pendant que la grappe est saine. Ce qu'il ne fait pas : répondre 200 à `sys/health`. Lis les paramètres `standbyok` et `perfstandbyok` de `sys/health` et demande-toi pourquoi le script de keepalived ne doit **pas** les utiliser.
</details>

<details><summary>Indice 2</summary>

Pour le défi ACME : au M07, le port 80 de chaque répartiteur relaie `/.well-known/acme-challenge/` vers un backend qui contient **les deux** répartiteurs sur un port de défi ; seul celui qui demande y écoute. Rien n'empêche d'installer le même petit relais HAProxy sur les nœuds du coffre (quelques Mo de mémoire), en ne lui confiant **que** le port 80.
</details>

<details><summary>Indice 3</summary>

L'arrêt brutal est le plus long : le leader Raft disparu, les suiveurs attendent l'expiration de leur délai d'élection, puis le nouveau leader doit encore **prendre le verrou** d'actif et reconstruire son état (montages, baux) avant de répondre 200 — et keepalived doit le voir (intervalle × nombre d'échecs). Additionne ces délais avant de mesurer, puis compare.
</details>

**Pour aller plus loin** (facultatif) : ajoute un nœud **non électeur** permanent (`bao operator raft join -non-voter`) dans une VM jetable et observe-le dans autopilot ; lis la section *Performance standby* de la documentation : est-ce disponible dans OpenBao ? Qu'est-ce que ça changerait pour la charge de lecture d'ESO ?

---

### M25-E25 — Auto-descellement : `kms01` et migration du seal  `LAB` `★★★`

> **Ticket PLAT-2625** — *De : Nadia Roussel* — *Copie : Sophie Laurent*
> Avec trois nœuds, chaque redémarrage demande trois parts pour **chaque** nœud. La nuit dernière, la mise à jour de sécurité de Debian a redémarré `vault02` : il est resté scellé jusqu'au matin, et personne ne s'en est aperçu. Je veux que le coffre redémarre **seul**. Sophie veut qu'une copie volée d'un disque de nœud ne serve à rien, et que les parts restent indispensables pour les opérations sensibles.

**Objectifs pédagogiques**
- Comprendre l'**auto-descellement** : la clé racine n'est plus reconstituée par des parts, elle est chiffrée par un service externe (ici le moteur `transit` d'un second OpenBao), et les parts deviennent des **clés de récupération**.
- Installer un OpenBao mononœud dédié (`kms01`) qui ne sert **que** ce chiffrement, avec un jeton orphelin et périodique au moindre privilège.
- Migrer le seal d'une grappe Raft **sans perte de données** en suivant la procédure officielle dans l'ordre, nœud par nœud.
- Écrire le runbook du redémarrage et des cas où l'auto-descellement ne peut pas fonctionner.

**Prérequis** : M25-E24 (grappe, VIP), M25-E03 (procédure d'initialisation et de dépôt des parts), M25-E17 (moteur `transit`).
**Durée indicative** : 3 h 30.

**Contexte technique**
- **Lecture obligatoire** : [concepts du seal](https://openbao.org/docs/concepts/seal/) (en particulier *Seal migration*), [seal `transit`](https://openbao.org/docs/configuration/seal/transit/) (paramètres, variable d'environnement du jeton, politique requise, renouvellement), [`bao operator unseal`](https://openbao.org/docs/commands/operator/unseal/) (`-migrate`).
- `kms01` : rôle Ansible **`openbao_kms`** (même installation que `openbao`, sans `retry_join`, sans keepalived, sans relais ACME : le nom `kms01.par1.medisphere.internal` n'est porté que par lui). Initialisation Shamir 5/3 selon la procédure d'E03 (parts chiffrées `age` pour les dépositaires, fichier `secrets/kms01-init.yml`), jeton racine révoqué à la fin de l'exercice. Pas de méthode d'authentification humaine sur `kms01` : son administration passe par un jeton racine **régénéré à la demande** (procédure d'E28). Or, dans les versions de référence, lancer cette régénération exige déjà un jeton (point d'accès authentifié, voir E28) : prévois, **avant** de révoquer le jeton racine de `kms01`, un jeton qui ne sait faire que cela, et dis où il est rangé.
- Clé de transit **`autodescellement-par1`** : `aes256-gcm96`, non exportable, suppression interdite. Politique **`kms-autodescellement`** : `update` sur `transit/encrypt/autodescellement-par1` et `transit/decrypt/autodescellement-par1`, rien d'autre.
- Jeton de la grappe : **orphelin**, **périodique**, sans la politique `default`, nom d'affichage parlant ; il ne passe jamais à l'écran : la sortie de `bao token create` va dans `ansible-vault` (`vault_openbao_kms_jeton`, Vault `critique`), puis dans `/etc/openbao/kms.env` par le rôle.
- Flux : `vault01-03` et la future `bao-restauration` (E26, temporaire) → `kms01` 8200 ; `kms01` n'accepte rien d'autre que MGMT (administration), `mon01` et les travailleurs (supervision, E27).

> ⚠️ **Attention** : (1) **instantané avant** (E24) et vérification des parts : la migration réécrit la clé racine ; (2) la procédure se fait **dans l'ordre** de la documentation : en attente d'abord, actif en dernier ; ne redémarre jamais deux nœuds à la fois ; (3) pendant la migration, ne touche pas à `kms01` ; (4) une fois migrée, la grappe **dépend de `kms01` pour démarrer** : `kms01` scellé ou injoignable au mauvais moment = coffre fermé (c'est l'objet de RB-251) ; (5) retour arrière tant que la migration n'est pas terminée : retirer le bloc `seal` des nœuds déjà modifiés et les redémarrer ; après : migration inverse (`disabled = "true"` sur le bloc `transit`, `unseal -migrate` avec les clés de récupération), décrite dans RB-251.

**Travail demandé**
1. **`kms01`.** VM par `plateforme/infra` (état `socle`), rôle `openbao_kms`, initialisation et descellement Shamir, moteur, clé et politique (à la main avec le jeton racine de `kms01`, consignés dans `~/m25/e25/kms01.md` : `kms01` n'est pas géré par `plateforme/secrets`, explique pourquoi). Vérifie que la clé n'est ni exportable ni supprimable.
2. **Jeton.** Crée le jeton de la grappe (TTL de la période à justifier), range-le directement dans le Vault `critique`. Vérifie ses propriétés avec `bao token lookup -accessor <ACCESSOR>` (jamais le jeton lui-même). Que se passe-t-il si sa période expire, et qui le renouvelle ?
3. **Configuration.** Ajoute au gabarit du rôle `openbao` le bloc `seal "transit"` (adresse, clé, montage, racine de confiance, nom TLS) **sans** le jeton, la surcharge systemd qui lit `/etc/openbao/kms.env`, et le fichier lui-même (600). Lis la page du seal `transit` : quel est le nom exact de la variable d'environnement qui porte le jeton, et pourquoi ne pas le mettre dans `openbao.hcl` ?
4. **Migration.** Suis la procédure officielle : chaque nœud **en attente**, l'un après l'autre (Ansible `--limit`, redémarrage, `bao operator unseal -migrate` avec trois parts **sur l'adresse du nœud**), puis passage de témoin du nœud actif et observation de la migration dans son journal, puis l'ancien actif. Note à chaque étape ce que renvoient `sys/seal-status` et `sys/health` de chaque nœud (attends-toi à des réponses déroutantes pendant la migration : explique-les).
5. **Épreuves.** (a) Redémarre les trois nœuds en même temps (`qm reboot`) : ils doivent revenir descellés **sans personne**, et la VIP doit revenir. (b) Arrête `openbao` sur `kms01`, puis redémarre `vault02` : que se passe-t-il, que dit son journal, que fait systemd au bout de quelques essais (lis `StartLimitBurst` dans l'unité) ? Remets `kms01` en service : `vault02` revient-il seul ? (c) Qu'est-ce qui change, pour la grappe **déjà descellée**, quand `kms01` est arrêté une heure ?
6. **Clés de récupération.** Vérifie que `bao status` annonce un *Recovery Seal* et que les anciennes parts n'ouvrent plus rien par `unseal`. Mets à jour `secrets/openbao-init.yml` (commentaire : « clés de récupération depuis E25 ») et la décision écrite des dépositaires.
7. **RB-251.** Rédige `docs/securite/secrets/runbooks/RB-251-descellement-et-redemarrage.md` : redémarrage normal ; nœud qui ne démarre pas parce que `kms01` est injoignable (et `systemctl reset-failed`) ; `kms01` redémarré (scellé : descellement Shamir par trois dépositaires, puis la grappe) ; perte définitive de `kms01` (ce qui est récupérable, avec quoi) ; migration inverse vers Shamir ; contacts et délais.

**Critères de réussite**
- [ ] Les trois nœuds annoncent un seal `transit` descellé avec un *recovery seal* ; `kms01` répond 200 à `sys/health`, seal Shamir, descellé.
- [ ] Sur chaque nœud, `/etc/openbao/kms.env` existe en 600, `openbao.hcl` ne contient ni jeton ni bloc `seal "shamir"`, l'unité lit `kms.env`.
- [ ] Après un redémarrage simultané des trois nœuds, ils reviennent descellés sans intervention (preuve dans ton journal de travail : heures, journaux).
- [ ] RB-251 est sur `main` de `plateforme/medisphere` et couvre les cas listés.

**Vérification** : `lab/bin/check 25 25`

<details><summary>Indice 1</summary>

Pendant la migration, un nœud en attente déjà basculé tient une configuration (`transit`) qui ne correspond pas encore au type de barrière enregistré dans les données (`shamir`) : il refuse de dire son état. C'est le nœud **actif**, au moment où il prend la main, qui réécrit la clé racine et le type de seal ; les autres le lisent ensuite par Raft.
</details>

<details><summary>Indice 2</summary>

Le jeton du seal `transit` est renouvelé par le serveur lui-même tant que le paramètre `disable_renewal` reste à sa valeur par défaut. Un jeton **périodique** sans TTL maximal reste renouvelable indéfiniment ; un jeton **orphelin** ne meurt pas quand son parent est révoqué. Il ne reste qu'un cas où il meurt : on ne l'a pas renouvelé pendant une période entière (grappe arrêtée plus longtemps que la période, par exemple).
</details>

<details><summary>Indice 3</summary>

Avec un seal `transit`, le serveur a besoin de `kms01` **au démarrage**, pour configurer le seal, avant même d'ouvrir son écouteur : si `kms01` ne répond pas, le processus s'arrête en erreur. L'unité du paquet a `Restart=on-failure`, `RestartSec=5`, `StartLimitIntervalSec=60` et `StartLimitBurst=3` : fais le calcul.
</details>

**Pour aller plus loin** (facultatif) : lis la documentation du seal `static` (clé AES fournie par fichier) et du *Seal High Availability* ; écris dans ton journal ce que chacun protégerait et ne protégerait pas dans le lab. Ces éléments serviront l'ADR-0250 (E31).

---

### M25-E26 — Instantanés chiffrés et restauration éprouvée  `LAB` `★★★`

> **Ticket SEC-2626** — *De : Sophie Laurent* — *Copie : Claire Morel*
> L'auditeur HDS revient dans six semaines. Sa première question sur le coffre sera : « montrez-moi une restauration ». Pas une sauvegarde : une restauration, chronométrée, avec la perte de données maximale et le temps de remise en service. Et je ne veux pas que la sauvegarde du coffre devienne la façon la plus simple de voler le coffre.

**Objectifs pédagogiques**
- Sauvegarder une grappe Raft par **instantané** (`bao operator raft snapshot save`) avec une identité au moindre privilège, sur le seul nœud actif, chiffré côté client, envoyé hors des nœuds.
- Comprendre ce qu'un instantané contient (données **chiffrées par la barrière**) et ce qu'il faut en plus pour le relire (clé racine → seal → `kms01`, ou clés de récupération).
- Restaurer sur une grappe neuve et isolée, mesurer **RPO** et **RTO**, et connaître les dangers d'une copie vivante du coffre.
- Distinguer instantané Raft et sauvegarde de VM (PBS) : ce que chacun permet de reconstruire.

**Prérequis** : M25-E25 (seal `transit`), M14-E24 (rôle `etcd_instantane` : modèle du script, de `age`, de `rclone` et du compartiment non effaçable), M05-E10 (identités et compartiments de `s3-01`), M00 (PBS).
**Durée indicative** : 3 h.

**Contexte technique**
- **Lecture obligatoire** : [`bao operator raft snapshot`](https://openbao.org/docs/commands/operator/raft/) (`save`, `restore`, `-force`), le [guide de sauvegarde Raft](https://openbao.org/docs/concepts/integrated-storage/) (section *snapshots*), la page [`/sys/storage/raft`](https://openbao.org/api-docs/system/storage/raft/) (capacités nécessaires).
- Il n'y a **pas** d'instantanés automatiques intégrés à OpenBao (annexe des versions du bloc F) : on les planifie soi-même.
- Script **`/usr/local/sbin/openbao-instantane`** sur les trois nœuds, lancé par **`openbao-instantane.timer`** (horaire, minute fixe, `Persistent=true`) : il ne travaille que si le nœud local est **actif** (`/v1/sys/leader`, champ `is_self`), sinon il sort en succès. Identité : AppRole **`openbao-instantanes`** (politique du même nom), `secret_id` déposé par Ansible dans `/etc/openbao/instantanes.env` (root, 600), lié aux adresses des trois nœuds ; jeton **batch** de courte durée.
- Chiffrement **age** vers la clé publique de restauration de l'équipe (privée : Vault `critique` et papier, jamais sur un nœud) ; envoi par `rclone` (fournisseur `Other`, style par chemin) vers `s3-01:8333`, compartiment **`openbao-instantanes`**, préfixe `horaire/<AAAA-MM-JJ>/`, identité **`openbao-instantanes`** (lecture, écriture, listage ; suppression refusée par la politique du compartiment ; `/etc/openbao/s3.env`, root, 600, depuis le Vault `critique`), **règle de cycle de vie 30 jours**. Trace du dernier succès dans `/var/lib/openbao-instantane/dernier-succes` et métrique pour le collecteur *textfile* de node_exporter (E27).
- Restauration d'essai : VM **`bao-restauration`** (2252, `vsandbox`, 10.10.99.52, état `envs/m25`), même rôle `openbao` sans keepalived ni `retry_join`, seal `transit` vers `kms01` avec un **jeton dédié** de courte durée ; flux **temporaire** 10.10.99.52 → `kms01` 8200 (bordure et pare-feu local), **retiré** après l'essai.
- Les VMs `vault01-03` et `kms01` sont aussi sauvegardées par PBS (stockage `pbs-par2-secrets`, espace de noms `par1/secrets`, tâche `secrets-nuit`) : à toi de dire ce que cette sauvegarde permet et ne permet pas.

> ⚠️ **Attention** : une copie **vivante** du coffre a les mêmes moteurs, les mêmes baux et les mêmes identifiants de connexion que la production. Si elle peut joindre PostgreSQL de MédiAgenda, son gestionnaire d'expiration **révoquera de vrais identifiants** (et `rotate-root` pourrait changer le mot de passe du rôle `openbao`). `bao-restauration` doit rester dans `vsandbox` **sans aucun autre flux** que vers `kms01` 8200 et depuis MGMT. Et la clé privée `age` de restauration ne doit vivre que le temps du déchiffrement, sur `adm01`, dans un fichier 600 effacé ensuite.

**Travail demandé**
1. **Lecture.** Dans ton journal : qu'y a-t-il dans un fichier d'instantané (ouvre-le : `tar -tzf`) ? Les secrets y sont-ils lisibles ? Que faut-il de plus pour qu'il serve ? Pourquoi prendre l'instantané sur le nœud actif seulement, alors qu'un nœud en attente sait le faire ? Quelle capacité, sur quel chemin, faut-il à l'AppRole ?
2. **Stockage objet.** Identité, compartiment, politique de compartiment (refus de suppression et de modification de la configuration), cycle de vie de 30 jours, essai d'écriture et de suppression refusée avec l'identité, sur le modèle du M14-E24.
3. **Rôle.** Écris le rôle **`openbao_instantane`** (script, unité durcie, minuterie, fichiers d'environnement, `OnFailure=ms-alerte@%n.service`) et l'AppRole dans `plateforme/secrets`. Le script échoue bruyamment au moindre problème (nœud scellé, connexion refusée, envoi incomplet) et ne laisse **aucune** copie claire sur le disque.
4. **Premier envoi.** Lance le service à la main sur les trois nœuds : deux sortent sans rien faire, un envoie. Vérifie l'objet (taille, en-tête `age-encryption.org/v1`) avec l'identité depuis `adm01`.
5. **PBS.** Ajoute les quatre VMs du coffre à une tâche PBS nocturne dans l'espace de noms `par1/secrets`. Que contient la sauvegarde d'une VM en attente ? Peut-on restaurer **une** VM de la grappe à partir de PBS et la laisser rejoindre ? Et les trois ?
6. **Restauration éprouvée.** Note l'heure T0, écris un secret témoin `kv/wb-essais/rpo` **après** le dernier instantané, puis : VM `bao-restauration` (OpenTofu `envs/m25`), flux temporaire, rôle `openbao`, `bao operator init` (seal `transit` : clés de récupération), téléchargement et déchiffrement de l'instantané sur `adm01`, copie sur la VM, `bao operator raft snapshot restore -force`, redémarrage. Vérifie : seal `transit` descellé, données présentes (un secret ancien lisible avec ton jeton OIDC… qui est-ce qui l'accepte ?), secret témoin **absent** (c'est ton RPO), pairs Raft. Note T1 (RTO).
7. **Nettoyage.** Destruction de `bao-restauration`, révocation du jeton dédié sur `kms01`, retrait du flux temporaire (MR), effacement de la clé privée et des fichiers clairs sur `adm01`.
8. **RB-252.** `docs/securite/secrets/runbooks/RB-252-sauvegarde-restauration-openbao.md` : ce qui est sauvegardé et où, qui détient quoi, contrôle quotidien, restauration complète (grappe neuve), restauration d'un nœud, essai trimestriel, **RPO et RTO mesurés** (valeurs, date), dangers d'une copie vivante.

**Critères de réussite**
- [ ] La minuterie est active sur les trois nœuds ; un seul nœud envoie ; le dernier objet de `openbao-instantanes` a moins de deux heures, est chiffré `age`, et l'identité ne peut pas le supprimer.
- [ ] Le compartiment porte une règle de cycle de vie de 30 jours.
- [ ] La restauration a été faite : RB-252 donne T0, T1, le RPO et le RTO mesurés ; `bao-restauration` (2252) n'existe plus et aucun flux vers `kms01` depuis `vsandbox` ne subsiste.

**Vérification** : `lab/bin/check 25 26`

<details><summary>Indice 1</summary>

`bao operator raft snapshot save` passe par l'API `sys/storage/raft/snapshot` en lecture : aucune autre capacité n'est nécessaire, et un jeton *batch* (pas de stockage côté serveur, pas de renouvellement) suffit pour une opération de quelques secondes. `rclone` peut se configurer **entièrement** par variables d'environnement `RCLONE_CONFIG_<NOM>_…` : aucun fichier de configuration avec les clés.
</details>

<details><summary>Indice 2</summary>

Une grappe neuve initialisée a sa propre clé racine et ses propres jetons ; l'instantané apporte ceux de la production. C'est pour cela que la restauration exige `-force` sur une grappe qui n'est pas celle d'origine, et que le jeton racine de la grappe neuve ne vaut plus rien une seconde après. Avec un seal `transit`, la clé racine de l'instantané reste lisible tant que la **même clé de transit** de `kms01` est joignable.
</details>

**Pour aller plus loin** (facultatif) : chronomètre la restauration d'**un** nœud perdu (VM recréée vide, `retry_join`, réplication par Raft) et compare avec la restauration complète ; écris quand tu choisirais l'une ou l'autre.

---

### M25-E27 — Superviser OpenBao  `LAB` `★★`

> **Ticket PLAT-2627** — *De : Nadia Roussel*
> Le jour où `vault02` est resté scellé toute la nuit, la supervision était verte : node_exporter disait que la VM allait bien. Je veux être réveillée si un nœud est scellé ou injoignable, s'il n'y a plus de nœud actif, si l'audit n'écrit plus (on m'a dit que dans ce cas le coffre refuse tout), si les baux explosent, si un certificat de service va expirer, et si la sauvegarde horaire n'a pas tourné.

**Objectifs pédagogiques**
- Activer la télémétrie Prometheus d'OpenBao et choisir comment l'exposer (accès non authentifié sur l'écouteur ou jeton de lecture).
- Écrire des alertes sur l'état du coffre (scellé, actif, audit, baux, instantanés) et les tester avec `promtool`.
- Superviser de l'extérieur (sonde `blackbox` depuis `mon01`) et construire un tableau de bord versionné.

**Prérequis** : M25-E24, E25, E26 ; M21-E08 (ScrapeConfig hors cluster), M21-E11 (témoin de `mon01`), M21-E14 et E16 (règles, routes), M21-E19 (tableaux versionnés).
**Durée indicative** : 2 h 30.

**Contexte technique**
- **Lecture obligatoire** : [bloc `telemetry`](https://openbao.org/docs/configuration/telemetry/) (`prometheus_retention_time`, `disable_hostname`), [paramètres de l'écouteur TCP](https://openbao.org/docs/configuration/listener/tcp/) (`telemetry` → `unauthenticated_metrics_access`), [`/sys/metrics`](https://openbao.org/api-docs/system/metrics/), la [liste des métriques](https://openbao.org/docs/internals/telemetry/metrics/).
- Les métriques d'OpenBao portent encore le préfixe historique **`vault_`** (`vault_core_unsealed`, `vault_core_active`, `vault_expire_num_leases`, `vault_audit_log_request_failure`, `vault_autopilot_healthy`…) : vérifie sur ta grappe avant d'écrire une règle (`curl …/v1/sys/metrics?format=prometheus`).
- Collecte par Prometheus du cluster (travailleurs → `vault01-03`, `kms01` 8200, flux à ouvrir à la bordure) : ScrapeConfig **`openbao`** (`jobName: openbao`), quatre cibles, étiquette `role` (`coffre`, `kms`) ; instantanés : métrique écrite par le script d'E26 pour le collecteur *textfile* de node_exporter (déjà collecté par le job `vms`).
- Règles dans **`regles/secrets.yaml`** (PrometheusRule `secrets`), tests dans `tests/secrets.test.yaml`, étiquettes d'alerte habituelles (`gravite`, `equipe`, annotations `resume`, `description`, `runbook_url` vers RB-251/RB-252) ; tableau `tableaux/plateforme/openbao.json`.
- Témoin de `mon01` : sonde de `https://openbao.par1.medisphere.internal:8200/v1/sys/health` (le nœud actif, 200) et des quatre nœuds (200 **ou** 429 acceptés : un module de sonde à toi).

**Travail demandé**
1. **Exposition.** Ajoute `telemetry` et l'accès aux métriques à la configuration (rôles `openbao` et `openbao_kms`, un nœud à la fois). Compare les deux options (sans authentification sur l'écouteur, ou jeton de lecture dans un Secret pour Prometheus) : ce que chacune expose, ce qu'elle coûte, ce qui peut fuir ; choisis et écris pourquoi dans `docs/securite/secrets/supervision.md`. Que renvoie `/v1/sys/metrics` sur un nœud **scellé** ?
2. **Collecte.** ScrapeConfig, flux, MR ; les quatre cibles `UP`.
3. **Alertes.** Les cinq de la fiche, plus une alerte sur l'âge du dernier instantané et une sur la tolérance aux pannes d'autopilot. Pour chacune : expression, durée, gravité, et **pourquoi** cette expression (piège : certaines métriques existent en deux séries par nœud ; regarde l'étiquette `cluster`). Teste-les toutes avec `promtool test rules`.
4. **Sonde extérieure.** Module et cibles dans `host_vars/mon01/supervision_temoin.yml`.
5. **Tableau.** Nœud actif, état de chaque nœud, leader Raft et index appliqués, tolérance aux pannes, baux, requêtes par seconde et latence, échecs d'audit, âge du dernier instantané, durée restante du jeton de `kms01` si tu sais l'obtenir (sinon dis pourquoi).
6. **Épreuve.** Scelle un nœud **en attente** (`bao operator seal` ne s'applique qu'au nœud actif : comment sceller un nœud en attente proprement ? essaie un arrêt du service), et vérifie que l'alerte part et arrive à l'astreinte, puis revient.

**Critères de réussite**
- [ ] Le job `openbao` a quatre cibles `up == 1` et `vault_core_unsealed` est présent pour chacune.
- [ ] Les règles de la fiche, l'alerte d'instantané et l'alerte de tolérance sont chargées ; leurs tests passent dans la CI de `plateforme/observabilite`.
- [ ] La sonde extérieure du nœud actif est verte sur le témoin ; le tableau est provisionné dans Grafana.

**Vérification** : `lab/bin/check 25 27`

<details><summary>Indice 1</summary>

`vault_core_active` et `vault_core_unsealed` sont émises avec une étiquette `cluster` qui peut être **vide** pour une partie de la vie du processus : une série vaut 0 avec `cluster=""`, une autre la vraie valeur avec le nom de la grappe. `max by (instance)` lève l'ambiguïté. Et une cible injoignable ne produit **aucune** série `vault_core_unsealed` : une alerte « scellé » doit aussi regarder `up`.
</details>

<details><summary>Indice 2</summary>

Quand l'unique dispositif d'audit ne peut plus écrire, OpenBao refuse les requêtes : `vault_audit_log_request_failure` est un **compteur** ; il ne descend jamais. Une alerte doit regarder son augmentation sur une fenêtre, pas sa valeur.
</details>

**Pour aller plus loin** (facultatif) : ajoute une alerte du ruler de Loki (locataire `audit`) sur l'usage d'un jeton portant la politique `root` (E28 dira pourquoi ce ne doit jamais arriver).

---

### M25-E28 — Durcir OpenBao : jeton racine, enveloppement, systemd, TLS  `LAB` `★★★`

> **Ticket SEC-2628** — *De : Sophie Laurent*
> Le rapport de pré-audit relève sur le coffre : « jeton racine initial retrouvé dans l'historique d'un poste d'administration (révoqué depuis, mais aucune procédure écrite pour en obtenir un nouveau) » ; « `secret_id` AppRole transmis en clair dans un fichier de variables » ; « service exécuté avec l'unité par défaut du paquet » ; « TLS 1.2 accepté » ; « aucune limite de durée de vie des baux ni de débit ». Je veux chaque point fermé, avec la preuve.

**Objectifs pédagogiques**
- Vivre **sans jeton racine** et savoir en régénérer un, à plusieurs, avec les clés de récupération, quand il le faut (et le révoquer aussitôt).
- Transmettre un `secret_id` par **enveloppement de réponse** (*response wrapping*) : usage unique, durée courte, détection d'interception.
- Durcir l'unité systemd, l'écouteur (TLS 1.3, en-têtes, points d'accès non authentifiés), les durées de vie des baux et les quotas de débit.

**Prérequis** : M25-E05 (jetons, politiques), M25-E07 (AppRole), M25-E21 (audit), M25-E25 (clés de récupération), M25-E27 (alertes) ; M26 n'est pas requis.
**Durée indicative** : 3 h.

**Contexte technique**
- **Lecture obligatoire** : [`bao operator generate-root`](https://openbao.org/docs/commands/operator/generate-root/) et [`/sys/generate-root`](https://openbao.org/api-docs/system/generate-root/) (lis l'avertissement de dépréciation et le paramètre d'écouteur `disable_unauthed_generate_root_endpoints`), [enveloppement de réponse](https://openbao.org/docs/concepts/response-wrapping/), [quotas de débit](https://openbao.org/api-docs/system/rate-limit-quotas/), [paramètres de l'écouteur TCP](https://openbao.org/docs/configuration/listener/tcp/) (`tls_min_version`, `custom_response_headers`), [paramètres globaux](https://openbao.org/docs/configuration/) (`default_lease_ttl`, `max_lease_ttl`), `man systemd.exec`.
- Dans les versions de référence (2.6.4 et 2.7.1), la génération d'un jeton racine passe par un point d'accès **authentifié** (`sys/generate-root-token/…`) ; l'ancien point non authentifié est désactivé par défaut. Il faut donc une **politique** pour lancer la procédure, en plus des clés de récupération (seuil 3) : décide qui la porte.
- Unité du paquet : `ProtectSystem=full`, `ProtectHome=read-only`, `PrivateTmp`, `PrivateDevices`, `NoNewPrivileges`, `CapabilityBoundingSet=CAP_SYSLOG`, `MemorySwapMax=0`, `StartLimitBurst=3`. Tu la complètes par la surcharge `openbao.service.d/medisphere.conf` (E25), jamais en modifiant le fichier du paquet.
- Durées de vie retenues par Sophie : baux et jetons **24 h au plus** par défaut, 12 h pour les sessions humaines OIDC, 72 h pour le montage `pki-services` ; chaque méthode d'authentification a un réglage explicite (`tune`) dans `plateforme/secrets`.
- Les `secret_id` des AppRole de machines (`medictl`, `ansible-*`, `openbao-instantanes`) sont délivrés **enveloppés** (5 min) à partir de cet exercice : seul le destinataire déballe.

> ⚠️ **Attention** : (1) un quota de débit mal réglé bloque la CI, ESO et les checks d'un coup : commence large, observe les en-têtes et le journal, resserre ensuite ; (2) l'unité durcie peut empêcher le service d'écrire (Raft, audit) : un nœud **en attente** à la fois, `bao operator raft list-peers` entre deux ; retour arrière : supprimer la surcharge, `systemctl daemon-reload`, redémarrer ; (3) la procédure `generate-root` produit un jeton **tout-puissant** : à révoquer dans la minute, jamais affiché ailleurs que dans ton terminal, la séance consignée.

**Travail demandé**
1. **Jeton racine.** Vérifie qu'aucun jeton racine n'existe plus (comment le prouver ? pense à l'audit et à l'alerte d'E27). Dans `plateforme/secrets`, donne à `plateforme-admin` (et à elle seule) les capacités de lancer et d'alimenter la génération. Puis **répète la procédure** avec trois dépositaires (simulés : trois clés de récupération déchiffrées une par une, chacune dans un terminal distinct si tu veux jouer le jeu) : OTP, nonce, parts, décodage, usage (une action précise), révocation. Écris la procédure dans `docs/securite/secrets/procedure-jeton-racine.md` (qui, quand, comment, preuves dans l'audit).
2. **Enveloppement.** Change la livraison du `secret_id` de `medictl` et de `openbao-instantanes` : Ansible (ou toi) demande un `secret_id` **enveloppé**, le destinataire le déballe. Montre ce qui se passe si quelqu'un déballe avant lui. Que voit-on dans l'audit ?
3. **Unité systemd.** Complète la surcharge : `ProtectSystem=strict` avec les seuls chemins inscriptibles nécessaires, protections du noyau, restrictions de familles d'adresses et d'appels système, limites de fichiers ouverts. Compare `systemd-analyze security openbao.service` avant et après (note les scores).
4. **Écouteur.** TLS 1.3 seulement, en-têtes de réponse (lis ceux qu'OpenBao envoie déjà avant d'en ajouter), point d'accès non authentifié de `generate-root` désactivé **explicitement**. Prouve-le avec `openssl s_client -tls1_2` et `curl -I`.
5. **Baux.** Paramètres globaux et réglages par montage d'authentification et de moteur, dans `plateforme/secrets`. Que deviennent les baux déjà émis avec une durée plus longue ?
6. **Quotas.** Un quota global large et un quota strict sur la connexion AppRole. Vérifie qu'il mord (code HTTP, en-têtes) avec une boucle de connexions fautives, puis qu'il ne gêne ni la CI ni ESO.
7. **Preuves** : un tableau des cinq points du rapport, avec la commande qui prouve chacun, dans `docs/securite/secrets/durcissement-openbao.md`.

**Critères de réussite**
- [ ] Aucune requête faite avec un jeton `root` dans l'audit depuis 24 h, et une génération de jeton racine par `sys/generate-root-token` tracée dans l'audit depuis 30 jours ; la procédure est sur `main`.
- [ ] Les `secret_id` des AppRole de machines sont délivrés enveloppés (preuve dans l'audit) ; aucun `secret_id` en clair depuis 7 jours.
- [ ] Sur chaque nœud, l'unité est en `ProtectSystem=strict` avec les protections du noyau ; TLS 1.2 est refusé ; `generate-root` non authentifié est désactivé.
- [ ] Les méthodes `approle`, `gitlab`, `k8s-par1` ont un TTL maximal explicite d'au plus 24 h, `oidc` d'au plus 12 h ; un quota de débit vise `auth/approle`.

**Vérification** : `lab/bin/check 25 28`

<details><summary>Indice 1</summary>

L'audit HMAC les jetons, mais pas les politiques : une entrée faite avec un jeton racine porte `"token_policies":["root"]` dans son bloc `auth`. Et le jeton racine initial révoqué en E08 ne réapparaît pas : un nouveau jeton racine ne peut naître que par `generate-root` (ou par `bao token create` avec un jeton racine…).
</details>

<details><summary>Indice 2</summary>

Ce qui doit pouvoir écrire : les données Raft et l'audit. Ce qui doit pouvoir être lu : la configuration, le TLS, la racine MédiSphère. Le reste du système peut être en lecture seule. `SystemCallFilter=@system-service` est un bon point de départ pour un programme Go ; vérifie le journal après le redémarrage.
</details>

<details><summary>Indice 3</summary>

Un quota de débit se déclare sur un chemin qui commence par un **montage existant** (un montage qui n'existe pas encore est refusé). S'il vise le montage entier, il s'applique à **toutes** les requêtes de ce montage, y compris celles d'OpenTofu qui lit et écrit les rôles : regarde jusqu'où le chemin peut descendre. Le code HTTP au-delà du quota te dira s'il a mordu.
</details>

**Pour aller plus loin** (facultatif) : chiffre les parts de récupération pour les dépositaires **par OpenBao lui-même** à la régénération (`-pgp-key`) et compare avec les clés `age` du palier 1 ; lis la documentation des *Control Groups* (OpenBao 2.7) : une demande de lecture approuvée par un second humain.

---

### M25-E29 — Monter de version la grappe sans coupure  `LAB` `★★`

> **Ticket CHG-2629** — *De : Karim Benali*
> OpenBao 2.7.1 corrige des failles dans l'AppRole, l'authentification Kubernetes et le journal d'audit : on y va cette semaine, et sans couper la CI ni MédiAgenda. Lis les notes de version de la 2.7 avant : j'ai vu passer « stockage `file` supprimé » et « seals cloud en greffons ». Et je veux un retour arrière écrit **avant** de commencer.

**Objectifs pédagogiques**
- Lire des notes de version et décider ce qui concerne la grappe (stockage, seal, méthodes, moteurs, comportement par défaut).
- Monter de version en **roulement** dans l'ordre qui minimise les bascules : nœuds en attente d'abord, passage de témoin, ancien actif en dernier ; puis `kms01`.
- Préparer et documenter un retour arrière réaliste (et découvrir pourquoi « réinstaller l'ancien paquet » n'en est pas un).

**Prérequis** : M25-E24 à E28.
**Durée indicative** : 2 h.

**Contexte technique**
- **Lecture obligatoire** : [notes de version 2.7.0](https://openbao.org/community/release-notes/2-7-0/) (et celles des correctives jusqu'à 2.7.1 dans l'[index](https://openbao.org/community/release-notes/)), [dépréciations](https://openbao.org/community/deprecation/), page [autopilot](https://openbao.org/docs/concepts/integrated-storage/autopilot/) (des montées de version automatisées y sont-elles décrites ?).
- Paquet et empreinte : voir les faits communs ; le rôle `openbao` télécharge le `.deb` amont et vérifie son SHA-256 (`openbao_version`, `openbao_sha256` dans `group_vars/role_coffre/openbao.yml` et `group_vars/role_kms/openbao.yml`).
- La boucle d'écriture d'E24 tourne pendant tout l'exercice ; un pipeline de CI qui lit un secret et un `ExternalSecret` à rafraîchissement court sont observés avant, pendant, après.

> ⚠️ **Attention** : (1) instantané **juste avant** (`systemctl start openbao-instantane.service` sur le nœud actif, puis contrôle de l'objet) ; (2) un nœud à la fois, et autopilot sain entre deux ; (3) `kms01` en dernier, **seul** (pendant son redémarrage, la grappe reste descellée mais aucun nœud ne pourrait redémarrer : ne touche à aucun nœud de la grappe à ce moment-là) ; et `kms01` redémarré **revient scellé** : ses trois dépositaires doivent être là.

**Travail demandé**
1. **Notes de version.** Dans `~/m25/e29/analyse.md` : chaque rupture de la 2.7 et sa conséquence pour la grappe et `kms01` (stockage, seal, méthodes d'authentification et moteurs utilisés, valeurs par défaut) ; ce qui ne nous concerne pas et pourquoi.
2. **Retour arrière.** Avant de commencer, écris-le : où est l'instantané, comment réinstaller la 2.6.4, ce qu'on fait des nœuds déjà montés. Essaie-le **en vrai** sur un nœud en attente après sa montée (réinstallation de la 2.6.4) : que dit son journal ? Conclus.
3. **Roulement.** Les deux nœuds en attente (Ansible `--limit`, un par un, version et santé vérifiées entre deux), passage de témoin, l'ancien actif. Relève la durée de la seule indisponibilité d'écriture (celle du passage de témoin).
4. **`kms01`.** Montée, descellement Shamir, vérification que la grappe peut encore redémarrer un nœud.
5. **Vérifications** après coup : versions (`sys/health`), autopilot, pipeline et ExternalSecret, alertes restées muettes (ou parties, si attendu), journaux sans erreur nouvelle.
6. **RB-253.** `docs/securite/secrets/runbooks/RB-253-montee-de-version-openbao.md` : préparation, ordre, contrôles, retour arrière (celui qui marche), durée.

**Critères de réussite**
- [ ] Les trois nœuds et `kms01` annoncent 2.7.1 ; la grappe est saine.
- [ ] RB-253 est sur `main` et décrit un retour arrière fondé sur l'instantané, avec ce que l'essai sur un nœud a montré.

**Vérification** : `lab/bin/check 25 29`

<details><summary>Indice 1</summary>

Un nœud monté de version écrit des données que l'ancienne version ne sait pas toujours relire : au redémarrage dans l'ancienne version, la lecture de certaines structures internes peut échouer **sans** empêcher le processus de tourner. Un nœud « qui démarre » n'est pas un nœud sain : lis son journal entier.
</details>

<details><summary>Indice 2</summary>

Dans quel ordre les nœuds deviennent-ils actifs pendant ton roulement ? Si tu montes l'actif en premier, un nœud **ancien** prend la main sur des données déjà touchées par la nouvelle version.
</details>

**Pour aller plus loin** (facultatif) : écris le playbook `playbooks/montee-openbao.yml` qui enchaîne le roulement (ordre calculé à partir de `sys/leader`, `serial: 1`, contrôles d'autopilot entre deux nœuds) et essaie-le à blanc (`--check`).

---

### M25-E30 — Comparer : HashiCorp Vault 2.2  `LAB` `★★`

> **Ticket PLAT-2630** — *De : Claire Morel*
> Le comité d'architecture me demande pourquoi nous n'avons pas pris « le standard », HashiCorp Vault. Je ne veux pas une opinion : monte un Vault 2.2 avec la même configuration de base que la nôtre, fais-lui faire les mêmes gestes, et dis-moi ce qui diffère, ce qui coûte et ce qui casserait si un jour nous devions changer.

**Objectifs pédagogiques**
- Installer HashiCorp Vault 2.2 depuis les binaires officiels (empreinte et signature vérifiées) sur une VM jetable, avec la configuration d'OpenBao.
- Constater les différences de licence (BUSL 1.1), de fonctions réservées à l'édition Enterprise, de configuration et d'API, et ce qu'OpenBao a ajouté de son côté.
- Vérifier la compatibilité des clients de MédiSphère (fournisseur OpenTofu `hashicorp/vault`, ESO, `community.hashi_vault`, Cosign `hashivault://`, CLI) et les chemins de migration dans les deux sens.

**Prérequis** : M25-E24 à E29.
**Durée indicative** : 2 h.

**Contexte technique**
- VM **`bao-essai`** (2251, `vsandbox`, 2 Go, état `envs/m25`), Debian 13. Vault **2.2.x** : archive `vault_<VERSION>_linux_amd64.zip` de `https://releases.hashicorp.com/vault/<VERSION>/`, fichier `vault_<VERSION>_SHA256SUMS` et sa signature (`.sig`, clé PGP publique de HashiCorp publiée sur leur site). Prends la dernière corrective de la 2.2 au moment de l'exercice.
- Même configuration que la grappe : Raft, TLS (certificat par `step ca certificate` avec le provisioner `admin` pour la durée de l'essai), écouteur 8200/8201, seal `transit` vers `kms01` avec une **clé de transit dédiée à l'essai** et **un jeton dédié de 4 h** (l'essai n'a aucune raison de pouvoir utiliser la clé de la grappe ; flux temporaire `vsandbox` → `kms01` 8200, comme en E26), audit vers un fichier.
- Flux : MGMT → `bao-essai` 8200 ; **aucun** autre flux (pas de PostgreSQL, pas de Keycloak).
- Licence : lis le texte de la BUSL 1.1 et la *Additional Use Grant* de HashiCorp/IBM ; ne conclus pas sur la conformité d'un usage sans le dire comme une lecture.

**Travail demandé**
1. **Installation.** VM par OpenTofu (`envs/m25`), binaire vérifié (empreinte **et** signature), utilisateur et unité. Démarre avec **exactement** la configuration d'un nœud OpenBao (adaptée aux chemins) : que refuse Vault ? Que corriges-tu ? (Note la différence de traitement de `disable_mlock` entre les deux.)
2. **Gestes communs.** Initialisation (seal `transit` vers `kms01` : fonctionne-t-il contre OpenBao ?), KV v2, politique, AppRole, audit (**compare** avec la façon dont OpenBao 2.6+ active l'audit), instantané Raft.
3. **Différences.** Espaces de noms (*namespaces*) dans les deux produits ; réplication ; HSM/PKCS#11 ; plugin KMS de Kubernetes ; *Control Groups* ; montages ajoutés par défaut ; ce qu'OpenBao a pris de son côté (namespaces libres, audit déclaratif, `generate-root` authentifié, PKI/transit à clés externes, ML-DSA…). Vérifie chaque affirmation sur l'une des deux instances ou sur la documentation, jamais de mémoire.
4. **Compatibilité des clients.** Avec ta configuration `plateforme/secrets` en lecture seule (`tofu plan` contre `bao-essai`) : quelles ressources le fournisseur `hashicorp/vault` sait-il appliquer ? ESO (fournisseur `vault`), `community.hashi_vault`, Cosign (`hashivault://`) : quelles différences attends-tu, et pourquoi ?
5. **Migration.** Essaie de restaurer un instantané d'OpenBao dans Vault (copie d'essai, jamais la production) : que se passe-t-il, et qu'en conclus-tu sur un retour vers Vault (ou un passage de Vault à OpenBao) ?
6. **Nettoyage.** Destruction de `bao-essai`, révocation du jeton dédié et suppression de la clé d'essai sur `kms01`, retrait du flux.
7. **Compte rendu** `docs/securite/secrets/comparatif-vault.md` : tableau (licence, fonctions, configuration, API, clients, migration, communauté et cycle de versions), ce qui coûterait un passage dans un sens ou l'autre, recommandation pour l'ADR.

**Critères de réussite**
- [ ] `comparatif-vault.md` est sur `main` et répond aux points 1 à 5 avec des constats observés (commandes et sorties résumées).
- [ ] `bao-essai` (2251) n'existe plus, aucun flux `vsandbox` → `kms01` ne subsiste, le jeton dédié est révoqué.

**Vérification** : `lab/bin/check 25 30`

<details><summary>Indice 1</summary>

Les deux produits partagent l'API d'avant le fork, mais ont divergé : certains réglages de configuration n'ont plus le même statut (obligatoire d'un côté, inconnu de l'autre), certaines opérations d'administration ont changé de chemin ou de mode (API ou fichier de configuration). Lis le journal de démarrage **entier** des deux côtés.
</details>

<details><summary>Indice 2</summary>

Un instantané Raft contient la table des montages et les données de chaque moteur, chiffrées. Que se passe-t-il si le serveur qui le relit ne connaît pas le **type** d'un montage, ou le connaît sous une autre forme ?
</details>

**Pour aller plus loin** (facultatif) : refais l'essai avec le moteur `kv` en version 1 et un moteur `transit` ; compare les montages par défaut des deux produits après `operator init`.

---

### M25-E31 — ADR : le coffre de MédiSphère et le chiffrement d'etcd  `RED` `★★`

> **Ticket PLAT-2631** — *De : Claire Morel* — *Copie : Sophie Laurent*
> Deux décisions à écrire pour le comité, avec ce qu'elles nous coûtent : le coffre lui-même (produit, topologie, seal, sauvegarde), et ce qu'on fait du chiffrement des Secrets dans etcd maintenant qu'on a un coffre — on avait écrit au M14 que la cible était « KMS v2 avec le coffre ».

**Objectifs pédagogiques**
- Rédiger deux ADR qui comparent de vraies options sur des critères pondérés par le contexte, avec les conséquences négatives et leurs actions.
- Relier les mesures et constats du palier (bascules, restauration, comparaison avec Vault) aux décisions.
- Revenir sur une décision antérieure (M14-E28, ADR-0160) quand la cible annoncée n'est pas disponible, et le dire.

**Prérequis** : M25-E24 à E30 ; M14-E28 (`docs/kubernetes/securite/chiffrement-secrets.md`), M16-E26 (KEK de la classe chiffrée), ADR-0200 (modèle).
**Durée indicative** : 1 h 30.

**Travail demandé**
1. **ADR-0250** `docs/securite/secrets/adr/ADR-0250-coffre.md` :
   - contexte (exigences HDS, souveraineté, incidents du module, contraintes du lab) ;
   - options de **produit** : OpenBao, HashiCorp Vault (édition communautaire, édition Enterprise), un coffre de nuage public (et pourquoi c'est une option à écrire même si elle est écartée), CyberArk Conjur ou Infisical (une ligne chacun, vérifiée) ;
   - options de **seal** : Shamir seul, `transit` (second OpenBao), `static` (clé sur fichier), HSM/PKCS#11 (greffon depuis la 2.7) ;
   - **topologie** (trois nœuds Raft, VIP, `kms01` à part) et ce qu'elle ne couvre pas (site PAR2, perte de `pve01`) ;
   - **sauvegarde** (instantanés, PBS, restauration éprouvée, RPO/RTO mesurés) ;
   - décision, conséquences négatives avec leur action, conditions de révision chiffrées.
2. **ADR-0251** `docs/securite/secrets/adr/ADR-0251-chiffrement-etcd.md` : relis la promesse du M14 (« KMS v2 avec OpenBao au M25 ») et de l'ADR-0160/M16 (KEK des volumes chiffrés dans un coffre) ; vérifie ce qui existe aujourd'hui (plugin KMS v2 pour OpenBao ? celui de HashiCorp ? le projet Trousseau ?) ; décide (`secretbox` conservé ou autre), écris les compensations (accès aux nœuds de contrôle, chiffrement des disques, rotation de la clé, contrôle de clair) et le **critère de réexamen** observable ; dis ce qu'il advient de la KEK de `ceph-rbd-chiffre` (fournisseurs KMS de ceph-csi : `vault`, `vaulttokens`, `vaulttenantsa` — compatibilité avec OpenBao à vérifier ou à écrire comme non vérifiée).

**Critères de réussite**
- [ ] Les deux ADR sont sur `main` de `plateforme/medisphere` (MR relue par Karim et Sophie), au format des ADR du dépôt.
- [ ] ADR-0250 compare au moins trois produits et quatre seals sur au moins six critères, cite les mesures du palier, et chaque conséquence négative a une action ou une acceptation explicite.
- [ ] ADR-0251 dit explicitement que la cible du M14 n'est pas atteinte, pourquoi, ce qui la remplace, et à quelle condition on rouvrira la décision.

**Pour aller plus loin** (facultatif) : une annexe « sortie de produit » : les étapes, la durée et le risque d'un passage d'OpenBao à Vault Enterprise (ou l'inverse), d'après les constats d'E30.

---

### M25-E32 — Questions de production : secrets  `Q` `★★★`

> *De : Sophie Laurent* — Avant de te confier les clés du coffre (au sens propre), quelques questions que je pose à tous ceux qui l'administrent. Réponds sans relire le module, puis vérifie.

1. Quel est le « secret zéro » de chacune de nos identités de machine (CI, pods, Ansible, `medictl`, instantanés, grappe → `kms01`) ? Lequel te paraît le plus fragile, et pourquoi ?
2. On tourne la clé de transit `sops-plateforme` (`rotate`). Les fichiers SOPS déjà chiffrés sont-ils encore lisibles ? Que faut-il faire pour que l'ancienne version de la clé ne serve plus à rien, et dans quel ordre ?
3. Une équipe veut des identifiants PostgreSQL dynamiques d'une durée de 30 jours « pour éviter les reconnexions ». Que réponds-tu, chiffres et risques à l'appui ?
4. Pour le futur site PAR2 (F5), compare trois façons d'avoir un coffre à PAR2 : grappe Raft étendue sur deux sites, grappe indépendante alimentée par instantanés, réplication (fonction de quel produit ?). Laquelle retiens-tu pour un RPO d'une heure ?
5. Les secrets dynamiques ont un coût. Lesquels, côté OpenBao, côté base de données et côté application ? Donne un cas où un secret statique tourné régulièrement est un meilleur choix.
6. Un HSM physique : qu'apporterait-il exactement à notre architecture (quels secrets, quelles attaques), et à quoi ressemblerait l'intégration avec OpenBao 2.7 ?
7. Séparation des pouvoirs : qui, chez MédiSphère, peut lire `kv/data/mediagenda/prod/*` ? Qui peut s'en donner le droit, et comment l'auditeur le verrait-il ? Comment rendre cela impossible pour une personne seule ?
8. L'auditeur HDS demande « qui a lu le mot de passe de la base de production le 3 mars ». Que peux-tu lui fournir, avec quelles limites (HMAC, rétention de Loki, identifiants dynamiques), et comment prouver que le journal n'a pas été modifié ?
9. `kms01` a disparu (disque perdu, pas de sauvegarde PBS utilisable). La grappe tourne encore. Quelles sont tes actions, dans l'ordre, et que se passe-t-il si un nœud redémarre avant que tu aies fini ?
10. Tu retrouves un jeton OpenBao dans les journaux d'un pod. Comment sais-tu ce qu'il permettait, depuis quand il circule, et qu'a-t-il servi à lire ? Que révoques-tu, et qu'est-ce que tu ne révoques **pas** ?
11. Pourquoi la grappe de trois nœuds ne protège-t-elle pas contre une mauvaise manipulation (`kv metadata delete`, politique effacée) ? Qu'est-ce qui le fait, avec quel délai ?
12. Un collègue propose d'augmenter la grappe à cinq nœuds « pour la sécurité ». Sur un seul hyperviseur, qu'est-ce que cela change (tolérance, latence d'écriture, mémoire, domaine de panne) ?

**Durée indicative** : 1 h.

---

### M25-E33 — Une politique de rotation automatisée  `LIBRE` `★★★`

> **Ticket SEC-2633** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Le coffre a réglé le stockage des secrets ; il n'a pas réglé leur **âge**. Les secrets des clients Keycloak ont l'âge du M24, les jetons GitLab de service ont un an, les mots de passe de comptes de service ne changent jamais. Je veux une politique écrite (quoi, tous les combien, par qui, comment on le prouve) et que tout ce qui peut tourner tout seul tourne tout seul. Ce qui ne le peut pas doit au moins me prévenir avant d'être en retard.

**Objectifs pédagogiques**
- Classer les secrets de MédiSphère par type et par risque, et fixer pour chacun une période, une méthode et une preuve.
- Automatiser des rotations de bout en bout (source → coffre → consommateurs) sans coupure, dans un pipeline planifié qui s'authentifie sans secret durable.
- Rendre l'âge de chaque secret observable et alerter avant l'échéance.

**Prérequis** : M25-E02 (inventaire des secrets), E10 (JWT de la CI), E13 (ExternalSecret), E15 (rotation sans redémarrage manuel), E21 (audit), E28 (durées de vie) ; M24 (clients Keycloak, `plateforme/identite`).
**Durée indicative** : 3 h.

**Contraintes**
- Livrables : `docs/securite/secrets/politique-rotation.md` (un tableau par type de secret : exemples réels, période, méthode, automatique ou non, propriétaire, preuve, alerte) et `docs/securite/secrets/runbooks/RB-254-rotation.md` (rotation de chaque type, à la main quand l'automate est en panne, contrôle de non-coupure, retour arrière).
- Automatisation **dans `plateforme/secrets`** : un pipeline **planifié** (au moins hebdomadaire), authentifié par jeton d'identité GitLab auprès d'OpenBao avec un rôle et une politique dédiés au plus juste, qui tourne au minimum : les secrets des clients confidentiels de Keycloak consommés par la plateforme (au moins `grafana` et `argocd`), un mot de passe de compte de service, un jeton d'accès GitLab de service. Aucun secret ne s'affiche dans les journaux du job ; le job échoue si un consommateur n'a pas repris le nouveau secret.
- **Métadonnées** : chaque secret de `kv/plateforme/` porte des métadonnées personnalisées `proprietaire` et `rotation` (période, au format des durées d'OpenBao, ex. `2160h`) ; un contrôle (dans le même pipeline) signale tout secret qui a dépassé sa période ; une alerte prévient l'équipe propriétaire.
- Les identifiants dynamiques (PostgreSQL, PKI) et les clés du coffre (transit, keyring, `kms01`) figurent dans la politique avec leur mécanisme propre ; la rotation de la clé de transit `sops-plateforme` et celle du trousseau de la barrière sont faites au moins une fois, tracées.
- Ce qui ne peut pas être automatisé (parts de récupération, clés `age` des dépositaires, racine hors ligne, clés WireGuard des passerelles, jetons Proxmox…) est listé avec sa raison, sa période et le rappel qui le déclenche.
- Toute rotation laisse une preuve dans l'audit (qui, quand, quel chemin), citée par la politique.

**Critères de réussite**
- [ ] Les deux documents sont sur `main` de `plateforme/medisphere` ; la politique couvre au moins dix types de secrets.
- [ ] Le pipeline planifié de `plateforme/secrets` a réussi dans les huit derniers jours.
- [ ] Chaque secret de `kv/plateforme/` porte `proprietaire` et `rotation`, et aucun n'a dépassé sa période.
- [ ] La rotation du trousseau et une rotation de la clé `sops-plateforme` sont tracées dans l'audit depuis 30 jours.

**Vérification** : `lab/bin/check 25 33`

---

### M25-E34 — Rotation d'urgence en temps limité  `CHRONO` `★★★`

> **Incident INC-5234** — *De : Sophie Laurent* — *Copie : Nadia Roussel, Claire Morel*
> Lucas a joint à un ticket du support la sortie d'un `kubectl describe` et d'un fichier de configuration : on y lit le **secret du client `grafana`** de Keycloak et le **mot de passe Valkey de MédiAgenda recette**. Le ticket a été lu par un prestataire. On considère les deux secrets comme compromis. Tu as **45 minutes** pour qu'ils ne servent plus à rien, sans couper Grafana ni la recette, et je veux les preuves.

**Objectifs pédagogiques**
- Appliquer RB-250 (fuite de secret) et RB-254 (rotation) sous contrainte de temps, sans coupure.
- Prouver la rotation (audit, métadonnées, consommateurs) et l'absence de coupure (supervision), et écrire un journal exploitable.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé. Tes runbooks, tes scripts, tes tableaux de bord et la documentation officielle sont permis.
- Interdits : désactiver le client `grafana`, couper l'accès de la recette « le temps de tourner », modifier un objet du cluster autrement que par Git et Argo CD (sauf l'annotation de rafraîchissement d'un `ExternalSecret`, permise), afficher l'un des nouveaux secrets.
- Durée : **45 min** entre T0 et les deux secrets tournés avec l'ancien inutilisable ; 15 min de plus pour le journal et les preuves.

**Prérequis** : paliers 1 à 3 du module, en particulier E13, E15, E21, E23 (RB-250), E33 (RB-254).
**Durée** : 1 h chronométrée + 30 minutes de retour d'expérience.

**Lancement** : `lab/bin/break 25 34` relève l'état de départ (versions des deux secrets dans le coffre, date du secret du client dans Keycloak) et affiche l'incident : c'est **T0**. `lab/bin/break 25 34 --annuler` clôt l'exercice (l'état de départ reste pour la vérification).

**Journal** : `docs/kubernetes/journal/<AAAA-MM-JJ>-M25-E34-inc-5234.md` sur `plateforme/medisphere`, rempli au fil de l'eau : heures, périmètre (qui consomme chaque secret, où il est copié), actions, preuves (audit, métadonnées, état des consommateurs), ce qui reste à faire (révocation des sessions ? autres copies ?), retour d'expérience.

**Critères de réussite**
- [ ] Le secret du client `grafana` a été régénéré dans Keycloak après T0, et l'ancien n'est plus accepté ; `kv/plateforme/grafana/oidc` a une nouvelle version écrite après T0, et l'`ExternalSecret` de Grafana s'est rafraîchi depuis.
- [ ] `kv/mediagenda/recette/valkey` a une nouvelle version écrite après T0, Valkey de la recette l'utilise, l'`ExternalSecret` correspondant s'est rafraîchi, et l'ancien mot de passe est refusé.
- [ ] Ni Grafana ni MédiAgenda recette n'ont été indisponibles plus d'une minute pendant l'exercice (sondes du témoin, erreurs 5xx de la recette).
- [ ] Le journal est sur `main` avec au moins cinq étapes horodatées et les preuves citées.

**Vérification** : `lab/bin/check 25 34` (à la fin, après le journal)

**Pour aller plus loin** (facultatif) : refais l'exercice en visant 20 minutes avec le pipeline de rotation d'E33 lancé à la demande ; écris ce qu'il faudrait pour que la rotation d'urgence d'un secret quelconque soit un seul bouton.
