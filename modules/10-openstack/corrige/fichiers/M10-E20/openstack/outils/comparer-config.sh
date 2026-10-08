#!/usr/bin/env bash
# comparer-config.sh — compare, sur un nœud, la configuration GÉNÉRÉE par Kolla (après
# « kolla-ansible genconfig ») à celle que le conteneur utilise encore (M10-E20).
# Usage : outils/comparer-config.sh <hôte> <conteneur> <fichier-généré> <fichier-dans-le-conteneur>
#   ex. : outils/comparer-config.sh oscmp02 nova_compute /etc/kolla/nova-compute/nova.conf /etc/nova/nova.conf
# Lecture seule. Les lignes de secrets (password, transport_url, connection) sont masquées.
set -euo pipefail
[[ $# -eq 4 ]] || { sed -n '4,5p' "$0" >&2; exit 2; }
hote="$1"; conteneur="$2"; genere="$3"; dedans="$4"

masquer() { sed -E 's/^((.*password|transport_url|connection|.*secret.*|memcache_secret_key)[[:space:]]*=).*/\1 ***/I'; }

# shellcheck disable=SC2029  # les chemins sont évalués sur le nœud, volontairement
diff -u \
  <(ssh -o BatchMode=yes "$hote" "sudo docker exec $conteneur cat $dedans" | masquer) \
  <(ssh -o BatchMode=yes "$hote" "sudo cat $genere" | masquer) \
  && echo "aucune différence : le prochain reconfigure ne redémarrera pas $conteneur sur $hote"
