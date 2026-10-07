# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E39.sh — M06-E39 « Panne : NetBox en erreur » : NetBox répond sur son FQDN, l'API voit sa
# base et ses workers (donc le cache), et les services de nbx01 tournent. Lecture seule.

# shellcheck source=_m06-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-expert.sh"

title "M06-E39 — NetBox en service"
require_cmd curl jq ssh

check_http "NetBox : page de connexion (HTTPS vérifié, FQDN)" "$_m06x_netbox_url/login/" 200
_m06_e39_statut="$(netbox_api status/ 2>/dev/null || true)"
check_cmd "API : /api/status/ répond (jeton des checks)" jq -e '."netbox-version"' <<<"$_m06_e39_statut"
check_cmd "API : NetBox 4.6.x" jq -e '."netbox-version" | startswith("4.6.")' <<<"$_m06_e39_statut"
check_cmd "API : au moins un worker RQ actif (cache et files de tâches joignables)" \
  jq -e '."rq-workers-running" >= 1' <<<"$_m06_e39_statut"
_m06_e39_base() { netbox_api "virtualization/virtual-machines/?limit=1" | jq -e '.count >= 1' >/dev/null; }
check_cmd "API : la base répond (liste des VMs)" _m06_e39_base
check_ssh "nbx01 : netbox, netbox-rq, nginx, postgresql et valkey-server actifs" nbx01 \
  'for s in netbox netbox-rq nginx postgresql valkey-server; do systemctl is-active -q "$s" || exit 1; done'
check_ssh "nbx01 : aucune règle « reject » dans pg_hba.conf" nbx01 \
  '! sudo -n grep -hE "^[^#]*[[:space:]]reject([[:space:]]|$)" /etc/postgresql/*/main/pg_hba.conf'
check_cmd "panne M06-E39 close (lab/bin/break 06 39 --annuler après réparation)" _m06x_aucune_panne_active E39
