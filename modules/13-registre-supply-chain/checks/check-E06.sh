# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E06.sh — M13-E06 : SBOM avec Syft, analyse avec Grype
# À lancer depuis adm01. Lecture seule : paquets et fichiers locaux, API de Harbor, GitLab.

# shellcheck source=_m13-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-operationnel.sh"

title "M13-E06 — SBOM avec Syft, analyse avec Grype"
require_cmd jq

_m13_s="$(dpkg-query -W -f='${Version}' syft 2>/dev/null || true)"
_m13_g="$(dpkg-query -W -f='${Version}' grype 2>/dev/null || true)"
check_output "adm01 : paquet syft en 1.54.x (installé : ${_m13_s:-absent})" '^1\.54\.' echo "$_m13_s"
check_output "adm01 : paquet grype en 0.120.x (installé : ${_m13_g:-absent})" '^0\.120\.' echo "$_m13_g"
_m13_db() { grype db status -o json 2>/dev/null | jq -e '(.schemaVersion // "" | tostring | test("^v?6")) and (.valid // false)' >/dev/null 2>&1; }
check_cmd "adm01 : base de Grype valide, schéma v6" _m13_db
_m13_role() {
  local d
  d="$(_m13d_contenu_main "$_M13D_ANSIBLE" roles/outils_supply_chain/defaults/main.yml)"
  grep -q 'syft_1\.54\.1_checksums\.txt\.sigstore\.json' <<<"$d" && grep -q 'grype_0\.120\.1_checksums\.txt\.sigstore\.json' <<<"$d"
}
check_cmd "plateforme/ansible (main) : Syft et Grype vérifiés par leur fichier d'empreintes signé" _m13_role

for _m13_d in "${_M13O_APPS[@]}"; do
  _m13_f="$_M13D_TRAVAIL/e06/$_m13_d"
  check_cmd "m13/e06 : $_m13_d.spdx.json est une SBOM SPDX 2.3 non vide" \
    jq -e '.spdxVersion == "SPDX-2.3" and (.packages | length) > 0' "$_m13_f.spdx.json"
  check_cmd "m13/e06 : $_m13_d.cdx.json est une SBOM CycloneDX non vide" \
    jq -e '.bomFormat == "CycloneDX" and (.components | length) > 0' "$_m13_f.cdx.json"
  check_cmd "m13/e06 : $_m13_d.grype.json est un rapport Grype" \
    jq -e 'has("matches") and (.descriptor.name // "") == "grype"' "$_m13_f.grype.json"
done

_m13_auto() { _m13d_projet medisphere | jq -e '.metadata.auto_sbom_generation == "true"' >/dev/null 2>&1; }
check_cmd "Harbor : génération de SBOM à la poussée active sur medisphere" _m13_auto
_m13_sbom() {
  _m13d_artefacts medisphere mediagenda-api | jq -e '
    [.[]? | select(((.sbom_overview.scan_status // "") == "Success")
                   or ([.accessories[]?.type] | any(test("sbom"; "i"))))] | length >= 1' >/dev/null 2>&1
}
check_cmd "Harbor : un artefact de medisphere/mediagenda-api a une SBOM produite par Harbor" _m13_sbom
check_cmd "docs/registre/comparaison-analyseurs.md sur main" _m13o_doc docs/registre/comparaison-analyseurs.md
