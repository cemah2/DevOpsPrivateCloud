#!/usr/bin/env bash
# vider-noeud-calcul.sh — M10-E29 (RB-102) : vide un nœud de calcul par migrations à chaud.
# À lancer depuis adm01 avec le cloud d'administration. Ne retire RIEN d'OpenStack : il désactive
# le service (avec raison), migre, attend, vérifie. Le retrait (Kolla, inventaire, services,
# agents) est la suite de RB-102.
#
# Usage : vider-noeud-calcul.sh [-n] HÔTE "RAISON (référence de ticket)"
#   -n : à blanc — affiche le plan (instances, capacité restante) sans rien faire.
# Codes : 0 nœud vide ; 1 au moins une instance encore présente ; 2 usage.
set -euo pipefail

CLOUD="${CLOUD:-medisphere-admin}"
os() { openstack --os-cloud "$CLOUD" "$@"; }

blanc=0
if [[ "${1:-}" == "-n" ]]; then blanc=1; shift; fi
[[ $# -eq 2 && -n "$2" ]] || { echo "Usage : $0 [-n] HÔTE \"RAISON\"" >&2; exit 2; }
hote="$1" raison="$2"

mapfile -t instances < <(os server list --all-projects --host "$hote" -f value -c ID)
echo "$hote : ${#instances[@]} instance(s)"
for i in "${instances[@]}"; do
  os server show "$i" -f value -c name -c status -c flavor | paste -sd' ' | sed 's/^/  /'
done

# Capacité des AUTRES calculs : usage et inventaire Placement (greffon osc-placement).
echo "Capacité des autres calculs (Placement) :"
while read -r rp nom; do
  [[ "$nom" == "$hote" ]] && continue
  inv="$(os resource provider inventory list "$rp" -f json)"
  use="$(os resource provider usage show "$rp" -f json)"
  jq -rn --arg n "$nom" --argjson inv "$inv" --argjson use "$use" '
    def cap(c): ($inv[] | select(.resource_class == c) | ((.total - .reserved) * .allocation_ratio));
    def usage(c): ($use[] | select(.resource_class == c) | .usage);
    "  \($n) : VCPU \(usage("VCPU"))/\(cap("VCPU")) ; MEMORY_MB \(usage("MEMORY_MB"))/\(cap("MEMORY_MB"))"'
done < <(os resource provider list -f value -c uuid -c name)

if ((blanc)); then echo "(à blanc : rien n'a été fait)"; exit 0; fi

echo "Désactivation de nova-compute sur $hote : $raison"
os compute service set --disable --disable-reason "$raison" "$hote" nova-compute

for i in "${instances[@]}"; do
  echo "migration à chaud de $i…"
  # Pas d'hôte cible : l'ordonnanceur choisit (et vérifie la capacité).
  os server migrate --live-migration --wait "$i" || echo "  ÉCHEC pour $i : lire nova-compute.log de $hote (source)" >&2
done

restant="$(os server list --all-projects --host "$hote" -f value -c ID | wc -l)"
if ((restant == 0)); then
  echo "$hote est vide."
else
  echo "$hote porte encore $restant instance(s) : NE PAS retirer le nœud." >&2
  exit 1
fi
