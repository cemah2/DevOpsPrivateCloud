# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _f3-sante.sh — fonctions PARTAGÉES par toutes les vérifications du final F3 (check-S01 à check-S16)
# et par le contrôle préalable des pannes (corrige/pannes/_f3-commun.sh). Sourcé, jamais lancé seul.
# Préfixe : _f3s_. Lecture seule : « kube » (compte wb-checks), API GitLab en GET (jeton des checks),
# Alertmanager et Prometheus en GET, Prometheus témoin de mon01 en GET, Mailpit en GET (compte des
# checks), « ceph » en LECTURE par SSH + sudo -n sur le nœud _admin. Jamais un Secret, jamais une valeur
# de secret. Toutes les commandes qui peuvent échouer sont protégées (les checks tournent sous
# « set -euo pipefail »).
#
# ============================================================================================
# MODE D'EMPLOI (pour les autres scripts du final)
# ============================================================================================
# Chargement depuis un check :   source "$(dirname "${BASH_SOURCE[0]}")/_f3-sante.sh"
# Chargement depuis une panne :  source "$WB_ROOT/finaux/F3-astreinte/checks/_f3-sante.sh"
#                                (fait par corrige/pannes/_f3-commun.sh)
#
# 1. Contrôle de santé (celui que lance « lab/bin/check F3 1 », exigé avant chaque incident)
#    _f3s_sante                 ajoute une ligne OK/KO (check-lib) par contrôle : nœuds, Argo CD, Ceph,
#                               alertes critiques, sondes du témoin de mon01. Aucun code de retour à lire :
#                               le bilan est fait par « summary ».
#    _f3s_sain                  même contrôle SANS affichage check-lib : code 0 si tout est sain, 1 sinon ;
#                               chaque problème est écrit sur la sortie d'erreur (une ligne « - … »).
#                               C'est ce qu'appelle le contrôle préalable des pannes.
#    Prédicats élémentaires (code 0/1, raison sur stdout si 1), utilisables seuls :
#      _f3s_p_noeuds   _f3s_p_argocd   _f3s_p_ceph   _f3s_p_alertes   _f3s_p_temoin
#
# 2. Trace d'un incident dans plateforme/medisphere (main courante) et dans Mailpit
#    Convention (enonce/00-introduction.md) : main courante docs/exploitation/journal/<AAAA-MM-JJ>.md,
#    une ligne par entrée, de la forme
#        - HH:MM INC-59XX [type] texte
#    type ∈ ouverture | état | action | décision | clôture (« etat », « decision », « cloture » acceptés).
#    Messages d'état par courriel : objet qui contient « INC-59XX » (Mailpit, relais smtp.par1…).
#    _f3s_journal_lignes INC    toutes les lignes de main courante (sur main) qui citent INC
#    _f3s_compter INC TYPE      nombre d'entrées de ce type pour INC
#    _f3s_duree_min INC         minutes entre la première [ouverture] et la dernière [clôture] (vide si
#                               l'une manque ; même jour seulement)
#    _f3s_mailpit_inc INC       nombre de messages Mailpit dont l'objet contient INC
#    _f3s_ticket_inc INC        nombre de tickets (issues) de plateforme/medisphere qui citent INC
#    _f3s_trace INC [N_ETATS=1] [courriel=oui]
#                               ajoute les lignes OK/KO : incident ouvert et clos (main courante, ou
#                               ticket fermé), au moins N_ETATS messages d'état consignés, et (sauf
#                               « non » en 3e argument) au moins un message d'état envoyé par courriel.
#
# 3. Documents de plateforme/medisphere (branche main)
#    _f3s_fichier CHEMIN [RÉF=main]     contenu brut (code ≠ 0 si absent)
#    _f3s_arbre [DOSSIER] [RÉF=main]    chemins des fichiers (récursif)
#    _f3s_doc_present CHEMIN "desc"     ligne OK/KO : le fichier existe sur main
#    _f3s_doc_contient CHEMIN 'regex étendue, insensible à la casse' "desc"
#                                       ligne OK/KO : le fichier contient la regex
#    _f3s_etiquette NOM                 code 0 si l'étiquette existe sur plateforme/medisphere
#
# Variables (lab/lab.env, toutes facultatives) :
#    WB_F3_DEPOT          projet de documentation (plateforme/medisphere)
#    WB_F3_DOC            dossier de l'exploitation (docs/exploitation)
#    WB_F3_APPS_IGNOREES  regex des Applications Argo CD exclues du contrôle de santé (vide : aucune)
#    WB_F3_CEPH_TOLERES   regex des codes de santé Ceph tolérés (vide : aucun ; ex. « RECENT_CRASH »)
#    WB_F3_TEMOIN_URL     Prometheus témoin de mon01 (http://mon01.par1.medisphere.internal:9090)
#    WB_F3_CEPH_ADMIN     nœud _admin de Ceph (défaut : WB_CEPH_ADMIN, sinon ceph01)
# ============================================================================================

