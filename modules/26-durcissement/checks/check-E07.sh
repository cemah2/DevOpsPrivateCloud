# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E07.sh — M26-E07 : Kyverno : installation et premières politiques CEL
# À lancer depuis adm01. Lecture seule : Applications Argo CD, pods et Deployments de kyverno, politiques
# (policies.kyverno.io), rapports (wgpolicyk8s.io) et configurations de webhooks par le compte des checks
# (ClusterRole wb-checks-securite étendue en E07) ; pipeline de plateforme/politiques par l'API de GitLab.

# shellcheck source=_m26-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-decouverte.sh"

title "M26-E07 — Kyverno : installation et premières politiques CEL"
require_cmd jq curl kubectl

# --- 1. Le contrôleur ---------------------------------------------------------------------------------
check_cmd "Application Argo CD kyverno : Synced et Healthy" _m26d_app_saine kyverno
_m26d_e07_adm="$(_m26d_k -n kyverno get deployment kyverno-admission-controller -o json)"
check_cmd "kyverno-admission-controller : 3 réplicas prêts" \
  _m26d_json "$_m26d_e07_adm" '.spec.replicas >= 3 and (.status.readyReplicas // 0) >= 3'
check_cmd "Contrôleur d'admission réparti sur au moins deux nœuds" \
  _m26d_json "$(_m26d_k -n kyverno get pods -l app.kubernetes.io/component=admission-controller -o json)" \
  '[.items[] | select(.status.phase == "Running") | .spec.nodeName] | unique | length >= 2'
check_cmd "Espace kyverno : toutes les images viennent de Harbor (cache ghcr), aucune de reg.kyverno.io" \
  _m26d_images_harbor kyverno
check_cmd "Espace kyverno : Pod Security restricted imposé" \
  _m26d_json "$(_m26d_k get namespace kyverno -o json)" \
  '.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"'

# --- 2. Les webhooks excluent les espaces critiques ---------------------------------------------------
_m26d_e07_wh="$(_m26d_k get validatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno -o json)"
if [[ -z "$_m26d_e07_wh" ]]; then
  skip "Sélecteurs des webhooks de Kyverno" "configurations illisibles : ajoute validatingwebhookconfigurations à wb-checks-securite (étape 9)"
else
  # Webhooks qui reçoivent les ressources (politiques CEL et classiques), pas ceux qui valident les
  # politiques elles-mêmes (objets sans espace).
  check_cmd "Webhooks de ressources de Kyverno : kube-system, argocd et kyverno exclus du sélecteur d'espaces" \
    _m26d_json "$_m26d_e07_wh" '[.items[] | select(.metadata.name == "kyverno-resource-validating-webhook-cfg") | .webhooks[]]
      | length > 0 and all(
          [.namespaceSelector.matchExpressions[]? | select(.key == "kubernetes.io/metadata.name" and .operator == "NotIn") | .values[]]
          | (index("kube-system") != null and index("argocd") != null and index("kyverno") != null))'
  check_cmd "Webhooks des ValidatingPolicy d'audit : failurePolicy Ignore" \
    _m26d_json "$_m26d_e07_wh" '[.items[].webhooks[] | select(.name | startswith("vpol.validate.kyverno.svc"))] as $w
      | ($w | length > 0) and ($w | any(.failurePolicy == "Ignore"))'
fi

# --- 3. Les politiques ---------------------------------------------------------------------------------
check_cmd "Application Argo CD politiques : Synced et Healthy" _m26d_app_saine politiques
_m26d_e07_vpol="$(_m26d_k get validatingpolicies.v1.policies.kyverno.io -o json)"
for _m26d_e07_pol in registres-autorises exiger-etiquettes; do
  check_cmd "ValidatingPolicy $_m26d_e07_pol (policies.kyverno.io/v1) prête, en [Audit, Warn] sans Deny, failurePolicy Ignore" \
    _m26d_json "$_m26d_e07_vpol" '[.items[] | select(.metadata.name == $n)] | length == 1 and (.[0] |
        (.spec.validationActions | index("Audit") != null and index("Deny") == null)
        and .spec.failurePolicy == "Ignore"
        and ((.status.conditionStatus.ready // false) | tostring) == "true")' --arg n "$_m26d_e07_pol"
done
# _m26d_e07_aucune_ancienne — aucune ClusterPolicy ni Policy de kyverno.io dans le cluster.
_m26d_e07_aucune_ancienne() {
  local liste
  liste="$(kube get clusterpolicies.kyverno.io,policies.kyverno.io -A -o name 2>/dev/null)" || return 1
  [[ -z "$liste" ]]
}
if _m26d_lisible clusterpolicies.kyverno.io; then
  check_cmd "Aucune ClusterPolicy ni Policy (types dépréciés en 1.19, supprimés en 1.20)" _m26d_e07_aucune_ancienne
else
  skip "Absence de ClusterPolicy" "type illisible par le compte des checks (règle kyverno.io de wb-checks-securite)"
fi

# --- 4. Les rapports -----------------------------------------------------------------------------------
_m26d_e07_rap="$(_m26d_k get policyreports.wgpolicyk8s.io -A -o json)"
if [[ -z "$_m26d_e07_rap" ]]; then
  _ko "PolicyReport illisibles par le compte des checks (règle wgpolicyk8s.io de wb-checks-securite ?)"
else
  for _m26d_e07_pol in registres-autorises exiger-etiquettes; do
    check_cmd "PolicyReport : résultats de l'analyse pour $_m26d_e07_pol" \
      _m26d_json "$_m26d_e07_rap" '[.items[].results[]? | select(.policy == $n)] | length > 0' --arg n "$_m26d_e07_pol"
  done
fi

# --- 5. Le dépôt et ses tests -----------------------------------------------------------------------
check_cmd "plateforme/politiques : un test kyverno par politique (kyverno/tests/<politique>/kyverno-test.yaml)" \
  bash -c '[ -n "$1" ] && [ -n "$2" ]' _ \
  "$(_m26d_contenu_main plateforme/politiques kyverno/tests/registres-autorises/kyverno-test.yaml)" \
  "$(_m26d_contenu_main plateforme/politiques kyverno/tests/exiger-etiquettes/kyverno-test.yaml)"
check_cmd "plateforme/politiques : kustomization.yaml sans ressource de test" \
  bash -c '[ -n "$1" ] && ! grep -q "tests/" <<<"$1"' _ "$(_m26d_contenu_main plateforme/politiques kustomization.yaml)"
check_output "plateforme/politiques : dernier pipeline de main réussi (kyverno test)" '^success$' \
  _m26d_pipeline_main plateforme/politiques
