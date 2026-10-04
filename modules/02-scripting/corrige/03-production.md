# Module 02 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

Fichiers complets : [`fichiers/M02-E24/`](fichiers/M02-E24/) à [`fichiers/M02-E34/`](fichiers/M02-E34/), à placer aux mêmes chemins dans `~/src/outils` (ils s'appuient sur `lib/ms-commun.sh` de M02-E10/E13 et sur le Taskfile de M02-E20). Ils ont été vérifiés avec ShellCheck 0.11 (`-x`), bats-core 1.13 contre la bibliothèque de E13, pytest, ruff, `systemd-analyze verify` et `visudo -c`.

Points non testés en conditions réelles (signale tes retours) : la publication dans le registre PyPI de GitLab 19.4 (dont `--check-url` avec un registre privé), la reprise des identifiants du magasin `uv auth` par `uv tool upgrade`, l'option d'expiration de `proxmox-backup-manager user generate-token`, et les droits PBS posés sur un namespace plutôt que sur le datastore. Ils sont marqués « ⚠️ À vérifier sur ta version ».

---

### M02-E24 — CI du projet outils : lint et tests sur `runner01`

**Solution**

*1. Outiller `runner01`* : script [`fichiers/M02-E24/installer-outils-runner01.sh`](fichiers/M02-E24/installer-outils-runner01.sh). Il reprend les versions et la provenance de l'introduction (ShellCheck par `trixie-backports`, binaires de release pour shfmt, jq et Task, archive de l'étiquette pour bats dans `/opt/bats`), refuse tout téléchargement dont l'empreinte n'est pas fournie, et ne retélécharge pas un outil déjà à la bonne version :

```
admin@adm01:~$ scp ~/src/outils/outils-ci/installer-outils-runner01.sh runner01:
admin@runner01:~$ sudo SHFMT_SHA256=<EMPREINTE> JQ_SHA256=<EMPREINTE> BATS_SHA256=<EMPREINTE> \
                       TASK_SHA256=<EMPREINTE> ./installer-outils-runner01.sh
…
shellcheck /usr/bin/shellcheck
shfmt      /usr/local/bin/shfmt
jq         /usr/local/bin/jq
bats       /usr/local/bin/bats
task       /usr/local/bin/task
uv         /usr/local/bin/uv
```

`<EMPREINTE>` : les empreintes que tu as vérifiées et notées en installant `adm01` (la même version donne le même fichier ; pour bats, compare avec celle que tu avais calculée). Pourquoi vérifier avec `gitlab-runner` : le runner `shell` lance chaque job sous ce compte, avec **son** `PATH` de shell de connexion. `admin` a des outils dans `~/.local/bin`, des alias, un `PATH` enrichi : un `command -v` réussi en `admin` ne prouve rien pour les jobs.

*2. Les jobs* : [`fichiers/M02-E24/.gitlab-ci.yml`](fichiers/M02-E24/.gitlab-ci.yml). L'essentiel :

```yaml
include:
  - project: plateforme/ci-templates
    ref: v1
    file: [templates/qualite.yml, templates/release.yml]

.outils:
  tags: [shell]
  interruptible: true

.si-bash:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes: [bin/**/*, sbin/**/*, lib/**/*, tests/bats/**/*, .shellcheckrc, .editorconfig, Taskfile.yml, .gitlab-ci.yml]
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

bats:
  extends: [.outils, .si-bash]
  stage: test
  script:
    - task test:bats
  artifacts:
    when: always
    reports:
      junit: rapports/report.xml
```

`stages` et `workflow` ne sont pas redéfinis : ceux de `qualite.yml` conviennent (pipelines de MR, pipelines de branche sans MR, pas de doublon). Réponses du journal :
- un job **absent** d'un pipeline (règle non satisfaite) ne bloque pas la fusion : « Pipelines must succeed » ne regarde que le statut du pipeline, qui ne contient pas ce job. C'est ce qui rend `rules:changes` utilisable sans casser les MR ;
- un job **en échec** fait échouer le pipeline (sauf `allow_failure`), donc bloque la fusion.

La couverture : `coverage: '/^TOTAL\s+.*\s+(\d+(?:\.\d+)?)%$/'` lit la dernière colonne de la ligne `TOTAL` que `pytest --cov … --cov-report=term-missing` (tâche `test:py`) affiche ; GitLab l'affiche dans la MR et dans la liste des jobs.

*3. Doublon* (exemple de justification) : on garde les jobs dédiés `shellcheck` et `ruff`. Ils utilisent les **mêmes binaires** que les développeurs (installés depuis la même source, mêmes versions), leurs échecs sont lisibles d'un coup d'œil dans la MR, et le surcoût est de quelques secondes. Le hook pre-commit reste la barrière locale. Le prix : deux endroits où une version peut dériver (le `rev` du hook et le binaire du runner) ; on le contrôle en revue lors de chaque montée de version. Choix inverse défendable : laisser pre-commit seul juge du formatage et de l'analyse statique, et garder en CI seulement ce que pre-commit ne fait pas (tests, construction).

*4. Isolement* : trois barrières indépendantes.
1. **Code** : les tests bats remplacent `curl`/`pve_api` (E14) et les tests pytest simulent l'API avec `responses` (E18) ; ils fabriquent un faux fichier d'accès dans un dossier temporaire.
2. **Configuration** : le projet n'a **aucune** variable CI `PVE_*` ni jeton Proxmox ; un test qui chercherait le vrai Proxmox n'aurait pas d'identité.
3. **Réseau** : un job tourne sur `runner01`, dans le VLAN INFRA ; la matrice des flux (M00) interdit INFRA → `pve01`. Cette barrière est la plus fragile : le PLAN prévoit d'ouvrir un jour `runner01` → `pve01` (IPSet `automation`) pour l'IaC. Ce jour-là, seules les deux premières restent : d'où leur importance.

