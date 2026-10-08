# shellcheck shell=bash
# _m08-commun.sh — fonctions partagées par les scripts de panne du module 08 (M08-E35 à M08-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_avert, WB_EX, WB_VAR…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.9 « Pannes du bloc B ») :
#   - les pannes agissent par SSH (utilisateur admin + sudo) sur ceph01-03 et cephcli01 seulement ;
#     jamais sur pve01, pbs01, ni sur le réseau de pve01 ;
#   - AUCUNE donnée n'est détruite : pas de « ceph osd purge », de « zap », de « pool delete », de
#     disque détaché de la VM ; un disque est au plus mis hors ligne côté invité (sysfs), un démon
#     arrêté, une règle CRUSH ou un réglage changé, avec l'état d'origine sauvegardé ;
#   - l'annulation ne rétablit que ce qui porte encore la marque de la panne (une réparation de
#     l'apprenant n'est jamais défaite).
#
# 1. Exécution distante : m08_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF (wb_exec + aide ci-dessous).
#    L'aide fournit, sur les nœuds Ceph : FSID, ceph_sh (script dans l'environnement ceph : CLI native
#    si présente avec le trousseau admin, sinon « cephadm shell »), ceph_, rbd_, rgwadm_, unite_
#    (unité systemd d'un démon cephadm), demons_ (démons d'un type présents sur l'hôte).
# 2. Témoins du palier 4 (m08_temoins) : ressources de test créées à la première injection et
#    conservées (voir l'en-tête de enonce/04-expert.md) :
#      - client.sonde (RBD, pool rbd-test), image rbd-test/sonde (1 Gio, ext4) montée sur
#        cephcli01:/mnt/sonde ;
#      - client.sonde-fs (CephFS « cephfs », racine en rw) monté sur cephcli01:/mnt/sonde-fs ;
#      - utilisateur RGW sonde-s3, compartiment « sonde », objet « temoin » ; identifiants dans
#        cephcli01:/etc/workbook/sonde-s3.curl (600, format de configuration de curl) ;
#      - sonde /usr/local/sbin/wb-sonde-stockage sur cephcli01 (essais RBD, CephFS et S3).
# 3. État local (adm01) : ~/.local/state/workbook/M08-EXX/ (valeurs d'origine non secrètes).

_M08_ADMIN="${WB_CEPH_ADMIN:-ceph01}"
_M08_CLIENT="${WB_CEPH_CLIENT:-cephcli01}"
_M08_NOEUDS=(ceph01 ceph02 ceph03)
_M08_POOL=rbd-test
_M08_FS=cephfs
_M08_RGW_FQDN=rgw.par1.medisphere.internal
# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
declare -A _M08_IP_PUB=([ceph01]=10.10.30.51 [ceph02]=10.10.30.52 [ceph03]=10.10.30.53 [ceph04]=10.10.30.54
  [cephcli01]=10.10.30.20)
# shellcheck disable=SC2034
declare -A _M08_IP_CLU=([ceph01]=10.10.31.51 [ceph02]=10.10.31.52 [ceph03]=10.10.31.53 [ceph04]=10.10.31.54)

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

# m08_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m08_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M08-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

# m08_journal EXX "message" — journal local de la panne.
m08_journal() {
  local ex="$1" d
  shift
  d="$(m08_etat "$ex")"
  printf '%s %s [M08-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}

# m08_lire EXX CLÉ / m08_ecrire EXX CLÉ VALEUR / m08_oublier EXX CLÉ — petites valeurs d'état.
m08_lire() {
  local f
  f="$(m08_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m08_ecrire() {
  local d
  d="$(m08_etat "$1")"
  # Une seule écriture par clé et par panne : on ne capture jamais un état déjà cassé.
  [[ -f "$d/$2" ]] || printf '%s\n' "$3" >"$d/$2"
}
m08_oublier() {
  local d
  d="$(m08_etat "$1")"
  rm -f -- "${d:?}/$2"
}

# ---------------------------------------------------------------------------
# Aide envoyée aux hôtes distants (après le prélude de wb_exec, exécutée en root)
# ---------------------------------------------------------------------------
read -r -d '' _M08_AIDE_DISTANTE <<'AIDE' || true
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# FSID du cluster (nœuds Ceph) : dossier /var/lib/ceph/<fsid>, lisible même sans quorum.
FSID="$(find /var/lib/ceph -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
  | sed -nE 's#.*/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$#\1#p' | head -n 1)"
