# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E35.sh — M25-E35 « Panne : le coffre est scellé après un redémarrage » : les trois nœuds
# répondent PAR LEUR NOM (TLS vérifié contre la racine MédiSphère), un actif et deux en attente, tous
# descellés ; sur chaque nœud, l'écouteur API n'est pas limité à la boucle locale, aucune surcharge
# systemd hors medisphere.conf, limite de descripteurs effective ≥ 65536 dans le processus, certificat
# présenté qui couvre le nom du nœud et celui du service ; la VIP répond ; prévention : le rôle openbao
# purge les surcharges non déclarées, une alerte distingue « injoignable » de « scellé » ; journal
# INC-5235 ; aucune panne M25-E35 encore marquée active.
# Lecture seule : sys/health et sys/seal-status sans jeton, openssl s_client, SSH en consultation
# (systemctl show, ss, /proc/PID/limits), GitLab et Prometheus en lecture.

# shellcheck source=_m25-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-expert.sh"

title "M25-E35 — Panne : le coffre est scellé après un redémarrage"
require_cmd curl jq openssl

# --- Vu des clients : chaque nœud par son nom --------------------------------------------------------

_m25x_e35_en_service() { local c; c="$(_m25p_code "$1")"; [[ "$c" == 200 || "$c" == 429 ]]; }
_m25x_e35_un_actif() { [[ "$(_m25p_actifs | grep -c .)" == 1 ]]; }

for _m25x_e35_n in "${_M25P_NOEUDS[@]}"; do
  check_cmd "$_m25x_e35_n : répond par son nom, TLS vérifié (200 actif ou 429 en attente)" \
    _m25x_e35_en_service "$_m25x_e35_n"
  check_cmd "$_m25x_e35_n : descellé" \
    _m25p_jq "$(_m25p_scellement "$_m25x_e35_n")" '.sealed == false'
done
check_cmd "grappe : exactement un nœud actif" _m25x_e35_un_actif
check_cmd "VIP openbao.par1.medisphere.internal:8200 : nœud actif, descellé" \
  _m25p_jq "$(curl -s --max-time "$WB_TIMEOUT" "https://$_M25P_SERVICE:$_M25P_PORT/v1/sys/health" 2>/dev/null || true)" \
  '.sealed == false and .standby == false'

# _m25x_e35_certificat HÔTE — le certificat présenté sur 8200 couvre le nom du nœud ET celui du service.
_m25x_e35_certificat() {
  local nom="$1.$_M25P_DOMAINE" pem
  pem="$(openssl s_client -connect "$nom:$_M25P_PORT" -servername "$nom" </dev/null 2>/dev/null | openssl x509 2>/dev/null)" || return 1
  [[ -n "$pem" ]] || return 1
  openssl x509 -noout -checkhost "$nom" <<<"$pem" 2>/dev/null | grep -q ' does match' \
    && openssl x509 -noout -checkhost "$_M25P_SERVICE" <<<"$pem" 2>/dev/null | grep -q ' does match'
}

# --- Sur chaque nœud (consultation) ------------------------------------------------------------------

# Écoute sur 8200 : au moins une adresse qui n'est pas la boucle locale.
_M25X_E35_ECOUTE='ss -Hltn "sport = :8200" | awk "{ print \$4 }" | grep -Evq "^(127\.0\.0\.1|\[::1\]):8200$"'
# Surcharges de l'unité : medisphere.conf seule (celles du paquet, sous /usr/lib, sont admises).
_M25X_E35_SURCHARGES='for f in $(systemctl show -p DropInPaths --value openbao); do case "$f" in /usr/lib/*|*/openbao.service.d/medisphere.conf) ;; *) exit 1 ;; esac; done'
# Limite effective dans le processus en cours (pas seulement dans l'unité).
_M25X_E35_LIMITE='pid="$(systemctl show -p MainPID --value openbao)"; [ -n "$pid" ] && [ "$pid" != 0 ] && awk "/^Max open files/ { exit !(\$4 >= 65536) }" "/proc/$pid/limits"'

for _m25x_e35_n in "${_M25P_NOEUDS[@]}"; do
  check_cmd "$_m25x_e35_n : certificat présenté émis pour $_m25x_e35_n et pour $_M25P_SERVICE" \
    _m25x_e35_certificat "$_m25x_e35_n"
  check_cmd "$_m25x_e35_n : API 8200 écoutée sur le réseau (pas seulement 127.0.0.1)" \
    _m25p_ssh "$_m25x_e35_n" "$_M25X_E35_ECOUTE"
  check_cmd "$_m25x_e35_n : aucune surcharge systemd d'openbao hors medisphere.conf" \
    _m25p_ssh "$_m25x_e35_n" "$_M25X_E35_SURCHARGES"
  check_cmd "$_m25x_e35_n : limite de descripteurs du processus openbao ≥ 65536" \
    _m25p_ssh "$_m25x_e35_n" "$_M25X_E35_LIMITE"
done

# --- Prévention -------------------------------------------------------------------------------------

# Rôle openbao : une tâche supprime les fichiers non déclarés du dossier de surcharge.
_m25x_e35_role() {
  local c
  c="$(_m25p_fichier "$_M25P_ANSIBLE" roles/openbao/tasks/configuration.yml)" || return 1
  grep -q 'ansible.builtin.find' <<<"$c" && grep -q 'openbao.service.d' <<<"$c" && grep -q 'state: absent' <<<"$c"
}
check_cmd "plateforme/ansible : le rôle openbao retire les surcharges systemd non déclarées" _m25x_e35_role

# Alerte : un nœud injoignable (up == 0) a sa PROPRE alerte, distincte de « scellé ».
_m25x_e35_alerte() {
  prom_api rules 2>/dev/null | jq -e '[.data.groups[]?.rules[]? | select(.type == "alerting")
      | select((.query | test("up\\{[^}]*job=\"openbao\"")) and ((.query | test("vault_core_unsealed")) | not))]
      | length > 0' >/dev/null 2>&1
}
check_cmd "Prometheus : alerte « nœud OpenBao injoignable » distincte de OpenBaoScelle" _m25x_e35_alerte

check_cmd "journal de diagnostic INC-5235 sur main (plateforme/medisphere)" _m25x_journal INC-5235
check_cmd "aucune panne M25-E35 encore marquée active sur ce poste" _m25p_marqueur_absent E35
