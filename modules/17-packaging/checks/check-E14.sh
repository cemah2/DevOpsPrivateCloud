# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E14.sh — M17-E14 « Différences et dérive » : release du dev en SSA à 448 Mi, plus aucun
# gestionnaire manuel ni dérive, diff Kustomize de la recette vide, documentation et gabarits de MR.
# Lecture seule (kubectl diff --server-side n'écrit rien).

# shellcheck source=_m17-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-production.sh"

title "M17-E14 — Différences et dérive"
require_cmd jq kubectl helm yq git

check_output "release mediagenda (mediagenda-dev) : deployed" '^deployed$' _m17p_rel_statut mediagenda-dev mediagenda
check_cmd "release mediagenda (mediagenda-dev) : appliquée en server-side apply" _m17p_rel_ssa mediagenda-dev mediagenda

_e14_d="$(_m17p_deploy mediagenda-dev mediagenda)" || _e14_d=""
if [[ -n "$_e14_d" ]]; then
  check_cmd "Deployment du dev : limite mémoire de l'API à 448Mi" \
    _m17p_jq "$_e14_d" '.spec.template.spec.containers[] | select(.name == "api") | .resources.limits.memory == "448Mi"'
  check_cmd "Deployment du dev : aucun champ possédé par un geste manuel (kubectl-edit, -patch, -set, client-side apply)" \
    _m17p_sans_manuel "$_e14_d"
  _e14_attendu="$(_m17p_helm get manifest mediagenda -n mediagenda-dev \
    | yq 'select(.kind == "Deployment") | .spec.template.spec.containers[] | select(.name == "api") | .env[] | select(.name == "MEDIAGENDA_LOG_LEVEL") | .value' 2>/dev/null)" || _e14_attendu=""
  check_cmd "MEDIAGENDA_LOG_LEVEL du dev = valeur du chart (${_e14_attendu:-?})" \
    test -n "$_e14_attendu" -a "$(_m17p_env "$_e14_d" MEDIAGENDA_LOG_LEVEL)" = "$_e14_attendu"
else
  check_cmd "Deployment mediagenda présent dans mediagenda-dev" false
fi

if [[ -d "$_m17p_deploiement/.git" ]]; then
  check_cmd "kubectl diff --server-side de l'overlay recette (origin/main) : vide" _m17p_diff_overlay recette
else
  check_cmd "copie de travail $_m17p_deploiement présente" false
fi

check_cmd "plateforme/medisphere : docs/kubernetes/packaging/derive.md" \
  _m17p_gl_existe plateforme/medisphere docs/kubernetes/packaging/derive.md
for _e14_p in mediagenda/chart mediagenda/deploiement; do
  check_output "$_e14_p : gabarit de MR qui demande le diff" '\.md$' _m17p_gl_arbre "$_e14_p" .gitlab/merge_request_templates
done
