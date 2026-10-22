# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E39.sh — M19-E39 « Panne : le déploiement en dev est refusé » : agent prêt et pointé vers git01,
# droits de l'agent dans mediagenda-dev, ci_access du groupe mediagenda, dernier deployer-dev réussi,
# RB-197, panne close. Lecture seule.

# shellcheck source=_m19-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-expert.sh"

title "M19-E39 — Le déploiement en dev passe à nouveau"
require_cmd jq yq kubectl curl

if _m19x_api_repond; then
  check_cmd "agent k8s-par1 : Deployment de gitlab-agent disponible" \
    _m19x_kq '[.items[] | select(any(.spec.template.spec.containers[].args[]?; startswith("--kas-address=")))
              | select((.status.availableReplicas // 0) >= 1 and (.status.availableReplicas // 0) == (.spec.replicas // 1))] | length >= 1' \
    -n gitlab-agent deploy
  check_cmd "agent k8s-par1 : --kas-address vers git01.par1.medisphere.internal" \
    _m19x_kq 'all(.items[].spec.template.spec.containers[].args[]? | select(startswith("--kas-address=")); contains("git01.par1.medisphere.internal"))
              and any(.items[].spec.template.spec.containers[].args[]?; startswith("--kas-address="))' -n gitlab-agent deploy
  check_cmd "mediagenda-dev : un RoleBinding donne ses droits au compte de service de l'agent" \
    _m19x_kq 'any(.items[]; any(.subjects[]?; .kind == "ServiceAccount" and .namespace == "gitlab-agent"))' -n mediagenda-dev rolebindings
else
  skip "objets de l'agent" "l'API de k8s-par1 ne répond pas au compte des checks"
fi
_m19_e39_ci_access() {
  _m19x_brut plateforme/k8s .gitlab/agents/k8s-par1/config.yaml main | yq -e '.ci_access.groups[] | select(.id == "mediagenda")' >/dev/null 2>&1
}
check_cmd "plateforme/k8s : ci_access de l'agent autorise le groupe mediagenda" _m19_e39_ci_access
_m19_e39_dernier() {
  gitlab_api "projects/$(_m19x_enc mediagenda/deploiement)/jobs?per_page=100" 2>/dev/null |
    jq -e '[.[] | select(.name == "deployer-dev" and .ref == "main" and (.status == "success" or .status == "failed"))] | max_by(.id) | .status == "success"' >/dev/null 2>&1
}
check_cmd "mediagenda/deploiement : le dernier job deployer-dev de main a réussi" _m19_e39_dernier
check_cmd "RB-197 : diagnostic d'un déploiement par l'agent (jeton, ci_access, RBAC, kasAddress)" \
  _m19x_doc_contient 'RB-197*.md' 'ci_access'
check_cmd "panne M19-E39 close (lab/bin/break 19 39 --annuler après réparation)" _m19x_aucune_panne_active E39
