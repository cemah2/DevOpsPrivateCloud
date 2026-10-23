# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq, requêtes LogQL et commandes distantes entre apostrophes
# _m24-expert.sh — fonctions partagées par les checks M24-E35 à M24-E39 (lecture seule).
# Sourcé par ces check-EXX.sh (lab/bin/check ne lance que les check-EXX.sh ; check-E43 et check-E46
# les rechargent à la suite). Préfixe _m24x_ : pas de collision avec les autres paliers (_m24d_,
# _m24o_, _m24c_, _m24p_) ni avec l'autre partie du palier 4 (_m24y_, _m24-expert-b.sh).
# Réutilise _m24-production.sh (qui charge _m24-decouverte.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - Keycloak : keycloak_api (wb-checks : view-realm, view-users, view-clients ; jamais un secret) ;
#     point d'autorisation PUBLIC (code HTTP d'une demande d'autorisation, aucune connexion faite) ;
#     base de Keycloak par SELECT (sudo -n -u postgres psql sur idp01, comme au palier 3) ;
#   - annuaire : ipa_ldap (compte système wb-checks) ;
#   - Loki (locataire audit : requêtes et règles du ruler), Prometheus (règles chargées) ;
#   - cluster : « kube » (wb-checks : liaisons RBAC, ConfigMaps d'argocd) ;
#   - SSH en admin : date, timedatectl, et lecture du fichier d'authentification en sudo -n (cat) ;
#   - GitLab : fichiers et pipelines de main (gitlab_api).
#
# Variables de lab/lab.env (valeurs par défaut) : WB_M24_IDP (idp01), WB_M24_CP
# (« k8s-cp01 k8s-cp02 k8s-cp03 »), WB_M24_AUTHN_FICHIER (/etc/kubernetes/authentification/config.yaml).

# shellcheck source=_m24-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-production.sh"

read -r -a _M24X_CP <<<"${WB_M24_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
_M24X_AUTHN="${WB_M24_AUTHN_FICHIER:-/etc/kubernetes/authentification/config.yaml}"
_M24X_GROUPES_RE='^(plateforme-admins|plateforme|mediagenda|medidoc|securite|support|direction)$'

# --- Pannes et documentation -------------------------------------------------------------------------

# _m24x_panne_close EXX — la panne n'est plus marquée active (lab/bin/break 24 XX --annuler).
_m24x_panne_close() {
  [[ ! -e "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives/M24-$1" ]]
}

# _m24x_journal EXX — un journal de diagnostic de la panne est sur main (docs/socle/journal/*M24-EXX*).
_m24x_journal() {
  _m24p_arbre plateforme/medisphere docs/socle/journal | grep -Eq -- "M24-$1[^/]*\.md$"
}

# _m24x_rb246 — contenu de RB-246 sur main (vide si absent).
_m24x_rb246() {
  local p
  p="$(_m24p_arbre plateforme/medisphere "$_M24P_DOC/runbooks" | grep -E '/RB-246[^/]*\.md$' | head -n 1 || true)"
  if [[ -n "$p" ]]; then _m24p_doc "$p"; fi
}

# _m24x_section TEXTE REGEX — le document a un titre (#…) qui correspond à la regex (insensible à la casse).
_m24x_section() { [[ -n "$1" ]] && grep -Eqi -- "^#+ .*($2)" <<<"$1"; }

# --- Règles chargées ---------------------------------------------------------------------------------

# _m24x_ruler_qui LOCATAIRE REGEX — une règle d'alerte du ruler de Loki a une requête qui correspond.
_m24x_ruler_qui() {
  curl -sf --max-time "$WB_TIMEOUT" -H "X-Scope-OrgID: $1" -H "Accept: application/json" \
    "$_M24P_LOKI/prometheus/api/v1/rules" 2>/dev/null \
    | jq -e --arg r "$2" '[.data.groups[]?.rules[]? | select(.type == "alerting") | select(.query | test($r))] | length > 0' >/dev/null 2>&1
}

# _m24x_prom_qui REGEX — une règle d'alerte chargée par Prometheus (vue globale) a une expression qui correspond.
_m24x_prom_qui() {
  prom_api "rules?type=alert" 2>/dev/null \
    | jq -e --arg r "$1" '[.data.groups[]?.rules[]? | select(.query | test($r))] | length > 0' >/dev/null 2>&1
}

# --- Loki ---------------------------------------------------------------------------------------------

