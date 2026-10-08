# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
# check-E25.sh — M11-E25 « Mini-projet : l'usine de provisioning » : contrôle global.
#   1. la chaîne (reprend les contrôles de E13, E19, E20, E21) ;
#   2. l'inventaire de hp01 (reprend E18) ;
#   3. l'usine : pipeline de plateforme/provisioning vert avec validation des rendus, journal NetBox
#      de la démonstration, documentation, étiquette provisioning-v1 ;
#   4. le nettoyage : maas01, VM 2117, compte wb-maas, flux et pare-feu de Proxmox, pannes M11.
#   Si l'ADR-0110 conserve MAAS (choix justifié), WB_M11_MAAS_CONSERVE=1 dans lab/lab.env saute les
#   contrôles de retrait de MAAS (et seulement eux).
# Lecture seule. Prend quelques minutes.

_m11_e25_dir="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E13.sh
source "$_m11_e25_dir/check-E13.sh"
# shellcheck source=check-E19.sh
source "$_m11_e25_dir/check-E19.sh"
# shellcheck source=check-E20.sh
source "$_m11_e25_dir/check-E20.sh"
# shellcheck source=check-E21.sh
source "$_m11_e25_dir/check-E21.sh"
# shellcheck source=check-E18.sh
source "$_m11_e25_dir/check-E18.sh"

title "M11-E25 — L'usine de provisioning"

# --- Usine --------------------------------------------------------------------------------------
_m11_e25_ci="$(_m11p_gitlab_brut plateforme/provisioning .gitlab-ci.yml)" || true
check_cmd "pipeline de plateforme/provisioning : validation des rendus (ksvalidator, debconf-set-selections ou script de vérification)" \
  bash -c 'grep -Eq "ksvalidator|debconf-set-selections|verifier" <<<"$1" && grep -Eq "when:[[:space:]]*manual" <<<"$1"' _ "$_m11_e25_ci"
_m11_e25_pipeline() {
  [[ "$(gitlab_api "projects/plateforme%2Fprovisioning/pipelines?ref=main&per_page=1" | jq -r '.[0].status // empty')" == success ]]
}
check_cmd "dernier pipeline de main de plateforme/provisioning réussi" _m11_e25_pipeline
_m11_e25_demo() {
  local n=0 id
  for id in $(netbox_api "dcim/devices/?role=serveur-bm&limit=50" | jq -r '.results[].id'); do
    if [[ "$(netbox_api "extras/journal-entries/?assigned_object_type=dcim.device&assigned_object_id=$id&limit=1" | jq -r '.count // 0')" -ge 3 ]]; then
      n=$((n + 1))
    fi
  done
  ((n >= 2))
}
check_cmd "NetBox : au moins deux serveurs bm* portent le journal d'une mise en service" _m11_e25_demo
for _m11_e25_f in docs/provisioning/usine.md docs/provisioning/orchestration.md docs/provisioning/securite-chaine.md; do
  check_cmd "$_m11_e25_f sur main de plateforme/medisphere" _m11p_gitlab_fichier plateforme/medisphere "$_m11_e25_f"
done
_m11_e25_liste() { _m11p_gitlab_ls plateforme/medisphere "$1" | sort | tr '\n' ' '; }
check_output "ADR-0110 et ADR-0111 sur main" 'ADR-0110.*ADR-0111' _m11_e25_liste docs/socle/adr
check_output "RB-110 et RB-111 sur main" 'RB-110.*RB-111' _m11_e25_liste docs/socle/runbooks
check_output "matrice des flux documentée : VLAN 60 (10.10.60.0/24)" '10\.10\.60\.' \
  _m11p_gitlab_brut plateforme/medisphere docs/socle/matrice-flux.md
check_cmd "étiquette provisioning-v1 sur plateforme/medisphere" \
  gitlab_api "projects/plateforme%2Fmedisphere/repository/tags/provisioning-v1"

# --- Nettoyage -----------------------------------------------------------------------------------
if [[ "${WB_M11_MAAS_CONSERVE:-0}" == 1 ]]; then
  skip "retrait de MAAS (maas01, wb-maas, flux)" "WB_M11_MAAS_CONSERVE=1 : MAAS conservé par l'ADR-0110"
else
  check_ssh "pve01 : VM 2116 (maas01) détruite" "$WB_PVE_HOST" '! qm status 2116 >/dev/null 2>&1'
  check_output "DNS : maas01.par1.medisphere.internal n'existe plus (NXDOMAIN)" 'status: NXDOMAIN' \
    dig +time=3 +tries=1 @10.10.20.10 maas01.par1.medisphere.internal A
  _m11_e25_nb_maas() {
    [[ "$(netbox_api "virtualization/virtual-machines/?name=maas01&status=active" | jq -r .count)" == 0 &&
      "$(netbox_api "dcim/devices/?name=maas01&status=active" | jq -r .count)" == 0 ]]
  }
  check_cmd "NetBox : plus de VM ni d'équipement maas01 actif" _m11_e25_nb_maas
  check_ssh "pve01 : compte wb-maas@pve supprimé ou désactivé, sans jeton" "$WB_PVE_HOST" \
    'u="$(pveum user list --output-format json | python3 -c "import json,sys; u=[x for x in json.load(sys.stdin) if x.get(\"userid\")==\"wb-maas@pve\"]; print(\"absent\" if not u else (\"actif\" if u[0].get(\"enable\",1) else \"inactif\"))")"; [ "$u" = absent ] || { [ "$u" = inactif ] && [ "$(pveum user token list wb-maas@pve --output-format json | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")" = 0 ]; }'
  check_cmd "matrice des flux : plus de référence à maas01 (10.10.60.11)" \
    bash -c '[ -s "$1" ] && ! grep -Eqi "10\.10\.60\.11|maas" "$1"' _ "$_m11p_src/ansible/inventories/lab/host_vars/gw01/pare_feu.yml"
  check_ssh "pare-feu de Proxmox : plus de référence à maas01 (10.10.60.11)" "$WB_PVE_HOST" \
    '! grep -rqs "10\.10\.60\.11" /etc/pve/firewall/'
fi
check_ssh "pve01 : VM jetable 2117 (m11-build) détruite" "$WB_PVE_HOST" '! qm status 2117 >/dev/null 2>&1'
check_cmd "aucune panne M11 active" _m11p_aucune_panne_active
