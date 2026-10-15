#!/usr/bin/env bash
# helm-release.sh — décode une révision de release Helm SANS en afficher les valeurs (M17-E23, PLAT-1837).
#
# Usage : outils/helm-release.sh [--pilote secret|configmap] <espace> <release> [révision]
#   Sans révision : la plus haute révision stockée. Sans --pilote : HELM_DRIVER, sinon détection
#   (Secrets puis ConfigMaps portant owner=helm,name=<release>).
# Sortie : JSON — statut, dates, description, chart, méthode d'application, objets du manifeste,
#   hooks, et les CLÉS de premier niveau des valeurs fournies (jamais leurs valeurs).
# Droits : lire les Secrets (ou ConfigMaps) de l'espace. Lecture seule.
set -euo pipefail

pilote="${HELM_DRIVER:-}"
if [[ "${1:-}" == "--pilote" ]]; then
  pilote="${2:-}"
  shift 2
fi
if (($# < 2)); then
  echo "usage : $0 [--pilote secret|configmap] <espace> <release> [révision]" >&2
  exit 2
fi
ns="$1" rel="$2" rev="${3:-}"
for c in kubectl jq base64 gzip; do
  command -v "$c" >/dev/null 2>&1 || { echo "outil manquant : $c" >&2; exit 2; }
done

lister() { # lister secret|configmap — « version nom » des révisions stockées
  kubectl get "$1" -n "$ns" -l "owner=helm,name=$rel" \
    -o jsonpath='{range .items[*]}{.metadata.labels.version} {.metadata.name}{"\n"}{end}' 2>/dev/null | sort -n
}

case "$pilote" in
  secret | secrets) pilote=secret ;;
  configmap | configmaps) pilote=configmap ;;
  "") if [[ -n "$(lister secret)" ]]; then pilote=secret; else pilote=configmap; fi ;;
  *) echo "pilote non pris en charge : $pilote (secret ou configmap ; le pilote sql n'est pas lu ici)" >&2; exit 2 ;;
esac

revisions="$(lister "$pilote")"
[[ -n "$revisions" ]] || { echo "aucune révision de $ns/$rel (pilote $pilote)" >&2; exit 1; }
if [[ -z "$rev" ]]; then
  nom="$(tail -n1 <<<"$revisions" | cut -d' ' -f2)"
else
  nom="$(awk -v r="$rev" '$1 == r { print $2 }' <<<"$revisions")"
  [[ -n "$nom" ]] || { echo "révision $rev absente de $ns/$rel" >&2; exit 1; }
fi

# Secret : base64 de l'API (jsonpath renvoie .data encodé) puis base64 de Helm ; ConfigMap : base64 de Helm.
brut="$(kubectl get "$pilote" "$nom" -n "$ns" -o jsonpath='{.data.release}')"
if [[ "$pilote" == secret ]]; then
  brut="$(base64 -d <<<"$brut")"
fi
if ! json="$(base64 -d <<<"$brut" 2>/dev/null | gzip -dc 2>/dev/null)" || ! jq -e . >/dev/null 2>&1 <<<"$json"; then
  echo "révision $nom illisible (contenu tronqué ou corrompu)" >&2
  exit 1
fi

jq --arg stockage "$pilote/$nom" '{
  stockage: $stockage,
  release: .name, espace: .namespace, revision: .version,
  statut: .info.status, description: .info.description,
  premier_deploiement: .info.first_deployed, dernier_deploiement: .info.last_deployed,
  chart: {nom: .chart.metadata.name, version: .chart.metadata.version, appVersion: .chart.metadata.appVersion},
  methode_application: (.apply_method // "inconnue (client-side, révision antérieure à Helm 4)"),
  cles_valeurs_fournies: ((.config // {}) | keys),
  objets: [(.manifest // "") | split("\n---") | .[]
           | capture("(?m)^kind: (?<kind>\\S+)[\\s\\S]*?^  name: (?<name>\\S+)")? | "\(.kind)/\(.name)"],
  hooks: [(.hooks // [])[] | {nom: .name, genre: .kind, evenements: .events, derniere_execution: .last_run.phase}]
}' <<<"$json"
