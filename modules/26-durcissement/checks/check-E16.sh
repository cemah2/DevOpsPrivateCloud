# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E16.sh — M26-E16 : Kyverno, muter et générer (et valider), tests en CI.
# À lancer depuis adm01. Lecture seule : cluster (« kube » : politiques, NetworkPolicy et pod d'essai
# de wb-modele-equipe), GitLab (pipeline et tests de plateforme/politiques), ~/m26/e16.

# shellcheck source=_m26-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel.sh"

title "M26-E16 — Kyverno : muter et générer"
require_cmd jq curl kubectl

for _m26o_e16_v in exiger-limites exiger-digest interdire-identifiants-url; do
  check_cmd "ValidatingPolicy $_m26o_e16_v prête et en refus (Deny)" \
    _m26o_json "$(_m26o_politique validatingpolicies "$_m26o_e16_v")" \
    '.status.conditionStatus.ready == true and (.spec.validationActions | index("Deny")) != null'
done
check_cmd "MutatingPolicy seccomp-par-defaut prête" \
  _m26o_json "$(_m26o_politique mutatingpolicies seccomp-par-defaut)" '.status.conditionStatus.ready == true'
check_cmd "GeneratingPolicy networkpolicy-par-defaut prête, synchronisée, sans suppression des objets générés" \
  _m26o_json "$(_m26o_politique generatingpolicies networkpolicy-par-defaut)" \
  '.status.conditionStatus.ready == true and .spec.evaluation.synchronize.enabled == true and .spec.evaluation.orphanDownstreamOnPolicyDelete.enabled == true'

_m26o_e16_np="$(_m26o_k get networkpolicies -n wb-modele-equipe -o json)"
for _m26o_e16_n in refus-par-defaut sortie-dns; do
  check_cmd "wb-modele-equipe : NetworkPolicy $_m26o_e16_n générée par Kyverno" _m26o_json "$_m26o_e16_np" --arg n "$_m26o_e16_n" \
    'any(.items[]; .metadata.name == $n and .metadata.labels["medisphere.internal/modele"] == "reseau-v1")'
done
check_cmd "wb-modele-equipe : refus-par-defaut bloque entrées ET sorties de tous les pods" _m26o_json "$_m26o_e16_np" \
  'any(.items[]; .metadata.name == "refus-par-defaut" and .spec.podSelector == {} and (.spec.policyTypes | sort) == ["Egress","Ingress"] and (.spec.ingress // []) == [] and (.spec.egress // []) == [])'
check_cmd "wb-modele-equipe : le pod essai-seccomp a reçu seccomp RuntimeDefault au niveau du pod" \
  _m26o_json "$(_m26o_k get pod -n wb-modele-equipe essai-seccomp -o json)" \
  '.spec.securityContext.seccompProfile.type == "RuntimeDefault"'

check_cmd "plateforme/politiques : au moins cinq dossiers de tests kyverno" bash -c \
  '[[ $(grep -c "kyverno-test.yaml$" <<<"$1") -ge 5 ]]' _ "$(_m26o_arbre "$_M26O_P_POLITIQUES" kyverno/tests)"
check_cmd "plateforme/politiques : dernier pipeline de main réussi, avec le job kyverno:tests" \
  _m26o_job_ok "$_M26O_P_POLITIQUES" "kyverno:tests"
check_cmd "travail ~/m26/e16/decisions.md : limites CPU, mutation des contrôleurs, espaces existants, suppression" bash -c \
  'f="$1"; [[ -s "$f" ]] && grep -qi cpu "$f" && grep -Eqi "argo|outofsync|écart" "$f" && grep -Eqi "existant" "$f" && grep -Eqi "orphan|suppression" "$f"' _ \
  "$_M26O_TRAVAIL/e16/decisions.md"
