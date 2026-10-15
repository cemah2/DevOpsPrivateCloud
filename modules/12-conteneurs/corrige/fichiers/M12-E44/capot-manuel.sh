#!/usr/bin/env bash
# capot-manuel.sh — M12-E44, partie 1 : un conteneur « à la main » sur ctr01 (Debian 13, cgroup v2).
#
# À LIRE ligne par ligne et à rejouer étape par étape (root@ctr01:~#). Les étapes 4 et 5 s'exécutent
# dans le shell isolé lancé à l'étape 3 : elles sont données en commentaire, pas exécutées ici.
# Retour arrière : voir la fonction nettoyer (en bas).
set -euo pipefail

B=/srv/capot
IMAGE=docker://docker.io/library/debian:trixie-slim

# 1. Image OCI sans Docker, lecture de l'index, du manifeste et de la configuration
apt-get install -y skopeo umoci jq
mkdir -p "$B"
skopeo copy "$IMAGE" "oci:$B/oci:trixie"
jq . "$B/oci/index.json"
m="$(jq -r '.manifests[0].digest' "$B/oci/index.json" | cut -d: -f2)"
jq . "$B/oci/blobs/sha256/$m"
c="$(jq -r '.config.digest' "$B/oci/blobs/sha256/$m" | cut -d: -f2)"
jq '.config | {Entrypoint, Cmd, Env, User, WorkingDir}' "$B/oci/blobs/sha256/$c"

# 2. Extraction des couches dans l'ordre (la première est la plus basse). Un fichier « .wh.<nom> »
#    d'une couche supérieure signifie « <nom> supprimé » : il faut supprimer <nom> et le marqueur.
mkdir -p "$B/manuel/inf" "$B/manuel/sup" "$B/manuel/trav" "$B/manuel/fusion"
for couche in $(jq -r '.layers[].digest' "$B/oci/blobs/sha256/$m" | cut -d: -f2); do
  tar -xzf "$B/oci/blobs/sha256/$couche" -C "$B/manuel/inf"
  find "$B/manuel/inf" -name '.wh.*' ! -name '.wh..wh..opq' -print0 | while IFS= read -r -d '' w; do
    cible="$(dirname "$w")/$(basename "$w" | sed 's/^\.wh\.//')"
    case "$cible" in "$B"/manuel/inf/?*) rm -rf "$cible" "$w" ;; esac
  done
done

# 3. cgroup v2 à la main : contrôleurs disponibles, cgroup dédié, limites
cat /sys/fs/cgroup/cgroup.controllers
grep -qw memory /sys/fs/cgroup/cgroup.subtree_control || echo "+memory" > /sys/fs/cgroup/cgroup.subtree_control
grep -qw pids /sys/fs/cgroup/cgroup.subtree_control || echo "+pids" > /sys/fs/cgroup/cgroup.subtree_control
mkdir -p /sys/fs/cgroup/capot-manuel
echo 32M > /sys/fs/cgroup/capot-manuel/memory.max
echo 16 > /sys/fs/cgroup/capot-manuel/pids.max

echo "Ouvre un shell isolé (il entre lui-même dans le cgroup avant de s'isoler) :"
cat <<'MANUEL'
  root@ctr01:~# bash -c 'echo $$ > /sys/fs/cgroup/capot-manuel/cgroup.procs && exec unshare --mount --uts --ipc --net --pid --fork --mount-proc bash'

  # 4. Dans le shell isolé : propagation privée, overlay, nom d'hôte
  mount --make-rprivate /
  mount -t overlay overlay -o lowerdir=/srv/capot/manuel/inf,upperdir=/srv/capot/manuel/sup,workdir=/srv/capot/manuel/trav /srv/capot/manuel/fusion
  echo essai > /srv/capot/manuel/fusion/root/essai ; ls /srv/capot/manuel/sup/root/     # la copie sur écriture
  hostname capot

  # 5. Changement de racine
  cd /srv/capot/manuel/fusion && mkdir -p ancienne
  pivot_root . ancienne
  cd / && umount -l /ancienne && rmdir /ancienne
  mount -t proc proc /proc
  ps -ef ; hostname ; ip link ; cat /etc/os-release | head -n 2
  for i in $(seq 20); do sleep 300 & done      # échoue vers le 15e : pids.max = 16

  # Depuis un AUTRE terminal de l'hôte :
  root@ctr01:~# P=$(cat /sys/fs/cgroup/capot-manuel/cgroup.procs | head -n 1)
  root@ctr01:~# for n in pid mnt uts ipc net; do echo "$n $(readlink /proc/$P/ns/$n) $(readlink /proc/1/ns/$n)"; done
  root@ctr01:~# nsenter -t <PID-DU-BASH-ISOLÉ> -a ps -ef      # le PID 1 de l'espace « pid »
  root@ctr01:~# cat /sys/fs/cgroup/capot-manuel/memory.current /sys/fs/cgroup/capot-manuel/pids.current
MANUEL

nettoyer() {
  # Après « exit » du shell isolé (ses montages disparaissent avec son espace de noms)
  rmdir /sys/fs/cgroup/capot-manuel 2>/dev/null || echo "cgroup non vide : des processus y tournent encore"
  rm -rf "$B/manuel"
}
: "${NETTOYER:=0}"
if [[ "$NETTOYER" == 1 ]]; then nettoyer; fi
