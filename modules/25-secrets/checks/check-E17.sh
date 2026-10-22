# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E17.sh — M25-E17 « Transit : le chiffrement comme service ».
# Vérifie : moteur transit monté ; clé medictl-donnees non exportable, sans sauvegarde en clair, non
# supprimable, tournée au moins une fois, rotation automatique annuelle, aucune version gelée ; clé
# d'essai supprimée ; politique medictl limitée à encrypt/decrypt/rewrap de SA clé ; l'export de
# travail ~/m25/e17/fiche-intervention.json chiffré à la DERNIÈRE version ; module transit de medictl
# et note transit.md sur main.
# Lecture seule : OpenBao (wb-checks : métadonnées des clés, jamais de chiffrement ni de déchiffrement),
# GitLab, fichier local.

# shellcheck source=_m25-operationnel-c.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel-c.sh"

title "M25-E17 — Transit : le chiffrement comme service"
require_cmd jq curl

check_cmd "moteur transit monté en transit/" _m25c_montage "transit/" "transit"

_m25c_e17_cle="$(_m25c_cle medictl-donnees)"
if [[ -z "$_m25c_e17_cle" ]]; then
  check_cmd "clé medictl-donnees lisible par wb-checks (absente, ou politique wb-checks sans transit/keys/+)" false
else
  check_cmd "medictl-donnees : aes256-gcm96, non exportable, sans sauvegarde en clair, non supprimable" \
    _m25c_json "$_m25c_e17_cle" '.type == "aes256-gcm96" and .exportable == false
      and .allow_plaintext_backup == false and .deletion_allowed == false'
  check_cmd "medictl-donnees : rotation automatique d'un an (auto_rotate_period)" \
    _m25c_json "$_m25c_e17_cle" '(.auto_rotate_period // 0) == 31536000'
  check_cmd "medictl-donnees : au moins une rotation faite (latest_version ≥ 2)" \
    _m25c_json "$_m25c_e17_cle" '.latest_version >= 2'
  check_cmd "medictl-donnees : aucune version gelée par erreur (min_decryption_version = 1)" \
    _m25c_json "$_m25c_e17_cle" '.min_decryption_version == 1'
fi

_m25c_e17_cles="$(_m25c_cles)"
if [[ -z "$_m25c_e17_cles" ]]; then
  check_cmd "liste des clés de transit lisible par wb-checks" false
else
  check_cmd "clé d'essai essai-e17 supprimée" bash -c '! grep -qx essai-e17 <<<"$1"' _ "$_m25c_e17_cles"
fi

_m25c_e17_pol="$(_m25c_politique medictl)"
check_cmd "politique medictl : encrypt, decrypt et rewrap sur transit/…/medictl-donnees" \
  bash -c 'for op in encrypt decrypt rewrap; do grep -Eq "path \"transit/$op/medictl-donnees\"" <<<"$1" || exit 1; done' _ "$_m25c_e17_pol"
check_cmd "politique medictl : aucun droit sur transit/keys, export, backup ni sur d'autres clés" \
  bash -c '[[ -n "$1" ]] && ! grep -Eq "path \"transit/(keys|export|backup|restore)|path \"transit/[^\"]*(\\*|\\+)" <<<"$1"' _ "$_m25c_e17_pol"

# L'export de travail : chaque champ chiffré l'est à la dernière version de la clé (rewrap fait).
_m25c_e17_fiche="$(_m25c_travail e17/fiche-intervention.json)"
_m25c_e17_derniere="$(jq -r '.latest_version // empty' <<<"$_m25c_e17_cle" 2>/dev/null || true)"
if [[ ! -r "$_m25c_e17_fiche" ]]; then
  check_cmd "fiche d'intervention chiffrée présente ($_m25c_e17_fiche)" false
else
  check_cmd "fiche d'intervention : code_baie et astreinte_tel chiffrés partout (aucune valeur en clair)" \
    jq -e '[(if type == "array" then .[] else . end) | (.code_baie, .astreinte_tel) | select(. != null)]
           | length > 0 and all(test("^vault:v[0-9]+:"))' "$_m25c_e17_fiche"
  check_cmd "fiche d'intervention : tous les chiffrés à la dernière version de la clé (v${_m25c_e17_derniere:-?})" \
    jq -e --arg v "vault:v${_m25c_e17_derniere:-x}:" '[(if type == "array" then .[] else . end)
           | (.code_baie, .astreinte_tel) | select(. != null)] | length > 0 and all(startswith($v))' "$_m25c_e17_fiche"
fi

_m25c_e17_outils() { _m25c_fichier "$_M25C_P_OUTILS" src/medictl/transit.py && _m25c_fichier "$_M25C_P_OUTILS" tests/python/test_transit.py; }
check_cmd "plateforme/outils : module medictl transit sur main (src/medictl/transit.py et ses tests)" _m25c_e17_outils
check_cmd "plateforme/secrets : moteur et clés de transit décrits en code (tofu/transit.tf)" \
  _m25c_contient "$_M25C_P_SECRETS" tofu/transit.tf 'vault_transit_secret_backend_key'
check_cmd "documentation : $_M25C_DOC_SECRETS/transit.md (quand chiffrer, rotation, crypto-effacement)" \
  _m25c_contient "$_M25C_P_DOC" "$_M25C_DOC_SECRETS/transit.md" 'min_decryption_version'
