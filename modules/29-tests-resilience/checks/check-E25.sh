# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# check-E25.sh — M29-E25 « Mini-projet : tests et résilience de MédiSphère v1 » : contrôle global de la
# livraison resilience-v1 (depuis adm01). Rejoue les vérifications clés des paliers 1 à 4 présentes dans
# ce dépôt, puis vérifie ce qui n'appartient qu'à la livraison : composant validation consommé partout à
# la même version, pipelines nocturnes verts, Chaos Mesh filtré, rien d'actif, aucune VM de test, pannes
# closes, actions de journée de jeu closes, documentation, étiquette. Lecture seule. 3 à 5 minutes.

# shellcheck source=_m29-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-expert.sh"

_m29_e25_dir="$(dirname "${BASH_SOURCE[0]}")"

title "M29-E25 — Tests et résilience de MédiSphère v1 : contrôle global"
require_cmd kubectl jq curl yq ssh conftest opa

# --- 1. Vérifications clés des exercices (chacune affiche son propre titre) ----------------------------
# _M29_MINI_PROJET : les checks rejoués adaptent ce qui n'a de sens que pendant l'exercice (E05, E06 :
# traces de charge des 7 derniers jours ; E07 : sondes Goss si l'essai a été retiré par décision écrite ;
# E09 : première expérience supprimée depuis ; E13 : objets de la série supprimés après l'exercice).
_M29_MINI_PROJET=1
for _m29_e25_ex in 02 03 04 05 06 07 08 09 10 13 14 19 20 21 22; do
  _m29_e25_f="$_m29_e25_dir/check-E$_m29_e25_ex.sh"
  if [[ -f "$_m29_e25_f" ]]; then
    # shellcheck disable=SC1090  # vérifications des exercices, chargées dynamiquement
    source "$_m29_e25_f"
  else
    skip "vérification de M29-E$_m29_e25_ex" "script absent de ce dépôt"
  fi
done

# --- 2. Livraison ------------------------------------------------------------------------------------
title "M29-E25 — Livraison resilience-v1"

# Composant validation : même version @vX.Y.Z dans les quatre projets, aucun job en allow_failure.
_m29_e25_versions=""
for _m29_e25_p in plateforme/k8s plateforme/gitops plateforme/infra plateforme/ansible; do
  _m29_e25_v="$(_m29p_fichier_main "$_m29_e25_p" .gitlab-ci.yml 2>/dev/null | grep -oE 'ci-templates/validation@v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)" || _m29_e25_v=""
  check_cmd "$_m29_e25_p : consomme le composant validation (@vX.Y.Z)" test -n "$_m29_e25_v"
  check_cmd "$_m29_e25_p : aucun job de validation en allow_failure: true" _m29x_sans_allow_failure "$_m29_e25_p"
  _m29_e25_versions+="${_m29_e25_v##*@}"$'\n'
done
check_cmd "même version du composant validation dans les quatre projets" \
  bash -c '[[ "$(grep -v "^$" <<<"$1" | sort -u | wc -l)" == 1 ]]' _ "$_m29_e25_versions"

# Pipelines nocturnes et de main.
check_cmd "plateforme/ansible : dernier pipeline planifié (Testinfra) réussi" _m29p_pipeline_ok plateforme/ansible schedule
check_cmd "plateforme/resilience : dernier pipeline planifié (non-régression) réussi" _m29p_pipeline_ok "$_m29p_resilience" schedule
check_cmd "plateforme/tofu-modules : dernier pipeline planifié (nettoyeur) réussi" \
  _m29p_pipeline_ok "${WB_M29_PROJET_TOFU_MODULES:-plateforme/tofu-modules}" schedule
for _m29_e25_p in "$_m29p_resilience" plateforme/politiques plateforme/ci-templates; do
  check_cmd "$_m29_e25_p : dernier pipeline de main réussi" _m29p_pipeline_ok "$_m29_e25_p"
done

