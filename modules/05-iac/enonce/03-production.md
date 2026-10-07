# Module 05 — Palier 3 : Production

Le socle est déclaré : `s3-01` porte l'état, le verrou tient, les VMs permanentes sont importées, le module `vm-debian` est publié par version. Mais tout part encore de ton poste, avec tes accès, et chaque nouvel environnement se fabrique par copier-coller de six fichiers. Karim Benali veut supprimer cette duplication avant qu'elle ne coûte un état écrasé. Sophie Laurent a trois exigences : l'état est chiffré, le code d'infrastructure est analysé comme du code applicatif, et aucun outil de sécurité ne s'installe « en dernière version » depuis Internet (l'incident Trivy de mars 2026 est passé par là). Claire Morel veut qu'aucun `apply` du socle ne parte plus d'un poste. Nadia Roussel veut savoir le matin si la réalité a dérivé du code, retrouver un état perdu en dix minutes, et un runbook pour le verrou que personne ne lâche. Ce palier industrialise la chaîne : Terragrunt (E24), analyse de sécurité (E25), pipeline plan/apply (E26), chiffrement de l'état (E27), dérive (E28), sauvegarde et restauration de l'état (E29), la décision sur le stockage S3 (E30), les montées de version des providers (E31), les questions qu'on te posera en revue (E32), le runbook du verrou (E33). Un exercice chronométré clôt le palier (E34).

> **Rappels** : tout se fait depuis `adm01`, dans `~/src/infra` (variable `WB_SRC`), par MR fusionnée dans `main` avec pipeline vert. Accès : `~/.config/workbook/pve-tofu.env` (jeton `wb-tofu@pve!tofu`, E03) et `~/.config/workbook/s3-tofu.env` (identité S3 `tofu-etat`, profil AWS `s3-socle`, E10-E11), à charger avant toute commande : `set -a; . ~/.config/workbook/pve-tofu.env; . ~/.config/workbook/s3-tofu.env; set +a`. À partir de E27, un script du projet le fait pour toi. Configurations OpenTofu existantes : `socle/`, `envs/lab-m05/`, `envs/recette-m05/` (palier 2), compartiment `tofu-state` de `s3-01`, versionné.

> **VMs de ce palier** : VMID **2057, 2058 et 2059** (étiquette `env-m05`, VNet `vsandbox`, DHCP), que les paliers 1 et 2 n'utilisent pas. Vérifie qu'elles sont libres (`ssh pve01 qm list`) avant E24 et E34. Les VMs laissées par le palier 2 (`envs/lab-m05`, `envs/recette-m05`) restent en place : ne les détruis pas ici, les pannes du palier 4 s'appuient sur leurs plans vides.

