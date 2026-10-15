# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E25.sh — M18-E25 « Mini-projet : distributions MédiSphère v1 » (contrôle global, quelques minutes).
# Lecture seule : documentation et étiquette sur GitLab, VMs et comptes sur pve01 (qm list, pveum … list),
# NetBox (lecture), matrice des flux sur main, fichiers locaux, marqueurs de pannes, puis le contrôle
# global de k8s-par1 (lab/bin/check 14 46, lancé dans un processus séparé).
# Réglages de lab/lab.env (traduction de l'ADR-0180) : WB_M18_TEMPLATES_CONSERVES, WB_M18_WBCAPI_CONSERVE.

# shellcheck source=_m18-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-production.sh"

title "M18-E25 — Distributions MédiSphère v1"
require_cmd jq ssh curl

_e25_d=docs/kubernetes/distributions
_e25_tpl="${WB_M18_TEMPLATES_CONSERVES:-0}"
_e25_capi="${WB_M18_WBCAPI_CONSERVE:-0}"

title "Décision et mesures"
check_cmd "ADR-0180 accepté (trois besoins, k8s-par1, cluster de gestion, templates, wb-capi)" \
  _m18p_doc_prefixe "$_e25_d/adr" ADR-0180 'Statut.*(Accept|accept)' 'Lyon|agence' 'recette' 'k8s-par1' 'wb-capi' 'template|9060' 'r(é|e)examen'
check_cmd "comparatif.md : six options, critères mesurés, démonstration chronométrée" \
  _m18p_fichier_contient plateforme/medisphere "$_e25_d/comparatif.md" \
  'kubeadm' 'k3s' 'rke2' 'talos' 'cluster api|capmox' 'kind|k3d' 'RTO|restauration' 'demo:construire'
check_cmd "demontage.md : ordre écrit, Cluster API avant les VMs, flux et comptes" \
  _m18p_fichier_contient plateforme/medisphere "$_e25_d/demontage.md" 'cluster api|capi' 'tofu' 'wb-capi' 'pare_feu|flux' 'check 14 46'
for _e25_rb in RB-180 RB-181 RB-182 RB-183 RB-184 RB-185; do
  check_cmd "$_e25_rb publié" _m18p_doc_prefixe "$_e25_d/runbooks" "$_e25_rb" '.'
done
check_cmd "durcissement.md et tests/restaurations.md publiés" bash -c \
  '[[ -n "$1" && -n "$2" ]]' _ "$(_m18p_fichier_main plateforme/medisphere "$_e25_d/durcissement.md" | head -c 1)" \
  "$(_m18p_fichier_main plateforme/medisphere "$_e25_d/tests/restaurations.md" | head -c 1)"
check_cmd "plateforme/distributions : tâches demo:construire et demo:detruire sur main" \
  _m18p_fichier_contient plateforme/distributions Taskfile.yml 'demo:construire' 'demo:detruire'
_e25_tag="$(gitlab_api "projects/$(_m18p_enc plateforme/medisphere)/repository/tags/distributions-v1" 2>/dev/null | jq -r '.name // empty')" || _e25_tag=""
check_output "étiquette distributions-v1 sur plateforme/medisphere" '^distributions-v1$' echo "$_e25_tag"

title "Proxmox : plus rien du module"
_e25_qm="$(_m18p_pve 'qm list')" || _e25_qm=""
check_cmd "pve01 répond (qm list)" grep -q 'VMID' <<<"$_e25_qm"
if grep -q 'VMID' <<<"$_e25_qm"; then
  _e25_vms="$(awk 'NR > 1 && (($1 >= 2181 && $1 <= 2188) || ($1 >= 5180 && $1 <= 5193)) {printf "%s ", $1}' <<<"$_e25_qm")"
  check_output "aucune VM 2181-2188 ni 5180-5193 (restantes : ${_e25_vms:-aucune})" '^$' echo "${_e25_vms% }"
  _e25_t="$(awk 'NR > 1 && $1 >= 9060 && $1 <= 9069 {printf "%s ", $1}' <<<"$_e25_qm")"
  if [[ "$_e25_tpl" == 1 ]]; then
    check_output "templates Cluster API conservés par l'ADR (présents : ${_e25_t:-aucun})" '[0-9]' echo "$_e25_t"
  else
    check_output "templates Cluster API 9060-9069 supprimés (restants : ${_e25_t:-aucun})" '^$' echo "${_e25_t% }"
  fi
