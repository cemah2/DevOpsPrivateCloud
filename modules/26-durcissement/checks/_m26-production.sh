# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# _m26-production.sh — fonctions partagées par les checks M26-E24 à M26-E34 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : lab/bin/check tourne sous « set -euo pipefail » : toute commande qui peut échouer hors
# des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Variables de lab/lab.env utilisées (toutes facultatives) :
#   WB_PROM_URL, WB_LOKI_URL, WB_GITLAB_URL, WB_GITLAB_TOKEN_FILE (check-lib) ;
#   WB_K8S_KUBECONFIG (kube : compte wb-checks, lecture, jamais les Secrets) ;
#   WB_K8S_ADMIN_KUBECONFIG (défaut ~/.kube/config) : SEULEMENT pour des commandes de CONSULTATION dans
#     l'agent Cilium (cilium-dbg status / endpoint list / endpoint config sans argument) — le compte
#     wb-checks n'a pas « pods/exec » ;
#   WB_M26_S3_URL               s3-01 (défaut https://s3-01.par1.medisphere.internal:8333)
#   WB_M26_S3_CONFORMITE_FILE   identité de LECTURE « conformite-lecture » (défaut ~/.config/workbook/s3-conformite.env)
#   WB_M26_VMS_ECHANTILLON      VMs lues par SSH (défaut « mon01 nbx01 dns02 ipa01 »)
# Accès : « kube » (lecture), API de Prometheus/Thanos Query, de Loki (GET), de GitLab (GET), SSH avec
# « sudo -n » en LECTURE (stat, grep, sha256sum, systemctl is-*/show), aws s3api en LECTURE.

_M26P_DOC=plateforme/medisphere
_M26P_OBS=plateforme/observabilite
_M26P_K8S=plateforme/k8s
_M26P_ANSIBLE=plateforme/ansible
_M26P_POLITIQUES=plateforme/politiques
_M26P_S3_URL="${WB_M26_S3_URL:-https://s3-01.par1.medisphere.internal:8333}"
_M26P_S3_ENV="${WB_M26_S3_CONFORMITE_FILE:-$HOME/.config/workbook/s3-conformite.env}"
read -r -a _M26P_VMS <<<"${WB_M26_VMS_ECHANTILLON:-mon01 nbx01 dns02 ipa01}"
_M26P_CP=(k8s-cp01 k8s-cp02 k8s-cp03)
_M26P_TRAV=(k8s-w01 k8s-w02 k8s-w03)
_M26P_NOEUDS=("${_M26P_CP[@]}" "${_M26P_TRAV[@]}")
declare -A _M26P_IP=([k8s-cp01]=10.10.40.51 [k8s-cp02]=10.10.40.52 [k8s-cp03]=10.10.40.53
                     [k8s-w01]=10.10.40.61 [k8s-w02]=10.10.40.62 [k8s-w03]=10.10.40.63)

# --- API Kubernetes (compte wb-checks) ---------------------------------------------------------

