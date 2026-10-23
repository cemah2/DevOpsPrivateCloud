# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E18.sh — M25-E18 « Des secrets chiffrés dans Git : SOPS, age et transit ».
# Vérifie : clé de transit sops-plateforme et politique sops-plateforme (chiffrer, déchiffrer, rien
# d'autre) ; dépôt formation/sops-labo : règles .sops.yaml (transit d'OpenBao + une seule clé age de
# secours), au moins un *.sops.yaml chiffré par SOPS 3.13.3 avec les deux destinataires et AUCUNE valeur
# en clair, contrôle CI au vert ; sops 3.13.3 et age sur adm01, liste d'autorisation de SOPS posée ;
# comparaison écrite.
# Lecture seule : rien n'est déchiffré (le check n'a aucun droit sur la clé de transit).

# shellcheck source=_m25-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel.sh"

title "M25-E18 — Des secrets chiffrés dans Git : SOPS, age et transit"
require_cmd jq yq curl

_m25c_e18_labo="${WB_M25_SOPS_LABO:-formation/sops-labo}"
_m25c_e18_uri="https://openbao.par1.medisphere.internal:8200/v1/transit/keys/sops-plateforme"

_m25c_e18_cle="$(_m25c_cle sops-plateforme)"
check_cmd "clé de transit sops-plateforme : aes256-gcm96, non exportable, non supprimable" \
  _m25c_json "$_m25c_e18_cle" '.type == "aes256-gcm96" and .exportable == false and .deletion_allowed == false'
_m25c_e18_pol="$(_m25c_politique sops-plateforme)"
check_cmd "politique sops-plateforme : encrypt et decrypt sur sops-plateforme, rien d'autre" \
  bash -c 'grep -q "path \"transit/encrypt/sops-plateforme\"" <<<"$1" && grep -q "path \"transit/decrypt/sops-plateforme\"" <<<"$1" \
    && [[ "$(grep -c "^path " <<<"$1")" -eq 2 ]]' _ "$_m25c_e18_pol"

if ! _m25c_projet "$_m25c_e18_labo"; then
  check_cmd "projet GitLab $_m25c_e18_labo" false
else
  _m25c_e18_regles="$(_m25c_contenu "$_m25c_e18_labo" .sops.yaml | yq -o=json '.' 2>/dev/null || true)"
  check_cmd ".sops.yaml : une règle chiffre data/stringData par la clé de transit d'OpenBao" \
    _m25c_json "$_m25c_e18_regles" '[.creation_rules[]? | select((.hc_vault_transit_uri // "") | contains($u))
      | select((.encrypted_regex // "") | test("stringData"))] | length > 0' --arg u "$_m25c_e18_uri"
  check_cmd ".sops.yaml : une seule clé age (la clé de secours de l'équipe ; les clés personnelles retirées)" \
    _m25c_json "$_m25c_e18_regles" '[.creation_rules[]? | select((.hc_vault_transit_uri // "") != "")
      | (.age // "") | (if type == "array" then . else split(",") end) | map(select(test("age1")))]
      | length > 0 and all(length == 1)'

  _m25c_e18_fichier="$(gitlab_api "projects/$(_m25c_uri "$_m25c_e18_labo")/repository/tree?ref=main&recursive=true&per_page=100&path=k8s" 2>/dev/null \
    | jq -r '[.[] | select(.type == "blob" and (.path | endswith(".sops.yaml"))) | .path][0] // empty' 2>/dev/null || true)"
  if [[ -z "$_m25c_e18_fichier" ]]; then
    check_cmd "au moins un fichier k8s/**/*.sops.yaml sur main" false
  else
    _m25c_e18_chiffre="$(_m25c_contenu "$_m25c_e18_labo" "$_m25c_e18_fichier" | yq -o=json '.' 2>/dev/null || true)"
    check_cmd "$_m25c_e18_fichier : chiffré par SOPS 3.13.3 (pas 3.13.2), MAC présent" \
      _m25c_json "$_m25c_e18_chiffre" '.sops.version == "3.13.3" and ((.sops.mac // "") | startswith("ENC[AES256_GCM,"))'
    check_cmd "$_m25c_e18_fichier : destinataires transit (sops-plateforme) ET une clé age" \
      _m25c_json "$_m25c_e18_chiffre" '([.sops.hc_vault[]? | select(.key_name == "sops-plateforme")] | length) == 1
        and ((.sops.age // []) | length) == 1'
    check_cmd "$_m25c_e18_fichier : aucune valeur en clair sous data/stringData" \
      _m25c_json "$_m25c_e18_chiffre" '[(.data, .stringData) | select(. != null) | .[]] as $v
        | ($v | length) > 0 and ($v | all(type == "string" and startswith("ENC[AES256_GCM,")))'
  fi
  _m25c_e18_pipeline() {
    gitlab_api "projects/$(_m25c_uri "$_m25c_e18_labo")/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1
  }
  check_cmd "$_m25c_e18_labo : contrôle « aucun secret en clair » au vert sur main" _m25c_e18_pipeline
fi

check_output "sops 3.13.3 installé sur adm01" '^sops 3\.13\.3' sops --version --disable-version-check
check_cmd "age installé sur adm01" age --version
check_cmd "SOPS_HC_VAULT_ALLOWLIST limitée au coffre de MédiSphère (~/.bashrc)" \
  grep -Eq '^[[:space:]]*export[[:space:]]+SOPS_HC_VAULT_ALLOWLIST=.?https://openbao\.par1\.medisphere\.internal:8200' "$HOME/.bashrc"
check_cmd "comparaison SOPS / ESO écrite ($_M25C_DOC_SECRETS/comparatif-livraison-k8s.md)" \
  _m25c_contient "$_M25C_P_DOC" "$_M25C_DOC_SECRETS/comparatif-livraison-k8s.md" 'SOPS'
