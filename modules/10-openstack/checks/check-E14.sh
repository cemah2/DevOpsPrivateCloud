# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E14.sh — M10-E14 : Heat : des piles d'infrastructure
# À lancer depuis adm01 avant la suppression de la pile. Lecture seule : API (cloud du projet mediagenda-dev), GitLab, HTTP.

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E14 — Heat : des piles d'infrastructure"
require_cmd openstack jq curl

_m10o_hot="$(_m10o_contenu_main "$_M10O_PROJET_OS" heat/pile-recette.yaml)"
check_cmd "heat/pile-recette.yaml (main) : version 2021-04-16 (wallaby)" \
  bash -c 'grep -Eq "^heat_template_version:[[:space:]]*[\"'"'"']?(2021-04-16|wallaby)" <<<"$1"' _ "$_m10o_hot"
check_cmd "heat/pile-recette.yaml (main) : paramètres contraints" \
  bash -c 'grep -q "custom_constraint" <<<"$1" && grep -q "range" <<<"$1"' _ "$_m10o_hot"
check_cmd "heat/pile-recette.yaml (main) : sorties ip_flottante et url" \
  bash -c 'grep -Eq "^[[:space:]]+ip_flottante:" <<<"$1" && grep -Eq "^[[:space:]]+url:" <<<"$1"' _ "$_m10o_hot"

if _m10o_cloud_existe "$_M10O_CLOUD_DEV"; then
  _m10o_pile="$(_m10o_osc "$_M10O_CLOUD_DEV" stack show -f json recette-e14 || true)"
  check_cmd "pile recette-e14 (mediagenda-dev) : UPDATE_COMPLETE" jq -e '.stack_status == "UPDATE_COMPLETE"' <<<"$_m10o_pile"
  _m10o_res="$(_m10o_osc "$_M10O_CLOUD_DEV" stack resource list -f json recette-e14 || true)"
  _m10o_srv="$(jq -r 'map(select(.resource_type == "OS::Nova::Server")) | first | .physical_resource_id // empty' <<<"$_m10o_res" 2>/dev/null || true)"
  _m10o_vol="$(jq -r 'map(select(.resource_type == "OS::Cinder::Volume")) | first | .physical_resource_id // empty' <<<"$_m10o_res" 2>/dev/null || true)"
  check_output "instance de la pile : gabarit m1.moyen" 'm1\.moyen' \
    bash -c '[[ -n "$1" ]] && openstack --os-cloud "$2" server show -f json "$1" 2>/dev/null | jq -r ".flavor | tostring"' _ "$_m10o_srv" "$_M10O_CLOUD"
  check_output "volume de la pile : 10 Go" '^10$' \
    bash -c '[[ -n "$1" ]] && openstack --os-cloud "$2" volume show -f value -c size "$1" 2>/dev/null' _ "$_m10o_vol" "$_M10O_CLOUD"
  _m10o_url="$(jq -r '.outputs // [] | map(select(.output_key == "ip_flottante")) | first | .output_value // empty' <<<"$_m10o_pile" 2>/dev/null || true)"
  if [[ -n "$_m10o_url" ]]; then
    check_http "la page de l'instance répond sur http://$_m10o_url/" "http://$_m10o_url/" 200
  else
    _ko "pile recette-e14 : sortie ip_flottante absente"
  fi
else
  _ko "cloud $_M10O_CLOUD_DEV absent de clouds.yaml (E05) : impossible de lire la pile du projet"
fi
