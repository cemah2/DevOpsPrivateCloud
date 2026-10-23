# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _f4-montees.sh — fonctions partagées par les vérifications des phases « Gouverner » et « Montées » du
# final F4 (check-S01 à check-S08), et réutilisables par les phases suivantes (S09 à S14). Sourcé, jamais
# lancé seul. Préfixe _f4m_ (évite les collisions si un check charge plusieurs fichiers de fonctions).
#
# Lecture seule : GitLab en GET (jeton des checks), « kube » (compte wb-checks, jamais les Secrets),
# Prometheus du cluster (Thanos Query, WB_PROM_URL) et Prometheus témoin de mon01 en GET, Grafana en GET.
#
# Variables de lab/lab.env (toutes facultatives, défauts adaptés au lab) :
#   WB_F4_DOC                dossier de la documentation des changements (défaut docs/changements)
#   WB_F4_PROJET_DOC         projet de la documentation (défaut plateforme/medisphere)
#   WB_F4_PROJET_RESILIENCE  projet de la sonde de charge (défaut plateforme/resilience)
#   WB_F4_PROJET_OBSERVABILITE  projet des règles et tableaux (défaut plateforme/observabilite)
#   WB_F4_PROM_TEMOIN_URL    Prometheus témoin de mon01 (défaut http://mon01.par1.medisphere.internal:9090)
#   WB_F4_TOLERANCE_S        écart admis entre l'interruption déclarée dans une fiche et celle
#                            recalculée par le check (défaut 30 s)
#   WB_F4_COUVERTURE_MIN     part minimale de la fenêtre couverte par la mesure (défaut 0.9)
#   WB_F4_TABLEAU_UID        UID du tableau « changement en cours » (défaut f4-changement-en-cours)
# et celles de lab/lib/check-lib.sh (WB_GITLAB_*, WB_PROM_URL, WB_GRAFANA_*, WB_K8S_KUBECONFIG, WB_TIMEOUT).
#
# ---------------------------------------------------------------------------------------------------
# LA MESURE D'INTERRUPTION (contrat partagé avec les phases 3 et 4, S09 à S14)
# ---------------------------------------------------------------------------------------------------
# La sonde de continuité (F4-S02) publie deux séries enregistrées :
#   - sur le Prometheus TÉMOIN de mon01 (rôle supervision_temoin, règles continuite.yml) :
#       continuite:sonde_en_erreur        1 par sonde blackbox en échec (groupes « continuite-* »), sinon 0
#       continuite:sondes_en_erreur:max   1 si AU MOINS une sonde de continuité est en échec, sinon 0
#     (étiquette job="blackbox" conservée : ces séries sont aussi fédérées vers le cluster) ;
#   - sur le Prometheus du CLUSTER (plateforme/observabilite, PrometheusRule « continuite ») :
#       continuite:en_erreur              1 si une sonde échoue OU si la charge k6 de la sonde voit des
#                                         erreurs OU si MédiAgenda prod renvoie des 5xx, sinon 0.
# Les deux règles sont évaluées toutes les 15 s (_F4M_PAS). « Secondes d'erreur cumulées » entre DÉBUT
# et FIN = moyenne de la série 0/1 sur la fenêtre × durée de la fenêtre, évaluée à FIN (côté cluster :
# Thanos Query interrogé avec dedup=false, max des deux réplicas, voir _f4m_prom).
# Source « cluster » (défaut) = continuite:en_erreur via Thanos Query ; source « temoin » =
# continuite:sondes_en_erreur:max sur mon01 (seule source disponible quand k8s-par1 est arrêté, F4-S08),
# ou, si la fiche restreint les groupes de sondes (clé mesure-groupes, expression régulière sur
# l'étiquette « groupe »), max(continuite:sonde_en_erreur{groupe=~"<mesure-groupes>"}) : en F4-S08, le
# cluster est arrêté par contrainte de mémoire du lab, seules comptent les sondes continuite-openstack.
#
# Chaque fiche CHG porte, dans son en-tête YAML (entre deux lignes « --- »), les clés :
#   mesure-source: cluster|temoin     mesure-debut: <ISO 8601>     mesure-fin: <ISO 8601>
#   mesure-objectif-s: <entier>       mesure-interruption-s: <nombre, valeur relevée par l'apprenant>
#   mesure-groupes: <regex>           (facultatif, source temoin seulement : groupes de sondes retenus)
# Fonctions à utiliser depuis un check :
#   _f4m_interruption DEBUT FIN [SOURCE] [GROUPES] → affiche les secondes d'erreur cumulées (entier), code ≠ 0
#                                            si la mesure n'existe pas sur la fenêtre
#   _f4m_couverture DEBUT FIN [SOURCE] [GROUPES] → affiche la part (0 à 1) de la fenêtre où la mesure existait
#   _f4m_mesurer CHG-34XX                  → lit la fiche et remplit _F4M_M_* (voir plus bas) ; code ≠ 0
#                                            si la fiche ou ses clés de mesure manquent
#   _f4m_m_couverte / _f4m_m_sous_objectif / _f4m_m_declaree_juste
#                                          → prédicats sur la dernière mesure lue (pour check_cmd)
# Exemple (check-S13 de la bascule de Legacy-RDV) :
#   source "$(dirname "${BASH_SOURCE[0]}")/_f4-montees.sh"
#   if _f4m_mesurer CHG-3413; then
#     check_cmd "CHG-3413 : mesure présente sur ${_F4M_M_COUVERTURE_PCT} % de la fenêtre" _f4m_m_couverte
#     check_cmd "CHG-3413 : ${_F4M_M_MESUREE} s d'erreur ≤ objectif ${_F4M_M_OBJECTIF} s" _f4m_m_sous_objectif
#   fi
# ---------------------------------------------------------------------------------------------------

