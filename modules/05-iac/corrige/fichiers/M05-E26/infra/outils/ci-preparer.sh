# shellcheck shell=bash
# ci-preparer.sh — environnement commun des jobs OpenTofu de plateforme/infra (M05-E26).
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
#     branche protégée : on ne fait que le signaler.

if [ "$(id -un)" != "gitlab-runner" ]; then
  echo "ci-preparer : ce job doit tourner sous gitlab-runner (runner01), pas sous $(id -un)" >&2
  return 1
fi

export TF_IN_AUTOMATION=1
export TF_INPUT=0

export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.https://gitlab-ci-token:${CI_JOB_TOKEN}@git01.par1.medisphere.internal/.insteadOf"
export GIT_CONFIG_VALUE_0="https://git01.par1.medisphere.internal/"

if [ -n "${PROXMOX_VE_API_TOKEN:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "ci-preparer : accès Proxmox et S3 disponibles (branche protégée)."
else
  echo "ci-preparer : aucun accès Proxmox ni S3 (branche non protégée, ou job qui n'en a pas besoin)."
fi
tofu version | head -n 1
