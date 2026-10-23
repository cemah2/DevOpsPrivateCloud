# Final F5 — Phase 2 : Construire PAR2 — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les solutions des `LIBRE` sont **des** solutions de référence : il en existe d'autres, jugées sur les mêmes critères (indépendance vis-à-vis de PAR1, sécurité des sauvegardes, mesures).

**Fichiers** : [`fichiers/F5-S03/`](fichiers/F5-S03/) à [`fichiers/F5-S07/`](fichiers/F5-S07/), en extraits des projets : `medisphere/…` = `plateforme/medisphere`, `infra/…` = `plateforme/infra`, `ansible/…` = `plateforme/ansible`, `k8s/…` = `plateforme/k8s`, `gitops/…` = `plateforme/gitops`, `secrets/…` = `plateforme/secrets`, `mediagenda-deploiement/…` = `mediagenda/deploiement`, `copie-par2/…` = `plateforme/copie-par2` (projet nouveau). Les `*.extrait*` sont à fusionner dans le fichier existant (l'emplacement est en tête).

---

### F5-S03 — L'hyperviseur et le réseau de PAR2

**Solution**

*1. Go/no-go et retour arrière.* [RB-353](fichiers/F5-S03/medisphere/docs/pra/runbooks/RB-353-hyperviseur-par2.md) et [CHG-3503](fichiers/F5-S03/medisphere/docs/changements/fiches/CHG-3503-hyperviseur-par2.md). Le go/no-go est un script **en lecture** ([`go-no-go-hp01.sh`](fichiers/F5-S03/infra/outils/par2/go-no-go-hp01.sh)) : état de PBS (services, `ds-lab`, aucune tâche en cours, aucune en échec depuis 24 h), ressources, Debian 13 et noyau `-pve`, nom d'hôte résolu vers 10.20.10.10, port 8006 libre, sauvegarde de configuration du jour, et surtout une **simulation APT** de `proxmox-ve postfix open-iscsi chrony` : aucun paquet retiré, aucun `proxmox-backup*` touché, aucun noyau Debian. La sauvegarde de configuration ([`sauvegarder-config-pbs.sh`](fichiers/F5-S03/infra/outils/par2/sauvegarder-config-pbs.sh)) prend `/etc/proxmox-backup`, le réseau, `/etc/wireguard`, APT, chrony et la liste des paquets ; elle se relit et part **hors de `hp01`** (`~/f5/` de `adm01`).

```
root@pbs01:~# /root/f5/sauvegarder-config-pbs.sh
root@pbs01:~# /root/f5/go-no-go-hp01.sh
OK  PBS : proxmox-backup-proxy et proxmox-backup actifs
…
OK  simulation APT : aucun paquet retiré
GO (décision à reporter dans CHG-3503 avec cette sortie)
root@pbs01:~# apt-get install proxmox-ve postfix open-iscsi chrony
root@pbs01:~# pveversion && proxmox-backup-manager datastore list
```

Le retour arrière (RB-353 §8) s'appuie sur l'**historique d'APT** (`/var/log/apt/history.log`) : on purge exactement les paquets de la transaction, après simulation, puis on compare la liste des paquets à celle de l'archive. C'est écrit comme une limite : Proxmox ne documente pas ce chemin.

*2. L'hyperviseur.* Rôle [`hote_par2`](fichiers/F5-S03/ansible/roles/hote_par2/) (appliqué **après** l'installation, qu'il vérifie) : stockage `par2-vms` sur un jeu ZFS avec `quota` **et** `refquota` (ou un volume séparé préparé à la main), pool `par2`. Compte OpenTofu ([`compte-tofu-par2.sh`](fichiers/F5-S03/infra/outils/par2/compte-tofu-par2.sh)) : `wb-tofu@pve!par2`, rôle `WBTofuPar2`, ACL sur `/pool/par2`, `/storage/par2-vms`, `/sdn/zones/localnetwork/vmbr2` (droit `SDN.Use` sur le pont, exigé depuis PVE 8) et le seul template. Image dorée : sauvegarde du template `current` de `pve01` dans PBS, restauration sur `hp01` par un stockage PBS **local** en lecture (`pbs-local`, utilisateur `DatastoreReader`, clé de chiffrement de PBS), étiquettes `gold`/`debian13`/`current`.

*3. Réseau.* `vmbr2` créé par l'API réseau de Proxmox (`pvesh`, appliqué par ifupdown2 : `vmbr0`, `vmbr1` et `wg0` ne bougent pas) ; routage IPv4 ; table [`inet par2`](fichiers/F5-S03/ansible/roles/hote_par2/templates/par2.nft.j2) chargée par une **unité dédiée** (`nftables-par2.service`, `destroy table` puis définition) et **jamais** par `/etc/nftables.conf`, dont le `flush ruleset` effacerait les règles des autres. Chaîne `forward` en refus par défaut : PAR2 INFRA ↔ PAR1 par `wg0`, `wg1` → PAR2 INFRA, PAR2 INFRA → Internet sauf LAN maison, masquage vers le LAN de `hp01` ; un set `isoles` (S05) prépare l'isolement de `kms01` restauré. Côté bordure, rien à changer dans `wg0` (`gw01` accepte déjà 10.20.0.0/16) : les flux sont ajoutés à la matrice ([extrait](fichiers/F5-S03/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait-F5) ; `REG02` existe déjà pour la VM jetable du M13, d'où `REG02_PAR2`). Temps : chrony de `hp01` garde la bordure **et** des serveurs publics, et sert PAR2 INFRA (`allow`).

*4. VPN de secours.* [`wg1.conf`](fichiers/F5-S03/ansible/roles/hote_par2/templates/wg1.conf.j2) : 10.255.3.1/24, UDP 51823 ; le poste a `AllowedIPs = 10.255.3.1/32, 10.20.0.0/16`. Essai depuis le poste : `ssh admin@10.20.20.10`, puis tentative vers 10.10.20.10 → refusée (forward de `inet par2`).

*5. VMs.* [`envs/par2`](fichiers/F5-S03/infra/envs/par2/) avec un module **local** [`vm-par2`](fichiers/F5-S03/infra/envs/par2/modules/vm-par2/) : `vm-noeud` refuse les VMID 1050-1059 et 0,5 Go, écrit dans NetBox et se télécharge depuis `git01` — trois dépendances à PAR1. Catalogue des six VMs, variable `absentes` pour l'amorçage par étapes, `started`/`on_boot` ignorés après création (pilotés par les runbooks). Noms de PAR2 publiés par l'état **socle** ([`dns-par2.tf`](fichiers/F5-S03/infra/socle/dns-par2.tf), A, PTR, joker `*.apps.par2`) : écrits une fois à PAR1, transférés à `dns03`. Ansible : groupe [`site_par2`](fichiers/F5-S03/ansible/inventories/lab/hosts-site-par2.yml.extrait), [`playbooks/site-par2.yml`](fichiers/F5-S03/ansible/playbooks/site-par2.yml) avec les **rôles de PAR1** (`base`, `pare_feu_local`, `certificats_acme`, `node_exporter`, `powerdns_auth`, `powerdns_recursor`, `seaweedfs`).

*6. Amorçage de l'état* (RB-353 §5) : `backend_override.tf` local → `apply` avec `absentes = [reg02, k8s-par2-n01, bao-par2]` → Ansible sur `s3-02` (compartiment `tofu-par2` versionné, identité `tofu-par2`, [`host_vars/s3-02/seaweedfs.yml`](fichiers/F5-S03/ansible/inventories/lab/host_vars/s3-02/seaweedfs.yml)) → suppression de l'override → `tofu init -migrate-state` → `shred` de l'état local → `tofu plan` vide depuis `adm02`. Reconstruction si `s3-02` est perdu : versions de l'objet, sinon `tofu import` des VMs par leur VMID.

*7. Noms.* `dns03` secondaire de toutes les zones ([`powerdns_auth.yml`](fichiers/F5-S03/ansible/inventories/lab/host_vars/dns03/powerdns_auth.yml), même clé TSIG `axfr-par1`, NOTIFY de `dns01`) et récurseur qui relaie les zones internes à l'autoritaire **local** d'abord ([`powerdns_recursor.yml`](fichiers/F5-S03/ansible/inventories/lab/host_vars/dns03/powerdns_recursor.yml)) ; CNAME globaux à TTL 60 dans la zone parente ([extrait](fichiers/F5-S03/ansible/inventories/lab/group_vars/role_dns/powerdns_auth.yml.extrait-F5)).

**Explications**

- **Pourquoi un go/no-go en simulation** : PVE et PBS partagent une base (Debian 13, noyau Proxmox, bibliothèques `libproxmox-*`), mais leurs dépôts publient à des rythmes différents. Une simulation APT montre, avant d'agir, si une dépendance tirerait une version d'une bibliothèque que PBS n'attend pas ; c'est la seule information qui permette un « non » argumenté.
- **Pourquoi `refquota` en plus de `quota`** : `quota` compte aussi les instantanés et les enfants ; `refquota` limite l'espace référencé par le jeu lui-même. Les deux ensemble empêchent un disque de VM de remplir le pool de `ds-lab`. Une option de PVE ne suffit pas : un disque `qcow2` grossit **après** sa création.
- **Pourquoi l'état n'est pas sur `s3-01`** : le jour du sinistre, `tofu plan` à PAR2 doit fonctionner sans PAR1. Un état sur `s3-01` (ou un module sur `git01`, ou NetBox) rend `envs/par2` inutilisable précisément quand on en a besoin.
- **DNS** : un secondaire suit le primaire tant que la zone n'expire pas (SOA `expire` : 14 jours) ; promu, il sert seul. Le récurseur de `dns03` ne suit jamais la délégation `par1` (NS vers `dns01`/`dns02`, morts en PRA) parce que les zones internes sont relayées sans récursion à l'autoritaire local.

**Alternatives**
- **PBS en VM sur un PVE réinstallé** : la voie documentée par Proxmox, mais elle impose de réinstaller `hp01`, donc de déplacer ou réimporter `ds-lab` : risque bien plus grand pour les sauvegardes. Écartée.
- **Un second disque dédié à `par2-vms`** : la meilleure isolation (deux systèmes de fichiers, deux pannes indépendantes) si `hp01` a une baie libre.
- **`dns03` primaire de `par2.medisphere.internal`** : PAR2 autonome pour ses noms, au prix d'un second chemin d'écriture DNS (ADR-0350, alternatives).
- **NAT par la bordure de PAR1** (PAR2 sort par `wg0`) : rien à faire sur `hp01`, mais PAR2 perd Internet avec PAR1 : contraire à l'objectif.

**Pièges classiques**
- `apt full-upgrade` « pendant qu'on y est » sur `hp01` : PBS change de version en même temps, le retour arrière devient impossible à cerner.
- Laisser le dépôt d'entreprise de PVE actif sans abonnement : `apt update` en erreur, plus aucune mise à jour (y compris de PBS).
- `/etc/hosts` qui résout `pbs01` vers `127.0.1.1` ou l'adresse du LAN : `pve-cluster` ne démarre pas, ou l'API écoute sur la mauvaise adresse.
- Une règle `nft` ajoutée à `/etc/nftables.conf` : le `flush ruleset` du fichier standard efface tout au prochain rechargement, y compris d'autres tables.
- `forward` en acceptation par défaut : PAR2 INFRA joint le LAN maison (les photos de `hp01` y sont peut-être encore).
- Créer les VMs de PAR2 avec `vm-noeud` en contournant ses validations : NetBox à PAR1 devient une dépendance de la reprise.
- Garder l'état local d'amorçage dans le dépôt (il contient des valeurs sensibles) ou l'oublier sur `adm01`.
- Oublier que `hp01` reçoit l'heure de la bordure : en PRA, les VMs de PAR2 dérivent, puis les jetons et certificats échouent.

**En production chez MédiSphère**
Un hyperviseur de secours ne partage pas son hôte avec les sauvegardes : `hp01` porte les deux faute de budget (ADR-0350, risque accepté). La cible est un second serveur à PAR2, PBS restant seul sur `hp01`, et une copie des sauvegardes hors des deux sites (tâche *sync* de PBS vers un troisième emplacement).

---

### F5-S04 — Les données partent à PAR2

**Solution**

*1. Objets.* Le filer de `s3-01` n'écoute qu'en local (M05) : variable [`seaweedfs_ecoute_interne`](fichiers/F5-S04/ansible/roles/seaweedfs/defaults/main.yml.extrait-F5) (127.0.0.1 par défaut, 0.0.0.0 sur `s3-01`), pare-feu local qui n'ouvre 8888/18888 qu'à `s3-02`, et [`security.toml`](fichiers/F5-S04/ansible/roles/seaweedfs/templates/security.toml.j2) : TLS **mutuel** gRPC (autorité dédiée, `allowed_commonNames`) et signature des accès HTTP au filer. Sur `s3-02`, le rôle [`replication_par2`](fichiers/F5-S04/ansible/roles/replication_par2/) lance **une unité par compartiment** ([`seaweedfs-filer-sync@.service`](fichiers/F5-S04/ansible/roles/replication_par2/templates/seaweedfs-filer-sync@.service.j2) : `-isActivePassive -a.filerProxy`, `-a.path`/`-b.path` = `/buckets/<nom>`, `-a.security`/`-b.security`) pour une liste **minimale** : `cnpg-k8s-par1`, `velero-k8s-par1`, `etcd-k8s-par1`, `openbao-instantanes`, `argocd-sauvegardes`, `identite-sauvegardes`, `mariadb-legacy-rdv`, `messagerie-definitions`, `tofu-state` — pas `ci-cache`, `conformite`, `data-extractions`. Identités de PAR2 dans le `s3.json` de `s3-02` ([extrait](fichiers/F5-S04/ansible/inventories/lab/host_vars/s3-02/seaweedfs.yml.extrait-F5)) : aucune ne peut écrire à PAR1.

*2. Documents.* [`medidoc-copie.service`](fichiers/F5-S04/ansible/roles/replication_par2/templates/medidoc-copie.service.j2) et sa minuterie (15 min) : `rclone sync` du RGW (compte RGW **en lecture** `medidoc-copie-par2`) vers `medidoc-documents` de `s3-02`, compartiment **versionné** ; configuration par variables d'environnement (`RCLONE_CONFIG_<DISTANT>_<CLÉ>`), sans fichier de configuration en clair.

*3. Code.* Rôle [`miroirs_git`](fichiers/F5-S04/ansible/roles/miroirs_git/) sur `adm02` : compte `miroir` à `git-shell`, dépôts nus `/srv/miroirs/<groupe>/<projet>.git`, clés d'**écriture** (une par miroir GitLab, `restrict`) et de **lecture** (commande forcée [`miroir-lecture`](fichiers/F5-S04/ansible/roles/miroirs_git/files/miroir-lecture) : `git-upload-pack` sous `/srv/miroirs` seulement), clés lues hors du dossier du compte (`AuthorizedKeysFile` par `Match User`). Dans GitLab, pour chaque projet : *Settings → Repository → Mirroring repositories*, URL `ssh://miroir@adm02.par2.medisphere.internal/srv/miroirs/<groupe>/<projet>.git`, « Detect host keys », authentification par clé SSH publique (GitLab en génère une par miroir), « Mirror only protected branches ».

*4. Images.* Projet [`plateforme/copie-par2`](fichiers/F5-S04/copie-par2/) : pipeline planifié sur le runner **protégé** ; [`copier-images.sh`](fichiers/F5-S04/copie-par2/outils/copier-images.sh) lit dans Harbor les trois dernières versions `v*` des dépôts listés, **vérifie** chaque signature (`cosign verify --key cosign.pub --insecure-ignore-tlog=true`, comme au M13), copie par `cosign copy` (image, signatures, attestations), revérifie **sur `reg02`**, et réécrit (`--force`) l'étiquette la plus récente à chaque passage (battement de cœur mesuré sur `reg02`). `reg02` réutilise le rôle `registre_travail` du M12 ([`host_vars`](fichiers/F5-S04/ansible/inventories/lab/host_vars/reg02/registre_travail.yml)).

*5. Retard.* Mesuré **à l'arrivée** : [`pra-retards.sh`](fichiers/F5-S04/ansible/roles/replication_par2/files/pra-retards.sh) (chaque minute, âge du dernier objet par flux sur `s3-02`), [`pra-marquer-reussite`](fichiers/F5-S04/ansible/roles/replication_par2/files/pra-marquer-reussite) (dernière copie MédiDoc réussie), [`pra-miroirs.sh`](fichiers/F5-S04/ansible/roles/miroirs_git/files/pra-miroirs.sh) (écart miroir/GitLab), [âge sur `reg02`](fichiers/F5-S04/ansible/roles/supervision_temoin/files/pra-reg02-age.extrait) ; collecteur *textfile* de node_exporter, collecté par le témoin de `mon01` ; [règles](fichiers/F5-S04/ansible/roles/supervision_temoin/files/regles/pra-replication.yml) et [tests promtool](fichiers/F5-S04/ansible/roles/supervision_temoin/files/regles/pra-replication.test.yml). Mesures sur 24 h : [`retard-replication.md`](fichiers/F5-S04/medisphere/docs/pra/mesures/retard-replication.md).

*6. Copie ≠ sauvegarde.* Essai sur un compartiment `pra-essai` répliqué temporairement : l'objet supprimé à PAR1 disparaît de PAR2 en quelques secondes (`filer.sync`) ; sur `medidoc-documents` versionné, une version reste. [RB-354](fichiers/F5-S04/medisphere/docs/pra/runbooks/RB-354-replication-par2.md) : principes, diagnostic par alerte, conduite en PRA (arrêter les réplications, relever les âges, `adm02` devient la forge) et au retour (inversion temporaire, rattrapage des commits avant de réactiver les miroirs).

**Explications**

- **Actif-passif, tiré depuis PAR2** : seules les modifications de `s3-01` vont vers `s3-02`. Le processus tourne à PAR2 : PAR1 n'a aucune identité ni aucun accès vers PAR2, et la réplication s'arrête d'elle-même quand PAR1 disparaît. Avec `-a.filerProxy`, `s3-02` n'a besoin que du filer de `s3-01`, pas de ses volumes (annoncés en 127.0.0.1).
- **Une unité par compartiment** : un compartiment bloqué (droit, objet géant) n'arrête pas les autres ; la reprise au point de contrôle est par compartiment ; la liste **est** la politique de minimisation.
- **Le retard à l'arrivée** : un processus `filer.sync` actif peut ne rien copier (TLS expiré, filer de `s3-01` redémarré sur 127.0.0.1). Seul l'âge du dernier objet arrivé dit la vérité ; c'est aussi la base du RPO mesuré le jour J.
- **Les images** : la copie ne contourne pas la chaîne de confiance du M13 ; elle la **prolonge** (vérification avant et après). Les manifestes gardent `registry.par1…` : `containerd` de `k8s-par2` tire de `reg02` par miroir (S06), et les digests ne changent pas.

**Alternatives**
- **Réplication par l'API S3** (`rclone` ou `aws s3 sync` entre `s3-01` et `s3-02`) : pas de filer exposé, mais un balayage complet à chaque passage (lent sur des milliers de WAL) et un retard en minutes.
- **Synchronisation PBS** (*sync job* push de `ds-lab` vers un second datastore) : protège les **sauvegardes** (rétention, immuabilité), pas les archives continues ; complémentaire.
- **Réplication de Harbor** (règles de réplication vers un registre distant) : native, mais Harbor la réalise avec son propre compte et ne vérifie pas les signatures avec notre clé ; `reg02` devrait accepter Harbor comme source d'écriture.
- **Miroirs en tirage** depuis `adm02` (`git fetch` planifié) : `adm02` aurait besoin d'un jeton GitLab en lecture sur tous les projets ; les *push mirrors* ne donnent à PAR2 aucun accès à PAR1.

**Pièges classiques**
- Exposer le filer de `s3-01` sur le réseau **sans** TLS mutuel ni signature : n'importe quel hôte qui le joint lit et écrit toutes les données de `s3-01`, état OpenTofu compris.
- Oublier que les identités S3 ne se répliquent pas : à PAR2, `cnpg-k8s-par1` existe mais personne ne peut le lire.
- Une `retentionPolicy` sur un ObjectStore qui pointe la **copie** : le plugin efface à PAR2 ce que `filer.sync` y a copié (ou l'inverse).
- `rclone sync` vers un compartiment **non** versionné : une suppression accidentelle sur le RGW est répercutée sans retour.
- Copier « tout Harbor » : des heures de copie, des caches publics inutiles, `reg02` plein.
- Une alerte de retard sur le statut du processus (`up`) au lieu de l'âge des données.
- Activer un *push mirror* sur une branche non protégée : n'importe quel développeur pousse à PAR2.

**En production chez MédiSphère**
Les compartiments de sauvegarde de `s3-01` passent en verrouillage d'objets (F6) : une purge malveillante ne se propage plus ; un tableau « PAR2 » (retards par flux, dernier exercice, prochaine expiration de certificat) est relu chaque semaine en réunion d'exploitation ; la liste des compartiments et des projets miroités est revue avec Sophie à chaque nouveau service (minimisation HDS).

---

### F5-S05 — La confiance et les secrets hors de PAR1

**Solution**

*1. L'autorité de PAR2.* [`csr-autorite-par2.sh`](fichiers/F5-S05/ansible/outils/csr-autorite-par2.sh) **sur `adm02`** : clé EC P-256 et CSR dans un dossier en mémoire, clé chiffrée aussitôt dans `secrets/pki-par2.yml` (Ansible Vault « critique »), CSR dans `pki/`. Cérémonie sur `adm01` avec la racine hors ligne :

```
admin@adm01:~/src/ansible/pki$ step certificate inspect medisphere-par2-intermediate-ca.csr --short
admin@adm01:~/src/ansible/pki$ DUREE_INTERMEDIAIRE=26280h ceremonie-pki.sh signer medisphere-par2-intermediate-ca.csr
admin@adm01:~/src/ansible/pki$ openssl x509 -in medisphere-par2-intermediate-ca.crt -noout -subject -ext basicConstraints
admin@adm01:~/src/ansible/pki$ ceremonie-pki.sh archiver
```

Trois ans (renouvellement planifié, inférieur aux cinq ans de « Services CA » : une autorité qui vit dans un cluster de secours moins surveillé doit vivre moins longtemps), `pathlen 0`. Procès-verbal : [extrait](fichiers/F5-S05/medisphere/docs/securite/identite/ceremonie-ca.md.extrait-F5). Certificat public publié dans `docs/pra/pki/` et `pki/` ; la clé ne quitte Ansible Vault que pour l'amorçage de `k8s-par2` (S06).

*2. Le coffre de secours.* `bao-par2` dans `envs/par2` (arrêté à la création), configuré par le **rôle `openbao` du M25** ([`host_vars/bao-par2/openbao.yml`](fichiers/F5-S05/ansible/inventories/lab/host_vars/bao-par2/openbao.yml)) : nœud unique, seal `transit` vers `https://10.20.20.24:8200` avec `tls_server_name` `kms01.par1.medisphere.internal`, jeton périodique de la production (`vault_openbao_kms_jeton`). En veille : installé, **non initialisé**, arrêté.

*3. La répétition.* [`restaurer-kms01-par2.sh`](fichiers/F5-S05/infra/outils/par2/restaurer-kms01-par2.sh) et [RB-355](fichiers/F5-S05/medisphere/docs/pra/runbooks/RB-355-coffre-de-secours.md) : refus si 10.20.20.24 n'est pas dans le set `isoles` de `inet par2` ; `qmrestore … 3501 --unique 1` ; carte **coupée** (`link_down=1`) et déplacée sur `vmbr2`, `ipconfig0` changé ; premier démarrage carte coupée, adresse vérifiée par l'agent QEMU ; minuteries qui sortent neutralisées ; carte rebranchée (l'isolement de `inet par2` empêche toute sortie) ; descellement Shamir par trois gardiens ; `bao-par2` initialisé, instantané le plus récent restauré (`instantane-vers-restauration.sh` du M25, pointé vers `s3-02`), redémarré : descellé par transit. Contrôles : secret ancien présent, secret témoin écrit après l'instantané absent (RPO), validité du jeton de seal et du certificat de la copie. Remise en veille : `bao-par2` vidé et arrêté, 3501 détruite. [Compte rendu](fichiers/F5-S05/medisphere/docs/pra/mesures/repetition-coffre-2026-11-12.md).

*4. L'enveloppe.* [`enveloppe.md`](fichiers/F5-S05/medisphere/docs/pra/enveloppe.md) : douze éléments (E1 à E12) avec forme, emplacement, gardiens, usage et **vérification sans ouvrir** ; règles de séparation et de rotation ; conduite si un élément manque ; journal des ouvertures. Aucune valeur.

**Explications**

- **Pourquoi une autorité intermédiaire et pas la racine à PAR2** : la racine reste hors ligne ; l'intermédiaire de PAR2 ne signe que des certificats finaux (`pathlen 0`) et peut être révoquée sans toucher au reste. Sa clé n'a jamais existé à PAR1 : un attaquant de PAR1 ne peut pas usurper PAR2, et la perte de PAR1 ne la fait pas perdre.
- **Ce que le descellement automatique exige** : trois choses restaurées ensemble — la **même clé de transit** (dans `kms01`), un **jeton valide** sur `kms01` (jeton périodique de 168 h : il expire 168 h après son dernier renouvellement, donc ≈ 7 jours après la sauvegarde restaurée), un **certificat** de `kms01` valide au nom attendu (30 jours au plus). D'où les contrôles de RB-355 §5 et l'annexe « PRA long » de RB-350.
- **Pourquoi `bao-par2` est vide en veille** : une copie du coffre au repos à PAR2 serait chiffrée (barrière), mais sa clé racine est elle-même déchiffrable par `kms01` restauré : deux copies d'un même secret = deux surfaces d'attaque. On restaure au moment du PRA, depuis l'instantané le plus récent (meilleur RPO).
- **L'isolement en deux ceintures** : une copie de `kms01` qui joindrait PAR1 ferait des instantanés dans `s3-01`, des demandes ACME à `ca01`, des journaux dans Loki : une seconde production, invisible. La table `inet par2` (set `isoles`) la coupe de tout ce qui n'est pas PAR2 INFRA ; les minuteries neutralisées sont la seconde ceinture (le compte rendu montre qu'elle a servi).

**Alternatives**
- **Autorité de PAR2 portée par OpenBao** (`pki-par2` dans le coffre, comme « Services CA ») : émission en ligne, révocation, CRL ; mais `bao-par2` est arrêté en veille, et en PRA il est restauré **après** le besoin de certificats de la Gateway. La `ClusterIssuer` CA de cert-manager fonctionne seule.
- **Seal Shamir pour `bao-par2`** (pas de `kms01` à PAR2) : une étape de moins en PRA, mais il faudrait une **migration de seal** de la copie restaurée (sa clé racine est chiffrée par transit) : plus long et plus risqué le jour J.
- **Coffre externe** (gestionnaire de mots de passe d'entreprise) comme seule enveloppe : pratique, mais ajoute une dépendance (compte, MFA, éditeur) qui doit elle-même être dans l'enveloppe papier.

**Pièges classiques**
- Restaurer 3501 et la démarrer **carte branchée** avec son adresse d'origine 10.10.20.24 : sur un réseau qui atteint PAR1, deux `kms01` répondent à la même adresse.
- `--unique` oublié : même adresse MAC que la production.
- Croire que `link_down=1` suffit : au rebranchement, sans isolement réseau, les minuteries de la copie repartent.
- Restaurer l'instantané **sans** `-force` sur une grappe neuve (refusé) — ou **avec** `-force` sur la production par erreur (retour arrière d'une heure de tout le coffre) : le garde-fou du script du M25 refuse `vault0*` et `kms01*`.
- Un jeton de seal **créé pour l'essai** sur la copie, puis gardé dans la configuration : la copie détruite, le jeton n'existe plus le jour J.
- Écrire un identifiant de gardien **et** l'emplacement de sa part dans `enveloppe.md` public ; une valeur de secret dans le procès-verbal.
- Générer la CSR de l'autorité de PAR2 sur `adm01` « parce que c'est plus pratique ».

**En production chez MédiSphère**
L'enveloppe physique est vérifiée chaque semestre par deux personnes, dont une hors de l'équipe Plateforme ; la restauration du coffre est rejouée chaque trimestre (calendrier des tests) ; l'autorité de PAR2 a des contraintes de noms et une CRL publiée ; à terme, un HSM réseau à PAR2 remplacerait `kms01` restauré.

---

### F5-S06 — Le cluster de secours `k8s-par2`

**Solution**

*1. Le cluster.* VM `k8s-par2-n01` de `envs/par2` ; groupe [`k8s_par2`](fichiers/F5-S06/ansible/inventories/lab/group_vars/k8s_par2/) (mêmes rôles que `k8s-par1`, valeurs de site : nœud unique sans *taint*, pas de VIP, API en 6443, miroir `reg02` sans repli vers PAR1). Différences rassemblées dans [RB-356](fichiers/F5-S06/medisphere/docs/pra/runbooks/RB-356-cluster-de-secours.md) §1.

*2. Couche de base.* Helmfile, environnement [`par2`](fichiers/F5-S06/k8s/environnements/par2.yaml) ([`_communs`](fichiers/F5-S06/k8s/releases/_communs.yaml.extrait-F5)) : Cilium avec les valeurs communes **plus** [`values-par2.yaml`](fichiers/F5-S06/k8s/composants/cilium/values-par2.yaml) (`l2announcements.enabled`, BGP coupé, `k8sClientRateLimit` relevé comme le demande la documentation) ; [`lb-par2`](fichiers/F5-S06/k8s/sites/par2/reseau/lb-par2.yaml) (`CiliumLoadBalancerIPPool` 10.20.20.200-239, `CiliumL2AnnouncementPolicy` `loadBalancerIPs: true` sur `eth0`) ; [`ClusterIssuer` CA](fichiers/F5-S06/k8s/sites/par2/certificats/autorite-par2.yaml) ; [`gw-par2`](fichiers/F5-S06/k8s/sites/par2/passerelles/gw-par2.yaml) en 10.20.20.200 avec un certificat qui couvre `*.apps.par2` **et** les noms globaux ; [stockage local](fichiers/F5-S06/k8s/sites/par2/stockage/stockage-local.yaml.gotmpl) ; CloudNativePG et son plugin, ESO, Argo CD. Amorçage : [`amorcer-par2.sh`](fichiers/F5-S06/k8s/outils/amorcer-par2.sh) (autorité, identifiants des miroirs pour Argo CD, tirage `reg02`, kubeconfig [`wb-checks`](fichiers/F5-S06/k8s/sites/par2/rbac/wb-checks.yaml)).

*3. La base.* [`mediagenda-db-par2`](fichiers/F5-S06/k8s/sites/par2/mediagenda-prod/50-mediagenda-db-par2.yaml) : `bootstrap.recovery` depuis la copie de l'archive de PAR1, `replica.primary: mediagenda-db`, `replica.source: mediagenda-db`, **les deux** archives dans `externalClusters`, archivage propre dans `cnpg-k8s-par2` ; [ObjectStores](fichiers/F5-S06/k8s/sites/par2/mediagenda-prod/60-objectstores.yaml) (copie en lecture **sans** rétention, archive de PAR2 avec rétention) ; [Services](fichiers/F5-S06/k8s/sites/par2/mediagenda-prod/70-services.yaml) `mediagenda-db-rw` (ancien nom, vise le primaire de PAR2) et `mediagenda-db-par2-openbao` (10.20.20.205, pour `bao-par2` en PRA). À PAR1 (CHG-3506, fenêtre, sonde) : [`topologie-distribuee.yaml`](fichiers/F5-S06/mediagenda-deploiement/overlays/prod/topologie-distribuee.yaml) (`replica.primary` = lui-même, `source: mediagenda-db-par2`, deux `externalClusters` ajoutés) et [`objectstore-par2.yaml`](fichiers/F5-S06/mediagenda-deploiement/overlays/prod/objectstore-par2.yaml).

```
admin@adm02:~$ kubectl --context k8s-par2 cnpg status mediagenda-db-par2 -n mediagenda-prod
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-prod
```

*4. Les secrets.* [`45-secrets.yaml`](fichiers/F5-S06/k8s/sites/par2/mediagenda-prod/45-secrets.yaml) : en veille, `SecretStore` vers le coffre de **PAR1** avec la méthode **`k8s-par2`** déclarée dans [`plateforme/secrets`](fichiers/F5-S06/secrets/tofu/k8s-par2.tf) ; les Secrets existent donc à PAR2 avant le sinistre (`deletionPolicy: Retain` ; ESO ne les efface pas quand la source disparaît). En PRA : `server` repointé vers `bao-par2` (la méthode est dans l'instantané) ; identifiants **dynamiques** de la base périmés → moteur `db-mediagenda` repointé vers 10.20.20.205 (RB-356 §4).

*5. Les applications.* Overlay [`prod-par2`](fichiers/F5-S06/mediagenda-deploiement/overlays/prod-par2/kustomization.yaml) de `mediagenda/deploiement` : `resources: ../prod` plus les différences de site (base de PAR1 retirée, Pooler repointé, HPA retiré **et** Rollout à 0, Valkey à 0, route sur `gw-par2` avec les noms de PAR2 et le nom global, repère `par2`, témoin suspendu). Même modèle pour `medidoc/deploiement` (`overlays/recette-par2`), `legacy/deploiement` et `medinotif/deploiement` (`overlays/prod-par2`). Argo CD de `k8s-par2` : [racine](fichiers/F5-S06/gitops/sites/par2/racine-par2.yaml) et [ApplicationSet](fichiers/F5-S06/gitops/sites/par2/applications/applications-par2.yaml) sur les **miroirs**, synchronisation manuelle.

*6. Repère, sonde et témoin.* Sonde : rôle [`sonde_pra`](fichiers/F5-S06/ansible/roles/sonde_pra/) sur `adm02` ([script](fichiers/F5-S06/ansible/roles/sonde_pra/files/ms-sonde-pra) : une ligne `horodatage_utc,cible,code_http,latence_ms,site` par nom global toutes les 15 s, minuterie `OnUnitActiveSec=15s`, compte dédié, unité durcie, rotation hebdomadaire gardée 60 jours). Repère `par1` par un correctif de l'overlay de prod ([extrait](fichiers/F5-S06/mediagenda-deploiement/overlays/prod/kustomization.extrait-F5.yaml)), `par2` par `prod-par2`. Témoin : component [`temoin-rpo`](fichiers/F5-S06/mediagenda-deploiement/components/temoin-rpo/) (CronJob chaque minute, `praticien: "PRA-TEMOIN"`, horodatage dans `motif`, `debut` = maintenant + 10 ans à la minute, PSA `restricted`, politiques réseau) ; requête du RPO dans RB-356 §6 :

```
admin@adm02:~$ kubectl --context k8s-par2 cnpg psql mediagenda-db-par2 -n mediagenda-prod -- -d mediagenda -Atc \
    "SELECT max(cree_le), max(motif) FROM rendez_vous WHERE praticien = 'PRA-TEMOIN'"
```

**Explications**

- **Topologie distribuée** (documentation CloudNativePG 1.30, « Distributed Topology ») : chaque cluster connaît les deux archives sous les noms des clusters ; `replica.primary` désigne le primaire **pour toute la topologie**. Une bascule contrôlée rétrograde le primaire (jeton dans `.status.demotionToken`, segment `.partial` archivé), puis promeut l'autre avec `primary` **et** `promotionToken` dans la même modification : le cluster promu attend d'avoir rejoué jusqu'au jeton. Sans jeton, la promotion est immédiate et l'ancien primaire est à **reconstruire** : c'est le cas du sinistre, et le point de non-retour de RB-350.
- **Pourquoi l'archive et pas le flux** : aucune connexion réseau entre les deux bases (rien de la production n'est exposé à PAR2), un RPO de quelques minutes conforme à l'objectif ; le flux ajouterait des secondes de RPO au prix d'un Service de base exposé à travers `wg0`.
- **L2 announcements** : la Gateway obtient 10.20.20.200 du pool `lb-par2` ; Cilium répond aux requêtes ARP pour cette adresse depuis le nœud qui détient le bail (*Lease*) ; `hp01` et les VMs de PAR2, sur le même `vmbr2`, la joignent directement. Les Services en `externalTrafficPolicy: Local` sont incompatibles (documentation) : aucun à PAR2.
- **Même code** : une différence = un fichier de site ou une valeur ; ce qui n'existe qu'à PAR2 (base de secours, autorité, pool L2) est dans `sites/par2/`. Le jour où `k8s-par1` monte de version, `k8s-par2` suit par les mêmes rôles et les mêmes releases.

**Alternatives**
- **Velero de PAR1 restauré à PAR2 le jour J** au lieu d'un cluster tiède : pas de veille à entretenir, mais RTO de plusieurs heures (installation, restauration des objets, images à tirer) et pas de réplica de base : le RPO redevient celui de la dernière sauvegarde.
- **Garder le nom `mediagenda-db` à PAR2** avec `spec.replica.self` : la documentation le permet (identité de topologie différente du nom) ; aucun Service à renommer, mais deux objets de même nom dans deux clusters, source de confusion dans les runbooks.
- **Applications démarrées en veille** (site chaud) : RTO plus court, mais charge permanente sur 5 Go et risque d'écritures sur un réplica.
- **ESO toujours sur `bao-par2`** (démarré en permanence) : un coffre de plus à surveiller et à garder à jour par restaurations régulières ; incohérent avec « aucune copie du coffre au repos ».

**Pièges classiques**
- Oublier l'archive de **son propre** cluster dans `externalClusters` ou se tromper de `serverName` (celui du F1 : `mediagenda-db-prod-day0`) : le réplica ne démarre pas, ou rejoue la recette.
- Promouvoir en changeant `primary` sans jeton alors que PAR1 est vivant : deux primaires, divergence.
- Une `retentionPolicy` sur l'ObjectStore de la copie de PAR1.
- Laisser le HPA de prod à PAR2 : impossible d'être à zéro réplica (`minReplicas` ≥ 1).
- Renommer la base et oublier les Services attendus par l'application (`mediagenda-db-rw`, `mediagenda-db-pooler-rw`).
- Des sources Argo CD vers `git01` à PAR2 : le jour J, plus rien ne se synchronise.
- Le témoin qui écrit directement en SQL : il mesure la base, pas ce qu'un patient perd (l'API, le pooler, les identifiants).
- Des valeurs de PAR2 copiées-collées dans un second jeu de fichiers : à la prochaine montée de version, PAR2 diverge en silence.

**En production chez MédiSphère**
`k8s-par2` reçoit les montées de version dans la même fiche de changement que `k8s-par1` (F4), le contrôle `helmfile -e par2 diff` tourne chaque nuit, et un exercice de bascule **contrôlée** (avec jetons, PAR1 vivant) a lieu entre deux exercices de sinistre : il valide le chemin du retour.

---

### F5-S07 — Le runbook de bascule et la cellule de crise

**Solution**

Documents de référence : [RB-350](fichiers/F5-S07/medisphere/docs/pra/runbooks/RB-350-bascule-par2.md) et [`cellule-de-crise.md`](fichiers/F5-S07/medisphere/docs/pra/cellule-de-crise.md).

1. **Déclenchement** : un critère temporel et observable (PAR1 injoignable de PAR2 **et** de l'extérieur depuis 30 min, retour annoncé au-delà de 2 h ou inconnu), une autorité (Claire, suppléée par Nadia), et le calcul qui le justifie : RTO 4 h − 2 h 30 de bascule − 30 min de marge ⇒ décision au plus tard à T0 + 1 h.
2. **Vagues 0 à 6** reprises de `dependances.md`, chacune avec gestes, **condition de passage** et preuve : isoler et figer (PAR1 ne doit plus écrire ; arrêt des réplications ; âge des données), socle (DNS promu, forge sur `adm02`, sonde), secrets (RB-355), données (promotion — **point de non-retour** — et RPO), applications (ordre de la BIA), noms (CNAME, TTL, **T reprise**), mode dégradé.
3. **Si une vague échoue** : on s'arrête, on le dit, 20 min de recherche, puis décision de la pilote ; toute improvisation est tracée.
4. **Cellule de crise** : rôles et suppléants (décision ≠ clavier), canaux **indépendants de PAR1** (pont téléphonique, messagerie externe, SMS, papier), rythme (points toutes les 30 min, message aux cabinets toutes les heures), main courante INC-6109 et ce qui doit **obligatoirement** y figurer, modèles de messages, fin de crise.
5. Les deux documents sont dans le miroir de `plateforme/medisphere` sur `adm02` **et** imprimés dans l'enveloppe.

**Explications**

Un runbook de crise s'écrit pour quelqu'un de fatigué, interrompu, qui n'est peut-être pas l'auteur : une colonne de gestes, une condition de passage qui se lit sur un écran, une preuve à coller. Le travail à deux (A au clavier, B lit et coche) vient de l'aviation et du nucléaire : il divise les erreurs d'omission. La séparation entre la décision et le clavier évite qu'une personne absorbée par une commande décide seule de franchir un point de non-retour.

**Alternatives**
- **Bascule automatique** sur sonde : RTO de minutes, mais un faux positif (coupure de `wg0` seulement, PAR1 vivant) produit deux primaires ; écarté (ADR-0350).
- **Organisation ICS complète** (commandant, liaison, logistique, planification) : adaptée à une grande organisation ; à cinq, les rôles se cumulent (règle : jamais décision et clavier).
- **Runbook exécutable** (script qui enchaîne les vagues et s'arrête aux conditions) : excellent pour la répétition ; le jour J, chaque vague demande un jugement (PAR1 vraiment mort ?) que le script ne porte pas.

**Pièges classiques**
- Un critère de déclenchement qui laisse « attendre encore un peu » : le RTO se consume en hésitation.
- Une main courante sur un outil de PAR1 (wiki, GitLab, Mailpit).
- Promouvoir la base **avant** d'avoir écrit ce qu'on fait si PAR1 revient.
- Basculer les noms **avant** d'avoir vérifié l'application en direct : les patients voient les erreurs.
- Oublier de relever les âges des données **avant** de toucher à quoi que ce soit : le RPO n'est plus mesurable ensuite.
- Un observateur qui aide : il ne relève plus les heures.

**En production chez MédiSphère**
Les fiches « une page » par rôle sont plastifiées et rangées avec l'enveloppe ; le runbook est rejoué chaque semestre (exercice) et chaque trimestre sur table (lecture à voix haute avec un nouvel arrivant) ; le pont téléphonique et le groupe de messagerie externe sont testés le premier lundi de chaque mois.

---

## Points non testés en conditions réelles

Validé hors du lab (à la rédaction, 23/10/2026) : scripts `bash -n` et `shellcheck` ; fichiers YAML lisibles ; table `inet par2` rendue et vérifiée par `nft -c` ; checks du final rejoués sur les documents de référence (S01, S02, S07 : verts ; S03-S06 : parties documentaires vertes). Le reste est **à confirmer sur ton lab** (signale tes retours, ils corrigent le workbook) :

- **Proxmox VE ajouté à un PBS installé par ISO** : non documenté par Proxmox ; la simulation APT et le retour arrière par l'historique d'APT sont la méthode retenue, pas une procédure éprouvée. Vérifie aussi que l'API réseau de PVE (`pvesh create /nodes/pbs01/network`) et celle de PBS ne se gênent pas sur `/etc/network/interfaces`.
- Options `pveum`/`pvesh`/`pvesm` utilisées (`--output-format json` de `pvesm list`, `pvesh get /pools`, ACL `/sdn/zones/localnetwork/vmbr2`), `qm destroy --destroy-unreferenced-disks`, `qmrestore --unique` : à relire dans `--help` de PVE 9.2.
- **Cloud-init** d'une VM restaurée dont on change `ipconfig0` : la nouvelle adresse doit être appliquée au premier démarrage (instance différente) ; le script le **vérifie** avant de rebrancher la carte.
- `nft destroy table` exige nftables ≥ 1.0.8 et un noyau qui connaît la commande (Debian 13, noyau Proxmox 7.0 : attendu).
- **SeaweedFS** : clés exactes de `security.toml` (`allowed_commonNames`, `jwt.filer_signing.read`) pour ta version (`weed scaffold -config=security`) ; effet de la signature du filer sur la passerelle S3 et sur `weed shell` du rôle ; réplication par `filer.sync` des compartiments **versionnés** (dossiers de versions) ; option `-ip.bind` partagée par master, volume et filer.
- `rclone` : fournisseurs `Ceph` et `SeaweedFS`, `--fast-list`, `lsjson --max-age` sur des milliers de WAL (durée de la mesure).
- `cosign copy --force` qui réécrit bien l'étiquette (et donc le lien sur disque de `registry:3`) à chaque passage ; présence de `jq`, `yq` et `curl` dans l'image `outils-supply-chain` ; copie des référents OCI (SBOM du M13) par Cosign 3.1.
- **containerd 2.3** : transmission au miroir `reg02` des identifiants que le kubelet fournit pour l'hôte `registry.par1.medisphere.internal` ; sinon, rendre le tirage de `reg02` anonyme derrière le filtrage réseau, ou des `imagePullSecrets` au nom de `reg02` dans les fichiers de site.
- **CloudNativePG 1.30** : absence de redémarrage quand on ajoute `spec.replica` à un primaire existant ; archivage par le primaire désigné d'un réplica vers sa propre archive (`isWALArchiver` sur un réplica de la topologie) ; `cnpg.io/instanceRole` comme sélecteur du primaire ; Pooler vers un cluster réplica.
- **Cilium 1.20** : `k8sClientRateLimit` (valeurs de la référence), L2 sur `eth0` avec ifupdown2 côté `hp01` ; local-path-provisioner v0.0.37 appliqué par Helmfile depuis son manifeste copié (dossier de manifestes et `strategicMergePatches` de Helmfile, en particulier sur `reclaimPolicy`, champ immuable d'une StorageClass : à poser dès la première installation).
- OpenBao : jeton périodique valable ≈ 7 jours après la sauvegarde (calcul, à mesurer par `token lookup` en répétition) ; connexion d'un `SecretStore` d'ESO à un coffre restauré dont la méthode `k8s-par2` a été configurée avec l'adresse de l'API de `k8s-par2` (même à PAR1 et à PAR2 : attendu).
- PowerDNS 5 : sous-commande de `pdnsutil` qui change le type d'une zone (secondaire → native) et noms des sous-commandes de liste (RB-350 renvoie à `--help`).
- Fichiers OpenTofu (`envs/par2`, `vm-par2`, `socle/dns-par2.tf`, `secrets/tofu/k8s-par2.tf`) : **non passés à `tofu validate`** à la rédaction (pas d'OpenTofu disponible) ; attributs repris des fichiers du M05, du M25 et du module `vm-noeud`.
- Les durées, retards et mesures des documents de référence sont ceux d'un lab imaginé.
