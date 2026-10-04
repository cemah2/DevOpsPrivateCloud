# Module 02 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les fichiers complets sont dans [`fichiers/`](fichiers/). Organisation :

| Dossier | Contenu |
|---|---|
| `M02-E10/lib/ms-commun.sh` | bibliothèque, version E10 |
| `M02-E11/bin/ms-snapshot` | `ms-snapshot`, version E11 (sans verrou) |
| `M02-E12/bin/ms-ranger` | rangement par mois avec manifeste |
| `M02-E13/` | bibliothèque avec `lock_or_die`, `ms-export-config`, `ms-snapshot` avec verrou |
| `M02-E14/tests/bats/` | tests bats, faux `curl`, données de test |
| `M02-E15/src/medictl/` | `cli.py` et `sortie.py` de E15 (le reste vient de E07 et E08) |
| `M02-E20/outils/` | **le projet complet à la fin de E20** : bibliothèque, scripts, `medictl` (E15 à E19), tests, `pyproject.toml`, `uv.lock`, `Taskfile.yml`, `Makefile`, configurations de E02/E04 |
| `M02-E21/` | ce qu'ajoute E21 : `inventaire.py`, `cli.py` complet, `test_inventaire.py` |
| `M02-E22/ms-collecte-etc` | version corrigée du script de Lucas |
| `M02-E23/rapport_capacite.py` | version corrigée du rapport de capacité |

Les exercices E16 à E19 font évoluer le même paquet : leurs corrigés renvoient aux fichiers de `M02-E20/outils/src/medictl/` et indiquent ce que chaque exercice y ajoute. Tout le code fourni a été exécuté : `shellcheck` (0.11, avec le `.shellcheckrc` du projet) et `shfmt -d` muets, 60 tests bats et 104 tests pytest (113 avec E21) verts, `ruff check` et `ruff format --check` muets, `uv build` réussi — **sans** Proxmox réel. Les points qui n'ont pas pu être confrontés au vrai lab sont signalés « ⚠️ À vérifier sur ta version ».

---

### M02-E10 — Bibliothèque Bash commune `lib/ms-commun.sh`

**Solution**

Fichier complet : [`fichiers/M02-E10/lib/ms-commun.sh`](fichiers/M02-E10/lib/ms-commun.sh). Ses choix structurants :

