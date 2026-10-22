# shellcheck shell=bash
# ci-preparer.sh — environnement commun des jobs OpenTofu de plateforme/identite (M24-E08).
# Modèle : outils/ci-preparer.sh de plateforme/infra (M05-E26, M05-E27). À SOURCER dans le
# before_script (« . outils/ci-preparer.sh »). Ne jamais lancer un job avec « set -x ».
#
# Variables du projet, toutes PROTÉGÉES (branches protégées et MR issues de conf/*) :
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY  (masquée, cachée)  identité S3 tofu-etat
#   KEYCLOAK_CLIENT_ID                                           svc-tofu-keycloak
#   KEYCLOAK_CLIENT_SECRET                    (masquée, cachée)  son secret
#   TF_VAR_svc_keycloak_mot_de_passe          (masquée, cachée)  mot de passe de svc-keycloak (annuaire)
#   TOFU_PHRASE_CHIFFREMENT                   (masquée, cachée)  64 caractères hexadécimaux (M05-E27)

if [ "$(id -un)" != "gitlab-runner" ]; then
  echo "ci-preparer : ce job doit tourner sous gitlab-runner (runner01), pas sous $(id -un)" >&2
  return 1
fi

export TF_IN_AUTOMATION=1
export TF_INPUT=0

if [ -n "${TOFU_PHRASE_CHIFFREMENT:-}" ]; then
  case "$TOFU_PHRASE_CHIFFREMENT" in
    *[!0-9a-f]*)
      echo "ci-preparer : TOFU_PHRASE_CHIFFREMENT doit être hexadécimale (openssl rand -hex 32)" >&2
      return 1 ;;
  esac
  # Guillemets VOULUS (le contenu est du HCL, pas du shell) :
  # shellcheck disable=SC2089,SC2090
  printf -v TF_ENCRYPTION 'key_provider "pbkdf2" "etat" { passphrase = "%s" }' "$TOFU_PHRASE_CHIFFREMENT"
  # shellcheck disable=SC2090
  export TF_ENCRYPTION
fi

if [ -n "${KEYCLOAK_CLIENT_SECRET:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "ci-preparer : accès Keycloak et S3 disponibles (branche protégée)."
  if [ -z "${TF_ENCRYPTION:-}" ] || [ -z "${TF_VAR_svc_keycloak_mot_de_passe:-}" ]; then
    echo "ci-preparer : TOFU_PHRASE_CHIFFREMENT ou TF_VAR_svc_keycloak_mot_de_passe absente" >&2
    return 1
  fi
else
  echo "ci-preparer : aucun accès Keycloak ni S3 (branche non protégée, ou job qui n'en a pas besoin)."
fi
tofu version | head -n 1