_f4m_doc_dir="${WB_F4_DOC:-docs/changements}"
_f4m_projet_doc="${WB_F4_PROJET_DOC:-plateforme/medisphere}"
_f4m_resilience="${WB_F4_PROJET_RESILIENCE:-plateforme/resilience}"
_f4m_observabilite="${WB_F4_PROJET_OBSERVABILITE:-plateforme/observabilite}"
_f4m_temoin="${WB_F4_PROM_TEMOIN_URL:-http://mon01.par1.medisphere.internal:9090}"
_f4m_tolerance="${WB_F4_TOLERANCE_S:-30}"
_f4m_couverture_min="${WB_F4_COUVERTURE_MIN:-0.9}"
_f4m_tableau="${WB_F4_TABLEAU_UID:-f4-changement-en-cours}"
_F4M_PAS=15

# --- GitLab (lecture) ------------------------------------------------------------------------------

_f4m_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _f4m_fichier PROJET CHEMIN [RÉF=main] — contenu du fichier.
_f4m_fichier() {
  gitlab_api "projects/$(_f4m_enc "$1")/repository/files/$(_f4m_enc "$2")/raw?ref=$(_f4m_enc "${3:-main}")"
}

# _f4m_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif (casse ignorée).
_f4m_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_f4m_fichier "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _f4m_arbre PROJET [DOSSIER] [RÉF=main] — chemins des fichiers (récursif).
_f4m_arbre() {
  local p page=1 r ref
  p="$(_f4m_enc "$1")"
  ref="$(_f4m_enc "${3:-main}")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=$ref&recursive=true&per_page=100&page=$page${2:+&path=$(_f4m_enc "$2")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _f4m_chemin PROJET DOSSIER MOTIF_NOM — premier fichier sous DOSSIER dont le NOM correspond au motif.
_f4m_chemin() {
  local f
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $3 ]] && { printf '%s\n' "$f"; return 0; }
  done < <(_f4m_arbre "$1" "$2")
  return 1
}

