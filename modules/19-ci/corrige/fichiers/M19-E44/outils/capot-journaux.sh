#!/usr/bin/env bash
# capot-journaux.sh — extrait des journaux de GitLab (sur git01, avec sudo) les lignes utiles au
# compte rendu de M19-E44, pour une fenêtre de temps : routes, statuts, durées, classes Sidekiq.
# Aucun en-tête, aucun paramètre de requête, aucun jeton n'est recopié (champs choisis un par un).
# Usage : sudo capot-journaux.sh DEBUT FIN   (heures ISO UTC, ex. 2026-11-04T09:12 2026-11-04T09:20)
set -euo pipefail

DEBUT="${1:?début (ISO UTC) attendu}"
FIN="${2:?fin (ISO UTC) attendue}"
L=/var/log/gitlab

fenetre() { jq -c --arg d "$DEBUT" --arg f "$FIN" "select((.time // \"\") >= \$d and (.time // \"\") <= \$f) | $1" "$2" 2>/dev/null || true; }

echo "## gitlab-shell (poussées SSH)"
fenetre '{time, msg, command, gl_project_path, status}' "$L/gitlab-shell/gitlab-shell.log"

echo "## API interne et API des runners (api_json.log)"
fenetre 'select(.route | test("internal/(allowed|post_receive)|jobs/request|jobs/:id")) | {time, method, route, status, duration_s, correlation_id}' \
  "$L/gitlab-rails/api_json.log"

echo "## Sidekiq (classes et durées)"
fenetre 'select(.job_status == "done" or .job_status == "fail") | select(.class | test("PostReceive|Pipeline|Build|Ci::")) | {time, class, job_status, duration_s, correlation_id}' \
  "$L/sidekiq/current"

echo "## Workhorse (long polling)"
fenetre 'select(.uri == "/api/v4/jobs/request") | {time, status, duration_ms}' "$L/gitlab-workhorse/current"
