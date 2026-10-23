# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _m25-operationnel.sh — fonctions partagées par les vérifications du palier 2 (M25-E10 à M25-E21).
# Sourcé par ces check-EXX.sh, jamais lancé seul. Deux préfixes, sans collision avec les autres
# paliers : _m25o_ (E10 à E16, première partie du fichier) et _m25c_ (E17 à E21, seconde partie).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) ; toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès, tous en LECTURE :
#   - OpenBao : bao_api (AppRole wb-checks ; politique étendue en M25-E10 à la CONFIGURATION des
#     méthodes, moteurs et rôles, et à la liste des baux — jamais une valeur de secret) ;
#     points publics de la PKI (ca/pem, crl/pem) lus sans jeton ;
#   - cluster : « kube » (compte wb-checks : objets d'ESO et de cert-manager par wb-checks-securite,
#     Applications d'Argo CD par wb-checks-livraison ; jamais les Secrets) ;
#   - GitLab : gitlab_api (jeton read_api des checks) ;
#   - fichiers de travail de l'apprenant sous ~/m25/ (preuves, sans valeur de secret).

_M25O_TRAVAIL="$HOME/m25"
_M25O_BAO="${WB_OPENBAO_URL:-https://openbao.par1.medisphere.internal:8200}"
_M25O_P_SECRETS="plateforme/secrets"
_M25O_P_CI="plateforme/ci-templates"
_M25O_P_ANSIBLE="plateforme/ansible"
_M25O_P_K8S="plateforme/k8s"
_M25O_P_GITOPS="plateforme/gitops"
_M25O_P_DOC="plateforme/medisphere"
_M25O_P_API="mediagenda/api"
_M25O_P_MEDIDOC="medidoc/medidoc"
_M25O_P_DEP_MEDIAGENDA="mediagenda/deploiement"
_M25O_P_DEP_MEDIDOC="medidoc/deploiement"
_M25O_DOC_SECRETS="docs/securite/secrets"
# Motifs de jetons ou de clés qui ne doivent JAMAIS apparaître dans une preuve de l'apprenant.
_M25O_MOTIF_SECRET='(\b[sbr]\.[A-Za-z0-9]{24}\b|glpat-[A-Za-z0-9_-]{20}|glrt-[A-Za-z0-9_-]{20}|-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16})'

# --- Outils génériques ---------------------------------------------------------------------------

