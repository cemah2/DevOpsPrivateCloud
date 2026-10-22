# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # motifs et filtres entre apostrophes
#
# check-E04.sh — M22-E04 : LogQL : filtres, analyseurs et métriques de journaux
# À lancer depuis adm01. Lecture seule : requetes/E04.logql sur main de plateforme/observabilite
# (GitLab), puis chaque requête jouée contre Loki (GET query_range, 1 h) dans son locataire.
# Format du fichier : une requête par ligne ; « # locataire: X » vaut pour les lignes suivantes.

# shellcheck source=_m22-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-decouverte.sh"

title "M22-E04 — LogQL : filtres, analyseurs et métriques de journaux"
require_cmd jq curl

# --- 1. logcli sur adm01 -------------------------------------------------------------------------------
check_output "logcli installé sur adm01, même version que Loki (3.7)" '3\.7\.[0-9]+' logcli --version
check_cmd "logcli : lien /usr/local/bin/logcli posé par le rôle outils_k8s" test -L /usr/local/bin/logcli

# --- 2. Le fichier de requêtes ---------------------------------------------------------------------------
_m22d_e04_f="$(_m22d_contenu_main "$_M22D_P_OBS" requetes/E04.logql)"
check_cmd "plateforme/observabilite (main) : requetes/E04.logql" bash -c '[[ -n "$1" ]]' _ "$_m22d_e04_f"
_m22d_e04_req="$(grep -Ev '^[[:space:]]*(#|$)' <<<"$_m22d_e04_f" || true)"
check_cmd "au moins 10 requêtes" bash -c '(( $(grep -c . <<<"$1") >= 10 ))' _ "$_m22d_e04_req"
for _m22d_e04_m in '| json' '| logfmt' '| pattern' 'line_format' 'count_over_time' 'rate(' 'unwrap' 'quantile_over_time' '|=' '!='; do
  check_cmd "le fichier utilise « $_m22d_e04_m »" grep -qF -- "$_m22d_e04_m" <<<"$_m22d_e04_req"
done
check_cmd "le fichier interroge au moins deux locataires (plateforme, mediagenda)" bash -c \
  '(( $(grep -Eo "^#[[:space:]]*locataire:[[:space:]]*[a-z]+" <<<"$1" | sort -u | wc -l) >= 2 ))' _ "$_m22d_e04_f"

# --- 3. Chaque requête s'exécute et renvoie des données ----------------------------------------------
_m22d_e04_loc=plateforme
_m22d_e04_n=0
while IFS= read -r _m22d_e04_l; do
  if [[ "$_m22d_e04_l" =~ ^#[[:space:]]*locataire:[[:space:]]*([a-z0-9-]+) ]]; then
    _m22d_e04_loc="${BASH_REMATCH[1]}"
    continue
  fi
  [[ "$_m22d_e04_l" =~ ^[[:space:]]*(#|$) ]] && continue
  _m22d_e04_n=$((_m22d_e04_n + 1))
  _m22d_e04_r="$(_m22d_requete "$_m22d_e04_l" "$_m22d_e04_loc" 1h)"
  _m22d_e04_err="$(jq -r 'if .status == "success" then "" else (.error // "réponse vide") end' <<<"${_m22d_e04_r:-{\}}" 2>/dev/null || echo "réponse illisible")"
  check_cmd "requête $_m22d_e04_n ($_m22d_e04_loc) : s'exécute et renvoie des données sur 1 h${_m22d_e04_err:+ — $_m22d_e04_err}" \
    _m22d_json "$_m22d_e04_r" '.status == "success" and (.data.result | length) > 0'
done <<<"$_m22d_e04_f"
if (( _m22d_e04_n == 0 )); then
  _ko "aucune requête lue dans requetes/E04.logql"
fi
