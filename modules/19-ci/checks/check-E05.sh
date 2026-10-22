# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E05.sh — M19-E05 : anatomie d'un job dans Kubernetes
# À lancer depuis adm01. Lecture seule : API GitLab en GET (jobs, artefact anatomie.txt, fichiers de main).
# Le job « anatomie » est cherché parmi les jobs RÉUSSIS récents de ci-labo (en E06 il ne tourne plus
# que sur les lancements manuels : il n'est pas forcément dans le dernier pipeline).

# shellcheck source=_m19-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-decouverte.sh"

title "M19-E05 — Anatomie d'un job dans Kubernetes"
require_cmd jq curl

_m19d_e05_p="$(_m19d_enc "$_M19D_LABO")"
_m19d_e05_job="$(_m19d_api "projects/$_m19d_e05_p/jobs?scope%5B%5D=success&per_page=100" \
  | jq -c '[.[]? | select(.name == "anatomie")] | sort_by(.id) | last // empty' 2>/dev/null || true)"

if [[ -z "$_m19d_e05_job" ]]; then
  check_cmd "$_M19D_LABO : un job « anatomie » réussi parmi les 100 derniers jobs réussis" false
  skip "contrôles du job anatomie" "aucun job anatomie réussi"
else
  _m19d_e05_id="$(jq -r .id <<<"$_m19d_e05_job")"
  check_cmd "$_M19D_LABO : job anatomie #$_m19d_e05_id réussi" true
  check_cmd "job anatomie exécuté par le runner $_M19D_RUNNER" _m19d_json "$_m19d_e05_job" \
    '(.runner.description // "") == $r' --arg r "$_M19D_RUNNER"
  check_cmd "job anatomie : archive d'artefacts, expiration à 8 jours au plus" _m19d_json "$_m19d_e05_job" '
    any(.artifacts[]?; .file_type == "archive")
    and (.artifacts_expire_at != null)
    and (((.artifacts_expire_at | sub("\\.[0-9]+"; "") | sub("[+]00:00$"; "Z") | fromdateiso8601)
          - (.created_at | sub("\\.[0-9]+"; "") | sub("[+]00:00$"; "Z") | fromdateiso8601)) <= 8 * 86400)'
  _m19d_e05_txt="$(_m19d_api "projects/$_m19d_e05_p/jobs/$_m19d_e05_id/artifacts/anatomie.txt")"
  check_cmd "anatomie.txt présent dans les artefacts" test -n "$_m19d_e05_txt"
  check_output "anatomie.txt : limite mémoire du conteneur build = 1 Gi (1073741824)" '^1073741824$' \
    printf '%s\n' "$_m19d_e05_txt"
  # Jeton monté = un montage sur …/kubernetes.io/serviceaccount (ligne de /proc/self/mounts) ou un
  # fichier « token » listé dans ce dossier (« token -> ..data/token ») ; le message d'erreur de ls
  # (dossier absent), lui, cite le chemin sans être un montage.
  check_cmd "anatomie.txt : aucun jeton de compte de service monté" bash -c \
    '[[ -n "$1" ]] && ! grep -Eq "^[^[:space:]]+ (/var)?/run/secrets/kubernetes\.io/serviceaccount |serviceaccount/token|[[:space:]]token( -> |$)" <<<"$1"' _ "$_m19d_e05_txt"
  check_cmd "anatomie.txt : aucune valeur sensible recopiée (CI_JOB_TOKEN, mots de passe)" bash -c \
    '! grep -Eq "^(CI_JOB_TOKEN|CI_REGISTRY_PASSWORD|CI_JOB_JWT|CI_DEPENDENCY_PROXY_PASSWORD)=" <<<"$1"' _ "$_m19d_e05_txt"
fi

_m19d_e05_doc="$(_m19d_contenu_main plateforme/medisphere docs/livraison/ci/anatomie-job.md)"
check_cmd "plateforme/medisphere (main) : docs/livraison/ci/anatomie-job.md" test -n "$_m19d_e05_doc"
for _m19d_e05_mot in init-permissions helper build attach; do
  check_cmd "anatomie-job.md décrit « $_m19d_e05_mot »" bash -c 'grep -qi -- "$2" <<<"$1"' _ "$_m19d_e05_doc" "$_m19d_e05_mot"
done
