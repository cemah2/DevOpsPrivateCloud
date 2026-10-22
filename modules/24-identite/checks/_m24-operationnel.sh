# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et expressions régulières entre apostrophes (pas de développement voulu)
# _m24-operationnel.sh — fonctions partagées par les checks M24-E11 à M24-E16 (lecture seule).
# Sourcé par les check-EXX.sh du palier 2 (lab/bin/check ne lance que les check-EXX.sh). Il source
# lui-même _m24-decouverte.sh (constantes du module, _m24d_kc, _m24d_contenu_main, _m24d_ssh…).
# Préfixe _m24o_ : pas de collision avec les fonctions des autres paliers ni avec celles de
# _m24-operationnel-c.sh (préfixe _m24c_, M24-E17 à E23).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - Keycloak : « keycloak_api » (client wb-checks du royaume medisphere : view-clients suffit pour
#     lire la représentation des clients, jamais leur secret) ; découverte publique ;
#   - GitLab : gitlab_api (jeton read_api) ; Grafana : grafana_api (compte de service Viewer) ;
#     Harbor : harbor_api (robot de lecture) ; cluster : « kube » (wb-checks) ;
#   - SSH en consultation : root@pve01 (WB_PVE_HOST), root@pbs01 (WB_PBS_HOST), admin@nbx01,
#     admin@k8s-cp01..03 (sudo -n en lecture).
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous), en plus de celles du palier 1 :
#   WB_M24_NBX01       alias SSH de nbx01 (nbx01)
#   WB_M24_CP          nœuds de contrôle, séparés par des espaces (k8s-cp01 k8s-cp02 k8s-cp03)

# shellcheck source=_m24-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-decouverte.sh"

_M24O_NBX01="${WB_M24_NBX01:-nbx01}"
read -r -a _M24O_CP <<<"${WB_M24_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
_M24O_P_IDENTITE="plateforme/identite"
_M24O_P_ANSIBLE="plateforme/ansible"
_M24O_P_INFRA="plateforme/infra"
_M24O_P_K8S="plateforme/k8s"
_M24O_P_OBS="plateforme/observabilite"
_M24O_P_GITOPS="plateforme/gitops"
_M24O_VAULT_CRITIQUE='^\$ANSIBLE_VAULT;1\.2;AES256;critique$'

# _m24o_k ARGS… — kubectl en lecture par le compte des checks (sortie vide en cas d'erreur).
_m24o_k() { kube "$@" 2>/dev/null || true; }

