#!/usr/bin/env bash
# outils/argocd-webhooks-gitlab.sh (plateforme/k8s) — M20-E27, PLAT-2127.
# Crée ou met à jour, de façon idempotente, le webhook « push » vers Argo CD de chaque projet GitLab
# suivi par Argo CD. Le jeton secret est réécrit à chaque passage (l'API ne le renvoie jamais : on ne
# peut pas savoir s'il est déjà le bon).
#
# Usage : outils/argocd-webhooks-gitlab.sh [PROJET…]
#   défaut : plateforme/gitops mediagenda/deploiement medidoc/deploiement formation/gitops-labo
# Fichiers (600, hors dépôt) :
#   GITLAB_JETON_FICHIER  jeton GitLab de portée « api », d'un Maintainer des projets
#                         (défaut : ~/.config/workbook/gitlab-moi-api.token)
#   WEBHOOK_SECRET_FICHIER  secret partagé, le même que dans le Vault (secrets/argocd.yml,
#                         argocd_webhook_gitlab_secret) ; défaut : ~/.config/workbook/argocd-webhook-gitlab.secret
# Rien n'est affiché des secrets ; ils passent à curl par des fichiers de configuration (jamais en
# argument : visibles dans « ps »).
set -Eeuo pipefail
umask 077

GITLAB_URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
ARGOCD_WEBHOOK="${ARGOCD_WEBHOOK:-https://argocd.apps.par1.medisphere.internal/api/webhook}"
jeton_fichier="${GITLAB_JETON_FICHIER:-$HOME/.config/workbook/gitlab-moi-api.token}"
secret_fichier="${WEBHOOK_SECRET_FICHIER:-$HOME/.config/workbook/argocd-webhook-gitlab.secret}"

for f in "$jeton_fichier" "$secret_fichier"; do
  [[ -r "$f" ]] || { echo "illisible : $f" >&2; exit 2; }
  [[ "$(stat -c %a "$f")" == 600 ]] || { echo "$f doit être en 600" >&2; exit 2; }
done
command -v jq >/dev/null || { echo "jq introuvable" >&2; exit 2; }

if (( $# > 0 )); then
  projets=("$@")
else
  projets=(plateforme/gitops mediagenda/deploiement medidoc/deploiement formation/gitops-labo)
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# En-tête d'authentification GitLab, dans un fichier de configuration curl.
printf 'header = "PRIVATE-TOKEN: %s"\n' "$(tr -d '[:space:]' <"$jeton_fichier")" >"$tmp/curl-gitlab"

api() { # api MÉTHODE CHEMIN [FICHIER_JSON]
  local methode="$1" chemin="$2"
  if [[ $# -ge 3 ]]; then
    curl -sSf -K "$tmp/curl-gitlab" -X "$methode" -H 'Content-Type: application/json' \
      --data-binary @"$3" "$GITLAB_URL/api/v4/$chemin"
  else
    curl -sSf -K "$tmp/curl-gitlab" -X "$methode" "$GITLAB_URL/api/v4/$chemin"
  fi
}

for projet in "${projets[@]}"; do
  id="$(jq -rn --arg p "$projet" '$p | @uri')"
  # Corps de la requête : le secret est lu par jq depuis son fichier (--rawfile), jamais en argument.
  jq -n --arg url "$ARGOCD_WEBHOOK" --rawfile secret "$secret_fichier" '{
      url: $url,
      name: "argocd",
      description: "Rafraîchissement d Argo CD (M20-E27)",
      token: ($secret | rtrimstr("\n")),
      push_events: true,
      tag_push_events: false,
      merge_requests_events: false,
      enable_ssl_verification: true
    }' >"$tmp/corps.json"
  existant="$(api GET "projects/$id/hooks?per_page=100" | jq -r --arg url "$ARGOCD_WEBHOOK" \
    '[.[] | select(.url == $url)] | first | .id // empty')"
  if [[ -n "$existant" ]]; then
    api PUT "projects/$id/hooks/$existant" "$tmp/corps.json" >/dev/null
    echo "[OK] $projet : webhook $existant mis à jour"
  else
    nouveau="$(api POST "projects/$id/hooks" "$tmp/corps.json" | jq -r '.id')"
    echo "[OK] $projet : webhook $nouveau créé"
  fi
done
echo "Teste : Paramètres → Webhooks → Tester → « Push events » ; réponse attendue 200."