# ceph_sh 'script' — exécute le script là où les commandes ceph/rbd/radosgw-admin existent.
ceph_sh() {
  if command -v ceph >/dev/null 2>&1 && [ -r /etc/ceph/ceph.client.admin.keyring ]; then
    timeout 150 bash -c "$1" </dev/null
  else
    timeout 180 cephadm shell -- bash -c "$1" </dev/null 2>/dev/null
  fi
}
ceph_()   { ceph_sh "ceph --connect-timeout 20 $(printf '%q ' "$@")"; }
rbd_()    { ceph_sh "rbd $(printf '%q ' "$@")"; }
rgwadm_() { ceph_sh "radosgw-admin $(printf '%q ' "$@")"; }
# unite_ NOM_DE_DÉMON — unité systemd d'un démon cephadm (ex. unite_ osd.3).
unite_() { printf 'ceph-%s@%s.service\n' "$FSID" "$1"; }
# demons_ TYPE — démons de ce type déployés sur cet hôte (osd, mon, mds, rgw, haproxy…).
demons_() {
  [ -n "$FSID" ] || return 0
  find "/var/lib/ceph/$FSID" -mindepth 1 -maxdepth 1 -type d -name "$1.*" -printf '%f\n' 2>/dev/null | sort
}
# masque_ UNITÉ — 0 si l'unité est masquée.
masque_() { [ "$(systemctl is-enabled "$1" 2>/dev/null)" = masked ]; }
# py_ 'expression' — petit filtre JSON (python3 existe sur Rocky et Debian).
py_() { python3 -c "import json,sys
d=json.load(sys.stdin)
$1"; }
AIDE

# m08_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec (SSH, root par sudo), avec l'aide.
m08_wb_exec() {
  { printf '%s\n' "$_M08_AIDE_DISTANTE"; cat; } | wb_exec "$@"
}

# m08_admin [VAR=valeur…] <<'EOF' … EOF — sur le nœud qui porte le trousseau admin (WB_CEPH_ADMIN).
m08_admin() {
  m08_wb_exec "$_M08_ADMIN" "$@"
}

# m08_ceph ARGS… — une commande ceph sur le nœud admin, sortie standard renvoyée.
m08_ceph() {
  local a
  a="$(printf '%q ' "$@")"
  m08_admin A="$a" <<'EOF'
ceph_sh "ceph --connect-timeout 20 $A"
EOF
}

# m08_existe HÔTE — l'hôte répond en SSH.
m08_existe() { remote "$1" true >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Lecture de l'état du cluster
# ---------------------------------------------------------------------------

# m08_sain — 0 si le cluster est sain pour une injection (quorum complet, OSD tous up et in, PG
# tous actifs, aucun drapeau de pause ou de remplissage, HEALTH_OK) ; sinon affiche pourquoi.
m08_sain() {
  local r
  r="$(m08_admin <<'EOF' 2>/dev/null
j="$(ceph_sh 'printf "{\"s\":"; ceph --connect-timeout 20 status -f json; printf ",\"o\":"; ceph --connect-timeout 20 osd dump -f json; printf "}"')"
printf '%s' "$j" | py_ '
s, o = d["s"], d["o"]
pb = []
if s["health"]["status"] != "HEALTH_OK":
    pb.append("santé " + s["health"]["status"] + " (" + ", ".join(sorted(s["health"].get("checks", {}).keys())) + ")")
if len(s.get("quorum_names", [])) != s["monmap"]["num_mons"]:
    pb.append("quorum incomplet")
om = s["osdmap"]
if not (om["num_osds"] == om["num_up_osds"] == om["num_in_osds"]):
    pb.append("OSD pas tous up et in")
fl = set(o.get("flags", "").split(","))
for f in ("pauserd", "pausewr", "full", "noout", "noup", "nodown", "noin"):
    if f in fl:
        pb.append("drapeau " + f)
inactifs = [x for x in s["pgmap"].get("pgs_by_state", []) if not x["state_name"].startswith("active+clean")]
if inactifs:
    pb.append("PG pas tous active+clean")
print("OK" if not pb else "; ".join(pb))
' 2>/dev/null || echo "cluster injoignable depuis le nœud admin"
EOF
)" || true
  if [[ "$r" == OK ]]; then return 0; fi
  wb_avert "le cluster ceph-par1 n'est pas sain avant la panne : ${r:-pas de réponse de $_M08_ADMIN}. Lance lab/bin/check 08 ${WB_EX#M08-E} et répare d'abord."
  return 1
}

# m08_attendre SECONDES commande [args…] — relance la commande toutes les 5 s jusqu'à succès.
m08_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 5
    t=$((t + 5))
  done
  "$@"
}

# m08_osd_infos — lignes « id hôte périphérique » des OSD (périphérique : sdb… ou « - »).
m08_osd_infos() {
  m08_admin <<'EOF'
ceph_ osd metadata -f json | py_ '
for m in d:
    dev = m.get("devices", "") or "-"
    print(m["id"], m.get("hostname", "?"), dev if "," not in dev else "-")
'
EOF
}

# m08_demons TYPE — lignes « hôte nom_du_démon » des démons cephadm de ce type (ceph orch ps).
m08_demons() {
  m08_admin T="$1" <<'EOF'
ceph_ orch ps --daemon-type "$T" -f json | py_ '
for x in d:
    print(x["hostname"], x.get("daemon_name") or (x["daemon_type"] + "." + x["daemon_id"]))
'
EOF
}

# m08_arreter HÔTE DÉMON [masquer] — arrête (et masque) l'unité systemd d'un démon cephadm.
m08_arreter() {
  m08_wb_exec "$1" D="$2" M="${3:-}" <<'EOF'
u="$(unite_ "$D")"
systemctl cat "$u" >/dev/null 2>&1 || exit 10
systemctl stop "$u"
if [ -n "$M" ]; then systemctl mask "$u" >/dev/null 2>&1; fi
journal "démon $D arrêté${M:+ et masqué} ($u)"
EOF
}

# m08_relancer HÔTE DÉMON — annulation : démasque si masqué, relance si inactif (idempotent).
m08_relancer() {
  m08_wb_exec "$1" D="$2" <<'EOF' || wb_avert "annulation incomplète sur $1 (démon $2)"
u="$(unite_ "$D")"
if masque_ "$u"; then systemctl unmask "$u" >/dev/null 2>&1; journal "annulation : $u démasquée"; fi
if ! systemctl is-active -q "$u"; then
  systemctl reset-failed "$u" >/dev/null 2>&1 || true
  systemctl start "$u" && journal "annulation : $u relancée"
fi
EOF
}

# ---------------------------------------------------------------------------
# Témoins du palier 4 (créés si absents, jamais supprimés par les pannes)
# ---------------------------------------------------------------------------

# Sonde installée sur cephcli01 (lue par l'apprenant : elle ne révèle aucune cause).
read -r -d '' _M08_SONDE <<'SONDE' || true
#!/bin/bash
# wb-sonde-stockage — sonde du workbook (module 08, palier 4) : le stockage vu d'un client.
# Essais : écriture + relecture sur /mnt/sonde (RBD) et /mnt/sonde-fs (CephFS), GET et PUT S3 sur
# https://rgw.par1.medisphere.internal/sonde/ (identifiants : /etc/workbook/sonde-s3.curl).
# Lancer en root : sudo wb-sonde-stockage
ko=0
essai() {
  local libelle="$1" delai="$2" sortie p i=0
  shift 2
  sortie="$(mktemp)"
  ( "$@" ) >"$sortie" 2>&1 &
  p=$!
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt "$delai" ]; do sleep 1; i=$((i + 1)); done
  if kill -0 "$p" 2>/dev/null; then
    echo "[KO] $libelle : aucune réponse après ${delai} s (opération bloquée)"
    ko=1
  elif wait "$p"; then
    echo "[OK] $libelle"
  else
    echo "[KO] $libelle : $(tail -c 400 "$sortie" | tr '\n' ' ')"
    ko=1
  fi
  rm -f "$sortie"
}
ecrire() { mountpoint -q "$1" || { echo "$1 n'est pas monté"; return 1; }; date -Is >"$1/essai" && sync "$1/essai" && cat "$1/temoin" >/dev/null; }
s3() { curl -sS --fail-with-body --max-time 15 -K /etc/workbook/sonde-s3.curl "$@"; }
essai "RBD    écriture sur /mnt/sonde (rbd-test/sonde)" 20 ecrire /mnt/sonde
essai "CephFS écriture sur /mnt/sonde-fs (cephfs)" 20 ecrire /mnt/sonde-fs
essai "S3     lecture  https://rgw.par1.medisphere.internal/sonde/temoin" 20 s3 -o /dev/null https://rgw.par1.medisphere.internal/sonde/temoin
essai "S3     écriture https://rgw.par1.medisphere.internal/sonde/essai" 20 s3 -o /dev/null -T /etc/hostname https://rgw.par1.medisphere.internal/sonde/essai
exit "$ko"
SONDE

