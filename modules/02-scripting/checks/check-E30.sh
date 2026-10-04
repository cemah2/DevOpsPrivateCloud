# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E30.sh — M02-E30 : Signaux, délais et sous-processus
# À lancer depuis adm01. Lance TON bin/ms-attendre sur des commandes locales inoffensives
# (true, false, sleep) : délais, codes retour, signaux, processus orphelins. Lecture seule.

title "M02-E30 — Signaux, délais et sous-processus"
require_cmd timeout python3 pgrep

_m02_o="${WB_SRC:-$HOME/src}/outils/bin/ms-attendre"
check_cmd "bin/ms-attendre existe et est exécutable" test -x "$_m02_o"

# _m02_duree CMD... — affiche « code durée_en_secondes »
_m02_duree() {
  local d="$SECONDS" rc=0
  timeout 60 "$@" >/dev/null 2>&1 || rc=$?
  echo "$rc $((SECONDS - d))"
}
# _m02_orphelins SIGNATURE — nombre de processus « sleep SIGNATURE » encore vivants
_m02_orphelins() { pgrep -fx "sleep $1" | grep -c . || true; }

check_output "succès immédiat : code 0" '^0 [0-2]$' _m02_duree "$_m02_o" -- true
check_output "délai total de 3 s dépassé : code 1, en moins de 7 s" '^1 [2-6]$' \
  _m02_duree "$_m02_o" -d 3 -i 1 -- false
check_output "essai bloqué (sleep 30) tué au bout de -e 1 : code 1 en moins de 9 s" '^1 [1-8]$' \
  _m02_duree "$_m02_o" -d 4 -i 1 -e 1 -- sleep 30
check_output "usage invalide : code 2" '^2 [0-2]$' _m02_duree "$_m02_o" -d abc -- true

for _m02_sig in TERM INT; do
  _m02_sg="31.$((RANDOM % 900 + 100))"
  # Lancé par python3 avec SIGINT remis à son action par défaut : une commande lancée en
  # arrière-plan par un script hérite d'un SIGINT ignoré, que bash ne peut plus intercepter.
  python3 -c 'import os, signal, sys
signal.signal(signal.SIGINT, signal.SIG_DFL)
os.setsid()
os.execv(sys.argv[1], sys.argv[1:])' "$_m02_o" -d 60 -e 50 -- sleep "$_m02_sg" >/dev/null 2>&1 &
  _m02_pid=$!
  sleep 1
  _m02_t0="$SECONDS"
  kill -s "$_m02_sig" "$_m02_pid" 2>/dev/null
  _m02_rc=0
  wait "$_m02_pid" 2>/dev/null || _m02_rc=$?
  _m02_d=$((SECONDS - _m02_t0))
  sleep 0.5
  _m02_attendu=143
  [[ "$_m02_sig" == INT ]] && _m02_attendu=130
  check_output "SIG$_m02_sig pendant un essai : sortie immédiate avec le code $_m02_attendu" "^$_m02_attendu [0-2]\$" \
    echo "$_m02_rc $_m02_d"
  check_output "SIG$_m02_sig : l'essai en cours a été tué (aucun « sleep » orphelin)" '^0$' \
    _m02_orphelins "$_m02_sg"
  pkill -KILL -fx "sleep $_m02_sg" 2>/dev/null || true
done

# --- Tests pytest du comportement face aux signaux, dans la CI ----------------------------
_m02_p="projects/plateforme%2Foutils"
_m02_pl="$(gitlab_api "$_m02_p/pipelines?ref=main&status=success&per_page=1" 2>/dev/null)" || _m02_pl="[]"
_m02_pid="$(jq -r '.[0].id // empty' <<<"$_m02_pl" 2>/dev/null)"
_m02_tr=""
[[ -n "$_m02_pid" ]] && { _m02_tr="$(gitlab_api "$_m02_p/pipelines/$_m02_pid/test_report" 2>/dev/null)" || _m02_tr=""; }
check_output "CI (main) : des tests pytest de ms-attendre réussis, dont un sur les signaux" '^true$' \
  jq -r '[.test_suites[] | select(.name == "pytest") | .test_cases[]
    | select(.status == "success" and ((.classname + " " + .name) | test("attendre"; "i")))] as $t
    | ($t | length) >= 3 and any($t[]; .name | test("signal"; "i"))' <<<"${_m02_tr:-{\}}"
