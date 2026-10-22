#!/usr/bin/env bash
# outils/signer.sh — signe par la clé MédiSphère chaque digest de recopies.txt qui ne l'est pas encore
# (M20-E13). Tourne dans l'image plateforme/outils-supply-chain (M13-E09 : Cosign 3.1, clé publique
# et configuration de signature sans service embarquées).
# On signe le DIGEST, jamais l'étiquette ; « cosign sign » n'étant pas idempotent (chaque appel ajoute
# un référent), on vérifie d'abord : un chart déjà signé n'est pas re-signé à chaque planification.
# Variables (CI) : COSIGN_PRIVATE_KEY (type fichier, protégée), COSIGN_PASSWORD (masquée, protégée).
set -euo pipefail

PUB=/etc/medisphere/cosign.pub
CONF=/etc/medisphere/signing-config.json
: "${COSIGN_PRIVATE_KEY:?}"

while read -r ref; do
  [[ -n "$ref" ]] || continue
  [[ "$ref" == *@sha256:* ]] || { echo "ERREUR « $ref » n'est pas une référence par digest" >&2; exit 1; }
  if cosign verify --key "$PUB" --insecure-ignore-tlog=true "$ref" >/dev/null 2>&1; then
    echo "déjà signé : $ref"
    continue
  fi
  cosign sign --key "$COSIGN_PRIVATE_KEY" --signing-config "$CONF" "$ref"
  cosign verify --key "$PUB" --insecure-ignore-tlog=true "$ref" >/dev/null
  echo "signé : $ref"
done <recopies.txt
