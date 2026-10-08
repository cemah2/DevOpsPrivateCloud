#!/usr/bin/env bash
# attribution-audit-heritee.sh — M10-E23 (SEC-1133) : « reader » HÉRITÉ du groupe equipe-securite
# sur le domaine medisphere (s'applique à tous ses projets, présents et futurs). Idempotent.
# Complète playbooks/identite.yml, dont le module role_assignment ne gère pas l'héritage.
# Usage : OS_CLOUD=medisphere-admin outils/attribution-audit-heritee.sh
set -euo pipefail
: "${OS_CLOUD:?définis OS_CLOUD (ex. medisphere-admin)}"
dom=medisphere

openstack role add --group equipe-securite --group-domain "$dom" --domain "$dom" --inherited reader
echo "Attributions de equipe-securite :"
openstack role assignment list --names --group equipe-securite --group-domain "$dom"
echo "Effet sur sophie.laurent (projets du domaine) :"
openstack role assignment list --names --effective --user sophie.laurent --user-domain "$dom"
