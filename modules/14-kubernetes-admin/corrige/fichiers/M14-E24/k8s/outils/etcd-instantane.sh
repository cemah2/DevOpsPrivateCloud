#!/usr/bin/env bash
# =============================================================================
# outils/etcd-instantane.sh — plateforme/k8s (M14-E24) : instantané etcd À LA DEMANDE, avant une
# opération (montée de version, changement du serveur d'API, restauration…), depuis adm01.
#
# Déclenche le service etcd-instantane.service (rôle etcd_instantane) sur un nœud de contrôle, attend
# sa fin, affiche le résultat et l'objet envoyé sur s3-01. Avec --verifier, télécharge l'objet,
# le déchiffre (clé privée lue dans le Vault « critique » de plateforme/k8s) et lance
# « etcdutl snapshot status » : c'est l'instantané « vérifié » exigé par les runbooks.
#
# Usage : outils/etcd-instantane.sh [--noeud k8s-cp01] [--verifier] [--garder FICHIER]
#   --garder FICHIER : conserve l'instantané déchiffré (mode 600) au lieu de l'effacer (RB-141).
# Prérequis : SSH admin vers le nœud (sudo), ~/.config/workbook/s3-etcd.env, aws, age, etcdutl,
#   ansible-vault (environnement uv de plateforme/ansible) et outils/vault-pass-client.sh.
# =============================================================================
set -Eeuo pipefail
umask 077

noeud=k8s-cp01
verifier=0
garder=""
racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cle_chiffree="$racine/secrets/etcd-instantane-age.cle"
compartiment=etcd-k8s-par1
s3_env="$HOME/.config/workbook/s3-etcd.env"
s3_point="${WB_S3_ENDPOINT:-https://s3-01.par1.medisphere.internal:8333}"
vault_id="${ETCD_VAULT_ID:-critique@$HOME/src/ansible/outils/vault-pass-client.sh}"

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
die() { printf 'etcd-instantane: ERREUR : %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --noeud) noeud="${2:?}"; shift 2 ;;
    --verifier) verifier=1; shift ;;
    --garder) garder="${2:?}"; verifier=1; shift 2 ;;
    -h|--help) usage 0 ;;
    *) usage 2 ;;
  esac
done
[[ "$noeud" =~ ^k8s-cp0[1-3]$ ]] || die "nœud de contrôle inconnu : $noeud"

avant="$(ssh "$noeud" 'sudo -n cat /var/lib/etcd-instantane/dernier-succes 2>/dev/null' || true)"
echo "Instantané sur $noeud…"
# « systemctl start » d'un oneshot attend la fin du service et renvoie son échec éventuel.
if ! ssh "$noeud" 'sudo -n systemctl start etcd-instantane.service'; then
  ssh "$noeud" 'sudo -n journalctl -u etcd-instantane.service -n 20 --no-pager -o cat' >&2 || true
  die "le service a échoué sur $noeud (journal ci-dessus)"
fi
apres="$(ssh "$noeud" 'sudo -n cat /var/lib/etcd-instantane/dernier-succes')"
[[ "$apres" != "$avant" ]] || die "le dernier succès n'a pas changé : rien n'a été envoyé"
read -r horodatage objet revision <<<"$apres"
printf 'OK : %s, révision %s, s3://%s/%s\n' "$(date -d "@$horodatage" '+%F %T')" "$revision" "$compartiment" "$objet"

(( verifier )) || exit 0

for outil in aws age etcdutl ansible-vault; do command -v "$outil" >/dev/null || die "outil manquant : $outil"; done
[[ -r "$s3_env" ]] || die "identité S3 absente : $s3_env"
[[ -r "$cle_chiffree" ]] || die "clé privée chiffrée absente : $cle_chiffree"
travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT
(
  set -a
  # shellcheck source=/dev/null
  . "$s3_env"
  set +a
  aws --endpoint-url "$s3_point" s3 cp --only-show-errors "s3://$compartiment/$objet" "$travail/i.db.age"
) || die "téléchargement impossible"
# La clé privée ne touche jamais le disque en clair : elle passe par un descripteur.
age -d -i <(ansible-vault view --vault-id "$vault_id" "$cle_chiffree") -o "$travail/i.db" "$travail/i.db.age" \
  || die "déchiffrement impossible"
etcdutl snapshot status "$travail/i.db" -w table || die "instantané illisible"
if [[ -n "$garder" ]]; then
  install -m 0600 "$travail/i.db" "$garder"
  echo "Instantané déchiffré conservé : $garder (données sensibles : efface-le après usage)"
fi
echo "Instantané vérifié."
