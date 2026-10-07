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
# Codes retour : 0 = écriture conditionnelle respectée, 1 = NON respectée, 2 = erreur.
set -euo pipefail

compartiment="${1:-tofu-state}"
cle="_essais/if-none-match-$(date +%Y%m%d-%H%M%S)-$$"
contenu="$(mktemp)"
trap 'rm -f "$contenu"' EXIT
printf 'essai d écriture conditionnelle %s\n' "$(date -Is)" > "$contenu"

command -v aws >/dev/null || { echo "aws (CLI v2) introuvable" >&2; exit 2; }
: "${AWS_PROFILE:?profil aws absent : charge ~/.config/workbook/s3-tofu.env}"

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

if (( rc != 0 )) && grep -q 'PreconditionFailed' <<<"$sortie"; then
  echo "OK : seconde écriture refusée (PreconditionFailed / HTTP 412)."
  echo "     Le verrou use_lockfile d'OpenTofu est fiable sur ce stockage."
  exit 0
fi
echo "ÉCHEC : la seconde écriture n'a pas été refusée comme attendu." >&2
echo "       Sortie : $sortie" >&2
echo "       N'utilise PAS use_lockfile sur ce stockage : le verrou serait illusoire." >&2
exit 1