# _m25o_json JSON [--arg NOM VALEUR]… FILTRE — 0 si le filtre jq (dernier argument) est vrai.
_m25o_json() {
  local donnees="$1"
  shift
  local filtre="${*: -1}"
  local -a options=("${@:1:$#-1}")
  [[ -n "$donnees" ]] && jq -e "${options[@]}" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m25o_uri TEXTE — encodage pour une URL.
_m25o_uri() { jq -rn --arg v "$1" '$v | @uri'; }

# _m25o_k ARGS… — kubectl en lecture par le compte des checks (sortie vide en cas d'erreur).
_m25o_k() { kube "$@" 2>/dev/null || true; }

# _m25o_local FICHIER 'regex' — un fichier de travail (~/m25/…) existe et contient la regex (insensible
# à la casse), SANS aucun motif de jeton ou de clé privée.
_m25o_local() {
  local f="$_M25O_TRAVAIL/$1"
  [[ -r "$f" ]] && grep -Eqi -- "$2" "$f" && ! grep -Eq -- "$_M25O_MOTIF_SECRET" "$f"
}

# --- OpenBao ---------------------------------------------------------------------------------------

# _m25o_bao CHEMIN — JSON de la réponse (vide en cas d'erreur ou de refus).
_m25o_bao() { bao_api "$1" 2>/dev/null || true; }

# _m25o_auth_type CHEMIN TYPE — la méthode montée en CHEMIN/ est de ce type.
_m25o_auth_type() {
  _m25o_json "$(_m25o_bao sys/auth)" --arg c "$1/" --arg t "$2" '(.data // .)[$c].type == $t'
}

# _m25o_moteur_type CHEMIN TYPE [VERSION] — le moteur monté en CHEMIN/ est de ce type (et version KV).
_m25o_moteur_type() {
  _m25o_json "$(_m25o_bao sys/mounts)" --arg c "$1/" --arg t "$2" --arg v "${3:-}" \
    '(.data // .)[$c] as $m | $m.type == $t and ($v == "" or ($m.options.version // "") == $v)'
}

# _m25o_politique NOM — texte HCL de la politique SANS ses lignes de commentaire (vide si absente ou
# illisible) : les contrôles portent sur les règles, pas sur ce que disent les commentaires.
_m25o_politique() {
  _m25o_bao "sys/policies/acl/$1" | jq -r '.data.policy // empty' 2>/dev/null | grep -Ev '^[[:space:]]*(#|//)' || true
}

# _m25o_politique_existe NOM
_m25o_politique_existe() { [[ -n "$(_m25o_politique "$1")" ]]; }

# _m25o_politique_contient NOM 'regex' — la politique existe et contient la regex étendue.
_m25o_politique_contient() {
  local p
  p="$(_m25o_politique "$1")"
  [[ -n "$p" ]] && grep -Eq -- "$2" <<<"$p"
}

# _m25o_politique_exclut NOM 'regex' — la politique existe et NE contient PAS la regex.
_m25o_politique_exclut() {
  local p
  p="$(_m25o_politique "$1")"
  [[ -n "$p" ]] && ! grep -Eq -- "$2" <<<"$p"
}

# _m25o_kv_version CHEMIN — version courante d'un secret KV v2 du moteur kv/ (0 si absent).
_m25o_kv_version() {
  local v
  v="$(_m25o_bao "kv/metadata/$1" | jq -r '.data.current_version // 0' 2>/dev/null)" || v=0
  printf '%s\n' "${v:-0}"
}

# _m25o_kv_existe CHEMIN — le secret KV existe (au moins une version).
_m25o_kv_existe() { [[ "$(_m25o_kv_version "$1")" -ge 1 ]]; }

# _m25o_baux PREFIXE — nombre de baux actifs sous un préfixe (ex. db-mediagenda/creds/mediagenda-api-recette).
_m25o_baux() {
  local n
  n="$(_m25o_bao "sys/leases/lookup/$1?list=true" | jq -r '.data.keys | length' 2>/dev/null)" || n=0
  printf '%s\n' "${n:-0}"
}

# _m25o_secondes DUREE — durée OpenBao (nombre de secondes, ou « 10m », « 1h ») en secondes.
_m25o_secondes() {
  local d="$1"
  case "$d" in
    '' | null) echo 0 ;;
    *[!0-9smhd]*) echo 0 ;;
    *d) echo $((${d%d} * 86400)) ;;
    *h) echo $((${d%h} * 3600)) ;;
    *m) echo $((${d%m} * 60)) ;;
    *s) echo "${d%s}" ;;
    *) echo "$d" ;;
  esac
}

# --- GitLab ----------------------------------------------------------------------------------------

# _m25o_contenu PROJET CHEMIN [BRANCHE=main] — contenu brut d'un fichier (vide si absent).
_m25o_contenu() {
  gitlab_api "projects/$(_m25o_uri "$1")/repository/files/$(_m25o_uri "$2")/raw?ref=$(_m25o_uri "${3:-main}")" 2>/dev/null || true
}

# _m25o_fichier PROJET CHEMIN [BRANCHE=main] — le fichier existe.
_m25o_fichier() {
  gitlab_api "projects/$(_m25o_uri "$1")/repository/files/$(_m25o_uri "$2")?ref=$(_m25o_uri "${3:-main}")" >/dev/null 2>&1
}

