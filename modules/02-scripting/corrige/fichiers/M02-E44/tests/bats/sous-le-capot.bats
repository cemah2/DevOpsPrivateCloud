#!/usr/bin/env bats
# sous-le-capot.bats — spécification exécutable du comportement de Bash (M02-E44, PLAT-385).
#
# Chaque test fixe UN comportement sur lequel les outils de plateforme/outils s'appuient (ou
# qu'ils doivent contourner). Le code étudié tourne dans un « bash -c » neuf : ni les options de
# bats, ni l'environnement du test ne le perturbent. Vérifié avec Bash 5.2 (Debian 13) et
# bats-core 1.13. Si un test casse après une montée de version de Bash, c'est une information.
# Aucun accès réseau ; tous les fichiers sont créés dans $BATS_TEST_TMPDIR.
# shellcheck disable=SC2016  # le code entre apostrophes est évalué par « bash -c », pas ici

bats_require_minimum_version 1.5.0

setup() {
  cd "$BATS_TEST_TMPDIR" || return 1
}

# Aucun processus d'essai ne survit au test, même s'il échoue en cours de route.
teardown() {
  local f
  for f in "$BATS_TEST_TMPDIR"/pid*; do
    [[ -f "$f" ]] && kill "$(cat "$f")" 2>/dev/null
  done
  return 0
}

# sh 'code' [args...] — exécute le code dans un bash neuf, sans profil, sans option héritée.
sh() {
  local code="$1"
  shift
  bash --norc --noprofile -c "$code" bash "$@"
}

@test "expansions : l'accolade est développée AVANT les variables (pas de {1..3} dynamique)" {
  run -0 sh 'n=3; echo {1..$n}; a="{1,2}"; echo $a'
  [[ "${lines[0]}" == '{1..3}' ]]
  [[ "${lines[1]}" == '{1,2}' ]]
}

@test "expansions : le tilde n'est pas développé s'il vient d'une variable" {
  run -0 sh 'v="~"; echo $v; echo ~'
  [[ "${lines[0]}" == '~' ]]
  [[ "${lines[1]}" == "$HOME" ]]
}

@test "découpage : une variable vide non protégée disparaît, protégée elle compte" {
  run -0 sh 'compte() { echo $#; }; vide=""; compte $vide; compte "$vide"'
  [[ "${lines[*]}" == '0 1' ]]
}

@test "découpage : \"\$@\" garde chaque argument intact, \$* et \$@ non protégés les recoupent" {
  run -0 sh 'compte() { echo $#; }; compte "$@"; compte "$*"; compte $@' 'un deux' trois
  [[ "${lines[*]}" == '2 1 3' ]]
}

@test "globbing : le motif contenu dans une variable non protégée est développé (et pas entre guillemets)" {
  touch a.log b.log
  run -0 sh 'x="*.log"; echo $x; echo "$x"'
  [[ "${lines[0]}" == 'a.log b.log' ]]
  [[ "${lines[1]}" == '*.log' ]]
}

@test "globbing : sans correspondance, le motif reste tel quel, sauf avec nullglob" {
  run -0 sh 'for f in *.absent; do echo "[$f]"; done; shopt -s nullglob; for f in *.absent; do echo "[$f]"; done; echo fin'
  [[ "${lines[*]}" == '[*.absent] fin' ]]
}

@test "substitution de commande : les sauts de ligne FINAUX sont supprimés" {
  run -0 sh 'x="$(printf "a\n\n\n")"; printf "%s|" "$x"; y="$(printf "a\n\n"; printf .)"; y="${y%.}"; printf "%s|" "${#y}"'
  [[ "$output" == 'a|3|' ]]
}

@test "sous-shell : une variable modifiée dans « cmd | while read » est perdue" {
  run -0 sh 'n=0; printf "1\n2\n" | while read -r l; do n=$((n + l)); done; echo "$n"'
  [[ "$output" == 0 ]]
}

@test "sous-shell : « done < <(cmd) » ou lastpipe gardent la variable dans le shell courant" {
  run -0 sh 'n=0; while read -r l; do n=$((n + l)); done < <(printf "1\n2\n"); echo "$n"
             m=0; shopt -s lastpipe; printf "1\n2\n" | while read -r l; do m=$((m + l)); done; echo "$m"'
  [[ "${lines[*]}" == '3 3' ]]
}

