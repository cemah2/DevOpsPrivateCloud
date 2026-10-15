# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes
#
# check-E08.sh — M18-E08 : Cluster API, concepts et cluster de gestion
# À lancer depuis adm01. Lecture seule : pvesh/pveum en lecture sur pve01, curl sans jeton depuis
# m18-dev01 (TLS vérifié), kubectl get avec kind-gestion.kubeconfig (ou k3s01 après le pivot),
# GitLab en GET. Le secret du jeton n'est jamais lu.

# shellcheck source=_m18-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-operationnel.sh"

title "M18-E08 — Cluster API : concepts et cluster de gestion"
require_cmd jq kubectl

# --- 1. Proxmox -------------------------------------------------------------------------------------
check_cmd "pve01 : utilisateur wb-capi@pve" _m18d_json "$(_m18o_pve /access/users)" 'any(.[]; .userid == "wb-capi@pve")'
check_cmd "pve01 : jeton capi avec séparation des privilèges et expiration" _m18d_json \
  "$(_m18o_pve /access/users/wb-capi@pve/token)" 'any(.[]; .tokenid == "capi" and (.privsep | tostring) == "1" and (.expire // 0) > 0)'
_m18d_e08_roles="$(_m18o_pve /access/roles)"
check_cmd "pve01 : rôle WBCapi (clone, allocation, agent ; ni console, ni sauvegarde, ni migration)" _m18d_json "$_m18d_e08_roles" \
  'any(.[]; .roleid == "WBCapi" and (.privs | test("VM.Clone") and test("VM.Allocate") and test("VM.GuestAgent.Audit")
     and (test("VM.Console|VM.Backup|VM.Migrate|VM.Monitor") | not)))'
check_cmd "pve01 : rôle WBCapiAudit (Sys.Audit seul)" _m18d_json "$_m18d_e08_roles" 'any(.[]; .roleid == "WBCapiAudit" and .privs == "Sys.Audit")'
check_cmd "pve01 : stockage capi-iso, contenu iso seulement" _m18d_json "$(_m18o_pve /storage/capi-iso)" '.content == "iso"'
_m18d_e08_acl="$(_m18o_pve /access/acl)"
check_cmd "pve01 : ACL du jeton : WBCapi sur /pool/lab, PVEDatastoreAdmin sur capi-iso, PVESDNUser sur vk8s" _m18d_json "$_m18d_e08_acl" \
  '[.[] | select(.ugid == "wb-capi@pve!capi") | "\(.path) \(.roleid)"] as $a
   | ($a | index("/pool/lab WBCapi")) and ($a | index("/storage/capi-iso PVEDatastoreAdmin")) and ($a | index("/sdn/zones/lab/vk8s PVESDNUser"))'
check_cmd "pve01 : aucun droit du compte sur hdd-bulk" _m18d_json "$_m18d_e08_acl" \
  '[.[] | select((.ugid | startswith("wb-capi@pve")) and (.path == "/storage/hdd-bulk" or .path == "/storage"))] | length == 0'
check_cmd "pve01 : IPSet capi (deux adresses au moins)" _m18d_json "$(_m18o_pve /cluster/firewall/ipset/capi)" 'length >= 2'
check_cmd "pve01 : règle d'entrée 8006 depuis +capi" _m18d_json "$(_m18o_pve /cluster/firewall/rules)" \
  'any(.[]; .source == "+capi" and (.dport | tostring) == "8006" and .action == "ACCEPT" and ((.enable // 1) | tostring) == "1")'

# --- 2. Identifiants et accès -------------------------------------------------------------------------
_m18d_e08_env="$HOME/.config/workbook/pve-capi.env"
check_cmd "$_m18d_e08_env en 600" _m18d_600 "$_m18d_e08_env"
_m18d_e08_url="$(sed -n 's/^PROXMOX_URL=//p' "$_m18d_e08_env" 2>/dev/null | tr -d '"' || true)"
check_output "m18-dev01 → API de pve01 : réponse 401 sans jeton, TLS vérifié" '^401$' \
  remote "$_M18D_DEV" "curl -s -o /dev/null -w '%{http_code}' --max-time ${WB_TIMEOUT:-5} '${_m18d_e08_url%/}/api2/json/version'"
check_output "Bordure : les règles de M18-E08 sont dans la matrice" 'M18-E08' \
  _m18d_contenu_main plateforme/ansible inventories/lab/group_vars/role_routeur/pare_feu.yml

# --- 3. Cluster de gestion -----------------------------------------------------------------------------
_m18d_e08_g="$(_m18o_gestion)"
if [[ -z "$_m18d_e08_g" ]]; then
  # Avant E10 : pas encore de capi-essai, on lit le cluster d'amorçage.
  _m18d_e08_g=kind-gestion
fi
if [[ "$_m18d_e08_g" == kind-gestion ]]; then
  check_cmd "kind-gestion.kubeconfig en 600" _m18d_600 "$_M18D_DIR/kind-gestion.kubeconfig"
  check_output "kind-gestion.kubeconfig : serveur https://m18-dev01.par1.medisphere.internal:6443" \
    '^https://m18-dev01\.par1\.medisphere\.internal:6443$' _m18d_serveur kind-gestion
  check_output "Le cluster kind gestion répond depuis adm01 (TLS vérifié par le nom)" '^ok$' _m18d_k kind-gestion get --raw /readyz
else
  skip "Cluster kind gestion" "pivot fait (M18-E12) : fournisseurs lus sur k3s01"
fi
check_cmd "Fournisseurs : cluster-api et kubeadm ×2 en $_M18O_CAPI, proxmox $_M18O_CAPMOX, in-cluster $_M18O_IPAM" \
  _m18o_fournisseurs_ok "$_m18d_e08_g"
check_cmd "Contrôleurs des cinq fournisseurs disponibles" _m18o_controleurs_ok "$_m18d_e08_g"
check_cmd "CAPMOX sans identifiants globaux (capmox-manager-credentials présent mais vide)" bash -c \
  '[[ "$1" == *url* && -z "$2" && -z "$3" ]]' _ \
  "$(_m18d_kj "$_m18d_e08_g" -n capmox-system get secret capmox-manager-credentials -o jsonpath='{.data}')" \
  "$(_m18o_secret_cle "$_m18d_e08_g" capmox-system capmox-manager-credentials url)" \
  "$(_m18o_secret_cle "$_m18d_e08_g" capmox-system capmox-manager-credentials token)"

# --- 4. Le code et la conclusion --------------------------------------------------------------------------
check_output "plateforme/distributions (main) : capi/versions.env (CAPI v1.12.11)" '^CAPI_VERSION=v1\.12\.11$' \
  _m18d_contenu_main plateforme/distributions capi/versions.env
_m18d_fichiers_main plateforme/distributions capi/init.sh capi/pve-compte-capi.sh capi/preflight-pve.sh kind/gestion.yaml kind/gestion-capd.yaml
check_output "capmox-pve9.md (main) : décision écrite" '^#+ *D[ée]cision' \
  bash -c 'grep -Ei "^#+ *D[ée]cision" <<<"$1"' _ "$(_m18d_contenu_main plateforme/medisphere docs/kubernetes/distributions/capmox-pve9.md)"
