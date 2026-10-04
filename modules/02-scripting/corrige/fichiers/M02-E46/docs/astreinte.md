# Guide d'astreinte — outillage `plateforme/outils` (v1)

Public : la personne d'astreinte, de nuit, sans l'auteur des outils sous la main.
Règle : un outil qui échoue le dit **clairement** (code ≠ 0, message en clair) ; s'il ne le dit
pas, c'est un bogue à remonter (ticket `INC-`, étiquette `outils`).

Version v1 : guide de M02-E31 complété par les incidents du palier 4 (INC-2841 à INC-2850).
Chaque section renvoie au journal de diagnostic correspondant dans `docs/socle/journal/` de
`plateforme/medisphere`.

## 1. Réflexes communs

| Code retour | Signification | Premier geste |
|---|---|---|
| 0 | succès | — |
| 1 | erreur d'exécution (réseau, API, droits, tâche Proxmox) | lire le message, puis le journal |
| 2 | usage (option, argument) | `<outil> --help` |
| 3 | refus d'un garde-fou (VM hors pool `lab`, zone non marquée, autre exécution en cours…) | **ne pas contourner** : comprendre pourquoi |
| 130 / 143 | interrompu (Ctrl-C / arrêt) | relancer la même commande : les outils sont idempotents |

- Journaux des services : `journalctl -u <unité> -n 50 --no-pager` ; alertes : `journalctl -t ms-alerte -p crit`.
- Configuration **effective** d'une unité (fichier + drop-ins) : `systemctl cat <unité>` ; valeurs
  appliquées : `systemctl show <unité> -p User,ExecStart,Environment,ProtectHome`.
- Droits d'un jeton Proxmox : `root@pve01:~# pveum user token permissions wb-automation@pve <jeton> --path /pool/lab`.
- Version installée : `medictl --version`, `uv tool list` ; scripts : `ls -l /usr/local/bin/ms-*`
  et notes de version dans les Releases GitLab de `plateforme/outils`.
- Ne jamais lire ni recopier un secret dans un ticket ou un canal : on cite le **fichier** et ses droits.

## 2. Alerte « ÉCHEC ms-verif-sauvegardes.service »

**Ce que ça veut dire** : à 07:30, au moins une VM du socle n'avait pas de sauvegarde PBS de
moins de 26 h valable, **ou** le contrôle n'a pas pu se faire. Les deux sont graves.

1. Lire le rapport : `journalctl -u ms-verif-sauvegardes -n 40 --no-pager`.
   - `KO (trop ancienne)` / `aucune sauvegarde` : la sauvegarde `lab-nuit` a échoué ou n'a pas
     tourné → runbook **RB-004 « sauvegarde en échec »** (`plateforme/medisphere`).
   - `vérification en échec` : instantané corrompu → prévenir Karim ; ne **pas** élaguer le groupe.
   - tout autre message (`illisible`, `aucune VM … visible`, `API … injoignable`, `refus`,
     `public key does not match`) : c'est le **contrôle** qui est cassé → section 3.
2. Rejouer **dans les conditions du service**, jamais seulement dans ton terminal :
   `sudo systemctl start ms-verif-sauvegardes.service; systemctl status ms-verif-sauvegardes --no-pager`.
3. Vérifier à la main que les sauvegardes existent (interface de `pbs01`, namespace `par1`) pour
   borner l'impact, puis communiquer.

## 3. Le contrôle lui-même est en panne

| Symptôme | Causes probables | Vérification |
|---|---|---|
| `fichier de configuration illisible : /home/…` | drop-in `ProtectHome=yes` (ou `tmpfs`) | `systemctl show -p ProtectHome` ; attendu `read-only` |
| `fichier de configuration illisible : /root/…` | drop-in `User=root` (le `HOME` change) | `systemctl show -p User` ; attendu `admin` |
| `API … injoignable`, `Failed to connect to 10.10.20.250 port 3128` | proxy imposé par `Environment=` sans exemption des API internes | `systemctl show -p Environment` ; `no_proxy` doit couvrir l'adresse de `pve01` et 10.20.10.10 |
| sortie au format inattendu (`KO  VM …`), `403` | `ExecStart` redirigé vers une vieille copie (`override.conf`) | `systemctl cat` ; `ExecStart=/usr/local/bin/ms-verif-sauvegardes` attendu |
| `aucune VM du pool lab … visible` | jeton `!lecture` sans `VM.Audit`, **ou ACL de l'utilisateur** `wb-automation@pve` retirée (droits du jeton = intersection), étiquettes retirées | `pveum user token permissions wb-automation@pve lecture --path /pool/lab` ; `pveum acl list` |
| `API PBS … 401` | jeton PBS expiré ou révoqué | `proxmox-backup-manager user list-tokens wb-verif@pbs` |
| `public key does not match pinned public key` | certificat de `pbs01` renouvelé | recalculer l'épingle (M02-E26) **après** vérification de l'empreinte sur la console de `pbs01` |

