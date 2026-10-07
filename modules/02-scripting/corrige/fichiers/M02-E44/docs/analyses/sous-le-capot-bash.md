# Sous le capot de Bash : expansions, sous-shells et descripteurs

> Analyse de l'équipe Plateforme (ticket PLAT-385). Référence : Bash 5.2 (Debian 13). Chaque
> affirmation est prouvée par un test de [`tests/bats/sous-le-capot.bats`](../../tests/bats/sous-le-capot.bats)
> (`bats tests/bats/sous-le-capot.bats`) ; le numéro du test est indiqué entre crochets.
> Source : manuel de GNU Bash, sections *Shell Expansions*, *Redirections*, *Command Execution
> Environment*, *Pipelines*, *Bash Builtins* (`read`, `local`, `shopt`).

## Résumé pour la revue de code

| Motif repéré en revue | Risque | Écrire plutôt |
|---|---|---|
| `cmd \| while read …; do var=…; done` puis `$var` | valeur perdue (sous-shell) | `while …; done < <(cmd)` |
| `$var` non protégé | découpage + globbing | `"$var"`, tableaux `"${a[@]}"` |
| `x=$(cat f)` pour reconstruire un fichier | sauts de ligne finaux perdus | travailler sur le fichier, ou `x=$(cat f; printf .)` puis `${x%.}` |
| `cmd 2>&1 >f` | stderr pas dans `f` | `cmd >f 2>&1` |
| verrou `flock` + enfant en arrière-plan | verrou tenu après la fin du script | fermer le descripteur pour l'enfant (`{fd}>&-`) |
| `read l` | `\` et espaces de tête mangés | `IFS= read -r l` |
| `[[ $a == $b ]]` | `$b` interprété comme motif | `[[ $a == "$b" ]]` |
| variable non déclarée `local` dans une fonction | modifie celle de l'appelant | `local` systématique, noms préfixés dans les bibliothèques |

## Réponses aux questions

1. **Ordre des expansions.** Bash développe dans cet ordre : accolades → tilde, paramètres et
   variables, arithmétique, substitution de commande et de processus (de gauche à droite, au même
   niveau) → découpage en mots (`IFS`) → développement des chemins (globbing) → retrait des
   guillemets. `{1..$n}` : l'accolade est traitée **avant** que `$n` ne vaille 3 ; la séquence
   `{1..$n}` n'est pas valide, elle reste littérale [1]. `v='~'; ls $v` : le tilde n'est reconnu
   qu'au début d'un mot écrit tel quel ; issu d'une variable, il n'est jamais développé [2]. Pour
   une suite dynamique : `seq 1 "$n"` ou `for ((i = 1; i <= n; i++))`.

2. **Nombre d'arguments.** `$vide` → 0 argument (le mot vide disparaît au découpage) ; `"$vide"`
   → 1 argument vide [3]. Avec `'un deux' trois` : `"$@"` → 2 arguments intacts, `"$*"` → 1 seul
   (joints par le premier caractère d'`IFS`), `$@`/`$*` non protégés → 3 (recoupés) [4]. Pour
   **transmettre** des arguments : toujours `"$@"`. `"$*"` ne sert qu'à fabriquer un message.

3. **Globbing.** Le développement des chemins a lieu après le découpage, donc sur le **contenu**
   des variables non protégées [5]. Sans correspondance, le motif est passé tel quel (`rm *.tmp`
   reçoit l'argument littéral `*.tmp` et échoue) ; avec `nullglob`, il disparaît [6]. Danger de
   `nullglob` : une commande qui n'a plus d'argument change de sens (`ls $motif` liste le dossier
   courant ; `rm -f -- $motif` devient `rm -f --`, sans effet, mais `cat $motif` lit l'entrée
   standard et bloque). D'où : `nullglob` seulement dans une boucle `for`, ou `failglob` pour
   transformer l'absence en erreur.

4. **Substitution de commande.** `$(…)` supprime **tous** les sauts de ligne finaux [7] (et
   les octets nuls, avec un avertissement). Un script qui relit un fichier par `$(cat f)` puis le
   réécrit le modifie ; une empreinte calculée sur `"$x"` ne correspond plus au fichier. Parades :
   travailler sur le fichier lui-même (`sha256sum f`, `cp`), ou ajouter une sentinelle
   (`x=$(cat f; printf .); x=${x%.}`) quand le contenu doit transiter par une variable.

5. **`cmd | while read`.** Chaque étage d'un tube s'exécute dans un sous-shell : la boucle
   modifie **sa copie** de `n`, perdue à la fin du tube [8]. Corrections [9] :
   `while …; done < <(cmd)` (la boucle reste dans le shell courant, `cmd` passe dans le
   sous-processus) ; ou `shopt -s lastpipe`, qui exécute le **dernier** étage dans le shell
   courant, mais seulement quand le contrôle des tâches est désactivé (cas d'un script, pas d'un
   terminal interactif). Limite de `< <(cmd)` : le code retour de `cmd` est perdu, sauf
   `wait "$!"` (question 10).

6. **`$$`, `$BASHPID`, `BASH_SUBSHELL`.** `$$` vaut le PID du shell **principal**, même dans un
   sous-shell ; `$BASHPID` vaut le PID du processus Bash courant ; `BASH_SUBSHELL` augmente de 1
   à chaque niveau [10]. Pour un fichier propre à un processus fils, `$BASHPID` est le seul juste
   (`/tmp/x.$$` serait partagé par tous les fils). Mais un nom prévisible dans `/tmp` reste une
   faille (lien symbolique préparé par un autre utilisateur) : `mktemp` crée le fichier de façon
   atomique, avec un nom imprévisible et les droits 600.

7. **Ce qui crée un sous-shell.** `( … )`, chaque étage d'un tube (sauf le dernier avec
   `lastpipe`), `$( … )` et `` ` … ` ``, `<( … )`/`>( … )`, une commande lancée avec `&`, et les
   coprocessus. N'y survivent pas : les affectations de variables, `cd`, `umask`, `set`/`shopt`,
   les `trap` ; `exit` ne quitte que le sous-shell, son code devient celui de `( … )` [11]. À
   l'inverse, `{ …; }` groupe sans sous-shell.

8. **Ordre des redirections.** Elles s'appliquent de gauche à droite et `n>&m` **copie** le
   descripteur `m` tel qu'il est à cet instant [12]. `cmd 2>&1 >f` : (1) stderr devient une copie
   de stdout, qui est encore le terminal ; (2) stdout est redirigé vers `f`. Résultat : stdout dans
   `f`, stderr au terminal. `cmd >f 2>&1` : stdout vers `f`, puis stderr copie de ce nouveau
   stdout : les deux dans `f`. `exec 3>&1 1>&2 2>&3 3>&-` échange stdout et stderr du shell
   courant en passant par un descripteur temporaire 3, refermé ensuite.

9. **`exec {fd}>fichier`.** Bash choisit un descripteur libre à partir de 10 [13] pour ne pas
   écraser 0-9, que les scripts utilisent en dur (`3>`, `9>`…) ; le numéro est dans `$fd`. Un
   descripteur ouvert par `exec` reste ouvert **et hérité par tous les enfants** jusqu'à sa
   fermeture. Le verrou de `lock_or_die` (E13) est un `flock` sur un tel descripteur : il est
   relâché quand le **dernier** processus qui détient le descripteur le ferme. Un `sleep 600 &`
   (ou un `ssh` en arrière-plan, un démon lancé par le script) hérite du descripteur et garde le
   verrou après la fin du script : l'exécution suivante est refusée (code 3) [17]. Parade : fermer
   le descripteur pour l'enfant (`cmd {fd}>&- &`), ou utiliser `flock -o` quand on passe par
   la commande `flock` (le verrou n'est alors pas transmis à la commande lancée).

10. **`/dev/fd/63`.** `<(cmd)` lance `cmd` avec sa sortie reliée à un tube, et remplace
    l'expression par un chemin `/dev/fd/N` qui désigne l'autre extrémité [14] ; `diff` ouvre ces
    chemins comme des fichiers. Le code retour de `cmd` n'est pas celui de la commande principale.
    Depuis Bash 4.4, `$!` contient le PID de la dernière substitution de processus et
    `wait "$!"` rend son code retour : c'est ce que font `ms-purge-rapports` (E37) et
    `ms-archiver-journaux` (E39) après `mapfile … < <(find …)`.

11. **`read`.** Sans `-r`, `\` est un caractère d'échappement (et `\` en fin de ligne joint la
    ligne suivante) ; sans `IFS=`, les espaces et tabulations de début et de fin sont retirés [16].
    `-d ''` lit jusqu'à un octet nul (couple avec `find -print0`). Une dernière ligne sans saut de
    ligne final : `read` la lit mais rend 1 (fin de fichier), donc `while read` sort sans traiter
    la ligne. Parade : `while IFS= read -r l || [[ -n "$l" ]]; do …`.

12. **Portée dynamique.** Une variable `local` est visible des fonctions **appelées** par la
    fonction qui la déclare, et une affectation sans `local` dans l'appelée modifie la variable
    de l'appelant [18]. `retry 3 2 ma_fonction` : si `retry` avait une locale `essai` et que
    `ma_fonction` utilisait (sans `local`) une variable `essai`, elle écraserait le compteur de
    `retry`, qui bouclerait à l'infini ou s'arrêterait trop tôt. Les préfixes `_ms_` de la
    bibliothèque rendent la collision improbable ; la règle d'équipe reste « `local` partout ».

13. **Comparaisons.** Dans `[[ $a == $b ]]`, le membre droit non protégé est un **motif** :
    `b='*'` rend la comparaison toujours vraie (un garde-fou contourné par un argument) [19] ;
    `[[ $a == "$b" ]]` compare des chaînes. Dans `[[ ]]`, pas de découpage ni de globbing sur les
    variables, d'où l'absence de guillemets nécessaires à gauche. `[ $a = $b ]` est une commande
    ordinaire : variables découpées et globbées, `[: too many arguments` si l'une contient un
    espace, test faux ou erreur si l'une est vide. Dans les outils : `[[ ]]` (règle ShellCheck
    `require-double-brackets` du projet).

14. **`PIPESTATUS`.** Tableau des codes de chaque étage du **dernier** tube exécuté ; toute
    commande suivante (même `echo`) le remplace : il faut le copier immédiatement
    (`codes=("${PIPESTATUS[@]}")`) [20]. `pipefail` donne le code du dernier étage en échec, ce
    qui suffit à **détecter** ; `PIPESTATUS` dit **lequel** a échoué (utile pour un message
    d'erreur : `tar` ou `gzip` ?). Avec `set -e`, il faut tester le tube dans un `if !` ou avec
    `|| codes=…` pour avoir le temps de lire `PIPESTATUS`.

## Ce que l'audit du projet a trouvé

Commandes lancées dans `~/src/outils` (à compléter par l'équipe à chaque revue) :

```
grep -rnE '\|[[:space:]]*while[[:space:]]+(IFS=[^ ]*[[:space:]]+)?read' bin lib
grep -rnE '2>&1[[:space:]]*>[^&]' bin lib
grep -rnE '\bread[[:space:]]+[^-]' bin lib            # read sans option
grep -rnE '&[[:space:]]*$' bin lib                      # lancements en arrière-plan à examiner (verrou)
```

Tout résultat est examiné en MR : soit corrigé, soit justifié par un commentaire.
