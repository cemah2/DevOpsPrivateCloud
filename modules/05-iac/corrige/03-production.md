# Module 05 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Ce qui a été exécuté pour écrire ce corrigé** (bac à sable, octobre 2026) : OpenTofu 1.13.1, Terragrunt 1.1.6, Checkov 3.3.26, Trivy 0.75.0, tflint 0.64.0, AWS CLI 2.37 contre une passerelle **SeaweedFS 4.48** locale. Vérifiés en vrai : verrou `use_lockfile` (412 au second `apply`), versionnage et restauration d'une version par `copy-object`, migration vers un état chiffré (`fallback` puis `enforced`), `TF_ENCRYPTION` fusionné avec le code, refus d'un plan périmé, `tofu state push` refusant un état chiffré, Terragrunt (`run --all`, `dag graph`, `list`, `--filter`, `--out-dir`, `dependency` avec sorties factices, génération du backend et du bloc `encryption`), règles maison Checkov (YAML, y compris sur un bloc `provider`) et Trivy (Rego `terraform-raw`), expiration dans `.trivyignore`, signature Sigstore de Trivy et de Terragrunt, `outils/analyse-securite.sh`, `outils/derive.sh`, `outils/derive-alerte.sh` (contre une fausse API GitLab), tâches Ansible (`ansible-lint` profil `production`).

**Non testé en conditions réelles** (signale tes retours) : tout ce qui touche à Proxmox et à GitLab réels — en particulier `artifacts:access` combiné aux rapports, la variable `$DOSSIER` dans `artifacts:paths`, `allow_failure: exit_codes`, *Prevent outdated deployment jobs*, le comportement de `bpg/proxmox` 0.116.0 sur nos VMs clonées, et les scripts `sauvegarder-etats.sh` / `restaurer-etat.sh` dans leur version finale (leurs commandes S3 ont été validées une par une, pas le script complet). Ces points sont signalés « ⚠️ À vérifier sur ta version » là où ils interviennent.

---

### M05-E24 — Terragrunt : factoriser backends, providers et environnements

**Solution**

Fichiers complets : [`fichiers/M05-E24/infra/terragrunt/`](fichiers/M05-E24/infra/terragrunt/) — `live/root.hcl`, `live/commun.hcl`, `live/_commun/proxmox.hcl`, `live/dev-agenda/` et `live/dev-doc/` (un `env.hcl` et deux unités chacun, avec leurs `.terraform.lock.hcl`), `composants/acces/` et `composants/vms/`.

*1. La duplication.* Les trois dossiers répètent le bloc `required_providers`, le bloc `provider "proxmox"` et onze lignes de backend ; seule la `key` diffère. Si l'on copie `envs/recette-m05` en `envs/dev-agenda` sans changer la `key`, les deux configurations lisent et écrivent **le même objet d'état** : le premier `plan` de `dev-agenda` voit dans l'état les VMs de `recette-m05`, absentes de son code, et propose de les **détruire** ; s'il est appliqué, elles disparaissent. Le verrou n'y peut rien : il empêche deux écritures simultanées, pas deux configurations de partager un état.

*2. Installation.*

```
admin@adm01:~$ mkdir -p ~/m05/e24 && cd ~/m05/e24
admin@adm01:~/m05/e24$ curl -fsSLO https://github.com/gruntwork-io/terragrunt/releases/download/v1.1.6/terragrunt_linux_amd64
admin@adm01:~/m05/e24$ curl -fsSLO https://github.com/gruntwork-io/terragrunt/releases/download/v1.1.6/SHA256SUMS
admin@adm01:~/m05/e24$ grep ' terragrunt_linux_amd64$' SHA256SUMS | sha256sum -c -
terragrunt_linux_amd64: OK
admin@adm01:~/m05/e24$ sudo install -m 0755 terragrunt_linux_amd64 /usr/local/bin/terragrunt
admin@adm01:~/m05/e24$ terragrunt --version
terragrunt version v1.1.6
```

La somme téléchargée au même endroit que le binaire ne protège que contre un téléchargement **abîmé** : quelqu'un qui remplace le binaire sur la page des versions remplace aussi `SHA256SUMS`. Deux protections réelles : une empreinte **figée dans ton dépôt** au moment où tu as validé la version (une substitution ultérieure est détectée), et la **signature** de `SHA256SUMS`, qui prouve que le fichier vient du flux de publication du projet. Avec `cosign` (module 13) :

```
admin@adm01:~/m05/e24$ curl -fsSLO https://github.com/gruntwork-io/terragrunt/releases/download/v1.1.6/SHA256SUMS.sigstore.json
admin@adm01:~/m05/e24$ cosign verify-blob --bundle SHA256SUMS.sigstore.json \
    --certificate-identity-regexp '^https://github.com/gruntwork-io/terragrunt/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com SHA256SUMS
Verified OK
```

(Le certificat de la 1.1.6 désigne `…/.github/workflows/release.yml@refs/heads/main` : l'expression régulière accepte ce flux ; tu peux la resserrer à ce chemin exact.)

*3-5. Composants, racine, unités.* Les points clés de [`root.hcl`](fichiers/M05-E24/infra/terragrunt/live/root.hcl) :

```hcl
remote_state {
  backend  = "s3"
  generate = { path = "backend.tf", if_exists = "overwrite_terragrunt" }
  config = {
    bucket = "tofu-state"
    key    = "envs/${path_relative_to_include()}/terraform.tfstate"   # live/dev-agenda/vms → envs/dev-agenda/vms/…
    # … mêmes réglages qu'en E11 …
    use_lockfile = true
  }
}
```

`path_relative_to_include()` renvoie le chemin de l'unité par rapport au dossier de `root.hcl` : deux unités ne peuvent pas avoir la même clé, et la clé se lit dans l'arborescence. Le bloc `provider "proxmox"` est dans [`_commun/proxmox.hcl`](fichiers/M05-E24/infra/terragrunt/live/_commun/proxmox.hcl), inclus par les seules unités `vms` : généré dans l'unité `acces`, il ferait chercher à OpenTofu un provider `hashicorp/proxmox` (un bloc `provider` sans `required_providers` correspondant désigne l'espace de noms `hashicorp`), qui n'existe pas, et `init` échouerait.

L'unité `vms` ([`terragrunt.hcl`](fichiers/M05-E24/infra/terragrunt/live/dev-agenda/vms/terragrunt.hcl)) lit l'environnement par `read_terragrunt_config(find_in_parent_folders("env.hcl"))`, la source par `${get_repo_root()}/terragrunt/composants//vms`, et la clé publique par :

```hcl
dependency "acces" {
  config_path  = "../acces"
  mock_outputs = { cle_publique_openssh = "ssh-ed25519 AAAA… maquette" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
```

Sans la restriction, un `run --all apply` lancé avant que `acces` ait une sortie pourrait créer les VMs avec la clé **factice** : elles seraient injoignables avec la clé de l'environnement (et un `apply` suivant les recréerait, la clé cloud-init étant dans `initialization`).

*6. Observer.*

```
admin@adm01:~/src/infra/terragrunt/live$ . ~/src/infra/outils/charger-acces.sh   # ou les deux « set -a; . … » avant E27
admin@adm01:~/src/infra/terragrunt/live$ terragrunt list --dag
dev-agenda/acces  dev-doc/acces     dev-agenda/vms    dev-doc/vms
admin@adm01:~/src/infra/terragrunt/live$ terragrunt dag graph
digraph {
	"dev-agenda/acces" ;
	"dev-agenda/vms" ;
	"dev-agenda/vms" -> "dev-agenda/acces";
	"dev-doc/acces" ;
	"dev-doc/vms" ;
	"dev-doc/vms" -> "dev-doc/acces";
}
admin@adm01:~/src/infra/terragrunt/live$ terragrunt run --all plan
… WARN [dev-agenda/vms] Config …/dev-agenda/acces/terragrunt.hcl is a dependency of …/vms/terragrunt.hcl that has no outputs, but mock outputs provided and returning those in dependency output.
… STDOUT [dev-agenda/acces] tofu: Plan: 1 to add, 0 to change, 0 to destroy.
… STDOUT [dev-agenda/vms] tofu: Plan: 2 to add, 0 to change, 0 to destroy.
❯❯ Run Summary  4 units
   Succeeded    4
```

Dans `dev-agenda/vms/.terragrunt-cache/<hash>/<hash>/vms/` : le composant copié, plus `backend.tf` et `provider-proxmox.tf` générés (en-tête « Generated by Terragrunt »). Le `.terraform.lock.hcl` est écrit par `tofu init` dans la copie de travail **puis recopié** par Terragrunt dans le dossier de l'unité (`live/dev-agenda/vms/.terraform.lock.hcl`) : c'est celui-là qu'on versionne ; le cache est jetable et ignoré (`.terragrunt-cache/` dans `.gitignore`).

*7. Appliquer.* Depuis `live/dev-agenda` : `terragrunt run --all apply` traite `acces` puis `vms` (ordre du graphe), en demandant une confirmation globale (`--non-interactive` / `TG_NON_INTERACTIVE=true` la supprime : à réserver à la CI). Clés créées :

```
admin@adm01:~$ aws s3 ls s3://tofu-state/envs/ --recursive
… envs/dev-agenda/acces/terraform.tfstate
… envs/dev-agenda/vms/terraform.tfstate
… envs/dev-doc/acces/terraform.tfstate
… envs/dev-doc/vms/terraform.tfstate
```

*8. La clé de Julien.*

```
admin@adm01:~/src/infra/terragrunt/live/dev-agenda/acces$ umask 077; terragrunt output -raw cle_privee_openssh > ~/m05/e24/dev-agenda.cle
admin@adm01:~$ ssh -o IdentitiesOnly=yes -o ControlPath=none -i ~/m05/e24/dev-agenda.cle admin@<IP-M05-AGENDA-API> hostname
m05-agenda-api
```

`<IP-M05-AGENDA-API>` : sortie `vms` de l'unité `vms` (`terragrunt output vms`), adresse DHCP en 10.10.99.x. `-o IdentitiesOnly=yes` empêche l'agent de proposer ta clé personnelle (sinon la connexion réussirait avec elle, et le test ne prouverait rien) ; `ControlPath=none` évite une connexion multiplexée existante. Où d'autre la clé est-elle en clair ? Dans l'objet `envs/dev-agenda/acces/terraform.tfstate` (attribut `private_key_openssh`), donc dans les versions de cet objet, dans la sauvegarde PBS de `s3-01`, et dans tout plan enregistré de cette unité.

