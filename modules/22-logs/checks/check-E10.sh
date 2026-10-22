# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E10.sh — M22-E10 : Fluent Bit : un autre collecteur
# À lancer depuis adm01. Lecture seule : trace de l'essai dans Loki (locataire essai, 30 jours),
# comparatif sur main (GitLab), et RETRAIT complet (espace, Application, chart du miroir, règle réseau).

# shellcheck source=_m22-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-operationnel.sh"

title "M22-E10 — Fluent Bit : un autre collecteur"
require_cmd jq kubectl curl

# --- 1. L'essai a eu lieu ------------------------------------------------------------------------------
check_cmd "Loki a reçu des journaux de Fluent Bit dans le locataire essai (job=fluent-bit, 30 j)" bash -c \
  'grep -qx fluent-bit <<<"$1"' _ "$(_m22o_valeurs job essai 720h)"

# --- 2. Le comparatif ------------------------------------------------------------------------------------
_m22o_e10_doc="$(_m22o_contenu_main "$_M22O_P_DOC" docs/observabilite/journaux/comparatif-collecteurs.md)"
check_cmd "plateforme/medisphere (main) : docs/observabilite/journaux/comparatif-collecteurs.md" bash -c '[[ -n "$1" ]]' _ "$_m22o_e10_doc"
check_cmd "le comparatif cite les deux collecteurs et leurs versions (Alloy 1.21, Fluent Bit 5.1)" bash -c \
  'grep -q "1\\.21" <<<"$1" && grep -q "5\\.1" <<<"$1"' _ "$_m22o_e10_doc"
check_cmd "le comparatif donne des mesures (mémoire en Mi ou Mo, CPU en m ou cœur)" bash -c \
  'grep -Eiq "[0-9]+ ?(Mi|Mo|MiB)" <<<"$1" && grep -Eiq "[0-9]+ ?(m\\b|millicœurs|cœur)" <<<"$1"' _ "$_m22o_e10_doc"
check_cmd "le comparatif conclut (section Décision ou Recommandation)" bash -c \
  'grep -Eiq "^#+ .*(décision|recommandation|conclusion)" <<<"$1"' _ "$_m22o_e10_doc"

# --- 3. Le retrait -------------------------------------------------------------------------------------------
# Contrôles d'absence : ils n'ont de sens que si la lecture du cluster fonctionne.
if [[ -z "$(_m22o_k get namespace "$_M22O_NS" -o name)" ]]; then
  skip "retrait de l'essai (espace, Application, droits, règle réseau)" "lecture du cluster impossible avec wb-checks (WB_K8S_KUBECONFIG)"
else
  check_cmd "espace journaux-essai supprimé" bash -c '[[ -z "$1" ]]' _ \
    "$(_m22o_k get namespace journaux-essai -o name)"
  check_cmd "Application Argo CD fluent-bit-essai supprimée" bash -c '[[ -z "$1" ]]' _ \
    "$(_m22o_k get applications.argoproj.io -n argocd fluent-bit-essai -o name)"
  check_cmd "plus aucune ClusterRole de Fluent Bit" _m22o_json "$(_m22o_k get clusterroles -o json)" \
    '[.items[] | select(.metadata.name | test("fluent-bit"))] | length == 0'
  check_cmd "CNP loki-entree : plus de règle pour journaux-essai" _m22o_json \
    "$(_m22o_k get ciliumnetworkpolicies.cilium.io -n "$_M22O_NS" loki-entree -o json)" \
    '[.spec.ingress[]?.fromEndpoints[]?.matchLabels["io.kubernetes.pod.namespace"] // empty] | index("journaux-essai") == null'
fi
_m22o_e10_miroir="$(_m22o_contenu_main projects/plateforme%2Fcharts-miroir charts.yaml)"
if [[ -n "$_m22o_e10_miroir" ]]; then
  check_cmd "plateforme/charts-miroir : plus de chart fluent-bit dans charts.yaml" bash -c '! grep -q "fluent-bit" <<<"$1"' _ "$_m22o_e10_miroir"
else
  skip "chart fluent-bit retiré du miroir" "charts.yaml illisible sur main de plateforme/charts-miroir"
fi