> ⚠️ **Ce palier donne à `runner01` le pouvoir de modifier le socle** (jeton Proxmox, identité S3, phrase de chiffrement de l'état), et il réécrit l'état du socle (chiffrement, montée de version du provider). Avant chaque étape qui écrit un état : copie de sauvegarde (versionnage vérifié, E11), plan relu en entier, aucune ligne `-` ou `-/+` sur une VM du socle. Retour arrière général : la version précédente de l'objet d'état dans `tofu-state` (E29) et le commit précédent de `main`.

---

### M05-E24 — Terragrunt : factoriser backends, providers et environnements  `LAB` `★★★`

> **Ticket PLAT-650** — *De : Karim Benali* — *Copie : Julien Petit*
> J'ai compté : `socle/`, `envs/lab-m05/` et `envs/recette-m05/` répètent chacun leur bloc backend, leur provider et leurs contraintes de versions. Julien voudrait un environnement de test par application, à la demande. Au rythme actuel, ça fait six fichiers copiés par environnement, et le jour où quelqu'un oublie de changer la `key` du backend, deux environnements partagent le même état : le plan de l'un propose de détruire les VMs de l'autre.
> Évalue Terragrunt sur deux environnements de Julien, `dev-agenda` et `dev-doc` : un seul endroit pour le backend et le provider, une clé d'état qu'on ne peut pas se tromper à écrire, et des environnements qui ne diffèrent que par ce qui les distingue vraiment. Dis-moi aussi si le socle doit y passer.

**Objectifs pédagogiques**
- Comprendre ce que Terragrunt ajoute à OpenTofu : unités, configuration héritée (`include`), génération de fichiers (`generate`, `remote_state`), dépendances entre unités (`dependency`), exécution d'un ensemble (`run --all`).
- Utiliser la CLI de Terragrunt 1.x (`run --all`, variables `TG_*`, `root.hcl`) et repérer les tutoriels écrits pour les versions 0.x.
- Séparer le code réutilisable (composants) de la configuration propre à chaque environnement (unités).
- Mesurer le prix de l'outil : une couche de plus à comprendre, à mettre à jour et à dépanner.

**Prérequis** : M05-E11 (backend S3), M05-E13 et M05-E14 (module `vm-debian` publié), M05-E15 (environnements par répertoires).
**Durée indicative** : 4 h.

**Contexte technique**
- Terragrunt **1.1.x** : binaire de la page des versions (<https://github.com/gruntwork-io/terragrunt/releases>), fichier `terragrunt_linux_amd64`, à vérifier avec le fichier `SHA256SUMS` publié à côté ; ce fichier est lui-même signé (Sigstore, `SHA256SUMS.sigstore.json`). Installation dans `/usr/local/bin` sur `adm01` (puis sur `runner01` en E26, par Ansible). Documentation : <https://docs.terragrunt.com/>.
- Terragrunt appelle `tofu` par défaut (`--tf-path` / `TG_TF_PATH` pour un autre binaire). La CLI 1.x a supprimé `run-all`, le préfixe `--terragrunt-` des options et les variables `TERRAGRUNT_*` : la plupart des tutoriels en ligne sont écrits pour l'ancienne CLI.
- Arborescence imposée dans `plateforme/infra` :
  ```
  terragrunt/
  ├── composants/<composant>/     code OpenTofu réutilisable : ni backend ni provider
  └── live/
      ├── root.hcl                configuration héritée par toutes les unités
      ├── commun.hcl              constantes non secrètes (nœud, pool, DNS, clé d'administration)
      ├── _commun/                morceaux de configuration inclus par certaines unités seulement
      └── <environnement>/
          ├── env.hcl             ce qui distingue l'environnement
          └── <unité>/terragrunt.hcl
  ```
- Deux composants : `acces` (une paire de clés SSH propre à l'environnement, provider `hashicorp/tls` `~> 4.4.0`, clé `ED25519`) et `vms` (les VMs de l'environnement, par le module `vm-debian` à ta dernière version publiée). L'unité `vms` dépend de l'unité `acces` (la clé publique de l'environnement est injectée dans les VMs, en plus de celle de `admin@adm01`).
- Environnements : `dev-agenda` (VMs `m05-agenda-api` VMID 2057, 1 vCPU, 1 Go ; `m05-agenda-bdd` VMID 2058, 1 vCPU, 1,5 Go) et `dev-doc` (`m05-doc-api` VMID 2059, 1 vCPU, 1 Go). Étiquettes `env-m05` et le nom de l'environnement ; VNet `vsandbox` (DHCP) ; disque système 10 Go.
- Clés d'état : `envs/<environnement>/<unité>/terraform.tfstate` dans `tofu-state`, **déduites du chemin** de l'unité, jamais écrites à la main.

**Travail demandé**
1. **Mesure la duplication.** Compare les blocs `terraform {}` et `provider` de `socle/`, `envs/lab-m05/` et `envs/recette-m05/` (`diff`, ou à l'œil). Note dans ton journal : ce qui est identique, ce qui doit différer (la clé d'état), et ce qui se passerait si l'on copiait `envs/recette-m05` vers `envs/dev-agenda` sans changer la clé. Ne le fais pas : décris-le à partir de ce que tu sais de l'état (E05, E11).
2. **Installe Terragrunt** sur `adm01` : télécharge le binaire et `SHA256SUMS`, vérifie la somme, installe, puis `terragrunt --version`. Explique pourquoi la somme seule, téléchargée au même endroit que le binaire, ne prouve pas grand-chose, et ce qu'apporte la signature (tu la vérifieras avec `cosign` au module 13 ; si tu veux le faire dès maintenant, l'identité attendue est celle du flux de publication du dépôt `gruntwork-io/terragrunt`).
3. **Écris les deux composants** dans `terragrunt/composants/`. Ce sont des configurations OpenTofu ordinaires (`versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`), sans bloc `backend` ni `provider`. Les variables du composant `vms` refusent un VMID hors 2050-2059 et deux VMs au même VMID. La clé privée de l'environnement est une sortie `sensitive`.
4. **Écris `live/root.hcl`** : un bloc `remote_state` qui génère le backend S3 (mêmes réglages qu'en E11) avec une clé calculée à partir du chemin de l'unité, et des `inputs` communs lus dans `commun.hcl`. Le bloc `provider "proxmox"` est généré par un fichier de `live/_commun/`, inclus **seulement** par les unités qui gèrent des VMs : pourquoi ne pas le générer pour toutes ?
5. **Écris les unités** des deux environnements. Les fichiers `terragrunt.hcl` d'une même unité doivent être **identiques** d'un environnement à l'autre : tout ce qui varie est dans `env.hcl`. L'unité `vms` lit la clé publique par un bloc `dependency` ; prévois des sorties factices (`mock_outputs`) pour qu'un `validate` et un `plan` d'ensemble passent avant le premier `apply`, et limite-les à ces commandes : que se passerait-il sinon ?
6. **Observe avant d'appliquer** :
   ```
   admin@adm01:~/src/infra/terragrunt/live$ terragrunt list --dag
   admin@adm01:~/src/infra/terragrunt/live$ terragrunt dag graph
   admin@adm01:~/src/infra/terragrunt/live$ terragrunt run --all validate
   admin@adm01:~/src/infra/terragrunt/live$ terragrunt run --all plan
   ```
   Cherche dans une unité le dossier `.terragrunt-cache/` : quels fichiers Terragrunt a-t-il générés, et où a-t-il copié le composant ? Où a-t-il écrit `.terraform.lock.hcl` ? Lequel des deux versionnes-tu ?
7. **Applique** `dev-agenda` seul, puis `dev-doc` (`terragrunt run --all apply` depuis le dossier d'un environnement). Note l'ordre dans lequel les unités sont traitées. Vérifie les clés créées dans `tofu-state` (`aws s3 ls s3://tofu-state/envs/ --recursive`) et les VMs dans Proxmox (étiquettes, pool).
8. **Remets à Julien sa clé.** Récupère la clé privée de `dev-agenda` (`terragrunt output` dans l'unité `acces`), range-la dans `~/m05/e24/` en `600`, et connecte-toi à `m05-agenda-api` avec elle seule (`ssh -o IdentitiesOnly=yes -o ControlPath=none -i …`). Où d'autre cette clé est-elle écrite en clair ? Note-le pour Sophie : c'est l'objet de E27.
9. **Le socle sous Terragrunt ?** Réponds dans ton journal, en 10 lignes : faut-il migrer `socle/`, `envs/lab-m05` et `envs/recette-m05` sous Terragrunt ? Pour la réponse « oui », dis ce que la migration toucherait (bloc backend, clé d'état, pipeline, pannes) ; pour « non », ce que tu perds. Ne migre rien dans cet exercice.
10. **Détruis `dev-doc`** avec `terragrunt run --all destroy` (dans quel ordre les unités sont-elles détruites, et pourquoi ?). **Garde `dev-agenda`** : E27 s'en sert. Ajoute `.terragrunt-cache/` au `.gitignore`, puis fusionne par MR.

**Critères de réussite**
- [ ] `terragrunt --version` donne une version 1.x sur `adm01`.
- [ ] Sur `main` : `terragrunt/live/root.hcl` (backend généré, clé déduite du chemin), `commun.hcl`, les unités des deux environnements avec leurs `.terraform.lock.hcl`, les deux composants ; aucun bloc `backend` ni `provider` dans `terragrunt/composants/`.
- [ ] `tofu-state` contient les clés `envs/dev-agenda/acces/…`, `envs/dev-agenda/vms/…`, `envs/dev-doc/acces/…` et `envs/dev-doc/vms/…`.
- [ ] Les VMs 2057 et 2058 tournent avec les étiquettes `env-m05` et `dev-agenda` ; la VM 2059 a été créée puis détruite par Terragrunt.
- [ ] Ton journal contient la réponse argumentée sur le socle et l'explication de l'ordre de destruction.

**Vérification** : `lab/bin/check 05 24`

<details><summary>Indice 1</summary>

Dans `root.hcl`, la fonction `path_relative_to_include()` renvoie le chemin de l'unité **relativement au dossier de `root.hcl`**. Un bloc `remote_state` avec un attribut `generate = { path = …, if_exists = … }` écrit le bloc backend dans la copie de travail de l'unité. Une unité peut avoir plusieurs blocs `include` nommés.
</details>

<details><summary>Indice 2</summary>

`find_in_parent_folders("env.hcl")` et `read_terragrunt_config(…)` permettent à une unité de lire les `locals` du fichier de son environnement. Une source locale de la forme `…/composants//vms` (double barre oblique) fait copier tout `composants/` et placer Terragrunt dans `vms/`. Les entrées (`inputs`) arrivent à OpenTofu comme des variables d'environnement `TF_VAR_…` : une entrée qu'un composant ne déclare pas est ignorée.
</details>

<details><summary>Indice 3</summary>

`mock_outputs_allowed_terraform_commands` limite les commandes où les sorties factices sont acceptées. Pour ne traiter qu'une partie de l'arborescence, lance la commande depuis un sous-dossier, ou regarde l'option `--filter` de `terragrunt run`.
</details>

**Pour aller plus loin** (facultatif) : les *stacks* de Terragrunt (`terragrunt.stack.hcl`) génèrent les unités d'un environnement à partir d'une description unique ; compare avec ce que tu as écrit. Lis aussi la page *Migrating from the old CLI* de la documentation pour repérer les commandes 0.x que tu croiseras dans les dépôts existants.

---

### M05-E25 — Analyse de sécurité du code : Checkov et Trivy  `LAB` `★★`

> **Ticket SEC-653** — *De : Sophie Laurent*
> Le code d'infrastructure crée des machines qui portent des données de santé : il passe par les mêmes contrôles que le code applicatif. Je veux deux analyseurs, Checkov et Trivy, sur toute MR de `plateforme/infra`, et des règles qui parlent de **notre** infrastructure, pas seulement d'AWS.
> Deuxième point, non négociable. En mars, Trivy lui-même a été compromis : une version piégée publiée sur les canaux officiels, des étiquettes de l'action GitHub déplacées vers du code malveillant. Les équipes qui installaient « la dernière version » à chaque job ont exécuté un voleur de secrets dans leurs pipelines. Chez nous, un outil de sécurité s'installe à une version fixée, vérifiée par son empreinte, et ne télécharge rien de lui-même à l'exécution.

**Objectifs pédagogiques**
- Installer un outil de la chaîne d'approvisionnement de façon vérifiable : version figée, empreinte, signature, aucun téléchargement implicite à l'exécution.
- Utiliser Checkov et Trivy sur du code OpenTofu, lire leurs résultats, et savoir ce qu'ils ne voient pas (aucune règle Proxmox fournie).
- Écrire des règles maison (YAML pour Checkov, Rego pour Trivy) et les tester sur des cas qui doivent échouer.
- Gérer les exceptions : justification écrite, date d'expiration, revue.

**Prérequis** : M05-E20 (chaîne de qualité, pre-commit), M05-E24.
**Durée indicative** : 3 h.

**Contexte technique**
- **Checkov 3.3.x** (PyPI, licence Apache 2.0) : outil Python, installé par `uv tool install 'checkov==<VERSION>'` (PLAN : jamais de `pip` global). Configuration par fichier `.checkov.yaml` (mêmes noms que les options longues de la CLI). Documentation : <https://www.checkov.io/>.
- **Trivy 0.75.0** (licence Apache 2.0) : archive `trivy_0.75.0_Linux-64bit.tar.gz`, fichier de sommes `trivy_0.75.0_checksums.txt`, et signature Sigstore `trivy_0.75.0_Linux-64bit.tar.gz.sigstore.json` sur <https://github.com/aquasecurity/trivy/releases/tag/v0.75.0>. Identité du signataire : `https://github.com/aquasecurity/trivy/.github/workflows/reusable-release.yaml@refs/tags/v0.75.0`, émetteur `https://token.actions.githubusercontent.com`. Documentation : <https://trivy.dev/>.
- **L'incident** (CVE-2026-33634, avis GHSA-cxm3-wv7p-598c) : le 19 mars 2026, un compte de publication compromis a diffusé un Trivy **v0.69.4** malveillant pendant environ trois heures, et des étiquettes de `aquasecurity/trivy-action` et `setup-trivy` ont été déplacées vers des commits malveillants ; le 22 mars, des images Docker `0.69.5` et `0.69.6` piégées ont suivi. Les secrets accessibles aux pipelines touchés sont à considérer comme volés.
- Par défaut, `trivy config` télécharge à chaque exécution un paquet de règles (*checks bundle*) depuis un registre OCI ; le binaire embarque une copie de ces règles, utilisée avec `--skip-check-update`. Les règles maison Rego pour du code OpenTofu brut utilisent le type d'entrée `terraform-raw` et l'option `--raw-config-scanners terraform`.
- Emplacements dans `plateforme/infra` : règles dans `politiques/checkov/` et `politiques/trivy/`, cas de test dans `politiques/tests/`, versions et empreintes des outils dans `outils/versions-outils.env`, script `outils/analyse-securite.sh`, rapports dans `rapports/` (non versionné).

> ⚠️ **Attention** : n'installe pas Trivy par `curl … | sh`, par un dépôt APT non épinglé ni par l'image `latest`. Si une version de Trivy comprise entre 0.69.4 et 0.69.6 a tourné sur une de tes machines en mars 2026, considère ses secrets comme compromis (procédure de l'avis de sécurité).

**Travail demandé**
1. **Installe** Checkov et Trivy sur `adm01`. Pour Trivy : télécharge l'archive, le fichier de sommes et la signature dans `~/m05/e25/`, vérifie la somme, installe le binaire dans `/usr/local/bin`. Relève dans `outils/versions-outils.env` la version et deux empreintes SHA-256 : celle de l'archive et celle du binaire installé. Écris dans ton journal ce que chaque vérification prouve et ne prouve pas (somme seule, somme figée dans ton dépôt, signature), et à quel moment une empreinte figée aurait protégé une équipe le 19 mars.
2. **Premier passage.** Lance Checkov puis Trivy sur `socle/`, `envs/` et `terragrunt/composants/`, d'abord sans configuration. Combien de règles s'appliquent vraiment à des ressources Proxmox ? Que signalent-ils sur les sources de modules (`?ref=v1.1.0`) ? Les règles `CKV_TF_1` et `CKV_TF_2` se contredisent-elles ? Décide laquelle tu retiens, au regard de ce que tu sais des étiquettes de `plateforme/tofu-modules` (protégées, M01) et de l'incident de mars.
3. **Règles maison.** Écris au moins quatre règles Checkov (YAML) et deux règles Trivy (Rego) qui traduisent nos conventions (introduction du module, M03) : par exemple TLS vérifié par le provider, étiquettes toujours déclarées, clone complet, agent QEMU actif, ressource expérimentale `proxmox_vm` interdite. Pour **chaque** règle, crée dans `politiques/tests/` un fichier qui la viole : une règle qu'on n'a jamais vue échouer ne prouve rien.
4. **Exceptions.** S'il reste des alertes justifiées par un choix de l'équipe, ignore-les **une par une** (jamais une famille entière), avec la raison et une date d'expiration dans `.trivyignore`, et la raison en commentaire dans `.checkov.yaml`. Vérifie qu'une exception expirée fait réapparaître l'alerte.
5. **Script.** `outils/analyse-securite.sh` lance les deux analyseurs avec la configuration du dépôt, sans téléchargement implicite, refuse de tourner si le Trivy installé n'a pas l'empreinte attendue, écrit des rapports JUnit dans `rapports/`, et sort en erreur s'il y a la moindre alerte. Il passe sur le code du dépôt et échoue sur `politiques/tests/`. Branche-le dans pre-commit à l'étape `pre-push`.
6. Ouvre une MR (le job de CI viendra en E26).

**Critères de réussite**
- [ ] `trivy --version` donne 0.75.0 et l'empreinte du binaire installé correspond à celle de `outils/versions-outils.env` ; `checkov --version` donne une 3.3.x.
- [ ] Sur `main` : `.checkov.yaml`, `.trivyignore` (s'il sert), au moins 4 règles Checkov et 2 règles Trivy, un cas de test qui viole chaque règle, `outils/analyse-securite.sh`, `outils/versions-outils.env`.
- [ ] `outils/analyse-securite.sh` sort en 0 sur le code du dépôt et en erreur sur `politiques/tests/`.
- [ ] Ton journal explique la décision `CKV_TF_1`/`CKV_TF_2` et ce que protège chaque vérification d'installation.

**Vérification** : `lab/bin/check 05 25`

<details><summary>Indice 1</summary>

Une règle YAML de Checkov a une section `metadata` (`id` au format `CKV2_<NOM>_<N>`, `name`, `category`) et une section `definition` (`cond_type: attribute`, `resource_types`, `attribute`, `operator`, `value`). Les attributs des blocs imbriqués se désignent avec des points (`agent.enabled`). Le bloc provider se désigne comme un type de ressource : `provider.<nom>`. Le dossier des règles se passe par `external-checks-dir`.
</details>

<details><summary>Indice 2</summary>

Pour écrire une règle Trivy sur du code brut, commence par une règle qui renvoie `json.marshal(input)` en message : tu verras la structure (`modules`, `blocks`, `kind`, `type`, `name`, `attributes`). Options utiles : `--config-check`, `--check-namespaces`, `--raw-config-scanners`. Une ligne de `.trivyignore` accepte une expiration sous la forme `ID exp:AAAA-MM-JJ`.
</details>

<details><summary>Indice 3</summary>

Trivy et Checkov essaient de télécharger les modules distants qu'ils trouvent (`git::https://git01…`) : sur `adm01`, la réécriture d'URL de E14 leur sert aussi. Et un cas de test fautif enregistré en `.tf` dans le dépôt sera vu par **tous** les outils de E20 (`tofu fmt`, `outils/tofu-valider.sh`, `tflint --recursive`) : trouve un moyen de le garder hors de leur portée.
</details>

**Pour aller plus loin** (facultatif) : analyse le **plan** plutôt que le code (`tofu show -json plan.tfplan`, puis `trivy config` ou `checkov -f`) : les variables et les modules y sont résolus. Attention à ce que contient ce JSON (E27).

---

### M05-E26 — Pipeline IaC : plan en MR, apply protégé  `LAB` `★★★`

> **Ticket PLAT-656** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> Même règle que pour Ansible au module 04 : plus aucun changement du socle ne part d'un poste. Une MR montre le plan, exact, à son relecteur ; après fusion, quelqu'un qui en a le droit déclenche l'apply, et c'est **le plan relu** qui s'applique, pas un nouveau calcul. Un seul apply à la fois par état. Sophie ajoute : le plan contient l'état, donc des secrets ; il ne traîne pas dans les artefacts à la vue de tous.

**Objectifs pédagogiques**
- Concevoir un pipeline d'infrastructure : contrôles statiques, analyse de sécurité, plan par état en MR, apply manuel du plan enregistré, sur `main` seulement.
- Comprendre pourquoi on applique un plan enregistré (`tofu apply plan.tfplan`) et ce qui se passe quand il est périmé.
- Lire les codes retour de `tofu plan -detailed-exitcode` et les utiliser dans un job.
- Faire avec les limites de GitLab CE (pas d'environnements protégés) : branches protégées, variables protégées, `resource_group`, droits sur les artefacts.

**Prérequis** : M04-E27 (modèle de pipeline protégé), M05-E14 (accès aux modules par jeton de job), M05-E20 (qualité), M05-E25 (analyse de sécurité).
**Durée indicative** : 5 h.

**Contexte technique**
- `runner01` (exécuteur `shell`, utilisateur `gitlab-runner`, étiquette `shell`) n'a encore ni OpenTofu, ni Terragrunt, ni tflint, ni terraform-docs, ni Checkov, ni Trivy. Ils s'y installent **par Ansible** (rôle `gitlab_runner` de `plateforme/ansible`, M04-E16), aux versions et empreintes de `outils/versions-outils.env` : OpenTofu par le dépôt APT signé (même méthode qu'en E02), les binaires par archive vérifiée, Checkov par `uv tool` dans `/opt/uv-tools`, `jq` et `awscli` (paquet Debian 13, AWS CLI v2) par APT.
- Flux : `runner01` → `pve01`:8006 (ouvert en M03-E15), `runner01` → `s3-01`:8333 (même VLAN), `runner01` → `git01` (même VLAN). Rien à ouvrir.
- GitLab CE 19.4 :
  - les **environnements protégés** sont réservés aux éditions payantes ; un job manuel d'une branche protégée ne peut être lancé que par qui peut fusionner dans cette branche ;
  - le rapport `artifacts:reports:terraform` (résumé du plan dans le widget de la MR) est disponible dans toutes les éditions ; il attend un JSON `{"create": N, "update": N, "delete": N}` ;
  - `artifacts:access` accepte `all`, `developer`, `maintainer` (depuis 18.4) et `none` ; `artifacts:expose_as` affiche un artefact dans la MR ;
  - une variable masquée doit tenir sur une ligne, sans espace, 8 caractères au moins ; désactive « Expand variable reference » pour pouvoir y mettre `!` ou `=`.
- Variables CI du projet, toutes **protégées** : `PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN` (masquée et cachée), `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (masquée et cachée). Branches protégées : `main` et `conf/*` (comme `plateforme/ansible`), option *Allow merge request pipelines to access protected variables and runners* activée.
- E20 a mis `SKIP: tofu-fmt,tofu-validate,tflint,terraform-docs` dans le `.gitlab-ci.yml` en attendant les outils de `runner01` : c'est le moment de le retirer.
- Configurations à traiter par le pipeline : `socle/`, `envs/lab-m05/`, `envs/recette-m05/`. Les environnements Terragrunt restent hors pipeline dans cet exercice (voir « Pour aller plus loin »).

> ⚠️ **Attention** : à la fin de cet exercice, quiconque peut faire exécuter du code à `runner01` sur une branche protégée détient les droits de `wb-tofu` sur le pool `lab` et l'accès en écriture à tous les états. Vérifie qui peut pousser sur `conf/*` et fusionner dans `main` **avant** de créer les variables. Le premier apply du socle par le pipeline se fait sur une MR dont le plan est vide ou ne change qu'une description.

**Travail demandé**
1. **Outils de `runner01`.** Ajoute au rôle `gitlab_runner` l'installation des outils IaC, avec vérification de chaque empreinte. Applique par le pipeline de `plateforme/ansible` (M04-E27). Vérifie en tant que `gitlab-runner` : `sudo -u gitlab-runner tofu version`, `terragrunt --version`, `tflint --version`, `checkov --version`, `trivy --version`, `aws --version`.
2. **Variables et protections.** Crée les variables CI, protège `conf/*`, active l'accès des pipelines de MR aux variables protégées, ajoute `plateforme/infra` à la liste d'autorisation des jetons de job de `plateforme/tofu-modules` si ce n'est pas déjà fait (E14). Note dans ton journal qui peut désormais lire le jeton `wb-tofu`.
3. **Le pipeline** (`.gitlab-ci.yml`, en plus du gabarit `qualite.yml`) :
   - les contrôles de E20 (`tofu fmt`, `validate`, tflint, terraform-docs) sur toute MR et sur `main`, sans accès à Proxmox ni à S3 : retrait du `SKIP`, et ce qu'il faut au job qui les lance pour télécharger les modules de `plateforme/tofu-modules` ;
   - `securite` : `outils/analyse-securite.sh` (E25), rapports JUnit dans la MR ; le job vérifie l'empreinte de Trivy, et l'empreinte attendue est écrite dans le `.gitlab-ci.yml` ;
   - un job `plan` **par configuration** (`plan:socle`, `plan:lab-m05`, `plan:recette-m05`), sur les MR et sur `main` : `.terraform.lock.hcl` en lecture seule, plan enregistré, texte du plan et rapport `terraform` en artefacts, accès aux artefacts restreint ; le job distingue « aucun changement », « changements » et « erreur » ;
   - un job `apply` par configuration (`apply:socle`…) : sur `main` seulement, manuel, environnement `lab/<configuration>` (palier `production` pour le socle), un seul à la fois par état, qui applique **le plan enregistré du même pipeline**, puis vérifie qu'un nouveau plan est vide ;
   - une MR issue d'une branche non protégée ne reçoit pas les secrets : le pipeline le dit clairement au lieu de passer en silence.
4. **La preuve.** Une MR depuis `conf/…` qui change la description de `s3-01` : relis le plan dans la MR (widget et artefact), fusionne, lance `apply:socle`, constate le plan de contrôle vide. Puis provoque un plan périmé : deux pipelines de `main` successifs, lance l'apply du **premier** après celui du second. Que dit OpenTofu ? Quel réglage de GitLab l'aurait empêché avant même de lancer le job (*Prevent outdated deployment jobs*) ?
5. **Les artefacts.** Télécharge le plan d'un job `plan:socle` avec un compte *Reporter* (`lucas.martin`), puis avec ton compte. Que contient un `plan.tfplan` (lis la documentation de `tofu show`) ? Justifie le niveau d'accès choisi et la durée de conservation.
6. **Retour à la règle.** Écris dans `CONTRIBUTING.md` du projet le chemin normal d'un changement d'infrastructure et ce qui reste permis depuis `adm01` (lecture, plan, environnements Terragrunt de test ; jamais d'apply du socle hors bris de glace).

**Critères de réussite**
- [ ] Sur `main`, `.gitlab-ci.yml` contient `securite`, un `plan:` et un `apply:` par configuration ; les `apply:` sont manuels, sur `main`, avec environnement et `resource_group` ; le `SKIP` de E20 a disparu et le job `pre-commit` réussit ; l'empreinte de Trivy y figure.
- [ ] Un déploiement réussi existe pour l'environnement `lab/socle` ; un pipeline de MR a exécuté `plan:socle` avec succès et publié un rapport `terraform`.
- [ ] `PROXMOX_VE_API_TOKEN` et `AWS_SECRET_ACCESS_KEY` sont protégées et masquées ; `main` et `conf/*` sont protégées.
- [ ] Les artefacts des jobs `plan:` ne sont pas accessibles à tous.
- [ ] `runner01` a OpenTofu 1.13, Terragrunt 1.x, tflint, Checkov et Trivy 0.75.0 à l'empreinte attendue.

**Vérification** : `lab/bin/check 05 26`

<details><summary>Indice 1</summary>

`tofu plan -detailed-exitcode` sort en 0 (aucun changement), 2 (changements) ou 1 (erreur) : dans un `script:` de GitLab, une commande qui sort en 2 fait échouer le job si tu ne captures pas son code (`… || rc=$?`). `tofu init -lockfile=readonly` refuse de modifier `.terraform.lock.hcl`. Le rapport `terraform` se calcule avec `jq` sur `tofu show -json plan.tfplan` (champ `resource_changes[].change.actions`).
</details>

<details><summary>Indice 2</summary>

Un job `apply` récupère les artefacts du job `plan` correspondant par `needs:`. Le dossier `.terraform/` n'est pas dans ces artefacts : il faut refaire `tofu init` avant d'appliquer, et les providers téléchargés doivent correspondre exactement au lock. Une seconde passe `tofu plan -detailed-exitcode` après l'apply doit sortir en 0.
</details>

<details><summary>Indice 3</summary>

M04-E27 a déjà résolu « une MR depuis une branche non protégée » : une variable protégée absente est **vide**, une règle `if: $PROXMOX_VE_API_TOKEN` teste sa présence. Pour les modules de `plateforme/tofu-modules`, reprends l'extrait `.acces-modules` de E14.
</details>

**Pour aller plus loin** (facultatif) : ajoute les environnements Terragrunt au pipeline (`terragrunt run --all --out-dir plans plan`, puis `apply` avec le même `--out-dir`) avec un job par environnement ; et regarde le composant CI/CD OpenTofu proposé par GitLab : qu'apporte-t-il, et que te coûterait-il sur un runner `shell` ?

---

### M05-E27 — Secrets et chiffrement de l'état  `LAB` `★★★`

> **Ticket SEC-659** — *De : Sophie Laurent*
> J'ai lu l'objet `envs/dev-agenda/acces/terraform.tfstate` avec l'identité S3 de la CI : la clé privée SSH de l'environnement de Julien y est en clair. Demain, ce sera un mot de passe de base de données ou un jeton. L'état est sur un disque de `s3-01`, dans les sauvegardes PBS, dans les artefacts des pipelines : autant de copies.
> Je veux l'état et les plans **chiffrés côté client**, par OpenTofu, avant qu'ils ne quittent la machine qui les calcule. La phrase secrète n'est ni dans le code, ni dans un plan, ni dans un journal de job. Et la migration ne doit rien recréer.

**Objectifs pédagogiques**
- Comprendre ce que contient l'état et pourquoi `sensitive` ne protège rien dans l'état.
- Configurer le chiffrement de l'état et des plans d'OpenTofu : fournisseur de clé `pbkdf2`, méthode `aes_gcm`, blocs `state` et `plan`, `fallback`, `enforced`.
- Migrer des états existants sans interruption, puis interdire tout retour en clair.
- Choisir le canal de la phrase secrète (variable OpenTofu ou `TF_ENCRYPTION`) en vérifiant où elle finit.

**Prérequis** : M05-E24 (`dev-agenda` en place), M05-E26 (pipeline).
**Durée indicative** : 3 h.

**Contexte technique**
- Documentation : <https://opentofu.org/docs/language/state/encryption/>. Fournisseur `pbkdf2` : phrase de 16 caractères au moins ; méthode `aes_gcm` ; la méthode `unencrypted` n'existe que pour migrer. `TF_ENCRYPTION` accepte la même syntaxe que le bloc `encryption` ; le contenu de la variable est **fusionné** avec le code, et l'emporte.
- Le **nom** du fournisseur de clé est écrit dans les métadonnées de chaque état chiffré : le renommer plus tard demande une migration (`fallback`) ou `encrypted_metadata_alias`. Nom imposé : fournisseur `pbkdf2 "etat"`, méthode `aes_gcm "etat"`.
- Phrase secrète : `~/.config/workbook/tofu-chiffrement.pass` (600), générée par `openssl rand -hex 32` ; en CI, variable `TOFU_PHRASE_CHIFFREMENT` (protégée, masquée et cachée). Elle s'inscrit au registre des secrets, avec sa procédure de rotation et l'endroit où elle est sauvegardée hors de `adm01` (coffre de l'équipe).
- Configurations à chiffrer : `socle/`, `envs/lab-m05/`, `envs/recette-m05/` et toutes les unités Terragrunt.
- Script attendu : `outils/charger-acces.sh`, à **sourcer** (`. outils/charger-acces.sh`), qui charge sur `adm01` les accès Proxmox, S3 et la phrase de chiffrement ; son équivalent CI est appelé par le `before_script` des jobs OpenTofu.

> ⚠️ **Attention** : une phrase perdue = des états **illisibles**, définitivement (aucune porte de secours). Avant de chiffrer : la phrase est dans le coffre de l'équipe **et** dans `~/.config/workbook/`, et tu as vérifié que tu peux la relire depuis le coffre. Avant chaque migration, note la version courante de chaque objet d'état (`aws s3api list-object-versions`) : c'est ton retour arrière.

**Travail demandé**
1. **Ce que contient l'état.** Avec l'identité `tofu-etat`, lis l'objet `envs/dev-agenda/acces/terraform.tfstate` sans OpenTofu (`aws s3 cp … -`) et retrouve la clé privée. Lis aussi l'état du socle : que trouverait un attaquant d'utile (adresses, MAC, VMID, empreintes de clés, chemins, noms de stockages) ? Pourquoi la sortie `cle_privee_openssh` est-elle masquée à l'écran mais pas dans l'objet ?
2. **Où va la phrase ?** Fais l'expérience dans `~/m05/e27/` (état local jetable, ressource `terraform_data`) : passe la phrase par une **variable** OpenTofu (`TF_VAR_…`), enregistre un plan, puis lis-le avec `tofu show -json`. Recommence avec `TF_ENCRYPTION`. Conclus : quel canal retiens-tu, et pourquoi ?
3. **Le code.** Écris le bloc `encryption` (méthode, `state`, `plan`, et la lecture des états distants par `terraform_remote_state` si une configuration en utilise) dans chaque configuration racine, et fais-le **générer** par `root.hcl` pour Terragrunt. Le fournisseur de clé, lui, vient de `TF_ENCRYPTION`. Écris `outils/charger-acces.sh` et le script de CI qui construit `TF_ENCRYPTION` à partir de `TOFU_PHRASE_CHIFFREMENT`.
4. **Migration.** Pour chaque état : une phase où l'on écrit chiffré mais où l'on sait encore lire en clair, un apply (le plan doit être **vide**), la vérification que l'objet dans `tofu-state` est chiffré, puis une seconde MR qui retire la possibilité de lire en clair et **interdit** d'écrire en clair. Pour le socle et les configurations du pipeline, passe par le pipeline (E26) ; pour les unités Terragrunt, depuis `adm01` (`dev-agenda`, et aussi `dev-doc` : ses VMs sont détruites mais ses états, vides, sont encore en clair).
5. **Preuves.** Montre que : (a) l'objet du socle dans `tofu-state` ne contient plus aucune ressource lisible ; (b) un `tofu plan` sans phrase échoue, avec une mauvaise phrase aussi (note les deux messages : l'un d'eux est trompeur, lequel ?) ; (c) un artefact `plan.tfplan` du pipeline est illisible sans la phrase ; (d) `tofu state pull` affiche l'état **en clair** : qu'en conclus-tu pour les sauvegardes (E29) ?
6. **Rotation (à froid).** Rédige dans le registre des secrets la procédure de rotation de la phrase (ancienne phrase en `fallback` avec un second fournisseur, nouvelle en méthode principale, réécriture de chaque état, retrait de l'ancienne) : tu ne l'exécutes pas ici, mais chaque étape doit être vérifiable. Puis détruis `dev-agenda` (`terragrunt run --all destroy`).

**Critères de réussite**
- [ ] Les objets d'état de `socle/`, `envs/lab-m05/`, `envs/recette-m05/` et de toutes les unités Terragrunt dans `tofu-state` sont chiffrés (aucune clé `resources` lisible).
- [ ] Sur `main` : le bloc `encryption` avec `enforced = true` pour `state` et `plan` dans chaque configuration racine et dans la génération Terragrunt, sans `fallback` vers `unencrypted` ; aucune phrase dans le dépôt.
- [ ] `TOFU_PHRASE_CHIFFREMENT` est protégée et masquée ; `~/.config/workbook/tofu-chiffrement.pass` existe en 600 ; le registre des secrets décrit la phrase et sa rotation.
- [ ] Le plan du socle est vide ; les VMs 2057 et 2058 sont détruites.

**Vérification** : `lab/bin/check 05 27`

<details><summary>Indice 1</summary>

Une migration qui fonctionne : `method = method.aes_gcm.etat` avec un bloc `fallback { method = method.unencrypted.<nom> }` dans `state` et dans `plan`. OpenTofu lit avec la méthode principale, se rabat sur le `fallback` si elle échoue, et écrit **toujours** avec la principale. Un `apply` dont le plan est vide réécrit quand même l'état.
</details>

<details><summary>Indice 2</summary>

Le code peut **référencer** un fournisseur de clé qu'il ne déclare pas (`keys = key_provider.pbkdf2.etat`) si `TF_ENCRYPTION` le déclare. Sans `TF_ENCRYPTION`, l'erreur est explicite. `openssl rand -hex 32` produit une phrase sans guillemet, sans `$` ni `%` : rien à échapper dans du HCL, et acceptée par GitLab comme variable masquée.
</details>

**Pour aller plus loin** (facultatif) : les valeurs éphémères et les attributs *write-only* (OpenTofu 1.11) permettent à certains providers de recevoir un secret **sans** l'écrire dans l'état ; cherche si `bpg/proxmox` en propose. Au module 25, le fournisseur de clé `openbao` remplacera la phrase par une clé de transit OpenBao.

---

### M05-E28 — Détecter la dérive de l'infrastructure  `LIBRE` `★★`

> **Ticket PLAT-662** — *De : Nadia Roussel* — *Copie : Sophie Laurent*
> Cette nuit, à l'astreinte, j'ai monté la mémoire de `s3-01` dans l'interface de Proxmox : le compartiment saturait. Ce matin, Karim me dit que le prochain apply la remettra à 2 Go sans prévenir personne. Je ne veux pas qu'on l'apprenne au prochain apply. Je veux savoir chaque matin si ce qui tourne correspond au code, et faire la différence entre « quelqu'un a touché à la main » et « une MR fusionnée n'a pas encore été appliquée ». Sophie veut la preuve conservée pour l'audit.

**Objectifs pédagogiques**
- Distinguer la **dérive** (la réalité a changé hors d'OpenTofu) de l'**écart de code** (le code a changé, l'apply n'a pas eu lieu) et les détecter séparément.
- Concevoir une détection planifiée qui ne modifie rien, ne gêne pas les applys et produit une preuve exploitable.
- Décider, pour chaque dérive, entre « réappliquer le code » et « faire entrer le changement dans le code ».

**Prérequis** : M05-E26, M05-E27 ; M04-E29 (détection de dérive de configuration, même logique).
**Durée indicative** : 3 h.

**Contraintes**
- Exécution quotidienne en heures creuses (fuseau Europe/Paris) par un pipeline planifié de `plateforme/infra` sur `main`, pour `socle/`, `envs/lab-m05/` et `envs/recette-m05/`.
- Trois issues distinctes par configuration et pour l'ensemble : **conforme**, **dérive** (et, séparément, **écart de code non appliqué**), **erreur** (plan impossible, backend injoignable). Le même outil se lance à la main sur `adm01` et renvoie un code de sortie différent pour chaque issue.
- Rien n'est écrit : ni état, ni infrastructure. La détection ne tourne jamais pendant un apply du même état, et ne laisse jamais de verrou derrière elle.
- Le rapport nomme chaque ressource concernée et chaque attribut qui diffère, sans aucun secret ni contenu d'état ; il est conservé **90 jours**.
- Alerte : un ticket GitLab étiqueté `derive` dans `plateforme/infra` (un seul ouvert à la fois, les détections suivantes le commentent), avec le lien vers le rapport, créé par un jeton aux droits minimaux, inscrit au registre des secrets.
- Démonstration complète sur `s3-01`, sans risque pour le service : une modification **réversible et sans effet sur le service** faite à la main dans Proxmox, détectée, signalée, puis résolue par la bonne voie (et justifie laquelle) ; une modification de code fusionnée sans apply, signalée comme écart et non comme dérive ; puis une détection conforme.
- Écris, dans `docs/socle/iac.md` de `plateforme/medisphere`, ce qu'on fait d'une dérive constatée : qui décide, quelle voie, sous quel délai.

**Critères de réussite**
- [ ] Un pipeline planifié actif sur `main` lance la détection chaque jour ; une détection planifiée a produit un rapport conservé 90 jours.
- [ ] Un ticket étiqueté `derive` a été ouvert par une détection, puis fermé après résolution.
- [ ] La dernière détection planifiée est conforme.
- [ ] L'outil, lancé à la main sur `adm01`, renvoie trois codes distincts (conforme, dérive ou écart, erreur), sans laisser de verrou.

**Vérification** : `lab/bin/check 05 28`

<details><summary>Indice 1</summary>

Un plan ordinaire compare le **code** à la réalité ; un plan `-refresh-only` compare l'**état** à la réalité. Le JSON d'un plan (`tofu show -json`) contient un champ `resource_drift` à côté de `resource_changes`.
</details>

<details><summary>Indice 2</summary>

Relis le `resource_group` de tes jobs `apply:` (E26) et les options de verrou de `tofu plan` (`-lock`, `-lock-timeout`). Pour le ticket, un jeton d'accès de projet de rôle *Reporter* avec la portée `api` suffit (M04-E29).
</details>

**Pour aller plus loin** (facultatif) : publie le nombre de ressources en dérive comme métrique pour Prometheus (module 21), et compare avec la détection de dérive de configuration de M04-E29 : laquelle verrait une option de `sshd` modifiée à la main, laquelle la mémoire d'une VM ?

---

### M05-E29 — Sauvegarder et restaurer l'état  `LAB` `★★`

> **Ticket PLAT-665** — *De : Nadia Roussel*
> Si l'objet `socle/terraform.tfstate` disparaît ou est écrasé, OpenTofu croit que le socle n'existe pas et propose de tout recréer. Je veux trois choses : savoir combien de temps il nous faut pour revenir à un état sain, l'avoir mesuré une fois pour de vrai, et une copie de chaque état qui survive à la perte de `s3-01`. Une sauvegarde qu'on n'a jamais restaurée, chez moi, ça n'existe pas.

**Objectifs pédagogiques**
- Identifier les niveaux de protection de l'état (versionnage de l'objet, sauvegarde de la VM, copie externe) et le scénario que couvre chacun.
- Restaurer une version précédente d'un objet d'état, et une copie externe, en sachant ce que vérifient (ou non) OpenTofu et S3 au passage.
- Valider une sauvegarde par un plan, sans toucher à l'état de production.

**Prérequis** : M05-E11 (versionnage), M05-E26 (pipeline), M05-E27 (états chiffrés).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Le compartiment `tofu-state` est versionné : une écriture crée une version, une suppression crée un **marqueur de suppression** (`delete marker`). Commandes utiles : `aws s3api list-object-versions`, `get-object --version-id`, `copy-object --copy-source 'tofu-state/<clé>?versionId=<ID>'`.
- `s3-01` (avec son disque de données) est sauvegardée chaque nuit par PBS (tâche `lab-nuit` du pool `lab`, M00).
- Un état chiffré (E27) garde **en clair** `serial` et `lineage` : on peut vérifier une sauvegarde sans la phrase. `tofu state push` refuse un fichier chiffré ; `tofu state pull` produit une copie **en clair**.
- Copie externe : un job planifié de `plateforme/infra` (variable de planification `PLANIF=sauvegarde-etats`) qui conserve les objets d'état **tels quels** (chiffrés) en artefact, 90 jours, accès réservé aux Maintainers. Restaurations d'essai sous le préfixe `_restauration/` du compartiment, à vider après usage.
- Scripts attendus dans `plateforme/infra` : `outils/sauvegarder-etats.sh` et `outils/restaurer-etat.sh`.

> ⚠️ **Attention** : ne t'entraîne **jamais** sur l'objet du socle en place. Les exercices de restauration portent sur `envs/lab-m05/` (version précédente) et sur une copie de l'état du socle restaurée sous `_restauration/`. N'utilise `tofu state push -force` dans aucun cas.

**Travail demandé**
1. **Cartographie.** Dans `docs/socle/iac.md` (section « Sauvegarde et restauration de l'état »), un tableau : scénario (écrasement par un apply erroné, suppression de l'objet, état corrompu, phrase de chiffrement perdue, perte de `s3-01`, perte de `pve01`), mécanisme qui le couvre, perte de données maximale (RPO), durée de retour (RTO) estimée. Un des scénarios n'est couvert par aucun mécanisme technique : lequel, et que fais-tu ?
2. **`outils/sauvegarder-etats.sh DOSSIER`** : copie chaque objet d'état courant du compartiment (pas les verrous, pas `_restauration/`) dans un dossier daté, sans le déchiffrer, avec un manifeste (clé, `VersionId`, `serial`, `lineage`, SHA-256) ; il **refuse** de terminer avec succès si un état est en clair (après E27, c'est une anomalie) ou si un objet est illisible.
3. **Job planifié** `sauvegarde-etats`, une fois par jour, artefact conservé 90 jours, accès Maintainers. Vérifie le premier artefact.
4. **Restauration d'une version** (sur `envs/lab-m05/`) : enregistre la version courante de l'objet, provoque une écriture erronée **sans rien appliquer** (retire une VM de l'état avec `tofu state rm`), constate le plan qui en découle (n'applique pas), puis restaure la version précédente avec `outils/restaurer-etat.sh`. Le plan doit redevenir vide. Le script garde une trace de la version qu'il remplace et refuse de restaurer un objet dont le `lineage` diffère.
5. **Restauration d'une copie externe** (le socle) : à partir de l'artefact du job, restaure l'objet du socle sous `_restauration/socle/terraform.tfstate`, puis prouve qu'il est utilisable : un `tofu plan` dans une copie temporaire de `socle/` (hors de `~/src/infra`) branchée sur cette clé doit être vide. Mesure le temps total, du téléchargement de l'artefact au plan vide : c'est ton RTO mesuré. Vide `_restauration/` ensuite.
6. Remplis le tableau avec tes mesures et fusionne.

**Critères de réussite**
- [ ] Un pipeline planifié actif lance `sauvegarde-etats` chaque jour ; son dernier job a réussi et conservé ses artefacts environ 90 jours, accès restreint.
- [ ] `outils/sauvegarder-etats.sh` et `outils/restaurer-etat.sh` sont sur `main` ; `sauvegarder-etats.sh` échoue sur un état en clair.
- [ ] Le plan de `envs/lab-m05/` est vide après la restauration ; l'objet a au moins une version de plus qu'avant l'exercice.
- [ ] Aucun objet ne reste sous `_restauration/` ; aucun fichier d'état ne traîne dans `~/src/infra`.
- [ ] `docs/socle/iac.md` contient le tableau des scénarios avec un RTO **mesuré**.

**Vérification** : `lab/bin/check 05 29`

<details><summary>Indice 1</summary>

`tofu init -reconfigure -backend-config=key=<autre clé>` branche une copie d'une configuration sur un autre objet du même compartiment, sans toucher au `.terraform/` de ta copie de travail si tu travailles dans un autre dossier. `-lock=false` est acceptable pour un plan en lecture sur une clé que personne d'autre n'utilise ; jamais pour une commande qui écrit.
</details>

<details><summary>Indice 2</summary>

Un objet d'état chiffré est un JSON qui a les clés `encrypted_data`, `serial` et `lineage` et pas de clé `resources`. Avec la CLI `aws` et `--query`, la version la plus récente non courante d'une clé se trouve dans `Versions[?IsLatest==\`false\`]` (attention à l'ordre).
</details>

**Pour aller plus loin** (facultatif) : la passerelle S3 de SeaweedFS sait-elle appliquer une règle de cycle de vie aux versions non courantes (`put-bucket-lifecycle-configuration`, `NoncurrentVersionExpiration`) ? Teste-le sur un compartiment d'essai : les verrous `.tflock` créent une version (et un marqueur) à chaque opération.

---

### M05-E30 — ADR : le stockage S3 du socle après l'abandon de MinIO  `RED` `★★`

> **Ticket PLAT-668** — *De : Claire Morel*
> On a choisi SeaweedFS dans l'urgence, au palier 2, parce que MinIO venait de nous lâcher. Avant que MédiDoc, les sauvegardes Velero (module 16) et d'autres projets ne s'y installent, je veux une décision écrite : pourquoi SeaweedFS, contre quoi, à quelles conditions on en changerait, et comment on en sortirait. Les arguments doivent être **vérifiés**, pas recopiés d'un comparatif. Format ADR habituel ; Karim et Sophie relisent.

**Objectifs pédagogiques**
- Évaluer un composant d'infrastructure sur des critères explicites : fonctions indispensables, licence, gouvernance, maintenance, sécurité, coût d'exploitation, réversibilité.
- Vérifier une affirmation technique par un test plutôt que par une documentation ou un comparatif.
- Tirer les leçons d'un abandon de projet libre et prévoir une stratégie de sortie.

**Prérequis** : M05-E10, M05-E12 (script de test des écritures conditionnelles), M05-E29 ; ADR précédents (format).
**Durée indicative** : 2 h.

**Contexte technique** (faits datés, à revérifier)
- MinIO : plus de binaires ni d'images de l'édition communautaire depuis octobre 2025, console retirée de l'édition libre, dépôt archivé en février 2026 ; l'offre commerciale continue (AIStor). Un fork communautaire (`pgsty/minio`, février 2026, AGPLv3) republie binaires et paquets.
- Besoins du socle : écritures conditionnelles (`If-None-Match: *`, verrou `use_lockfile`), versionnage, TLS, identités par usage, empreinte mémoire compatible avec 2 Go de RAM ; besoins à venir : MédiDoc, Velero (module 16), éventuellement un datastore S3 de PBS.
- Candidats à évaluer au minimum : SeaweedFS, Garage, Versity Gateway, RustFS (version 1.0 publiée en septembre 2026), Ceph RGW (qui arrive au module 08), le fork communautaire de MinIO ; et une option sans S3 : l'état OpenTofu géré par GitLab (backend `http`).

**Travail demandé**

Rédige `docs/socle/adr/ADR-0050-stockage-s3-socle.md` dans `plateforme/medisphere` (MR relue). L'ADR doit :
- poser le contexte (ce qui s'est passé avec MinIO, ce que le socle exige aujourd'hui et demain) et des **facteurs de décision** explicites et pondérés ;
- comparer au moins **cinq** options dans un tableau, avec pour chaque cellule « vérifié par test », « vérifié dans la documentation officielle (lien, date) » ou « non vérifié » ;
- pour au moins **deux** candidats autres que SeaweedFS, rapporter le résultat du script de M05-E12 (écritures conditionnelles) lancé contre une instance d'essai sur une VM jetable (VMID 2057-2059, détruite ensuite), **ou** expliquer précisément pourquoi le test n'a pas pu être fait ;
- trancher, et dire **à quelles conditions** la décision serait revue (indicateurs observables : activité du projet, délai de correction des failles, changement de licence…) ;
- décrire la **stratégie de sortie** : comment migrer les états et les données vers un autre stockage, en combien de temps, avec quel test ;
- nommer les conséquences négatives et leur traitement.

**Critères de réussite**
- [ ] L'ADR est fusionné, au format des ADR précédents, avec au moins cinq options comparées et la nature de chaque vérification.
- [ ] Au moins deux candidats ont été testés (ou l'impossibilité est argumentée), et la décision cite ces résultats.
- [ ] Les conditions de révision sont observables, la stratégie de sortie est testable.

<details><summary>Indice 1</summary>

Le statut d'un projet se lit dans ses dépôts : date de la dernière version, nombre de mainteneurs actifs, délai de traitement des avis de sécurité, licence et éventuel accord de contribution (CLA). Un projet porté par une seule entreprise peut changer de licence ; un projet porté par une seule personne peut s'arrêter.
</details>

<details><summary>Indice 2</summary>

Pour une stratégie de sortie, pense à ce qui est **portable** : les états OpenTofu sont des objets que `aws s3 sync` copie d'un stockage à un autre ; un changement de backend se fait par `tofu init -migrate-state`. Ce qui l'est moins : les identités, les politiques d'accès, les URL écrites dans les configurations des consommateurs.
</details>

**Pour aller plus loin** (facultatif) : compare le budget mémoire réel de `s3-01` (`ps`, `free`, métriques de SeaweedFS) avec ce que demanderait Ceph RGW au module 08 ; à partir de quel volume de données ou de quel besoin de haute disponibilité la décision basculerait-elle ?

---

### M05-E31 — Mettre à jour les providers sans surprise  `LAB` `★★`

> **Ticket CHG-671** — *De : Karim Benali*
> `bpg/proxmox` a publié une 0.116.0 le 6 octobre. On est en `~> 0.115.0`, et ce provider est encore en 0.x : chaque version mineure peut casser quelque chose. Je ne veux ni rester trois ans en arrière, ni découvrir une rupture le jour où l'on doit recréer une VM en urgence. Monte de version proprement, sur tout le dépôt, et écris la procédure : on la refera chaque mois.

**Objectifs pédagogiques**
- Lire un journal des modifications de provider et en déduire les risques pour son code.
- Maîtriser la contrainte de version, le fichier de verrouillage des dépendances (`.terraform.lock.hcl`), `tofu init -upgrade` et `tofu providers lock`.
- Valider une montée de version par des plans sur **toutes** les configurations avant tout apply, et prévoir un retour arrière qui tienne compte de l'état.

**Prérequis** : M05-E03 (lock et contraintes), M05-E24, M05-E26, M05-E29.
**Durée indicative** : 2 h.

**Contexte technique**
- Journal des modifications : <https://github.com/bpg/terraform-provider-proxmox/blob/main/CHANGELOG.md>. Registre : `registry.opentofu.org/bpg/proxmox`.
- Configurations qui déclarent le provider : `socle/`, `envs/lab-m05/`, `envs/recette-m05/`, le composant Terragrunt `vms` (et ses unités), le module `vm-debian` de `plateforme/tofu-modules`.
- Le lock enregistre deux familles d'empreintes : `zh:` (empreintes des archives publiées par le registre, toutes plateformes) et `h1:` (empreinte du contenu du paquet). `tofu providers lock -platform=…` complète le lock pour des plateformes données.
- Après un apply, l'état garde la **version du schéma** de chaque ressource écrite par le provider.

**Travail demandé**
1. **Lecture.** Lis les entrées 0.116.0 du journal (et des versions sautées, s'il y en a). Pour chacune, note dans ton journal : touche-t-elle une ressource que nous utilisons ? Peut-elle changer un plan sans changement de code ? Une entrée concerne les VMs **clonées** : laquelle, et que crains-tu ?
2. **Contraintes.** Sur une branche `conf/provider-0.116`, change la contrainte dans chaque configuration racine et dans le composant Terragrunt. Faut-il toucher au module `vm-debian` ? Justifie à partir de sa contrainte.
3. **Lock.** Mets à jour chaque lock (`tofu init -upgrade`, puis `tofu providers lock` pour `linux_amd64`). Relis le diff du lock : que vérifie OpenTofu au téléchargement d'un provider, et que se passerait-il en CI si tu avais oublié une plateforme ?
4. **Plans.** Lance un plan sur chaque configuration (et `terragrunt run --all plan` s'il reste des unités). Le résultat attendu est « No changes » partout. Si un plan change quelque chose, ne l'accepte pas par réflexe : explique l'origine (normalisation par le provider, nouvelle valeur par défaut, vraie différence), et décide (accepter, `ignore_changes` argumenté, rester sur 0.115). Si tout est vide, explique pourquoi l'entrée qui t'inquiétait n'a pas eu d'effet.
5. **Retour arrière.** Avant de fusionner, écris le retour arrière **exact**. Que se passe-t-il si l'on revient à 0.115.0 **après** un apply en 0.116.0 qui a réécrit l'état ? Quelle version de l'objet d'état faudrait-il restaurer (E29) ?
6. Fusionne, applique par le pipeline (plan vide : l'apply réécrit l'état avec le nouveau provider), puis écris la procédure mensuelle dans `docs/socle/iac.md` (section « Montée de version des providers ») : fréquence, lecture, branche, locks, plans, apply, retour arrière, et qui décide d'un report.

**Critères de réussite**
- [ ] Sur `main`, toutes les configurations racine et le composant Terragrunt `vms` contraignent `bpg/proxmox` à `~> 0.116.0`, et chaque `.terraform.lock.hcl` versionné fixe 0.116.0.
- [ ] Les plans de `socle/`, `envs/lab-m05/` et `envs/recette-m05/` sont vides avec le nouveau provider.
- [ ] Le pipeline a appliqué le socle après la fusion.
- [ ] `docs/socle/iac.md` contient la procédure de montée de version, retour arrière compris.

**Vérification** : `lab/bin/check 05 31`

<details><summary>Indice 1</summary>

`tofu init -upgrade` choisit la version la plus récente qui satisfait la contrainte et réécrit le lock ; sans `-upgrade`, `tofu init` respecte le lock existant, même si une version plus récente satisfait la contrainte. `tofu version` et `tofu providers` montrent ce qui est réellement utilisé.
</details>

<details><summary>Indice 2</summary>

Un provider plus ancien qui rencontre une ressource dont le schéma a été écrit par une version plus récente peut refuser de la lire. Les versions de l'objet d'état dans `tofu-state` gardent l'état d'avant l'apply.
</details>

**Pour aller plus loin** (facultatif) : Renovate (module 13) sait ouvrir ces MR tout seul, lock compris ; quelles règles lui donnerais-tu pour un provider en 0.x ?

---

### M05-E32 — Questions de production : état, équipes et rayon d'impact  `Q` `★★★`

> **Ticket PLAT-674** — *De : Karim Benali*
> Questions de revue d'architecture, pour le jour où trois équipes écriront de l'OpenTofu dans le même cloud privé. Argumente, chiffre quand tu peux, et dis quand « ça dépend » — mais de quoi.

**Objectifs pédagogiques**
- Raisonner sur le découpage des états, les droits, les dépendances entre équipes et le rayon d'impact d'une erreur.
- Connaître les mécanismes de partage entre états et leurs risques.
- Anticiper les défaillances d'une chaîne IaC en production.

**Prérequis** : paliers 1 à 3 du module.
**Durée indicative** : 1 h 30.

**Questions**

1. Le socle, MédiAgenda et MédiDoc auront leur infrastructure dans OpenTofu. Un seul état, un état par équipe, un état par composant (réseau, VMs, DNS…) ? Donne les critères (fréquence de changement, rayon d'impact, droits, durée du plan, dépendances) et propose un découpage pour MédiSphère.
2. Une équipe a besoin de l'adresse de `s3-01`, produite par l'état du socle. Compare `terraform_remote_state`, un `dependency` Terragrunt, une source de données du provider (lire la VM dans Proxmox) et une valeur publiée ailleurs (NetBox au module 06). Quels droits chaque méthode donne-t-elle au lecteur ? Que lit vraiment `terraform_remote_state` ?
3. QCM — Après la fusion d'une MR, le pipeline de `main` recalcule un plan avant l'apply. Ce plan peut différer de celui relu dans la MR. Pourquoi ?
   a) il ne peut pas différer, le code est le même ; b) parce qu'une autre MR a été fusionnée entre-temps, ou que la réalité a changé (dérive), ou qu'un module référencé par une étiquette mobile a changé ; c) parce que GitLab réécrit le code à la fusion ; d) uniquement si le provider a changé de version.
4. Que garantit `tofu apply plan.tfplan` que ne garantit pas `tofu apply -auto-approve` ? Et que **ne** garantit-il **pas** (pense à ce qui a été relu, et à quand) ?
5. `-target` (et `-exclude`, propre à OpenTofu) : dans quels cas sont-ils légitimes ? Pourquoi un pipeline ne devrait-il jamais en avoir besoin ? Que dit OpenTofu quand on les utilise, et pourquoi ?
6. QCM — Un `tofu apply` du socle a été tué (job annulé) au milieu de la création d'une VM. Que trouves-tu probablement ?
   a) rien : OpenTofu est transactionnel et a tout annulé ; b) un verrou peut-être resté, une VM peut-être créée dans Proxmox mais absente de l'état (ou marquée *tainted*), un état écrit jusqu'à la dernière ressource terminée ; c) un état corrompu à restaurer obligatoirement ; d) toutes les VMs du socle arrêtées.
7. Le jeton `wb-tofu` a les droits de clonage et de destruction sur tout le pool `lab`, et chaque état du dépôt l'utilise. Propose un découpage des identités (Proxmox et S3) par état. Qu'est-ce que ça change si un environnement de test est compromis ? Quelle limite de Proxmox rencontre-t-on (pense au pool unique, ADR-0030) ?
8. Les politiques de sécurité de l'E25 analysent le code. Qu'est-ce qu'une analyse du **plan** (Checkov sur le plan JSON, OPA/conftest) voit en plus ? Qu'est-ce qu'aucune des deux ne voit ?
9. QCM — Deux équipes veulent « déplacer » une VM d'un état à un autre. La bonne démarche est :
   a) `tofu state mv` vers un fichier local, puis copie de l'objet S3 à la main ; b) un bloc `removed` (avec `lifecycle { destroy = false }`) dans l'état d'origine et un bloc `import` dans l'état d'arrivée, appliqués dans cet ordre, chacun relu sur son plan ; c) supprimer la VM et la recréer dans le nouvel état ; d) éditer les deux objets d'état avec `jq`.
10. Ton runner `shell` exécute les pipelines de tous les projets. Pourquoi est-ce un problème particulier pour `plateforme/infra` ? Liste trois mesures, dont une qui arrivera au module 19.
11. L'état géré par GitLab (backend `http`), Atlantis, ou un pipeline maison comme le tien : cite deux avantages et deux inconvénients de chacun pour MédiSphère.
12. Quels indicateurs suivrais-tu chaque mois pour dire que l'IaC « fonctionne » ? Propose-en quatre, avec leur seuil d'alerte et la source de la donnée.

**Critères de réussite**
- [ ] Les 12 questions ont une réponse écrite et argumentée ; les QCM indiquent la bonne réponse **et** pourquoi les autres sont fausses.
- [ ] Après correction, trois points faibles identifiés, avec pour chacun un exercice à refaire ou une lecture.

<details><summary>Indice 1</summary>

Pour la question 2, relis la documentation de la source de données `terraform_remote_state` : elle lit **tout** l'état distant pour n'en extraire que les sorties. Pour la question 6, rappelle-toi qu'OpenTofu écrit l'état au fil des ressources terminées, pas en une transaction.
</details>

<details><summary>Indice 2</summary>

Pour la question 3, regarde comment ton dépôt référence le module `vm-debian` : une étiquette Git protégée est-elle immuable ? Pour la question 9, relis E16 et E17.
</details>

**Pour aller plus loin** (facultatif) : lis le chapitre sur l'organisation des « stacks » du livre de Kief Morris (*Infrastructure as Code*, 3ᵉ éd.) et compare avec ton découpage de la question 1.

---

### M05-E33 — Runbook : verrou d'état bloqué  `RED` `★★`

> **Ticket PLAT-677** — *De : Nadia Roussel*
> Hier, le job `apply:socle` a été annulé par erreur, et le suivant a échoué sur « Error acquiring the state lock ». Karim n'était pas là, et personne n'a osé toucher à rien : on a perdu une demi-journée. Il me faut un runbook que l'astreinte de premier niveau peut suivre : comment savoir si le verrou est vraiment orphelin, comment le lever sans casser l'état, et quand surtout ne **pas** le faire.

**Objectifs pédagogiques**
- Comprendre le verrou natif S3 d'OpenTofu : objet `.tflock`, écriture conditionnelle, contenu, cycle de vie.
- Établir qu'un verrou est orphelin avant de le lever (preuve, pas intuition), et le lever par la commande prévue.
- Écrire un runbook exécutable par quelqu'un qui ne connaît pas OpenTofu en profondeur.

**Prérequis** : M05-E12, M05-E26, M05-E29 ; runbooks précédents (format RB-040).
**Durée indicative** : 2 h.

**Contexte technique**
- Le verrou d'un état `<clé>` est l'objet `<clé>.tflock` du même compartiment, écrit avec `If-None-Match: *` et supprimé à la fin de l'opération. Son contenu JSON est celui qu'affiche le message d'erreur (`ID`, `Operation`, `Who`, `Version`, `Created`, `Path`).
- `tofu force-unlock <ID>` supprime le verrou **si** son identifiant correspond. Les options `-lock-timeout` des commandes attendent qu'un verrou se libère.
- Le compartiment est versionné : chaque prise et chaque libération de verrou laissent une version et un marqueur.
- Les jobs `apply:` et la détection de dérive partagent un `resource_group` par état (E26, E28) ; un verrou peut aussi venir de `adm01` (plan ou apply d'un humain) ou d'un `terragrunt` lancé sur un environnement.

**Travail demandé**
1. **Fabrique un verrou orphelin, sans risque** : sur `envs/lab-m05/`, lance un `tofu plan` (un plan prend le verrou) et tue-le avec `kill -9` pendant qu'il rafraîchit. Constate le message du plan suivant, lis l'objet `.tflock`, et lève le verrou. Recommence en tuant le processus avec `Ctrl+C` : la différence ?
2. **Les autres cas.** Décris (sans les provoquer sur le socle) ce que tu observerais : un job `apply:socle` en cours ; un job annulé dans GitLab ; un `tofu apply` lancé depuis `adm01` dans un `tmux` oublié ; un `runner01` redémarré pendant un job.
3. Rédige **RB-050 « Verrou d'état bloqué »** dans `docs/socle/runbooks/` de `plateforme/medisphere`, au format de RB-040 : symptômes, informations à relever, **arbre de décision** (qui détient le verrou, est-il vivant, que faire), commandes exactes, vérification après levée (plan, état non corrompu, version de l'objet), ce qu'il ne faut jamais faire (et pourquoi), escalade, consignation.
4. Fais relire RB-050 par une personne qui ne connaît pas OpenTofu (ou, à défaut, relis-le le lendemain en suivant les étapes à la lettre sur un nouveau verrou orphelin fabriqué comme en 1).

**Critères de réussite**
- [ ] RB-050 est fusionné dans `plateforme/medisphere`, au format des runbooks précédents.
- [ ] Il contient un arbre de décision qui distingue au moins : opération en cours, job CI annulé ou tué, processus humain oublié, détenteur inconnu.
- [ ] Il donne la commande de levée **et** la vérification qui suit ; il interdit explicitement `-lock=false` sur une commande qui écrit et la suppression directe de l'objet `.tflock` hors cas décrit.
- [ ] Aucun verrou ne reste sur `envs/lab-m05` ; son plan est vide.

<details><summary>Indice 1</summary>

Le champ `Who` du verrou vaut `utilisateur@machine`. Sur `runner01`, l'utilisateur est `gitlab-runner` ; sur `adm01`, `admin`. `pgrep -af tofu` sur la machine indiquée, et la liste des jobs en cours du projet dans GitLab, disent si le détenteur vit encore.
</details>

<details><summary>Indice 2</summary>

Un `Ctrl+C` envoie un signal que `tofu` intercepte pour s'arrêter proprement ; `kill -9` ne lui en laisse pas le temps. Un job GitLab annulé reçoit d'abord un signal, puis est tué au bout d'un délai.
</details>

**Pour aller plus loin** (facultatif) : écris `outils/verrou-etat.sh <clé>` qui affiche le contenu du verrou, son âge, et, si le détenteur est `gitlab-runner@runner01`, l'état des jobs `apply:` en cours par l'API de GitLab.

---

### M05-E34 — Un environnement complet en temps limité  `CHRONO` `★★★`

> **Ticket DEV-679** — *De : Julien Petit*
> La semaine prochaine, on fait la répétition générale de la mise en production de MédiAgenda. Il me faut un environnement de préproduction neuf, à l'image de ce que sera la production, et je dois pouvoir m'y connecter jeudi matin. Le cahier des charges est prêt. Karim relira la MR comme d'habitude, et Sophie passera derrière.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas de code copié d'Internet ; ton dépôt, tes notes, la documentation officielle (OpenTofu, Terragrunt, `bpg/proxmox`) sont permis.
- Durée : **3 h** entre l'ouverture du cahier des charges (T0) et la MR prête à fusionner, pipeline vert, environnement en service (T4). Les pauses ne comptent pas, les attentes de la CI et de Proxmox comptent.
- Le cahier des charges est dans `~/DevOpsPrivateCloud/modules/05-iac/ressources/M05-E34/cahier-des-charges.md`. **Ne l'ouvre qu'au démarrage du chrono.**
- VMID disponibles : **2057, 2058 et 2059** (les environnements de E24 et E27 doivent être détruits avant de commencer).

**Prérequis** : M05-E24 à M05-E27.
**Durée** : 3 h chronométrées + 30 minutes de retour d'expérience.

**Déroulé**
1. Prépare ta feuille de temps (ci-dessous) et un chronomètre. Vérifie que les VMs 2057-2059 n'existent pas, que le pipeline de `main` est vert et que `git status` est propre.
2. T0 : ouvre le cahier des charges.
3. Livre : le code, l'environnement appliqué, la MR.
4. Arrête le chrono quand la MR est prête à fusionner (pipeline vert, description complète) et que l'environnement répond. Fusionne ensuite (hors chrono). Lance la vérification, puis détruis l'environnement **par Terragrunt** et vérifie que les VMs ont disparu.

**Feuille de temps à remplir**

| Jalon | Définition | Heure | Écart depuis T0 | Commentaire |
|---|---|---|---|---|
| T0 | Ouverture du cahier des charges | | 0 | |
| T1 | Code écrit, `terragrunt run --all plan` sans erreur | | | |
| T2 | Environnement appliqué, connexion SSH réussie sur chaque VM avec la clé de l'environnement | | | |
| T3 | Analyse de sécurité et contrôles de qualité locaux au vert, MR ouverte | | | |
| T4 | Pipeline de la MR vert, description complète (plan, preuves, ce qui n'est pas testé) | | | |

**Retour d'expérience à rédiger** (une demi-page, dans ton journal) : ce qui a pris le plus de temps, ce que tu as dû chercher dans la documentation, ce que ta structure Terragrunt t'a épargné (ou coûté), ce que tu automatiserais pour le prochain environnement.

**Critères de réussite**
- [ ] Le code de l'environnement est sur `main` (fusionné après le chrono) et respecte chaque exigence du cahier des charges.
- [ ] Au moment de la vérification, les VMs demandées tournent avec les bonnes étiquettes et ressources, et leurs états sont chiffrés dans `tofu-state`.
- [ ] Après la vérification, l'environnement est détruit par Terragrunt (VMs 2057-2059 absentes).
- [ ] T4 − T0 ≤ 3 h (sinon, refais l'exercice avec un autre cahier des charges de ton choix après avoir lu la grille du corrigé).

**Vérification** : `lab/bin/check 05 34` (à lancer **avant** de détruire l'environnement).

**Pour aller plus loin** (facultatif) : refais l'exercice en binôme « auteur / relecteur » : l'un écrit, l'autre ne relit que la MR finale avec la grille du corrigé.