*9. Le socle sous Terragrunt ?* Réponse attendue : **pas maintenant**. Arguments : un seul état, déjà sous pipeline (E26), protégé (`prevent_destroy`, `protection`) ; le migrer impose de retirer son bloc `backend` (sinon il entre en conflit avec le backend généré), ce qui casse tout `tofu` lancé directement dans `socle/` (le pipeline, les pannes du palier 4, l'habitude de l'équipe), pour un gain nul (rien à factoriser pour **un** état). Ce qu'on perd : une seule façon de lancer OpenTofu dans le dépôt, et la génération centralisée (elle couvrira quand même le chiffrement en E27, par copie du fichier du socle). Pour `envs/lab-m05` et `envs/recette-m05` : à migrer **à leur prochaine recréation** (ce sont des environnements jetables : détruire, recréer sous Terragrunt), pas par déplacement d'état.

*10. Détruire `dev-doc`.* `terragrunt run --all destroy` depuis `live/dev-doc` détruit `vms` **puis** `acces` : l'ordre inverse du graphe, parce qu'une unité ne peut pas perdre une dépendance encore utilisée. Puis `.terragrunt-cache/` dans `.gitignore`, MR, fusion.

**Explications**

Terragrunt ne remplace pas OpenTofu : il prépare, pour chaque **unité** (dossier qui contient un `terragrunt.hcl`), une copie de travail où il copie le code du composant et **génère** les fichiers communs (backend, provider, chiffrement), puis lance `tofu` dedans en passant les `inputs` comme variables `TF_VAR_…`. `run --all` découvre toutes les unités sous le dossier courant, construit le graphe à partir des blocs `dependency`, et exécute dans l'ordre (en parallèle quand c'est possible). Un `dependency` lit les sorties d'une autre unité par `tofu output -json` sur **son** état : c'est un couplage par les sorties, comme `terraform_remote_state`, mais ordonné.

**Alternatives**
- **OpenTofu seul** : un fichier de configuration partielle du backend (`backend "s3" {}` + `tofu init -backend-config=../backend.hcl -backend-config=key=…`) et des liens symboliques vers un `providers.tf` commun. Ça fonctionne, mais la clé reste à écrire à la main à chaque `init`, et rien n'ordonne les dépendances entre états.
- **Workspaces** d'OpenTofu (E15) : un seul code, une clé par espace de travail ; pratique pour des environnements **identiques**, mais un seul jeu de variables à brancher par workspace et un risque d'appliquer dans le mauvais.
- **Terragrunt *stacks*** (`terragrunt.stack.hcl`) : génèrent les unités d'un environnement depuis une description unique ; plus concis, une abstraction de plus.

**Pièges classiques**
- Tutoriels 0.x : `terragrunt run-all plan`, `--terragrunt-non-interactive`, `TERRAGRUNT_*` n'existent plus en 1.x ; un `terragrunt.hcl` à la racine (au lieu de `root.hcl`) est déprécié et fait de la racine une unité.
- Un composant qui garde son bloc `backend` : conflit avec le backend généré (« Duplicate backend configuration »).
- `mock_outputs` sans restriction de commandes : apply avec des valeurs factices.
- Versionner `.terragrunt-cache/` (providers de 100 Mo, fichiers générés) ou, à l'inverse, oublier le `.terraform.lock.hcl` de chaque unité.
- `run --all apply` depuis `live/` : il applique **tous** les environnements. Toujours se placer dans le dossier de l'environnement visé, ou utiliser `--filter`.

**En production chez MédiSphère**
Terragrunt reste réservé aux environnements nombreux et semblables (environnements de test à la demande, futurs clusters du bloc C) ; le socle reste une configuration simple sous pipeline. Version de Terragrunt figée sur `adm01` et `runner01` (`outils/versions-outils.env`), mise à jour par la procédure de E31. Chaque environnement porte une étiquette à son nom et une date de fin dans `env.hcl` : un job planifié (« Pour aller plus loin » de E26) signale ceux qui l'ont dépassée.

---

### M05-E25 — Analyse de sécurité du code : Checkov et Trivy

**Solution**

Fichiers : [`fichiers/M05-E25/infra/`](fichiers/M05-E25/infra/) — `.checkov.yaml`, `.trivyignore`, `politiques/checkov/*.yaml` (4 règles), `politiques/trivy/*.rego` (2 règles), `politiques/tests/` (6 cas fautifs), `outils/versions-outils.env`, `outils/analyse-securite.sh`, `pre-commit-extrait.yaml`.

*1. Installation.*

```
admin@adm01:~$ uv tool install 'checkov==3.3.26' && checkov --version
3.3.26
admin@adm01:~$ cd ~/m05/e25
admin@adm01:~/m05/e25$ V=0.75.0; B=https://github.com/aquasecurity/trivy/releases/download/v$V
admin@adm01:~/m05/e25$ curl -fsSLO $B/trivy_${V}_Linux-64bit.tar.gz -fsSLO $B/trivy_${V}_checksums.txt -fsSLO $B/trivy_${V}_Linux-64bit.tar.gz.sigstore.json
admin@adm01:~/m05/e25$ grep " trivy_${V}_Linux-64bit.tar.gz$" trivy_${V}_checksums.txt | sha256sum -c -
trivy_0.75.0_Linux-64bit.tar.gz: OK
admin@adm01:~/m05/e25$ sudo mkdir -p /opt/trivy/$V && sudo tar -xzf trivy_${V}_Linux-64bit.tar.gz -C /opt/trivy/$V
admin@adm01:~/m05/e25$ sudo ln -sfn /opt/trivy/$V/trivy /usr/local/bin/trivy
admin@adm01:~/m05/e25$ trivy --version | head -1; sha256sum /opt/trivy/$V/trivy
Version: 0.75.0
93f9da8e4ba5e0c1c76d8234ed2494cf9afb0a96fd21953e424bb795f3299b8e  /opt/trivy/0.75.0/trivy
```

