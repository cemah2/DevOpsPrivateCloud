# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E14.sh — M13-E14 « Politiques : signature obligatoire, vulnérabilités bloquantes »
# Lecture seule : métadonnées du projet medisphere et artefacts (API Harbor), gabarit de CI et pipeline
# (API GitLab), documentation.

# shellcheck source=_m13-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-production.sh"

title "M13-E14 — Politiques du projet medisphere"
require_cmd jq curl
check_cmd "medisphere : signature Cosign exigée" _m13p_projet_meta medisphere enable_content_trust_cosign true
check_cmd "medisphere : prévention des images vulnérables activée" _m13p_projet_meta medisphere prevent_vul true
check_cmd "medisphere : seuil « critical »" _m13p_projet_meta medisphere severity critical
check_cmd "medisphere : analyse automatique à la poussée" _m13p_projet_meta medisphere auto_scan true
check_cmd "medisphere : projet privé" _m13p_projet_meta medisphere public false

title "Images"
_m13_e14_a="$(_m13p_derniere_version medisphere mediagenda-api)" || _m13_e14_a=""
check_cmd "medisphere/mediagenda-api : une version v* existe" _m13p_jq "$_m13_e14_a" '.digest | startswith("sha256:")'
check_cmd "… elle est signée (accessoire signature.cosign)" _m13p_signee "$_m13_e14_a"
check_cmd "… elle est analysée, sans vulnérabilité critique" _m13p_sans_critique "$_m13_e14_a"
check_cmd "le dépôt d'essai medisphere/essai-politiques n'existe plus" _m13p_repos_motif_absents medisphere '(^|/)essai-politiques$'

title "Vérification par le consommateur"
check_cmd "plateforme/ci-templates : verification.yml contient un « cosign verify » par clé" \
  _m13p_fichier_motifs plateforme/ci-templates verification.yml 'cosign verify' '--key'
check_cmd "… et vérifie l'attestation SBOM (verify-attestation)" \
  _m13p_fichier_motifs plateforme/ci-templates verification.yml 'verify-attestation'
check_cmd "mediagenda/api : le dernier pipeline de main a réussi un job verifier-signature" \
  _m13p_job_reussi mediagenda/api verifier-signature
check_cmd "docs/registre/politiques.md sur main (messages de refus, exception)" \
  _m13p_doc_main docs/registre/politiques.md '412|precondition' 'cosign' 'exception|allowlist|liste blanche'
