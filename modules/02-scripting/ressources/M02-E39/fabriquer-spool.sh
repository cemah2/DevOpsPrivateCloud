#!/usr/bin/env bash
# fabriquer-spool.sh — spool de journaux JETABLE pour M02-E39 (archivage des journaux).
#
# Usage : fabriquer-spool.sh [--sain] ZONE
#   Crée dans ZONE (qui ne doit pas exister, ou être vide) :
#     ZONE/spool/<hôte>/*.log*   journaux collectés (gw01, dns01, git01), marqués .zone-de-test
#     ZONE/archives/             destination des archives
#     ZONE/attendu/<hôte>.liste  noms des fichiers de chaque hôte (pour vérifier une archive)
#   Sans --sain, un journal de dns01 arrive avec des droits 000 (illisible pour un
#   utilisateur non root) : c'est ce qui arrive parfois avec l'agent de collecte.
#   Avec --sain, tous les fichiers sont lisibles.
set -euo pipefail

sain=0
if [[ "${1:-}" == --sain ]]; then
  sain=1
  shift
fi
if (($# != 1)); then
  echo "Usage : $0 [--sain] ZONE" >&2
  exit 2
fi
zone="$1"
if [[ -e "$zone" ]] && [[ -n "$(ls -A "$zone" 2>/dev/null)" ]]; then
  echo "$zone existe et n'est pas vide : refus." >&2
  exit 3
fi
mkdir -p "$zone/spool" "$zone/archives" "$zone/attendu"
zone="$(cd "$zone" && pwd)"
maintenant="$(date +%s)"

# journal HÔTE FICHIER NB_LIGNES SERVICE
journal() {
  local h="$1" f="$2" n="$3" svc="$4" i chemin
  chemin="$zone/spool/$h/$f"
  mkdir -p "$zone/spool/$h"
  for ((i = 1; i <= n; i++)); do
    printf '%s %s %s[%d]: événement %04d de démonstration (données fictives)\n' \
      "$(date -d "@$((maintenant - (n - i) * 60))" '+%b %e %H:%M:%S')" "$h" "$svc" $((1000 + i)) "$i"
  done >"$chemin"
  printf '%s\n' "$f" >>"$zone/attendu/$h.liste"
}

journal gw01 nftables.log 400 kernel
journal gw01 chrony.log 50 chronyd
journal gw01 wireguard.log 30 kernel
journal dns01 dnsmasq.log 800 dnsmasq
journal dns01 dnsmasq.log.1 800 dnsmasq
journal dns01 dnsmasq-dhcp.log 120 dnsmasq-dhcp
journal git01 gitlab-nginx.log 600 nginx
journal git01 sshd.log 90 sshd

if ((!sain)); then
  chmod 000 "$zone/spool/dns01/dnsmasq.log.1"
fi
printf 'Zone de test du workbook (M02-E39) : données fictives.\n' >"$zone/spool/.zone-de-test"
echo "Spool créé dans $zone/spool (sain=$sain)."