# _m24x_loki_dernier 'LogQL' LOCATAIRE DEPUIS — horodatage (ns, en chaîne : 19 chiffres dépassent la
# précision d'un nombre jq) de la ligne la plus récente ; « 0 » si
# aucune ligne ; VIDE si Loki ne répond pas (un contrôle qui l'utilise passe alors au rouge).
_m24x_loki_dernier() {
  local r
  r="$(loki_requete "$1" "$2" "$3" 2>/dev/null)" || r=""
  jq -r 'select(.status == "success") | [.data.result[]?.values[]?[0] | tostring] | max_by([length, .]) // "0"' <<<"$r" 2>/dev/null || true
}

# _m24x_apres A B — A et B sont des nombres et A > B (comparaison de grands entiers en chaînes).
_m24x_apres() {
  [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] || return 1
  if ((${#1} != ${#2})); then ((${#1} > ${#2})); return; fi
  [[ "$1" > "$2" ]]
}

# --- Keycloak -----------------------------------------------------------------------------------------

# _m24x_portees_defaut CLIENT_ID — noms des portées par défaut du client (une par ligne).
_m24x_portees_defaut() {
  local id
  id="$(_m24d_kc_client "$1" | jq -r '.id // empty' 2>/dev/null || true)"
  [[ -n "$id" ]] || return 0
  _m24d_kc "clients/$id/default-client-scopes" | jq -r '.[].name' 2>/dev/null || true
}

# _m24x_mappeur_groups — JSON du mappeur « groups » (Group Membership) de la portée « groupes ».
_m24x_mappeur_groups() {
  local pid
  pid="$(_m24d_kc "client-scopes" | jq -r '[.[] | select(.name == "groupes")][0].id // empty' 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 0
  _m24d_kc "client-scopes/$pid/protocol-mappers/models" \
    | jq -c '[.[] | select(.protocolMapper == "oidc-group-membership-mapper")][0] // empty' 2>/dev/null || true
}

# _m24x_noms_courts — la revendication groups est faite de noms courts, dans l'ID token et le jeton d'accès.
_m24x_noms_courts() {
  _m24d_json "$(_m24x_mappeur_groups)" '.config["full.path"] == "false" and .config["claim.name"] == "groups"
    and .config["id.token.claim"] == "true" and .config["access.token.claim"] == "true"'
}

# _m24x_code_auth CLIENT_ID REDIRECT — code HTTP du point d'autorisation (200 : formulaire ; 400 : refus).
_m24x_code_auth() {
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" --cacert "$_M24D_RACINE" -G \
    --data-urlencode "client_id=$1" --data-urlencode "redirect_uri=$2" --data-urlencode response_type=code \
    --data-urlencode scope=openid --data-urlencode "state=wbcheck" \
    "$_M24D_EMETTEUR/protocol/openid-connect/auth" 2>/dev/null || true
}

# _m24x_ldap_federation — composant de la fédération « ipa01 » (JSON, vide si absent).
_m24x_ldap_federation() {
  _m24d_kc "components?type=org.keycloak.storage.UserStorageProvider" \
    | jq -c '[.[] | select(.providerId == "ldap" and .name == "ipa01")][0] // empty' 2>/dev/null || true
}

# _m24x_tofu_valeur FICHIER ARGUMENT — valeur entre guillemets de « ARGUMENT = "…" » dans un .tf de
# plateforme/identite/tofu sur main (vide si absent).
_m24x_tofu_valeur() {
  _m24d_contenu_main plateforme/identite "tofu/$1" \
    | sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*(#.*)?\$/\\1/p" | head -n 1 || true
}

# --- VMs ----------------------------------------------------------------------------------------------

# _m24x_ecart HÔTE — écart d'horloge en secondes (hôte − adm01) ; vide si l'hôte ne répond pas.
_m24x_ecart() {
  local d
  d="$(remote "$1" 'date +%s' </dev/null 2>/dev/null || true)"
  [[ "$d" =~ ^[0-9]+$ ]] || return 0
  printf '%s\n' "$((d - $(date +%s)))"
}

# _m24x_a_l_heure HÔTE — écart de moins de 5 s et noyau synchronisé par le service de temps.
_m24x_a_l_heure() {
  local e
  e="$(_m24x_ecart "$1")"
  [[ -n "$e" ]] && ((e > -5 && e < 5)) || return 1
  [[ "$(remote "$1" 'timedatectl show -p NTPSynchronized --value' </dev/null 2>/dev/null || true)" == yes ]]
}

# _m24x_authn_json NŒUD — fichier d'authentification structurée du nœud, en JSON compact (sans les
# commentaires, que le gabarit du rôle personnalise par nœud) ; vide si illisible.
_m24x_authn_json() {
  remote "$1" "sudo -n cat $(printf '%q' "$_M24X_AUTHN")" </dev/null 2>/dev/null \
    | yq -o=json -I=0 '.' 2>/dev/null || true
}
