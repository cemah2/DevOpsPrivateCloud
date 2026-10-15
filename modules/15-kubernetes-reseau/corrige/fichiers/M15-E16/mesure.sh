#!/usr/bin/env bash
# ~/m15/e16/mesure.sh — mesure du routage d'essai-avance (M15-E16, étape 3). Depuis adm01.
set -euo pipefail
U=https://essai.apps.par1.medisphere.internal
compter() { sed -E 's/-[a-z0-9]+-[a-z0-9]+$//' | sort | uniq -c; }

echo "== 200 requêtes sans en-tête (attendu ≈ 180 v1 / 20 v2)"
for _ in $(seq 200); do curl -fsS "$U/hostname"; echo; done | compter
echo "== 20 requêtes avec X-Canari: oui (attendu : 20 v2)"
for _ in $(seq 20); do curl -fsS -H 'X-Canari: oui' "$U/hostname"; echo; done | compter
echo "== réécriture /v2/hostname (attendu : un pod v2, code 200)"
curl -fsS -w ' (%{http_code})\n' "$U/v2/hostname"
echo "== redirection /ancien/hostname (attendu : 301, Location …/hostname)"
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' "$U/ancien/hostname"
echo "== en-tête ajouté (attendu : essai), même si le client en envoie un autre"
curl -fsS -H 'X-Medisphere-Env: prod' "$U/header?key=X-Medisphere-Env"; echo
