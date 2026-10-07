# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E06.sh — M04-E06 : Variables et précédence
# À lancer depuis adm01. Lecture seule : valeurs EFFECTIVES des variables (module debug,
# évalué sur adm01 sans connexion aux hôtes), playbook en --check, dpkg-query sur gw01.

# shellcheck source=_m04-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-decouverte.sh"

title "M04-E06 — Variables et précédence"
require_cmd git jq curl

# --- Variables du site -----------------------------------------------------------------------
check_output "ms_domaine vaut par1.medisphere.internal" '^"par1\.medisphere\.internal"$' _m04_debug dns01 ms_domaine
check_output "ms_resolveur vaut 10.10.20.10" '^"10\.10\.20\.10"$' _m04_debug runner01 ms_resolveur
for _m04_paire in adm01:10.10.10.1 dns01:10.10.20.1 git01:10.10.20.1 runner01:10.10.20.1; do
  _m04_h="${_m04_paire%%:*}"
  _m04_gw="${_m04_paire#*:}"
  check_output "$_m04_h : ms_passerelle = $_m04_gw (passerelle de son VLAN)" "^\"${_m04_gw//./\\.}\"\$" \
    _m04_debug "$_m04_h" ms_passerelle
  check_output "$_m04_h : ms_serveurs_ntp = [\"$_m04_gw\"]" "^\[\"${_m04_gw//./\\.}\"\]\$" \
    _m04_debug "$_m04_h" ms_serveurs_ntp
done
check_output "gw01 : au moins une source de temps (ms_serveurs_ntp non vide)" '^true$' \
  _m04_debug gw01 "ms_serveurs_ntp | length > 0"
check_output "gw01 : ms_serveurs_ntp ne contient aucune adresse du lab (ni gw01 lui-même)" '^\[\]$' \
  _m04_debug gw01 "ms_serveurs_ntp | select('match', '^10[.]') | list"

# --- Trousse pilotée par l'inventaire -----------------------------------------------------------
check_output "trousse_paquets : liste commune définie pour tout le socle (8 outils au moins)" \
  '^([89]|[1-9][0-9])$' _m04_debug git01 "trousse_paquets | length"
check_output "trousse_paquets_role : vide par défaut (dns01)" '^\[\]$' _m04_debug dns01 trousse_paquets_role
check_output "trousse_paquets_role de gw01 : conntrack et ethtool" '^2$' \
  _m04_debug gw01 "trousse_paquets_role | select('in', ['conntrack', 'ethtool']) | list | length"
check_cmd "le playbook ne fixe plus les listes dans « vars: » (elles écraseraient l'inventaire)" \
  bash -c '! grep -Eq "^[[:space:]]+trousse_paquets[a-z_]*:" "$1"' _ "$_M04_SRC/playbooks/trousse-diagnostic.yml"
_m04_sortie="$(_m04_simuler playbooks/trousse-diagnostic.yml)"
for _m04_h in $_M04_SOCLE; do
  check_cmd "--check de la trousse sur $_m04_h : aucun changement, aucun échec" _m04_recap "$_m04_sortie" "$_m04_h"
done
for _m04_p in conntrack ethtool; do
  check_cmd "gw01 : $_m04_p installé (outil propre au routeur)" _m04_paquet gw01 "$_m04_p"
done
# _m04_e06_publies — group_vars/all et host_vars/gw01 sont sur main (fichier ou dossier)
_m04_e06_publies() {
  { _m04_fichier_main inventories/lab/group_vars/all/main.yml || _m04_fichier_main inventories/lab/group_vars/all.yml; } \
    && { _m04_fichier_main inventories/lab/host_vars/gw01/main.yml || _m04_fichier_main inventories/lab/host_vars/gw01.yml; }
}
check_cmd "group_vars/all et host_vars/gw01 publiés sur main" _m04_e06_publies
