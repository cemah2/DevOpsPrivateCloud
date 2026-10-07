# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E08.sh — M04-E08 : Handlers et validation avant rechargement
# À lancer depuis adm01. Lecture seule : configuration et état de chrony sur les hôtes
# (cat, chronyc), contenu du playbook, playbook en --check (attend aussi la synchronisation :
# jusqu'à une minute par hôte si chrony vient de redémarrer).

# shellcheck source=_m04-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-decouverte.sh"

title "M04-E08 — Handlers et validation avant rechargement"
require_cmd git jq curl

_m04_pb="playbooks/chrony-client.yml"
check_cmd "$_m04_pb publié sur main" _m04_fichier_main "$_m04_pb"
check_cmd "la configuration est validée par chronyd avant d'être mise en place (validate:)" \
  _m04_contient "$_m04_pb" 'validate:.*chronyd[[:space:]].*-p'
check_cmd "un changement notifie un handler (notify: et handlers:)" \
  bash -c 'grep -Eq "^[[:space:]]+notify:" "$1" && grep -Eq "^[[:space:]]*handlers:" "$1"' _ "$_M04_SRC/$_m04_pb"
# _m04_e08_sans_gw01 — le playbook vise des hôtes, mais pas gw01 (--list-hosts ne connecte rien)
_m04_e08_sans_gw01() {
  local liste
  liste="$(_m04_ans ansible-playbook "$_m04_pb" --list-hosts 2>/dev/null)" || return 1
  grep -q 'hosts (' <<<"$liste" && ! grep -qw gw01 <<<"$liste"
}
check_cmd "le playbook ne vise pas le routeur gw01 (serveur de temps du lab)" _m04_e08_sans_gw01

# --- Clients chrony -------------------------------------------------------------------------------
for _m04_paire in adm01:10.10.10.1 dns01:10.10.20.1 git01:10.10.20.1 runner01:10.10.20.1; do
  _m04_h="${_m04_paire%%:*}"
  _m04_gw="${_m04_paire#*:}"
  check_ssh_output "$_m04_h : /etc/chrony/chrony.conf géré par Ansible" "$_m04_h" '^#.*[Aa]nsible' \
    'cat /etc/chrony/chrony.conf'
  check_ssh_output "$_m04_h : source déclarée dans chrony.conf : server $_m04_gw" "$_m04_h" \
    "^server[[:space:]]+${_m04_gw//./\\.}([[:space:]]|\$)" 'cat /etc/chrony/chrony.conf'
  check_ssh "$_m04_h : aucune source Internet (pool) dans chrony.conf" "$_m04_h" \
    '! grep -Eq "^[[:space:]]*(pool|server)[[:space:]]+[^[:space:]]*pool\.ntp\.org" /etc/chrony/chrony.conf'
  check_ssh "$_m04_h : l'ancienne source manuelle (sources.d/lab.sources) a disparu" "$_m04_h" \
    '! test -e /etc/chrony/sources.d/lab.sources'
  check_ssh_output "$_m04_h : une seule source de temps connue de chrony" "$_m04_h" '^1$' \
    'chronyc -n sources | grep -cE "^[=#^][-*+?x~][[:space:]]"'
  check_ssh_output "$_m04_h : $_m04_gw est la source sélectionnée (^*)" "$_m04_h" \
    "^\\^\\*[[:space:]]+${_m04_gw//./\\.}[[:space:]]" 'chronyc -n sources'
done

# --- Le serveur de temps n'a pas été touché ---------------------------------------------------------
check_ssh "gw01 : chrony actif" gw01 'systemctl is-active --quiet chrony'
check_ssh_output "gw01 : synchronisé sur une source externe (^*)" gw01 '^\^\*' 'chronyc -n sources'
check_ssh_output "gw01 : sert toujours le lab (accès autorisé depuis 10.10.20.10)" gw01 '208 Access allowed' \
  'sudo -n chronyc accheck 10.10.20.10'

# --- Idempotence ---------------------------------------------------------------------------------------
_m04_sortie="$(_m04_simuler "$_m04_pb")"
for _m04_h in adm01 dns01 git01 runner01; do
  check_cmd "--check sur $_m04_h : aucun changement, aucun échec, synchronisation confirmée" \
    _m04_recap "$_m04_sortie" "$_m04_h"
done
