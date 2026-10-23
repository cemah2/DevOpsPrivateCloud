# shellcheck shell=bash
# preuves/collecteurs/_commun.sh — fonctions communes des collecteurs de ms-preuves (F6-S02, PLAT-3602).
# Sourcé par chaque collecteur, jamais lancé seul (son nom ne correspond pas à un collecteur du catalogue).
#
# Règles d'un collecteur :
#   - LECTURE SEULE : GET, list, get ; jamais d'écriture, même « inoffensive » ;
#   - la preuve sur la sortie standard, les erreurs sur la sortie d'erreur ; code ≠ 0 si la preuve est
#     incomplète (ms-preuves la marque « echec » et garde ce qui a été écrit) ;
#   - jamais de secret dans la sortie (ms-preuves refuse la preuve s'il en détecte un) ; identités
#     lues dans l'environnement, passées à curl et ldapsearch par descripteur (jamais dans « ps ») ;
#   - une sortie stable (tri) : deux lots identiques ont la même empreinte, une différence est un fait.
set -euo pipefail

DELAI_HTTP="${MS_PREUVES_DELAI_HTTP:-20}"

manque() { printf 'identité ou adresse absente : %s\n' "$*" >&2; exit 1; }
exige() {
  local v
  for v in "$@"; do [[ -n "${!v:-}" ]] || manque "$v"; done
}
enc() { jq -rn --arg s "$1" '$s|@uri'; }

# http_jeton URL JETON [EN-TÊTE=Authorization: Bearer] — GET avec un jeton passé par descripteur.
http_jeton() {
  curl -sf --max-time "$DELAI_HTTP" -H 'Accept: application/json' \
    -K <(printf 'header = "%s %s"\n' "${3:-Authorization: Bearer}" "$2") "$1"
}

# http_basique URL UTILISATEUR MOT_DE_PASSE — GET en authentification basique (par descripteur).
http_basique() {
  curl -sf --max-time "$DELAI_HTTP" -H 'Accept: application/json' \
    -K <(printf 'user = "%s:%s"\n' "$2" "$3") "$1"
}

# entete_preuve — en-tête JSON commun (horodatage UTC, identifiant de la preuve, hôte).
entete_preuve() {
  jq -n --arg id "${MS_PREUVES_ID:-?}" --arg lot "${MS_PREUVES_LOT:-?}" \
    --arg h "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg hote "$(hostname -s)" \
    '{preuve: $id, lot: $lot, collecte_utc: $h, hote: $hote}'
}
