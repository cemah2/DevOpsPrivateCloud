#!/usr/bin/env bash
# outillage.sh — M08-E10 (PLAT-920) : volume CephFS, sous-volume « outillage », client restreint.
# Rejouable depuis adm01 (chaque étape est idempotente). La clé et le montage partent ensuite par
# le rôle ceph_client (outils/ajouter-cle-ceph.sh, group_vars, playbook ceph-clients.yml).
# shellcheck disable=SC2029  # développement local voulu dans les commandes ssh
set -euo pipefail

ADMIN=${WB_CEPH_ADMIN:-ceph01}
CLIENT=${WB_CEPH_CLIENT:-cephcli01}
VOL=cephfs
GROUPE=plateforme
SOUSVOL=outillage
TAILLE=10737418240          # 10 Gio, en octets

# c ARGS… — commande ceph dans le conteneur de la release, sur le nœud _admin.
c() {
  ssh -o BatchMode=yes "$ADMIN" "sudo ceph $(printf '%q ' "$@")" 2>/dev/null
}

echo "== MDS : étiquette, cache plafonné"
for h in ceph01 ceph02; do c orch host label add "$h" mds >/dev/null; done
c config set mds mds_cache_memory_limit 536870912

echo "== Volume $VOL"
if ! c fs volume ls | grep -q "\"name\": \"$VOL\""; then
  c fs volume create "$VOL" "label:mds count:2"
fi
c fs status "$VOL"

echo "== Groupes et sous-volume"
for g in plateforme applications; do c fs subvolumegroup create "$VOL" "$g"; done   # idempotent
c fs subvolume create "$VOL" "$SOUSVOL" --group_name "$GROUPE" --size "$TAILLE"     # idempotent (redimensionne)
CHEMIN="$(c fs subvolume getpath "$VOL" "$SOUSVOL" --group_name "$GROUPE" | tr -d '\r')"
echo "chemin du sous-volume : $CHEMIN"

echo "== Client client.$SOUSVOL (lecture-écriture sur le seul sous-volume)"
c fs subvolume authorize "$VOL" "$SOUSVOL" "$SOUSVOL" --group_name="$GROUPE" --access_level=rw
c auth get "client.$SOUSVOL" | grep -E '^\s*caps'

cat <<FIN

Suite (la clé ne quitte le nœud _admin que par Ansible) :
  cd ~/src/ansible && outils/ajouter-cle-ceph.sh client.$SOUSVOL      # → vault_ceph_cle_$SOUSVOL (chiffrée)
  group_vars/role_ceph_client/ceph_client.yml : clé dans ceph_client_cles, montage dans
  ceph_client_cephfs avec le chemin $CHEMIN
  MR, puis : uv run ansible-playbook playbooks/ceph-clients.yml
  Contrôle sur $CLIENT : findmnt /mnt/$SOUSVOL ; sudo ls -l /etc/ceph/$SOUSVOL.secret
FIN
