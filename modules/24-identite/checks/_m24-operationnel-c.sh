# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# _m24-operationnel-c.sh — fonctions partagées par les checks M24-E17 à M24-E21 (lecture seule).
# Sourcé par ces check-EXX.sh (lab/bin/check ne lance que les check-EXX.sh). Préfixe _m24c_ : pas de
# collision avec les fonctions des autres parties du palier (_m24o_) ni des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - Keycloak : « keycloak_api » (client wb-checks du royaume medisphere : view-realm, view-users,
#     view-clients) ; découverte et pages publiques sans authentification ;
#   - annuaire : « ipa_ldap » (compte système wb-checks) ;
#   - cluster : « kube » (compte de service wb-checks : lecture sans Secrets, création de
#     SubjectAccessReview, qui n'écrit rien dans etcd) ;
#   - VMs : SSH en admin, commandes de consultation seulement (sudo -n en lecture) ;
#   - GitLab : gitlab_api (jeton read_api) ; Mailpit : mailpit_api (compte wb-checks) ;
#   - step-ca : liste PUBLIQUE des provisioners (GET /provisioners).
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_MOI              ton identifiant (bloc A) : aussi ton compte dans l'annuaire (E03)
#   WB_M24_INSCRITS     hôtes inscrits dans l'annuaire (E19), séparés par des espaces
#   WB_M24_MON01        alias SSH de mon01 (mon01)
#   WB_STEP_CA_URL      URL de step-ca (https://ca01.par1.medisphere.internal)
#   WB_RACINE_PKI       racine MédiSphère sur adm01

_M24C_MOI="${WB_MOI:-}"
_M24C_DOMAINE=par1.medisphere.internal
_M24C_BASE="dc=par1,dc=medisphere,dc=internal"
_M24C_SSO="${WB_KEYCLOAK_URL:-https://sso.par1.medisphere.internal}"
_M24C_EMETTEUR="$_M24C_SSO/realms/medisphere"
_M24C_RACINE="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_M24C_MON01="${WB_M24_MON01:-mon01}"
_M24C_STEP_CA="${WB_STEP_CA_URL:-https://ca01.par1.medisphere.internal}"
# Hôtes inscrits (E19) : socle hors bordure et hors ipa01 (le serveur), puis les nœuds de k8s-par1.
read -r -a _M24C_INSCRITS <<<"${WB_M24_INSCRITS:-adm01 dns01 ca01 git01 nbx01 s3-01 runner01 dns02 lb01 lb02 runner02 reg01 mon01 idp01 k8s-cp01 k8s-cp02 k8s-cp03 k8s-w01 k8s-w02 k8s-w03}"
_M24C_BORDURE=(gw01 gw02)

# _m24c_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m24c_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m24c_uri TEXTE — encodage pour une URL.
_m24c_uri() { jq -rn --arg v "$1" '$v | @uri'; }

# _m24c_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m24c_contenu_main() {
  gitlab_api "projects/$(_m24c_uri "$1")/repository/files/$(_m24c_uri "$2")/raw?ref=main" 2>/dev/null || true
}

# _m24c_sur_main PROJET CHEMIN REGEX — le fichier existe sur main et contient la regex étendue.
_m24c_sur_main() {
  local c
  c="$(_m24c_contenu_main "$1" "$2")"
  [[ -n "$c" ]] && grep -Eq -- "$3" <<<"$c"
}

# _m24c_kc CHEMIN — API d'administration du royaume medisphere (sortie vide en cas d'erreur).
_m24c_kc() { keycloak_api "$1" 2>/dev/null || true; }

# _m24c_kc_client CLIENT_ID — représentation JSON du client (vide si absent ou illisible), sans son
# secret (Keycloak 26.7 le livre à view-clients : voir _m24d_kc_client).
_m24c_kc_client() {
  _m24c_kc "clients?clientId=$(_m24c_uri "$1")" | jq -c '.[0] // empty | del(.secret)' 2>/dev/null || true
}

