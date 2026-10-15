# Module 13 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les fichiers complets sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `fichiers/M13-EXX/infra/…` = chemins de `plateforme/infra` (dont `registre/`), `…/tofu-modules/…` = `plateforme/tofu-modules`, `…/ansible/…` = `plateforme/ansible`, `…/ci-templates/…` = `plateforme/ci-templates`, `…/medisphere/…` = la documentation, `…/outils/…` = scripts de `plateforme/outils`, `…/mediagenda-api/…` = `mediagenda/api`. On **superpose** les dossiers dans l'ordre (E03, E04…) ; un fichier d'un exercice plus récent remplace le précédent (ex. `registre/projets.tf` : E03, puis E06, puis E10). Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête), les `*.exemple` des modèles sans valeur réelle.

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *Faits de distribution* relevés à la source le 8 octobre 2026 : empreinte SHA-256 de `harbor-offline-installer-v2.15.3.tgz` (`9609b32e…9336`, archive complète téléchargée, MD5 identique au fichier `md5sum` de la release), présence de son bundle Sigstore et identité du signataire (`https://github.com/goharbor/harbor/.github/workflows/publish_release.yml@refs/tags/v2.15.3`, lue dans le certificat du bundle) ; **les releases de Harbor 2.12+ ne publient plus de `.asc` GPG** (la page « Download the installer » de la documentation le cite encore) ; empreintes et identités des paquets Cosign 3.1.3, Trivy 0.75.0, Syft 1.54.1, Grype 0.120.1 (fichiers `*_checksums.txt` et certificats des bundles).
- *Harbor 2.15.3* : `harbor.yml.tmpl`, `install.sh`, `common.sh`, `prepare` et le gabarit `docker-compose.yml.jinja` du tag `v2.15.3` ont été lus : le gabarit du rôle n'utilise que des clés de ce `harbor.yml.tmpl` ; `prepare` copie le certificat dans `/data/secret/cert/` (propriétaire 10000) ; `install.sh` fait `down -v` puis `up -d` ; le mandataire s'appelle `nginx` ; le port des métriques est publié par `nginx`.
- *OpenTofu* : la configuration `registre/` (E03 + E04 + E05 + E10 + E11) passe `tofu validate` et `tofu fmt -check` avec OpenTofu 1.13.0, `goharbor/harbor` **3.12.5** et `hashicorp/random` 3.9.1 ; tous les attributs utilisés ont été contrôlés dans le schéma du fournisseur (`tofu providers schema -json`). `vm-debian` étendu passe `tofu validate`.
- *Ansible* : rôles `harbor` et `outils_supply_chain` et playbooks : `ansible-lint` 26 en profil `production` (rôles `docker_engine` et `certificats_acme` remplacés par des bouchons).
- *Scripts* : ShellCheck 0.11 (`-x`) et `bash -n` sur tous les scripts et les checks ; les checks ont été lancés sans lab (tout en KO, aucun faux positif constaté, aucune erreur d'exécution sous `set -euo pipefail`).

**Non testés en conditions réelles** (⚠️ à vérifier sur ton lab, et signale tes retours) : l'installation complète de Harbor par le rôle (premier passage, second passage à `changed=0`, redémarrage) ; le rechargement de nginx après renouvellement ; le comportement exact des caches (requête `HEAD` à l'amont, rétention par défaut des caches) ; les champs exacts de quelques réponses de l'API de Harbor lus par les vérifications (`metadata.auto_scan`, `scan_overview`, `quota.hard.storage`, `entity_type`, `expires_at` des robots) ; la syntaxe `allowed_images` à double astérisque de GitLab Runner 19.4.

**Où lancer les commandes.** `admin@adm01:~$` = sur `adm01` ; `admin@reg01:~$` = sur `reg01` (sudo pour Docker) ; `root@pve01:~#` = en root sur `pve01`. Dans `~/src/infra` : `. outils/charger-acces.sh` (accès S3 et `TF_ENCRYPTION`, M05) avant toute commande `tofu`.

---

### M13-E01 — Questions : la chaîne d'approvisionnement logicielle

**Grille** : 2 points si la réponse contient les éléments en gras, 1 si elle est juste mais incomplète, 0 sinon. 32/40 et plus : à l'aise ; 24-31 : relis les concepts de l'introduction ; moins de 24 : lis la documentation de Sigstore et la spécification SLSA avant E07.

