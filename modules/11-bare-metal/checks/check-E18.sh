# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions jq entre apostrophes
# check-E18.sh — M11-E18 « Inventaire matériel et firmware » : hp01 dans NetBox avec numéro de série
# (identique à celui de l'iLO), versions du BIOS et de l'iLO, date d'inventaire récente, éléments
# d'inventaire ; script et documentation sur main. Lecture seule (Redfish en GET).

# shellcheck source=_m11-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-production.sh"

title "M11-E18 — Inventaire matériel de hp01"
require_cmd curl jq

_m11_e18_dev="$(_m11p_equipement hp01)" || true
check_cmd "NetBox : équipement hp01 présent" test -n "$_m11_e18_dev"
_m11_e18_serie="$(jq -r '.serial // ""' <<<"$_m11_e18_dev" 2>/dev/null)" || true
check_cmd "hp01 : numéro de série renseigné" test -n "$_m11_e18_serie"
for _m11_e18_cf in firmware_bios firmware_ilo; do
  check_cmd "hp01 : champ personnalisé $_m11_e18_cf renseigné" \
    bash -c 'v="$(jq -r --arg c "$1" ".custom_fields[\$c] // \"\"" <<<"$2")"; [ -n "$v" ] && [ "$v" != null ]' _ "$_m11_e18_cf" "$_m11_e18_dev"
done
_m11_e18_frais() {
  local d
  d="$(jq -r '.custom_fields.inventaire_maj // ""' <<<"$_m11_e18_dev")"
  [[ -n "$d" && "$d" != null ]] || return 1
  (( $(date +%s) - $(date -d "$d" +%s) < 8 * 86400 ))
}
check_cmd "hp01 : inventaire_maj de moins de 8 jours (collecte planifiée)" _m11_e18_frais

_m11_e18_id="$(jq -r '.id // empty' <<<"$_m11_e18_dev" 2>/dev/null)" || true
_m11_e18_items="$(netbox_api "dcim/inventory-items/?device_id=${_m11_e18_id:-0}&limit=200" 2>/dev/null | jq -r '.results[].name' 2>/dev/null)" || true
check_cmd "hp01 : au moins un élément d'inventaire processeur" grep -Eqi 'cpu|proc' <<<"$_m11_e18_items"
check_cmd "hp01 : au moins un élément d'inventaire mémoire" grep -Eqi 'dimm|mem' <<<"$_m11_e18_items"

# Comparaison avec l'iLO, en suivant les liens Redfish depuis la racine.
_m11_e18_serie_ilo() {
  local sys
  sys="$(_m11p_ilo /redfish/v1/Systems/ | jq -r '.Members[0]["@odata.id"] // empty')" || return 1
  [[ -n "$sys" ]] || return 1
  _m11p_ilo "$sys" | jq -r '.SerialNumber // empty' | tr -d '[:space:]'
}
_m11_e18_si="$(_m11_e18_serie_ilo 2>/dev/null)" || true
if [[ -z "$_m11_e18_si" ]]; then
  skip "numéro de série de NetBox identique à celui de l'iLO" "iLO illisible depuis adm01 ($_m11p_ilo_env, flux, certificat)"
else
  check_cmd "numéro de série de NetBox identique à celui de l'iLO" test "$_m11_e18_si" = "$(tr -d '[:space:]' <<<"$_m11_e18_serie")"
fi

check_cmd "outils/inventaire-redfish.py sur main de plateforme/provisioning" \
  _m11p_gitlab_fichier plateforme/provisioning outils/inventaire-redfish.py
check_cmd "docs/provisioning/firmware.md sur main de plateforme/medisphere" \
  _m11p_gitlab_fichier plateforme/medisphere docs/provisioning/firmware.md
skip "refus du jeton svc-automatisation sur un autre équipement" "auto-évaluation : essai consigné dans firmware.md (un contrôle ne fait pas d'écriture)"
