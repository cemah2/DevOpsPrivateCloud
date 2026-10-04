# shellcheck shell=bash
# =============================================================================
# ms-commun.sh — bibliothèque commune des outils Bash de plateforme/outils
# (M02-E10)
#
# Chargement, en tête d'un script de bin/, APRÈS le mode strict :
#   set -euo pipefail
#   # shellcheck source=../lib/ms-commun.sh
#   source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/ms-commun.sh"
#
# API (stable : toute modification incompatible = version majeure du projet)
#   log_info MSG...          journal sur stderr : horodatage ISO 8601, script, PID, niveau
#   log_warn MSG...
#   log_err  MSG...
#   die MESSAGE [CODE]       journalise l'erreur et quitte (code 1 par défaut)
#   require_cmd CMD...       quitte (code 1) si une commande manque, en les listant toutes
#   confirm QUESTION         0 si l'opérateur répond oui ; sans terminal : refus, sauf MS_YES=1
#   retry N DÉLAI CMD...     relance CMD au plus N fois, délai doublé à chaque échec
#   pve_api MÉTHODE /CHEMIN [clé=valeur...]
#                            appel à l'API Proxmox ; affiche le champ .data en JSON compact ;
#                            code 1 (et message clair) sur erreur réseau, TLS ou HTTP
#   pve_wait_task UPID [DÉLAI_MAX]
#                            attend la fin d'une tâche Proxmox et vérifie son résultat
#
# Codes retour communs à tous les outils : 0 succès, 1 erreur, 2 usage, 3 refus d'un garde-fou.
#
# Variables d'environnement reconnues
#   MS_PVE_ENV  fichier d'accès à l'API (défaut ~/.config/workbook/pve-api.env, format M00-E17)
#   PVE_API_URL, PVE_NODE, PVE_TOKEN_ID, PVE_TOKEN_SECRET, PVE_CACERT
#                    si elles sont déjà définies, elles l'emportent sur le fichier (CI)
#   MS_PVE_TIMEOUT   délai maximal d'un appel HTTP, en secondes (défaut 30)
#   MS_PVE_POLL      intervalle de scrutation des tâches, en secondes (défaut 2)
#   MS_YES=1         répond « oui » à confirm (usage non interactif assumé)
#
# La bibliothèque ne change PAS les options du shell (set -e…) : c'est le rôle du script.
# =============================================================================

# Exécutée au lieu d'être chargée : on refuse (elle ne ferait rien d'utile).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "ms-commun.sh est une bibliothèque : charge-la avec « source », ne l'exécute pas." >&2
  exit 2
fi

# Chargement unique (un script et ses fonctions peuvent la sourcer plusieurs fois).
if [[ -n "${_MS_COMMUN_CHARGEE:-}" ]]; then
  return 0
fi
_MS_COMMUN_CHARGEE=1

# Nom du programme dans les journaux (surchargeable avant le chargement).
MS_PROG="${MS_PROG:-$(basename -- "$0")}"

# -----------------------------------------------------------------------------
# Journalisation : toujours sur stderr. stdout est réservé aux données (JSON,
# listes) pour qu'un appelant puisse les rediriger ou les passer à jq.
# -----------------------------------------------------------------------------
_ms_log() {
  local niveau="$1"
  shift
  printf '%s %s[%d] %s %s\n' "$(date -Iseconds)" "$MS_PROG" "$$" "$niveau" "$*" >&2
}
log_info() { _ms_log INFO "$@"; }
log_warn() { _ms_log AVERT "$@"; }
log_err() { _ms_log ERREUR "$@"; }

# die MESSAGE [CODE] — attention : appelée dans une substitution $(…), elle ne
# quitte que le sous-shell. L'appelant doit tester le code : x="$(f)" || exit $?
die() {
  local code="${2:-1}"
  log_err "$1"
  exit "$code"
}

