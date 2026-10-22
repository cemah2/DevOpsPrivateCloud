# shellcheck shell=bash
# _m25-decouverte.sh — fonctions partagées par les checks M25-E03 à M25-E08 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m25d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès à OpenBao (tous en LECTURE ; jamais kv/data/*) :
#   - à partir de M25-E07 : « bao_api » (AppRole wb-checks, ~/.config/workbook/openbao-checks.env,
#     politique de métadonnées seulement) ;
#   - avant M25-E07 (le fichier n'existe pas encore) : le jeton de TA session de la CLI bao
#     (« bao print token » : jeton racine initial jusqu'à E08, ou ton jeton OIDC). Le check le
#     signale par une ligne « ignoré » et ne fait que des lectures avec ce jeton.
#   - sys/health et sys/seal-status : sans jeton.
# Autres accès : SSH en admin sur vault01 (consultation, sudo -n en lecture), GitLab (gitlab_api),
# NetBox (netbox_api), Keycloak (keycloak_api, client wb-checks du M24).
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_MOI                 ton identifiant (bloc A)
#   WB_M25_VAULT01         alias SSH de vault01 (vault01)
#   WB_OPENBAO_URL         adresse du coffre (https://openbao.par1.medisphere.internal:8200)
#   WB_OPENBAO_CHECKS_FILE identifiants AppRole des checks (~/.config/workbook/openbao-checks.env)
#   WB_RACINE_PKI          racine MédiSphère sur adm01

_M25D_MOI="${WB_MOI:-}"
_M25D_VAULT01="${WB_M25_VAULT01:-vault01}"
_M25D_RACINE="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_M25D_DOMAINE=par1.medisphere.internal
_M25D_URL="${WB_OPENBAO_URL:-https://openbao.par1.medisphere.internal:8200}"
_M25D_FICHIER_CHECKS="${WB_OPENBAO_CHECKS_FILE:-$HOME/.config/workbook/openbao-checks.env}"
_M25D_SSO="https://sso.par1.medisphere.internal"
_M25D_EMETTEUR="$_M25D_SSO/realms/medisphere"
# Groupes Keycloak → politiques OpenBao (PLAN §4.12, M25-E06).
declare -A _M25D_GROUPES=(
  [plateforme-admins]=plateforme-admin [plateforme]=plateforme-lecture [support]=plateforme-lecture
  [securite]=securite-audit [mediagenda]=mediagenda-dev
)
_M25D_MODE=""

# _m25d_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m25d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m25d_uri TEXTE — encodage pour une URL.
_m25d_uri() { jq -rn --arg v "$1" '$v | @uri'; }

# _m25d_contient TEXTE REGEX — le texte (non vide) correspond à la regex étendue.
_m25d_contient() { [[ -n "$1" ]] && grep -Eq -- "$2" <<<"$1"; }

# _m25d_aucun REGEX TEXTE — le texte est NON VIDE et aucune de ses lignes ne correspond.
_m25d_aucun() { [[ -n "${2//[[:space:]]/}" ]] && ! grep -Eq -- "$1" <<<"$2"; }

# _m25d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m25d_contenu_main() {
  gitlab_api "projects/$(_m25d_uri "$1")/repository/files/$(_m25d_uri "$2")/raw?ref=main" 2>/dev/null || true
}

# _m25d_arbre_main PROJET DOSSIER — chemins des fichiers du dossier sur main (un par ligne).
_m25d_arbre_main() {
  gitlab_api "projects/$(_m25d_uri "$1")/repository/tree?ref=main&path=$(_m25d_uri "$2")&per_page=100" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
}

# _m25d_pipeline_main PROJET — statut du dernier pipeline de main (vide si aucun).
_m25d_pipeline_main() {
  gitlab_api "projects/$(_m25d_uri "$1")/pipelines?ref=main&per_page=1" 2>/dev/null \
    | jq -r '.[0].status // empty' 2>/dev/null || true
}

# _m25d_ssh HÔTE COMMANDE — sortie d'une commande de consultation sur une VM (vide si échec).
_m25d_ssh() { remote "$1" "$2" 2>/dev/null || true; }

# _m25d_chaine_tls HÔTE PORT [NOM] — la chaîne présentée se vérifie jusqu'à la racine MédiSphère
# pour le nom donné (SNI et vérification du nom).
_m25d_chaine_tls() {
  local hote="$1" port="$2" nom="${3:-$1}" sortie
  sortie="$(timeout "$WB_TIMEOUT" openssl s_client -connect "$hote:$port" -servername "$nom" \
    -CAfile "$_M25D_RACINE" -verify_return_error -verify_hostname "$nom" </dev/null 2>&1)" || return 1
  grep -q 'Verify return code: 0 (ok)' <<<"$sortie"
}

# _m25d_etat — sys/seal-status (sans jeton) : JSON ou vide.
_m25d_etat() { bao_api sys/seal-status 2>/dev/null || true; }

