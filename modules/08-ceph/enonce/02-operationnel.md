# Module 08 — Palier 2 : Opérationnel

Le palier 1 a monté `ceph-par1` : trois nœuds Rocky Linux 10, trois moniteurs, deux gestionnaires, neuf OSD décrits par une spécification, des pools répliqués, du bloc RBD consommé par `cephcli01`. Le cluster est sain, mais il ne rend encore qu'un service, à un seul client, avec une clé trop large, et ses données sont placées par la règle CRUSH par défaut, qui mélange SSD et HDD. Ce palier fait de `ceph-par1` un service de stockage d'entreprise : du **fichier** (CephFS, NFS), de l'**objet** (RGW et son point d'entrée haute disponibilité, comptes et quotas pour MédiDoc), du **bloc** pour un client qui ne parle pas Ceph (iSCSI) ; des accès **cephx minimaux** ; un placement **maîtrisé** (règles CRUSH par classe et par baie, codes d'effacement) ; les gestes d'exploitation courants (ajouter un nœud, remplacer un disque, surveiller la capacité). Tu termines en relisant le travail de Lucas, en écrivant le runbook de remplacement de disque et en mettant tout le cluster sous forme de code dans `plateforme/ceph`.

> **Rappels du module** (introduction) : toute nouvelle VM passe par OpenTofu (état `ceph` de `plateforme/infra`), toute configuration d'hôte par un rôle Ansible, toute nouvelle adresse et tout nouveau nom par NetBox (puis PowerDNS), tout certificat par step-ca, tout secret par Ansible Vault et le registre des secrets, tout nouveau flux traversant les passerelles par la matrice des flux (`group_vars/role_routeur/pare_feu.yml`, commune à `gw01` et `gw02` depuis M07-E24). Les commandes Ceph se lancent en root sur un nœud `_admin` (`[root@ceph01 ~]#`, `ceph-common` 20.2.3 du palier 1) ; `crushtool` (paquet `ceph-base`, absent des nœuds) se lance dans `sudo cephadm shell`. Les spécifications vivent dans `plateforme/ceph` (clone `~/src/ceph`) et passent par une MR. Les vérifications se lancent depuis `adm01`. **Aucune commande destructive** (`ceph osd purge`, `ceph orch device zap`, `ceph osd pool delete`, `ceph fs volume rm`) sans avoir vérifié deux fois la cible.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Cluster | `ceph-par1`, Ceph Tentacle 20.2.3 (cephadm, Podman), `ceph01-03` (10.10.30.51-53 / 10.10.31.51-53), MTU 9000, administration depuis `ceph01` (variable `WB_CEPH_ADMIN`) |
| Étiquettes d'hôtes cephadm | `_admin`, `mon`, `mgr`, `osd` sur `ceph01-03` (palier 1) ; ce palier ajoute `mds` (`ceph01`, `ceph02`), `rgw` (`ceph02`, `ceph03`), `nfs` (`ceph01`) |
| Client | `cephcli01` (2085, Debian 13, 10.10.30.20) : rôle `ceph_client` (E06 : `ceph-common` 18.2 de Debian, `ceph.conf` minimal, trousseaux en 600 depuis le Vault `lab`, `rbdmap`) ; clé `client.rbd-test` (profil RBD sur `rbd-test`). Un trousseau ne quitte un nœud `_admin` que par Ansible |
| CephFS (E10) | volume `cephfs`, MDS `mds.cephfs` (un actif, un en attente), groupes de sous-volumes `plateforme` et `applications` |
| RGW (E11, E12) | service `rgw.par1` (ceph02, ceph03, port 8080, réseau 10.10.30.0/24), service `ingress.rgw.par1` (haproxy + keepalived, VIP 10.10.30.200/24, port 443, statistiques sur 1967, VRID 80), nom `rgw.par1.medisphere.internal`, zone par défaut (pas de *realm*) |
| Certificat du point d'entrée S3 (E11) | step-ca, provisioner JWK dédié `ceph-ingress` (30 jours, restreint au nom `rgw.par1.medisphere.internal`), renouvelé depuis `adm01` par `ceph-cert-ingress.timer` |
| Règles CRUSH (E14) | hiérarchie `datacenter par1` → baies `par1-baie-a`, `par1-baie-b`, `par1-baie-c` → hôtes ; règles `ssd-baie` et `hdd-baie` (domaine de panne : la baie) |
| Codes d'effacement (E15) | profil `ec-21-hdd` (k=2, m=1, classe `hdd`, domaine de panne baie), pool `rbd-ec-donnees` |
| NFS (E16) | cluster NFS `par1` (NFS-Ganesha sur `ceph01`, port 2049), export `/legacy-rdv` |
| iSCSI (E17) | cible LIO sur `cephcli01` (10.10.30.20:3260), IQN `iqn.2026-10.internal.medisphere.par1:cephcli01.legacy` ; initiateur jetable `m08-initiateur` (VMID 2086, 10.10.30.21) |
| Quatrième nœud (E18, E19) | `ceph04` (2084, 10.10.30.54 / 10.10.31.54), baie `par1-baie-a` ; conservé jusqu'au mini-projet |
| Documentation | `plateforme/medisphere` : `docs/stockage/` (runbooks `docs/stockage/runbooks/RB-08N-*.md`) ; projet `plateforme/ceph` (E23) ; brouillons dans `~/m08/eXX/` sur `adm01` |

Durée indicative du palier : 22 à 28 heures. Ordre conseillé :

```
E10 ─┬─ E16
     │
E11 ─ E12
E13 (dès E10 fait)
E14 ─ E15 ─ E17
E18 ─ E19 ─ E22
E20
E21 (quand tu veux, idéalement après E14)
E23 (en dernier : il reprend tout)
```

---

### M08-E10 — CephFS : volumes, sous-volumes et clients  `LAB` `★★`

> **Ticket PLAT-920** — *De : Nadia Roussel*
> Les scripts d'astreinte, les exports de diagnostic et les sauvegardes de configuration traînent dans des dossiers personnels sur `adm01` et sur le vieux NAS d'InfoGér. Il me faut un espace partagé, monté au même endroit sur les machines d'administration, avec une taille plafonnée (10 Gio pour commencer), des instantanés pour revenir en arrière quand quelqu'un écrase un script, et un accès qui ne permette pas de lire autre chose que ce dossier.

**Objectifs pédagogiques**
- Comprendre ce qu'apporte le MDS à un système de fichiers distribué (métadonnées, capacités, sessions client).
- Créer un volume CephFS par l'interface `volumes` du gestionnaire, et y découper des groupes de sous-volumes et des sous-volumes avec quota.
- Donner à un client un accès restreint à un chemin, monter le système de fichiers avec le pilote noyau, durablement.
- Utiliser les instantanés d'un sous-volume.

**Prérequis** : M08-E05 (pools répliqués), M08-E06 (`cephcli01` client du cluster).
**Durée indicative** : 2 h.

**Contexte technique**
- Les MDS tournent sur les hôtes portant l'étiquette `mds` (`ceph01`, `ceph02`) : deux démons, un actif et un en attente. Ajoute l'étiquette avant de créer le volume.
- Volume : `cephfs`. Groupes de sous-volumes : `plateforme` (ce ticket) et `applications` (E16). Sous-volume : `outillage` dans `plateforme`, 10 Gio.
- Client : `client.outillage`, droits **en lecture-écriture sur le seul sous-volume**. Sa clé va dans le Vault `lab` (`vault_ceph_cle_outillage`, `group_vars/role_ceph_client/vault-lab.yml`) et arrive sur `cephcli01` par le rôle `ceph_client` : `/etc/ceph/ceph.client.outillage.keyring` et `/etc/ceph/outillage.secret` (la clé seule, pour `mount.ceph`), `root`, 600.
- Point de montage : `/mnt/outillage` sur `cephcli01`, monté au démarrage. Le rôle `ceph_client` d'E06 ne sait monter que des images RBD (`noauto`, montées par `rbdmap`) : tu l'étends (variable de montages CephFS, scénario Molecule mis à jour). Debian 13 (noyau 6.12) fournit le pilote `ceph` ; l'assistant `mount.ceph` vient de `ceph-common`.
- Mémoire : un MDS consomme de 300 Mo à 1 Go selon son cache (`mds_cache_memory_limit`, 4 Gio par défaut). Sur des nœuds de 6 Go, tu le limiteras à 512 Mio.

**Travail demandé**
1. Lis la page *CephFS → Mount CephFS: Prerequisites* et *FS volumes and subvolumes* de la documentation Tentacle. Note dans ton journal (`~/m08/e10/journal.md`) : que fait `ceph fs volume create` de plus que `ceph fs new` ? Que contient un sous-volume sur disque (chemin réel) et pourquoi ce chemin n'est-il pas `/plateforme/outillage` ?
2. Ajoute l'étiquette `mds` à `ceph01` et `ceph02` dans `specs/hosts.yaml` (MR, puis application), plafonne le cache des MDS à 512 Mio dans la configuration centralisée, puis crée le volume `cephfs` avec un placement qui utilise cette étiquette. Observe les pools créés, leur règle CRUSH et le service `mds.cephfs` (`ceph fs status`, `ceph orch ls mds`) ; exporte sa spécification dans `specs/mds.yaml` (MR).
3. Crée les groupes de sous-volumes `plateforme` et `applications`, puis le sous-volume `outillage` (10 Gio) dans `plateforme`. Récupère son chemin.
4. Crée `client.outillage` avec un accès en lecture-écriture au seul sous-volume. Lis ses capacités (`ceph auth get`) et explique chaque ligne. Range sa clé dans le Vault `lab` sans qu'elle passe par l'écran, un fichier en clair ou une ligne de commande (même méthode qu'en E06 ; fais-en un petit outil réutilisable, `outils/ajouter-cle-ceph.sh` dans `plateforme/ansible` : tu t'en resserviras en E13 et E17).
5. Essaie d'abord le montage à la main sur `cephcli01`, avec la syntaxe de périphérique « v2 » (`<utilisateur>@<fsid>.<fs>=<chemin>`) et une copie temporaire de la clé (effacée ensuite). Puis étends le rôle `ceph_client` : fichier de clé seule, entrée `/etc/fstab` permanente (pense au réseau au démarrage), montage ; scénario Molecule, MR, playbook `ceph-clients.yml`. Redémarre `cephcli01` et vérifie.
6. Prouve les limites : depuis `cephcli01`, tente de monter la racine du volume avec `client.outillage` ; réduis temporairement le quota du sous-volume à 1 Gio et écris 1,2 Gio ; remets 10 Gio. Note les messages obtenus.
7. Instantanés : crée l'instantané `avant-essai` du sous-volume, modifie un fichier, puis récupère sa version précédente depuis le répertoire `.snap` côté client. Liste les instantanés côté cluster.
8. Bascule : arrête le MDS actif (`ceph orch daemon stop mds.cephfs.<HÔTE>.<ID>`), mesure combien de temps une écriture reste bloquée sur `cephcli01`, puis relance le démon. Note ce que montre `ceph fs status` pendant la bascule.

**Critères de réussite**
- [ ] Le volume `cephfs` existe, avec un MDS actif et au moins un en attente, sur les hôtes étiquetés `mds`.
- [ ] Le sous-volume `outillage` (groupe `plateforme`) a un quota de 10 Gio ; le groupe `applications` existe.
- [ ] `client.outillage` n'a de droits MDS que sur le chemin du sous-volume ; sa clé est sur `cephcli01` en 600, et aucune clé n'apparaît dans `/etc/fstab`.
- [ ] `/mnt/outillage` est monté en `ceph` sur `cephcli01` et le reste après un redémarrage.
- [ ] Au moins un instantané du sous-volume existe ; le journal répond aux questions des étapes 1, 4, 6 et 8.

**Vérification** : `lab/bin/check 08 10`

<details><summary>Indice 1</summary>

`ceph fs volume create` accepte un placement au format de l'orchestrateur (« `label:mds count:2` », entre guillemets). Le paramètre de cache se règle pour la section `mds` de la configuration centralisée (`ceph config set mds …`), pas dans un fichier.
</details>

<details><summary>Indice 2</summary>

Le sous-volume sait donner un accès à un client : regarde `ceph fs subvolume authorize` et compare avec `ceph fs authorize`. Pour la clé, `ceph auth get-key` écrit sur la sortie standard : à travers `ssh`, elle peut alimenter directement `ansible-vault` (qui lit l'entrée standard avec le nom de fichier `-`). Pour ajouter une variable à un fichier déjà chiffré : `ansible-vault view`, plus la nouvelle ligne, renvoyés ensemble dans `ansible-vault encrypt --output`.
</details>

<details><summary>Indice 3</summary>

Dans `/etc/fstab`, le « périphérique » est la chaîne v2 ; `mount.ceph` lit `/etc/ceph/ceph.conf` pour trouver les moniteurs (et le `fsid` si tu écris un point seul avant le nom du système de fichiers ; le rôle connaît le `fsid`, autant l'écrire). Options utiles : `secretfile=`, `_netdev`, `noatime`, `ms_mode=`. Le module `ansible.posix.mount` avec `state: mounted` écrit l'entrée **et** monte.
</details>

**Pour aller plus loin** (facultatif) : lis *CephFS → Snapshot schedules* (`ceph fs snap-schedule`) et programme un instantané quotidien gardé 7 jours ; lis ce que fait `allow_standby_replay` et mesure de nouveau la durée de bascule.

---

### M08-E11 — RGW : la passerelle S3 et son point d'entrée  `LAB` `★★`

> **Ticket PLAT-921** — *De : Claire Morel*
> MédiDoc stocke aujourd'hui les documents patients sur le S3 du socle (`s3-01`), une seule VM. L'ADR de fin de module dira si l'on bascule sur Ceph, mais pour décider il nous faut un S3 Ceph **réel** : deux passerelles, un point d'entrée unique qui survit à la perte d'un nœud, en HTTPS avec un certificat de notre PKI, sous un nom stable. Et que le certificat se renouvelle sans que quelqu'un y pense.

**Objectifs pédagogiques**
- Déployer des démons RGW par une spécification cephadm, et comprendre les pools qu'ils créent.
- Publier RGW derrière le service `ingress` de cephadm (haproxy + keepalived) avec une adresse virtuelle.
- Obtenir un certificat de la PKI interne pour un service qui ne peut pas répondre à un défi ACME, et automatiser son renouvellement.
- Déclarer l'adresse et le nom par la source de vérité.

**Prérequis** : M08-E05, M06-E15 (DNS généré depuis NetBox), M06-E18 et M06-E27 (certificats, politique de durées), M07 (keepalived, matrice des flux v2).
**Durée indicative** : 3 h.

**Contexte technique**
- RGW : service `rgw.par1`, hôtes étiquetés `rgw` (`ceph02`, `ceph03`), port **8080** en HTTP, lié au réseau public 10.10.30.0/24. Le chiffrement est porté par le point d'entrée.
- Point d'entrée : service `ingress.rgw.par1` sur les mêmes hôtes, VIP **10.10.30.200/24**, port 443, statistiques haproxy sur 1967, VRID keepalived **80** (les passerelles utilisent 30 sur ce VLAN : deux routeurs virtuels d'un même segment doivent avoir des VRID distincts).
- Nom : `rgw.par1.medisphere.internal`. L'adresse 10.10.30.200 est à créer dans NetBox (rôle VIP, `dns_name`), puis publiée par la génération DNS de M06-E15 (`medictl dns sync`).
- Pourquoi pas ACME : haproxy est déployé et configuré par cephadm ; il ne sait pas répondre à un défi HTTP-01, et rien n'écoute sur le port 80 de la VIP. La politique de certification (M06-E33) n'autorise par ailleurs que 7 jours au provisioner `admin`. Décision de Karim : un provisioner **JWK dédié** `ceph-ingress`, 30 jours au plus, restreint au seul nom `rgw.par1.medisphere.internal` par une politique de provisioner, son mot de passe dans le Vault `critique` et dans `~/.config/workbook/step-ceph-ingress.pass` (600) sur `adm01`. Le renouvellement se fait par le certificat lui-même (`step ca renew`, TLS mutuel) : aucun mot de passe n'est nécessaire tant que le certificat n'a pas expiré.
- Le service `ingress` lit le certificat **et** la clé dans sa spécification (`ssl_cert`, `ssl_key`). La spécification versionnée ne contient donc jamais ces blocs : ils sont ajoutés au moment d'appliquer. Clé et certificat en cours sont conservés sur `adm01` dans `~/.config/workbook/ceph-ingress/` (700).
- Flux : `adm01` joint le VLAN 30 (MGMT joint tout) ; `cephcli01` est sur le VLAN 30 ; `runner01` (tests de la CI de MédiDoc) doit joindre la VIP en TCP 443 : flux à ajouter.

**Travail demandé**
1. Lis *Cephadm → Services → RGW Service* (sections *Deploy RGWs*, *High availability service for RGW*). Note dans ton journal : quels pools RGW crée-t-il au premier démarrage ? Quel démon porte la VIP, et comment l'autre sait-il qu'il doit la reprendre ? Pourquoi la documentation conseille-t-elle trois démons et trois hôtes d'*ingress*, et que perds-tu avec deux ?
2. Ajoute l'étiquette `rgw` dans `specs/hosts.yaml` et écris `specs/rgw.yaml` (service `rgw.par1`) dans `~/src/ceph` ; MR relue. Après fusion, applique depuis `ceph01` (ou `ssh ceph01 sudo ceph orch apply -i - < fichier`) d'abord avec `--dry-run`, puis pour de bon. Vérifie que chaque démon répond sur `http://<nœud>:8080` depuis `cephcli01`, et liste les pools créés.
3. Dans NetBox, crée l'adresse 10.10.30.200/24 (rôle VIP, `dns_name` `rgw.par1.medisphere.internal`, description). Attends (ou lance) la génération DNS et vérifie A et PTR.
4. PKI : ajoute le provisioner `ceph-ingress` par le rôle `step_ca` (`group_vars/role_pki/step_ca.yml`), avec ses durées et une politique qui n'autorise que le nom du point d'entrée. Clé créée sur `adm01` (`step crypto jwk create`), partie privée chiffrée dans le Vault `critique`, inscrite au registre des secrets. Pipeline de `plateforme/ansible`, puis `step ca provisioner list`. Prouve la restriction : une demande pour `essai.par1.medisphere.internal` avec ce provisioner doit être refusée.
5. Émets le certificat dans `~/.config/workbook/ceph-ingress/` (chaîne complète : certificat + intermédiaire).
6. Écris `specs/ingress.yaml` **sans** certificat, puis un script `outils/cert-ingress.sh` (dans `plateforme/ceph`) qui lui ajoute `ssl_cert` et `ssl_key` à la volée et l'applique sur `ceph01` **sans écrire la clé sur le disque de `ceph01`**. MR, puis application.
7. Contrôle depuis `adm01` et `cephcli01` : `curl https://rgw.par1.medisphere.internal/` (sans option de contournement TLS) répond ; `openssl s_client` montre l'émetteur et la durée. Repère quel nœud porte la VIP.
8. Bascule : sur le nœud qui porte la VIP, arrête le démon haproxy du service (`ceph orch daemon stop haproxy.rgw.par1.<HÔTE>.<ID>`). Mesure, depuis `cephcli01`, l'interruption avec une boucle de requêtes. Relance.
9. Renouvellement : transforme le script de l'étape 6 en outil idempotent (renouvelle à 15 jours de l'échéance, réapplique seulement si le certificat a changé), et planifie-le sur `adm01` par une minuterie systemd quotidienne `ceph-cert-ingress.timer`, reliée à `ms-alerte@` en cas d'échec. Simule un renouvellement (`--force`) et vérifie que haproxy présente le nouveau numéro de série.
10. Flux : ajoute `runner01` → 10.10.30.200 TCP 443 à la matrice des flux par MR (et la matrice documentaire). Teste depuis `runner01`.

**Critères de réussite**
- [ ] `rgw.par1` tourne avec deux démons (ceph02, ceph03) ; `ingress.rgw.par1` avec deux haproxy et deux keepalived ; VRID 80.
- [ ] `rgw.par1.medisphere.internal` se résout en 10.10.30.200 (et inversement), à partir de NetBox.
- [ ] `https://rgw.par1.medisphere.internal/` répond depuis `adm01`, `cephcli01` et `runner01` avec un certificat de « MédiSphère Intermediate CA », valable 30 jours au plus.
- [ ] Le provisioner `ceph-ingress` existe et refuse un autre nom ; sa clé est dans le Vault et au registre des secrets.
- [ ] La minuterie `ceph-cert-ingress.timer` est active sur `adm01` ; aucune clé privée n'est dans un dépôt.
- [ ] La perte du haproxy actif interrompt le service moins de 10 secondes (mesure dans le journal).

**Vérification** : `lab/bin/check 08 11`

<details><summary>Indice 1</summary>

Dans une spécification RGW, `networks:` dit sur quel réseau le démon écoute et `spec.rgw_frontend_port` sur quel port. Dans celle d'*ingress*, `backend_service` vaut le nom complet du service RGW (`rgw.par1`), `virtual_ip` porte le masque (`/24`) : c'est lui qui permet à cephadm de choisir l'interface qui a déjà une adresse dans ce réseau.
</details>

<details><summary>Indice 2</summary>

Une politique de provisioner step-ca se déclare dans `ca.json`, dans l'objet du provisioner : `policy.x509.allow.dns`. Le rôle `step_ca` écrit la liste `step_ca_provisioners` telle quelle. Le mot de passe du provisioner se passe à `step` par `--provisioner-password-file`.
</details>

<details><summary>Indice 3</summary>

`ceph orch apply -i -` lit la spécification sur l'entrée standard, et `ssh` transmet la sienne : `yq` sur `adm01` assemble le YAML (`load_str`), `ssh ceph01 sudo ceph orch apply -i -` l'applique. `step certificate needs-renewal` dit s'il est temps de renouveler (code de sortie).
</details>

**Pour aller plus loin** (facultatif) : lis la page *Certificate Management* (`ceph orch certmgr cert ls`) : comment cephadm surveille-t-il un certificat qu'il n'a pas émis ? Et la section *Setting up HTTPS* de RGW : que changerait un chiffrement de bout en bout (haproxy → RGW en HTTPS) ?

---

### M08-E12 — RGW : comptes, utilisateurs, quotas et politiques  `LAB` `★★★`

> **Ticket DEV-922** — *De : Claire Morel* — *Copie : Sophie Laurent*
> L'équipe MédiDoc veut essayer le S3 de Ceph avec de vraies règles. Ce qu'elle demande : un espace à elle qu'elle administre elle-même (créer ses clés, ses utilisateurs applicatifs), deux compartiments (`medidoc-documents`, versionné, et `medidoc-journaux`), une application qui ne touche qu'aux documents, un compte de lecture pour l'audit. Ce que Sophie exige : un plafond global de 20 Gio, aucune clé « superutilisateur » dans les mains de l'application, et que la suppression d'un document soit récupérable.

**Objectifs pédagogiques**
- Utiliser les **comptes** RGW (*user accounts*, Tentacle) et leur utilisateur racine, et comprendre ce qui remplace l'IAM au niveau *tenant* (déprécié).
- Créer des utilisateurs IAM et leur donner des politiques d'identité minimales ; écrire une politique de compartiment.
- Poser des quotas au niveau du compte et des compartiments ; activer le versionnage.

**Prérequis** : M08-E11.
**Durée indicative** : 3 h.

**Contexte technique**
- Compte : nom `medidoc`, courriel `medidoc@medisphere.internal`. Utilisateur racine `medidoc-racine` (identifiant RGW), réservé à l'administration du compte.
- Utilisateurs IAM du compte : `medidoc-app` (lecture et écriture d'objets dans `medidoc-documents` seulement) et `medidoc-audit` (liste et lecture dans les deux compartiments).
- Quotas : compte 20 Gio ; chaque compartiment 1 000 000 d'objets au plus.
- Clients : `aws` (AWS CLI v2, paquet Debian 13) sur `adm01` et `cephcli01`, adressage par chemin (`addressing_style = path`), point d'accès `https://rgw.par1.medisphere.internal`. Comme pour `s3-01` (M05), `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` évite des sommes de contrôle que tous les serveurs S3 n'acceptent pas : vérifie si c'est encore utile avec RGW 20.2.
- Secrets : les clés de `medidoc-racine` vont dans le Vault `critique` ; celles de `medidoc-app` et `medidoc-audit` dans le Vault `lab` et, pour les essais et les vérifications, dans `~/.config/workbook/s3-medidoc-app.env` et `s3-medidoc-audit.env` (600, variables `AWS_ACCESS_KEY_ID` et `AWS_SECRET_ACCESS_KEY`). Toutes au registre des secrets.

**Travail demandé**
1. Lis *Object Gateway → User Accounts* et *IAM API*. Réponds dans ton journal : à qui appartiennent les compartiments créés par un utilisateur d'un compte ? Sur quoi portent les quotas ? Pourquoi un utilisateur IAM nouvellement créé ne peut-il **rien** faire ?
2. Avec `radosgw-admin` (sur `ceph01`), crée le compte et son utilisateur racine. Note l'identifiant du compte (`RGW` + 17 chiffres). Pose les quotas du compte et des compartiments, et active-les.
3. Configure un profil `aws` pour l'utilisateur racine sur `adm01` (les clés ne passent ni sur la ligne de commande ni dans l'historique). Avec ce profil : crée les deux compartiments, active le versionnage de `medidoc-documents`, crée les deux utilisateurs IAM, leurs clés, et leurs politiques d'identité.
4. Écris une politique de compartiment sur `medidoc-documents` qui refuse la suppression **définitive** d'une version d'objet (`s3:DeleteObjectVersion`) à tout le monde sauf l'utilisateur racine du compte.
5. Essais (notes dans le journal) avec `medidoc-app` : envoi, lecture, suppression d'un objet dans `medidoc-documents`, puis restauration de la version précédente ; liste de `medidoc-journaux` ; création d'un compartiment. Avec `medidoc-audit` : lecture, envoi. Chaque refus doit être un `AccessDenied` que tu sais expliquer.
6. Remplis le compte jusqu'au quota avec des objets de test (réduis d'abord temporairement le quota du compte à 50 Mio) : quel code renvoie RGW ? Rétablis 20 Gio et supprime les objets de test (et leurs versions).
7. Explique dans ton journal ce que tu aurais fait sans les comptes (utilisateur RGW classique, *tenant*), et pourquoi Tentacle déprécie l'IAM au niveau *tenant*.

