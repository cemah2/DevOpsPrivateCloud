# Module 13 — Palier 1 : Découverte

Un registre ne vaut que par ce qu'on peut prouver sur ce qu'il contient. Ce palier commence par un questionnaire sur la chaîne d'approvisionnement logicielle, puis installe **Harbor** sur `reg01` par le code, avec un installateur dont tu vérifies toi-même la signature. Tu y crées les projets, les comptes humains et les robots, tu y migres les images du registre de travail du module 12, tu mets en place les **caches** des registres publics, et tu découvres l'analyse de vulnérabilités avec **Trivy**, en ligne de commande et intégré à Harbor.

Prérequis : module 12 terminé (`lab/bin/check 12 46` vert : images des quatre applications, `runner02`, pipeline de construction sans privilège, registre de travail sur `ctr01`) ; module 06 (step-ca ACME, PowerDNS, NetBox) ; module 05 (OpenTofu, état chiffré). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les règles du module.

---

### M13-E01 — Questions : la chaîne d'approvisionnement logicielle  `Q` `★★`

> **Ticket PLAT-1401** — *De : Karim Benali*
> Avant d'installer quoi que ce soit, on parle le même langage. Une heure, par écrit, sans moteur de recherche ni IA. Registres, empreintes, SBOM, signatures, SLSA, et ce que les incidents récents nous ont appris. Réponds même là où tu hésites : le raisonnement compte plus que le mot exact.

**Objectifs pédagogiques**
- Évaluer tes acquis sur les images OCI, les registres et la sécurité de la chaîne d'approvisionnement.
- Relier chaque mécanisme du module (cache, analyse, SBOM, signature, attestation, mise à jour automatique) au risque qu'il traite.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Images et registres*

1. Une image `python:3.13-slim-trixie` est tirée lundi puis vendredi sur deux serveurs. Pourquoi les deux serveurs peuvent-ils exécuter des contenus différents ? Comment l'empêcher, et quel prix paie-t-on ?

2. *(QCM)* L'empreinte `sha256:…` affichée par `docker pull` pour une image multi-architecture est celle :
   - A. de la couche la plus haute de l'image
   - B. du fichier de configuration de l'image (`config`)
   - C. de l'index (*manifest list*) qui référence un manifeste par architecture
   - D. de l'archive `docker save` de l'image

3. Qu'apporte un **cache** de registre public (*pull-through* ou *proxy cache*) à une entreprise ? Donne trois bénéfices et un risque nouveau qu'il introduit.

4. Un dépôt d'images public est supprimé par son auteur (ou une étiquette est réécrite par un attaquant). Que se passe-t-il pour une entreprise qui tirait l'étiquette directement ? Et pour une entreprise qui la tirait par un cache, par étiquette ? Par empreinte ?

5. Pourquoi l'**immuabilité des étiquettes** d'un registre ne remplace-t-elle pas le déploiement par empreinte ?

*Analyse de vulnérabilités*

6. Une analyse remonte 140 CVE sur une image `debian:trixie-slim`, dont 3 « critiques » sans version corrigée. Quelles questions poses-tu avant de décider d'un blocage ? Que signifient pour toi **CVSS**, **EPSS** et le catalogue **KEV** de la CISA ?

7. *(QCM)* L'option `--ignore-unfixed` d'un analyseur :
   - A. masque les vulnérabilités qui n'ont pas encore de correctif publié
   - B. masque les vulnérabilités que l'équipe a déjà déclarées traitées
   - C. supprime les paquets vulnérables de l'image
   - D. désactive la mise à jour de la base de vulnérabilités

8. Deux analyseurs (par exemple Trivy et Grype) donnent des listes différentes pour la même image. Donne trois raisons possibles.

9. Qu'est-ce qu'un document **VEX** et à quel problème répond-il que le fichier d'exceptions local d'un analyseur résout mal ?

*SBOM et provenance*

10. Qu'est-ce qu'une **SBOM** ? Cite les deux formats normalisés principaux et ce que contient au minimum chaque composant. Pourquoi la conserver, alors qu'on peut réanalyser l'image à tout moment ?

11. Distingue une **signature** d'image et une **attestation**. Donne un exemple d'attestation utile au moment d'un audit.

12. Résume les niveaux de **SLSA** (piste *Build*) en une phrase chacun. À quel niveau correspond un pipeline GitLab CI auto-hébergé qui produit une provenance signée par une clé dont le pipeline lui-même dispose ?

*Signature*

13. Que signe exactement Cosign quand on lance `cosign sign … image@sha256:…` ? Pourquoi signer **par empreinte** et non par étiquette ?

14. *(QCM)* Avec Cosign 3 et un registre compatible OCI 1.1, la signature d'une image est stockée :
    - A. dans une étiquette `sha256-<empreinte>.sig` du même dépôt
    - B. comme un artefact **référent** dont le champ `subject` désigne le manifeste signé
    - C. dans le journal de transparence public uniquement
    - D. dans les annotations du manifeste de l'image, qui change donc d'empreinte

15. Explique la signature **sans clé** (*keyless*) de Sigstore : rôle de l'identité OIDC, de Fulcio, de Rekor. Pourquoi MédiSphère ne l'utilise-t-elle pas avec les services publics, et que faudrait-il pour l'utiliser en privé ?

16. La clé privée de signature de MédiSphère est volée. Que peut faire l'attaquant ? Que fais-tu dans l'heure, et qu'aurait-il fallu prévoir avant ?

*Incidents et mises à jour*

