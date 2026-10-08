# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E28.sh — M07-E28 « HAProxy en production »
# Lecture seule : requêtes HTTPS (GET/HEAD) depuis adm01 et runner01, lb01/lb02 (admin + sudo -n :
# configuration, « show stat » sur le socket d'API, journal), API GitLab.

# shellcheck source=_m07-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-production.sh"

title "M07-E28 — HAProxy en production"
require_cmd curl openssl jq ssh
_m07p_charger_adresses lb01 lb02

title "Points d'entrée publiés"
check_cmd "VIP 10.10.70.200 portée par un seul répartiteur" _m07p_vip_unique 10.10.70.200 lb01 lb02
check_output "GitLab par son nom publié (TLS vérifié) : 200" '^200$' _m07p_code "https://gitlab.$_M07P_ZONE/users/sign_in"
check_output "NetBox par son nom publié (TLS vérifié) : 200" '^200$' _m07p_code "https://netbox.$_M07P_ZONE/login/"
check_output "HSTS sur GitLab (au moins 6 mois)" 'max-age=(1[5-9][0-9]{6}|[2-9][0-9]{7}|[0-9]{9,})' \
  _m07p_entete "https://gitlab.$_M07P_ZONE/users/sign_in" Strict-Transport-Security
check_output "HSTS sur NetBox" 'max-age=[0-9]+' _m07p_entete "https://netbox.$_M07P_ZONE/login/" Strict-Transport-Security
check_output "HTTP redirigé vers HTTPS" '^30[18]$' \
  bash -c 'curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://netbox.par1.medisphere.internal/login/" || true'

title "Configuration des répartiteurs"
for _m07_h in lb01 lb02; do
  check_ssh "$_m07_h : TLS 1.2 minimum et suites fixées, contrôles applicatifs en TLS vérifié avec SNI" "$_m07_h" '
    c=$(sudo -n cat /etc/haproxy/haproxy.cfg) || exit 1
    grep -Eq "ssl-default-bind-options .*ssl-min-ver TLSv1\.2" <<<"$c" &&
    grep -Eq "^[[:space:]]*ssl-default-bind-ciphers[[:space:]]" <<<"$c" &&
    grep -Eq "^[[:space:]]*http-check send .*uri /-/readiness" <<<"$c" &&
    grep -Eq "^[[:space:]]*http-check send .*uri /login/" <<<"$c" &&
    [ "$(grep -E "^[[:space:]]*server " <<<"$c" | grep "verify required" | grep -c "check-sni")" -ge 2 ]'
  check_ssh "$_m07_h : erreurs des vraies requêtes observées (observe layer7)" "$_m07_h" \
    '[ "$(sudo -n grep -Ec "^[[:space:]]*server .*observe layer7" /etc/haproxy/haproxy.cfg)" -ge 2 ]'
  check_ssh "$_m07_h : aucun mot de passe en clair (insecure-password)" "$_m07_h" \
    '! sudo -n grep -q "insecure-password" /etc/haproxy/haproxy.cfg && sudo -n grep -Eq "^[[:space:]]*user .* password [$]" /etc/haproxy/haproxy.cfg'
  check_ssh "$_m07_h : identifiant unique de requête transmis (X-Request-ID) et journalisé" "$_m07_h" \
    'c=$(sudo -n cat /etc/haproxy/haproxy.cfg); grep -q "unique-id-format" <<<"$c" && grep -q "unique-id-header X-Request-ID" <<<"$c" && grep -q "%ID" <<<"$c"'
  check_ssh_output "$_m07_h : socket d'API d'exécution en 660" "$_m07_h" '^660 ' \
    'sudo -n stat -c "%a %U %G" /run/haproxy/admin.sock'
  check_ssh "$_m07_h : sockets d'écoute transmis au rechargement (expose-fd listeners)" "$_m07_h" \
    'sudo -n grep -Eq "^[[:space:]]*stats socket /run/haproxy/admin\.sock .*expose-fd listeners" /etc/haproxy/haproxy.cfg'
  check_cmd "$_m07_h : serveur git01 UP" _m07p_serveur_up "$_m07_h" be_gitlab git01
  check_cmd "$_m07_h : serveur nbx01 UP" _m07p_serveur_up "$_m07_h" be_netbox nbx01
done
# _m07_conf_identiques — même configuration au nom et à l'adresse propre près.
_m07_conf_identiques() {
  local a b
  a="$(remote lb01 'sudo -n cat /etc/haproxy/haproxy.cfg' 2>/dev/null | sed -e 's/lb0[12]/lbXX/g' -e 's/10\.10\.70\.1[01]\b/ADRESSE/g')" || return 1
  b="$(remote lb02 'sudo -n cat /etc/haproxy/haproxy.cfg' 2>/dev/null | sed -e 's/lb0[12]/lbXX/g' -e 's/10\.10\.70\.1[01]\b/ADRESSE/g')" || return 1
  [[ -n "$a" && "$a" == "$b" ]]
}
check_cmd "lb01 et lb02 : même configuration (au nom et à l'adresse propre près)" _m07_conf_identiques
# Une requête de l'exercice vient de passer (contrôle ci-dessus) : elle doit être dans le journal.
_m07_lb_actif="$(_m07p_porteurs 10.10.70.200 lb01 lb02 | head -n 1)"
check_ssh_output "${_m07_lb_actif:-lb01} (actif) : journal HAProxy (systemd) avec identifiant de requête" "${_m07_lb_actif:-lb01}" \
  ' id=[0-9A-F]+:' 'sudo -n journalctl -u haproxy --since -15min --no-pager -o cat | tail -n 50'

title "Statistiques et métriques"
# _m07_stats_refuse_runner01 FQDN — depuis runner01, la page ne répond ni 200 ni 401 (refus ou
# filtrage). Échoue si runner01 ne répond pas (sinon : faux positif).
_m07_stats_refuse_runner01() {
  local c
  remote runner01 true >/dev/null 2>&1 || return 1
  c="$(remote runner01 "curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://$1:8404/stats" 2>/dev/null)" || true
  [[ "$c" != 200 && "$c" != 401 ]]
}
for _m07_h in lb01 lb02; do
  check_output "$_m07_h:8404/stats sans identifiants depuis adm01 : 401" '^401$' _m07p_code "https://$_m07_h.$_M07P_ZONE:8404/stats"
  check_cmd "$_m07_h:8404 refusé depuis runner01 (hors MGMT)" _m07_stats_refuse_runner01 "$_m07_h.$_M07P_ZONE"
done
_m07_env="$HOME/.config/workbook/haproxy-stats.env"
if [[ -r "$_m07_env" ]]; then
  # Identifiants lus dans un sous-shell, passés à curl par l'entrée standard (jamais dans « ps »).
  _m07_metriques() {
    (
      set +u
      # shellcheck source=/dev/null
      source "$_m07_env" >/dev/null 2>&1 || exit 1
      curl -s --max-time 10 --cacert "$_M07P_RACINE" -K - "https://lb01.$_M07P_ZONE:8404/metrics" \
        <<<"user = \"${HAPROXY_STATS_USER}:${HAPROXY_STATS_PASSWORD}\""
    ) 2>/dev/null | grep -q '^haproxy_process_'
  }
  check_cmd "/metrics (format Prometheus) servi au compte de supervision" _m07_metriques
  check_output "identifiants des statistiques en 600" '^[4-7]00$' stat -c '%a' "$_m07_env"
else
  skip "/metrics avec le compte de supervision" "$_m07_env absent"
fi

title "Documentation"
check_cmd "plateforme/medisphere : RB-070 sur main" _m07p_doc_main docs/socle/runbooks RB-070