**Critères de réussite**
- [ ] Le compte `medidoc` existe avec un quota de 20 Gio et un quota de compartiment de 1 000 000 d'objets, actifs.
- [ ] Il contient l'utilisateur racine et les utilisateurs IAM `medidoc-app` et `medidoc-audit` ; les deux compartiments appartiennent au compte ; `medidoc-documents` est versionné.
- [ ] `medidoc-app` lit `medidoc-documents` et se voit refuser la liste de `medidoc-journaux`.
- [ ] Les fichiers `s3-medidoc-*.env` sont en 600 ; les clés figurent au registre des secrets ; aucun objet de test ne reste.

**Vérification** : `lab/bin/check 08 12`

<details><summary>Indice 1</summary>

`radosgw-admin account create`, puis `radosgw-admin user create … --account-id <ID> --account-root` ; les quotas : `radosgw-admin quota set --quota-scope=account|bucket --account-id …` puis `quota enable`. Le profil `aws` se configure avec `aws configure --profile …` (saisie interactive) et `aws configure set … endpoint_url`.
</details>

<details><summary>Indice 2</summary>

Les ARN d'un compte RGW ont la forme `arn:aws:iam::<ID-COMPTE>:user/<nom>`, et ceux des compartiments `arn:aws:s3:::<compartiment>` et `arn:aws:s3:::<compartiment>/*`. Une liste d'objets (`s3:ListBucket`) porte sur le compartiment, une lecture (`s3:GetObject`) sur les objets.
</details>

