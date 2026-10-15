# shellcheck shell=bash
# _m13-production.sh — fonctions partagées par les checks M13-E13 à M13-E18 et M13-E25 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Identités utilisées (toutes en LECTURE) :
#   - robot$wb-checks de reg01 : WB_HARBOR_CHECKS_FILE (M13-E03), par harbor_api de check-lib.sh ;
#   - robot$wb-checks de reg02 : WB_HARBOR_REG02_CHECKS_FILE (défaut ~/.config/workbook/harbor-reg02-checks.env, E13) ;
#   - jeton GitLab des checks (gitlab_api) ; SSH admin + « sudo -n » de consultation sur reg01, runner02, pbs01.
# Préfixe _m13p_ : évite les collisions quand check-E25 charge d'autres fichiers communs.

_M13P_REGISTRE="${WB_HARBOR_URL:-https://registry.par1.medisphere.internal}"
_M13P_REGISTRE_NOM="${_M13P_REGISTRE#https://}"
_M13P_REG02_URL="${WB_HARBOR_REG02_URL:-https://reg02.par1.medisphere.internal}"
_M13P_REG02_NOM="${_M13P_REG02_URL#https://}"
_M13P_REG02_FICHIER="${WB_HARBOR_REG02_CHECKS_FILE:-$HOME/.config/workbook/harbor-reg02-checks.env}"
_M13P_RACINE=/usr/local/share/ca-certificates/medisphere-root-ca.crt
# Dernière version corrective attendue (PLAN §6 ; à relever si une version plus récente est publiée
# et appliquée en M13-E16) : WB_M13_HARBOR_VERSION dans lab/lab.env.
_M13P_VERSION="${WB_M13_HARBOR_VERSION:-v2.15.3}"
# shellcheck disable=SC2034  # utilisé par les checks qui sourcent ce fichier
_M13P_APPS=(mediagenda-api medidoc medinotif legacy-rdv)

# --- API Harbor ------------------------------------------------------------------------------------

# _m13p_api CHEMIN — GET sur l'API de reg01 (robot des checks) ; sortie JSON ou rien.
_m13p_api() { harbor_api "$1" 2>/dev/null; }

# _m13p_api2 CHEMIN — GET sur l'API de reg02 avec son propre robot des checks.
_m13p_api2() {
  [[ -r "$_M13P_REG02_FICHIER" ]] || return 1
  WB_HARBOR_URL="$_M13P_REG02_URL" WB_HARBOR_CHECKS_FILE="$_M13P_REG02_FICHIER" harbor_api "$1" 2>/dev/null
}

# _m13p_jq JSON FILTRE — filtre booléen jq (faux si le JSON est vide ou invalide).
_m13p_jq() {
  [[ -n "$1" ]] && jq -e "$2" >/dev/null 2>&1 <<<"$1"
}

# _m13p_sante [URL] — tous les composants « healthy » (point d'entrée public, sans identité).
_m13p_sante() {
  local u="${1:-$_M13P_REGISTRE}" s
  s="$(curl -sf --max-time "$WB_TIMEOUT" --cacert "$_M13P_RACINE" "$u/api/v2.0/health" 2>/dev/null)" || return 1
  _m13p_jq "$s" '.status == "healthy" and (.components | length > 0) and all(.components[]; .status == "healthy")'
}

# _m13p_version — version de Harbor de reg01 (systeminfo, champ harbor_version, identité requise).
_m13p_version() { _m13p_api systeminfo | jq -r '.harbor_version // empty' 2>/dev/null; }

# _m13p_version_ok — la version commence par la version attendue (« v2.15.3-abcdef » convient).
_m13p_version_ok() {
  local v
  v="$(_m13p_version)" || return 1
  [[ -n "$v" && "$v" == "$_M13P_VERSION"* ]]
}

# _m13p_meta PROJET — métadonnées du projet (JSON).
_m13p_meta() { _m13p_api "projects/$1" | jq -c '.metadata // {}' 2>/dev/null; }

# _m13p_projet_meta PROJET CLÉ VALEUR — la métadonnée vaut VALEUR (chaînes « true »/« false » de l'API).
_m13p_projet_meta() {
  local m
  m="$(_m13p_meta "$1")" || return 1
  _m13p_jq "$m" ".\"$2\" == \"$3\""
}

