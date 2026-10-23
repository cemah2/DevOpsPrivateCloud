#!/usr/bin/env bash
# =============================================================================
# outils/tester-politiques.sh — plateforme/secrets (M25-E40, INC-5240)
# Test des politiques ACL AVANT l'apply : un OpenBao de développement JETABLE (en mémoire, local au job,
# aucun lien avec la grappe) charge les politiques/*.hcl du dépôt, puis, pour chaque ligne de
# tests/politiques/capacites.tsv, crée un jeton portant la ou les politiques citées et compare ses
# capacités sur le chemin (sys/capabilities) à celles attendues.
#
#   tests/politiques/capacites.tsv : <politiques séparées par +>  <chemin>  <capacités attendues triées,
#   séparées par des virgules, ou « deny »>   (tabulations ; lignes « # » ignorées)
#
# Ce que ça attrape : « + » au lieu de « * », data/ oublié, deny qui l'emporte (politiques combinées
# comme sur un jeton d'identité), règle plus précise qui en masque une autre. Ce que ça n'attrape pas :
# les groupes externes et leurs alias (configuration OpenTofu : relue au plan).
# Usage : outils/tester-politiques.sh [dossier_politiques] [fichier_tsv]   (bao dans le PATH)
# Code retour : 0 si tout est conforme, 1 sinon. Aucun secret : le jeton racine du serveur jetable
# est tiré au hasard, passé par l'environnement, et meurt avec le processus.
# =============================================================================
set -Eeuo pipefail

POLITIQUES="${1:-politiques}"
ATTENDUS="${2:-tests/politiques/capacites.tsv}"
PORT="${TESTER_POLITIQUES_PORT:-18299}"
ADRESSE="http://127.0.0.1:$PORT"

command -v bao >/dev/null || { echo "bao absent du PATH" >&2; exit 2; }
[[ -d "$POLITIQUES" && -r "$ATTENDUS" ]] || { echo "usage : $0 [politiques/] [capacites.tsv]" >&2; exit 2; }

travail="$(mktemp -d)"
racine="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
nettoyer() { [[ -n "${pid:-}" ]] && kill "$pid" 2>/dev/null; rm -rf "$travail"; }
trap nettoyer EXIT

# Serveur jetable : le jeton racine passe par l'environnement (pas d'argument visible dans ps).
BAO_DEV_ROOT_TOKEN_ID="$racine" bao server -dev -dev-listen-address="127.0.0.1:$PORT" >"$travail/serveur.log" 2>&1 &
pid=$!
export BAO_ADDR="$ADRESSE"
for _ in $(seq 1 40); do
  curl -sf "$ADRESSE/v1/sys/health" >/dev/null 2>&1 && break
  sleep 0.25
done
curl -sf "$ADRESSE/v1/sys/health" >/dev/null || { echo "serveur de test injoignable" >&2; cat "$travail/serveur.log" >&2; exit 2; }

# api MÉTHODE CHEMIN — corps JSON sur l'entrée standard, jeton racine par un en-tête (-K).
api() {
  curl -sf -X "$1" -K <(printf 'header = "X-Vault-Token: %s"\n' "$racine") \
    -H 'Content-Type: application/json' --data-binary @- "$ADRESSE/v1/$2"
}

# 1. Charger toutes les politiques du dépôt (*.hcl ; les gabarits *.tftpl sont rendus par OpenTofu).
n=0
for f in "$POLITIQUES"/*.hcl; do
  nom="$(basename "$f" .hcl)"
  jq -Rs '{policy: .}' "$f" | api PUT "sys/policies/acl/$nom" >/dev/null \
    || { echo "ÉCHEC : politique $nom refusée par OpenBao (syntaxe ?)" >&2; exit 1; }
  n=$((n + 1))
done
echo "$n politiques chargées dans le serveur de test"

# 2. Comparer les capacités.
echecs=0 tests=0
while IFS=$'\t' read -r pols chemin attendu; do
  [[ -z "${pols// /}" || "$pols" == \#* ]] && continue
  tests=$((tests + 1))
  jeton="$(jq -nc --arg p "$pols" '{policies: ($p | split("+")), no_default_policy: true, ttl: "5m"}' \
    | api POST auth/token/create | jq -r '.auth.client_token')"
  obtenu="$(jq -nc --arg t "$jeton" --arg c "$chemin" '{token: $t, paths: [$c]}' \
    | api POST sys/capabilities | jq -r --arg c "$chemin" '.data[$c] // .capabilities | sort | join(",")')"
  if [[ "$obtenu" == "$attendu" ]]; then
    printf '[OK]   %-40s %-45s %s\n' "$pols" "$chemin" "$obtenu"
  else
    printf '[KO]   %-40s %-45s attendu %s, obtenu %s\n' "$pols" "$chemin" "$attendu" "$obtenu"
    echecs=$((echecs + 1))
  fi
done <"$ATTENDUS"

echo "$tests cas, $echecs écart(s)"
((tests > 0 && echecs == 0))
