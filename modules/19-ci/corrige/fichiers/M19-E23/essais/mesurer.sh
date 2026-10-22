#!/usr/bin/env bash
# mesurer.sh — M19-E23 (DEV-2023) : durée des N derniers pipelines de MR réussis d'un projet, par job.
# Usage : ~/m19/e23/mesurer.sh [projet] [N]     (défaut : mediagenda/api 5)
# Sortie : par pipeline, durée totale, attente, chemin critique estimé ; par job (agrégé sur les N
# pipelines), durée et attente médianes ; enfin la médiane des durées des pipelines.
# Lecture seule : jeton read_api des checks (~/.config/workbook/gitlab-checks.token).
set -euo pipefail

projet="${1:-mediagenda/api}"
n="${2:-5}"
GL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4"
jeton="${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
p="$(jq -rn --arg v "$projet" '$v | @uri')"
api() { curl -sSf -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<"$jeton")") "$GL/$1"; }
# mediane : lit des nombres (un par ligne) sur l'entrée standard.
mediane() { sort -n | awk '{v[NR]=$1} END {if (NR == 0) {print "-"} else if (NR % 2) {print v[(NR+1)/2]} else {printf "%.0f\n", (v[NR/2]+v[NR/2+1])/2}}'; }

travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT
api "projects/$p/pipelines?source=merge_request_event&status=success&order_by=id&sort=desc&per_page=$n" > "$travail/pipelines.json"
nb="$(jq length "$travail/pipelines.json")"
((nb > 0)) || { echo "aucun pipeline de MR réussi pour $projet" >&2; exit 1; }

printf '%-10s %-8s %-8s %s\n' pipeline durée attente "job le plus long (fin la plus tardive)"
for id in $(jq -r '.[].id' "$travail/pipelines.json"); do
  api "projects/$p/pipelines/$id" > "$travail/p-$id.json"
  api "projects/$p/pipelines/$id/jobs?per_page=100&scope[]=success" > "$travail/j-$id.json"
  dernier="$(jq -r 'max_by(.finished_at) | "\(.name) (\(.duration | floor) s)"' "$travail/j-$id.json")"
  printf '%-10s %-8s %-8s %s\n' "$id" \
    "$(jq -r '.duration // 0 | floor' "$travail/p-$id.json")s" \
    "$(jq -r '.queued_duration // 0 | floor' "$travail/p-$id.json")s" "$dernier"
done

echo
printf '%-34s %-14s %s\n' job "durée médiane" "attente médiane"
jq -r '.[] | .name' "$travail"/j-*.json | sort -u | while read -r job; do
  d="$(jq -r --arg j "$job" '.[] | select(.name == $j) | .duration // 0 | floor' "$travail"/j-*.json | mediane)"
  a="$(jq -r --arg j "$job" '.[] | select(.name == $j) | .queued_duration // 0 | floor' "$travail"/j-*.json | mediane)"
  printf '%-34s %-14s %s\n' "$job" "${d}s" "${a}s"
done

echo
echo "Médiane des durées des $nb pipelines de MR : $(jq -r '.duration // 0 | floor' "$travail"/p-*.json | mediane) s"
