# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E04.sh — M25-E04 : Premiers pas : KV v2, versions, CLI et API
# À lancer depuis adm01. Lecture seule : montages et MÉTADONNÉES du moteur KV v2 (jamais une valeur
# de secret), document de conventions sur main de plateforme/medisphere.

# shellcheck source=_m25-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-decouverte.sh"

title "M25-E04 — Premiers pas : KV v2, versions, CLI et API"
require_cmd jq curl

_m25d_annoncer_acces

# --- 1. Le moteur ----------------------------------------------------------------------------------
_m25d_e04_montages="$(_m25d_api sys/mounts)"
if [[ -z "$_m25d_e04_montages" ]]; then
  _ko "Montages du coffre illisibles (sys/mounts) : coffre scellé, ou accès des vérifications refusé"
else
  check_cmd "Moteur KV version 2 monté en kv/" _m25d_json "$_m25d_e04_montages" \
    '(.data // .)["kv/"] | .type == "kv" and .options.version == "2"'
  check_cmd "Aucun moteur KV version 1 ni montage « secret/ » par défaut" _m25d_json "$_m25d_e04_montages" \
    '[(.data // .) | to_entries[] | select(.value.type == "kv" and (.value.options.version // "1") != "2")] | length == 0'
fi
check_cmd "kv/config : 10 versions gardées par secret" _m25d_json "$(_m25d_api kv/config)" '.data.max_versions == 10'

# --- 2. Le secret d'essai ----------------------------------------------------------------------------------
_m25d_e04_meta="$(_m25d_api kv/metadata/plateforme/essai/demo)"
if [[ -z "$_m25d_e04_meta" ]]; then
  _ko "kv/plateforme/essai/demo introuvable (métadonnées absentes)"
else
  check_cmd "kv/plateforme/essai/demo : au moins 3 versions écrites" _m25d_json "$_m25d_e04_meta" \
    '.data.current_version >= 3'
  check_cmd "kv/plateforme/essai/demo : la version 1 est DÉTRUITE (bao kv destroy), pas seulement supprimée" \
    _m25d_json "$_m25d_e04_meta" '.data.versions["1"].destroyed == true'
  check_cmd "kv/plateforme/essai/demo : la version courante est lisible (supprimée puis restaurée, ou réécrite)" \
    _m25d_json "$_m25d_e04_meta" \
    '.data.versions[(.data.current_version | tostring)] | .destroyed == false and .deletion_time == ""'
  check_cmd "kv/plateforme/essai/demo : écriture conditionnelle imposée (cas_required)" \
    _m25d_json "$_m25d_e04_meta" '.data.cas_required == true'
  check_cmd "kv/plateforme/essai/demo : métadonnées propriétaire et rotation renseignées" \
    _m25d_json "$_m25d_e04_meta" '(.data.custom_metadata.proprietaire // "") != "" and (.data.custom_metadata.rotation // "") != ""'
fi

# --- 3. Les conventions écrites --------------------------------------------------------------------------------
_m25d_e04_doc="$(_m25d_contenu_main plateforme/medisphere docs/securite/secrets/conventions-kv.md)"
check_cmd "plateforme/medisphere : docs/securite/secrets/conventions-kv.md sur main" _m25d_contient "$_m25d_e04_doc" 'kv/plateforme/'
check_cmd "conventions-kv.md : chemins des applications par environnement (kv/<application>/<env>/…)" \
  _m25d_contient "$_m25d_e04_doc" 'kv/(<application>|mediagenda)/'
check_cmd "conventions-kv.md : métadonnées obligatoires (proprietaire, rotation)" \
  _m25d_contient "$(grep -c -E 'proprietaire|rotation' <<<"$_m25d_e04_doc" || true)" '^([2-9]|[1-9][0-9]+)$'
