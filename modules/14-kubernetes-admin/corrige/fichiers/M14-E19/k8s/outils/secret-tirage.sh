#!/usr/bin/env bash
# plateforme/k8s — outils/secret-tirage.sh (M14-E19)
# Crée ou met à jour le Secret « harbor-pull » (type kubernetes.io/dockerconfigjson) dans chaque
# espace donné, à partir des identifiants du robot Harbor robot$k8s-pull.
#
# Usage : outils/secret-tirage.sh ESPACE [ESPACE...]
#   ex.   outils/secret-tirage.sh mediagenda-dev mediagenda-recette
# Identifiants : ~/.config/workbook/harbor-k8s-pull.env (600), deux lignes, entre apostrophes
# (le « $ » du nom du robot ne doit pas être interprété) :
#   HARBOR_USER='robot$k8s-pull'
#   HARBOR_PASSWORD='<SECRET-DU-ROBOT>'
# Le secret ne passe ni par l'écran, ni par un fichier en clair, ni par la ligne de commande
# (jq lit les variables d'environnement, kubectl lit l'entrée standard). Le Secret n'est JAMAIS
# versionné : seul ce script l'est.
set -euo pipefail

(($# >= 1)) || { sed -n '3,9p' "$0" >&2; exit 2; }
fichier="${WB_HARBOR_K8S_PULL_FILE:-$HOME/.config/workbook/harbor-k8s-pull.env}"
registre="registry.par1.medisphere.internal"

[[ -r "$fichier" ]] || { echo "identifiants illisibles : $fichier" >&2; exit 1; }
[[ "$(stat -c %a "$fichier")" == 600 ]] || { echo "$fichier doit être en 600" >&2; exit 1; }
HARBOR_USER=""; HARBOR_PASSWORD=""
# shellcheck disable=SC1090
source "$fichier"
[[ -n "$HARBOR_USER" && -n "$HARBOR_PASSWORD" ]] || { echo "HARBOR_USER ou HARBOR_PASSWORD vide" >&2; exit 1; }
export HARBOR_USER HARBOR_PASSWORD REGISTRE="$registre"

for espace in "$@"; do
  # Format attendu par le kubelet : {"auths": {"<registre>": {"username", "password", "auth"}}}
  jq -n '{auths: {(env.REGISTRE): {username: env.HARBOR_USER, password: env.HARBOR_PASSWORD,
          auth: ((env.HARBOR_USER + ":" + env.HARBOR_PASSWORD) | @base64)}}}' \
    | kubectl create secret generic harbor-pull -n "$espace" \
        --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=/dev/stdin \
        --dry-run=client -o yaml \
    | kubectl label --local -f - -o yaml app.kubernetes.io/managed-by=secret-tirage.sh \
    | kubectl apply -f -
done
