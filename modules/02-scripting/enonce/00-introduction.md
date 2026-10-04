# Module 02 — Introduction : scripting d'automatisation

## Le projet « outils »

Lundi matin, après la livraison de la forge. Un mail de Karim t'attend.

> **De** : Karim Benali — Ingénieur plateforme senior
> **À** : toi
> **Cc** : Claire Morel, Nadia Roussel, Sophie Laurent
> **Objet** : On range les scripts — projet `plateforme/outils`
>
> Salut,
>
> Bravo pour la forge. Maintenant qu'on a GitLab, la CI et les releases, je veux qu'on arrête de vivre avec des scripts qui traînent dans des `~/lab-scripts`, des `/usr/local/sbin` et des pièces jointes d'InfoGér. Personne ne sait lequel est le bon, aucun n'est testé, et la moitié échoue en silence.
>
> On ouvre le projet **`plateforme/outils`**. Tout outil d'exploitation de l'équipe y vit, passe en revue, est testé en CI et sort en version. Deux familles :
> - des scripts **Bash** pour les gestes système (`bin/ms-*`), avec une bibliothèque commune ;
> - une CLI **Python**, `medictl`, qui parle à l'API Proxmox pour l'inventaire et le cycle de vie des VMs du lab.
>
> Mes règles : ShellCheck à zéro, tests automatiques, jamais de secret dans le code ni dans les journaux, TLS **vérifié** partout. Nadia a la sienne, je la cite : « un outil d'astreinte échoue bruyamment et clairement, jamais à moitié et en silence ». Sophie relira tout ce qui touche aux jetons.
>
> On commence par un test de positionnement, comme d'habitude.
> Karim

---

## Ce que tu construis dans ce module

À la fin du module 02 :

