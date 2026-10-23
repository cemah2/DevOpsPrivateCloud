# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
# _m29-operationnel.sh — fonctions partagées par les checks M29-E06 à M29-E12 (lecture seule).
# Reprend _m29-decouverte.sh (préfixe _m29d_) et ajoute le préfixe _m29o_.
#
# Accès supplémentaires (tous en lecture) :
#   - Prometheus TÉMOIN de mon01 (MGMT → mon01:9090, M21) : sondes blackbox, règles chargées ;
#   - pve01 : « pvesh get » et « pveum user token permissions » en consultation (SSH, comme les
#     checks des modules précédents qui lisent « qm config ») ;
#   - NetBox : netbox_api (jeton de lecture des checks).
#
# Variables de lab/lab.env (défauts ci-dessous) :
#   WB_M29_TEMOIN_URL          Prometheus témoin (http://mon01.par1.medisphere.internal:9090)
#   WB_M29_CHAOS_NS            espace des expériences (chaos-experiences)
#   WB_M29_VERSION_VALIDATION  étiquette publiée du composant validation (v2.11.0)
#   WB_M29_GOSS_HOTES          VMs de l'essai Goss ("dns02 nbx01")

# shellcheck source=_m29-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-decouverte.sh"

_M29O_TEMOIN="${WB_M29_TEMOIN_URL:-http://mon01.par1.medisphere.internal:9090}"
_M29O_CHAOS_NS="${WB_M29_CHAOS_NS:-chaos-experiences}"
_M29O_VERSION_VALIDATION="${WB_M29_VERSION_VALIDATION:-v2.11.0}"
read -r -a _M29O_GOSS_HOTES <<<"${WB_M29_GOSS_HOTES:-dns02 nbx01}"
_M29O_P_CI="plateforme/ci-templates"
_M29O_P_INFRA="plateforme/infra"
_M29O_P_MODULES="plateforme/tofu-modules"
_M29O_PVE="${WB_PVE_HOST:-pve01}"
# Espaces où Chaos Mesh a le droit d'injecter (liste FERMÉE, PLAN §4.13).
_M29O_ESPACES_CHAOS='["mediagenda-recette","medinotif-recette","wb-essais"]'

# _m29o_temoin_requete 'PromQL' — requête instantanée au Prometheus témoin (JSON, vide si erreur).
_m29o_temoin_requete() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" --data-urlencode "query=$1" \
    "$_M29O_TEMOIN/api/v1/query" 2>/dev/null || true
}

# _m29o_temoin_regles — règles chargées par le Prometheus témoin (JSON, vide si erreur).
_m29o_temoin_regles() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" "$_M29O_TEMOIN/api/v1/rules" 2>/dev/null || true
}

# _m29o_pve COMMANDE — commande de CONSULTATION sur pve01 (sortie standard, vide si erreur).
_m29o_pve() { remote "$_M29O_PVE" "$1" 2>/dev/null || true; }

# _m29o_etiquette_existe PROJET ÉTIQUETTE — l'étiquette Git existe.
_m29o_etiquette_existe() {
  gitlab_api "projects/$(_m29d_uri "$1")/repository/tags/$(_m29d_uri "$2")" >/dev/null 2>&1
}

# _m29o_pipeline_main_ok PROJET [REGEX_JOB] — le dernier pipeline de main a réussi, et (si donné)
#   contient un job réussi dont le nom correspond.
_m29o_pipeline_main_ok() {
  local p id
  p="$(_m29d_dernier_pipeline "$1")"
  _m29d_json "$p" '.status == "success"' || return 1
  [[ -n "${2:-}" ]] || return 0
  id="$(jq -r '.id' <<<"$p")"
  gitlab_api "projects/$(_m29d_uri "$1")/pipelines/$id/jobs?per_page=100" 2>/dev/null \
    | jq -e --arg re "$2" 'any(.[]; (.name | test($re)) and .status == "success")' >/dev/null 2>&1
}

# _m29o_branche_existe PROJET BRANCHE
_m29o_branche_existe() {
  gitlab_api "projects/$(_m29d_uri "$1")/repository/branches/$(_m29d_uri "$2")" >/dev/null 2>&1
}
