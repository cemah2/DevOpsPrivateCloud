# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
#
# check-E46.sh — M19-E46 « Mini-projet : la chaîne de CI de MédiSphère v1 »
# Contrôle global de la livraison ci-v1 (depuis adm01). Rejoue les contrôles clés des paliers
# précédents (E04, E08, E10, E17, E18, E24, E29), puis vérifie l'adoption des composants par tous les
# projets applicatifs, les runners, le retrait de Jenkins et de SonarQube, la documentation et
# l'étiquette. Lecture seule : API GitLab en GET, « kube » (wb-checks), DNS. 2 à 4 minutes.

# shellcheck source=_m19-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-expert.sh"

title "M19-E46 — Chaîne de CI de MédiSphère v1 : contrôle global"
require_cmd jq yq kubectl curl dig

_m19_e46_dir="$(dirname "${BASH_SOURCE[0]}")"
for _m19_e46_c in E04 E08 E10 E17 E18 E24 E29; do
  if [[ -f "$_m19_e46_dir/check-$_m19_e46_c.sh" ]]; then
    # shellcheck disable=SC1090
    source "$_m19_e46_dir/check-$_m19_e46_c.sh"
  else
    skip "contrôle M19-$_m19_e46_c" "script check-$_m19_e46_c.sh absent"
  fi
done