# _f4m_doc SOUS-DOSSIER MOTIF_NOM REGEX… — un fichier de la documentation des changements (sous
# docs/changements/SOUS-DOSSIER, « . » pour la racine, récursif) dont le nom correspond au motif
# contient chaque motif.
_f4m_doc() {
  local d="$_f4m_doc_dir" motif="$2" f
  [[ "$1" != "." ]] && d="$d/$1"
  shift 2
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    _f4m_contient "$_f4m_projet_doc" "$f" "$@" && return 0
  done < <(_f4m_arbre "$_f4m_projet_doc" "$d")
  return 1
}

# _f4m_pipeline_ok PROJET — le dernier pipeline de main a réussi.
_f4m_pipeline_ok() {
  gitlab_api "projects/$(_f4m_enc "$1")/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1
}

# _f4m_date_commit PROJET CHEMIN — date (epoch) du PREMIER commit qui a créé le fichier sur main.
_f4m_date_commit() {
  local d
  d="$(gitlab_api "projects/$(_f4m_enc "$1")/repository/commits?ref_name=main&path=$(_f4m_enc "$2")&per_page=100" 2>/dev/null |
    jq -r 'last | .committed_date // empty' 2>/dev/null)" || return 1
  [[ -n "$d" ]] || return 1
  date -d "$d" +%s 2>/dev/null
}

# --- Fiches de changement --------------------------------------------------------------------------

# _f4m_fiche CHG — contenu de docs/changements/fiches/CHG-34XX*.md sur main (code ≠ 0 si absente).
_f4m_fiche() {
  local f
  f="$(_f4m_chemin "$_f4m_projet_doc" "$_f4m_doc_dir/fiches" "^$1([-_.].*)?\\.md\$")" || return 1
  _f4m_fichier "$_f4m_projet_doc" "$f"
}

# _f4m_fiche_contient CHG REGEX… — la fiche existe et contient chaque motif (casse ignorée).
_f4m_fiche_contient() {
  local c m
  c="$(_f4m_fiche "$1" 2>/dev/null)" || return 1
  shift
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _f4m_entete CONTENU CLÉ — valeur d'une clé de l'en-tête YAML (premier bloc entre « --- »), sans
# guillemets ni commentaire de fin de ligne.
_f4m_entete() {
  awk -v cle="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 {
      i = index($0, ":")
      if (i > 0 && substr($0, 1, i - 1) == cle) {
        v = substr($0, i + 1)
        sub(/[[:space:]]+#.*$/, "", v)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        gsub(/^["\x27]|["\x27]$/, "", v)
        print v
        exit
      }
    }' <<<"$1"
}

# _f4m_fiche_cle CHG CLÉ — valeur d'une clé de l'en-tête de la fiche (vide si absente).
_f4m_fiche_cle() {
  local c
  c="$(_f4m_fiche "$1" 2>/dev/null)" || return 1
  _f4m_entete "$c" "$2"
}

# _f4m_decision CHG — « go », « no-go » ou vide (en minuscules).
_f4m_decision() {
  local d
  d="$(_f4m_fiche_cle "$1" decision 2>/dev/null)" || return 1
  d="${d,,}"
  d="${d// /}"
  case "$d" in
    go | no-go | nogo) printf '%s\n' "${d/nogo/no-go}" ;;
    *) return 1 ;;
  esac
}

# --- Prometheus (cluster ou témoin) ----------------------------------------------------------------

