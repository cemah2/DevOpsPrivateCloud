# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E15.sh — M26-E15 : Kyverno n'admet que les images MédiSphère signées.
# À lancer depuis adm01. Lecture seule : cluster (« kube » : politique, ExternalSecret, rapports),
# Harbor (dépôts du projet medisphere), ~/m26/e15.

# shellcheck source=_m26-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel.sh"

title "M26-E15 — Kyverno : n'admettre que les images signées"
require_cmd jq curl kubectl

_m26o_e15_p="$(_m26o_politique imagevalidatingpolicies exiger-signature-medisphere)"
check_cmd "ImageValidatingPolicy exiger-signature-medisphere présente et prête (ready)" \
  _m26o_json "$_m26o_e15_p" '.status.conditionStatus.ready == true'
check_cmd "… en refus (Deny) avec failurePolicy Fail" \
  _m26o_json "$_m26o_e15_p" '(.spec.validationActions | index("Deny")) != null and .spec.failurePolicy == "Fail"'
check_cmd "… vise mediagenda-recette et mediagenda-prod" _m26o_json "$_m26o_e15_p" '
  [.spec.matchConstraints.namespaceSelector.matchExpressions[]? | select(.operator == "In") | .values[]] as $v
  | ($v | index("mediagenda-recette")) != null and ($v | index("mediagenda-prod")) != null'
check_cmd "… vise les images registry.par1.medisphere.internal/medisphere/*" _m26o_json "$_m26o_e15_p" \
  'any(.spec.matchImageReferences[]?; (.glob // "") | startswith("registry.par1.medisphere.internal/medisphere/"))'
check_cmd "… exige le condensé sans réécrire l'image (GitOps)" _m26o_json "$_m26o_e15_p" \
  '.spec.validationConfigurations.verifyDigest == true and .spec.validationConfigurations.mutateDigest == false'
check_cmd "… attesteurs à clé Cosign, sans journal de transparence, et attestation SPDX" _m26o_json "$_m26o_e15_p" '
  (.spec.attestors | length) >= 1
  and all(.spec.attestors[]; (.cosign.key.data // "") | test("BEGIN PUBLIC KEY"))
  and any(.spec.attestations[]?; .intoto.type == "https://spdx.dev/Document")'

check_cmd "ExternalSecret harbor-kyverno (espace kyverno) synchronisé" \
  _m26o_json "$(_m26o_k get externalsecrets.external-secrets.io -n kyverno harbor-kyverno -o json)" \
  'any(.status.conditions[]?; .type == "Ready" and .status == "True")'

for _m26o_e15_ns in mediagenda-recette mediagenda-prod; do
  check_cmd "$_m26o_e15_ns : aucun rapport en échec pour exiger-signature-medisphere" \
    bash -c '[[ "$1" == 0 ]]' _ "$(_m26o_echecs_rapport exiger-signature-medisphere "$_m26o_e15_ns")"
done

check_cmd "Harbor : dépôt d'essai medisphere/essai-signature supprimé" bash -c \
  'r="$1"; [[ -n "$r" ]] && jq -e "length == 0" <<<"$r" >/dev/null' _ \
  "$(harbor_api 'projects/medisphere/repositories?q=name%3D~essai-signature' 2>/dev/null || true)"
check_cmd "travail ~/m26/e15/essais.md : les quatre essais (signée, non signée, autre clé, étiquette)" bash -c \
  'f="$1"; [[ -s "$f" ]] && grep -qi "jetable\|autre clé" "$f" && grep -qi "digest\|condensé" "$f" && grep -qi "non sign" "$f"' _ \
  "$_M26O_TRAVAIL/e15/essais.md"
