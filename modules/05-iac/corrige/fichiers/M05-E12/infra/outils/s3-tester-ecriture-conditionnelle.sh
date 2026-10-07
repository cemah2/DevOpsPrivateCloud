#!/usr/bin/env bash
# s3-tester-ecriture-conditionnelle.sh — prouve qu'un stockage S3 refuse une écriture
# conditionnelle (If-None-Match: *) sur un objet qui existe déjà (M05-E12).
#
# C'est la propriété dont dépend le verrou natif d'OpenTofu (use_lockfile) : si le
# stockage ignore l'en-tête, deux « tofu apply » prennent le verrou en même temps et
# rien ne le signale. À relancer après toute montée de version de SeaweedFS (M05-E31).
#
# Usage (depuis plateforme/infra, identité tofu-etat chargée) :
#   set -a; . ~/.config/workbook/s3-tofu.env; set +a
#   outils/s3-tester-ecriture-conditionnelle.sh [COMPARTIMENT]
# Autre stockage (essai d'un candidat, M05-E30) : sans profil, avec l'adresse dans
# AWS_ENDPOINT_URL (variable reconnue par la CLI v2) et les clés du candidat :
#   env -u AWS_PROFILE AWS_ENDPOINT_URL=http://<IP>:<PORT> outils/s3-tester-ecriture-conditionnelle.sh essai
# (Un AWS_PROFILE VIDE mais exporté fait échouer la CLI : « config profile () could not be
# found » ; le script le retire s'il est vide.)
# Codes retour : 0 = écriture conditionnelle respectée, 1 = NON respectée, 2 = erreur.
set -euo pipefail

compartiment="${1:-tofu-state}"
cle="_essais/if-none-match-$(date +%Y%m%d-%H%M%S)-$$"
contenu="$(mktemp)"
trap 'rm -f "$contenu"' EXIT
printf 'essai d écriture conditionnelle %s\n' "$(date -Is)" > "$contenu"

command -v aws >/dev/null || { echo "aws (CLI v2) introuvable" >&2; exit 2; }
[[ -n "${AWS_PROFILE:-}" ]] || unset AWS_PROFILE
if [[ -z "${AWS_PROFILE:-}" && -z "${AWS_ENDPOINT_URL:-}" ]]; then
  echo "Ni profil (AWS_PROFILE) ni adresse (AWS_ENDPOINT_URL) : charge ~/.config/workbook/s3-tofu.env" >&2
  exit 2
fi

echo "1. Première écriture conditionnelle de s3://$compartiment/$cle (doit réussir)"
if ! aws s3api put-object --bucket "$compartiment" --key "$cle" --body "$contenu" \
     --if-none-match '*' --output text --query VersionId; then
  echo "Erreur : la première écriture a échoué (droits, réseau, certificat ?)" >&2
  exit 2
fi

echo "2. Seconde écriture conditionnelle de la même clé (doit être REFUSÉE : 412)"
set +e
sortie="$(aws s3api put-object --bucket "$compartiment" --key "$cle" --body "$contenu" \
          --if-none-match '*' 2>&1)"
rc=$?
set -e

echo "3. Ménage (marqueur de suppression ; les versions restent, c'est voulu)"
aws s3api delete-object --bucket "$compartiment" --key "$cle" >/dev/null || true

if (( rc == 0 )); then
  echo "ÉCHEC : la seconde écriture a été ACCEPTÉE : le stockage ignore If-None-Match." >&2
  echo "       N'utilise PAS use_lockfile sur ce stockage : le verrou serait illusoire." >&2
  exit 1
fi
if grep -q 'PreconditionFailed' <<<"$sortie"; then
  echo "OK : seconde écriture refusée (PreconditionFailed / HTTP 412)."
  echo "     Le verrou use_lockfile d'OpenTofu est fiable sur ce stockage."
  exit 0
fi
# Refusée, mais pas pour la bonne raison (réseau, droits, certificat, en-tête non géré) :
# on ne conclut rien sur le verrou.
echo "INDÉTERMINÉ : la seconde écriture a échoué pour une autre raison que 412 :" >&2
echo "       $sortie" >&2
exit 2
