#!/usr/bin/env bash
# plateforme/k8s — outils/controles-montee.sh (F4-S04, CHG-3404, RB-341)
# Contrôles en LECTURE avant une montée et avant chaque drain. Rien n'est modifié.
#
#   outils/controles-montee.sh avant              # santé globale, juste avant le go
#   outils/controles-montee.sh noeud k8s-w02      # avant de drainer CE nœud
#   outils/controles-montee.sh api 1.37           # API dépréciées appelées qui disparaissent en 1.37
#
# Code de sortie : 0 si tout est vert, 1 sinon (chaque problème est affiché).
# Prérequis : kubectl (identité de la plateforme), jq, curl ; Thanos Query joignable pour « api ».
set -euo pipefail

PROM="${PROM_URL:-http://prometheus.apps.par1.medisphere.internal:9090}"
ko=0
probleme() { printf '  [KO] %s\n' "$*"; ko=1; }
bon() { printf '  [OK] %s\n' "$*"; }

avant() {
  echo "== Nœuds"
  if kubectl get nodes -o json | jq -e 'all(.items[]; (.spec.unschedulable // false) == false and any(.status.conditions[]; .type == "Ready" and .status == "True"))' >/dev/null; then
    bon "tous Ready, aucun cordonné"
  else
    probleme "un nœud n'est pas Ready ou est déjà cordonné"
  fi
  echo "== PDB qui n'autorisent aucune perturbation (hors primaire CNPG, attendu)"
  kubectl get pdb -A -o json | jq -r '.items[]
    | select((.status.disruptionsAllowed // 0) == 0)
    | select(any(.metadata.ownerReferences[]?; .apiVersion | startswith("postgresql.cnpg.io")) | not)
    | "\(.metadata.namespace)/\(.metadata.name) (attendus \(.status.expectedPods // "?"), sains \(.status.currentHealthy // "?"), requis \(.status.desiredHealthy // "?"))"' |
    while IFS= read -r l; do printf '  [KO] PDB bloquante : %s\n' "$l"; done
  if kubectl get pdb -A -o json | jq -e '[.items[] | select((.status.disruptionsAllowed // 0) == 0)
      | select(any(.metadata.ownerReferences[]?; .apiVersion | startswith("postgresql.cnpg.io")) | not)] | length == 0' >/dev/null; then
    bon "toutes les PDB autorisent au moins une éviction"
  else
    ko=1
  fi
  echo "== Webhooks d'admission « Fail » et leurs points d'accès"
  local ns svc
  while read -r ns svc; do
    [[ -n "$svc" ]] || continue
    if kubectl -n "$ns" get endpointslices -l "kubernetes.io/service-name=$svc" -o json |
      jq -e '[.items[].endpoints[]? | select(.conditions.ready != false)] | length > 0' >/dev/null; then
      bon "$ns/$svc a des points d'accès prêts"
    else
      probleme "webhook vers $ns/$svc sans point d'accès prêt : toute admission visée sera refusée"
    fi
  done < <(kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -o json |
    jq -r '.items[].webhooks[]? | select((.failurePolicy // "Fail") == "Fail") | .clientConfig.service | select(. != null) | "\(.namespace) \(.name)"' | sort -u)
  echo "== Argo CD"
  if kubectl -n argocd get applications.argoproj.io -o json | jq -e 'all(.items[]; .status.sync.status == "Synced" and .status.health.status == "Healthy")' >/dev/null; then
    bon "toutes les Applications Synced et Healthy"
  else
    kubectl -n argocd get applications.argoproj.io -o json | jq -r '.items[] | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")
      | "  [KO] \(.metadata.name) : \(.status.sync.status) / \(.status.health.status)"'
    ko=1
  fi
  echo "== CloudNativePG"
  kubectl get clusters.postgresql.cnpg.io -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) \(.status.readyInstances // 0)/\(.spec.instances) \(.status.phase // "?")"' |
    while read -r n r p; do
      if [[ "$p" =~ [Hh]ealthy && "${r%/*}" == "${r#*/}" ]]; then bon "$n $r $p"; else printf '  [KO] %s %s %s\n' "$n" "$r" "$p"; fi
    done
  kubectl get clusters.postgresql.cnpg.io -A -o json |
    jq -e 'all(.items[]; ((.status.phase // "") | test("healthy"; "i")) and (.status.readyInstances // 0) == .spec.instances)' >/dev/null || ko=1
  echo "== Grappe RabbitMQ (aucune file quorum critique)"
  if kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-queues check_if_node_is_quorum_critical >/dev/null 2>&1; then
    bon "rabbitmq-server-0 : l'arrêt d'un nœud ne ferait perdre le quorum d'aucune file"
  else
    probleme "RabbitMQ : une file quorum est critique (ou la commande a échoué) — voir le runbook de la grappe RabbitMQ (M27, docs/donnees/runbooks/)"
  fi
  return "$ko"
}

noeud() {
  local n="$1"
  echo "== Pods de $n (hors DaemonSets)"
  kubectl get pods -A --field-selector "spec.nodeName=$n" -o json | jq -r '.items[]
    | select(any(.metadata.ownerReferences[]?; .kind == "DaemonSet") | not)
    | "\(.metadata.namespace) \(.metadata.name) \(.metadata.labels["cnpg.io/instanceRole"] // "-")"' |
    while read -r ns pod role; do
      printf '  %s/%s%s\n' "$ns" "$pod" "$([[ "$role" == primary ]] && echo '   ← PRIMAIRE CNPG : bascule automatique au cordon (à suivre)')"
    done
  echo "== PDB qui couvrent ces pods et n'autorisent aucune éviction"
  local pods pdbs
  pods="$(kubectl get pods -A --field-selector "spec.nodeName=$n" -o json)"
  pdbs="$(kubectl get pdb -A -o json)"
  jq -r --argjson pdbs "$pdbs" '.items[] | . as $p
    | [$pdbs.items[] | select(.metadata.namespace == $p.metadata.namespace)
       | select((.spec.selector.matchLabels // {}) | to_entries | all(.key as $k | .value as $v | ($p.metadata.labels // {})[$k] == $v))
       | select((.spec.selector.matchExpressions // []) == [])] as $m
    | if ($m | length) > 1 then "  [KO] \($p.metadata.namespace)/\($p.metadata.name) : \($m | length) PDB (l'\''éviction refuse un pod couvert par plusieurs PDB)"
      elif ($m | length) == 1 and (($m[0].status.disruptionsAllowed // 0) == 0)
           and (any($m[0].metadata.ownerReferences[]?; .apiVersion | startswith("postgresql.cnpg.io")) | not)
      then "  [KO] \($p.metadata.namespace)/\($p.metadata.name) : PDB \($m[0].metadata.name) n'\''autorise aucune éviction"
      else empty end' <<<"$pods" | tee /dev/stderr | grep -q . && ko=1
  echo "== Pods sans contrôleur (perdus au drain) ou à une seule réplique"
  jq -r '.items[] | select(any(.metadata.ownerReferences[]?; .kind == "DaemonSet") | not)
    | select((.metadata.ownerReferences // []) == []) | "  [!!] \(.metadata.namespace)/\(.metadata.name) : aucun contrôleur, il ne reviendra pas"' <<<"$pods"
  ((ko == 0)) && bon "$n peut être drainé"
  return "$ko"
}

api() {
  local cible="$1" r
  echo "== API dépréciées appelées (7 j) qui disparaissent en $cible"
  r="$(curl -sf --max-time 30 --data-urlencode "query=sum by (group, version, resource) (max_over_time(apiserver_requested_deprecated_apis{removed_release=\"$cible\"}[7d]))" \
    "$PROM/api/v1/query")" || { probleme "Prometheus injoignable ($PROM)"; return 1; }
  if jq -e '.data.result | length == 0' >/dev/null <<<"$r"; then
    bon "aucune"
  else
    jq -r '.data.result[].metric | "  [KO] \(.group // "core")/\(.version) \(.resource)"' <<<"$r"
    echo "  qui les appelle : journal d'audit (Loki, locataire audit) filtré sur l'annotation k8s.io/deprecated"
    ko=1
  fi
  return "$ko"
}

case "${1:-}" in
  avant) avant ;;
  noeud) [[ -n "${2:-}" ]] || { echo "Usage : $0 noeud <NOM>" >&2; exit 2; }; noeud "$2" ;;
  api) [[ "${2:-}" =~ ^1\.[0-9]+$ ]] || { echo "Usage : $0 api <MINEURE>  (ex. 1.37)" >&2; exit 2; }; api "$2" ;;
  *) echo "Usage : $0 avant | noeud <NOM> | api <MINEURE>" >&2; exit 2 ;;
esac