# _m25d_mode — choisit une fois l'accès authentifié : approle, session ou aucun.
_m25d_mode() {
  [[ -n "$_M25D_MODE" ]] && return 0
  if [[ -r "$_M25D_FICHIER_CHECKS" ]]; then
    _M25D_MODE=approle
  elif command -v bao >/dev/null 2>&1 && [[ -n "$(BAO_ADDR="$_M25D_URL" bao print token 2>/dev/null || true)" ]]; then
    _M25D_MODE=session
  else
    _M25D_MODE=aucun
  fi
}

# _m25d_annoncer_acces — une ligne qui dit avec quelle identité les contrôles lisent le coffre.
_m25d_annoncer_acces() {
  _m25d_mode
  case "$_M25D_MODE" in
    approle) ;;
    session) skip "Accès des vérifications au coffre" \
      "openbao-checks.env n'existe qu'à partir de M25-E07 : lectures avec le jeton de ta session bao" ;;
    aucun) _ko "Aucun accès au coffre pour les vérifications : ni openbao-checks.env (M25-E07), ni jeton de session (« bao login »)" ;;
  esac
}

# _m25d_requete METHODE CHEMIN [CORPS] — appel authentifié en LECTURE (GET, LIST, ou POST d'une
# consultation comme lookup-accessor). Sortie : JSON, vide en cas d'erreur.
_m25d_requete() {
  local methode="$1" chemin="$2" corps="${3:-}" jeton=""
  _m25d_mode
  case "$_M25D_MODE" in
    approle)
      # bao_api se connecte (AppRole) et garde le jeton dans _WB_BAO_JETON (check-lib.sh).
      if [[ "$methode" == GET ]]; then bao_api "$chemin" 2>/dev/null || true; return 0; fi
      [[ -n "$_WB_BAO_JETON" ]] || bao_api sys/auth >/dev/null 2>&1 || true
      jeton="$_WB_BAO_JETON" ;;
    session) jeton="$(BAO_ADDR="$_M25D_URL" bao print token 2>/dev/null || true)" ;;
    *) return 0 ;;
  esac
  [[ -n "$jeton" ]] || return 0
  if [[ -n "$corps" ]]; then
    curl -sf --max-time "$WB_TIMEOUT" -K <(printf 'header = "X-Vault-Token: %s"\n' "$jeton") \
      -X "$methode" -H "Content-Type: application/json" --data "$corps" "$_M25D_URL/v1/$chemin" 2>/dev/null || true
  else
    curl -sf --max-time "$WB_TIMEOUT" -K <(printf 'header = "X-Vault-Token: %s"\n' "$jeton") \
      -X "$methode" "$_M25D_URL/v1/$chemin" 2>/dev/null || true
  fi
}

# _m25d_api CHEMIN — lecture authentifiée (JSON ou vide).
_m25d_api() { _m25d_requete GET "$1"; }

# _m25d_liste CHEMIN — liste (clés) d'un chemin, une par ligne.
_m25d_liste() {
  local donnees
  _m25d_mode
  if [[ "$_M25D_MODE" == approle ]]; then
    donnees="$(bao_api "$1?list=true" 2>/dev/null || true)"
  else
    donnees="$(_m25d_requete LIST "$1")"
  fi
  [[ -n "$donnees" ]] || return 0
  jq -r '.data.keys[]?' <<<"$donnees" 2>/dev/null || true
}

# _m25d_politique NOM — texte HCL de la politique ACL (vide si absente).
_m25d_politique() { _m25d_api "sys/policies/acl/$1" | jq -r '.data.policy // empty' 2>/dev/null || true; }

# _m25d_normaliser — texte HCL sans commentaires, lignes vides ni espaces (comparaison code/serveur).
_m25d_normaliser() { sed -e 's/#.*$//' | tr -d '[:space:]'; }

# _m25d_kc_client CLIENT_ID — représentation JSON du client Keycloak (vide si absent ou illisible).
_m25d_kc_client() {
  keycloak_api "clients?clientId=$(_m25d_uri "$1")" 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null || true
}

# _m25d_jetons_racine — nombre de jetons vivants dotés de la politique root (vide si illisible).
_m25d_jetons_racine() {
  local acc n=0 lu=0 info
  while IFS= read -r acc; do
    [[ -n "$acc" ]] || continue
    info="$(_m25d_requete POST auth/token/lookup-accessor "$(jq -nc --arg a "$acc" '{accessor: $a}')")"
    [[ -n "$info" ]] || continue
    lu=$((lu + 1))
    if jq -e '.data.policies | index("root")' <<<"$info" >/dev/null 2>&1; then n=$((n + 1)); fi
  done < <(_m25d_liste auth/token/accessors)
  (( lu > 0 )) && echo "$n"
  return 0
}

# _m25d_regles_texte — lit une politique HCL sur l'entrée standard et écrit une ligne par règle :
#   <chemin> <capacités séparées par des virgules, entre guillemets>
# (commentaires et espaces retirés ; suffisant pour les politiques simples du workbook).
_m25d_regles_texte() {
  sed 's/#.*$//' | tr -d '[:space:]' | sed 's/path"/\npath"/g' \
    | sed -n 's/^path"\([^"]*\)"{capabilities=\[\([^]]*\)\]}.*$/\1 \2/p'
}

# _m25d_regles NOM — règles de la politique NOM du serveur (vide si absente).
_m25d_regles() { _m25d_politique "$1" | _m25d_regles_texte; }
