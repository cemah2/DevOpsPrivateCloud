# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E13.sh — M29-E13 « Expériences de chaos : réseau, ressources, horaires, enchaînements » :
# bibliothèque chaos/e13/ de plateforme/resilience (types, durées, cibles), Schedule borné et en pause,
# Workflow terminé, injections réelles, SLO de recette chargés, documents. Lecture seule.
# Mini-projet (_M29_MINI_PROJET=1) : la partie « objets dans le cluster » est sautée (ils ont été
# supprimés après l'exercice, comme demandé).

# shellcheck source=_m29-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-production.sh"

title "M29-E13 — Bibliothèque d'expériences de chaos"
require_cmd kubectl jq curl yq

_m29_e13_docs="$(_m29p_yaml_json "$_m29p_resilience" chaos/e13)" || true
[[ -n "$_m29_e13_docs" ]] || _m29_e13_docs='[]'

# _m29_e13_a 'filtre jq booléen sur un document' — au moins un document de la bibliothèque le satisfait.
_m29_e13_a() { jq -e "any(.[]; $1)" >/dev/null 2>&1 <<<"$_m29_e13_docs"; }

check_cmd "chaos/e13/ (main) : une NetworkChaos « delay »" _m29_e13_a '.kind == "NetworkChaos" and .spec.action == "delay"'
check_cmd "chaos/e13/ : une NetworkChaos « loss »" _m29_e13_a '.kind == "NetworkChaos" and .spec.action == "loss"'
check_cmd "chaos/e13/ : une NetworkChaos « partition » avec une cible (target)" \
  _m29_e13_a '.kind == "NetworkChaos" and .spec.action == "partition" and (.spec.target.selector != null)'
check_cmd "chaos/e13/ : une StressChaos (stressors)" _m29_e13_a '.kind == "StressChaos" and (.spec.stressors != null or .spec.stressngStressors != null)'
check_cmd "chaos/e13/ : une PodChaos « container-kill » avec containerNames" \
  _m29_e13_a '.kind == "PodChaos" and .spec.action == "container-kill" and ((.spec.containerNames // []) | length) > 0'
check_cmd "chaos/e13/ : un Schedule Forbid, historyLimit ≤ 3, expérience embarquée avec durée" \
  _m29_e13_a '.kind == "Schedule" and (.spec.concurrencyPolicy // "Forbid") == "Forbid" and (.spec.historyLimit // 99) <= 3
              and ([.spec | to_entries[] | select(.key | test("Chaos$")) | .value.duration // ""] | any(. != ""))'
check_cmd "chaos/e13/ : un Workflow avec Parallel, Suspend et StatusCheck à interruption" \
  _m29_e13_a '.kind == "Workflow" and ([.spec.templates[]?.templateType] | (index("Parallel") != null and index("Suspend") != null and index("StatusCheck") != null))
              and any(.spec.templates[]?; .abortWithStatusCheck == true)'
check_cmd "chaos/e13/ : toute expérience hors Workflow et Schedule a une durée" \
  bash -c '[[ "$(jq length <<<"$2")" -gt 0 && "$(jq "$1" <<<"$2")" == 0 ]]' _ "$_m29p_jq_sans_duree" "$_m29_e13_docs"
check_cmd "chaos/e13/ : aucune cible dans un espace de prod, messagerie ou de plateforme" \
  bash -c '[[ "$(jq length <<<"$2")" -gt 0 && "$(jq "$1" <<<"$2")" == 0 ]]' _ "$_m29p_jq_espaces_interdits" "$_m29_e13_docs"
_m29_e13_entetes() {
  local f c n=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    n=$((n + 1))
    c="$(_m29p_fichier_main "$_m29p_resilience" "$f" 2>/dev/null)" || return 1
    grep -qi "hypoth" <<<"$c" && grep -qi "mesure" <<<"$c" && grep -qi "arr[eê]t" <<<"$c" || return 1
  done < <(jq -r '[.[]._fichier] | unique[]' <<<"$_m29_e13_docs")
  ((n > 0))
}
check_cmd "chaos/e13/ : chaque fichier porte Hypothèse / Mesure / Arrêt" _m29_e13_entetes
check_cmd "chaos/catalogue.md : résultats et section « Écartées » (IOChaos…)" \
  _m29p_fichier_contient "$_m29p_resilience" chaos/catalogue.md 'confirm|réfut|refut' '^#+ .*[ÉE]cart' 'IOChaos'
check_cmd "outils/chaos-arret.sh : pause par annotation et option --supprimer" \
  _m29p_fichier_contient "$_m29p_resilience" outils/chaos-arret.sh 'experiment\.chaos-mesh\.org/pause' '--supprimer'
check_cmd "RB-294 publié (main) : arrêt d'une expérience de chaos" \
  _m29p_doc docs/qualite '^RB-294' 'pause' 'containerRecords|enregistrement'

if [[ -n "${_M29_MINI_PROJET:-}" ]]; then
  skip "objets de la série E13 dans le cluster" "mini-projet : supprimés après l'exercice"
elif ! _m29p_api_repond; then
  skip "objets de chaos dans le cluster" "l'API ne répond pas au compte des checks"
elif ! _m29p_lit_chaos; then
  skip "objets de chaos dans le cluster" "le compte des checks ne lit pas chaos-mesh.org (ClusterRole wb-checks-services-m29, M29-E09)"
else
  check_cmd "$_m29p_chaos_ns : le Schedule de la série est en pause" _m29p_kq \
    'any(.items[]; .metadata.annotations["experiment.chaos-mesh.org/pause"] == "true")' -n "$_m29p_chaos_ns" schedules.chaos-mesh.org
  check_cmd "$_m29p_chaos_ns : un Workflow terminé (Accomplished) ou interrompu" _m29p_kq \
    'any(.items[]; any(.status.conditions[]?; .type == "Accomplished" and .status == "True") or (.status.endTime != null))' \
    -n "$_m29p_chaos_ns" workflows.chaos-mesh.org
  _m29_e13_injecte() {
    kube get "$1" -n "$_m29p_chaos_ns" -o json 2>/dev/null |
      jq -e 'any(.items[]; any(.status.experiment.containerRecords[]?; (.injectedCount // 0) >= 1))' >/dev/null 2>&1
  }
  for _m29_e13_t in networkchaos stresschaos podchaos; do
    check_cmd "$_m29p_chaos_ns : une $_m29_e13_t a réellement injecté (containerRecords)" _m29_e13_injecte "$_m29_e13_t.chaos-mesh.org"
  done
fi

if _m29p_api_repond; then
  check_cmd "Pyrra : au moins deux SLO portant sur mediagenda-recette" _m29p_kq \
    '[.items[] | select(.spec.indicator | tostring | test("mediagenda-recette"))] | length >= 2' servicelevelobjectives.pyrra.dev -A
else
  skip "SLO de recette" "l'API ne répond pas au compte des checks"
fi
