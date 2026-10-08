# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur pve01 ou par bash -c
# check-E22.sh — M11-E22 « Panne : MAAS ne pilote plus les machines » (MAAS démarré) : état
# d'alimentation interrogeable pour les quatre machines bm*, vérification TLS active, jeton
# wb-maas@pve!maas valide, rôle WBMaas et ACL au plus juste, noms des VMs d'origine ; panne close.
# Lecture seule (query_power_state interroge l'alimentation sans la modifier).

# shellcheck source=_m11-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-expert.sh"

title "M11-E22 — MAAS pilote les machines bm*"
require_cmd curl jq ssh

if [[ ! -r "$_m11x_maas_cle" ]]; then
  check_cmd "clé d'API de MAAS lisible sur adm01 ($_m11x_maas_cle)" false
fi
mapfile -t _m11_e22_bm < <(_m11x_maas_bm)
check_cmd "MAAS répond et connaît les quatre machines bm01-bm04" test "${#_m11_e22_bm[@]}" -eq 4
for _m11_e22_l in "${_m11_e22_bm[@]}"; do
  read -r _m11_e22_id _m11_e22_nom <<<"$_m11_e22_l"
  _m11_e22_etat="$(_m11x_maas GET "machines/$_m11_e22_id/?op=query_power_state" | jq -r '.state // empty' 2>/dev/null)" || true
  check_cmd "$_m11_e22_nom : état d'alimentation interrogé avec succès (${_m11_e22_etat:-échec})" \
    bash -c '[ "$1" = on ] || [ "$1" = off ]' _ "$_m11_e22_etat"
  _m11_e22_p="$(_m11x_maas GET "machines/$_m11_e22_id/?op=power_parameters")" || true
  check_cmd "$_m11_e22_nom : pilote Proxmox, vérification TLS active" \
    bash -c 'jq -e "(to_entries | map(select(.key | test(\"verify\"))) | .[0].value) as \$v | (\$v == true or (\$v | tostring | test(\"^(true|1|y|yes)$\"; \"i\")))" <<<"$1" >/dev/null' _ "$_m11_e22_p"
done

# pve01 : jeton, rôle, ACL, noms
check_ssh "pve01 : jeton wb-maas@pve!maas présent et non expiré" "$WB_PVE_HOST" \
  'pveum user token list wb-maas@pve --output-format json | python3 -c "import json,sys,time; t=[x for x in json.load(sys.stdin) if x.get(\"tokenid\")==\"maas\"]; e=int(t[0].get(\"expire\",0) or 0) if t else -1; sys.exit(0 if t and (e==0 or e>time.time()) else 1)"'
check_ssh "pve01 : rôle WBMaas avec VM.Audit et VM.PowerMgmt, sans privilège d'administration" "$WB_PVE_HOST" \
  'p="$(pveum role list --output-format json | python3 -c "import json,sys; r=[x for x in json.load(sys.stdin) if x.get(\"roleid\")==\"WBMaas\"]; print(r[0][\"privs\"] if r else \"\")")"; case ",$p," in *,VM.Audit,*) ;; *) exit 1 ;; esac; case ",$p," in *,VM.PowerMgmt,*) ;; *) exit 1 ;; esac; ! printf "%s" "$p" | grep -Eq "Sys\.Modify|Permissions\.Modify|User\.Modify|VM\.Allocate|Datastore\.Allocate"'
check_ssh "pve01 : droits de wb-maas limités aux VMs 2112 à 2115" "$WB_PVE_HOST" \
  'pveum acl list --output-format json | python3 -c "import json,sys; a=[x for x in json.load(sys.stdin) if str(x.get(\"ugid\",\"\")).startswith(\"wb-maas@pve\")]; ok={\"/vms/2112\",\"/vms/2113\",\"/vms/2114\",\"/vms/2115\"}; sys.exit(0 if a and all(x[\"path\"] in ok for x in a) else 1)"'
check_ssh "pve01 : VMs 2112-2115 nommées bm01 à bm04" "$WB_PVE_HOST" \
  'for i in 1 2 3 4; do qm config 211$((i + 1)) | grep -qx "name: bm0$i" || exit 1; done'
check_cmd "panne M11-E22 close (lab/bin/break 11 22 --annuler après réparation)" _m11p_aucune_panne_active E22