@test "sous-shell : \$\$ reste le PID du script, \$BASHPID et BASH_SUBSHELL changent" {
  run -0 sh 'echo "$$ $BASHPID $BASH_SUBSHELL"; ( echo "$$ $BASHPID $BASH_SUBSHELL" )'
  read -r p1 b1 n1 <<<"${lines[0]}"
  read -r p2 b2 n2 <<<"${lines[1]}"
  [[ "$p1" == "$p2" && "$b1" == "$p1" && "$b2" != "$b1" ]]
  [[ "$n1" == 0 && "$n2" == 1 ]]
}

@test "sous-shell : exit et cd dans ( … ) ne touchent pas le shell parent" {
  run -0 sh 'cd /; ( cd /tmp; exit 7 ); echo "code=$? pwd=$PWD"'
  [[ "$output" == 'code=7 pwd=/' ]]
}

@test "redirections : lues de gauche à droite (« 2>&1 >f » laisse stderr sur l'ancienne sortie)" {
  run -0 --separate-stderr sh 'f() { echo out; echo err >&2; }; f 2>&1 >un.txt; f >deux.txt 2>&1'
  [[ "$output" == 'err' ]]
  [[ "$(cat un.txt)" == 'out' ]]
  [[ "$(cat deux.txt)" == $'out\nerr' ]]
}

@test "redirections : {fd}> alloue un descripteur libre (≥ 10) et l'ouvre dans le shell courant" {
  run -0 sh 'exec {fd}>trace.txt; echo "fd=$fd"; echo ligne >&"$fd"; exec {fd}>&-; cat trace.txt'
  [[ "${lines[0]}" =~ ^fd=([0-9]+)$ ]]
  ((BASH_REMATCH[1] >= 10))
  [[ "${lines[1]}" == ligne ]]
}

@test "redirections : une substitution de processus est un chemin /dev/fd/N" {
  run -0 sh 'echo <(true)'
  [[ "$output" =~ ^/dev/fd/[0-9]+$ ]]
}

@test "here-string : <<< ajoute un saut de ligne final, printf ne le fait pas" {
  run -0 sh 'wc -c <<<"abc"; printf "%s" abc | wc -c'
  [[ "${lines[*]}" == '4 3' ]]
}

@test "read : sans -r les barres obliques inverses sont mangées ; sans IFS= les espaces de tête aussi" {
  run -0 sh 'printf "  a\\\\b\n" | { read l; echo "[$l]"; }; printf "  a\\\\b\n" | { IFS= read -r l; echo "[$l]"; }'
  [[ "${lines[0]}" == '[ab]' ]]
  [[ "${lines[1]}" == '[  a\b]' ]]
}

@test "descripteurs hérités : un enfant en arrière-plan garde le verrou flock après la fin du script" {
  command -v flock >/dev/null || skip "flock absent"
  # Le script prend le verrou, lance un « sleep » en arrière-plan et se termine.
  sh 'exec {v}>verrou; flock -n "$v"; sleep 30 & echo $! >pid'
  run -1 flock -n verrou true
  # Correction : le descripteur est fermé pour l'enfant ({v}>&-), le verrou meurt avec le script.
  sh 'exec {v}>verrou2; flock -n "$v"; sleep 30 {v}>&- & echo $! >pid2'
  run -0 flock -n verrou2 true
}

@test "portée dynamique : une fonction voit (et modifie) les variables locales de son appelant" {
  run -0 sh 'g() { x=modifie; }; f() { local x=local; g; echo "$x"; }; x=global; f; echo "$x"'
  [[ "${lines[*]}" == 'modifie global' ]]
}

@test "[[ == ]] : le membre droit NON protégé est un motif, protégé c'est une chaîne" {
  run -0 sh 'v="a*"; [[ abc == $v ]] && echo motif; [[ abc == "$v" ]] || echo chaine'
  [[ "${lines[*]}" == 'motif chaine' ]]
}

@test "PIPESTATUS : le code de chaque étage d'un tube, à lire immédiatement" {
  run -0 sh 'false | true | (exit 3); echo "${PIPESTATUS[*]}"; echo "${PIPESTATUS[*]}"'
  [[ "${lines[0]}" == '1 0 3' ]]
  [[ "${lines[1]}" == '0' ]]
}
