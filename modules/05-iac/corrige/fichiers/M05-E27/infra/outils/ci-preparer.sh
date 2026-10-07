# shellcheck shell=bash
# ci-preparer.sh — environnement commun des jobs OpenTofu de plateforme/infra
# (M05-E26, chiffrement de l'état ajouté en M05-E27).
#
# À SOURCER dans le before_script des jobs (« . outils/ci-preparer.sh ») : il exporte des
# variables pour la suite du job. Ne jamais lancer un job avec « set -x » : les secrets
# passeraient dans le journal (GitLab ne masque que les valeurs exactes des variables masquées).
#
# Ce qu'il prépare :
#   - garde-fou : on tourne sous gitlab-runner, sur runner01 ;
#   - OpenTofu en mode automatisé, sans question ;
#   - accès en lecture aux modules de plateforme/tofu-modules avec le jeton du job (M05-E14),
#     limité au processus du job (aucun fichier de configuration Git modifié) ;
#   - les secrets (PROXMOX_VE_*, AWS_*) sont déjà dans l'environnement s'il s'agit d'une
#     branche protégée : on ne fait que le signaler ;
#   - TF_ENCRYPTION (fournisseur de clé « pbkdf2 etat ») construit à partir de la variable CI
#     protégée, masquée et cachée TOFU_PHRASE_CHIFFREMENT (64 caractères hexadécimaux). On ne
#     peut pas masquer TF_ENCRYPTION elle-même (espaces, guillemets) : GitLab masque en revanche
#     la phrase partout où elle apparaîtrait dans le journal.

if [ "$(id -un)" != "gitlab-runner" ]; then
  echo "ci-preparer : ce job doit tourner sous gitlab-runner (runner01), pas sous $(id -un)" >&2
  return 1
fi

export TF_IN_AUTOMATION=1
export TF_INPUT=0

export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.https://gitlab-ci-token:${CI_JOB_TOKEN}@git01.par1.medisphere.internal/.insteadOf"
export GIT_CONFIG_VALUE_0="https://git01.par1.medisphere.internal/"

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

if [ -n "${PROXMOX_VE_API_TOKEN:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "ci-preparer : accès Proxmox et S3 disponibles (branche protégée)."
  if [ -z "${TF_ENCRYPTION:-}" ]; then
    echo "ci-preparer : TOFU_PHRASE_CHIFFREMENT absente : les états chiffrés seront illisibles" >&2
    return 1
  fi
else
  echo "ci-preparer : aucun accès Proxmox ni S3 (branche non protégée, ou job qui n'en a pas besoin)."
fi
tofu version | head -n 1
