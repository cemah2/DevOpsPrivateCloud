#!/usr/bin/env bash
# cible-sauvegarde.sh — Secret S3 de Longhorn et cible de sauvegarde « en aperçu » (M16-E15).
# Lit ~/.config/workbook/s3-longhorn-essai.env (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) et la
# racine MédiSphère ; aucune clé sur la ligne de commande ni dans un fichier temporaire.
#   cible-sauvegarde.sh poser | retirer
set -euo pipefail
env_fichier="$HOME/.config/workbook/s3-longhorn-essai.env"
ca=/usr/local/share/ca-certificates/medisphere-root-ca.crt
cible='s3://longhorn-essai@us-east-1/'

case "${1:-}" in
  poser)
    [[ "$(stat -c %a "$env_fichier")" == 600 ]] || { echo "$env_fichier doit être en 600" >&2; exit 1; }
    # shellcheck disable=SC1090
    source "$env_fichier"
    kubectl -n longhorn-system create secret generic longhorn-s3 \
      --from-file=AWS_ACCESS_KEY_ID=<(printf '%s' "$AWS_ACCESS_KEY_ID") \
      --from-file=AWS_SECRET_ACCESS_KEY=<(printf '%s' "$AWS_SECRET_ACCESS_KEY") \
      --from-literal=AWS_ENDPOINTS=https://s3-01.par1.medisphere.internal:8333 \
      --from-file=AWS_CERT="$ca" \
      --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n longhorn-system patch backuptargets.longhorn.io default --type merge \
      -p "{\"spec\":{\"backupTargetURL\":\"$cible\",\"credentialSecret\":\"longhorn-s3\"}}"
    ;;
  retirer)
    kubectl -n longhorn-system patch backuptargets.longhorn.io default --type merge \
      -p '{"spec":{"backupTargetURL":"","credentialSecret":""}}'
    kubectl -n longhorn-system delete secret longhorn-s3 --ignore-not-found
    ;;
  *) echo "usage : $0 poser|retirer" >&2; exit 2 ;;
esac