<details><summary>Indice 3</summary>

Dans un compartiment versionné, `aws s3 rm` pose un **marqueur de suppression** ; la version précédente reste, et `aws s3api list-object-versions` la montre. La supprimer pour de bon demande `delete-object --version-id`. Pour vider le compartiment de test, il faut supprimer versions **et** marqueurs.
</details>

**Pour aller plus loin** (facultatif) : ajoute une règle de cycle de vie (`put-bucket-lifecycle-configuration`) qui expire les versions non courantes après 30 jours ; lis *Object Lock* et dis si MédiDoc en a besoin pour la conformité HDS.

---

### M08-E13 — Cephx : des clients aux droits minimaux  `LAB` `★★`

> **Ticket SEC-923** — *De : Sophie Laurent*
> Au palier 1, `cephcli01` a reçu une clé limitée à un pool : bien. Depuis, il y a des clés pour CephFS, pour RGW, pour NFS, et je ne sais plus qui détient quoi. Je veux l'inventaire de **toutes** les clés du cluster avec la justification de chacune ; une clé cliente qui ne fonctionne que depuis la machine prévue (si on la vole, elle ne sert à rien ailleurs) ; une clé en **lecture seule** pour les sauvegardes qui arrivent ; et une procédure pour changer une clé sans arrêter le client.

**Objectifs pédagogiques**
- Lire et écrire des capacités cephx (`mon`, `osd`, `mgr`, `mds`), utiliser les profils (`profile rbd`, `profile rbd-read-only`) et les restrictions par pool, espace de noms et réseau.
- Auditer les clés d'un cluster, distinguer clés de démons et clés clientes, repérer les excès.
- Modifier les capacités d'une clé en service, et faire tourner une clé (`ceph auth rotate`) en mesurant l'effet sur un client.

**Prérequis** : M08-E06 (`client.rbd-test`, rôle `ceph_client`), M08-E10 (`outils/ajouter-cle-ceph.sh`).
**Durée indicative** : 2 h.

**Contexte technique**
- `client.rbd-test` (E06) : profils RBD sur `rbd-test`. À restreindre à **10.10.30.20/32** (adresse de `cephcli01`) sans changer sa clé.
- Nouvelle clé `client.rbd-lecture` : lecture seule des images de `rbd-test` (sauvegardes du palier 3), déposée sur `cephcli01` par le rôle `ceph_client` (Vault `lab`, `vault_ceph_cle_rbd_lecture`).
- `client.admin` n'existe que sur les nœuds `_admin` ; le rôle `ceph_client` refuse de la déposer ailleurs (E06).
- Registre des secrets : chaque clé cliente y figure (nom, usage, capacités, emplacement, propriétaire, rotation).

**Travail demandé**
1. Inventaire : liste toutes les entités de `ceph auth ls` et classe-les dans ton journal (`~/m08/e13/journal.md`) en trois groupes : démons (créées et rangées par cephadm), amorçage, clients. Pour chaque client, note qui l'utilise, d'où, et où se trouve sa clé. Cherche `ceph.client.admin.keyring` partout dans le lab (nœuds, `cephcli01`, `adm01`).
2. Lis *Cephx → User Management*, sections *Authorization (Capabilities)* et *Profiles*. Explique dans ton journal la différence entre `osd 'allow rwx pool=rbd-test'` et `osd 'profile rbd pool=rbd-test'`, et pourquoi le profil `rbd` a besoin d'une capacité `mon` particulière (pense au verrouillage exclusif et au *blocklist*).
3. Restreins `client.rbd-test` à 10.10.30.20/32 sur `mon` et `osd` (`ceph auth caps` : que devient le reste de ses capacités si tu n'en donnes qu'une partie ?). Vérifie que `/mnt/disque01` fonctionne toujours, puis qu'après un démappage/remappage il fonctionne encore.
4. Crée `client.rbd-lecture`, range sa clé dans le Vault avec ton outil d'E10, ajoute-la aux variables du rôle, MR, playbook.
5. Prouve les droits depuis `cephcli01` : avec `rbd-lecture`, `rbd ls`, `rbd info` et une lecture d'image réussissent, une écriture échoue ; depuis une autre machine du VLAN 30 (copie **temporaire** du trousseau de `rbd-test` sur `ceph02`, effacée aussitôt), `rbd-test` est refusée. Copie les messages d'erreur dans le journal.
6. Rotation : une image est mappée sur `cephcli01`. Fais tourner la clé de `client.rbd-lecture` (`ceph auth rotate`), observe ce qui se passe pour une session ouverte et pour une nouvelle commande tant que le trousseau n'est pas redéployé, puis redéploie-le (Vault, playbook). Écris la procédure de rotation **sans interruption** que tu en déduis pour `client.rbd-test`.
7. Mets à jour le registre des secrets.

