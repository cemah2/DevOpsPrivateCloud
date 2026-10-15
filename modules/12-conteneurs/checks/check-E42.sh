# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# check-E42.sh — M12-E42 « Panne : le pipeline ne publie plus l'image » : le registre de travail de
# ctr01 présente un certificat de la PKI MédiSphère et exige une authentification ; runner02 est en
# ligne, sans mode privilégié ni politique de tirage « never » seule ; le dernier pipeline de main de
# mediagenda/api a réussi APRÈS l'injection de la panne (si elle est encore marquée active), job de
# publication compris. Lecture seule (openssl s_client, curl, API GitLab en GET, lecture de
# config.toml par sudo).

# shellcheck source=_m12-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-expert.sh"

title "M12-E42 — Le pipeline publie de nouveau l'image"
require_cmd jq curl openssl ssh

_m12_e42_racine="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_m12_e42_reg="$_m12x_nom01:5000"
_m12_e42_projet="${WB_M12_PROJET_IMAGE:-mediagenda%2Fapi}"

_m12_e42_tls() {
  timeout 10 openssl s_client -connect "$_m12_e42_reg" -servername "$_m12x_nom01" -CAfile "$_m12_e42_racine" \
    -verify_return_error </dev/null >/dev/null 2>&1
}
_m12_e42_valide() {
  timeout 10 openssl s_client -connect "$_m12_e42_reg" -servername "$_m12x_nom01" </dev/null 2>/dev/null \
    | openssl x509 -noout -checkend $((7 * 86400)) >/dev/null 2>&1
}
check_cmd "registre : certificat signé par la PKI MédiSphère (chaîne vérifiée)" _m12_e42_tls
check_cmd "registre : certificat valide encore au moins 7 jours" _m12_e42_valide
check_http "registre : /v2/ exige une authentification (401 sans identifiants)" \
  "https://$_m12_e42_reg/v2/" 401 --cacert "$_m12_e42_racine"

if _m12x_joignable "$_m12x_runner02"; then
  _m12_e42_conf="$(_m12x_root "$_m12x_runner02" <<<'cat /etc/gitlab-runner/config.toml')" || true
  check_cmd "runner02 : config.toml lisible" test -n "$_m12_e42_conf"
  check_cmd "runner02 : aucun runner en mode privilégié" \
    bash -c '! grep -Eq "^[[:space:]]*privileged[[:space:]]*=[[:space:]]*true" <<<"$1"' _ "$_m12_e42_conf"
  check_cmd "runner02 : pas de politique de tirage « never » seule" \
    bash -c '! grep -Eq "^[[:space:]]*pull_policy[[:space:]]*=[[:space:]]*\[[[:space:]]*\"never\"[[:space:]]*\]" <<<"$1"' _ "$_m12_e42_conf"
  check_ssh "runner02 : service gitlab-runner actif" "$_m12x_runner02" 'systemctl is-active -q gitlab-runner'
else
  skip "runner02" "$_m12x_runner02 ne répond pas en SSH (avec sudo)"
fi

_m12_e42_runner_en_ligne() {
  gitlab_api "runners/all?tag_list=docker&per_page=100" \
    | jq -e '[.[] | select(.online == true or .status == "online")] | length >= 1' >/dev/null
}
check_cmd "GitLab : au moins un runner d'étiquette docker en ligne" _m12_e42_runner_en_ligne

_m12_e42_debut="$(_m12x_marqueur_date E42)"
_m12_e42_pipeline() {
  local p
  p="$(gitlab_api "projects/$_m12_e42_projet/pipelines?ref=main&per_page=1&order_by=id&sort=desc")" || return 1
  jq -e --arg d "${_m12_e42_debut:-0}" '
    .[0].status == "success" and
    (($d | tonumber) == 0 or ((.[0].updated_at | sub("\\.[0-9]+"; "") | sub("Z$"; "") | strptime("%Y-%m-%dT%H:%M:%S") | mktime) > ($d | tonumber)))' \
    >/dev/null <<<"$p"
}
if [[ -n "$_m12_e42_debut" ]]; then
  check_cmd "mediagenda/api : dernier pipeline de main réussi, terminé après l'injection de la panne" _m12_e42_pipeline
else
  check_cmd "mediagenda/api : dernier pipeline de main réussi" _m12_e42_pipeline
fi
_m12_e42_publication() {
  local id
  id="$(gitlab_api "projects/$_m12_e42_projet/pipelines?ref=main&per_page=1&order_by=id&sort=desc" | jq -r '.[0].id')" || return 1
  gitlab_api "projects/$_m12_e42_projet/pipelines/$id/jobs?per_page=100" \
    | jq -e '[.[] | select((.name | test("image|constru|build|publi|push"; "i")) and .status == "success")] | length >= 1' >/dev/null
}
check_cmd "mediagenda/api : job de construction et de publication réussi dans ce pipeline" _m12_e42_publication
check_cmd "panne M12-E42 close (lab/bin/break 12 42 --annuler après réparation)" _m12x_aucune_panne_active E42
