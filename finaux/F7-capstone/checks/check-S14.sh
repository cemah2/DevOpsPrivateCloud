# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S14.sh — F7-S14 « Recette capstone-v1 » : pipelines verts des projets de la capstone,
# Applications du client saines, recette du client reconstruite (espace recréé après la production),
# preuves dans le compartiment verrouillé, document de recette, étiquette. Lecture seule.

# shellcheck source=_f7-livraison.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-livraison.sh"

title "F7-S14 — Recette capstone-v1"
require_cmd curl jq kubectl

# --- Pipelines ---------------------------------------------------------------------------------------
for _f7_p in "$_f7l_equipes" "$_f7l_identite" plateforme/secrets plateforme/k8s plateforme/gitops \
  "$_f7l_observabilite" "$_f7l_outils" "$_f7l_api" "$_f7l_deploiement" "$_f7l_doc_projet"; do
  check_cmd "$_f7_p : le dernier pipeline de main a réussi" _f7l_pipeline_ok "$_f7_p"
done

# --- Cluster -------------------------------------------------------------------------------------------
if _f7l_api_repond; then
  check_cmd "Application de $_f7l_ns_recette Synced/Healthy" _f7l_app_saine "$_f7l_ns_recette"
  check_cmd "Application de $_f7l_ns_prod Synced/Healthy" _f7l_app_saine "$_f7l_ns_prod"
  _f7_s14_recree() {
    local r p
    r="$(kube get namespace "$_f7l_ns_recette" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)"
    p="$(kube get namespace "$_f7l_ns_prod" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)"
    [[ -n "$r" && -n "$p" ]] || return 1
    (($(date -d "$r" +%s) > $(date -d "$p" +%s) + 86400))
  }
  check_cmd "$_f7l_ns_recette reconstruit depuis le code (créé au moins un jour après $_f7l_ns_prod)" _f7_s14_recree
else
  _ko "contrôles Kubernetes : impossibles, l'API de k8s-par1 ne répond pas au compte des checks (kube)"
fi
check_output "$_f7l_url_recette/pret répond 200 après la reconstruction" '^200$' _f7l_code "$_f7l_url_recette/pret"

# --- Preuves -------------------------------------------------------------------------------------------
_f7_s14_preuves_env="${WB_F6_PREUVES_ENV:-$HOME/.config/workbook/s3-preuves-conformite-lecture.env}"
if [[ -r "$_f7_s14_preuves_env" ]]; then
  _f7_s14_preuves() {
    _f7l_s3_ls "$_f7_s14_preuves_env" "${WB_F6_RGW_URL:-https://rgw.par1.medisphere.internal}" \
      "s3://${WB_F6_PREUVES_BUCKET:-preuves-conformite}/" | grep -Eqi "capstone|${_f7l_client}"
  }
  check_cmd "preuves-conformite : des preuves de la capstone déposées par ms-preuves" _f7_s14_preuves
else
  skip "preuves de la capstone dans preuves-conformite" "identité S3 de lecture des preuves absente ($_f7_s14_preuves_env, F6)"
fi
check_cmd "annexes-preuves.md cite des preuves de preuves-conformite" \
  _f7c_doc_contient soutenance/annexes-preuves.md 'preuves-conformite'

# --- Recette et étiquette -----------------------------------------------------------------------------
check_cmd "recette.md : contrôles, durées (reconstruction), écarts restants" \
  _f7l_doc . '^recette\.md$' 'reconstru' 'dur(é|e)e|min' '(é|e)cart' 'plan'
check_cmd "étiquette capstone-v1 posée sur $_f7l_doc_projet" _f7l_etiquette capstone-v1
