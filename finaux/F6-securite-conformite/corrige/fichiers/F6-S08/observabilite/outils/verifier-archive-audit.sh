#!/usr/bin/env bash
# verifier-archive-audit.sh — contrôle d'intégrité de l'archive d'audit (F6-S08, ECA-3601).
#
# plateforme/observabilite — outils/verifier-archive-audit.sh. Lancé par un pipeline planifié et à la
# demande d'un auditeur. LECTURE SEULE sur l'archive (identité de lecture ; jamais d'écriture).
#
# Pour une période (un préfixe AAAA-MM-JJ de l'archive) :
#   1. télécharge le manifeste (manifeste.json), les objets listés et la signature (manifeste.sig) ;
#   2. vérifie la signature du manifeste par « transit » d'OpenBao (ou cosign si configuré) ;
#   3. recalcule le SHA-256 de chaque objet et le compare au manifeste ;
#   4. vérifie que tous les objets du manifeste sont présents (archive non tronquée).
# Sortie 0 si tout concorde, 1 sinon (un écart est une alerte).
#
# Variables (défauts) :
#   WB_F6_RGW_URL        point d'accès S3 du RGW de ceph-par1   (https://rgw.par1.medisphere.internal)
#   WB_F6_ARCHIVE_BUCKET compartiment d'archive                 (archive-audit)
#   WB_F6_ARCHIVE_ENV    identité S3 de lecture                 (~/.config/workbook/s3-archive-audit-lecture.env)
#   WB_F6_TRANSIT_ADDR   adresse d'OpenBao                      (https://openbao.par1.medisphere.internal:8200)
#   WB_F6_TRANSIT_CLE    clé transit de signature de l'audit    (audit-archive)
#   BAO_TOKEN            jeton OpenBao (vérification de signature) — lu dans l'environnement
set -euo pipefail

RGW="${WB_F6_RGW_URL:-https://rgw.par1.medisphere.internal}"
BUCKET="${WB_F6_ARCHIVE_BUCKET:-archive-audit}"
ENV_FILE="${WB_F6_ARCHIVE_ENV:-$HOME/.config/workbook/s3-archive-audit-lecture.env}"
BAO_ADDR="${WB_F6_TRANSIT_ADDR:-https://openbao.par1.medisphere.internal:8200}"
TRANSIT_CLE="${WB_F6_TRANSIT_CLE:-audit-archive}"

usage() {
  echo "Usage : $0 <AAAA-MM-JJ>   (période à vérifier dans s3://$BUCKET/)" >&2
  exit 2
}
[[ $# -eq 1 ]] || usage
periode="$1"
[[ "$periode" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage

for c in aws jq sha256sum curl; do
  command -v "$c" >/dev/null 2>&1 || { echo "outil manquant : $c" >&2; exit 2; }
done
[[ -r "$ENV_FILE" ]] || { echo "identité S3 de lecture illisible : $ENV_FILE" >&2; exit 2; }

s3() {
  (
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
    aws --endpoint-url "$RGW" "$@"
  )
}

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
condense="$(sha256sum "$tmp/manifeste.json" | cut -d' ' -f1 | xxd -r -p | base64)"
signature="$(cat "$tmp/manifeste.sig")"
verif="$(curl -sf --max-time 10 \
  -H "X-Vault-Token: ${BAO_TOKEN:?BAO_TOKEN requis pour la vérification de signature}" \
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
