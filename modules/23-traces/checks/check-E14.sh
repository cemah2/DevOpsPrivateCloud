# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E14.sh — M23-E14 « Profilage continu avec Pyroscope ». Lecture seule.

# shellcheck source=_m23-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-production.sh"

title "M23-E14 — Profilage continu avec Pyroscope"
require_cmd kubectl jq curl aws

check_cmd "Application Argo CD « pyroscope » Synced et Healthy" _m23p_application_saine pyroscope
check_cmd "Pyroscope : pods prêts dans l'espace traces" \
  _m23p_kq '[.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "pyroscope")
            | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length >= 1' -n traces pods
check_cmd "Pyroscope : le sous-chart Alloy du chart est désactivé (la collecte passe par l'Alloy de M22)" \
  _m23p_kq '[.items[] | select((.metadata.labels["app.kubernetes.io/name"] // "") == "alloy")] | length == 0' -n traces statefulsets
_m23_e14_s3="$HOME/.config/workbook/s3-pyroscope.env"
if [[ -r "$_m23_e14_s3" ]]; then
  check_cmd "compartiment RGW pyroscope-k8s-par1 : des objets y sont écrits" _m23p_compartiment_non_vide "$_m23_e14_s3" pyroscope-k8s-par1
else
  skip "compartiment pyroscope-k8s-par1" "identité de lecture absente : $_m23_e14_s3 (voir l'énoncé de M23-E14)"
fi

check_cmd "profils CPU récents (15 min) de mediagenda-api (SDK Python)" _m23p_profils mediagenda-api
check_cmd "profils CPU récents (15 min) de medidoc (pprof collecté par Alloy)" _m23p_profils medidoc
_m23_e14_memoire() {
  _m23p_profils medidoc "memory:alloc_space:bytes:space:bytes" || _m23p_profils medidoc "memory:inuse_space:bytes:space:bytes"
}
check_cmd "profils mémoire récents de medidoc (godeltaprof ou heap)" _m23_e14_memoire
check_cmd "Alloy (plateforme/observabilite/alloy) : composant pyroscope.scrape déclaré" \
  _m23p_depot_contient plateforme/observabilite alloy 'pyroscope\.scrape'
check_cmd "medidoc-dev : le port pprof n'est publié par aucun Service" \
  _m23p_kq '[.items[].spec.ports[]? | select(.port == 6060 or .targetPort == 6060 or (.name // "" | test("pprof")))] | length == 0' -n medidoc-dev services

_m23_e14_tempo="$(_m23p_ds tempo)" || _m23_e14_tempo=""
check_cmd "source Grafana Tempo : lien vers les profils (tracesToProfiles.datasourceUid)" \
  jq -e '(.jsonData.tracesToProfiles.datasourceUid // "") != ""' <<<"${_m23_e14_tempo:-null}"
check_cmd "docs/observabilite/traces/profilage.md : lecture d'un flame graph et surcoût mesuré" \
  _m23p_doc docs/observabilite/traces profilage 'flame' 'surco'
