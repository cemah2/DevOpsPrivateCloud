# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E25.sh — M17-E25 « Mini-projet : packaging MédiSphère v1 » : contrôle global. Chart publié et
# signé par son pipeline ; dev, recette et prod livrés par les overlays depuis ce chart, sans dérive ;
# plus de release Helm applicative ; plateforme sous Helmfile sans écart ; documentation ; essais
# nettoyés ; étiquette packaging-v1. Lecture seule. Durée : quelques minutes (helmfile diff).

# shellcheck source=_m17-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-production.sh"

title "M17-E25 — Packaging MédiSphère v1"
require_cmd jq kubectl helm git curl

# --- Rien de provisoire -------------------------------------------------------------
check_cmd "aucune panne M17 active (E19 à E22)" _m17p_panne_close E19 E20 E21 E22
_e25_cm() { [[ -z "$(kube get configmap -n wb-essais -l owner=helm -o name 2>/dev/null)" ]]; }
_e25_sec() { [[ -z "$(_m17p_kadmin get secret -n wb-essais -l owner=helm -o name)" ]]; }
check_cmd "wb-essais : aucune release Helm d'essai (pilote secret)" _e25_sec
check_cmd "wb-essais : aucune release Helm d'essai (pilote configmap)" _e25_cm

# --- Chart ------------------------------------------------------------------------
check_cmd "mediagenda/chart : pipeline de main réussi" _m17p_gl_pipeline_ok mediagenda/chart main
_e25_v="$(_m17p_gl_derniere_version mediagenda/chart)" || _e25_v=""
check_cmd "mediagenda/chart : pipeline de l'étiquette v${_e25_v:-?} réussi (publication et signature)" \
  _m17p_gl_jobs_ok mediagenda/chart "v$_e25_v" 'pousser|push' 'sign'

# _e25_chart_signe VERSION — la version existe dans Harbor et sa signature se vérifie (ou est attachée).
_e25_chart_signe() {
  local art rc=0
  art="$(_m17p_harbor_artefact charts mediagenda "$1")" || art=""
  [[ -n "$art" ]] || return 1
  _m17p_cosign_ok "$_m17p_harbor_hote/charts/mediagenda@$(jq -r .digest <<<"$art")" || rc=$?
  if ((rc == 2)); then
    _m17p_jq "$art" '(.accessories // []) | length > 0'
    return
  fi
  ((rc == 0))
}

# --- Environnements ---------------------------------------------------------------
for _e25_env in dev recette prod; do
  _e25_ns="mediagenda-$_e25_env"
  _e25_d="$(_m17p_deploy "$_e25_ns" mediagenda)" || _e25_d=""
  _e25_c="$(jq -r '.metadata.labels["helm.sh/chart"] // empty' <<<"$_e25_d" 2>/dev/null)" || _e25_c=""
  check_cmd "$_e25_env : Deployment à jour, pods prêts" _m17p_deploy_a_jour "$_e25_d"
  check_cmd "$_e25_env : rendu d'un chart publié et signé (${_e25_c:-?})" _e25_chart_signe "${_e25_c#mediagenda-}"
  check_cmd "$_e25_env : MEDIAGENDA_ENVIRONNEMENT=$_e25_env" test "$(_m17p_env "$_e25_d" MEDIAGENDA_ENVIRONNEMENT)" = "$_e25_env"
  check_cmd "$_e25_env : aucun geste manuel dans les managedFields" _m17p_sans_manuel "$_e25_d"
  _e25_st="$(_m17p_rel_statut "$_e25_ns" mediagenda)" || _e25_st=""
  check_cmd "$_e25_env : aucune release Helm « mediagenda » (livraison par les overlays)" test -z "$_e25_st"
  check_cmd "$_e25_env : le gestionnaire « helm » ne possède plus aucun champ du Deployment" _m17p_jq "$_e25_d" \
    '[.metadata.managedFields[]? | select(.manager == "helm")] | length == 0'
  if [[ -d "$_m17p_deploiement/.git" ]]; then
    check_cmd "$_e25_env : kubectl diff --server-side -k overlays/$_e25_env (origin/main) vide" _m17p_diff_overlay "$_e25_env"
  fi
done
_e25_p="$(_m17p_deploy mediagenda-prod mediagenda)" || _e25_p=""
check_cmd "prod : au moins 3 réplicas (component haute-disponibilite)" _m17p_jq "$_e25_p" '(.spec.replicas // 0) >= 3'
check_output "prod : budget de perturbation minAvailable 2" '^2$' kube get pdb mediagenda -n mediagenda-prod -o jsonpath='{.spec.minAvailable}'
check_cmd "prod : aucun réglage de débogage" _m17p_jq "$_e25_p" \
  '[.spec.template.spec.containers[] | .env[]? | select((.name == "MEDIAGENDA_LOG_LEVEL" and .value == "DEBUG") or (.name == "MEDIAGENDA_LOG_FORMAT" and .value == "texte"))] | length == 0'
for _e25_h in mediagenda-recette mediagenda; do
  check_http "https://$_e25_h.apps.par1.medisphere.internal/pret répond 200" "https://$_e25_h.apps.par1.medisphere.internal/pret"
done
check_cmd "mediagenda/deploiement : pipeline de main réussi" _m17p_gl_pipeline_ok mediagenda/deploiement main

# --- Plateforme ---------------------------------------------------------------------
check_cmd "plateforme/k8s : pipeline de main réussi" _m17p_gl_pipeline_ok plateforme/k8s main
if [[ -d "$_m17p_k8s/.git" ]]; then
  _e25_rc=0
  _m17p_helmfile_diff_vide || _e25_rc=$?
  if ((_e25_rc == 2)); then
    skip "helmfile -e par1 diff vide" "helmfile absent de ce poste"
  else
    check_cmd "helmfile -e par1 diff (origin/main) : aucun écart sur toute la plateforme" test "$_e25_rc" -eq 0
  fi
else
  check_cmd "copie de travail $_m17p_k8s présente" false
fi
_e25_attente() { [[ -z "$(_m17p_helm list -A --pending -q)" && -z "$(_m17p_helm list -A --failed -q)" ]]; }
check_cmd "aucune release Helm en échec ou en attente dans le cluster" _e25_attente

# --- Documentation et livraison ---------------------------------------------------
_e25_docs="$(_m17p_gl_arbre plateforme/medisphere docs/kubernetes/packaging)" || _e25_docs=""
for _e25_f in 'adr/ADR-0170' 'runbooks/RB-170' 'runbooks/RB-171' 'runbooks/RB-172' 'secrets.md' 'derive.md' 'architecture.md'; do
  check_cmd "docs/kubernetes/packaging : $_e25_f" grep -q "packaging/$_e25_f" <<<"$_e25_docs"
done
_e25_tag() { gitlab_api "projects/$(_m17p_enc plateforme/medisphere)/repository/tags/packaging-v1" 2>/dev/null | jq -e '.name == "packaging-v1"' >/dev/null 2>&1; }
check_cmd "plateforme/medisphere : étiquette packaging-v1" _e25_tag
