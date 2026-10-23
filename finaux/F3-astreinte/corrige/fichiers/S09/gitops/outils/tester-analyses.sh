#!/usr/bin/env bash
# outils/tester-analyses.sh — plateforme/gitops (F3-S09, INC-5909, PLAT-3309)
# Rejoue chaque requête Prometheus des ClusterAnalysisTemplate du dépôt, arguments remplacés par ceux
# d'un Rollout RÉEL (espace, hachage de la révision stable), et échoue si une requête ne renvoie rien.
# Une requête vide met la mesure en ERREUR et fait abandonner tout canary, même sain (INC-5909).
# À lancer depuis adm01 (Prometheus 10.10.41.60 n'est joignable que depuis MGMT et mon01) avant de
# fusionner une MR qui touche analyses/, et chaque nuit par la minuterie de mon01 (PLAT-3309-b).
# Usage : outils/tester-analyses.sh [ESPACE=mediagenda-recette] [DOSSIER=analyses]
# Requiert : kubectl (lecture des Rollouts), yq (mikefarah), jq, curl.
set -euo pipefail

espace="${1:-mediagenda-recette}"
dossier="${2:-analyses}"
prom="${PROM_URL:-http://prometheus.apps.par1.medisphere.internal:9090}"

hachage="$(kubectl -n "$espace" get rollouts.argoproj.io mediagenda -o jsonpath='{.status.stableRS}')"
[[ -n "$hachage" ]] || { echo "hachage stable introuvable (Rollout mediagenda de $espace)" >&2; exit 2; }

echec=0
while IFS= read -r f; do
  while IFS=$'\t' read -r gabarit mesure requete; do
    q="$(sed -e "s/{{args.namespace}}/$espace/g" -e "s/{{args.hash-canary}}/$hachage/g" <<<"$requete")"
    n="$(curl -sf --max-time 20 --data-urlencode "query=$q" "$prom/api/v1/query" | jq '.data.result | length')" || n="erreur"
    if [[ "$n" =~ ^[1-9][0-9]*$ ]]; then
      echo "OK      $gabarit/$mesure ($n série(s))"
    else
      echo "ÉCHEC   $gabarit/$mesure : la requête ne renvoie rien ($n) avec namespace=$espace, hash=$hachage" >&2
      echec=1
    fi
  done < <(yq -o=json '.' "$f" | jq -r 'select(.kind == "ClusterAnalysisTemplate" or .kind == "AnalysisTemplate")
            | .metadata.name as $g | .spec.metrics[] | select(.provider.prometheus.query)
            | [$g, .name, (.provider.prometheus.query | gsub("\n"; " "))] | @tsv')
done < <(find "$dossier" -name '*.yaml' -o -name '*.yml')
exit "$echec"