# _f4m_prom SOURCE 'PromQL' [INSTANT] — JSON d'une requête instantanée (SOURCE : cluster|temoin).
# _F4M_SANS_DEDUP=1 (cluster) : requête Thanos Query avec dedup=false. Nécessaire pour la MESURE : la
# charge k6 n'écrit que dans prometheus-kps-prometheus-0 (M29-E14), donc continuite:en_erreur ne voit les
# erreurs de la charge que sur ce réplica ; le dédoublonnage de Query (« penalty », M21-E24) peut suivre
# l'autre réplica. Sans dédoublonnage, max(continuite:en_erreur) prend le pire des deux réplicas.
_f4m_prom() {
  local base
  local -a t=()
  if [[ "$1" == temoin ]]; then base="$_f4m_temoin"; else base="${WB_PROM_URL:-http://prometheus.apps.par1.medisphere.internal:9090}"; fi
  [[ -n "${3:-}" ]] && t=(--data-urlencode "time=$3")
  [[ "$1" != temoin && "${_F4M_SANS_DEDUP:-0}" == 1 ]] && t+=(--data-urlencode "dedup=false")
  curl -sf --max-time "$((WB_TIMEOUT * 4))" -H "Accept: application/json" --data-urlencode "query=$2" \
    "${t[@]}" "$base/api/v1/query"
}

# _f4m_prom_val SOURCE 'PromQL' [INSTANT] — première valeur (vide si aucune série).
_f4m_prom_val() {
  _f4m_prom "$@" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null
}

# _f4m_prom_non_vide SOURCE 'PromQL' — au moins une série.
_f4m_prom_non_vide() {
  _f4m_prom "$1" "$2" 2>/dev/null | jq -e '.status == "success" and (.data.result | length) > 0' >/dev/null 2>&1
}

# _f4m_epoch ISO8601 — horodatage Unix (code ≠ 0 si illisible).
_f4m_epoch() { [[ -n "${1:-}" ]] && date -d "$1" +%s 2>/dev/null; }

# _f4m_serie SOURCE [GROUPES] — série 0/1 de la mesure selon la source (GROUPES : regex sur l'étiquette
# « groupe » des sondes, source temoin seulement ; caractères admis : lettres, chiffres, - . * |).
_f4m_serie() {
  if [[ "$1" == temoin && -n "${2:-}" && "$2" =~ ^[a-z0-9.*|-]+$ ]]; then
    printf 'max(continuite:sonde_en_erreur{groupe=~"%s"})\n' "$2"
  elif [[ "$1" == temoin ]]; then
    echo 'max(continuite:sondes_en_erreur:max)'
  else
    echo 'max(continuite:en_erreur)'
  fi
}

# _f4m_interruption DEBUT FIN [SOURCE=cluster] [GROUPES] — secondes d'erreur cumulées (entier arrondi).
_f4m_interruption() {
  local d0 d1 d v src="${3:-cluster}"
  d0="$(_f4m_epoch "$1")" || return 1
  d1="$(_f4m_epoch "$2")" || return 1
  d=$((d1 - d0))
  ((d > 0)) || return 1
  v="$(_F4M_SANS_DEDUP=1 _f4m_prom_val "$src" "avg_over_time($(_f4m_serie "$src" "${4:-}")[${d}s:${_F4M_PAS}s]) * $d" "$d1")" || return 1
  [[ -n "$v" && "$v" != NaN ]] || return 1
  awk -v x="$v" 'BEGIN { printf "%d\n", x + 0.5 }'
}

# _f4m_couverture DEBUT FIN [SOURCE=cluster] [GROUPES] — part de la fenêtre où la mesure existait (0 à 1).
_f4m_couverture() {
  local d0 d1 d v src="${3:-cluster}"
  d0="$(_f4m_epoch "$1")" || return 1
  d1="$(_f4m_epoch "$2")" || return 1
  d=$((d1 - d0))
  ((d > 0)) || return 1
  v="$(_F4M_SANS_DEDUP=1 _f4m_prom_val "$src" "count_over_time($(_f4m_serie "$src" "${4:-}")[${d}s:${_F4M_PAS}s]) * ${_F4M_PAS} / $d" "$d1")" || return 1
  [[ -n "$v" ]] || { echo 0; return 0; }
  awk -v x="$v" 'BEGIN { if (x > 1) x = 1; printf "%.2f\n", x }'
}

