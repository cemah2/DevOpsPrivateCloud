# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E19.sh — M10-E19 : Exploiter le calcul : migrer, évacuer, désactiver
# À lancer depuis adm01, oscmp02 redémarré. Lecture seule : API OpenStack, virsh sur oscmp02.

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E19 — Exploiter le calcul : migrer, évacuer, désactiver"
require_cmd openstack jq

_m10o_mig="$(_m10o_os --os-compute-api-version 2.80 server migration list -f json || echo '[]')"
check_cmd "historique : au moins une migration à chaud terminée" \
  jq -e 'map(tostring | select(test("live-migration") and test("\"completed\""))) | length > 0' <<<"$_m10o_mig"
check_cmd "historique : au moins une migration à froid confirmée" \
  jq -e 'map(tostring | select(test("\"migration\"") and test("\"confirmed\""))) | length > 0' <<<"$_m10o_mig"

_m10o_svc="$(_m10o_os compute service list --service nova-compute -f json || echo '[]')"
check_cmd "les deux services nova-compute sont enabled et up" \
  jq -e 'length == 2 and all(.Status == "enabled" and .State == "up")' <<<"$_m10o_svc"

_m10o_ev="$(_m10o_serveur e19-evac)"
check_cmd "e19-evac : ACTIVE sur oscmp01" \
  jq -e '.status == "ACTIVE" and (.["OS-EXT-SRV-ATTR:host"] // "" | startswith("oscmp01"))' <<<"$_m10o_ev"
_m10o_nom="$(jq -r '.["OS-EXT-SRV-ATTR:instance_name"] // empty' <<<"$_m10o_ev" 2>/dev/null || true)"
if [[ -n "$_m10o_nom" ]]; then
  check_ssh "oscmp02 : libvirt n'héberge plus e19-evac ($_m10o_nom)" oscmp02 \
    "sudo -n docker exec nova_libvirt virsh list --all --name >/dev/null && ! sudo -n docker exec nova_libvirt virsh list --all --name | grep -qx '$_m10o_nom'"
else
  _ko "e19-evac : introuvable"
fi

_m10o_b="$(_m10o_serveur e19-b)"
check_cmd "e19-b : en m1.moyen, ACTIVE (redimensionnement confirmé)" \
  jq -e '.status == "ACTIVE" and (.flavor | tostring | test("m1\\.moyen"))' <<<"$_m10o_b"
