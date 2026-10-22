# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq, requêtes LogQL/PromQL et commandes distantes entre apostrophes
# _m25-production.sh — fonctions partagées par les checks M25-E24 à M25-E34 (palier 3). Sourcé par les
# check-EXX.sh concernés, jamais lancé seul. Préfixe _m25p_ (évite les collisions entre paliers).
# LECTURE SEULE : API d'OpenBao (sys/health, sys/seal-status, sys/leader sans jeton ; le reste par
# l'AppRole wb-checks, métadonnées seulement), commandes de consultation en SSH (admin, sudo -n),
# Prometheus du cluster et témoin de mon01, Loki (locataire audit), GitLab (jeton de lecture),
# Grafana (Viewer), s3-01 (identités en LECTURE : list, get), Proxmox (qm status).
# Rappel : lab/bin/check tourne sous « set -euo pipefail » : toute commande qui peut échouer hors
# des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Variables de lab/lab.env (toutes facultatives) :
#   WB_M25_NOEUDS               nœuds de la grappe (défaut « vault01 vault02 vault03 »)
#   WB_M25_KMS                  OpenBao de descellement (défaut kms01)
#   WB_M25_S3_INSTANTANES_FILE  identité S3 openbao-instantanes (défaut ~/.config/workbook/s3-openbao-instantanes.env :
#                               AWS_ACCESS_KEY_ID=…, AWS_SECRET_ACCESS_KEY=…)
#   WB_M25_S3_ADMIN_FILE        identité d'administration S3, lecture du cycle de vie (défaut ~/.config/workbook/s3-admin.env)
#   WB_M25_S3_URL               point d'accès de s3-01 (défaut https://s3-01.par1.medisphere.internal:8333)
#   WB_M21_TEMOIN_URL           Prometheus témoin de mon01 (défaut http://mon01.par1.medisphere.internal:9090)
#   WB_M25_DOMAINE, WB_M25_PORT domaine et port d'API des nœuds (défauts par1.medisphere.internal, 8200 ;
#                               ne servent qu'à rejouer les checks sur un banc d'essai)

_M25P_DOMAINE="${WB_M25_DOMAINE:-par1.medisphere.internal}"
_M25P_PORT="${WB_M25_PORT:-8200}"
read -r -a _M25P_NOEUDS <<<"${WB_M25_NOEUDS:-vault01 vault02 vault03}"
_M25P_KMS="${WB_M25_KMS:-kms01}"
_M25P_VIP=10.10.20.200
_M25P_SERVICE="openbao.$_M25P_DOMAINE"
_M25P_S3_ENV="${WB_M25_S3_INSTANTANES_FILE:-$HOME/.config/workbook/s3-openbao-instantanes.env}"
_M25P_S3_ADMIN="${WB_M25_S3_ADMIN_FILE:-$HOME/.config/workbook/s3-admin.env}"
_M25P_S3_URL="${WB_M25_S3_URL:-https://s3-01.par1.medisphere.internal:8333}"
_M25P_TEMOIN="${WB_M21_TEMOIN_URL:-http://mon01.par1.medisphere.internal:9090}"
_M25P_DOC=plateforme/medisphere
_M25P_ANSIBLE=plateforme/ansible
_M25P_OBS=plateforme/observabilite
_M25P_SECRETS=plateforme/secrets
_M25P_RB=docs/securite/secrets/runbooks

# --- OpenBao, sans jeton ------------------------------------------------------------------------------

# _m25p_url HÔTE — URL de l'API d'un nœud (nom court).
_m25p_url() { printf 'https://%s.%s:%s' "$1" "$_M25P_DOMAINE" "$_M25P_PORT"; }

# _m25p_code HÔTE — code HTTP de /v1/sys/health du nœud (000 si aucune réponse).
_m25p_code() {
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "$(_m25p_url "$1")/v1/sys/health" 2>/dev/null || true
}

