# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E21.sh — M13-E21 « Panne : la signature n'est plus reconnue » : l'étiquette signee:1.0 désigne
# le digest produit, ce digest porte une signature vérifiable par la clé de test d'origine (cosign verify
# depuis adm01), et la sonde utilise Cosign 3 avec la bonne clé publique.

# shellcheck source=_m13-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-expert.sh"

title "M13-E21 — La signature est reconnue"
require_cmd jq curl cosign

check_cmd "Harbor répond « healthy »" _m13p_sante
check_cmd "medisphere : signature exigée (inchangée)" _m13p_projet_meta medisphere enable_content_trust_cosign true

if _m13x_temoins; then
  _m13_e21_att="$(remote "$_m13x_runner" 'sudo -n cat /etc/workbook/sonde-registre/temoins.txt' 2>/dev/null | awk '$1 == "signee:1.0" { print $2 }')" || _m13_e21_att=""
  _m13_e21_cour="$(_m13p_api projects/wb-sonde/repositories/signee/artifacts/1.0 | jq -r '.digest // empty' 2>/dev/null)" || _m13_e21_cour=""
  check_cmd "wb-sonde/signee:1.0 désigne le digest produit (temoins.txt)" \
    test -n "$_m13_e21_att" -a "$_m13_e21_att" = "$_m13_e21_cour"
  _m13_e21_signe() {
    _m13p_api "projects/wb-sonde/repositories/signee/artifacts/$1/accessories" \
      | jq -e 'any(.[]?; .type == "signature.cosign")' >/dev/null 2>&1
  }
  check_cmd "ce digest porte une signature Cosign (accessoire)" _m13_e21_signe "${_m13_e21_att:-absent}"
  check_ssh "la sonde utilise la clé publique de test d'origine" "$_m13x_runner" \
    'sudo -n cmp -s /etc/workbook/sonde-registre/cosign.pub /var/lib/workbook/temoins-m13/cosign-sonde.pub'
  check_ssh_output "la sonde utilise une image Cosign 3.x" "$_m13x_runner" '^COSIGN_IMAGE=.*:v3\.' \
    'sudo -n grep "^COSIGN_IMAGE=" /etc/workbook/sonde-registre/sonde.conf'
  _m13_e21_cle="$(mktemp)"
  remote "$_m13x_runner" 'sudo -n cat /var/lib/workbook/temoins-m13/cosign-sonde.pub' >"$_m13_e21_cle" 2>/dev/null || true
  check_cmd "cosign verify (clé de test, sans journal de transparence) réussit depuis adm01 sur wb-sonde/signee:1.0" \
    _m13x_cosign_verify "$_M13P_REGISTRE_NOM/wb-sonde/signee:1.0" "$_m13_e21_cle"
  rm -f -- "$_m13_e21_cle"
else
  skip "contrôles des témoins" "témoins pas encore créés (ils le sont à la première injection)"
fi
check_cmd "RB-134 publié dans docs/registre/runbooks/" _m13p_doc_prefixe docs/registre/runbooks RB-134
check_cmd "panne M13-E21 close (lab/bin/break 13 21 --annuler après réparation)" _m13p_aucune_panne_active E21
