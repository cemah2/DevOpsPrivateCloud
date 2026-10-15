# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E07.sh — M13-E07 : Signer et vérifier avec Cosign
# À lancer depuis adm01. Lecture seule : GitLab en GET (fichiers, recherche, variables), API de
# Harbor et cosign verify avec wb-checks (dossier d'authentification temporaire).

# shellcheck source=_m13-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-operationnel.sh"

title "M13-E07 — Signer et vérifier avec Cosign"
require_cmd jq cosign

check_output "adm01 : Cosign 3.1.x" 'GitVersion: *v?3\.1\.' cosign version
_m13_pub() { grep -q 'BEGIN PUBLIC KEY' "$(_m13d_cle_publique)"; }
check_cmd "plateforme/medisphere (main) : docs/registre/cosign.pub est une clé publique" _m13_pub
_m13_sc() {
  _m13d_contenu_main "$_M13D_DOC" docs/registre/signing-config.json \
    | jq -e '(.mediaType | startswith("application/vnd.dev.sigstore.signingconfig"))
             and ((.rekorTlogUrls // []) + (.tsaUrls // []) + (.caUrls // []) + (.oidcUrls // []) | length == 0)' >/dev/null 2>&1
}
check_cmd "signing-config.json (main) : configuration de signature sans journal ni autorité publique" _m13_sc
check_cmd "docs/registre/signature.md sur main" _m13o_doc docs/registre/signature.md

# Aucune clé privée Cosign en clair dans les dépôts de la plateforme et des applications.
_m13_sans_cle() {
  local p r
  for p in plateforme%2Fmedisphere plateforme%2Fansible plateforme%2Fci-templates mediagenda%2Fapi medidoc%2Fmedidoc medinotif%2Fworker legacy%2Flegacy-rdv; do
    r="$(gitlab_api "projects/$p/search?scope=blobs&search=PRIVATE%20KEY-----&ref=main" 2>/dev/null)" || return 1
    jq -e '[.[]? | select(.data | test("BEGIN (ENCRYPTED )?(SIGSTORE|COSIGN) PRIVATE KEY"))] | length == 0' <<<"$r" >/dev/null 2>&1 || return 1
  done
}
check_cmd "aucune clé privée Cosign en clair dans les dépôts (main)" _m13_sans_cle
_m13_vault() {
  _m13d_contenu_main "$_M13D_ANSIBLE" secrets/cosign/cosign.key | head -n 1 | grep -Eq '^\$ANSIBLE_VAULT;1\.[12];AES256;critique'
}
check_cmd "plateforme/ansible (main) : secrets/cosign/cosign.key chiffré (Vault critique)" _m13_vault
_m13_registre() { grep -qi 'cosign' "${WB_DEPOT:-$HOME/medisphere}/docs/socle/registre-secrets.md" 2>/dev/null; }
check_cmd "registre des secrets : clé Cosign inscrite" _m13_registre

for _m13_d in "${_M13O_APPS[@]}"; do
  _m13_ref="$(_m13o_ref_version "$_m13_d")"
  if [[ -z "$_m13_ref" ]]; then
    _ko "medisphere/$_m13_d : aucune version étiquetée trouvée"
    continue
  fi
  check_cmd "medisphere/$_m13_d (dernière version) : signature vérifiée avec la clé publiée" _m13d_cosign_verifie "$_m13_ref"
done

for _m13_g in "${_M13O_GROUPES[@]}"; do
  check_cmd "groupe $_m13_g : COSIGN_PRIVATE_KEY de type fichier, protégée" \
    jq -e '.variable_type == "file" and .protected == true' <<<"$(_m13o_var_groupe "$_m13_g" COSIGN_PRIVATE_KEY)"
  check_cmd "groupe $_m13_g : COSIGN_PASSWORD protégée et masquée" \
    jq -e '.protected == true and .masked == true' <<<"$(_m13o_var_groupe "$_m13_g" COSIGN_PASSWORD)"
done
