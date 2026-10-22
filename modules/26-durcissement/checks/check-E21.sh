# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E21.sh — M26-E21 : des charges sûres par construction
# À lancer depuis adm01. Lecture seule : pods, espaces et rapports de politiques (compte wb-checks),
# dépôts (GitLab).
# Ce qui est vérifié : aucun écart à la norme « charge sûre » (C1 à C8, même filtre que
# outils/audit-charges-sures.sh) pour les pods EN SERVICE de mediagenda-* et medidoc-* ; aucun échec
# dans leurs rapports Kyverno ; Pod Security restricted imposé ; norme et outil versionnés.

# shellcheck source=_m26-operationnel-c.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel-c.sh"

title "M26-E21 — Des charges sûres par construction"
require_cmd jq kubectl curl

_m26c_e21_motif='^(mediagenda|medidoc)-'
_m26c_e21_ecarts="$(_m26c_ecarts_charges "$_m26c_e21_motif")"
_m26c_e21_sans_ecart() { [[ -z "$_m26c_e21_ecarts" ]]; }
check_cmd "aucun écart à la norme « charge sûre » dans les pods en service de mediagenda-* et medidoc-*" \
  _m26c_e21_sans_ecart
if [[ -n "$_m26c_e21_ecarts" ]]; then
  # Aide au diagnostic : les premiers écarts constatés (espace, pod, conteneur, critère).
  head -n 8 <<<"$_m26c_e21_ecarts" | tr '\t' ' ' | sed 's/^/         /'
fi

_m26c_e21_ns="$(_m26c_k get namespaces -o json)"
check_cmd "espaces mediagenda-* et medidoc-* : Pod Security enforce=restricted" \
  _m26c_json "$_m26c_e21_ns" '[.items[] | select(.metadata.name | test("^(mediagenda|medidoc)-"))] as $e
    | ($e | length) >= 3 and ($e | all(.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"))'

_m26c_e21_rapports="$(_m26c_k get policyreports.wgpolicyk8s.io -A -o json)"
check_cmd "rapports Kyverno de mediagenda-* et medidoc-* : aucun échec" \
  _m26c_json "$_m26c_e21_rapports" '[.items[] | select(.metadata.namespace | test("^(mediagenda|medidoc)-"))] as $r
    | ($r | length) >= 1 and ([$r[].results[]? | select(.result == "fail")] | length == 0)'

check_cmd "plateforme/k8s : outils/audit-charges-sures.sh sur main" \
  _m26c_fichier "$_M26C_P_K8S" outils/audit-charges-sures.sh
check_cmd "plateforme/medisphere : $_M26C_DOC/charges-sures.md sur main" \
  _m26c_fichier "$_M26C_P_DOC" "$_M26C_DOC/charges-sures.md"
