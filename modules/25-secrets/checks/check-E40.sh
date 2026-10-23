# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E40.sh — M25-E40 « Panne : permission denied » : la politique mediagenda-dev accorde de nouveau
# l'écriture sous kv/data/mediagenda/dev/ (motif « * » complet, préfixe data/) et la liste sous
# kv/metadata/mediagenda/dev/ ; le groupe externe mediagenda ne porte qu'elle, son alias s'appelle
# exactement « mediagenda » sur le montage oidc/ ; aucune politique ne pose de deny sur les secrets de
# développement de MédiAgenda ; test des politiques dans la CI de plateforme/secrets ; journal INC-5240.
# Lecture seule : bao_api (politiques, groupes, sys/auth), gitlab_api.

# shellcheck source=_m25-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-expert.sh"

title "M25-E40 — Panne : « permission denied »"
require_cmd curl jq awk
_m25p_connexion

_m25x_e40_pol="$(_m25x_politique mediagenda-dev)"
check_cmd "mediagenda-dev : création, lecture, mise à jour, suppression sous kv/data/mediagenda/dev/*" \
  _m25x_caps_ont "$_m25x_e40_pol" 'kv/data/mediagenda/dev/*' create read update delete
check_cmd "mediagenda-dev : liste sous kv/metadata/mediagenda/dev/*" \
  _m25x_caps_ont "$_m25x_e40_pol" 'kv/metadata/mediagenda/dev/*' list
_m25x_e40_motifs_sains() {
  [[ -n "$1" ]] && ! grep -Eq 'path "kv/(data|metadata)/mediagenda/\+"|path "kv/mediagenda/' <<<"$1" \
    && ! grep -Eq 'path "kv/(data/)?(mediagenda/)?\*"' <<<"$1"
}
check_cmd "mediagenda-dev : ni motif « + » à la place de dev/*, ni chemin sans data/, ni joker trop large" \
  _m25x_e40_motifs_sains "$_m25x_e40_pol"

_m25x_e40_grp="$(_m25x_groupe mediagenda)"
_m25x_e40_oidc="$(_m25x_accessor_auth oidc/)"
check_cmd "groupe externe mediagenda : ne porte que la politique mediagenda-dev" \
  _m25p_jq "$_m25x_e40_grp" '.data.type == "external" and .data.policies == ["mediagenda-dev"]'
check_cmd "groupe externe mediagenda : alias « mediagenda » exactement, sur le montage oidc/" \
  _m25p_jq "$_m25x_e40_grp" '.data.alias.name == "mediagenda" and .data.alias.mount_accessor == $a' --arg a "$_m25x_e40_oidc"
check_cmd "aucune politique ne pose « deny » sur les secrets de développement de MédiAgenda" \
  _m25x_aucun_deny_sur 'mediagenda/(dev|\+|\*)'

_m25x_e40_ci() {
  local ci
  ci="$(_m25p_fichier "$_M25P_SECRETS" .gitlab-ci.yml)" || return 1
  grep -q 'tester-politiques' <<<"$ci" && _m25p_fichier "$_M25P_SECRETS" tests/politiques/capacites.tsv | grep -q 'mediagenda-dev'
}
check_cmd "plateforme/secrets : test des politiques en CI (tests/politiques/capacites.tsv couvre mediagenda-dev)" _m25x_e40_ci
check_cmd "journal de diagnostic INC-5240 sur main (plateforme/medisphere)" _m25x_journal INC-5240
