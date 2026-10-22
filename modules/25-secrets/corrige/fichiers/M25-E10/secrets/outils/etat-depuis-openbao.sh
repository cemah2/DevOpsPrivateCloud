# shellcheck shell=bash
# outils/etat-depuis-openbao.sh — accès à l'état OpenTofu de plateforme/secrets, lus dans le coffre
# (M25-E10). À SOURCER après outils/openbao-ci.sh (jeton présent dans BAO_TOKEN).
# kv/plateforme/tofu/etat-secrets : clés AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (identité S3
# tofu-etat) et TOFU_PHRASE_CHIFFREMENT (la phrase de ~/.config/workbook/tofu-chiffrement.pass du
# palier 1, mêmes règles que outils/charger-acces.sh). Rien n'est affiché.

_etat_json="$(bao kv get -format=json -mount=kv plateforme/tofu/etat-secrets)" || {
  echo "etat-depuis-openbao : lecture de kv/plateforme/tofu/etat-secrets refusée" >&2
  return 1
}
AWS_ACCESS_KEY_ID="$(jq -r '.data.data.AWS_ACCESS_KEY_ID // empty' <<<"$_etat_json")"
AWS_SECRET_ACCESS_KEY="$(jq -r '.data.data.AWS_SECRET_ACCESS_KEY // empty' <<<"$_etat_json")"
_etat_phrase="$(jq -r '.data.data.TOFU_PHRASE_CHIFFREMENT // empty' <<<"$_etat_json")"
unset _etat_json
if [[ ${#_etat_phrase} -lt 16 || ! "$_etat_phrase" =~ ^[A-Za-z0-9+/=._-]+$ ]]; then
  echo "etat-depuis-openbao : TOFU_PHRASE_CHIFFREMENT absente, trop courte ou caractères non admis" >&2
  return 1
fi
# Guillemets VOULUS (le contenu est du HCL, pas du shell) :
# shellcheck disable=SC2089,SC2090
printf -v TF_ENCRYPTION 'key_provider "pbkdf2" "etat" { passphrase = "%s" }' "$_etat_phrase"
unset _etat_phrase
# shellcheck disable=SC2090
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_ENCRYPTION
echo "etat-depuis-openbao : accès à l'état chargés."
