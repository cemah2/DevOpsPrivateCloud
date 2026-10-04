# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent leurs paramètres en arguments
#
# check-E44.sh — M01-E44 « Trouver le commit fautif avec git bisect run »
# Dépôt ~/src/labo-e44 (ressources/M01-E44/fabriquer-depot.sh) : bisection terminée, script de
# test réutilisable, correctif par revert du commit fautif (et de lui seul), tests au vert,
# résultat consigné dans le journal. Lecture seule : les tests sont rejoués sur une copie
# extraite par « git archive » dans un dossier temporaire.

title "M01-E44 — Trouver le commit fautif avec git bisect run"
require_cmd git

_m01_d44="${WB_SRC:-$HOME/src}/labo-e44"
_m01_script44="${WB_SRC:-$HOME/src}/bisect-e44.sh"
_m01_fautif="$(git -C "$_m01_d44" log --format=%H main \
  --grep='^refactor(ports): simplifier le découpage des plages$' 2>/dev/null | head -n 1)" || _m01_fautif=""

check_cmd "labo-e44 : dépôt présent" git -C "$_m01_d44" rev-parse --is-inside-work-tree
check_cmd "labo-e44 : aucune bisection en cours (git bisect reset fait)" \
  bash -c '! test -e "$(git -C "$1" rev-parse --git-path BISECT_START 2>/dev/null)"' _ "$_m01_d44"
check_cmd "script de bisection $_m01_script44 présent et exécutable" test -x "$_m01_script44"
check_cmd "script de bisection : distingue « non testable » (code 125)" \
  grep -Eq '(^|[^0-9])125([^0-9]|$)' "$_m01_script44"
check_cmd "labo-e44 : branche fix/regression-plages issue de main" \
  git -C "$_m01_d44" merge-base --is-ancestor main fix/regression-plages
check_cmd "fix/regression-plages : annule précisément le commit fautif (git revert)" bash -c '
  [ -n "$2" ] && git -C "$1" log --format=%B main..fix/regression-plages | grep -q "This reverts commit $2"' \
  _ "$_m01_d44" "$_m01_fautif"
check_cmd "fix/regression-plages : la fusion de la branche refactor/ports n'est pas annulée en bloc" bash -c '
  m=$(git -C "$1" log --format=%H --merges --grep="^Merge branch .refactor/ports.$" main | head -n 1)
  [ -n "$m" ] && ! git -C "$1" log --format=%B main..fix/regression-plages | grep -q "This reverts commit $m"' _ "$_m01_d44"
check_cmd "fix/regression-plages : tests au vert" bash -c '
  t=$(mktemp -d) || exit 1
  git -C "$1" archive fix/regression-plages | tar -x -C "$t" && "$t/tests/test.sh" >/dev/null 2>&1; r=$?
  rm -rf "$t"; exit $r' _ "$_m01_d44"
check_cmd "journal de diagnostic : empreinte du commit fautif consignée" bash -c '
  [ -n "$2" ] && grep -rqs "${2:0:7}" "$1/docs/socle/journal/"' _ "${WB_DEPOT:-$HOME/medisphere}" "$_m01_fautif"
