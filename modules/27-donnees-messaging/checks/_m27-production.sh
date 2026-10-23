# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et requêtes entre apostrophes
# _m27-production.sh — fonctions partagées par les vérifications du palier 3 du module 27 (check-E13 à
# check-E17), réutilisées par le palier 4 et le mini-projet. Sourcé, jamais lancé seul.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Lecture seule : « kube » (compte wb-checks : ClusterRoles agrégées, dont wb-checks-services pour les CRD
# de CNPG et de RabbitMQ ; jamais les Secrets), Prometheus/Thanos Query (GET), API de gestion de RabbitMQ
# (compte wb-checks, étiquette monitoring), Grafana (Viewer), GitLab (read_api), NetBox (lecture), pve01
# (« qm list »), DNS. Préfixe _m27p_ : évite les collisions quand check-E25 charge plusieurs checks.

# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
{
  _m27p_docs=docs/donnees
  _m27p_runbooks=docs/donnees/runbooks
  _m27p_recette=mediagenda-recette
  _m27p_prod=mediagenda-prod
  _m27p_secours=mediagenda-secours
  _m27p_vhost_recette=medinotif-recette
  _m27p_vhost_prod=medinotif-prod
}

# --- Kubernetes (compte wb-checks) ------------------------------------------------------------

# _m27p_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_m27p_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _m27p_peut VERBE RESSOURCE [ESPACE] — le compte des checks a ce droit (sinon le contrôle est ignoré).
_m27p_peut() {
  local r
  r="$(kube auth can-i "$1" "$2" ${3:+-n "$3"} 2>/dev/null)" || r=""
  [[ "$r" == yes ]]
}

# _m27p_application_saine NOM — Application Argo CD Synced et Healthy.
_m27p_application_saine() {
  _m27p_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"' -n argocd applications.argoproj.io "$1"
}

# _m27p_cluster_joignable — l'API Kubernetes répond au compte des checks (sinon aucune absence ne prouve rien).
_m27p_cluster_joignable() { kube get namespace default >/dev/null 2>&1; }

# _m27p_absent RESSOURCE ESPACE — aucune ressource de ce type dans l'espace (espace absent = rien), le
# cluster étant joignable.
_m27p_absent() {
  _m27p_cluster_joignable || return 1
  kube get namespace "$2" >/dev/null 2>&1 || return 0
  _m27p_kq '.items | length == 0' -n "$2" "$1"
}

# _m27p_cluster_sain ESPACE NOM — Cluster CNPG : toutes les instances prêtes, état sain.
_m27p_cluster_sain() {
  _m27p_kq '(.status.readyInstances // 0) >= 1 and (.status.readyInstances // 0) == .spec.instances
            and (.status.phase // "") == "Cluster in healthy state"' -n "$1" clusters.postgresql.cnpg.io "$2"
}

# _m27p_regles_alertes — toutes les règles d'alerte des PrometheusRule du cluster, une par ligne :
# {"alert":…, "expr":…, "runbook":…} en JSON compact.
_m27p_regles_alertes() {
  kube get prometheusrules.monitoring.coreos.com -A -o json 2>/dev/null |
    jq -c '.items[].spec.groups[]?.rules[]? | select(.alert != null)
           | {alert, expr: (.expr | tostring), runbook: (.annotations.runbook_url // "")}'
}

# _m27p_alerte_famille 'regex sur expr' — au moins une alerte dont l'expression correspond, et TOUTES les
# alertes qui correspondent ont un runbook_url.
_m27p_alerte_famille() {
  _m27p_regles_alertes | jq -s -e --arg r "$1" '[.[] | select(.expr | test($r))] as $a
    | ($a | length) > 0 and all($a[]; .runbook != "")' >/dev/null 2>&1
}

# --- Prometheus (Thanos Query) -------------------------------------------------------------------

_m27p_prom_nb() { prom_requete "$1" 2>/dev/null | jq '.data.result | length' 2>/dev/null || echo 0; }
_m27p_prom_present() { (($(_m27p_prom_nb "$1") > 0)); }

# _m27p_prom_vrai 'PromQL' — la requête rend au moins un résultat et tous ses résultats sont non nuls
# (utile avec une comparaison : « expr < 900 » ne rend que les séries qui la satisfont).
_m27p_prom_positif() {
  prom_requete "$1" 2>/dev/null | jq -e '(.data.result | length) > 0 and all(.data.result[]; (.value[1] | tonumber) > 0)' >/dev/null 2>&1
}

# _m27p_prom_nul_ou_absent 'PromQL' — la requête a réussi et ne rend aucune valeur strictement positive.
_m27p_prom_nul_ou_absent() {
  local r
  r="$(prom_requete "$1" 2>/dev/null)" || return 1
  jq -e '.status == "success" and ([.data.result[]?.value[1] | tonumber | select(. > 0)] | length == 0)' >/dev/null 2>&1 <<<"$r"
}

# --- RabbitMQ (compte wb-checks, monitoring) -----------------------------------------------------

_m27p_enc() { jq -rn --arg v "$1" '$v | @uri'; }

# _m27p_file VHOST FILE 'filtre jq' — l'objet file de l'API de gestion satisfait le filtre.
_m27p_file() {
  rabbitmq_api "queues/$(_m27p_enc "$1")/$(_m27p_enc "$2")" 2>/dev/null | jq -e "$3" >/dev/null 2>&1
}

# --- GitLab (lecture) ----------------------------------------------------------------------------

_m27p_fichier() { gitlab_api "projects/$(_m27p_enc "$1")/repository/files/$(_m27p_enc "$2")/raw?ref=main"; }

_m27p_arbre() {
  gitlab_api "projects/$(_m27p_enc "$1")/repository/tree?ref=main&path=$(_m27p_enc "$2")&recursive=true&per_page=100" 2>/dev/null |
    jq -r '.[]? | select(.type == "blob") | .path'
}

# _m27p_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif (casse ignorée).
_m27p_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m27p_fichier "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m27p_doc DOSSIER MOTIF_DE_NOM REGEX… — un fichier dont le NOM contient MOTIF_DE_NOM, sous DOSSIER de
# plateforme/medisphere, contient chaque motif.
_m27p_doc() {
  local d="$1" mot="$2" f
  shift 2
  for f in $(_m27p_arbre plateforme/medisphere "$d" | awk -F/ -v p="$mot" 'index($NF, p) > 0'); do
    if _m27p_contient plateforme/medisphere "$f" "$@"; then return 0; fi
  done
  return 1
}

# _m27p_depot_contient PROJET DOSSIER REGEX — un fichier sous DOSSIER (main) contient la regex.
_m27p_depot_contient() {
  local f
  for f in $(_m27p_arbre "$1" "$2"); do
    if _m27p_fichier "$1" "$f" 2>/dev/null | grep -Eq -- "$3"; then return 0; fi
  done
  return 1
}

# _m27p_depot_contient_tout PROJET DOSSIER REGEX… — UN MÊME fichier sous DOSSIER contient toutes les regex.
_m27p_depot_contient_tout() {
  local p="$1" d="$2" f
  shift 2
  for f in $(_m27p_arbre "$p" "$d"); do
    if _m27p_contient "$p" "$f" "$@"; then return 0; fi
  done
  return 1
}

# --- Pannes ------------------------------------------------------------------------------------

# _m27p_aucune_panne_active [EXX…] — aucune des pannes listées (ou M27-* si aucune) n'est marquée active.
_m27p_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M27-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M27-$e" ]] || return 1
  done
}
