#!/usr/bin/env bash
# outils/par2/sauvegarder-config-pbs.sh — sauvegarde de la configuration de hp01 AVANT tout changement
# (F5-S03, CHG-3503, RB-353 §2). Projet plateforme/infra. À lancer EN ROOT SUR hp01.
#
# Contenu : /etc/proxmox-backup (datastores, utilisateurs, ACL, jetons, tâches, certificats), réseau
# (/etc/network/interfaces*, /etc/hosts, /etc/hostname, /etc/resolv.conf), /etc/wireguard, /etc/apt,
# chrony, nftables, liste des paquets (dpkg --get-selections), versions (proxmox-backup-manager versions).
# Ne contient PAS les données du datastore (elles ne bougent pas).
#
# ⚠️ L'archive contient des secrets (clés privées WireGuard et TLS de PBS, jetons) : mode 600 sur hp01,
# copie chiffrée hors de hp01 (age vers la clé publique de restauration, ou scp vers ~/f5/ de adm01
# chiffré par ton propre outil), jamais dans Git.
#
# Usage : sauvegarder-config-pbs.sh   → /root/f5/pbs-config-AAAAMMJJ.tar.gz (+ .sha256)
set -euo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo "à lancer en root sur hp01" >&2; exit 2; }
dest_dir=/root/f5
jour="$(date +%Y%m%d)"
archive="$dest_dir/pbs-config-$jour.tar.gz"
install -d -m 700 "$dest_dir"
[[ ! -e "$archive" ]] || { echo "$archive existe déjà : la déplacer avant d'en refaire une." >&2; exit 1; }

travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT
dpkg --get-selections >"$travail/dpkg-selections.txt"
proxmox-backup-manager versions --verbose >"$travail/versions.txt" 2>&1 || true
proxmox-backup-manager datastore list --output-format json >"$travail/datastores.json"
uname -a >"$travail/uname.txt"
ip -d addr show >"$travail/ip-addr.txt"
ip route show table all >"$travail/ip-route.txt"

chemins=(/etc/proxmox-backup /etc/network /etc/hosts /etc/hostname /etc/resolv.conf /etc/apt)
for c in /etc/wireguard /etc/chrony /etc/nftables.conf /etc/nftables.d /etc/sysctl.d; do
  [[ -e "$c" ]] && chemins+=("$c")
done

tar -czf "$archive" --absolute-names "${chemins[@]}" -C "$travail" .
sha256sum "$archive" >"$archive.sha256"

# Vérification : l'archive se relit et contient les fichiers vitaux de PBS.
for f in proxmox-backup/datastore.cfg proxmox-backup/user.cfg proxmox-backup/acl.cfg network/interfaces; do
  tar -tzf "$archive" | grep -q "$f" || { echo "ÉCHEC : $f absent de l'archive" >&2; exit 1; }
done
echo "archive : $archive ($(du -h "$archive" | cut -f1))"
cat "$archive.sha256"
echo "suite : copie CHIFFRÉE hors de hp01 (RB-353 §2), puis comparaison des empreintes."
