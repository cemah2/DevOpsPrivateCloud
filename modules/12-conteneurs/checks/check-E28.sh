# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E28.sh — M12-E28 « Superviser les conteneurs »
# À lancer depuis adm01 (où vivent la sonde et son timer). Lecture seule : métriques HTTP du démon
# de ctr01, conteneurs de ctr01 (docker ps), compte supervision (id, essai par sa clé : la commande
# forcée ne fait que lire), unités systemd, une exécution de la sonde (lecture seule), journal,
# fichiers sur main (API GitLab).

# shellcheck source=_m12-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-production.sh"

title "M12-E28 — Superviser les conteneurs"
require_cmd curl jq systemctl ssh

title "Moteur (ctr01)"
check_output "métriques du démon sur ctr01:9323" '^engine_daemon_engine_info' \
  curl -s --max-time "$WB_TIMEOUT" "http://ctr01.$_M12P_DOMAINE:9323/metrics"
check_output "aucun conteneur cAdvisor sur ctr01" '^0$' \
  bash -c 'grep -ci cadvisor <<<"$1" || true' _ "$(_m12p_docker ctr01 "ps -a --format '{{.Image}} {{.Names}}'")"

title "Accès de supervision"
check_ssh_output "ctr01 : le compte supervision existe et n'est pas dans le groupe docker" ctr01 '^OK$' \
  "id supervision >/dev/null 2>&1 && ! id -nG supervision | tr ' ' '\n' | grep -qx docker && echo OK"
_m12_e28_cle="$HOME/.config/workbook/ssh-supervision-conteneurs"
check_cmd "clé de supervision en 600 sur adm01" bash -c '[[ "$(stat -c %a "$1" 2>/dev/null)" == 600 ]]' _ "$_m12_e28_cle"
_m12_e28_a="$(ssh -n -o BatchMode=yes -o ConnectTimeout="$WB_TIMEOUT" -i "$_m12_e28_cle" "supervision@ctr01.$_M12P_DOMAINE" etat 2>/dev/null | tail -n 1 || true)"
_m12_e28_b="$(ssh -n -o BatchMode=yes -o ConnectTimeout="$WB_TIMEOUT" -i "$_m12_e28_cle" "supervision@ctr01.$_M12P_DOMAINE" 'echo intrus' 2>/dev/null || true)"
check_output "la clé ne donne que l'état des conteneurs (ligne de fin)" '^fin [0-9]+$' echo "$_m12_e28_a"
# Une autre commande demandée : la commande forcée répond quand même (ligne de fin), sans l'exécuter.
check_cmd "une autre commande demandée par ssh n'est pas exécutée" \
  bash -c 'grep -Eq "^fin [0-9]+$" <<<"$1" && ! grep -qx intrus <<<"$1"' _ "$_m12_e28_b"

title "Sonde sur adm01"
check_cmd "sonde installée sous /usr/local/bin" test -x /usr/local/bin/ms-verif-conteneurs
check_cmd "configuration installée sous /usr/local/etc" test -r /usr/local/etc/ms-verif-conteneurs.conf
check_cmd "la sonde conclut que tout va bien (code 0)" timeout 120 /usr/local/bin/ms-verif-conteneurs --quiet
check_output "une option inconnue donne le code 2" '^2$' \
  bash -c 'timeout 30 /usr/local/bin/ms-verif-conteneurs --nimporte-quoi >/dev/null 2>&1; echo $?'
check_output "le service est de type oneshot" '^Type=oneshot$' systemctl show -p Type ms-verif-conteneurs.service
check_output "le service déclenche ms-alerte@… en cas d'échec" '^OnFailure=.*ms-alerte@' \
  systemctl show -p OnFailure ms-verif-conteneurs.service
check_cmd "le timer est actif" systemctl is-active --quiet ms-verif-conteneurs.timer
check_output "le timer passe toutes les 5 minutes" 'OnCalendar=\*-\*-\* \*:(00|0)/5(:00)?' \
  systemctl show -p TimersCalendar ms-verif-conteneurs.timer
check_output "une alerte de la sonde a été reçue (30 jours)" '(ÉCHEC|ECHEC) ms-verif-conteneurs' \
  sudo -n journalctl -q --no-pager --since -30d -t ms-alerte -o cat

title "Dans le code"
check_cmd "plateforme/outils : tests bats de ms-verif-conteneurs sur main" \
  _m12p_arbre_contient plateforme/outils '^tests/bats/ms-verif-conteneurs\.bats$'
check_cmd "plateforme/outils : dernier pipeline de main réussi" _m12p_pipeline_ok plateforme/outils
check_cmd "plateforme/ansible : rôle supervision_conteneurs sur main" \
  _m12p_arbre_contient plateforme/ansible '^roles/supervision_conteneurs/'
check_cmd "docs/conteneurs/supervision.md sur main" \
  _m12p_doc_main plateforme/medisphere docs/conteneurs/supervision.md 'ms-verif-conteneurs' 'prometheus'
