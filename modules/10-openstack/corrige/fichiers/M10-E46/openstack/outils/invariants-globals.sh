#!/usr/bin/env bash
# invariants-globals.sh — M10-E46 : vérifie que la configuration Kolla respecte les décisions
# figées de MédiSphère (PLAN §4.9, ADR-0100, SEC-1153). Lecture seule, sans accès réseau.
# Fusionne globals.yml puis globals.d/*.yml (ordre alphabétique, comme kolla-ansible).
set -euo pipefail

racine="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$racine/etc/kolla"

python3 - globals.yml globals.d/*.yml <<'PY'
import sys, yaml
conf = {}
for f in sys.argv[1:]:
    with open(f) as fh:
        conf.update(yaml.safe_load(fh) or {})

def norm(v):
    return {"true": "yes", "false": "no"}.get(str(v).lower(), str(v)) if isinstance(v, (bool, str)) else v

attendu = {
    "kolla_base_distro": "debian",
    "neutron_plugin_agent": "ovn",
    "kolla_internal_vip_address": "10.10.50.200",
    "kolla_external_vip_address": "10.10.50.201",
    "kolla_external_fqdn": "openstack.par1.medisphere.internal",
    "kolla_internal_fqdn": "openstack-int.par1.medisphere.internal",
    "keepalived_virtual_router_id": "150",
    "enable_cinder": "yes",
    "enable_cinder_backup": "yes",
    "enable_octavia": "yes",
    "octavia_provider_drivers": "ovn:OVN provider",
    "glance_backend_ceph": "yes",
    "cinder_backend_ceph": "yes",
    "nova_backend_ceph": "yes",
    "kolla_enable_tls_external": "yes",
    "kolla_enable_tls_internal": "yes",
    "enable_mariabackup": "yes",
}
ecarts = [f"{k} : attendu « {v} », trouvé « {norm(conf.get(k, '(absent)'))} »"
          for k, v in attendu.items() if str(norm(conf.get(k, "(absent)"))) != v]
for e in ecarts:
    print("ÉCART", e)
print(f"{len(attendu) - len(ecarts)}/{len(attendu)} invariants respectés")
sys.exit(1 if ecarts else 0)
PY