1. Une étiquette est un **pointeur mobile** : l'éditeur republie `3.13-slim-trixie` à chaque correctif Debian ou Python. Lundi et vendredi, le même nom désigne deux empreintes. On l'empêche en tirant **par empreinte** (`…@sha256:…`) ; le prix : plus aucune mise à jour implicite, il faut un outil qui propose les nouvelles empreintes (Renovate, E11), sinon on fige des vulnérabilités.
2. **C.** Pour une image multi-architecture, `docker pull` affiche l'empreinte de l'**index** ; le moteur choisit ensuite le manifeste de sa plateforme. A : une couche n'identifie pas l'image. B : l'empreinte de la configuration est l'« ID » de l'image, pas ce que le registre adresse. D : l'archive `docker save` n'existe pas dans le registre.
3. Bénéfices : **indépendance** vis-à-vis des limites et pannes de l'amont, **débit** local, **contrôle et traçabilité** de ce qui entre (qui a tiré quoi, analyse, politique). Risque : un **point unique de défaillance** et une cible (tout le parc tire par lui), et l'illusion de sécurité (un cache public sert ce que l'amont publie, piégé ou non).
4. Tirage direct par étiquette : on reçoit **la nouvelle version** (piégée) ou une erreur si le dépôt a disparu. Par cache, par étiquette : le cache **revérifie l'étiquette auprès de l'amont** et sert la nouvelle version s'il en voit une ; il sert la copie locale seulement si l'amont ne répond plus (selon réglage). Par empreinte : on reçoit **exactement** ce qu'on avait validé (l'empreinte ne peut pas désigner autre chose), servi par le cache même si l'amont l'a supprimé, tant qu'il est en cache.
5. L'immuabilité protège **une étiquette dans un registre** ; elle ne dit rien d'une étiquette **dans un autre registre** (amont, réplique), elle peut être levée par un administrateur, et le consommateur, lui, résout toujours l'étiquette à l'instant du tirage. Le déploiement par empreinte rend le contenu **vérifiable de bout en bout** (c'est l'empreinte qu'on signe et qu'on vérifie).
6. Questions : le paquet est-il **utilisé** à l'exécution (une bibliothèque du noyau dans une image n'est jamais chargée) ? **Exploitable** dans notre contexte (réseau exposé, entrée utilisateur) ? Existe-t-il un **correctif** (sinon, quelle mitigation) ? CVSS = **gravité théorique** (0-10) ; EPSS = **probabilité d'exploitation** dans les 30 jours ; KEV = liste des vulnérabilités **effectivement exploitées**. Une CVE KEV « moyenne » est plus urgente qu'une « critique » sans exploitation connue.
7. **A.** `--ignore-unfixed` écarte les vulnérabilités **sans version corrigée** publiée. B : ce sont les exceptions (`.trivyignore`, VEX). C : un analyseur ne modifie rien. D : c'est `--skip-db-update`.
8. **Catalogues différents** (ce que chaque outil sait reconnaître : dpkg, métadonnées Python, binaires Go), **bases différentes** (sources d'avis, dates de mise à jour), **correspondance différente** (CPE contre `purl`, avis de la distribution contre amont, notion de « corrigé »). Aussi : sévérités prises chez la distribution ou à la NVD.
9. Un **VEX** (*Vulnerability Exploitability eXchange*, formats OpenVEX, CSAF, CycloneDX) est une déclaration **signable et partageable** du producteur : « mon produit **n'est pas affecté** par la CVE X, parce que… ». Un `.trivyignore` est local, propre à un outil, sans justification structurée ni signature, et ne voyage pas avec l'image.
10. Inventaire des composants (nom, **version**, identifiant **`purl`**, licence, empreintes, relations), aux formats **SPDX** et **CycloneDX**. On la conserve parce qu'elle décrit l'image **telle qu'elle a été construite** (un analyseur futur pourrait voir autre chose), parce qu'elle permet de répondre en minutes à « qui contient X ? » sans tirer et réanalyser des centaines d'images, et parce qu'elle est une **preuve** pour l'auditeur.
11. La signature dit **qui** approuve **cette empreinte** ; l'attestation est une **déclaration signée à propos** de l'empreinte (SBOM, provenance, résultat d'analyse, revue). Pour l'audit : la **provenance** (commit, pipeline, images de base) prouve qu'une image de production vient du code relu et du pipeline officiel.
12. L1 : la construction **produit une provenance** ; L2 : sur une **plateforme hébergée**, qui **génère et signe** la provenance elle-même ; L3 : plateforme **durcie**, constructions **isolées**, clés de signature hors de portée du code utilisateur. Un GitLab CI auto-hébergé dont un **job** signe la provenance avec une clé qu'il détient : **L1** (avec un environnement de L2, mais la provenance n'est pas infalsifiable par le job lui-même). Voir aussi E08.
13. Cosign signe **l'empreinte du manifeste** (une charge utile JSON « simple signing » qui contient l'empreinte et le nom), pas les couches une à une : l'empreinte couvre récursivement tout le contenu. Par empreinte parce qu'une étiquette peut **changer entre la résolution et la signature** (ou après) : on signerait ou on croirait vérifier autre chose.
14. **B.** Cosign 3 pousse un bundle Sigstore comme **artefact référent** (champ `subject`), retrouvé par l'API *Referrers* (ou par l'étiquette de repli `sha256-<empreinte>` si le registre ne l'a pas). A : schéma de Cosign 2 (mode *legacy*). C : le journal contient une trace, pas la signature stockée pour le registre. D : modifier le manifeste changerait son empreinte : la signature ne peut pas y vivre.
15. Le signataire présente un **jeton OIDC** (identité : courriel, ou projet/pipeline pour une CI) à **Fulcio**, qui délivre un certificat de quelques minutes lié à une clé éphémère ; la signature et le certificat sont inscrits dans **Rekor**, journal public **horodaté** et auditable ; on vérifie « signé par telle identité, à un moment où le certificat était valide ». MédiSphère ne l'utilise pas avec les services publics : **le journal est public** (fuite de l'inventaire de nos images) et dépend d'Internet. En privé : **Fulcio et Rekor auto-hébergés** (avec leur racine TUF), l'**émetteur OIDC de GitLab** (`id_tokens`).
16. L'attaquant **signe n'importe quelle image** que nos vérificateurs accepteront, et rien ne distingue ses signatures des nôtres (pas d'horodatage de confiance sans journal). Dans l'heure : **retirer la clé publique** des vérificateurs (tout est bloqué, c'est voulu), faire tourner la clé et les secrets voisins, re-signer ce qui a été **reconstruit**. Il fallait prévoir : une procédure de rotation, des **vérificateurs qui acceptent plusieurs clés**, une clé hors de portée des développeurs, idéalement un HSM/KMS (M25).
17. Le **système de construction** de SolarWinds a été compromis : le code malveillant (Sunburst) était injecté **pendant la compilation**, dans un binaire ensuite **signé légitimement**. La signature prouvait l'origine, pas l'intégrité du processus. SLSA vise ce cas par la **provenance infalsifiable** et la **construction isolée et durcie** (L3), et par des constructions reproductibles.
18. Une **porte dérobée volontaire**, préparée pendant deux ans par un mainteneur gagné par ingénierie sociale, pas une erreur. Le code actif était dans des **fichiers de test binaires** et dans le script de construction des **archives de distribution** (`.tar.gz` générées), absent du dépôt Git visible. Leçon : une archive de distribution n'est pas le code relu ; préférer construire **depuis les sources Git**, comparer, et ne pas faire confiance à la seule signature du mainteneur.
19. Mesures : épingler les actions et images **par empreinte (SHA de commit, `@sha256`)** et non par étiquette (les étiquettes ont été **réécrites**) ; **vérifier la signature et l'empreinte** des binaires téléchargés ; **ne pas exposer de secrets** aux jobs d'analyse (moindre privilège, secrets limités aux jobs qui en ont besoin) ; **délai de maturité** avant d'adopter une version ; cache interne et liste d'images autorisées ; rotation rapide des secrets. « Épingler la version » ne suffit pas : une **étiquette** de version peut être republiée avec un autre contenu ; et la version piégée 0.69.4 venait du pipeline de publication officiel (étiquette poussée par l'attaquant) : sa signature aurait été valide, seul le **délai** avant adoption l'aurait écartée.
20. **Délai de maturité** (`minimumReleaseAge`, quelques jours) ; **fusion automatique limitée aux correctifs** avec une CI verte ; **épinglage par empreinte** et revue humaine des mineures et majeures ; règles plus strictes pour les outils qui voient des secrets ; analyse dans la MR.

---

### M13-E02 — Installer Harbor sur `reg01`

**Solution**

Fichiers : [`vm-debian/main.tf`](fichiers/M13-E02/tofu-modules/vm-debian/main.tf), [`variables.tf.extrait`](fichiers/M13-E02/tofu-modules/vm-debian/variables.tf.extrait), [`README.md.extrait`](fichiers/M13-E02/tofu-modules/vm-debian/README.md.extrait) ; [`socle/reg01.tf`](fichiers/M13-E02/infra/socle/reg01.tf) ; le rôle [`harbor`](fichiers/M13-E02/ansible/roles/harbor/) ; [`playbooks/registre.yml`](fichiers/M13-E02/ansible/playbooks/registre.yml) ; [`group_vars/role_registre/`](fichiers/M13-E02/ansible/inventories/lab/group_vars/role_registre/) ; [`host_vars/reg01/certificats.yml`](fichiers/M13-E02/ansible/inventories/lab/host_vars/reg01/certificats.yml) ; [`pare_feu.yml.extrait`](fichiers/M13-E02/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; [RB-130](fichiers/M13-E02/medisphere/docs/registre/runbooks/RB-130-installer-reconstruire-reg01.md).

*A. Cosign et la provenance.*

1. Amorçage de Cosign 3 par le Cosign de Debian :
   ```
   admin@adm01:~/m13/e02$ B=https://github.com/sigstore/cosign/releases/download/v3.1.3
   admin@adm01:~/m13/e02$ curl -fLO $B/cosign_3.1.3_amd64.deb -fLO $B/cosign_3.1.3_amd64.deb.sigstore.json -fLO $B/cosign_checksums.txt
   admin@adm01:~/m13/e02$ sudo apt install cosign            # 2.5 (Debian 13), pour ce seul usage
   admin@adm01:~/m13/e02$ cosign verify-blob --new-bundle-format --bundle cosign_3.1.3_amd64.deb.sigstore.json \
       --certificate-identity keyless@projectsigstore.iam.gserviceaccount.com \
       --certificate-oidc-issuer https://accounts.google.com cosign_3.1.3_amd64.deb
   Verified OK
   admin@adm01:~/m13/e02$ grep ' cosign_3.1.3_amd64.deb$' cosign_checksums.txt | sha256sum -c -
   cosign_3.1.3_amd64.deb: OK
   admin@adm01:~/m13/e02$ sudo apt remove cosign && sudo apt install ./cosign_3.1.3_amd64.deb && cosign version | grep GitVersion
   GitVersion:    v3.1.3
   ```
   La **signature** prouve **qui** a publié (l'identité du projet Sigstore, inscrite dans un journal public horodaté) ; l'**empreinte** prouve que le fichier n'a pas changé depuis, et c'est elle qu'on **épingle** dans le code : la vérification future ne dépend plus d'Internet ni de Sigstore. L'empreinte seule, lue dans le `checksums.txt` d'un site compromis, ne prouve rien ; la signature seule, rejouée à chaque installation, rend l'installation dépendante d'un service externe. ⚠️ Le paquet amont s'appelle aussi `cosign` : vérifie `dpkg -l cosign` (version 3.1.3).
2. Lecture et vérification du bundle de Harbor :
   ```
   admin@adm01:~/m13/e02$ jq -r .mediaType harbor-offline-installer-v2.15.3.tgz.sigstore.json
   application/vnd.dev.sigstore.bundle.v0.3+json
   admin@adm01:~/m13/e02$ jq -r .verificationMaterial.certificate.rawBytes harbor-offline-installer-v2.15.3.tgz.sigstore.json \
       | base64 -d | openssl x509 -inform der -noout -text | grep -A1 -E 'Subject Alternative|57264.1.1:'
       X509v3 Subject Alternative Name: critical
           URI:https://github.com/goharbor/harbor/.github/workflows/publish_release.yml@refs/tags/v2.15.3
       1.3.6.1.4.1.57264.1.1:
           https://token.actions.githubusercontent.com
   admin@adm01:~/m13/e02$ cosign verify-blob harbor-offline-installer-v2.15.3.tgz \
       --bundle harbor-offline-installer-v2.15.3.tgz.sigstore.json \
       --certificate-oidc-issuer https://token.actions.githubusercontent.com \
       --certificate-identity https://github.com/goharbor/harbor/.github/workflows/publish_release.yml@refs/tags/v2.15.3
   Verified OK
   admin@adm01:~/m13/e02$ sha256sum harbor-offline-installer-v2.15.3.tgz
   9609b32edaa0075ce2bfa336b5e72447f8782ded9f576b5df7cd92bdd8359336  harbor-offline-installer-v2.15.3.tgz
   ```
   L'identité contient l'**étiquette Git** : une archive signée par le même workflow pour une autre version (ou depuis une branche) est refusée. Pour une nouvelle version (étape 4) : notes de version et avis de sécurité, chemin de mise à jour (une 2.x ne saute pas de mineure sans lire la procédure de migration), délai de quelques jours, et la même vérification avec la nouvelle étiquette dans l'identité (RB-130).

*B. La VM.*

3. `vm-debian` reçoit un `dynamic "disk"` sur `disques_donnees` (liste vide par défaut) : aucun consommateur ne voit son plan changer, c'est une **mineure**. `vm-noeud` ne convient pas : sa validation refuse les VMID du socle, et c'est un module de nœuds de cluster (cartes multiples, adresses imposées sur des VLAN non routés).
4. Plan de `socle/reg01.tf` : 1 VM, les objets NetBox (VM, interface, adresse, IP primaire), A, PTR et le CNAME — **une seule** VM ajoutée, rien de modifié ni détruit ailleurs. Lire `scsi1` : `hdd-bulk`, `backup = false`, `serial = reg01-donnees`.
   ```
   root@pve01:~# qm config 1013 | grep -E '^(scsi|net)'
   scsi0: local-nvme:vm-1013-disk-0,discard=on,iothread=1,size=32G
   scsi1: hdd-bulk:vm-1013-disk-1,backup=0,discard=on,iothread=1,serial=reg01-donnees,size=200G
   net0: virtio=BC:24:11:..,bridge=vinfra,firewall=0
   root@pve01:~# qm set 1013 --startup order=4
   ```
5. La matrice : une définition `REG01` et une règle de transit `{entree: [$V_K8S, $V_SANDBOX], destination: $REG01, proto: tcp, ports: 443}` (extrait). Rien pour `adm01` (règle « bastion vers tout le lab »), rien pour `runner01`/`runner02`/`ca01` (même VLAN), rien pour la sortie (« lab vers Internet »).

*C. Le rôle.*

6. Lecture de l'installateur. `install.sh` charge les images (`docker load` de `harbor.v2.15.3.tar.gz`), lance `prepare`, **arrête** une instance existante par `docker compose down -v`, puis `up -d`. `prepare` tourne dans un conteneur `goharbor/prepare` et écrit dans le dossier de l'installateur : `common/config/…` (configurations des composants, secrets internes) et `docker-compose.yml` ; il **copie** le certificat et la clé de `harbor.yml` dans `/data/secret/cert/server.crt|key` (10000:10000), montés dans `nginx` sous `/etc/cert/`. Le **nom de projet Compose** est celui du dossier (`harbor`) : il préfixe le réseau (`harbor_harbor`) ; si on installait directement dans `/opt/harbor-2.15.3`, la version suivante créerait un autre projet et laisserait l'ancien tourner. D'où le lien `/opt/harbor` → `/opt/harbor-dist/<version>/harbor` (le dossier extrait s'appelle `harbor`).
7. Le rôle (fichiers) : `prerequis.yml` (Debian 13, Compose ≥ 2.3, XFS sur `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_reg01-donnees`, montage par UUID, surcharge `RequiresMountsFor=/data` de `docker.service`, dossier des certificats, script de rechargement, unité) ; `installer.yml` (`get_url` avec `checksum: sha256:…`, décompression `creates:`, garde-fou de version, lien) ; `configurer.yml` (`harbor.yml` en 600 avec `diff: false`, `install.sh --with-trivy` avec `creates: docker-compose.yml`, sinon `prepare` + redémarrage si `harbor.yml` a changé, puis la ligne `CONTENT_TRUST_LEGACY_SIGNER_PULL_ENABLED` de `common/config/core/env`, à `false` jusqu'à M13-E14 qui en explique le rôle) ; `service.yml` ; `verifier.yml` (`/api/v2.0/health` par le nom de service et image de `harbor-core`).
8. Playbook : Docker → `harbor` (`tasks_from: prerequis`) → `certificats_acme` → `harbor`. À l'émission, `step` écoute en autonome sur le port 80 pour le défi HTTP-01 : Harbor (son `nginx` publie 80) doit être arrêté, d'où `avant_emission: systemctl stop harbor.service` — d'où aussi l'unité, qui doit **exister** (sinon `systemctl stop` échoue au premier passage). Au premier passage, `apres_emission: systemctl start harbor.service` ne démarre rien (condition `ConditionPathExists` sur `docker-compose.yml` : l'unité est sautée sans erreur) ; le rôle `harbor` installe juste après. Le script de rechargement sort proprement si `/data/secret/cert/` n'existe pas encore.
9. Application et contrôles :
   ```
   admin@adm01:~$ ssh reg01 'findmnt /data; systemctl is-active harbor; sudo docker ps --format "{{.Names}}\t{{.Status}}"'
   TARGET SOURCE    FSTYPE OPTIONS
   /data  /dev/sdb  xfs    rw,noatime,attr2,inode64,…
   active
   harbor-jobservice  Up 3 minutes (healthy)
   nginx              Up 3 minutes (healthy)
   harbor-core        Up 3 minutes (healthy)
   trivy-adapter      Up 3 minutes (healthy)
   …
   admin@adm01:~$ curl -s https://registry.par1.medisphere.internal/api/v2.0/health | jq -r '.status, (.components[] | "\(.name) \(.status)")'
   healthy
   core healthy
   database healthy
   jobservice healthy
   portal healthy
   redis healthy
   registry healthy
   registryctl healthy
   trivy healthy
   root@pve01:~# qm reboot 1013      # puis la même lecture : Harbor revient seul
   ```
10. RB-130, inventaire (`reg01` dans le socle, rôles appliqués), registre des secrets (`vault_harbor_admin_mdp`, `vault_harbor_db_mdp`, Vault `critique` ; le mot de passe d'`admin` sera aussi en variable masquée de `plateforme/infra` en E03).

**Explications**

- **Pourquoi `RequiresMountsFor` sur Docker.** Les conteneurs de Harbor ont `restart: always` : au démarrage de la machine, c'est **Docker** qui les relance, avant même `harbor.service`. Sans dépendance, si `/data` monte en retard (ou pas : disque absent, `nofail`), PostgreSQL initialise une base vide sur le disque système, et le registre sert un dépôt vide : une panne silencieuse (M13-E22 en joue une variante).
- **Pourquoi un script de rechargement.** Le renouvellement (`cert-renewer@harbor`) réécrit `/etc/harbor/tls/registry.crt`, mais `nginx` lit sa **copie** dans `/data/secret/cert/`. Le script recopie le contenu (`cat >` garde propriétaire et droits 10000) puis `nginx -t` et `nginx -s reload` dans le conteneur : pas de coupure. Relancer `prepare` marcherait aussi, mais redémarrerait toute la pile toutes les deux semaines.
- **Le mot de passe d'`admin`** n'est lu qu'à la première installation (la valeur est ensuite dans la base) : changer la variable du Vault ne change pas Harbor.

**Alternatives**

- *Chart Helm de Harbor* dans Kubernetes : haute disponibilité possible (base et Redis externes, stockage objet), mais le registre dépendrait du cluster qu'il alimente (œuf et poule au démarrage d'un cluster neuf, M14). On garde une VM pour le socle ; l'ADR-0130 (palier 3) en discute.
- *Stockage objet* (`storage_service` S3 vers `s3-01` ou RGW) au lieu de `/data` : plus de place et une sauvegarde différente ; mais `s3-01` est petit et `ceph-par1` est arrêtable.
- *Installateur en ligne* : plus léger, mais les images sont tirées de Docker Hub à l'installation (limites de débit, et l'empreinte de l'archive ne couvre plus les images).

**Pièges classiques**

- **Le `.asc` de la documentation n'existe plus** pour les versions récentes : chercher le bundle `.sigstore.json` et lire l'identité dans le certificat ; ne pas « vérifier » avec le fichier `md5sum` de la même release (même source, même compromission).
- Relancer `install.sh` à chaque passage d'Ansible : `down -v` + `up -d`, Harbor redémarre à chaque pipeline.
- Monter `/data` par `/dev/sdb` : le nom peut changer (ajout d'un disque, contrôleur différent).
- Oublier l'ordre certificat / installation : `prepare` échoue (fichier absent) ou le défi ACME échoue (port 80 occupé par Harbor).
- Appliquer `pare_feu_local` (M06-E30) à `reg01` : son `flush ruleset` efface les règles nftables que Docker écrit, les conteneurs perdent leur réseau ; et les ports publiés par Docker passent par la chaîne `forward`, pas `input` : le filtrage local d'entrée ne les verrait pas. Un filtrage local d'un hôte Docker se fait dans la chaîne `DOCKER-USER` (M26).
- Interroger la santé par `localhost` ou par l'adresse IP : le certificat ne couvre pas ces noms, et l'on ne teste pas ce que voient les clients.
- `hostname: reg01.par1.medisphere.internal` dans `harbor.yml` : Harbor fabrique ses URL (jetons, redirections) avec ce nom ; les clients qui utilisent `registry` reçoivent un « realm » sur `reg01` (il marche, mais le nom de service perd son intérêt).

**En production chez MédiSphère**

Deux registres (le second répliqué, M13-E13), sauvegarde applicative testée (M13-E15), supervision des composants et du disque (M13-E16, M21), journal d'audit de Harbor exporté (M22), comptes humains par OIDC (M24), mot de passe d'`admin` sous scellé et alerte sur son usage.

---

### M13-E03 — Projets, membres et comptes robots

**Solution**

Fichiers : [`registre/`](fichiers/M13-E03/infra/registre/) (`versions.tf`, `chiffrement.tf`, `providers.tf`, `variables.tf`, `terraform.tfvars.exemple`, `utilisateurs.tf`, `projets.tf`, `robots.tf`, `sorties.tf`) ; [`outils/publier-secrets-registre.sh`](fichiers/M13-E03/outils/publier-secrets-registre.sh), [`outils/migrer-registre-travail.sh`](fichiers/M13-E03/outils/migrer-registre-travail.sh).

1. Permissions et rôles :
   ```
   admin@adm01:~$ curl -s --netrc-file ~/.config/workbook/harbor-admin.netrc https://registry.par1.medisphere.internal/api/v2.0/permissions | jq '.system | length, (.project | map(.resource) | unique)'
   ```
   (fichier `netrc` en 600, créé le temps de l'exploration et supprimé ensuite.) *Developer* pousse et tire, gère les étiquettes et labels, lance une analyse ; *Guest* tire et lit ; *Maintainer* gère en plus la rétention, l'immuabilité, les robots du projet ; *Project Admin* gère les membres et la configuration. Un robot peut recevoir des droits **système** (registres distants, réplication, ramasse-miettes, analyse globale, et même `user:create`) qu'aucun rôle de projet ne donne : un robot système mal réglé est un administrateur.
2. `registre/` séparé de `socle` : cycle de vie et dépendances différents (le fournisseur Harbor exige un Harbor joignable ; un `plan` du socle ne doit pas échouer parce que Harbor est en maintenance), et des **secrets** dans l'état (d'où le chiffrement, obligatoire ici). `insecure` vaut `true` par défaut dans le fournisseur : sans `insecure = false`, le mot de passe d'`admin` partirait vers n'importe quel serveur qui se ferait passer pour Harbor.
3. Robots : un `random_password` par robot (32 caractères, sans spéciaux : ni `$` ni `+` dans la valeur), `duration = 180`, permissions explicites (voir `robots.tf`). `wb-checks` : actions `list`, `read` et `pull` seulement. Membres : `harbor_project_member_user` avec `projectadmin`, `developer`, `guest`.
4. Après l'`apply` du pipeline :
   ```
   admin@adm01:~/src/infra$ . outils/charger-acces.sh
   admin@adm01:~/src/infra$ tofu -chdir=registre init && ~/src/outils/publier-secrets-registre.sh
   écrit : /home/admin/.config/workbook/harbor-checks.env (600)
   écrit : /home/admin/.config/workbook/harbor-moi.env (600)
   groupe mediagenda : HARBOR_ROBOT_USER (protégée, masquée=false, non développée)
   …
   ```
   `tofu output -json robots` ne passe jamais par un journal de CI : on le lance depuis `adm01`, l'état déchiffré en mémoire. Les mots de passe initiaux des personnages sont transmis hors bande (dans un vrai service : un message chiffré, ou un lien à usage unique), et changés à la première connexion (`ignore_changes = [password]` : OpenTofu ne les réécrit pas).
5. Preuves par l'échec : création de projet avec `wb-checks` → `403 FORBIDDEN` ; poussée avec `k8s-pull` → `unauthorized to access repository … action: push`.
6. Migration :
   ```
   admin@adm01:~$ ~/src/outils/migrer-registre-travail.sh --essai | head -3
   admin@adm01:~$ ~/src/outils/migrer-registre-travail.sh
   OK  mediagenda/api:0.1.0 → medisphere/mediagenda-api:0.1.0 (sha256:…)
   OK  mediagenda/api:0.2.0 → medisphere/mediagenda-api:0.2.0 (sha256:…)
   …
   ```
   `--all` copie l'index et tous les manifestes (multi-architecture de M12-E12, attestations éventuelles) ; `--preserve-digests` fait **échouer** la copie plutôt que de convertir (un changement de format de manifeste changerait l'empreinte). Le script recalcule l'empreinte du manifeste brut des deux côtés.
7. Registre des secrets : robots (usage, porteur, emplacement, date d'expiration = date de création + 180 j, procédure de rotation), mot de passe d'`admin` (Vault + variable de `plateforme/infra`), mots de passe initiaux ; `registre-travail.env` et les comptes du registre de travail marqués « retirés ». Puis `ctr01` : retrait de `ctr01` du code de `envs/m12` (état `m12-conteneurs`), plan relu (seule `ctr01` et ses objets NetBox et DNS partent), application par le pipeline, `WB_M12_CTR01_CONSERVE` retiré de `lab/lab.env`.

**Explications**

Le robot de CI est **de projet** : une fuite de son jeton n'expose que `medisphere`. `k8s-pull` est **système** parce qu'il couvre plusieurs projets, mais n'a que `repository:pull`. Les identifiants de `wb-checks` sont lus par `harbor_api` (`lab/lib/check-lib.sh`) ; `repository:pull` lui permet de vérifier les signatures (Cosign lit le manifeste et les référents).

**Alternatives**

- Secrets des robots en **écriture seule** (`secret_wo` + `secret_wo_version`, fournisseur 3.12) : rien dans l'état, mais il faut générer et transporter les secrets hors d'OpenTofu (fichier, Vault au M25). Le fournisseur le propose (avertissement de `tofu validate`) ; à adopter au M25.
- Migration par **réplication *pull*** de Harbor (point d'accès `docker-registry` vers `ctr01:5000`, CA renseignée dans le point d'accès depuis 2.15) : traçable dans Harbor, mais il faut confier à Harbor les identifiants du registre de travail. Pour une migration unique, `skopeo` depuis `adm01` suffit.
- Membres déclarés par groupe (groupes OIDC, M24) plutôt qu'utilisateur par utilisateur.

**Pièges classiques**

- `insecure` laissé à sa valeur par défaut.
- `HARBOR_USER=robot$wb-checks` sans apostrophes dans un fichier sourcé : `$wb` est développé, l'utilisateur devient `robot-checks`. Même piège dans une variable GitLab non marquée « non développée ».
- Mot de passe généré avec des caractères spéciaux refusés par Harbor, ou trop court (politique : 8 à 128, majuscule, minuscule, chiffre).
- Robot sans date d'expiration (`duration` absent = jamais) : il ne sera jamais tourné.
- Copier les images avec `docker pull/tag/push` : une seule architecture, empreintes changées, attestations perdues.

**En production chez MédiSphère**

Rotation des robots planifiée (alerte à J-30 sur `expires_at`, M21), OIDC pour les humains (M24), secrets des robots dans OpenBao avec rotation automatique (M25), audit des actions par robot dans le journal de Harbor.

---

### M13-E04 — Des caches pour les registres publics

**Solution**

Fichiers : [`registre/caches.tf`](fichiers/M13-E04/infra/registre/caches.tf) ; [`gitlab_runner.yml.extrait`](fichiers/M13-E04/ansible/inventories/lab/host_vars/runner02/gitlab_runner.yml.extrait) ; rôle `podman_hote` : [`tasks/miroirs.yml`](fichiers/M13-E04/ansible/roles/podman_hote/tasks/miroirs.yml), [`templates/registries-miroirs.conf.j2`](fichiers/M13-E04/ansible/roles/podman_hote/templates/registries-miroirs.conf.j2), [`defaults-main.yml.extrait`](fichiers/M13-E04/ansible/roles/podman_hote/defaults-main.yml.extrait) ; [`group_vars/all/miroirs-registres.yml`](fichiers/M13-E04/ansible/inventories/lab/group_vars/all/miroirs-registres.yml) ; [`templates/image.yml.extrait`](fichiers/M13-E04/ci-templates/templates/image.yml.extrait) ; [`Dockerfile-FROM.extrait`](fichiers/M13-E04/applications/Dockerfile-FROM.extrait) ; [`docs/registre/caches.md`](fichiers/M13-E04/medisphere/docs/registre/caches.md).

1. Comportement (documentation « Configure Proxy Cache ») : par **étiquette**, Harbor interroge l'amont (requête légère sur le manifeste) pour savoir si l'étiquette désigne toujours la même empreinte, et tire la nouvelle si besoin ; par **empreinte**, il sert sa copie sans contacter l'amont ; amont injoignable : il sert ce qu'il a ; images non tirées : supprimées par une rétention par défaut du projet cache (⚠️ à vérifier sur ta version : onglet « Policy » du projet cache, 7 jours sans tirage).
2. `caches.tf` : le type du fournisseur pour GHCR s'écrit `github` (traduit en `github-ghcr` par le fournisseur), pour registry.k8s.io `docker-registry`.
3. Premiers tirages :
   ```
   admin@runner02:~$ sudo docker pull registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim
   admin@runner02:~$ sudo docker pull registry.par1.medisphere.internal/k8s/pause:3.10
   admin@runner02:~$ sudo docker pull registry.par1.medisphere.internal/ghcr/astral-sh/uv:0.12.23
   admin@runner02:~$ sudo docker pull registry.par1.medisphere.internal/quay/skopeo/stable:v1.18.0
   ```
   Dans Harbor, `dockerhub/library/debian` apparaît avec l'étiquette ; le tirage par empreinte suivant est servi localement (journal d'audit : `pull` sans nouvelle requête vers l'amont). `registry-mirrors` de Docker ne sert qu'à Docker Hub et attend les dépôts à la racine (`/v2/library/debian`) : Harbor les sert sous `/v2/dockerhub/library/debian`. Donc, côté Docker : le **nom du cache** dans chaque référence.
4. `config.toml` de `runner02` (par le rôle) : `image`, `allowed_images = ["registry.par1.medisphere.internal/**/*"]`, `allowed_services` idem, `allowed_pull_policies`. Un job `image: python:3.13` échoue avant de tirer : *« The "python:3.13" image is not present on list of allowed images »*. (⚠️ Syntaxe des motifs à vérifier sur ton GitLab Runner 19.4 : la documentation de l'exécuteur Docker décrit `*` et `**`.)
5. MR sur `templates/image.yml` (nouvelle version `1.x.y` du dépôt de gabarits) et sur les Dockerfiles : seul le préfixe change, **l'empreinte reste** (un cache sert le manifeste de l'amont tel quel, même empreinte) ; c'est aussi ce qui permet de vérifier une signature amont à travers le cache.
6. `podman_hote` : `registries.conf.d/50-miroirs-medisphere.conf`, un bloc `[[registry]]` (`prefix`, `location` = l'amont) et `[[registry.mirror]]` (`location` = le cache) par amont ; liste vide par défaut ; scénario Molecule : `podman pull docker.io/library/debian:trixie-slim` puis lecture des journaux de Harbor (ou `podman --log-level=debug pull` : « Trying to access registry.par1… »).
7. `docs/registre/caches.md`.

**Explications**

Le cache est **public** : tout le lab (selon la bordure) peut y tirer sans identifiant, ce qui simplifie containerd au M14 et Podman. Le contenu est public par nature ; le risque est la **consommation** (quotas par cache) et l'**arrivée d'images non contrôlées** (`allowed_images` sur `runner02`, Kyverno au M26). Le compte Docker Hub, s'il existe, ne sert qu'à relever la limite de tirage.

**Alternatives**

- Caches **privés** (tirage par robot) : traçabilité par identité, mais un identifiant de plus sur chaque nœud et chaque hôte.
- Un **miroir complet** (réplication *pull* planifiée d'une liste d'images) au lieu d'un cache à la demande : rien n'entre qu'on n'a pas choisi, mais il faut tenir la liste.
- `gcr.io` : un cinquième cache (type `docker-registry` vers `https://gcr.io`) aurait été possible ; on garde la liste du PLAN et on **copie** l'image distroless dans `bibliotheque` (une seule image, déjà contrôlée par le pipeline des images de base).

**Pièges classiques**

- Oublier `library/` pour les images officielles de Docker Hub (`…/dockerhub/debian` n'existe pas).
- Mettre le type « Docker Registry » pour Docker Hub : l'authentification et les limites de Docker Hub ne sont pas gérées comme avec le type dédié.
- Croire qu'un tirage par étiquette n'atteint jamais l'amont : il l'atteint (vérification), et compte parfois dans les limites de Docker Hub.
- Changer l'empreinte en changeant le préfixe : non, et si elle change, c'est qu'on a tiré une **autre** image.
- Oublier `allowed_services` : `services: postgres:18` passe encore par Docker Hub.

**En production chez MédiSphère**

Supervision de l'état des points d'accès et des quotas des caches, analyse planifiée de leur contenu, liste blanche d'images par politique d'admission (M26), helper image du runner elle aussi par le cache.

---

### M13-E05 — Analyser les images avec Trivy

**Solution**

Fichiers : rôle [`outils_supply_chain`](fichiers/M13-E05/ansible/roles/outils_supply_chain/), [`playbooks/outils-supply-chain.yml`](fichiers/M13-E05/ansible/playbooks/outils-supply-chain.yml), [`host_vars/adm01/outils_supply_chain.yml`](fichiers/M13-E05/ansible/inventories/lab/host_vars/adm01/outils_supply_chain.yml) ; [`registre/analyse.tf`](fichiers/M13-E05/infra/registre/analyse.tf) ; [`.trivyignore`](fichiers/M13-E05/mediagenda-api/.trivyignore) ; [`docs/registre/analyse.md`](fichiers/M13-E05/medisphere/docs/registre/analyse.md).

1. Le rôle : catalogue (version, URL, SHA-256, mode de signature, identité, émetteur), versions interdites, `get_url` avec `checksum`, `cosign verify-blob` si Cosign est présent (Cosign passe en premier : la version en place vérifie la suivante), `apt: deb:`, contrôle de `dpkg-query`. Vérification manuelle avant épinglage :
   ```
   admin@adm01:~/m13/e05$ B=https://github.com/aquasecurity/trivy/releases/download/v0.75.0
   admin@adm01:~/m13/e05$ curl -fLO $B/trivy_0.75.0_Linux-64bit.deb -fLO $B/trivy_0.75.0_Linux-64bit.deb.sigstore.json
   admin@adm01:~/m13/e05$ cosign verify-blob trivy_0.75.0_Linux-64bit.deb --bundle trivy_0.75.0_Linux-64bit.deb.sigstore.json \
       --certificate-oidc-issuer https://token.actions.githubusercontent.com \
       --certificate-identity https://github.com/aquasecurity/trivy/.github/workflows/reusable-release.yaml@refs/tags/v0.75.0
   Verified OK
   admin@adm01:~/m13/e05$ sha256sum trivy_0.75.0_Linux-64bit.deb
   b6d7b944b6cbf4e7de5b4bc6c3635900c50fed53b64b77b99a5fbc3136cd1d5d  trivy_0.75.0_Linux-64bit.deb
   ```
2. Base : `trivy image --download-db-only` puis `trivy version` (« Vulnerability DB: Version 2, UpdatedAt … ») ; cache `~/.cache/trivy` ; hors ligne : `--db-repository` vers une copie interne, ou `--skip-db-update` avec une base copiée.
3. Analyse des images :
   ```
   admin@adm01:~$ set -a; . ~/.config/workbook/harbor-moi.env; set +a
   admin@adm01:~$ export TRIVY_USERNAME="$HARBOR_USER" TRIVY_PASSWORD="$HARBOR_PASSWORD"
   admin@adm01:~$ for d in mediagenda-api medidoc medinotif legacy-rdv; do
       t=$(skopeo list-tags --creds "$HARBOR_USER:$HARBOR_PASSWORD" docker://registry.par1.medisphere.internal/medisphere/$d | jq -r '.Tags[]' | sort -V | tail -1)
       trivy image --format json -o ~/m13/e05/$d.json registry.par1.medisphere.internal/medisphere/$d:$t
       trivy image --severity CRITICAL,HIGH --ignore-unfixed registry.par1.medisphere.internal/medisphere/$d:$t | tail -20
     done
   ```
   (⚠️ `--creds` place le secret dans les arguments ; préfère `--authfile`, comme dans les scripts.) Les vulnérabilités de l'image de base (`debian`, cible `… (debian 13.x)`) dominent ; MédiDoc (statique, distroless) n'en a presque pas ; Legacy-RDV en a le plus (image PHP-Apache complète). La colonne `Fixed Version` décide de ce qui reste avec `--ignore-unfixed`.
4. Dépôt `mediagenda/api` :
   ```
   admin@adm01:~/src/mediagenda-api$ trivy fs --scanners vuln,secret --format json -o ~/m13/e05/mediagenda-fs.json .
   admin@adm01:~/src/mediagenda-api$ trivy config --format json -o ~/m13/e05/mediagenda-config.json .
   ```
   `trivy config` signale typiquement : absence de `HEALTHCHECK` dans le Dockerfile, conteneurs `compose.yaml` sans `read_only` ou sans `cap_drop` (selon ce que M12-E24 a déjà durci) ; les identifiants changent de forme depuis 0.69 (`DS-0026` au lieu de `AVD-DS-0026`, ⚠️ à vérifier sur ta sortie). On corrige ce qui est fondé (HEALTHCHECK, `cap_drop`) ; on justifie le reste.
5. `.trivyignore` : identifiant précédé d'un commentaire daté. Contrôle :
   ```
   admin@adm01:~/src/mediagenda-api$ trivy image --severity CRITICAL --ignore-unfixed --exit-code 1 --ignorefile .trivyignore registry…/medisphere/mediagenda-api:<VERSION>; echo $?
   ```
6. `analyse.tf` : `default_scanner = "Trivy"`, `vulnerability_scan_policy` en cron à six champs. Écarts avec Harbor : Trivy **0.74** dans l'adaptateur contre **0.75** en CLI, bases téléchargées à des moments différents, options (`ignore_unfixed` de `harbor.yml`).
7. `analyse.md`.

**Explications**

Le rôle vérifie la **signature** quand il le peut et l'**empreinte** toujours : si Sigstore est injoignable, l'installation reste sûre (empreinte épinglée après vérification humaine) ; si la signature d'un fichier ne passe plus, le rôle échoue (republication suspecte). Refuser explicitement 0.69.4-0.69.6 protège contre une MR qui « remonterait » par erreur une version piégée.

**Alternatives**

- Dépôt APT d'Aqua (`aquasecurity.github.io/trivy-repo`) : mises à jour par `apt`, mais confiance déléguée à une clé de dépôt et version moins maîtrisée (une montée de version arrive sans MR).
- Trivy en **mode client/serveur** (`trivy server` interne, une seule base) : utile à grande échelle.
- Format `.trivyignore.yaml` (expiration `expired_at`, chemins, `purl`) : plus fin ; VEX pour les exceptions de produit.

**Pièges classiques**

- Copier l'empreinte depuis `checksums.txt` **sans** vérifier le bundle.
- `--exit-code 1` sans `--severity` : tout fait échouer, l'équipe met `allow_failure` (voir E12).
- Analyser par étiquette et conclure sur une autre empreinte.
- Ignorer une CVE dans le `.trivyignore` alors qu'un correctif existe dans une nouvelle empreinte de l'image de base : c'est Renovate (E11) qu'il fallait.

**En production chez MédiSphère**

Base de Trivy servie en interne, exceptions revues mensuellement (rapport), analyse nocturne dont les nouvelles critiques ouvrent un ticket (M21), VEX publiés pour les images livrées à des clients.