# m08_temoins — crée ce qui manque des témoins (idempotent, quelques secondes s'ils existent).
m08_temoins() {
  local sortie k1 k2 ak sk fsid mons cree s3
  if ! m08_existe "$_M08_CLIENT"; then
    wb_avert "$_M08_CLIENT ne répond pas en SSH (M08-E06) : impossible de préparer les témoins"
    return 1
  fi
  sortie="$(m08_admin P="$_M08_POOL" F="$_M08_FS" <<'EOF'
ceph_ osd pool ls | grep -qx "$P" || { echo "ERREUR=pool $P absent (M08-E05)"; exit 0; }
ceph_ fs ls -f json | py_ 'sys.exit(0 if any(x["name"] == "'"$F"'" for x in d) else 1)' \
  || { echo "ERREUR=système de fichiers $F absent (M08-E10)"; exit 0; }
ceph_ auth get client.sonde >/dev/null 2>&1 \
  || ceph_ auth get-or-create client.sonde mon 'profile rbd' osd "profile rbd pool=$P" >/dev/null
ceph_ auth get client.sonde-fs >/dev/null 2>&1 || ceph_ fs authorize "$F" client.sonde-fs / rw >/dev/null
echo "K1=$(ceph_ auth get-key client.sonde)"
echo "K2=$(ceph_ auth get-key client.sonde-fs)"
cree=0
if ! rbd_ info "$P/sonde" >/dev/null 2>&1; then rbd_ create --size 1G "$P/sonde" && cree=1; fi
echo "CREE=$cree"
echo "FSID=$(ceph_ fsid)"
echo "MONS=$(ceph_ mon dump -f json | py_ '
a = []
for m in d["mons"]:
    for v in m["public_addrs"]["addrvec"]:
        if v["type"] == "v2":
            a.append(v["addr"])
print("/".join(a))')"
u="$(rgwadm_ user info --uid=sonde-s3 2>/dev/null)"
[ -n "$u" ] || u="$(rgwadm_ user create --uid=sonde-s3 --display-name='Sonde du workbook (M08)' 2>/dev/null)"
if [ -n "$u" ]; then
  printf '%s' "$u" | py_ '
k = d["keys"][0]
print("AK=" + k["access_key"])
print("SK=" + k["secret_key"])'
fi
EOF
)" || { wb_avert "nœud admin $_M08_ADMIN injoignable pour préparer les témoins"; return 1; }
  if grep -q '^ERREUR=' <<<"$sortie"; then
    wb_avert "témoins impossibles : $(sed -n 's/^ERREUR=//p' <<<"$sortie")"
    return 1
  fi
  k1="$(sed -n 's/^K1=//p' <<<"$sortie")"
  k2="$(sed -n 's/^K2=//p' <<<"$sortie")"
  ak="$(sed -n 's/^AK=//p' <<<"$sortie")"
  sk="$(sed -n 's/^SK=//p' <<<"$sortie")"
  fsid="$(sed -n 's/^FSID=//p' <<<"$sortie")"
  mons="$(sed -n 's/^MONS=//p' <<<"$sortie")"
  cree="$(sed -n 's/^CREE=//p' <<<"$sortie")"
  s3=1
  [[ -n "$ak" && -n "$sk" ]] || s3=0
  [[ -n "$k1" && -n "$k2" && -n "$fsid" && -n "$mons" ]] || { wb_avert "témoins : réponse incomplète du nœud admin"; return 1; }
  # Les clés passent par l'entrée standard (en-tête du script), jamais en argument de commande.
  m08_wb_exec "$_M08_CLIENT" K1="$k1" K2="$k2" AK="$ak" SK="$sk" FSID="$fsid" MONS="$mons" CREE="$cree" \
    S3="$s3" P="$_M08_POOL" F="$_M08_FS" RGW="$_M08_RGW_FQDN" SONDE="$_M08_SONDE" <<'EOF'