# require_cmd CMD... — vérifie toutes les commandes avant de quitter, pour
# donner la liste complète en une fois.
require_cmd() {
  local c manquants=()
  for c in "$@"; do
    if ! command -v -- "$c" >/dev/null 2>&1; then
      manquants+=("$c")
    fi
  done
  if ((${#manquants[@]} > 0)); then
    die "commande(s) introuvable(s) : ${manquants[*]}" 1
  fi
}

# confirm QUESTION — lit la réponse sur le terminal. Sans terminal (cron, CI,
# tube), refuse : une action destructrice ne s'improvise pas sans opérateur.
confirm() {
  local question="$1" reponse=""
  if [[ "${MS_YES:-0}" == 1 ]]; then
    log_info "confirmation automatique (MS_YES=1) : $question"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    log_err "confirmation impossible sans terminal (« $question ») : relance en interactif, ou avec MS_YES=1 si c'est voulu"
    return 1
  fi
  read -r -p "$question [o/N] " reponse || return 1
  [[ "$reponse" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]]
}

# retry N DÉLAI CMD... — N tentatives au plus, délai initial DÉLAI secondes,
# doublé après chaque échec. Renvoie le code du dernier échec.
# Seul le nom de la commande est journalisé (ses arguments peuvent être sensibles).
# Attention : CMD est exécutée dans un contexte où « set -e » est suspendu ; une
# fonction passée à retry doit donc signaler ses échecs par son code de retour.
retry() {
  if (($# < 3)) || [[ ! "$1" =~ ^[1-9][0-9]*$ || ! "$2" =~ ^[0-9]+$ ]]; then
    die "retry : usage retry TENTATIVES DÉLAI COMMANDE [ARG...]" 2
  fi
  local max="$1" delai="$2" n=1 rc=0
  shift 2
  while :; do
    "$@" && return 0
    rc=$?
    if ((n >= max)); then
      log_err "« $1 » en échec après $n tentative(s) (code $rc)"
      return "$rc"
    fi
    log_warn "« $1 » en échec (code $rc), tentative $n/$max ; nouvel essai dans ${delai}s"
    sleep "$delai"
    n=$((n + 1))
    delai=$((delai * 2))
  done
}

# -----------------------------------------------------------------------------
# API Proxmox
# -----------------------------------------------------------------------------
readonly _MS_PVE_VARS=(PVE_API_URL PVE_NODE PVE_TOKEN_ID PVE_TOKEN_SECRET PVE_CACERT)

# _ms_pve_charger — lit le fichier d'accès (une fois par shell). Les variables
# PVE_* déjà présentes dans l'environnement l'emportent sur le fichier.
_ms_pve_charger() {
  if [[ -n "${_MS_PVE_CHARGE:-}" ]]; then
    return 0
  fi
  local fichier="${MS_PVE_ENV:-$HOME/.config/workbook/pve-api.env}" v mode
  local -A avant=()
  for v in "${_MS_PVE_VARS[@]}"; do
    if [[ -n "${!v:-}" ]]; then
      avant[$v]="${!v}"
    fi
  done
  if [[ -f "$fichier" ]]; then
    mode="$(stat -c '%a' -- "$fichier")"
    if (((8#$mode & 8#077) != 0)); then
      log_err "$fichier est accessible à d'autres que son propriétaire (mode $mode) : il contient un secret, corrige ses droits"
      return 1
    fi
    # Fichier de confiance (le nôtre, mode 600) : on peut le sourcer.
    # shellcheck source=/dev/null
    source "$fichier" || {
      log_err "lecture impossible de $fichier"
      return 1
    }
  elif ((${#avant[@]} == 0)); then
    log_err "fichier d'accès à l'API introuvable : $fichier (et aucune variable PVE_* définie)"
    return 1
  fi
  for v in "${!avant[@]}"; do
    printf -v "$v" '%s' "${avant[$v]}"
  done
  for v in PVE_API_URL PVE_TOKEN_ID PVE_TOKEN_SECRET; do
    if [[ -z "${!v:-}" ]]; then
      log_err "variable $v absente (fichier $fichier ou environnement)"
      return 1
    fi
  done
  if [[ "$PVE_API_URL" != https://* ]]; then
    log_err "PVE_API_URL doit commencer par https:// (valeur : $PVE_API_URL)"
    return 1
  fi
  if [[ -n "${PVE_CACERT:-}" && ! -r "$PVE_CACERT" ]]; then
    log_err "certificat d'autorité illisible : $PVE_CACERT"
    return 1
  fi
  _MS_PVE_CHARGE=1
}

# pve_api MÉTHODE /CHEMIN [clé=valeur...]
#   GET et DELETE : paramètres dans l'URL ; POST et PUT : corps de formulaire.
#   Le secret passe par un descripteur (-H @<(…)) : jamais dans « ps » ni dans « set -x ».
#   Proxmox place le motif d'une erreur dans la ligne de statut HTTP
#   (« 403 Permission check failed (/vms/100, VM.Audit) ») : on la restitue.
pve_api() {
  if (($# < 2)); then
    log_err "pve_api : usage pve_api MÉTHODE /chemin [clé=valeur...]"
    return 2
  fi
  local methode="$1" chemin="$2"
  shift 2
  _ms_pve_charger || return 1

  local -a args=(--silent --show-error --include --suppress-connect-headers
    --max-time "${MS_PVE_TIMEOUT:-30}" -X "$methode")
  if [[ -n "${PVE_CACERT:-}" ]]; then
    args+=(--cacert "$PVE_CACERT")
  fi
  case "$methode" in
    GET | DELETE) args+=(--get) ;;
    POST | PUT) ;;
    *)
      log_err "pve_api : méthode HTTP non prise en charge : $methode"
      return 2
      ;;
  esac
  local kv
  for kv in "$@"; do
    args+=(--data-urlencode "$kv")
  done

  local reponse rc=0
  reponse="$(curl "${args[@]}" \
    -H @<(printf 'Authorization: PVEAPIToken=%s=%s\n' "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET") \
    "${PVE_API_URL%/}${chemin}")" || rc=$?
  if ((rc != 0)); then
    log_err "$methode $chemin : échec réseau ou TLS (curl code $rc)"
    return 1
  fi

  # Réponse brute : en-têtes, ligne vide (CRLF CRLF), corps JSON.
  local statut="${reponse%%$'\r'*}" corps="${reponse#*$'\r\n\r\n'}"
  local _version code motif
  read -r _version code motif <<<"$statut"
  if [[ ! "$code" =~ ^2[0-9][0-9]$ ]]; then
    local details
    details="$(jq -c '.errors // empty' <<<"$corps" 2>/dev/null || true)"
    log_err "$methode $chemin → HTTP ${code:-?} ${motif:-}${details:+ $details}"
    return 1
  fi
  jq -c '.data' <<<"$corps"
}

# pve_wait_task UPID [DÉLAI_MAX] — attend la fin d'une tâche asynchrone
# (clone, snapshot, destruction…). 0 si exitstatus vaut OK (ou WARNINGS),
# 1 si la tâche échoue ou dépasse DÉLAI_MAX secondes (défaut 600).
# Le nœud qui exécute la tâche est le 2e champ de l'UPID.
pve_wait_task() {
  local upid="${1:-}" max="${2:-600}" debut=$SECONDS noeud upid_url etat statut
  if [[ "$upid" != UPID:* ]]; then
    log_err "pve_wait_task : UPID invalide : « $upid »"
    return 1
  fi
  noeud="$(cut -d: -f2 <<<"$upid")"
  upid_url="$(jq -rn --arg u "$upid" '$u | @uri')"
  while :; do
    etat="$(pve_api GET "/nodes/$noeud/tasks/$upid_url/status")" || return 1
    if [[ "$(jq -r '.status' <<<"$etat")" == stopped ]]; then
      statut="$(jq -r '.exitstatus // "inconnu"' <<<"$etat")"
      case "$statut" in
        OK) return 0 ;;
        WARNINGS*)
          log_warn "tâche terminée avec avertissements ($statut) : $upid"
          return 0
          ;;
        *)
          log_err "tâche en échec ($statut) : $upid"
          return 1
          ;;
      esac
    fi
    if ((SECONDS - debut >= max)); then
      log_err "tâche toujours en cours après ${max}s : $upid"
      return 1
    fi
    sleep "${MS_PVE_POLL:-2}"
  done
}
