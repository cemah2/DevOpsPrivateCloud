# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # noms de robots (robot$…) et filtres jq entre apostrophes
#
# check-E03.sh — M13-E03 : Projets, membres et comptes robots
# À lancer depuis adm01. Lecture seule : API de Harbor (robot wb-checks), skopeo inspect (lecture
# de manifestes), registre de travail en lecture si ctr01 existe encore, GitLab en GET.

# shellcheck source=_m13-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-decouverte.sh"

title "M13-E03 — Projets, membres et comptes robots"
require_cmd jq curl skopeo

_m13_env="${WB_HARBOR_CHECKS_FILE:-$_M13D_CFG/harbor-checks.env}"
check_cmd "harbor-checks.env présent en 600 (~/.config/workbook)" _m13d_local600 "$_m13_env"
check_cmd "harbor-moi.env présent en 600 (~/.config/workbook)" _m13d_local600 "$_M13D_CFG/harbor-moi.env"
_m13_lit() { harbor_api "projects?page_size=100" | jq -e 'type == "array"' >/dev/null 2>&1; }
check_cmd "le robot wb-checks lit l'API de Harbor" _m13_lit

# Le refus d'écriture de wb-checks est vérifié sur ses permissions (section Robots) : un check ne
# tente jamais une écriture, même vouée à l'échec.

# --- Projets ---------------------------------------------------------------------------------------
for _m13_p in medisphere plateforme bibliotheque charts; do
  _m13_j="$(_m13d_projet "$_m13_p")"
  check_cmd "projet $_m13_p : existe et est privé" \
    jq -e '.name and (.metadata.public // "false") == "false" and (.registry_id // 0) == 0' <<<"${_m13_j:-null}"
done

# --- Membres de medisphere --------------------------------------------------------------------------
_m13_membres="$(_m13d_api "projects/medisphere/members?page_size=100")"
# role_id : 1 Project Admin, 2 Developer, 3 Guest, 4 Maintainer, 5 Limited Guest
_m13_role() { jq -e --arg u "$1" --argjson r "$2" '[.[]? | select(.entity_name == $u and .entity_type == "u")][0].role_id == $r' <<<"$_m13_membres" >/dev/null 2>&1; }
if [[ -n "${WB_MOI:-}" ]]; then
  check_cmd "medisphere : $WB_MOI administrateur du projet" _m13_role "$WB_MOI" 1
else
  skip "medisphere : ton compte administrateur du projet" "WB_MOI non défini dans lab/lab.env"
fi
check_cmd "medisphere : karim.benali administrateur du projet" _m13_role karim.benali 1
check_cmd "medisphere : julien.petit développeur" _m13_role julien.petit 2
_m13_lucas() { jq -e '[.[]? | select(.entity_name == "lucas.martin")][0].role_id | IN(3, 5)' <<<"$_m13_membres" >/dev/null 2>&1; }
check_cmd "medisphere : lucas.martin invité (sans poussée)" _m13_lucas

# --- Robots ----------------------------------------------------------------------------------------------
for _m13_r in 'robot$medisphere+ci' 'robot$bibliotheque+ci' 'robot$k8s-pull' 'robot$wb-checks'; do
  _m13_j="$(_m13d_robot "$_m13_r")"
  check_cmd "$_m13_r : existe, actif, expire dans 180 jours au plus" \
    bash -c '[[ -n "$1" ]] && jq -e ".disable == false" <<<"$1" >/dev/null' _ "$_m13_j"
  if [[ -n "$_m13_j" ]] && _m13d_robot_expire_bien "$_m13_j"; then _ok "$_m13_r : date d'expiration conforme"; else _ko "$_m13_r : n'expire pas, ou dans plus de 180 jours"; fi