**Critères de réussite**
- [ ] Aucune clé `client.admin` sur `cephcli01` ; aucune entité cliente autre que `client.admin` (hors clés des démons créées par cephadm) n'a `allow *` sur les moniteurs.
- [ ] `client.rbd-test` a les profils `rbd` limités au pool `rbd-test` et à 10.10.30.20/32 ; `client.rbd-lecture` le profil `rbd-read-only` sur `rbd-test`, sans droit d'écriture.
- [ ] Les deux trousseaux sont sur `cephcli01` en 600, propriétaire `root`, déposés par le rôle ; `rbd ls rbd-test --id rbd-lecture` fonctionne.
- [ ] Le registre des secrets liste les clés clientes ; le journal contient l'inventaire et la procédure de rotation.

**Vérification** : `lab/bin/check 08 13`

<details><summary>Indice 1</summary>

`ceph auth caps client.<nom> mon '…' osd '…' mgr '…'` **remplace** toutes les capacités de l'entité : celles que tu n'écris pas disparaissent. Relis `ceph auth get` avant et après.
</details>

<details><summary>Indice 2</summary>

La restriction réseau s'ajoute à la fin d'une capacité : `profile rbd pool=rbd-test network 10.10.30.20/32`. Elle vaut pour chaque démon : mets-la sur `mon` **et** `osd`. Le gestionnaire (`mgr`) a aussi un profil `rbd` : à quoi sert-il côté client ?
</details>

<details><summary>Indice 3</summary>

Après une rotation, les sessions déjà authentifiées gardent leurs tickets jusqu'à leur renouvellement ; une nouvelle authentification échoue tant que le client présente l'ancienne clé. Combien de temps vit un ticket (`auth_service_ticket_ttl`) ? Et que se passe-t-il si deux entités ont les mêmes capacités ?
</details>

**Pour aller plus loin** (facultatif) : lis la note de version de Tentacle 20.2.4 sur CVE-2025-30156 (CephX) : quel type de client était concerné, et pourquoi la montée de version (E26) est-elle prioritaire ?

---

### M08-E14 — CRUSH : règles par classe et domaines de panne  `LAB` `★★★`

> **Ticket PLAT-924** — *De : Karim Benali*
> Deux problèmes dans la carte CRUSH actuelle. Un : `replicated_rule` place les répliques n'importe où, y compris sur le disque HDD de chaque nœud ; les images de VM et les métadonnées CephFS n'ont rien à y faire. Deux : en salle, `ceph01` et la future extension partageront une baie (même alimentation, même commutateur) : le domaine de panne doit être la **baie**, pas l'hôte. Je veux une hiérarchie qui décrit la salle, une règle par classe de disque, et plus aucun pool sur la règle par défaut. Valide tes règles hors ligne avant de les injecter.

**Objectifs pédagogiques**
- Lire la carte CRUSH : hiérarchie, *buckets*, poids, classes de disques et arbres fantômes (*shadow trees*).
- Construire une hiérarchie (centre de données, baies) et y déplacer des hôtes en mesurant le mouvement de données.
- Créer des règles répliquées par classe et domaine de panne, les tester hors ligne avec `crushtool`, et les affecter aux pools.

**Prérequis** : M08-E04 (classes `ssd` et `hdd`), M08-E05, M08-E10, M08-E11 (pools CephFS et RGW existants).
**Durée indicative** : 3 h.

**Contexte technique**
- Hiérarchie cible : `root default` → `datacenter par1` → `rack par1-baie-a` (`ceph01`, plus tard `ceph04`), `rack par1-baie-b` (`ceph02`), `rack par1-baie-c` (`ceph03`).
- Règles : `ssd-baie` (répliquée, classe `ssd`, domaine de panne `rack`) et `hdd-baie` (répliquée, classe `hdd`, domaine de panne `rack`).
- Affectation : tous les pools répliqués existants sur `ssd-baie` (images, métadonnées et données CephFS, `.mgr`, pools RGW), sauf choix argumenté ; la règle des nouveaux pools par défaut devient `ssd-baie` (`osd_pool_default_crush_rule`).
- Avec trois baies d'un hôte chacune, le domaine « baie » se comporte comme le domaine « hôte » : la différence apparaîtra avec `ceph04` (E18).
- ⚠️ Déplacer un hôte dans la hiérarchie ou changer la règle d'un pool **déplace des données**. Sur ce cluster presque vide, c'est rapide ; en production, c'est un changement planifié. Fais-le pool par pool et attends `HEALTH_OK` entre deux.

**Travail demandé**
1. Exporte et décompile la carte CRUSH actuelle dans `~/m08/e14/` (`ceph osd getcrushmap`, `crushtool -d`). Lis-la : où sont les classes de disques ? Que montre `ceph osd crush tree --show-shadow` ? Que fait chaque étape (`take`, `chooseleaf firstn 0 type host`, `emit`) de `replicated_rule` ?
2. Hors ligne d'abord : sur une copie décompilée, ajoute la hiérarchie et les deux règles, recompile, et teste-les avec `crushtool --test` (nombre de répliques 3, règle par règle, `--show-bad-mappings`, `--show-utilization`). Vérifie qu'une règle `ssd-baie` ne donne jamais deux OSD de la même baie. Essaie aussi une règle volontairement impossible (classe `nvme`) : que montre le test ?
3. En ligne, par des commandes (pas en injectant ta carte) : crée le *datacenter*, les trois baies, rattache-les, déplace chaque hôte dans sa baie. Observe `ceph -s` et `ceph osd df tree` après chaque déplacement.
4. Crée les règles `ssd-baie` et `hdd-baie` (`ceph osd crush rule create-replicated`), puis compare-les (`ceph osd crush rule dump`) avec celles de ta carte hors ligne.
5. Affecte les pools, un par un, en attendant `HEALTH_OK` ; note pour chacun le pourcentage d'objets déplacés (`misplaced`) affiché par `ceph -s`. Mets `ssd-baie` comme règle par défaut des nouveaux pools.
6. Vérifie avec `ceph pg ls-by-pool rbd-test` que les trois OSD de quelques PG sont sur trois hôtes distincts et de classe `ssd`.
7. Dans le journal : pourquoi `cephfs.cephfs.meta` et les index de RGW (`default.rgw.buckets.index`) doivent-ils être sur SSD même si les données ne l'étaient pas ? Que deviendrait l'écriture sur `rbd-test` si les deux SSD d'un hôte tombaient ?

**Critères de réussite**
- [ ] La hiérarchie `datacenter par1` → trois baies → hôtes est en place, chaque hôte dans sa baie.
- [ ] Les règles `ssd-baie` et `hdd-baie` existent avec la bonne classe et le domaine de panne `rack`.
- [ ] Plus aucun pool répliqué n'utilise `replicated_rule` ; `osd_pool_default_crush_rule` désigne `ssd-baie`.
- [ ] Tous les PG sont `active+clean` ; la carte décompilée et les résultats de `crushtool --test` sont dans `~/m08/e14/`.

**Vérification** : `lab/bin/check 08 14`

<details><summary>Indice 1</summary>

`ceph osd crush add-bucket <nom> <type>` crée un *bucket* vide ; `ceph osd crush move <nom> <type>=<parent>` le rattache (un hôte, une baie). Un *bucket* vide ne pèse rien : les données ne bougent qu'au déplacement des hôtes.
</details>

<details><summary>Indice 2</summary>

`crushtool -i <carte> --test --rule <id> --num-rep 3 --show-mappings` montre, pour des entrées fictives, les OSD choisis ; `--show-bad-mappings` ne montre que les cas où la règle n'a pas trouvé assez d'OSD. Les identifiants de règle se lisent dans la carte décompilée.
</details>

<details><summary>Indice 3</summary>

`ceph config set global osd_pool_default_crush_rule <ID>` attend l'identifiant numérique de la règle (`ceph osd crush rule dump ssd-baie`), pas son nom.
</details>

**Pour aller plus loin** (facultatif) : lis la section *Device classes* sur le « reclassement » (`crushtool --reclassify`) : comment l'utilise-t-on pour migrer une ancienne carte à racines séparées SSD/HDD vers les classes sans déplacer de données ?

---

### M08-E15 — Codes d'effacement  `LAB` `★★★`

> **Ticket PLAT-925** — *De : Claire Morel*
> La réplication triple nous coûte trois fois le volume. Pour les archives (exports, vieilles images, sauvegardes de configuration), le HDD et un code d'effacement suffiraient sûrement. Montre-moi, chiffres à l'appui, ce qu'on gagne et ce qu'on perd sur notre cluster à trois nœuds, et prépare un pool que l'équipe pourra utiliser pour des images RBD d'archives.

**Objectifs pédagogiques**
- Comprendre les codes d'effacement (k, m, *chunks*, `min_size`) et leurs contraintes sur un petit cluster.
- Créer un profil et un pool EC, l'utiliser comme pool de données d'images RBD (réécritures partielles).
- Mesurer le surcoût réel et le comportement en cas de perte d'un OSD.

**Prérequis** : M08-E14.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Profil : `ec-21-hdd` : k=2, m=1, classe `hdd`, domaine de panne `rack`. Tentacle utilise par défaut le greffon **ISA-L** (`plugin=isa`) pour les nouveaux profils.
- Pool : `rbd-ec-donnees` (EC, application `rbd`, réécritures autorisées). Les métadonnées d'une image (en-tête, *omap*) ne peuvent pas aller dans un pool EC : elles restent dans `rbd-test`.
- Image d'essai : `rbd-test/archives-ec`, 10 Gio, données dans `rbd-ec-donnees`.
- Tentacle introduit des optimisations EC (« FastEC », `allow_ec_optimizations`) pour les petites écritures de RBD et CephFS. Elles sont **irréversibles** sur un pool.