# _m24c_kc_utilisateur IDENTIFIANT — identifiant interne Keycloak de la personne (vide si absente).
_m24c_kc_utilisateur() {
  _m24c_kc "users?username=$(_m24c_uri "$1")&exact=true&briefRepresentation=true" | jq -r '.[0].id // empty' 2>/dev/null || true
}

# _m24c_ldap FILTRE [ATTRIBUTS…] — recherche dans l'annuaire (sortie vide en cas d'erreur).
_m24c_ldap() { ipa_ldap "$@" 2>/dev/null || true; }

# _m24c_ssh HÔTE COMMANDE — sortie d'une commande de consultation sur une VM (vide si échec).
_m24c_ssh() { remote "$1" "$2" 2>/dev/null || true; }

# _m24c_k ARGS… — kubectl en lecture avec wb-checks ; sortie standard seule, vide si erreur.
_m24c_k() { kube "$@" 2>/dev/null || true; }

# _m24c_peut UTILISATEUR GROUPES(virgules) VERBE RESSOURCE [ESPACE] [SOUS-RESSOURCE] [GROUPE_API]
#   Décision de l'autorisateur (SubjectAccessReview) pour cette identité : « yes », « no » ou « ? ».
#   Même méthode que _m14o_peut (M14) : aucun droit d'usurpation n'est nécessaire.
_m24c_peut() {
  local u="$1" g="$2" verbe="$3" res="$4" ns="${5:-}" sous="${6:-}" api="${7:-}"
  jq -n --arg u "$u" --arg g "$g" --arg v "$verbe" --arg r "$res" --arg ns "$ns" --arg s "$sous" --arg a "$api" '
    {apiVersion: "authorization.k8s.io/v1", kind: "SubjectAccessReview",
     spec: {user: $u, groups: ($g | split(",") + ["system:authenticated"]),
            resourceAttributes: ({verb: $v, resource: $r, group: $a}
              + (if $ns != "" then {namespace: $ns} else {} end)
              + (if $s != "" then {subresource: $s} else {} end))}}' \
    | kube create -f - -o json 2>/dev/null \
    | jq -r 'if .status.allowed == true then "yes" else "no" end' 2>/dev/null || echo "?"
}

# _m24c_droit ATTENDU(yes|no) UTILISATEUR GROUPES VERBE RESSOURCE [ESPACE] [SOUS-RESSOURCE] [GROUPE_API]
#   OK (code 0) si la décision est celle attendue.
_m24c_droit() {
  local attendu="$1"
  shift
  [[ "$(_m24c_peut "$@")" == "$attendu" ]]
}

# _m24c_vers_sso URL CLIENT_ID — une visite SANS session est renvoyée (302) vers le point
#   d'autorisation du royaume medisphere, pour ce client, avec PKCE S256.
_m24c_vers_sso() {
  local url="$1" client="$2" loc
  loc="$(curl -s -o /dev/null --max-time "$WB_TIMEOUT" --cacert "$_M24C_RACINE" -w '%{http_code} %{redirect_url}' "$url" 2>/dev/null)" || return 1
  # OAuth2 Proxy peut passer par /oauth2/start (page de connexion sautée) : on suit au plus un saut local.
  if [[ "$loc" =~ ^30[27]\ (https://[^/]+)?/oauth2/start ]]; then
    loc="$(curl -s -o /dev/null --max-time "$WB_TIMEOUT" --cacert "$_M24C_RACINE" -w '%{http_code} %{redirect_url}' "${loc#* }" 2>/dev/null)" || return 1
  fi
  [[ "$loc" =~ ^30[27]\  ]] || return 1
  loc="${loc#* }"
  [[ "$loc" == "$_M24C_EMETTEUR/protocol/openid-connect/auth?"* ]] \
    && grep -Eq "[?&]client_id=$client(&|$)" <<<"$loc" \
    && grep -Eq '[?&]code_challenge_method=S256(&|$)' <<<"$loc"
}

# _m24c_provisioners — liste publique des provisioners de step-ca (JSON, vide si erreur).
_m24c_provisioners() {
  curl -sf --max-time "$WB_TIMEOUT" --cacert "$_M24C_RACINE" "$_M24C_STEP_CA/provisioners?limit=100" 2>/dev/null || true
}
