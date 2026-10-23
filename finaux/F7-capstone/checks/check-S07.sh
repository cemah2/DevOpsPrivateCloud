# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S07.sh — F7-S07 « Le client en code » : fichier du client dans plateforme/equipes, locataire
# Capsule, espaces, AppProject et Applications, instances publiées en marque blanche, clés transit
# dédiées, export de réversibilité et documentation. Lecture seule.

# shellcheck source=_f7-livraison.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-livraison.sh"

title "F7-S07 — Le client en code"
require_cmd curl jq kubectl

# --- plateforme/equipes ----------------------------------------------------------------------------
check_cmd "$_f7l_equipes (main) : equipes/${_f7l_client}.yaml décrit un client (type client, bloc client)" \
  _f7l_contient "$_f7l_equipes" "equipes/${_f7l_client}.yaml" '^[[:space:]]*type:[[:space:]]*client' '^[[:space:]]*client:' 'reversibilit'
check_cmd "$_f7l_equipes : le dernier pipeline de main a réussi (validation, tests, capacité, propagation)" \
  _f7l_pipeline_ok "$_f7l_equipes"

# --- Kubernetes ------------------------------------------------------------------------------------
if _f7l_api_repond; then
  check_cmd "Tenant Capsule « $_f7l_client » présent et protégé contre la suppression" \
    _f7l_kq '.spec.preventDeletion == true' tenants.capsule.clastix.io "$_f7l_client"
  _f7_s07_espace() {
    local ns="$1"
    kube get namespace "$ns" -o json 2>/dev/null | jq -e --arg t "$_f7l_client" '.metadata.labels["capsule.clastix.io/tenant"] == $t
      and .metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"' >/dev/null 2>&1 || return 1
    _f7l_kq '(.items | length) > 0' -n "$ns" resourcequotas || return 1
    _f7l_kq '(.items | length) > 0' -n "$ns" limitranges || return 1
    _f7l_kq '(.items | length) > 0' -n "$ns" secretstores.external-secrets.io
  }
  for _f7_ns in "$_f7l_ns_recette" "$_f7l_ns_prod"; do
    check_cmd "espace $_f7_ns : locataire $_f7l_client, PSA restricted, quota, LimitRange, SecretStore" _f7_s07_espace "$_f7_ns"
  done
  _f7_s07_projet() {
    kube -n argocd get appprojects.argoproj.io "$_f7l_client" -o json 2>/dev/null | jq -e --arg c "$_f7l_client" '
      (.spec.sourceRepos | length) == 1 and (.spec.sourceRepos[0] | test("\\*") | not)
      and (.spec.destinations | length) >= 1
      and all(.spec.destinations[]; (.namespace == ($c + "-recette") or .namespace == ($c + "-prod")))
      and ((.spec.clusterResourceWhitelist // []) | length) == 0' >/dev/null 2>&1
  }
  check_cmd "AppProject $_f7l_client : un seul dépôt source (sans joker), destinations limitées aux deux espaces, aucun objet de cluster" \
    _f7_s07_projet
  check_cmd "Application de $_f7l_ns_recette Synced/Healthy" _f7l_app_saine "$_f7l_ns_recette"
  check_cmd "Application de $_f7l_ns_prod Synced/Healthy" _f7l_app_saine "$_f7l_ns_prod"
  _f7_s07_prod_manuelle() {
    local a
    a="$(_f7l_app "$_f7l_ns_prod")"
    [[ -n "$a" ]] && _f7l_kq '(.spec.syncPolicy.automated // null) == null' -n argocd applications.argoproj.io "$a"
  }
  check_cmd "la production du client se synchronise à la main (pas de synchronisation automatique)" _f7_s07_prod_manuelle
else
  _ko "contrôles Kubernetes : impossibles, l'API de k8s-par1 ne répond pas au compte des checks (kube)"
fi

# --- Publication et marque blanche -------------------------------------------------------------------
check_output "$_f7l_url_prod/pret répond 200" '^200$' _f7l_code "$_f7l_url_prod/pret"
check_output "$_f7l_url_recette/pret répond 200" '^200$' _f7l_code "$_f7l_url_recette/pret"
_f7_s07_titre() {
  local t
  t="$(_f7l_json "$_f7l_url_recette/openapi.json" | jq -r '.info.title // empty' 2>/dev/null)"
  [[ -n "$t" ]] && ! grep -Eqi 'm[ée]di(agenda|sph[eè]re)' <<<"$t"
}
check_cmd "description OpenAPI de l'instance du client : titre du service du GHSV (ni MédiAgenda ni MédiSphère)" _f7_s07_titre

# --- Clés dédiées -----------------------------------------------------------------------------------
_f7_s07_cles() {
  local cles k n=0
  cles="$(_f7l_cles_client)"
  [[ -n "$cles" ]] || return 1
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    bao_api "transit/keys/$k" 2>/dev/null | jq -e '.data.exportable == false and .data.deletion_allowed == false
      and (.data.allow_plaintext_backup // false) == false' >/dev/null 2>&1 || return 1
    n=$((n + 1))
  done <<<"$cles"
  ((n >= 1))
}
check_cmd "clés transit/${_f7l_client}-* présentes, ni exportables ni supprimables (lues avec wb-checks)" _f7_s07_cles

# --- Réversibilité et documentation ------------------------------------------------------------------
check_cmd "docs/capstone/locataire-${_f7l_client}.md (création, hors fichier, arrivée et départ, clés)" \
  _f7l_doc . "^locataire-${_f7l_client}\\.md$" 'equipes/' 'transit' 'd(é|e)part|fin de contrat' 'r(é|e)versibilit'
check_cmd "RB-371 (réversibilité et fin de contrat : export, remise, destruction, effacement des clés)" \
  _f7l_doc runbooks '^RB-371' 'export' 'destruction|d(é|e)truire' 'cl(é|e)' '30'
check_cmd "compte rendu d'essai de relecture (docs/capstone/reversibilite/) : empreinte et relecture" \
  _f7l_doc reversibilite '\.md$' '[0-9a-f]{64}' 'relu|relecture|recharg'
if [[ -r "$_f7l_s3_rev" ]]; then
  _f7_s07_export() { [[ -n "$(_f7l_s3_ls "$_f7l_s3_rev" "$_f7l_rgw" "s3://${_f7l_client}-reversibilite/")" ]]; }
  check_cmd "compartiment ${_f7l_client}-reversibilite : au moins un export déposé" _f7_s07_export
else
  skip "contenu du compartiment ${_f7l_client}-reversibilite" "identité S3 de lecture absente ($_f7l_s3_rev)"
fi