# _m13p_repo_existe PROJET DÉPÔT / _m13p_repo_absent PROJET DÉPÔT (le second échoue si l'API ne répond pas).
_m13p_repo_existe() { _m13p_api "projects/$1/repositories/$2" | jq -e '.name' >/dev/null 2>&1; }
_m13p_repos_motif_absents() {
  local l
  l="$(_m13p_api "projects/$1/repositories?page_size=100")" || return 1
  [[ -n "$l" ]] || return 1
  jq -e --arg m "$2" '[.[]? | .name | select(test($m))] | length == 0' >/dev/null 2>&1 <<<"$l"
}

# _m13p_derniere_version PROJET DÉPÔT [API] — artefact (JSON compact) le plus récemment poussé qui
# porte une étiquette vX.Y.Z, avec étiquettes, accessoires et résumé d'analyse. API : _m13p_api (défaut)
# ou _m13p_api2 (reg02).
_m13p_derniere_version() {
  local f="${3:-_m13p_api}" l
  l="$("$f" "projects/$1/repositories/$2/artifacts?with_tag=true&with_accessory=true&with_scan_overview=true&page_size=50&sort=-push_time")" || return 1
  jq -c '[.[]? | select(any(.tags[]?; .name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+")))] | sort_by(.push_time) | last // empty' <<<"$l" 2>/dev/null
}

# _m13p_digest_version PROJET DÉPÔT [API] — digest de la dernière version vX.Y.Z.
_m13p_digest_version() { _m13p_derniere_version "$@" | jq -r '.digest // empty' 2>/dev/null; }

# _m13p_signee JSON_ARTEFACT — au moins un accessoire de signature Cosign (type signature.cosign).
_m13p_signee() { _m13p_jq "$1" 'any(.accessories[]?; .type == "signature.cosign")'; }