**Travail demandé**
1. Lis *Erasure code* (Tentacle) et note dans ton journal : avec k=2, m=1, combien de *chunks* par objet, combien d'OSD distincts, quel surcoût brut, combien de pertes simultanées tolérées ? Quel `min_size` Ceph pose-t-il par défaut avec m=1, et pourquoi la documentation recommande-t-elle k+1 ?
2. Crée le profil, affiche-le, et vérifie le greffon. Pourquoi un profil k=4, m=2 avec domaine de panne `rack` est-il impossible ici ? Vérifie-le **hors ligne** sur ta carte de E14 (`crushtool --test` avec une règle *indep* à 6 répliques) plutôt qu'en créant le pool.
3. Crée le pool `rbd-ec-donnees` avec ce profil, autorise les réécritures, active l'application `rbd`. Décide (et justifie) si tu actives `allow_ec_optimizations`.
4. Crée l'image `archives-ec` avec ses données dans le pool EC (`rbd create --data-pool`). Mappe-la sur `cephcli01` avec `client.rbd-test` (quel droit lui manque ?), formate-la, écris 2 Gio. Compare dans `ceph df detail` la place prise dans `rbd-ec-donnees` et ce qu'aurait pris le même volume dans `rbd-test`.
5. Perte d'un OSD : arrête l'OSD `hdd` de `ceph03` (`ceph orch daemon stop osd.<ID>`). La lecture et l'écriture sur `/dev/rbd…` continuent-elles ? Quel état prennent les PG (`ceph pg ls-by-pool rbd-ec-donnees`) ? Relance l'OSD et attends `HEALTH_OK`. ⚠️ N'arrête jamais deux OSD `hdd` à la fois : avec m=1, ce serait une perte de données d'essai — et en production, une perte de données.
6. Dans le journal, un tableau pour Claire : réplication ×3 sur SSD, réplication ×3 sur HDD, EC 2+1 sur HDD — capacité utile sur nos neuf disques, tolérance aux pannes, comportement pendant une panne, performances attendues en petites écritures, et ta recommandation pour les archives.

**Critères de réussite**
- [ ] Le profil `ec-21-hdd` existe : k=2, m=1, greffon `isa`, classe `hdd`, domaine `rack`.
- [ ] Le pool `rbd-ec-donnees` utilise ce profil, accepte les réécritures et porte l'application `rbd`.
- [ ] L'image `rbd-test/archives-ec` a ses données dans `rbd-ec-donnees`.
- [ ] Tous les PG sont `active+clean` à la fin ; le tableau comparatif est dans le journal.

**Vérification** : `lab/bin/check 08 15`

<details><summary>Indice 1</summary>

`ceph osd erasure-code-profile set <nom> k=… m=… crush-device-class=… crush-failure-domain=…`, puis `ceph osd pool create <pool> erasure <profil>`. Un profil ne se modifie plus une fois qu'un pool l'utilise.
</details>

<details><summary>Indice 2</summary>

`ceph osd pool set <pool> allow_ec_overwrites true` ; `ceph osd pool application enable <pool> rbd`. L'image se crée dans le pool **répliqué** (`rbd create rbd-test/archives-ec --data-pool …`) : c'est là que vivent ses métadonnées.
</details>

<details><summary>Indice 3</summary>

Un code d'effacement écrit un objet en k+m morceaux ; une écriture partielle doit relire, recalculer et réécrire la bande (*read-modify-write*). C'est ce que FastEC améliore, et ce qui rend un pool EC plus lent qu'un pool répliqué en petites écritures aléatoires.
</details>

**Pour aller plus loin** (facultatif) : ajoute un pool de données EC au volume CephFS (`ceph fs add_data_pool`) et place un répertoire `archives/` du sous-volume `outillage` dessus avec un attribut de *layout* (`setfattr -n ceph.dir.layout.pool`).

---

### M08-E16 — Exports NFS  `LAB` `★★`

> **Ticket PLAT-926** — *De : Nadia Roussel*
> Legacy-RDV dépose ses pièces jointes sur un partage NFS du vieux NAS d'InfoGér, que nous devons rendre dans trois mois. L'application ne sait pas parler CephFS, et on ne la modifiera pas avant sa migration. Il lui faut un partage NFS servi par Ceph, accessible **uniquement** depuis son serveur, sans que root sur ce serveur soit root sur le partage. On teste depuis `cephcli01` en attendant la VM définitive.

**Objectifs pédagogiques**
- Déployer NFS-Ganesha par l'orchestrateur (`ceph nfs cluster`) et comprendre où vit sa configuration.
- Créer un export d'un sous-volume CephFS restreint à un client, avec écrasement des droits de root.
- Comprendre les limites (haute disponibilité, NFSv3) et les options d'un NFS servi par Ceph.

**Prérequis** : M08-E10.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Cluster NFS : identifiant `par1`, un démon sur l'hôte étiqueté `nfs` (`ceph01`), port 2049, NFSv4 seulement (NFSv3 désactivé par défaut depuis Squid).
- Sous-volume : `legacy-rdv` (5 Gio) dans le groupe `applications` du volume `cephfs`.
- Export : pseudo-chemin `/legacy-rdv`, lecture-écriture pour 10.10.30.20 seulement, `root_squash`.
- Client : `cephcli01`, paquet `nfs-common`, point de montage `/mnt/legacy-rdv` (montage manuel : ce n'est qu'un essai).

**Travail demandé**
1. Lis *CephFS & RGW Exports over NFS* (`mgr/nfs`). Note : où le gestionnaire stocke-t-il la configuration des exports ? Que fait l'option `--ingress` de `ceph nfs cluster create`, et pourquoi ne l'utilises-tu pas ici ?
2. Ajoute l'étiquette `nfs` à `ceph01` dans `specs/hosts.yaml` (MR, application), crée le sous-volume `legacy-rdv`, puis le cluster NFS `par1` avec un placement sur cette étiquette ; exporte la spécification du service dans `specs/nfs.yaml`.
3. Crée l'export `/legacy-rdv` du sous-volume, restreint à `cephcli01`, avec `root_squash`. Affiche-le (`ceph nfs export info`) et explique chaque champ dans ton journal (`fsal.user_id` compris : quelle clé cephx a été créée ?).
4. Monte l'export sur `cephcli01` en NFSv4.1 ou 4.2. Crée un fichier en root : à qui appartient-il côté CephFS ? Crée un dossier `pieces-jointes/` accessible en écriture à l'utilisateur `admin` de `cephcli01` et écris-y.
5. Essaie un montage depuis `ceph02` : quel message ? Essaie un montage NFSv3 depuis `cephcli01` : quel message ?
6. Modifie l'export pour passer en lecture seule **par un fichier JSON** (`ceph nfs export info` → modification → `ceph nfs export apply`), vérifie, puis reviens en lecture-écriture.
7. Démonte, et note dans le journal ce qu'il faudrait pour la production : haute disponibilité (service `ingress` en mode `keepalive-only` ou haproxy), délai de grâce de Ganesha, sauvegarde du sous-volume.

**Critères de réussite**
- [ ] Le cluster NFS `par1` tourne sur `ceph01` (port 2049).
- [ ] L'export `/legacy-rdv` sert le sous-volume `applications/legacy-rdv`, en lecture-écriture pour 10.10.30.20 seulement, avec `root_squash`.
- [ ] Le dossier `pieces-jointes/` existe dans le sous-volume et appartient à un utilisateur non root.
- [ ] Le journal contient les réponses et les messages des essais refusés.

**Vérification** : `lab/bin/check 08 16`

<details><summary>Indice 1</summary>

`ceph nfs cluster create <id> "<placement>"`, puis `ceph nfs export create cephfs --cluster-id … --pseudo-path … --fsname cephfs --path <chemin du sous-volume> --client_addr … --squash …`. Le chemin du sous-volume vient de `ceph fs subvolume getpath`.
</details>

<details><summary>Indice 2</summary>

Avec `--client_addr`, le bloc principal de l'export passe en `access_type: none` et un bloc `clients` porte l'accès accordé : c'est ce qui ferme l'export aux autres adresses. Le montage : `mount -t nfs -o vers=4.2 <hôte>:/legacy-rdv /mnt/legacy-rdv`.
</details>

**Pour aller plus loin** (facultatif) : crée un export RGW (`ceph nfs export create rgw`) du compartiment `medidoc-journaux` en lecture seule : quels usages permet-il, et lesquels sont dangereux (renommages, écritures partielles) ?

---

### M08-E17 — Exporter un bloc en iSCSI  `LAB` `★★★`

> **Ticket PLAT-927** — *De : Karim Benali*
> InfoGér nous laisse un serveur de numérisation sous un système propriétaire qui ne sait monter que des LUN iSCSI ; il part dans six mois. En attendant, il lui faut 20 Gio de bloc. Avant tout, sache que la passerelle `ceph-iscsi` n'est plus maintenue : on ne la déploie pas. On fera une cible LIO standard sur une machine cliente du cluster, en connaissant ses limites. Teste avec une VM jetable comme initiateur.

**Objectifs pédagogiques**
- Mapper durablement une image RBD par le pilote noyau (`rbdmap`) avec une clé dédiée.
- Exporter un périphérique bloc en iSCSI avec LIO (`targetcli`) : *backstore*, cible, portail, ACL, authentification CHAP.
- Se connecter depuis un initiateur `open-iscsi` ; connaître les limites (point unique de défaillance, pas de multichemin cohérent) et l'alternative moderne (NVMe-oF).

**Prérequis** : M08-E06, M08-E13.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Image : `rbd-test/iscsi-scan`, 20 Gio, mappée sur `cephcli01` par `rbdmap` avec la clé dédiée `client.iscsi-cephcli01` (profil `rbd` sur `rbd-test`, depuis 10.10.30.20), déployée par le rôle `ceph_client` (clé dans le Vault, image dans `ceph_client_rbdmap`).
- Cible : LIO sur `cephcli01` (paquet `targetcli-fb`), IQN `iqn.2026-10.internal.medisphere.par1:cephcli01.legacy`, portail **10.10.30.20:3260** seulement, *backstore* `block` sur `/dev/rbd/rbd-test/iscsi-scan`, LUN 0.
- Initiateur d'essai : VM jetable `m08-initiateur` (VMID 2086, Debian 13, image dorée `current`, VNet `vstopub`, 10.10.30.21/24, MTU 9000, étiquette `env-m08`), créée dans l'état `ceph` de `plateforme/infra` et détruite à la fin. IQN de l'initiateur : `iqn.2026-10.internal.medisphere.par1:m08-initiateur`.
- Authentification : CHAP sur l'ACL de l'initiateur ; identifiant `scan-legacy`, secret de 16 caractères au moins dans le Vault `lab` (jamais dans `history` ni dans un dépôt).
- ⚠️ Un même LUN monté par deux initiateurs avec un système de fichiers non partagé (ext4, XFS) **se corrompt**. Un seul initiateur ici.

**Travail demandé**
1. Note dans ton journal pourquoi `ceph-iscsi` a été abandonné, ce que propose Ceph à la place (passerelle NVMe-oF, service `nvmeof` de cephadm), et les limites de la solution de ce ticket (que se passe-t-il si `cephcli01` redémarre ? s'il tombe ?).
2. Crée l'image et la clé `client.iscsi-cephcli01`. Range la clé dans le Vault, déclare-la et l'image dans les variables du rôle `ceph_client` (MR, playbook), redémarre `cephcli01` et vérifie que `/dev/rbd/rbd-test/iscsi-scan` existe après démarrage.
3. Configure la cible avec `targetcli` : *backstore*, cible, LUN, portail (remplace celui sur `0.0.0.0`), ACL pour l'IQN de l'initiateur, CHAP. Sauvegarde la configuration et vérifie qu'elle est rechargée au démarrage (service de restauration de LIO), **après** `rbdmap`. Cette cible temporaire se configure par un script versionné (pas de rôle : elle disparaît avec l'appareil) : écris-le dans `plateforme/ansible` (`outils/`) et note la date de fin dans la fiche.
4. Crée `m08-initiateur` par OpenTofu, installe `open-iscsi`, règle l'IQN de l'initiateur et les identifiants CHAP (fichier `iscsid.conf` ou paramètres du nœud), puis découvre et connecte la cible. Formate le LUN en XFS, monte-le, écris un fichier.
5. Essaie une connexion avec un mauvais secret : que voit l'initiateur, que journalise la cible ?
6. Redémarre `cephcli01` pendant qu'un `dd` tourne sur l'initiateur : combien de temps dure l'interruption, et l'initiateur reprend-il seul ? Lis `replacement_timeout` dans `iscsid.conf`.
7. Démonte, déconnecte (`iscsiadm … --logout`), détruis `m08-initiateur`. Laisse la cible configurée (elle sert à la vérification), ou retire-la si tu ne gardes pas le besoin : note ton choix.