# _m25o_contient PROJET CHEMIN 'regex' [BRANCHE] — le fichier existe et contient la regex.
_m25o_contient() {
  local c
  c="$(_m25o_contenu "$1" "$2" "${4:-main}")"
  [[ -n "$c" ]] && grep -Eq -- "$3" <<<"$c"
}

# _m25o_projet_id PROJET — identifiant numérique du projet (vide si inconnu).
_m25o_projet_id() { gitlab_api "projects/$(_m25o_uri "$1")" 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true; }

# _m25o_pipeline_vert PROJET [BRANCHE=main] — le dernier pipeline de la branche a réussi.
_m25o_pipeline_vert() {
  gitlab_api "projects/$(_m25o_uri "$1")/pipelines?ref=$(_m25o_uri "${2:-main}")&per_page=1" 2>/dev/null |
    jq -e '.[0].status == "success"' >/dev/null 2>&1
}

# _m25o_variables projects|groups CHEMIN — noms des variables de CI (une par ligne). Code 2 si
# l'API refuse (le jeton des checks n'a pas le rôle Maintainer) : le contrôle est alors ignoré.
_m25o_variables() {
  local r
  r="$(gitlab_api "$1/$(_m25o_uri "$2")/variables?per_page=100" 2>/dev/null)" || return 2
  jq -r '.[].key' <<<"$r" 2>/dev/null
}

# _m25o_doc_contient CHEMIN 'regex' — un document de plateforme/medisphere (main) contient la regex.
_m25o_doc_contient() { _m25o_contient "$_M25O_P_DOC" "$1" "$2"; }

# --- Kubernetes -----------------------------------------------------------------------------------

# _m25o_pret JSON — l'objet a une condition Ready à True.
_m25o_pret() { _m25o_json "$1" '[.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0'; }

# _m25o_objet_pret RESSOURCE NOM [ESPACE] — l'objet existe et est Ready.
_m25o_objet_pret() {
  local j
  if [[ -n "${3:-}" ]]; then j="$(_m25o_k get "$1" "$2" -n "$3" -o json)"; else j="$(_m25o_k get "$1" "$2" -o json)"; fi
  _m25o_pret "$j"
}

# _m25o_es_pret ESPACE NOM — l'ExternalSecret existe et est Ready (dernière synchronisation réussie).
_m25o_es_pret() { _m25o_objet_pret externalsecrets.external-secrets.io "$2" "$1"; }

# _m25o_app_ok NOM — Application Argo CD Synced et Healthy.
_m25o_app_ok() {
  _m25o_json "$(_m25o_k get applications.argoproj.io "$1" -n argocd -o json)" \
    '.status.sync.status == "Synced" and .status.health.status == "Healthy"'
}

# _m25o_peut VERBE RESSOURCE [ESPACE] — le compte des checks a ce droit (kubectl auth can-i).
_m25o_peut() {
  local r
  if [[ -n "${3:-}" ]]; then r="$(_m25o_k auth can-i "$1" "$2" -n "$3")"; else r="$(_m25o_k auth can-i "$1" "$2")"; fi
  [[ "$r" == yes ]]
}

# _m25o_http URL — code HTTP d'une URL (racine MédiSphère du système ; vide si aucune réponse).
_m25o_http() { curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "$1" 2>/dev/null || true; }

# =====================================================================================================
# Seconde partie (préfixe _m25c_) : transit, SOPS, Sealed Secrets et CSI, Cosign, audit (E17 à E21).
# Accès supplémentaires, en lecture : Loki (locataire audit) et l'API des règles du ruler (GET) ;
# Harbor par l'identité de LECTURE des checks (harbor-checks.env), pour « cosign verify » ; SSH
# « admin » vers vault01-03 (sudo -n stat, grep, test). Variables facultatives de lab/lab.env :
# WB_M25_NOEUDS (« vault01 vault02 vault03 »), WB_M25_TRAVAIL (~/m25).
# =====================================================================================================

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
read -r -a _M25C_COFFRES <<<"${WB_M25_NOEUDS:-vault01 vault02 vault03}"
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
