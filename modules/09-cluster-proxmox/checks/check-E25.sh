# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c ou sur l'hôte distant
#
# check-E25.sh — M09-E25 « Superviser le cluster »
# À lancer depuis adm01 (où vivent la sonde et sa minuterie). Lecture seule : ACL du cluster
# (pveum acl list), privilèges effectifs du jeton (GET /access/permissions avec le jeton de
# l'apprenant), unités systemd, exécutions de la sonde (qui ne fait que lire), GitLab.

# shellcheck source=_m09-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-production.sh"

title "M09-E25 — Superviser le cluster"
require_cmd jq curl systemctl
_m09p_charger

_m09_e25_env="$HOME/.config/workbook/pve-hv-supervision.env"
_m09_e25_svc=ms-verif-cluster.service
_m09_e25_tim=ms-verif-cluster.timer

title "Identité de supervision"
check_output "fichier d'accès en 600" '^[4-7]00$' stat -c '%a' "$_m09_e25_env"
check_cmd "fichier d'accès : jeton wb-supervision@pve!hv, aucune autre identité" bash -c \
  'grep -Eq "^PVE_TOKEN_ID=\"?wb-supervision@pve!hv\"?$" "$1" && [ "$(grep -c "^PVE_TOKEN_ID=" "$1")" = 1 ]' _ "$_m09_e25_env"
_m09_e25_acl() {
  local n j
  n="$(_m09p_noeud)" || return 1
  j="$(_m09p_hv "$n" 'pveum acl list --output-format json')" || return 1
  jq -e '
    [.[] | select(.ugid | startswith("wb-supervision@pve"))] as $a
    | ($a | length) == 2
      and ($a | all(.roleid == "PVEAuditor" and .path == "/"))
      and ($a | any(.ugid == "wb-supervision@pve")) and ($a | any(.ugid == "wb-supervision@pve!hv"))' >/dev/null <<<"$j"
}
check_cmd "ACL : PVEAuditor sur / pour l'utilisateur ET le jeton, rien d'autre" _m09_e25_acl

# Privilèges effectifs du jeton, lus AVEC le jeton (secret passé à curl par stdin, jamais dans ps).
_m09_e25_perms() {
  (
    set +u
    # shellcheck source=/dev/null
    source "$_m09_e25_env" >/dev/null 2>&1 || exit 1
    [[ -n "${PVE_TOKEN_ID:-}" && -n "${PVE_TOKEN_SECRET:-}" ]] || exit 1
    url="https://hv01.$_M09P_ZONE:8006/api2/json/access/permissions?path=/"
    curl -sS --fail --max-time "$WB_TIMEOUT" ${PVE_CACERT:+--cacert "$PVE_CACERT"} -K - "$url" \
      <<<"header = \"Authorization: PVEAPIToken=${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}\""
  ) 2>/dev/null
}
_m09_e25_lecture() { _m09_e25_perms | jq -e '.data["/"]["Sys.Audit"] == 1 and .data["/"]["VM.Audit"] == 1' >/dev/null; }
_m09_e25_pas_ecriture() {
  _m09_e25_perms | jq -e '.data["/"] | keys | length > 0 and all(test("\\.Audit$"))' >/dev/null
}
check_cmd "le jeton lit l'API (Sys.Audit, VM.Audit)" _m09_e25_lecture
check_cmd "le jeton n'a que des privilèges *.Audit (aucune écriture)" _m09_e25_pas_ecriture

title "Unités systemd"
check_output "service oneshot" '^Type=oneshot$' systemctl show -p Type "$_m09_e25_svc"
check_output "service lancé en admin" '^User=admin$' systemctl show -p User "$_m09_e25_svc"
check_output "service : ms-alerte@… en cas d'échec" '^OnFailure=.*ms-alerte@' systemctl show -p OnFailure "$_m09_e25_svc"
check_output "service : copie installée sous /usr/local" 'path=/usr/local/bin/ms-verif-cluster' systemctl show -p ExecStart "$_m09_e25_svc"
check_cmd "minuterie activée" systemctl is-enabled --quiet "$_m09_e25_tim"
check_cmd "minuterie active" systemctl is-active --quiet "$_m09_e25_tim"
check_output "minuterie toutes les 5 minutes" 'OnCalendar=\*-\*-\* \*:(00|0)/5(:00)?' systemctl show -p TimersCalendar "$_m09_e25_tim"

title "La sonde, maintenant"
check_cmd "configuration installée (/usr/local/etc/ms-verif-cluster.conf)" test -r /usr/local/etc/ms-verif-cluster.conf
check_cmd "le cluster est sain pour la sonde (code 0)" timeout 180 /usr/local/bin/ms-verif-cluster --quiet
check_output "un nœud de trop annoncé la fait échouer (code 1)" '^1$' \
  bash -c 'timeout 180 /usr/local/bin/ms-verif-cluster --quiet --noeuds-attendus 4 >/dev/null 2>&1; echo $?'
check_output "une option inconnue donne le code 2" '^2$' \
  bash -c 'timeout 30 /usr/local/bin/ms-verif-cluster --nimporte-quoi >/dev/null 2>&1; echo $?'
check_cmd "plateforme/outils : tests bats de ms-verif-cluster sur main" \
  _m09p_fichier_existe plateforme/outils tests/bats/ms-verif-cluster.bats
