#!/usr/bin/env bash
# nft-trace.sh — Trace nftables temporaire d'un flux sur gw01 (M00-E47).
# Usage (root sur gw01) : nft-trace.sh <ip-source> <ip-destination> [durée-en-secondes]
# Crée une table dédiée « wbtrace » (jamais /etc/nftables.conf), affiche la trace pendant
# la durée demandée, puis supprime la table, même en cas d'interruption (Ctrl-C).
set -euo pipefail

src="${1:?ip source}"; dst="${2:?ip destination}"; duree="${3:-20}"
[[ $EUID -eq 0 ]] || { echo "À lancer en root sur gw01." >&2; exit 1; }

nettoyer() { nft delete table inet wbtrace 2>/dev/null || true; }
trap nettoyer EXIT INT TERM

nettoyer
nft add table inet wbtrace
# Priorité -350 : avant conntrack (-200) et avant la table raw (-300).
nft add chain inet wbtrace pre '{ type filter hook prerouting priority -350; }'
nft add chain inet wbtrace out '{ type filter hook output priority -350; }'
nft add rule inet wbtrace pre ip saddr "$src" ip daddr "$dst" meta nftrace set 1
nft add rule inet wbtrace pre ip saddr "$dst" ip daddr "$src" meta nftrace set 1
nft add rule inet wbtrace out ip daddr "$src" meta nftrace set 1

echo "Trace active $duree s pour $src <-> $dst. Génère le trafic maintenant."
timeout "$duree" nft monitor trace || true
echo "Table de traçage supprimée."
