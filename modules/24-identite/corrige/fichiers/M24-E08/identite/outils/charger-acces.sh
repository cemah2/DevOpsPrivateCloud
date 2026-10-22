# shellcheck shell=bash
# charger-acces.sh — accès OpenTofu de plateforme/identite pour la session courante sur adm01 (M24-E08).
# Modèle : outils/charger-acces.sh de plateforme/infra (M05-E27).
#
# À SOURCER depuis la racine du dépôt :   . outils/charger-acces.sh
# Charge, depuis ~/.config/workbook/ (fichiers en 600 uniquement) :
#   s3-tofu.env             AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (identité S3 tofu-etat, M05)
#   keycloak-tofu.env       KEYCLOAK_CLIENT_ID, KEYCLOAK_CLIENT_SECRET (client svc-tofu-keycloak de master)
#   tofu-chiffrement.pass   phrase de chiffrement de l'état → TF_ENCRYPTION (fournisseur « pbkdf2 etat »)
# et lit dans annuaire/vault-critique.yml (Ansible Vault « critique ») le mot de passe de
# svc-keycloak → TF_VAR_svc_keycloak_mot_de_passe (variable éphémère, jamais dans un plan).
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
  local f phrase mdp
  for f in s3-tofu.env keycloak-tofu.env; do
    _ca_lisible_600 "$_ca_dossier/$f" || return 1
    set -a
    # shellcheck source=/dev/null
    . "$_ca_dossier/$f"
    set +a
  done

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

  # Mot de passe de svc-keycloak : lu dans le Vault du dépôt, jamais écrit sur disque en clair.
  mdp="$(uv run ansible-vault view annuaire/vault-critique.yml 2>/dev/null \
    | sed -n 's/^vault_annuaire_svc_keycloak_mot_de_passe: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p')"
  if [[ -z "$mdp" ]]; then
    echo "charger-acces : mot de passe de svc-keycloak introuvable dans annuaire/vault-critique.yml" >&2
    return 1
  fi
  export TF_VAR_svc_keycloak_mot_de_passe="$mdp"
  echo "charger-acces : S3 (état), Keycloak ($KEYCLOAK_CLIENT_ID), chiffrement et svc-keycloak chargés."
}

_ca_charger
_ca_rc=$?
unset -f _ca_charger _ca_lisible_600
unset _ca_dossier
return "$_ca_rc"
