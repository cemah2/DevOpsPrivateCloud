# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # requêtes LogQL et filtres jq entre apostrophes
# check-S08.sh — F6-S08 « Une traçabilité inaltérable » (LIBRE, ferme ECA-3601) : les six sources
# d'audit arrivent dans le locataire « audit » de Loki ; le compartiment RGW archive-audit est en
# verrouillage d'objets (COMPLIANCE, rétention ≥ 1 an) et reçoit des manifestes signés ; le contrôle
# d'intégrité et la politique sont sur main ; ECA-3601 est clos. Lecture seule (Loki, RGW en lecture, GitLab).

# shellcheck source=_f6-incident.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-incident.sh"

title "F6-S08 — Une traçabilité inaltérable (ECA-3601)"
require_cmd curl jq aws

# --- Les six sources dans le locataire « audit » de Loki --------------------------------------------
# Sélecteurs figés : Kubernetes (M22-E07), OpenBao (M25-E21), Keycloak et FreeIPA (M24-E26) existent
# avant le F6 ; GitLab et Proxmox sont ajoutés en S08 (étiquette service, liste fermée du M22).
_s08_source_presente() {
  local r
  r="$(loki_requete "$1" audit 24h 2>/dev/null)" || return 1
  jq -e '(.data.result | length) > 0' >/dev/null 2>&1 <<<"$r"
}
for _s08_sel in '{job="kubernetes-audit"}' '{service="openbao"}' '{service="keycloak"}' \
  '{service="freeipa"}' '{service="gitlab"}' '{service="proxmox"}'; do
  check_cmd "locataire audit : lignes des dernières 24 h pour $_s08_sel" _s08_source_presente "$_s08_sel"
done

# --- Archive en verrouillage d'objets ----------------------------------------------------------------
if ! _f6i_archive_identite; then
  _ko "identité de lecture de l'archive illisible ($_f6i_archive_env) : verrouillage de $_f6i_archive_bucket non contrôlable"
else
  _s08_lock="$(_f6i_archive_s3 s3api get-object-lock-configuration --bucket "$_f6i_archive_bucket" || true)"
  [[ -n "$_s08_lock" ]] || _s08_lock='{}'
  check_cmd "compartiment $_f6i_archive_bucket : verrouillage d'objets activé" \
    _f6i_json "$_s08_lock" '.ObjectLockConfiguration.ObjectLockEnabled == "Enabled"'
  check_cmd "compartiment $_f6i_archive_bucket : rétention par défaut COMPLIANCE d'au moins un an (fin des essais en GOVERNANCE)" \
    _f6i_json "$_s08_lock" '.ObjectLockConfiguration.Rule.DefaultRetention
      | .Mode == "COMPLIANCE" and (((.Years // 0) >= 1) or ((.Days // 0) >= 365))'
  # Un archivage effectif récent : une période AAAA-MM-JJ/ des trois derniers jours a son manifeste signé.
  _s08_archive_recente() {
    local l j p
    l="$(_f6i_archive_s3 s3 ls --recursive "s3://$_f6i_archive_bucket/" || true)"
    for j in 1 2 3; do
      p="$(date -u -d "-$j day" +%F)"
      grep -q " $p/manifeste\.json\$" <<<"$l" && grep -q " $p/manifeste\.sig\$" <<<"$l" && return 0
    done
    return 1
  }
  check_cmd "archive : une période des trois derniers jours a son manifeste et sa signature (manifeste.json, manifeste.sig)" \
    _s08_archive_recente
fi

# --- Contrôle d'intégrité, politique, écart clos (sur main) -----------------------------------------
check_cmd "plateforme/observabilite (main) : contrôle d'intégrité outils/verifier-archive-audit.sh" \
  _f6i_existe plateforme/observabilite outils/verifier-archive-audit.sh
check_cmd "journaux-audit.md (main) : sources, horodatage, archive, intégrité, conservation d'un an" \
  _f6c_doc . '^journaux-audit\.md$' 'archive|verrouillage' 'int(e|é)grit' 'horodat' '1 an|un an|365'
check_cmd "ECA-3601 clos sur main (statut, date de clôture, lot de preuve antérieur à la clôture)" _f6c_ecart_clos 3601
