# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _m25-operationnel-c.sh — fonctions partagées par les checks M25-E17 à M25-E21 (lecture seule).
# Sourcé par check-E17.sh à check-E21.sh (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m25c_ : pas de collision avec les fonctions des autres paliers ni avec _m25-operationnel.sh
# (exercices E10 à E16).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - OpenBao : bao_api (AppRole wb-checks : métadonnées ; M25-E17 ajoute transit/keys en lecture) ;
#   - GitLab : gitlab_api (jeton read_api des checks) ;
#   - cluster : « kube » (compte wb-checks : Applications d'Argo CD, espaces, CRD ; jamais les Secrets) ;
#   - Loki : loki_requete (locataire audit) et l'API des règles du ruler (GET) ;
#   - SSH « admin » vers vault01-03 : commandes de consultation (sudo -n stat, grep, test) ;
#   - Harbor : identité de LECTURE des checks (harbor-checks.env), pour « cosign verify » ;
#   - fichiers de travail de l'apprenant sur adm01 (~/m25/eXX/), lus sans rien modifier.
#
# Variables facultatives de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_M25_COFFRES     nœuds OpenBao interrogés en SSH (« vault01 vault02 vault03 »)
#   WB_M25_TRAVAIL     dossier de travail de l'apprenant (~/m25)

_M25C_P_SECRETS="plateforme/secrets"
_M25C_P_OUTILS="plateforme/outils"
_M25C_P_DOC="plateforme/medisphere"
_M25C_P_GITOPS="plateforme/gitops"
_M25C_P_K8S="plateforme/k8s"
_M25C_P_CI="plateforme/ci-templates"
_M25C_P_OBS="plateforme/observabilite"
_M25C_P_ANSIBLE="plateforme/ansible"
_M25C_DOC_SECRETS="docs/securite/secrets"
_M25C_TRAVAIL="${WB_M25_TRAVAIL:-$HOME/m25}"
read -r -a _M25C_COFFRES <<<"${WB_M25_COFFRES:-vault01 vault02 vault03}"
_M25C_LOKI="${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}"

# _m25c_json JSON FILTRE_JQ [--arg NOM VALEUR]… — 0 si le filtre (jq -e) est vrai sur le JSON.
_m25c_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m25c_uri TEXTE — encodage pour une URL.
_m25c_uri() { jq -rn --arg v "$1" '$v | @uri'; }

# --- GitLab ----------------------------------------------------------------------------------------
# _m25c_contenu PROJET CHEMIN [RÉF=main] — contenu brut d'un fichier (vide si absent).
_m25c_contenu() {
  gitlab_api "projects/$(_m25c_uri "$1")/repository/files/$(_m25c_uri "$2")/raw?ref=$(_m25c_uri "${3:-main}")" 2>/dev/null || true
}

# _m25c_fichier PROJET CHEMIN [RÉF=main] — le fichier existe.
_m25c_fichier() {
  gitlab_api "projects/$(_m25c_uri "$1")/repository/files/$(_m25c_uri "$2")?ref=$(_m25c_uri "${3:-main}")" >/dev/null 2>&1
}

# _m25c_contient PROJET CHEMIN 'regex étendue' — le fichier (sur main) existe et contient la regex.
_m25c_contient() {
  local c
  c="$(_m25c_contenu "$1" "$2")"
  [[ -n "$c" ]] && grep -Eq -- "$3" <<<"$c"
}

# _m25c_ne_contient_pas PROJET CHEMIN 'regex' — le fichier existe et NE contient PAS la regex.
_m25c_ne_contient_pas() {
  local c
  c="$(_m25c_contenu "$1" "$2")"
  [[ -n "$c" ]] && ! grep -Eq -- "$3" <<<"$c"
}

# _m25c_commits_chemin PROJET CHEMIN — nombre de commits de main qui ont touché ce chemin.
_m25c_commits_chemin() {
  gitlab_api "projects/$(_m25c_uri "$1")/repository/commits?ref_name=main&per_page=20&path=$(_m25c_uri "$2")" 2>/dev/null \
    | jq -r 'length' 2>/dev/null || echo 0
}

