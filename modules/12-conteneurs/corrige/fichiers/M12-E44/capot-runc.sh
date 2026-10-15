#!/usr/bin/env bash
# capot-runc.sh — M12-E44, partie 2 : le même conteneur avec runc seul (validé avec runc 1.5.1).
# root@ctr01:~# bash capot-runc.sh           (après la partie 1, qui a rempli /srv/capot/oci)
# root@ctr01:~# ARRETER=1 bash capot-runc.sh (arrêt et suppression du conteneur, après la vérification)
set -euo pipefail

B=/srv/capot/bundle

if [[ "${ARRETER:-0}" == 1 ]]; then
  runc kill capot KILL 2>/dev/null || true
  sleep 1
  runc delete capot 2>/dev/null || true
  rm -rf "$B"
  exit 0
fi

# Paquet OCI : rootfs depuis l'image (umoci écrit aussi un config.json à partir de la configuration
# de l'image : Entrypoint, Cmd, Env, User), puis modèle de runc pour comparer.
rm -rf "$B"
umoci unpack --image /srv/capot/oci:trixie "$B"
cd "$B"
mv config.json config.umoci.json
runc spec                                   # modèle : espaces pid, network, ipc, uts, mount (+ cgroup en cgroup v2)
diff <(jq -S . config.umoci.json) <(jq -S . config.json) | head -n 40 || true

# Adaptation : processus, racine en lecture seule, nom d'hôte, cgroup et limites (ajoutées à côté
# de la règle de périphériques du modèle, linux.resources.devices, qu'on garde)
jq '.process.terminal = false
  | .process.args = ["sleep", "infinity"]
  | .hostname = "capot"
  | .root.readonly = true
  | .linux.cgroupsPath = "/capot"
  | .linux.resources.memory = {"limit": 67108864}
  | .linux.resources.pids = {"limit": 32}' config.json > config.json.nouveau
mv config.json.nouveau config.json
jq '{namespaces: .linux.namespaces, caps: .process.capabilities.bounding, user: .process.user}' config.json

# Lancement détaché : sans terminal, runc transmet ses descripteurs au conteneur → redirection
runc run -d capot </dev/null >/srv/capot/capot.log 2>&1
runc list
runc state capot
runc ps capot
P="$(runc state capot | jq -r .pid)"
for n in pid mnt uts ipc net; do echo "$n $(readlink "/proc/$P/ns/$n") (hôte : $(readlink "/proc/1/ns/$n"))"; done
cat /proc/"$P"/cgroup
cat /sys/fs/cgroup/capot/memory.max /sys/fs/cgroup/capot/pids.max
nsenter -t "$P" -u hostname
