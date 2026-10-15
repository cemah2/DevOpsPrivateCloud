#!/usr/bin/env bash
# k3s/outils/gestion-sauvegarde.sh — sauvegarde à froid du cluster de gestion k3s01 (SQLite) (M18-E14).
# Usage (depuis adm01) : k3s/outils/gestion-sauvegarde.sh [HÔTE]     (défaut : k3s01)
# Ce que fait le script :
#   1. arrête k3s sur l'hôte (les conteneurs continuent : KillMode=process ; l'API et les contrôleurs,
#      donc Cluster API, sont interrompus quelques dizaines de secondes) ;
#   2. archive server/db, server/token, server/cred et server/tls (la PKI est aussi dans la base, chiffrée
#      par le jeton : les fichiers servent à reconstruire sans redémarrer depuis la base) ;
#   3. redémarre k3s, attend /readyz ;
#   4. chiffre l'archive pour le destinataire age MédiSphère et l'envoie dans s3://etcd-m18/gestion/.
# L'archive en clair ne quitte jamais k3s01 ; elle y est effacée à la fin.
set -euo pipefail

hote="${1:-k3s01}"
racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dest="$racine/outils/age-sauvegardes-m18.pub"
s3env="$HOME/.config/workbook/s3-etcd-m18.env"
point="https://s3-01.par1.medisphere.internal:8333"
nom="k3s01-$(date +%Y%m%d-%H%M%S).tar.gz.age"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

[[ -r "$dest" ]] || { echo "destinataire age introuvable : $dest" >&2; exit 1; }
[[ -r "$s3env" ]] || { echo "identité S3 introuvable : $s3env" >&2; exit 1; }
command -v age >/dev/null || { echo "age absent de ce poste" >&2; exit 1; }

debut=$(date +%s)
# Arrêt, archive, redémarrage : un seul passage SSH pour que le redémarrage ait lieu même si
# l'archive échoue (trap distant).
ssh "$hote" 'sudo -n bash -s' <<'DISTANT'
set -euo pipefail
trap 'systemctl start k3s' EXIT
systemctl stop k3s
umask 077
tar -C /var/lib/rancher/k3s -czf /root/k3s01-sauvegarde.tar.gz server/db server/token server/cred server/tls
DISTANT

# Attente de l'API (le trap distant a relancé k3s).
for _ in $(seq 1 60); do
  if ssh "$hote" 'sudo -n k3s kubectl get --raw /readyz' 2>/dev/null | grep -qx ok; then break; fi
  sleep 2
done
fin=$(date +%s)
echo "interruption de l'API de $hote : $((fin - debut)) s"

# Chiffrement à la volée : l'archive en clair transite chiffrée par SSH, n'est jamais écrite sur adm01.
ssh "$hote" 'sudo -n cat /root/k3s01-sauvegarde.tar.gz' | age -R "$dest" > "$tmp/$nom"
ssh "$hote" 'sudo -n rm -f /root/k3s01-sauvegarde.tar.gz'

(
  set -a
  # shellcheck source=/dev/null
  . "$s3env"
  set +a
  aws --endpoint-url "$point" s3 cp "$tmp/$nom" "s3://etcd-m18/gestion/$nom" --only-show-errors
  aws --endpoint-url "$point" s3api head-object --bucket etcd-m18 --key "gestion/$nom" --query ContentLength
)
echo "archive envoyée : s3://etcd-m18/gestion/$nom"