Pour reproduire exactement l'environnement du service avec une seule propriété changée :
`sudo systemd-run --wait --pipe --collect -p User=admin -p ProtectHome=read-only /usr/local/bin/ms-verif-sauvegardes`.

Ne jamais « réparer » en donnant au jeton de lecture des droits d'écriture, ni en lançant le
contrôle en root : signaler à Sophie Laurent (RSSI) tout besoin de droit supplémentaire.

## 4. Alerte « ÉCHEC ms-verif-fraicheur.service » (le contrôle ne tourne plus)

**Ce que ça veut dire** : le contrôle des sauvegardes n'a pas tourné, ou pas réussi, depuis plus
de 26 h. Aucune alerte d'échec n'a pu partir : il n'a pas échoué, il n'a pas eu lieu.

| Constat (`systemctl list-timers --all ms-verif-sauvegardes.timer`, `systemctl status …timer`) | Cause | Remède |
|---|---|---|
| `NEXT` vide, timer `inactive (dead)` | timer arrêté à chaud | `sudo systemctl start …timer` ; chercher qui l'a arrêté (`journalctl -u …timer`, `journalctl _COMM=sudo`) |
| `Loaded: bad-setting` | `OnCalendar` invalide dans un drop-in | `systemd-analyze calendar '<expression>'`, corriger ou retirer le drop-in, `daemon-reload` |
| `NEXT` dans plusieurs jours | planification modifiée (`Mon *-*-* …`) | `systemctl cat …timer`, revenir à `*-*-* 07:30:00` |
| timer sain, service « start condition unmet » | `ConditionPathExists=` ou autre condition jamais remplie (gel oublié) | `systemctl status ms-verif-sauvegardes.service` ; lever le gel **avec** son demandeur |

Après correction : `sudo systemctl start ms-verif-sauvegardes.service`, puis
`/usr/local/bin/ms-verif-fraicheur ms-verif-sauvegardes.timer` doit répondre 0.

## 5. `ms-snapshot` avant une intervention

- Toujours : `ms-snapshot --dry-run <VMID>…` d'abord, lire le plan, puis la même commande sans
  `--dry-run`.
- `VM verrouillée (snapshot|backup)` : une tâche est en cours (sauvegarde nocturne ?) ou a été
  interrompue. Ne déverrouiller (`qm unlock`) qu'après s'être assuré qu'aucune tâche ne tourne.
- `déjà en cours d'exécution` (code 3) : quelqu'un d'autre l'utilise, ou un processus lancé par une
  exécution précédente garde le verrou (`fuser -v ~/.local/state/ms-outils/verrous/*`).
- `hors pool lab` sur **toutes** les VMs : ce n'est pas la VM, ce sont les droits (section 6).
- Interrompu : relancer la même commande ; un instantané de moins de 30 min est réutilisé.

## 6. `medictl` ne parle plus à Proxmox

Remonter la chaîne dans l'ordre, une preuve par maillon (`medictl -vv vm list` donne la classe
d'erreur) :

| Maillon | Symptôme | Vérification | Remède |
|---|---|---|---|
| TLS | `certificate verify failed` | `openssl s_client -connect <IP-PVE01>:8006 -CAfile ~/.config/workbook/pve-root-ca.pem` | recopier `/etc/pve/pve-root-ca.pem` de `pve01` (par SSH) dans `PVE_CACERT` |
| authentification | `401` | `pveum user token list wb-automation@pve` (expiration), `pveum user list` (compte actif) | prolonger ou renouveler le jeton (≤ 1 an), réactiver le compte **avec** Sophie |
| autorisation | liste **vide** sans erreur, `403`, refus « hors pool » | `pveum user token permissions wb-automation@pve lab --path /pool/lab` | ACL de l'utilisateur **et** du jeton sur `/pool/lab` (`WBAutomation`) |

