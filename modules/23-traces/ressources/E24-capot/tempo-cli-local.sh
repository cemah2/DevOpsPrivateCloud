#!/usr/bin/env bash
# shellcheck disable=SC2016  # les accents graves sont des littéraux JMESPath de --query, pas une substitution
# tempo-cli-local.sh — copie EN LECTURE un bloc de tempo-k8s-par1 sur adm01 et l'ouvre avec tempo-cli (M23-E24).
# Usage : ./tempo-cli-local.sh [ID-DE-BLOC]   (sans argument : liste les blocs et copie le plus récent)
# Identifiants RGW de Tempo (M23-E03) : ~/.config/workbook/s3-tempo.env (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY),
# utilisés en LECTURE seulement (liste et copie) : ils pourraient écrire, ce script ne le fait jamais.
# tempo-cli lit la copie avec le moteur « local » : aucune écriture dans le compartiment, aucun accès au cluster.
set -euo pipefail

RGW="${WB_RGW_ENDPOINT:-https://rgw.par1.medisphere.internal}"
COMPARTIMENT=tempo-k8s-par1
LOCATAIRE=single-tenant
COPIE="${COPIE:-$HOME/m23/e24/copie}"
ENV_S3="$HOME/.config/workbook/s3-tempo.env"

[[ -r "$ENV_S3" ]] || { echo "identité de lecture absente : $ENV_S3" >&2; exit 1; }
command -v tempo-cli >/dev/null || { echo "tempo-cli introuvable dans le PATH (voir l'énoncé de M23-E24)" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_S3"
set +a
s3() { aws --endpoint-url "$RGW" "$@"; }

bloc="${1:-}"
if [[ -z "$bloc" ]]; then
  echo "Blocs du locataire $LOCATAIRE (les plus récents en dernier) :"
  s3 s3api list-objects-v2 --bucket "$COMPARTIMENT" --prefix "$LOCATAIRE/" --query 'Contents[?ends_with(Key, `meta.json`)].[LastModified, Key]' --output text | sort | tail -n 10
  bloc="$(s3 s3api list-objects-v2 --bucket "$COMPARTIMENT" --prefix "$LOCATAIRE/" --query 'Contents[?ends_with(Key, `meta.json`)].[LastModified, Key]' --output text |
    sort | tail -n 1 | awk '{print $2}' | cut -d/ -f2)"
fi
[[ "$bloc" =~ ^[0-9a-f-]{36}$ ]] || { echo "identifiant de bloc invalide : $bloc" >&2; exit 1; }

mkdir -p "$COPIE/$LOCATAIRE/$bloc"
s3 s3 cp --recursive --only-show-errors "s3://$COMPARTIMENT/$LOCATAIRE/$bloc/" "$COPIE/$LOCATAIRE/$bloc/"
ls -l "$COPIE/$LOCATAIRE/$bloc"
echo
tempo-cli list blocks "$LOCATAIRE" --backend local --bucket "$COPIE"
echo
echo "Suite : tempo-cli view schema $LOCATAIRE $bloc --backend local --bucket $COPIE"
echo "        tempo-cli list column $LOCATAIRE $bloc TraceIDText --backend local --bucket $COPIE"
echo "        tempo-cli query trace-summary <TRACE-ID> $LOCATAIRE --backend local --bucket $COPIE"
