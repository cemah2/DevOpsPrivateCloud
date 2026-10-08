# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E12.sh — M08-E12 : RGW : comptes, utilisateurs, quotas et politiques
# À lancer depuis adm01. Lecture seule : radosgw-admin (get, info, stats), lectures S3 (liste).
# Les clés S3 sont lues dans leurs fichiers par un sous-shell (variables d'environnement d'aws) :
# elles n'apparaissent ni dans ps ni dans la sortie. Seule la clé d'ACCÈS (identifiant public, pas
# le secret) est transmise à radosgw-admin pour retrouver l'utilisateur.

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E12 — RGW : comptes, utilisateurs, quotas et politiques"
require_cmd jq aws

_m08o_compte="$(_m08o_outil radosgw-admin account get --account-name=medidoc)"
_m08o_id="$(jq -r '.id // ""' <<<"$_m08o_compte" 2>/dev/null || true)"
_m08o_app="$_M08O_CFG/s3-medidoc-app.env"
_m08o_audit="$_M08O_CFG/s3-medidoc-audit.env"

check_output "compte RGW « medidoc » (identifiant RGW + 17 chiffres : ${_m08o_id:-absent})" '^RGW[0-9]{17}$' echo "$_m08o_id"
check_cmd "compte : quota de 20 Gio actif" \
  jq -e '.quota.enabled == true and .quota.max_size == 21474836480' <<<"$_m08o_compte"
check_cmd "compte : quota de compartiment de 1 000 000 d'objets actif" \
  jq -e '.bucket_quota.enabled == true and .bucket_quota.max_objects == 1000000' <<<"$_m08o_compte"
check_cmd "utilisateur racine medidoc-racine rattaché au compte" \
  jq -e --arg id "$_m08o_id" '.account_id == $id and $id != ""' <<<"$(_m08o_outil radosgw-admin user info --uid=medidoc-racine)"

# Utilisateur retrouvé par la clé d'accès du fichier (identifiant public).
_m08o_cle_acces() { sed -nE 's/^(export[[:space:]]+)?AWS_ACCESS_KEY_ID="?([^"]*)"?.*/\2/p' "$1" 2>/dev/null | head -n 1; }
_m08o_utilisateur_iam() {   # FICHIER NOM
  local ak
  ak="$(_m08o_cle_acces "$1")"
  [[ -n "$ak" ]] || return 1
  _m08o_outil radosgw-admin user info --access-key="$ak" \
    | jq -e --arg n "$2" --arg id "$_m08o_id" '.display_name == $n and .account_id == $id and $id != ""' >/dev/null
}
_m08o_iam_ok() { _m08o_local600 "$1" && _m08o_utilisateur_iam "$1" "$2"; }
check_cmd "s3-medidoc-app.env (600) : clés de l'utilisateur IAM medidoc-app du compte" _m08o_iam_ok "$_m08o_app" medidoc-app
check_cmd "s3-medidoc-audit.env (600) : clés de l'utilisateur IAM medidoc-audit du compte" _m08o_iam_ok "$_m08o_audit" medidoc-audit

# --- Compartiments ------------------------------------------------------------------------------
for _m08o_b in medidoc-documents medidoc-journaux; do
  check_cmd "compartiment $_m08o_b : appartient au compte" \
    jq -e --arg id "$_m08o_id" '.owner == $id and $id != ""' <<<"$(_m08o_outil radosgw-admin bucket stats --bucket="$_m08o_b")"
done

# --- Droits effectifs, en lecture ---------------------------------------------------------------------
_m08o_s3() {   # FICHIER_ENV commande aws… — clés dans l'environnement du seul sous-shell
  ( set -a
    # shellcheck source=/dev/null
    . "$1"
    set +a
    export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-https://rgw.par1.medisphere.internal}"
    export AWS_REQUEST_CHECKSUM_CALCULATION="${AWS_REQUEST_CHECKSUM_CALCULATION:-when_required}"
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-default}"
    shift
    timeout 20 aws "$@" ) 2>&1
}
check_cmd "medidoc-app liste medidoc-documents" \
  _m08o_s3 "$_m08o_app" s3api list-objects-v2 --bucket medidoc-documents --max-items 1
check_output "medidoc-app se voit refuser la liste de medidoc-journaux (AccessDenied)" 'AccessDenied' \
  _m08o_s3 "$_m08o_app" s3api list-objects-v2 --bucket medidoc-journaux --max-items 1
check_cmd "medidoc-audit liste medidoc-journaux" \
  _m08o_s3 "$_m08o_audit" s3api list-objects-v2 --bucket medidoc-journaux --max-items 1
check_output "medidoc-documents : versionnage activé" '"Status": *"Enabled"' \
  _m08o_s3 "$_m08o_audit" s3api get-bucket-versioning --bucket medidoc-documents --output json
check_cmd "registre des secrets : clés S3 de MédiDoc inscrites" _m08o_registre 'medidoc-(app|racine)'
