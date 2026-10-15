# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants et bash -c entre apostrophes
# check-E44.sh — M12-E44 « Sous le capot : un conteneur construit à la main » : sur ctr01, le
# conteneur runc « capot » tourne depuis le paquet /srv/capot/bundle (rootfs extrait d'une image),
# isolé dans ses propres espaces de noms (pid, mnt, uts, ipc, net), dans le cgroup /capot limité à
# 64 Mio et 32 processus, racine en lecture seule, nom d'hôte « capot » ; le compte rendu
# docs/conteneurs/sous-le-capot.md est commité. Lecture seule (runc state, /proc, /sys/fs/cgroup).

# shellcheck source=_m12-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-expert.sh"

title "M12-E44 — Un conteneur construit à la main"
require_cmd jq ssh git

_m12_e44="$(_m12x_root "$_m12x_ctr01" <<'EOF'
b=/srv/capot/bundle
etat="$(runc state capot 2>/dev/null)"
pid="$(printf '%s' "$etat" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("pid",0) if d.get("status")=="running" else 0)' 2>/dev/null || echo 0)"
echo "pid=$pid"
echo "paquet=$(printf '%s' "$etat" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("bundle",""))' 2>/dev/null)"
[ -f "$b/config.json" ] && echo "config=ok"
[ -x "$b/rootfs/bin/sh" ] || [ -x "$b/rootfs/usr/bin/sh" ] && echo "rootfs=ok"
python3 - "$b/config.json" <<'PY' 2>/dev/null
import json, sys
c = json.load(open(sys.argv[1]))
print("lecture_seule=%s" % ("ok" if c.get("root", {}).get("readonly") else "non"))
print("hostname=%s" % c.get("hostname", ""))
print("cgroups_path=%s" % c.get("linux", {}).get("cgroupsPath", ""))
ns = sorted(n.get("type") for n in c.get("linux", {}).get("namespaces", []))
print("ns_config=%s" % ",".join(ns))
PY
if [ "$pid" != 0 ] && [ -d "/proc/$pid" ]; then
  for n in pid mnt uts ipc net; do
    [ "$(readlink /proc/$pid/ns/$n)" != "$(readlink /proc/1/ns/$n)" ] && echo "ns_$n=isole"
  done
  cg="$(sed -n 's/^0:://p' /proc/$pid/cgroup)"
  echo "cgroup=$cg"
  echo "memory_max=$(cat /sys/fs/cgroup$cg/memory.max 2>/dev/null)"
  echo "pids_max=$(cat /sys/fs/cgroup$cg/pids.max 2>/dev/null)"
  echo "nom_hote=$(nsenter -t "$pid" -u hostname 2>/dev/null)"
  awk '$5 == "/" {print "racine_options=" $6}' "/proc/$pid/mountinfo" | head -n 1
fi
EOF
)" || true
_m12_e44_vaut() { grep -Eq "^$1=$2\$" <<<"$_m12_e44"; }

check_cmd "conteneur runc « capot » en cours d'exécution" bash -c '! grep -q "^pid=0$" <<<"$1" && grep -q "^pid=[0-9]" <<<"$1"' _ "$_m12_e44"
check_cmd "paquet OCI : /srv/capot/bundle/config.json présent" _m12_e44_vaut config ok
check_cmd "paquet OCI : rootfs extrait d'une image (shell présent)" _m12_e44_vaut rootfs ok
check_cmd "le conteneur a été lancé depuis /srv/capot/bundle" _m12_e44_vaut paquet /srv/capot/bundle
for _m12_e44_n in pid mnt uts ipc net; do
  check_cmd "espace de noms $_m12_e44_n distinct de celui de l'hôte" _m12_e44_vaut "ns_$_m12_e44_n" isole
done
check_cmd "cgroup /capot (cgroupsPath de config.json)" _m12_e44_vaut cgroup /capot
check_cmd "cgroup : memory.max = 64 Mio (67108864)" _m12_e44_vaut memory_max 67108864
check_cmd "cgroup : pids.max = 32" _m12_e44_vaut pids_max 32
check_cmd "racine du conteneur montée en lecture seule" bash -c 'grep -Eq "^racine_options=ro(,|$)" <<<"$1"' _ "$_m12_e44"
check_cmd "nom d'hôte du conteneur : capot" _m12_e44_vaut nom_hote capot

_m12_e44_doc="${WB_DEPOT:-$HOME/medisphere}/docs/conteneurs/sous-le-capot.md"
for _m12_e44_m in unshare nsenter pivot_root cgroup.procs overlay 'runc spec'; do
  check_output "compte rendu : « $_m12_e44_m » expliqué" "$_m12_e44_m" cat "$_m12_e44_doc"
done
check_cmd "compte rendu commité dans le dépôt de documentation" \
  bash -c 'cd "$(dirname "$1")" && git ls-files --error-unmatch "$1" >/dev/null 2>&1 && [ -z "$(git status --porcelain -- "$1")" ]' _ "$_m12_e44_doc"
