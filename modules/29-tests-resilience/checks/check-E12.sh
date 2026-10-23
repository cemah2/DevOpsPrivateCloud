# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par bash -c, entre apostrophes exprès
#
# check-E12.sh — M29-E12 : Stratégie de tests de la plateforme
# À lancer depuis adm01. Lecture seule : documents sur main de plateforme/medisphere. Exercice de
# rédaction : le contrôle vérifie la PRÉSENCE des parties demandées ; la qualité s'auto-évalue avec le
# corrigé et la relecture de Karim.

# shellcheck source=_m29-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-operationnel.sh"

title "M29-E12 — Stratégie de tests de la plateforme"
require_cmd jq curl

_m29o_e12_s="$(_m29d_contenu "$_M29D_P_DOC" docs/qualite/strategie-tests.md)"
check_cmd "docs/qualite/strategie-tests.md sur main" bash -c '[[ -n "$1" ]]' _ "$_m29o_e12_s"
_m29o_e12_a() { grep -Eqi -- "$2" <<<"$1"; }
check_cmd "stratégie : la pyramide (étages, du statique au chaos)" _m29o_e12_a "$_m29o_e12_s" 'pyramide'
check_cmd "stratégie : ce qui tourne à chaque MR" _m29o_e12_a "$_m29o_e12_s" 'chaque MR|chaque merge request'
check_cmd "stratégie : ce qui tourne chaque nuit (planifié)" _m29o_e12_a "$_m29o_e12_s" 'nuit|nocturne|planifi'
check_cmd "stratégie : ce qui se lance à la main (manuel)" _m29o_e12_a "$_m29o_e12_s" 'manuel|à la main|à la demande'
check_cmd "stratégie : les coûts" _m29o_e12_a "$_m29o_e12_s" 'coût'
check_cmd "stratégie : les propriétaires" _m29o_e12_a "$_m29o_e12_s" 'propriétaire'
check_cmd "stratégie : ce qu'on ne teste pas" _m29o_e12_a "$_m29o_e12_s" 'ne teste pas|ne testons pas|pas testé'
check_cmd "stratégie : cite les outils du module (kubeconform, conftest, Testinfra, Terratest, k6, Chaos Mesh)" bash -c '
  for o in kubeconform conftest testinfra terratest k6 "chaos"; do grep -qi -- "$o" <<<"$1" || exit 1; done' _ "$_m29o_e12_s"

_m29o_e12_rb="$(_m29d_arbre "$_M29D_P_DOC" docs/qualite/runbooks | grep -E '/RB-290-[^/]+\.md$' | head -1 || true)"
check_cmd "docs/qualite/runbooks/RB-290-…md (lancer un test de charge sans nuire)" bash -c '[[ -n "$1" ]]' _ "$_m29o_e12_rb"
if [[ -n "$_m29o_e12_rb" ]]; then
  _m29o_e12_r="$(_m29d_contenu "$_M29D_P_DOC" "$_m29o_e12_rb")"
  check_cmd "RB-290 : la production est exclue, la recette est la cible" bash -c '
    grep -qi "prod" <<<"$1" && grep -qi "recette" <<<"$1"' _ "$_m29o_e12_r"
  check_cmd "RB-290 : annonce avant, arrêt pendant, nettoyage après" bash -c '
    grep -Eqi "annonc|prévenir|ticket" <<<"$1" && grep -Eqi "arrêt|arrêter|abortOnFail|ctrl-c" <<<"$1" && grep -Eqi "nettoy|factice|dr-k6" <<<"$1"' _ "$_m29o_e12_r"
fi