# _m25p_sante HÔTE — corps JSON de /v1/sys/health quel que soit l'état (codes forcés à 200), ou null.
_m25p_sante() {
  local s
  s="$(curl -s --max-time "$WB_TIMEOUT" \
    "$(_m25p_url "$1")/v1/sys/health?standbycode=200&sealedcode=200&uninitcode=200&perfstandbyok=true" 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m25p_scellement HÔTE — corps de /v1/sys/seal-status, ou null.
_m25p_scellement() {
  local s
  s="$(curl -s --max-time "$WB_TIMEOUT" "$(_m25p_url "$1")/v1/sys/seal-status" 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m25p_jq JSON FILTRE [ARGS jq…] — filtre booléen jq (null → faux).
_m25p_jq() {
  local doc="$1" filtre="$2"
  shift 2
  [[ -n "$doc" && "$doc" != null ]] && jq -e "$@" "$filtre" >/dev/null 2>&1 <<<"$doc"
}

# _m25p_actifs — noms des nœuds de la grappe qui répondent 200 à sys/health (un par ligne).
_m25p_actifs() {
  local n
  for n in "${_M25P_NOEUDS[@]}"; do
    [[ "$(_m25p_code "$n")" == 200 ]] && printf '%s\n' "$n"
  done
  return 0
}

# --- OpenBao, AppRole wb-checks (métadonnées) -------------------------------------------------------

# _m25p_connexion — obtient le jeton wb-checks dans le shell COURANT (bao_api le garde dans
#   _WB_BAO_JETON ; appelé dans une substitution de commande, il le perdrait et se reconnecterait à
#   chaque appel — et le quota de débit de la connexion AppRole (M25-E28) finirait par répondre 429).
#   À appeler en tête des checks qui lisent OpenBao avec un jeton.
_m25p_connexion() { [[ -n "$_WB_BAO_JETON" ]] || bao_api sys/mounts >/dev/null 2>&1 || true; }

# _m25p_bao CHEMIN — réponse JSON de bao_api, ou null.
_m25p_bao() {
  local s
  s="$(bao_api "$1" 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m25p_kv_meta CHEMIN — {"version": N, "cree": époque de la version courante, "meta": custom_metadata}
#   d'un secret du montage kv, ou null. L'âge est celui de la VERSION (updated_time bouge aussi quand
#   seules les métadonnées changent).
_m25p_kv_meta() {
  _m25p_bao "kv/metadata/$1" | jq -c '
    if . == null then null else .data
      | {version: .current_version,
         cree: (.versions[(.current_version | tostring)].created_time // "" | sub("\\.[0-9]+"; "")
                | if . == "" then 0 else fromdateiso8601 end),
         meta: (.custom_metadata // {})} end' 2>/dev/null || echo null
}

# _m25p_kv_feuilles PRÉFIXE/ — chemins des secrets sous le préfixe (récursif, 3 niveaux), un par ligne.
_m25p_kv_feuilles() {
  local p="$1" k profondeur="${2:-0}"
  ((profondeur <= 3)) || return 0
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    if [[ "$k" == */ ]]; then _m25p_kv_feuilles "$p$k" $((profondeur + 1)); else printf '%s%s\n' "$p" "$k"; fi
  done < <(_m25p_bao "kv/metadata/$p?list=true" | jq -r '.data.keys[]? // empty' 2>/dev/null || true)
}

# --- SSH (consultation) ---------------------------------------------------------------------------------

# _m25p_ssh HÔTE 'commande' — commande de consultation en root (sudo -n), code de retour.
_m25p_ssh() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null >/dev/null 2>&1; }
# _m25p_ssh_sortie HÔTE 'commande' — idem, sortie standard.
_m25p_ssh_sortie() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null 2>/dev/null || true; }

# _m25p_vm_absente VMID — la VM n'existe plus sur pve01.
_m25p_vm_absente() { ! remote "$WB_PVE_HOST" "qm status $1" </dev/null >/dev/null 2>&1; }

# --- GitLab (jeton de lecture des checks) ------------------------------------------------------------------

_m25p_fichier() {
  local p c
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  c="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$p/repository/files/$c/raw?ref=main" 2>/dev/null
}

_m25p_arbre() {
  local p
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&path=$(jq -rn --arg v "$2" '$v | @uri')" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
}

# _m25p_doc_chemin PROJET DOSSIER REGEX — premier fichier du dossier dont le chemin correspond.
_m25p_doc_chemin() { _m25p_arbre "$1" "$2" | grep -Ei -- "$3" | head -n 1 || true; }

# _m25p_doc PROJET DOSSIER REGEX_CHEMIN MIN_LIGNES REGEX… — un fichier correspondant existe sur main,
#   compte au moins MIN_LIGNES lignes non vides et contient chaque REGEX (insensible à la casse).
_m25p_doc() {
  local projet="$1" dossier="$2" motif="$3" min="$4" f contenu r
  shift 4
  f="$(_m25p_doc_chemin "$projet" "$dossier" "$motif")"
  [[ -n "$f" ]] || return 1
  contenu="$(_m25p_fichier "$projet" "$f")" || return 1
  (($(grep -c '[^[:space:]]' <<<"$contenu") >= min)) || return 1
  for r in "$@"; do grep -Eqi -- "$r" <<<"$contenu" || return 1; done
}

# _m25p_fichier_sans PROJET CHEMIN REGEX — le fichier existe sur main et ne contient PAS la regex.
_m25p_fichier_sans() {
  local c
  c="$(_m25p_fichier "$1" "$2")" || return 1
  [[ -n "$c" ]] && ! grep -Eq -- "$3" <<<"$c"
}

# --- Loki (locataire audit) ---------------------------------------------------------------------------------

# _m25p_loki_nb 'LogQL' DEPUIS — nombre de lignes renvoyées (au plus 100), vide si Loki ne répond pas.
_m25p_loki_nb() {
  loki_requete "$1" audit "$2" 2>/dev/null | jq -r '[.data.result[]?.values[]?] | length' 2>/dev/null || true
}

# --- Prometheus -----------------------------------------------------------------------------------------------

_m25p_valeur() { prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true; }

_m25p_temoin_valeur() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" --data-urlencode "query=$1" \
    "$_M25P_TEMOIN/api/v1/query" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true
}

# _m25p_compare VALEUR OP SEUIL — comparaison numérique (awk), faux si VALEUR vide ou NaN.
_m25p_compare() {
  [[ -n "$1" && "$1" != NaN ]] && awk -v v="$1" -v s="$3" "BEGIN { exit !(v $2 s) }"
}

# --- s3-01 (LECTURE) ------------------------------------------------------------------------------------------

# _m25p_s3 FICHIER_ENV ARGS… — aws avec une identité lue dans un fichier (jamais sur la ligne de commande).
_m25p_s3() {
  local env="$1"
  shift
  [[ -r "$env" ]] || return 1
  (
    set -a
    # shellcheck source=/dev/null
    . "$env"
    set +a
    export AWS_REQUEST_CHECKSUM_CALCULATION="${AWS_REQUEST_CHECKSUM_CALCULATION:-when_required}"
    exec aws --endpoint-url "$_M25P_S3_URL" --output json "$@" </dev/null
  )
}

# _m25p_marqueur_absent EXX — aucune panne M25-EXX marquée active sur ce poste.
_m25p_marqueur_absent() { [[ ! -e "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives/M25-$1" ]]; }
