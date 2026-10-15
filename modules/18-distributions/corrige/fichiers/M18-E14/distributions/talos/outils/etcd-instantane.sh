#!/usr/bin/env bash
# talos/outils/etcd-instantane.sh — instantané etcd du cluster talos-essai vers s3-01 (M18-E14).
# Usage (depuis adm01) : talos/outils/etcd-instantane.sh [NŒUD-DE-CONTRÔLE]   (défaut : 10.10.99.85)
# Identité Talos : talosconfig de rôle os:etcd:backup UNIQUEMENT (~/.config/workbook/m18/talosconfig-sauvegarde).
# Étapes : instantané (talosctl etcd snapshot), contrôle d'intégrité (etcdutl snapshot status),
# chiffrement age, envoi dans s3://etcd-m18/talos/, relecture de la taille de l'objet.
set -euo pipefail

noeud="${1:-10.10.99.85}"
racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dest="$racine/outils/age-sauvegardes-m18.pub"
tc="$HOME/.config/workbook/m18/talosconfig-sauvegarde"
s3env="$HOME/.config/workbook/s3-etcd-m18.env"
point="https://s3-01.par1.medisphere.internal:8333"
nom="talos-essai-$(date +%Y%m%d-%H%M%S).db.age"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"

for f in "$dest" "$tc" "$s3env"; do
  [[ -r "$f" ]] || { echo "fichier introuvable : $f" >&2; exit 1; }
done
for c in talosctl etcdutl age aws jq; do
  command -v "$c" >/dev/null || { echo "outil absent : $c" >&2; exit 1; }
done

talosctl --talosconfig "$tc" -n "$noeud" etcd snapshot "$tmp/etcd.db"
# Intégrité : etcdutl relit l'instantané (empreinte, révision, nombre de clés).
etcdutl snapshot status "$tmp/etcd.db" -w json | jq -e '.totalKey > 0' >/dev/null \
  || { echo "instantané illisible ou vide" >&2; exit 1; }
etcdutl snapshot status "$tmp/etcd.db" -w table

age -R "$dest" < "$tmp/etcd.db" > "$tmp/$nom"
rm -f "$tmp/etcd.db"

(
  set -a
  # shellcheck source=/dev/null
  . "$s3env"
  set +a
  aws --endpoint-url "$point" s3 cp "$tmp/$nom" "s3://etcd-m18/talos/$nom" --only-show-errors
  taille="$(aws --endpoint-url "$point" s3api head-object --bucket etcd-m18 --key "talos/$nom" --query ContentLength --output text)"
  [[ "$taille" == "$(stat -c %s "$tmp/$nom")" ]] || { echo "taille de l'objet différente du fichier envoyé" >&2; exit 1; }
)
echo "instantané envoyé : s3://etcd-m18/talos/$nom"
