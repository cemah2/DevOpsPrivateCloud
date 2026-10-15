# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E28.sh — M16-E28 « Mesurer les performances des volumes »
# Lecture seule : image dans Harbor (API, robot des checks), objets de mesure restants dans
# wb-essais, script du banc et résultats (API GitLab).

# shellcheck source=_m16-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-production.sh"

title "M16-E28 — Mesurer les performances des volumes"
require_cmd jq kubectl curl

title "Image du banc"
# Accessoires (signature Cosign) : présentation par l'API de Harbor 2.15 à confirmer sur ton lab
# (accessoire « signature.cosign » ou référent OCI).
_m16_e28_art="$(harbor_api 'projects/plateforme/repositories/outils-stockage/artifacts/1.0.0?with_accessory=true' 2>/dev/null || echo null)"
check_cmd "plateforme/outils-stockage:1.0.0 est dans Harbor" _m16p_jq "$_m16_e28_art" '.digest | startswith("sha256:")'
check_cmd "l'image est signée (accessoire de signature)" \
  _m16p_jq "$_m16_e28_art" 'any(.accessories[]?; (.type // "") | test("signature"))'

title "Banc et résultats"
check_cmd "plateforme/k8s : script du banc sur main (profils wal, oltp, iops, debit)" \
  _m16p_recherche_main plateforme/k8s "fdatasync"
check_cmd "performances.md : quatre profils et les cibles ceph-rbd, ceph-rbd-chiffre, cephfs, emptyDir" \
  _m16p_doc_main docs/kubernetes/stockage/tests/performances.md '\bwal\b' 'oltp' 'iops' 'debit|débit' \
  'ceph-rbd-chiffre' 'cephfs' 'emptyDir' 'longhorn'
check_cmd "performances.md : interprétation (surcoût, LUKS, limites du lab)" \
  _m16p_doc_main docs/kubernetes/stockage/tests/performances.md 'LUKS' 'p99' 'ne permet pas|limite'

title "Nettoyage"
check_cmd "aucun Job, pod ou PVC de mesure dans wb-essais" \
  _m16p_jq "$(_m16p_kj jobs,pods,pvc -n wb-essais -l medisphere.internal/banc=oui)" '(.items | length) == 0'
check_cmd "le volume témoin e26-temoin a été supprimé" \
  _m16p_jq "$(_m16p_kj pvc -n wb-essais)" 'all(.items[]?; .metadata.name != "e26-temoin")'