17. **SolarWinds** (2020) : qu'est-ce qui a été compromis, et pourquoi les signatures des éditeurs n'ont-elles rien empêché ? Quel principe de SLSA vise ce scénario ?

18. **xz-utils** (CVE-2024-3094) : en quoi l'attaque différait-elle d'une vulnérabilité classique ? Pourquoi la porte dérobée n'était-elle pas visible dans le dépôt Git, et qu'est-ce que cela dit de la confiance dans les archives de distribution ?

19. **Trivy, mars 2026** : un outil de sécurité publié piégé, des étiquettes d'actions CI réécrites, des images piégées. Cite quatre mesures qui auraient protégé un pipeline consommateur, et explique pourquoi « épingler la version » ne suffit pas.

20. Les mises à jour automatiques de dépendances (Renovate, Dependabot) réduisent le temps d'exposition aux CVE connues, mais elles peuvent aussi **accélérer** l'arrivée d'une version piégée. Quels réglages concilient les deux ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 20 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille du corrigé (0, 1 ou 2 points) et calculé ton score sur 40.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour chaque mécanisme, demande-toi : qu'est-ce qui est **adressé par son contenu** (et ne peut donc pas changer sans changer de nom), et qu'est-ce qui est un **pointeur** qu'on peut déplacer ?
</details>

<details><summary>Indice 2</summary>

Pour les incidents, sépare trois choses : la **source** (le code), la **construction** (la machine et le processus qui produisent le binaire), la **distribution** (le canal par lequel le binaire arrive chez toi). Chaque attaque célèbre vise un maillon différent.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M13-E25), sans relire le corrigé, et compare.

---

### M13-E02 — Installer Harbor sur `reg01`  `LAB` `★★`

> **Ticket PLAT-1402** — *De : Karim Benali* — *Copie : Claire Morel, Sophie Laurent*
> Harbor rejoint le socle : `reg01`, VMID 1013, 10.10.20.18, et un seul nom pour les clients, `registry.par1.medisphere.internal`, qui pourra suivre si on déplace le service un jour. Installateur **hors ligne**, de la version que l'on a choisie, dont tu vérifies la provenance avant de l'épingler : après l'histoire de Trivy, je ne veux plus d'archive « téléchargée et lancée ». Les données de Harbor sur leur propre disque. Un certificat de notre PKI qui se renouvelle seul. Et un rôle Ansible : si `reg01` brûle, on le reconstruit en une commande (RB-130).

**Objectifs pédagogiques**
- Vérifier la provenance d'un logiciel distribué (bundle Sigstore d'une release, identité du pipeline de publication) et l'épingler par empreinte.
- Ajouter un hôte permanent au socle par le code (VM, disque de données, DNS, NetBox, flux).
- Comprendre comment l'installateur de Harbor fonctionne (`harbor.yml`, `prepare`, Compose) et l'automatiser proprement (rôle idempotent, unité systemd, ordre de démarrage).
- Raccorder un service conteneurisé au renouvellement automatique de ses certificats.

**Prérequis** : M12-E20 (rôle `docker_engine`, `runner02`) ; M06-E13, M06-E14 (NetBox, DNS par OpenTofu) ; M06-E18 (rôle `certificats_acme`) ; M07-E30 (matrice des flux commune de la bordure).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VM | `reg01`, VMID 1013, pool `lab`, étiquettes `socle` et `role-registre`, 2 vCPU, 6144 Mo, démarrage automatique ; `net0` sur `vinfra`, 10.10.20.18/24 imposée ; disque système `scsi0` 32 Gio sur `local-nvme` ; disque de données `scsi1` 200 Gio sur `hdd-bulk`, numéro de série `reg01-donnees`, **exclu** de la sauvegarde PBS de la VM |
| Code | état `socle` de `plateforme/infra` (`socle/reg01.tf`) ; module `vm-debian` de `plateforme/tofu-modules`, qui n'accepte aujourd'hui qu'un disque : à étendre (version **mineure**) |
| DNS | A et PTR `reg01.par1.medisphere.internal` ; CNAME `registry.par1.medisphere.internal.` → `reg01.par1.medisphere.internal.` (zone `par1`, écrite par l'API de l'autoritaire comme les autres enregistrements de l'état `socle`) |
| Installateur | `harbor-offline-installer-v2.15.3.tgz` (environ 700 Mo) et son bundle Sigstore `harbor-offline-installer-v2.15.3.tgz.sigstore.json`, publiés dans la release `v2.15.3` de `github.com/goharbor/harbor` ; le fichier `md5sum` de la release n'est **pas** une preuve de provenance |
| Cosign sur `adm01` | Cosign **3.1.3** de la release `github.com/sigstore/cosign` (paquet `cosign_3.1.3_amd64.deb`, son bundle `.sigstore.json`, `cosign_checksums.txt`) ; les releases de Cosign sont signées en *keyless* par l'identité `keyless@projectsigstore.iam.gserviceaccount.com` (émetteur `https://accounts.google.com`) ; Debian 13 fournit un paquet `cosign` 2.5 |
| Ansible | groupe `role_registre` (étiquette NetBox `role-registre`, à ajouter au modèle par le script de M06-E05) ; rôles : communs du socle, `docker_engine` (M12), `certificats_acme` (id `harbor`), `harbor` (à écrire) ; playbook `playbooks/registre.yml` ; secrets `vault_harbor_admin_mdp` et `vault_harbor_db_mdp` dans `group_vars/role_registre/vault-critique.yml` (identité `critique`) |
| Harbor | `hostname: registry.par1.medisphere.internal` ; HTTP 80 (redirige vers HTTPS), HTTPS 443 ; `data_volume: /data` ; Trivy activé (`--with-trivy`) ; métriques **désactivées** pour l'instant (palier 3) |
| Certificat | noms `registry.par1.medisphere.internal` (sujet) et `reg01.par1.medisphere.internal` ; fichiers sources dans `/etc/harbor/tls/` ; le script `prepare` les **copie** dans `/data/secret/cert/server.crt` et `server.key`, que le conteneur `nginx` lit sous `/etc/cert/` |
| Flux | VLAN 40 et VLAN 99 → `reg01` TCP 443 à ouvrir dans `group_vars/role_routeur/pare_feu.yml` ; le reste existe (introduction, « Ports et flux ») |

**Travail demandé**

*A. Cosign sur `adm01`, et la provenance de l'installateur*

1. Sur `adm01`, télécharge dans `~/m13/e02/` le paquet `cosign_3.1.3_amd64.deb`, son bundle et `cosign_checksums.txt`. Tu n'as pas encore de Cosign 3 pour vérifier Cosign 3 : utilise le `cosign` 2.5 de Debian (paquet signé par l'archive Debian, donc de confiance pour ce seul usage) pour vérifier le bundle du `.deb`, avec l'identité et l'émetteur du contexte technique. Lis `cosign verify-blob --help` : en version 2.x, le format *bundle* de Cosign 3 demande une option.
2. Contrôle aussi l'empreinte SHA-256 du `.deb` contre `cosign_checksums.txt`. Installe-le, retire le `cosign` de Debian, vérifie `cosign version`. Note dans ton journal pourquoi la vérification de signature **et** celle de l'empreinte ont chacune un rôle.
3. Télécharge l'installateur hors ligne de Harbor 2.15.3 et son bundle. Lis le bundle (`jq`) et le certificat qu'il contient (`openssl x509 -text`) : quelle **identité** a signé, depuis quel **workflow**, pour quelle **étiquette** Git ? Vérifie la signature avec `cosign verify-blob` en imposant cette identité et l'émetteur `https://token.actions.githubusercontent.com`. Calcule l'empreinte SHA-256 de l'archive : c'est elle que le rôle épinglera.
4. Que vérifierais-tu de plus avant d'accepter une **nouvelle** version dans six mois (journal des modifications, avis de sécurité, chemin de mise à jour) ? Écris-le dans le brouillon de RB-130.

