# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes : pas d'expansion voulue
#
# check-E18.sh — M09-E18 : Piloter le cluster par le code
# À lancer depuis adm01. Lecture seule : DNS, HTTPS sur la VIP (TLS vérifié par le magasin système, sans
# authentification), état de keepalived et des adresses des nœuds, ressources du cluster, API GitLab.

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E18 — Piloter le cluster par le code"
require_cmd jq curl dig

_m09o_vip=10.10.10.200
_m09o_nom=hv.par1.medisphere.internal
_m09o_url="https://$_m09o_nom:8006/api2/json/version"

check_dns "$_m09o_nom résout en $_m09o_vip (DNS du lab)" "$_m09o_nom" A "^${_m09o_vip//./\\.}$" "$_M09O_DNS"
check_dns "PTR de $_m09o_vip : $_m09o_nom" "200.10.10.10.in-addr.arpa" PTR "^${_m09o_nom//./\\.}\.$" "$_M09O_DNS"
# 401 = l'API répond ; un échec TLS (certificat inconnu ou sans le nom) donnerait « aucune réponse ».
check_http "adm01 : l'API répond sur la VIP avec un certificat valide pour $_m09o_nom (TLS vérifié)" "$_m09o_url" 401
check_ssh_output "runner01 : l'API répond sur la VIP, TLS vérifié (flux INFRA → MGMT 8006 et autorité de confiance)" runner01 '^401$' \
  "curl -s -o /dev/null -w '%{http_code}' --max-time 5 $_m09o_url"

_m09o_porteurs=0
for _m09o_n in $_M09O_NOEUDS; do
  check_ssh "$_m09o_n : keepalived actif et activé" "$_m09o_n" 'systemctl is-active --quiet keepalived && systemctl is-enabled --quiet keepalived'
  check_ssh "$_m09o_n : instance VRRP de VRID 110 dans la configuration" "$_m09o_n" \
    'grep -Eq "virtual_router_id[[:space:]]+110\b" /etc/keepalived/keepalived.conf'
  if _m09o_hv "$_m09o_n" "ip -4 -o addr show" | grep -q " ${_m09o_vip}/"; then
    _m09o_porteurs=$((_m09o_porteurs + 1))
    check_ssh "$_m09o_n porte la VIP : il est dans une partition qui a le quorum" "$_m09o_n" \
      'corosync-quorumtool -s | grep -Eq "^Quorate:[[:space:]]+Yes"'
  fi
done
check_output "la VIP $_m09o_vip est portée par exactement un nœud ($_m09o_porteurs)" '^1$' echo "$_m09o_porteurs"

# --- Code -----------------------------------------------------------------------------------------------
_m09o_v="$(_m09o_contenu_main plateforme/infra envs/hv-invites/versions.tf)"
check_output "plateforme/infra (main) : envs/hv-invites avec le provider bpg/proxmox épinglé (~> 0.x)" \
  'version[[:space:]]*=[[:space:]]*"~>[[:space:]]*0\.[0-9]+' echo "$_m09o_v"
check_cmd "plateforme/infra (main) : .terraform.lock.hcl de envs/hv-invites versionné" \
  _m09o_fichier_main plateforme/infra envs/hv-invites/.terraform.lock.hcl
check_output "plateforme/infra (main) : état distant envs/hv-invites, verrou natif" 'key[[:space:]]*=[[:space:]]*"envs/hv-invites/' \
  _m09o_contenu_main plateforme/infra envs/hv-invites/backend.tf
check_cmd "plateforme/infra (main) : aucun « insecure = true » dans envs/hv-invites" bash -c \
  '[[ -n "$1" ]] && ! grep -Eq "insecure[[:space:]]*=[[:space:]]*true" <<<"$1"' _ "$(_m09o_contenu_main plateforme/infra envs/hv-invites/providers.tf)"
check_cmd "plateforme/ansible (main) : rôle pve_cluster" _m09o_fichier_main plateforme/ansible roles/pve_cluster/tasks/main.yml

# --- VMs de recette ----------------------------------------------------------------------------------------
_m09o_res="$(_m09o_ressources)"
for _m09o_id in 130 131; do
  check_cmd "invité $_m09o_id : dans le pool recette, étiquette tofu, démarré" _m09o_json "$_m09o_res" \
    'map(select(.vmid == $id))[0] | . != null and .pool == "recette" and ((.tags // "") | split(";") | index("tofu") != null)
     and .status == "running"' --argjson id "$_m09o_id"
  check_cmd "invité $_m09o_id : disque(s) sur ceph-vm" _m09o_disques_sur "$(_m09o_conf "$_m09o_id")" ceph-vm
done
check_output "rec01 (130) et rec02 (131) portent leurs noms" '^rec01 rec02$' \
  bash -c 'jq -r "[.[] | select(.vmid == 130 or .vmid == 131)] | sort_by(.vmid) | map(.name) | join(\" \")" <<<"$1"' _ "$_m09o_res"
check_cmd "aucune VM étiquetée tofu hors du pool recette" _m09o_json "$_m09o_res" \
  'map(select(((.tags // "") | split(";") | index("tofu") != null) and (.pool // "") != "recette")) | length == 0'
