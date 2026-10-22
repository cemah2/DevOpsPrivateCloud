# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E33.sh — M20-E33 « Accueillir MédiDoc en GitOps » (DEV-2133)
# À lancer depuis adm01. Lecture seule : espace medidoc-recette et ses garde-fous, pods, Applications
# (wb-checks) ; arbre et fichiers de medidoc/deploiement sur main (GitLab) ; documentation sur main.

# shellcheck source=_m20-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-production.sh"

title "M20-E33 — Accueillir MédiDoc en GitOps"
require_cmd kubectl jq
check_cmd "l'API du cluster répond (readyz)" _m20p_joignable

title "Espace medidoc-recette (plateforme)"
_m20_e33_ns="$(_m20p_json get namespace medidoc-recette)"
check_cmd "étiquette d'équipe medidoc et Pod Security restricted (enforce)" _m20p_jq "$_m20_e33_ns" \
  '.metadata.labels["medisphere.internal/equipe"] == "medidoc"
   and .metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"'
check_cmd "un ResourceQuota" _m20p_jq "$(_m20p_json -n medidoc-recette get resourcequotas)" '(.items | length) > 0'
check_cmd "un LimitRange avec des valeurs par défaut pour les conteneurs" _m20p_jq "$(_m20p_json -n medidoc-recette get limitranges)" \
  'any(.items[].spec.limits[]; .type == "Container" and (.defaultRequest | type) == "object")'
check_cmd "refus réseau par défaut en entrée et en sortie" _m20p_jq "$(_m20p_json -n medidoc-recette get networkpolicies)" \
  'any(.items[]; (.spec.podSelector | length) == 0 and ((.spec.policyTypes // []) | index("Ingress") and index("Egress"))
       and ((.spec.ingress // []) | length) == 0 and ((.spec.egress // []) | length) == 0)'

title "Applications"
for _m20_e33_env in dev recette; do
  _m20_e33_app="$(_m20p_app "medidoc-$_m20_e33_env")"
  check_cmd "medidoc-$_m20_e33_env générée par l'ApplicationSet medidoc, projet medidoc" _m20p_jq "$_m20_e33_app" \
    'any(.metadata.ownerReferences[]?; .kind == "ApplicationSet" and .name == "medidoc") and .spec.project == "medidoc"'
  check_cmd "medidoc-$_m20_e33_env : destination medidoc-$_m20_e33_env, synchronisation automatique" _m20p_jq "$_m20_e33_app" \
    ".spec.destination.namespace == \"medidoc-$_m20_e33_env\" and (.spec.syncPolicy.automated | type) == \"object\""
  check_cmd "medidoc-$_m20_e33_env Synced/Healthy" _m20p_app_saine "$_m20_e33_app"
done
check_cmd "AppProject medidoc : destinations limitées à medidoc-dev et medidoc-recette" _m20p_jq "$(_m20p_projet medidoc)" \
  '(.spec.destinations | length) > 0 and all(.spec.destinations[]; .namespace | IN("medidoc-dev", "medidoc-recette"))'

title "MédiDoc recette tourne"
check_cmd "un pod MédiDoc prêt dans medidoc-recette, image du projet medisphere par digest" _m20p_jq \
  "$(_m20p_json -n medidoc-recette get pods)" \
  'any(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True")
       and any(.spec.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/medisphere/medidoc(:[^@]+)?@sha256:[0-9a-f]{64}$")))'

title "Dépôt medidoc/deploiement"
_m20_e33_arbre="$(_m20p_arbre medidoc/deploiement)"
check_output "overlays/recette/kustomization.yaml sur main" '^overlays/recette/kustomization\.ya?ml$' \
  printf '%s\n' "$_m20_e33_arbre"
_m20_e33_secrets() {
  local f
  while IFS= read -r f; do
    [[ "$f" =~ \.(ya?ml|json)$ ]] || continue
    if _m20p_fichier_main medidoc/deploiement "$f" | grep -Eq '^[[:space:]]*"?kind"?[[:space:]]*:[[:space:]]*"?Secret"?[[:space:]]*,?$'; then
      echo "$f"
    fi
  done <<<"$_m20_e33_arbre"
}
_m20_e33_trouves="$(_m20_e33_secrets || true)"
check_output "aucun manifeste « kind: Secret » dans l'arbre de main${_m20_e33_trouves:+ (trouvé dans : $(tr '\n' ' ' <<<"$_m20_e33_trouves"))}" '^ok$' \
  bash -c '[[ -n "$1" && -z "$2" ]] && echo ok' _ "$_m20_e33_arbre" "$_m20_e33_trouves"

title "Documentation"
check_cmd "docs/livraison/gitops/accueil-equipe-gitops.md sur main" \
  _m20p_doc docs/livraison/gitops/accueil-equipe-gitops.md 'ApplicationSet|AppProject'
