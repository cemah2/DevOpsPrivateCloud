# shellcheck shell=bash
# _m21-decouverte.sh — fonctions partagées par les checks M21-E02 à M21-E08 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m21d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - cluster : « kube » (compte wb-checks ; ClusterRole agrégée wb-checks-observabilite, M21-E02,
#     et wb-checks-livraison pour les Applications d'Argo CD, M20) ;
#   - Prometheus : prom_api / prom_requete (WB_PROM_URL, défaut http://prometheus.apps…:9090) ;
#   - Alertmanager : am_api (WB_AM_URL) ; Grafana : grafana_api (jeton Viewer, M21-E05) ;
#   - Mailpit : mailpit_api (M19) ; GitLab : gitlab_api (jeton read_api).
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_M21_VMS_SOCLE   nombre de VMs du socle supervisées par node_exporter (15)
#   WB_M21_HOTES_TLS   hôtes du socle dont le check E08 vérifie le TLS depuis adm01 (mon01 dns01)
#   WB_M21_NOEUDS      nombre de nœuds de k8s-par1 (6)

_M21D_NS=supervision
_M21D_NS_NOEUDS=supervision-noeuds
_M21D_SELECTEUR="medisphere.internal/supervision"
_M21D_VMS="${WB_M21_VMS_SOCLE:-15}"
_M21D_NOEUDS="${WB_M21_NOEUDS:-6}"
read -r -a _M21D_HOTES_TLS <<<"${WB_M21_HOTES_TLS:-mon01 dns01}"
_M21D_DOMAINE=par1.medisphere.internal

# _m21d_k ARGS… — kubectl en lecture par le compte des checks (sortie vide en cas d'erreur).
_m21d_k() {
  kube "$@" 2>/dev/null || true
}

# _m21d_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m21d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m21d_uri TEXTE — encodage pour une URL (chemins GitLab, requêtes Grafana).
_m21d_uri() {
  jq -rn --arg v "$1" '$v | @uri'
}

# _m21d_fichier_main PROJET CHEMIN — le fichier existe sur la branche main du projet GitLab.
_m21d_fichier_main() {
  gitlab_api "projects/$(_m21d_uri "$1")/repository/files/$(_m21d_uri "$2")?ref=main" >/dev/null 2>&1
}

# _m21d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m21d_contenu_main() {
  gitlab_api "projects/$(_m21d_uri "$1")/repository/files/$(_m21d_uri "$2")/raw?ref=main" 2>/dev/null || true
}

# _m21d_pipeline_main PROJET — statut du dernier pipeline de main (vide si aucun).
_m21d_pipeline_main() {
  gitlab_api "projects/$(_m21d_uri "$1")/pipelines?ref=main&per_page=1" 2>/dev/null \
    | jq -r '.[0].status // empty' 2>/dev/null || true
}

# _m21d_application NOM — Application Argo CD (JSON, vide si illisible).
_m21d_application() {
  _m21d_k -n argocd get applications.argoproj.io "$1" -o json
}

# _m21d_app_saine NOM — Application Synced et Healthy.
_m21d_app_saine() {
  _m21d_json "$(_m21d_application "$1")" '.status.sync.status == "Synced" and .status.health.status == "Healthy"'
}

# _m21d_valeur 'PromQL' — première valeur du résultat (vide si pas de résultat ou erreur).
_m21d_valeur() {
  prom_requete "$1" 2>/dev/null | jq -r 'if .status == "success" then (.data.result[0].value[1] // empty) else empty end' 2>/dev/null || true
}

# _m21d_au_moins 'PromQL' N — la première valeur du résultat est >= N.
_m21d_au_moins() {
  local v
  v="$(_m21d_valeur "$1")"
  [[ -n "$v" ]] && awk -v v="$v" -v n="$2" 'BEGIN { exit !(v + 0 >= n + 0) }'
}

# _m21d_vide 'PromQL' — la requête réussit et ne renvoie AUCUNE série (ex. « up == 0 »).
_m21d_vide() {
  prom_requete "$1" 2>/dev/null | jq -e '.status == "success" and (.data.result | length == 0)' >/dev/null 2>&1
}

# _m21d_requetes CONTENU — découpe un fichier .promql (format de plateforme/observabilite :
# une requête par bloc, blocs séparés par une ligne vide, commentaires en « # ») ; écrit une
# requête par ligne (lignes du bloc jointes par une espace).
_m21d_requetes() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { if (q != "") { print q; q = "" } next }
    { sub(/^[[:space:]]+/, ""); q = (q == "" ? $0 : q " " $0) }
    END { if (q != "") print q }
  ' <<<"$1"
}

# _m21d_donne_des_donnees 'PromQL' — la requête est valide et renvoie au moins un résultat
# (vecteur ou matrice non vide, ou scalaire).
_m21d_donne_des_donnees() {
  prom_requete "$1" 2>/dev/null | jq -e '
    .status == "success" and
    (if .data.resultType == "scalar" or .data.resultType == "string" then true
     else (.data.result | length) > 0 end)' >/dev/null 2>&1
}

# _m21d_controler_fichier_promql PROJET CHEMIN MINIMUM — contrôle un fichier de requêtes de
# travail : présent sur main, au moins MINIMUM requêtes, chacune s'évalue et renvoie des données.
# Affiche un OK/KO par requête (numérotées dans l'ordre du fichier).
_m21d_controler_fichier_promql() {
  local projet="$1" chemin="$2" minimum="$3" contenu n=0 q
  local -a requetes=()
  contenu="$(_m21d_contenu_main "$projet" "$chemin")"
  if [[ -z "$contenu" ]]; then
    _ko "$projet : $chemin absent de main"
    return 0
  fi
  mapfile -t requetes < <(_m21d_requetes "$contenu")
  if (( ${#requetes[@]} >= minimum )); then
    _ok "$chemin : ${#requetes[@]} requête(s) (au moins $minimum attendues)"
  else
    _ko "$chemin : ${#requetes[@]} requête(s), au moins $minimum attendues (une par question)"
  fi
  for q in "${requetes[@]}"; do
    n=$((n + 1))
    check_cmd "$chemin, requête $n : valide et renvoie des données ($(cut -c1-60 <<<"$q")…)" \
      _m21d_donne_des_donnees "$q"
  done
}

# _m21d_yaml_json — convertit en JSON compact le YAML lu sur l'entrée standard (vide si aucun
# convertisseur). Essaie yq de Mike Farah, yq de Python (surcouche de jq), puis PyYAML.
_m21d_yaml_json() {
  local yaml
  yaml="$(cat)"
  if command -v yq >/dev/null 2>&1; then
    yq -o=json -I=0 '.' <<<"$yaml" 2>/dev/null && return 0
    yq -c '.' <<<"$yaml" 2>/dev/null && return 0
  fi
  python3 -c 'import json, sys, yaml; print(json.dumps(yaml.safe_load(sys.stdin)))' <<<"$yaml" 2>/dev/null || true
}
