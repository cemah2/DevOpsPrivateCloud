# Module 02 — Palier 2 : Opérationnel

Le projet `plateforme/outils` existe, la forge le protège, et tu as écrit tes premiers scripts « qui disent la vérité ». Il faut maintenant passer à l'échelle : un deuxième script Bash qui recopie les mêmes vingt lignes de gestion d'erreur que le premier, c'est un troisième qui les oubliera. Ce palier construit le **socle commun** des outils de l'équipe : une bibliothèque Bash partagée, des scripts qui traitent n'importe quel nom de fichier, qui ne se marchent pas dessus quand cron et un humain les lancent en même temps, et qui sont **testés** sans jamais toucher au vrai Proxmox. Côté Python, `medictl` devient une vraie CLI : lister, décrire, créer et détruire des VMs jetables avec des garde-fous, échouer proprement, se tester, se configurer sans laisser traîner de secret. Le palier se termine par l'orchestration des tâches du projet, un premier livrable de documentation généré depuis l'API, et deux revues de code du stagiaire.

> **Rappels** : tout se fait depuis `adm01`, dans la copie de travail `~/src/outils` ; chaque exercice se termine par une MR fusionnée dans `main` (pipeline vert). Conventions communes (codes retour 0/1/2/3, stdout pour les données, secrets, TLS) : voir [`00-introduction.md`](00-introduction.md). VMs jetables de ce palier : **2020** `m02-cobaye` (E11 à E16) et **2021** `m02-test` (E16), pool `lab`, VNet `vsandbox`, étiquette `env-m02`.

---

### M02-E10 — Bibliothèque Bash commune `lib/ms-commun.sh`  `LAB` `★★`

> **Ticket PLAT-320** — *De : Karim Benali*
> J'ai relu `ms-collecte-config` et deux scripts en cours : chacun a sa fonction `die`, son format de journal, sa façon d'appeler l'API Proxmox (dont une qui met le jeton dans la ligne de commande de `curl`…). On factorise. Une bibliothèque, `lib/ms-commun.sh`, avec une API **figée** : les scripts des prochains mois s'appuieront dessus, et la CI de E24 la testera. Fais-la petite, prévisible, et sans effet de bord sur le script qui la charge.

**Objectifs pédagogiques**
- Concevoir une bibliothèque Bash chargée par `source` : garde contre l'exécution directe, chargement unique, aucune option de shell imposée.
- Maîtriser les pièges des fonctions : portée dynamique des variables `local`, `exit` dans une substitution `$(…)`, `set -e` suspendu dans un `if` ou un `&&`.
- Appeler l'API Proxmox avec `curl` sans exposer le secret, et restituer le motif d'erreur que Proxmox place dans la ligne de statut HTTP.
- Suivre une tâche asynchrone (UPID) de façon réutilisable.

**Prérequis** : M02-E03, M02-E04, M02-E05 ; M00-E17 et M00-E18 (jeton, UPID).
**Durée indicative** : 3 h.

**Contexte technique**

API à fournir (les vérifications, les autres scripts du module et les tests de E14 s'y fient) :

| Fonction | Contrat |
|---|---|
| `log_info`, `log_warn`, `log_err MSG…` | une ligne sur **stderr** : horodatage ISO 8601 (avec fuseau), nom du script, PID, niveau, message ; rien sur stdout |
| `die MESSAGE [CODE]` | journalise l'erreur et quitte avec CODE (1 par défaut) |
| `require_cmd CMD…` | quitte en 1 si au moins une commande manque, en les citant toutes |
| `confirm QUESTION` | 0 si l'opérateur répond oui ; sans terminal sur l'entrée standard : refus (code ≠ 0), sauf si `MS_YES=1` |
| `retry N DÉLAI CMD…` | au plus N tentatives, délai initial DÉLAI secondes (0 accepté), doublé après chaque échec ; renvoie le code du dernier échec |
| `pve_api MÉTHODE /CHEMIN [clé=valeur…]` | GET, POST, PUT, DELETE sur l'API ; affiche le champ `data` en JSON compact sur stdout ; code 1 et message clair (avec le code HTTP et le motif renvoyé par Proxmox) sur erreur réseau, TLS ou HTTP |
| `pve_wait_task UPID [DÉLAI_MAX]` | attend la fin de la tâche ; 0 si `exitstatus` vaut `OK` (ou `WARNINGS…`), 1 si elle échoue ou dépasse DÉLAI_MAX secondes (défaut 600) |

- Chargement, en tête de chaque script de `bin/` (après le mode strict) : `source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/ms-commun.sh"`. `readlink -f` résout les liens symboliques ; `BASH_SOURCE[0]` plutôt que `$0` permet aussi de charger un script par `source` dans les tests (E14).
- Fichier d'accès à l'API : `${MS_PVE_ENV:-~/.config/workbook/pve-api.env}` (format M00-E17). Les variables `PVE_*` déjà présentes dans l'environnement l'emportent (cas de la CI). Un fichier accessible au groupe ou aux autres est **refusé**. Le contrôle planifié de E26 utilisera `MS_PVE_ENV` pour pointer vers un jeton en lecture seule.
- TLS vérifié avec `PVE_CACERT` ; le secret ne doit apparaître ni dans la liste des processus, ni dans `set -x`, ni dans un fichier temporaire lisible.
- Codes retour communs : 0, 1, 2 (usage), 3 (garde-fou).

**Travail demandé**
1. Avant d'écrire, réponds dans ton journal : pourquoi une bibliothèque ne doit-elle pas faire `set -euo pipefail` ? Que se passe-t-il si un script la charge deux fois ? Comment détecter qu'elle a été **exécutée** au lieu d'être chargée ?
2. Écris la journalisation, `die`, `require_cmd`, `confirm`. Expérience à noter : `x="$(die "oups")"` dans un script en mode strict. Qui s'arrête, le sous-shell ou le script ? Et avec `local x="$(die "oups")"` ?
3. Écris `retry`. Teste-la avec une fonction qui compte ses appels dans une variable `n` :
   ```
   admin@adm01:~/src/outils$ bash -c 'source lib/ms-commun.sh; n=0; f() { n=$((n+1)); ((n >= 3)); }; retry 5 0 f; echo "n=$n"'
   ```
   Le résultat est-il celui que tu attends ? Explique dans ton journal ce que révèle ce test sur `local` en Bash, et protège ta fonction.
4. Écris `pve_api`. Choisis comment passer le jeton à `curl` sans qu'il apparaisse dans `ps` et justifie. Récupère le code HTTP **et** le motif de la ligne de statut (Proxmox y écrit par exemple `403 Permission check failed (/nodes/pve01, Sys.Syslog)`), ainsi que le champ `errors` des réponses 400. Teste : `GET /version`, `GET /nodes/<NŒUD>/syslog` (refusé au jeton), un `POST` avec un paramètre invalide.
5. Écris `pve_wait_task` (souviens-toi de M00-E18 : l'UPID contient des `:` et des `!`, et le nœud qui exécute la tâche est dans l'UPID).
6. En tête du fichier, documente l'API (une ligne par fonction, variables reconnues, codes). ShellCheck muet, avec les règles du `.shellcheckrc` du projet.
7. MR `feat(lib): bibliothèque commune ms-commun.sh`, fusion.

**Critères de réussite**
- [ ] Exécutée directement (`bash lib/ms-commun.sh`), la bibliothèque refuse avec un code non nul ; chargée, elle ne modifie pas les options du shell.
- [ ] Les journaux partent sur stderr au format demandé ; `die` respecte le code demandé.
- [ ] `retry` fait exactement N tentatives, même quand la commande utilise une variable `n`.
- [ ] `pve_api GET /version` affiche un objet JSON ; un refus de l'API donne un code 1 et un message qui cite le code HTTP et le motif.
- [ ] Un fichier d'accès en mode 644 est refusé ; le secret n'apparaît jamais dans les arguments de `curl`.
- [ ] La bibliothèque est sur `main`.

**Vérification** : `lab/bin/check 02 10`

<details><summary>Indice 1</summary>

Comparer `${BASH_SOURCE[0]}` et `$0` dit si le fichier est exécuté ou chargé. Pour le chargement unique, une variable témoin suffit, suivie d'un `return` (pas `exit` : on est dans le shell de l'appelant).
</details>

<details><summary>Indice 2</summary>

`curl -H @fichier` lit les en-têtes dans un fichier, et `<(…)` fournit un « fichier » qui n'existe que dans `/dev/fd`. `curl --include` met la ligne de statut et les en-têtes devant le corps, séparés par une ligne vide en CRLF. Pense à `--suppress-connect-headers` au cas où un mandataire s'intercale.
</details>

<details><summary>Indice 3</summary>

En Bash, une variable `local` est visible des fonctions **appelées** (portée dynamique) : la commande passée à `retry` voit ses variables locales. Des noms préfixés (`_ms_…`) évitent la collision.
</details>

**Pour aller plus loin** (facultatif) : ajoute un mode `MS_DEBUG=1` qui journalise chaque appel d'API (méthode, chemin, durée) **sans** les paramètres ni l'en-tête ; mesure le coût d'un `source` de la bibliothèque (`time`) ; lis la page « BashFAQ/105 » (pourquoi `set -e` surprend) sur mywiki.wooledge.org.

---

### M02-E11 — `ms-snapshot` : instantanés du lab avant intervention  `LAB` `★★`

> **Ticket PLAT-321** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Règle d'astreinte à partir de lundi : **pas d'intervention sur une VM sans instantané pris juste avant**. Aujourd'hui on clique dans l'interface, avec des noms au hasard (« test », « avant », « avant2 »), et personne ne fait le ménage : la semaine dernière, un disque de `git01` s'est rempli d'instantanés oubliés. Je veux une commande, un nommage unique, et une rotation qui ne touche **qu'aux instantanés de l'outil**.

