# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-E34.sh — M25-E34 « Rotation d'urgence en temps limité » (CHRONO), lancé par « lab/bin/break 25 34 ».
# Script AUTONOME (ne dépend pas de _m25-commun.sh).
#
# Scénario : le secret du client Keycloak « grafana » et le mot de passe Valkey de MédiAgenda recette
# ont fuité dans un ticket (INC-5234). Rien n'est cassé dans le lab : l'« injection » relève l'état de
# départ (T0) que la vérification comparera à l'état final :
#   - T0 (époque, secondes) ;
#   - version courante et date de création de la version de kv/plateforme/grafana/oidc et de
#     kv/mediagenda/recette/valkey (métadonnées seulement, AppRole wb-checks : jamais une valeur) ;
#   - date du secret du client grafana dans Keycloak (attribut client.secret.creation.time, lu avec le
#     compte de service wb-checks, rôle view-clients : jamais le secret).
# Une seule variante. Aucune modification du lab, donc rien à sauvegarder ni à restaurer ; « --annuler »
# clôt l'exercice (marqueur) et GARDE l'état de départ (~/.local/state/workbook/M25-E34/) pour
# « lab/bin/check 25 34 ». Si l'état de départ ne peut pas être relevé (coffre ou Keycloak muets,
# chemins absents), l'injection échoue : pas de chrono sur un lab qui ne permettrait pas de vérifier.
# Variables (lab/lab.env) : WB_OPENBAO_CHECKS_FILE, WB_KEYCLOAK_CHECKS_FILE (check-lib).

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_E34_ETAT="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M25-E34"
_E34_KV_GRAFANA=plateforme/grafana/oidc
_E34_KV_VALKEY=mediagenda/recette/valkey

# _e34_meta CHEMIN — {"version": N, "cree": "<date de la version courante>"} ou rien.
_e34_meta() {
  bao_api "kv/metadata/$1" 2>/dev/null \
    | jq -ce '.data | {version: .current_version, cree: .versions[(.current_version | tostring)].created_time}
              | select(.version > 0 and (.cree | type) == "string")' 2>/dev/null
}

# _e34_keycloak — date de création du secret du client grafana (attribut client.secret.creation.time :
#   époque en secondes, ou en millisecondes selon la version — le check accepte les deux), ou rien.
_e34_keycloak() {
  keycloak_api "clients?clientId=grafana" 2>/dev/null \
    | jq -er '.[0].attributes["client.secret.creation.time"] // empty' 2>/dev/null
}

panne_E34_v1() {
  local g v k t0
  command -v jq >/dev/null || { wb_avert "jq absent sur ce poste"; return 1; }
  g="$(_e34_meta "$_E34_KV_GRAFANA")" || { wb_avert "métadonnées de kv/$_E34_KV_GRAFANA illisibles (AppRole wb-checks ?)"; return 1; }
  v="$(_e34_meta "$_E34_KV_VALKEY")" || { wb_avert "métadonnées de kv/$_E34_KV_VALKEY illisibles"; return 1; }
  k="$(_e34_keycloak)" || k=""
  t0="$(date +%s)"
  mkdir -p "$_E34_ETAT" && chmod 700 "$_E34_ETAT"
  jq -n --argjson t0 "$t0" --argjson g "$g" --argjson v "$v" --arg k "$k" \
    '{t0: $t0, grafana: $g, valkey: $v, keycloak_secret_cree: $k}' >"$_E34_ETAT/etat.json.tmp" \
    && mv -f "$_E34_ETAT/etat.json.tmp" "$_E34_ETAT/etat.json"
}

# verifier_E34 — l'état de départ est complet et récent (moins de 5 min).
verifier_E34() {
  jq -e --argjson n "$(date +%s)" '(.t0 > ($n - 300)) and (.grafana.version > 0) and (.valkey.version > 0)' \
    "$_E34_ETAT/etat.json" >/dev/null 2>&1
}

annuler_E34() {
  # Rien à défaire dans le lab. L'état de départ est GARDÉ pour lab/bin/check 25 34.
  if [[ -f "$_E34_ETAT/etat.json" ]]; then
    jq --argjson f "$(date +%s)" '. + {fin: $f}' "$_E34_ETAT/etat.json" >"$_E34_ETAT/etat.json.tmp" 2>/dev/null \
      && mv -f "$_E34_ETAT/etat.json.tmp" "$_E34_ETAT/etat.json"
  fi
  return 0
}

symptome_E34() {
  wb_symptome "INC-5234 — Deux secrets ont fuité dans un ticket du support" \
    "Le ticket SUP-5234, lu par un prestataire, contient la sortie d'un « kubectl describe » et un" \
    "fichier de configuration : on y lit le secret du client Keycloak « grafana » et le mot de passe" \
    "Valkey de MédiAgenda recette. Les deux sont réputés compromis." \
    "Objectif : en 45 minutes, deux secrets neufs en service et les anciens inutilisables, sans" \
    "coupure de Grafana ni de la recette ; journal horodaté avec les preuves (RB-250, RB-254)." \
    "T0 = maintenant ($(date +%H:%M)). État de départ relevé ; vérification : lab/bin/check 25 34."
}

resume_E34() { echo "secret du client grafana et mot de passe Valkey de la recette exposés dans un ticket"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 25 E34 1 "$@"; }
fi
