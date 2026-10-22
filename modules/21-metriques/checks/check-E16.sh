# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E16.sh — M21-E16 : Silences, inhibitions et routage par équipe
# À lancer depuis adm01. Lecture seule : API v2 de l'Alertmanager du cluster (status, silences), GitLab.

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E16 — Silences, inhibitions et routage par équipe"
require_cmd jq curl yq

_m21o_e16_c="$(_m21o_am_config)"
# Toutes les routes de l'arbre, à plat (les sous-routes comprises).
_m21o_e16_routes='[.route | recurse(.routes[]?)]'
for _m21o_e16_eq in mediagenda medidoc plateforme; do
  check_cmd "route de l'équipe $_m21o_e16_eq vers $_m21o_e16_eq-mail" _m21o_json "$_m21o_e16_c" --arg e "$_m21o_e16_eq" \
    "$_m21o_e16_routes"' | any(.[]; (.receiver // "") == ($e + "-mail")
      and any((.matchers // [])[]; test("^ *equipe *= *\"?" + $e + "\"? *$")))'
done
check_cmd "les alertes critiques vont à astreinte-mail ET continuent vers l'équipe (continue: true)" _m21o_json "$_m21o_e16_c" \
  "$_m21o_e16_routes"' | any(.[]; .receiver == "astreinte-mail" and .continue == true
      and any((.matchers // [])[]; test("gravite *= *\"?critique")))'
check_cmd "intervalle heures-ouvrees défini (lundi-vendredi) et utilisé par une route d'avertissements" _m21o_json "$_m21o_e16_c" '
  any((.time_intervals // [])[]; .name == "heures-ouvrees")
  and ('"$_m21o_e16_routes"' | any(.[]; ((.active_time_intervals // []) | index("heures-ouvrees")) != null
      and any((.matchers // [])[]; test("gravite *= *\"?avertissement"))))'
check_cmd "inhibition CibleInjoignable → autres alertes de la même instance (equal: instance)" _m21o_json "$_m21o_e16_c" '
  any((.inhibit_rules // [])[]; any((.source_matchers // [])[]; test("CibleInjoignable"))
      and ((.equal // []) | index("instance")) != null)'
check_cmd "inhibition nœud non prêt → MediagendaPodsNonPrets du même nœud (equal: node)" _m21o_json "$_m21o_e16_c" '
  any((.inhibit_rules // [])[]; any((.source_matchers // [])[]; test("KubeNode"))
      and any((.target_matchers // [])[]; test("MediagendaPodsNonPrets"))
      and ((.equal // []) | index("node")) != null)'

_m21o_e16_s="$(am_api "silences" 2>/dev/null || true)"
check_cmd "un silence CHG-2216 a été posé (actif ou expiré), avec un auteur" _m21o_json "$_m21o_e16_s" '
  any(.[]; (.comment // "" | test("CHG-2216")) and ((.createdBy // "") != ""))'

check_output "alertmanager/routes-tests.txt sur main couvre les récepteurs d'équipe" 'mediagenda-mail' \
  _m21o_contenu "$_M21O_P_OBS" alertmanager/routes-tests.txt
check_cmd "plateforme/observabilite : le job alertmanager:verifier du dernier pipeline de main a réussi" \
  _m21o_job_ok "$_M21O_P_OBS" "alertmanager:verifier"