Le dossier de version garde `contrib/junit.tpl` à côté du binaire (le script s'en sert). Signature (facultative ici, module 13) :

```
admin@adm01:~/m05/e25$ cosign verify-blob --bundle trivy_0.75.0_Linux-64bit.tar.gz.sigstore.json \
    --certificate-identity 'https://github.com/aquasecurity/trivy/.github/workflows/reusable-release.yaml@refs/tags/v0.75.0' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com trivy_0.75.0_Linux-64bit.tar.gz
Verified OK
```

Ce que prouve chaque vérification : la somme du fichier de sommes → le téléchargement est intact, rien de plus (même origine que l'archive) ; l'empreinte **figée dans `outils/versions-outils.env`** → la machine exécute exactement ce qui a été validé ce jour-là, et toute substitution ultérieure est refusée ; la signature → l'archive a été produite par le flux de publication du projet, à cette étiquette. Le 19 mars, un compte de publication compromis a **publié** une v0.69.4 signée par le flux officiel : la signature seule n'aurait pas suffi. Ce qui protégeait : ne pas avoir de raison de prendre une nouvelle version sans revue (version figée, pas de `latest`), et une empreinte figée **avant** l'incident, qui aurait fait échouer tout job sur lequel un binaire différent serait apparu. Les étiquettes déplacées de `trivy-action` sont l'autre leçon : une étiquette se déplace, une empreinte non (d'où les `rev` figées par empreinte de pre-commit, M01-E15).

*2. Premier passage.* Checkov n'a **aucune** règle pour les ressources `proxmox_*` ; Trivy non plus (ses règles visent les clouds publics, Kubernetes, Dockerfile…). Les seules alertes viennent des règles génériques : `CKV_TF_1` (« Ensure Terraform module sources use a commit hash ») sur chaque `module` ; `CKV_TF_2` (« … use a tag with a version number ») seulement sur une source sans `?ref=`. Elles ne se contredisent pas, elles graduent : `CKV_TF_2` exige une version, `CKV_TF_1` une empreinte immuable. Décision : on garde `CKV_TF_2` et on ignore `CKV_TF_1`, **justifié** dans `.checkov.yaml` : nos étiquettes `v*` de `plateforme/tofu-modules` sont protégées (seule la release du projet les pose), elles se lisent, et semantic-release les compare ; un module **tiers** entrant dans le dépôt serait, lui, épinglé par empreinte. C'est exactement la distinction de l'incident Trivy : les étiquettes déplacées étaient celles d'un dépôt tiers.

*3. Règles maison.* Checkov, en YAML ([`politiques/checkov/`](fichiers/M05-E25/infra/politiques/checkov/)) :

```yaml
metadata:
  id: "CKV2_MS_3"
  name: "Les VMs Proxmox clonées sont des clones complets (clone.full différent de false)"
  category: "GENERAL_SECURITY"
definition:
  cond_type: "attribute"
  resource_types:
    - "proxmox_virtual_environment_vm"
  attribute: "clone.full"
  operator: "not_equals"
  value: false
```

Les quatre : TLS vérifié (`resource_types: ["provider.proxmox"]`, `insecure` `not_equals` `true`), étiquettes déclarées (`tags` `exists`), clone complet, agent QEMU actif. `not_equals false` (et non `equals true`) pour le clone : `full` vaut `true` par défaut dans le provider, une VM qui ne l'écrit pas est conforme. Trivy, en Rego sur le code brut ([`politiques/trivy/`](fichiers/M05-E25/infra/politiques/trivy/)) :

```rego
# METADATA
# title: Ressource expérimentale proxmox_vm interdite
# custom:
#   id: MS-PVE-001
#   severity: HIGH
#   input:
#     selector:
#     - type: terraform-raw
package user.medisphere.pve001

import rego.v1

deny contains res if {
	some m in input.modules
	some b in m.blocks
	b.kind == "resource"
	b.type == "proxmox_vm"
	res := result.new(sprintf("%s utilise la ressource expérimentale proxmox_vm", [b.__defsec_metadata.resource]), b)
}
```

L'entrée `terraform-raw` (option `--raw-config-scanners terraform`) expose `input.modules[].blocks[]` avec `kind` (`resource`, `provider`, `module`…), `type`, `name`, `attributes.<nom>.value`. La seconde règle refuse `insecure = true` sur le bloc `provider "proxmox"` : volontairement redondante avec `CKV2_MS_1` (deux outils, deux équipes de mainteneurs : si l'un se trompe, l'autre voit).

Les cas de test sont dans `politiques/tests/<cas>/main.tf.cas` + `ATTENDU` : l'extension `.tf.cas` les met hors de portée de `tofu fmt`, `tofu-valider.sh` et `tflint --recursive` (E20), qui échoueraient sur ces configurations volontairement fautives ; le script les copie en `main.tf` dans un dossier temporaire.

```
admin@adm01:~/src/infra$ outils/analyse-securite.sh --tests
ok   ckv2-ms-1    refusé par CKV2_MS_1
ok   ckv2-ms-2    refusé par CKV2_MS_2
ok   ckv2-ms-3    refusé par CKV2_MS_3
ok   ckv2-ms-4    refusé par CKV2_MS_4
ok   ms-pve-001   refusé par MS-PVE-001
ok   ms-pve-002   refusé par MS-PVE-002
```

Les deux modes se complètent : `--tests` prouve qu'une règle **échoue** sur un cas fautif ; l'analyse du dépôt prouve qu'elle **passe** sur le bon code. Une règle cassée qui échoue toujours (attribut mal orthographié : `agent.enable`) passe le premier test… et fait échouer le second.

*4. Exceptions.* `.trivyignore` accepte `ID exp:AAAA-MM-JJ` : passé la date, l'alerte revient (vérifié : une ligne `MS-PVE-001 exp:2026-01-01` ne masque plus rien). Checkov n'a pas d'expiration native dans `skip-check` : la justification et la date de revue vont en commentaire, et le check de l'exercice vérifie que chaque exception est commentée. Pour une exception **ponctuelle** sur une ressource, Checkov accepte aussi un commentaire en ligne dans le code (`#checkov:skip=CKV2_MS_4:raison`), plus précis qu'une exclusion globale.

*5. Le script.* [`outils/analyse-securite.sh`](fichiers/M05-E25/infra/outils/analyse-securite.sh) : refuse (code 3) un Trivy dont l'empreinte diffère de `TRIVY_EMPREINTE` (CI) ou de `TRIVY_BINAIRE_SHA256` (poste), vérifie les versions, lance Checkov (`--config-file .checkov.yaml`, rapports JUnit) puis Trivy sur chaque dossier avec `--skip-check-update` (règles **embarquées** dans le binaire vérifié) et le modèle `contrib/junit.tpl`. Branché à l'étape `pre-push` ([`pre-commit-extrait.yaml`](fichiers/M05-E25/infra/pre-commit-extrait.yaml)) : 20 à 40 s, trop long à chaque commit. Ajouter `rapports/` au `.gitignore`.

**Explications**

Un analyseur de code d'infrastructure applique des règles à une représentation du code : Checkov à un graphe des blocs, Trivy à un modèle « cloud » (ressources AWS, Azure…) **ou**, avec `terraform-raw`, aux blocs bruts. Sans règle pour ton provider, il ne voit rien : sa valeur pour une infrastructure Proxmox, c'est le **cadre** (exécution en MR, rapports, exceptions tracées) dans lequel tu écris tes conventions. Côté chaîne d'approvisionnement, `trivy config` télécharge par défaut, à chaque exécution, un paquet de règles depuis un registre OCI (`mirror.gcr.io/aquasec/trivy-checks:2` en 0.75) : du code exécuté sans revue, qui contourne l'épinglage du binaire. `--skip-check-update` l'évite au prix de règles plus anciennes (celles du binaire), ce qui est sans conséquence ici. Checkov, lui, embarque ses règles dans le paquet PyPI dont la version est fixée.

**Alternatives**
- **OPA/conftest** sur le plan JSON (module 29) : un seul langage (Rego) pour tout, et des règles sur les valeurs **résolues** (variables, modules).
- **tflint avec un jeu de règles maison** (plugin) : pour les conventions de style plutôt que de sécurité.
- **KICS** (Checkmarx) : autre analyseur libre ; son action GitHub a été compromise le 23 mars 2026, même famille d'attaque.
- Image de conteneur de Trivy épinglée par **digest** (`aquasec/trivy@sha256:…`) quand les runners auront Docker (modules 12 et 19) : même principe que l'empreinte du binaire.

**Pièges classiques**
- Installer « la dernière version » dans le job (`curl … | sh`, `trivy-action@v0`) : c'est exactement le vecteur de mars 2026.
- Laisser Trivy télécharger son paquet de règles à chaque exécution en croyant l'avoir épinglé.
- Une règle maison jamais vue échouer ; ou un cas fautif enregistré en `.tf`, qui casse les hooks de E20.
- `skip-check` sur une famille (`CKV_TF_*`) ou une exception sans date : elle devient permanente par oubli.
- Analyser seulement la racine : les VMs sont dans le module `vm-debian`, que Checkov ne voit que s'il télécharge les modules (`download-external-modules`).

**En production chez MédiSphère**
Les mêmes règles maison s'appliquent à `plateforme/tofu-modules` (le job `securite` y est ajouté) ; le rapport JUnit apparaît dans chaque MR ; une alerte bloque la fusion. La veille de sécurité (avis GitHub, CVE) des outils de la chaîne est l'affaire de Sophie : une alerte sur Trivy, Checkov, Terragrunt ou OpenTofu déclenche une revue de `outils/versions-outils.env` dans la journée.

---

### M05-E26 — Pipeline IaC : plan en MR, apply protégé

**Solution**

Fichiers : [`fichiers/M05-E26/infra/.gitlab-ci.yml`](fichiers/M05-E26/infra/.gitlab-ci.yml), [`outils/ci-preparer.sh`](fichiers/M05-E26/infra/outils/ci-preparer.sh) ; pour `runner01`, dans `plateforme/ansible` : [`tasks/opentofu.yml`](fichiers/M05-E26/ansible/roles/gitlab_runner/tasks/opentofu.yml), [`tasks/outils_iac.yml`](fichiers/M05-E26/ansible/roles/gitlab_runner/tasks/outils_iac.yml), extraits pour [`defaults/main.yml`](fichiers/M05-E26/ansible/roles/gitlab_runner/defaults/main-extrait-M05.yml) et [`tasks/main.yml`](fichiers/M05-E26/ansible/roles/gitlab_runner/tasks/main-extrait-M05.yml). L'état final du palier (avec E27 à E29) est dans [`fichiers/M05-E29/infra/.gitlab-ci.yml`](fichiers/M05-E29/infra/.gitlab-ci.yml).

*1. Outils de `runner01`.* Le rôle `gitlab_runner` (M04-E16) a déjà la mécanique « binaire de release, empreinte vérifiée, dossier par version, lien dans `/usr/local/bin` » (`gitlab_runner_outils`) : Terragrunt, tflint, terraform-docs et Trivy y sont **quatre entrées de plus**. OpenTofu suit la méthode de E02 (clés vérifiées par empreinte, dépôt limité à ces clés, série épinglée), Checkov celle de pre-commit (`uv tool` dans `/opt/uv-tools`), `unzip` (pour l'archive de tflint) et `awscli` (paquet Debian 13, AWS CLI v2, utile en E29) viennent d'APT. Après l'application (`--limit runner01`) :

```
admin@adm01:~$ ssh runner01 'sudo -u gitlab-runner -H bash -lc "tofu version | head -1; terragrunt --version; trivy --version | head -1; checkov --version"'
OpenTofu v1.13.1
terragrunt version v1.1.6
Version: 0.75.0
3.3.26
```

*2. Variables et protections.* Dans *Settings → CI/CD → Variables* de `plateforme/infra`, toutes **protégées** : `PROXMOX_VE_ENDPOINT` ; `PROXMOX_VE_API_TOKEN` (*Masked and hidden*, « Expand variable reference » décoché, car le jeton contient `!` et `=`) ; `AWS_ACCESS_KEY_ID` ; `AWS_SECRET_ACCESS_KEY` (masquée et cachée). Branches protégées `main` (personne ne pousse, Maintainers fusionnent) et `conf/*` (Developers et Maintainers poussent) ; *Allow merge request pipelines to access protected variables and runners* activé. Qui lit désormais le jeton `wb-tofu` : tout compte qui peut pousser sur `conf/*` (il fait exécuter son code par `runner01` avec les variables), tout Maintainer, et quiconque a un accès `root` à `runner01`. C'est le vrai périmètre à surveiller.

*3. Le pipeline.* Structure (voir le fichier, commenté) :

| Étape | Jobs | Quand | Secrets |
|---|---|---|---|
| lint | `pre-commit` (fmt, validate, tflint, terraform-docs), `commitlint`, `gitleaks` | MR, branches | non (jeton de job pour les modules) |
| test | `securite` | MR, branches | non |
| plan | `plan:socle`, `plan:lab-m05`, `plan:recette-m05` ; `secrets-indisponibles` | MR et `main` | oui |
| apply | `apply:socle`… (manuels) | `main` seulement | oui |

Le cœur d'un job `plan` :

```sh
tofu init -input=false -lockfile=readonly
rc=0
tofu plan -input=false -lock-timeout=10m -detailed-exitcode -out=plan.tfplan || rc=$?
[ "$rc" -eq 1 ] && exit 1          # erreur
echo "$rc" > plan.code             # 0 = aucun changement, 2 = changements
tofu show -no-color plan.tfplan > plan.txt
tofu show -json plan.tfplan | jq -c '[.resource_changes[]?.change.actions] | flatten
  | {create: map(select(. == "create")) | length, update: …, delete: …}' > rapport-terraform.json
```

`-detailed-exitcode` sort en **2** quand il y a des changements : sans `|| rc=$?`, le shell du job s'arrête et le job échoue sur un plan normal. `-lockfile=readonly` : la CI ne réécrit jamais le lock (un provider absent du lock est une erreur, pas une mise à jour silencieuse). Le rapport `terraform` alimente le widget de la MR (« 1 to change »). Le job `apply` récupère `plan.tfplan` par `needs: ["plan:socle"]`, refait `tofu init` (le dossier `.terraform/` n'est pas un artefact) et applique **ce fichier** ; puis un second `tofu plan -detailed-exitcode` doit sortir en 0.

*4. La preuve.* Une MR `conf/s3-01-description` qui change la `description` de `s3-01` : `plan:socle` affiche `~ description = "…" -> "…"` et `Plan: 0 to add, 1 to change, 0 to destroy`, le widget l'annonce ; après fusion, `apply:socle` lancé à la main applique, le contrôle de convergence affiche « No changes ». Plan périmé : deux pipelines de `main` (P1 puis P2), apply de P2, puis apply de P1 :

```
Error: Saved plan is stale

The given plan file can no longer be applied because the state was changed by
another operation after the plan was created.
```

OpenTofu compare le `serial` et le `lineage` de l'état enregistrés dans le plan à l'état courant. Avec *Prevent outdated deployment jobs* (*Settings → CI/CD → General pipelines*), GitLab refuse même de lancer le job d'un pipeline plus ancien que le dernier déploiement de l'environnement. ⚠️ À vérifier sur ta version : le libellé exact de l'option et son effet sur un job manuel jamais lancé.

*5. Les artefacts.* Un `plan.tfplan` est une archive qui contient le plan, **une copie de l'état** et la configuration, avec les **valeurs des variables** (`tofu show -json` les affiche). Avec `access: developer`, `lucas.martin` (Reporter) reçoit un refus ; toi, tu télécharges. Pourquoi pas `maintainer` : les relecteurs (Developers) doivent lire `plan.txt` ; et un Developer peut déjà pousser sur `conf/*`, donc faire exécuter du code avec les secrets : l'accès aux artefacts ne lui donne rien de plus. 30 jours : le temps d'une revue a posteriori ; au-delà, l'artefact n'est qu'une copie de plus de l'état. Depuis E27, le plan est chiffré. ⚠️ À vérifier sur ta version : que le rapport `terraform` reste affiché dans la MR quand `artifacts:access` n'est pas `all`.

*6. `CONTRIBUTING.md`* : chemin normal (branche `conf/<sujet>` → MR → plans relus → fusion → `apply:` lancé par un Maintainer → contrôle vert) ; permis depuis `adm01` : `plan`, `validate`, lecture d'état, environnements Terragrunt de test ; interdit : `apply` sur `socle/`, `envs/lab-m05`, `envs/recette-m05` hors bris de glace (procédure de l'ADR-0040, transposée : ticket INC, plan relu, journal, MR de régularisation).

**Explications**

Appliquer un plan enregistré garantit que **ce qui s'exécute est ce qui a été affiché** dans le journal du job `plan` du même pipeline. Sans fichier de plan, `tofu apply -auto-approve` recalcule un plan au moment de l'apply : si la réalité ou l'état ont changé entre-temps, il applique quelque chose que personne n'a lu. La contrepartie est le plan périmé : c'est une **bonne** erreur. GitLab CE n'a pas d'environnements protégés : la protection de `apply:` repose sur la branche protégée (un job manuel de `main` ne se lance que par qui peut fusionner dans `main`), les variables protégées (absentes ailleurs) et `resource_group` (un apply à la fois par état, tous pipelines confondus, en plus du verrou S3).

**Alternatives**
- **Composant CI/CD OpenTofu de GitLab** (`gitlab-org/components/opentofu`) : jobs prêts à l'emploi (fmt, validate, plan, apply, rapport) ; conçu pour des exécuteurs à conteneurs, donc pour le module 19.
- **Atlantis** : plan/apply pilotés par commentaires de MR, verrou par MR ; un service de plus à exploiter, avec les secrets.
- **État géré par GitLab** (backend `http`) : supprime S3 pour l'état, au prix du couplage état-forge (ADR-0050).
- Commenter le plan dans la MR (API, jeton de projet) en plus du widget : plus lisible, un secret de plus.

**Pièges classiques**
- `tofu plan -detailed-exitcode` non capturé : tout plan avec changements fait échouer le job.
- `apply` qui recalcule un plan (`-auto-approve`) au lieu d'appliquer l'artefact.
- Artefacts `plan.tfplan` publics (projet interne ou public) : copie de l'état offerte à tous.
- Oublier `tofu init` dans le job `apply`, ou laisser le lock se réécrire en CI.
- Jobs de plan lancés sur une MR de branche non protégée : ils « passent » sans rien vérifier (variables vides). D'où `secrets-indisponibles`.
- `set -x` dans un job : TF_ENCRYPTION, jetons… dans le journal.

**En production chez MédiSphère**
Un runner **dédié** à `plateforme/infra` (étiquette `iac`, exécuteur isolé au module 19), seul à porter les secrets d'infrastructure ; un jeton Proxmox par état (socle, environnements) ; approbation obligatoire des MR (fonction payante dans GitLab : à défaut, règle d'équipe vérifiée par un job qui lit les approbations par l'API) ; journal des déploiements de `lab/socle` conservé un an.

---

### M05-E27 — Secrets et chiffrement de l'état

**Solution**

Fichiers : [`socle/chiffrement.tf`](fichiers/M05-E27/infra/socle/chiffrement.tf) (définitif, identique dans `envs/lab-m05/` et `envs/recette-m05/`), [`phase1/chiffrement.tf`](fichiers/M05-E27/phase1/chiffrement.tf) (migration), [`terragrunt/live/root.hcl`](fichiers/M05-E27/infra/terragrunt/live/root.hcl) (génération), [`outils/charger-acces.sh`](fichiers/M05-E27/infra/outils/charger-acces.sh), [`outils/ci-preparer.sh`](fichiers/M05-E27/infra/outils/ci-preparer.sh), expérience [`experience/main.tf`](fichiers/M05-E27/experience/main.tf), [extrait du registre des secrets](fichiers/M05-E27/medisphere/docs/socle/registre-secrets-extrait.md).

*1. Ce que contient l'état.*

```
admin@adm01:~$ aws s3 cp s3://tofu-state/envs/dev-agenda/acces/terraform.tfstate - | jq -r '.resources[].instances[].attributes.private_key_openssh' | head -2
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAA… (contenu de la clé privée)
```

(Sortie tronquée.) L'état du socle donne à un attaquant la carte du lab : VMID, noms, adresses IP et MAC, VNets, stockages, nœud, empreintes des clés publiques, configuration cloud-init, chemins des snippets. `sensitive = true` ne change que l'**affichage** (plan, sorties) : le provider rend la valeur à OpenTofu, qui l'enregistre telle quelle dans l'état pour pouvoir la comparer au prochain plan.

*2. Où va la phrase ?* Avec la variante A de l'expérience (fournisseur de clé dont `passphrase = var.phrase_essai`) :

```
admin@adm01:~/m05/e27$ tofu show -json a.tfplan | jq -c .variables
{"phrase_essai":{"value":"phrase-de-demonstration-01"},"secret_essai":{"value":"valeur-secrete-de-demonstration"}}
```

La phrase est **dans le plan** (chiffré, certes, avec la clé qu'elle sert à dériver), et `tofu show -json` l'imprime en clair : tout JSON de plan produit en CI (rapport, analyse de sécurité du plan) la fuirait. Avec `TF_ENCRYPTION` (variante B), `phrase_essai` vaut `null` : la phrase n'est jamais une variable du module racine. On retient `TF_ENCRYPTION`. Remarque : `secret_essai`, lui, reste en clair dans le JSON du plan : un plan est un secret, chiffré ou pas.

*3. Le code.* Le bloc `encryption` **référence** `key_provider.pbkdf2.etat` sans le déclarer ; `TF_ENCRYPTION` le déclare :

```
TF_ENCRYPTION='key_provider "pbkdf2" "etat" { passphrase = "<PHRASE>" }'
```

OpenTofu fusionne les deux (la variable l'emporte en cas de conflit). Sans `TF_ENCRYPTION` : `Error: Reference to undeclared key provider` — explicite. `outils/charger-acces.sh` (à sourcer) construit la variable depuis `~/.config/workbook/tofu-chiffrement.pass` (600 exigé), `ci-preparer.sh` depuis `TOFU_PHRASE_CHIFFREMENT` ; les deux par `printf -v` et en n'acceptant que des caractères sûrs dans du HCL. Terragrunt copie `socle/chiffrement.tf` dans chaque unité (`generate "chiffrement"` avec `contents = file("${get_repo_root()}/socle/chiffrement.tf")`) : une seule source, une rotation faite dans ce fichier vaut partout.

*4. Migration.* Phase 1 (fichier [`phase1/chiffrement.tf`](fichiers/M05-E27/phase1/chiffrement.tf)) : méthode principale `aes_gcm.etat`, `fallback` vers `unencrypted.migration`. Ordre : variable `TOFU_PHRASE_CHIFFREMENT` créée **avant** la MR (sinon `ci-preparer.sh` refuse) ; MR, plans **vides** ; fusion ; `apply:socle`, `apply:lab-m05`, `apply:recette-m05` (un plan vide s'applique : l'état est réécrit, chiffré) ; pour Terragrunt, depuis `adm01` : `terragrunt run --all apply` dans `live/dev-agenda` puis `live/dev-doc`. Contrôle :

```
admin@adm01:~$ aws s3 cp s3://tofu-state/socle/terraform.tfstate - | jq -c 'keys'
["encrypted_data","encryption_version","lineage","meta","serial"]
```

Phase 2 : le fichier définitif (plus de méthode `unencrypted`, `enforced = true` sur `state` et `plan`), seconde MR, plans vides.

*5. Preuves.* (a) ci-dessus. (b) Sans phrase : `Reference to undeclared key provider` (clair). Avec une **mauvaise** phrase, le message de fond est `decryption failed for all provided methods … cipher: message authentication failed` (AES-GCM authentifie le contenu : une mauvaise clé ne produit pas un état « faux », elle échoue). Mais sur un état **local** (ton expérience), OpenTofu le présente sous le titre `Error acquiring the state lock` (il écrit une sauvegarde de l'état au moment de prendre le verrou) : trompeur, on cherche un verrou qui n'existe pas. ⚠️ À vérifier sur ta version : le titre du même message avec le backend S3. (c) `tofu show plan.tfplan` sur l'artefact d'un job, sans `TF_ENCRYPTION` : refus. (d) `tofu state pull` **déchiffre** : sa sortie est l'état en clair. Conséquence pour E29 : on sauvegarde l'objet chiffré tel quel, jamais une sortie de `state pull`.

*6. Rotation.* Voir l'extrait du registre : un **nouveau** fournisseur sous un autre nom (`etat_2027`) devient principal, l'ancien `etat` (ancienne phrase) passe en `fallback` ; on réécrit chaque état ; on retire l'ancien. Le nom compte : les métadonnées d'un état chiffré rangent le sel PBKDF2 **sous le nom du fournisseur** (`"meta": {"key_provider.pbkdf2.etat": "…"}`) ; donner la nouvelle phrase au fournisseur `etat` rendrait tous les états illisibles. Enfin `terragrunt run --all destroy` dans `live/dev-agenda`.

**Explications**

Le chiffrement d'OpenTofu est **côté client** : l'état est chiffré par `tofu` avant d'être envoyé au backend, et déchiffré après lecture. Le stockage (S3, sauvegardes, artefacts) ne voit qu'une enveloppe JSON : `serial`, `lineage`, `meta` (paramètres de dérivation de clé, pas la clé) et `encrypted_data` (AES-GCM, authentifié : une altération est détectée). PBKDF2 (600 000 itérations de SHA-512 par défaut) dérive une clé de 32 octets de la phrase et d'un sel aléatoire. Le verrou (`.tflock`) n'est pas chiffré : il ne contient que l'identité du détenteur.

**Alternatives**
- **Variable OpenTofu** pour la phrase : fonctionne, mais la phrase entre dans chaque plan enregistré (étape 2).
- **Fournisseur de clé `openbao`** (ou `aws_kms`, `gcp_kms`…) : la clé ne quitte jamais le coffre, rotation et révocation centralisées ; au module 25.
- **Chiffrement côté serveur** (SSE de SeaweedFS) : protège le disque de `s3-01`, pas une copie téléchargée par quiconque détient l'identité S3 ; complément, pas remplacement.
- **Valeurs éphémères / attributs *write-only*** (OpenTofu 1.11) : le secret n'entre pas du tout dans l'état, quand le provider le permet. ⚠️ À vérifier : `bpg/proxmox` 0.115/0.116 n'en propose pas pour les attributs que nous utilisons (au moment de la rédaction).

**Pièges classiques**
- Perdre la phrase : tout est illisible, copies comprises. Coffre de l'équipe **avant** la migration.
- Oublier `TOFU_PHRASE_CHIFFREMENT` avant de fusionner : tous les jobs de plan échouent.
- Phase 2 sans phase 1 (ou `enforced` d'emblée) : OpenTofu refuse de lire les états encore en clair.
- Renommer le fournisseur ou la méthode « pour faire propre » : états illisibles.
- Mettre la phrase dans `TF_ENCRYPTION` d'un fichier `.envrc` versionné, ou dans le journal d'un job (`set -x`, `env`).
- Croire qu'un état chiffré peut se restaurer par `tofu state push` : il refuse un fichier chiffré (E29).

**En production chez MédiSphère**
Fournisseur `openbao` (module 25) avec une clé de transit par état, rotation annuelle automatisée ; la phrase PBKDF2 actuelle reste en `fallback` le temps de la migration. Audit trimestriel : aucun objet de `tofu-state` sans `encrypted_data` (le job de sauvegarde de E29 le vérifie chaque nuit).

---

### M05-E28 — Détecter la dérive de l'infrastructure

**Solution**

Fichiers : [`outils/derive.sh`](fichiers/M05-E28/infra/outils/derive.sh), [`outils/derive-alerte.sh`](fichiers/M05-E28/infra/outils/derive-alerte.sh), jobs `derive:*` et `derive:alerte` dans le [`.gitlab-ci.yml` de fin de palier](fichiers/M05-E29/infra/.gitlab-ci.yml), section de [`docs/socle/iac.md`](fichiers/M05-E28/medisphere/docs/socle/iac-extrait-derive.md).

Conception :
- **Deux plans par configuration.** `tofu plan -refresh-only -detailed-exitcode` compare l'état à la réalité : non vide = **dérive** (quelqu'un a modifié hors d'OpenTofu). Seulement s'il est vide, le plan ordinaire compare le code à la réalité : non vide = **écart de code** (MR fusionnée, apply pas lancé). Le JSON du plan rafraîchi (`tofu show -json`) liste les ressources dérivées dans `resource_drift` ; le script n'en garde que l'adresse et les **noms** des attributs qui diffèrent (`before`/`after` contiennent des valeurs, parfois secrètes).
- **Codes** : 0 conforme, 2 dérive, 3 écart, 1 erreur (l'erreur l'emporte). En CI, `allow_failure: exit_codes: [2, 3]` : un job orange pour une dérive, rouge (pipeline en échec) pour une erreur.
- **Pas pendant un apply, pas de verrou oublié** : chaque job `derive:<configuration>` est dans le `resource_group` de son `apply:` ; les plans prennent le verrou de l'état avec `-lock-timeout=10m` (un apply lancé depuis `adm01` est attendu) et le rendent en fin normale. Pas de `-lock=false` : un plan sans verrou pourrait lire un état en cours d'écriture.
- **Preuve** : `rapports/derive-*/derive.json`, `derive.md` et `derive-junit.xml` en artefacts, 90 jours.
- **Alerte** : `derive:alerte` (après les trois jobs, `when: always`) fusionne les rapports, ouvre ou commente l'unique ticket `derive` avec un jeton de projet *Reporter*/`api` (`DERIVE_TOKEN`, protégé, masqué).

Démonstration sur `s3-01`, sans effet sur le service : la **description** (notes) de la VM, modifiée dans l'interface de Proxmox (ou `qm set 1006 --description "…"`). La nuit suivante :

```
socle              derive
envs/lab-m05       conforme
envs/recette-m05   conforme
| `socle` | derive | `module.s3_01.proxmox_virtual_environment_vm.vm` (description) |
```

Le ticket est créé. Résolution : la description n'a pas à changer → `apply:socle` du dernier pipeline de `main`, qui remet celle du code ; si elle devait changer (la mémoire montée par Nadia, dans le ticket), c'est une MR qui fait entrer la valeur dans le code, plan relu **vide** sur cette ressource (le code rejoint la réalité), puis apply. Écart de code : une MR fusionnée (par exemple une sortie de plus dans `socle/outputs.tf`) sans lancer `apply:socle` → `socle  ecart`, commentaire dans le ticket. Une nuit conforme ensuite, et le ticket est fermé par un humain avec la décision.

À la main, sur `adm01` :

```
admin@adm01:~/src/infra$ . outils/charger-acces.sh
admin@adm01:~/src/infra$ outils/derive.sh -r ~/m05/e28/rapports; echo "code $?"
socle              conforme
envs/lab-m05       conforme
envs/recette-m05   conforme
code 0
```

Planification : *Build → Pipeline schedules*, `main`, `17 2 * * *`, fuseau Europe/Paris, variable `PLANIF=derive`.

**Explications**

`-refresh-only` est le mode « que s'est-il passé dehors ? » : OpenTofu lit chaque ressource auprès du provider et compare aux attributs **enregistrés** dans l'état, sans regarder le code. Le plan ordinaire fait ce rafraîchissement **puis** compare au code : une dérive y apparaît aussi, mêlée aux changements de code. Faire les deux, dans cet ordre, sépare « on nous a touché l'infrastructure » de « on n'a pas fini notre travail » : deux réponses différentes (enquête ou apply), deux responsables différents.

**Alternatives**
- Un seul plan ordinaire avec `-detailed-exitcode` (M04-E29) : plus simple, ne distingue pas dérive et écart.
- `tofu apply -refresh-only` planifié : **accepte** la réalité dans l'état sans rien changer à l'infrastructure ; dangereux en automatique (la dérive devient la référence de l'état, le code n'en sait rien, le prochain plan la défait).
- Outils dédiés (driftctl, archivé ; services SaaS) : hors périmètre, et un plan fait le même travail pour un provider qu'ils ne connaissent pas.

**Pièges classiques**
- `-lock=false` « pour ne pas gêner » : lecture d'un état en cours d'écriture, faux positifs.
- Un rapport qui recopie `before`/`after` : des secrets dans un ticket.
- Des faux positifs permanents (attribut que Proxmox normalise : ordre des étiquettes, valeurs par défaut) : corriger le **code** (`sort()`, valeur explicite, `ignore_changes` argumenté), jamais la détection.
- Corriger une dérive à la main dans Proxmox : on remplace une dérive par une autre.
- Un ticket par nuit : on ne les lit plus. Un seul ouvert, commenté.

**En production chez MédiSphère**
Métrique « ressources en dérive » exportée vers Prometheus (module 21), alerte si une dérive dure plus de deux jours ouvrés ; les dérives et leur décision sont revues au comité des changements mensuel ; l'audit HDS reçoit l'historique des tickets `derive` et les rapports de 90 jours.

---

### M05-E29 — Sauvegarder et restaurer l'état

**Solution**

Fichiers : [`outils/sauvegarder-etats.sh`](fichiers/M05-E29/infra/outils/sauvegarder-etats.sh), [`outils/restaurer-etat.sh`](fichiers/M05-E29/infra/outils/restaurer-etat.sh), job `sauvegarde-etats` du [`.gitlab-ci.yml`](fichiers/M05-E29/infra/.gitlab-ci.yml), section de [`docs/socle/iac.md`](fichiers/M05-E29/medisphere/docs/socle/iac-extrait-sauvegarde.md).

*1. Cartographie.* Voir le tableau de l'extrait de `iac.md`. Le scénario sans parade technique : **la phrase de chiffrement perdue** (E27) — toutes les copies, versions et sauvegardes comprises, sont illisibles. Parade : la phrase dans le coffre de l'équipe (deux détenteurs), relue à chaque rotation ; en dernier recours, ré-importer toute l'infrastructure (E16) dans des états neufs.

*2-3. Copie externe.* Le script liste les clés `*.tfstate` (hors `_restauration/`, `_essais/`, verrous), télécharge chaque objet **tel quel** avec son `VersionId`, vérifie qu'il est chiffré (`encrypted_data` présent, pas de `resources`), et écrit un manifeste (`serial`, `lineage`, SHA-256) et un `SHA256SUMS`. Il ne déchiffre rien : il n'a pas besoin de la phrase, et la copie peut vivre dans un artefact. Un état en clair ou illisible fait échouer le job (après copie, pour ne rien perdre). Planification `PLANIF=sauvegarde-etats`, `access: maintainer`, 90 jours.

*4. Restauration d'une version* (sur `envs/lab-m05`, jamais sur le socle en place) :

```
admin@adm01:~/src/infra$ . outils/charger-acces.sh
admin@adm01:~/src/infra$ outils/restaurer-etat.sh --lister envs/lab-m05/terraform.tfstate | head -3
2026-10-14T08:02:11+00:00  version   6731…e2c  (courante) 9214 o
2026-10-12T21:40:37+00:00  version   672f…a91   9214 o
…
admin@adm01:~/src/infra/envs/lab-m05$ tofu state list
admin@adm01:~/src/infra/envs/lab-m05$ tofu state rm 'proxmox_virtual_environment_vm.app["app01"]'
Removed proxmox_virtual_environment_vm.app["app01"]
Successfully removed 1 resource instance(s).
admin@adm01:~/src/infra/envs/lab-m05$ tofu plan
…
Plan: 1 to add, 0 to change, 0 to destroy.
```

(L'adresse dépend de ton code au palier 2 : prends-en une dans `tofu state list`.) Le plan propose de **créer** une VM qui existe : un apply échouerait (VMID déjà pris) ou, pire, sur une autre ressource, créerait un doublon. On n'applique pas, on restaure la version d'avant le `state rm` (la deuxième de la liste) :

```
admin@adm01:~/src/infra$ outils/restaurer-etat.sh --version envs/lab-m05/terraform.tfstate 672f…a91
État       : s3://tofu-state/envs/lab-m05/terraform.tfstate
Courant    : version 6731…e2c, serial 18
Restauré   : serial 17, lineage 3c1d… (--version)
Confirmer la restauration (oui/non) ? oui
Copie de l'ancienne version et journal : /home/admin/.local/state/infra-restaurations/20261014-101203
Restauré : nouvelle version 6731…f07. Lance maintenant « tofu plan » dans la configuration concernée.
admin@adm01:~/src/infra/envs/lab-m05$ tofu plan
No changes. Your infrastructure matches the configuration.
```

La restauration crée une **nouvelle** version (copie côté serveur, `copy-object --copy-source 'tofu-state/<clé>?versionId=<ID>'`) : l'historique n'est jamais réécrit, et l'état « fautif » reste lisible pour l'enquête. Le `serial` restauré (17) est plus petit que le courant (18) : `tofu state push` le refuserait (« cannot import state with serial 17 over newer state with serial 18 ») — c'est une protection normale de `push`, et une raison de plus de restaurer côté S3, avec vérification du `lineage` (même état) et sans verrou présent.

*5. Restauration d'une copie externe* (le socle, sous une autre clé) :

```
admin@adm01:~$ mkdir -p ~/m05/e29 && cd ~/m05/e29
admin@adm01:~/m05/e29$ # télécharger l'artefact du dernier job sauvegarde-etats (Maintainer), puis :
admin@adm01:~/m05/e29$ unzip -q artifacts.zip && cd etats-* && sha256sum -c SHA256SUMS
admin@adm01:~/m05/e29/etats-…$ ~/src/infra/outils/restaurer-etat.sh --fichier _restauration/socle/terraform.tfstate socle/terraform.tfstate --oui
admin@adm01:~/m05/e29$ cp -r ~/src/infra/socle socle-test && cd socle-test && rm -rf .terraform
admin@adm01:~/m05/e29/socle-test$ tofu init -reconfigure -backend-config=key=_restauration/socle/terraform.tfstate
admin@adm01:~/m05/e29/socle-test$ tofu plan -lock=false
No changes. Your infrastructure matches the configuration.
```

`-backend-config=key=…` remplace la clé du bloc `backend` de la copie ; `-lock=false` est acceptable pour un **plan** sur une clé que personne d'autre n'utilise. Mesure du temps, du téléchargement au plan vide (typiquement 5 à 10 minutes, dont l'init) ; puis ménage :

```
admin@adm01:~$ aws s3 rm s3://tofu-state/_restauration/ --recursive
admin@adm01:~$ shred -u ~/m05/e29/etats-*/*/*.tfstate 2>/dev/null; rm -rf ~/m05/e29
```

(Les objets sous `_restauration/` gardent des versions et des marqueurs dans le compartiment versionné : ils sont chiffrés, ce n'est pas une fuite, mais un `list-object-versions` les montre.)

**Explications**

Trois niveaux, trois rayons : la **version** couvre l'erreur logique (mauvaise écriture, suppression) en quelques minutes, sans perte ; la **sauvegarde de la VM** couvre la perte du stockage, avec une journée de perte possible et une restauration lourde ; la **copie externe** couvre la perte de `s3-01` **et** de sa sauvegarde, et sert d'essai de restauration quotidien implicite (si le job réussit, chaque état est lisible, chiffré et cohérent). Un état chiffré garde `serial` et `lineage` en clair : on peut vérifier une sauvegarde (même état, plus ou moins récent) sans la phrase.

**Alternatives**
- **Réplication de compartiment** vers un second stockage S3 (sur PAR2, module F5) : RPO quasi nul ; un second service à exploiter.
- **`proxmox-backup-client`** pour pousser les états vers PBS (comme la sauvegarde applicative de GitLab, M01) : un flux de plus (`runner01` → `pbs01`:8007) et un jeton PBS de plus.
- **Verrouillage d'objets (Object Lock)** en mode conformité sur les versions : empêche même un administrateur S3 de supprimer l'historique. ⚠️ À vérifier : support et maturité dans ta version de SeaweedFS.

**Pièges classiques**
- Sauvegarder par `tofu state pull` : copie en clair.
- Restaurer par `tofu state push -force` : écrase sans vérifier le lineage, et refuse de toute façon un fichier chiffré.
- S'entraîner sur l'objet du socle en place.
- Restaurer pendant qu'un verrou existe (une opération est peut-être en cours).
- Appliquer juste après une restauration, sans lire le plan.
- Oublier `_restauration/` ou les copies téléchargées dans `~/m05/e29/` (et surtout pas dans `~/src/infra`).

**En production chez MédiSphère**
Copie externe répliquée sur PAR2 (module F5), essai de restauration complet chaque trimestre (consigné dans `docs/socle/tests/`), RTO suivi comme un indicateur ; alerte si le job `sauvegarde-etats` échoue deux nuits de suite.

---

### M05-E30 — ADR : le stockage S3 du socle après l'abandon de MinIO

**Solution**

ADR exemplaire : [`ADR-0050-stockage-s3-socle.md`](fichiers/M05-E30/medisphere/docs/socle/adr/ADR-0050-stockage-s3-socle.md). Grille : [`grille-evaluation.md`](fichiers/M05-E30/grille-evaluation.md). Note ton ADR **avant** de lire l'exemple.

L'exemple garde SeaweedFS, parce que c'est la seule option qui satisfait **par test** les deux critères éliminatoires (écritures conditionnelles et versionnage), avec une licence permissive et une empreinte compatible avec le socle ; il fixe des conditions de révision observables et une stratégie de sortie en partie déjà répétée (E29). Les cellules `<…>` de son tableau sont à remplir avec **tes** essais : le corrigé ne fabrique pas de résultat qu'il n'a pas obtenu.

Faits utiles (vérifiés le 7 octobre 2026) :
- **Garage** : la documentation dit « Garage does not (yet) support object versioning » et ne mentionne pas les écritures conditionnelles dans sa matrice de compatibilité ; le journal des décisions du PLAN (3 octobre) l'a écarté pour l'absence d'écritures conditionnelles. Le versionnage manquant suffit à l'éliminer pour l'état.
- **RustFS** : version 1.0 annoncée en septembre 2026 (Apache 2.0) ; trop récente pour porter l'état du socle, à revoir.
- **Fork MinIO** `pgsty/minio` (février 2026, AGPL 3.0) : republie binaires, images et paquets ; gouvernance d'une petite équipe sans lien avec MinIO Inc.
- **Ceph RGW** : la cible du module 08 ; coût en mémoire et en compétences hors de proportion pour un état OpenTofu aujourd'hui.
- **État géré par GitLab** : disponible dans GitLab CE (backend `http`), mais l'état dépendrait de la forge (forge en panne = plus de plan ni d'apply) et ne servirait aucun autre usage S3.

Test d'un candidat : une VM jetable (2057, clone lié de l'image `current`, détruite ensuite), le binaire du candidat en mode le plus simple, un compartiment, puis le script de E12 :

```
admin@adm01:~/src/infra$ AWS_PROFILE= aws --endpoint-url http://<IP-VM-ESSAI>:<PORT> s3api create-bucket --bucket essai
admin@adm01:~/src/infra$ AWS_PROFILE= AWS_ENDPOINT_URL=http://<IP-VM-ESSAI>:<PORT> outils/s3-tester-ecriture-conditionnelle.sh essai
```

(`<IP-VM-ESSAI>`, `<PORT>` : adresse DHCP de la VM et port S3 du candidat ; identifiants du candidat dans `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` le temps de l'essai. ⚠️ À vérifier : le script de E12 exige `AWS_PROFILE` ; adapte-le pour accepter `AWS_ENDPOINT_URL`, reconnu par la CLI v2.)

**Explications**

L'abandon de MinIO illustre un risque de gouvernance, pas de technique : un projet libre porté par **une** entreprise peut changer de licence, retirer des fonctions de l'édition libre ou cesser de publier. Les critères qui le mesurent sont observables : qui détient le droit d'auteur (CLA), combien de mainteneurs actifs, qui finance, quel délai de correction des failles. La stratégie de sortie est la vraie assurance : un état OpenTofu est un objet portable, c'est l'adresse du backend et les identités qui coûtent à changer.

**Alternatives**
Voir le tableau de l'ADR et la section « Décisions également valables » de la grille.

**Pièges classiques**
- Recopier un comparatif en ligne (souvent écrit pour un usage différent, ou daté).
- Écarter un candidat sur une fonction **supposée** absente, ou le retenir sur une fonction supposée présente.
- Oublier le versionnage (sans lui, pas de retour arrière d'un état écrasé).
- Une stratégie de sortie « on migrera » sans procédure ni durée.

**En production chez MédiSphère**
La veille des composants du socle (SeaweedFS, OpenTofu, provider, Terragrunt…) a une ligne au calendrier mensuel de l'équipe ; chaque ADR de choix de composant porte ses conditions de révision, et elles sont relues lors de la revue annuelle de l'architecture.

---

### M05-E31 — Mettre à jour les providers sans surprise

**Solution**

Fichiers : [`socle/versions.tf`](fichiers/M05-E31/infra/socle/versions.tf) (même changement dans `envs/lab-m05/`, `envs/recette-m05/`, `terragrunt/composants/vms/`), procédure dans [`docs/socle/iac.md`](fichiers/M05-E31/medisphere/docs/socle/iac-extrait-providers.md).

*1. Lecture.* Le journal de la 0.116.0 (6 octobre 2026) contient des fonctions (`notification_mode` des tâches de sauvegarde, migration de conteneur LXC, lien vers la documentation dans les erreurs SSH) et des corrections : rafraîchissement d'état des fichiers sur d'autres nœuds, diagnostics des jetons, rejet d'une interface `initialization` en collision avec un disque, et **« vm: refresh smbios from Proxmox for cloned VMs »**. C'est celle qui inquiète : toutes nos VMs sont des clones ; si le provider lit désormais le bloc SMBIOS que Proxmox a posé au clonage, un plan pourrait montrer un changement sur `smbios` alors que personne n'a rien modifié. Les autres ne touchent pas nos ressources, ou ne changent rien à un plan.

*2. Contraintes.* `version = "~> 0.116.0"` dans chaque configuration racine et dans le composant `vms`. Le module `vm-debian` déclare `>= 0.115.0, < 1.0.0` : il admet 0.116, on n'y touche pas (c'est la configuration racine qui épingle).

*3. Locks.*

```
admin@adm01:~/src/infra/socle$ tofu init -upgrade
- Installing bpg/proxmox v0.116.0...
- Installed bpg/proxmox v0.116.0 (signed, key ID …)
admin@adm01:~/src/infra/socle$ tofu providers lock -platform=linux_amd64
admin@adm01:~/src/infra/socle$ git diff --stat .terraform.lock.hcl
```

Au téléchargement, OpenTofu vérifie la signature du paquet (clé publiée par le registre pour ce provider) et compare son empreinte au lock ; le lock contient des empreintes `zh:` (archives publiées, toutes plateformes) et `h1:` (contenu du paquet). Une plateforme absente du lock : `tofu init` sur `runner01` échouerait en `-lockfile=readonly` (le paquet téléchargé ne correspond à aucune empreinte enregistrée dans le lock), ou, sans `readonly`, ajouterait silencieusement une empreinte non relue. D'où `-platform=linux_amd64` explicite.

*4. Plans.* Partout, dans la MR (jobs `plan:`) et sur `adm01` (`terragrunt run --all plan` s'il reste des unités). Si un plan montre `~ smbios { … }` sur des VMs clonées, c'est la correction annoncée : le provider lit maintenant la valeur réelle ; décider entre l'accepter (l'apply écrit dans Proxmox la même valeur qu'il a lue : sans effet), ou l'ignorer explicitement. Si les plans sont vides, c'est que nos VMs n'ont pas de bloc `smbios` dans le code et que la valeur lue ne produit pas d'écart : le noter dans la MR. ⚠️ À vérifier sur ta version : l'effet exact de cette correction sur des clones de l'image dorée, non observé en conditions réelles pour ce corrigé.

*5. Retour arrière.* Avant tout apply : revert de la MR. Après l'apply : l'état contient la **version de schéma** de chaque ressource écrite par 0.116 ; un 0.115 peut refuser de les lire. Retour = revert **et** restauration, pour chaque état, de la version notée dans la MR (`outils/restaurer-etat.sh --version`, E29), puis plans vides.

*6.* Fusion, `apply:` de chaque configuration (plans vides : l'état est réécrit avec le nouveau provider), procédure dans `iac.md`.

**Explications**

Trois objets différents : la **contrainte** (ce que le code accepte), le **lock** (ce que l'équipe a choisi et vérifié, au paquet près), et l'**état** (écrit par une version donnée, dans son schéma). `tofu init` sans `-upgrade` respecte le lock même si une version plus récente satisfait la contrainte : c'est ce qui rend les plans reproductibles entre `adm01` et `runner01`. `-upgrade` est l'acte de décision, fait dans une MR.

**Alternatives**
- **Renovate** (module 13) : ouvre la MR de montée de version et met à jour les locks ; la relecture des journaux reste humaine.
- Rester épinglé longtemps sur une version : moins de travail mensuel, mais une montée de plusieurs versions mineures d'un coup en urgence, au pire moment.
- Un environnement de test qui reçoit la nouvelle version une semaine avant le socle (avec Terragrunt, une unité par environnement le permet).

**Pièges classiques**
- `tofu init -upgrade` lancé « pour réparer » une erreur sans rapport : nouvelle version de provider glissée sans relecture.
- Lock régénéré sur un autre système (Mac, Windows) sans `linux_amd64` : échec en CI (c'est une variante de la panne de M05-E41).
- Accepter un plan qui « change un peu » une VM du socle sans comprendre l'attribut.
- Revenir en arrière par le code seul, après un apply.

**En production chez MédiSphère**
Montée mensuelle, une configuration de test d'abord, le socle une semaine plus tard ; tableau des versions de chaque outil (OpenTofu, providers, Terragrunt, analyseurs) dans `docs/socle/iac.md`, avec la date de la dernière revue.

---

### M05-E32 — Questions de production : état, équipes et rayon d'impact

**1.** Critères : **rayon d'impact** (ce qu'un apply raté peut détruire), **fréquence** de changement (une configuration qui change chaque jour ne doit pas embarquer le socle qui change chaque mois), **droits** (qui peut appliquer quoi ; un état = un jeu d'identifiants), **durée du plan** (le rafraîchissement lit chaque ressource : un état de 500 ressources prend des minutes), **dépendances** (ce qui se lit entre états par des sorties). Découpage proposé : `socle` (VMs permanentes, rarement modifié, Maintainers seuls), un état par environnement d'équipe (`envs/<équipe>-<environnement>`), et, plus tard, des états par composant transverse (réseau SDN, DNS NetBox au module 06) dont les autres lisent les sorties. Ni un état unique (tout le monde bloqué par un verrou, une erreur touche tout), ni un état par ressource (dépendances ingérables).

**2.** `terraform_remote_state` lit **tout** l'objet d'état distant (il faut les droits de lecture S3 et la phrase de chiffrement), pour n'exposer que ses **sorties** : un lecteur a, en pratique, accès à tout l'état (secrets compris). `dependency` de Terragrunt fait un `tofu output` dans l'unité : mêmes droits nécessaires, mais ordonné. Une **source de données du provider** (lire la VM 1006 dans Proxmox) ne demande que des droits de lecture Proxmox, ne dépend pas de l'état d'une autre équipe, mais couple au provider et à la réalité (pas à l'intention). Une valeur publiée ailleurs (**NetBox**, module 06, ou un simple fichier versionné) découple totalement, au prix d'une synchronisation. Pour une équipe applicative : NetBox (ou la source de données Proxmox), jamais l'accès à l'état du socle.

**3. QCM — réponse b.** Entre le plan relu en MR et le plan de `main` : une autre MR a pu être fusionnée (le code n'est plus le même que celui relu), la réalité a pu changer (dérive), un module référencé par une étiquette a pu être déplacé (si les étiquettes n'étaient pas protégées) ou une source de données (l'image `current`) a pu changer de valeur. a) faux : le plan dépend aussi de l'état, de la réalité et des sources de données ; c) GitLab ne modifie pas le code ; d) le provider est fixé par le lock, il n'est qu'une des causes possibles. D'où la règle : le Maintainer relit le plan **de `main`** avant de lancer `apply:`.

**4.** `tofu apply plan.tfplan` garantit que les actions exécutées sont **exactement** celles du plan affiché, et refuse si l'état a changé depuis (plan périmé). Il ne garantit **pas** que ce plan a été relu (c'est une question d'organisation), ni que la réalité n'a pas changé entre le plan et l'apply pour des attributs que le plan ne touche pas, ni que les valeurs « known after apply » seront celles qu'on imagine.

**5.** Légitimes : réparer un état ou dépanner une ressource isolée **en incident**, quand le reste de la configuration ne peut pas être planifié (une ressource d'un provider en panne, par exemple). OpenTofu affiche un avertissement : le résultat ne reflète pas toute la configuration, l'état peut rester incohérent avec le code. Un pipeline n'en a jamais besoin : si un plan complet est impossible ou trop risqué, c'est que les états sont mal découpés (question 1).

**6. QCM — réponse b.** OpenTofu n'est pas transactionnel : il écrit l'état au fil des ressources terminées. Tué en cours de route : le verrou peut rester (RB-050), une VM peut exister dans Proxmox sans être dans l'état (création lancée, pas enregistrée) ou y figurer marquée *tainted* (création commencée, pas finie), et l'état reflète tout ce qui s'est terminé avant. a) faux, aucun retour arrière automatique ; c) l'état est en général lisible (l'écriture d'un objet S3 est atomique) ; d) sans rapport.

**7.** Une identité Proxmox par état : `wb-tofu-socle` (droits sur les seules VMs 1000-1099), `wb-tofu-envs` (2000-2999). Mais Proxmox ne sait pas restreindre par **plage de VMID** : les ACL portent sur des chemins (`/vms/<id>`, `/pool/<pool>`). Avec le pool unique `lab` (ADR-0030), un jeton d'environnement compromis peut détruire le socle. La vraie séparation demande des pools distincts (`socle`, `envs`), décision reportée au bloc B par le PLAN. Côté S3 : une identité par préfixe (`tofu-state/socle/*`, `tofu-state/envs/*`), ce que SeaweedFS sait faire. ⚠️ À vérifier : la syntaxe des actions par préfixe dans `s3.json` de ta version.

**8.** Une analyse du **plan** voit les valeurs **résolues** : variables, sorties de modules, valeurs par défaut du provider, résultats de sources de données (l'image réellement clonée), et les **actions** (une destruction, un remplacement) : on peut écrire « aucune VM du socle ne doit être remplacée ». Ni l'une ni l'autre ne voit ce qui est fait **hors** d'OpenTofu (dérive), ni ce que fait la VM une fois démarrée (configuration Ansible, failles de l'image).

**9. QCM — réponse b.** Un bloc `removed` (avec `lifecycle { destroy = false }`) retire la ressource de l'état d'origine **sans la détruire** ; un bloc `import` l'ajoute à l'état d'arrivée ; chacun relu sur son plan (« 1 to forget » puis « 1 to import »), dans cet ordre (sinon les deux états la gèrent un temps). a) manipule des états à la main ; c) détruit une VM pour rien ; d) édition à la main, interdite.

**10.** Un runner `shell` partagé exécute le code de **tous** les projets avec le même compte : un job d'un autre projet peut lire les fichiers laissés par un job d'infra (plans, `.terraform/`), le cache des providers, ou l'environnement d'un processus en cours. Mesures : runner **dédié** à `plateforme/infra` (étiquette propre, verrouillé sur le projet) ; nettoyage systématique (`after_script`, `GIT_CLEAN_FLAGS`) ; exécuteur à conteneurs éphémères au module 19 (chaque job dans un environnement neuf).

**11.** État GitLab : + rien à exploiter, + droits de la forge ; − dépendance forte à la forge, − seul usage couvert. Atlantis : + plan/apply par commentaires, verrou par MR ; − un service de plus, qui détient tous les secrets, − modèle différent des autres pipelines. Pipeline maison : + même outil que le reste (GitLab CI), contrôle total ; − à maintenir, − fonctions payantes absentes (environnements protégés, approbations).

**12.** (a) **Taux de détections conformes** (E28) : < 90 % sur le mois → revue ; (b) **délai de résolution d'une dérive** (ouverture → fermeture du ticket `derive`) : > 2 jours ouvrés ; (c) **délai fusion → apply** (MR fusionnées non appliquées, écarts de E28) : > 2 jours ; (d) **taux d'échec des jobs `apply:`** : > 10 % ; en complément, l'âge des providers (versions de retard) et le résultat du job `sauvegarde-etats` (aucun échec toléré). Sources : API GitLab (tickets, jobs, déploiements), rapports de dérive.

**Grille d'auto-évaluation** : 1 point par question correctement argumentée (QCM : bonne réponse **et** réfutation des autres). 10 ou plus : maîtrisé ; 7 à 9 : relis E26 (plan enregistré) et E16-E17 (import, `removed`) ; moins de 7 : reprends le palier 3 dans l'ordre.

---

### M05-E33 — Runbook : verrou d'état bloqué

**Solution**

Runbook exemplaire : [`RB-050-verrou-etat-bloque.md`](fichiers/M05-E33/medisphere/docs/socle/runbooks/RB-050-verrou-etat-bloque.md).

*1. Le verrou orphelin.*

```
admin@adm01:~/src/infra/envs/lab-m05$ . ../../outils/charger-acces.sh
admin@adm01:~/src/infra/envs/lab-m05$ tofu plan & sleep 3; kill -9 %1
admin@adm01:~/src/infra/envs/lab-m05$ tofu plan
╷
│ Error: Error acquiring the state lock
│
│ Error message: operation error S3: PutObject, https response error StatusCode: 412, … api error
│ PreconditionFailed: At least one of the pre-conditions you specified did not hold
│ Lock Info:
│   ID:        d5472f42-a279-0199-7b3a-8ed2364fd62e
│   Path:      tofu-state/envs/lab-m05/terraform.tfstate
│   Operation: OperationTypePlan
│   Who:       admin@adm01
│   Version:   1.13.1
│   Created:   2026-10-14 09:12:03.79 +0000 UTC
…
admin@adm01:~/src/infra/envs/lab-m05$ aws s3api get-object --bucket tofu-state --key envs/lab-m05/terraform.tfstate.tflock /tmp/verrou.json >/dev/null && jq . /tmp/verrou.json
admin@adm01:~/src/infra/envs/lab-m05$ pgrep -af tofu || echo aucun processus
admin@adm01:~/src/infra/envs/lab-m05$ tofu force-unlock d5472f42-a279-0199-7b3a-8ed2364fd62e
Do you really want to force-unlock?
  …
  Enter a value: yes
OpenTofu state has been successfully unlocked!
```

(Si le `kill` arrive avant la prise du verrou, recommence avec un délai plus long.) Avec `Ctrl+C`, `tofu` reçoit SIGINT, interrompt proprement et **rend** le verrou : pas d'orphelin. Un job GitLab annulé reçoit un signal puis, après un délai, est tué : selon le moment, verrou rendu ou orphelin.

*2. Les autres cas.* Job `apply:socle` en cours : `Who: gitlab-runner@runner01`, job « running » dans GitLab, processus `tofu` sur `runner01` → vivant, attendre. Job annulé : plus de job en cours, pas de processus → orphelin, mais `OperationTypeApply` : plan à lire ligne à ligne (état partiel possible). `tmux` oublié sur `adm01` : `Who: admin@adm01`, `pgrep` trouve le processus → vivant, prévenir la personne. `runner01` redémarré : plus de processus, job en échec « runner system failure » → orphelin.

*3. RB-050* : voir le fichier. Ses choix : lecture seule jusqu'à la décision, trois conditions cumulatives pour lever, levée par `force-unlock` (qui vérifie l'ID) et jamais par suppression de l'objet, vérification par un plan lu ligne à ligne quand l'opération était un apply, et la liste des interdits avec leur raison.

**Explications**

Le verrou S3 natif est un objet créé par écriture **conditionnelle** : le stockage refuse (412) d'écrire `<clé>.tflock` s'il existe déjà, et c'est cette atomicité côté serveur qui garantit l'exclusion. OpenTofu le supprime en fin d'opération ; s'il meurt avant, l'objet reste. `force-unlock` lit le verrou, compare son ID à celui fourni, et ne supprime que s'ils correspondent : il ne peut pas lever par erreur un verrou posé **entre-temps** par une autre opération (une suppression manuelle, si).

**Alternatives**
- `-lock-timeout=10m` dans les jobs (déjà fait) : la plupart des « verrous bloqués » sont des opérations qui finissent.
- Un script d'aide (« Pour aller plus loin ») qui croise le verrou avec les jobs en cours par l'API de GitLab : moins d'erreurs à 3 h du matin.

**Pièges classiques**
- Lever un verrou parce qu'il est « vieux ».
- `-lock=false` pour « passer quand même ».
- Annuler un job `apply:` pour libérer le verrou : c'est ce qui fabrique l'orphelin.
- Relancer l'ancien pipeline après la levée.

**En production chez MédiSphère**
RB-050 est exercé au moins une fois par semestre lors d'une astreinte d'entraînement (pannes du palier 4, M05-E36) ; chaque levée de verrou est tracée dans un ticket INC ; deux orphelins du même type en un mois déclenchent un post-mortem.

---

### M05-E34 — Un environnement complet en temps limité

**Solution** — environnement de référence (réalisable en 1 h 30 à 2 h avec la structure de E24)

Fichiers : [`live/preprod-agenda/`](fichiers/M05-E34/infra/terragrunt/live/preprod-agenda/) (`env.hcl`, unités `acces` et `vms` **identiques** à celles de `dev-agenda`), composant `vms` étendu ([`variables.tf`](fichiers/M05-E34/infra/terragrunt/composants/vms/variables.tf), [`main.tf`](fichiers/M05-E34/infra/terragrunt/composants/vms/main.tf)).

Correspondance exigences → code → preuve :

| Exigence | Dans le code | Preuve |
|---|---|---|
| X1 | `live/preprod-agenda/` ; unités copiées de `dev-agenda` | `diff` des `terragrunt.hcl` vide |
| X2 | `env.hcl` : 2057, 2058, 2059, ressources | `qm config` (`cores`, `memory`) |
| X3 | `disques_donnees = [{ taille_go = 10, datastore = "local-nvme", format = "raw" }]` pour `pp-bdd` | `qm config 2059` : `scsi1: local-nvme:…,size=10G` |
| X4 | `etiquettes` par VM, concaténées à l'environnement | étiquettes dans Proxmox |
| X5 | attributs `optional(…, [])` dans `var.vms` | plan de `dev-agenda` inchangé (si l'environnement existait encore : `terragrunt run --all plan` vide) ; `validate` des autres unités |
| X6 | unité `acces` | `ssh -o IdentitiesOnly=yes -o ControlPath=none -i … admin@<IP>` sur les trois VMs |
| X7 | sortie `vms` du composant | `terragrunt output vms` dans l'unité `vms` |
| X8 | `root.hcl` (clé déduite, `chiffrement.tf` généré) | `aws s3 cp … - \| jq keys` : `encrypted_data` |
| X9 | aucune exception | `outils/analyse-securite.sh` ; `pre-commit run --all-files` |
| X10 | MR `conf/preprod-agenda` | pipeline vert, description |
| X11 | `terragrunt run --all destroy` dans `live/preprod-agenda` | `qm list` sans 2057-2059 |

Le seul vrai travail de code est X3-X5 : étendre l'objet `vms` du composant avec deux attributs **facultatifs** (`optional(list(string), [])` et la liste d'objets des disques, avec les mêmes valeurs par défaut que le module `vm-debian`), et les transmettre au module. Avec des valeurs par défaut égales à ce que le module recevait avant (aucune étiquette en plus, aucun disque), le plan des autres environnements ne bouge pas. Le format `raw` n'est pas un caprice : LVM-thin (comme ZFS) ne stocke que du `raw` ; `qcow2` sur `local-nvme` ferait échouer la création.

Déroulé type :

| Jalon | Ce qu'on fait | Temps typique |
|---|---|---|
| T0 → T1 | Lecture, branche `conf/preprod-agenda`, copie du dossier `dev-agenda`, `env.hcl`, extension du composant, `terragrunt run --all plan` | 30 à 45 min |
| T1 → T2 | `terragrunt run --all apply`, attente des VMs, sortie `vms`, connexions SSH avec la clé de l'environnement | 20 à 30 min |
| T2 → T3 | `outils/analyse-securite.sh`, `pre-commit run --all-files`, locks, MR | 20 à 30 min |
| T3 → T4 | Pipeline de la MR, description (résumé du plan, preuves, non testé) | 15 à 20 min |

**Grille d'auto-évaluation** (à remplir après le chrono) :

| Critère | Points |
|---|---|
| Les onze exigences couvertes, chacune avec une preuve observable | /4 |
| Unités identiques aux autres environnements (rien de spécifique hors `env.hcl`) | /2 |
| Extension du composant compatible (attributs facultatifs, plan des autres environnements inchangé, validé) | /3 |
| Disque de données au bon format sur le bon stockage, seulement sur la base | /2 |
| Connexion SSH prouvée avec la **seule** clé de l'environnement (`IdentitiesOnly`, `ControlPath=none`) | /2 |
| États chiffrés vérifiés dans `tofu-state` | /1 |
| Analyse de sécurité et hooks sans exception ajoutée | /2 |
| MR décrite (plan, preuves, non testé) | /1 |
| T4 − T0 ≤ 3 h | /3 |

**Total : /20.** 16 ou plus : environnement livrable. Moins de 12 : refais l'exercice avec un autre cahier des charges (par exemple un environnement MédiDoc avec un disque de données sur `hdd-bulk` et une VM de plus) après avoir relu E24.

**Explications**

Le CHRONO mesure ce que la structure de E24 rapporte : un nouvel environnement doit coûter un `env.hcl` et une copie de dossier, pas une heure de copier-coller. Le piège est l'évolution du composant partagé : tout ajout doit être **compatible**, sinon un environnement neuf casse les autres.

**Pièges classiques**
- Modifier les `terragrunt.hcl` de l'environnement au lieu de `env.hcl` (les unités ne sont plus identiques).
- Rendre les nouveaux attributs obligatoires : `dev-agenda` ne se valide plus.
- `qcow2` sur `local-nvme`, ou disque de données sur les frontaux.
- Tester SSH avec ta clé personnelle chargée dans l'agent.
- Détruire avant de lancer la vérification ; ou détruire à la main dans Proxmox (les états mentent ensuite).

**En production chez MédiSphère**
Les environnements de préproduction sont créés par un job de pipeline à partir d'un `env.hcl` relu en MR, ont une date de fin, et leur clé d'environnement est remise par le coffre de secrets (module 25), jamais par fichier.
