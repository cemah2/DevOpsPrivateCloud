# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E08.sh — M28-E08 : Un modèle « nouveau service »
# Lecture seule : API du catalogue ; projets, MR et utilisateurs GitLab (GET, jeton read_api de ton
# compte d'administration : l'attribut is_admin d'un utilisateur n'est visible que d'un administrateur) ;
# Deployment du service (kube).

# shellcheck source=_m28-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-operationnel.sh"

title "M28-E08 — Un modèle « nouveau service »"
require_cmd jq kubectl curl

check_cmd "Template nouveau-service dans le catalogue, chargé depuis plateforme/portail-modeles" _m28o_eq template nouveau-service \
  '(.metadata.annotations["backstage.io/managed-by-location"] // "") | test("portail-modeles")'
check_cmd "projet medidoc/medidoc-vignettes : catalog-info.yaml rattaché à l'équipe medidoc" \
  _m28d_contient medidoc/medidoc-vignettes catalog-info.yaml 'name: *medidoc-vignettes' 'owner: *group:default/medidoc'
check_cmd "projet medidoc/medidoc-vignettes : dernier pipeline de main réussi" _m28d_pipeline_vert medidoc/medidoc-vignettes
check_cmd "Component medidoc-vignettes au catalogue, possédé par group:default/medidoc" _m28o_eq component medidoc-vignettes \
  '.spec.owner == "group:default/medidoc"'
check_cmd "MR « medidoc-vignettes » ouverte par svc-portail dans plateforme/gitops" _m28o_mr_portail plateforme/gitops medidoc-vignettes
check_cmd "MR « medidoc-vignettes » ouverte par svc-portail dans plateforme/k8s" _m28o_mr_portail plateforme/k8s medidoc-vignettes
check_cmd "medidoc-vignettes tourne en dev (Deployment disponible dans medidoc-vignettes-dev)" _m28d_kq \
  '(.status.availableReplicas // 0) >= 1' -n medidoc-vignettes-dev deployment medidoc-vignettes

_m28o_e08_id="$(gitlab_api 'users?username=svc-portail' 2>/dev/null | jq -r '.[0].id // empty' 2>/dev/null || true)"
check_cmd "svc-portail existe et n'est pas administrateur de l'instance" bash -c \
  'jq -e ".[0].is_admin == false" >/dev/null <<<"$1"' _ "$(gitlab_api 'users?username=svc-portail' 2>/dev/null || true)"
for _m28o_e08_p in plateforme/gitops plateforme/k8s; do
  check_cmd "svc-portail au plus Developer (30) sur $_m28o_e08_p" bash -c \
    '[[ -n "$1" ]] && jq -e ".access_level <= 30" >/dev/null <<<"$2"' _ "$_m28o_e08_id" \
    "$(gitlab_api "projects/$(_m28d_enc "$_m28o_e08_p")/members/all/${_m28o_e08_id:-0}" 2>/dev/null || true)"
done
# _m28o_e08_pas_proprietaire GROUPE — svc-portail connu, et son appartenance (directe ou héritée) au
# groupe est < 50 ; un 404 (pas membre) compte comme « pas propriétaire », une autre erreur échoue.
_m28o_e08_pas_proprietaire() {
  local r code
  [[ -n "$_m28o_e08_id" ]] || return 1
  r="$(gitlab_api "groups/$(_m28d_enc "$1")/members/all/$_m28o_e08_id" 2>/dev/null)" && {
    jq -e '.access_level < 50' >/dev/null 2>&1 <<<"$r"
    return
  }
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "${WB_TIMEOUT:-5}" \
    -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<"${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}")") \
    "${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4/groups/$(_m28d_enc "$1")/members/all/$_m28o_e08_id" 2>/dev/null || true)"
  [[ "$code" == 404 ]]
}
for _m28o_e08_g in medidoc mediagenda medinotif; do
  check_cmd "svc-portail n'est pas propriétaire (50) du groupe $_m28o_e08_g" _m28o_e08_pas_proprietaire "$_m28o_e08_g"
done

check_cmd "plateforme/medisphere : docs/plateforme-dev/modeles.md (actions, droits, limites)" \
  _m28d_doc docs/plateforme-dev/modeles.md 'publish:gitlab' 'svc-portail' 'ne fait pas|limites'
