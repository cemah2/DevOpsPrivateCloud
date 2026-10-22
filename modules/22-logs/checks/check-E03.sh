# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E03.sh — M22-E03 : Alloy dans le cluster : pods et nœuds
# À lancer depuis adm01. Lecture seule : Application et DaemonSet (« kube »), requêtes LogQL sur les
# 15 dernières minutes par locataire, noms d'étiquettes indexées (API labels de Loki).

# shellcheck source=_m22-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-decouverte.sh"

title "M22-E03 — Alloy dans le cluster : pods et nœuds"
require_cmd jq kubectl curl

# --- 1. Déploiement ----------------------------------------------------------------------------------------
_m22d_e03_app="$(_m22d_app alloy)"
check_cmd "Application Argo CD alloy : chart de Harbor, synchronisée et saine" _m22d_json "$_m22d_e03_app" \
  "any((.spec.sources // [.spec.source])[]; (.repoURL | test(\"registry\\\\.par1\\\\.medisphere\\\\.internal/charts\")) and .chart == \"alloy\") and $_M22D_APP_SAINE"
_m22d_e03_ds="$(_m22d_k get daemonsets -n "$_M22D_NS" -l app.kubernetes.io/name=alloy -o json)"
_m22d_e03_noeuds="$(_m22d_k get nodes -o json | jq -r '.items | length' 2>/dev/null || true)"
_m22d_e03_noeuds="${_m22d_e03_noeuds:-0}"
check_cmd "DaemonSet Alloy : un pod prêt sur CHACUN des ${_m22d_e03_noeuds} nœuds (contrôle et k8s-w03 compris)" _m22d_json "$_m22d_e03_ds" \
  '(.items | length) == 1 and .items[0].status.desiredNumberScheduled == ($n | tonumber)
   and .items[0].status.numberReady == ($n | tonumber)' --arg n "$_m22d_e03_noeuds"
check_cmd "Alloy : positions de lecture sur le disque du nœud (hostPath), pas dans un emptyDir" _m22d_json "$_m22d_e03_ds" \
  '.items[0].spec.template.spec as $s
   | ($s.containers[] | select(.name == "alloy") | .args | map(select(startswith("--storage.path="))) | .[0] // "" | sub("--storage.path="; "")) as $p
   | ($p | startswith("/tmp") | not) and any($s.volumes[]; has("hostPath") and (.hostPath.path | startswith("/var/lib/alloy")))'
check_cmd "Alloy : /var/log du nœud monté en lecture seule" _m22d_json "$_m22d_e03_ds" \
  'any(.items[0].spec.template.spec.containers[] | select(.name == "alloy") | .volumeMounts[]; .mountPath == "/var/log" and .readOnly == true)'
check_cmd "Alloy : limite de mémoire déclarée" _m22d_json "$_m22d_e03_ds" \
  '.items[0].spec.template.spec.containers[] | select(.name == "alloy") | .resources.limits.memory != null'
check_cmd "Alloy : ses droits ne lisent pas les Secrets" _m22d_json \
  "$(_m22d_k get clusterroles -l app.kubernetes.io/name=alloy -o json)" \
  '(.items | length) >= 1 and ([.items[].rules[]? | select((.resources // []) | index("secrets"))] | length == 0)'
check_cmd "configuration dans Git (ConfigMap alloy-config générée, pas de contenu collé dans les values)" _m22d_json \
  "$(_m22d_k get configmap alloy-config -n "$_M22D_NS" -o json)" '.data["config.alloy"] | test("loki.write")'

# --- 2. Flux reçus par locataire (15 dernières minutes) ------------------------------------------------
check_cmd "plateforme : journaux des pods de kube-system et de journaux" bash -c '[[ "$1" -ge 2 ]]' _ \
  "$(_m22d_nb_resultats 'sum by (namespace) (count_over_time({job="pods", namespace=~"kube-system|journaux"}[15m]))' plateforme 15m)"
check_cmd "plateforme : journal systemd de chacun des ${_m22d_e03_noeuds} nœuds (job=journald, étiquette node)" bash -c '[[ "$2" -ge 1 && "$1" -ge "$2" ]]' _ \
  "$(_m22d_nb_resultats 'sum by (node) (count_over_time({job="journald", node=~"k8s-.+"}[15m]))' plateforme 15m)" "$_m22d_e03_noeuds"
check_cmd "mediagenda : journaux des pods des espaces mediagenda-*" bash -c '[[ "$1" -ge 1 ]]' _ \
  "$(_m22d_nb_resultats 'sum by (namespace) (count_over_time({namespace=~"mediagenda-.+"}[15m]))' mediagenda 15m)"
check_cmd "medidoc : journaux des pods des espaces medidoc-* depuis 2 h (MédiDoc n'écrit qu'aux vraies requêtes)" bash -c '[[ "$1" -ge 1 ]]' _ \
  "$(_m22d_nb_resultats 'sum by (namespace) (count_over_time({namespace=~"medidoc-.+"}[2h]))' medidoc 2h)"
# Contrôle d'absence : n'a de sens que si les journaux des équipes arrivent bien quelque part.
if [[ "$(_m22d_nb_resultats '{namespace=~"mediagenda-.+"}' mediagenda 15m)" -ge 1 ]]; then
  check_cmd "cloisonnement : aucun journal de mediagenda-* ni medidoc-* dans le locataire plateforme" bash -c '[[ "$1" -eq 0 ]]' _ \
    "$(_m22d_nb_resultats 'sum by (namespace) (count_over_time({namespace=~"(mediagenda|medidoc)-.+"}[15m]))' plateforme 15m)"
else
  skip "cloisonnement des locataires" "aucun journal de mediagenda-* reçu : contrôle sans objet"
fi

# --- 3. Liste fermée d'étiquettes -------------------------------------------------------------------------
for _m22d_e03_t in plateforme mediagenda medidoc; do
  _m22d_e03_hors="$(_m22d_hors_liste "$_m22d_e03_t" 15m)"
  check_cmd "$_m22d_e03_t : aucune étiquette indexée hors liste (${_m22d_e03_hors:-aucune})" bash -c '[[ -z "$1" ]]' _ "$_m22d_e03_hors"
done
check_cmd "plateforme : le nom du pod est une métadonnée structurée, pas une étiquette" bash -c '[[ "$1" -ge 1 ]]' _ \
  "$(_m22d_nb_resultats '{namespace="journaux", container="loki"} | pod=~"loki-.+"' plateforme 15m)"