*B. La VM, les noms, les flux*

5. Étends `vm-debian` d'une liste **facultative** de disques de données (stockage, taille, série, sauvegarde), sans changer le plan d'aucun consommateur existant. Publie une version **mineure** de `plateforme/tofu-modules`. Pourquoi ne pas utiliser `vm-noeud` pour `reg01` ?
6. Ajoute `socle/reg01.tf` : la VM, ses enregistrements A et PTR, le CNAME `registry`. Ajoute l'étiquette `role-registre` au modèle NetBox. `plan` lu et commenté dans la MR, `apply` par le pipeline. Pose l'ordre de démarrage de la VM (après le DNS et la PKI) comme pour les autres hôtes du socle.
7. Ouvre les flux VLAN 40 et VLAN 99 → `reg01:443` dans la matrice de la bordure (MR, motif, référence `M13-E02`), régénère `docs/socle/matrice-flux.md`.
   > ⚠️ **Attention** : la matrice s'applique aux **deux** passerelles. Suis la procédure du module 07 (filet anti-coupure du rôle `pare_feu`, une passerelle à la fois, la secondaire d'abord) et garde une console Proxmox ouverte sur `gw01`.

*C. Le rôle `harbor`*

8. Avant d'écrire le rôle, décompresse l'archive dans `~/m13/e02/` et lis `install.sh`, `prepare` et `harbor.yml.tmpl`. Réponds dans ton journal : que fait `install.sh` à chaque lancement (pense à `down -v`) ? Où `prepare` écrit-il ce qu'il génère ? Que deviennent le certificat et la clé indiqués dans `harbor.yml` ? Quel nom de projet Compose les conteneurs reçoivent-ils, et pourquoi cela compte-t-il pour une montée de version ?
9. Écris le rôle `harbor`. Exigences :
   - refus de tout autre système que Debian 13 ; disque de données formaté (XFS) et monté sur `/data` par son **identifiant stable**, pas par `/dev/sdb` ;
   - le démon Docker ne démarre qu'**après** le montage de `/data` (sinon les conteneurs à `restart: always` démarreraient sur un `/data` vide) ;
   - archive téléchargée **sur `reg01`** et vérifiée par l'empreinte épinglée ; installation dans un dossier par version, lien `/opt/harbor` vers la version active ; le rôle **refuse** de changer de version sans une variable explicite (la montée de version est une procédure, palier 3) ;
   - `harbor.yml` rendu à partir du `harbor.yml.tmpl` **de la version** (garde les clés de ce gabarit, n'en invente pas), mode 600, mots de passe depuis le Vault `critique` ;
   - `install.sh --with-trivy` lancé **une seule fois** (première installation) ; ensuite, un changement de `harbor.yml` relance `prepare` puis redémarre la pile ;
   - unité `harbor.service` qui démarre et arrête la pile Compose, active au démarrage ;
   - un script de rechargement du certificat (copie dans `/data/secret/cert/` en conservant propriétaire et droits, puis rechargement de nginx dans son conteneur), appelé par `cert-renewer@harbor` ;
   - pour finir, `/api/v2.0/health` interrogé par son nom, TLS vérifié, jusqu'à « healthy ».
10. Écris `host_vars/reg01/certificats.yml` (rôle `certificats_acme`) et `playbooks/registre.yml`. L'ordre compte : quels prérequis du rôle `harbor` doivent exister **avant** l'émission du certificat, et pourquoi le port 80 doit-il être libre à ce moment-là ?
11. Applique par le pipeline de `plateforme/ansible`. Second passage : `changed=0`. Redémarre `reg01` (`qm reboot 1013` sur `pve01`) et vérifie que Harbor revient seul, en bonne santé.
12. Connecte-toi à l'IHM avec `admin` (mot de passe du Vault) ; n'y crée rien : la configuration est l'objet de E03. Lis la page « Configuration > System Settings » et l'API (`/devcenter-api-2.0`).
13. Rédige RB-130 « Installer ou reconstruire `reg01` » dans `docs/registre/runbooks/` (vérification de l'installateur, ordre OpenTofu → Ansible, contrôles de fin) ; mets à jour l'inventaire de la plateforme et le registre des secrets.

**Critères de réussite**
- [ ] La VM 1013 `reg01` est créée par OpenTofu (état `socle`) conforme au contexte technique (2 vCPU, 6144 Mo, `vinfra`, disque système 32 Gio sur `local-nvme`, disque de 200 Gio sur `hdd-bulk` exclu de la sauvegarde), décrite dans NetBox (IP primaire 10.10.20.18/24).
- [ ] `reg01.par1.medisphere.internal` résout en A et PTR ; `registry.par1.medisphere.internal` est un CNAME vers `reg01`.
- [ ] Sur `reg01` : `/data` est un XFS monté depuis le disque de 200 Gio ; Docker 29 et Compose v5 ; `harbor.service` actif et activé ; les conteneurs de Harbor 2.15.3, dont `trivy-adapter`, en bonne santé ; `harbor.yml` en 600, sans le mot de passe par défaut.
- [ ] `https://registry.par1.medisphere.internal/api/v2.0/health` répond « healthy » depuis `adm01` et `runner02`, TLS vérifié ; le certificat est émis par l'intermédiaire MédiSphère, couvre les deux noms, dure 30 jours au plus ; `cert-renewer@harbor.timer` est actif.
- [ ] La bordure laisse passer VLAN 40 et VLAN 99 vers `reg01:443` ; la matrice des flux documentée mentionne `reg01`.
- [ ] Cosign 3.1.x est installé sur `adm01` ; le rôle `harbor`, le playbook et `socle/reg01.tf` sont sur `main` ; RB-130 est publié.

**Vérification** : `lab/bin/check 13 02`

<details><summary>Indice 1</summary>

Le certificat d'un bundle Sigstore est dans `verificationMaterial.certificate.rawBytes` (DER en base64). Ses extensions OID `1.3.6.1.4.1.57264.1.*` décrivent l'émetteur OIDC, le dépôt, le workflow, la référence Git. Côté OpenTofu, un `dynamic "disk"` dont la liste par défaut est vide ne change aucun plan existant ; un disque de données branché sur `scsi1` reçoit un numéro de série visible dans `/dev/disk/by-id/`.
</details>

<details><summary>Indice 2</summary>

`install.sh` arrête l'instance existante avec `docker compose down -v` puis relance `prepare` et `up -d` : le relancer à chaque passage d'Ansible redémarrerait Harbor pour rien. Le module `command` d'Ansible a une option qui rend une commande idempotente si elle produit un fichier. Pour l'ordre de démarrage, une surcharge systemd (`RequiresMountsFor=`) sur `docker.service` dit à systemd d'attendre un point de montage.
</details>

<details><summary>Indice 3</summary>

Le rôle `certificats_acme` lance ses crochets (`avant_emission`, `recharger`…) avec le module `command` : pas de `||`, pas de redirection. Un script installé par le rôle `harbor` **avant** `certificats_acme` règle la question ; il doit sortir proprement quand Harbor n'est pas encore installé (premier passage). Le conteneur du mandataire s'appelle `nginx` (service `proxy` du `docker-compose.yml` généré).
</details>

**Pour aller plus loin** (facultatif) : compare l'installateur hors ligne et le chart Helm de Harbor (qui servira si le registre migre un jour dans Kubernetes) : qu'est-ce qui change pour la sauvegarde, la mise à jour et la haute disponibilité ?

---

### M13-E03 — Projets, membres et comptes robots  `LAB` `★★`

> **Ticket PLAT-1403** — *De : Karim Benali* — *Copie : Julien Petit*
> Harbor tourne ; maintenant on le remplit, **par le code** : projets, comptes, droits, robots. Quatre projets privés pour commencer. Julien pousse ses images mais ne touche pas aux réglages du projet ; Lucas regarde sans rien pousser. La CI pousse avec un robot du projet, les nœuds Kubernetes tireront avec un robot système, et les vérifications du workbook lisent avec un robot qui ne peut **rien** écrire. Tous les robots expirent. Ensuite, on vide le registre de travail de `ctr01` dans Harbor, empreintes intactes.

**Objectifs pédagogiques**
- Décrire la configuration d'un service par l'API avec OpenTofu (fournisseur `goharbor/harbor`) dans un état séparé de l'infrastructure.
- Distinguer les rôles de projet de Harbor et les permissions des comptes robots ; appliquer le moindre privilège.
- Migrer des images entre registres sans changer leurs empreintes.

**Prérequis** : M13-E02 ; M05-E27 (état chiffré) ; M12-E15 (registre de travail sur `ctr01`, `~/.config/workbook/registre-travail.env`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| État | dossier `registre/` de `plateforme/infra`, clé `registre/terraform.tfstate`, même *backend* et même chiffrement que `socle` ; fournisseur `goharbor/harbor` `~> 3.12` (et `hashicorp/random` pour les secrets) ; variables protégées et masquées du projet `plateforme/infra` : `HARBOR_URL`, `HARBOR_USERNAME` (`admin`), `HARBOR_PASSWORD` |
| Projets | `medisphere`, `plateforme`, `bibliotheque`, `charts` : privés, analyse à la poussée laissée active |
| Utilisateurs (base locale) | `<MOI>`, `karim.benali`, `julien.petit`, `lucas.martin` (adresses `@medisphere.internal`) |
| Rôles dans `medisphere` | `<MOI>` et `karim.benali` : administrateurs du projet ; `julien.petit` : développeur ; `lucas.martin` : invité (lecture) |
| Robots | `medisphere+ci` (projet `medisphere` : poussée, tirage, lecture des artefacts et des étiquettes, création d'étiquettes) ; `bibliotheque+ci` (idem sur `bibliotheque`) ; `k8s-pull` (système : tirage seul sur `medisphere`, `plateforme`, `bibliotheque`, `charts`) ; `wb-checks` (système : lecture seule, voir ci-dessous) ; durée de vie **180 jours** au plus |
| `wb-checks` | lecture des projets, de leurs métadonnées, membres, robots, quotas, dépôts, artefacts, étiquettes, accessoires (signatures), analyses, SBOM, règles d'immuabilité et de rétention ; lecture des registres distants, de la réplication, du ramasse-miettes, de l'analyse planifiée, des analyseurs ; **tirage** des dépôts (vérification des signatures) ; aucune action `create`, `update`, `delete`, `push`, `stop` |
| Fichiers | `~/.config/workbook/harbor-checks.env` et `~/.config/workbook/harbor-moi.env` (600) : `HARBOR_USER=…` et `HARBOR_PASSWORD=…` |
| Migration | registre de travail `ctr01.par1.medisphere.internal:5000` (M12-E15) : `mediagenda/api`, `medidoc/medidoc`, `medinotif/worker`, `legacy/legacy-rdv`, images de base `bibliotheque/*` (M12-E27) ; cibles : `medisphere/mediagenda-api`, `medisphere/medidoc`, `medisphere/medinotif`, `medisphere/legacy-rdv`, `bibliotheque/<même nom>` ; **toutes** les étiquettes, **toutes** les architectures, empreintes conservées |

**Travail demandé**

1. Lis la liste des permissions qu'un robot peut recevoir : `GET /api/v2.0/permissions` (avec `admin`, depuis `adm01`, mot de passe lu dans un fichier), et la page « Robot Accounts » de la documentation. Compare-la aux rôles de projet (*Project Admin*, *Maintainer*, *Developer*, *Guest*, *Limited Guest*) : qu'est-ce qu'un développeur peut faire qu'un invité ne peut pas, et inversement qu'est-ce qu'un robot peut recevoir qu'aucun rôle de projet ne donne ?
2. Crée la configuration racine `registre/` : versions, *backend*, chiffrement, fournisseur (lis sa documentation : **attention à la valeur par défaut de `insecure`**). Pourquoi un état séparé de `socle` ?
3. Déclare les utilisateurs (mots de passe générés, conformes à la politique de Harbor), les projets, les membres de `medisphere`, les quatre robots. Les secrets des robots et des utilisateurs sont des **sorties sensibles** : comment les récupères-tu sans les écrire dans le journal du pipeline ?
4. `plan` lu dans la MR, `apply` par le pipeline. Récupère les secrets depuis `adm01` (l'état est chiffré : tu as la phrase), écris `harbor-checks.env` et `harbor-moi.env` en 600. Transmets leur mot de passe initial aux personnages comme tu le ferais à de vrais collègues (registre des secrets : où, comment).
5. Vérifie les droits **par l'échec** : avec `harbor-checks.env`, une lecture de projet réussit et une création de projet échoue (403) ; avec le robot `k8s-pull`, `skopeo` peut lire un manifeste mais pas pousser.
   ```
   admin@adm01:~$ ( . ~/.config/workbook/harbor-checks.env
     curl -sf -u "$HARBOR_USER:$HARBOR_PASSWORD" https://registry.par1.medisphere.internal/api/v2.0/projects?name=medisphere | jq '.[].name' )
   ```
   > ⚠️ **Attention** : `curl -u utilisateur:secret` place le secret dans les arguments du processus, visibles par `ps` le temps de la requête. Acceptable sur ton poste d'administration personnel pour une exploration ; dans un script, utilise un fichier `--netrc-file` en 600 ou `--config`.
6. Migre les images du registre de travail : écris `outils/migrer-registre-travail.sh` (dépôt `plateforme/outils`) qui, pour chaque dépôt source et chaque étiquette, copie l'image vers sa cible avec `skopeo`, toutes architectures, empreintes **préservées** (et refuse sinon), en lisant les identifiants dans des fichiers (`--authfile`), jamais en argument. Lance-le depuis `adm01`, puis compare les empreintes source et cible d'au moins une image multi-architecture.
7. Mets à jour le registre des secrets et l'inventaire de la plateforme. Une fois les empreintes comparées, `ctr01` et son registre de travail n'ont plus d'usage : détruis la VM par le code (état `m12-conteneurs`), retire `WB_M12_CTR01_CONSERVE` de `lab/lab.env` et, si elles existent encore, les règles de la matrice des flux qui visent `ctr01`. Jusqu'à E09, les jobs de publication des applications échouent faute de registre : c'est attendu, la chaîne de E09 les remplace.

**Critères de réussite**
- [ ] `~/.config/workbook/harbor-checks.env` et `harbor-moi.env` existent en 600 ; le robot `wb-checks` lit l'API et **ne peut pas** créer de projet.
- [ ] Les projets `medisphere`, `plateforme`, `bibliotheque` et `charts` existent et sont privés.
- [ ] Dans `medisphere`, `<MOI>` et `karim.benali` sont administrateurs du projet, `julien.petit` développeur, `lucas.martin` invité.
- [ ] Les robots `robot$medisphere+ci`, `robot$bibliotheque+ci`, `robot$k8s-pull` et `robot$wb-checks` existent, expirent dans 180 jours au plus ; `k8s-pull` et `wb-checks` n'ont aucune permission d'écriture ; `medisphere+ci` ne peut pousser que dans `medisphere`.
- [ ] Les dépôts `medisphere/mediagenda-api`, `medisphere/medidoc`, `medisphere/medinotif` et `medisphere/legacy-rdv` contiennent les images migrées, aux mêmes empreintes que sur le registre de travail ; `bibliotheque` contient les images de base.
- [ ] La configuration `registre/` est sur `main` de `plateforme/infra`, fournisseur épinglé, `insecure = false`.

**Vérification** : `lab/bin/check 13 03`

<details><summary>Indice 1</summary>

Le fournisseur `goharbor/harbor` lit `HARBOR_URL`, `HARBOR_USERNAME` et `HARBOR_PASSWORD` dans l'environnement : aucune valeur dans le code. Les membres d'un projet se déclarent avec une ressource par utilisateur ; les robots avec des blocs `permissions` (`kind`, `namespace`, `access { resource, action }`), où `namespace = "*"` désigne tous les projets et `"/"` le niveau système.
</details>

<details><summary>Indice 2</summary>

`tofu output -json <sortie>` lit une sortie sensible sans l'afficher dans un `plan`. Pour `skopeo`, regarde `--all`, `--preserve-digests`, `--src-authfile`, `--dest-authfile` et `skopeo list-tags`. Un fichier d'authentification se fabrique avec `skopeo login --authfile <fichier> --password-stdin`.
</details>

<details><summary>Indice 3</summary>

Le nom complet d'un robot de projet est `robot$<projet>+<nom>` : le `$` est un piège dans tout ce qui développe les variables (shell entre guillemets doubles, `.env` lus par certains outils, variables GitLab). Le fournisseur expose `full_name`.
</details>

**Pour aller plus loin** (facultatif) : Harbor sait aussi **tirer** depuis un autre registre par une règle de réplication *pull-based* (point d'accès de type `docker-registry`). Compare avec `skopeo` : qui porte les identifiants, qui garde la trace, que se passe-t-il pour la CA de `ctr01` ?

---

### M13-E04 — Des caches pour les registres publics  `LAB` `★★`

> **Ticket PLAT-1404** — *De : Karim Benali* — *Copie : Nadia Roussel*
> Docker Hub nous a encore limités hier soir : six jobs en échec pour un `toomanyrequests`. Et Sophie veut savoir quelles images publiques entrent chez nous. À partir d'aujourd'hui, `runner02` et tout ce qui tire des images publiques passe par Harbor : Docker Hub, Quay, GHCR, registry.k8s.io. Les images de base de nos Dockerfiles et les images de nos jobs aussi.

**Objectifs pédagogiques**
- Configurer des points d'accès de registres distants et des projets cache (*proxy cache*) dans Harbor.
- Comprendre le comportement d'un cache (premier tirage, empreinte, disponibilité de l'amont, nom des dépôts).
- Faire utiliser les caches par un exécuteur GitLab Docker, par les Dockerfiles et par Podman.

**Prérequis** : M13-E03 ; M12-E20 (`runner02`, exécuteur `docker`) ; M12-E21 (gabarit `templates/image.yml`) ; M12-E02 (rôle `podman_hote`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Points d'accès (*registries*) | `dockerhub` (type Docker Hub, `https://hub.docker.com`), `quay` (type Quay, `https://quay.io`), `ghcr` (type GitHub GHCR, `https://ghcr.io`), `k8s` (type Docker Registry, `https://registry.k8s.io`) ; identifiants Docker Hub facultatifs (un compte gratuit relève la limite de tirage) |
| Projets cache | `dockerhub`, `quay`, `ghcr`, `k8s`, **publics** (tirage anonyme depuis le lab ; le contenu est public par nature, l'accès réseau est limité par la bordure) |
| Noms | `registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim` (images officielles : préfixe `library/`), `…/ghcr/astral-sh/uv:0.12.23`, `…/quay/skopeo/stable:v1.18.0`, `…/k8s/pause:3.10` |
| `runner02` | `config.toml` géré par le rôle `gitlab_runner` (M12-E20) : image par défaut, liste d'images autorisées |
| Podman | rôle `podman_hote` (M12) : `registries.conf` ; Podman sait utiliser un **miroir** avec un chemin (`location = "hôte/projet"`), Docker non |
| Images gcr.io | `gcr.io/distroless/static-debian13` (MédiDoc) : pas de cache `gcr` prévu ; l'image est copiée dans `bibliotheque` par le pipeline des images de base |

**Travail demandé**

1. Lis la page « Configure Proxy Cache » de la documentation de Harbor. Note : quand Harbor contacte-t-il l'amont pour un tirage par étiquette ? par empreinte ? Que se passe-t-il si l'amont est injoignable ? Que deviennent les images du cache qui ne sont plus tirées ?
2. Déclare dans l'état `registre` les quatre points d'accès et les quatre projets cache (fichier `caches.tf`), avec un quota par cache (Docker Hub 40 Gio, GHCR 20 Gio, Quay 10 Gio, registry.k8s.io 15 Gio). MR, `apply` par le pipeline. Dans l'IHM, « Registries » : l'état de chaque point d'accès est « Healthy ».
3. Depuis `runner02`, tire une image par chaque cache, puis observe dans Harbor ce qui est apparu (dépôts, artefacts, étiquettes). Retire l'image locale et tire-la de nouveau **par empreinte** : d'où vient-elle cette fois ? Lis `docker info` : pourquoi le réglage `registry-mirrors` du démon Docker ne convient-il pas à un cache Harbor ?
4. Fais passer l'exécuteur de `runner02` par les caches, par le rôle `gitlab_runner` : image par défaut tirée du cache, et **liste d'images autorisées** limitée à `registry.par1.medisphere.internal` (lis la documentation de l'exécuteur Docker : `allowed_images`, `allowed_pull_policies`). Qu'arrive-t-il à un job qui déclare encore `image: python:3.13` ?
5. Mets à jour le gabarit `templates/image.yml` de `plateforme/ci-templates` (nouvelle version `1.x.y`, que la branche `v1` suit) et les Dockerfiles des quatre applications (`FROM`, `COPY --from`) pour passer par les caches (une MR par projet). Les images de base épinglées par empreinte au M12 gardent leur empreinte : pourquoi ?
6. Étends le rôle `podman_hote` pour déclarer des miroirs (Docker Hub, Quay, GHCR, registry.k8s.io) dans `registries.conf` à partir d'une variable, sans changer les hôtes qui ne la définissent pas ; teste avec son scénario Molecule.
7. Documente dans `docs/registre/caches.md` les noms à utiliser, le comportement en cas de panne de l'amont, et la façon de demander l'ajout d'un registre amont.

**Critères de réussite**
- [ ] Harbor a quatre points d'accès sains, de types Docker Hub, Quay, GitHub GHCR et Docker Registry (registry.k8s.io).
- [ ] Les projets `dockerhub`, `quay`, `ghcr` et `k8s` sont des caches de ces points d'accès, publics, avec un quota.
- [ ] Chaque cache contient au moins un dépôt (dont `dockerhub/library/debian`).
- [ ] Sur `runner02`, l'exécuteur tire par défaut une image du cache et n'autorise que `registry.par1.medisphere.internal` ; des images des caches sont présentes localement.
- [ ] Le gabarit `templates/image.yml` de `plateforme/ci-templates` (sur `main`) ne désigne plus aucune image hors de Harbor ; le rôle `podman_hote` sur `main` sait déclarer des miroirs vers les caches.

**Vérification** : `lab/bin/check 13 04`

<details><summary>Indice 1</summary>

Dans le fournisseur OpenTofu, un projet devient un cache quand on lui donne le `registry_id` d'un point d'accès. Les noms des types de points d'accès ne sont pas ceux de l'IHM : lis la liste des valeurs de `provider_name` dans la documentation de la ressource `harbor_registry`.
</details>

<details><summary>Indice 2</summary>

`registry-mirrors` ne s'applique qu'à Docker Hub et attend un registre qui sert les dépôts **à la racine** (`/v2/library/debian/…`), alors que Harbor les sert sous le nom du projet (`/v2/dockerhub/library/debian/…`). Dans `registries.conf`, un bloc `[[registry]]` par registre amont (`prefix`, `location`) et un sous-bloc `[[registry.mirror]]`.
</details>

**Pour aller plus loin** (facultatif) : l'option « servir depuis le cache si l'image a disparu de l'amont » (Harbor 2.15.1+) : dans quel cas l'activerais-tu, dans quel cas serait-elle dangereuse ?

---

### M13-E05 — Analyser les images avec Trivy  `LAB` `★★`

> **Ticket SEC-1405** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Trivy est notre analyseur de référence, **malgré** mars 2026 : le projet a réagi correctement, et on a appris à installer un outil de sécurité. Donc : la version 0.75, vérifiée, épinglée, installée par le code ; jamais une 0.69.4. Je veux savoir ce que contiennent nos quatre images, nos Dockerfiles et notre code, avec un seuil clair (critique et corrigeable = bloquant), des exceptions **justifiées et datées**, et l'analyse automatique dans Harbor, à la poussée et chaque nuit.

**Objectifs pédagogiques**
- Installer un outil de sécurité par le code, vérifié (signature et empreinte) et épinglé.
- Utiliser Trivy sur une image, un système de fichiers et des fichiers de configuration ; régler sévérité, correctifs disponibles, exceptions, base locale.
- Activer et lire l'analyse intégrée de Harbor.

**Prérequis** : M13-E02 (Cosign sur `adm01`) ; M13-E03 (images dans `medisphere`, `harbor-moi.env`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Paquet | `trivy_0.75.0_Linux-64bit.deb`, son bundle `.sigstore.json` et `trivy_0.75.0_checksums.txt`, release `v0.75.0` de `github.com/aquasecurity/trivy` ; identité du signataire : workflow `https://github.com/aquasecurity/trivy/.github/workflows/reusable-release.yaml@refs/tags/v0.75.0`, émetteur `https://token.actions.githubusercontent.com` |
| Rôle | `outils_supply_chain` (nouveau, `plateforme/ansible`), appliqué à `adm01` ; il installera aussi Syft et Grype en E06 ; Cosign y est repris (installé à la main en E02) |
| Base de vulnérabilités | téléchargée par Trivy (`mirror.gcr.io/aquasec/trivy-db:2`, puis `ghcr.io/aquasecurity/trivy-db:2`) dans son cache (`~/.cache/trivy`) |
| Accès à Harbor | Trivy lit les identifiants du registre dans `TRIVY_USERNAME` et `TRIVY_PASSWORD`, ou dans le fichier d'authentification Docker |
| Rapports | `~/m13/e05/` sur `adm01` (sans secret) |
| Harbor | analyseur Trivy intégré (adaptateur, Trivy 0.74 embarqué) ; analyse à la poussée (propriété du projet) ; analyse planifiée de tout le registre (« Interrogation Services ») |

**Travail demandé**

1. Écris le rôle `outils_supply_chain` : pour chaque outil d'une liste (nom, version, URL du paquet, empreinte SHA-256, identité et émetteur du signataire), téléchargement vérifié par l'empreinte, vérification du bundle Sigstore avec Cosign quand Cosign est déjà présent, installation du paquet, contrôle de la version installée. Une version **interdite** (Trivy 0.69.4 à 0.69.6) fait échouer le rôle. Applique-le à `adm01` avec Cosign et Trivy.
   > ⚠️ **Attention** : avant d'épingler une empreinte, vérifie toi-même, à la main, le bundle de **ce** fichier avec l'identité attendue (comme en E02). Une empreinte recopiée d'un forum ou d'un fichier `checksums.txt` non vérifié n'épingle rien.
2. Prépare la base de Trivy (`trivy image --download-db-only`) et lis `trivy version` : âge de la base, source. Où vit le cache ? Comment ferais-tu sans Internet ?
3. Analyse les images migrées (toutes les étiquettes récentes des quatre dépôts de `medisphere`) avec ton compte (`harbor-moi.env`), en JSON et en tableau, dans `~/m13/e05/`. Compare avec `--severity CRITICAL,HIGH` puis avec `--ignore-unfixed` : combien restent, et lesquelles sont dans l'image de base, lesquelles dans les dépendances de l'application ?
4. Analyse le dépôt `mediagenda/api` cloné : `trivy fs` (dépendances du verrou `uv.lock`, secrets) et `trivy config` (Dockerfile, `compose.yaml`). Qu'est-ce que `trivy config` reproche au Dockerfile et au `compose.yaml` ? Corrige ce qui est justifié par une MR.
5. Pour une vulnérabilité que l'équipe décide d'accepter (pas de correctif amont, composant non utilisé), crée dans `mediagenda/api` un fichier d'exceptions `.trivyignore` où **chaque** ligne porte une justification, une date de revue et un auteur. Vérifie que la commande de blocage (« critique et corrigeable ») donne le code retour attendu avant et après l'exception.
6. Dans Harbor (état `registre`) : analyseur Trivy par défaut, analyse planifiée **chaque nuit** de tout le registre, analyse à la poussée dans les projets privés. Lance une analyse de `medisphere` depuis l'IHM et compare son résultat avec le tien. Pourquoi les chiffres diffèrent-ils peut-être ?
7. Écris `docs/registre/analyse.md` : seuil de blocage, gestion des exceptions (format, revue, expiration), où lire les rapports.

**Critères de réussite**
- [ ] Trivy 0.75.x est installé sur `adm01` par le rôle `outils_supply_chain` (sur `main`), qui épingle l'empreinte du paquet et refuse les versions 0.69.4 à 0.69.6 ; la base locale de Trivy existe.
- [ ] `~/m13/e05/` contient un rapport JSON de Trivy pour chacune des quatre images de `medisphere` et un rapport `trivy config` du dépôt `mediagenda/api`.
- [ ] Le `.trivyignore` de `mediagenda/api` (sur `main`) ne contient que des exceptions commentées (justification, date de revue).
- [ ] Harbor : Trivy est l'analyseur par défaut, l'analyse de tout le registre est planifiée, l'analyse à la poussée est active sur `medisphere` ; les images de `medisphere/mediagenda-api` ont été analysées avec succès.
- [ ] `docs/registre/analyse.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 13 05`

<details><summary>Indice 1</summary>

`ansible.builtin.get_url` accepte `checksum: sha256:<empreinte>` : le fichier n'est gardé que s'il correspond. `cosign verify-blob` prend le fichier, `--bundle`, `--certificate-identity` et `--certificate-oidc-issuer`. La version installée se lit avec `dpkg-query -W -f='${Version}' <paquet>`.
</details>

<details><summary>Indice 2</summary>

Le code retour de Trivy se règle par `--exit-code` ; la sévérité par `--severity` ; `--ignore-unfixed` écarte ce qui n'a pas de correctif. `trivy config` ne lit pas les images, seulement des fichiers (Dockerfile, Compose, manifestes Kubernetes, OpenTofu). Dans le fournisseur OpenTofu de Harbor, l'analyse planifiée se règle par la ressource `harbor_interrogation_services`.
</details>

**Pour aller plus loin** (facultatif) : `trivy image --scanners vuln,secret,misconfig,license` sur `medisphere/legacy-rdv` ; quelles licences trouves-tu, et lesquelles poseraient un problème si MédiSphère distribuait l'image à un client ?
