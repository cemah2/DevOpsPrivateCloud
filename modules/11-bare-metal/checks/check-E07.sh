# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E07.sh — M11-E07 : IPMI et Redfish : découvrir l'iLO de hp01
# À lancer depuis adm01. Lecture seule : des GET Redfish avec le compte wb-redfish (certificat épinglé),
# aucune action sur l'iLO ni sur hp01. Le mot de passe n'est jamais affiché.

# shellcheck source=_m11-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-operationnel.sh"

title "M11-E07 — IPMI et Redfish : découvrir l'iLO de hp01"
require_cmd jq curl openssl

# --- Les fichiers d'accès --------------------------------------------------------------------------------
check_cmd "ilo-hp01.env présent, en mode 600" _m11o_mode600 "$_M11O_ILO_ENV"
_m11o_cles_env() {
  local k
  for k in ILO_HOST ILO_NOM_TLS ILO_USER ILO_PASSWORD; do
    [[ -n "$(_m11o_lire "$_M11O_ILO_ENV" "$k")" ]] || return 1
  done
  [[ "$(_m11o_lire "$_M11O_ILO_ENV" ILO_USER)" == wb-redfish ]]
}
check_cmd "ilo-hp01.env : ILO_HOST, ILO_NOM_TLS, ILO_PASSWORD renseignés, ILO_USER = wb-redfish" _m11o_cles_env
check_cmd "ilo-hp01.pem présent, en mode 600, et c'est un certificat" \
  bash -c '[ "$(stat -c %a "$1")" = 600 ] && openssl x509 -in "$1" -noout' _ "$_M11O_ILO_PEM"
_m11o_mdp_hors_historique() {
  local p f
  p="$(_m11o_lire "$_M11O_ILO_ENV" ILO_PASSWORD)"
  [[ -n "$p" ]] || return 1
  for f in "$HOME/.bash_history" "$HOME/.zsh_history"; do
    [[ -f "$f" ]] && grep -qF -- "$p" "$f" && return 1
  done
  return 0
}
check_cmd "le mot de passe de l'iLO n'apparaît pas dans l'historique du shell" _m11o_mdp_hors_historique

# --- Redfish, TLS vérifié ----------------------------------------------------------------------------------
_m11o_sys="$(_m11o_redfish /redfish/v1/Systems/1/ || true)"
check_output "Redfish : Systems/1 lu avec wb-redfish, certificat épinglé (état d'alimentation)" '^(On|Off)$' \
  jq -r '.PowerState // empty' <<<"$_m11o_sys"
check_output "Redfish : modèle et numéro de série lisibles" '.' jq -r '(.Model // empty) + " " + (.SerialNumber // empty) | select(test("[^ ]"))' <<<"$_m11o_sys"
_m11o_cert_servi() {
  local hote nom
  hote="$(_m11o_lire "$_M11O_ILO_ENV" ILO_HOST)"; nom="$(_m11o_lire "$_M11O_ILO_ENV" ILO_NOM_TLS)"
  timeout "$WB_TIMEOUT" openssl s_client -connect "$hote:443" -servername "$nom" </dev/null 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 2>/dev/null
}
check_output "le certificat épinglé est bien celui que présente l'iLO" \
  "^$(openssl x509 -in "$_M11O_ILO_PEM" -noout -fingerprint -sha256 2>/dev/null || echo absent)\$" _m11o_cert_servi

# --- Privilèges minimaux de wb-redfish (si l'iLO laisse ce compte lire sa propre fiche) ------------------------------
_m11o_comptes="$(_m11o_redfish /redfish/v1/AccountService/Accounts/ || true)"
_m11o_fiche=""
if [[ -n "$_m11o_comptes" ]]; then
  for _m11o_m in $(jq -r '.Members[]?["@odata.id"]' <<<"$_m11o_comptes" 2>/dev/null); do
    _m11o_c="$(_m11o_redfish "$_m11o_m" || true)"
    if [[ "$(jq -r '.UserName // empty' <<<"$_m11o_c" 2>/dev/null)" == wb-redfish ]]; then _m11o_fiche="$_m11o_c"; fi
  done
fi
if [[ -n "$_m11o_fiche" ]]; then
  check_cmd "wb-redfish : privilège de connexion seulement (ni configuration, ni comptes, ni console, ni média, ni alimentation)" \
    jq -e '.Oem.Hp.Privileges as $p | $p.LoginPriv == true and ($p.iLOConfigPriv | not) and ($p.UserConfigPriv | not)
           and ($p.RemoteConsolePriv | not) and ($p.VirtualMediaPriv | not) and ($p.VirtualPowerAndResetPriv | not)' <<<"$_m11o_fiche"
else
  skip "privilèges de wb-redfish" "l'iLO ne laisse pas ce compte lire les comptes : contrôle fait au corrigé (capture d'écran dans ton journal)"
fi

# --- Flux, outil, registre ---------------------------------------------------------------------------------------
_m11o_pf="$(_m11o_contenu_main "$_M11O_PROJET_ANSIBLE" inventories/lab/host_vars/gw01/pare_feu.yml)"
check_output "matrice de la bordure (main) : adm01 → iLO en TCP 443" '(ILO|ilo|iLO).*ports: 443|ports: 443.*(ILO|ilo|iLO)' echo "$_m11o_pf"
check_output "matrice de la bordure (main) : adm01 → iLO en UDP 623 (IPMI)" '(ILO|ilo|iLO).*ports: 623|ports: 623.*(ILO|ilo|iLO)' echo "$_m11o_pf"
_m11o_rf="$(_m11o_contenu_main "$_M11O_PROJET_PROV" outils/redfish.sh)"
check_output "plateforme/provisioning : outils/redfish.sh sur main" 'redfish' echo "$_m11o_rf"
check_cmd "outils/redfish.sh : jamais de vérification TLS désactivée (-k, --insecure)" \
  bash -c '[ -n "$1" ] && ! grep -Eq -- "(^|[[:space:]])(-k|--insecure)([[:space:]]|$)" <<<"$1"' _ "$_m11o_rf"
check_cmd "registre des secrets : compte wb-redfish inscrit" grep -q 'wb-redfish' "$_M11O_REGISTRE"
