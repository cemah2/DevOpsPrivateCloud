#!/usr/bin/env bash
# dispenser-comptes-service.sh — M10-E27 : dispense les comptes de SERVICE du verrouillage de
# Keystone, AVANT d'activer [security_compliance] lockout_failure_attempts. À lancer depuis adm01.
# Idempotent. Un compte de service verrouillé (mot de passe faux après une rotation ratée, ou
# tentatives d'un tiers) = panne du service entier pendant lockout_duration.
set -euo pipefail

CLOUD="${CLOUD:-medisphere-admin}"
os() { openstack --os-cloud "$CLOUD" "$@"; }

# Comptes du domaine Default créés par Kolla pour les services activés au M10, plus les comptes de
# service de MédiSphère : OpenTofu (E15) et la sonde (E26).
# Liste à revoir à chaque service activé : « openstack user list --domain Default ».
COMPTES=(nova neutron glance cinder placement heat octavia svc-tofu svc-supervision)

for c in "${COMPTES[@]}"; do
  if os user show "$c" --domain Default >/dev/null 2>&1; then
    os user set --ignore-lockout-failure-attempts --domain Default "$c"
    printf 'dispensé : %s\n' "$c"
  else
    printf 'absent   : %s (service non activé ?)\n' "$c" >&2
  fi
done

echo
echo "Comptes du domaine Default NON dispensés (à examiner : humain ou service oublié ?) :"
os user list --domain Default -f value -c Name | while read -r u; do
  if ! os user show "$u" --domain Default -f json | jq -e '.options.ignore_lockout_failure_attempts == true' >/dev/null; then
    printf '  %s\n' "$u"
  fi
done
