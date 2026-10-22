# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq et LogQL entre apostrophes
# break-E21.sh — M22-E21 « Panne : les requêtes expirent »
#
# Un commit de Lucas dans plateforme/observabilite (loki/values.yaml) « protège Loki des requêtes trop
# lourdes » en ajoutant une surcharge au locataire plateforme :
#   1. query_timeout: 1s       → requêtes interrompues (504 « request timed out ») ; sans effet si la
#                                requête de référence répond quand même en moins d'une seconde ;
#   2. max_query_length: 6h    → toute requête sur plus de 6 h refusée (400 « the query time range
#                                exceeds the limit ») ;
#   3. max_query_series: 3     → toute requête métrique qui renvoie plus de 3 séries refusée (400
#                                « maximum number of series (3) reached »).
# Requête de référence (le tableau de Nadia) : nombre de lignes par espace sur 24 h, locataire plateforme.
# Annulation : commit inverse si le fichier est encore exactement dans l'état injecté.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m22-commun.sh
source "$WB_ROOT/modules/22-logs/corrige/pannes/_m22-commun.sh"

_E21_REF='sum by (namespace) (count_over_time({namespace=~".+"}[10m]))'

# _e21_reference — code HTTP de la requête de référence sur 24 h.
_e21_reference() { m22_requete plateforme "$_E21_REF" 24h | jq -r '.http' 2>/dev/null; }
_e21_reference_echoue() {
  local c
  c="$(_e21_reference)"
  [[ -n "$c" && "$c" != 200 ]]
}

# _e21_limite_vaut CLÉ VALEUR — la limite publiée pour plateforme vaut VALEUR.
_e21_limite_vaut() { [[ "$(m22_limite plateforme "$1")" == "$2" ]]; }
_e21_v1_chargee() { _e21_limite_vaut query_timeout 1s; }
_e21_v2_chargee() { _e21_limite_vaut max_query_length 6h; }
_e21_v3_chargee() { _e21_limite_vaut max_query_series 3; }

_m22E21_une() {
  local n="$1" expr msg
  # La requête de référence doit fonctionner avant la panne.
  if _e21_reference_echoue; then
    echo "La requête de référence sur 24 h échoue déjà avant la panne (lab/bin/check 22 21)." >&2
    return 1
  fi
  case "$n" in
    1) expr='.loki.runtimeConfig.overrides.plateforme.query_timeout = "1s"'
       msg="Une requête qui dure plus d'une seconde, c'est une requête mal écrite." ;;
    2) expr='.loki.runtimeConfig.overrides.plateforme.max_query_length = "6h"'
       msg="Personne n'a besoin de plus de 6 h d'un coup, et ça soulage Loki." ;;
    3) expr='.loki.runtimeConfig.overrides.plateforme.max_query_series = 3'
       msg="Moins de séries = moins de mémoire." ;;
  esac
  m22_poser E21 expr "$expr"
  _m22_transformer() {
    local f
    f="$(mktemp)"
    cat >"$f"
    yq -e '.loki.runtimeConfig.overrides' "$f" >/dev/null 2>&1 || { rm -f "$f"; return 10; }
    yq "$(m22_lire E21 expr)" "$f"
    rm -f "$f"
  }
  m22_git_modifier E21 "$_M22_F_LOKI" "perf(loki): protéger Loki des requêtes trop lourdes (M22-E21)

$msg -- Lucas" || return $?
  m22_attendre 420 "_e21_v${n}_chargee" || return 1
  sleep 15
  if ! _e21_reference_echoue; then
    _e21_defaire
    return 10
  fi
  m22_journal E21 "variante $n posée"
}

_e21_defaire() {
  m22_git_annuler E21 || true
  m22_oublier E21 expr
}

panne_E21_v1() { m22_preparer && m22_essayer E21 3 1; }
panne_E21_v2() { m22_preparer && m22_essayer E21 3 2; }
panne_E21_v3() { m22_preparer && m22_essayer E21 3 3; }

verifier_E21() { _e21_reference_echoue; }

annuler_E21() {
  _e21_defaire
  m22_journal E21 "annulation"
}

resume_E21() {
  echo "Le tableau « Activité par espace sur 24 h » de Nadia tombe en erreur, comme toute requête un peu longue dans Explore."
}

symptome_E21() {
  wb_symptome "Ticket INC-4921 — De : Nadia Roussel" \
    "Mon tableau « Activité par espace sur 24 h » (locataire plateforme) affiche une erreur" \
    "depuis ce matin, et dans Explore les requêtes sur plusieurs heures échouent alors que" \
    "celles sur 5 minutes passent. Les autres locataires ont l'air d'aller. Rien n'a changé" \
    "dans le tableau. Je veux mes requêtes, et une explication." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 22 21"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 22 E21 3 "$@"; }
fi