**Objectifs pédagogiques**
- Piloter les instantanés par l'API (`/nodes/{node}/qemu/{vmid}/snapshot`) et suivre leurs tâches (UPID).
- Écrire un outil qui valide **tout** avant d'agir (« tout ou rien ») et n'agit que dans son périmètre.
- Écrire une rotation sûre : sélection par motif exact, tri par date, jamais de purge si la création a échoué.
- Fournir un mode simulation (`--dry-run`) fidèle.

**Prérequis** : M02-E10.
**Durée indicative** : 3 h.

**Contexte technique**
- Usage imposé : `ms-snapshot [-n|--dry-run] [-k|--keep N] [-p|--prefix PRÉFIXE] (--pool lab | VMID...)`. Nom créé : `<PRÉFIXE>-AAAAMMJJ-HHMMSS`, préfixe `avant` par défaut, **même horodatage** pour toutes les VMs d'une exécution ; `--keep` vaut 3 par défaut (minimum 1).
- Proxmox : un nom d'instantané suit le format `pve-configid` (une lettre, puis lettres, chiffres, `_` ou `-`) et fait 40 caractères au plus. Le jeton `wb-automation@pve!lab` a déjà `VM.Snapshot` (M00-E17). La liste des instantanés contient une entrée `current` qui n'en est pas un.
- Codes : 0 succès ; 1 au moins une VM en échec ; 2 usage (option inconnue, valeur invalide, `--pool` et VMID ensemble) ; 3 refus (VM hors pool `lab`, invisible, template, pool autre que `lab`).
- VM d'essai : **2020** `m02-cobaye`, créée avec le script de M00-E18 :
  ```
  admin@adm01:~$ VMID=2020 VMNAME=m02-cobaye NET0="virtio,bridge=vsandbox" ~/lab-scripts/vm-api.sh create
  ```
  Elle restera en place jusqu'à M02-E16, qui la détruira avec `medictl`.

**Travail demandé**
1. Explore à la main avec `pve_api` (charge la bibliothèque dans un shell) : liste des instantanés de 2020, création d'un instantané, suivi de la tâche, suppression. Note la forme exacte des réponses (champ `snaptime`, entrée `current`, `parent`).
2. Pose l'étiquette `env-m02` sur 2020 **par l'API** (paramètre `tags` de `POST …/config`), puis, sur `pve01`, un instantané « humain » que l'outil ne devra jamais toucher :
   ```
   root@pve01:~# qm snapshot 2020 manuel-karim --description "posé à la main avant migration"
   ```
