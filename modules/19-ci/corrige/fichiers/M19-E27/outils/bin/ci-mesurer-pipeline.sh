#!/usr/bin/env bash
# plateforme/outils — bin/ci-mesurer-pipeline.sh (M19-E27, PLAT-2027).
# Mesure un pipeline par l'API : pour chaque job, attente (queued_duration), durée, runner, puis
# médiane et 95e centile de l'attente. Lecture seule.
# Usage : ci-mesurer-pipeline.sh PROJET ID_PIPELINE [MOTIF_DE_NOM_DE_JOB]
#   ex.   ci-mesurer-pipeline.sh formation/ci-labo 4321 '^charge '
# Le gestionnaire précis (system_id) n'est pas dans l'API des jobs : il est lu dans la première
# ligne du journal de chaque job (« Running with gitlab-runner … on <runner> <system_id> »), si
# MESURER_GESTIONNAIRE=1 (une requête de plus par job).
set -euo pipefail

GITLAB_URL="${GITLAB_URL:-${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}}"
JETON="${GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
(( $# >= 2 )) || { echo "usage : $0 PROJET ID_PIPELINE [MOTIF]" >&2; exit 2; }
projet="${1//\//%2F}" pipeline="$2" motif="${3:-.}"

api() {
  curl -sSf --max-time 30 -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<"$JETON")") "$GITLAB_URL/api/v4/$1"
}

jobs="$(api "projects/$projet/pipelines/$pipeline/jobs?per_page=100&include_retried=false")"
printf 'job\tstatut\tattente_s\tduree_s\trunner\tgestionnaire\n'
jq -r --arg m "$motif" '.[] | select(.name | test($m)) | [.id, .name, .status, (.queued_duration // 0 | floor), (.duration // 0 | floor), (.runner.description // "-")] | @tsv' <<<"$jobs" \
  | while IFS=$'\t' read -r id nom statut attente duree runner; do
      gest="-"
      if [[ "${MESURER_GESTIONNAIRE:-0}" == 1 ]]; then
        gest="$(api "projects/$projet/jobs/$id/trace" | head -n 3 | sed -nE 's/.* on [^ ]+ ([^ ,]+).*/\1/p' | head -n 1)" || gest="?"
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$nom" "$statut" "$attente" "$duree" "$runner" "${gest:--}"
    done
jq -r --arg m "$motif" '[.[] | select(.name | test($m)) | (.queued_duration // 0)] | sort
  | if length == 0 then "aucun job" else
      "jobs=\(length)  attente médiane=\(.[(length/2|floor)] | floor) s  p95=\(.[((length*0.95)|ceil) - 1] | floor) s  max=\(.[-1] | floor) s"
    end' <<<"$jobs" >&2