**Critères de réussite**
- [ ] `/dev/rbd/rbd-test/iscsi-scan` est mappé au démarrage de `cephcli01` par `rbdmap` avec `client.iscsi-cephcli01`.
- [ ] La cible LIO expose ce périphérique en LUN 0 sur 10.10.30.20:3260 seulement, avec une ACL pour l'IQN de l'initiateur et CHAP ; la configuration survit à un redémarrage.
- [ ] Un fichier écrit depuis l'initiateur a été relu après redémarrage de la cible (journal).
- [ ] `m08-initiateur` (2086) est détruite à la fin de l'exercice.

**Vérification** : `lab/bin/check 08 17`

<details><summary>Indice 1</summary>

Une ligne de `/etc/ceph/rbdmap` : `<pool>/<image> id=<nom-du-client>,keyring=<chemin>`. Le lien `/dev/rbd/<pool>/<image>` est créé par une règle udev de `ceph-common` : c'est lui qu'il faut donner à LIO, pas `/dev/rbd0` dont le numéro peut changer.
</details>

<details><summary>Indice 2</summary>

Dans `targetcli`, les objets s'empilent : `/backstores/block create …`, `/iscsi create <IQN>`, puis dans `…/tpg1/` : `luns`, `portals`, `acls`. Le CHAP se règle par ACL (`set auth userid=… password=…`) ; `saveconfig` écrit le fichier rechargé au démarrage. Le secret saisi dans le shell de `targetcli` n'entre pas dans l'historique de `bash` : vérifie qu'il n'entre pas non plus dans un fichier lisible par tous.
</details>

<details><summary>Indice 3</summary>

`iscsiadm -m discovery -t sendtargets -p 10.10.30.20`, puis `iscsiadm -m node -T <IQN> -p 10.10.30.20 --op update -n node.session.auth.authmethod -v CHAP` (et `username`, `password`), puis `--login`. L'IQN de l'initiateur est dans `/etc/iscsi/initiatorname.iscsi`.
</details>

**Pour aller plus loin** (facultatif) : lis *Ceph NVMe-oF Gateway* et la spécification `nvmeof` de cephadm : quels composants faut-il (passerelle, groupe, sous-système, espace de noms), et pourquoi le multichemin y est-il cohérent alors qu'il ne l'est pas avec deux cibles LIO sur la même image ?

---

### M08-E18 — Étendre le cluster : un quatrième nœud  `LAB` `★★`

> **Ticket CHG-928** — *De : Claire Morel*
> Le nouveau serveur de stockage est livré, rangé dans la baie A à côté de `ceph01`. Je veux le voir entrer dans le cluster par le même chemin que les trois premiers — rien à la main —, et savoir à l'avance combien de données vont bouger et pendant combien de temps les performances baisseront. Fiche de changement d'abord.

