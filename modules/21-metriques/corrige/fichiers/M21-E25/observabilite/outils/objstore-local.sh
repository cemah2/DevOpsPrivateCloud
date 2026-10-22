#!/usr/bin/env bash
# outils/objstore-local.sh — fabrique, sur adm01, une configuration objstore de Thanos pour LIRE le
# compartiment thanos-k8s-par1 avec « thanos tools bucket ls|inspect|web » (M21-E25, PLAT-2225).
# Lit ~/.config/workbook/s3-thanos.env (600), écrit un fichier 600 dans un dossier 700 de
# $XDG_RUNTIME_DIR (mémoire, effacé à la déconnexion) et affiche son chemin. Rien sur la sortie
# n'est secret. Usage :
#   cfg="$(outils/objstore-local.sh)"
#   thanos tools bucket inspect --objstore.config-file="$cfg"
#   thanos tools bucket web --objstore.config-file="$cfg" --http-address=127.0.0.1:10902
#   rm -f "$cfg"
# ⚠️ L'identité « thanos » peut aussi ÉCRIRE et SUPPRIMER : n'utilise ici que les sous-commandes de
# lecture (ls, inspect, web, verify sans --repair). Jamais « cleanup », « mark », « rewrite »,
# « retention » à la main : c'est le travail du Compactor, et deux acteurs = blocs perdus.
set -euo pipefail

env_fichier="${WB_M21_S3_THANOS_FILE:-$HOME/.config/workbook/s3-thanos.env}"
racine="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"

[[ -r "$env_fichier" ]] || { echo "illisible : $env_fichier" >&2; exit 1; }
[[ "$(stat -c %a "$env_fichier")" == 600 ]] || { echo "$env_fichier doit être en 600" >&2; exit 1; }
[[ -r "$racine" ]] || { echo "racine MédiSphère introuvable : $racine" >&2; exit 1; }

dossier="${XDG_RUNTIME_DIR:-/tmp}/thanos-objstore"
install -d -m 700 "$dossier"
cfg="$dossier/objstore.yml"

(
  set -a
  # shellcheck source=/dev/null
  . "$env_fichier"
  set +a
  umask 077
  CA="$racine" yq -n '
    .type = "S3" |
    .config.bucket = "thanos-k8s-par1" |
    .config.endpoint = "rgw.par1.medisphere.internal" |
    .config.region = "us-east-1" |
    .config.insecure = false |
    .config.bucket_lookup_type = "path" |
    .config.access_key = strenv(AWS_ACCESS_KEY_ID) |
    .config.secret_key = strenv(AWS_SECRET_ACCESS_KEY) |
    .config.http_config.tls_config.ca_file = strenv(CA)
  ' > "$cfg"
)
chmod 600 "$cfg"
printf '%s\n' "$cfg"
