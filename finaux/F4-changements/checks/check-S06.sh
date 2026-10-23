# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S06.sh — F4-S06 « Panne : la montée qui bloque » (BF) : état sain après réparation, quelle que
# soit la variante injectée — aucun nœud cordonné, aucune PDB d'un espace applicatif qui interdit toute
# éviction (hors PDB de CloudNativePG), aucun webhook d'admission « Fail » sans point d'accès prêt, aucune
# Application Argo CD en erreur, aucune API retirée dans mediagenda/deploiement ; post-mortem INC-6006.
# Lecture seule.

# shellcheck source=_f4-montees.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-montees.sh"

title "F4-S06 — Panne : la montée qui bloque"
require_cmd kubectl curl jq yq

if ! _f4m_api_repond; then
  skip "état du cluster" "l'API ne répond pas au compte des checks"
else
  check_cmd "tous les nœuds Ready, aucun cordonné" _f4m_noeuds_sains
  check_cmd "aucune PDB d'un espace applicatif n'interdit toute éviction (hors PDB gérées par CloudNativePG)" _f4m_kq \
    '[.items[] | select(.metadata.namespace | test("^(mediagenda|medidoc|medinotif|legacy)-"))
      | select(any(.metadata.ownerReferences[]?; .apiVersion | startswith("postgresql.cnpg.io")) | not)
      | select((.spec.maxUnavailable // "x" | tostring) == "0" or (.spec.maxUnavailable // "x" | tostring) == "0%"
               or (.spec.minAvailable // "x" | tostring) == "100%")] | length == 0' pdb -A

  _f4_s06_webhooks() {
    local j svc ns
    j="$(kube get validatingwebhookconfigurations,mutatingwebhookconfigurations -o json 2>/dev/null)" || return 2
    while IFS=' ' read -r ns svc; do
      [[ -n "$svc" ]] || continue
      kube get endpointslices -n "$ns" -l "kubernetes.io/service-name=$svc" -o json 2>/dev/null |
        jq -e '[.items[].endpoints[]? | select(.conditions.ready != false)] | length > 0' >/dev/null 2>&1 || return 1
    done < <(jq -r '.items[].webhooks[]? | select((.failurePolicy // "Fail") == "Fail") | .clientConfig.service
      | select(. != null) | "\(.namespace) \(.name)"' <<<"$j" | sort -u)
    return 0
  }
  _f4_s06_rc=0
  _f4_s06_webhooks || _f4_s06_rc=$?
  if ((_f4_s06_rc == 2)); then
    skip "webhooks d'admission" "le compte des checks ne lit pas les configurations de webhooks"
  else
    check_cmd "webhooks d'admission « Fail » : chacun a au moins un point d'accès prêt" test "$_f4_s06_rc" -eq 0
  fi
  check_cmd "Argo CD : aucune Application en erreur de comparaison ou de synchronisation" _f4m_kq \
    '[.items[] | select(any(.status.conditions[]?; .type | test("ComparisonError|SyncError|InvalidSpecError")))
      | select(.status.operationState.phase? != "Running")] | length == 0' -n argocd applications.argoproj.io
fi

_f4_s06_depot="${WB_F4_PROJET_DEPLOIEMENT:-mediagenda/deploiement}"
_f4_s06_apis_retirees() {
  local f c n=0
  while IFS= read -r f; do
    [[ "$f" =~ \.ya?ml$ ]] || continue
    c="$(_f4m_fichier "$_f4_s06_depot" "$f" 2>/dev/null)" || continue
    n=$((n + 1))
    grep -Eq '^apiVersion:[[:space:]]*(policy/v1beta1|autoscaling/v2beta[12]|batch/v1beta1|extensions/v1beta1|networking\.k8s\.io/v1beta1|flowcontrol\.apiserver\.k8s\.io/v1beta[123]|discovery\.k8s\.io/v1beta1|events\.k8s\.io/v1beta1)[[:space:]]*$' <<<"$c" && return 1
  done < <(_f4m_arbre "$_f4_s06_depot")
  # Dépôt illisible ou vide : rien n'a été vérifié, ce n'est pas un succès.
  ((n > 0))
}
check_cmd "$_f4_s06_depot (main) : aucun manifeste dans une version d'API retirée" _f4_s06_apis_retirees
check_cmd "post-mortem INC-6006 publié : symptôme, cause, détection, prévention" \
  _f4m_doc post-mortems '^INC-6006' 'cause' 'pr(é|e)vention|action' 'drain|admission|api'
