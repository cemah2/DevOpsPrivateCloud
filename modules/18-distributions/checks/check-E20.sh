# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E20.sh — M18-E20 « Panne : le nœud Talos refuse sa configuration »
# Lecture seule : talosctl (version, health, patch --dry-run qui n'applique rien), nœuds Kubernetes, branche
# locale lucas/* de ~/src/distributions (git show), documentation sur main.

# shellcheck source=_m18-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-production.sh"

title "M18-E20 — Talos accepte sa configuration"
require_cmd talosctl kubectl jq yq openssl git

title "Client (talosconfig)"
check_cmd "talosconfig en 600" _m18p_local600 "$_M18P_TALOSCONFIG"
_e20_roles="$(_m18p_talos_roles "$_M18P_TALOSCONFIG" | sort -u | tr '\n' ' ')" || _e20_roles=""
check_output "talosconfig : rôle os:admin (lu : ${_e20_roles:-aucun})" 'os:admin' echo "$_e20_roles"
for _e20_ip in "$_M18P_TALOS_CP" "${_M18P_TALOS_TRAV[@]}"; do
  check_cmd "$_e20_ip répond à talosctl en TLS mutuel (pas en maintenance)" _m18p_talos -n "$_e20_ip" version
done

title "Cluster"
check_cmd "talosctl health vert (vu de talos-01)" \
  timeout 180 talosctl --talosconfig "$_M18P_TALOSCONFIG" -n "$_M18P_TALOS_CP" health --wait-timeout 2m
check_cmd "trois nœuds Ready dans Kubernetes" _m18p_noeuds_prets "$_M18P_KC_TALOS" 3

title "Correctif de Lucas (si une branche lucas/* existe)"
_e20_depot="${WB_SRC:-$HOME/src}/distributions"
_e20_br="$(git -C "$_e20_depot" for-each-ref --format='%(refname:short)' 'refs/heads/lucas/*' 2>/dev/null | head -1)" || _e20_br=""
if [[ -n "$_e20_br" ]]; then
  _e20_patch_ok() {
    local n="$1" ip="$2" t rc=0
    t="$(mktemp)"
    git -C "$_e20_depot" show "$_e20_br:talos/noeuds/$n.yaml" >"$t" 2>/dev/null || { rm -f "$t"; return 1; }
    _m18p_talos -n "$ip" patch mc --dry-run -p "@$t" >/dev/null || rc=1
    rm -f "$t"
    return "$rc"
  }
  _e20_zone() {
    [[ "$(_m18p_k "$_M18P_KC_TALOS" get node "$1" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')" == "$2" ]]
  }
  check_cmd "$_e20_br : le correctif de talos-02 passe la validation (patch --dry-run)" _e20_patch_ok talos-02 10.10.99.86
  check_cmd "$_e20_br : le correctif de talos-03 passe la validation (patch --dry-run)" _e20_patch_ok talos-03 10.10.99.87
  check_cmd "talos-02 porte topology.kubernetes.io/zone=par1-baie-b" _e20_zone talos-02 par1-baie-b
  check_cmd "talos-03 porte topology.kubernetes.io/zone=par1-baie-c" _e20_zone talos-03 par1-baie-c
else
  skip "correctif de Lucas" "aucune branche lucas/* dans $_e20_depot"
fi

title "Documentation"
check_cmd "RB-184 publié (client, configuration, nœud ; maintenance ; ce qu'on ne fait jamais)" \
  _m18p_doc_prefixe docs/kubernetes/distributions/runbooks RB-184 'talosconfig' 'maintenance' 'insecure' 'appliquer\.sh|apply-config'
check_cmd "journal de diagnostic INC-4520 publié dans docs/socle/journal/" \
  _m18p_un_fichier_contient plateforme/medisphere docs/socle/journal 'INC-4520'