**Objectifs pédagogiques**
- Ajouter un hôte à un cluster cephadm (prérequis, clé SSH, spécification d'hôte, emplacement CRUSH initial).
- Laisser la spécification OSD créer les OSD, et observer le rééquilibrage (*backfill*).
- Prévoir et limiter l'impact d'une extension (poids CRUSH progressif, réglages de récupération).

**Prérequis** : M08-E02 à M08-E04 (préparation et ajout des nœuds), M08-E14 (baies).
**Durée indicative** : 2 h 30.

**Contexte technique**
- `ceph04` : VMID 2084, 10.10.30.54 (VLAN 30) et 10.10.31.54 (VLAN 31), MTU 9000, mêmes ressources et mêmes disques que `ceph01-03` ; déclaré dans l'état `ceph` de `plateforme/infra` comme les trois premiers (module `vm-noeud`, variable `noeuds_ceph`), préparé par le rôle `ceph_noeud` (E02, E03). Étiquettes cephadm : `osd` seulement.
- Emplacement CRUSH : baie `par1-baie-a` (champ `location` de la spécification d'hôte, pris en compte **à l'ajout seulement**).
- Mémoire : 6 Go de plus sur `pve01`. Vérifie ta marge avant de créer la VM (`free -g` sur `pve01`, profil infra).
- Fiche de changement : `docs/stockage/changements/CHG-928-ceph04.md` dans `plateforme/medisphere` (modèle des fiches du socle).

**Travail demandé**
1. Rédige la fiche de changement : objectif, prérequis, étapes, contrôles, impact attendu (estime le volume qui va migrer à partir de `ceph df` et de la part de capacité qu'apporte `ceph04` dans la baie A et dans le cluster), retour arrière (retirer l'hôte avant que des données n'y soient), critères de fin.
2. Crée la VM par le pipeline de `plateforme/infra`, enregistre-la dans NetBox (deux interfaces, deux adresses), vérifie le DNS, puis applique le rôle de préparation des nœuds. Vérifie : Podman, chrony, MTU 9000 sur les deux interfaces (`ping -M do -s 8972` vers `ceph01` sur les deux réseaux), disques vides.
3. Vérifie que la clé publique de l'orchestrateur (`ceph cephadm get-pub-key`) est autorisée pour le compte `cephadm` de `ceph04` : c'est le rôle `ceph_noeud` qui la pose depuis E03, pas un `ssh-copy-id` à la main. `cephadm check-host` sur `ceph04` doit être vert.
4. Vérifie que la spécification OSD du palier 1 couvrira `ceph04` (placement), puis prévois l'impact : décide si tu fais entrer les OSD avec leur poids complet ou progressivement (`osd_crush_initial_weight`), et règle la récupération (profil mClock) en conséquence. Justifie dans la fiche.
5. Ajoute l'hôte par une spécification (`hosts.yaml` : adresse, étiquettes, `location`), avec `--dry-run` d'abord.
6. Suis l'arrivée : `ceph orch host ls`, `ceph orch ps ceph04`, `ceph osd tree`, `ceph -s` (objets *misplaced*, débit de *backfill*), `ceph osd df tree`. Mesure la durée du rééquilibrage et compare à ton estimation.
7. Si tu as fait entrer les OSD à poids nul, augmente leur poids par paliers jusqu'à leur taille. Remets les réglages de récupération par défaut. Ferme la fiche (résultat, écarts).
8. Tire de la fiche un runbook générique `RB-081 — ajouter un nœud` dans `docs/stockage/runbooks/` (n'importe quel nœud, n'importe quelle baie : prérequis, estimation du mouvement, ajout, suivi, retour arrière, critères de fin). Il servira aussi, en sens inverse, à retirer `ceph04` au mini-projet.

**Critères de réussite**
- [ ] `ceph04` est un hôte du cluster (10.10.30.54, étiquette `osd`), dans la baie `par1-baie-a` de la carte CRUSH.
- [ ] Ses trois OSD (deux `ssd`, un `hdd`) sont `up` et `in`, avec un poids CRUSH égal à leur taille.
- [ ] `ceph04` est dans NetBox avec ses deux adresses, et son nom se résout ; MTU 9000 sur ses deux interfaces.
- [ ] Le cluster est revenu à `HEALTH_OK` ; la fiche CHG-928 est fermée et RB-081 publié dans `plateforme/medisphere`.

**Vérification** : `lab/bin/check 08 18`

<details><summary>Indice 1</summary>

Une spécification d'hôte : `service_type: host`, `hostname`, `addr`, `labels`, `location: {rack: par1-baie-a}`. `ceph orch apply -i hosts.yaml` accepte plusieurs documents YAML : les hôtes déjà présents ne bougent pas.
</details>

<details><summary>Indice 2</summary>

`ceph config set osd osd_crush_initial_weight 0` avant l'ajout fait entrer les nouveaux OSD sans données ; `ceph osd crush reweight osd.<ID> <poids>` les remplit ensuite. Le poids « normal » d'un OSD est sa taille en Tio (≈ 0,0625 pour 64 Gio). N'oublie pas de supprimer le réglage après.
</details>

**Pour aller plus loin** (facultatif) : lis la documentation du module `balancer` (mode `upmap`) : après l'extension, la répartition des PG entre OSD est-elle équilibrée (`ceph osd df` : colonne `PGS`, écart `STDDEV`) ?

---

### M08-E19 — Retirer et remplacer un OSD  `LAB` `★★`

> **Ticket PLAT-929** — *De : Nadia Roussel*
> En production, un disque qui meurt est une affaire de quand, pas de si. Je veux que l'équipe ait fait le geste au moins une fois à froid : sortir proprement un OSD dont le disque « faiblit », remplacer le disque, faire revenir l'OSD avec le **même** identifiant, sans jamais passer par un état où une seule copie des données existe. Fais-le sur `ceph04`, c'est pour ça qu'on l'a.

**Objectifs pédagogiques**
- Savoir si un OSD peut être arrêté ou détruit sans risque (`ok-to-stop`, `safe-to-destroy`).
- Retirer un OSD par l'orchestrateur en conservant son identifiant (`--replace`), effacer le disque, et faire recréer l'OSD par la spécification.
- Remplacer physiquement (ici, virtuellement) un disque et retrouver la correspondance disque ↔ OSD.

**Prérequis** : M08-E18.
**Durée indicative** : 2 h.

**Contexte technique**
- OSD visé : un des deux OSD `ssd` de `ceph04` (note son identifiant : `<ID>`).
- « Remplacement du disque » : dans Proxmox, détache et supprime le disque virtuel de cet OSD sur la VM 2084, puis ajoute un disque neuf de même taille, même stockage, mêmes options. ⚠️ Cette opération ne concerne **que** la VM 2084 et le seul disque identifié : vérifie deux fois (numéro de série, `scsiN`) avant de supprimer.
- La spécification OSD du palier 1 est « gérée » : un disque vide qui correspond à ses filtres devient un OSD tout seul. C'est voulu ici ; tu dois en connaître le moment.

**Travail demandé**
1. Retrouve la correspondance entre `<ID>`, son périphérique dans `ceph04` (`ceph osd metadata <ID>`, `ceph device ls-by-host ceph04`) et le disque virtuel de la VM 2084 (numéro de série posé par le module `vm-noeud`, ligne `scsiN` de `qm config 2084`). Écris-en un petit script en lecture seule, réutilisable par l'astreinte. Note la correspondance.
2. Interroge le cluster : `ceph osd ok-to-stop <ID>`, `ceph osd safe-to-destroy <ID>`. Explique les deux réponses dans le journal.
3. Retire l'OSD en vue de son remplacement, avec effacement (`ceph orch osd rm <ID> --replace --zap`). Suis `ceph orch osd rm status` et `ceph -s` jusqu'à la fin de la vidange. Lis l'état de l'OSD dans `ceph osd tree`.
4. Remplace le disque dans Proxmox (détacher, supprimer, ajouter), puis vérifie que `ceph04` voit un disque neuf (`lsblk`, `ceph orch device ls ceph04 --refresh`).
5. Observe la recréation de l'OSD : quel identifiant reçoit-il ? Combien de temps se passe-t-il entre l'apparition du disque et l'OSD `up` ? Attends `HEALTH_OK`.
6. Dans le journal : qu'aurait changé un retrait **sans** `--replace` ? Et une panne réelle (disque mort, OSD déjà `down`) : quelles étapes de ton déroulé disparaissent, lesquelles restent ? Ce sera la base du runbook RB-080 (E22).

**Critères de réussite**
- [ ] `ceph04` a de nouveau trois OSD `up` et `in`, dont un sur le disque neuf ; aucun OSD n'est à l'état `destroyed`.
- [ ] Aucune suppression d'OSD n'est en attente (`ceph orch osd rm status`) ; le cluster est en `HEALTH_OK`.
- [ ] Le journal contient la correspondance OSD ↔ disque, les réponses de `ok-to-stop`/`safe-to-destroy` et l'identifiant obtenu par le nouvel OSD.

**Vérification** : `lab/bin/check 08 19`

<details><summary>Indice 1</summary>

Le numéro de série d'un disque virtuel Proxmox est celui que tu lui as donné (`serial=` : `ceph04-ssd1`… depuis E02) ; dans l'invité, `lsblk -o NAME,SERIAL,SIZE` et `ls -l /dev/disk/by-id/` le montrent. `ceph device ls` affiche l'identifiant de périphérique (fabricant_modèle_série) et les démons qui l'utilisent. Le disque neuf doit recevoir le même numéro de série (la ligne d'OpenTofu ou `qm set … serial=`).
</details>

<details><summary>Indice 2</summary>

Avec `--replace`, l'OSD reste dans la carte CRUSH marqué `destroyed` : son identifiant et sa place attendent un nouveau disque sur le **même hôte**. Le *backfill* commence dès que l'OSD sort (`out`), et l'OSD n'est détruit qu'une fois vide.
</details>

**Pour aller plus loin** (facultatif) : lis *Device Management* (`ceph device`) et la surveillance SMART des disques (`ceph device get-health-metrics`) : que verrais-tu sur un vrai disque qui faiblit, et comment le module `devicehealth` peut-il marquer un OSD `out` avant la panne ?

---

### M08-E20 — Capacité, quotas et seuils de remplissage  `LAB` `★★`

> **Ticket PLAT-930** — *De : Nadia Roussel*
> Un cluster Ceph plein s'arrête d'écrire, pour tout le monde. Je veux savoir **combien on peut vraiment stocker** — pas la somme des disques —, être prévenue bien avant le mur, et qu'un seul projet ne puisse pas remplir le cluster pour les autres. Et un rapport de capacité que je peux lire sans être experte de Ceph.

**Objectifs pédagogiques**
- Lire `ceph df` et `ceph osd df` (brut, stocké, utilisé, `MAX AVAIL`, écart entre OSD) et en déduire la capacité utile.
- Régler les seuils `nearfull`, `backfillfull`, `full` en fonction des pannes à absorber.
- Poser des quotas de pool et des tailles cibles pour l'autoscaler ; surveiller le surengagement des images RBD.

**Prérequis** : M08-E14, M08-E15, M08-E18.
**Durée indicative** : 2 h.

**Contexte technique**
- Valeurs par défaut de Ceph : `nearfull` 0,85, `backfillfull` 0,90, `full` 0,95.
- Seuils retenus par Nadia (à justifier par ton calcul, ou à contester) : `nearfull` 0,75 et `backfillfull` 0,85 ; `full` reste à 0,95.
- Quotas : `rbd-test` 100 Gio, `rbd-ec-donnees` 60 Gio.
- Pool d'essai : `essai-plein` (répliqué, `ssd-baie`, quota de 2 Gio), **supprimé** à la fin. La suppression d'un pool exige `mon_allow_pool_delete` : tu le remets à `false` aussitôt.
- Rapport : script `outils/rapport-capacite.sh` de `plateforme/ceph` (MR), lisible par un humain, sans droits d'écriture sur le cluster, lancé sur un nœud `_admin` avec sa propre clé.

**Travail demandé**
1. Lis `ceph df detail` et `ceph osd df tree`. Pour chaque classe de disque, calcule la capacité utile **en régime normal** (réplication ×3, EC 2+1) puis **après la perte d'un OSD SSD** de `ceph01` : où vont ses données, avec le domaine de panne `rack` ? Quel remplissage maximal des SSD de la baie A permet d'absorber cette perte sans atteindre `full` ? Compare avec la colonne `MAX AVAIL`.
2. Conclus : les seuils de Nadia sont-ils suffisants ? Pose les seuils retenus (`ceph osd set-nearfull-ratio`, `set-backfillfull-ratio`) et explique dans le journal ce que déclenche chacun.
3. Pose les quotas de pool. Renseigne pour l'autoscaler une taille cible (`target_size_ratio` ou `target_size_bytes`) sur `rbd-test` et regarde `ceph osd pool autoscale-status` : le nombre de PG proposé change-t-il ?
4. Surengagement : `rbd du -p rbd-test` montre la taille provisionnée et la taille utilisée des images. Combien de Gio sont promis au total ? Qu'arrive-t-il si toutes les images se remplissent ?
5. Crée `essai-plein` avec un quota de 2 Gio, remplis-le avec `rados bench` (sans nettoyage) ou des objets `rados put`, et observe : alerte de santé, comportement de l'écriture. Que se passerait-il au seuil `full` du cluster plutôt qu'au quota du pool ? Supprime le pool (et remets `mon_allow_pool_delete` à `false`).
6. Écris `rapport-capacite.sh` : capacité brute et utile par classe, remplissage par pool avec quota et marge, OSD le plus rempli, surengagement RBD, alerte si un seuil est proche. Il utilise une clé cephx **en lecture seule** (`client.rapport`, `mon 'allow r'`, `mgr 'allow r'` ; trousseau sur `ceph01`, 600) : justifie que rien de plus n'est nécessaire.

**Critères de réussite**
- [ ] `nearfull` vaut 0,75 au plus, `backfillfull` 0,85 au plus, dans l'ordre `nearfull < backfillfull < full`.
- [ ] `rbd-test` et `rbd-ec-donnees` ont un quota en octets ; `rbd-test` a une taille cible pour l'autoscaler.
- [ ] Le pool `essai-plein` n'existe plus et `mon_allow_pool_delete` vaut `false`.
- [ ] `client.rapport` n'a que des droits de lecture ; le rapport tourne avec elle ; le calcul de capacité est dans le journal.

**Vérification** : `lab/bin/check 08 20`

<details><summary>Indice 1</summary>

Avec la règle `ssd-baie`, chaque PG a exactement une copie par baie. Si un OSD SSD de la baie A meurt, ses copies ne peuvent aller **que** sur les autres OSD SSD de la même baie (les autres baies en ont déjà une). C'est le domaine de panne le plus petit qui fixe la marge.
</details>

<details><summary>Indice 2</summary>

`ceph osd pool set-quota <pool> max_bytes <octets>` ; `ceph osd pool get-quota <pool>`. Pour remplir : `rados bench -p essai-plein 120 write --no-cleanup -b 4M`. Un pool qui atteint son quota passe `POOL_FULL` : les écritures **de ce pool** sont bloquées, pas celles des autres.
</details>

**Pour aller plus loin** (facultatif) : dans le tableau de bord, regarde les prévisions de capacité ; lis la documentation de `ceph osd pool set <pool> bulk true` et dis si un pool de MédiSphère devrait la porter.

---

### M08-E21 — Revue : spécifications et règles CRUSH du stagiaire  `REV` `★★`

> **Ticket PLAT-931** — *De : Karim Benali* — *Copie : Lucas Martin*
> Lucas prépare le cluster Ceph du site de secours (PAR2) : trois nœuds `ceph21-23` et une passerelle S3. Il m'envoie ses spécifications cephadm et ses ajouts à la carte CRUSH, « testés sur trois VMs de la sandbox ». Fais-lui une vraie revue avant qu'on s'en serve : chaque défaut, sa gravité, ce qu'il casserait **chez nous**, la correction.

**Objectifs pédagogiques**
- Relire des spécifications cephadm et des règles CRUSH comme elles s'appliqueront réellement.
- Repérer les défauts de disponibilité (quorum, domaines de panne, `min_size`), de sécurité (secrets, clés d'administration) et d'exploitation (mémoire, ports, gestion automatique des disques).
- Rédiger une revue utile à son destinataire.

**Prérequis** : M08-E10 à M08-E15.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers : `ressources/M08-E21/` (`MR-lucas.md`, `hosts.yaml`, `mon.yaml`, `osd.yaml`, `mds.yaml`, `rgw.yaml`, `ingress.yaml`, `crush-ajouts.txt`, `pools.sh`). La clé privée qu'ils contiennent est **fictive**.
- Cible de Lucas : PAR2, réseaux 10.20.30.0/24 (public, VLAN STOR-PUB de PAR2) et 10.20.31.0/24 (cluster) ; nœuds `ceph21-23` (.51-.53), mêmes disques que `ceph01-03` (2 SSD + 1 HDD de 64 Gio, 6 Go de mémoire) ; VIP S3 10.20.30.200 ; le client de PAR2 `pbs01` y déposera des sauvegardes.
- Lucas a testé sur trois VMs de la sandbox, à quatre Go, sans charge et sans panne.

**Travail demandé**
1. Lis tout sans rien noter. Puis réponds : combien de moniteurs, sur quelles adresses ? Où vont les trois copies d'un objet de `sauvegardes` ? Qui détient la clé `client.admin` ? Que se passe-t-il quand un disque est ajouté à un nœud ?
2. Rédige la revue en tableau : n°, fichier et ligne(s), défaut, catégorie (disponibilité, sécurité, performance, exploitation), gravité (critique, élevée, moyenne, faible), impact concret chez nous, correction.
3. Classe les défauts par ordre de traitement et justifie le premier.
4. Propose les versions corrigées de `mon.yaml`, `osd.yaml`, `ingress.yaml` et de la règle CRUSH principale (seulement ce qui change).
5. Question de fond (dix lignes) : un cluster à trois nœuds sur un site de secours, avec réplication ×2 « pour économiser », est-ce défendable ? Que proposerais-tu à la place, et que faudrait-il pour que PAR2 serve vraiment de secours à `ceph-par1` ?
6. Trois lignes de conseils à Lucas sur sa façon de tester.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 10 défauts identifiés, dont tous les défauts critiques et élevés du corrigé.
- [ ] Chaque défaut a un impact concret et une correction précise (champ, valeur, commande).
- [ ] La question de fond reçoit une réponse argumentée.

<details><summary>Indice 1</summary>

Pour chaque adresse, demande-toi sur quel réseau elle est et qui doit la joindre. Pour chaque nombre (démons, répliques, mémoire), refais le calcul pour un nœud perdu.
</details>

<details><summary>Indice 2</summary>

Dans une règle CRUSH, lis le type de l'étape `chooseleaf` : c'est lui qui dit ce que deux copies ne partagent jamais. Dans une spécification OSD, lis les filtres : que choisit-elle **demain**, pas seulement aujourd'hui ?
</details>

<details><summary>Indice 3</summary>

Deux services sur les mêmes hôtes ne peuvent pas écouter le même port sur la même adresse. Et un fichier versionné n'est jamais l'endroit d'un bloc `-----BEGIN … PRIVATE KEY-----`.
</details>

**Pour aller plus loin** (facultatif) : écris le contrôle automatique (`yq` + `crushtool --test`) qui aurait attrapé les trois défauts les plus graves avant la MR ; tu le réutiliseras en E23.

---

### M08-E22 — Runbook : remplacer un disque défaillant  `RED` `★★`

> **Ticket PLAT-932** — *De : Nadia Roussel*
> Tu as remplacé un OSD à froid (E19). Maintenant écris-le pour l'astreinte de 3 h du matin : un disque est mort ou meurt, la personne d'astreinte n'est pas experte de Ceph, elle doit savoir quoi vérifier, quoi faire, quoi **ne pas** faire, et quand m'appeler.

**Objectifs pédagogiques**
- Transformer un geste maîtrisé en procédure exécutable par quelqu'un d'autre, avec points d'arrêt et retour arrière.
- Distinguer les situations (OSD `down` sans perte de données, PG dégradés, PG inactifs, plusieurs disques) et les décisions qui relèvent d'un expert.

**Prérequis** : M08-E19.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Runbook : `docs/stockage/runbooks/RB-080-remplacer-un-disque.md` dans `plateforme/medisphere`, au format des runbooks du socle (M01 : objet, déclencheur, prérequis, étapes numérotées, contrôles, retour arrière, escalade, historique).
- Public : astreinte de niveau 1 (Nadia, l'équipe support), accès `sudo ceph` sur `ceph01` (nœud `_admin`), accès Proxmox `wb-admin`.
- Le matériel est virtuel dans le lab ; écris la procédure pour un serveur réel (remplacement à chaud du disque par le prestataire de la salle) **et** sa transposition au lab (disque virtuel).

**Travail demandé**
1. Écris RB-080. Il doit au minimum couvrir : la qualification (quel OSD, quel disque, quel hôte, l'OSD est-il `down`, des PG sont-ils `degraded`, `undersized`, **inactifs** ?) ; les conditions d'arrêt immédiat et d'escalade (plus d'un OSD perdu dans des baies différentes, PG `inactive` ou `incomplete`, `HEALTH_ERR` autre que l'OSD) ; la décision « attendre la récupération » ou « retirer » ; le retrait avec conservation de l'identifiant ; l'identification physique du disque (numéro de série, voyant de localisation `ceph device light on`) ; le remplacement ; le contrôle de la recréation ; la clôture (`ceph crash archive`, ticket) ; ce qu'il ne faut **jamais** faire (`ceph osd purge` d'un OSD qui a des PG uniques, `ceph osd lost`, `--force` sans avis, effacer un autre disque).
2. Ajoute un tableau « symptôme → section du runbook » en tête, et les commandes exactes avec ce qu'on doit voir en sortie.
3. Fais relire ton runbook par quelqu'un (ou relis-le le lendemain) en le **jouant** sur `ceph04` sans regarder E19 : note ce qui manquait.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] RB-080 est fusionné dans `plateforme/medisphere`, au format des runbooks.
- [ ] Les situations d'escalade et les gestes interdits sont explicites ; chaque étape a sa commande et son résultat attendu.
- [ ] La transposition au lab est décrite et a été jouée une fois.

<details><summary>Indice 1</summary>

Pars de ton déroulé d'E19 et ajoute, avant chaque geste, la question « que dois-je voir pour avoir le droit de continuer ? ». Une étape sans contrôle de sortie n'est pas exécutable à 3 h du matin.
</details>

<details><summary>Indice 2</summary>

Une panne réelle commence souvent par un OSD déjà `down` : le cluster le marque `out` tout seul après `mon_osd_down_out_interval` (10 minutes par défaut) et la récupération démarre. Le runbook doit dire quand on la laisse finir et quand on met `noout` (maintenance prévue, pas panne).
</details>

---

### M08-E23 — Le cluster décrit par le code  `LIBRE` `★★★`

> **Ticket PLAT-933** — *De : Karim Benali*
> `plateforme/ceph` existe depuis l'amorçage, mais il ne contient que ce qui a été fait au palier 1, sans aucun contrôle, et une partie de l'état réel de `ceph-par1` (CRUSH, pools, quotas, seuils) n'est que dans la tête de celui qui a tapé les commandes. Je veux que le projet décrive **tout** le cluster : spécifications cephadm versionnées, relues en MR, contrôlées automatiquement, appliquées par une procédure unique, et une alerte quand le cluster s'écarte du dépôt. Étudie ce que la CI peut faire elle-même et ce qui doit rester sur `adm01` : je veux l'argument, pas seulement le résultat.

**Objectifs pédagogiques**
- Concevoir le dépôt de configuration d'un cluster cephadm (périmètre, structure, secrets).
- Construire une validation automatique pertinente (syntaxe, règles maison, secrets) et une détection de dérive.
- Arbitrer entre application par la CI et application par un opérateur, au regard des flux, des droits cephx et du risque.

**Prérequis** : M08-E10 à M08-E21 ; M01 (gabarits CI, protections), M04-E27 (pipeline d'application protégé).
**Durée indicative** : 4 h à 6 h.

**Contexte technique**
- Projet GitLab `plateforme/ceph`, créé en E03 (`bootstrap/`, `specs/`, `.yamllint`), complété depuis (`outils/pool-repliquee.sh` d'E05, spécifications de ce palier) ; branche `main` protégée, fusion par MR, Conventional Commits, gabarits `qualite.yml` et `release.yml` de `plateforme/ci-templates`.
- Contenu attendu au minimum : `specs/hosts.yaml`, `specs/mon.yaml`, `specs/mgr.yaml`, `specs/osd.yaml`, `specs/mds.yaml`, `specs/rgw.yaml`, `specs/ingress.yaml`, `specs/nfs.yaml`, des scripts dans `outils/` (dont le renouvellement du certificat d'E11 et le rapport d'E20), un README.
- Exécuteur disponible : `runner01` (shell, Debian 13, VLAN INFRA). Il ne joint pas le VLAN 30 aujourd'hui. Le client Ceph de Debian 13 est en version 18.2 (Reef).
- Ce que la configuration de Ceph contient **hors** spécifications (règles CRUSH, profils EC, pools, quotas, seuils, `ceph config`) : à toi de décider ce qui entre dans le dépôt et sous quelle forme.

**Travail demandé**
Complète, par MR sur `plateforme/ceph`, le projet et sa mise en service. Contraintes :
- l'**état réel** du cluster et le dépôt concordent à la fin : chaque service cephadm du cluster (hors services par défaut, à lister) a sa spécification dans `specs/`, et les spécifications du dépôt sont celles qui tournent ;
- **aucun secret** dans le dépôt (certificat et clé du point d'entrée S3, mots de passe éventuels) ; un contrôle automatique le garantit ;
- un pipeline de MR qui valide au moins : la syntaxe YAML, des **règles maison** issues de la revue d'E21 (au moins cinq : nombre de moniteurs, ports, VIP avec masque, pas de bloc de clé, `osd_memory_target` compatible avec la mémoire des nœuds…), la recherche de secrets ;
- une **procédure d'application** unique (script), qui montre le résultat de `--dry-run` et demande confirmation avant d'appliquer ; la décision écrite sur **qui** l'exécute (CI ou `adm01`), avec l'étude des flux et des droits cephx nécessaires dans chaque cas ;
- une **détection de dérive** planifiée qui compare `ceph orch ls --export` au dépôt et alerte en cas d'écart, avec des droits cephx en lecture seule ;
- le README : périmètre, structure, procédure, décision, ce qui n'est pas (encore) dans le dépôt et pourquoi.

**Critères de réussite**
- [ ] Le projet `plateforme/ceph` existe, `main` protégée ; les huit fichiers de spécifications sont sur `main` et aucun ne contient de clé privée.
- [ ] Chaque service `mon`, `mgr`, `osd.*`, `mds.*`, `rgw.*`, `ingress.*`, `nfs.*` du cluster a une spécification dans `specs/`.
- [ ] Le dernier pipeline de `main` est réussi ; une MR de démonstration montre le pipeline rejetant une spécification fautive (un défaut d'E21).
- [ ] Une détection de dérive planifiée existe et a tourné au moins une fois ; si elle accède au cluster, c'est avec une clé en lecture seule.
- [ ] Le README contient la décision argumentée sur l'exécution de l'application.

**Vérification** : `lab/bin/check 08 23`

<details><summary>Indice 1</summary>

`ceph orch ls --export` donne la spécification de chaque service telle que le cluster la connaît. Comparer « texte à texte » échoue sur l'ordre des clés et les valeurs par défaut ajoutées par cephadm : normalise des deux côtés (même outil, clés triées) avant de comparer, et écarte les champs que cephadm remplit seul.
</details>

<details><summary>Indice 2</summary>

Pour qu'un client joigne le cluster, il faut les moniteurs (3300 en msgr2) **et**, pour les commandes de l'orchestrateur, le gestionnaire actif (port dynamique dans 6800-7568). Quel est le coût d'ouvrir ces flux à `runner01`, et quel est le gain ? Quelles capacités `mgr` faut-il pour `orch ls`, et pour `orch apply` ?
</details>

<details><summary>Indice 3</summary>

`yq` (mikefarah) lit des fichiers à plusieurs documents (`select(.service_type == "mon")`) ; `crushtool --test` sur la carte exportée valide une règle avant de l'appliquer. Les règles maison sont des tests : chacune doit avoir un cas fautif qui la fait échouer.
</details>

**Pour aller plus loin** (facultatif) : regarde comment Rook décrit un cluster Ceph dans Kubernetes (ressources `CephCluster`, `CephBlockPool`) : qu'apporte un opérateur qui réconcilie en continu, par rapport à ta détection de dérive ? Tu le pratiqueras au module 16.