# _m25c_etiquette PROJET ÉTIQUETTE — l'étiquette Git existe.
_m25c_etiquette() {
  gitlab_api "projects/$(_m25c_uri "$1")/repository/tags/$(_m25c_uri "$2")" >/dev/null 2>&1
}

# _m25c_projet PROJET — le projet existe (visible par le jeton des checks).
_m25c_projet() { gitlab_api "projects/$(_m25c_uri "$1")" >/dev/null 2>&1; }

# --- OpenBao -------------------------------------------------------------------------------------
# _m25c_cle NOM — JSON des métadonnées d'une clé de transit (vide si absente ou illisible).
_m25c_cle() { bao_api "transit/keys/$1" 2>/dev/null | jq -c '.data // empty' 2>/dev/null || true; }

# _m25c_cles — noms des clés de transit, une par ligne.
_m25c_cles() { bao_api "transit/keys?list=true" 2>/dev/null | jq -r '.data.keys[]?' 2>/dev/null || true; }

# _m25c_politique NOM — texte HCL d'une politique ACL (vide si absente).
_m25c_politique() { bao_api "sys/policies/acl/$1" 2>/dev/null | jq -r '.data.policy // empty' 2>/dev/null || true; }

# _m25c_politiques — noms des politiques ACL, une par ligne (vide si l'API ne répond pas).
_m25c_politiques() { bao_api "sys/policies/acl?list=true" 2>/dev/null | jq -r '.data.keys[]?' 2>/dev/null || true; }

# _m25c_montage CHEMIN TYPE — un moteur de ce type est monté à ce chemin (ex. transit/ transit).
_m25c_montage() {
  _m25c_json "$(bao_api sys/mounts 2>/dev/null || true)" \
    '(.data // .) as $m | ($m[$c].type // "") == $t' --arg c "$1" --arg t "$2"
}

# --- VMs du coffre -------------------------------------------------------------------------------
# _m25c_noeud_joignable HÔTE — l'hôte répond en SSH (nœud créé).
_m25c_noeud_joignable() { remote "$1" true </dev/null >/dev/null 2>&1; }

# _m25c_sur HÔTE 'commande' — commande de consultation en root (sudo -n) ; code de retour.
_m25c_sur() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null >/dev/null 2>&1; }

# _m25c_sortie_sur HÔTE 'commande' — idem, sortie standard.
_m25c_sortie_sur() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null 2>/dev/null || true; }

# --- Loki ----------------------------------------------------------------------------------------
# _m25c_loki_nb 'LogQL' LOCATAIRE [DEPUIS=1h] — nombre de lignes renvoyées (0 si erreur).
_m25c_loki_nb() {
  loki_requete "$1" "$2" "${3:-1h}" 2>/dev/null | jq -r '[.data.result[]?.values[]?] | length' 2>/dev/null || echo 0
}

# _m25c_regles_loki LOCATAIRE — règles chargées par le ruler de Loki pour ce locataire (JSON).
_m25c_regles_loki() {
  curl -sf --max-time "$WB_TIMEOUT" -H "X-Scope-OrgID: $1" -H "Accept: application/json" \
    "$_M25C_LOKI/prometheus/api/v1/rules" 2>/dev/null || true
}

# --- Kubernetes ----------------------------------------------------------------------------------
# _m25c_absent RESSOURCE NOM [-n ESPACE] — l'API répond « NotFound » (un refus d'accès n'est PAS
# une absence : sans ce test, un droit manquant ferait passer le contrôle au vert).
_m25c_absent() {
  local sortie
  sortie="$(kube get "$@" -o name 2>&1)" && return 1
  grep -q 'NotFound' <<<"$sortie"
}

# --- Fichiers de travail -------------------------------------------------------------------------
# _m25c_travail CHEMIN_RELATIF — chemin d'un fichier de travail (~/m25/…).
_m25c_travail() { printf '%s/%s\n' "$_M25C_TRAVAIL" "$1"; }
