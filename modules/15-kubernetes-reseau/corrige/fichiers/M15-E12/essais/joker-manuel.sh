#!/usr/bin/env bash
# ~/m15/e12/joker-manuel.sh — certificat joker PROVISOIRE de M15-E12 (remplacé en E14 par cert-manager).
# La clé ne touche que /run/user/<uid> (tmpfs, en mémoire) et est effacée en sortie, même en cas d'erreur.
# Prérequis : step 0.31 (contexte ca01 configuré, M06), kubectl (identité d'administration),
#             ~/.config/workbook/step-admin.pass (provisioner JWK admin, 7 jours au plus).
set -euo pipefail

nom='*.apps.par1.medisphere.internal'
tmp="/run/user/$(id -u)/joker"
install -d -m 700 "$tmp"
trap 'rm -rf "$tmp"' EXIT

step ca certificate "$nom" "$tmp/joker.crt" "$tmp/joker.key" \
  --provisioner admin --provisioner-password-file ~/.config/workbook/step-admin.pass \
  --not-after 168h --force

kubectl -n passerelles create secret tls apps-joker \
  --cert="$tmp/joker.crt" --key="$tmp/joker.key" --dry-run=client -o yaml \
  | kubectl apply -f -

step certificate inspect --short "$tmp/joker.crt"
step certificate fingerprint "$tmp/joker.crt"