umask 077
[ -r /etc/ceph/ceph.conf ] || { echo "ceph.conf absent sur le client (M08-E06)" >&2; exit 3; }
command -v rbd >/dev/null && command -v mount.ceph >/dev/null || { echo "ceph-common absent sur le client" >&2; exit 3; }
install -d -m 700 /etc/workbook
printf '[client.sonde]\n\tkey = %s\n' "$K1" >/etc/ceph/ceph.client.sonde.keyring
printf '%s\n' "$K2" >/etc/ceph/sonde-fs.secret
chmod 600 /etc/ceph/ceph.client.sonde.keyring /etc/ceph/sonde-fs.secret
if [ "$S3" = 1 ]; then
  printf 'user = "%s:%s"\naws-sigv4 = "aws:amz:us-east-1:s3"\n' "$AK" "$SK" >/etc/workbook/sonde-s3.curl
  chmod 600 /etc/workbook/sonde-s3.curl
fi
printf '%s\n' "$SONDE" >/usr/local/sbin/wb-sonde-stockage
chmod 755 /usr/local/sbin/wb-sonde-stockage
install -d -m 755 /mnt/sonde /mnt/sonde-fs
# RBD (une partie qui échoue n'empêche pas les suivantes ; code 4 à la fin)
rc=0
dev="$(rbd device list --format json 2>/dev/null | py_ '
for x in d:
    if x.get("pool") == "'"$P"'" and x.get("name") == "sonde":
        print(x["device"]); break' 2>/dev/null)"
