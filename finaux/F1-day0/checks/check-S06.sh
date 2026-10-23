# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # programmes bash -c et filtres jq entre apostrophes
# check-S06.sh — F1-S06 « L'usine prépare un nœud Kubernetes ». Lecture seule : dépôts sur main
# (GitLab), NetBox (wb-checks), journal d'accès nginx de pxe01 (sudo -n zgrep), qm sur pve01,
# nœud k8s-w03 par le compte wb-checks.
#
# Variables : WB_F1_ESSAI_VMID (3101), WB_F1_ESSAI_NOM (f1-usine-essai), WB_F1_ESSAI_MAC
# (02:4d:53:60:31:01), WB_F1_PXE (pxe01), WB_F1_PROFIL (k8s-noeud).

# shellcheck source=_f1-preparer.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-preparer.sh"

title "F1-S06 — L'usine prépare un nœud Kubernetes"
require_cmd curl jq kubectl ssh

_f1_s06_vmid="${WB_F1_ESSAI_VMID:-3101}"
_f1_s06_nom="${WB_F1_ESSAI_NOM:-f1-usine-essai}"
_f1_s06_mac="${WB_F1_ESSAI_MAC:-02:4d:53:60:31:01}"
_f1_s06_mac_tirets="$(tr 'A-F:' 'a-f-' <<<"$_f1_s06_mac")"
_f1_s06_pxe="${WB_F1_PXE:-pxe01}"
_f1_s06_profil="${WB_F1_PROFIL:-k8s-noeud}"

# --- Le profil dans la chaîne de provisioning ----------------------------------------------------
_f1_s06_gabarits="$(_f1p_arbre plateforme/provisioning gabarits)"
check_cmd "plateforme/provisioning (main) : un gabarit d'installation propre aux nœuds Kubernetes (gabarits/*k8s*)" \
  bash -c 'grep -Eq "(^|/)[^/]*k8s[^/]*$" <<<"$1"' _ "$_f1_s06_gabarits"
_f1_s06_outils=""
while IFS= read -r _f1_s06_f; do
  [[ "$_f1_s06_f" =~ \.(py|sh|ya?ml|j2)$ ]] || continue
  _f1_s06_outils+="$(_f1p_fichier plateforme/provisioning "$_f1_s06_f" 2>/dev/null)"$'\n' || true
done < <(_f1p_arbre plateforme/provisioning outils; printf 'parametres.yml\n')
check_cmd "plateforme/provisioning (main) : les outils de rendu connaissent le profil « $_f1_s06_profil »" \
  _f1p_contient "$_f1_s06_outils" "$_f1_s06_profil"
check_cmd "plateforme/provisioning : dernier pipeline de main réussi" \
  bash -c 'jq -e ".[0].status == \"success\"" <<<"$1" >/dev/null' _ "$(_f1p_pipelines plateforme/provisioning '' 1)"
check_cmd "NetBox : plate-forme « $_f1_s06_profil » déclarée" \
  bash -c 'jq -e ".count == 1" <<<"$1" >/dev/null' _ "$(netbox_api "dcim/platforms/?slug=$_f1_s06_profil" 2>/dev/null)"

# --- L'essai : servi par pxe01, installé, puis retiré -------------------------------------------
if remote "$_f1_s06_pxe" true </dev/null >/dev/null 2>&1; then
  check_cmd "$_f1_s06_pxe : le script iPXE de la machine d'essai ($_f1_s06_mac) a été servi (HTTP 200)" \
    _f1p_hote "$_f1_s06_pxe" "zgrep -h 'GET /ipxe/mac-$_f1_s06_mac_tirets.ipxe' /var/log/nginx/pxe-acces.log* | grep -q '\" 200 '"
  check_cmd "$_f1_s06_pxe : le fichier de réponse de l'installation d'essai a été téléchargé (HTTP 200)" \
    _f1p_hote "$_f1_s06_pxe" "zgrep -h 'GET /preseed/$_f1_s06_nom\\.' /var/log/nginx/pxe-acces.log* | grep -q '\" 200 '"
else
  check_cmd "$_f1_s06_pxe joignable en SSH depuis adm01 (ses journaux d'accès prouvent l'essai : allume-la le temps du contrôle)" false
fi
# Absente = pve01 répond (liste des VMs lue) ET le VMID n'y figure pas : jamais « absente » par défaut.
_f1_s06_vm_absente() {
  local l
  l="$(remote "$WB_PVE_HOST" "qm list" </dev/null 2>/dev/null)" || return 1
  [[ -n "$l" ]] && ! awk -v v="$1" '$1 == v {f = 1} END {exit !f}' <<<"$l"
}
check_cmd "VM d'essai $_f1_s06_vmid détruite à la fin de l'essai" _f1_s06_vm_absente "$_f1_s06_vmid"
_f1_s06_nb_vm="$(netbox_api "virtualization/virtual-machines/?name=$_f1_s06_nom" 2>/dev/null | jq -r '.count // empty')" || _f1_s06_nb_vm=""
_f1_s06_nb_eq="$(netbox_api "dcim/devices/?name=$_f1_s06_nom" 2>/dev/null | jq -r '.count // empty')" || _f1_s06_nb_eq=""
check_cmd "NetBox : plus aucun objet « $_f1_s06_nom » (VM ou équipement)" \
  bash -c '[[ "$1" == 0 && "$2" == 0 ]]' _ "$_f1_s06_nb_vm" "$_f1_s06_nb_eq"
check_cmd "docs/day0/usine-k8s.md : profil, essai chronométré, préparation de k8s-w03" \
  _f1p_doc '^usine-k8s\.md$' "$_f1_s06_profil" "$_f1_s06_nom|3101" 'k8s-w03' '[0-9]+ ?(min|h)'

# --- k8s-w03 préparé dans le code, sans avoir été touché ----------------------------------------
_f1_s06_k8s=""
while IFS= read -r _f1_s06_f; do
  [[ "$_f1_s06_f" =~ \.(tf|tfvars)$ ]] || continue
  _f1_s06_k8s+="$(_f1p_fichier plateforme/infra "$_f1_s06_f" 2>/dev/null)"$'\n' || true
done < <(_f1p_arbre plateforme/infra envs/k8s)
check_cmd "plateforme/infra (main) : l'état envs/k8s sait démarrer un nœud sur le VLAN 60 (réseau de provisioning)" \
  _f1p_contient "$_f1_s06_k8s" 'vprov'

if _f1p_api_repond; then
  check_cmd "k8s-w03 est toujours un nœud Ready du cluster en service (rien n'est encore détruit)" _f1p_kq \
    'any(.status.conditions[]; .type == "Ready" and .status == "True")' node k8s-w03
else
  check_cmd "l'API de k8s-par1 répond au compte des checks" false
fi
