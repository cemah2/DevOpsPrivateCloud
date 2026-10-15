# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E05.sh — M13-E05 : Analyser les images avec Trivy
# À lancer depuis adm01. Lecture seule : paquets et fichiers locaux (adm01), API de Harbor
# (wb-checks), GitLab en GET.

# shellcheck source=_m13-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-decouverte.sh"

title "M13-E05 — Analyser les images avec Trivy"
require_cmd jq

# --- Trivy sur adm01 -----------------------------------------------------------------------------
_m13_v="$(dpkg-query -W -f='${Version}' trivy 2>/dev/null || true)"
check_output "adm01 : paquet trivy en 0.75.x (installé : ${_m13_v:-absent})" '^0\.75\.' echo "$_m13_v"
_m13_pas_compromis() { ! command -v trivy >/dev/null 2>&1 || ! trivy --version 2>/dev/null | grep -Eq '0\.69\.[4-6]'; }
check_cmd "adm01 : aucune version compromise de Trivy (0.69.4 à 0.69.6)" _m13_pas_compromis
_m13_base() { trivy version --format json 2>/dev/null | jq -e '(.VulnerabilityDB.UpdatedAt // "") != ""' >/dev/null; }
check_cmd "adm01 : base de vulnérabilités de Trivy présente" _m13_base
_m13_role() {
  local d
  d="$(_m13d_contenu_main "$_M13D_ANSIBLE" roles/outils_supply_chain/defaults/main.yml)"
  grep -q 'trivy_0\.75\.0_Linux-64bit\.deb' <<<"$d" \
    && grep -Eq 'sha256: *"?b6d7b944b6cbf4e7de5b4bc6c3635900c50fed53b64b77b99a5fbc3136cd1d5d' <<<"$d" \
    && grep -q '0\.69\.4' <<<"$d"
}
check_cmd "plateforme/ansible (main) : outils_supply_chain épingle Trivy 0.75.0 par empreinte et interdit 0.69.4-0.69.6" _m13_role

# --- Rapports ----------------------------------------------------------------------------------------
# _m13_rapport_image DÉPÔT — un rapport JSON de Trivy de l'image medisphere/DÉPÔT dans ~/m13/e05.
_m13_rapport_image() {
  local f
  for f in "$_M13D_TRAVAIL"/e05/*.json; do
    [[ -s "$f" ]] || continue
    jq -e --arg n "$_M13D_NOM/medisphere/$1" \
      '(.SchemaVersion // 0) >= 2 and ((.ArtifactName // "") | startswith($n)) and (.ArtifactType // "") == "container_image"' \
      "$f" >/dev/null 2>&1 && return 0
  done
  return 1
}
for _m13_d in mediagenda-api medidoc medinotif legacy-rdv; do
  check_cmd "m13/e05 : rapport JSON Trivy de l'image medisphere/$_m13_d" _m13_rapport_image "$_m13_d"
done
_m13_config() {
  local f
  for f in "$_M13D_TRAVAIL"/e05/*.json; do
    [[ -s "$f" ]] || continue
    jq -e '[.Results[]? | select(.Class == "config")] | length >= 1' "$f" >/dev/null 2>&1 && return 0
  done
  return 1
}
check_cmd "m13/e05 : rapport « trivy config » (résultats de classe config)" _m13_config

# --- Exceptions -------------------------------------------------------------------------------------------
_m13_ignore() {
  local c prec="" l n=0
  c="$(_m13d_contenu_main "projects/mediagenda%2Fapi" .trivyignore)"
  [[ -n "$c" ]] || return 1
  while IFS= read -r l; do
    if [[ -z "${l//[[:space:]]/}" ]]; then prec=""; continue; fi
    if [[ "$l" =~ ^[[:space:]]*# ]]; then prec="$l"; continue; fi
    n=$((n + 1))
    # Chaque identifiant suit un commentaire qui porte une date de revue AAAA-MM-JJ.
    [[ "$prec" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]] || return 1
  done <<<"$c"
  (( n >= 1 ))
}
check_cmd "mediagenda/api (main) : .trivyignore dont chaque exception est commentée et datée" _m13_ignore

# --- Harbor -------------------------------------------------------------------------------------------------
_m13_scanner() { _m13d_api "scanners" | jq -e '[.[]? | select(.is_default == true and (.name | test("trivy"; "i")))] | length == 1' >/dev/null 2>&1; }
check_cmd "Harbor : Trivy est l'analyseur par défaut" _m13_scanner
_m13_planif() { _m13d_api "system/scanAll/schedule" | jq -e '((.schedule.type // "None") | IN("None", "")) | not' >/dev/null 2>&1; }
check_cmd "Harbor : analyse de tout le registre planifiée" _m13_planif
_m13_auto() { _m13d_projet medisphere | jq -e '.metadata.auto_scan == "true"' >/dev/null 2>&1; }
check_cmd "Harbor : analyse à la poussée active sur medisphere" _m13_auto
_m13_analyse() {
  _m13d_artefacts medisphere mediagenda-api \
    | jq -e '[.[]? | (.scan_overview // {}) | to_entries[] | select(.value.scan_status == "Success")] | length >= 1' >/dev/null 2>&1
}
check_cmd "Harbor : au moins un artefact de medisphere/mediagenda-api analysé avec succès" _m13_analyse
check_cmd "docs/registre/analyse.md sur main de plateforme/medisphere" _m13d_fichier_main "$_M13D_DOC" docs/registre/analyse.md
