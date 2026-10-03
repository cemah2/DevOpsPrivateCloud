#!/usr/bin/env bash
# webhook-pve.sh — Variante : cible webhook vers le récepteur de test sur adm01 (M00-E29).
# PVE 8.3+. Dans l'API, la valeur des en-têtes et le corps sont encodés en base64
# (l'interface web le fait pour toi). À vérifier avec « pvesh usage
# /cluster/notifications/endpoints/webhook -v » sur ta version.
set -euo pipefail

URL="http://10.10.10.10:8099/pve01"

# Modèle de corps JSON : « escape » protège les guillemets et retours à la ligne.
CORPS='{"source":"pve01","titre":"{{ escape title }}","severite":"{{ severity }}","message":"{{ escape message }}"}'

pvesh create /cluster/notifications/endpoints/webhook \
  --name webhook-adm01 --url "$URL" --method post \
  --header "name=Content-Type,value=$(printf '%s' 'application/json' | base64 -w0)" \
  --body "$(printf '%s' "$CORPS" | base64 -w0)" \
  --comment "Recepteur de test sur adm01"

pvesh create /cluster/notifications/targets/webhook-adm01/test