# _m26p_json ARGS… — sortie JSON valide de « kube ARGS -o json », ou « null ».
_m26p_json() {
  local s
  s="$(kube "$@" -o json 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m26p_jq JSON FILTRE [ARGS jq…] — filtre booléen jq sur un document (null → faux).
_m26p_jq() {
  local doc="$1" filtre="$2"
  shift 2
  [[ "$doc" != null && -n "$doc" ]] && jq -e "$@" "$filtre" >/dev/null 2>&1 <<<"$doc"
}

# _m26p_pret ESPACE TYPE NOM [MIN] — l'objet a au moins MIN réplicas prêts (défaut : ceux demandés, ≥ 1).
_m26p_pret() {
  local o
  o="$(_m26p_json -n "$1" get "$2" "$3")"
  if [[ -z "${4:-}" ]]; then
    _m26p_jq "$o" '(.status.readyReplicas // 0) >= ([(.spec.replicas // 1), 1] | max)'
  else
    _m26p_jq "$o" '(.status.readyReplicas // 0) >= ($m | tonumber)' --arg m "$4"
  fi
}

# _m26p_cilium_config CLE — valeur d'une clé de la ConfigMap kube-system/cilium-config (ou vide).
_m26p_cilium_config() {
  kube -n kube-system get configmap cilium-config -o json 2>/dev/null \
    | jq -r --arg k "$1" '.data[$k] // empty' 2>/dev/null || true
}

# _m26p_agent NŒUD COMMANDE… — commande de CONSULTATION dans l'agent Cilium du nœud (kubeconfig
# d'administration : wb-checks n'a pas pods/exec). Sortie sur stdout, code de la commande.
_m26p_agent() {
  local noeud="$1" pod kc="${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}"
  shift
  pod="$(kubectl --kubeconfig "$kc" --request-timeout="${WB_TIMEOUT}s" -n kube-system get pods -l k8s-app=cilium \
    --field-selector "spec.nodeName=$noeud" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" || return 1
  [[ -n "$pod" ]] || return 1
  kubectl --kubeconfig "$kc" --request-timeout=20s -n kube-system exec "$pod" -c cilium-agent -- "$@" 2>/dev/null
}

# _m26p_hote_id NŒUD — identifiant du point de terminaison d'hôte (identité 1) dans l'agent, ou vide.
_m26p_hote_id() {
  _m26p_agent "$1" cilium-dbg endpoint list -o json \
    | jq -r '[.[] | select(.status.identity.id == 1) | .id][0] // empty' 2>/dev/null || true
}

# --- Prometheus / Thanos Query -----------------------------------------------------------------

# _m26p_valeur 'PromQL' — valeur du premier résultat (instantané), ou vide.
_m26p_valeur() {
  prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true
}

# _m26p_nb 'PromQL' — nombre de séries du résultat ; « erreur » si la requête échoue (un contrôle
# « aucune série » ne doit jamais passer parce que Thanos Query est injoignable).
_m26p_nb() {
  local n
  n="$(prom_requete "$1" 2>/dev/null | jq -r 'if .status == "success" then (.data.result | length) else empty end' 2>/dev/null)" || n=""
  printf '%s\n' "${n:-erreur}"
}

# _m26p_absent ARGS… — l'objet n'existe pas (kube get … → NotFound), API joignable (sinon faux).
_m26p_absent() {
  local sortie
  kube get namespace default -o name >/dev/null 2>&1 || return 1
  sortie="$(kube get "$@" -o name 2>&1)" && return 1
  grep -qi 'not ?found' <<<"$sortie"
}

# _m26p_compare VALEUR OP SEUIL — comparaison numérique, faux si VALEUR vide ou NaN.
_m26p_compare() {
  [[ -n "$1" && "$1" != NaN ]] && awk -v v="$1" -v s="$3" "BEGIN { exit !(v $2 s) }"
}

# _m26p_alerte_chargee NOM — une règle d'alerte NOM est chargée par Prometheus (Thanos Query).
_m26p_alerte_chargee() {
  prom_api "rules?type=alert" 2>/dev/null \
    | jq -e --arg n "$1" 'any(.data.groups[].rules[]; .name == $n)' >/dev/null 2>&1
}

# --- Loki (lecture) ----------------------------------------------------------------------------

# _m26p_loki_trouve 'LogQL' LOCATAIRE DEPUIS — au moins une ligne de journal correspond.
_m26p_loki_trouve() {
  loki_requete "$1" "$2" "$3" 2>/dev/null \
    | jq -e '[.data.result[]?.values[]?] | length > 0' >/dev/null 2>&1
}

# _m26p_regles_loki LOCATAIRE — règles du ruler du locataire (YAML), ou vide.
_m26p_regles_loki() { loki_api rules "$1" 2>/dev/null || true; }

# --- GitLab (jeton des checks, lecture) --------------------------------------------------------

# _m26p_fichier PROJET CHEMIN — contenu brut du fichier sur main, ou rien (code ≠ 0).
_m26p_fichier() {
  local p c
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  c="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$p/repository/files/$c/raw?ref=main" 2>/dev/null
}

# _m26p_arbre PROJET DOSSIER — chemins des fichiers du dossier (récursif) sur main.
_m26p_arbre() {
  local p
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&path=$(jq -rn --arg v "$2" '$v | @uri')" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
}

# _m26p_doc_chemin PROJET DOSSIER REGEX_CHEMIN — chemin du premier fichier qui correspond, ou vide.
_m26p_doc_chemin() { _m26p_arbre "$1" "$2" | grep -Ei -- "$3" | head -n 1 || true; }

# _m26p_fichier_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque REGEX
# (grep -E, insensible à la casse).
_m26p_fichier_contient() {
  local projet="$1" chemin="$2" contenu r
  shift 2
  contenu="$(_m26p_fichier "$projet" "$chemin")" || return 1
  [[ -n "$contenu" ]] || return 1
  for r in "$@"; do grep -Eqi -- "$r" <<<"$contenu" || return 1; done
}

# _m26p_doc_present PROJET DOSSIER REGEX_CHEMIN MIN_LIGNES [REGEX_CONTENU…] — un fichier du dossier dont
# le chemin correspond existe sur main, compte au moins MIN_LIGNES lignes non vides et contient chaque
# REGEX_CONTENU.
_m26p_doc_present() {
  local projet="$1" dossier="$2" motif="$3" min="$4" f contenu n r
  shift 4
  f="$(_m26p_doc_chemin "$projet" "$dossier" "$motif")"
  [[ -n "$f" ]] || return 1
  contenu="$(_m26p_fichier "$projet" "$f")" || return 1
  n="$(grep -c '[^[:space:]]' <<<"$contenu" || true)"
  (( n >= min )) || return 1
  for r in "$@"; do grep -Eqi -- "$r" <<<"$contenu" || return 1; done
}

# --- Stockage objet s3-01 (identité conformite-lecture, LECTURE) -------------------------------

_m26p_s3() {
  [[ -r "$_M26P_S3_ENV" ]] || return 1
  (
    set -a
    # shellcheck source=/dev/null
    . "$_M26P_S3_ENV"
    set +a
    export AWS_REQUEST_CHECKSUM_CALCULATION="${AWS_REQUEST_CHECKSUM_CALCULATION:-when_required}"
    exec aws --endpoint-url "$_M26P_S3_URL" --output json "$@" </dev/null
  )
}

# --- VMs (SSH, sudo -n en lecture) -------------------------------------------------------------

# _m26p_famille HÔTE — « Debian », « RedHat » ou vide (lecture de /etc/os-release).
_m26p_famille() {
  remote "$1" '. /etc/os-release; case " $ID $ID_LIKE " in *" debian "*) echo Debian ;; *" rhel "*|*" fedora "*) echo RedHat ;; esac' 2>/dev/null || true
}