3. Écris `bin/ms-snapshot`. Exigences : toutes les cibles sont validées **avant** la première écriture (une seule VM refusée → rien n'est fait, code 3) ; la création attend la fin de sa tâche ; la purge ne considère que les noms **exactement** de la forme `<PRÉFIXE>-AAAAMMJJ-HHMMSS`, garde les N plus récents et ne s'exécute jamais si la création a échoué sur cette VM ; une VM en échec n'empêche pas les autres d'être traitées.
4. Écris `--dry-run` : aucune requête d'écriture, mais l'affichage de ce qui **serait** créé et supprimé (y compris la purge que provoquerait le nouvel instantané).
5. Isole la logique de sélection dans une fonction qui lit la liste JSON sur l'entrée standard et écrit les noms à supprimer : tu la testeras en E14 sans API. Le script doit pouvoir être chargé par `source` sans s'exécuter.
6. Lance cinq fois `ms-snapshot 2020` (à quelques secondes d'intervalle), puis `ms-snapshot --prefix avant-maj --keep 1 2020`. Regarde le résultat dans l'interface et avec `qm listsnapshot 2020` : combien d'instantanés `avant-…` ? `avant-maj-…` ? `manuel-karim` est-il intact ?
7. Questions pour le journal : pourquoi le préfixe `avant` ne doit-il pas capturer `avant-maj-20261004-101500` ? Que se passe-t-il si deux exécutions de l'outil tournent en même temps sur la même VM (tu le traiteras en E13) ? Un instantané sans état mémoire d'une VM démarrée est-il cohérent pour une base de données ?
8. ShellCheck muet, MR, fusion.

**Critères de réussite**
- [ ] `--help` sort en 0 ; option inconnue, absence de cible, `--keep 0` sortent en 2 ; le template 9000, un VMID inexistant et `--pool production` sont refusés en 3 sans aucune écriture.
- [ ] Le journal des tâches de `pve01` montre des `qmsnapshot` **et** des `qmdelsnapshot` sur 2020 exécutés par `wb-automation@pve!lab`.
- [ ] 2020 garde au plus 3 instantanés `avant-AAAAMMJJ-HHMMSS` ; `manuel-karim` existe toujours.
- [ ] `--dry-run` ne crée ni ne supprime rien.
- [ ] Le script charge `lib/ms-commun.sh`, passe ShellCheck et est sur `main`.

**Vérification** : `lab/bin/check 02 11` (avant de détruire 2020 en E16)

<details><summary>Indice 1</summary>

`GET /cluster/resources?type=vm` donne en un seul appel, pour chaque VM visible : `vmid`, `node`, `pool`, `template`, `name`. Une VM hors du pool est **invisible** pour le jeton : « absente » et « interdite » se confondent, et c'est très bien ainsi.
</details>

<details><summary>Indice 2</summary>

Avec jq : `test("^" + $p + "-[0-9]{8}-[0-9]{6}$")`, `sort_by(.snaptime)`, puis une tranche `.[0:length-N]` (attention aux longueurs négatives). Le préfixe vient de l'utilisateur : comme il a été validé (lettres, chiffres, `_`, `-`), il ne contient aucun caractère spécial d'expression régulière.
</details>

<details><summary>Indice 3</summary>

`if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi` en fin de script : exécuté, il tourne ; chargé par `source`, il expose seulement ses fonctions.
</details>

**Pour aller plus loin** (facultatif) : ajoute une option `--vmstate` (instantané avec la mémoire) et mesure la différence de durée et d'espace ; lis dans la documentation de Proxmox VE (chapitre « Snapshots » de `qm`) quels types de stockage acceptent les instantanés. M02-E27 rendra l'outil idempotent.

---

### M02-E12 — Traiter des fichiers en masse sans piège (espaces, `-print0`, tableaux)  `LAB` `★★`

> **Ticket PLAT-322** — *De : Claire Morel*
> InfoGér nous a rendu ses « exports » : des années de rapports, factures et sauvegardes de configuration, dans une arborescence où les noms de fichiers ont été tapés par des humains sous Windows. On garde tout (obligation contractuelle), mais rangé par mois et avec une preuve d'intégrité, comme pour les photos de `hp01`. Leur script de rangement a perdu une centaine de fichiers l'an dernier « à cause des espaces ». Le nôtre ne perdra rien.

**Objectifs pédagogiques**
- Parcourir une arborescence avec `find -print0` et lire le résultat sans le découper (`mapfile -d ''`, `read -d ''`).
- Manipuler des chemins quelconques : espaces, tiret initial, `*`, `?`, `[`, retour à la ligne, guillemets, antislash, UTF-8.
- Récupérer le code de retour d'une commande lancée en substitution de processus.
- Produire une preuve d'intégrité vérifiable (`sha256sum`), y compris pour des noms exotiques.

**Prérequis** : M02-E10.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Jeu de données (fictif, jetable) fabriqué par le workbook :
  ```
  admin@adm01:~$ mkdir -p ~/m02/e12 && ~/DevOpsPrivateCloud/modules/02-scripting/ressources/M02-E12/fabriquer-jeu.sh ~/m02/e12
  ```
  Il crée `~/m02/e12/exports-infoger/` : 35 fichiers ordinaires (dont 32 de plus de 90 jours), un lien symbolique, un fichier vide, un fichier caché, un dossier vide. **Ne regarde pas les noms avant d'avoir écrit ton script** : c'est le jeu de test, pas la spécification.
- Contrat de `bin/ms-ranger` :

| Élément | Exigence |
|---|---|
| Usage | `ms-ranger [-n\|--dry-run] [-a\|--age JOURS] [--] SOURCE DESTINATION` ; `--age` vaut 90 par défaut, au sens de `find -mtime +JOURS` |
| Sélection | fichiers **ordinaires** de SOURCE, sous-dossiers et fichiers cachés compris ; les liens symboliques ne sont ni suivis ni déplacés (comptés et signalés) |
| Destination | `DESTINATION/AAAA-MM/<chemin relatif dans SOURCE>`, AAAA-MM étant le mois de dernière modification du fichier |
| Écrasement | jamais : un fichier déjà présent à la destination est un conflit (signalé, source laissée en place, code final 1) |
| Preuve | manifeste `DESTINATION/MANIFESTE-*.sha256` au format de `sha256sum` (chemins relatifs à DESTINATION), empreintes calculées **avant** le déplacement, puis tout le manifeste revérifié **après** |
| Garde-fou | SOURCE et DESTINATION l'un dans l'autre : refus, code 3, avant toute action |
| Codes | 0 tout rangé ; 1 au moins un conflit ou une erreur ; 2 usage ; 3 refus |

**Travail demandé**
1. Écris d'abord, dans ton journal, la version « naïve » à laquelle tout le monde pense (`for f in $(find …)`) et prédis ce qu'elle fera sur un nom contenant deux espaces, `*`, ou un retour à la ligne. Vérifie sur trois fichiers de ton choix créés à la main dans `~/m02/e12/essais/`.
2. Écris `bin/ms-ranger` selon le contrat. Toute la chaîne doit être sûre : sélection, calcul du mois, création du dossier cible, déplacement, ligne de manifeste, messages.
3. Un `find` qui échoue (droits) dans `< <(find …)` ne fait pas échouer ton script : rends cette erreur fatale **avant** tout déplacement. Comment récupérer son code ?
4. Le format du manifeste : que fait `sha256sum` d'un nom contenant un retour à la ligne ou un antislash ? Ton manifeste doit être relu sans erreur par `sha256sum --check`.
5. Lance `--dry-run`, puis le vrai rangement vers `~/m02/e12/archive`. Vérifie le manifeste. Relance : que fait l'outil la seconde fois ?
6. Affiche les noms dans tes messages de façon non ambiguë (un retour à la ligne dans un nom ne doit pas couper une ligne de journal en deux). Quelle construction Bash utilises-tu ?
7. ShellCheck muet, MR, fusion.

**Critères de réussite**
- [ ] Sur un jeu neuf, les 32 vieux fichiers sont rangés au bon mois, noms intacts ; les 3 récents et le lien symbolique restent en place.
- [ ] `sha256sum --check` valide le manifeste ; il compte 32 lignes.
- [ ] `--dry-run` ne déplace rien ; une seconde exécution ne déplace rien et sort en 0.
- [ ] DESTINATION dans SOURCE : code 3, rien de créé.
- [ ] Le script est sur `main` et passe ShellCheck.

**Vérification** : `lab/bin/check 02 12` (le contrôle fabrique son propre jeu de données dans un dossier temporaire et y lance ton script)

<details><summary>Indice 1</summary>

`mapfile -d '' -t tableau < <(find … -print0)` puis `for f in "${tableau[@]}"`. En Bash 5.1 et plus, `$!` désigne le processus de la dernière substitution `<(…)`, et `wait "$!"` rend son code.
</details>

<details><summary>Indice 2</summary>

`date -r FICHIER +%Y-%m` donne le mois de modification. Pour le chemin relatif : `${f#"$source"/}` (les guillemets internes empêchent `$source` d'être lu comme un motif). Canonicalise SOURCE et DESTINATION avec `realpath` avant de comparer.
</details>

<details><summary>Indice 3</summary>

Calcule l'empreinte depuis l'entrée standard (`sha256sum < fichier`) : tu obtiens une empreinte sans nom, et tu écris toi-même la ligne du manifeste. Pour un nom avec `\` ou un retour à la ligne, `sha256sum` préfixe la ligne par `\` et échappe ces caractères : fais pareil. `printf '%q'` rend un nom affichable.
</details>

**Pour aller plus loin** (facultatif) : compare avec `find … -exec … {} +` et `xargs -0 -P` ; lis « Filenames and Pathnames in Shell: How to do it Correctly » (David A. Wheeler) ; ajoute une option `--supprimer-dossiers-vides`.

---

### M02-E13 — Verrous, fichiers temporaires et exécutions concurrentes  `LAB` `★★`

> **Ticket PLAT-323** — *De : Karim Benali* — *Copie : Julien Petit*
> Deux demandes qui se rejoignent. Un : je veux chaque nuit une « photo » de la configuration Proxmox de toutes les VMs du lab, pour répondre à « qu'est-ce qui a changé depuis hier ? » avec un simple `diff`. Julien veut brancher un script de comparaison dessus, qui ne doit **jamais** lire un export à moitié écrit. Deux : hier, `ms-snapshot` a tourné deux fois en même temps sur `git01` (cron + Nadia), et les deux purges se sont chevauchées. Plus jamais deux exécutions simultanées d'un même outil.

**Objectifs pédagogiques**
- Garantir l'exclusion mutuelle avec `flock(1)` : verrou bloquant ou non, délai, libération automatique, héritage des descripteurs.
- Publier un résultat de façon atomique : construire à côté, puis `rename(2)` ; remplacer un lien symbolique atomiquement.
- Nettoyer à coup sûr (piège `EXIT`, conversion des signaux) et choisir où créer les fichiers temporaires.
- Choisir un emplacement de verrou commun aux exécutions interactives et planifiées.

**Prérequis** : M02-E03 (`trap`, `mktemp`), M02-E10, M02-E11.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Ajout à l'API de la bibliothèque : `lock_or_die NOM [ATTENTE_S]` prend un verrou exclusif sur `$MS_LOCK_DIR/NOM.lock` pour **toute la durée du script** ; `ATTENTE_S` vaut 0 par défaut (échec immédiat) ; verrou non obtenu : message qui dit qui le tient, puis code **3**. `MS_LOCK_DIR` a une valeur par défaut que tu choisis (et justifies) ; les vérifications la remplacent par un dossier temporaire. Chaque outil utilise son propre nom comme NOM (`ms-snapshot`, `ms-export-config`).
- Contrat de `bin/ms-export-config [-g|--garder N]` :
  - pour chaque VM QEMU du pool `lab`, `GET /nodes/{node}/qemu/{vmid}/config`, écrit en JSON aux clés triées dans `$MS_EXPORT_DIR/AAAAMMJJ-HHMMSS/<VMID>-<nom>.json` (défaut `~/exports/config-vms`), plus un `index.json` ;
  - un export n'apparaît sous son nom définitif que **complet** ; le lien `$MS_EXPORT_DIR/dernier` pointe vers le dernier export complet et n'est jamais absent ni cassé pendant la mise à jour ;
  - aucune trace (dossier ou fichier temporaire) après succès, échec ou interruption ;
  - rotation : les N exports les plus récents sont gardés (défaut 14), rien d'autre n'est jamais supprimé ;
  - codes : 0, 1 (au moins une configuration illisible : rien n'est publié), 2, 3 (autre exécution en cours).

**Travail demandé**
1. Reproduis le problème avant de le corriger : dans deux terminaux, lance `ms-snapshot 2020` en même temps (ou en arrière-plan deux fois). Que montrent le journal des tâches de `pve01` et la liste des instantanés ? Note la course exacte.
2. Lis `man flock`. Réponds : que se passe-t-il pour le verrou si le script est tué par `kill -9` ? Si le script lance un processus en arrière-plan qui lui survit ? Pourquoi un fichier `.pid` « fait main » est-il fragile ?
3. Ajoute `lock_or_die` à la bibliothèque et appelle-la dans `ms-snapshot`, après la validation des arguments (une erreur d'usage ne doit pas attendre un verrou). Choisis `MS_LOCK_DIR` : `/tmp` ? `/run/lock` ? `$XDG_RUNTIME_DIR` ? `~/.local/state/…` ? Pense au cas où l'outil tourne sous cron ou sous systemd (E26) et en interactif.
4. Écris `bin/ms-export-config` selon le contrat. Où créer le dossier de travail pour que la publication soit un simple renommage ? Comment remplacer le lien `dernier` sans instant où il n'existe pas (`ln -sfn` suffit-il ? vérifie avec `strace -e trace=symlink,unlink,rename`) ?
5. Teste les interruptions : Ctrl-C pendant l'export (ajoute un `sleep` temporaire dans la boucle si c'est trop rapide), `kill -TERM`, une configuration illisible (VMID invisible ajouté à la main dans la boucle, temporairement). Dans chaque cas : `dernier` est-il intact ? Reste-t-il quelque chose ?
6. Teste l'exclusion : tiens le verrou toi-même (`flock <fichier> sleep 60 &`) et lance l'outil.
7. Lance un vrai export, puis un second une minute plus tard, et compare-les avec `diff -r`. Fais une modification anodine sur 2020 (description) entre deux exports et retrouve-la.
8. ShellCheck muet, MR, fusion.

**Critères de réussite**
- [ ] Verrou tenu : `ms-export-config` et `ms-snapshot` sortent en 3 sans rien écrire.
- [ ] Un export produit un dossier horodaté complet, `dernier` pointe dessus ; aucun fichier temporaire ne reste, ni dans `MS_EXPORT_DIR` ni dans `/tmp`.
- [ ] Après une interruption ou une erreur, `dernier` désigne toujours l'export précédent et rien ne traîne.
- [ ] Un export réel existe dans `~/exports/config-vms/` ; l'outil et la bibliothèque sont sur `main`.

**Vérification** : `lab/bin/check 02 13`

<details><summary>Indice 1</summary>

`exec {fd}>>"$fichier"` ouvre un descripteur dont Bash choisit le numéro ; `flock -n "$fd"` (ou `-w N`) le verrouille. Le verrou vit tant que le descripteur est ouvert, donc jusqu'à la fin du processus… et de tous ceux qui en ont hérité.
</details>

<details><summary>Indice 2</summary>

`rename(2)` remplace atomiquement sa cible, à condition de rester sur le même système de fichiers. `mv -T` évite que `mv` ne déplace « dans » le dossier ou le lien existant. Pour le lien : créer un lien temporaire à côté, puis le renommer par-dessus `dernier`.
</details>

<details><summary>Indice 3</summary>

Un seul piège `EXIT` qui nettoie, et des pièges `INT`/`TERM` qui se contentent de `exit 130` / `exit 143` : la sortie déclenche `EXIT`. `$XDG_RUNTIME_DIR` n'existe pas dans une session cron ni dans un service système.
</details>

**Pour aller plus loin** (facultatif) : remplace `flock` par un verrou `mkdir` et liste ce que tu perds ; lis la section « Concurrency » de systemd.service (que fait systemd si un timer redéclenche un service `oneshot` encore actif ?) ; écris le script de comparaison de Julien (`ms-diff-config HIER AUJOURDHUI`).

---

### M02-E14 — Tester ses scripts Bash avec bats  `LAB` `★★`

> **Ticket PLAT-324** — *De : Karim Benali*
> On a maintenant trois outils et une bibliothèque, et chaque MR se valide « à la main sur ma VM ». La CI de E24 doit pouvoir dire si un script fait ce qu'il promet, **sans** Proxmox (elle tourne sur `runner01`, qui n'a aucun accès à `pve01` et aucun jeton). Écris les tests bats de la bibliothèque et de `ms-snapshot`, avec une API simulée.

**Objectifs pédagogiques**
- Écrire des tests bats lisibles : `setup`, `run`, codes attendus (`run -N`), sorties séparées (`--separate-stderr`), dossiers jetables.
- Remplacer une dépendance externe par un double : faux `curl` dans le `PATH`, ou redéfinition de fonction après `source`.
- Tester les cas d'erreur et les garde-fous, pas seulement le chemin heureux.
- Vérifier une propriété de sécurité par un test (le secret n'est jamais passé en argument).

**Prérequis** : M02-E10, M02-E11, M02-E13 ; bats-core 1.13 installé sur `adm01` (voir l'introduction).
**Durée indicative** : 3 h.

**Contexte technique**
- Arborescence : `tests/bats/*.bats`, aides dans `tests/bats/helpers/`, données dans `tests/bats/fixtures/`. Lancement : `bats tests/bats` depuis la racine du projet.
- Documentation : https://bats-core.readthedocs.io (pages « Writing tests » et « Gotchas »). bats-core 1.13 : `bats_require_minimum_version 1.5.0` en tête de fichier pour `run -N` et `--separate-stderr`. Les bibliothèques `bats-support`/`bats-assert` ne sont **pas** installées sur `runner01` : écris tes assertions avec `[[ … ]]`.
- Les tests ne doivent dépendre ni du réseau, ni de `~/.config/workbook/`, ni de `~/.ssh` : les vérifications les lancent avec un `HOME` vide et un mandataire HTTPS inexistant.

**Travail demandé**
1. Choisis ta stratégie de double et justifie-la dans le fichier d'aide : faux exécutable `curl` en tête du `PATH` (il teste aussi `pve_api`), ou redéfinition de `pve_api` après `source` (plus simple, mais ne teste pas la plomberie HTTP). Tu peux combiner les deux.
2. Prépare un environnement par test : fichier d'accès factice (mode 600, faux secret), `MS_PVE_ENV`, `MS_LOCK_DIR` et dossiers de travail dans `$BATS_TEST_TMPDIR`, variables `PVE_*` de l'appelant neutralisées.
3. Tests de la bibliothèque (au moins 12) : format et destination des journaux, codes de `die`, `require_cmd`, `confirm` sans terminal et avec `MS_YES=1`, `retry` (nombre d'essais, délais croissants sans attendre vraiment, variable `n` de l'appelant), `pve_api` (données, erreur 403 avec motif, erreur 400 avec détail, erreur réseau, fichier 644 refusé, priorité de l'environnement, **secret absent des arguments**), `pve_wait_task` (OK, échec), `lock_or_die` (second détenteur refusé en 3, verrou libéré à la sortie).
4. Tests de `ms-snapshot` (au moins 10) : codes d'usage et de refus, aucune écriture envoyée en cas de refus, fonction de sélection (préfixe qui en prolonge un autre, moins de N instantanés), exécution complète (une création, deux suppressions des plus anciens), `--dry-run`, échec de création sans purge, tâche en échec, API injoignable, exécution concurrente refusée.
5. Ajoute au moins un test pour `ms-ranger` ou `ms-export-config`.
6. Casse volontairement ta bibliothèque (inverse un test dans `retry`, supprime le `-n` de `flock`) et vérifie qu'au moins un test passe au rouge. Note dans le corps de ta MR ce qu'a détecté chaque « mutation ».
7. Piège classique à vérifier : un processus lancé en arrière-plan dans un test qui garde le descripteur 3 de bats ouvert bloque la fin de la suite. Comment l'éviter ?
8. MR `test: tests bats de la bibliothèque et de ms-snapshot`, fusion.

**Critères de réussite**
- [ ] `bats tests/bats` passe sur `adm01` avec un `HOME` vide et sans accès réseau.
- [ ] Au moins 20 tests, dont des tests de `lib/ms-commun.sh` et de `ms-snapshot`.
- [ ] Une mutation volontaire de la bibliothèque fait échouer au moins un test (décrit dans la MR).
- [ ] Les tests sont sur `main`.

**Vérification** : `lab/bin/check 02 14`

<details><summary>Indice 1</summary>

`run -3 commande` vérifie le code ; `run --separate-stderr` remplit `$output` et `$stderr` séparément. `$BATS_TEST_DIRNAME` donne le dossier du fichier de test, `$BATS_TEST_TMPDIR` un dossier vidé à chaque test. `load helpers/commun` charge `helpers/commun.bash`.
</details>

<details><summary>Indice 2</summary>

Un faux `curl` n'a qu'à comprendre les options qu'utilise ta bibliothèque : `-X`, `--data-urlencode`, `-H @fichier`, l'URL. Il écrit chaque appel dans un journal (le test le relit), puis renvoie une ligne de statut, des en-têtes et un corps, séparés en CRLF comme pveproxy. Un petit état (fichier) lui permet de « se souvenir » d'un instantané créé.
</details>

<details><summary>Indice 3</summary>

Pour un processus en arrière-plan : `commande 3>&- &`. Pour tester une fonction de `ms-snapshot` sans lancer `main` : `source bin/ms-snapshot` (grâce à la garde de E11), puis `run a_purger avant 2 < fixtures/…`.
</details>

**Pour aller plus loin** (facultatif) : installe `bats-assert` dans le dépôt (sous-module ou copie figée) et compare la lisibilité ; produis le rapport JUnit (`bats --report-formatter junit -o rapports/`) qu'utilisera la CI en E24 ; mesure la durée de la suite (`bats -T`).

---

### M02-E15 — CLI `medictl` avec Typer : lister et décrire les VMs  `LAB` `★★`

> **Ticket PLAT-325** — *De : Karim Benali* — *Copie : Nadia Roussel*
> Le client Python de E08 marche, mais ce n'est pas un outil : pas de commande, pas de format de sortie, des traces Python à l'écran au moindre souci. Première version de `medictl` : `vm list` et `vm show`, lisibles par un humain **et** par un script (JSON). Nadia veut pouvoir faire `medictl vm list -f json | jq` à 3 h du matin sans surprise.

**Objectifs pédagogiques**
- Structurer une CLI Typer : application, sous-application `vm`, options typées, énumération de formats, option `--version` prioritaire.
- Séparer les responsabilités : accès à l'API (`pve.py`), mise en forme (`sortie.py`), interface (`cli.py`).
- Définir un contrat de sortie JSON stable et le distinguer de l'affichage pour humains.
- Transformer une exception technique en message d'une ligne et code de sortie.

**Prérequis** : M02-E07, M02-E08.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Typer 0.27 (Click est intégré à Typer depuis la 0.26, Rich est obligatoire). Documentation : https://typer.tiangolo.com (pages « Commands », « CLI Options », « Enum - Choices », « Version CLI Option, is_eager »). Le point d'entrée `medictl = "medictl.cli:app"` est déjà déclaré dans `pyproject.toml` (E07).
- Commandes de cet exercice : `medictl vm list [--pool POOL] [--format table|json]` et `medictl vm show VMID [--format table|json]` (`-f` en raccourci de `--format`).
- **Contrat JSON** de `vm list` (relu par d'autres outils, à ne pas casser sans version majeure) : une liste d'objets `{vmid, name, status, node, pool, template, cpus, memory_mib, disk_gib, tags}` — `template` booléen, `tags` liste de chaînes (Proxmox renvoie une chaîne séparée par `;`), `memory_mib` entier, `disk_gib` à une décimale.
- `vm show` en JSON : les mêmes clés, plus `config` (la configuration renvoyée par l'API).
- Codes : 0 ; 1 (VM introuvable, configuration absente, API en erreur : une ligne sur stderr, **rien** sur stdout) ; 2 (usage, géré par Typer).

**Travail demandé**
1. Réutilise `medictl/pve.py` de E08 (configuration et connexion). Crée `medictl/sortie.py` : conversion d'une ressource de `/cluster/resources` vers le contrat, rendu en tableau aligné, rendu JSON.
2. Crée `cli.py` : l'application, la sous-application `vm`, les deux commandes. Un seul appel d'API suffit pour `vm list` ; lequel ?
3. Formats : utilise une énumération pour `--format`. Que répond Typer à `--format yaml` ? Quel code ?
4. Erreurs : sans fichier d'accès, avec un VMID inexistant, avec `pve01` injoignable (adresse modifiée dans une **copie** du fichier passée par `MEDICTL_ENV_FILE`). Aucune trace Python ne doit s'afficher, et stdout doit rester vide.
5. Question pour le journal : pourquoi les nombres du JSON sont-ils des entiers en Mio et des Gio à une décimale, plutôt que des chaînes déjà formatées (« 4 Go ») ?
6. Essaie : `medictl vm list -f json | jq '[.[] | select(.status == "running")] | length'`, `medictl vm list | sort -k3`.
7. `ruff check` et `ruff format --check` muets ; MR `feat(medictl): vm list et vm show`, fusion.

**Critères de réussite**
- [ ] `medictl --version` affiche la version ; `medictl vm list -f json` produit un tableau JSON conforme au contrat, qui contient exactement les VMs QEMU du pool `lab`.
- [ ] Le template 9000 apparaît avec `template: true` ; `vm list` en table montre une ligne par VM.
- [ ] `medictl vm show 1002 -f json` contient la configuration de `dns01` (dont `net0`).
- [ ] `medictl vm show 999999` sort en 1 avec un message sur stderr et rien sur stdout.
- [ ] Le code ne désactive jamais la vérification TLS ; il est sur `main`.

**Vérification** : `lab/bin/check 02 15` (utilise `~/src/outils/.venv/bin/medictl`, ou celui du `PATH`)

<details><summary>Indice 1</summary>

`app.add_typer(vm_app, name="vm")` crée la sous-commande. `typer.Option("--format", "-f")` déclare les noms ; avec un paramètre Python nommé `format`, tu masques une fonction native : préfère `fmt`.
</details>

<details><summary>Indice 2</summary>

`typer.echo(…, err=True)` écrit sur stderr ; `raise typer.Exit(1)` termine avec un code. proxmoxer lève `ResourceException` pour les réponses HTTP ≥ 400, requests lève des `RequestException` pour le réseau et TLS.
</details>

<details><summary>Indice 3</summary>

Dans `/cluster/resources`, la mémoire (`maxmem`) et le disque (`maxdisk`) sont en octets, `template` vaut 0 ou 1, `tags` est une chaîne `a;b`. Écris la conversion une fois, dans `sortie.py`.
</details>

**Pour aller plus loin** (facultatif) : ajoute `--format csv` ; essaie l'autocomplétion de Typer (`--install-completion`) et explique pourquoi le projet la désactive (`add_completion=False`).

---

### M02-E16 — `medictl vm create/destroy` avec garde-fous  `LAB` `★★★`

> **Ticket PLAT-326** — *De : Nadia Roussel* — *Copie : Sophie Laurent*
> Pour les exercices de panne et les essais, on crée et on détruit des VMs jetables toute la journée. Je veux `medictl vm create` et `medictl vm destroy`. Mais je connais l'histoire : un jour, quelqu'un tapera `destroy 1004` au lieu de `destroy 2004`. L'outil doit rendre cette erreur **impossible**, pas seulement improbable. Sophie veut voir les garde-fous écrits noir sur blanc dans le code et testés.

**Objectifs pédagogiques**
- Enchaîner des opérations asynchrones de l'API (clonage, configuration, démarrage, arrêt, destruction) en attendant chaque tâche.
- Concevoir des garde-fous en défense en profondeur : plages de VMID, appartenance au pool, nature de la VM, confirmation, et les vérifier **avant** toute écriture.
- Décider quoi faire d'un échec à mi-parcours (VM créée mais pas prête).
- Écrire les garde-fous comme des fonctions pures, testables sans Proxmox.

**Prérequis** : M02-E15 ; M00-E18 (cycle de vie par l'API).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Commandes : `medictl vm create NOM --vmid N [--template 9000] [--vnet vsandbox] [--cores 1] [--memory 1024] [--tags T] [--wait/--no-wait]` et `medictl vm destroy VMID [--yes]`.
- Règles (PLAN.md §4.6) : création et destruction **uniquement** pour les VMID 2000-2999 et 5000-5999, VMs membres du pool `lab` ; jamais le socle (1000-1099), jamais un template (9000-9099) ; la source d'un clonage est un template (9000-9099) du pool `lab` ; le nom est un nom DNS court. Tout refus : **code 3**, rien de modifié.
- `create` : clone lié dans le pool `lab`, puis `net0` sur le VNet demandé, `ipconfig0=ip=dhcp`, cœurs, mémoire, étiquettes, démarrage ; avec `--wait` (défaut), attend que l'agent QEMU réponde. Un VMID déjà pris est un refus (3).
- `destroy` : arrêt si la VM tourne, destruction avec purge des références et des disques orphelins. Sans `--yes` : confirmation interactive ; sans terminal et sans `--yes` : refus (3).
- VM de l'exercice : **2021** `m02-test`, étiquette `env-m02`. En fin d'exercice, `medictl` détruit 2021 **et** 2020 (`m02-cobaye`, créée en E11).

**Travail demandé**
1. Liste dans ton journal, pour chaque garde-fou, l'erreur humaine qu'il empêche et **où** il est vérifié (avant tout appel réseau, après lecture de l'inventaire, côté Proxmox). Quels contrôles Proxmox fait-il déjà de lui-même grâce au jeton limité au pool ? Pourquoi les doubler dans l'outil ?
2. Écris `medictl/garde_fous.py` : fonctions pures, une exception dédiée qui porte le code 3. Elles ne connaissent ni Typer ni proxmoxer.
3. Étends le client : clonage, configuration (`POST …/config` renvoie un UPID ou rien), démarrage, arrêt, destruction, attente d'une tâche (statut, `exitstatus`, délai maximal), attente de l'agent. Comment savoir qu'un VMID est libre avec un jeton qui ne voit pas les VMs hors pool (M00-E18) ?
4. Écris les deux commandes. Ordre : garde-fous sans réseau, puis lecture, puis garde-fous avec données, puis écritures. Si une étape échoue **après** le clonage, le message doit dire que la VM existe et comment la supprimer.
5. Essaie les refus : `destroy 1004 --yes`, `destroy 9000 --yes`, `create m02-test --vmid 1050`, `create M02_TEST --vmid 2022`, `create m02-test --vmid 2021` deux fois, `destroy 2021` dans un tube (`echo o | medictl vm destroy 2021`). Note les codes.
   > ⚠️ **Attention** : n'essaie un refus de destruction que sur une VM qui existe **et** dont la perte serait acceptable, ou sur un VMID **libre**. Tant que tes garde-fous ne sont pas écrits et testés, `destroy 1004 --yes` détruirait `git01` ; commence donc par écrire `garde_fous.py`, puis teste les refus avec des VMID libres (1099, 4242).
6. Cycle complet : `medictl vm create m02-test --vmid 2021 --tags env-m02`, vérifie dans l'interface (pool, VNet, étiquette, IP DHCP via `vm show`), puis `medictl vm destroy 2021` (confirmation interactive), puis `medictl vm destroy 2020 --yes`.
7. MR `feat(medictl): vm create et vm destroy avec garde-fous`, fusion.

**Critères de réussite**
- [ ] Les destructions de 1099, 4242 et 9099 (VMID libres) sont refusées en 3 ; un nom invalide est refusé en 3 ; `create` sans `--vmid` sort en 2 ; aucun de ces essais ne crée de VM.
- [ ] Le journal des tâches de `pve01` montre, par le jeton, le démarrage et la destruction d'une VM 2021-2029, et la destruction de 2020.
- [ ] Plus aucune VM 2020-2029 n'existe à la fin de l'exercice.
- [ ] Les garde-fous sont dans un module dédié, sur `main`.

**Vérification** : `lab/bin/check 02 16` (les refus ne sont testés que sur des VMID libres)

<details><summary>Indice 1</summary>

`range(2000, 3000)` contient 2000 à 2999 : `vmid in range(…)` se lit bien et ne se trompe pas de borne. Une exception avec un attribut de classe `code = 3`, attrapée à un seul endroit de la CLI, évite de disperser les `typer.Exit(3)`.
</details>

<details><summary>Indice 2</summary>

`GET /cluster/nextid?vmid=N` répond 400 si N est pris, même par une VM invisible. proxmoxer : `api.nodes(n).qemu(9000).clone.post(newid=…, name=…, pool="lab")`, `api.nodes(n).qemu(v).delete(purge=1, **{"destroy-unreferenced-disks": 1})`, `api.nodes(n).tasks(upid).status.get()`.
</details>

<details><summary>Indice 3</summary>

`sys.stdin.isatty()` dit si une confirmation est possible. `typer.confirm(…, default=False)` pose la question. Dans les tests (E18), l'entrée de `CliRunner` n'est pas un terminal : c'est voulu.
</details>

**Pour aller plus loin** (facultatif) : ajoute `--dry-run` aux deux commandes ; une option `--ttl 2h` qui écrit une date d'expiration dans la description, et une commande `medictl vm expirees`. Le module 05 confiera la création à OpenTofu : quels garde-fous faudra-t-il y reproduire ?

---

### M02-E17 — Erreurs, journalisation et reprises en Python  `LAB` `★★`

> **Ticket PLAT-327** — *De : Nadia Roussel*
> Cette nuit, `medictl vm list` a affiché quarante lignes de trace Python parce que `pve01` redémarrait. Le collègue d'astreinte a cru à un bogue de l'outil. Ce que je veux : une ligne qui dit ce qui se passe, des détails seulement si je les demande (`-v`), et que l'outil réessaie tout seul quand ça vaut la peine — mais pas quand c'est inutile ou dangereux.

**Objectifs pédagogiques**
- Configurer le module `logging` pour une CLI : niveaux, format, sortie d'erreur, bibliothèques tierces.
- Classer les erreurs : transitoires (réseau, 5xx) ou permanentes (TLS, 4xx) ; idempotentes ou non.
- Écrire une reprise avec délai exponentiel bornée et testable (pas de `sleep` réel en test).
- Traduire les exceptions techniques en messages d'astreinte actionnables.

**Prérequis** : M02-E16.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Verbosité : option globale `-v` (`-v` INFO, `-vv` DEBUG ; `-vvv` peut ouvrir les journaux de proxmoxer et urllib3). Sans option : seuls avertissements et erreurs. Journal sur stderr, données sur stdout.
- Reprises : 4 tentatives au plus, délais 1 s, 2 s, 4 s, sur erreurs réseau et réponses 5xx **seulement**.
- proxmoxer 2.3 : `ResourceException` (attributs `status_code`, `content`, `errors`) pour HTTP ≥ 400 ; il **désactive les avertissements TLS d'urllib3 à l'import** (à garder en tête : un `verify=False` ne préviendrait plus) et fixe ses propres journaux au niveau WARNING.
- requests : `SSLError` est une sous-classe de `ConnectionError`.

**Travail demandé**
1. Inventaire dans ton journal : pour `vm list`, `vm show`, `vm create` et `vm destroy`, chaque appel d'API, idempotent ou non. Que risque-t-on à reprendre automatiquement un `POST …/clone` après une coupure réseau ? Un `GET …/tasks/{upid}/status` ?
2. Écris la configuration du journal (module dédié) et l'option `-v` (compteur). Vérifie que `medictl -vv vm list -f json | jq .` fonctionne.
3. Écris la reprise : une fonction qui prend l'appel à faire, décide si l'erreur est transitoire, attend de façon exponentielle et journalise chaque nouvel essai. La fonction d'attente doit être **injectable** pour les tests. Qui décide de ce qu'on reprend : la fonction de reprise, ou le client ?
4. Traduis les erreurs en messages : certificat refusé (que vérifier ?), Proxmox injoignable, 401 (jeton supprimé, expiré ou secret faux), 403 (avec le motif renvoyé), autres. Une seule ligne sur stderr, code 1 ; la pile d'appels seulement en `-vv`.
5. Provoque chaque cas avec une **copie** du fichier d'accès (`MEDICTL_ENV_FILE`) : secret faux, adresse `https://127.0.0.1:9/api2/json`, `PVE_CACERT` pointant sur `/etc/ssl/certs/ca-certificates.crt`. Observe avec `-v` : qui est repris, combien de fois, en combien de temps ?
6. Question : Proxmox renvoie souvent un **500** pour une erreur métier (« VM is locked », « unable to find configuration file »). Est-ce gênant pour ta politique de reprise ? Pourquoi le choix « lectures seulement » limite-t-il les dégâts ?
7. `ruff` muet, MR `feat(medictl): journal, erreurs et reprises`, fusion.

**Critères de réussite**
- [ ] Avec `-vv`, stdout reste un JSON valide et stderr contient des messages DEBUG ; sans `-v` et sans incident, stderr est vide.
- [ ] Secret faux : code 1, message qui cite le 401, aucune trace Python.
- [ ] API injoignable : au moins deux nouveaux essais journalisés avec leur délai, puis code 1 et une ligne claire.
- [ ] Certificat refusé : code 1, message qui parle du certificat, **aucune** reprise.

**Vérification** : `lab/bin/check 02 17`

<details><summary>Indice 1</summary>

`logging.getLogger("medictl")` et des sous-journaux par module (`__name__`) ; un seul `StreamHandler(sys.stderr)` configuré au lancement (callback de l'application Typer). `typer.Option("--verbose", "-v", count=True)` compte les `-v`.
</details>

<details><summary>Indice 2</summary>

Teste `SSLError` **avant** `ConnectionError` dans ta fonction de classement. Pour proxmoxer : `exc.status_code >= 500` ; 501 (« not implemented ») est permanent.
</details>

<details><summary>Indice 3</summary>

Passe `dormir=time.sleep` en paramètre par défaut ; un test passe `dormir=pauses.append` et vérifie la liste des délais sans attendre.
</details>

**Pour aller plus loin** (facultatif) : ajoute une part d'aléa aux délais (*jitter*) et explique quel problème cela évite quand vingt clients réessaient en même temps ; compare avec `urllib3.util.Retry` monté sur la session de requests (`allowed_methods`, `status_forcelist`, `backoff_factor`).

---

### M02-E18 — Tester `medictl` avec pytest sans toucher à Proxmox  `LAB` `★★`

> **Ticket PLAT-328** — *De : Karim Benali*
> Même exigence que pour les scripts Bash : la CI doit prouver que `medictl` fait ce qu'il promet, garde-fous en tête, sans Proxmox. Je veux des tests qui lisent comme une spécification, et un chiffre de couverture, pas pour l'afficher, pour voir ce qu'on n'a **pas** testé.

**Objectifs pédagogiques**
- Organiser une suite pytest : `conftest.py`, fixtures, paramétrage, `tmp_path`, `monkeypatch`.
- Tester une CLI Typer par son comportement observable (`CliRunner` : code, stdout, stderr).
- Choisir le bon niveau de double : faux client injecté (logique) ou HTTP simulé avec `responses` (plomberie proxmoxer).
- Mesurer la couverture et lire ce qu'elle dit vraiment.

**Prérequis** : M02-E15, M02-E16, M02-E17.
**Durée indicative** : 3 h.

**Contexte technique**
- pytest 9 (configuration dans `[tool.pytest.ini_options]` de `pyproject.toml`, lue aussi par pytest 8), `responses` 0.26, `pytest-cov` à ajouter au groupe `dev` (`uv add --dev pytest-cov`). Tests dans `tests/python/`.
- `typer.testing.CliRunner` : `result.exit_code`, `result.stdout`, `result.stderr` (séparés, comme depuis Click 8.2) ; son entrée standard n'est jamais un terminal.
- Les vérifications lancent la suite avec un `HOME` vide, sans variable `PVE_*` et avec un mandataire HTTPS inexistant : un test qui parle au vrai Proxmox échouera.
- Documentation : https://docs.pytest.org (« How to use fixtures », « How to parametrize », « monkeypatch »), https://github.com/getsentry/responses.

**Travail demandé**
1. Point d'injection : la CLI doit obtenir son client par une fonction que les tests peuvent remplacer (`monkeypatch.setattr`). Écris un `FauxClient` qui a la même interface que ton client, lit un jeu de ressources enregistré (`tests/python/donnees/`) et **journalise les écritures** demandées.
2. Garde-fous : tests paramétrés sur toutes les frontières (999, 1000, 1099, 1999, 2000, 2999, 3000, 4999, 5000, 5999, 6000, 9000, 9099) et sur les noms.
3. CLI : `vm list` (JSON conforme au contrat, table), `vm show` (dont VM introuvable : code 1, stdout vide), `create` nominal (ordre des écritures, paramètres envoyés), `create`/`destroy` refusés (code 3 **et aucune écriture**), `destroy` sans `--yes` hors terminal, échec après clonage (message de nettoyage).
4. Client HTTP avec `responses` : URL et paramètres réellement envoyés, en-tête d'authentification, reprises sur 503 avec la liste des délais, abandon après coupures répétées, **pas** de reprise sur 401/403/400 ni sur `SSLError` ni sur un `POST`, attente de tâche (running puis stopped), destruction avec purge.
5. Lance `uv run pytest --cov=medictl --cov-report=term-missing`. Lis les lignes non couvertes : lesquelles comptent vraiment ? Ajoute les tests utiles, pas ceux qui ne servent qu'au chiffre.
6. Mutation volontaire : élargis une plage dans `garde_fous.py` (`range(1000, 3000)`) ; combien de tests échouent ? Remets en ordre.
7. MR `test(medictl): suite pytest sans Proxmox`, fusion.

**Critères de réussite**
- [ ] Au moins 30 tests, tous verts sans accès au lab.
- [ ] Des tests vérifient les refus des garde-fous (code 3, aucune écriture).
- [ ] Le client HTTP est testé avec `responses` (ou un faux client injecté pour la logique de la CLI).
- [ ] Couverture de `medictl` mesurée, au moins 70 %.
- [ ] Les tests sont sur `main`.

**Vérification** : `lab/bin/check 02 18`

<details><summary>Indice 1</summary>

Une fixture `faux_client(monkeypatch)` qui fait `monkeypatch.setattr(cli, "fabriquer_client", lambda: client)` et rend le client : chaque test lit ensuite `client.appels`.
</details>

<details><summary>Indice 2</summary>

Avec `responses.RequestsMock()` comme gestionnaire de contexte, enregistre plusieurs réponses pour la même URL : elles sont servies dans l'ordre (503, 503, 200). `api.calls[i].request` donne l'URL, les en-têtes et le corps envoyés. Un UPID dans une URL : utilise un motif `re.compile(…)`.
</details>

<details><summary>Indice 3</summary>

`responses` ne sait pas fabriquer la phrase de motif personnalisée que Proxmox met dans la ligne de statut : teste le code HTTP et le message que **ton** code en tire, pas le texte exact de Proxmox.
</details>

**Pour aller plus loin** (facultatif) : essaie `hypothesis` sur `verifier_vmid_modifiable` ; lis la documentation de `pytest --strict-markers` et `-ra` ; compare la couverture des lignes et celle des branches (`--cov-branch`).

---

### M02-E19 — Configuration et secrets des outils  `LAB` `★★`

> **Ticket SEC-329** — *De : Sophie Laurent*
> Audit rapide de `plateforme/outils` avant qu'il serve à l'astreinte. Je veux être sûre de quatre choses : la configuration est lue, jamais exécutée ; un fichier de secrets mal protégé est refusé ; le secret n'apparaît nulle part (écran, journaux, dépôt, liste des processus), même en mode bavard ; et on sait à tout moment **d'où** vient chaque valeur. Prouve-le-moi, tests à l'appui.

**Objectifs pédagogiques**
- Définir un ordre de priorité de configuration (fichier, environnement) et le rendre visible.
- Lire un fichier de type shell sans l'exécuter, en gérant guillemets, commentaires et `$HOME`.
- Protéger un secret dans un programme Python : `repr`, journaux, messages d'erreur, filtre de journalisation.
- Vérifier l'absence de secret dans un dépôt et son historique.

**Prérequis** : M02-E15 à M02-E18.
**Durée indicative** : 2 h.

**Contexte technique**
- Priorité, du plus faible au plus fort : fichier `MEDICTL_ENV_FILE` (défaut `~/.config/workbook/pve-api.env`), puis variables d'environnement `PVE_*` (la CI de E24 et E25 n'aura que des variables).
- Nouvelle commande : `medictl config` affiche la configuration **effective** (une ligne par variable), le secret masqué (`****`) et l'origine de chaque valeur (fichier ou environnement).
- Un fichier accessible au groupe ou aux autres est refusé (code 1, message qui dit quoi corriger). `PVE_CACERT` absent : magasin de certificats du système ; jamais de vérification désactivée.
- La configuration quitte `pve.py` (E08) pour un module `medictl/config.py` ; garde les noms de E08 (`PveConfig`, `ConfigError`) pour ne pas casser les imports.
- Le `.gitignore` du projet (E02) ignore déjà `*.env`.

**Travail demandé**
1. Relis la lecture du fichier de E08 avec un œil d'attaquant : que se passerait-il si on remplaçait la lecture par un `source` ou un `eval` dans un script Bash, avec la valeur `PVE_NODE="$(touch /tmp/pirate)"` ? Et dans ta version Python ? Écris le test qui le prouve.
2. Déplace et complète la configuration : priorité fichier puis environnement, droits du fichier, validation (`https://`, chemin `/api2/json`, forme `utilisateur@domaine!jeton`, CA lisible), origine de chaque valeur.
3. Ajoute `medictl config`.
4. Défense en profondeur dans les journaux : un filtre de `logging` qui remplace le secret par `****` dans **tous** les messages, y compris ceux des bibliothèques. Pourquoi est-ce utile alors que tu ne journalises jamais le secret ?
5. Tests : priorité, fichier 644 refusé, fichier absent mais variables présentes, valeurs invalides, `repr()` sans secret, `medictl config` masqué, `medictl -vvv vm list` sans secret à l'écran (avec `responses`).
6. Vérifie le dépôt : `git log --all -p | grep -F -f <(…)` avec ton vrai secret, sans le taper en argument. Que ferais-tu s'il y apparaissait ?
7. Côté Bash : `lib/ms-commun.sh` applique-t-il les mêmes règles (priorité, droits) ? Note les écarts dans la MR.
8. MR `refactor(medictl): configuration et secrets`, fusion.

**Critères de réussite**
- [ ] `~/.config/workbook` est en 700, `pve-api.env` en 600, hors de tout dépôt.
- [ ] `medictl config` montre le jeton utilisé, jamais le secret ; `PVE_NODE=x medictl config` montre `x` comme venant de l'environnement.
- [ ] Une copie du fichier en mode 644 est refusée (code 1, message sur stderr).
- [ ] `medictl -vvv vm list -f json` n'affiche jamais le secret ; il n'apparaît pas dans l'historique Git du projet.

**Vérification** : `lab/bin/check 02 19`

<details><summary>Indice 1</summary>

`shlex.split(ligne, comments=True)` découpe une affectation shell simple comme le ferait le shell, sans rien exécuter ; `os.path.expandvars` développe `$HOME` (pas entre apostrophes, comme en shell).
</details>

<details><summary>Indice 2</summary>

`stat.S_IMODE(chemin.stat().st_mode) & 0o077` : différent de 0, d'autres que le propriétaire ont des droits. `dataclasses.field(repr=False)` exclut un champ de `repr()`.
</details>

<details><summary>Indice 3</summary>

Un `logging.Filter` posé sur le gestionnaire (pas sur un journal) voit tous les messages qui y passent ; `record.getMessage()` donne le message final, arguments compris.
</details>

**Pour aller plus loin** (facultatif) : lance `gitleaks git` sur le dépôt ; lis la documentation de `keyring` (Python) et réfléchis à ce qu'apporterait le trousseau du système sur `adm01` ; au module 25, le secret viendra de Vault.

---

### M02-E20 — Taskfile (et Makefile) : les tâches du projet  `LAB` `★★`

> **Ticket PLAT-330** — *De : Karim Benali* — *Copie : Lucas Martin*
> Pour lancer les tests, il faut aujourd'hui connaître six commandes et leurs options, et la CI de E24 en aura une septième version. Je veux **une** interface : `task lint`, `task test`, `task build`, `task install`, identiques sur `adm01` et sur `runner01`. Lucas demande pourquoi pas un Makefile : écris aussi l'équivalent, et dis-nous ce que chacun fait mieux.

**Objectifs pédagogiques**
- Décrire les tâches d'un projet avec Task 3 : dépendances, préconditions, variables, sources et produits (reconstruction seulement si nécessaire).
- Écrire l'équivalent Make et comparer (dépendances de fichiers, `.PHONY`, tabulations, un shell par ligne).
- Distinguer une installation de développement (liens vers le clone) d'une installation figée (copie versionnée) et savoir laquelle un service planifié doit utiliser.

**Prérequis** : M02-E14, M02-E18 ; Task 3.54 installé sur `adm01` (voir l'introduction).
**Durée indicative** : 2 h.

**Contexte technique**
- Task 3 : https://taskfile.dev (« Guide », « Usage », notamment `deps`, `preconditions`, `sources`/`generates`, `--status`, `--list`) ; `version: '3'` reste obligatoire.
- Tâches attendues (noms imposés, réutilisés par la CI en E24 et par les exercices suivants) : `lint` (ShellCheck et shfmt sans option, réglages lus dans `.shellcheckrc` et `.editorconfig` ; `ruff check` et `ruff format --check`), `test` (bats et pytest, rapports JUnit dans `rapports/`, déjà ignoré par Git), `build` (paquet `medictl` dans `dist/` avec `uv build`, **seulement** si les sources ont changé), `install`, `ci` (lint, test, build dans cet ordre), `clean`. Chaque tâche a une description (`desc`).
- `task install` installe une copie **figée** : `bin/ms-*` dans `/usr/local/bin`, `lib/ms-commun.sh` dans `/usr/local/lib` (les scripts trouvent la bibliothèque par `readlink -f`, donc `/usr/local/bin/../lib`), et `medictl` comme outil uv (`uv tool install`). Le contrôle planifié de E26 exécutera `/usr/local/bin/ms-verif-sauvegardes`, jamais le clone de travail.
- `sudo` sur `adm01` : l'utilisateur `admin` l'a sans mot de passe (cloud-init) ; `task install` est la seule tâche qui l'utilise.

**Travail demandé**
1. Écris `Taskfile.yml`. Pour `build`, déclare les sources et le produit ; lance deux fois et observe. Que fait `task --status build` ?
2. Les tâches `lint` et `test` dépendent d'un environnement Python synchronisé : une tâche `setup` (`uv sync --locked`) appelée une seule fois même si plusieurs tâches en dépendent. Pourquoi `--locked` en CI comme en local ?
3. `task install` : copie, pas lien symbolique. Ajoute une précondition qui refuse d'installer si `bin/` ou `lib/` ont des modifications non commitées. Justifie dans ton journal.
4. Passe des arguments à pytest à travers Task (`task test:py -- -k garde`) : comment ?
5. Écris le `Makefile` équivalent (`make lint`, `make test`, `make build` avec une vraie cible fichier, `make install`, `make ci`, `make help`). Note dans ton journal trois différences concrètes avec Task, et ce qui t'a fait perdre du temps.
6. Mets à jour `README.md` (section « Démarrer ») : une ligne par tâche.
7. Lance `task ci`, puis `task install`, puis vérifie : `medictl --version`, `/usr/local/bin/ms-snapshot --help`.
8. MR `build: Taskfile et Makefile du projet`, fusion.

**Critères de réussite**
- [ ] `task --list` décrit au moins `lint`, `test`, `build`, `install` ; `task lint` et `task test` réussissent ; `task test` produit des rapports JUnit dans `rapports/`.
- [ ] Après `task build`, `task --status build` indique qu'il n'y a rien à refaire ; `dist/` contient la roue `medictl`.
- [ ] `make -n lint` et `make -n test` sont valides.
- [ ] `/usr/local/bin/ms-snapshot` est un fichier (pas un lien), qui trouve sa bibliothèque ; `uv tool list` montre `medictl`.

**Vérification** : `lab/bin/check 02 20` (lance `task lint` et `task test` dans ton clone)

<details><summary>Indice 1</summary>

`sources:` et `generates:` (motifs de fichiers) font sauter une tâche dont les sources n'ont pas changé ; l'empreinte est gardée dans `.task/`, à ignorer dans Git. `run: once` évite d'exécuter deux fois une dépendance commune.
</details>

<details><summary>Indice 2</summary>

`{{.CLI_ARGS}}` contient ce qui suit `--` sur la ligne de commande de `task`. Pour une liste de fichiers calculée : une variable dynamique (`sh:`), déclarée dans la tâche qui l'utilise pour ne pas imposer l'outil à toutes les autres.
</details>

<details><summary>Indice 3</summary>

Dans un Makefile, `$$` pour un `$` destiné au shell, une tabulation obligatoire en tête de recette, et `.PHONY` pour une cible qui n'est pas un fichier. Une cible fichier (`dist/.construit: pyproject.toml uv.lock …`) donne à Make la même économie que `sources`/`generates`.
</details>

**Pour aller plus loin** (facultatif) : ajoute une tâche `doc` qui vérifie que chaque `bin/ms-*` répond à `--help` par une ligne `Usage` ; lis la page « Taskfile Versions » de taskfile.dev ; regarde `just` et compare.

---

### M02-E21 — Générer l'inventaire du socle depuis l'API  `LIBRE` `★★★`

> **Ticket PLAT-331** — *De : Claire Morel* — *Copie : Sophie Laurent*
> L'inventaire du socle (`docs/socle/inventaire.md` dans `plateforme/medisphere`) est faux depuis le module 01 : `git01` et `runner01` y ont été ajoutés à la main, avec une erreur de mémoire, et personne n'a reporté le changement d'adresse d'hier. Un inventaire tenu à la main finit toujours faux. Je veux qu'il soit **généré** depuis l'hyperviseur, relu en MR comme n'importe quel changement, et que deux générations sans changement du lab donnent exactement le même fichier. Sophie s'en servira pour l'audit ISO 27001 (inventaire des actifs).

**Objectifs pédagogiques**
- Concevoir de bout en bout une petite fonctionnalité : contrat de sortie, données sources, cas dégradés, intégration dans un document existant.
- Produire une sortie déterministe et exploitable en revue de code (diff minimal).
- Combiner plusieurs points de l'API (ressources, agent QEMU) avec des performances maîtrisées.

**Prérequis** : M02-E15 à M02-E20 ; M01 (MR sur `plateforme/medisphere`).
**Durée indicative** : 4 h.

**Contexte technique**
- Source : les VMs portant l'étiquette Proxmox `socle` (PLAN.md §4.8), visibles par le jeton `wb-automation@pve!lab`. Le rôle se lit dans l'étiquette `role-<rôle>`. Les adresses IPv4 viennent de l'agent QEMU (`VM.GuestAgent.Audit`, déjà dans le rôle `WBAutomation`).
- Interface : `medictl inventaire [--format markdown|json]` (tu peux ajouter des options).
- Contrat JSON (lu par les vérifications et par les exercices suivants) : une liste d'objets avec au moins `vmid`, `name`, `status`, `tags` et `ipv4` (liste de chaînes, vide si l'agent ne répond pas).
- Contrat Markdown : un tableau dont chaque ligne de VM commence par `| <VMID> |`.

**Travail demandé**

Livre `medictl inventaire` et une MR sur `plateforme/medisphere` qui remplace la partie « VMs » de `docs/socle/inventaire.md` par la sortie de l'outil. Contraintes :
- le texte rédigé par l'équipe dans `inventaire.md` (introduction, remarques) est conservé ; seule la partie générée change, et elle est identifiable comme générée ;
- deux générations successives sans changement du lab produisent un résultat **identique, octet pour octet** ;
- une VM arrêtée, ou dont l'agent ne répond pas, apparaît quand même (sans adresse), sans faire échouer l'inventaire ni le ralentir de façon notable ; l'inventaire complet prend moins de 60 s ;
- aucune VM hors étiquette `socle` (ni template, ni VM jetable) ;
- la fonctionnalité est testée sans Proxmox (pytest) et passe `task lint` et `task test` ;
- la MR sur `plateforme/medisphere` explique comment régénérer le fichier.

**Critères de réussite**
- [ ] `medictl inventaire --format json` respecte le contrat et contient `gw01`, `adm01`, `dns01`, `git01`, `runner01` avec leurs adresses du plan (10.10.10.1, 10.10.10.10, 10.10.20.10, 10.10.20.12, 10.10.20.15).
- [ ] Le template 9000 et les VMs jetables n'y figurent pas ; la génération prend moins de 60 s.
- [ ] Deux sorties Markdown successives sont identiques.
- [ ] Sur `main` de `plateforme/medisphere`, `docs/socle/inventaire.md` contient les lignes du tableau tel que l'outil le génère aujourd'hui.

**Vérification** : `lab/bin/check 02 21`

<details><summary>Indice 1</summary>

Qu'est-ce qui, dans une sortie, change d'une exécution à l'autre sans que le lab ait changé ? Pense à l'ordre, aux dates, aux valeurs instantanées (CPU, mémoire utilisée, durée de fonctionnement).
</details>

<details><summary>Indice 2</summary>

Pour remplacer une partie d'un document sans toucher au reste, il faut savoir où elle commence et où elle finit, de façon fiable même si quelqu'un modifie le texte autour. Que doit faire l'outil si ces repères sont absents ou en double ?
</details>

<details><summary>Indice 3</summary>

L'agent QEMU d'une VM arrêtée ne répondra pas : est-il utile de lui poser la question ? Un appel qui échoue doit-il être repris ici ?
</details>

**Pour aller plus loin** (facultatif) : ajoute la colonne « dernière sauvegarde » (elle sera disponible en E26) ; génère aussi le fichier en CI et fais échouer le pipeline de `plateforme/medisphere` si l'inventaire commité n'est plus à jour. Au module 06, la source de vérité deviendra NetBox.

---

### M02-E22 — Revue d'un script Bash du stagiaire  `REV` `★★`

> **Ticket PLAT-332** — *De : Karim Benali*
> Lucas a écrit un script de collecte nocturne de `/etc` de toutes les VMs du socle (`ressources/M02-E22/collecte-etc.sh`). Il tourne en cron sur sa VM d'essai depuis une semaine, « sans erreur ». Avant qu'il ouvre sa MR, fais-lui une vraie revue : chaque défaut, sa gravité, l'impact concret, la correction. Puis donne-nous ton avis sur la question de fond : a-t-on besoin de ce script ?

**Objectifs pédagogiques**
- Lire un script Bash comme il s'exécutera vraiment : sous cron, sans argument, avec une variable vide, avec une API en panne.
- Classer des défauts par nature (sécurité, fonctionnement, maintenabilité) et par gravité.
- Distinguer ce que ShellCheck trouve de ce qu'il ne peut pas trouver.
- Remettre en cause le besoin, pas seulement le code.

**Prérequis** : M02-E03, M02-E10, M02-E12, M02-E13.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Le script est fourni dans `ressources/M02-E22/collecte-etc.sh` ; le secret qu'il contient est **fictif**. Lucas le lance par cron (`0 2 * * *`), sans argument, depuis le compte `admin` de sa VM d'essai.
- Il contient une dizaine de défauts de gravités variées, plus quelques maladresses.

> ⚠️ **Attention** : **n'exécute pas** ce script, ni sur `adm01` ni ailleurs : selon l'environnement, il peut supprimer des fichiers de ton dossier personnel. Pour observer un comportement, recopie la ligne en cause dans un dossier jetable (`mktemp -d`).

**Travail demandé**
1. Lis le script une fois sans rien noter. Puis réponds : sous cron, avec `COLLECTE_DIR` non définie, que fait chaque ligne entre 12 et 35 ? Avec `COLLECTE_DIR` définie et l'API Proxmox en panne ? Avec cinq VMs du socle joignables ?
2. Lance `shellcheck` sur une copie : quels défauts trouve-t-il, lesquels lui échappent ?
3. Rédige la revue sous forme de tableau : n°, ligne(s), défaut, catégorie, gravité (critique, élevée, moyenne, faible), impact concret, correction.
4. Classe les défauts par ordre de traitement et explique ton ordre.
5. Propose une version corrigée complète, conforme aux conventions du projet (bibliothèque commune, codes retour, verrou), qui passe ShellCheck. Tu n'as pas à la fusionner.
6. Question de fond, en cinq lignes : ce script fait-il double emploi avec `ms-collecte-config` (E03) et avec les sauvegardes PBS (M00-E22) ? Que recommandes-tu à Karim ?
7. Trois lignes de conseils à Lucas sur sa façon de tester (« sans erreur depuis une semaine »).

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 9 défauts identifiés, dont tous les défauts critiques et élevés du corrigé.
- [ ] Chaque défaut a un impact concret et une correction précise.
- [ ] La version corrigée passe ShellCheck et ne réintroduit aucun défaut.
- [ ] La question de fond reçoit une réponse argumentée.

<details><summary>Indice 1</summary>

Trois défauts graves ne se voient qu'en se demandant ce que vaut chaque variable **sous cron**, puis ce que fait `cd` sans argument.
</details>

<details><summary>Indice 2</summary>

Regarde ce que renvoie `((OK++))` quand `OK` vaut 0, et ce que `set -e` en fait. Regarde aussi ce que contient une archive de `/etc` et qui pourra la lire.
</details>

<details><summary>Indice 3</summary>

Suis le jeton : où est-il écrit, où est-il affiché, à qui est-il envoyé, et que vérifie `curl` avant de l'envoyer ?
</details>

**Pour aller plus loin** (facultatif) : écris les tests bats qui auraient attrapé les trois défauts les plus graves (avec un faux `ssh` et un faux `curl`).

---

### M02-E23 — Revue d'un script Python du stagiaire  `REV` `★★`

> **Ticket PLAT-333** — *De : Claire Morel* — *Copie : Lucas Martin*
> Lucas propose un rapport nocturne de capacité mémoire (`ressources/M02-E23/rapport_capacite.py`) : combien de RAM est allouée par pool, et une alerte au-delà de 80 %. « Testé avec mon export, ça marche. » Je voudrais le brancher dès cette semaine. Fais la revue, et dis-moi franchement si je peux m'y fier pour décider d'acheter de la mémoire.

**Objectifs pédagogiques**
- Repérer les défauts classiques d'un script Python d'exploitation : TLS, délais, exceptions, état partagé, types, unités.
- Distinguer un script « qui marche avec mes données » d'un outil fiable en production (droits du jeton, cas vides, codes de sortie).
- Utiliser ruff (règles `B`, `S`) comme aide, sans s'y limiter.

**Prérequis** : M02-E15 à M02-E19.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers : `ressources/M02-E23/rapport_capacite.py` (le secret qu'il contient est fictif), et deux exports de `GET /cluster/resources` : `donnees/cluster-resources-admin.json` (celui de Lucas, fait avec son compte d'administrateur) et `donnees/cluster-resources-jeton.json` (ce que voit le jeton `wb-automation@pve!lab` du cron).
- Le script a une option `--depuis-fichier` qui permet de l'exécuter sans API : c'est la seule façon de l'exécuter dans cet exercice.
- `pve01` a 128 Go de mémoire (PLAN.md §3.1).

**Travail demandé**
1. Exécute-le dans un dossier jetable sur les deux exports, puis avec `--seuil 50`. Note ce qui se passe et pourquoi.
   ```
   admin@adm01:~$ mkdir -p ~/m02/e23 && cd ~/m02/e23 && cp ~/DevOpsPrivateCloud/modules/02-scripting/ressources/M02-E23/rapport_capacite.py .
   admin@adm01:~/m02/e23$ python3 rapport_capacite.py --depuis-fichier ~/DevOpsPrivateCloud/modules/02-scripting/ressources/M02-E23/donnees/cluster-resources-admin.json
   ```
2. Vérifie les chiffres à la main : la mémoire allouée totale annoncée est-elle juste ? Dans quelle unité ?
3. Lance `ruff check --select E,F,B,S,SIM` sur le fichier (avec l'environnement de `plateforme/outils`). Quels défauts trouve-t-il, lesquels lui échappent ?
4. Rédige la revue en tableau (n°, ligne(s), défaut, catégorie, gravité, impact concret, correction). Cherche aussi ce qui se passerait **en cron** : API injoignable, jeton expiré, export illisible, Ctrl-C.
5. Propose une version corrigée complète (testable : pas d'effet de bord à l'import, fonctions pures pour le calcul, codes de sortie exploitables par cron ou systemd).
6. Réponds à Claire en cinq lignes : peut-elle se fier au rapport, et à quelle condition sur les droits du jeton ?

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 10 défauts identifiés, dont tous les critiques et élevés du corrigé.
- [ ] L'écart entre l'export de Lucas et ce que voit le jeton est expliqué, avec sa conséquence.
- [ ] La version corrigée tourne sur les deux exports et passe `ruff check` avec les règles du projet.
- [ ] La réponse à Claire est argumentée.

<details><summary>Indice 1</summary>

Qu'est-ce qu'un argument de ligne de commande, en Python, avant conversion ? Que devient une valeur par défaut mutable d'une fonction après le premier appel ?
</details>

<details><summary>Indice 2</summary>

Compare les deux exports : quels types de ressources (`type`) contient chacun ? Le jeton du cron a-t-il `Sys.Audit` sur `/nodes` ?
</details>

<details><summary>Indice 3</summary>

Que fait `except:` d'un `KeyboardInterrupt` ? Que renvoie `r.json()["data"]` quand Proxmox répond 401 ? Combien de temps `requests.get` attend-il sans `timeout` ?
</details>

**Pour aller plus loin** (facultatif) : transforme la version corrigée en commande `medictl capacite` avec ses tests pytest ; au module 21, ce type de seuil deviendra une règle d'alerte Prometheus.
