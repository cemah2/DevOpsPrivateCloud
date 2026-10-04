# plateforme/outils

Outillage d'exploitation de l'équipe Plateforme MédiSphère : scripts Bash `ms-*` pour les gestes
système, et CLI Python `medictl` pour l'API Proxmox VE du lab.

> Astreinte : commence par [docs/astreinte.md](docs/astreinte.md).

## Ce que contient le projet

| Outil | Rôle | Écrit ? | Lancé par |
|---|---|---|---|
| `medictl` | Inventaire, création et destruction de VMs du pool `lab` (VMID 2000-2999, 5000-5999) | oui (garde-fous) | humain |
| `ms-snapshot` | Point de retour avant intervention, rotation des instantanés | oui | humain, avant un changement |
| `ms-verif-sauvegardes` | Vérifie qu'une sauvegarde PBS de moins de 26 h existe pour chaque VM du socle | non | timer systemd, 07:30 |
| `ms-etat-hotes` | Relevé rapide (noyau, démarrage, disque, mises à jour) des hôtes du socle | non | humain |
| `ms-attendre` | Relance une commande jusqu'au succès, dans un délai borné | selon la commande | scripts |
| `ms-diag` | Archive de diagnostic d'un service, pour le support | non (root, via sudo) | astreinte |
| `lib/ms-commun.sh` | Journalisation, garde-fous, accès API commun aux scripts Bash | — | — |

Contrat commun à tous les outils :

- **codes retour** : `0` succès, `1` erreur, `2` usage, `3` refus d'un garde-fou ; `130`/`143`
  interrompu (Ctrl-C, arrêt) ;
- **sorties** : les données sur la sortie standard (exploitables par `jq`, `cut`), les journaux sur
  la sortie d'erreur, horodatés ;
- **aide** : `<outil> --help` décrit l'usage, les options, les codes retour et la configuration ;
- **secrets** : jamais en argument ni dans le dépôt ; fichiers `~/.config/workbook/*.env` en mode 600.

## Installation

### Poste d'administration (`adm01`) — version publiée

```
admin@adm01:~$ uv tool install medictl --index outils=https://git01.par1.medisphere.internal/api/v4/projects/<ID-PROJET>/packages/pypi/simple
admin@adm01:~$ medictl --version
admin@adm01:~$ uv tool upgrade medictl          # mise à jour vers la dernière version publiée
```

Prérequis : jeton de déploiement en lecture du registre enregistré par `uv auth login`, et
`system-certs = true` dans `~/.config/uv/uv.toml` (PKI interne). Détails : M02-E25.

Scripts planifiés : `task install:systeme` (copie, par `sudo`, dans `/usr/local/bin` et
`/usr/local/lib`, jamais de lien vers un clone de travail), puis unités systemd de `systemd/`.
Pas de `task install` sur ce poste : il installerait aussi `medictl` depuis le clone, à la place
de la version publiée (réservé au développement).

### Développement

```
admin@adm01:~$ git clone git@git01.par1.medisphere.internal:plateforme/outils.git ~/src/outils
admin@adm01:~$ cd ~/src/outils && pre-commit install && task setup
admin@adm01:~$ task lint test        # comme la CI
```

Outils attendus : uv, ShellCheck 0.11, shfmt 3.14, bats-core 1.13, Task 3.x, jq.

## Configuration

| Fichier | Contenu | Utilisé par |
|---|---|---|
| `~/.config/workbook/pve-api.env` | jeton `wb-automation@pve!lab` (écriture, pool `lab`) | `medictl`, `ms-snapshot` |
| `~/.config/workbook/pve-lecture.env` | jeton `wb-automation@pve!lecture` (PVEAuditor) | `ms-verif-sauvegardes` |
| `~/.config/workbook/pbs-lecture.env` | jeton PBS `wb-verif@pbs!lecture` (DatastoreAudit) + épingle TLS | `ms-verif-sauvegardes` |
| `/etc/ms-alerte.env` (root, 600) | `MS_ALERTE_WEBHOOK` facultatif | `ms-alerte@.service` |

Variables : `MS_PVE_ENV_FILE` (fichier d'accès de `pve_api`), `MS_YES=1` (confirmation non
interactive assumée), `MEDICTL_ENV_FILE`, `MS_VERIF_AGE_MAX_H`.

## Contribuer

Branche courte, Conventional Commits, MR vers `main` (voir `CONTRIBUTING.md`). La CI (`shellcheck`,
`ruff`, `bats`, `pytest`, `build`) doit être verte ; la version est publiée par semantic-release
à la fusion. Aucun test ne doit joindre le vrai Proxmox.

Décisions : [ADR-0020 — langages des outils](https://git01.par1.medisphere.internal/plateforme/medisphere/-/blob/main/docs/socle/adr/ADR-0020-langages-outils-plateforme.md).
Responsable : équipe Plateforme (Karim Benali).