title "M19-E46 — Adoption des composants CI/CD"
# Projets applicatifs : uniquement des composants de plateforme/ci-templates épinglés à une version
# complète vX.Y.Z ≥ v2.0.0 (forme des étiquettes publiées : « v » compris, pas de version partielle ni
# ~latest), plus aucun include « project: plateforme/ci-templates » (anciens gabarits v1.x).
_m19_e46_composants() {
  local ci
  ci="$(_m19x_brut "$1" .gitlab-ci.yml main)" || return 1
  [[ -n "$ci" ]] || return 1
  yq -e '
    (.include // []) as $i
    | ($i | length) > 0
      and ($i | all_c(has("component")))
      and ($i | all_c(.component | test("/plateforme/ci-templates/[a-z-]+@v([2-9]|[1-9][0-9])\\.[0-9]+\\.[0-9]+$")))' <<<"$ci" >/dev/null 2>&1
}
for _m19_e46_p in mediagenda/api mediagenda/chart mediagenda/deploiement medidoc/medidoc mediagenda/annuaire; do
  check_cmd "$_m19_e46_p : includes = composants de plateforme/ci-templates @vX.Y.Z ≥ v2.0.0 seulement" _m19_e46_composants "$_m19_e46_p"
  check_cmd "$_m19_e46_p : dernier pipeline de main réussi" _m19x_pipeline_vert "$_m19_e46_p" main
done
check_cmd "plateforme/ci-templates : une release v2 (ou plus) publiée" \
  _m19x_gl '[.[].tag_name | select(test("^v?([2-9]|[1-9][0-9])\\."))] | length >= 1' "projects/$(_m19x_enc plateforme/ci-templates)/releases?per_page=100"

title "M19-E46 — Runners"
_m19_e46_runner() {
  local r
  r="$(_m19x_runner_json "$1" 2>/dev/null)" || return 1
  jq -e --arg t "$2" '.status == "online" and (.paused | not) and (.tag_list | index($t))' <<<"$r" >/dev/null
}
check_cmd "runner k8s-par1 en ligne (étiquette k8s)" _m19_e46_runner k8s-par1 k8s
check_cmd "runner k8s-par1-protege en ligne (étiquette protege, références protégées)" _m19_e46_runner k8s-par1-protege protege
_m19_e46_runner02() {
  gitlab_api "runners/all?per_page=100&tag_list=docker" 2>/dev/null | jq -e 'any(.[]; .status == "online")' >/dev/null 2>&1
}
check_cmd "runner02 (étiquette docker) toujours en ligne" _m19_e46_runner02

title "M19-E46 — Retrait de Jenkins et de SonarQube"
if _m19x_api_repond; then
  check_cmd "espaces jenkins et sonarqube supprimés (releases, base CNPG sonarqube-db et routes avec eux)" \
    _m19x_kq '[.items[].metadata.name | select(. == "jenkins" or . == "sonarqube")] | length == 0' namespaces
else
  skip "objets du cluster" "l'API de k8s-par1 ne répond pas au compte des checks"
fi
_m19_e46_nxdomain() {
  local r
  r="$(dig +time=3 +tries=1 @10.10.20.10 "$1" A 2>/dev/null)" || return 1
  grep -q 'status: NXDOMAIN' <<<"$r" || { grep -q 'status: NOERROR' <<<"$r" && ! grep -q 'ANSWER SECTION' <<<"$r"; }
}
check_cmd "DNS : jenkins.apps.par1.medisphere.internal n'est plus publié" _m19_e46_nxdomain jenkins.apps.par1.medisphere.internal
check_cmd "DNS : sonarqube.apps.par1.medisphere.internal n'est plus publié" _m19_e46_nxdomain sonarqube.apps.par1.medisphere.internal
_m19_e46_sans_variables() {
  local p g
  for p in mediagenda/api medidoc/medidoc mediagenda/annuaire; do
    gitlab_api "projects/$(_m19x_enc "$p")/variables?per_page=100" 2>/dev/null |
      jq -e '[.[].key | select(test("^(SONAR|JENKINS)"))] | length == 0' >/dev/null 2>&1 || return 1
  done
  for g in mediagenda medidoc; do
    gitlab_api "groups/$g/variables?per_page=100" 2>/dev/null |
      jq -e '[.[].key | select(test("^(SONAR|JENKINS)"))] | length == 0' >/dev/null 2>&1 || return 1
  done
}
check_cmd "plus aucune variable de CI SONAR_* ni JENKINS_* (projets et groupes applicatifs)" _m19_e46_sans_variables

title "M19-E46 — Clé de signature : fin de l'exception de M19-E24"
# La clé Cosign n'existe plus que dans le Secret ci-jobs-protege/cosign-medisphere, monté par le seul
# runner protégé : plus aucune variable COSIGN_* dans les groupes ni dans les projets applicatifs.
_m19_e46_sans_cosign() {
  local p g
  for g in mediagenda medidoc medinotif legacy; do
    gitlab_api "groups/$g/variables?per_page=100" 2>/dev/null |
      jq -e '[.[].key | select(test("^COSIGN_"))] | length == 0' >/dev/null 2>&1 || return 1
  done
  for p in mediagenda/api mediagenda/chart mediagenda/deploiement medidoc/medidoc mediagenda/annuaire medinotif/worker; do
    gitlab_api "projects/$(_m19x_enc "$p")/variables?per_page=100" 2>/dev/null |
      jq -e '[.[].key | select(test("^COSIGN_"))] | length == 0' >/dev/null 2>&1 || return 1
  done
}
check_cmd "plus aucune variable COSIGN_* (groupes mediagenda, medidoc, medinotif, legacy ; projets signés)" _m19_e46_sans_cosign

title "M19-E46 — Documentation et livraison"
check_cmd "ADR-0190 présente et commitée" _m19x_doc_commite 'ADR-0190*.md'
_m19_e46_runbooks() {
  local n
  for n in 190 191 192 193 194 195 196 197 198; do _m19x_doc_commite "RB-$n*.md" || return 1; done
}
check_cmd "runbooks RB-190 à RB-198 commités dans docs/livraison/ci/runbooks/" _m19_e46_runbooks
check_cmd "état livré : docs/livraison/ci/etat-ci-v1.md (ce que trouve le M20)" _m19x_doc_contient 'etat-ci-v1.md' 'M20|module 20'
check_cmd "étiquette ci-v1 posée sur plateforme/medisphere" \
  _m19x_gl '.name == "ci-v1"' "projects/$(_m19x_enc plateforme/medisphere)/repository/tags/ci-v1"
check_cmd "aucune panne M19 encore marquée active" _m19x_aucune_panne_active
