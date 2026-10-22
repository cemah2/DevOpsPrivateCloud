#!/usr/bin/env bash
# kubescape-resume.sh — M26-E05 (SEC-2705) : extrait d'un rapport JSON de kubescape 4 un résumé
# publiable (scores par cadre, contrôles en échec et nombre de ressources), sans noms d'objets ni
# d'images. Le rapport complet reste dans ~/m26/e05/ (non versionné).
#
# Usage : kubescape-resume.sh kubescape.json > kubescape-resume.json
# Champs lus (kubescape 4.0, sortie --format json) : .summaryDetails.frameworks[] (name,
# complianceScore) et .summaryDetails.controls (controlID, name, severity, status,
# ResourceCounters.failedResources).
set -euo pipefail

[[ $# -eq 1 && -r "$1" ]] || { echo "Usage : $0 <rapport kubescape.json>" >&2; exit 2; }

jq --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
  genere: $date,
  outil: "kubescape",
  cadres: [.summaryDetails.frameworks[] | {nom: .name, score: (.complianceScore | . * 10 | round / 10)}],
  score_global: (.summaryDetails.complianceScore | . * 10 | round / 10),
  controles_en_echec: (
    [.summaryDetails.controls | to_entries[] | .value
     | select(.status == "failed")
     | {id: .controlID, nom: .name, gravite: .severity,
        ressources_en_echec: .ResourceCounters.failedResources}]
    | sort_by(-.ressources_en_echec))
}' "$1"