fi
_e25_u="$(_m18p_pve 'pveum user list --output-format json')" || _e25_u=""
_e25_r="$(_m18p_pve 'pveum role list --output-format json')" || _e25_r=""
if [[ "$_e25_capi" == 1 ]]; then
  check_cmd "compte wb-capi@pve conservé par l'ADR, avec son jeton" _m18p_jq "${_e25_u:-null}" 'any(.[]; .userid == "wb-capi@pve")'
else
  check_cmd "compte wb-capi@pve supprimé" _m18p_jq "${_e25_u:-null}" '(length > 0) and ([.[] | select(.userid == "wb-capi@pve")] | length == 0)'
  check_cmd "rôle WBCapi supprimé" _m18p_jq "${_e25_r:-null}" '(length > 0) and ([.[] | select(.roleid == "WBCapi")] | length == 0)'
  check_cmd "fichier pve-capi.env supprimé de ~/.config/workbook/ (adm01)" test ! -e "$HOME/.config/workbook/pve-capi.env"
fi

title "Inventaire et bordure"
_e25_nb() {
  local n c
  for n in k3s01 rke2-01 rke2-02 rke2-03 talos-01 talos-02 talos-03 m18-dev01 k3s-ha01 k3s-ha02 k3s-ha03; do
    c="$(netbox_api "virtualization/virtual-machines/?name=$n" 2>/dev/null | jq -r '.count // empty')" || return 1
    [[ "$c" == 0 ]] || return 1
  done
}
check_cmd "NetBox : aucune VM du module" _e25_nb
check_cmd "matrice de la bordure (main) : plus aucune règle provisoire du module (M18-E08, M18-E14, M18-E16)" \
  bash -c '[[ -n "$1" ]] && ! grep -Eq "ref: *M18-E(08|14|16)" <<<"$1"' _ \
  "$(_m18p_fichier_main plateforme/ansible inventories/lab/group_vars/role_routeur/pare_feu.yml)"
_e25_ipsets="$(_m18p_pve 'pvesh get /cluster/firewall/ipset --output-format json')" || _e25_ipsets=""
check_cmd "pare-feu de pve01 : plus d'IPSet capi (M18-E08)" _m18p_jq "${_e25_ipsets:-null}" \
  '[.[]? | select(.name == "capi")] | length == 0'
_e25_regles="$(_m18p_pve 'pvesh get /cluster/firewall/rules --output-format json')" || _e25_regles=""
check_cmd "pare-feu de pve01 : plus de règle depuis +capi" _m18p_jq "${_e25_regles:-null}" \
  '[.[]? | select((.source // "") == "+capi")] | length == 0'

title "Poste d'administration"
_e25_restes="$(find "$_M18P_DIR" -maxdepth 1 \( -name '*.kubeconfig' -o -name 'talosconfig*' \) -printf '%f ' 2>/dev/null)" || _e25_restes=""
check_output "aucun kubeconfig ni talosconfig de cluster détruit dans ~/.config/workbook/m18/ (restants : ${_e25_restes:-aucun})" \
  '^$' echo "${_e25_restes% }"
_e25_pannes="$(find "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives/" -maxdepth 1 -name 'M18-*' -printf '%f ' 2>/dev/null)" || _e25_pannes=""
check_output "aucune panne M18 active (actives : ${_e25_pannes:-aucune})" '^$' echo "${_e25_pannes% }"

title "k8s-par1 de retour (lab/bin/check 14 46)"
_e25_racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
check_cmd "lab/bin/check 14 46 entièrement vert" timeout 900 "$_e25_racine/lab/bin/check" 14 46
