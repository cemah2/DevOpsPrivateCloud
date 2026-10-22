# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-E35.sh — M24-E35 « Panne : plus personne n'entre dans Grafana »
#
# Trois variantes, toutes côté Keycloak (royaume medisphere, client « grafana »), comme un clic de
# trop dans la console :
#   1. secret du client remplacé dans Keycloak (Grafana garde l'ancien : l'échange du code échoue,
#      événement CODE_TO_TOKEN_ERROR, invalid_client_credentials) ;
#   2. URI de redirection « nettoyée » : …/login/generic_oauth remplacée par …/login/oauth (Keycloak
#      refuse la redirection avant même le formulaire : « Invalid parameter: redirect_uri ») ;
#   3. portée « groupes » retirée des portées par défaut du client : plus de revendication groups,
#      role_attribute_strict de Grafana refuse la connexion.
# Export JSON du client avant modification ; restauration seulement si la valeur injectée est encore là.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m24-commun.sh
source "$WB_ROOT/modules/24-identite/corrige/pannes/_m24-commun.sh"

_E35_CLIENT=grafana
_E35_RAPPEL="$_M24_GRAFANA/login/generic_oauth"
_E35_RAPPEL_FAUX="$_M24_GRAFANA/login/oauth"

# _e35_secret_invalide SECRET — le point de jetons rejette ce secret pour le client grafana.
# (client_credentials : un secret juste donne « unauthorized_client » — le client n'a pas de compte de
# service — ; un secret faux donne « invalid_client » / « Invalid client or Invalid client credentials ».)
_e35_secret_invalide() {
  local r
  r="$(curl -s --max-time 20 --cacert "$_M24_RACINE" -K <(printf 'user = "%s:%s"\n' "$_E35_CLIENT" "$1") \
    -d grant_type=client_credentials "$_M24_EMETTEUR/protocol/openid-connect/token" 2>/dev/null)" || return 1
  jq -e '(.error // "") == "invalid_client" or ((.error_description // "") | test("[Ii]nvalid client"))' >/dev/null 2>&1 <<<"$r"
}

_m24E35_une() {
  local n="$1" c id s neuf pid
  c="$(m24_kc_client "$_E35_CLIENT")"
  [[ -n "$c" ]] || return 10
  id="$(jq -r .id <<<"$c")"
  m24_kc_sauver E35 client "$c"
  m24_ecrire E35 variante "$n"
  case "$n" in
    1)
      s="$(m24_kc GET "clients/$id/client-secret" 2>/dev/null | jq -r '.value // empty')" || s=""
      [[ -n "$s" ]] || return 10
      m24_ecrire E35 secret-avant "$s"
      neuf="$(openssl rand -hex 24)"
      m24_ecrire E35 secret-injecte "$neuf"
      m24_kc_json PUT "clients/$id" "$(jq -c --arg s "$neuf" '{id, clientId, secret: $s}' <<<"$c")" >/dev/null || return 1
      ;;
    2)
      jq -e --arg u "$_E35_RAPPEL" '.redirectUris | index($u) != null' >/dev/null <<<"$c" || return 10
      m24_kc_json PUT "clients/$id" "$(jq -c --arg a "$_E35_RAPPEL" --arg b "$_E35_RAPPEL_FAUX" \
        '{id, clientId, redirectUris: [.redirectUris[] | if . == $a then $b else . end]}' <<<"$c")" >/dev/null || return 1
      ;;
    3)
      pid="$(m24_kc_portee_uuid groupes)"
      [[ -n "$pid" ]] || return 10
      m24_kc GET "clients/$id/default-client-scopes" 2>/dev/null | jq -e --arg p "$pid" 'any(.[]; .id == $p)' >/dev/null || return 10
      m24_ecrire E35 portee "$pid"
      m24_kc DELETE "clients/$id/default-client-scopes/$pid" >/dev/null || return 1
      ;;
  esac
  m24_journal E35 "variante $n posée sur le client $_E35_CLIENT"
}

