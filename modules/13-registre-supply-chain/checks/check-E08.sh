# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E08.sh — M13-E08 : Attestations : SBOM et provenance attachés à l'image
# À lancer depuis adm01. Lecture seule : cosign verify-attestation avec wb-checks, GitLab.

# shellcheck source=_m13-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-operationnel.sh"

title "M13-E08 — Attestations : SBOM et provenance attachés à l'image"
require_cmd jq cosign

_m13_ref="$(_m13o_ref_version mediagenda-api)"
if [[ -z "$_m13_ref" ]]; then
  _ko "medisphere/mediagenda-api : aucune version étiquetée trouvée"
else
  check_cmd "mediagenda-api (dernière version) : attestation SPDX vérifiée avec la clé publiée" \
    _m13d_attestation_verifiee "$_m13_ref" spdxjson
  check_cmd "mediagenda-api (dernière version) : attestation CycloneDX vérifiée avec la clé publiée" \
    _m13d_attestation_verifiee "$_m13_ref" cyclonedx
fi
_m13_doc() { _m13d_contenu_main "$_M13D_DOC" docs/registre/signature.md | grep -qiE '^#+ .*attestation'; }
check_cmd "docs/registre/signature.md (main) : section sur les attestations" _m13_doc
_m13_prov() { _m13d_contenu_main "$_M13D_DOC" docs/registre/signature.md | grep -qi 'provenance'; }
check_cmd "docs/registre/signature.md (main) : la provenance y est traitée" _m13_prov
