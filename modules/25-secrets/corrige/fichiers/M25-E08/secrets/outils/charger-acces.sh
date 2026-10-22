# shellcheck shell=bash
# charger-acces.sh — accès OpenTofu de plateforme/secrets pour la session courante sur adm01 (M25-E08).
# Modèle : outils/charger-acces.sh de plateforme/identite (M24-E08).
#
# À SOURCER depuis la racine du dépôt :   . outils/charger-acces.sh
# Charge, depuis ~/.config/workbook/ (fichiers en 600 uniquement) :
#   s3-tofu.env             AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (identité S3 tofu-etat, M05)
#   tofu-chiffrement.pass   phrase de chiffrement de l'état → TF_ENCRYPTION (fournisseur « pbkdf2 etat »)
# et VÉRIFIE (sans le lire ni l'afficher) le jeton OpenBao de la session : celui que
# « bao login -method=oidc » a rangé dans ~/.vault-token, que le fournisseur hashicorp/vault lit seul.
# Refuse un jeton racine, un jeton expiré ou un jeton sans la politique plateforme-admin.
# N'affiche jamais un secret. Retourne 1 (sans quitter ton shell) si quelque chose manque.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "charger-acces : à sourcer (« . outils/charger-acces.sh »), pas à exécuter" >&2
  exit 2
fi

_ca_dossier="$HOME/.config/workbook"

_ca_lisible_600() {
  [[ -r "$1" ]] || { echo "charger-acces : $1 introuvable ou illisible" >&2; return 1; }
  [[ "$(stat -c %a "$1")" == "600" ]] || { echo "charger-acces : $1 doit être en 600 (chmod 600)" >&2; return 1; }
}

_ca_charger() {
  local phrase infos
  _ca_lisible_600 "$_ca_dossier/s3-tofu.env" || return 1
  set -a
  # shellcheck source=/dev/null
  . "$_ca_dossier/s3-tofu.env"
  set +a

  _ca_lisible_600 "$_ca_dossier/tofu-chiffrement.pass" || return 1
  phrase="$(tr -d '\n' < "$_ca_dossier/tofu-chiffrement.pass")"
  if [[ ${#phrase} -lt 16 || ! "$phrase" =~ ^[A-Za-z0-9+/=._-]+$ ]]; then
    echo "charger-acces : phrase de chiffrement trop courte ou caractères non admis" >&2
    return 1
  fi
  # Guillemets VOULUS (le contenu est du HCL, pas du shell) :
  # shellcheck disable=SC2089,SC2090
  printf -v TF_ENCRYPTION 'key_provider "pbkdf2" "etat" { passphrase = "%s" }' "$phrase"
  # shellcheck disable=SC2090
  export TF_ENCRYPTION

  # Le jeton : une variable VAULT_TOKEN ou BAO_TOKEN oubliée dans le shell passerait AVANT
  # ~/.vault-token ; on n'en veut pas (c'est souvent le jeton racine d'E03 à E07).
  if [[ -n "${VAULT_TOKEN:-}" || -n "${BAO_TOKEN:-}" ]]; then
    echo "charger-acces : VAULT_TOKEN ou BAO_TOKEN est défini dans ce shell : « unset VAULT_TOKEN BAO_TOKEN » puis « bao login -method=oidc »" >&2
    return 1
  fi
  if ! infos="$(bao token lookup -format=json 2>/dev/null)"; then
    echo "charger-acces : pas de jeton OpenBao valable : « bao login -method=oidc » (BAO_ADDR=${BAO_ADDR:-non défini})" >&2
    return 1
  fi
  if jq -e '.data.policies | index("root")' <<<"$infos" >/dev/null; then
    echo "charger-acces : le jeton de la session est un jeton RACINE : jamais pour OpenTofu ; connecte-toi par OIDC" >&2
    return 1
  fi
  if ! jq -e '[.data.policies[], (.data.identity_policies // [])[]] | index("plateforme-admin")' <<<"$infos" >/dev/null; then
    echo "charger-acces : le jeton n'a pas la politique plateforme-admin (groupe plateforme-admins de Keycloak)" >&2
    return 1
  fi
  echo "charger-acces : S3 (état), chiffrement et jeton OpenBao ($(jq -r '.data.display_name' <<<"$infos"), $(jq -r '.data.ttl' <<<"$infos") s restantes) prêts."
}

_ca_charger
_ca_rc=$?
unset -f _ca_charger _ca_lisible_600
unset _ca_dossier
return "$_ca_rc"
