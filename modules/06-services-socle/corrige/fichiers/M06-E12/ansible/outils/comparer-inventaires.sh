#!/usr/bin/env bash
# comparer-inventaires.sh — NetBox (intention) et Proxmox (réalité) décrivent-ils le même socle ?
# (M06-E12)
#
# Usage (racine du projet, accès chargés : pve-ansible.env et netbox-ansible.env) :
#   outils/comparer-inventaires.sh
# Compare, pour les groupes socle et role_*, la liste des hôtes de chaque inventaire, puis
# l'adresse de connexion (ansible_host) de chaque hôte du socle. Les variables propres à
# chaque plugin (proxmox_*, custom_fields…) sont ignorées.
# Codes retour : 0 identiques, 1 différences (affichées), 2 inventaire illisible.
set -euo pipefail

[[ -f inventories/lab/netbox.yml && -f inventories/lab/proxmox.yml ]] \
  || { echo "À lancer depuis la racine du projet ansible" >&2; exit 2; }

resume() {
  # Groupes socle et role_* : {groupe: [hôtes triés]} ; puis {hôte: ansible_host}.
  # ansible-core ≥ 2.19 peut marquer certaines valeurs {"__ansible_unsafe": …} dans --list :
  # « brut » les ramène à leur valeur pour comparer des sources différentes.
  uv run ansible-inventory -i "$1" --list 2>/dev/null | jq -S '
    def brut: if type == "object" and has("__ansible_unsafe") then .__ansible_unsafe else . end;
    . as $inv
    | {
        groupes: (with_entries(select(.key == "socle" or (.key | startswith("role_"))))
                  | map_values((.hosts // []) | sort)),
        adresses: ([($inv.socle.hosts // [])[] as $h | {($h): ($inv._meta.hostvars[$h].ansible_host | brut)}] | add // {})
      }'
}

nb="$(resume inventories/lab/netbox.yml)" || { echo "inventaire NetBox illisible" >&2; exit 2; }
pve="$(resume inventories/lab/proxmox.yml)" || { echo "inventaire Proxmox illisible" >&2; exit 2; }
if [[ "$(jq '.groupes.socle | length' <<<"$nb")" -eq 0 ]]; then
  echo "inventaire NetBox vide (jeton ? NetBox joignable ? étiquette socle ?)" >&2
  exit 2
fi

if diff -u --label proxmox <(printf '%s\n' "$pve") --label netbox <(printf '%s\n' "$nb"); then
  echo "OK : NetBox et Proxmox décrivent le même socle ($(jq '.groupes.socle | length' <<<"$nb") hôtes)."
  exit 0
fi
echo "DIFFÉRENCES : corrige la source fautive (NetBox = intention, Proxmox = réalité), jamais les deux." >&2
exit 1
