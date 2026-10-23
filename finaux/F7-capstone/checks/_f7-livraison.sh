# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _f7-livraison.sh — fonctions partagées par les vérifications des phases « Livrer » et « Soutenir » du
# final F7 (check-S07 à check-S14). Sourcé, jamais lancé seul. Préfixe _f7l_. Charge _f7-capstone.sh
# (fonctions _f7c_ de lecture de GitLab et des documents de docs/capstone/).
#
# Lecture seule : GitLab en GET (jeton des checks) ; Kubernetes par « kube » (compte wb-checks, jamais
# les Secrets) ; Keycloak par keycloak_api (client wb-checks du royaume medisphere : + rôle
# view-identity-providers, énoncé F7-S08) ; OpenBao par bao_api (AppRole wb-checks : + list sur
# transit/keys et read sur transit/keys/<client>-*, énoncé F7-S07) ; Prometheus (Thanos Query) et
# témoin de mon01 en GET ; HTTPS anonyme vers les noms publiés du client ; état local de la panne de
# S11 (lecture).
#
# Variables de lab/lab.env (toutes facultatives) ; préfixe WB_F7_ :
#   WB_F7_CLIENT              nom du client (défaut ghsv)
#   WB_F7_URL_PROD            https://ghsv.apps.par1.medisphere.internal
#   WB_F7_URL_RECETTE         https://ghsv-recette.apps.par1.medisphere.internal
#   WB_F7_URL_AGENTS          https://ghsv-agents.apps.par1.medisphere.internal
#   WB_F7_IDP_ALIAS           alias du fournisseur d'identité dans medisphere (défaut ghsv-idp)
#   WB_F7_GROUPE_AGENTS       groupe Keycloak des agents (défaut ghsv-agents)
#   WB_F7_GROUPE_IDP          groupe convenu chez le GHSV (défaut secretariat-medical)
#   WB_F7_PROJET_EQUIPES      plateforme/equipes        WB_F7_PROJET_IDENTITE   plateforme/identite
#   WB_F7_PROJET_API          mediagenda/api            WB_F7_PROJET_DEPLOIEMENT mediagenda/deploiement
#   WB_F7_PROJET_OUTILS       plateforme/outils         WB_F7_PROJET_OBSERVABILITE plateforme/observabilite
#   WB_F7_PAR2_KUBECONFIG     kubeconfig EN LECTURE de k8s-par2 (défaut ~/.config/workbook/k8s-par2-checks.kubeconfig ;
#                             absent : contrôles de PAR2 ignorés)
#   WB_F7_S3_REVERSIBILITE_ENV  identité S3 en LECTURE du compartiment de réversibilité (facultatif ;
#                             défaut ~/.config/workbook/s3-ghsv-reversibilite-lecture.env)
#   WB_F7_RGW_URL             https://rgw.par1.medisphere.internal
# Et celles du F6 pour le compartiment de preuves (WB_F6_PREUVES_ENV, WB_F6_PREUVES_BUCKET, WB_F6_RGW_URL),
# celles du F4 pour le témoin de mon01 (WB_F4_PROM_TEMOIN_URL), et celles de lab/lib/check-lib.sh.

# shellcheck source=_f7-capstone.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-capstone.sh"

