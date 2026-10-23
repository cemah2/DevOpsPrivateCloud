#!/usr/bin/env bash
# verifier-archive-audit.sh — contrôle d'intégrité de l'archive d'audit (F6-S08, ECA-3601).
#
# plateforme/observabilite — outils/verifier-archive-audit.sh. Lancé par le pipeline planifié
# « archive:verifier » (chaque matin, sur la veille ; rôle JWT ci-observabilite-archive, politique
# audit-archive-verif) et à la demande d'un auditeur. LECTURE SEULE (identité archive-audit-lecture).
#
# Pour une période (un préfixe AAAA-MM-JJ de l'archive) :
#   1. télécharge le manifeste (manifeste.json), les objets listés et la signature (manifeste.sig) ;
#   2. vérifie la signature du manifeste par « transit » d'OpenBao (ou cosign si configuré) ;
#   3. recalcule le SHA-256 de chaque objet et le compare au manifeste ;
#   4. vérifie que tous les objets du manifeste sont présents (archive non tronquée).
# Sortie 0 si tout concorde, 1 sinon (un écart est une alerte).
#
# Variables (défauts) :
#   RGW_URL              point d'accès S3 du RGW de ceph-par1   (https://rgw.par1.medisphere.internal)
#   ARCHIVE_BUCKET       compartiment d'archive                 (archive-audit)
#   ARCHIVE_S3_ENV       fichier d'identité de lecture, si AWS_ACCESS_KEY_ID n'est pas déjà dans
#                        l'environnement (à la main : ~/.config/workbook/s3-archive-audit-lecture.env)
#   BAO_ADDR             adresse d'OpenBao                      (https://openbao.par1.medisphere.internal:8200)
#   TRANSIT_CLE          clé transit de signature de l'audit    (audit-archive)
#   BAO_TOKEN            jeton OpenBao (transit/verify) — lu dans l'environnement
set -euo pipefail

RGW="${RGW_URL:-https://rgw.par1.medisphere.internal}"
BUCKET="${ARCHIVE_BUCKET:-archive-audit}"
ENV_FILE="${ARCHIVE_S3_ENV:-$HOME/.config/workbook/s3-archive-audit-lecture.env}"
BAO_ADDR="${BAO_ADDR:-https://openbao.par1.medisphere.internal:8200}"
TRANSIT_CLE="${TRANSIT_CLE:-audit-archive}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

usage() {
  echo "Usage : $0 <AAAA-MM-JJ>   (période à vérifier dans s3://$BUCKET/)" >&2
  exit 2
}
[[ $# -eq 1 ]] || usage
periode="$1"
[[ "$periode" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage

for c in aws jq sha256sum curl openssl; do
  command -v "$c" >/dev/null 2>&1 || { echo "outil manquant : $c" >&2; exit 2; }
done
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
  [[ -r "$ENV_FILE" ]] || { echo "identité S3 de lecture absente (AWS_ACCESS_KEY_ID ou $ENV_FILE)" >&2; exit 2; }
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi
s3() { aws --endpoint-url "$RGW" "$@"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

prefixe="$periode/"
echo "== Vérification de l'archive d'audit : s3://$BUCKET/$prefixe =="

# 1. Récupération du manifeste et de sa signature.
s3 s3 cp "s3://$BUCKET/${prefixe}manifeste.json" "$tmp/manifeste.json" >/dev/null 2>&1 \
  || { echo "KO : manifeste absent pour $periode (archive manquante ?)"; exit 1; }
s3 s3 cp "s3://$BUCKET/${prefixe}manifeste.sig" "$tmp/manifeste.sig" >/dev/null 2>&1 \
  || { echo "KO : signature du manifeste absente"; exit 1; }

# 2. Vérification de la signature du manifeste (transit d'OpenBao).
#    La signature porte sur le condensat SHA-256 du manifeste, encodé en base64 (format transit).
condense="$(openssl dgst -sha256 -binary "$tmp/manifeste.json" | openssl base64 -A)"
signature="$(cat "$tmp/manifeste.sig")"
verif="$(curl -sf --max-time 10 \
  -K <(printf 'header = "X-Vault-Token: %s"\n' "${BAO_TOKEN:?BAO_TOKEN requis pour la vérification de signature}") \
  --data "$(jq -n --arg i "$condense" --arg s "$signature" \
            '{input: $i, signature: $s, hash_algorithm: "sha2-256", prehashed: true}')" \
  "$BAO_ADDR/v1/transit/verify/$TRANSIT_CLE" | jq -r '.data.valid // false')" \
  || { echo "KO : vérification de signature impossible (OpenBao injoignable ?)"; exit 1; }
if [[ "$verif" != "true" ]]; then
  echo "KO : signature du manifeste INVALIDE — le manifeste a été modifié ou n'a pas été signé par $TRANSIT_CLE"
  exit 1
fi
echo "OK : signature du manifeste valide ($TRANSIT_CLE)"

# 3-4. Objets : présence + condensat.
echec=0
nb="$(jq '.objets | length' "$tmp/manifeste.json")"
echo "manifeste : $nb objet(s) pour la période $(jq -r '.periode' "$tmp/manifeste.json")"
while IFS=$'\t' read -r nom sha; do
  if ! s3 s3 cp "s3://$BUCKET/$prefixe$nom" "$tmp/$nom" >/dev/null 2>&1; then
    echo "KO : objet manquant (archive tronquée) : $nom"
    echec=1
    continue
  fi
  reel="$(sha256sum "$tmp/$nom" | cut -d' ' -f1)"
  if [[ "$reel" != "$sha" ]]; then
    echo "KO : condensat différent pour $nom (attendu $sha, obtenu $reel) — objet modifié"
    echec=1
  else
    echo "OK : $nom"
  fi
done < <(jq -r '.objets[] | [.nom, .sha256] | @tsv' "$tmp/manifeste.json")

if (( echec )); then
  echo "== Intégrité NON vérifiée pour $periode =="
  exit 1
fi
echo "== Intégrité vérifiée pour $periode =="