_f3s_depot="${WB_F3_DEPOT:-plateforme/medisphere}"
_f3s_doc="${WB_F3_DOC:-docs/exploitation}"
_f3s_temoin="${WB_F3_TEMOIN_URL:-http://mon01.par1.medisphere.internal:9090}"
_f3s_ceph_admin="${WB_F3_CEPH_ADMIN:-${WB_CEPH_ADMIN:-ceph01}}"

_f3s_enc() { jq -rn --arg v "$1" '$v | @uri'; }

# ---------------------------------------------------------------------------------------------
# 1. Santé du lab
# ---------------------------------------------------------------------------------------------

# _f3s_p_noeuds — tous les nœuds Ready, sans pression, planifiables.
_f3s_p_noeuds() {
  local j r
  j="$(kube get nodes -o json 2>/dev/null)" || { echo "API Kubernetes injoignable avec le compte des checks"; return 1; }
  r="$(jq -r '.items[]
      | .metadata.name as $n
      | ([.status.conditions[]? | select(.type == "Ready")][0].status // "Unknown") as $ready
      | ([.status.conditions[]? | select((.type | test("Pressure$|NetworkUnavailable")) and .status == "True") | .type]) as $p
      | select($ready != "True" or ($p | length) > 0 or (.spec.unschedulable // false))
      | "\($n) : Ready=\($ready)\(if ($p | length) > 0 then ", " + ($p | join(",")) else "" end)\(if (.spec.unschedulable // false) then ", non planifiable" else "" end)"' <<<"$j" 2>/dev/null)" || r="lecture des nœuds impossible"
  if [[ "$(jq '.items | length' <<<"$j" 2>/dev/null || echo 0)" -lt 1 ]]; then r="aucun nœud lu"; fi
  [[ -z "$r" ]] && return 0
  printf '%s\n' "$r"
  return 1
}

# _f3s_p_argocd — toutes les Applications Synced et Healthy (sauf WB_F3_APPS_IGNOREES).
_f3s_p_argocd() {
  local j r
  j="$(kube -n argocd get applications.argoproj.io -o json 2>/dev/null)" || { echo "Applications Argo CD illisibles (ClusterRole wb-checks-livraison)"; return 1; }
  r="$(jq -r --arg ign "${WB_F3_APPS_IGNOREES:-}" '.items[]
      | select(($ign == "") or (.metadata.name | test($ign) | not))
      | select((.status.sync.status // "") != "Synced" or (.status.health.status // "") != "Healthy")
      | "\(.metadata.name) : \(.status.sync.status // "?")/\(.status.health.status // "?")"' <<<"$j" 2>/dev/null)" || r="lecture impossible"
  if [[ "$(jq '.items | length' <<<"$j" 2>/dev/null || echo 0)" -lt 1 ]]; then r="aucune Application lue"; fi
  [[ -z "$r" ]] && return 0
  printf '%s\n' "$r"
  return 1
}

# _f3s_ceph_json "ARGS" — sortie JSON d'une commande ceph de lecture sur le nœud _admin.
_f3s_ceph_json() {
  remote "$_f3s_ceph_admin" "if command -v ceph >/dev/null; then sudo -n ceph $1 -f json; else sudo -n cephadm shell -- ceph $1 -f json; fi" 2>/dev/null </dev/null
}

# _f3s_p_ceph — HEALTH_OK, ou seulement des avertissements tolérés (WB_F3_CEPH_TOLERES).
_f3s_p_ceph() {
  local j st r
  j="$(_f3s_ceph_json "health")" || { echo "ceph injoignable sur $_f3s_ceph_admin (SSH + sudo -n)"; return 1; }
  st="$(jq -r '.status // empty' <<<"$j" 2>/dev/null)" || st=""
  [[ "$st" == HEALTH_OK ]] && return 0
  [[ -n "$st" ]] || { echo "état de santé Ceph illisible"; return 1; }
  r="$(jq -r --arg t "${WB_F3_CEPH_TOLERES:-}" '[.checks // {} | keys[] | select(($t == "") or (test($t) | not))] | join(",")' <<<"$j" 2>/dev/null)" || r="?"
  [[ -z "$r" ]] && return 0
  echo "$st ($r)"
  return 1
}

# _f3s_p_alertes — aucune alerte critique active (ni en silence, ni inhibée) dans l'Alertmanager du cluster.
_f3s_p_alertes() {
  local j r
  j="$(am_api "alerts?active=true&silenced=false&inhibited=false" 2>/dev/null)" || { echo "Alertmanager du cluster injoignable"; return 1; }
  r="$(jq -r '[.[] | select(.labels.alertname != "Watchdog")
      | select((.labels.gravite // "") == "critique" or (.labels.severity // "") == "critical")
      | "\(.labels.alertname)\(if .labels.namespace then " (" + .labels.namespace + ")" else "" end)"] | unique | join(", ")' <<<"$j" 2>/dev/null)" || r="lecture impossible"
  [[ -z "$r" ]] && return 0
  echo "$r"
  return 1
}

# _f3s_temoin_requete 'PromQL' — requête instantanée sur le Prometheus témoin de mon01.
_f3s_temoin_requete() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" --data-urlencode "query=$1" \
    "$_f3s_temoin/api/v1/query" 2>/dev/null
}

# _f3s_p_temoin — témoin de mon01 : la sonde Watchdog voit le cluster (dead man's switch), aucune sonde
# en échec, aucune alerte critique du témoin en cours.
_f3s_p_temoin() {
  local j r=""
  j="$(_f3s_temoin_requete 'probe_success{job="watchdog-cluster"}')" || { echo "Prometheus témoin de mon01 injoignable"; return 1; }
  if ! jq -e '(.data.result | length) >= 1 and all(.data.result[]; .value[1] == "1")' <<<"$j" >/dev/null 2>&1; then
    r+="sonde Watchdog du cluster absente ou en échec ; "
  fi
  j="$(_f3s_temoin_requete 'probe_success == 0')" || j='{"data":{"result":[]}}'
  r+="$(jq -r '[.data.result[]? | "\(.metric.job)/\(.metric.instance // "?")"] | if length > 0 then "sondes en échec : " + join(", ") + " ; " else "" end' <<<"$j" 2>/dev/null)" || true
  j="$(_f3s_temoin_requete 'ALERTS{alertstate="firing", gravite="critique"}')" || j='{"data":{"result":[]}}'
  r+="$(jq -r '[.data.result[]? | .metric.alertname // empty] | unique | if length > 0 then "alertes critiques du témoin : " + join(", ") else "" end' <<<"$j" 2>/dev/null)" || true
  [[ -z "$r" ]] && return 0
  echo "${r% ; }"
  return 1
}

_f3s_LIBELLES=(
  "nœuds de k8s-par1 Ready, sans pression, planifiables"
  "Applications Argo CD synchronisées et saines"
  "Ceph ceph-par1 en HEALTH_OK"
  "aucune alerte critique active dans l'Alertmanager du cluster"
  "témoin de mon01 : Watchdog vu, sondes vertes, aucune alerte critique"
)
_f3s_PREDICATS=(_f3s_p_noeuds _f3s_p_argocd _f3s_p_ceph _f3s_p_alertes _f3s_p_temoin)

# _f3s_sante — lignes OK/KO du contrôle de santé (check-lib).
_f3s_sante() {
  local i raison
  for i in "${!_f3s_PREDICATS[@]}"; do
    if raison="$("${_f3s_PREDICATS[i]}")"; then
      _ok "santé : ${_f3s_LIBELLES[i]}"
    else
      _ko "santé : ${_f3s_LIBELLES[i]} — $(tr '\n' ';' <<<"$raison" | sed 's/;$//; s/;/ ; /g')"
    fi
  done
}

# _f3s_sain — même contrôle, sans affichage check-lib ; problèmes sur stderr ; code 0 si sain.
_f3s_sain() {
  local i raison rc=0
  for i in "${!_f3s_PREDICATS[@]}"; do
    if ! raison="$("${_f3s_PREDICATS[i]}")"; then
      printf '  - %s : %s\n' "${_f3s_LIBELLES[i]}" "$(tr '\n' ';' <<<"$raison" | sed 's/;$//; s/;/ ; /g')" >&2
      rc=1
    fi
  done
  return "$rc"
}

# ---------------------------------------------------------------------------------------------
# 3. Documents de plateforme/medisphere
# ---------------------------------------------------------------------------------------------

_f3s_fichier() {
  gitlab_api "projects/$(_f3s_enc "$_f3s_depot")/repository/files/$(_f3s_enc "$1")/raw?ref=$(_f3s_enc "${2:-main}")"
}

_f3s_arbre() {
  local page=1 r ref
  ref="$(_f3s_enc "${2:-main}")"
  while ((page <= 30)); do
    r="$(gitlab_api "projects/$(_f3s_enc "$_f3s_depot")/repository/tree?ref=$ref&recursive=true&per_page=100&page=$page${1:+&path=$(_f3s_enc "$1")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r" 2>/dev/null || return 0
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

_f3s_doc_present() {
  local chemin="$1" desc="$2"
  if _f3s_fichier "$chemin" >/dev/null 2>&1; then _ok "$desc"; else _ko "$desc ($chemin absent de main)"; fi
}

_f3s_doc_contient() {
  local chemin="$1" regex="$2" desc="$3" c
  c="$(_f3s_fichier "$chemin" 2>/dev/null)" || c=""
  if [[ -n "$c" ]] && grep -Eqi -- "$regex" <<<"$c"; then _ok "$desc"; else _ko "$desc"; fi
}

_f3s_etiquette() {
  gitlab_api "projects/$(_f3s_enc "$_f3s_depot")/repository/tags/$(_f3s_enc "$1")" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------------------------
# 2. Trace d'un incident
# ---------------------------------------------------------------------------------------------

# Cache de la main courante pour la durée du check (une lecture de l'API par fichier).
_f3s_JOURNAL_CACHE=""
_f3s_JOURNAL_LU=0
_f3s_journal_tout() {
  local f c
  if ((_f3s_JOURNAL_LU == 0)); then
    _f3s_JOURNAL_LU=1
    while IFS= read -r f; do
      [[ "$f" == *.md ]] || continue
      c="$(_f3s_fichier "$f" 2>/dev/null)" || continue
      _f3s_JOURNAL_CACHE+="$(awk -v f="${f##*/}" '{print f "\t" $0}' <<<"$c")"$'\n'
    done < <(_f3s_arbre "$_f3s_doc/journal")
  fi
  printf '%s' "$_f3s_JOURNAL_CACHE"
}

# _f3s_journal_lignes INC — « fichier<TAB>ligne » des entrées qui citent INC.
_f3s_journal_lignes() {
  _f3s_journal_tout | grep -E $'\t'"[-*] +[0-2]?[0-9][:h][0-5][0-9] +$1 +\[" || true
}

# _f3s_type_regex TYPE — regex qui accepte les graphies du type.
_f3s_type_regex() {
  case "$1" in
    ouverture) echo 'ouverture' ;;
    état | etat) echo '(é|e|É|E)tat' ;;
    action) echo 'action' ;;
    décision | decision) echo 'd(é|e)cision' ;;
    clôture | cloture) echo 'cl(ô|o)ture' ;;
    *) echo "$1" ;;
  esac
}

_f3s_compter() {
  local n
  n="$(_f3s_journal_lignes "$1" | grep -Eic -- "\[$(_f3s_type_regex "$2")\]" || true)"
  echo "${n:-0}"
}

# _f3s_duree_min INC — minutes entre la première ouverture et la dernière clôture.
_f3s_duree_min() {
  local o c ho mo hc mc
  o="$(_f3s_journal_lignes "$1" | grep -Ei '\[ouverture\]' | head -n 1 | sed -E 's/^[^[:space:]]*[[:space:]]+[-*] +([0-2]?[0-9])[:h]([0-5][0-9]).*/\1 \2/')" || o=""
  c="$(_f3s_journal_lignes "$1" | grep -Ei '\[cl(ô|o)ture\]' | tail -n 1 | sed -E 's/^[^[:space:]]*[[:space:]]+[-*] +([0-2]?[0-9])[:h]([0-5][0-9]).*/\1 \2/')" || c=""
  [[ -n "$o" && -n "$c" ]] || return 0
  read -r ho mo <<<"$o"
  read -r hc mc <<<"$c"
  echo $(((10#$hc * 60 + 10#$mc) - (10#$ho * 60 + 10#$mo)))
}

_f3s_mailpit_inc() {
  local j
  j="$(mailpit_api "search?query=$(_f3s_enc "subject:\"$1\"")&limit=50" 2>/dev/null)" || { echo 0; return 0; }
  jq -r '.messages_count // .total // 0' <<<"$j" 2>/dev/null || echo 0
}

_f3s_ticket_inc() {
  local j
  j="$(gitlab_api "projects/$(_f3s_enc "$_f3s_depot")/issues?search=$(_f3s_enc "$1")&per_page=20" 2>/dev/null)" || { echo 0; return 0; }
  jq -r --arg e "${2:-}" '[.[] | select(($e == "") or (.state == $e))] | length' <<<"$j" 2>/dev/null || echo 0
}

# _f3s_trace INC [N_ETATS=1] [courriel=oui]
_f3s_trace() {
  local inc="$1" n="${2:-1}" courriel="${3:-oui}" ouv clo et
  ouv="$(_f3s_compter "$inc" ouverture)"
  clo="$(_f3s_compter "$inc" clôture)"
  if ((ouv >= 1 && clo >= 1)); then
    _ok "$inc ouvert et clos dans la main courante ($_f3s_doc/journal/)"
  elif (($(_f3s_ticket_inc "$inc" closed) >= 1)); then
    _ok "$inc ouvert et clos (ticket fermé de $_f3s_depot)"
  else
    _ko "$inc : ouverture et clôture introuvables dans la main courante de main ($_f3s_doc/journal/, entrées « - HH:MM $inc [ouverture] … » et « [clôture] »)"
  fi
  et="$(_f3s_compter "$inc" état)"
  if ((et >= n)); then
    _ok "$inc : $et message(s) d'état consigné(s) dans la main courante (au moins $n)"
  else
    _ko "$inc : $et message(s) d'état consigné(s) dans la main courante, $n attendu(s) au moins"
  fi
  if [[ "$courriel" != non ]]; then
    if (($(_f3s_mailpit_inc "$inc") >= 1)); then
      _ok "$inc : message(s) d'état envoyé(s) par courriel (objet avec $inc, Mailpit)"
    else
      _ko "$inc : aucun courriel dont l'objet cite $inc dans Mailpit"
    fi
  fi
}
