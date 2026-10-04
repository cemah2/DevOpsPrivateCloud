# Guide d'astreinte — outillage `plateforme/outils`

Public : la personne d'astreinte, de nuit, sans l'auteur des outils sous la main.
Règle : un outil qui échoue le dit **clairement** (code ≠ 0, message en clair) ; s'il ne le dit
pas, c'est un bogue à remonter (ticket `INC-`, étiquette `outils`).

## 1. Réflexes communs

| Code retour | Signification | Premier geste |
|---|---|---|
| 0 | succès | — |
| 1 | erreur d'exécution (réseau, API, droits, tâche Proxmox) | lire le message, puis le journal |
| 2 | usage (option, argument) | `<outil> --help` |
| 3 | refus d'un garde-fou (VM hors pool `lab`, autre exécution en cours…) | **ne pas contourner** : comprendre pourquoi |
| 130 / 143 | interrompu (Ctrl-C / arrêt) | relancer la même commande : les outils sont idempotents |

- Journaux des services : `journalctl -u <unité> -n 50 --no-pager` ; alertes : `journalctl -t ms-alerte -p crit`.
- Droits d'un jeton Proxmox : `root@pve01:~# pveum user token permissions wb-automation@pve <jeton>`.
- Version installée : `medictl --version`, `head -n 3 /usr/local/bin/ms-verif-sauvegardes`, tâches et
  dates d'installation dans le CHANGELOG des Releases GitLab de `plateforme/outils`.

## 2. Alerte « ÉCHEC ms-verif-sauvegardes.service »

**Ce que ça veut dire** : à 07:30, au moins une VM du socle n'avait pas de sauvegarde PBS de
moins de 26 h valable, **ou** le contrôle n'a pas pu se faire. Les deux sont graves : on ne sait
plus si on sait restaurer.

1. Lire le rapport : `journalctl -u ms-verif-sauvegardes -n 40 --no-pager`.
   - Lignes `KO (trop ancienne)` / `aucune sauvegarde` : la sauvegarde nocturne `lab-nuit` a
     échoué ou n'a pas tourné → runbook **RB-004 « sauvegarde en échec »** (`plateforme/medisphere`).
   - `vérification en échec` : un instantané est corrompu → prévenir Karim, lancer une
     vérification manuelle sur `pbs01`, ne **pas** élaguer (prune) le groupe concerné.
   - `aucune VM … visible`, `API … injoignable`, `refus`, `chmod 600` : c'est le **contrôle**
     qui est cassé, pas forcément les sauvegardes → section 3.
2. Rejouer le contrôle à la main **dans les conditions du service** :
   `sudo systemctl start ms-verif-sauvegardes.service; systemctl status ms-verif-sauvegardes --no-pager`.
   Le lancer seulement en `admin` dans un terminal ne prouve rien (environnement différent).
3. Une fois la sauvegarde refaite (`vzdump` de la VM vers `pbs-par2`), rejouer le contrôle :
   le service doit repasser en succès.

## 3. Le contrôle lui-même est en panne

| Symptôme | Causes probables | Vérification |
|---|---|---|
| `aucune VM du pool lab avec l'étiquette « socle »` | jeton `!lecture` sans `VM.Audit` sur `/pool/lab`, étiquettes retirées | `pveum user token permissions wb-automation@pve lecture --path /pool/lab` ; `qm config <VMID> \| grep tags` |
| `API PBS … 401` | jeton PBS expiré ou révoqué | `proxmox-backup-manager user list-tokens wb-verif@pbs` sur `pbs01` |
| `public key does not match pinned public key` | certificat de `pbs01` renouvelé | recalculer l'épingle (procédure M02-E26) **après** avoir vérifié l'empreinte sur la console de `pbs01` |
| `fichier de configuration illisible` / `chmod 600` | `HOME` différent (service lancé en root ?), droits modifiés | `systemctl cat ms-verif-sauvegardes` (User=, drop-ins), `ls -l ~/.config/workbook/` |
| timer jamais déclenché | timer arrêté, drop-in invalide, condition non remplie | `systemctl list-timers ms-verif-sauvegardes.timer`, `systemctl status ms-verif-sauvegardes.timer`, `systemctl cat …` |

Ne jamais « réparer » en donnant au jeton de lecture des droits d'écriture : signaler à Sophie
Laurent (RSSI) tout besoin de droit supplémentaire.

## 4. `ms-snapshot` avant une intervention

- Toujours : `ms-snapshot --dry-run <VMID>…` d'abord, lire le plan, puis la même commande sans
  `--dry-run`.
- `VM verrouillée (snapshot|backup)` : une tâche est en cours (sauvegarde nocturne ?) ou a été
  interrompue. Vérifier les tâches de la VM dans l'interface ; ne déverrouiller (`qm unlock`)
  qu'après s'être assuré qu'aucune tâche ne tourne.
- `déjà en cours d'exécution` (code 3) : quelqu'un d'autre l'utilise ; attendre.
- Interrompu : relancer la même commande ; un instantané de moins de 30 min est réutilisé.

## 5. `medictl`

- `refus` (code 3) : VMID hors des plages 2000-2999 / 5000-5999 ou hors pool `lab`. C'est voulu.
- Erreur TLS : `PVE_CACERT` absent ou périmé (`~/.config/workbook/pve-root-ca.pem`).
- Après une mise à jour qui casse : revenir à la version précédente
  `uv tool install --force medictl==<VERSION> --index outils=<URL>` puis ouvrir un ticket.

## 6. Escalade

| Situation | Qui |
|---|---|
| Sauvegardes absentes depuis plus de 48 h, restauration nécessaire | Claire Morel (décision) + Karim Benali |
| Droits, jetons, secrets exposés | Sophie Laurent (RSSI) — immédiatement |
| Bogue d'un outil | ticket `INC-` dans `plateforme/outils`, étiquette `outils` |

Après chaque incident : une ligne dans `docs/socle/journal/` de `plateforme/medisphere`, et ce
guide mis à jour si une étape manquait.