- `refus` (code 3) : VMID hors des plages 2000-2999 / 5000-5999 ou hors pool `lab`. C'est voulu.

## 7. `medictl` ou les tests plantent avec une erreur Python

Ne rien réinstaller avant d'avoir identifié **quel** `medictl` et **quel** Python sont appelés :

```
type -a medictl ; head -n 1 "$(command -v medictl)" ; ls -l "$(command -v medictl)"
uv tool list ; uv tool dir
python3 -c 'import importlib.util as u; print(u.find_spec("medictl"))'      # doit afficher None
cd ~/src/outils && uv run --no-sync python -c 'import medictl, sys; print(medictl.__file__); print(sys.path)'
```

| Constat | Cause | Remède |
|---|---|---|
| `cannot execute: required file not found` | l'interpréteur de l'environnement de l'outil a disparu | `uv tool install --force --reinstall medictl --index outils=<URL>` |
| `medictl 0.1.0`, lanceur `#!/usr/bin/python3` | vieux paquet installé par `pip --user` | archiver puis retirer `~/.local/lib/python3.13/site-packages/medictl*`, réinstaller l'outil |
| `ModuleNotFoundError` dans `.venv` alors que `uv pip show` voit le paquet | fichiers supprimés, métadonnées restées | `uv sync --locked --reinstall-package <paquet>` (ou recréer `.venv`) |
| `medictl.__file__` hors de `src/` | fichier `.pth` étranger dans `.venv` | retirer le `.pth`, recréer `.venv` |

`.venv` est jetable : `rm -rf .venv && uv sync --locked` le reconstruit à l'identique. On ne
fait **jamais** `pip install --break-system-packages`, ni le « ménage » de `~/.local/share/uv` à la main.

## 8. Pipeline rouge, « mais ça marche chez moi »

1. Lire le job en échec : quelle tâche, quelle commande, quel message.
2. Reproduire **comme la CI** : clone propre, `task ci` (les tâches utilisent `--locked`), pas
   `uv run pytest` dans une copie de travail.
3. Chercher ce qui diffère : verrou `uv.lock` non mis à jour, test qui lit `~/.config` ou appelle
   le vrai Proxmox, outil présent sur `adm01` mais pas sur `runner01`, variable CI héritée du
   groupe (Paramètres CI/CD du projet → variables héritées).
4. Corriger dans le dépôt (verrou, test, script d'installation de `runner01`), jamais en
   désactivant un job ou en ajoutant `allow_failure`.

## 9. Scripts qui suppriment ou déplacent des données

`ms-purge-rapports`, `ms-archiver-journaux` et tout futur script destructeur :

- en cas de doute sur ce qu'un passage a supprimé : **arrêter** le timer ou la tâche qui le
  relance, avant toute autre action ;
- comparer l'état avec la dernière sauvegarde (`tar -tzvf`), restaurer dans un dossier à part,
  puis remettre en place en conservant les dates (`tar`, `cp -a`, `rsync -a`) ;
- ne jamais essayer un correctif sur les vraies données : jeu de test (`fabriquer-donnees.sh`,
  `fabriquer-spool.sh`) et `--dry-run` d'abord.

## 10. Escalade

| Situation | Qui |
|---|---|
| Sauvegardes absentes depuis plus de 48 h, restauration nécessaire | Claire Morel (décision) + Karim Benali |
| Droits, jetons, secrets exposés ; journaux de sécurité perdus | Sophie Laurent (RSSI) — immédiatement |
| Bogue d'un outil | ticket `INC-` dans `plateforme/outils`, étiquette `outils` |
| Incident à plusieurs causes, ou P2 de plus de 2 h | Nadia Roussel (pilotage, communication) |

Après chaque incident : une ligne dans `docs/socle/journal/` de `plateforme/medisphere`, un
post-mortem pour toute P1/P2, et ce guide mis à jour si une étape manquait.