- le projet **`plateforme/outils`** existe sur `git01`, configuré comme tous les projets de la plateforme (M01) : `main` protégée, pre-commit, pipeline de qualité obligatoire, versions publiées par semantic-release ;
- des scripts Bash robustes (`bin/ms-*`) s'appuient sur une **bibliothèque commune** `lib/ms-commun.sh` (journalisation, garde-fous, appels à l'API Proxmox) et passent ShellCheck, shfmt et des tests **bats** ;
- la CLI **`medictl`** (Typer + proxmoxer) liste, décrit, crée et détruit les VMs jetables du lab avec des garde-fous, est testée avec **pytest** sans jamais toucher au vrai Proxmox, puis est publiée dans le **registre de paquets** de GitLab et installée sur `adm01` ;
- la CI du projet tourne sur `runner01` (lint, tests, construction, release) ;
- un **contrôle planifié** (timer systemd) vérifie chaque matin que les VMs du socle ont une sauvegarde récente ;
- la documentation (README, guide d'astreinte, ADR-0020) et l'inventaire du socle régénéré depuis l'API.

## Architecture du module

```
                  ┌──────────────────────── git01 (1004) · 10.10.20.12 ──────────────────────┐
                  │ GitLab CE — projet plateforme/outils                                       │
  push / MR (SSH) │  main protégée · pipeline obligatoire · releases vX.Y.Z (semantic-release) │
 ┌───────────────►│  registre de paquets PyPI du projet : medictl (E25)                        │
 │                └───────────────┬───────────────────────────────────────────────────────────┘
 │                                │ jobs (étiquette « shell »)
 │                ┌───────────────▼──────── runner01 (1007) · 10.10.20.15 ────────────────────┐
 │                │ exécuteur shell : shellcheck, shfmt, bats, uv (ruff, pytest), task (E24)   │
 │                │ les tests n'appellent JAMAIS le vrai Proxmox                               │
 │                └────────────────────────────────────────────────────────────────────────────┘
┌┴──────────────────────────── adm01 (1001) · 10.10.10.10 ───────────────┐
│ ~/src/outils      copie de travail du projet (versionnée)               │   API REST, TCP 8006, TLS vérifié
│ ~/m02/eXX/        brouillons et données des exercices (non versionnés)  │ ───────────────────────────────► pve01
│ outils : shellcheck, shfmt, jq, yq, uv, task, bats (/usr/local/bin)     │   jeton wb-automation@pve!lab
│ medictl installé depuis le registre (E25)                               │   (+ jeton en lecture seule, E26)
│ ~/.config/workbook/   secrets (700, fichiers 600)                       │
│ timer systemd ms-verif-sauvegardes (E26)                                │ ───────────────────────────────► pbs01
└─────────────────────────────────────────────────────────────────────────┘   (contrôle des sauvegardes)

  VMs jetables du module : VMID 2020-2029, noms « m02-… », pool lab, VNet vsandbox (DHCP), étiquette env-m02
```

Aucun nouveau flux réseau n'est nécessaire : `adm01` (VLAN MGMT) joint déjà `pve01` (8006), `git01` (22, 443) et PAR2 depuis le module 00 ; `runner01` et `git01` sont dans le même VLAN.

### Le projet `plateforme/outils`

Arborescence visée en fin de module (chaque exercice indique ce qu'il ajoute) :

```
outils/
├── .gitlab-ci.yml            gabarits qualite.yml + release.yml (E02), jobs du projet (E24)
├── .pre-commit-config.yaml   configuration standard M01 + shellcheck, shfmt (E04) + ruff (E07)
├── .shellcheckrc             règles ShellCheck du projet (E04)
├── .editorconfig             style commun, lu aussi par shfmt (E04)
├── .releaserc.json, commitlint.config.mjs, CONTRIBUTING.md, .gitlab/   standard M01 (E02)
├── Taskfile.yml              tâches lint, test, build, install (E20) ; Makefile équivalent pour comparaison
├── bin/                      scripts Bash exécutables, préfixe ms- (E03, E11, E26…)
├── lib/
│   ├── ms-commun.sh          bibliothèque Bash commune (E10)
│   └── jq/                   filtres jq réutilisables (E05)
├── systemd/                  unités du contrôle planifié (E26)
├── tests/
│   ├── bats/                 tests des scripts Bash (E14)
│   └── python/               tests de medictl (E18)
├── pyproject.toml, uv.lock, .python-version   projet Python géré par uv (E07)
├── src/medictl/              CLI Python (E07, E08, E15-E19, E21)
└── docs/                     README, guide d'astreinte (E31)
```

### Conventions communes à tous les outils

Elles sont fixées dès maintenant ; les vérifications et les exercices suivants en dépendent.

| Convention | Règle |
|---|---|
| Codes retour | `0` succès · `1` erreur · `2` erreur d'usage (arguments) · `3` refus d'un garde-fou |
| Sorties | Résultat sur la sortie standard (exploitable par un autre programme) ; messages, avertissements et erreurs sur la sortie d'erreur |
| Aide | `-h` / `--help` sur chaque outil, qui commence par une ligne `Usage : …` |
| Secrets | Jamais en argument de ligne de commande, jamais dans le dépôt, jamais dans les journaux. Fichiers dans `~/.config/workbook/` (dossier 700, fichiers 600) ; en CI, variables protégées et masquées |
| TLS | Toujours vérifié. Désactiver la vérification (`curl -k`, `verify=False`) est interdit, même « en attendant » |
| Noms | Scripts Bash : `bin/ms-<verbe-ou-objet>` sans extension ; CLI Python : `medictl <objet> <action>` |
| VMs créées par les outils | VMID 2020-2029 (exercices) ou 5000-5999 (sandbox), pool `lab`, jamais le socle (1000-1099) ni les templates (9000-9099) |

### Où travailler

| Emplacement | Contenu | Versionné ? |
|---|---|---|
| `~/src/outils` | Copie de travail de `plateforme/outils` (variable `WB_SRC` = `~/src`) | oui, via MR |
| `~/m02/eXX/` | Brouillons, fichiers fournis à modifier, résultats d'exercices hors projet (ex. `~/m02/e04/`) | non |
| `~/DevOpsPrivateCloud/modules/02-scripting/ressources/` | Fichiers fournis par le workbook (scripts à relire, réponses d'API enregistrées) | — (lecture seule) |
| `~/.config/workbook/` | Secrets : `pve-api.env` (M00-E17), jetons GitLab (M01), autres fichiers d'accès créés dans ce module | jamais |

### Variables de `lab/lab.env` utiles dans ce module

Rien de nouveau à renseigner si tu as suivi le module 01 ; vérifie simplement ces valeurs.

| Variable | Défaut | Rôle |
|---|---|---|
| `WB_SRC` | `$HOME/src` | Dossier des copies de travail : les vérifications cherchent `$WB_SRC/outils` |
| `WB_GITLAB_URL` | `https://git01.par1.medisphere.internal` | URL de GitLab |
| `WB_GITLAB_TOKEN_FILE` | `~/.config/workbook/gitlab-checks.token` | Jeton en lecture (`read_api`) utilisé par les vérifications |
| `WB_GITLAB_ADMIN_TOKEN_FILE` | `~/.config/workbook/gitlab-admin.token` | Jeton d'administration : scripts de ressources et de panne |
| `WB_PVE_HOST` | `pve01` | Alias SSH de l'hyperviseur (vérifications) |

---

## Préparer `adm01` : les outils du module

Tu installes ici, une fois, les outils en ligne de commande du module. Ils serviront jusqu'à la fin du workbook. `runner01` recevra les mêmes, aux mêmes versions, en M02-E24.

### Versions et provenance

| Outil | Version | Provenance | Emplacement | Contrôle d'intégrité |
|---|---|---|---|---|
| ShellCheck | 0.11.0 | dépôt Debian `trixie-backports` (Debian 13 livre la 0.10) | `/usr/bin` | signature du dépôt APT |
| shfmt | 3.14.1 | binaire de la release officielle (`mvdan/sh`) | `/usr/local/bin` | empreinte SHA-256 affichée sur la page de la release |
| jq | 1.8.2 | binaire de la release officielle (`jqlang/jq`) ; Debian 13 livre la 1.7.1 | `/usr/local/bin` | fichier `sha256sum.txt` de la release |
| yq | 4.54.1 | binaire de la release officielle (`mikefarah/yq`) | `/usr/local/bin` | fichiers `checksums` et `checksums_hashes_order` |
| uv, uvx | 0.12.23 | archive de la release officielle (`astral-sh/uv`) | `/usr/local/bin` | fichier `.sha256` de l'archive |
| Task | 3.54.0 | archive de la release officielle (`go-task/task`) | `/usr/local/bin` | fichier `task_checksums.txt` |
| bats-core | 1.13.0 | archive de l'étiquette `v1.13.0` (`bats-core/bats-core`) | `/opt/bats`, lien dans `/usr/local/bin` | aucune empreinte publiée : note la tienne |

Ce sont les derniers correctifs des versions de référence (PLAN.md §6) au moment de la rédaction. Une version de correctif plus récente (`3.14.2`, `0.12.24`…) convient : adapte les numéros, et note-les dans ton journal.

> ⚠️ **Attention : deux outils s'appellent `yq`.** Le paquet Debian `yq` est un programme Python (kislyuk) à la syntaxe différente, qui n'est **pas** celui du workbook. Ne l'installe pas ; s'il est présent (`dpkg -l yq`), retire-le (`sudo apt remove yq`). Même vigilance pour `jq` : après installation, le binaire de `/usr/local/bin` passe devant celui de Debian (`/usr/bin/jq`) dans le `PATH` ; vérifie avec `type -a jq`.

Pourquoi `/usr/local/bin` et pas `~/.local/bin` ? Les outils doivent être disponibles pour tous les comptes et pour les services systemd, dont le `PATH` ne contient pas `~/.local/bin`. Tu retrouveras cette question en palier 3 et 4.

### ShellCheck 0.11 depuis les rétroportages Debian

Les images *cloud* de Debian activent souvent déjà `trixie-backports`. Regarde d'abord :

```
admin@adm01:~$ apt-cache policy shellcheck
```

Si aucune ligne `trixie-backports` n'apparaît, déclare le dépôt. Reprends pour `Signed-By` **exactement** le trousseau (noté `<TROUSSEAU-DEBIAN>` ci-dessous) qu'utilise déjà ton fichier `/etc/apt/sources.list.d/debian.sources` (son nom dépend de la version du paquet `debian-archive-keyring`) :

```
admin@adm01:~$ grep -h Signed-By /etc/apt/sources.list.d/*.sources | sort -u
Signed-By: <TROUSSEAU-DEBIAN>
admin@adm01:~$ sudo tee /etc/apt/sources.list.d/debian-backports.sources >/dev/null <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main
Signed-By: <TROUSSEAU-DEBIAN>
EOF
admin@adm01:~$ sudo apt update
```

Puis installe la version rétroportée (les rétroportages ne sont jamais installés sans `-t` ; une fois installés, ils sont mis à jour normalement) :

```
admin@adm01:~$ sudo apt install -t trixie-backports shellcheck
admin@adm01:~$ shellcheck --version
ShellCheck - shell script analysis tool
version: 0.11.0
…
```

### Binaires des releases officielles : la méthode

Pour chaque binaire : téléchargement dans un dossier temporaire, **vérification de l'empreinte avant toute exécution**, installation par `install` (propriétaire root, mode 755). Ne colle jamais un `curl … | sh` sans avoir lu ce qu'il exécute.

```
admin@adm01:~$ cd "$(mktemp -d)"
```

**jq 1.8.2**

```
admin@adm01:/tmp/tmp.Xy$ curl -fLO https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64
admin@adm01:/tmp/tmp.Xy$ curl -fLO https://github.com/jqlang/jq/releases/download/jq-1.8.2/sha256sum.txt
admin@adm01:/tmp/tmp.Xy$ sha256sum --check --ignore-missing sha256sum.txt
jq-linux-amd64: OK
admin@adm01:/tmp/tmp.Xy$ sudo install -m 755 jq-linux-amd64 /usr/local/bin/jq
```

**yq 4.54.1** (le fichier `checksums` contient plusieurs algorithmes par ligne ; le script fourni par le projet extrait la colonne SHA-256)

```
admin@adm01:/tmp/tmp.Xy$ base=https://github.com/mikefarah/yq/releases/download/v4.54.1
admin@adm01:/tmp/tmp.Xy$ for f in yq_linux_amd64 checksums checksums_hashes_order extract-checksum.sh; do curl -fLO "$base/$f"; done
admin@adm01:/tmp/tmp.Xy$ bash extract-checksum.sh SHA-256 yq_linux_amd64 | awk '{ print $2 "  " $1 }' | sha256sum -c -
yq_linux_amd64: OK
admin@adm01:/tmp/tmp.Xy$ sudo install -m 755 yq_linux_amd64 /usr/local/bin/yq
```

**shfmt 3.14.1** (le projet ne publie plus de fichier d'empreintes : GitHub affiche l'empreinte `sha256:…` de chaque fichier sur la page de la release)

```
admin@adm01:/tmp/tmp.Xy$ curl -fLO https://github.com/mvdan/sh/releases/download/v3.14.1/shfmt_v3.14.1_linux_amd64
admin@adm01:/tmp/tmp.Xy$ sha256sum shfmt_v3.14.1_linux_amd64
<EMPREINTE>  shfmt_v3.14.1_linux_amd64
admin@adm01:/tmp/tmp.Xy$ sudo install -m 755 shfmt_v3.14.1_linux_amd64 /usr/local/bin/shfmt
```

`<EMPREINTE>` doit être **identique** à celle affichée sur <https://github.com/mvdan/sh/releases/tag/v3.14.1> pour ce fichier. Sinon, tu n'installes pas.

**uv 0.12.23**

```
admin@adm01:/tmp/tmp.Xy$ base=https://github.com/astral-sh/uv/releases/download/0.12.23
admin@adm01:/tmp/tmp.Xy$ curl -fLO "$base/uv-x86_64-unknown-linux-gnu.tar.gz"
admin@adm01:/tmp/tmp.Xy$ curl -fLO "$base/uv-x86_64-unknown-linux-gnu.tar.gz.sha256"
admin@adm01:/tmp/tmp.Xy$ sha256sum -c uv-x86_64-unknown-linux-gnu.tar.gz.sha256
uv-x86_64-unknown-linux-gnu.tar.gz: OK
admin@adm01:/tmp/tmp.Xy$ tar -xzf uv-x86_64-unknown-linux-gnu.tar.gz
admin@adm01:/tmp/tmp.Xy$ sudo install -m 755 uv-x86_64-unknown-linux-gnu/uv uv-x86_64-unknown-linux-gnu/uvx /usr/local/bin/
```

Si tu avais déjà un `uv` (installé au module 01 pour pre-commit, par exemple dans `~/.local/bin`), `type -a uv` en montre plusieurs : garde-en **un seul**, celui de `/usr/local/bin`, et vérifie que les outils installés avec `uv tool install` (pre-commit) fonctionnent toujours (`pre-commit --version`).

**Task 3.54.0**

```
admin@adm01:/tmp/tmp.Xy$ base=https://github.com/go-task/task/releases/download/v3.54.0
admin@adm01:/tmp/tmp.Xy$ curl -fLO "$base/task_linux_amd64.tar.gz"
admin@adm01:/tmp/tmp.Xy$ curl -fLO "$base/task_checksums.txt"
admin@adm01:/tmp/tmp.Xy$ sha256sum --check --ignore-missing task_checksums.txt
task_linux_amd64.tar.gz: OK
admin@adm01:/tmp/tmp.Xy$ tar -xzf task_linux_amd64.tar.gz task
admin@adm01:/tmp/tmp.Xy$ sudo install -m 755 task /usr/local/bin/task
```

**bats-core 1.13.0** (aucune empreinte n'est publiée : calcule celle de l'archive, note-la dans ton journal, et compare-la si tu réinstalles un jour ; c'est ce que fera `runner01` en E24)

```
admin@adm01:/tmp/tmp.Xy$ curl -fL -o bats-core-1.13.0.tar.gz https://github.com/bats-core/bats-core/archive/refs/tags/v1.13.0.tar.gz
admin@adm01:/tmp/tmp.Xy$ sha256sum bats-core-1.13.0.tar.gz
admin@adm01:/tmp/tmp.Xy$ tar -xzf bats-core-1.13.0.tar.gz
admin@adm01:/tmp/tmp.Xy$ sudo bats-core-1.13.0/install.sh /opt/bats
admin@adm01:/tmp/tmp.Xy$ sudo ln -sf /opt/bats/bin/bats /usr/local/bin/bats
```

Les bibliothèques d'assertions de bats (`bats-support`, `bats-assert`) viendront avec les tests, en E14.

### Contrôle

```
admin@adm01:~$ hash -r
admin@adm01:~$ for o in shellcheck shfmt jq yq uv task bats; do printf '%-10s %s\n' "$o" "$(command -v "$o")"; done
admin@adm01:~$ shellcheck --version | sed -n 2p; shfmt --version; jq --version; yq --version; uv --version; task --version; bats --version
```

Chaque outil doit répondre depuis l'emplacement prévu, à la version prévue. Les vérifications des exercices E04 à E07 le contrôlent. Note les versions et les empreintes dans ton journal : c'est la première page du futur rôle Ansible qui installera ces outils (module 04).

---

## Concepts clés

Une synthèse pour se repérer, pas un cours : les exercices et les liens « Pour aller plus loin » approfondissent.

**Bash pour les gestes système, Python pour les programmes.** Bash excelle à enchaîner des commandes, des tubes et des fichiers ; il devient fragile dès qu'il manipule des structures de données, des erreurs fines ou des API. Python apporte des types, des exceptions, des bibliothèques (HTTP, JSON, TLS) et des tests confortables, au prix d'un environnement à gérer. L'exercice E09 et l'ADR-0020 (E32) formalisent le choix.

**Le mode strict n'est pas une assurance.** `set -euo pipefail` arrête un script sur la plupart des erreurs, mais `set -e` est volontairement inactif dans de nombreux contextes (conditions, `&&`/`||`, substitutions passées en argument, `local x=$(…)`). Un script robuste vérifie explicitement ce qui compte, nettoie derrière lui (`trap … EXIT`), n'expose jamais un fichier à moitié écrit, et sort avec un code qui veut dire quelque chose.

**L'analyse statique d'abord.** ShellCheck trouve en une seconde la moitié des bogues classiques du shell (guillemets, `cd` sans contrôle, boucles sur `ls`, `$?` testé trop tard). shfmt met fin aux discussions de style. ruff fait les deux pour Python. Ils tournent dans l'éditeur, dans pre-commit et en CI, **à la même version**.

**JSON et YAML se modifient avec des outils qui les comprennent.** `jq` (JSON) et `yq` (YAML) interrogent et transforment des documents structurés. `sed` sur du YAML, c'est jouer à la roulette avec l'indentation, les types implicites (`no`, `3.10`, `0640`) et les commentaires.

**Un projet Python moderne est déclaratif et verrouillé.** `pyproject.toml` décrit le projet et ses dépendances ; `uv.lock` fige les versions exactes et leurs empreintes ; `.venv/` est jetable et se reconstruit à l'identique (`uv sync --locked`). On n'installe jamais rien avec `pip` dans le Python du système : Debian 13 l'interdit d'ailleurs (PEP 668).

**Parler à une API, c'est gérer l'échec.** Délais maximaux, codes HTTP, tâches asynchrones (UPID), reprises limitées aux erreurs transitoires, secrets hors des arguments et des journaux, certificat vérifié contre la bonne autorité. `medictl` le fait une fois pour toutes, proprement, pour l'équipe.

**Tester sans casser.** bats exécute des scripts Bash dans un environnement contrôlé ; pytest et une API simulée (`responses`) testent `medictl` sans Proxmox. Un test qui a besoin du vrai lab n'a pas sa place en CI.

**Un outil s'exploite.** Version, aide, documentation, guide d'astreinte, exécution planifiée supervisée, distribution reproductible : c'est ce qui sépare un script d'un outil d'équipe.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 02 <XX>`. Elles cherchent le projet dans `$WB_SRC/outils` et les fichiers d'exercice dans `~/m02/eXX/`. Certaines **exécutent tes scripts** dans des dossiers temporaires pour observer leur comportement (codes retour, sorties) ; elles ne modifient rien d'autre.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Même quand ta vérification est verte, lis « Pièges classiques ».
- Les scripts de panne (`corrige/pannes/`) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─┬─ E05 ─ E06 ──────────┐
                       └─ E07 ─ E08 ─ E09 ────┴─ palier 2 : E10 (lib Bash) … E15 (medictl) …
```

1. **E01** — positionnement, à froid, avant de lire la suite.
2. **E02** — le projet doit exister avant d'y mettre quoi que ce soit.
3. **E03 → E04** — un premier script robuste, puis les outils qui le gardent propre.
4. **E05, E06** — JSON et YAML ; indépendants de la branche Python.
5. **E07 → E08** — l'environnement Python, puis le premier client de l'API.
6. **E09** — à faire en dernier : il demande d'avoir pratiqué les deux langages.

Durée indicative du palier 1 : 15 à 18 heures.

## Pour aller plus loin

- Manuel de GNU Bash : <https://www.gnu.org/software/bash/manual/>
- Wiki de ShellCheck (une page par code) : <https://www.shellcheck.net/wiki/>
- *BashFAQ* et *BashPitfalls* : <https://mywiki.wooledge.org/BashPitfalls>
- Manuel de jq : <https://jqlang.org/manual/>
- Documentation de yq : <https://mikefarah.gitbook.io/yq/>
- Documentation de uv : <https://docs.astral.sh/uv/>
- Typer : <https://typer.tiangolo.com/> · proxmoxer : <https://proxmoxer.github.io/docs/>
- API Proxmox VE : <https://pve.proxmox.com/pve-docs/api-viewer/>