# _f4m_charge_active DEBUT FIN — la charge k6 de la sonde (testid sonde-continuite*) a envoyé des
# requêtes pendant la fenêtre (Prometheus du cluster).
_f4m_charge_active() {
  local d0 d1 d v
  d0="$(_f4m_epoch "$1")" || return 1
  d1="$(_f4m_epoch "$2")" || return 1
  d=$((d1 - d0))
  ((d > 0)) || return 1
  v="$(_f4m_prom_val cluster "sum(increase(k6_http_reqs_total{testid=~\"sonde-continuite.*\"}[${d}s]))" "$d1")" || return 1
  awk -v x="${v:-0}" 'BEGIN { exit !(x > 0) }'
}

# Dernière mesure lue par _f4m_mesurer :
_F4M_M_CHG=""
_F4M_M_SOURCE=""
_F4M_M_GROUPES=""
_F4M_M_DEBUT=""
_F4M_M_FIN=""
_F4M_M_OBJECTIF=""
_F4M_M_DECLAREE=""
_F4M_M_MESUREE=""
_F4M_M_COUVERTURE=""
_F4M_M_COUVERTURE_PCT=""

# _f4m_mesurer CHG — lit l'en-tête de la fiche et recalcule la mesure. Code ≠ 0 si la fiche, la fenêtre
# ou l'objectif manquent (les variables _F4M_M_* restent alors vides ou partielles).
_f4m_mesurer() {
  local c
  _F4M_M_CHG="$1"
  _F4M_M_SOURCE="" _F4M_M_GROUPES="" _F4M_M_DEBUT="" _F4M_M_FIN="" _F4M_M_OBJECTIF="" _F4M_M_DECLAREE=""
  _F4M_M_MESUREE="" _F4M_M_COUVERTURE="" _F4M_M_COUVERTURE_PCT=""
  c="$(_f4m_fiche "$1" 2>/dev/null)" || return 1
  _F4M_M_SOURCE="$(_f4m_entete "$c" mesure-source)"
  [[ "$_F4M_M_SOURCE" == temoin ]] || _F4M_M_SOURCE=cluster
  _F4M_M_GROUPES="$(_f4m_entete "$c" mesure-groupes)"
  _F4M_M_DEBUT="$(_f4m_entete "$c" mesure-debut)"
  _F4M_M_FIN="$(_f4m_entete "$c" mesure-fin)"
  _F4M_M_OBJECTIF="$(_f4m_entete "$c" mesure-objectif-s)"
  _F4M_M_DECLAREE="$(_f4m_entete "$c" mesure-interruption-s)"
  _f4m_epoch "$_F4M_M_DEBUT" >/dev/null || return 1
  _f4m_epoch "$_F4M_M_FIN" >/dev/null || return 1
  [[ "$_F4M_M_OBJECTIF" =~ ^[0-9]+$ ]] || return 1
  _F4M_M_COUVERTURE="$(_f4m_couverture "$_F4M_M_DEBUT" "$_F4M_M_FIN" "$_F4M_M_SOURCE" "$_F4M_M_GROUPES" 2>/dev/null)" || _F4M_M_COUVERTURE=0
  _F4M_M_COUVERTURE_PCT="$(awk -v x="${_F4M_M_COUVERTURE:-0}" 'BEGIN { printf "%d", x * 100 + 0.5 }')"
  _F4M_M_MESUREE="$(_f4m_interruption "$_F4M_M_DEBUT" "$_F4M_M_FIN" "$_F4M_M_SOURCE" "$_F4M_M_GROUPES" 2>/dev/null)" || _F4M_M_MESUREE=""
  return 0
}

# _f4m_m_couverte — la mesure existe sur au moins WB_F4_COUVERTURE_MIN de la fenêtre.
_f4m_m_couverte() {
  [[ -n "$_F4M_M_COUVERTURE" ]] && awk -v x="$_F4M_M_COUVERTURE" -v m="$_f4m_couverture_min" 'BEGIN { exit !(x >= m) }'
}

# _f4m_m_sous_objectif — interruption recalculée ≤ objectif de la fiche.
_f4m_m_sous_objectif() {
  [[ "$_F4M_M_MESUREE" =~ ^[0-9]+$ && "$_F4M_M_OBJECTIF" =~ ^[0-9]+$ ]] && ((_F4M_M_MESUREE <= _F4M_M_OBJECTIF))
}

# _f4m_m_declaree_juste — la valeur notée dans la fiche est celle de la mesure, à WB_F4_TOLERANCE_S près.
_f4m_m_declaree_juste() {
  [[ "$_F4M_M_MESUREE" =~ ^[0-9]+$ && "$_F4M_M_DECLAREE" =~ ^[0-9]+([.,][0-9]+)?$ ]] || return 1
  awk -v a="${_F4M_M_DECLAREE/,/.}" -v b="$_F4M_M_MESUREE" -v t="$_f4m_tolerance" \
    'BEGIN { e = a - b; if (e < 0) e = -e; exit !(e <= t) }'
}

# _f4m_controles_mesure CHG — bloc standard de trois contrôles sur la mesure d'une fiche (utilisé par
# S04, S05, S07, S08 ; réutilisable par S10 et S13).
_f4m_controles_mesure() {
  if _f4m_mesurer "$1"; then
    check_cmd "$1 : mesure de la sonde présente sur ${_F4M_M_COUVERTURE_PCT} % de la fenêtre (source $_F4M_M_SOURCE, attendu ≥ $(awk -v m="$_f4m_couverture_min" 'BEGIN { printf "%d", m * 100 }') %)" _f4m_m_couverte
    check_cmd "$1 : interruption recalculée ${_F4M_M_MESUREE:-?} s ≤ objectif ${_F4M_M_OBJECTIF} s" _f4m_m_sous_objectif
    check_cmd "$1 : interruption notée dans la fiche (${_F4M_M_DECLAREE:-absente}) conforme à la mesure (± ${_f4m_tolerance} s)" _f4m_m_declaree_juste
  else
    _ko "$1 : en-tête de mesure absent ou incomplet (mesure-debut, mesure-fin, mesure-objectif-s)"
  fi
}

# --- Kubernetes (lecture, compte wb-checks) ---------------------------------------------------------

_f4m_api_repond() { kube get --raw /livez >/dev/null 2>&1; }

# _f4m_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_f4m_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _f4m_app_saine NOM — Application Argo CD Synced et Healthy.
_f4m_app_saine() {
  _f4m_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"' -n argocd applications.argoproj.io "$1"
}

# _f4m_noeuds_sains — tous les nœuds Ready, aucun cordonné, au moins six.
_f4m_noeuds_sains() {
  _f4m_kq '(.items | length) >= 6 and all(.items[]; (.spec.unschedulable // false) == false
    and any(.status.conditions[]; .type == "Ready" and .status == "True"))' nodes
}

# _f4m_kubelets_mineure MINEURE — tous les kubelets en vMINEURE.x (ex. 1.37).
_f4m_kubelets_mineure() {
  kube get nodes -o json 2>/dev/null | jq -e --arg m "v$1." '(.items | length) > 0 and all(.items[]; .status.nodeInfo.kubeletVersion | startswith($m))' >/dev/null 2>&1
}

# _f4m_version_sup A B — A > B (tri de versions).
_f4m_version_sup() {
  [[ -n "$1" && -n "$2" && "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" ]]
}

# _f4m_version_image ESPACE REGEX_DÉPÔT — version (sans « v ») de la première image de conteneur d'un
# Deployment, StatefulSet ou DaemonSet de l'espace dont le dépôt correspond à la regex.
_f4m_version_image() {
  kube get deployments,statefulsets,daemonsets -n "$1" -o json 2>/dev/null |
    jq -r --arg r "$2" '[.items[].spec.template.spec.containers[].image
        | select(test($r)) | (split("@")[0] | split(":") | if length > 1 then last else "" end)
        | ltrimstr("v") | select(test("^[0-9]+\\.[0-9]+"))] | first // empty' 2>/dev/null
}
