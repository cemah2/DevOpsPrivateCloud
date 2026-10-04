# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E34.sh — M02-E34 : Un script de vérification en temps limité (recette du cahier des charges)
# À lancer depuis adm01. Lance TON bin/ms-verif-socle (lecture seule : DNS, SSH, chronyc, df,
# TLS) sur le socle réel, puis vérifie son interface. Lecture seule.

title "M02-E34 — Un script de vérification en temps limité"
require_cmd jq shellcheck bats timeout

_m02_r="${WB_SRC:-$HOME/src}/outils"
_m02_o="$_m02_r/bin/ms-verif-socle"
check_cmd "bin/ms-verif-socle existe et est exécutable" test -x "$_m02_o"
check_cmd "shellcheck -x : aucun message" bash -c 'cd "$1" && shellcheck -x bin/ms-verif-socle' _ "$_m02_r"

# --- Exécution par défaut sur le socle ---------------------------------------------------------
_m02_t0="$SECONDS"
_m02_sortie="$(timeout 120 "$_m02_o" 2>/dev/null)"
_m02_rc=$?
_m02_d=$((SECONDS - _m02_t0))
check_output "socle sain : code 0" '^0$' echo "$_m02_rc"
check_output "durée < 60 s pour les cinq hôtes" '^ok$' bash -c '(( $1 < 60 )) && echo ok' _ "$_m02_d"
for _m02_h in gw01 dns01 git01 runner01 pbs01; do
  check_output "$_m02_h : contrôles dns, ssh, temps, disque, tls dans cet ordre" '^dns ssh temps disque tls$' \
    bash -c 'awk -F"\t" -v h="$2" "\$1 == h { print \$2 }" <<<"$1" | paste -sd " "' _ "$_m02_sortie" "$_m02_h"
done
check_output "git01 : certificat HTTPS contrôlé (état OK)" '^OK$' \
  bash -c 'awk -F"\t" "\$1 == \"git01\" && \$2 == \"tls\" { print \$3 }" <<<"$1"' _ "$_m02_sortie"
check_output "gw01 : port 443 fermé, contrôle tls « NA »" '^NA$' \
  bash -c 'awk -F"\t" "\$1 == \"gw01\" && \$2 == \"tls\" { print \$3 }" <<<"$1"' _ "$_m02_sortie"
check_output "chaque ligne : 4 champs séparés par des tabulations, état OK, KO ou NA" '^ok$' \
  bash -c 'awk -F"\t" "NF != 4 || \$3 !~ /^(OK|KO|NA)\$/ { bad = 1 } END { if (!bad && NR > 0) print \"ok\" }" <<<"$1"' _ "$_m02_sortie"

# --- Hôte inconnu, usage, JSON --------------------------------------------------------------------
_m02_s2="$(timeout 60 "$_m02_o" hote-inexistant gw01 2>/dev/null)"
_m02_rc2=$?
check_output "hôte inconnu : code 1" '^1$' echo "$_m02_rc2"
check_output "hôte inconnu : dns et ssh en KO" '^KO KO$' \
  bash -c 'awk -F"\t" "\$1 == \"hote-inexistant\" && (\$2 == \"dns\" || \$2 == \"ssh\") { print \$3 }" <<<"$1" | paste -sd " "' _ "$_m02_s2"
check_output "hôte inconnu : les hôtes suivants sont quand même contrôlés" '^OK$' \
  bash -c 'awk -F"\t" "\$1 == \"gw01\" && \$2 == \"ssh\" { print \$3 }" <<<"$1"' _ "$_m02_s2"
check_output "nom d'hôte invalide refusé (code 2)" '^2$' bash -c '"$1" "gw01;id" >/dev/null 2>&1; echo $?' _ "$_m02_o"
check_output "option inconnue refusée (code 2)" '^2$' bash -c '"$1" --nimporte >/dev/null 2>&1; echo $?' _ "$_m02_o"
check_cmd "--json : un tableau JSON d'objets {hote, controle, etat, detail}, rien d'autre sur stdout" \
  bash -c 'timeout 60 "$1" --json gw01 2>/dev/null | jq -e "type == \"array\" and length == 5 and all(.[]; has(\"hote\") and has(\"controle\") and has(\"etat\") and has(\"detail\"))" >/dev/null' _ "$_m02_o"

# --- Tests -------------------------------------------------------------------------------------
check_output "au moins trois tests bats dans tests/bats/ms-verif-socle.bats" '^([3-9]|[1-9][0-9]+)$' \
  bats --count "$_m02_r/tests/bats/ms-verif-socle.bats"
check_cmd "les tests bats de ms-verif-socle passent" bash -c \
  'cd "$1" && env https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 timeout 120 bats tests/bats/ms-verif-socle.bats </dev/null >/dev/null 2>&1' _ "$_m02_r"