if _m29p_api_repond; then
  for _m29_e25_app in chaos-mesh k6-operator; do
    check_cmd "Application Argo CD $_m29_e25_app : Synced et Healthy" _m29p_app_saine "$_m29_e25_app"
  done
  check_cmd "espaces annotés chaos-mesh.org/inject=enabled : exactement mediagenda-recette, medinotif-recette, wb-essais" _m29p_kq \
    '[.items[] | select(.metadata.annotations["chaos-mesh.org/inject"] == "enabled") | .metadata.name] | sort
     == ["mediagenda-recette", "medinotif-recette", "wb-essais"]' namespaces
  check_cmd "Chaos Mesh : filtre d'espaces actif (ENABLE_FILTER_NAMESPACE du contrôleur)" _m29p_kq \
    'any(.spec.template.spec.containers[].env[]?; .name == "ENABLE_FILTER_NAMESPACE" and (.value | ascii_downcase) == "true")' \
    -n chaos-mesh deployment chaos-controller-manager
  if _m29p_lit_chaos; then
    check_cmd "aucune expérience, aucun Schedule ni Workflow actif dans le cluster" \
      bash -c '[[ "$(jq length <<<"$1")" == 0 ]]' _ "$(_m29x_chaos_actifs)"
  else
    skip "expériences actives" "le compte des checks ne lit pas chaos-mesh.org"
  fi
  if kube get testruns.k6.io -n k6 -o name >/dev/null 2>&1; then
    check_cmd "k6 : aucun TestRun en cours (stage hors finished/error)" _m29p_kq \
      '[.items[] | select((.status.stage // "") | test("^(finished|error)$") | not)] | length == 0' -n k6 testruns.k6.io
  fi
  check_cmd "wb-essais : aucun pod de test restant (*-e24, cible, client)" _m29p_kq \
    '[.items[] | select(.metadata.name | test("-e24|^cible|^client"))] | length == 0' -n wb-essais pods
else
  skip "Chaos Mesh et k6 dans le cluster" "l'API ne répond pas au compte des checks"
fi
check_cmd "aucune panne M29 encore marquée active (lab/bin/break)" _m29x_aucune_panne_active

# Journée de jeu suivie d'effets : chaque action est close, ou reportée par une décision écrite (issue
# restée ouverte avec l'étiquette « reportee » en plus de journee-de-jeu).
_m29_e25_ouvertes_non_reportees() {
  gitlab_api "projects/$(_m29p_enc "$_m29p_resilience")/issues?labels=journee-de-jeu&state=opened&not%5Blabels%5D=reportee&per_page=100" 2>/dev/null |
    jq 'length' 2>/dev/null || echo 99
}
check_cmd "journée de jeu : au moins une action ouverte en E16, aucune ouverte sans être close ni reportée (étiquette reportee)" bash -c \
  '[[ "$1" -ge 1 && "$2" == 0 ]]' _ "$(_m29p_issues "$_m29p_resilience" journee-de-jeu all)" "$(_m29_e25_ouvertes_non_reportees)"

# --- 3. Documentation et étiquette ------------------------------------------------------------------
check_cmd "strategie-tests.md à jour de la livraison (k6-operator, non-régression, journées de jeu, nettoyeur Terratest)" \
  _m29p_doc docs/qualite '^strategie-tests' 'kubeconform' 'Testinfra' 'Chaos Mesh' 'k6-operator' 'non-r.{1,2}gression' 'journ.{1,2}es? de jeu|journees-de-jeu' 'nettoy'
for _m29_e25_rb in RB-290 RB-291 RB-292 RB-293 RB-294 RB-295 RB-296 RB-297; do
  check_cmd "runbook $_m29_e25_rb publié (main)" _m29p_doc docs/qualite "^$_m29_e25_rb" '.'
done
check_cmd "ADR-0290 publié (main)" _m29p_doc docs/qualite/adr '^ADR-0290' 'Chaos Mesh' 'Litmus'
check_cmd "post-mortem INC-5623 publié (main)" _m29p_doc docs/qualite/post-mortems 'INC-5623' '/pret'
check_cmd "sous-le-capot-chaos-mesh.md publié (main)" _m29p_doc docs/qualite '^sous-le-capot-chaos-mesh' 'netem'
check_cmd "note de livraison livraison-resilience-v1.md : finaux, reste à faire" \
  _m29p_doc docs/qualite '^livraison-resilience-v1' 'F[1-7]' 'contrat' 'prod'
_m29_e25_etiquette() {
  gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/resilience-v1' 2>/dev/null | jq -e '.name == "resilience-v1"' >/dev/null 2>&1
}
check_cmd "étiquette resilience-v1 posée sur plateforme/medisphere" _m29_e25_etiquette
