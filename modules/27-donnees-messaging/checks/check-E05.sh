# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E05.sh — M27-E05 : Flyway : reprendre les migrations de MédiAgenda
# À lancer depuis adm01. Lecture seule : fichiers sur main de mediagenda/api et mediagenda/deploiement
# (GitLab), Job mediagenda-migrations des espaces de recette et de prod, et son JOURNAL (le Job
# termine par « flyway info » : c'est là qu'on lit l'historique, sans accès à la base).

# shellcheck source=_m27-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-decouverte.sh"

title "M27-E05 — Flyway : reprendre les migrations de MédiAgenda"
require_cmd jq kubectl curl

# --- 1. Le dépôt de l'API ------------------------------------------------------------------------------
_m27d_e05_df="$(_m27d_contenu_main "$_M27D_P_API" Dockerfile.migrations)"
check_cmd "mediagenda/api (main) : Dockerfile.migrations sur Flyway 13 du cache Harbor, par empreinte" bash -c '
  grep -Eq "^FROM +registry\.par1\.medisphere\.internal/dockerhub/flyway/flyway:13\.[0-9]+(\.[0-9]+)?@sha256:[0-9a-f]{64}" <<<"$1"' _ "$_m27d_e05_df"
check_cmd "Dockerfile.migrations : utilisateur non root" bash -c 'grep -Eq "^USER +[1-9][0-9]*" <<<"$1"' _ "$_m27d_e05_df"
check_cmd "mediagenda/api (main) : migrations V1 et V2 inchangées de nom" bash -c '
  _a="$(jq -r ".[].name" <<<"$1" 2>/dev/null)"; grep -qx "V1__init.sql" <<<"$_a" && grep -qx "V2__index.sql" <<<"$_a"' _ \
  "$(gitlab_api "$_M27D_P_API/repository/tree?ref=main&path=migrations&per_page=100" 2>/dev/null || true)"
check_output "mediagenda/api (main) : rappel beforeBaseline (garde-fou de la reprise)" 'mediagenda_historique_schema' \
  _m27d_contenu_main "$_M27D_P_API" flyway/rappels/beforeBaseline.sql

# --- 2. Le Job, par environnement -----------------------------------------------------------------------
for _m27d_e05_env in "$_M27D_ENV_RECETTE" "$_M27D_ENV_PROD"; do
  _m27d_e05_ns="mediagenda-${_m27d_e05_env}"
  _m27d_e05_jobs="$(_m27d_k get jobs -n "$_m27d_e05_ns" -o json)"
  _m27d_e05_job="$(jq -c '[.items[] | select(.metadata.name == "mediagenda-migrations")] | first // empty' <<<"${_m27d_e05_jobs:-{\}}" 2>/dev/null || true)"
  if [[ -z "$_m27d_e05_job" ]]; then
    _ko "$_m27d_e05_env : aucun Job mediagenda-migrations (component migrations, synchronisation Argo CD)"
    continue
  fi
  check_cmd "$_m27d_e05_env : Job mediagenda-migrations en hook Sync, vague -1" _m27d_json "$_m27d_e05_job" \
    '.metadata.annotations["argocd.argoproj.io/hook"] == "Sync" and .metadata.annotations["argocd.argoproj.io/sync-wave"] == "-1"'
  check_cmd "$_m27d_e05_env : dernier Job réussi" _m27d_json "$_m27d_e05_job" '(.status.succeeded // 0) >= 1'
  check_cmd "$_m27d_e05_env : image medisphere/mediagenda-migrations" _m27d_json "$_m27d_e05_job" \
    'any(.spec.template.spec.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/medisphere/mediagenda-migrations[:@]"))'
  check_cmd "$_m27d_e05_env : FLYWAY_URL du Job vers le primaire (mediagenda-db-rw), TLS vérifié, jamais par le pooler" _m27d_json "$_m27d_e05_job" \
    'any(.spec.template.spec.containers[].env[]?; .name == "FLYWAY_URL"
       and ((.value // "") | test("^jdbc:postgresql://mediagenda-db-rw[.:/]")) and ((.value // "") | test("sslmode=verify-(full|ca)"))
       and ((.value // "") | test("pooler") | not))'
  check_cmd "$_m27d_e05_env : compte du migrateur dynamique (Secret mediagenda-db-migrateur)" _m27d_json "$_m27d_e05_job" \
    'any(.spec.template.spec.containers[].env[]?; .name == "FLYWAY_USER" and .valueFrom.secretKeyRef.name == "mediagenda-db-migrateur")
     and any(.spec.template.spec.containers[].env[]?; .name == "FLYWAY_PASSWORD" and .valueFrom.secretKeyRef.name == "mediagenda-db-migrateur")'
  check_cmd "$_m27d_e05_env : l'ancien Job mediagenda-migrate n'existe plus" _m27d_json "$_m27d_e05_jobs" \
    '[.items[] | select(.metadata.name == "mediagenda-migrate")] | length == 0'
  # Journal du dernier pod du Job : tableau de « flyway info » en fin d'exécution.
  _m27d_e05_pod="$(_m27d_k get pods -n "$_m27d_e05_ns" -l job-name=mediagenda-migrations -o json |
    jq -r '[.items[] | select(.status.phase == "Succeeded")] | sort_by(.metadata.creationTimestamp) | last | .metadata.name // empty' 2>/dev/null || true)"
  if [[ -z "$_m27d_e05_pod" ]]; then
    skip "$_m27d_e05_env : historique Flyway (journal du Job)" "aucun pod réussi du Job encore présent ; relance une synchronisation"
    continue
  fi
  _m27d_e05_log="$(_m27d_k logs -n "$_m27d_e05_ns" "$_m27d_e05_pod")"
  check_cmd "$_m27d_e05_env : reprise à la version 2 dans flyway_schema_history (ligne BASELINE)" bash -c '
    grep -Eq "^\| +\| 2 +\|.*\| BASELINE +\|" <<<"$1"' _ "$_m27d_e05_log"
  check_cmd "$_m27d_e05_env : V1 et V2 NON rejouées (sous la reprise)" bash -c '
    grep -Eq "^\| Versioned \| 1 +\|.*Below Baseline" <<<"$1" && ! grep -Eq "^\| Versioned \| [12] +\|.*\| Success +\|" <<<"$1"' _ "$_m27d_e05_log"
done

check_cmd "plateforme/medisphere (main) : ${_M27D_DOC}/migrations.md (reprise, flyway_schema_history)" \
  _m27d_doc_contient "${_M27D_DOC}/migrations.md" 'flyway_schema_history'
