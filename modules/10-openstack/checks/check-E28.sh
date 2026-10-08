# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E28.sh — M10-E28 « Mettre à jour OpenStack »
# Lecture seule : uv.lock du clone ~/src/openstack, version publiée sur PyPI (si joignable),
# images des conteneurs sur chaque nœud (docker inspect), services OpenStack, GitLab.

# shellcheck source=_m10-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-production.sh"

title "M10-E28 — Mettre à jour OpenStack"
require_cmd openstack jq ssh curl
_m10p_charger

_m10_lock="$_M10P_SRC/openstack/uv.lock"
# _m10_version_lock PAQUET — version épinglée dans uv.lock (format TOML de uv : name puis version).
_m10_version_lock() {
  awk -v p="$1" '$0 == "name = \"" p "\"" { getline; gsub(/version = |"/, ""); print; exit }' "$_m10_lock" 2>/dev/null
}
_m10_ka="$(_m10_version_lock kolla-ansible || true)"
_m10_ac="$(_m10_version_lock ansible-core || true)"

title "Versions épinglées (plateforme/openstack)"
check_output "uv.lock : kolla-ansible 22.x (trouvé : ${_m10_ka:-rien})" '^22\.' printf '%s\n' "${_m10_ka:-}"
check_output "uv.lock : ansible-core ≥ 2.19.1 et < 2.21 (trouvé : ${_m10_ac:-rien})" '^2\.(19\.([1-9]|[1-9][0-9])|20\.[0-9]+)' \
  printf '%s\n' "${_m10_ac:-}"
_m10_pypi="$(curl -s --max-time "$WB_TIMEOUT" https://pypi.org/pypi/kolla-ansible/json 2>/dev/null \
  | jq -r '[.releases | keys[] | select(test("^22\\.[0-9]+\\.[0-9]+$"))] | sort_by(split(".") | map(tonumber)) | last // empty' 2>/dev/null || true)"
if [[ -n "$_m10_pypi" ]]; then
  check_output "uv.lock : dernière kolla-ansible 22.x publiée ($_m10_pypi)" "^${_m10_pypi//./\\.}\$" printf '%s\n' "${_m10_ka:-}"
else
  skip "dernière version publiée de kolla-ansible" "PyPI injoignable depuis adm01"
fi

title "Images en service"
# Pour chaque conteneur : l'image avec laquelle il a été créé == l'image désignée MAINTENANT par
# son étiquette. Échoue si Docker ne répond pas ou s'il n'y a aucun conteneur.
_m10_images_a_jour() {
  remote "$1" 'n=0
    for c in $(sudo -n docker ps --format "{{.Names}}"); do
      img=$(sudo -n docker inspect -f "{{.Config.Image}}" "$c") || exit 1
      [ "$(sudo -n docker inspect -f "{{.Image}}" "$c")" = "$(sudo -n docker image inspect -f "{{.Id}}" "$img")" ] || exit 1
      n=$((n + 1))
    done
    [ "$n" -gt 0 ]' >/dev/null 2>&1
}
for _m10_h in "${_M10P_NOEUDS[@]}"; do
  check_cmd "$_m10_h : chaque conteneur tourne sur l'image actuellement désignée par son étiquette" _m10_images_a_jour "$_m10_h"
  check_cmd "$_m10_h : aucun conteneur unhealthy, arrêté ou en redémarrage" _m10p_conteneurs_sains "$_m10_h"
done

title "Services"
check_cmd "services de calcul : tous activés et « up »" _m10p_calcul_up
check_cmd "agents réseau OVN : tous vivants, passerelle présente" _m10p_agents_vivants
check_cmd "services Cinder : « up »" _m10p_volumes_up
check_cmd "plus aucune instance maj-essai*" _m10p_aucune_instance maj-essai

title "Documentation"
check_cmd "RB-101 dans docs/cloud/runbooks/ (montée de série décrite)" \
  _m10p_doc_contient docs/cloud/runbooks RB-101 'deploy' 'upgrade' 'retour arri'
check_cmd "CHG-1154 dans docs/cloud/changements/ (abandon, retour arrière, mesures, clôture)" \
  _m10p_doc_contient docs/cloud/changements CHG-1154 'abandon' 'retour arri' 'clos|cl[oô]tur'
_m10_photos() {
  gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=docs%2Fcloud%2Fchangements&per_page=100" 2>/dev/null \
    | jq -e '[.[]? | select(.name | test("CHG-1154.*(avant|apres)"))] | length >= 2' >/dev/null
}
check_cmd "photographies des images avant/après versionnées" _m10_photos