# _m24o_json JSON [--arg NOM VALEUR]… FILTRE — OK si le filtre jq (-e), DERNIER argument, est vrai.
_m24o_json() {
  local donnees="$1"
  shift
  local filtre="${*: -1}"
  local -a options=("${@:1:$#-1}")
  [[ -n "$donnees" ]] && jq -e "${options[@]}" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m24o_portees_client CLIENT_ID — noms des portées PAR DÉFAUT du client (une par ligne, vide si erreur).
_m24o_portees_client() {
  local id
  id="$(_m24d_kc_client "$1" | jq -r '.id // empty' 2>/dev/null || true)"
  [[ -n "$id" ]] || return 0
  _m24d_kc "clients/$id/default-client-scopes" | jq -r '.[].name' 2>/dev/null || true
}

# _m24o_controler_client CLIENT TYPE PKCE REDIRECTION… — contrôles communs d'un client OIDC de service
#   (faits communs du palier 2). TYPE : confidentiel | public ; PKCE : S256 | non (pas exigé).
#   Chaque contrôle peut passer au rouge : client absent, flux supplémentaire, joker, redirection en
#   plus ou en moins, PKCE retiré, portée « groupes » retirée, tous les rôles du royaume dans les jetons.
_m24o_controler_client() {
  local client="$1" type="$2" pkce="$3" json redirections portees public
  shift 3
  redirections="$(printf '%s\n' "$@" | jq -R . | jq -sc 'sort')"
  json="$(_m24d_kc_client "$client")"
  if [[ -z "$json" ]]; then
    _ko "Keycloak : client $client absent du royaume medisphere (ou API illisible avec wb-checks)"
    return 0
  fi
  [[ "$type" == public ]] && public=true || public=false
  check_cmd "Client $client : $type, flux standard seul (ni implicite, ni Direct Access Grants, ni compte de service)" \
    _m24o_json "$json" --argjson p "$public" '.enabled == true and .publicClient == $p and .standardFlowEnabled == true
      and .implicitFlowEnabled == false and .directAccessGrantsEnabled == false and (.serviceAccountsEnabled | not)
      and ((.attributes["oauth2.device.authorization.grant.enabled"] // "false") == "false")'
  check_cmd "Client $client : redirections exactes, sans joker : $*" \
    _m24o_json "$json" --argjson r "$redirections" '(.redirectUris | sort) == $r and all(.redirectUris[]; contains("*") | not)'
  if [[ "$pkce" == S256 ]]; then
    check_cmd "Client $client : PKCE S256 exigé" _m24o_json "$json" '.attributes["pkce.code.challenge.method"] == "S256"'
  fi
  check_cmd "Client $client : aucun rôle du royaume recopié dans les jetons (full scope désactivé)" \
    _m24o_json "$json" '.fullScopeAllowed == false'
  portees="$(_m24o_portees_client "$client")"
  check_cmd "Client $client : portée par défaut « groupes » (revendication groups)" grep -qx groupes <<<"$portees"
}

# _m24o_fichier_main PROJET CHEMIN REGEX — le fichier existe sur main et correspond à la regex.
_m24o_fichier_main() {
  _m24d_contient "$(_m24d_contenu_main "$1" "$2")" "$3"
}

# _m24o_vault_critique PROJET CHEMIN — le fichier sur main est un Ansible Vault de l'identité « critique ».
_m24o_vault_critique() {
  _m24d_contenu_main "$1" "$2" | head -n 1 | grep -Eq -- "$_M24O_VAULT_CRITIQUE"
}

# _m24o_aucune_ligne REGEX TEXTE — le texte est NON VIDE et aucune ligne ne correspond.
_m24o_aucune_ligne() { [[ -n "${2//[[:space:]]/}" ]] && ! grep -Eq -- "$1" <<<"$2"; }

# _m24o_membres_gitlab GROUPE — JSON des membres DIRECTS d'un groupe GitLab (vide si erreur).
_m24o_membres_gitlab() {
  gitlab_api "groups/$(_m24d_uri "$1")/members?per_page=100" 2>/dev/null || true
}

# _m24o_jeton_wb_checks — jeton d'accès du client wb-checks (client_credentials), sur la sortie
#   standard, pour le présenter à un AUTRE service (refus attendu, M24-E16). Jamais affiché par les checks.
_m24o_jeton_wb_checks() {
  local f="${WB_KEYCLOAK_CHECKS_FILE:-$HOME/.config/workbook/keycloak-checks.env}" KEYCLOAK_CLIENT_ID="" KEYCLOAK_CLIENT_SECRET=""
  [[ -r "$f" ]] || return 0
  # shellcheck disable=SC1090
  source "$f"
  curl -sf --max-time "$WB_TIMEOUT" --cacert "$_M24D_RACINE" \
    -K <(printf 'user = "%s:%s"\n' "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET") \
    -d grant_type=client_credentials "${WB_KEYCLOAK_URL:-$_M24D_SSO}/realms/medisphere/protocol/openid-connect/token" 2>/dev/null \
    | jq -r '.access_token // empty' 2>/dev/null || true
}

# _m24o_cnp ESPACE NOM — JSON d'une CiliumNetworkPolicy (vide si absente ou illisible).
_m24o_cnp() { _m24o_k -n "$1" get ciliumnetworkpolicies.cilium.io "$2" -o json; }