_f7l_client="${WB_F7_CLIENT:-ghsv}"
_f7l_doc_projet="${WB_F7_PROJET_DOC:-plateforme/medisphere}"
_f7l_url_prod="${WB_F7_URL_PROD:-https://ghsv.apps.par1.medisphere.internal}"
_f7l_url_recette="${WB_F7_URL_RECETTE:-https://ghsv-recette.apps.par1.medisphere.internal}"
_f7l_url_agents="${WB_F7_URL_AGENTS:-https://ghsv-agents.apps.par1.medisphere.internal}"
_f7l_idp="${WB_F7_IDP_ALIAS:-ghsv-idp}"
_f7l_groupe_agents="${WB_F7_GROUPE_AGENTS:-ghsv-agents}"
_f7l_groupe_idp="${WB_F7_GROUPE_IDP:-secretariat-medical}"
_f7l_equipes="${WB_F7_PROJET_EQUIPES:-plateforme/equipes}"
_f7l_identite="${WB_F7_PROJET_IDENTITE:-plateforme/identite}"
_f7l_api="${WB_F7_PROJET_API:-mediagenda/api}"
_f7l_deploiement="${WB_F7_PROJET_DEPLOIEMENT:-mediagenda/deploiement}"
_f7l_outils="${WB_F7_PROJET_OUTILS:-plateforme/outils}"
_f7l_observabilite="${WB_F7_PROJET_OBSERVABILITE:-plateforme/observabilite}"
_f7l_par2_kc="${WB_F7_PAR2_KUBECONFIG:-$HOME/.config/workbook/k8s-par2-checks.kubeconfig}"
_f7l_s3_rev="${WB_F7_S3_REVERSIBILITE_ENV:-$HOME/.config/workbook/s3-ghsv-reversibilite-lecture.env}"
_f7l_rgw="${WB_F7_RGW_URL:-https://rgw.par1.medisphere.internal}"
_f7l_ns_recette="${_f7l_client}-recette"
_f7l_ns_prod="${_f7l_client}-prod"

# --- GitLab -----------------------------------------------------------------------------------------

# _f7l_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif (casse ignorée).
_f7l_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_f7c_fichier "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" && ! "$c" =~ ^\{\"(message|error)\" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _f7l_trouver PROJET DOSSIER REGEX_CHEMIN REGEX… — un fichier sous DOSSIER (récursif) dont le CHEMIN
# correspond à REGEX_CHEMIN contient chaque motif ; affiche son chemin.
_f7l_trouver() {
  local p="$1" d="$2" motif="$3" f
  shift 3
  while IFS= read -r f; do
    [[ -n "$f" && "$f" =~ $motif ]] || continue
    if _f7l_contient "$p" "$f" "$@"; then printf '%s\n' "$f"; return 0; fi
  done < <(_f7c_arbre "$p" "$d")
  return 1
}

# _f7l_doc DOSSIER_RELATIF REGEX_NOM REGEX… — un document sous docs/capstone/DOSSIER dont le NOM
# correspond contient chaque motif (« . » pour docs/capstone lui-même).
_f7l_doc() {
  local d="$_f7c_doc_dir" motif="$2" f
  [[ "$1" != "." ]] && d="$d/$1"
  shift 2
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    _f7l_contient "$_f7l_doc_projet" "$f" "$@" && return 0
  done < <(_f7c_arbre "$_f7l_doc_projet" "$d")
  return 1
}

# _f7l_pipeline_ok PROJET — le dernier pipeline de main a réussi.
_f7l_pipeline_ok() {
  gitlab_api "projects/$(_f7c_enc "$1")/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1
}

# _f7l_etiquette ÉTIQUETTE — l'étiquette existe sur plateforme/medisphere.
_f7l_etiquette() {
  gitlab_api "projects/$(_f7c_enc "$_f7l_doc_projet")/repository/tags/$(_f7c_enc "$1")" 2>/dev/null | jq -e '.name' >/dev/null 2>&1
}

# --- Kubernetes -------------------------------------------------------------------------------------

_f7l_api_repond() { kube get --raw /livez >/dev/null 2>&1; }

# _f7l_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_f7l_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _f7l_app ESPACE — nom de l'Application Argo CD dont la destination est ESPACE.
_f7l_app() {
  kube -n argocd get applications.argoproj.io -o json 2>/dev/null |
    jq -r --arg ns "$1" '[.items[] | select(.spec.destination.namespace == $ns) | .metadata.name][0] // empty'
}

# _f7l_app_saine ESPACE — l'Application de l'espace est Synced et Healthy.
_f7l_app_saine() {
  local a
  a="$(_f7l_app "$1")"
  [[ -n "$a" ]] && _f7l_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"' -n argocd applications.argoproj.io "$a"
}

# _f7l_api_pretes ESPACE — nombre de pods prêts de l'API MédiAgenda dans l'espace.
_f7l_api_pretes() {
  kube -n "$1" get pods -l 'app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api' -o json 2>/dev/null |
    jq '[.items[] | select(.metadata.deletionTimestamp == null)
      | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' 2>/dev/null || echo 0
}

# _f7l_par2 ARGS… — kubectl en lecture sur k8s-par2 (code 2 si le kubeconfig manque).
_f7l_par2() {
  [[ -r "$_f7l_par2_kc" ]] || return 2
  kubectl --kubeconfig "$_f7l_par2_kc" --request-timeout="${WB_TIMEOUT}s" "$@"
}

# --- HTTP -------------------------------------------------------------------------------------------

# _f7l_code URL [options curl] — code HTTP (vide si aucune réponse).
_f7l_code() {
  local u="$1"
  shift
  curl -s -o /dev/null -w '%{http_code}' --max-time "$((WB_TIMEOUT * 2))" "$@" "$u" 2>/dev/null || true
}

# _f7l_code_dans URL REGEX_CODES [options curl] — le code correspond à la regex (ex. '^(401|403|404)$').
_f7l_code_dans() {
  local u="$1" r="$2" c
  shift 2
  c="$(_f7l_code "$u" "$@")"
  [[ -n "$c" && "$c" =~ $r ]]
}

# _f7l_json URL — corps JSON d'une réponse 200 (anonyme).
_f7l_json() { curl -sf --max-time "$((WB_TIMEOUT * 2))" -H 'Accept: application/json' "$1" 2>/dev/null; }

# --- Prometheus -------------------------------------------------------------------------------------

# _f7l_prom_positif 'PromQL' [SOURCE=cluster|temoin] — la première valeur existe et est > 0.
_f7l_prom_positif() {
  local base v
  if [[ "${2:-cluster}" == temoin ]]; then base="${WB_F4_PROM_TEMOIN_URL:-http://mon01.par1.medisphere.internal:9090}"; else base="${WB_PROM_URL:-http://prometheus.apps.par1.medisphere.internal:9090}"; fi
  v="$(curl -sf --max-time "$((WB_TIMEOUT * 4))" -H 'Accept: application/json' --data-urlencode "query=$1" "$base/api/v1/query" 2>/dev/null |
    jq -r '.data.result[0].value[1] // empty' 2>/dev/null)" || return 1
  [[ -n "$v" ]] && awk -v x="$v" 'BEGIN { exit !(x + 0 > 0) }'
}

