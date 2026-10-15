# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E22.sh — M17-E22 « Panne : conflit de propriété des champs » : release du dev « deployed »,
# plus aucun gestionnaire manuel ni « scale » concurrent sur les objets de la release, HPA cohérent
# avec le chart, RB-171 publié. Lecture seule.

# shellcheck source=_m17-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-production.sh"

title "M17-E22 — Conflit de propriété des champs"
require_cmd jq kubectl helm yq

check_output "release mediagenda (mediagenda-dev) : deployed" '^deployed$' _m17p_rel_statut mediagenda-dev mediagenda
_e22_d="$(_m17p_deploy mediagenda-dev mediagenda)" || _e22_d=""
_e22_c="$(kube get configmap mediagenda -n mediagenda-dev --show-managed-fields -o json 2>/dev/null)" || _e22_c=""
check_cmd "Deployment du dev : aucun champ possédé par un geste manuel" _m17p_sans_manuel "$_e22_d"
check_cmd "ConfigMap du dev : aucun champ possédé par un geste manuel" _m17p_sans_manuel "$_e22_c"

_e22_hpa="$(kube get hpa -n mediagenda-dev -o json 2>/dev/null | jq -r '[.items[] | select(.spec.scaleTargetRef.kind == "Deployment" and .spec.scaleTargetRef.name == "mediagenda")] | length' 2>/dev/null)" || _e22_hpa=0
if [[ "$_e22_hpa" =~ ^[1-9] ]]; then
  _e22_rep="$(_m17p_helm get manifest mediagenda -n mediagenda-dev | yq 'select(.kind == "Deployment" and .metadata.name == "mediagenda") | .spec.replicas' 2>/dev/null)" || _e22_rep=""
  check_cmd "un HPA pilote le dev : le chart ne rend plus spec.replicas" test "${_e22_rep:-null}" = null
  check_cmd "un HPA pilote le dev : helm ne possède plus spec.replicas" _m17p_jq "$_e22_d" \
    '[.metadata.managedFields[]? | select(.manager == "helm") | .fieldsV1["f:spec"]["f:replicas"]? // empty] | length == 0'
else
  check_cmd "aucun HPA : spec.replicas n'appartient qu'à helm (pas de « scale » concurrent)" _m17p_jq "$_e22_d" \
    '[.metadata.managedFields[]? | select(.subresource == "scale")] | length == 0'
fi
check_cmd "plateforme/medisphere : RB-171 publié (docs/kubernetes/packaging/runbooks/)" \
  bash -c "grep -q 'RB-171' <<<\"\$1\"" _ "$(_m17p_gl_arbre plateforme/medisphere docs/kubernetes/packaging/runbooks)"
check_cmd "panne M17-E22 close (lab/bin/break 17 22 --annuler après réparation)" _m17p_panne_close E22
