# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes
#
# check-E34.sh — M12-E34 « Conteneuriser une application en temps limité » (MédiAnnuaire)
# À lancer à T4. Lecture seule : API GitLab, API du registre de travail, docker inspect sur ctr01,
# HTTP vers la recette (GET ; le POST de rechargement n'est essayé que SANS jeton : refus attendu),
# configuration de la sonde sur adm01.

# shellcheck source=_m12-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-production.sh"

title "M12-E34 — MédiAnnuaire en temps limité"
require_cmd jq curl

title "Projet et pipeline (exigences 1 à 3)"
check_cmd "mediagenda/annuaire : code de l'application sur main" \
  _m12p_arbre_contient mediagenda/annuaire '^src/mediannuaire/__main__\.py$'
_m12_e34_dockerfile() {
  local c
  c="$(_m12p_fichier_main mediagenda/annuaire Dockerfile 2>/dev/null)" || return 1
  (($(grep -ciE '^FROM ' <<<"$c") >= 2)) && grep -Eq 'bibliotheque/[^ ]+@sha256:[0-9a-f]{64}' <<<"$c"
}
check_cmd "Dockerfile multi-étapes, image de base bibliotheque/ épinglée" _m12_e34_dockerfile
check_cmd ".dockerignore en liste blanche" _m12p_doc_main mediagenda/annuaire .dockerignore '^\*$'
check_cmd "compose.yaml sur main" _m12p_doc_main mediagenda/annuaire compose.yaml 'read_only' 'cap_drop'
check_cmd "dernier pipeline de main réussi" _m12p_pipeline_ok mediagenda/annuaire
_m12_e34_tags="$(_m12p_etiquettes mediagenda/annuaire || true)"
check_cmd "registre : mediagenda/annuaire:1.0.0 publiée" bash -c 'grep -qx 1.0.0 <<<"$1"' _ "$_m12_e34_tags"
check_cmd "registre : pas d'étiquette latest" bash -c '[[ -n "$1" ]] && ! grep -qx latest <<<"$1"' _ "$_m12_e34_tags"
_m12_e34_cfg="$(_m12p_config mediagenda/annuaire 1.0.0 || echo null)"
check_cmd "image : utilisateur numérique non nul, sonde de santé, forme exec" _m12p_jq "$_m12_e34_cfg" '
  (.config.User // "" | test("^[1-9][0-9]*(:[0-9]+)?$"))
  and ((.config.Healthcheck.Test // []) | length > 0)
  and ((.config.Cmd // []) | length > 0 and (.[0] | test("^/bin/sh$") | not))'
check_cmd "image : étiquettes OCI de version et de révision" _m12p_jq "$_m12_e34_cfg" \
  '(.config.Labels // {}) | (."org.opencontainers.image.version" // "" | length > 0) and (."org.opencontainers.image.revision" // "" | length > 6)'

title "Recette sur ctr01 (exigences 4 à 6)"
_m12_e34_c="$(_m12p_ctr_service ctr01 annuaire annuaire)"
_m12_e34_j="$(_m12p_inspect ctr01 "$_m12_e34_c")"
check_cmd "la recette tourne avec l'image publiée 1.0.0" _m12p_jq "$_m12_e34_j" \
  '.Config.Image == $r' --arg r "$_M12P_REGISTRE/mediagenda/annuaire:1.0.0"
check_cmd "durcie : UID non nul, aucune capacité, no-new-privileges, racine en lecture seule" _m12p_durci "$_m12_e34_j"
check_cmd "limites de mémoire et de processus" _m12p_jq "$_m12_e34_j" '(.HostConfig.Memory > 0) and ((.HostConfig.PidsLimit // 0) > 0)'
check_cmd "données montées en lecture seule" _m12p_jq "$_m12_e34_j" '[.Mounts[] | select(.Destination == "/donnees")] | length == 1 and (.[0].RW == false)'
check_cmd "le jeton d'administration n'est pas dans l'environnement du conteneur" _m12p_jq "$_m12_e34_j" \
  '(.Config.Env // []) | any(startswith("MEDIANNUAIRE_JETON_ADMIN=")) | not'
check_cmd "le conteneur est sain" _m12p_jq "$_m12_e34_j" '.State.Health.Status == "healthy"'
_m12_e34_url="http://ctr01.$_M12P_DOMAINE:8090"
check_http "/sante répond 200" "$_m12_e34_url/sante" 200
check_http "/pret répond 200" "$_m12_e34_url/pret" 200
check_output "la liste des praticiens n'est pas vide" '"id"' curl -s --max-time "$WB_TIMEOUT" "$_m12_e34_url/api/v1/praticiens"
check_http "rechargement sans jeton refusé (401)" "$_m12_e34_url/admin/recharger" 401 -X POST

title "Secrets et supervision (exigences 5 et 8)"
_m12_e34_sans_secret() {
  gitlab_api "projects/mediagenda%2Fannuaire" >/dev/null 2>&1 || return 1
  ! _m12p_arbre_contient mediagenda/annuaire '(^|/)secrets/'
}
check_cmd "aucun fichier de secret dans le dépôt" _m12_e34_sans_secret
check_cmd "registre des secrets : jeton de MédiAnnuaire" \
  _m12p_doc_main plateforme/medisphere docs/socle/registre-secrets.md 'annuaire'
check_cmd "sonde : le conteneur de la recette est attendu" \
  grep -Eq "ctr01:${_m12_e34_c:-annuaire-annuaire-1}" /usr/local/etc/ms-verif-conteneurs.conf
check_cmd "la sonde conclut que tout va bien" timeout 120 /usr/local/bin/ms-verif-conteneurs --quiet
