# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E05.sh — M04-E05 : Premier playbook idempotent
# À lancer depuis adm01. Lecture seule : le playbook est lancé en mode --check (simulation,
# rien n'est modifié) ; l'état des hôtes est lu par dpkg-query et grep. Durée : 1 à 2 min.
# Après M04-E10 (rôle base), le playbook n'existe plus : ses contrôles sont ignorés, seul
# l'état des hôtes (que le rôle doit maintenir) reste vérifié.

# shellcheck source=_m04-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-decouverte.sh"

title "M04-E05 — Premier playbook idempotent"
require_cmd git jq curl

_m04_pb="playbooks/trousse-diagnostic.yml"
if _m04_role_base_en_place; then
  skip "contrôles du playbook $_m04_pb" "repris et remplacé par le rôle base en M04-E10"
else
  check_cmd "$_m04_pb présent dans la copie de travail" test -s "$_M04_SRC/$_m04_pb"
  check_cmd "$_m04_pb publié sur main" _m04_fichier_main "$_m04_pb"
  check_cmd "paquets gérés par le module ansible.builtin.apt (nom complet)" _m04_contient "$_m04_pb" 'ansible\.builtin\.apt:'
  check_cmd "aucune commande apt/apt-get/dpkg lancée par shell ou command" \
    bash -c '! grep -Eq "(shell|command|raw)[^#]*(apt-get|apt |dpkg)" "$1"' _ "$_M04_SRC/$_m04_pb"
  check_cmd "aucun sudo dans les tâches (élévation par become)" \
    bash -c '! grep -Eq "^[^#]*sudo " "$1"' _ "$_M04_SRC/$_m04_pb"

  # --- Simulation : un passage de plus ne changerait rien ------------------------------------
  _m04_sortie="$(_m04_simuler "$_m04_pb")"
  for _m04_h in $_M04_SOCLE; do
    check_cmd "--check sur $_m04_h : aucun changement, aucun échec (idempotent)" _m04_recap "$_m04_sortie" "$_m04_h"
  done
fi

# --- État réel des hôtes -----------------------------------------------------------------------
for _m04_h in $_M04_SOCLE; do
  _m04_absents=""
  for _m04_p in bind9-dnsutils tcpdump mtr-tiny curl jq lsof strace htop; do
    _m04_paquet "$_m04_h" "$_m04_p" || _m04_absents+=" $_m04_p"
  done
  check_cmd "$_m04_h : trousse complète${_m04_absents:+ (manque :$_m04_absents)}" test -z "$_m04_absents"
  check_ssh "$_m04_h : aucun client telnet ou rsh installé" "$_m04_h" \
    '! dpkg-query -W -f="\${Status}\n" telnet inetutils-telnet rsh-client 2>/dev/null | grep -q "install ok installed"'
  check_ssh "$_m04_h : HISTTIMEFORMAT défini une seule fois dans /etc/bash.bashrc" "$_m04_h" \
    '[ "$(grep -c "^export HISTTIMEFORMAT=" /etc/bash.bashrc)" -eq 1 ]'
done