verifier_E35() {
  local id
  id="$(m24_kc_client_uuid "$_E35_CLIENT")"
  [[ -n "$id" ]] || return 1
  case "$WB_VAR" in
    1) m24_attendre 30 _e35_secret_invalide "$(m24_lire E35 secret-avant)" ;;
    2) [[ "$(m24_kc_code_auth "$_E35_CLIENT" "$_E35_RAPPEL")" == 400 ]] ;;
    3) ! m24_kc GET "clients/$id/default-client-scopes" 2>/dev/null | jq -e --arg p "$(m24_lire E35 portee)" 'any(.[]; .id == $p)' >/dev/null ;;
    *) return 1 ;;
  esac
}

panne_E35_v1() { m24_sain_keycloak && m24_essayer E35 3 1; }
panne_E35_v2() { m24_sain_keycloak && m24_essayer E35 3 2; }
panne_E35_v3() { m24_sain_keycloak && m24_essayer E35 3 3; }

annuler_E35() {
  local v id c s inj pid
  v="$(m24_lire E35 variante)"
  id="$(m24_kc_client_uuid "$_E35_CLIENT" 2>/dev/null || true)"
  if [[ -n "$id" && -n "$v" ]]; then
    c="$(m24_kc GET "clients/$id" 2>/dev/null || true)"
    case "$v" in
      1)
        s="$(m24_lire E35 secret-avant)"
        inj="$(m24_lire E35 secret-injecte)"
        if [[ -n "$s" && "$(m24_kc GET "clients/$id/client-secret" 2>/dev/null | jq -r '.value // empty' 2>/dev/null || true)" == "$inj" ]]; then
          m24_kc_json PUT "clients/$id" "$(jq -nc --arg i "$id" --arg c "$_E35_CLIENT" --arg s "$s" '{id: $i, clientId: $c, secret: $s}')" >/dev/null 2>&1 ||
            wb_avert "secret du client grafana non rétabli (export : $(m24_etat E35)/kc-client.json)"
        else
          m24_journal E35 "secret déjà changé depuis la panne (réparé ?) : rien à défaire"
        fi
        ;;
      2)
        if jq -e --arg b "$_E35_RAPPEL_FAUX" '.redirectUris | index($b) != null' >/dev/null 2>&1 <<<"$c"; then
          m24_kc_json PUT "clients/$id" "$(jq -c --arg a "$_E35_RAPPEL" --arg b "$_E35_RAPPEL_FAUX" \
            '{id, clientId, redirectUris: ([.redirectUris[] | if . == $b then $a else . end] | unique)}' <<<"$c")" >/dev/null 2>&1 ||
            wb_avert "redirection du client grafana non rétablie"
        fi
        ;;
      3)
        pid="$(m24_lire E35 portee)"
        if [[ -n "$pid" ]]; then
          m24_kc PUT "clients/$id/default-client-scopes/$pid" >/dev/null 2>&1 || wb_avert "portée groupes non rattachée au client grafana"
        fi
        ;;
    esac
  fi
  m24_oublier E35 secret-avant
  m24_oublier E35 secret-injecte
  m24_oublier E35 portee
  m24_oublier E35 variante
  m24_kc_oublier E35 client
  m24_journal E35 "annulation"
}

resume_E35() { echo "Plus personne n'entre dans Grafana par le SSO depuis ce matin ; le compte de service wb-checks, lui, répond."; }

symptome_E35() {
  local detail
  case "$WB_VAR" in
    1) detail="Je clique sur « SSO MédiSphère », je tape mon mot de passe, et je reviens sur Grafana avec « Login failed »." ;;
    2) detail="Je clique sur « SSO MédiSphère » et j'arrive sur une page d'erreur de Keycloak, sans formulaire." ;;
    *) detail="Je passe bien par le formulaire de Keycloak, puis Grafana m'affiche un refus de connexion." ;;
  esac
  wb_symptome "Ticket INC-5135 — De : Julien Petit" \
    "Plus personne n'entre dans Grafana depuis $(date +%H:%M) : ni moi, ni Nadia, ni Karim." \
    "$detail" \
    "Hier tout marchait. Lucas dit avoir « juste regardé » la console de Keycloak ce matin." \
    "Les tableaux s'affichent toujours pour les vérifications (compte de service wb-checks)." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 24 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 24 E35 3 "$@"; }
fi