# _m13p_sans_critique JSON_ARTEFACT — analyse terminée et sévérité maximale inférieure à Critical.
# Le résumé est indexé par type MIME du rapport ; on lit le premier.
_m13p_sans_critique() {
  _m13p_jq "$1" '(.scan_overview // {}) | to_entries | length > 0 and (.[0].value.scan_status == "Success")
    and ((.[0].value.severity // "None") | IN("Critical") | not)'
}

# --- Cosign (attestations) -------------------------------------------------------------------------

# _m13p_cle_publique FICHIER — écrit la clé publique MédiSphère (docs/registre/cosign.pub de main).
_m13p_cle_publique() {
  _m13p_fichier_main plateforme/medisphere docs/registre/cosign.pub >"$1" 2>/dev/null && grep -q 'PUBLIC KEY' "$1"
}

# _m13p_attestation_sbom IMAGE@DIGEST — imprime les paquets « nom version » du SBOM SPDX attesté et
# vérifié par la clé MédiSphère (cosign verify-attestation, sans journal de transparence). Configuration
# Docker temporaire avec le robot des checks (lecture), effacée en sortie. Échoue si rien n'est vérifié.
_m13p_attestation_sbom() {
  local img="$1" d f="${WB_HARBOR_CHECKS_FILE:-$HOME/.config/workbook/harbor-checks.env}" rc=0
  local HARBOR_USER="" HARBOR_PASSWORD=""
  command -v cosign >/dev/null 2>&1 || return 1
  [[ -r "$f" ]] || return 1
  # shellcheck disable=SC1090
  source "$f"
  d="$(mktemp -d)" || return 1
  (
    umask 077
    printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$_M13P_REGISTRE_NOM" \
      "$(printf '%s:%s' "$HARBOR_USER" "$HARBOR_PASSWORD" | base64 -w0)" >"$d/config.json"
    _m13p_cle_publique "$d/cosign.pub" || exit 1
    DOCKER_CONFIG="$d" timeout 60 cosign verify-attestation --key "$d/cosign.pub" --type spdxjson \
      --insecure-ignore-tlog=true "$img" 2>/dev/null \
      | jq -r '.payload | @base64d | fromjson | (.predicate.packages // .predicate.Data.packages // [])[] | "\(.name) \(.versionInfo // "")"' 2>/dev/null \
      | grep . || exit 1
  ) || rc=1
  rm -rf -- "$d"
  return "$rc"
}

# --- GitLab (jeton des checks, lecture) ---------------------------------------------------------------

_m13p_fichier_main() {
  local p="${1//\//%2F}" f="${2//\//%2F}"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m13p_doc_main CHEMIN REGEX... — le fichier existe sur main de plateforme/medisphere et contient chaque
# motif (grep -E, insensible à la casse).
_m13p_doc_main() {
  local c m chemin="$1"
  shift
  c="$(_m13p_fichier_main plateforme/medisphere "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m13p_fichier_motifs PROJET CHEMIN REGEX... — même chose pour un autre projet.
_m13p_fichier_motifs() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m13p_fichier_main "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m13p_doc_prefixe DOSSIER PRÉFIXE — un fichier « PRÉFIXE* » existe sous DOSSIER sur main de plateforme/medisphere.
_m13p_doc_prefixe() {
  local d="${1//\//%2F}"
  gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=$d&recursive=true&per_page=100" 2>/dev/null \
    | jq -e --arg p "$2" 'any(.[]?; .type == "blob" and (.name | startswith($p)))' >/dev/null
}

# _m13p_pipeline_ok PROJET — dernier pipeline de main réussi.
_m13p_pipeline_ok() {
  local p="${1//\//%2F}"
  gitlab_api "projects/$p/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null
}

# _m13p_job_reussi PROJET MOTIF — dans le DERNIER pipeline de main, un job dont le nom contient MOTIF a réussi.
_m13p_job_reussi() {
  local p="${1//\//%2F}" id
  id="$(gitlab_api "projects/$p/pipelines?ref=main&per_page=1" 2>/dev/null | jq -r '.[0].id // empty')" || return 1
  [[ -n "$id" ]] || return 1
  gitlab_api "projects/$p/pipelines/$id/jobs?per_page=100&include_retried=false" 2>/dev/null \
    | jq -e --arg m "$2" 'any(.[]?; (.name | contains($m)) and .status == "success")' >/dev/null
}

# --- Hôtes ------------------------------------------------------------------------------------------------

# _m13p_pbs_recent MOTIF_ARCHIVE HEURES — dans par1/registre du datastore ds-lab, une archive de moins de
# HEURES heures dont le nom correspond au motif (ex. « registre*.didx »). Lecture en root sur pbs01.
_m13p_pbs_recent() {
  remote "$WB_PBS_HOST" "
    p=\$(proxmox-backup-manager datastore show ds-lab --output-format json | sed -nE 's/.*\"path\" *: *\"([^\"]+)\".*/\1/p')
    [ -n \"\$p\" ] || exit 1
    find \"\$p/ns/par1/ns/registre\" -mindepth 4 -maxdepth 4 -type f -name '$1' -mmin -$(($2 * 60)) 2>/dev/null | grep -q ." \
    >/dev/null 2>&1
}

# _m13p_unite_recente HÔTE SERVICE HEURES — le dernier passage du service a réussi il y a moins de HEURES h.
_m13p_unite_recente() {
  # shellcheck disable=SC2016  # évalué sur l'hôte distant
  remote "$1" '
    r=$(systemctl show -p Result --value '"$2"'); t=$(systemctl show -p ExecMainExitTimestamp --value '"$2"')
    [ "$r" = success ] && [ -n "$t" ] || exit 1
    [ $(( $(date +%s) - $(date -d "$t" +%s) )) -lt $(('"$3"' * 3600)) ]' >/dev/null 2>&1
}

# _m13p_cert NOM PORT JOURS — chaîne vers la racine MédiSphère, nom vérifié, plus de JOURS jours restants.
_m13p_cert() {
  local pem
  pem="$(openssl s_client -connect "$1:$2" -servername "$1" -CAfile "$_M13P_RACINE" -verify_hostname "$1" \
    -verify_return_error </dev/null 2>/dev/null | openssl x509 2>/dev/null)" || return 1
  [[ -n "$pem" ]] && openssl x509 -noout -checkend $(($3 * 86400)) <<<"$pem" >/dev/null
}

# _m13p_vm_absente VMID — la VM n'existe plus (échoue si pve01 ne répond pas).
_m13p_vm_absente() {
  remote "$WB_PVE_HOST" "true" >/dev/null 2>&1 || return 1
  ! remote "$WB_PVE_HOST" "qm status $1" >/dev/null 2>&1
}

# _m13p_aucune_panne_active [EXX] — aucune panne M13 (ou M13-EXX) marquée par lab/bin/break.
_m13p_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"
  [[ -z "$(find "$d" -maxdepth 1 -name "M13-${1:-E}*" 2>/dev/null)" ]]
}
