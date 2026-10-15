# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E06.sh — M17-E06 « Dépendances et sous-charts ». Lecture seule.

# shellcheck source=_m17-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-operationnel.sh"

title "M17-E06 — Dépendances et sous-charts"
require_cmd jq yq kubectl curl

check_cmd "Chart.yaml (main) : dépendance medisphere-commun" _m17o_dependance medisphere-commun
check_cmd "Chart.yaml (main) : dépendance valkey sous condition valkey.enabled" _m17o_dependance valkey condition=valkey.enabled
check_cmd "mediagenda/chart (main) : charts/mediagenda/Chart.lock versionné" _m17d_gl_existe mediagenda/chart charts/mediagenda/Chart.lock
_e06_tgz() { ! _m17d_gl_arbre mediagenda/chart charts | grep -Eq '/charts/[^/]+\.tgz$'; }
check_cmd "mediagenda/chart (main) : aucune archive de dépendance versionnée" _e06_tgz
check_cmd "mediagenda/chart (main) : bibliothèque charts/medisphere-commun (type library)" \
  _m17d_jq "$(_m17d_gl_fichier mediagenda/chart charts/medisphere-commun/Chart.yaml | yq -o json 2>/dev/null)" '.type == "library"'

_e06_db="$(_m17d_obj mediagenda-dev cluster.postgresql.cnpg.io mediagenda-db)"
check_cmd "dev : le Cluster mediagenda-db appartient à la release mediagenda" _m17d_de_release "$_e06_db" mediagenda
check_cmd "dev : le Cluster porte helm.sh/resource-policy: keep" _m17d_jq "$_e06_db" \
  '.metadata.annotations["helm.sh/resource-policy"] == "keep"'
_e06_repris() {
  # Repris, pas recréé : le Cluster est plus ancien que le Deployment de Valkey du sous-chart.
  local tb tv
  tb="$(jq -r '.metadata.creationTimestamp // ""' <<<"$_e06_db")" || return 1
  tv="$(_m17d_obj mediagenda-dev deploy mediagenda-valkey | jq -r '.metadata.creationTimestamp // ""')" || return 1
  [[ -n "$tb" && -n "$tv" && "$tb" < "$tv" ]]
}
check_cmd "dev : le Cluster a été repris (antérieur au sous-chart Valkey), pas recréé" _e06_repris
_e06_v="$(_m17d_obj mediagenda-dev deploy mediagenda-valkey)"
_e06_valkey() { _m17d_de_release "$_e06_v" mediagenda && _m17d_pret "$_e06_v"; }
check_cmd "dev : Valkey du sous-chart (mediagenda-valkey) de la release, prêt" _e06_valkey
for _e06_o in "statefulset valkey" "service valkey" "networkpolicy dev-base-provisoire" "networkpolicy dev-valkey-provisoire" \
              "ciliumnetworkpolicy dev-base-provisoire-api-kubernetes"; do
  # shellcheck disable=SC2086  # type et nom séparés volontairement
  check_cmd "dev : objet provisoire absent ($_e06_o)" test -z "$(_m17d_obj mediagenda-dev $_e06_o)"
done
_e06_d="$(_m17d_obj mediagenda-dev deploy mediagenda)"
check_cmd "dev : l'API utilise redis://mediagenda-valkey…" _m17d_jq "$_e06_d" \
  '[.spec.template.spec.containers[] | select(.name == "api") | .env[]? | select(.name == "MEDIAGENDA_VALKEY_URL") | .value | test("^rediss?://mediagenda-valkey[:/]")] | any'
check_cmd "dev : API prête" _m17d_pret "$_e06_d"
check_cmd "https://mediagenda-dev.$_m17d_domaine/sante répond 200" _m17d_sante "https://mediagenda-dev.$_m17d_domaine/sante"
