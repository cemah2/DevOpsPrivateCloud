# shellcheck shell=bash
# outils/rotation/commun.sh — fonctions communes des rotations automatiques (M25-E33, SEC-2633).
# Sourcé par les scripts de outils/rotation/. Règles : aucune valeur de secret dans une variable
# d'environnement exportée, sur une ligne de commande ou dans la sortie ; les valeurs passent par
# des tubes et par « clé=- » (lecture sur l'entrée standard) de la CLI bao.
# Prérequis : BAO_ADDR et BAO_TOKEN (jeton du job, rôle ci-secrets-rotation, M25-E33), bao, jq, curl.
set -euo pipefail
umask 077

journal() { printf '[rotation] %s %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }
echec() { journal "ÉCHEC : $*"; exit 1; }
besoin() { local c; for c in "$@"; do command -v "$c" >/dev/null || echec "outil manquant : $c"; done; }

# kv_champ CHEMIN CHAMP — valeur d'un champ KV v2 (montage kv), sur la sortie standard (pour un tube).
kv_champ() { bao kv get -mount=kv -field="$2" "$1"; }

# kv_ecrire_champ CHEMIN CHAMP — remplace un champ (les autres sont gardés), valeur lue sur l'entrée
# standard ; crée une NOUVELLE VERSION (preuve de rotation : created_time de la version).
# ⚠️ « champ=- » garde TOUT ce qui arrive, saut de ligne final compris (essayé) : produire la valeur
# sans saut de ligne (jq -j, printf '%s').
kv_ecrire_champ() { bao kv patch -mount=kv "$1" "$2=-" >/dev/null; }

# kv_meta CHEMIN 'filtre jq' — lit les métadonnées (custom_metadata, versions) du secret.
kv_meta() { bao kv metadata get -mount=kv -format=json "$1" | jq -r "$2"; }

# curl_jeton JETON_SUR_STDIN URL [options curl…] — curl avec « Authorization: Bearer » lu sur
# l'entrée standard (jamais en argument).
curl_bearer() {
  local url="$1"
  shift
  curl -sS --fail-with-body --max-time 20 -K <(printf 'header = "Authorization: Bearer %s"\n' "$(cat)") "$@" "$url"
}
