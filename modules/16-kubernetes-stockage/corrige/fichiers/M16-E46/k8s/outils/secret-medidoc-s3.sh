#!/usr/bin/env bash
# outils/secret-medidoc-s3.sh (plateforme/k8s) — Secret medidoc-dev/medidoc-s3 depuis
# ~/.config/workbook/s3-medidoc-app.env (compte RGW medidoc-app, M08-E12). M16-E46.
# Le fichier contient AWS_ACCESS_KEY_ID=… et AWS_SECRET_ACCESS_KEY=… ; rien n'est affiché ni écrit.
# Usage : outils/secret-medidoc-s3.sh [ESPACE]   (défaut : medidoc-dev)
set -Eeuo pipefail
umask 077
espace="${1:-medidoc-dev}"
fichier="${MS_S3_MEDIDOC_ENV:-$HOME/.config/workbook/s3-medidoc-app.env}"
[[ -r "$fichier" ]] || { echo "illisible : $fichier" >&2; exit 2; }
[[ "$(stat -c %a "$fichier")" == 600 ]] || { echo "$fichier doit être en 600" >&2; exit 2; }
# Lecture dans un sous-shell : les variables ne restent pas dans l'environnement appelant.
(
  set -a
  # shellcheck disable=SC1090
  . "$fichier"
  set +a
  : "${AWS_ACCESS_KEY_ID:?absent de $fichier}" "${AWS_SECRET_ACCESS_KEY:?absent de $fichier}"
  kubectl create secret generic medidoc-s3 --namespace "$espace" \
    --from-file=AWS_ACCESS_KEY_ID=<(printf '%s' "$AWS_ACCESS_KEY_ID") \
    --from-file=AWS_SECRET_ACCESS_KEY=<(printf '%s' "$AWS_SECRET_ACCESS_KEY") \
    --dry-run=client -o yaml \
    | kubectl label --local -f - -o yaml medisphere.fr/source=workbook-config \
    | kubectl apply --server-side --field-manager=secret-medidoc-s3 -f - >/dev/null
)
echo "Secret $espace/medidoc-s3 à jour (aucune valeur affichée)"
