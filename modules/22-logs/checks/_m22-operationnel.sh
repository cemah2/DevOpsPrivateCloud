# shellcheck shell=bash
# _m22-operationnel.sh — fonctions partagées par les checks M22-E06 à M22-E11 (lecture seule).
# Sourcé par les check-EXX.sh du palier 2 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m22o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (PLAN §4.11) : Loki (loki_api, loki_requete, et l'API du ruler en GET), « kube » (wb-checks),
# GitLab (gitlab_api), Prometheus (prom_requete), Mailpit (mailpit_api) ; tout en lecture.

_M22O_NS=journaux
_M22O_LOKI="${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}"
_M22O_P_OBS="projects/plateforme%2Fobservabilite"
_M22O_P_DOC="projects/plateforme%2Fmedisphere"
_M22O_P_GITOPS="projects/plateforme%2Fgitops"
_M22O_LOCATAIRES=(plateforme mediagenda medidoc audit)
_M22O_ETIQUETTES_OK='^(cluster|namespace|app|container|node|job|host|role|site)$'

# _m22o_k ARGS… — kubectl en lecture avec wb-checks ; sortie standard seule, vide si erreur.
_m22o_k() { kube "$@" 2>/dev/null || true; }

# _m22o_json JSON FILTRE [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m22o_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m22o_requete 'LogQL' LOCATAIRE [DEPUIS=1h] — JSON de query_range (vide si erreur).
_m22o_requete() { loki_requete "$1" "${2:-plateforme}" "${3:-1h}" 2>/dev/null || true; }

# _m22o_nb 'LogQL' LOCATAIRE [DEPUIS] — nombre de flux ou de séries renvoyés (0 si erreur).
_m22o_nb() {
  local r
  r="$(_m22o_requete "$@")"
  jq -r 'if .status == "success" then (.data.result | length) else 0 end' <<<"${r:-{\}}" 2>/dev/null || echo 0
}

# _m22o_lignes 'LogQL' LOCATAIRE [DEPUIS] — nombre de LIGNES renvoyées (au plus 100, limite de loki_requete).
_m22o_lignes() {
  local r
  r="$(_m22o_requete "$@")"
  jq -r '[.data.result[]?.values | length] | add // 0' <<<"${r:-{\}}" 2>/dev/null || echo 0
}

# _m22o_texte 'LogQL' LOCATAIRE [DEPUIS] — les lignes renvoyées, une par ligne.
_m22o_texte() {
  local r
  r="$(_m22o_requete "$@")"
  jq -r '.data.result[]?.values[]?[1]' <<<"${r:-{\}}" 2>/dev/null || true
}

# _m22o_etiquettes LOCATAIRE [DEPUIS=1h] — noms d'étiquettes INDEXÉES (sans les métadonnées structurées).
_m22o_etiquettes() {
  loki_api "labels?since=${2:-1h}" "$1" 2>/dev/null | jq -r '.data[]?' 2>/dev/null || true
}

# _m22o_valeurs ÉTIQUETTE LOCATAIRE [DEPUIS=1h] — valeurs d'une étiquette indexée.
_m22o_valeurs() {
  loki_api "label/$1/values?since=${3:-1h}" "$2" 2>/dev/null | jq -r '.data[]?' 2>/dev/null || true
}

# _m22o_regles LOCATAIRE — règles chargées par le ruler (JSON de l'API compatible Prometheus).
_m22o_regles() {
  curl -sf --max-time "$WB_TIMEOUT" -H "X-Scope-OrgID: $1" -H "Accept: application/json" \
    "$_M22O_LOKI/prometheus/api/v1/rules" 2>/dev/null || true
}

# _m22o_fichier_main PROJET CHEMIN [BRANCHE=main] — le fichier existe sur la branche du projet GitLab.
_m22o_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=${3:-main}" >/dev/null 2>&1
}

# _m22o_contenu_main PROJET CHEMIN [BRANCHE=main] — contenu brut du fichier (vide si absent).
_m22o_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=${3:-main}" 2>/dev/null || true
}

# _m22o_prom_valeur 'PromQL' — valeur de la première série (0 si rien).
_m22o_prom_valeur() {
  prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo 0
}

# _m22o_courriels REQUÊTE — nombre de messages de Mailpit qui correspondent à la recherche.
_m22o_courriels() {
  local q
  q="$(jq -rn --arg v "$1" '$v | @uri')"
  mailpit_api "search?query=$q" 2>/dev/null | jq -r '.messages_count // 0' 2>/dev/null || echo 0
}

# Motifs de données personnelles (M22-E09) : NIR et courriel, en RE2 (LogQL).
# shellcheck disable=SC2034  # utilisés par check-E09.sh
_M22O_RE_NIR='\b[12][ .]?[0-9]{2}[ .]?(0[1-9]|1[0-2]|[2-9][0-9])[ .]?(2[ABab]|[0-9]{2})[ .]?[0-9]{3}[ .]?[0-9]{3}[ .]?[0-9]{2}\b'
# shellcheck disable=SC2034
_M22O_RE_COURRIEL='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'
