# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E17.sh — M15-E17 : Les politiques réseau de MédiAgenda
# À lancer depuis adm01. Lecture seule (kube get, requêtes HTTPS vers la recette, GitLab, journal).
# L'essai latéral (pod de wb-essais vers PostgreSQL) fait partie de l'exercice : le check en lit la
# trace dans ~/m15/e17/ (Hubble), il ne crée aucun pod.

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E17 — Les politiques réseau de MédiAgenda"
require_cmd kubectl jq curl

_m15o_u="https://$_M15O_NOM_MA"

for _m15o_e in mediagenda-dev mediagenda-recette; do
  _m15o_np="$(_m15o_kjson networkpolicies -n "$_m15o_e")"
  _m15o_cnp="$(_m15o_kjson ciliumnetworkpolicies -n "$_m15o_e")"
  check_cmd "$_m15o_e : refus par défaut en entrée ET en sortie (podSelector vide, aucune règle)" _m15o_jq "$_m15o_np" \
    'any(.items[]?; (.spec.podSelector | length) == 0 and ((.spec.policyTypes // []) | sort) == ["Egress","Ingress"] and ((.spec.ingress // []) | length) == 0 and ((.spec.egress // []) | length) == 0)'
  check_cmd "$_m15o_e : sortie DNS vers les seuls pods kube-dns de kube-system" _m15o_jq "$_m15o_np" \
    'any(.items[]?.spec.egress[]?; any(.to[]?; .namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "kube-system" and .podSelector.matchLabels["k8s-app"] == "kube-dns") and any(.ports[]?; .port == 53))'
  check_cmd "$_m15o_e : entrée de l'API depuis l'identité ingress (CiliumNetworkPolicy, règles L7 HTTP)" _m15o_jq "$_m15o_cnp" \
    'any(.items[]?.spec.ingress[]?; ((.fromEntities // []) | index("ingress")) and any(.toPorts[]?; (.rules.http // []) | length > 0))'
  check_cmd "$_m15o_e : aucune autorisation ouverte à tout (sélecteur vide en source/destination, world/all, 0.0.0.0/0)" \
    _m15o_politiques_fermees "$_m15o_np" "$_m15o_cnp"
done

# --- Comportement à travers gw-par1 ------------------------------------------------------------------
check_output "/pret répond 200 (PostgreSQL et Valkey joignables par l'API)" '^200$' _m15o_code "$_m15o_u/pret"
check_output "/api/v1/creneaux?date=… répond 200 (chaîne de requête acceptée par la politique L7)" '^200$' \
  _m15o_code "$_m15o_u/api/v1/creneaux?date=$(date +%F)"
check_output "/metrics est refusé depuis l'extérieur (403 de la politique L7)" '^403$' _m15o_code "$_m15o_u/metrics"
check_output "une méthode non prévue (PUT) est refusée (403)" '^403$' _m15o_code "$_m15o_u/api/v1/rendez-vous/1" -X PUT

# --- Preuves et code ----------------------------------------------------------------------------------
check_cmd "m15/e17/ : une chute vers PostgreSQL de la recette observée dans Hubble" \
  bash -c 'grep -hsE "mediagenda-recette/postgresql[^ ]*:5432.*(DROPPED|DENIED)|(DROPPED|DENIED).*mediagenda-recette/postgresql" "$1"/*' _ "$_M15O_TRAVAIL/e17"
check_cmd "politiques de MédiAgenda dans espaces/ de plateforme/k8s (main)" \
  bash -c '[[ $(grep -c . <<<"$1") -ge 3 ]]' _ "$(_m15o_arbre_main "$_M15O_K8S" espaces | grep -iE 'politi|polic|netpol|cnp' || true)"
check_cmd "matrice des flux docs/kubernetes/reseau/flux-mediagenda.md dans plateforme/medisphere" \
  _m15o_fichier_main "$_M15O_DOC" docs/kubernetes/reseau/flux-mediagenda.md