1. **Bibliothèque, pas programme.**
   ```bash
   if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
     echo "ms-commun.sh est une bibliothèque : charge-la avec « source », ne l'exécute pas." >&2
     exit 2
   fi
   if [[ -n "${_MS_COMMUN_CHARGEE:-}" ]]; then return 0; fi
   _MS_COMMUN_CHARGEE=1
   ```
   Pas de `set -euo pipefail` : c'est au script de choisir ses options. Une bibliothèque qui les impose change le comportement de code qu'elle ne connaît pas (un `grep` sans résultat devient fatal dans un script qui ne s'y attendait pas).

2. **Journal** : `printf '%s %s[%d] %s %s\n' "$(date -Iseconds)" "$MS_PROG" "$$" NIVEAU "$*" >&2`, niveaux `INFO`, `AVERT`, `ERREUR`. Exemple :
   ```
   2026-10-04T10:15:02+02:00 ms-snapshot[48121] INFO 2020 (m02-cobaye) : création de l'instantané avant-20261004-101502
   ```

3. **`die`** journalise puis `exit "${2:-1}"`. Réponse à l'expérience de l'étape 2 : dans `x="$(die oups)"`, `die` ne quitte **que le sous-shell** ; l'affectation prend son code (1), et `set -e` arrête alors le script. Avec `local x="$(die oups)"`, le code testé est celui de `local` (0) : le script continue avec `x` vide. D'où la règle : déclarer, puis affecter (`local x; x="$(…)"`), ou tester explicitement (`x="$(…)" || exit $?`).

4. **`confirm`** refuse sans terminal (`[[ -t 0 ]]`), sauf `MS_YES=1` (journalisé) ; `read -r -p` affiche la question sur stderr.

5. **`retry`** : délai doublé, seul le nom de la commande est journalisé (ses arguments peuvent contenir un secret). L'expérience de l'étape 3 donne `n=0` avec une version naïve qui déclare `local n=1` pour compter ses essais : la fonction `f` incrémente le `n` **local de `retry`** (portée dynamique de Bash), qui croit alors avoir fait plus d'essais qu'en réalité, et le `n` de l'appelant ne bouge pas. Correction : noms préfixés.
   ```bash
   local _ms_max="$1" _ms_delai="$2" _ms_essai=1 _ms_rc=0
   ```
   (Ce piège a été rencontré en écrivant ce corrigé : c'est la vérification de E10 qui l'a révélé.)

6. **`pve_api`** :
   ```bash
   reponse="$(curl "${args[@]}" \
     -H @<(printf 'Authorization: PVEAPIToken=%s=%s\n' "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET") \
     "${PVE_API_URL%/}${chemin}")" || rc=$?
   local statut="${reponse%%$'\r'*}" corps="${reponse#*$'\r\n\r\n'}"
   read -r _version code motif <<<"$statut"
   ```
   - `args` contient `--silent --show-error --include --suppress-connect-headers --max-time 30 -X MÉTHODE`, `--cacert "$PVE_CACERT"` si défini, `--get` pour GET et DELETE, et un `--data-urlencode clé=valeur` par paramètre.
   - `printf` est une commande interne : le secret n'apparaît dans aucun `argv` ; `<(…)` est un descripteur (`/dev/fd/63`), pas un fichier sur disque.
   - `--include` place la ligne de statut et les en-têtes avant le corps : le **motif** que Proxmox écrit dans la ligne de statut est restitué tel quel. Le champ `errors` des réponses 400 est ajouté au message.
   - Chargement du fichier d'accès : `${MS_PVE_ENV_FILE:-~/.config/workbook/pve-api.env}`, refusé si `mode & 077` ; les `PVE_*` déjà définies dans l'environnement sont sauvegardées avant le `source` puis restaurées (priorité à l'environnement). `PVE_API_URL` doit commencer par `https://`.
   - Sortie : `jq -c '.data'`.
   ```
   admin@adm01:~/src/outils$ bash -c 'source lib/ms-commun.sh; pve_api GET /version'
   {"release":"9.0","repoid":"…","version":"9.0.10"}
   admin@adm01:~/src/outils$ bash -c 'source lib/ms-commun.sh; . ~/.config/workbook/pve-api.env; pve_api GET /nodes/$PVE_NODE/syslog'
   2026-10-04T10:21:40+02:00 bash[48877] ERREUR GET /nodes/pve01/syslog → HTTP 403 Permission check failed (/nodes/pve01, Sys.Syslog)
   ```

7. **`pve_wait_task`** : nœud = 2e champ de l'UPID, UPID encodé pour l'URL (`jq -rn --arg u "$upid" '$u|@uri'`), interrogation de `/nodes/{nœud}/tasks/{upid}/status` toutes les `MS_PVE_POLL` secondes (2 par défaut) jusqu'à `status=stopped`, puis `exitstatus` : `OK` → 0, `WARNINGS: n` → 0 avec avertissement, autre → 1.

**Explications**

- **`source` exécute le fichier dans le shell courant** : fonctions et variables globales de la bibliothèque deviennent celles du script. D'où les préfixes (`_ms_`, `MS_`) et l'absence d'effets de bord au chargement (aucun appel réseau, aucune option modifiée).
- **`set -e` est suspendu** dans toute commande testée : condition d'un `if`/`while`, opérande gauche de `&&`/`||`, commande précédée de `!` — **et dans toutes les fonctions qu'elle appelle**. `retry ma_fonction` exécute `"$@" && return 0` : à l'intérieur de `ma_fonction`, une commande qui échoue ne l'arrête pas. Une fonction destinée à `retry` (ou à un `if`) doit donc renvoyer elle-même ses échecs (`|| return 1`).
- **Pourquoi `--include` plutôt que `-w '%{http_code}'`** : le code seul ne dit pas *pourquoi* (403 sur quel chemin, pour quel privilège ?). Proxmox met cette information dans la phrase de statut ; la perdre, c'est rendre chaque refus incompréhensible pour l'astreinte.
- **Priorité de l'environnement** : en CI (E24, E25), il n'y a pas de fichier, seulement des variables protégées et masquées ; sur `adm01`, le fichier. Une seule règle pour les deux.

**Alternatives**

- **`curl -K -`** (configuration lue sur l'entrée standard, avec une ligne `header = "Authorization: …"`) : aussi sûr que `-H @<(…)`, utilisé par le contrôle de E26 pour PBS. Un fichier temporaire en mode 600 fonctionne aussi (M00-E18), mais il faut le supprimer à coup sûr.
- **Analyser le fichier d'accès au lieu de le sourcer** : plus sûr (rien n'est exécuté) ; le `source` est acceptable ici parce que le fichier nous appartient et qu'il est refusé dès qu'un autre que nous peut l'écrire ou le lire (mode vérifié). `medictl` (E19) le lit sans l'exécuter.
- **`-w '%{http_code}' -o fichier`** : plus simple à analyser, mais perd le motif.

**Pièges classiques**

- `local x="$(commande)"` : masque le code de retour.
- Une bibliothèque qui fait `set -euo pipefail` ou `trap … EXIT` : elle écrase le piège du script, ou change son comportement.
- `exit` au lieu de `return` dans le garde de chargement unique : le script entier s'arrête.
- Journal sur stdout : `x="$(pve_api …)"` récupère les messages avec les données, et `jq` échoue.
- `curl -H "Authorization: PVEAPIToken=…"` : secret visible dans `ps` par tous les utilisateurs de `adm01`, et dans `set -x`.
- Analyser la réponse de `curl --include` sans `--suppress-connect-headers` derrière un mandataire : la première ligne de statut est celle du `CONNECT`.
- Variables locales génériques (`n`, `i`, `rc`) dans une fonction qui appelle du code fourni par l'appelant.

**En production chez MédiSphère**

La bibliothèque est versionnée avec le projet et testée en CI (E14, E24) ; toute modification incompatible de son API impose une version majeure (semantic-release, commit `feat!:`). Les scripts installés utilisent la copie installée avec eux (E20), jamais celle d'un clone.

---

### M02-E11 — `ms-snapshot` : instantanés du lab avant intervention

**Solution**

1. Exploration :
   ```
   admin@adm01:~/src/outils$ source lib/ms-commun.sh; . ~/.config/workbook/pve-api.env
   admin@adm01:~/src/outils$ pve_api GET /nodes/$PVE_NODE/qemu/2020/snapshot | jq .
   [ { "name": "current", "description": "You are here!", "running": 1 } ]
   admin@adm01:~/src/outils$ upid="$(pve_api POST /nodes/$PVE_NODE/qemu/2020/snapshot snapname=essai | jq -r .)"; echo "$upid"
   UPID:pve01:000BC2A1:0312F4E5:6720F00D:qmsnapshot:2020:wb-automation@pve!lab:
   admin@adm01:~/src/outils$ pve_wait_task "$upid" && pve_api DELETE /nodes/$PVE_NODE/qemu/2020/snapshot/essai
   ```
   Une entrée d'instantané : `name`, `description`, `snaptime` (secondes Unix), `vmstate`, `parent` ; l'entrée `current` n'a pas de `snaptime`.
2. Étiquette par l'API : `pve_api POST /nodes/$PVE_NODE/qemu/2020/config tags=env-m02` (renvoie un UPID ou `null` : à passer à `pve_wait_task` s'il y en a un). ⚠️ À vérifier sur ta version : la modification des étiquettes par un compte non administrateur dépend du réglage de datacenter `user-tag-access` (par défaut, les étiquettes libres sont autorisées avec `VM.Config.Options`).
3. Script complet : [`fichiers/M02-E11/bin/ms-snapshot`](fichiers/M02-E11/bin/ms-snapshot). Structure :
   - analyse des options (`while`/`case`, formes `--keep N` et `--keep=N`, `--`), validations : `--keep` entier ≥ 1 et préfixe valide (code 2), `--pool` et VMID exclusifs (2), pool autre que `lab` (3) ;
   - **un seul** appel `GET /cluster/resources?type=vm`, puis la fonction `cibles` valide chaque VMID demandé (absent/invisible, pas QEMU, hors pool, template → `die … 3`) **avant** toute écriture ;
   - un nom `${PREFIXE}-$(date +%Y%m%d-%H%M%S)` calculé une fois ;
   - `traiter_vm` : création + `pve_wait_task` ; si échec → `return 1` **sans purge** ; puis liste, sélection, suppressions (chacune attendue) ;
   - garde finale `if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi`.
4. La sélection, testable seule :
   ```bash
   a_purger() {
     jq -r --arg p "$1" --argjson n "$2" '
         [ .[] | select(.name | test("^" + $p + "-[0-9]{8}-[0-9]{6}$")) ]
         | sort_by(.snaptime // 0, .name)
         | .[0:(if length > $n then length - $n else 0 end)]
         | .[].name'
   }
   ```
   En `--dry-run`, l'instantané qui *serait* créé est ajouté à la liste avant la sélection (`. + [{name: $s, snaptime: now}]`) : la simulation annonce la même purge que l'exécution réelle.
5. Après cinq exécutions de `ms-snapshot 2020` et une de `--prefix avant-maj --keep 1` :
   ```
   root@pve01:~# qm listsnapshot 2020
   `-> manuel-karim                2026-10-04 10:02:11     posé à la main avant migration
    `-> avant-20261004-101502      2026-10-04 10:15:02     ms-snapshot par admin depuis adm01
     `-> avant-20261004-101531     2026-10-04 10:15:31     ms-snapshot par admin depuis adm01
      `-> avant-20261004-101559    2026-10-04 10:15:59     ms-snapshot par admin depuis adm01
       `-> avant-maj-20261004-101640 2026-10-04 10:16:40   ms-snapshot par admin depuis adm01
        `-> current                                        You are here!
   ```
   Trois `avant-…`, un `avant-maj-…`, `manuel-karim` intact. (Proxmox affiche une chaîne : chaque instantané a pour parent le précédent ; supprimer un instantané du milieu fusionne les différences, sans toucher aux autres.)
6. Réponses du journal :
   - **Préfixe et motif** : avec `test("^" + préfixe)` seul, `avant` capturerait `avant-maj-…` et la rotation de l'un supprimerait les instantanés de l'autre. Le motif complet ancré (`^avant-[0-9]{8}-[0-9]{6}$`) ne reconnaît que les noms de l'outil, pour ce préfixe exact.
   - **Deux exécutions simultanées** : chacune lit la liste avant que l'autre n'ait fini ; elles peuvent supprimer chacune « le plus ancien » (donc deux), ou tenter de supprimer le même (erreur de verrou de VM « VM is locked (snapshot-delete) »). Traité en E13 par un verrou.
   - **Cohérence** : sans `vmstate`, l'instantané fige les disques comme après une coupure de courant (*crash-consistent*). Un journal de système de fichiers s'en remet ; une base de données qui n'a pas écrit ses tampons, pas forcément. ⚠️ À vérifier sur ta version : Proxmox peut geler les systèmes de fichiers de l'invité par l'agent QEMU lors d'un instantané ; lis la documentation de `qm snapshot` et l'option `freeze-fs` de l'agent. Pour une base, on préfère un vidage applicatif avant l'instantané.

Exécution type :
```
admin@adm01:~/src/outils$ bin/ms-snapshot --dry-run 2020
2026-10-04T10:17:02+02:00 ms-snapshot[49210] INFO [simulation] 2020 (m02-cobaye) : créerait l'instantané avant-20261004-101702
2026-10-04T10:17:02+02:00 ms-snapshot[49210] INFO [simulation] 2020 (m02-cobaye) : supprimerait l'ancien instantané avant-20261004-101502
2026-10-04T10:17:02+02:00 ms-snapshot[49210] INFO bilan : 1 VM(s) traitée(s) (simulation, rien n'a été modifié) — instantané avant-20261004-101702
admin@adm01:~/src/outils$ bin/ms-snapshot 9000; echo "code $?"
2026-10-04T10:17:20+02:00 ms-snapshot[49301] ERREUR VM 9000 : template : refus
code 3
```

**Explications**

- **Tout ou rien** : la validation de toutes les cibles avant la première écriture évite l'état « la moitié des VMs ont leur instantané, l'outil s'est arrêté sur la 4e » ; à l'inverse, une fois les écritures commencées, une VM en échec n'arrête pas les autres (on veut un point de retour sur le maximum de VMs) et le code final 1 le signale.
- **Jamais de purge après un échec de création** : sinon une suite d'échecs (stockage plein) supprimerait un à un tous les points de retour.
- **Codes 2 et 3** : un préfixe mal formé est une erreur d'usage (2), même code que M02-E27 ; une cible interdite est un refus de garde-fou (3).
- **Tâches** : le `POST …/snapshot` répond tout de suite avec un UPID ; enchaîner une suppression sans attendre donne « VM is locked (snapshot) ».

**Alternatives**

- `qm snapshot` en SSH sur `pve01` : exige un accès root à l'hyperviseur, exactement ce que le jeton évite.
- Sauvegarde PBS avant intervention (`vzdump` d'une VM, M00-E22) : plus lente, mais hors de l'hyperviseur et sans dégrader les performances disque. Les instantanés servent au retour arrière rapide, pas à la sauvegarde.
- Python (`medictl vm snapshot`) : même logique, tests plus confortables ; le Bash reste pertinent pour un geste d'astreinte sans dépendance.

**Pièges classiques**

- Compter l'entrée `current` comme un instantané (tri par `snaptime` absent).
- Trier par nom un préfixe dont la date n'est pas en tête du tri (ici le nom fini par AAAAMMJJ-HHMMSS : tri par nom et par date coïncident, mais `snaptime` est la vraie source).
- Horodatage différent par VM : impossible ensuite de retrouver « l'état d'avant l'intervention » sur l'ensemble.
- `jq` en tranche négative : `.[0:-1]` sur une liste vide ou trop courte ne fait pas ce qu'on croit ; d'où le calcul explicite.
- Garder des instantanés des semaines : chaque instantané ralentit les écritures (copie sur écriture) et consomme de l'espace sur le stockage *thin* ; la rotation n'est pas un luxe.

**En production chez MédiSphère**

L'instantané est une étape du runbook d'intervention (RB-0xx), journalisée dans le ticket de changement (nom de l'instantané). Une supervision alerte sur les instantanés de plus de 7 jours. Les VMs en haute disponibilité (module 09) ont des contraintes supplémentaires (stockage partagé, réplication).

---

### M02-E12 — Traiter des fichiers en masse sans piège (espaces, `-print0`, tableaux)

**Solution**

Script complet : [`fichiers/M02-E12/bin/ms-ranger`](fichiers/M02-E12/bin/ms-ranger).

1. La version naïve :
   ```bash
   for f in $(find "$SRC" -type f -mtime +90); do mv "$f" …; done
   ```
   `$(…)` est découpé sur les espaces, tabulations et retours à la ligne (`IFS`), puis **chaque morceau subit l'expansion des motifs** : `rapport mensuel  février 2025.pdf` donne quatre « fichiers » ; `facture [2025] *finale*.txt` voit `*finale*.txt` remplacé par les fichiers du dossier courant qui correspondent ; un nom avec retour à la ligne est coupé en deux. C'est exactement « perdre des fichiers à cause des espaces ».
2. Le cœur de la version sûre :
   ```bash
   source="$(realpath -e -- "$1")"
   dest="$(realpath -m -- "$2")"
   if [[ "$dest/" == "$source/"* || "$source/" == "$dest/"* ]]; then
     die "SOURCE et DESTINATION ne doivent pas être l'un dans l'autre" 3
   fi
   mapfile -d '' -t fichiers < <(find "$source" -type f -mtime +"$age" -print0)
   wait "$!" || die "find a échoué en parcourant $source : rien n'a été déplacé" 1
   for f in "${fichiers[@]}"; do
     rel="${f#"$source"/}"
     mois="$(date -r "$f" +%Y-%m)"
     cible="$dest/$mois/$rel"
     [[ -e "$cible" || -L "$cible" ]] && { log_err "conflit : $(printf '%q' "$rel")"; erreurs=$((erreurs + 1)); continue; }
     h="$(sha256sum <"$f")"
     mkdir -p -- "$(dirname -- "$cible")" && mv -- "$f" "$cible"
     ligne_manifeste "${h%% *}" "$mois/$rel" >>"$manifeste"
   done
   (cd -- "$dest" && sha256sum --check --quiet --strict -- "$(basename -- "$manifeste")")
   ```
3. **Code de `find`** : dans `< <(find …)`, `find` tourne dans un processus séparé ; son échec n'atteint pas `set -e`. Depuis Bash 5.1, `$!` désigne ce processus et `wait "$!"` rend son code : on l'examine **avant** de déplacer quoi que ce soit.
4. **Manifeste** : `sha256sum` écrit `\<empreinte>  <nom échappé>` quand le nom contient `\` ou un retour à la ligne (`\\` et `\n`) ; `ligne_manifeste` reproduit cette forme, et `sha256sum --check` la relit.
   ```
   admin@adm01:~$ grep -c . ~/m02/e12/archive/MANIFESTE-*.sha256
   32
   admin@adm01:~$ grep '^\\' ~/m02/e12/archive/MANIFESTE-*.sha256
   \5f1c…  2025-01/journaux/ligne un\nligne deux.log
   \9a07…  2025-02/journaux/\nau début.log
   \c3e2…  2025-02/factures/C:\\Windows\\chemin.txt
   ```
5. Exécution :
   ```
   admin@adm01:~$ ~/src/outils/bin/ms-ranger ~/m02/e12/exports-infoger ~/m02/e12/archive
   2026-10-04T11:02:44+02:00 ms-ranger[51022] INFO 32 fichier(s) rangé(s) (2448 octets), 0 erreur(s), 1 lien(s) symbolique(s) ignoré(s) ; manifeste vérifié : /home/admin/m02/e12/archive/MANIFESTE-20261004-110244-51022.sha256
   admin@adm01:~$ ~/src/outils/bin/ms-ranger ~/m02/e12/exports-infoger ~/m02/e12/archive
   2026-10-04T11:03:10+02:00 ms-ranger[51101] INFO 0 fichier(s) rangé(s) (0 octets), 0 erreur(s), 1 lien(s) symbolique(s) ignoré(s)
   ```
   La seconde exécution ne trouve que les 3 fichiers récents (non candidats) : rien à faire, code 0. Le nom du manifeste contient le PID : deux exécutions dans la même seconde ne se marchent pas dessus.
6. **Affichage** : `printf '%q'` rend tout nom affichable sur une ligne (`$'ligne un\nligne deux.log'`), sans ambiguïté.

**Explications**

- **NUL** est le seul octet interdit dans un chemin (avec `/` dans un nom de fichier) : c'est le seul séparateur sûr. `-print0`, `mapfile -d ''`, `read -d ''`, `xargs -0`, `sort -z` forment la chaîne « NUL de bout en bout ».
- **`--`** et chemins préfixés : `-rf` passé à `rm` ou `mv` serait une option. Ici les chemins commencent par SOURCE (absolu), et `--` est mis partout par principe.
- **`${f#"$source"/}`** : sans les guillemets internes, `$source` serait un *motif* (un dossier nommé `exports[1]` ne se retirerait pas).
- **Empreinte avant, vérification après** : c'est la seule façon de prouver que le déplacement (copie + suppression s'il traverse deux systèmes de fichiers) n'a rien altéré.
- **`-mtime +90`** compte en jours entiers : un fichier de 90,5 jours n'est **pas** pris (`+90` = « plus de 90 jours entiers »).

**Alternatives**

- `find … -exec ms-ranger-un {} +` : pas de tableau, mais une logique éclatée entre deux programmes.
- `rsync --remove-source-files` + manifeste : efficace pour des volumes importants ; la répartition par mois demande quand même un calcul par fichier.
- Python (`pathlib.Path.rglob`, `os.walk`) : pas de problème de découpage du tout ; Bash reste raisonnable pour quelques milliers de fichiers.

**Pièges classiques**

- `for f in $(find …)`, `ls | while read f` (perd les espaces de tête, les antislashs sans `-r`, les retours à la ligne).
- Compter avec `wc -l` des noms qui contiennent des retours à la ligne : compter des NUL (`tr -cd '\0' | wc -c`).
- Suivre les liens symboliques (`find -L`) : on archiverait des fichiers hors de SOURCE, ou deux fois le même.
- Destination dans la source : `find` retrouve les fichiers déjà rangés.
- `mv -n` « pour ne pas écraser » : selon la version de coreutils, il réussit silencieusement sans rien faire ; tester l'existence explicitement est plus clair.

**En production chez MédiSphère**

Les archives contractuelles vont dans le stockage objet (`s3-01`, module 05) avec versionnage et verrouillage d'objet ; le manifeste est conservé à part (preuve). Un script comme celui-ci s'exécute une fois, sous contrôle, avec sa sortie archivée dans le ticket.

---

### M02-E13 — Verrous, fichiers temporaires et exécutions concurrentes

**Solution**

Fichiers : [`fichiers/M02-E13/lib/ms-commun.sh`](fichiers/M02-E13/lib/ms-commun.sh) (ajout de `lock_or_die`), [`fichiers/M02-E13/bin/ms-export-config`](fichiers/M02-E13/bin/ms-export-config), [`fichiers/M02-E13/bin/ms-snapshot`](fichiers/M02-E13/bin/ms-snapshot) (une ligne de plus).

1. **La course** (deux `ms-snapshot 2020` simultanés, `--keep 3`, trois instantanés existants) : chacun crée le sien (le second attend parfois le verrou de VM de Proxmox, ou échoue avec « VM is locked (snapshot) »), chacun lit une liste, chacun supprime « le plus ancien » de **sa** liste : on se retrouve avec deux instantanés au lieu de trois, ou une tâche `qmdelsnapshot` en erreur sur un instantané déjà supprimé.
2. **`flock`** : le verrou est attaché au descripteur ouvert, pas au fichier. Le noyau le libère quand le dernier descripteur se ferme : à la fin du processus, même après `kill -9`, donc pas de verrou orphelin. Mais un processus **enfant** hérite du descripteur : un `sleep 600 &` lancé par le script garde le verrou après sa fin. Un fichier `.pid` fait main a les défauts inverses : il survit à `kill -9` (verrou fantôme à nettoyer), et « tester puis créer » n'est pas atomique (deux processus peuvent tester en même temps).
3. `lock_or_die` :
   ```bash
   lock_or_die() {
     local nom="${1:-}" attente="${2:-0}"
     local dossier="${MS_LOCK_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ms-outils/verrous}"
     # validations (nom, attente) → die … 2
     (umask 077 && mkdir -p -- "$dossier") || die "impossible de créer le dossier des verrous $dossier"
     local fichier="$dossier/$nom.lock"
     exec {MS_LOCK_FD}>>"$fichier" || die "impossible d'ouvrir le verrou $fichier"
     local -a opt=(-n)
     if ((attente > 0)); then opt=(-w "$attente"); fi
     if ! flock "${opt[@]}" "$MS_LOCK_FD"; then
       die "$nom est déjà en cours d'exécution (verrou $fichier, tenu par : $(head -n 1 -- "$fichier")) : abandon" 3
     fi
     printf 'pid %d depuis %s (%s)\n' "$$" "$(date -Iseconds)" "${USER:-?}" >"$fichier"
   }
   ```
   Dans `ms-snapshot`, après la validation des arguments : `require_cmd curl jq flock` puis `lock_or_die ms-snapshot`.
   **Choix du dossier** : `$XDG_RUNTIME_DIR` (`/run/user/1000`) n'existe pas sous cron ni dans un service système : une exécution planifiée et une exécution manuelle prendraient deux verrous différents, et ne s'excluraient pas. `/tmp` est partagé par tous et nettoyé ; `/run/lock` dépend des droits posés par la distribution (⚠️ à vérifier sur Debian 13 : `stat /run/lock`). `~/.local/state/ms-outils/verrous` (privé, 700) est le même pour l'utilisateur `admin` en interactif, sous cron et sous systemd (`User=admin`). Le fichier persiste après un redémarrage, sans conséquence : seul compte le verrou noyau.
4. `ms-export-config`, l'essentiel :
   ```bash
   umask 077
   trap nettoyer EXIT          # supprime $TMP s'il existe encore
   trap 'exit 130' INT
   trap 'exit 143' TERM
   …
   TMP="$(mktemp -d -- "$BASE/.en-cours.XXXXXX")"     # même système de fichiers que la cible
   while read -r vmid noeud nom; do
     config="$(pve_api GET "/nodes/$noeud/qemu/$vmid/config")" || die "configuration de $vmid ($nom) illisible : export abandonné"
     jq -S . <<<"$config" >"$TMP/$vmid-$nom.json"
   done <<<"$liste"
   mv -T -- "$TMP" "$BASE/$horodatage"; TMP=""          # publication : un rename(2)
   ln -s -- "$horodatage" "$BASE/.dernier.$$"
   mv -T -- "$BASE/.dernier.$$" "$BASE/dernier"         # bascule atomique du lien
   ```
   puis la rotation, qui ne considère que les dossiers au format exact `AAAAMMJJ-HHMMSS` (`find -regextype posix-extended -regex …`), triés par nom, au-delà de `--garder`.
   **`ln -sfn`** : avec le coreutils de Debian 13, `strace -e trace=symlinkat,renameat ln -sfn b dernier` montre un `symlinkat` qui échoue (EEXIST), puis la création d'un lien au nom aléatoire et un `renameat` par-dessus `dernier` : c'est atomique. Ce n'est pas le cas partout (anciennes versions, BusyBox, macOS font `unlink` puis `symlink`, avec un instant sans lien). Le couple explicite « lien temporaire + `mv -T` » est atomique partout et dit ce qu'il fait.
5. Interruptions : Ctrl-C → `exit 130` → piège `EXIT` → dossier temporaire supprimé, message « export interrompu », `dernier` inchangé. Même chose pour `TERM` et pour une configuration illisible (`die` → `EXIT`).
6. Exclusion :
   ```
   admin@adm01:~$ flock ~/.local/state/ms-outils/verrous/ms-export-config.lock sleep 60 &
   admin@adm01:~$ ~/src/outils/bin/ms-export-config; echo "code $?"
   2026-10-04T11:40:03+02:00 ms-export-config[52210] ERREUR ms-export-config est déjà en cours d'exécution (verrou /home/admin/.local/state/ms-outils/verrous/ms-export-config.lock, tenu par : pid 52190 depuis …) : abandon
   code 3
   ```
   (Ici, le fichier contient encore la trace du dernier détenteur « officiel » : `flock` en ligne de commande n'y écrit rien. C'est une indication, pas une preuve.)
7. Comparaison de deux exports :
   ```
   admin@adm01:~$ diff -r ~/exports/config-vms/20261004-114500 ~/exports/config-vms/dernier/
   diff -r …/20261004-114500/2020-m02-cobaye.json …/dernier/2020-m02-cobaye.json
   5c5
   <   "description": "",
   ---
   >   "description": "essai E13",
   ```
   Les clés triées (`jq -S`) rendent le `diff` lisible ; `digest` change aussi à chaque modification de configuration.

**Explications**

- **Atomicité de `rename(2)`** : un lecteur voit l'ancien nom ou le nouveau, jamais un état intermédiaire — à condition que source et cible soient sur le même système de fichiers (sinon `mv` copie puis supprime). D'où le dossier temporaire **dans** `MS_EXPORT_DIR`, et pas dans `/tmp`.
- **Un seul piège `EXIT`** : les pièges de signaux se contentent de sortir avec le code conventionnel (128 + numéro du signal), ce qui déclenche `EXIT`. Écrire le nettoyage dans chaque piège mène à des doubles nettoyages ou des oublis.
- **Code 3 pour « déjà en cours »** : ce n'est pas une panne, c'est un garde-fou qui a joué ; un service planifié peut le traiter à part (ex. `SuccessExitStatus=3` si l'on juge normal qu'un export manuel soit en cours).

**Alternatives**

- **systemd** : un service `oneshot` déclenché par un timer n'est pas relancé tant qu'il est actif ; cela protège contre lui-même, pas contre une exécution manuelle hors systemd.
- **Verrou `mkdir`** : atomique et portable, mais pas de libération automatique (verrou orphelin après `kill -9`), et pas d'attente avec délai.
- **`flock` en préfixe** (`flock -n fichier commande`) : simple pour cron, mais chaque appelant doit y penser ; le verrou dans l'outil protège tout le monde.

**Pièges classiques**

- Prendre le verrou **avant** la validation des arguments : une faute de frappe attend un verrou ou bloque l'exécution planifiée.
- Fichier temporaire dans `/tmp` puis `mv` vers un autre système de fichiers : la publication redevient une copie, visible à moitié.
- `trap 'rm -rf $TMP' EXIT` avec `TMP` vide ou non initialisée : `rm -rf` sans argument ne fait rien, mais `rm -rf "$TMP"/*` avec `TMP` vide vise `/*`. Toujours tester la variable, et `${VAR:?}` dans les `rm -rf`.
- Oublier qu'un processus d'arrière-plan hérite du descripteur du verrou.
- Rotation par `ls | tail` qui supprime aussi `dernier` ou un dossier ajouté à la main.

**En production chez MédiSphère**

L'export nocturne devient un service planifié (comme E26), avec alerte sur échec. Les exports sont versionnés dans un dépôt Git dédié, ce qui donne l'historique et le `diff` gratuitement ; au module 05, la configuration des VMs vivra dans OpenTofu et cet export servira à détecter les dérives (*drift*).

---

### M02-E14 — Tester ses scripts Bash avec bats

**Solution**

Fichiers : [`fichiers/M02-E14/tests/bats/`](fichiers/M02-E14/tests/bats/) — 60 tests :

| Fichier | Rôle |
|---|---|
| `helpers/commun.bash` | `preparer_faux_pve` : fichier d'accès factice (600), `MS_PVE_ENV_FILE`, `MS_LOCK_DIR`, `MS_PVE_POLL=0`, `PATH` avec le faux `curl` en tête, variables `PVE_*` neutralisées ; `appels MOTIF` compte les appels journalisés |
| `helpers/bin/curl` | faux `curl` : comprend `-X`, `--data-urlencode`, `-H @fichier`, l'URL ; journalise `MÉTHODE CHEMIN DONNÉES` ; répond comme pveproxy (statut avec motif, CRLF) ; état dans un dossier (instantanés créés) ; échecs simulés par fichiers témoins (`tache-ko`, `snapshot-ko-<VMID>`, `config-ko-<VMID>`, `reseau-ko`) ; signale `SECRET_DANS_ARGV` si le secret factice apparaît en argument |
| `fixtures/ressources.json`, `fixtures/snapshots-2020.json` | réponses enregistrées (pool `lab`, template, VM hors pool ; instantanés de plusieurs préfixes) |
| `ms-commun.bats` (29 tests) | journal, `die`, `require_cmd`, `confirm`, `retry` (dont la portée dynamique), `pve_api` (données, 403, 400, réseau, mode 644, priorité de l'environnement, https obligatoire, secret absent des arguments), `pve_wait_task`, `lock_or_die` |
| `ms-snapshot.bats` (21 tests) | codes 2 et 3, aucune écriture en cas de refus, `a_purger` seule, exécution complète, `--dry-run`, `--pool lab`, même horodatage, échec de création sans purge, tâche en échec, API injoignable, exécution concurrente |
| `ms-export-config.bats`, `ms-ranger.bats` (10 tests) | publication atomique, nettoyage après échec, rotation, exclusion ; noms piégeux, manifeste, conflits, garde-fou |

Extraits :
```bash
setup() {
  load helpers/commun
  preparer_faux_pve
  SNAP="$RACINE/bin/ms-snapshot"
}

@test "crée l'instantané, attend la tâche, purge au-delà de --keep" {
  run -0 "$SNAP" --keep 3 2020
  [[ "$(appels '^POST /nodes/pve01/qemu/2020/snapshot snapname=avant-[0-9]{8}-[0-9]{6} ')" -eq 1 ]]
  [[ "$(appels '^DELETE ')" -eq 2 ]]
  [[ "$(appels '^DELETE /nodes/pve01/qemu/2020/snapshot/avant-20260101-080000')" -eq 1 ]]
  [[ "$(appels 'SECRET_DANS_ARGV|SANS_JETON')" -eq 0 ]]
}

@test "a_purger respecte un préfixe qui en prolonge un autre" {
  source "$SNAP"
  run -0 a_purger avant-maj 0 <"$FAUX_PVE_FIXTURES/snapshots-2020.json"
  [[ "$output" = "avant-maj-20251231-235900" ]]
}
```
```
admin@adm01:~/src/outils$ bats tests/bats
ms-commun.bats
 ✓ la bibliothèque refuse d'être exécutée directement (code 2)
 …
ms-snapshot.bats
 ✓ une seconde exécution simultanée est refusée (3)

60 tests, 0 failures
```

Mutations (étape 6), essayées sur la solution :

| Mutation | Tests en échec |
|---|---|
| `((_ms_essai < _ms_max))` au lieu de `>=` dans `retry` | 4 tests de `retry` |
| `-n` retiré de `flock` | le second détenteur attend au lieu d'être refusé : le test « refusé avec le code 3 » échoue |
| `-H "Authorization: PVEAPIToken=…"` au lieu de `-H @<(…)` | « pve_api ne passe jamais le secret en argument » et l'exécution complète de `ms-snapshot` |
| `return 1` retiré après un échec de création | « création en échec : aucune purge » et « tâche Proxmox en échec : aucune purge » |

La troisième ligne a d'abord **réussi à passer** : la première version du faux `curl` ne cherchait le secret que dans les paramètres et l'URL, pas dans les en-têtes. Un test de sécurité qui ne voit pas le défaut qu'il est censé voir est pire que pas de test : c'est exactement ce que la mutation sert à révéler. Le faux `curl` examine maintenant **tous** ses arguments.

Le `.editorconfig` de E04 reçoit une section pour les faux exécutables sans extension (`[tests/bats/helpers/bin/**]`, mêmes réglages que `bin/**`), sinon `shfmt` les indente avec des tabulations.

**Explications**

- **Deux niveaux de double** : le faux `curl` teste la vraie plomberie (`pve_api`, encodage, en-têtes, analyse de la réponse) ; la redéfinition de `pve_api` (comme dans les tests de E26 et E27) teste la logique d'un script en isolant la bibliothèque. Les deux sont légitimes ; le faux `curl` attrape plus de défauts, au prix d'un double plus long à écrire.
- **Le test de sécurité** : on ne peut pas vérifier « le secret n'est pas dans `ps` » directement ; on vérifie la cause : il n'est jamais passé en argument à `curl`.
- **`[[ ]]` plutôt que `[ ]`** : imposé par le `.shellcheckrc` du projet (`require-double-brackets`) ; dans bats, une condition `[[ … ]]` qui échoue fait bien échouer le test (Bash ≥ 4.1).
- **Descripteur 3** : bats lit les résultats sur le descripteur 3 ; un processus d'arrière-plan qui le garde ouvert empêche bats de se terminer. `commande 3>&- &`.

**Alternatives**

- `bats-assert`/`bats-support` (`assert_output --partial`, `assert_failure 3`) : messages d'échec plus clairs ; dépendance supplémentaire à installer sur `runner01`.
- `shellspec`, `shunit2` : autres cadres de tests Bash ; bats est le plus répandu.
- Tests de bout en bout sur une VM sandbox (5000-5999) en CI planifiée : utiles en complément, jamais à la place.

**Pièges classiques**

- Tests qui dépendent de `~/.config/workbook/pve-api.env` : ils « passent » sur `adm01` et appellent le vrai Proxmox, puis échouent en CI.
- Faux `curl` qui répond en LF au lieu de CRLF : la bibliothèque ne trouve pas la fin des en-têtes.
- `run` sans code attendu : `run commande` réussit toujours ; il faut tester `$status` ou utiliser `run -N`.
- Oublier `bats_require_minimum_version 1.5.0` : `run -N` déclenche un avertissement (BW02).
- Tester l'implémentation (« la fonction X est appelée ») plutôt que le comportement (« aucune écriture n'est envoyée »).

**En production chez MédiSphère**

La suite tourne à chaque MR (E24), avec un rapport JUnit affiché dans GitLab. Toute correction d'incident sur un script commence par un test qui reproduit l'incident (on le verra en E37 et E39).

---

### M02-E15 — CLI `medictl` avec Typer : lister et décrire les VMs

**Solution**

Fichiers : [`fichiers/M02-E15/src/medictl/cli.py`](fichiers/M02-E15/src/medictl/cli.py) et [`sortie.py`](fichiers/M02-E15/src/medictl/sortie.py) ; `pve.py` est celui de M02-E08 (`charger_config`, `connexion`), `pyproject.toml` celui de M02-E07.

1. `sortie.py` convertit une entrée de `/cluster/resources` vers le contrat :
   ```python
   def resume_vm(r: dict) -> dict[str, Any]:
       return {
           "vmid": r["vmid"], "name": r.get("name", ""), "status": r.get("status", "inconnu"),
           "node": r.get("node", ""), "pool": r.get("pool"),
           "template": str(r.get("template", 0)) == "1",
           "cpus": int(r.get("maxcpu", 0)),
           "memory_mib": int(r.get("maxmem", 0)) // 1024**2,
           "disk_gib": round(int(r.get("maxdisk", 0)) / 1024**3, 1),
           "tags": sorted(t for t in str(r.get("tags") or "").split(";") if t),
       }
   ```
   et fournit `en_json` (`json.dumps(…, ensure_ascii=False, indent=2)`) et `en_tableau` (colonnes alignées).
2. `cli.py` : `app = typer.Typer(no_args_is_help=True, add_completion=False)`, `vm_app` ajoutée par `app.add_typer(vm_app, name="vm")`, option `--version` avec `is_eager=True`, énumération `class Format(StrEnum)`. **Un seul appel** pour `vm list` : `GET /cluster/resources?type=vm` (proxmoxer : `pve.cluster.resources.get(type="vm")`), qui donne nœud, état, pool, ressources et étiquettes de chaque VM visible.
3. `--format yaml` : Typer refuse avant d'exécuter la commande, code **2**, avec la liste des valeurs permises.
4. Erreurs : `ConfigError` (E08), `ResourceException` (proxmoxer) et `requests.exceptions.RequestException` sont attrapées et transformées en `typer.echo("medictl : …", err=True)` puis `typer.Exit(1)` ; stdout reste vide.
5. Pourquoi des nombres : un autre programme doit pouvoir **calculer** (somme de la mémoire allouée, tri, seuil) sans réanalyser du texte ; l'unité est dans le nom de la clé (`memory_mib`). La mise en forme pour humains appartient à la vue « table ».

```
admin@adm01:~/src/outils$ uv run medictl vm list
VMID  NOM           ÉTAT     NŒUD   POOL  VCPU  RAM (Mio)  DISQUE (Gio)  ÉTIQUETTES
1000  gw01          running  pve01  lab   2     2048       10.0          role-routeur,socle
1001  adm01         running  pve01  lab   2     4096       32.0          role-bastion,socle
1002  dns01         running  pve01  lab   1     1024       10.0          role-dns,socle
1004  git01         running  pve01  lab   4     8192       60.0          role-gitlab,socle
1007  runner01      running  pve01  lab   2     4096       30.0          role-runner,socle
2020  m02-cobaye    running  pve01  lab   1     1024       3.5           env-m02
9000  tpl-debian13  stopped  pve01  lab   1     1024       3.5           debian13
admin@adm01:~/src/outils$ uv run medictl vm show 999999; echo "code $?"
medictl : VM 999999 introuvable (inexistante, ou hors du pool lab)
code 1
```
(Ressources indicatives : elles dépendent de tes choix du module 00 et 01.)

**Explications**

- **Énumération** : Typer valide l'option et génère l'aide ; le code n'a jamais à traiter une valeur inattendue.
- **Option prioritaire (`is_eager`)** : `--version` est traitée avant la validation des autres paramètres et avant la commande (sinon `medictl --version` exigerait une sous-commande).
- **`/cluster/resources` plutôt que `/nodes/{node}/qemu`** : une seule requête pour tout le cluster (utile au module 09), avec le pool de chaque VM. Le jeton n'y voit que les VMs sur lesquelles il a `VM.Audit`, donc celles du pool `lab`.
- **Séparation `pve` / `sortie` / `cli`** : la conversion se teste sans réseau ni Typer (E18).

**Alternatives**

- Click directement (Typer s'appuie sur lui) ; `argparse` de la bibliothèque standard : aucune dépendance, plus verbeux, pas d'aide riche.
- Rich pour les tableaux (`rich.table.Table`) : plus joli, mais la sortie « table » doit rester exploitable par `sort`, `awk` : un format texte simple est un choix délibéré.

**Pièges classiques**

- Imprimer des messages d'information sur stdout : `vm list -f json | jq` casse.
- Paramètre Python nommé `format` ou `id` : masque une fonction native (et une règle de ruff le signale si on l'active).
- Convertir les octets en « Go » avec 1000³ ici et 1024³ là : le contrat fixe Mio et Gio.
- Laisser remonter une `ResourceException` : trace de 40 lignes, exactement ce que Nadia ne veut plus.

**En production chez MédiSphère**

Le contrat JSON est documenté dans le README et protégé par des tests (E18) ; tout changement incompatible est une version majeure (`feat!:`). Une option `--format json` sur chaque commande est la règle de l'équipe : les outils se composent.

---

### M02-E16 — `medictl vm create/destroy` avec garde-fous

**Solution**

Version consolidée : [`fichiers/M02-E20/outils/src/medictl/`](fichiers/M02-E20/outils/src/medictl/) — `garde_fous.py` (nouveau), `erreurs.py` (nouveau), commandes `create` et `destroy` de `cli.py`, méthodes d'écriture et d'attente de `pve.py`.

1. Garde-fous et erreurs humaines :

   | Garde-fou | Erreur évitée | Où |
   |---|---|---|
   | VMID dans 2000-2999 ou 5000-5999, jamais 1000-1099 ni 9000-9099 | `destroy 1004` au lieu de `2004` | avant tout appel réseau |
   | Nom DNS court valide | nom refusé par Proxmox **après** clonage | avant tout appel réseau |
   | VM du pool `lab`, QEMU, pas un template | destruction d'une VM personnelle, d'un template | après lecture de l'inventaire |
   | Source de clonage = template 9000-9099 du pool | cloner `git01` (8 Go de disque, secrets) | après lecture |
   | VMID libre (`/cluster/nextid?vmid=`) | écraser ou mélanger avec une VM invisible | après lecture |
   | Confirmation (ou `--yes`), refus sans terminal | destruction par une commande collée dans le mauvais terminal | avant l'écriture |

   Proxmox, de son côté, refuse déjà tout ce qui sort du pool (droits du jeton) : `destroy` d'une VM personnelle échouerait en 403. On double quand même : la défense ne doit pas reposer sur une seule ACL (une ACL élargie un jour pour une autre raison, et le garde-fou a disparu), et le refus de l'outil est **compréhensible** (« plage protégée (socle permanent) ») là où un 403 ne l'est pas.
2. `garde_fous.py` (fonctions pures, extrait) :
   ```python
   PLAGES_AUTORISEES = (range(2000, 3000), range(5000, 6000))
   PLAGES_PROTEGEES = {"socle permanent": range(1000, 1100), "templates": range(9000, 9100)}

   def verifier_vmid_modifiable(vmid: int) -> None:
       for libelle, plage in PLAGES_PROTEGEES.items():
           if vmid in plage:
               raise RefusGardeFou(f"VMID {vmid} : plage protégée ({libelle}, {plage.start}-{plage.stop - 1})")
       if not any(vmid in plage for plage in PLAGES_AUTORISEES):
           raise RefusGardeFou(f"VMID {vmid} hors des plages autorisées (2000-2999, 5000-5999)")
   ```
   `RefusGardeFou` hérite de `ErreurMedictl` et porte `code = 3` ; un seul gestionnaire dans `cli.py` (`erreurs_propres()`) transforme toute `ErreurMedictl` en une ligne sur stderr et `typer.Exit(exc.code)`.
3. Client : `cloner` (`POST …/clone` avec `newid`, `name`, `pool=lab` ; clone lié par défaut depuis un template), `configurer` (`POST …/config`, renvoie un UPID ou `None`), `demarrer`, `arreter`, `detruire` (`DELETE …?purge=1&destroy-unreferenced-disks=1`), `attendre_tache` (statut toutes les 2 s, `exitstatus` `OK` ou `WARNINGS…`, délai maximal 600 s), `attendre_agent` (`POST …/agent/ping` jusqu'à réponse, 300 s), `vmid_libre` (`/cluster/nextid?vmid=N` : 400 si pris, quels que soient nos droits).
4. `vm create` : garde-fous sans réseau → lecture du template → garde-fou de source → VMID libre → clonage (attendu) → configuration (`net0=virtio,bridge=<vnet>`, `ipconfig0=ip=dhcp`, cœurs, mémoire, `tags`, description) → démarrage → agent si `--wait`. Toute erreur **après** le clonage est relancée avec la mention « la VM 2021 a été créée mais n'est pas prête ; pour la supprimer : medictl vm destroy 2021 ».
   `vm destroy` : garde-fou de plage (sans réseau) → lecture → garde-fous pool/template → confirmation (`sys.stdin.isatty()`, sinon refus 3 ; `typer.confirm(…, default=False)`) → arrêt si la VM tourne → destruction.
5. Refus observés :
   ```
   admin@adm01:~$ medictl vm destroy 1004 --yes; echo "code $?"
   medictl : VMID 1004 : plage protégée (socle permanent, 1000-1099)
   code 3
   admin@adm01:~$ medictl vm create M02_TEST --vmid 2022; echo "code $?"
   medictl : nom « M02_TEST » invalide : minuscules, chiffres et tirets, 63 caractères au plus
   code 3
   admin@adm01:~$ echo o | medictl vm destroy 2021; echo "code $?"
   medictl : confirmation impossible sans terminal : ajoute --yes
   code 3
   ```
6. Cycle :
   ```
   admin@adm01:~$ medictl -v vm create m02-test --vmid 2021 --tags env-m02
   … INFO medictl.cli : clonage de 9000 vers 2021 (m02-test)
   VM 2021 (m02-test) créée et démarrée ; agent QEMU prêt
   admin@adm01:~$ medictl vm destroy 2021
   Détruire la VM 2021 (m02-test) et ses disques ? [y/N]: y
   VM 2021 (m02-test) détruite
   admin@adm01:~$ medictl vm destroy 2020 --yes
   VM 2020 (m02-cobaye) détruite
   ```
   (`typer.confirm` affiche `[y/N]` ; la traduction n'est pas configurable simplement.)

**Explications**

- **Ordre des contrôles** : du moins coûteux au plus coûteux, et **tous** avant la première écriture. Un refus ne coûte rien et ne laisse rien.
- **`range(2000, 3000)`** : la borne haute est exclue, comme dans le plan (« 2000-2999 ») ; écrire `2000 <= v <= 2999` à la main est le meilleur moyen de se tromper d'une unité.
- **Pas de reprise sur les écritures** (E17) : un `POST …/clone` rejoué après une coupure pourrait créer une seconde VM (ou échouer sur un VMID devenu pris).
- **Échec à mi-parcours** : on ne détruit pas automatiquement la VM à moitié prête (l'erreur peut venir d'un problème qu'il faut diagnostiquer sur cette VM) ; on dit clairement qu'elle existe et comment la supprimer.

**Alternatives**

- Liste blanche par étiquette (`env-*`) en plus des plages : utile quand les plages ne suffisent plus (module 05).
- Protection côté Proxmox : option `protection: 1` sur les VMs du socle (`qm set 1004 --protection 1`) : la destruction est refusée par l'hyperviseur lui-même, quel que soit l'outil. À ajouter au socle : c'est complémentaire.
- OpenTofu (M05) : cycle de vie déclaratif, `prevent_destroy` sur le socle.

**Pièges classiques**

- Vérifier la plage **après** avoir lu la VM : un VMID mal tapé déclenche des appels inutiles, et un bogue dans la lecture contourne le garde-fou.
- Confirmer avec `input()` sans tester le terminal : dans un tube, la réponse vient de n'importe où (`yes | medictl vm destroy …`).
- Oublier `pool=lab` au clonage : refus de Proxmox (le jeton n'a `VM.Allocate` que sur le pool, M00-E17).
- Ne pas attendre la tâche de clonage avant `POST …/config` : « VM is locked (clone) ».
- Remplacer `net0` sans préciser le modèle (`virtio,bridge=…`) : Proxmox prend un autre modèle par défaut.

**En production chez MédiSphère**

Les VMs du socle portent `protection: 1` ; les destructions sont journalisées (journal des tâches de Proxmox, collecté au module 22). Les garde-fous de `medictl` sont revus par la RSSI à chaque modification de `garde_fous.py` (fichier sous la responsabilité de Sophie dans `CODEOWNERS`, contrôle manuel en revue puisque les propriétaires obligatoires sont Premium).

---

### M02-E17 — Erreurs, journalisation et reprises en Python

**Solution**

Version consolidée : [`journal.py`](fichiers/M02-E20/outils/src/medictl/journal.py), [`reprises.py`](fichiers/M02-E20/outils/src/medictl/reprises.py), fonctions `_lire`, `_ecrire` et `traduire` de [`pve.py`](fichiers/M02-E20/outils/src/medictl/pve.py), callback `principal` de [`cli.py`](fichiers/M02-E20/outils/src/medictl/cli.py).

1. Inventaire : `vm list` et `vm show` ne font que des GET (idempotents) ; `vm create` : GET (inventaire, `nextid`), puis POST clone, POST config, POST start, POST agent/ping, GET statut de tâche ; `vm destroy` : GET, POST stop, DELETE. Reprendre un `POST …/clone` après une coupure : si la première requête était arrivée, la seconde échoue (VMID pris) ou, pire, si le VMID est calculé côté client, crée une seconde VM. Reprendre un `GET …/tasks/{upid}/status` est sans risque.
2. Journal : un `StreamHandler(sys.stderr)`, format `%(asctime)s %(levelname)s %(name)s : %(message)s` ; niveau du journal `medictl` selon `-v` (WARNING, INFO, DEBUG) ; `-vvv` ouvre aussi `proxmoxer` et `urllib3` (qu'il faut **régler après** leur import : proxmoxer fixe ses journaux à WARNING en se chargeant). Option :
   ```python
   verbose: Annotated[int, typer.Option("--verbose", "-v", count=True)] = 0
   ```
3. Reprise (`reprises.py`) :
   ```python
   def est_transitoire(exc: BaseException) -> bool:
       if isinstance(exc, requests.exceptions.SSLError):
           return False  # sous-classe de ConnectionError : à tester AVANT
       if isinstance(exc, (requests.exceptions.ConnectionError, requests.exceptions.Timeout)):
           return True
       if isinstance(exc, ResourceException):
           return exc.status_code >= 500 and exc.status_code != 501
       return False

   def avec_reprises[T](fonction, *, nom, tentatives=4, delai=1.0, facteur=2.0, dormir=time.sleep) -> T:
       …  # 1 s, 2 s, 4 s, puis l'exception d'origine
   ```
   **C'est le client qui décide** de ce qu'on reprend : `_lire` (GET) passe par `avec_reprises`, `_ecrire` (POST, DELETE) jamais. La fonction de reprise ne sait que classer des erreurs.
4. `traduire` produit : « certificat de Proxmox refusé. Vérifie PVE_CACERT et que PVE_API_URL utilise un nom ou une adresse présents dans le certificat », « Proxmox injoignable (ConnectionError) », « jeton refusé (401). Secret erroné, jeton supprimé ou expiré », « droits insuffisants (403) — Permission check failed (…) », sinon « HTTP <code> <motif> <errors> ». Le gestionnaire de la CLI affiche une ligne et sort en 1 ; `log.debug(…, exc_info=True)` garde la pile pour `-vv`.
5. Observations :
   ```
   admin@adm01:~$ MEDICTL_ENV_FILE=~/m02/e17/injoignable.env medictl -v vm list
   … WARNING medictl.reprises : GET /cluster/resources : erreur transitoire (ConnectionError), essai 1/4, nouvel essai dans 1.0 s
   … WARNING medictl.reprises : GET /cluster/resources : erreur transitoire (ConnectionError), essai 2/4, nouvel essai dans 2.0 s
   … WARNING medictl.reprises : GET /cluster/resources : erreur transitoire (ConnectionError), essai 3/4, nouvel essai dans 4.0 s
   medictl : GET /cluster/resources : Proxmox injoignable (ConnectionError)
   admin@adm01:~$ MEDICTL_ENV_FILE=~/m02/e17/secret-faux.env medictl vm list; echo "code $?"
   medictl : GET /cluster/resources : jeton refusé (401). Secret erroné, jeton supprimé ou expiré
   code 1
   ```
   Injoignable : 4 essais en 7 s environ (port fermé : refus immédiat). Adresse qui ne répond pas du tout (paquets jetés) : chaque essai attend le délai de connexion (15 s), soit plus d'une minute ; c'est le prix d'un outil qui insiste. Certificat refusé : un seul essai.
   (Pour fabriquer les copies : `install -m 600 ~/.config/workbook/pve-api.env ~/m02/e17/secret-faux.env` puis modification à l'éditeur.)
6. Les 500 « métier » de Proxmox (VM verrouillée, configuration absente) seront repris inutilement **en lecture**, quatre fois, soit 7 s de perdues avant le même message : gênant mais sans danger. Sur une écriture, une reprise automatique serait dangereuse ; d'où la règle « lectures seulement ».

**Explications**

- **Transitoire ou permanent** : une erreur transitoire peut disparaître sans intervention (redémarrage de `pveproxy`, coupure réseau) ; une permanente demande d'agir (secret, droits, certificat). Reprendre une erreur permanente retarde le diagnostic sans aucune chance de succès.
- **`SSLError` avant `ConnectionError`** : l'ordre des `isinstance` compte avec une hiérarchie d'exceptions.
- **Délai exponentiel** : laisse le temps au service de revenir sans le marteler ; borné (4 essais) pour qu'une astreinte ait une réponse en quelques secondes.
- **proxmoxer et les avertissements TLS** : la bibliothèque appelle `urllib3.disable_warnings()` à l'import. Un `verify_ssl=False` glissé dans le code ne produirait aucun avertissement : la règle ruff `S501` et la revue sont les seuls filets.

**Alternatives**

- `urllib3.util.Retry` monté sur la session de requests (`allowed_methods={"GET"}`, `status_forcelist`, `backoff_factor`) : utilisé dans le corrigé de E23. Avec proxmoxer, la session est interne (`api._store["session"]`) : y toucher dépend d'un détail d'implémentation.
- Bibliothèques `tenacity` ou `backoff` : décorateurs riches (aléa, conditions) ; une dépendance de plus pour 30 lignes.
- Journalisation structurée (JSON, `structlog`) : utile quand les journaux partent vers Loki (module 22).

**Pièges classiques**

- `except Exception: pass` ou `except:` (attrape `KeyboardInterrupt`) dans une boucle de reprise : Ctrl-C ne fonctionne plus.
- Reprendre sur 4xx : un jeton expiré provoque 4 appels au lieu d'un, et retarde le vrai message.
- Journal configuré à l'import du module plutôt qu'au lancement : les tests et les autres programmes qui importent `medictl` subissent cette configuration.
- `logging.basicConfig` appelé deux fois : sans effet la seconde fois (sauf `force=True`).
- Pile d'appels affichée par défaut : l'astreinte voit un « bogue » là où il y a une simple panne réseau.

**En production chez MédiSphère**

Les journaux des outils lancés par systemd partent dans journald (E26), puis vers la pile de journalisation (module 22). Une alerte sur des erreurs 401 répétées signale un jeton expiré avant qu'il ne bloque toute l'automatisation.

---

### M02-E18 — Tester `medictl` avec pytest sans toucher à Proxmox

**Solution**

Version consolidée : [`fichiers/M02-E20/outils/tests/python/`](fichiers/M02-E20/outils/tests/python/) — 104 tests, couverture de `medictl` d'environ 90 %.

| Fichier | Contenu |
|---|---|
| `conftest.py` | fixtures `ressources` (export enregistré), `faux_client` (classe `FauxClient` injectée par `monkeypatch.setattr(cli, "fabriquer_client", …)`, qui journalise les écritures), `runner` (`CliRunner`), `fichier_env` (fichier d'accès jetable en 600, `HOME` et `MEDICTL_ENV_FILE` redirigés, `PVE_*` retirées) |
| `test_garde_fous.py` | frontières des plages (paramétrage), pool, template, source de clonage, noms |
| `test_cli.py` | `--version`, usage, `vm list` (contrat JSON exact, table), `vm show`, `create` nominal et `--no-wait`, refus de `create`/`destroy` en 3 **sans écriture**, confirmation hors terminal, échec après clonage |
| `test_pve_http.py` | `responses` : URL et en-tête envoyés, reprises 503 → 200 avec délais `[1.0, 2.0]`, abandon après 4 coupures, pas de reprise sur 400/401/403, `SSLError`, `POST` ; `nextid` ; attente de tâche ; `DELETE` avec purge ; adresses de l'agent |
| `test_reprises.py` | classement des erreurs, délais exponentiels |
| `test_config.py` | (E19) |

Extraits :
```python
@pytest.mark.parametrize(
    ("vmid", "motif"),
    [(1001, "socle"), (9000, "templates"), (2029, "hors du pool"), (100, "hors des plages")],
)
def test_destroy_refus_code_3(runner, faux_client, vmid, motif):
    resultat = runner.invoke(app, ["vm", "destroy", str(vmid), "--yes"])
    assert resultat.exit_code == 3
    assert motif in resultat.stderr
    assert faux_client.ecritures() == []

def test_lecture_reprise_sur_503_avec_delais_croissants(client, api, pauses):
    url = f"{BASE}/cluster/resources"
    api.get(url, status=503)
    api.get(url, status=503)
    api.get(url, json=_ressources())
    assert len(client.vms()) == 9
    assert len(api.calls) == 3
    assert pauses == [1.0, 2.0]
```
```
admin@adm01:~/src/outils$ uv run pytest --cov=medictl --cov-report=term-missing -q
…
TOTAL                          454     47    90%
104 passed in 1.9s
```
Les lignes non couvertes sont surtout `attendre_agent` (délais réels) et les branches de `vm show` en table : l'attente de l'agent mérite un test (avec un `dormir` injecté et une horloge simulée) ; l'affichage en table, beaucoup moins.

Mutation de l'étape 6 (`range(1000, 3000)` au lieu de `range(2000, 3000)`) : les tests paramétrés de frontières sur 1999 (« hors des plages ») passent au rouge — mais pas ceux sur 1000-1099, car la plage protégée « socle » est vérifiée **avant** les plages autorisées. Cette redondance voulue est une bonne nouvelle : un élargissement accidentel de la plage autorisée ne rend pas le socle destructible.

**Explications**

- **Deux niveaux de double**, comme en E14 : le `FauxClient` teste la logique de la CLI (rapide, lisible : « aucune écriture ») ; `responses` teste la plomberie proxmoxer/requests (URL, en-têtes, reprises).
- **`CliRunner`** : stdout et stderr sont séparés ; l'entrée n'est jamais un terminal (le refus sans `--yes` se teste donc naturellement).
- **Injection de dépendances** : `fabriquer_client()` dans la CLI, `dormir` dans la reprise, `environ` dans `charger_config` : ce sont des points d'entrée pour les tests, sans cadre d'injection.
- **Couverture** : elle montre ce qui n'est **pas** exécuté, pas ce qui est **vérifié**. Un test sans assertion couvre des lignes et ne prouve rien.

**Alternatives**

- `unittest.mock.patch` plutôt que `monkeypatch` : équivalent ; `monkeypatch` défait tout seul ses changements en fin de test.
- `pytest-httpserver` ou `vcrpy` (enregistrement de vraies réponses) : intéressant, mais un enregistrement contient des données du lab (noms, adresses) et parfois des en-têtes à nettoyer.
- Tests d'intégration contre une VM sandbox Proxmox imbriquée (module 09) : à planifier, pas à chaque MR.

**Pièges classiques**

- Tests qui lisent `~/.config/workbook/pve-api.env` : verts sur `adm01`, rouges (ou dangereux) en CI.
- Oublier `assert_all_requests_are_fired=False` quand une réponse n'est pas forcément consommée, ou au contraire le laisser à `False` partout et ne plus voir qu'un appel attendu n'a pas eu lieu.
- `time.sleep` réel dans les tests de reprise : une suite de 2 minutes que personne ne lance.
- Paquet de tests sans `__init__.py` et imports relatifs : `ModuleNotFoundError` selon le mode d'import de pytest.

**En production chez MédiSphère**

Le rapport JUnit (`rapports/junit-pytest.xml`) s'affiche dans la MR (E24) ; la couverture est suivie, avec un seuil qui ne baisse pas (règle d'équipe, pas un absolu).

---

### M02-E19 — Configuration et secrets des outils

**Solution**

Version consolidée : [`config.py`](fichiers/M02-E20/outils/src/medictl/config.py), commande `config` et `fabriquer_client` de [`cli.py`](fichiers/M02-E20/outils/src/medictl/cli.py), filtre `MasqueSecrets` de [`journal.py`](fichiers/M02-E20/outils/src/medictl/journal.py), tests [`test_config.py`](fichiers/M02-E20/outils/tests/python/test_config.py).

1. Œil d'attaquant : `source` ou `eval` d'un fichier contenant `PVE_NODE="$(touch /tmp/pirate)"` **exécute** la commande, avec les droits de celui qui lance l'outil (et sous systemd, ceux du service). En Python, `shlex.split` découpe sans exécuter. Le test :
   ```python
   def test_le_fichier_n_est_jamais_execute(tmp_path):
       temoin = tmp_path / "pirate"
       fichier = tmp_path / "env"
       fichier.write_text(f'PVE_NODE="$(touch {temoin})"\n')
       assert lire_fichier_env(fichier)["PVE_NODE"] == f"$(touch {temoin})"
       assert not temoin.exists()
   ```
   (Côté Bash, `lib/ms-commun.sh` **source** le fichier : c'est acceptable seulement parce qu'il refuse tout fichier accessible à d'autres. C'est l'écart à noter dans la MR.)
2. `charger_config(environ=None)` : chemin `MEDICTL_ENV_FILE` (défaut `~/.config/workbook/pve-api.env`) ; s'il existe, contrôle `stat.S_IMODE(mode) & 0o077` (sinon `ConfigError` « … mode 644 … corrige ses droits ») puis lecture ; ensuite chaque `PVE_*` non vide de l'environnement l'emporte ; validations ; `PveConfig(api_url, node, token_id, token_secret=field(repr=False), cacert, sources)` où `sources` dit, pour chaque clé, « fichier » ou « environnement ». La configuration a quitté `pve.py` ; les noms de E08 (`PveConfig`, `ConfigError`) sont conservés. Le paramètre change par rapport à E08 (`environ` au lieu de `chemin` : le fichier se choisit désormais par `MEDICTL_ENV_FILE`, comme en production) ; un appel sans argument, le seul que font la CLI et la vérification de E08, se comporte comme avant. `pve.py` réimporte `PveConfig`, `ConfigError` et `charger_config`, et garde `connexion()` : `from medictl.pve import ConfigError, charger_config, connexion` fonctionne toujours.
3. `medictl config` :
   ```
   admin@adm01:~$ PVE_NODE=pve02 medictl config
   PVE_API_URL=https://192.168.1.20:8006/api2/json   [/home/admin/.config/workbook/pve-api.env]
   PVE_NODE=pve02   [environnement]
   PVE_TOKEN_ID=wb-automation@pve!lab   [/home/admin/.config/workbook/pve-api.env]
   PVE_TOKEN_SECRET=****   [/home/admin/.config/workbook/pve-api.env]
   PVE_CACERT=/home/admin/.config/workbook/pve-root-ca.pem   [/home/admin/.config/workbook/pve-api.env]
   admin@adm01:~$ install -m 644 ~/.config/workbook/pve-api.env /tmp/ouvert.env; MEDICTL_ENV_FILE=/tmp/ouvert.env medictl vm list; echo "code $?"; rm /tmp/ouvert.env
   medictl : /tmp/ouvert.env est accessible à d'autres que son propriétaire (mode 644) : il contient un secret, corrige ses droits avant de continuer
   code 1
   ```
4. Filtre de journalisation : `fabriquer_client()` enregistre le secret (`journal.masquer(cfg.token_secret)`) ; le filtre, posé sur le **gestionnaire**, remplace le secret par `****` dans le message final de tout enregistrement, y compris venant de proxmoxer ou urllib3. Utile parce que le code d'aujourd'hui ne journalise pas le secret, mais celui de demain (un `log.debug("requête %s", requete.headers)` ajouté pendant un diagnostic) le pourrait.
5. Tests : voir `test_config.py` (priorité, 644 refusé, configuration par l'environnement seul, `http://`, chemin, forme du jeton, CA illisible, `repr`, `medictl config`, `-vvv vm list` sans secret avec `responses`).
6. Vérification du dépôt sans taper le secret :
   ```
   admin@adm01:~/src/outils$ git log --all -p | grep -cF -f <(. ~/.config/workbook/pve-api.env; printf '%s\n' "$PVE_TOKEN_SECRET")
   0
   ```
   S'il apparaissait : **révoquer d'abord** le jeton (`pveum user token remove …`, nouveau jeton, mise à jour du fichier), puis nettoyer l'historique (`git filter-repo`) et prévenir Sophie : un secret poussé sur la forge doit être considéré comme compromis, nettoyage ou pas.
7. Écarts Bash/Python : même priorité et même refus des droits ; le Bash source le fichier (exécution), le Python le lit ; le Bash n'a pas d'équivalent de `medictl config`.

**Explications**

- **Ordre de priorité explicite et visible** : la question « pourquoi l'outil parle-t-il à ce serveur ? » a toujours une réponse (`medictl config`). Les variables d'environnement l'emportent parce que c'est le mécanisme de la CI et des essais ponctuels.
- **`repr=False`** : un `print(cfg)`, une exception qui affiche l'objet, un débogueur ne montrent pas le secret.
- **Droits du fichier** : la même règle que `ssh` pour les clés privées ; refuser plutôt qu'avertir, parce qu'un avertissement dans un cron n'est lu par personne.

**Alternatives**

- `python-dotenv` : lit les fichiers `.env` (même logique, une dépendance) ; `pydantic-settings` : configuration typée avec priorité des sources.
- Trousseau du système (`keyring`) : secret chiffré au repos, déverrouillé par la session ; peu adapté aux services sans session.
- Vault/OpenBao (module 25) : secret délivré à la demande, durée de vie courte, plus de fichier du tout.

**Pièges classiques**

- `os.environ.get("PVE_TOKEN_SECRET", "valeur-par-defaut")` : un secret dans le code (le défaut de E23).
- Message d'erreur qui inclut la configuration entière (« configuration invalide : PveConfig(…) ») sans `repr=False`.
- Développer `$HOME` dans une valeur entre apostrophes (le shell ne le ferait pas) ou ne pas le développer entre guillemets (le fichier de M00-E17 en dépend).
- Vérifier les droits **après** avoir lu le fichier : le secret a déjà été chargé.

**En production chez MédiSphère**

Les jetons ont une date d'expiration et un propriétaire ; un contrôle planifié prévient 30 jours avant l'expiration. Au module 25, `medictl` lira son secret dans Vault (méthode d'authentification de la machine), et le fichier disparaîtra de `adm01`.

---

### M02-E20 — Taskfile (et Makefile) : les tâches du projet

**Solution**

Fichiers : [`fichiers/M02-E20/outils/Taskfile.yml`](fichiers/M02-E20/outils/Taskfile.yml) et [`Makefile`](fichiers/M02-E20/outils/Makefile) ; l'ensemble du projet à ce stade est dans [`fichiers/M02-E20/outils/`](fichiers/M02-E20/outils/) (dont `.editorconfig` complété, `.gitignore` de E02 avec `.task/` en plus, `pyproject.toml` avec `pytest-cov`).

1. Tâches (`task --list`) :
   ```
   admin@adm01:~/src/outils$ task --list
   task: Available tasks for this project:
   * build:           Construit dist/medictl-*.whl et .tar.gz si les sources ont changé
   * ci:              Enchaînement de la CI (lint, puis tests, puis paquet)
   * clean:           Supprime les produits de construction et les rapports
   * default:         Liste les tâches disponibles
   * install:         Poste de développement : install:systeme puis install:dev (pas sur un poste où medictl vient du registre)
   * lint:            Toutes les analyses statiques
   * setup:           Crée ou met à jour .venv exactement selon uv.lock
   * test:            Tous les tests (« task test:py -- -k garde » pour filtrer pytest)
   * install:dev:     medictl depuis la copie de travail (uv tool) — installation de développement
   * install:systeme: Copie figée de bin/ et lib/ dans /usr/local (sudo, root) — ce qu'exécutent les services planifiés
   * lint:py:         ruff (règles du pyproject.toml) et vérification du format
   * lint:sh:         ShellCheck et shfmt sur les scripts Bash et les tests bats
   * test:bats:       Tests des scripts Bash (API Proxmox simulée)
   * test:py:         Tests de medictl avec couverture (aucun appel au vrai Proxmox)
   ```
   `build` :
   ```yaml
   build:
     desc: Construit dist/medictl-*.whl et .tar.gz si les sources ont changé
     deps: [setup]
     sources: [pyproject.toml, uv.lock, README.md, src/**/*.py]
     generates: [dist/*.whl]
     cmds:
       - rm -rf dist
       - uv build
   ```
   Deuxième `task build` : `task: Task "build" is up to date`. `task --status build` sort en 0 si la tâche est à jour (non nul sinon) : c'est une question, pas une exécution.
2. `setup` (`uv sync --locked`, `run: once`) : `--locked` refuse de continuer si `uv.lock` ne correspond plus à `pyproject.toml`, au lieu de le réécrire en silence ; en CI comme en local, on teste exactement les versions verrouillées.
3. Installation, en trois tâches :
   ```yaml
   install:systeme:
     preconditions:
       - sh: git diff --quiet HEAD -- bin lib
         msg: "bin/ ou lib/ contient des modifications non commitées : on n'installe que du code versionné"
     cmds:
       - sudo install -d -m 755 {{.PREFIX}}/bin {{.PREFIX}}/lib
       - sudo install -m 644 -o root -g root lib/ms-commun.sh {{.PREFIX}}/lib/ms-commun.sh
       - sudo install -m 755 -o root -g root bin/ms-* {{.PREFIX}}/bin/
   install:dev:
     cmds:
       - uv tool install --force --reinstall --from {{.ROOT_DIR}} medictl
   install:
     cmds:
       - task: install:systeme
       - task: install:dev
   ```
   Une copie, parce qu'un service planifié (E26) qui exécute le clone change de comportement dès qu'on change de branche ou qu'on édite un fichier ; et parce qu'on doit pouvoir dire **quelle version** tourne. La précondition garantit que ce qui est installé correspond à un commit. Les deux moitiés sont séparées dès maintenant parce qu'elles n'ont pas le même avenir : en M02-E25, `medictl` s'installera depuis le registre de paquets, et `install:dev` (donc `task install`) remplacerait alors la version publiée par celle du clone. Sur `adm01`, on n'utilisera plus que `task install:systeme` (E26, E46) ; `task install` reste la commande d'un poste de développement.

4. Arguments : `{{.CLI_ARGS}}` dans la commande pytest de `test:py` ; `task test:py -- -k garde -x`.
5. `Makefile` : cibles `.PHONY`, `SHELL := bash` avec `.SHELLFLAGS := -euo pipefail -c`, `$(shell shfmt -f $(wildcard bin lib sbin tests))`, cible fichier `dist/.construit: pyproject.toml uv.lock README.md $(SOURCES_PY) | setup`, `help` qui extrait les commentaires `##`. Trois différences concrètes :
   - Make raisonne en **fichiers et dates** (cibles, prérequis) ; Task en **tâches**, avec des empreintes de contenu optionnelles (`sources`/`generates`, `method: checksum` par défaut). Une tâche sans fichier produit est naturelle dans Task, artificielle dans Make (`.PHONY`).
   - Make exécute chaque ligne de recette dans un shell séparé, exige une tabulation et double les `$` (`$$f`) ; Task exécute ses commandes avec un interpréteur shell intégré (mvdan/sh), sans ces pièges, mais ce n'est pas exactement Bash.
   - Make est installé partout ; Task est un binaire de plus à installer (et à figer) sur chaque machine.
6. README : section « Démarrer » complétée (`task lint`, `task test`, `task build`, `task install`, et `task install:systeme` pour les seuls scripts).
7. Vérifications :
   ```
   admin@adm01:~/src/outils$ task ci && task install
   …
   admin@adm01:~$ medictl --version && /usr/local/bin/ms-snapshot --help | head -n 1
   medictl 0.1.0
   Usage : ms-snapshot [options] (--pool lab | VMID...)
   ```

**Explications**

- **Une interface, plusieurs exécutants** : la CI (E24) appelle `task lint`, `task test`, `task build` ; si une commande change (nouvelle option de pytest), elle change à un seul endroit, et « vert en local, rouge en CI » (E38) devient beaucoup plus rare.
- **`lint` sans options** : ShellCheck lit `.shellcheckrc`, shfmt lit `.editorconfig` ; passer `-i 2` à shfmt **ignore** `.editorconfig` (comportement documenté de shfmt), et deux personnes formatent alors différemment.
- **Rapports JUnit** : `bats --report-formatter junit --output rapports` écrit `rapports/report.xml` ; pytest écrit `rapports/junit-pytest.xml`. Le dossier est déjà ignoré par Git (E02).
- **Variables dynamiques locales** : `SCRIPTS_SH` (`sh: shfmt -f …`) est déclarée dans `lint:sh` : déclarée au niveau du fichier, elle serait évaluée pour **toutes** les tâches, et `task --list` échouerait sur une machine sans shfmt.

**Alternatives**

- `just` : syntaxe proche de Make sans ses pièges, mais pas de reconstruction conditionnelle.
- Scripts `scripts/lint.sh`, `scripts/test.sh` : aucun outil de plus, mais pas de dépendances ni de liste des tâches.
- `nox`/`tox` côté Python : excellents pour tester plusieurs versions de Python, hors sujet pour la partie Bash.

**Pièges classiques**

- `task install` qui fait des liens symboliques vers le clone : le service planifié change quand on édite le clone.
- `sources` sans `generates` : Task ne peut pas savoir si le produit a été supprimé.
- Variable `sh:` globale qui dépend d'un outil absent : tout le Taskfile devient inutilisable.
- Makefile avec des espaces au lieu d'une tabulation : « missing separator ».
- Oublier `.task/` dans `.gitignore` : les empreintes de Task finissent dans les commits.

**En production chez MédiSphère**

Le Taskfile est la documentation exécutable du projet ; le README renvoie vers `task --list`. Sur `runner01`, Task est installé par Ansible au module 04, à la version figée de PLAN.md §6.

---

### M02-E21 — Générer l'inventaire du socle depuis l'API

**Solution** (une solution possible)

Fichiers : [`fichiers/M02-E21/src/medictl/inventaire.py`](fichiers/M02-E21/src/medictl/inventaire.py), [`cli.py`](fichiers/M02-E21/src/medictl/cli.py) (commande `inventaire` ajoutée à la version de E20), [`test_inventaire.py`](fichiers/M02-E21/tests/python/test_inventaire.py).

- **Collecte** : `client.vms()` (un appel), filtre sur l'étiquette `socle`, rôle tiré de `role-<rôle>`, ressources du contrat de E15, et **seulement pour les VMs démarrées** un appel à l'agent (`GET …/agent/network-get-interfaces`) : adresses IPv4 hors `lo`, `127.*` et `169.254.*`. Un agent muet (VM arrêtée, agent absent, 500) donne une liste vide, sans reprise, sans faire échouer l'inventaire.
- **Déterminisme** : tri par VMID, aucun horodatage, aucune valeur instantanée (CPU, mémoire utilisée, durée de fonctionnement) ; seules les ressources **allouées** (`maxcpu`, `maxmem`, `maxdisk`) et l'état figurent. Deux générations sans changement du lab donnent le même texte ; l'historique Git date chaque changement.
- **Intégration** : le bloc généré est encadré de balises :
  ```markdown
  <!-- medictl:inventaire:debut (bloc généré : ne pas modifier à la main) -->

  | VMID | Nom | Rôle | État | vCPU | RAM (Mio) | Disque (Gio) | IPv4 (agent QEMU) |
  |---|---|---|---|---|---|---|---|
  | 1000 | `gw01` | routeur | running | 2 | 2048 | 10.0 | 10.10.10.1, 10.10.20.1, 192.168.1.30 |
  | 1001 | `adm01` | bastion | running | 2 | 4096 | 32.0 | 10.10.10.10 |
  | 1002 | `dns01` | dns | running | 1 | 1024 | 10.0 | 10.10.20.10 |
  | 1004 | `git01` | gitlab | running | 4 | 8192 | 60.0 | 10.10.20.12 |
  | 1007 | `runner01` | runner | running | 2 | 4096 | 30.0 | 10.10.20.15 |

  <!-- medictl:inventaire:fin -->
  ```
  (Valeurs indicatives ; la liste de `gw01` dépend de ses interfaces.) `medictl inventaire --fichier docs/socle/inventaire.md` remplace le bloc s'il existe exactement une fois, l'ajoute en fin de document s'il n'existe pas, **refuse** un document aux balises dupliquées ou inversées, écrit par fichier temporaire puis renommage, et dit « déjà à jour » s'il n'y a rien à changer.
- **MR** sur `plateforme/medisphere` :
  ```
  admin@adm01:~/medisphere$ git switch -c docs/inventaire-genere
  admin@adm01:~/medisphere$ medictl inventaire --fichier docs/socle/inventaire.md
  docs/socle/inventaire.md : bloc d'inventaire mis à jour (5 VM)
  admin@adm01:~/medisphere$ git diff --stat && git commit -am "docs(socle): inventaire des VMs généré par medictl" && git push -u origin HEAD
  ```
  La description de la MR rappelle la commande de régénération et le principe « on ne modifie pas le bloc à la main ».

**Explications**

- **Une source de vérité** : l'hyperviseur sait quelles VMs existent et avec quelles ressources ; l'agent sait quelles adresses elles portent. Le document devient une **vue** relue en MR, pas une saisie.
- **Diff minimal** : la revue ne voit que ce qui a changé dans le lab ; un horodatage dans le bloc produirait un changement à chaque exécution et noierait les vrais.
- **Performances** : un appel pour l'inventaire, un par VM démarrée pour l'agent, aucune reprise sur l'agent ; une dizaine de VMs → une à deux secondes. L'exercice M02-E40 montrera ce qui se passe quand ces principes sont oubliés.

**Alternatives**

- Format JSON ou YAML commité à côté du Markdown (pour les machines), Markdown généré à partir de lui (pour les humains).
- Génération en CI planifiée dans `plateforme/medisphere`, qui ouvre la MR toute seule (jeton de projet) : l'étape suivante logique.
- NetBox (module 06) comme source de vérité, et Proxmox comme réalité à confronter.

**Pièges classiques**

- Inclure la mémoire utilisée, la charge ou la durée de fonctionnement : le fichier change à chaque exécution.
- Interroger l'agent d'une VM arrêtée, avec reprise : des dizaines de secondes perdues par VM.
- Réécrire tout le document : le texte de l'équipe disparaît à la première génération.
- Ne garder que la première adresse de l'agent : souvent `127.0.0.1` ou une adresse de lien local.

**En production chez MédiSphère**

L'inventaire des actifs fait partie des preuves ISO 27001 (A.5.9) : il est régénéré chaque semaine et toute différence avec la source de vérité (NetBox, module 06) ouvre un ticket.

---

### M02-E22 — Revue d'un script Bash du stagiaire

**Lecture du script**

Le fichier, numéroté (`cat -n ressources/M02-E22/collecte-etc.sh`), sert de référence aux numéros de ligne.

- **Sous cron, `COLLECTE_DIR` non définie** : ligne 6, `DEST` est vide ; ligne 12, `[ $DEBUG == "debug" ]` devient `[ == debug ]` (« unary operator expected », le script continue : pas de `set -e` à ce stade) ; ligne 16, `cd $DEST` devient `cd` : **retour dans le dossier personnel** ; ligne 18, `mkdir 20261004` dans `~` ; ligne 21, le jeton part vers 192.168.1.20 sans vérification de certificat ; ligne 22, liste des noms analysée par `grep` ; ligne 24, `set -e` ; lignes 26-30, première VM collectée dans `~/20261004/gw01.tar.gz`, puis `((OK++))` avec `OK=0` renvoie le code 1 → **le script s'arrête** silencieusement après une seule VM. La purge (lignes 33-35) n'est pas atteinte ce jour-là… mais le jour où `((OK++))` est corrigé, elle s'exécute **dans `~`** : `ls -t | tail -n +7` liste tout ce qui n'est pas parmi les 6 éléments les plus récents du dossier personnel, et `rm -rf` les supprime (`.ssh` n'est pas listé par `ls`, mais `DevOpsPrivateCloud`, `src`, `medisphere`, `exports` le sont).
- **`COLLECTE_DIR` définie, API en panne** : `curl -s` échoue sans message, `/tmp/vms.json` est vide (ou contient l'ancienne liste si un autre utilisateur l'a créé…), `HOTES` est vide, la boucle ne fait rien, la purge supprime des collectes, le script affiche « Terminé : 0 hôtes collectés » et sort en 0.
- **Cinq VMs joignables** : une seule collectée (ligne 29), code 1, sans message.

ShellCheck (0.11, règles par défaut) ne signale que des guillemets manquants (SC2086), les accents graves (SC2006) et `ls` (SC2012) : il ne voit ni le secret, ni `cd` vers `~`, ni `((OK++))` sous `set -e`, ni `-k`, ni le contenu des archives. Utile, mais très loin d'une revue.

**Revue**

| N° | Ligne(s) | Défaut | Catégorie | Gravité | Impact concret | Correction |
|---|---|---|---|---|---|---|
| 1 | 16, 33-35 (et 6) | `cd $DEST` sans contrôle, `DEST` vide sous cron, puis purge par `ls -t \| tail \| rm -rf` dans le dossier courant | Fonctionnement / sécurité | **Critique** | Le script s'installe dans `~` et en supprime le contenu (dépôts, exports) dès que la boucle va jusqu'au bout | Chemin absolu obligatoire et vérifié (`${DEST:?}`), pas de `cd`, purge par `find DEST -regex` sur les seuls dossiers au format de l'outil |
| 2 | 8, 13 | Secret Proxmox en clair dans le script (donc dans Git) et affiché en mode `debug` | Sécurité | **Critique** | Fuite du jeton (dépôt, journaux de cron, captures d'écran) : accès aux VMs du pool | Fichier `~/.config/workbook/pve-api.env` (600) lu par `pve_api` ; révoquer ce jeton |
| 3 | 21 | `curl -k` | Sécurité | **Élevée** | Le jeton est envoyé à quiconque se fait passer pour `pve01` | `--cacert "$PVE_CACERT"` (bibliothèque commune) |
| 4 | 28 | `sudo tar czf - /etc` : archives contenant `/etc/shadow`, clés d'hôte SSH, clés privées TLS et WireGuard, secrets GitLab, écrites avec l'umask par défaut (lisibles par tous) | Sécurité | **Élevée** | Copie en clair de tous les secrets du socle sur le bastion, lisible par tout compte local | Exclure les secrets, `umask 077`, et se demander s'il faut cette copie (voir la question de fond) |
| 5 | 24, 29 | `set -e` puis `((OK++))` qui renvoie 1 quand `OK` vaut 0 | Fonctionnement | **Élevée** | Arrêt silencieux après la première VM : une seule collecte par nuit, sans alerte | `OK=$((OK + 1))` ; mode strict dès la ligne 2 |
| 6 | 21-22, 37 | Aucune erreur détectée : `curl -s` sans contrôle, liste vide acceptée, code 0 « Terminé » | Fonctionnement | **Élevée** | API en panne, jeton expiré : « Terminé : 0 hôtes » chaque nuit, personne ne le voit | Code retour non nul si l'inventaire échoue ou si une VM échoue ; liste vide = erreur |
| 7 | 28 | `StrictHostKeyChecking=no` | Sécurité | Moyenne | Collecte (avec `sudo`) vers une machine usurpée, sans alerte | `BatchMode=yes` et clés d'hôte connues (`known_hosts`) |
| 8 | 28 | Archive non vérifiée ; échec SSH ou `sudo` → fichier vide ou tronqué conservé | Fonctionnement | Moyenne | Fausse sauvegarde (le défaut que E03 voulait éliminer) | Écrire dans un dossier temporaire, `gzip --test`, taille non nulle, sinon supprimer et compter l'échec |
| 9 | 22 | JSON analysé par `grep -o` : tous les noms, y compris templates, VMs arrêtées, VMs jetables | Fonctionnement | Moyenne | Collecte tentée sur `tpl-debian13` (échec), sur des VMs de test ; ordre et format fragiles | `jq` : `pool == "lab"`, étiquette `socle`, `status == "running"` |
| 10 | 21 | Fichier temporaire prévisible `/tmp/vms.json` | Sécurité / fonctionnement | Moyenne | Un autre utilisateur peut le préparer (lien symbolique, contenu choisi) ; deux exécutions se l'écrasent | Variable (`$(pve_api …)`) ou `mktemp` |
| 11 | — | Pas de verrou | Fonctionnement | Faible | Cron + lancement manuel : collectes et purges entremêlées | `lock_or_die` (E13) |
| 12 | 7 | Adresse de `pve01` en dur | Maintenabilité | Faible | Script à modifier à chaque changement d'adresse | `PVE_API_URL` du fichier d'accès |
| 13 | partout | Variables non protégées, accents graves, `cat \|` inutile, `[ … == … ]` | Maintenabilité | Faible | Comportements surprenants avec un nom ou une valeur inattendus | Guillemets, `$(…)`, `[[ ]]` |

Remarques mineures : la purge garde `GARDER - 1` collectes (`tail -n +7` saute 6 lignes) ; `mkdir $JOUR` échoue si le script est relancé le même jour (et la seconde collecte écrase la première) ; aucun message ne part sur stderr.

**Ordre de traitement** : d'abord ce qui détruit ou expose (1, 2 — avec révocation immédiate du jeton —, 3, 4), puis ce qui rend le script menteur (5, 6, 8), puis le reste. En pratique : on ne fusionne pas ce script, on révoque le jeton aujourd'hui.

**Version corrigée** : [`fichiers/M02-E22/ms-collecte-etc`](fichiers/M02-E22/ms-collecte-etc) — bibliothèque commune (`pve_api`, `lock_or_die`, journal), `umask 077`, sélection `jq` (pool `lab`, étiquette `socle`, VM démarrée), `ssh -n -o BatchMode=yes`, commande distante protégée (`printf '%q'`), exclusion des fichiers secrets (`tar -C / --exclude=etc/shadow … etc`), archive vérifiée, collecte dans un dossier temporaire publié par `mv -T`, purge par motif exact, code 1 si une VM échoue. Elle passe ShellCheck avec le `.shellcheckrc` du projet.

**Question de fond**

Le script fait double emploi. `ms-collecte-config` (E03) collecte déjà, à la demande et avant intervention, les fichiers de configuration utiles (pas `/etc` entier), avec les mêmes garanties ; les sauvegardes PBS nocturnes (M00-E22, chiffrées en M00-E36) contiennent `/etc` complet de chaque VM, hors du bastion, avec rétention et restauration de fichier testée (M00-E23). Une troisième copie, en clair, sur le bastion, ajoute du risque (tous les secrets du socle au même endroit) sans ajouter de capacité de restauration. Recommandation : ne pas fusionner ; si le besoin est de **comparer** des configurations dans le temps, planifier `ms-collecte-config` ou, mieux, versionner la configuration (Ansible, module 04).

**Conseils à Lucas sur sa méthode de test**
- « Sans erreur » ne veut rien dire pour un script qui ne vérifie aucune erreur : teste les cas qui doivent échouer (API coupée, hôte injoignable, variable absente) et regarde le code retour.
- Teste dans l'environnement réel d'exécution : `env -i HOME=… /chemin/du/script` ou une vraie entrée cron, pas ton terminal où `COLLECTE_DIR` est définie.
- Écris le test avant de corriger (bats, E14) : un faux `ssh` et un faux `curl` auraient montré les défauts 1, 5 et 6 en une minute.

**Explications**

Les défauts les plus graves ne sont pas des erreurs de syntaxe : ce sont des hypothèses fausses sur l'environnement (variable définie, dossier courant, API disponible) et des effets de bord non bornés (`rm -rf` relatif, archives en clair). Une revue efficace suit l'exécution **dans les conditions réelles**, ligne par ligne, avec les valeurs que prendront vraiment les variables.

**Alternatives**

- Réécrire le besoin en Python (`medictl`) : pas de gain particulier ici, le geste est système (SSH, tar).
- Ansible (module 04) : `fetch` de fichiers choisis, inventaire dynamique, rapport par hôte.

**Pièges classiques**

- S'arrêter aux remarques de ShellCheck.
- Corriger le style (guillemets) en laissant la purge relative et le secret en place.
- Oublier que le secret est **déjà** compromis : il est dans l'historique de la branche de Lucas.

**En production chez MédiSphère**

Tout script destiné à cron ou systemd passe par la MR, avec tests bats et exécution d'essai dans un environnement minimal ; les secrets détectés en revue déclenchent une révocation immédiate (procédure de M00-E17), pas seulement une correction du code.

---

### M02-E23 — Revue d'un script Python du stagiaire

**Ce que montre l'exécution**

```
admin@adm01:~/m02/e23$ python3 rapport_capacite.py --depuis-fichier …/cluster-resources-admin.json
pool,ram_go,pourcentage
aucun,49.152,37
lab,22.528000000000002,17
Total alloué : 71.68 Go
admin@adm01:~/m02/e23$ python3 rapport_capacite.py --depuis-fichier …/cluster-resources-admin.json --seuil 50
…
TypeError: '>' not supported between instances of 'float' and 'str'
admin@adm01:~/m02/e23$ python3 rapport_capacite.py --depuis-fichier …/cluster-resources-jeton.json
…
IndexError: list index out of range
admin@adm01:~/m02/e23$ ls
'rapport-2026-10-04 11:52:31.204871.csv'  rapport_capacite.py
```
- Les chiffres : 48 Gio de VMs personnelles + 22 Gio du pool `lab` (dont le template, 1 Gio) = 70 Gio alloués réellement ; le script annonce 71,68 « Go » parce qu'il divise par 1024 × 1024 × 1000 (ni des Gio, ni des Go). Les pourcentages restent justes (même erreur au numérateur et au dénominateur), les valeurs absolues non.
- Avec `--seuil 50`, la valeur reste une chaîne : comparaison impossible, **plantage au moment précis où l'alerte devrait partir**.
- Avec l'export du jeton : aucune entrée `node` (le jeton n'a pas `Sys.Audit` sur `/nodes`) : `noeuds[0]` plante. C'est **ce que verra le cron**, qui utilise le jeton, alors que Lucas a testé avec son export d'administrateur. ⚠️ À vérifier sur ta version : l'absence des nœuds dans `/cluster/resources` pour un jeton sans `Sys.Audit` (compare `pvesh get /cluster/resources` et la même requête avec le jeton).
- `ruff check --select E,F,B,S,SIM` trouve : imports sur une ligne (E401), `requests` sans délai (S113), `verify=False` (S501), `except:` nu (E722), argument par défaut mutable (B006), `open` sans gestionnaire de contexte (SIM115), `os.system` avec un shell (S605). Il ne trouve ni le secret par défaut (dans un appel à `os.environ.get`), ni le type de `seuil`, ni les unités, ni `noeuds[0]`, ni les codes de sortie.

**Revue**

| N° | Ligne(s) | Défaut | Catégorie | Gravité | Impact concret | Correction |
|---|---|---|---|---|---|---|
| 1 | 11 | Secret par défaut dans le code | Sécurité | **Critique** | Jeton dans Git, valable pour tout le pool ; utilisé silencieusement si la variable manque | Aucun défaut : configuration obligatoire (fichier 600 ou environnement), erreur claire sinon ; révoquer ce jeton |
| 2 | 8, 18 | `verify=False` et avertissements urllib3 désactivés | Sécurité | **Élevée** | Jeton envoyé à n'importe quel serveur qui se fait passer pour `pve01`, sans le moindre avertissement | `verify=PVE_CACERT` (ou `True`) |
| 3 | 46 (et 41) | `noeuds[0]` : un seul nœud supposé, et invisible pour le jeton du cron | Fonctionnement | **Élevée** | Plantage systématique en production ; au module 09 (trois nœuds), résultat faux | Somme des nœuds visibles ; si aucun : erreur explicite ou capacité passée en option ; jeton d'audit si l'on veut la vue complète |
| 4 | 15-22 | Boucle infinie de reprise, `except:` nu | Fonctionnement | **Élevée** | API coupée : le cron ne se termine jamais (et s'empile chaque nuit) ; Ctrl-C est avalé (`KeyboardInterrupt` attrapé) | Reprises bornées sur erreurs transitoires seulement, exceptions précises |
| 5 | 18 | Pas de délai (`timeout`) | Fonctionnement | **Élevée** | Une connexion qui ne répond pas bloque le script indéfiniment | `timeout=(5, 30)` |
| 6 | 19 | Statut HTTP ignoré : 401/403 → `data` vaut `None` | Fonctionnement | Moyenne | Jeton expiré : `TypeError` incompréhensible plus loin | Vérifier `status_code`, message « jeton refusé (401) » |
| 7 | 25-31 | `except Exception: return []` | Fonctionnement | Moyenne | Export illisible ou API en erreur → liste vide → plantage ailleurs (ou rapport vide présenté comme valide) | Laisser remonter, ou erreur explicite avec la cause |
| 8 | 63, 53 | `seuil` reste une chaîne quand l'option est donnée | Fonctionnement | Moyenne | Plantage dès qu'on change le seuil | `argparse` avec `type=float` |
| 9 | 34-37 | Argument par défaut mutable `cumul={}` | Fonctionnement | Moyenne | Le dictionnaire est partagé entre les appels : deuxième rapport dans le même processus (tests, boucle) = valeurs doublées | Accumulateur local à `rapport()` (`defaultdict(float)`) |
| 10 | 36, 46 | Unités : `/1024/1024/1000` affiché « Go » | Fonctionnement | Moyenne | Capacité surestimée de 2,4 % (ou sous-estimée de 4,6 % par rapport à des Go) : on achète de la mémoire sur un faux chiffre | Gio (`/ 1024**3`), unité dans l'en-tête |
| 11 | 42-45 | Templates comptés comme de la mémoire allouée | Fonctionnement | Faible | Surestimation (un template ne démarre jamais) | Exclure `template == 1` ; garder les VMs arrêtées (capacité réservée), et le dire |
| 12 | 66-73 | Code de sortie toujours 0, alerte par `os.system(… mail …)` sans contrôle | Fonctionnement | Moyenne | `mail` absent sur `adm01` : alerte perdue en silence ; cron ne voit jamais rien | Code 1 si seuil dépassé ou erreur ; laisser cron/systemd notifier (E26) ; `subprocess.run([...], check=True)` si un envoi est vraiment nécessaire |
| 13 | 73 | Valeurs insérées dans une commande shell (f-string) | Sécurité | Faible | Ici des nombres : pas exploitable aujourd'hui, mais le jour où l'on y met un nom de pool… | Liste d'arguments, jamais de shell |
| 14 | 67-69 | Fichier écrit dans le dossier courant (en cron : `~`), nom avec espaces et `:`, jamais fermé, CSV assemblé à la main | Maintenabilité | Faible | Fichiers mal nommés qui s'accumulent ; écriture partielle possible | Option `--csv`, module `csv`, `with`, écriture atomique |
| 15 | 57-73 | Code au niveau du module, analyse manuelle de `sys.argv` | Maintenabilité | Faible | Impossible d'importer le module dans un test sans lancer le rapport ; `--seuil` sans valeur → `IndexError` | `main(argv)` + `if __name__ == "__main__"`, `argparse` |

**Version corrigée** : [`fichiers/M02-E23/rapport_capacite.py`](fichiers/M02-E23/rapport_capacite.py) — `argparse`, configuration lue sans exécution (droits vérifiés, aucun secret par défaut), session requests avec `Retry` borné sur GET, autorité passée à **chaque** requête (`verify=PVE_CACERT` : fixée sur la session, `REQUESTS_CA_BUNDLE` la remplacerait), délai, fonctions pures (`ram_hote`, `calculer`), `--ram-hote-gio` quand les nœuds sont invisibles, CSV par le module `csv` (et écriture atomique avec `--csv`), codes de sortie : 0 sous le seuil, 1 seuil dépassé ou erreur, 2 usage.
```
admin@adm01:~/m02/e23$ python3 rapport_capacite.py --depuis-fichier …/cluster-resources-admin.json --seuil 50; echo "code $?"
pool,ram_gio,pourcentage
(hors pool),48.0,37.5
lab,21.0,16.4
ERROR ALERTE capacité : 69.0 Gio alloués sur 128.0 Gio (54 %, seuil 50 %)
code 1
admin@adm01:~/m02/e23$ python3 rapport_capacite.py --depuis-fichier …/cluster-resources-jeton.json; echo "code $?"
ERROR aucun nœud visible (jeton sans Sys.Audit ?) : indique --ram-hote-gio, ou utilise un jeton d'audit qui voit tout l'hôte
code 1
```
(69 Gio : sans le template.)

**Réponse à Claire**

Pas en l'état : il plante en production (le jeton du cron ne voit pas le nœud), son unité est fausse, et il ne sait pas alerter. Corrigé, il donne un chiffre juste **de ce que le jeton voit** : avec `wb-automation@pve!lab`, seulement le pool `lab` (21 Gio sur 128), pas les 48 Gio des VMs personnelles qui occupent pourtant la même mémoire. Pour décider d'un achat, il faut la vue de tout l'hôte : un jeton d'audit dédié (rôle `PVEAuditor` sur `/`, lecture seule, validé avec Sophie car il voit aussi les VMs hors lab), ou les métriques de l'hyperviseur (module 21). D'ici là, le rapport peut servir à suivre la croissance du lab, pas à dimensionner l'hôte.

**Explications**

Le script « marche avec mon export » parce que l'export a été fait avec d'autres droits que ceux de la production : c'est le défaut le plus instructif. Les autres sont des classiques de Python d'exploitation : réseau sans délai, exceptions avalées, état partagé caché, types issus de la ligne de commande, unités implicites.

**Alternatives**

- Intégrer la fonctionnalité à `medictl` (`medictl capacite`), qui a déjà configuration, client, reprises et tests.
- Prometheus + `pve-exporter` (module 21) : métriques historisées, alertes, graphiques ; le bon outil pour la capacité.

**Pièges classiques**

- Tester avec des droits d'administrateur un outil qui tournera avec un jeton restreint.
- Confondre « liste vide » et « rien à signaler ».
- Faire confiance aux seuls outils d'analyse statique : ruff a trouvé sept types de défauts (plus des lignes trop longues), mais aucun des trois qui faussent ou empêchent le résultat (droits du jeton, unités, type du seuil).

**En production chez MédiSphère**

Les rapports de capacité viennent de la supervision (module 21), avec historique et projection ; un script de ce type sert d'audit ponctuel, et sa sortie est versionnée avec la décision d'achat.
