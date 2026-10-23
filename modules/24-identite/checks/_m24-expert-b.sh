# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# _m24-expert-b.sh — fonctions partagées par les checks M24-E40 à M24-E46 (lecture seule).
# Sourcé par ces check-EXX.sh (lab/bin/check ne lance que les check-EXX.sh). Préfixe _m24y_ : pas de
# collision avec les autres parties du palier (_m24x_) ni avec les autres paliers (_m24d_, _m24o_,
# _m24c_, _m24p_), quand check-E43 et check-E46 chargent plusieurs checks à la suite.
# Réutilise _m24-production.sh (qui charge _m24-decouverte.sh) et _m24-operationnel-c.sh.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) : découverte et point d'autorisation PUBLICS de Keycloak (aucune connexion
# n'est faite : on lit le code HTTP) ; keycloak_api (wb-checks) ; ipa_ldap (wb-checks de l'annuaire) ;
# GitLab (gitlab_api, fichiers de main) ; SSH en admin et commandes de consultation (sudo -n : stat,
# grep, systemctl is-active, sssctl, sudo -l -U, psql -c « SHOW »/SELECT, journalctl) ; liste publique
# des provisioners de step-ca ; en-têtes de la réponse d'OAuth2 Proxy à une visite sans session.
#
# Variables de lab/lab.env (valeurs par défaut) : WB_M24_IDP (idp01), WB_M24_MON01 (mon01),
# WB_M24_VM_SSSD (nbx01), WB_M24_LB (« lb01 lb02 »), WB_M24_KC_CONF, WB_M24_HAPROXY_CFG.

# shellcheck source=_m24-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-production.sh"
# shellcheck source=_m24-operationnel-c.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel-c.sh"

_M24Y_VM_SSSD="${WB_M24_VM_SSSD:-nbx01}"
_M24Y_KC_CONF="${WB_M24_KC_CONF:-/opt/keycloak/conf/keycloak.conf}"
_M24Y_HAPROXY="${WB_M24_HAPROXY_CFG:-/etc/haproxy/haproxy.cfg}"
_M24Y_O2P_URL="${WB_M24_O2P_URL:-https://mon01.par1.medisphere.internal:8443}"
read -r -a _M24Y_LB <<<"${WB_M24_LB:-lb01 lb02}"

# _m24y_aucune_panne [EXX…] — aucune des pannes listées (ou aucune panne M24) n'est marquée active.
_m24y_aucune_panne() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M24-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M24-$e" ]] || return 1
  done
}

# _m24y_doc_trouver DOSSIER REGEX — premier chemin de plateforme/medisphere (main) sous DOSSIER qui
# correspond à la regex étendue (vide si aucun).
_m24y_doc_trouver() {
  _m24p_arbre plateforme/medisphere "$1" | grep -E -- "$2" | head -n 1 || true
}

# _m24y_rb246 — contenu de RB-246 sur main (vide si absent).
_m24y_rb246() {
  local p
  p="$(_m24y_doc_trouver "$_M24P_DOC/runbooks" '/RB-246[^/]*\.md$')"
  if [[ -n "$p" ]]; then _m24p_doc "$p"; fi
}

# _m24y_sans_jeton TEXTE — le texte est non vide et ne contient aucun JWT complet (trois parties
# base64url, en-tête et charge commençant par « eyJ ») ni bloc de clé privée.
_m24y_sans_jeton() {
  [[ -n "${1//[[:space:]]/}" ]] \
    && ! grep -Eq 'eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{16,}' <<<"$1" \
    && ! grep -q 'PRIVATE KEY' <<<"$1"
}

# _m24y_emetteur — émetteur annoncé par la découverte publique (vide si muette).
_m24y_emetteur() { _m24d_public "/realms/medisphere/.well-known/openid-configuration" | jq -r '.issuer // empty' 2>/dev/null || true; }

# _m24y_code_auth CLIENT_ID REDIRECT — code HTTP du point d'autorisation pour cette redirection
# (200 : formulaire ; 400 : redirection refusée). Aucune connexion n'est faite.
_m24y_code_auth() {
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" --cacert "$_M24D_RACINE" -G \
    --data-urlencode "client_id=$1" --data-urlencode "redirect_uri=$2" --data-urlencode response_type=code \
    --data-urlencode scope=openid --data-urlencode "state=wbcheck" \
    "$_M24D_EMETTEUR/protocol/openid-connect/auth" 2>/dev/null || true
}

# _m24y_entetes URL — en-têtes de la réponse à une visite sans session (sans suivre les redirections).
_m24y_entetes() {
  curl -s -o /dev/null -D - --max-time "$WB_TIMEOUT" --cacert "$_M24D_RACINE" "$1" 2>/dev/null | tr -d '\r' || true
}

# _m24y_ssh_ok HÔTE 'commande' — la commande de consultation affiche « oui » sur l'hôte.
_m24y_ssh_ok() { [[ "$(_m24d_ssh "$1" "$2" | tail -n 1)" == oui ]]; }

# _m24y_clients_tous — tous les clients du royaume (JSON), vide si illisible, SANS leurs secrets
# (livrés à view-clients, voir _m24d_kc_client) : retirés dès la lecture.
_m24y_clients_tous() {
  _m24d_kc "clients?max=500" | jq -c 'map(del(.secret))' 2>/dev/null || true
}