# --- Keycloak ---------------------------------------------------------------------------------------

# _f7l_idp — représentation du fournisseur d'identité du client (vide si illisible).
_f7l_idp() { keycloak_api "identity-provider/instances/$(_f7c_enc "$_f7l_idp")" 2>/dev/null; }

_f7l_idp_mappeurs() { keycloak_api "identity-provider/instances/$(_f7c_enc "$_f7l_idp")/mappers" 2>/dev/null; }

# _f7l_groupe_kc NOM — représentation du groupe Keycloak (premier résultat exact).
_f7l_groupe_kc() {
  keycloak_api "groups?search=$(_f7c_enc "$1")&exact=true" 2>/dev/null | jq -c --arg n "$1" '[.. | objects | select(.name? == $n)][0] // empty' 2>/dev/null
}

# --- OpenBao ----------------------------------------------------------------------------------------

# _f7l_cles_client — noms des clés transit/<client>-* (une par ligne).
_f7l_cles_client() {
  bao_api "transit/keys?list=true" 2>/dev/null | jq -r --arg p "${_f7l_client}-" '.data.keys[]? | select(startswith($p))' 2>/dev/null
}

# --- Compartiments S3 (lecture) -----------------------------------------------------------------------

# _f7l_s3_ls FICHIER_ENV URL S3_URI — liste récursive avec une identité de LECTURE (vide si absente).
_f7l_s3_ls() {
  [[ -r "$1" ]] || return 0
  (
    set -a
    # shellcheck disable=SC1090
    source "$1"
    set +a
    aws --endpoint-url "$2" s3 ls --recursive "$3" 2>/dev/null
  ) || true
}