done
_m13_k8s="$(_m13d_robot 'robot$k8s-pull')"; [[ -n "$_m13_k8s" ]] || _m13_k8s='{}'
check_cmd 'robot$k8s-pull : aucune permission d'"'"'écriture' _m13d_robot_sans_ecriture "$_m13_k8s"
check_cmd 'robot$k8s-pull : tirage sur medisphere, plateforme, bibliotheque, charts' \
  jq -e '[.permissions[]? | select([.access[]? | select(.resource == "repository" and .action == "pull")] | length > 0) | .namespace] as $n
         | ["medisphere","plateforme","bibliotheque","charts"] | all(. as $p | $n | index($p))' <<<"$_m13_k8s"
_m13_wb="$(_m13d_robot 'robot$wb-checks')"; [[ -n "$_m13_wb" ]] || _m13_wb='{}'
check_cmd 'robot$wb-checks : aucune permission d'"'"'écriture' _m13d_robot_sans_ecriture "$_m13_wb"
_m13_ci="$(_m13d_robot 'robot$medisphere+ci')"; [[ -n "$_m13_ci" ]] || _m13_ci='{}'
check_cmd 'robot$medisphere+ci : poussée dans medisphere seulement' \
  jq -e '[.permissions[]? | select([.access[]?.action] | index("push")) | .namespace] == ["medisphere"]' <<<"$_m13_ci"

# --- Images migrées --------------------------------------------------------------------------------------
for _m13_d in mediagenda-api medidoc medinotif legacy-rdv; do
  check_cmd "medisphere/$_m13_d : au moins une image étiquetée" \
    jq -e '[.[]? | select((.tags // []) | length > 0)] | length >= 1' <<<"$(_m13d_artefacts medisphere "$_m13_d")"
done
_m13_biblio() { _m13d_api "projects/bibliotheque/repositories?page_size=100" | jq -e 'length >= 1' >/dev/null 2>&1; }
check_cmd "bibliotheque : au moins une image de base" _m13_biblio

# Empreintes préservées : comparaison avec le registre de travail s'il existe encore.
_m13_rt="ctr01.par1.medisphere.internal:5000"
if timeout "$WB_TIMEOUT" bash -c "exec 3<>/dev/tcp/ctr01.par1.medisphere.internal/5000" 2>/dev/null && [[ -r "$_M13D_CFG/registre-travail.env" ]]; then
  _m13_t="$(_m13d_derniere_version medisphere mediagenda-api)"
  _m13_compare() {
    local REGISTRE_UTILISATEUR="" REGISTRE_MOT_DE_PASSE="" a b
    # shellcheck disable=SC1091
    source "$_M13D_CFG/registre-travail.env"
    a="$(skopeo inspect --raw --creds "$REGISTRE_UTILISATEUR:$REGISTRE_MOT_DE_PASSE" "docker://$_m13_rt/mediagenda/api:$_m13_t" 2>/dev/null | sha256sum | cut -d' ' -f1)"
    b="$(skopeo inspect --raw --authfile "$(_m13d_auth)/config.json" "docker://$_M13D_NOM/medisphere/mediagenda-api:$_m13_t" 2>/dev/null | sha256sum | cut -d' ' -f1)"
    [[ -n "$_m13_t" && "$a" == "$b" && "$a" != "$(printf '' | sha256sum | cut -d' ' -f1)" ]]
  }
  check_cmd "mediagenda-api:${_m13_t:-?} : même empreinte que sur le registre de travail" _m13_compare
else
  skip "empreintes identiques au registre de travail" "ctr01:5000 injoignable ou registre-travail.env absent"
fi

# --- Code --------------------------------------------------------------------------------------------------
_m13_code() {
  local v p
  v="$(_m13d_contenu_main "$_M13D_INFRA" registre/versions.tf)"
  p="$(_m13d_contenu_main "$_M13D_INFRA" registre/providers.tf)"
  grep -q 'goharbor/harbor' <<<"$v" && grep -Eq 'version *= *"~> *3\.' <<<"$v" && grep -Eq 'insecure *= *false' <<<"$p"
}
check_cmd "plateforme/infra (main) : registre/ avec goharbor/harbor épinglé et insecure = false" _m13_code
