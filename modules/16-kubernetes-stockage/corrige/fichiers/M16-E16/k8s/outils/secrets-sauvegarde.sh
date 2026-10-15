#!/usr/bin/env bash
# outils/secrets-sauvegarde.sh — Secrets des sauvegardes de k8s-par1 (M16-E16, E17, E19).
# Crée ou met à jour chaque Secret à partir des fichiers 600 de ~/.config/workbook/ ; n'affiche
# jamais une valeur ; aucune valeur ne passe sur une ligne de commande (process substitution et
# entrée standard seulement) ni dans un fichier temporaire.
#
#   outils/secrets-sauvegarde.sh velero          Secret velero-s3 (velero), depuis s3-velero.env
#   outils/secrets-sauvegarde.sh velero-kopia    mot de passe des dépôts Kopia (velero), lu sur
#                                                l'entrée standard (depuis le Vault critique)
#   outils/secrets-sauvegarde.sh cnpg [ESPACE]   Secrets cnpg-s3 et medisphere-ca (défaut :
#                                                mediagenda-recette), depuis s3-cnpg.env
#
# Remplacé en M16-E23 par outils/secrets-stockage.sh (qui couvre aussi ceph-csi).
set -euo pipefail

CONFIG="${WB_CONFIG:-$HOME/.config/workbook}"
CA_RACINE="${MS_CA_RACINE:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"

die() { echo "secrets-sauvegarde : $*" >&2; exit 1; }

# charger_env FICHIER — charge AWS_ACCESS_KEY_ID et AWS_SECRET_ACCESS_KEY d'un fichier 600.
charger_env() {
  local f="$1"
  [[ -f "$f" ]] || die "$f absent"
  [[ "$(stat -c %a "$f")" == 600 ]] || die "$f doit être en mode 600"
  AWS_ACCESS_KEY_ID="" AWS_SECRET_ACCESS_KEY=""
  # shellcheck disable=SC1090
  source "$f"
  [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]] || die "$f : clés manquantes"
}

appliquer() { kubectl apply -f - >/dev/null && echo "secrets-sauvegarde : $1 à jour"; }

velero() {
  charger_env "$CONFIG/s3-velero.env"
  kubectl -n velero create secret generic velero-s3 \
    --from-file=cloud=<(printf '[default]\naws_access_key_id=%s\naws_secret_access_key=%s\n' \
                          "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY") \
    --dry-run=client -o yaml | appliquer "velero/velero-s3"
}

velero_kopia() {
  # Changer ce mot de passe après la création d'un dépôt rend les sauvegardes illisibles.
  local depots
  depots="$(kubectl -n velero get backuprepositories.velero.io -o name 2>/dev/null | wc -l)"
  [[ "$depots" -eq 0 ]] || die "$depots dépôt(s) Kopia existent déjà : changement refusé (voir la doc Velero)"
  [[ ! -t 0 ]] || die "donne le mot de passe sur l'entrée standard (ex. depuis ansible-vault view)"
  local mdp
  IFS= read -r mdp || true
  [[ ${#mdp} -ge 32 ]] || die "mot de passe trop court (32 caractères au moins)"
  kubectl -n velero create secret generic velero-repo-credentials \
    --from-file=repository-password=<(printf '%s' "$mdp") \
    --dry-run=client -o yaml | appliquer "velero/velero-repo-credentials"
}

cnpg() {
  local espace="${1:-mediagenda-recette}"
  charger_env "$CONFIG/s3-cnpg.env"
  [[ -r "$CA_RACINE" ]] || die "racine MédiSphère illisible : $CA_RACINE"
  kubectl -n "$espace" create secret generic cnpg-s3 \
    --from-file=ACCESS_KEY_ID=<(printf '%s' "$AWS_ACCESS_KEY_ID") \
    --from-file=ACCESS_SECRET_KEY=<(printf '%s' "$AWS_SECRET_ACCESS_KEY") \
    --dry-run=client -o yaml | appliquer "$espace/cnpg-s3"
  kubectl -n "$espace" create secret generic medisphere-ca \
    --from-file=ca.crt="$CA_RACINE" \
    --dry-run=client -o yaml | appliquer "$espace/medisphere-ca"
}

case "${1:-}" in
  velero) velero ;;
  velero-kopia) velero_kopia ;;
  cnpg) shift; cnpg "$@" ;;
  *) echo "usage : $0 velero | velero-kopia | cnpg [ESPACE]" >&2; exit 2 ;;
esac
