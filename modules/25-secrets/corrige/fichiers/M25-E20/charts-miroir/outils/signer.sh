#!/usr/bin/env bash
# outils/signer.sh — signe par la clé MédiSphère chaque digest de recopies.txt qui ne l'est pas encore
# (M20-E13 ; clé dans OpenBao depuis M25-E20, SEC-2620). Tourne dans l'image plateforme/outils-supply-chain
# (Cosign 3.1, bao, clé PUBLIQUE de cosign-medisphere et configuration de signature sans service).
# On signe le DIGEST, jamais l'étiquette ; « cosign sign » n'étant pas idempotent (chaque appel ajoute
# un référent), on vérifie d'abord avec la clé publique : un chart déjà signé par la clé ACTUELLE n'est
# pas re-signé ; un chart signé seulement par l'ancienne clé du M13 l'est (re-signature automatique
# des recopies au premier passage après le changement de clé).
# Identité : BAO_ADDR et BAO_TOKEN (jeton de 10 min du rôle ci-signature, obtenu par le job) ;
# la clé privée ne quitte jamais le coffre.
set -euo pipefail

PUB=/etc/medisphere/cosign.pub
CONF=/etc/medisphere/signing-config.json
CLE="${CLE_SIGNATURE:-hashivault://cosign-medisphere}"
: "${BAO_ADDR:?}" "${BAO_TOKEN:?jeton OpenBao absent : le job doit se connecter (rôle ci-signature)}"

while read -r ref; do
  [[ -n "$ref" ]] || continue
  [[ "$ref" == *@sha256:* ]] || { echo "ERREUR « $ref » n'est pas une référence par digest" >&2; exit 1; }
  if cosign verify --key "$PUB" --insecure-ignore-tlog=true "$ref" >/dev/null 2>&1; then
    echo "déjà signé : $ref"
    continue
  fi
  cosign sign --key "$CLE" --signing-config "$CONF" "$ref"
  cosign verify --key "$PUB" --insecure-ignore-tlog=true "$ref" >/dev/null
  echo "signé : $ref"
done <recopies.txt