if [ -z "$dev" ]; then
  if dev="$(timeout 60 rbd device map --id sonde -o ms_mode=prefer-crc "$P/sonde" </dev/null)"; then
    journal "témoin : $P/sonde mappée sur $dev"
  else
    echo "rbd device map impossible" >&2; rc=4; dev=""
  fi
fi
if [ -n "$dev" ]; then
  if [ "$CREE" = 1 ] && ! blkid -p "$dev" >/dev/null 2>&1; then
    mkfs.ext4 -q -L sonde "$dev" && journal "témoin : système de fichiers créé sur l'image neuve $P/sonde"
  fi
  if mountpoint -q /mnt/sonde || timeout 60 mount "$dev" /mnt/sonde; then
    [ -f /mnt/sonde/temoin ] || { echo "témoin RBD du workbook" >/mnt/sonde/temoin; sync /mnt/sonde/temoin; }
  else
    echo "montage de /mnt/sonde impossible" >&2; rc=4
  fi
fi
# CephFS
if ! mountpoint -q /mnt/sonde-fs; then
  if timeout 60 mount -t ceph "sonde-fs@$FSID.$F=/" /mnt/sonde-fs \
    -o "mon_addr=$MONS,secretfile=/etc/ceph/sonde-fs.secret,ms_mode=prefer-crc" </dev/null; then
    journal "témoin : $F monté sur /mnt/sonde-fs"
  else
    echo "montage de /mnt/sonde-fs impossible" >&2; rc=4
  fi
fi
if mountpoint -q /mnt/sonde-fs && [ ! -f /mnt/sonde-fs/temoin ]; then
  echo "témoin CephFS du workbook" >/mnt/sonde-fs/temoin; sync /mnt/sonde-fs/temoin
fi
# S3 (si la passerelle existe)
if [ "$S3" = 1 ]; then
  c() { curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -K /etc/workbook/sonde-s3.curl "$@"; }
  if [ "$(c "https://$RGW/sonde/temoin")" != 200 ]; then
    c -X PUT "https://$RGW/sonde" >/dev/null || true
    printf 'témoin S3 du workbook\n' >/tmp/.wb-temoin
    [ "$(c -T /tmp/.wb-temoin "https://$RGW/sonde/temoin")" = 200 ] || { rm -f /tmp/.wb-temoin; echo "objet témoin S3 impossible à écrire" >&2; exit 5; }
    rm -f /tmp/.wb-temoin
    journal "témoin : objet s3://sonde/temoin écrit"
  fi
fi
exit "$rc"
EOF
}

# m08_temoins_s3 — 0 si les identifiants S3 du témoin existent sur le client (RGW déployé).
m08_temoins_s3() {
  remote "$_M08_CLIENT" "sudo -n test -s /etc/workbook/sonde-s3.curl" >/dev/null 2>&1
}

# m08_sonde_client — lance la sonde sur cephcli01 ; affiche sa sortie, renvoie son code.
m08_sonde_client() {
  remote "$_M08_CLIENT" "sudo -n /usr/local/sbin/wb-sonde-stockage" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Variantes sans effet sur un lab donné
# ---------------------------------------------------------------------------

# m08_essayer EXX NB DÉPART — appelle _mEXX_une N (codes : 0 panne posée, 10 variante sans effet ou
# impossible sur ce lab, déjà défaite ; autre = erreur) pour N = DÉPART, DÉPART+1… jusqu'à un succès.
m08_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M08-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

# m08_preparer — précondition commune : témoins prêts puis cluster sain. Pendant l'astreinte
# (M08-E43, _M08_ASTREINTE=1), break-E43 a fait ces contrôles une fois avant la première panne :
# les refaire ici « réparerait » la panne précédente (témoins recréés) ou échouerait (santé).
m08_preparer() {
  if [[ -n "${_M08_ASTREINTE:-}" ]]; then return 0; fi
  m08_temoins || return 1
  m08_sain
}