*5. Preuve* : la MR au test cassé montre dans l'onglet *Tests* la suite `bats` avec le test en échec, son message (`[ "$status" -eq 0 ]' failed`) et sa sortie ; le bouton de fusion est grisé. Une MR qui ne touche que `src/medictl/` crée un pipeline avec `pre-commit`, `commitlint`, `gitleaks`, `ruff`, `pytest`, `build`, sans `shellcheck` ni `bats`.

**Explications**

Un runner `shell` est un compte Unix qui exécute les scripts des jobs dans un répertoire de travail (`/home/gitlab-runner/builds/…`) réutilisé d'un job à l'autre (stratégie Git `fetch`, nettoyage `git clean -ffdx` par défaut) : les outils doivent y être installés comme sur un serveur, de façon reproductible, et les caches (`~gitlab-runner/.cache/uv`) persistent entre jobs et entre projets. Les rapports JUnit sont des artefacts de type particulier : GitLab les analyse, les agrège par pipeline (suite = nom du job) et compare les échecs avec la branche cible dans la MR. `artifacts:when: always` est indispensable : par défaut, les artefacts d'un job en échec ne sont pas conservés, et le rapport n'existerait justement pas quand on en a besoin. Appeler le Taskfile plutôt que recopier les commandes garantit que « vert en local » et « vert en CI » veulent dire la même chose (la panne M02-E38 te montrera ce qui arrive quand ce n'est pas le cas).

**Alternatives**
- Image Docker de CI avec tous les outils figés (exécuteurs Docker, modules 12 et 19) : plus reproductible, plus isolé, mais pas encore disponible dans le bloc A.
- Installer les outils de `runner01` par Ansible (module 04) : c'est ce qui remplacera ce script.
- `rules:changes:compare_to: refs/heads/main` pour filtrer aussi les pipelines de branche ; utile si l'équipe pousse beaucoup de branches sans MR.

**Pièges classiques**
- Tester les outils en `admin` sur `runner01` et s'étonner du `command not found` dans le job.
- Oublier `when: always` : pas de rapport de tests quand un test échoue.
- `rules:changes` sans condition de pipeline de MR : sur `main`, le job se lance ou non selon le dernier push, et un job sauté passe inaperçu.
- Redéfinir `stages` ou `workflow` dans le projet en croyant compléter ceux du gabarit : on les remplace (et on peut perdre la protection contre les pipelines en double).
- Un test qui « marche » parce qu'un `~/.config/workbook/pve-api.env` existe sur la machine : en CI, il échoue, ou pire, il touche Proxmox le jour où le réseau le permet.

**En production chez MédiSphère**
Les runners sont des machines gérées par Ansible, sans état, recréées depuis une image ; les outils viennent d'images de CI signées (module 13). Les jobs qui ont besoin d'atteindre une infrastructure le font avec un jeton dédié, à droits minimaux, dans des variables protégées, sur des runners dédiés et étiquetés. Les rapports de tests et la couverture alimentent un tableau de bord qualité, et la couverture ne doit pas baisser d'une MR à l'autre.

---

### M02-E25 — Empaqueter, versionner et distribuer `medictl`

**Solution**

*1. Où vit la version ?*

| Mécanisme | Qui écrit le numéro | `main` | Publication en échec après l'étiquette | Outils sur `runner01` |
|---|---|---|---|---|
| (a) plugin qui modifie `pyproject.toml` et commite | semantic-release | reçoit un commit `chore(release)` à chaque version : contraire à M01 (rien n'est commité) | étiquette posée, paquet absent ; relancer semantic-release ne republie pas | deux plugins npm de plus |
| (b) version dynamique depuis Git à la construction (`uv-dynamic-versioning`, `hatch-vcs`) | l'outil de construction, d'après `git describe` | inchangé | relancer la construction suffit | un autre système de construction ; clone complet avec étiquettes |
| (c) étiquette injectée dans la copie de travail du job (`uv version --frozen`) | l'étiquette posée par semantic-release | inchangé (`version` n'y est qu'un repère) | relancer le job de publication suffit | rien de nouveau |

Retenu : (c). Il respecte « rien n'est commité dans `main` », n'ajoute aucun outil, et l'étiquette reste l'unique source de vérité. Son seul défaut : `medictl --version` d'une installation de développement affiche la version repère du `pyproject.toml` (ici `0.1.0`), pas « la dernière étiquette + des commits » ; acceptable, une installation de développement n'est pas une version publiée.

*2. Le paquet.* `pyproject.toml` de E07/E15 convient : backend `uv_build`, point d'entrée `medictl = "medictl.cli:app"`, et `medictl/__init__.py` lit sa version par `importlib.metadata.version("medictl")`. La roue ne contient que `src/medictl/` et ses métadonnées : ni `tests/`, ni `bin/`, ni `lib/`. Les scripts Bash ne sont **pas** distribués par ce paquet (ils s'installent par `task install:systeme`, E20 et E26). `uv build` produit aussi l'archive source (`.tar.gz`).

*3. La publication* : job `publier-pypi` de [`fichiers/M02-E25/.gitlab-ci.yml`](fichiers/M02-E25/.gitlab-ci.yml) :

```yaml
publier-pypi:
  stage: release
  needs: [release]
  tags: [shell]
  resource_group: release
  variables:
    GIT_DEPTH: "0"
    GIT_STRATEGY: clone
    UV_PUBLISH_USERNAME: gitlab-ci-token
    UV_PUBLISH_PASSWORD: $CI_JOB_TOKEN
    UV_PUBLISH_URL: ${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/pypi
    UV_PUBLISH_CHECK_URL: ${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/pypi/simple
    UV_SYSTEM_CERTS: "true"
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_COMMIT_REF_PROTECTED == "true"
      exists: [.releaserc.json]
  script:
    - git fetch --quiet --tags --force origin
    - VERSION="$(git tag --points-at "$CI_COMMIT_SHA" --list 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -n 1)"
    - if [ -z "$VERSION" ]; then echo "Aucune version publiée par ce pipeline."; exit 0; fi
    - uv version --frozen "${VERSION#v}"
    - rm -rf dist && uv build
    - test -f "dist/medictl-${VERSION#v}-py3-none-any.whl"
    - uv publish dist/*
```

Points clés :
- même schéma que `publier-branche-majeure` de `plateforme/ci-templates` : le gabarit ne crée pas de pipeline sur les étiquettes, donc la publication suit `release` **dans le pipeline de `main`** et cherche l'étiquette posée sur ce commit ;
- `uv version --frozen` écrit la version dans le `pyproject.toml` **de la copie de travail du job** sans recalculer `uv.lock` ; rien n'est poussé ;
- le jeton de job (`CI_JOB_TOKEN`) suffit pour publier dans le registre de **son** projet ; il passe par l'environnement, jamais en argument (sur un runner `shell`, `ps` montre les arguments des processus de tous les jobs) ; GitLab le masque dans le journal ;
- `UV_PUBLISH_CHECK_URL` : uv consulte l'index et saute les fichiers déjà présents, si bien qu'un job relancé après une publication partielle ne bute pas sur le `400` de GitLab (publier deux fois le même fichier). ⚠️ À vérifier sur ta version : que uv transmet les identifiants à l'URL de vérification d'un registre privé (sinon, retire la variable ; la relance échouera alors proprement sur le fichier déjà publié) ;
- `UV_SYSTEM_CERTS` : sans lui, uv ne fait confiance qu'aux racines Mozilla embarquées et refuse le certificat de `git01` (`invalid peer certificate: UnknownIssuer`), alors que `curl` et `git` l'acceptent.

*4. Une release.* Après la fusion d'une MR `feat(medictl): …`, le pipeline de `main` montre `release` (semantic-release pose `v1.3.0`, crée la release) puis `publier-pypi`. *Deploy → Package registry* liste `medictl 1.3.0` avec deux fichiers.

*5. Le registre en lecture.*
- Groupe `plateforme` → *Settings → Packages and registries → Package forwarding* : décocher « Forward PyPI package requests » (rôle Owner du groupe).
- Projet → *Settings → Repository → Deploy tokens* : nom `medictl-lecture`, expiration, portée **`read_package_registry` seule**.
- Le risque de la redirection : un nom inconnu du registre interne est cherché sur pypi.org. Un paquet publié là-bas sous le nom d'un outil interne **pas encore publié**, ou un nom mal orthographié, se ferait installer comme s'il était interne (confusion de dépendances). Côté uv, la stratégie par défaut `first-index` protège `medictl` lui-même (trouvé dans le premier index qui le connaît) ; elle ne protège pas d'un registre qui va, lui, chercher ailleurs.

*6. L'installation sur `adm01`.*

```
admin@adm01:~$ uv tool uninstall medictl
admin@adm01:~$ install -d -m 700 ~/.config/uv && printf 'system-certs = true\n' >> ~/.config/uv/uv.toml
admin@adm01:~$ read -rs JETON && printf '%s' "$JETON" | uv auth login https://git01.par1.medisphere.internal \
                   --username <UTILISATEUR-DU-JETON> --password - ; unset JETON
admin@adm01:~$ chmod 700 "$(uv auth dir)" && chmod 600 "$(uv auth dir)/credentials.toml"
admin@adm01:~$ uv tool install medictl \
                   --index outils=https://git01.par1.medisphere.internal/api/v4/projects/<ID-PROJET>/packages/pypi/simple
admin@adm01:~$ medictl --version
medictl 1.3.0
```

Fichier : [`fichiers/M02-E25/uv.toml`](fichiers/M02-E25/uv.toml). Le magasin d'identifiants de uv est un fichier TOML en clair créé avec les droits de ton `umask`, d'où le `chmod`. Le reçu (`uv-receipt.toml`, sous `uv tool dir`) mémorise l'index (`url = "https://git01…/simple"`) **sans** identifiant, ce qui permet à `uv tool upgrade` de réutiliser le même index. Variante sans magasin : variables `UV_INDEX_OUTILS_USERNAME` / `UV_INDEX_OUTILS_PASSWORD` lues depuis un fichier 600.

*7. Mise à jour et retour arrière.*

```
admin@adm01:~$ uv tool upgrade medictl
admin@adm01:~$ uv tool install --force 'medictl==1.3.0' --index outils=<URL-DU-REGISTRE>   # retour arrière
```

⚠️ À vérifier sur ta version : que `uv tool upgrade` retrouve les identifiants du magasin `uv auth` pour l'index mémorisé (sinon : variables `UV_INDEX_OUTILS_*`).

**Explications**

La chaîne : un commit `feat:` fusionné → semantic-release décide `1.3.0`, pose `v1.3.0` avec le jeton `bot-release`, crée la release → le job suivant du même pipeline trouve l'étiquette sur `CI_COMMIT_SHA`, fabrique les métadonnées `Version: 1.3.0`, construit et publie. Le registre PyPI de GitLab implémente le protocole d'envoi de PyPI et l'API d'index simple (PEP 503) : `uv`, `pip` et `twine` lui parlent comme à pypi.org. Le jeton de job est éphémère (durée du job), avec les droits de l'utilisateur déclencheur restreints à ce que les jobs peuvent faire : pas de secret de publication stocké dans le projet.

**Alternatives**
- `twine upload` (la documentation de GitLab l'utilise) : équivalent, un outil de plus.
- Registre au niveau du **groupe** `plateforme` : un index unique pour tous les outils internes.
- Distribution sans registre : roue attachée à la release ; plus simple, mais pas de `uv tool upgrade`.
- Version dynamique (b) : préférable si l'on veut des versions de développement traçables.

**Pièges classiques**
- Mettre le jeton dans l'URL (`https://user:jeton@git01…/simple`) : il finit dans l'historique du shell et les journaux.
- Oublier les certificats du système pour uv : l'erreur TLS fait chercher du côté de GitLab.
- Publier depuis le pipeline de MR : le paquet d'une branche non relue devient installable par toute l'équipe.
- Laisser la redirection vers pypi.org active : confusion de dépendances.
- Recréer une étiquette déjà publiée : le registre refuse le même fichier, et des postes ont déjà l'« ancienne » version.

**En production chez MédiSphère**
Un registre de groupe (puis un dépôt proxy d'entreprise, module 13) avec la redirection publique coupée et une liste d'autorisation des paquets externes ; paquets signés et attestés (provenance SLSA) ; installation des outils sur les postes d'administration par Ansible, version épinglée, mise à jour planifiée ; jetons de déploiement à expiration courte renouvelés automatiquement (module 25).

---

### M02-E26 — Contrôle planifié des sauvegardes PBS avec un timer systemd

**Solution**

*1. Le jeton naïf.*

```
root@pve01:~# pveum user token add wb-automation@pve lecture --privsep 1 \
                --expire "$(date -d '+1 year' +%s)" --comment "Contrôle des sauvegardes, lecture (PLAT-356)"
root@pve01:~# pveum acl modify /pool/lab --tokens 'wb-automation@pve!lecture' --roles PVEAuditor
root@pve01:~# pveum acl modify /storage/pbs-par2 --users wb-automation@pve --roles PVEAuditor
root@pve01:~# pveum acl modify /storage/pbs-par2 --tokens 'wb-automation@pve!lecture' --roles PVEAuditor
admin@adm01:~$ MS_PVE_ENV_FILE=~/.config/workbook/pve-lecture.env bash -c \
    'source ~/src/outils/lib/ms-commun.sh; pve_api GET /nodes/<NOEUD>/storage/pbs-par2/content content=backup | jq length'
0
```

Zéro, avec un code HTTP 200, alors que l'interface (en `wb-admin`) montre des dizaines de sauvegardes. La documentation de `GET /nodes/{node}/storage/{storage}/content` exige `Datastore.Audit` **ou** `Datastore.AllocateSpace` sur le stockage pour **appeler** la liste. Mais chaque volume est ensuite filtré par `check_volume_access` (`PVE/Storage.pm`) : pour une sauvegarde de VM, il faut `Datastore.Allocate` sur le stockage, **ou** `Datastore.AllocateSpace` sur le stockage **et** `VM.Backup` sur `/vms/<VMID>`. Les volumes refusés sont **silencieusement** retirés de la liste.

Voir les sauvegardes par cette voie demanderait donc `Datastore.AllocateSpace` + `VM.Backup` : avec eux, le jeton peut lancer des sauvegardes, en restaurer par-dessus des VMs et **supprimer** des sauvegardes non protégées. Confier cela à un contrôle qui tourne sans surveillance est exactement ce qu'il faut éviter. Conclusion présentée à Sophie : interroger **PBS directement** (source de vérité des sauvegardes) avec un jeton PBS `DatastoreAudit` (lister groupes et instantanés, rien de plus), et garder un jeton Proxmox VE `PVEAuditor` sur `/pool/lab` pour savoir **quelles** VMs doivent être sauvegardées. On retire ensuite l'ACL devenue inutile sur `/storage/pbs-par2`.

*2. Les bons jetons.* Proxmox VE : `wb-automation@pve!lecture` avec `PVEAuditor` sur `/pool/lab`. Ses droits effectifs (intersection avec `WBAutomation`) : `VM.Audit`, `Pool.Audit`, `VM.GuestAgent.Audit`. PBS :

```
root@pbs01:~# proxmox-backup-manager user create wb-verif@pbs --comment "Contrôle des sauvegardes depuis adm01 (PLAT-356)"
root@pbs01:~# proxmox-backup-manager user generate-token wb-verif@pbs lecture --comment "ms-verif-sauvegardes"
root@pbs01:~# proxmox-backup-manager acl update /datastore/ds-lab/par1 DatastoreAudit --auth-id wb-verif@pbs
root@pbs01:~# proxmox-backup-manager acl update /datastore/ds-lab/par1 DatastoreAudit --auth-id 'wb-verif@pbs!lecture'
root@pbs01:~# proxmox-backup-manager user permissions 'wb-verif@pbs!lecture' --path /datastore/ds-lab/par1
Path: /datastore/ds-lab/par1
- Datastore.Audit (*)
```

`DatastoreAudit` ne donne que `Datastore.Audit` : lister groupes, instantanés, état de vérification ; pas `Datastore.Read` (télécharger le contenu), ni `Backup`, `Modify`, `Prune`. ⚠️ À vérifier sur ta version : l'expiration d'un jeton PBS et la visibilité avec des ACL limitées au namespace (sinon, poser l'ACL sur `/datastore/ds-lab`, comme pour `wb-backup` en M00-E22).

Confiance TLS envers le certificat autosigné de `pbs01` :

```
admin@adm01:~$ openssl s_client -connect 10.20.10.10:8007 </dev/null 2>/dev/null | openssl x509 > /tmp/pbs01.pem
admin@adm01:~$ openssl x509 -in /tmp/pbs01.pem -noout -fingerprint -sha256
sha256 Fingerprint=3A:5C:…:E1
root@pve01:~# awk '/^pbs: pbs-par2/,/^$/' /etc/pve/storage.cfg | grep fingerprint
	fingerprint 3a:5c:…:e1
admin@adm01:~$ openssl x509 -in /tmp/pbs01.pem -pubkey -noout | openssl pkey -pubin -outform der \
                 | openssl dgst -sha256 -binary | base64
6taJqtxQdYkzIsAx2jnvv4kUACUXp6WRXnJfvty6mYI=
```

Les deux empreintes de certificat coïncident (à la casse près) : ce certificat est bien celui auquel `pve01` fait déjà confiance (M00-E22 ; troisième source : `proxmox-backup-manager cert info` sur la console de `pbs01`). L'épingle de la **clé publique** va dans `PBS_PINNEDPUBKEY="sha256//6taJ…mYI="` de `pbs-lecture.env` (modèles : [`pbs-lecture.env.exemple`](fichiers/M02-E26/pbs-lecture.env.exemple), [`pve-lecture.env.exemple`](fichiers/M02-E26/pve-lecture.env.exemple)). Avec `--pinnedpubkey`, curl vérifie la clé du serveur **même si** la vérification de chaîne est désactivée (doc `CURLOPT_PINNEDPUBLICKEY`) : un autre certificat est refusé (`SSL: public key does not match pinned public key`), quel que soit le nom ou l'adresse utilisés.

*3. Le script* : [`fichiers/M02-E26/bin/ms-verif-sauvegardes`](fichiers/M02-E26/bin/ms-verif-sauvegardes), tests [`tests/bats/ms-verif-sauvegardes.bats`](fichiers/M02-E26/tests/bats/ms-verif-sauvegardes.bats) (9 tests, API remplacées par des fonctions). Choix notables :
- `unset PVE_*` puis `MS_PVE_ENV_FILE=…/pve-lecture.env` : la bibliothèque donne la priorité aux variables `PVE_*` présentes (utile en CI) ; un `source pve-api.env` traînant dans le shell ferait sinon tourner le contrôle avec le jeton d'écriture ;
- l'en-tête PBS (`Authorization: PBSAPIToken=<jeton>:<secret>`) passe par `curl -K -` (configuration lue sur l'entrée standard) : le secret n'apparaît pas dans `ps` ;
- `evaluer` est une fonction pure sur du JSON (testée sans réseau) : une VM est en défaut si sa dernière sauvegarde a plus de 26 h, si elle n'en a aucune, ou si la vérification PBS de la dernière a échoué ;
- **liste vide = échec** : aucune VM étiquetée `socle` visible, c'est un problème de droits ou d'étiquettes, jamais « tout va bien » ;
- exemple de sortie :

```
VMID   NOM          DERNIÈRE           ÂGE (h) VÉRIF.        ÉTAT
1000   gw01         2026-10-04 02:31       5.0 ok            OK
1002   dns01        2026-10-02 02:32      52.9 ok            KO (trop ancienne)
1004   git01        2026-10-04 02:40       4.8 jamais        OK
2026-10-04T07:30:04+02:00 ms-verif-sauvegardes[2211] ERREUR 1 VM(s) du socle sans sauvegarde valable de moins de 26 h
```

*4. L'installation* : la tâche `install:systeme` de E20 ([`Taskfile.yml`](fichiers/M02-E20/outils/Taskfile.yml)) copie `bin/ms-*` (dont `ms-verif-sauvegardes` et `ms-alerte`) et `lib/ms-commun.sh` dans `/usr/local`, en root ; rien à ajouter. Elle ne touche pas à `medictl`, installé depuis le registre depuis E25 (c'est pour cela qu'on ne lance plus `task install` sur `adm01`).

Le script retrouve sa bibliothèque par `readlink -f` : depuis `/usr/local/bin`, c'est `/usr/local/lib/ms-commun.sh`. Un lien vers `~/src/outils` ferait exécuter chaque matin l'état courant du clone (branche en cours, vieille version remise par `git checkout`, fichier à moitié édité), et rendrait le durcissement `ProtectHome` impossible. La version installée ne change que par une installation délibérée.

*5. Les unités* : [`systemd/ms-verif-sauvegardes.service`](fichiers/M02-E26/systemd/ms-verif-sauvegardes.service), [`.timer`](fichiers/M02-E26/systemd/ms-verif-sauvegardes.timer), [`ms-alerte@.service`](fichiers/M02-E26/systemd/ms-alerte@.service), [`bin/ms-alerte`](fichiers/M02-E26/bin/ms-alerte).

```ini
[Unit]
OnFailure=ms-alerte@%n.service
[Service]
Type=oneshot
User=admin
ExecStart=/usr/local/bin/ms-verif-sauvegardes
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
NoNewPrivileges=yes
[Timer]
OnCalendar=*-*-* 07:30:00
Persistent=true
```

```
admin@adm01:~/src/outils$ task install:systeme
admin@adm01:~/src/outils$ sudo install -m 0644 systemd/* /etc/systemd/system/
admin@adm01:~$ sudo systemd-analyze verify /etc/systemd/system/ms-verif-sauvegardes.{service,timer}
admin@adm01:~$ sudo systemctl daemon-reload && sudo systemctl enable --now ms-verif-sauvegardes.timer
admin@adm01:~$ systemctl list-timers ms-verif-sauvegardes.timer
NEXT                         LEFT     LAST PASSED UNIT                        ACTIVATES
Sun 2026-10-05 07:30:00 CEST 21h left -    -      ms-verif-sauvegardes.timer  ms-verif-sauvegardes.service
```

`ProtectHome=read-only` laisse le service lire `~admin/.config/workbook/` sans rien écrire dans `/home` ; `ProtectSystem=strict` met tout le reste en lecture seule. `ms-alerte@.service` tourne avec un utilisateur éphémère (`DynamicUser=yes`) membre de `systemd-journal` pour lire le journal de l'unité en échec ; il reçoit de systemd `MONITOR_UNIT`, `MONITOR_SERVICE_RESULT`, `MONITOR_EXIT_STATUS` et `MONITOR_INVOCATION_ID`, et extrait ainsi les lignes de **cette** exécution (`journalctl _SYSTEMD_INVOCATION_ID=…`). Pourquoi un gabarit `@` : la documentation précise que si plusieurs unités désignent le même gestionnaire unique, les variables `MONITOR_*` ne sont pas transmises ; et une instance par unité surveillée permet de réutiliser `ms-alerte@` pour les futurs contrôles.

*6. Les deux chemins.*

```
admin@adm01:~$ sudo systemctl start ms-verif-sauvegardes.service   # réussit
admin@adm01:~$ sudo systemctl edit ms-verif-sauvegardes.service    # drop-in temporaire
[Service]
Environment=MS_VERIF_AGE_MAX_H=1
admin@adm01:~$ sudo systemctl start ms-verif-sauvegardes.service   # échoue
admin@adm01:~$ journalctl -t ms-alerte -n 12 --no-pager
… ms-alerte[2290]: ÉCHEC ms-verif-sauvegardes.service sur adm01 (résultat exit-code, code exited/1)
… ms-alerte[2290]: --- dernières lignes ---
…
admin@adm01:~$ sudo systemctl revert ms-verif-sauvegardes.service
```

(Test à faire hors de la fenêtre 02:30-03:30 : avec un seuil d'une heure, il faut que les sauvegardes aient plus d'une heure.)

**Explications**

Le cœur de l'exercice est la différence entre un **contrôle d'échec** (les notifications PBS : « une tâche a échoué ») et un **contrôle de résultat** (« le résultat attendu existe ») : seul le second voit l'absence d'événement (tâche désactivée, VM sortie du pool, PBS éteint, tunnel coupé), et doit donc traiter comme un échec tout cas où il ne peut pas conclure. L'écueil des droits l'illustre : l'API renvoie une liste filtrée, pas une erreur. Côté planification, un service `oneshot` lancé par timer a un état (`Result=`), un journal par exécution, un délai maximal, un durcissement, un crochet d'échec : tout ce que cron n'offre pas. `Persistent=true` enregistre la dernière exécution sur disque et rattrape une échéance manquée au démarrage.

**Alternatives**
- Jeton Proxmox VE avec `Datastore.AllocateSpace` + `VM.Backup` et lecture par l'API de `pve01` : fonctionne mais donne des droits destructeurs. Refusé.
- `proxmox-backup-client snapshot list --output-format json` sur `adm01` (variables `PBS_REPOSITORY`, `PBS_PASSWORD`, `PBS_FINGERPRINT`) : même jeton PBS, empreinte native ; nécessite d'installer le client. Bon choix aussi.
- Contrôle sur `pbs01` (il ignore les étiquettes des VMs, et un PBS en panne ne se signalerait pas) ou sur `pve01` (un `pve01` éteint ne dirait rien) : `adm01` est le tiers qui observe les deux.
- Supervision (module 21) : métrique « âge de la dernière sauvegarde par VM » et règle d'alerte ; cible à terme.

**Pièges classiques**
- Conclure « tout va bien » sur une liste vide.
- Donner au jeton de lecture le droit qui « fait marcher » l'appel (`Datastore.Allocate`) sans mesurer ce qu'il permet.
- Oublier l'ACL de l'**utilisateur** avec la séparation des privilèges (l'erreur est alors un `403`, pas une liste vide).
- `curl -k` sans épingle : n'importe quel serveur sur le chemin peut se faire passer pour PBS.
- Tester dans son terminal et déclarer victoire : sous systemd, l'environnement, le `HOME`, l'utilisateur, le `PATH`, les protections changent (M02-E35).
- Un `OnFailure=` vers une unité absente ou qui échoue elle-même : aucune alerte, en silence.
- Un timer actif mais jamais déclenché (`OnCalendar` invalide, timer arrêté) : vérifier `NEXT` dans `list-timers` (M02-E41).

**En production chez MédiSphère**
Le contrôle devient une sonde de supervision (âge de la dernière sauvegarde, état de vérification) exposée en métrique, avec alerte routée vers l'astreinte (Alertmanager, module 21) ; un tableau de bord montre la couverture de sauvegarde de toutes les VMs. Les jetons de lecture sont renouvelés automatiquement (Vault, module 25), et un test de restauration mensuel (M00-E37) complète le contrôle d'existence : une sauvegarde qui existe n'est pas encore une sauvegarde qui se restaure.

---

### M02-E27 — Idempotence et `--dry-run`

**Solution**

*Définition (état visé).* « Après une exécution réussie, chaque VM ciblée possède un point de retour `<PRÉFIXE>-AAAAMMJJ-HHMMSS` pris avant l'intervention (le plus récent de moins de 30 minutes, ou un nouveau), et au plus N instantanés gérés ; rien d'autre n'a changé. » Relancer la commande ne change rien de plus : c'est l'idempotence.

*Ce qui ne l'était pas dans la version de E13.*
1. Chaque exécution crée un nouvel instantané (nouvel horodatage) : trois relances = trois instantanés, et la rotation chasse le vrai point de retour (l'incident de Nadia).
2. Deux exécutions dans la même seconde : le second `POST` échoue (`snapshot name … already used`), la VM est comptée en échec.
3. La simulation suit un autre chemin de code que l'exécution (liste complétée à la main, messages « créerait / supprimerait ») : rien ne garantit qu'ils restent d'accord.
4. Une VM verrouillée (sauvegarde en cours, tâche interrompue) fait échouer la création avec une erreur d'API brute.
5. Un Ctrl-C pendant l'attente ne dit rien de l'état laissé.

*Conception* : [`fichiers/M02-E27/bin/ms-snapshot`](fichiers/M02-E27/bin/ms-snapshot). Le traitement d'une VM est découpé en trois temps :
1. **lecture de l'état** : configuration de la VM (champ `lock`) et liste des instantanés (avec `snaptime`), en `GET` seulement ;
2. **plan** : une fonction pure, `planifier CONFIG INSTANTANES CIBLE MAINTENANT`, produit une action par ligne : `verrou <type>`, `reutiliser <nom>`, `creer <nom>`, `supprimer <nom>`. Elle choisit le point de retour (le nom cible s'il existe déjà, sinon le plus récent de moins de `--fenetre` minutes, sinon un nouveau), puis les instantanés gérés au-delà des N plus récents, **jamais** celui qu'elle garantit ;
3. **application** : dans l'ordre, arrêt au premier échec ; la création venant en premier, son échec empêche toute suppression.

`--dry-run` s'arrête après l'étape 2 et écrit le plan sur la sortie standard (`VMID<TAB>action nom`) ; l'exécution réelle applique **le même plan**. Options et codes de E11/E13 conservés ; nouvelle option `-f/--fenetre MINUTES` (défaut 30, `0` force un nouvel instantané). Un `trap` sur SIGINT/SIGTERM signale la tâche Proxmox éventuellement en cours (elle continue côté serveur) et invite à relancer.

```
admin@adm01:~$ ms-snapshot --dry-run --keep 2 2027
2027	reutiliser avant-20261004-091502
2027	supprimer avant-20261004-085011
2026-10-04T09:21:40+02:00 ms-snapshot[3121] INFO [simulation] 2027 (m02-idem) : réutiliserait l'instantané récent avant-20261004-091502
2026-10-04T09:21:40+02:00 ms-snapshot[3121] INFO [simulation] 2027 (m02-idem) : supprimerait l'ancien instantané avant-20261004-085011
```

*Tests* : [`tests/bats/ms-snapshot-idempotence.bats`](fichiers/M02-E27/tests/bats/ms-snapshot-idempotence.bats) et un faux Proxmox **avec état** en mémoire, [`fake-pve.bash`](fichiers/M02-E27/tests/bats/fake-pve.bash) (les instantanés créés et supprimés persistent d'une exécution à l'autre : on peut tester des relances). Dix tests, dont : aucune écriture en dry-run ; plan annoncé = requêtes réellement envoyées (comparaison automatique) ; trois exécutions → N instantanés, manuels intacts ; relance dans la fenêtre → réutilisation ; même seconde → pas de doublon ; reprise après interruption entre création et purge ; VM verrouillée ; création en échec sans suppression. Les trois tests de E14 qui appelaient la fonction interne `a_purger` (disparue au profit de `planifier`) sont retirés de [`ms-snapshot.bats`](fichiers/M02-E27/tests/bats/ms-snapshot.bats), dont les autres tests passent sans changement : tester le **contrat** laisse la liberté de restructurer l'implémentation.

*Démonstration sur la VM 2027* (journal, exemple) :

```
admin@adm01:~$ medictl vm create m02-idem --vmid 2027 --template 9000 --vnet vsandbox --tags env-m02 --wait
root@pve01:~# qm snapshot 2027 avant-manuel && qm snapshot 2027 avant-maj-demo
admin@adm01:~$ ms-snapshot -n -k 2 2027     # plan : creer avant-…-091502
admin@adm01:~$ ms-snapshot -k 2 2027        # 1. création
admin@adm01:~$ ms-snapshot -k 2 2027        # 2. relance immédiate : réutilisation, aucune écriture
admin@adm01:~$ ms-snapshot -k 2 -f 0 2027   # 3. forcée : création
admin@adm01:~$ ms-snapshot -k 2 -f 0 2027   # 4. forcée, Ctrl-C pendant l'attente → code 130
admin@adm01:~$ ms-snapshot -k 2 2027        # 5. relance : réutilise le dernier, purge le plus ancien
root@pve01:~# qm listsnapshot 2027 && qm config 2027 | grep -c '^lock:'
```

État final : `avant-manuel`, `avant-maj-demo`, deux `avant-AAAAMMJJ-HHMMSS`, pas de verrou. Puis `lab/bin/check 02 27`, et `medictl vm destroy 2027 --yes`.

**Explications**

L'idempotence se définit sur un **état**, jamais sur une action : `mkdir -p` est idempotent parce qu'il garantit « le dossier existe ». Pour un outil qui crée des objets horodatés, il faut choisir ce que l'on garantit ; ici, un point de retour pris **avant** l'intervention, ce qui rend la réutilisation plus sûre que la création (un instantané pris au milieu capturerait un état à moitié modifié et pousserait le bon hors de la rotation). Le motif « lire l'état → calculer un plan → appliquer » est celui de tous les outils déclaratifs (le `plan` d'OpenTofu au module 05, le `--check` d'Ansible au module 04) : la simulation est fidèle par construction, car elle **est** la première moitié de l'exécution. Un `lock` dans la configuration Proxmox signale qu'une opération est en cours ou interrompue ; agir dessus serait au mieux refusé, au pire incohérent.

**Alternatives**
- Nom d'instantané **choisi par l'opérateur** (`--nom avant-CHG-312`) : l'idempotence devient naturelle (le nom existe → rien à faire), au prix d'une discipline de nommage.
- Marqueur d'exécution local : à éviter, l'état réel est dans Proxmox et un fichier local diverge.
- Plan en JSON (`--format json`) pour qu'un autre outil le valide ou l'applique.

**Pièges classiques**
- Une sélection par préfixe (`startswith("avant")`) qui emporte `avant-maj-…` posé à la main.
- Calculer la rotation **avant** la création et l'appliquer même si la création échoue.
- Un dry-run qui « oublie » l'instantané qu'il créerait dans son calcul de rotation, ou qui appelle `POST` « juste pour voir ».
- Trier par nom quand les horloges divergent ; ici, tri sur `snaptime` (heure du serveur), puis sur le nom.
- Une boucle `while read` sur une liste, avec à l'intérieur une commande qui lit l'entrée standard : la boucle s'arrête après la première VM (d'où les descripteurs 3 et 4).

**En production chez MédiSphère**
Les instantanés d'intervention sont posés par le pipeline de changement (CHG) avec le numéro du changement dans le nom et la description, et leur ménage est automatique après clôture. Pour l'infrastructure déclarée (OpenTofu, Ansible), l'idempotence est une propriété testée en CI (deuxième exécution = aucun changement) ; pour les scripts d'exploitation, la même exigence s'écrit dans les tests, comme ici.

---

### M02-E28 — Paralléliser sans se tirer une balle dans le pied

**Solution**

*1. Mesure de départ* (exemple) : 4 hôtes réels en séquentiel ≈ 5 s (surtout `apt-get -s`) ; avec deux hôtes injoignables, ≈ 11-15 s (chaque injoignable coûte 3 à 5 s : délai de `gw01` puis ICMP *host unreachable*, ou `ConnectTimeout=5`).

*2. Version `xargs`* : [`fichiers/M02-E28/variantes/ms-etat-hotes.xargs`](fichiers/M02-E28/variantes/ms-etat-hotes.xargs). Le script s'appelle lui-même en mode `--un INDEX HOTE`, chaque ligne commence par son index, et l'ensemble est retrié. Le piège de la consigne :

```
admin@adm01:~$ printf '%s\n' h1 injoignable h2 h3 | xargs -n1 -P1 bash -c '[[ $0 == injoignable ]] && exit 255; echo $0'
h1
xargs: bash: exited with status 255; aborting
admin@adm01:~$ echo $?
124
```

`ssh` renvoie 255 quand la connexion échoue, et `xargs` **s'arrête** dès qu'une commande renvoie 255 : les hôtes suivants ne sont jamais interrogés. Le mode `--un` renvoie donc toujours 0 et l'état est porté par la ligne. (Autres codes de `xargs` : 123 si une commande a renvoyé 1 à 125.)

*3. Version GNU parallel* : [`variantes/ms-etat-hotes.parallel`](fichiers/M02-E28/variantes/ms-etat-hotes.parallel) : `parallel --will-cite --keep-order --jobs N --timeout 30 "$0" --un {} ::: "$@"`. `--keep-order` remplace l'index et le tri, `--tag` préfixerait chaque ligne par son argument, `--joblog` écrit durée et code de chaque job, `--timeout` borne un job bloqué. Son code retour est le **nombre** de jobs en échec (plafonné à 101 ; 255 pour une autre erreur) : on le déduit des lignes.

*4. Version Bash* (retenue) : [`fichiers/M02-E28/bin/ms-etat-hotes`](fichiers/M02-E28/bin/ms-etat-hotes) :

```bash
for i in "${!hotes[@]}"; do
  while (($(jobs -rp | wc -l) >= jobs_max)); do
    wait -n || true            # un hôte en échec ne doit pas arrêter le script (set -e)
  done
  etat_hote "${hotes[$i]}" >"$_tmp/$i" &
done
wait || true
```

Puis assemblage des fichiers `0`, `1`, … dans l'ordre (une ligne d'erreur si un fichier est vide), et code retour déduit des lignes. Le dossier temporaire est supprimé par un `trap … EXIT`. Ctrl-C : les jobs d'arrière-plan d'un script **ignorent SIGINT** ; sans traitement, le script meurt et ses `ssh` continuent (`pgrep -a ssh`). Le `trap` tue d'abord les enfants de chaque job (`pkill -TERM -P <job>`, c'est-à-dire le `ssh`), puis le job, attend, et sort en 130/143.

*5. Choix et tests.* Bash pur : aucune dépendance (ni `parallel` sur les hôtes, ni réécriture pour `xargs`), comportement complet sous contrôle (ordre, codes, nettoyage, interruption), ~40 lignes de plus que la version séquentielle. GNU parallel serait le choix si la collecte devenait plus riche (reprises, journal, exécution distante). Tests : [`tests/bats/ms-etat-hotes.bats`](fichiers/M02-E28/tests/bats/ms-etat-hotes.bats) avec un faux `ssh` en tête du `PATH` ([`fake-bin/ssh`](fichiers/M02-E28/tests/bats/fake-bin/ssh), 1 s par appel, 255 pour « injoignable ») : ordre, temps, borne `-j`, injoignable au milieu, pas de fichier résiduel, usage.

*6. Les limites* : `git01` × 16 avec `-j 16`.
- Sans multiplexage, 16 connexions s'ouvrent ensemble : `sshd` a `MaxStartups 10:30:100` par défaut (au-delà de 10 connexions non authentifiées, il en refuse 30 % puis de plus en plus). Des lignes `injoignable` apparaissent alors que l'hôte va bien : faux négatifs.
- Avec le multiplexage de `adm01` (`ControlMaster`/`ControlPersist`, M00-E15), les 16 sessions passent par **une** connexion maîtresse ; `MaxSessions 10` limite les sessions par connexion : au-delà, `channel N: open failed: administratively prohibited`. Le premier lancement, sans maîtresse, crée une course entre les processus.
- Règle retenue : `-j 4` par défaut, jamais plus de 8 vers un même hôte ; une collecte se parallélise **par hôte**. Pour l'API Proxmox : `pveproxy` a peu de *workers* (3 par défaut) ; au-delà de 4-8 requêtes simultanées on ne gagne plus rien et on ralentit l'interface des humains ; pas de parallélisme sur une même VM (verrous) ; reprises avec délai exponentiel seulement sur réseau et 5xx (E17).

*7. Mesure finale* (exemple) : 4 hôtes en `-j 4` ≈ 1,5 s ; 6 hôtes dont 2 injoignables ≈ 5 s (le plus lent fixe la durée).

**Explications**

Paralléliser, c'est gérer quatre choses que le séquentiel donnait gratuitement : l'**ordre** (les résultats arrivent dans l'ordre de fin), l'**intégrité** des sorties (une écriture de moins de `PIPE_BUF` = 4096 octets dans un tube est atomique, pas une écriture dans un fichier ou un terminal), les **codes retour** (le `$?` d'un job d'arrière-plan n'existe qu'au `wait` qui le récupère) et la **charge** imposée aux serveurs. Écrire chaque résultat dans son propre fichier règle les deux premiers ; déduire le code final des résultats règle le troisième ; `-j` règle le quatrième. `wait -n` (Bash ≥ 4.3) attend la fin d'**un** job quelconque, ce qui maintient un nombre constant de tâches en vol.

**Alternatives**
- Python `ThreadPoolExecutor(max_workers=4)` + `subprocess.run([...], timeout=…)` : ordre conservé avec `executor.map`, exceptions remontées par `future.result()` ; les threads conviennent (travail d'attente réseau, E33 q.10).
- Ansible (module 04) : `gather_facts` en parallèle (`forks`), gestion des injoignables : l'outil naturel dès que la collecte grossit.
- `pdsh`/`clush` : exécution parallèle SSH avec regroupement des sorties identiques.

**Pièges classiques**
- `xargs` arrêté par un code 255, sans que les hôtes non interrogés soient remarqués.
- `cmd & ... wait` sous `set -e` : le premier job en échec fait sortir le script.
- `ssh` sans `-n` dans une boucle `while read` : il avale le reste de la liste.
- `-j` illimité : on teste le serveur, pas les hôtes.
- Fichiers temporaires à nom fixe : collisions entre exécutions, et résidus après un Ctrl-C.

**En production chez MédiSphère**
Les relevés de parc passent par Ansible ou la supervision (exporters, module 21), pas par des boucles SSH. Les scripts qui parallélisent ont une limite par défaut prudente, documentée, et ne parallélisent jamais une action destructrice sans plan préalable et confirmation.

---

### M02-E29 — Durcir un script lancé avec `sudo`

**Solution**

L'exercice applique une idée simple : quand `sudo` fait tourner un script en root, **tout ce que l'appelant contrôle devient une entrée de confiance de root** — le code exécuté, les fichiers lus, l'environnement, les arguments, les programmes lancés, les chemins d'écriture. Durcir, c'est reprendre à l'appelant chacun de ces leviers. La version de Lucas les lui laisse tous.

*1. Lecture.* `shellcheck` ne signale que des guillemets manquants (SC2086) et la bibliothèque absente : aucune des faiblesses de conception. Faiblesses relevées (et la question que chacune pose) :

| # | Faiblesse (version de Lucas) | Question de sécurité |
|---|---|---|
| 1 | installé par **lien** vers `~admin/src/outils/bin/ms-diag`, qui charge `../lib/ms-commun.sh` | qui peut modifier le code que root exécute ? (ici : `admin`, et tout ce qui écrit dans le clone) |
| 2 | chemin de l'archive **choisi par l'appelant**, écrit par root | où root écrit-il, et qui choisit l'emplacement ? |
| 3 | `systemctl status` final **sur un terminal** : pager en root | root lance-t-il un programme qui peut ouvrir un shell ou un éditeur ? |
| 4 | copie de `/etc/ssh` entière dans l'archive | l'archive expose-t-elle des clés privées, des secrets de configuration ? |
| 5 | répertoire temporaire **fixe** `/tmp/ms-diag`, `rm -rf` puis `mkdir` | un tiers peut-il préparer ou détourner ce chemin avant root ? |
| 6 | arguments **non validés**, variables non protégées | l'appelant peut-il injecter options, globs, `..`, séparateurs ? |
| 7 | règle sudo `(ALL) … *` | la règle autorise-t-elle trop (autre utilisateur cible, arguments libres) ? |
| 8 | aucune trace de qui a collecté quoi | une utilisation laisse-t-elle une trace exploitable ? |

*2. Preuves.* Dans l'énoncé, tu installes la version de Lucas dans un bac à sable et tu démontres, depuis le compte sans privilège `astreinte01`, que trois des leviers ci-dessus (code modifiable, chemin d'écriture choisi, programme interactif) suffisent à obtenir des droits que l'astreinte ne devrait pas avoir. Note dans ton journal, pour chacun, la commande et son effet — puis **désinstalle** le lien et la règle, et vérifie avec `sudo -l -U astreinte01` qu'il ne reste rien.

*3. Le script durci* : [`fichiers/M02-E29/sbin/ms-diag`](fichiers/M02-E29/sbin/ms-diag). Chaque faiblesse reçoit sa parade :

| # | Parade |
|---|---|
| 1 | installé par **copie** dans `/usr/local/sbin`, `root:root 0755` ; **autonome** (ne charge aucune bibliothèque d'un clone modifiable). Dossiers parents non modifiables par un non-root |
| 2 | l'archive sort sur la **sortie standard**, redirigée par le shell de l'appelant, avec **ses** droits : root n'écrit aucun fichier choisi par l'appelant. Refus si la sortie est un terminal |
| 3 | aucun programme interactif : `SYSTEMD_PAGER=`, `PAGER=cat`, `systemctl --no-pager`, `journalctl --no-pager` |
| 4 | collecte **limitée** (statut, unité, journal de l'unité, ports, disques, mémoire, réseau) et **expurgée** : les valeurs qui ressemblent à un secret (`password=`, `token=`, `key=`…) sont masquées ; aucune clé ni fichier `.env` n'est copié |
| 5 | `mktemp -d` (nom imprévisible), `trap 'rm -rf -- "$tmp"' EXIT`, `umask 077` |
| 6 | arguments validés par **liste blanche** (`^[A-Za-z0-9][A-Za-z0-9:_.@-]{0,99}\.(service|timer|socket|mount|path)$`), 1 à 5 unités ; chaque unité doit exister (`systemctl show -p LoadState`) ; `--depuis` est un entier borné |
| 7 | règle minimale : le groupe `astreinte`, **ce seul programme**, en root (`(root)`), sans `*` superflu |
| 8 | `logger -t ms-diag -p auth.notice` nomme l'appelant (`$SUDO_USER`) et ce qu'il a demandé, à chaque exécution |

En-tête de la version durcie : mode strict, `PATH` et environnement fixés par le script (il peut être lancé un jour par systemd, cron ou root directement, pas seulement par `sudo`), shebang absolu, `umask 077`.

*4. La règle sudo* : [`fichiers/M02-E29/sudoers.d/ms-diag`](fichiers/M02-E29/sudoers.d/ms-diag).

```
Cmnd_Alias MS_DIAG = /usr/local/sbin/ms-diag
%astreinte ALL=(root) NOPASSWD: MS_DIAG
```

Installation **prudente** (le `⚠️` de l'énoncé) : écrire ailleurs, `visudo -cf <FICHIER>`, puis `install -m 0440 -o root -g root`, en gardant une session root ouverte. On peut restreindre aussi les arguments dans la règle (sudo ≥ 1.9.10 accepte une expression régulière entre `^` et `$`, `man sudoers` section *Regular expressions*) :

```
Cmnd_Alias MS_DIAG = /usr/local/sbin/ms-diag ^(--depuis [0-9]{1,2} )?[A-Za-z0-9@_.:-]+[.]service( [A-Za-z0-9@_.:-]+[.]service){0,4}$
```

La validation dans le script **reste nécessaire** : la règle sudo n'est qu'une première barrière (et le script doit rester sûr lancé autrement que par sudo).

*5. Contre-preuves.* Rejoue contre la version durcie, depuis `astreinte01`, les scénarios de l'étape 2 plus : un argument contenant `;`, `../` ou une option `--…`, une unité inexistante, une sortie vers un terminal. Tout est refusé proprement (code ≠ 0, aucune archive produite). Une collecte légitime laisse une ligne d'audit `ms-diag` nommant `astreinte01`.

```
astreinte01$ sudo ms-diag ssh.service > diag-ssh.tar.gz   # OK : archive écrite par astreinte01
astreinte01$ sudo ms-diag /etc/shadow                     # refus (nom d'unité invalide), rien produit
astreinte01$ sudo ms-diag ssh.service > /dev/pts/0        # refus (sortie = terminal)
```

*6. Le projet.* Script versionné (`sbin/ms-diag`) et règle (`sudoers.d/ms-diag`) dans `plateforme/outils`, avec des tests bats de la validation des arguments : [`tests/bats/ms-diag.bats`](fichiers/M02-E29/tests/bats/ms-diag.bats). Ils tournent sans root (en CI) parce que le script valide ses arguments **avant** de vérifier qu'il est root : la validation ne fait rien de privilégié, et l'ordre rend le filtre testable. `sbin/` rejoint la tâche `lint:sh` du Taskfile, `.editorconfig` et les règles `changes` de la CI (fichiers de référence de E20 et E24). Livraison sur une machine : par **copie** (Ansible au module 04), jamais par lien ; seul root peut modifier le fichier installé.

**Explications**

Un programme lancé par `sudo` s'exécute avec les privilèges de la cible, mais **avec des entrées fournies par un utilisateur moins privilégié**. Le durcissement consiste à traiter chacune de ces entrées comme hostile : le code et ses dépendances doivent appartenir à root et n'être modifiables que par root (sinon l'appelant choisit ce que root exécute) ; aucun chemin d'écriture, aucune partie de l'environnement (`PATH`, `IFS`, `BASH_ENV`…), aucun argument ne doit être pris tel quel ; aucun programme susceptible d'ouvrir un sous-shell ou un éditeur ne doit être lancé de façon interactive. `sudo` aide (`env_reset`, `secure_path`), mais le script ne doit pas en dépendre : il peut être appelé par systemd, cron ou root directement. Faire sortir le résultat sur la sortie standard de l'appelant est l'astuce qui supprime toute écriture privilégiée vers un chemin choisi : c'est le shell de l'appelant, avec ses propres droits, qui crée le fichier.

**Alternatives**
- `systemd-run --uid=0 --pipe …` pour une action privilégiée ponctuelle, encadrée par une unité transitoire durcie, plutôt qu'une entrée sudo permanente.
- `polkit` pour une autorisation plus fine (par action, par attribut), au prix d'une complexité supérieure.
- Un démon privilégié minimal qui expose une API de collecte à l'astreinte (surface d'attaque réduite au strict protocole), pour un parc important.
- Journalisation des entrées/sorties de sudo (`log_output`) : utile à l'audit, mais ne remplace pas la restriction (elle constate après coup).

**Pièges classiques**
- Autoriser en sudo un script modifiable par l'appelant (lien vers un clone, dossier parent ouvert en écriture).
- Laisser root écrire dans un chemin que l'appelant fournit.
- Lancer un programme qui peut ouvrir un pager ou un éditeur (d'où `--no-pager` partout).
- Valider les arguments par liste **noire** (interdire `;`, `..`) plutôt que par liste **blanche** (n'autoriser qu'un motif strict).
- Oublier que `sudo` sans arguments listés accepte **tous** les arguments : c'est au script de les valider.
- Copier des répertoires de configuration entiers dans une archive « de diagnostic » (clés, secrets).

**En production chez MédiSphère**
Les collectes de diagnostic passent par un outil versionné, livré par Ansible (copie, propriétaire root), autorisé par une règle sudo minimale et nominative, avec journalisation centralisée des appels (module 22) ; les archives expurgées sont déposées dans un espace à accès restreint, avec une rétention courte. Toute entrée sudo est revue périodiquement (audit HDS), et l'ajout d'une nouvelle entrée passe par une MR relue par la RSSI.

---

### M02-E30 — Signaux, délais et sous-processus

**Solution**

*1. Bash, observation.* Résultat attendu de [`ressources/M02-E30/demo-signaux.sh`](../ressources/M02-E30/demo-signaux.sh) :

| Mode | Ctrl-C (SIGINT au groupe du terminal) | `kill -TERM <PID du script>` |
|---|---|---|
| premier-plan (`sleep` au premier plan) | trap INT immédiat (le `sleep` reçoit aussi le signal du groupe et meurt), code 130, pas d'orphelin | trap TERM **après la fin du `sleep`** (Bash attend la commande de premier plan), code 143 |
| arrière-plan (`sleep & wait`) | trap INT immédiat (`wait` est interrompu), code 130, **mais** le `sleep` d'arrière-plan survit (il ignore SIGINT) | trap TERM immédiat, code 143, le `sleep` survit |
| arrière-plan-propre (idem + le trap tue l'enfant) | trap INT immédiat, enfant tué, pas d'orphelin | trap TERM immédiat, enfant tué, pas d'orphelin |

Lecture : (a) un `trap` ne s'exécute qu'**entre** deux commandes ; tant que Bash attend une commande de premier plan, le signal attend ; le builtin `wait`, lui, est interrompu. (b) Ctrl-C va à tout le **groupe de processus** du terminal (le `sleep` de premier plan le reçoit directement) ; `kill` à un seul PID ne touche pas les enfants. (c) les tâches d'arrière-plan d'un script non interactif **ignorent SIGINT** : d'où le mode « propre » qui les tue explicitement.

*2. `timeout`.* Codes : `124` si le délai est atteint (`SIGTERM` envoyé), `137` si il a fallu `SIGKILL` (`--kill-after`), sinon le code de la commande. Par défaut `timeout` met la commande dans **son propre groupe** et lui relaie les signaux qu'il reçoit ; `--foreground` la laisse dans le groupe courant (utile quand on veut qu'un Ctrl-C du clavier l'atteigne directement). Pour une commande qui crée elle-même des enfants, c'est à elle de les propager.

*3. Python, observation.* De [`ressources/M02-E30/demo_sous_processus.py`](../ressources/M02-E30/demo_sous_processus.py) :
- **cas 1** : `subprocess.run(..., shell=True, timeout=2)` lève `TimeoutExpired` et tue le **shell**, mais le petit-enfant (`sleep 301` lancé par ce shell) survit : Python ne tue que le processus qu'il a directement créé.
- **cas 2** : `start_new_session=True` place l'enfant dans une nouvelle session (donc un nouveau groupe) ; `os.killpg(proc.pid, SIGTERM)` tue tout le groupe, petit-enfant compris. Aucun orphelin.
- **cas 3** : un SIGTERM reçu par un programme Python sans gestionnaire termine l'interpréteur **sans** lever d'exception : le bloc `finally` ne s'exécute pas. Pour `medictl` arrêté par `systemctl stop` au milieu d'une création de VM, cela signifie qu'un nettoyage écrit dans un `finally` serait sauté.
- **cas 4** : un gestionnaire de SIGTERM qui lève `SystemExit` rend le signal « propre » : le `finally` s'exécute, le code de sortie est `143`.

*4. L'outil* : [`fichiers/M02-E30/bin/ms-attendre`](fichiers/M02-E30/bin/ms-attendre). Points de conception :
- chaque essai est lancé **en arrière-plan** (`timeout --kill-after=5 "$duree" "$@" & wait "$!"`) pour que le `trap` s'exécute immédiatement, et non après la fin de l'essai ;
- la durée d'un essai est le minimum de `--essai` et du temps restant sur le délai total : le délai total est tenu même si un essai bloque ;
- `trap 'arreter SIGINT 130' INT` / `'arreter SIGTERM 143' TERM` : `arreter` tue l'essai en cours (`kill -TERM "$_pid_essai"`, que `timeout` relaie à la commande), attend, puis sort avec le bon code ; aucun orphelin ;
- l'en-tête explique pourquoi `retry` (E10) ne suffisait pas : `retry` borne le **nombre** d'essais, pas la **durée**, et un essai bloqué (SSH sans réponse) le bloque indéfiniment.

*5. Les tests, en Python* : [`tests/python/test_ms_attendre.py`](fichiers/M02-E30/tests/python/test_ms_attendre.py). `pytest` pilote l'outil par `subprocess` : succès immédiat, délai total dépassé, essai bloqué tué, usage ; puis, pour SIGTERM **et** SIGINT (paramétré), l'outil est lancé dans une nouvelle session, on lui donne une signature unique (`sleep 47.25`), on lui envoie le signal, et on vérifie le code de sortie, le délai de réaction (< 3 s) et l'**absence d'orphelin** (parcours de `/proc`). Le `finally` du test tue le groupe en cas d'échec. Avec les règles `S` (bandit) du `pyproject.toml`, ruff signale les deux appels à `subprocess` (S603, « exécution d'une entrée non maîtrisée ») : ici, le programme lancé est celui du dépôt et ses arguments sont écrits dans le test ; on le justifie par un `# noqa: S603` commenté sur chaque appel, plutôt que de désactiver S603 pour tous les tests.

*6. Utilisation.*

```
admin@adm01:~$ medictl vm create m02-attente --vmid 2028 --template 9000 --vnet vsandbox --tags env-m02 --no-wait
admin@adm01:~$ ms-attendre -d 300 -i 5 -- ssh -o BatchMode=yes -o ConnectTimeout=5 admin@<IP-VM> true
2026-10-04T10:12:07+02:00 ms-attendre[4120] INFO réussite à l'essai 7 après 41 s
admin@adm01:~$ medictl vm destroy 2028 --yes
```

**Explications**

Trois mécanismes se combinent. (1) La **livraison** d'un signal : Ctrl-C va au groupe de processus de premier plan du terminal, `kill` à un PID, `killpg` à un groupe ; un processus lancé en arrière-plan par un script non interactif a SIGINT **ignoré** à l'hérédité. (2) Le **moment** où un gestionnaire s'exécute : en Bash, entre deux commandes, sauf `wait` qui est interruptible ; en Python, seulement si le signal est traduit en exception par un gestionnaire. (3) La **propagation** : tuer un processus ne tue pas ses enfants ; il faut une session/un groupe (`start_new_session`, `setsid`) et `killpg`, ou tuer explicitement les enfants. `timeout` encapsule (1) et (3) pour une commande externe ; pour du code maison, on les gère soi-même.

**Alternatives**
- `systemd-run --scope --property=TimeoutStopSec=… ` pour exécuter sous le contrôle de systemd, qui gère proprement l'arbre de processus (`KillMode=control-group`).
- En Python, `subprocess.run(timeout=…)` tue le processus direct ; pour l'arbre, `start_new_session=True` + `os.killpg`, ou le groupe de processus de `Popen`.
- `asyncio` avec `asyncio.wait_for` pour de nombreuses attentes concurrentes (au-delà du besoin ici).

**Pièges classiques**
- Attendre une commande **au premier plan** et s'étonner que le Ctrl-C ne soit traité qu'à la fin.
- Tuer le `timeout`/le shell sans tuer ses enfants : orphelins.
- Croire qu'un `finally` Python s'exécute sur SIGTERM sans gestionnaire (cas 3).
- `trap … INT` dans un script qui lance des tâches d'arrière-plan, sans les tuer : elles survivent.
- Boucler sur `--essai` sans borner le total : un enchaînement d'essais lents dépasse le délai annoncé.

**En production chez MédiSphère**
Les attentes (démarrage de VM, disponibilité d'un service) sont bornées et journalisées ; les services ont `TimeoutStartSec`/`TimeoutStopSec` et un `KillMode` adapté pour ne pas laisser d'orphelins au `systemctl stop` ; le code qui doit nettoyer sur arrêt installe un gestionnaire de SIGTERM (ou un `trap`), vérifié par un test, car un arrêt propre au milieu d'une opération fait partie du fonctionnement normal (déploiement, mise à l'échelle, éviction d'un pod au module 14).

---

### M02-E31 — Documenter un outil : aide, README, guide d'astreinte

**Démarche de référence**

Livrables : [`fichiers/M02-E31/README.md`](fichiers/M02-E31/README.md) (projet) et [`fichiers/M02-E31/docs/astreinte.md`](fichiers/M02-E31/docs/astreinte.md), plus l'aide harmonisée de chaque outil.

- **Trois supports, trois lecteurs.** L'**aide intégrée** (`--help`) répond à « comment j'appelle cet outil, maintenant » : usage, options, codes retour, configuration, un exemple ; sur la sortie standard, code 0 ; une erreur d'usage écrit l'aide sur la sortie d'erreur et rend 2. Le **README** répond au nouvel arrivant : ce que fait le projet, comment l'installer et contribuer. Le **guide d'astreinte** répond à la personne réveillée à 3 h : par symptôme, pas par architecture. Ne pas tout mettre partout : le guide renvoie à l'aide, le README renvoie aux ADR.
- **Harmoniser l'aide** : même ordre de sections dans tous les `ms-*` et dans `medictl --help`. Les codes retour y figurent (0/1/2/3), car l'astreinte les lit la nuit. Le guide d'astreinte et le `Documentation=` de l'unité systemd pointent vers le même fichier.
- **Du mode de défaillance à la procédure** : chaque panne rencontrée en écrivant les outils (droits d'un jeton, certificat, environnement de systemd, verrou, liste vide) devient une entrée « symptôme → causes probables → vérification » du guide. Le palier 4 (pannes E35-E43) en ajoutera ; le guide est fait pour grossir.
- **Test par un tiers** : le critère d'un bon guide est qu'une personne qui n'a pas écrit l'outil résolve le scénario (« alerte à 07:31, cause inconnue ») sans appeler l'auteur. Note ce qui a bloqué et corrige : c'est la seule vraie mesure.

**Grille d'auto-évaluation** (0-2 par ligne) : (1) tous les outils ont une aide harmonisée citant leurs codes retour ; (2) le README permet d'installer et contribuer sans autre source ; (3) le guide couvre l'alerte de contrôle des sauvegardes (vraie absence **et** contrôle en panne), `ms-snapshot` avant intervention, `medictl` en échec, l'escalade ; (4) chaque entrée du guide donne des commandes exactes, pas des généralités ; (5) le guide dit ce qu'il ne faut **pas** faire (contourner un garde-fou, élargir un jeton) ; (6) le scénario de relecture par un tiers est documenté. Cible : ≥ 10/12, et (3) non nul.

**En production chez MédiSphère** : documentation versionnée avec le code (une MR qui change un comportement change l'aide et le guide), relue comme du code ; les guides d'astreinte sont reliés aux alertes (chaque alerte porte un lien vers sa procédure, module 21) ; une revue périodique vérifie que les procédures correspondent encore à la réalité (exercice d'astreinte, M00-E37, final F3).

---

### M02-E32 — ADR : langages des outils de la plateforme

**Démarche de référence**

Livrable : [`fichiers/M02-E32/ADR-0020-langages-outils-plateforme.md`](fichiers/M02-E32/ADR-0020-langages-outils-plateforme.md) (à placer dans `docs/socle/adr/` de `plateforme/medisphere`). Le cœur d'un bon ADR ici n'est pas « Bash ou Python » mais des **critères applicables en revue** : un relecteur de MR doit pouvoir dire, sans débat, si un nouvel outil est dans le bon langage.

Critères retenus (exemple) — Bash si **toutes** ces conditions tiennent : l'outil enchaîne surtout des commandes système ; moins de ~200 lignes hors commentaires ; au plus une API simple (via `lib/ms-commun.sh`) ; données en lignes de texte ou JSON traité par quelques filtres `jq`. Sinon Python. Et, dans tous les cas : ce qui configure durablement des hôtes n'est **pas** un script (Ansible, module 04 ; OpenTofu, module 05). Exigences communes aux deux langages : mode strict, analyse statique sans avertissement (ShellCheck/ruff), tests (bats/pytest), contrat de codes retour 0/1/2/3, `--help`, publication par semantic-release.

Teste les critères sur des cas réels : `ms-snapshot` (surtout des appels d'API, de la logique de rotation, des structures de données → **Python** serait défendable ; reste en Bash car la logique tient en filtres `jq` et il orchestre `qm`/l'API — cas limite à surveiller), `ms-verif-sauvegardes` (deux API, agrégation, décision → proche de la limite), `medictl` (API, types, garde-fous, tests fins → **Python**, évident), `ms-diag` (enchaîne `systemctl`/`journalctl`/`tar` → **Bash**, évident). Un critère qui ne tranche pas ces cas est à revoir.

L'ADR présente au moins quatre options (tout Bash, tout Python, mixte avec critères, Go) avec pour/contre, retient le mixte, et écrit ses conséquences négatives (deux chaînes d'outillage, zone grise en revue, coût de réécriture quand un script franchit la limite) avec les actions compensatoires (revue annuelle de `bin/`, formation Python de l'astreinte, reprise des gestes de configuration par Ansible).

**Grille d'auto-évaluation** (0-2) : (1) gabarit MADR de M00-E33 respecté, ≤ 2 pages ; (2) ≥ 4 options avec pour/contre ; (3) critères réellement applicables (testés sur 3 outils existants + 1 imaginaire sans hésitation) ; (4) frontière avec Ansible/OpenTofu explicite ; (5) conséquences négatives et actions induites écrites ; (6) décision reliée aux contraintes métier (compétences de l'équipe, astreinte, sécurité). Cible : ≥ 10/12.

**En production chez MédiSphère** : l'ADR est relu en MR par Karim et la RSSI, sa date de révision est fixée (réexamen quand l'équipe gagne une compétence — Go — ou quand un besoin nouveau apparaît — un opérateur Kubernetes, bloc C) ; les critères sont rappelés dans le `CONTRIBUTING.md` du projet pour être appliqués sans rouvrir l'ADR à chaque MR.

---

### M02-E33 — Questions de production : outillage d'exploitation

**1. Confusion de dépendances — réponse b (avec la configuration retenue).** Avec la stratégie par défaut `first-index` de uv, un paquet est résolu dans le **premier** index qui le propose : `medictl` étant dans le registre interne (déclaré en premier), uv n'ira pas chercher une version plus haute ailleurs. **Mais** cette protection côté uv ne vaut que si l'index interne ne redirige pas lui-même : si la redirection de GitLab vers pypi.org est active, c'est **GitLab** qui, ne trouvant pas un nom, le sert depuis pypi.org — et uv reçoit alors un paquet d'origine publique en croyant parler au registre interne. D'où la double protection : `first-index` **et** redirection coupée. Pour les **dépendances** (`typer`, `requests`), c'est plus subtil : elles viennent légitimement de pypi.org ; le risque est qu'un nom interne futur soit « pré-publié » publiquement. Réponse d) est juste sur le principe (tout dépend de la stratégie et de la réponse du registre), mais en configuration retenue, b) décrit le comportement. a) et c) sont faux.

**2. Contrainte vs verrou.** `uv tool install medictl` lit les **contraintes** du paquet (`typer>=0.27.2`), pas le `uv.lock` du projet : le lock ne voyage pas dans la roue, il ne sert qu'au développement et à la CI du projet. Conséquence : deux installations à des dates différentes peuvent résoudre des versions de dépendances différentes — l'outil installé n'est pas reproductible à l'octet près. Parades : publier avec des bornes hautes (`typer>=0.27,<0.28`) ; ou distribuer un environnement figé (image de conteneur, module 12) ; ou `uv tool install --constraints` avec un fichier de contraintes publié ; ou vendoriser. En pratique pour un outil interne, des bornes raisonnables et des tests sur la version installée suffisent.

**3. SemVer d'une CLI — majeure, `feat!` ou `fix!` avec un pied de page `BREAKING CHANGE:`.** Renommer un champ d'une sortie `--format json` consommée par des scripts casse le contrat : c'est une rupture, donc une version **majeure** (ex. 1.x → 2.0.0). L'« API publique » d'une CLI, au sens SemVer, comprend : les noms et le comportement des commandes et options, le format des sorties destinées aux machines (`--format json`, codes retour), les noms des variables d'environnement et fichiers de configuration lus. Les messages lisibles par un humain et les détails internes n'en font pas partie. Leçon : un champ JSON est un contrat ; le renommer se planifie (ajouter le nouveau, déprécier l'ancien, puis le retirer à une majeure).

**4. Publication depuis un poste.** Trois raisons : (a) traçabilité — on ne sait plus qui a publié quoi, avec quel code exactement (un poste a des modifications locales) ; (b) sécurité — il faut un secret de publication durable sur un poste, au lieu d'un jeton de job éphémère ; (c) reproductibilité — « ça marche sur ma machine » : versions d'outils, environnement, `uv.lock` non garantis. À la place : réparer la CI, ou disposer d'un runner de secours ; en dernier recours, une publication manuelle est un **incident** documenté, avec un jeton à usage unique immédiatement révoqué.

**5. Cron vs systemd — réponse b.** On perd sûrement le **rattrapage** d'une exécution manquée (`Persistent=true`) et la **journalisation structurée par exécution** (identifiant d'invocation, `Result=`). a) est faux (cron sait faire 07:30), c) faux (cron lance aussi en `admin`), d) faux (le réseau ne dépend pas de cron). On perd **en plus** : le crochet `OnFailure=` (donc l'alerte), le durcissement (`ProtectHome`, `ProtectSystem`, `NoNewPrivileges`…), les dépendances (`After=network-online.target`), le délai maximal (`TimeoutStartSec`). Cron enverrait un mail à `root@localhost` en cas de sortie non vide — c'est précisément l'angle mort de M00-E29.

**6. Exposition d'un secret.** En **argument** : visible par tout utilisateur de la machine dans `ps`/`/proc/<pid>/cmdline`, dans l'historique du shell, dans un `set -x`, souvent journalisé. En **variable d'environnement** : visible dans `/proc/<pid>/environ` (propriétaire et root), héritée par les enfants, parfois affichée par un `env` de débogage — mieux, mais pas confidentiel vis-à-vis du même utilisateur et de root. En **fichier 600** : lisible seulement par son propriétaire (et root), non hérité, non journalisé ; c'est pourquoi les secrets du workbook vivent dans `~/.config/workbook/*.env` en 600, et que l'en-tête d'authentification passe par `curl -K -` (fichier de configuration sur l'entrée standard) plutôt que par `-H`.

**7. Jeton en lecture, danger.** Oui. (a) Un jeton `read_api` GitLab ou `Datastore.Audit` PBS **lit** des informations sensibles : configurations cloud-init (clés publiques, parfois secrets injectés), inventaire complet, noms et tailles de sauvegardes — utile à un attaquant pour préparer la suite. (b) La lecture peut coûter : une requête de liste très large, répétée, est un déni de service sur `pveproxy` (peu de *workers*). Un jeton de lecture se protège, s'expire et se révoque comme un autre.

**8. `set -e` qui n'arrête pas.** Trois situations classiques : (a) une commande dans une condition (`if cmd; then`, `cmd && …`, `cmd || …`, `!`) — son échec est « consommé » ; (b) une commande qui n'est pas la **dernière** d'un tube, sauf `set -o pipefail` (`faux | vrai` réussit) ; (c) une commande dans une substitution `$( )` dont on n'utilise pas le code, ou une fonction appelée dans un contexte où `set -e` est suspendu (condition, `&&`). Parades dans `plateforme/outils` : `set -euo pipefail` partout ; `pve_api`/`pve_wait_task` renvoient un code testé explicitement (`x="$(pve_api …)" || die …`) ; `retry` documente qu'il suspend `set -e` pour la commande qu'il relance. La panne M02-E39 est bâtie là-dessus.

**9. 200 VMs.** Ni séquentiel (200 × latence : des minutes), ni 200 threads (on assomme `pveproxy`, qui a peu de *workers*, et on prend la place des humains). ~10-20 appels concurrents est un bon compromis : la latence est masquée, le serveur tient. À surveiller : les verrous côté serveur (pas deux écritures sur la même VM), le partage de l'API avec d'autres outils (laisser de la marge), la reprise avec délai exponentiel sur 5xx et erreurs réseau seulement (E17) — pas sur un 4xx, qui ne s'améliorera pas en réessayant. Mesurer, ajuster.

**10. Threads vs processus — réponse b.** 200 appels HTTP sont **limités par les entrées-sorties** : les threads conviennent, et le GIL est relâché pendant l'attente réseau. Les processus (a) coûteraient en mémoire et en sérialisation sans gain. `asyncio` (c) est une option valable à grande échelle, pas une nécessité ici. Un `requests.Session` **n'est pas** garanti thread-safe pour un partage entre threads : on utilise une session par thread (ou `urllib3`/`httpx` avec un pool), sinon on s'expose à des connexions mélangées.

**11. Runner partagé.** Risques entre projets sur un runner `shell` au même compte : fichiers et caches laissés par un job et lus par un autre (secrets dans un `.env` oublié, `~/.cache`), variables d'environnement qui fuient, et surtout un job de MR venant d'un contributeur moins privilégié qui exécute du code arbitraire **avec les droits du runner** (donc l'accès réseau et les éventuels secrets du runner). Mesures immédiates : variables sensibles **protégées** (seulement sur branches protégées, hors MR de forks), `git clean` entre jobs (défaut), pas de secret d'infrastructure sur ce runner, nettoyage des répertoires de build. Les exécuteurs Docker/Kubernetes (modules 12 et 19) donnent à chaque job un environnement jetable et isolé : c'est la vraie réponse.

**12. `CI_JOB_TOKEN` vs jeton stocké.** Le jeton de job est **éphémère** (créé au début du job, invalidé à sa fin), **lié au job** (droits de l'utilisateur déclencheur, restreints à ce que les jobs peuvent faire), et n'a pas à être stocké ni renouvelé. Un jeton de déploiement en variable CI est durable : s'il fuite (journal, runner compromis), il reste exploitable jusqu'à expiration ou révocation manuelle. Pour publier dans le registre de **son** projet, `CI_JOB_TOKEN` suffit : moins de secret, moins de surface.

**13. D'où lancer le contrôle.** Pas depuis `pve01` : on y ajouterait un script et un jeton, et un `pve01` **éteint** (ou en panne) ne signalerait pas que ses VMs ne sont plus sauvegardées — le contrôle disparaîtrait avec ce qu'il surveille. Pas depuis `pbs01` : il ne connaît pas les étiquettes des VMs (il ne sait pas ce qui **devrait** être sauvegardé), et un PBS en panne ne se signalerait pas lui-même. `adm01` est un **tiers** qui observe les deux et dont la panne est, elle, visible (c'est le poste d'où travaille l'équipe). Principe : un contrôle ne doit pas partager le domaine de panne de ce qu'il contrôle.

**14. Métriques d'un outil d'exploitation.** Oui. Pour `ms-verif-sauvegardes` : âge de la dernière sauvegarde par VM (jauge), nombre de VMs en défaut, horodatage et succès de la dernière exécution. Pour `ms-snapshot` : nombre d'instantanés par VM, âge du plus ancien, durée de l'opération. Sans serveur : le **collecteur de fichiers texte** de node_exporter (écrire un fichier `.prom` dans un répertoire que node_exporter expose, module 21) ; en attendant node_exporter, un simple fichier d'état horodaté qu'un contrôle de second niveau peut lire. L'important : une donnée exploitée (alerte, tableau de bord), pas un journal que personne ne lit.

**15. Reprendre un script InfoGér critique.** Démarche par étapes, du moins risqué au plus : (1) **figer et comprendre** — le mettre sous Git, écrire ce qu'il fait réellement (pas ce qu'on croit), le passer à ShellCheck ; (2) **filet de sécurité** — des tests de caractérisation (bats) qui capturent le comportement actuel, même imparfait, pour détecter toute régression ; (3) **sécuriser le geste destructeur** — un `--dry-run`, des garde-fous, avant de toucher à la logique ; (4) **décider de la cible** : une purge de journaux sur 30 serveurs est un geste de **configuration récurrent** → sa place est dans **Ansible** (module 04 : `find`/`logrotate` idempotents, `--check`, limites, rapports), pas dans un script Bash lancé à la main. Réécrire en Python n'aurait de sens que si c'était un programme (logique, données), ce que ce n'est pas. Risque principal : remplacer d'un coup sans filet ; d'où les tests de caractérisation d'abord, puis une bascule progressive (un groupe de serveurs, puis le reste), l'ancien script gardé en secours le temps d'une fenêtre.

---

### M02-E34 — Un script de vérification en temps limité

**Solution de référence** : [`fichiers/M02-E34/bin/ms-verif-socle`](fichiers/M02-E34/bin/ms-verif-socle) et ses tests [`tests/bats/ms-verif-socle.bats`](fichiers/M02-E34/tests/bats/ms-verif-socle.bats). Cahier des charges : [`ressources/M02-E34/cahier-des-charges.md`](../ressources/M02-E34/cahier-des-charges.md).

L'épreuve n'évalue pas une trouvaille, mais la capacité à livrer, en 90 minutes et sous contrainte, un outil conforme au contrat du module : interface stricte, codes retour fiables, sorties lisibles par un humain et par une machine, tests sans réseau, ShellCheck propre. La bibliothèque commune (E10) et les outils déjà écrits (E26, E28, E34 partage avec `ms-etat-hotes`) sont censés faire gagner l'essentiel du temps : qui a investi dans `lib/ms-commun.sh` et dans des tests réutilisables finit l'épreuve ; qui repart de zéro ne finit pas.

Architecture retenue : une fonction par **accès au monde extérieur** (`ip_alias` via `ssh -G`, `resoudre_a`/`resoudre_ptr` via `dig @10.10.20.10`, `executer_distant` via `ssh`, `port_ouvert`, `tester_tls` via `openssl s_client -verify_return_error -verify_hostname`), chacune remplaçable dans les tests ; une fonction `verifier_hote` qui produit les cinq lignes `HOTE<TAB>CONTROLE<TAB>ETAT<TAB>DETAIL` ; `main` qui boucle, agrège, et sort en 0/1 selon la présence d'un `KO` (les `NA` ne comptent pas). Le mode `--json` passe les lignes TSV dans `jq -R -s` pour produire le tableau d'objets. Les contrôles :
- `dns` : `<hote>.par1.medisphere.internal` résout via 10.10.20.10 vers l'adresse de l'alias SSH (cohérence nom↔alias), et le PTR commence par `<hote>.` ;
- `ssh` : `ssh -n -o BatchMode=yes -o ConnectTimeout=5` ; si elle échoue, `temps` et `disque` sont `KO` (non vérifiables) ;
- `temps` : `chronyc -n tracking`, `Leap status : Normal` et écart `System time` < 0,5 s ;
- `disque` : occupation de `/` < 85 % ;
- `tls` : port 443 fermé → `NA` ; sinon chaîne et nom valides et validité restante ≥ 30 jours (`openssl x509 -checkend`).

Tests bats (6, sans réseau) : les fonctions d'accès sont redéfinies dans `setup` (socle sain, un hôte injoignable, disque plein, certificat expirant) ; on vérifie le code retour, l'ordre des contrôles, le `NA` d'un hôte sans 443, la validité du JSON, et le refus d'un nom d'hôte ou d'une option invalides.

Déroulé typique tenu en 90 min : squelette et interface (15 min) → un contrôle de bout en bout sur un hôte (20 min) → les cinq contrôles (25 min) → `--json` (10 min) → tests bats (15 min) → ShellCheck et commit (5 min). Ce qui fait déraper, d'expérience : l'analyse de `chronyc tracking` (format), l'épinglage mental du TLS (quel hôte a 443 : `git01` oui, `gw01` non), et les tabulations dans les comparaisons bats.

**Grille d'auto-évaluation** (le check fait foi, mais pour le retour d'expérience) : interface et codes conformes ; les cinq contrôles présents et justes ; sortie TSV **et** JSON ; au moins trois tests bats sans réseau ; ShellCheck `-x` propre ; durée < 60 s ; tenu en 90 min. Si ce n'est pas tenu : noter ce qui a manqué (souvent : pas assez de briques réutilisables), améliorer la bibliothèque, refaire l'épreuve une semaine plus tard — c'est le but.

**En production chez MédiSphère** : ce contrôle de santé devient une sonde de supervision (le JSON alimente une cible Prometheus, module 21) et un test de pré-astreinte (on le lance avant de prendre le quart). L'épreuve chronométrée elle-même est un entraînement pour les scénarios d'astreinte du final F3 : savoir produire vite un outil de diagnostic fiable, sous pression, fait partie du métier.
