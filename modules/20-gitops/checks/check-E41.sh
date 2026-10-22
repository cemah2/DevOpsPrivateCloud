# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E41.sh — M20-E41 « Panne : une synchronisation a supprimé des ressources » : dev rétabli
# (Synced, Healthy, /pret répond par la Gateway), et les protections en place : bases CNPG en
# Prune=false, PruneLast sur les Applications de MédiAgenda synchronisées automatiquement, aucune
# synchronisation automatique en production. RB-200, journal, panne close. Lecture seule.

# shellcheck source=_m20-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-expert.sh"

title "M20-E41 — Dev rétabli, l'élagage maîtrisé"
require_cmd jq kubectl curl

if ! _m20x_argo_lisible; then
  skip "Applications d'Argo CD" "le compte des checks ne lit pas les Applications (wb-checks-livraison, M20-E03)"
else
  check_cmd "$_m20x_app_dev : Synced, Healthy" _m20x_app_saine "$_m20x_app_dev"
  check_cmd "$_m20x_app_dev : aucune ressource manquante (Missing)" \
    _m20x_app_jq "$_m20x_app_dev" '[.status.resources[]? | select((.health.status // "") == "Missing")] | length == 0'
  check_cmd "mediagenda-dev : Service mediagenda présent et HTTPRoute résolue (ResolvedRefs)" \
    _m20x_kq '[.status.parents[]?.conditions[]? | select(.type == "ResolvedRefs" and .status == "True")] | length > 0' \
    -n "$_m20x_ns_dev" httproutes.gateway.networking.k8s.io mediagenda
  check_http "https://mediagenda-dev.apps.par1.medisphere.internal/pret répond 200" \
    "https://mediagenda-dev.apps.par1.medisphere.internal/pret" 200
  check_cmd "bases CNPG de mediagenda-* protégées de l'élagage (Prune=false)" \
    _m20x_cnpg_proteges "$_m20x_ns_dev" "$_m20x_ns_recette" "$_m20x_ns_prod"
  for _m20_e41_a in "$_m20x_app_dev" "$_m20x_app_recette"; do
    check_cmd "$_m20_e41_a : élagage en fin de synchronisation (PruneLast=true)" \
      _m20x_app_jq "$_m20_e41_a" '(.spec.syncPolicy.syncOptions // []) | index("PruneLast=true")'
  done
  check_cmd "$_m20x_app_prod : aucune synchronisation automatique (ni prune automatique)" \
    _m20x_app_jq "$_m20x_app_prod" '.spec.syncPolicy.automated == null or ((.spec.syncPolicy.automated.enabled // true) == false)'
fi
for _m20_e41_o in dev recette prod; do
  check_cmd "overlays/$_m20_e41_o (main) : component protection-donnees inclus" \
    bash -c 'grep -Eq "components/protection-donnees/?[[:space:]]*$" <<<"$1"' _ "$(_m20x_gitlab_brut mediagenda/deploiement "overlays/$_m20_e41_o/kustomization.yaml" 2>/dev/null)"
done
check_cmd "RB-200 : section sur les ressources supprimées par une synchronisation" _m20x_doc_contient "$_m20x_rb200" '^#+ .*(prune|élag|supprim)'
check_cmd "journal de diagnostic de INC-4741 commité (docs/kubernetes/journal/)" _m20x_journal 'INC-4741'
check_cmd "panne M20-E41 close (lab/bin/break 20 41 --annuler après réparation)" _m20x_aucune_panne_active E41
