#!/usr/bin/env bash
# mesurer.sh — Lance les profils P1 à P6 de M00-E48 sur UN disque de données de la VM 5048
# et affiche une ligne de tableau Markdown par profil.
#
# Usage (dans la VM sbx48, en root) :
#   ./mesurer.sh /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_nvme48 local-nvme [--precond]
#
# ⚠️ Écrit sur le périphérique brut : le script refuse un disque monté, partitionné, ou dont
#    le chemin ne contient pas « 48 » (numéro de série posé avec serial=xxx48).
set -euo pipefail

disque="${1:?chemin /dev/disk/by-id/... du disque de données}"
stockage="${2:?nom du stockage Proxmox (pour le tableau)}"
precond="${3:-}"
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
res="${RESULTATS:-$HOME/resultats-fio}"

[[ $EUID -eq 0 ]] || { echo "À lancer en root (sudo)." >&2; exit 1; }
if ! command -v fio >/dev/null || ! command -v jq >/dev/null; then echo "Installe fio et jq." >&2; exit 1; fi
[[ "$disque" == *48* ]] || { echo "Refus : $disque ne ressemble pas à un disque de mesure (serial *48)." >&2; exit 1; }
[[ -b "$disque" ]] || { echo "Refus : $disque n'est pas un périphérique bloc." >&2; exit 1; }
dev="$(readlink -f "$disque")"
if [[ -n "$(lsblk -nro MOUNTPOINT "$dev" | tr -d '[:space:]')" ]] || (( $(lsblk -nr "$dev" | wc -l) > 1 )); then
  echo "Refus : $dev est monté ou partitionné." >&2; exit 1
fi

mkdir -p "$res"
horo="$(date +%Y%m%d-%H%M%S)"

if [[ "$precond" == "--precond" ]]; then
  echo "Préconditionnement de $dev (écriture séquentielle complète)…" >&2
  fio --name=precond --filename="$disque" --rw=write --bs=1M --iodepth=16 --direct=1 \
      --ioengine=libaio --output=/dev/null
fi

# P1 à P5
DISQUE="$disque" fio --output-format=json --output="$res/$stockage-P1-P5-$horo.json" "$ici/perf-disques.fio"
# P6 : profil etcd (écritures de 2300 octets, fdatasync après chacune)
fio --name=P6-etcd-fdatasync --filename="$disque" --rw=write --ioengine=sync --fdatasync=1 \
    --bs=2300 --size=22m --percentile_list=50:99:99.9 \
    --output-format=json --output="$res/$stockage-P6-$horo.json"

# Extraction : IOPS, débit (Mo/s), latence moyenne, p99, p99.9 (en ms) — lecture ou écriture
# selon le sens du profil ; pour P6, latences de fdatasync (section « sync »).
jq -r --arg st "$stockage" '
  def ms: if . == null then "n/d" else ((. / 1e6) * 1000 | round / 1000 | tostring) end;
  .jobs[] | . as $j
  | (if ($j.read.io_bytes // 0) > 0 then $j.read else $j.write end) as $s
  | (if ($j.sync.lat_ns.N // 0) > 0 then $j.sync.lat_ns else $s.clat_ns end) as $lat
  | "| \($st) | \($j.jobname) | \($s.iops | round) | \(($s.bw / 1024) | round) Mo/s | \($lat.mean | ms) ms | \($lat.percentile["99.000000"] | ms) ms | \($lat.percentile["99.900000"] | ms) ms |"
' "$res/$stockage-P1-P5-$horo.json" "$res/$stockage-P6-$horo.json"

echo "Résultats bruts : $res/" >&2
