# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # gabarits Go et scripts entre apostrophes : évalués à distance
#
# check-E15.sh — M12-E15 : Un registre de travail
# À lancer depuis adm01. Lecture seule : TLS (openssl s_client), API du registre en GET (compte
# plateforme), docker inspect et systemctl is-active sur ctr01, lecture de config.yml (sudo), DNS.

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E15 — Un registre de travail"
require_cmd jq curl openssl dig

# --- 1. Adresse, TLS, authentification -----------------------------------------------------------------
check_dns "DNS : ctr01.par1.medisphere.internal → 10.10.99.121 (réservation Kea)" "$_M12O_NOM01" A '^10\.10\.99\.121$' 10.10.20.10
_m12o_e15_tls() {
  timeout 10 openssl s_client -connect "$_M12O_REGISTRE" -servername "$_M12O_NOM01" -CAfile "$_M12O_RACINE" \
    -verify_return_error </dev/null >/dev/null 2>&1
}
check_cmd "registre : certificat de la PKI MédiSphère, chaîne vérifiée" _m12o_e15_tls
check_output "registre : certificat émis par l'intermédiaire MédiSphère" 'issuer=.*M[ée]diSph[èe]re' bash -c \
  'timeout 10 openssl s_client -connect "$1" -servername "$2" </dev/null 2>/dev/null | openssl x509 -noout -issuer' _ "$_M12O_REGISTRE" "$_M12O_NOM01"
check_http "registre : /v2/ exige une authentification (401 sans identifiants)" "https://$_M12O_REGISTRE/v2/" 401 --cacert "$_M12O_RACINE"
check_cmd "adm01 : ~/.config/workbook/registre-travail.env en 600" \
  bash -c '[ "$(stat -c %a "$1" 2>/dev/null)" = 600 ]' _ "$_M12O_REGISTRE_ENV"
check_cmd "adm01 : ~/.config/workbook/registre-ci.curl en 600" \
  bash -c '[ "$(stat -c %a "$1" 2>/dev/null)" = 600 ]' _ "$HOME/.config/workbook/registre-ci.curl"
check_output "registre : le compte de registre-travail.env est accepté" '"repositories"' _m12o_registre "_catalog"
check_http "registre : le compte ci (registre-ci.curl) est accepté" "https://$_M12O_REGISTRE/v2/" 200 \
  --cacert "$_M12O_RACINE" -K "$HOME/.config/workbook/registre-ci.curl"

# --- 2. Contenu ------------------------------------------------------------------------------------------
_m12o_e15_mg="$(_m12o_etiquettes mediagenda/api)"
check_cmd "registre : mediagenda/api a les étiquettes 0.1.0 et 0.2.0" \
  bash -c 'grep -qx "0.1.0" <<<"$1" && grep -qx "0.2.0" <<<"$1"' _ "$_m12o_e15_mg"
check_cmd "registre : medidoc/medidoc:1.0.0 est un index linux/amd64 + linux/arm64" _m12o_multi_plateformes medidoc/medidoc 1.0.0

# --- 3. Le service sur ctr01 --------------------------------------------------------------------------------
_m12o_e15_reg="$(_m12o_docker "ps -q --filter publish=5000" | head -n 1)"
_m12o_e15_j="$( [[ -n "$_m12o_e15_reg" ]] && _m12o_docker "inspect $_m12o_e15_reg" | jq -c '.[0]' 2>/dev/null || true)"
check_cmd "ctr01 : conteneur du registre (registry:3) qui publie le port 5000" \
  _m12o_json "${_m12o_e15_j:-}" '.Config.Image | test("registry:3")'
check_cmd "registre : racine en lecture seule, aucune capacité, pas d'escalade" _m12o_json "${_m12o_e15_j:-}" \
  '.HostConfig.ReadonlyRootfs == true and ((.HostConfig.CapDrop // []) | map(ascii_upcase) | index("ALL") != null)
   and ((.HostConfig.SecurityOpt // []) | any(test("no-new-privileges")))'
check_ssh "ctr01 : suppression activée dans la configuration de Distribution" "$_M12O_CTR01" \
  'sudo -n grep -A1 -E "^ *delete:" /opt/registre/config.yml | grep -Eq "enabled: *true"'
for _m12o_e15_u in registre-gc.timer cert-renewer@registre.timer; do
  check_ssh "ctr01 : $_m12o_e15_u actif" "$_M12O_CTR01" "systemctl is-active -q $_m12o_e15_u"
done
