# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # requêtes LogQL et filtres jq entre apostrophes
# check-S08.sh — F6-S08 « Une traçabilité inaltérable » (LIBRE, ferme ECA-3601) : les six sources
# d'audit arrivent dans le locataire « audit » de Loki ; un compartiment RGW en verrouillage d'objets
# (COMPLIANCE, rétention ≥ 1 an) reçoit l'archive ; le contrôle d'intégrité et la doc sont sur main ;
# ECA-3601 est clos. Lecture seule (Loki, RGW en lecture, GitLab).

# shellcheck source=_f6-incident.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-incident.sh"

title "F6-S08 — Une traçabilité inaltérable (ECA-3601)"
require_cmd curl jq aws

# --- Les six sources dans le locataire « audit » de Loki --------------------------------------------
_s08_source_presente() {
  local j="$1" r
  r="$(loki_requete "{job=\"$j\"}" audit 24h 2>/dev/null)" || return 1
  jq -e '(.data.result | length) > 0' >/dev/null 2>&1 <<<"$r"
}
for j in kubernetes-audit openbao-audit keycloak-audit gitlab-audit proxmox-audit freeipa-audit; do
  check_cmd "locataire audit : lignes récentes de la source $j" _s08_source_presente "$j"
done

# --- Archive en verrouillage d'objets ----------------------------------------------------------------
_s08_arch_bucket="${WB_F6_ARCHIVE_BUCKET:-archive-audit}"
_s08_arch_env="${WB_F6_ARCHIVE_ENV:-$HOME/.config/workbook/s3-archive-audit-lecture.env}"
_s08_s3api() {
  [[ -r "$_s08_arch_env" ]] || return 1
  (
    set -a
    # shellcheck disable=SC1090
    source "$_s08_arch_env"
    set +a
    aws --endpoint-url "$_f6i_rgw" s3api "$@" 2>/dev/null
  )
}
if [[ ! -r "$_s08_arch_env" ]]; then
  _ko "identité S3 de lecture de l'archive illisible ($_s08_arch_env) : impossible de contrôler le verrouillage"
else
  _s08_lock="$(_s08_s3api get-object-lock-configuration --bucket "$_s08_arch_bucket" || true)"
  check_cmd "compartiment $_s08_arch_bucket : verrouillage d'objets activé" \
    _f6i_json "$_s08_lock" '.ObjectLockConfiguration.ObjectLockEnabled == "Enabled"'
  # Rétention par défaut >= 1 an (365 jours ou 1 an), mode COMPLIANCE ou GOVERNANCE.
  check_cmd "compartiment $_s08_arch_bucket : rétention par défaut >= 1 an" \
    _f6i_json "$_s08_lock" '(.ObjectLockConfiguration.Rule.DefaultRetention.Years // 0) >= 1
      or (.ObjectLockConfiguration.Rule.DefaultRetention.Days // 0) >= 365'
  # Au moins un manifeste signé déposé (preuve d'un archivage effectif).
  _s08_manifestes_ok() {
    local l
    l="$(_s08_s3api list-objects-v2 --bucket "$_s08_arch_bucket" --query 'Contents[].Key' --output text || true)"
    grep -q 'manifeste.json' <<<"$l" && grep -q 'manifeste.sig' <<<"$l"
  }
  check_cmd "au moins un manifeste signé déposé (manifeste.json + manifeste.sig)" _s08_manifestes_ok
fi

# --- Contrôle d'intégrité, politique, écart clos (sur main) -----------------------------------------
check_cmd "verifier-archive-audit.sh présent sur main (plateforme/observabilite)" \
  _f6i_fichier_existe plateforme/observabilite outils/verifier-archive-audit.sh
check_cmd "journaux-audit.md (main) : sources, horodatage, archive, intégrité, conservation 1 an" \
  _f6i_doc . '^journaux-audit\.md$' 'archive|verrouillage' 'int(e|é)grit' 'horodat' '1 an|un an|365'
check_cmd "ECA-3601 clos sur main avec preuve dans preuves-conformite" \
  _f6i_doc ecarts '^ECA-3601' 'statut:\s*clos' 'preuve' 'ECA-3601'
