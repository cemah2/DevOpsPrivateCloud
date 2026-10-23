# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
#
# check-E07.sh — M29-E07 : Goss : la comparaison et les sondes de santé
# À lancer depuis adm01. Lecture seule : Prometheus témoin de mon01 (résultat des sondes blackbox du
# groupe goss, règles chargées), fichiers de plateforme/ansible et de plateforme/medisphere sur main.
# Le port 8099 des VMs n'est ouvert qu'à mon01 (pare-feu local) : on lit le résultat par le témoin.

# shellcheck source=_m29-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-operationnel.sh"

title "M29-E07 — Goss : la comparaison et les sondes de santé"
require_cmd jq curl

# --- 1. Le code -------------------------------------------------------------------------------------
check_cmd "plateforme/ansible : rôle goss (gabarit des tests goss.yaml.j2)" \
  _m29d_existe "$_M29D_P_ANSIBLE" roles/goss/templates/goss.yaml.j2
check_cmd "rôle goss : binaire 0.4.10 vérifié par empreinte" bash -c '
  grep -Eq "0\.4\.10" <<<"$1" && grep -Eq "[0-9a-f]{64}" <<<"$1"' _ "$(_m29d_contenu "$_M29D_P_ANSIBLE" roles/goss/defaults/main.yml)"
_m29o_e07_unite="$(_m29d_contenu "$_M29D_P_ANSIBLE" roles/goss/templates/goss-serve.service.j2)"
check_cmd "goss serve : port 8099, sans privilège (DynamicUser ou utilisateur dédié)" bash -c '
  grep -q "8099" <<<"$1$2" && grep -Eq "^(DynamicUser=yes|User=[a-z])" <<<"$1"' _ "$_m29o_e07_unite" \
  "$(_m29d_contenu "$_M29D_P_ANSIBLE" roles/goss/defaults/main.yml)"

# --- 2. Les sondes de mon01 --------------------------------------------------------------------------
# Au mini-projet (check-E25), l'essai Goss a pu être retiré par la décision écrite (testinfra-goss.md,
# ADR-0290 : goss-retrait.yml) : les sondes ne sont plus exigées.
if [[ -n "${_M29_MINI_PROJET:-}" ]]; then
  skip "sondes et alertes Goss de mon01" "mini-projet : l'essai peut avoir été retiré par décision écrite (ADR-0290)"
else
  _m29o_e07_sondes="$(_m29o_temoin_requete 'probe_success{job="blackbox", groupe="goss"}')"
  if [[ -z "$_m29o_e07_sondes" ]]; then
    _ko "Prometheus témoin de mon01 injoignable ($_M29O_TEMOIN)"
  else
    for _m29o_e07_h in "${_M29O_GOSS_HOTES[@]}"; do
      check_cmd "sonde goss de $_m29o_e07_h : 200 (tous les tests Goss passent)" _m29d_json "$_m29o_e07_sondes" \
        'any(.data.result[]; (.metric.instance | test("//" + $h + "[.:]")) and .value[1] == "1")' --arg h "$_m29o_e07_h"
    done
  fi
  _m29o_e07_regles="$(_m29o_temoin_regles)"
  check_cmd "témoin : alertes TestsGossEnEchec et SondeGossMuette chargées" _m29d_json "$_m29o_e07_regles" \
    '[.data.groups[].rules[] | select(.type == "alerting") | .name] as $n | ($n | index("TestsGossEnEchec")) != null and ($n | index("SondeGossMuette")) != null'
  check_cmd "témoin : un test Goss rouge ne déclenche PAS SondeEnEchec (critique) : groupe goss exclu" _m29d_json "$_m29o_e07_regles" \
    'any(.data.groups[].rules[]; .name == "SondeEnEchec" and (.query | test("groupe *!= *\"goss\"")))'
fi

# --- 3. La comparaison ----------------------------------------------------------------------------------
_m29o_e07_doc="$(_m29d_contenu "$_M29D_P_DOC" docs/qualite/testinfra-goss.md)"
check_cmd "plateforme/medisphere : docs/qualite/testinfra-goss.md (comparaison et décision)" bash -c '
  grep -qi "testinfra" <<<"$1" && grep -qi "goss" <<<"$1" && grep -Eqi "décision|decision" <<<"$1"' _ "$_m29o_e07_doc"
check_cmd "plateforme/medisphere : RB-291 (sonde Goss rouge)" bash -c '[[ -n "$1" ]]' _ \
  "$(_m29d_arbre "$_M29D_P_DOC" docs/qualite/runbooks | grep -E '/RB-291-[^/]+\.md$' || true)"
