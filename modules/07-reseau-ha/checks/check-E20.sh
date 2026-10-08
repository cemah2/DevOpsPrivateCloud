# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E20.sh — M07-E20 : Méthode de diagnostic réseau
# À lancer depuis adm01. Lecture seule : l'outil est exécuté vers des destinations du lab.

# shellcheck source=_m07-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-operationnel.sh"

title "M07-E20 — Méthode de diagnostic réseau"

_m07o_outil="$(_m07o_contenu_main "$_M07O_PROJET_OUTILS" bin/ms-diag-chemin)"
check_output "plateforme/outils : bin/ms-diag-chemin sur main" '^#!' echo "$_m07o_outil"
_m07o_sc() {
  local f
  command -v shellcheck >/dev/null || return 1
  f="$(mktemp)"
  printf '%s\n' "$_m07o_outil" >"$f"
  # SC1091 : la bibliothèque ms-commun.sh n'est pas à côté de la copie temporaire.
  shellcheck -e SC1091 "$f" >/dev/null 2>&1
  local rc=$?
  rm -f "$f"
  return "$rc"
}
check_cmd "ms-diag-chemin : ShellCheck sans avertissement" _m07o_sc

# L'outil installé sur adm01 (depuis la CI du projet, ou ta copie de travail).
_m07o_cmd="$(command -v ms-diag-chemin || echo "${WB_SRC:-$HOME/src}/outils/bin/ms-diag-chemin")"
if [[ -x "$_m07o_cmd" ]]; then
  check_cmd "ms-diag-chemin → dns01:53 : code 0 (joint)" "$_m07o_cmd" dns01.par1.medisphere.internal 53
  _m07o_ko() { "$_m07o_cmd" 10.10.99.254 22 >/dev/null 2>&1; [[ $? -eq 1 ]]; }
  check_cmd "ms-diag-chemin → 10.10.99.254:22 (adresse inutilisée) : code 1" _m07o_ko
  _m07o_usage() { "$_m07o_cmd" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
  check_cmd "ms-diag-chemin sans argument : code 2 (usage)" _m07o_usage
  check_output "ms-diag-chemin --depuis srv01 : relevé fait depuis srv01" '^Chemin srv01 ' \
    "$_m07o_cmd" --depuis srv01 10.10.255.22
else
  skip "exécution de ms-diag-chemin" "introuvable ou non exécutable sur adm01 : $_m07o_cmd"
fi

_m07o_rb="$(_m07o_contenu_main "$_M07O_PROJET_DOC" docs/socle/runbooks/RB-072-diagnostic-reseau.md)"
check_output "RB-072 sur main de plateforme/medisphere" 'RB-072' echo "$_m07o_rb"
check_output "RB-072 : tableau symptôme → piste" '\|.*[Ss]ympt' echo "$_m07o_rb"
for _m07o_m in 'ip neigh|bridge fdb' 'ip route get' 'nft monitor trace' 'ping -M do' 'tcpdump'; do
  check_output "RB-072 mentionne « $_m07o_m »" "$_m07o_m" echo "$_m07o_rb"
done
check_output "RB-072 : la trace nftables se pose dans une table temporaire supprimée à la fin" 'delete table' echo "$_m07o_rb"
check_ssh "gw01 : aucune table de trace oubliée (seules inet filter et ip nat)" gw01 \
  '! sudo -n nft list tables | grep -Ev "^table (inet filter|ip nat)$" | grep -q .'
