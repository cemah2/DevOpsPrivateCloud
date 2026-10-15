# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E03.sh — M17-E03 « Écrire le chart mediagenda » : chart sur main (lint), release de dev.
# Lecture seule (rendu dans un répertoire temporaire, cluster lu par wb-checks).

# shellcheck source=_m17-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-decouverte.sh"

title "M17-E03 — Écrire le chart mediagenda"
require_cmd jq kubectl helm git curl

check_cmd "mediagenda/chart (main) : charts/mediagenda/Chart.yaml" _m17d_gl_existe mediagenda/chart charts/mediagenda/Chart.yaml
_e03_c="$(_m17d_chart_main)" || _e03_c=""
if [[ -n "$_e03_c" ]]; then
  # medisphere.environnement est exigé à partir de 0.2.0 (E05) et ignoré par le chart 0.1.0.
  check_cmd "helm lint --strict du chart de origin/main" helm lint --strict "$_e03_c" --set medisphere.environnement=dev
else
  skip "helm lint du chart de origin/main" "clone $_m17d_chart_clone absent ou sans origin/main"
fi

_e03_d="$(_m17d_obj mediagenda-dev deploy mediagenda)"
check_cmd "mediagenda-dev : Deployment mediagenda de la release Helm « mediagenda »" _m17d_de_release "$_e03_d" mediagenda
check_output "Deployment : étiquette helm.sh/chart mediagenda-0.x.y" '^mediagenda-0\.[0-9]+\.[0-9]+' \
  jq -r '.metadata.labels["helm.sh/chart"] // ""' <<<"$_e03_d"
check_cmd "Deployment : pods prêts" _m17d_pret "$_e03_d"
check_cmd "pods conformes à restricted (non root, seccomp, pas d'élévation, capacités retirées)" _m17d_restricted "$_e03_d"
check_cmd "conteneur api : requêtes CPU et mémoire, limite mémoire" _m17d_jq "$_e03_d" \
  '.spec.template.spec.containers[] | select(.name == "api") | .resources.requests.cpu and .resources.requests.memory and .resources.limits.memory'
check_cmd "conteneur api : vivacité /sante, disponibilité /pret" _m17d_jq "$_e03_d" \
  '.spec.template.spec.containers[] | select(.name == "api") | .livenessProbe.httpGet.path == "/sante" and .readinessProbe.httpGet.path == "/pret"'
check_cmd "gabarit de pod : annotation d'empreinte checksum/config" _m17d_jq "$_e03_d" \
  '.spec.template.metadata.annotations | has("checksum/config")'
_e03_r="$(_m17d_obj mediagenda-dev httproute mediagenda)"
check_cmd "HTTPRoute mediagenda acceptée, références résolues" _m17d_route_acceptee "$_e03_r"
check_cmd "https://mediagenda-dev.$_m17d_domaine/sante répond 200" _m17d_sante "https://mediagenda-dev.$_m17d_domaine/sante"
