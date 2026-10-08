#!/usr/bin/env bash
# mesurer-coupure.sh — mesure la coupure réseau d'une VM pendant une opération (M09-E11, E19, E20).
#
# Usage : mesurer-coupure.sh ADRESSE [INTERVALLE]
#   Lance un ping toutes les INTERVALLE secondes (0.2 par défaut) vers ADRESSE jusqu'à Ctrl-C,
#   puis affiche : paquets envoyés et perdus, plus longue suite de pertes consécutives et sa
#   durée estimée (= pertes × intervalle). À lancer depuis adm01 AVANT la migration, à arrêter
#   APRÈS. Un intervalle < 0.2 s exige root (limite de ping pour les utilisateurs).
set -euo pipefail

[[ $# -ge 1 && $# -le 2 ]] || { echo "Usage : $0 ADRESSE [INTERVALLE]" >&2; exit 2; }
cible="$1"
intervalle="${2:-0.2}"
journal="$(mktemp)"
trap 'rm -f "$journal"' EXIT

echo "ping vers $cible toutes les ${intervalle} s — Ctrl-C pour terminer"
# -O : signale chaque réponse manquante (« no answer yet for icmp_seq=N »)
# -D : horodatage ; le ping s'arrête sur SIGINT, le script continue ensuite.
trap ':' INT
ping -D -O -i "$intervalle" "$cible" >"$journal" 2>&1 || true
trap - INT

envoyes="$(grep -cE 'icmp_seq=' "$journal" || true)"
perdus="$(grep -c 'no answer yet' "$journal" || true)"
# Plus longue suite de « no answer yet » consécutives.
suite="$(awk '/no answer yet/ {c++; if (c > m) m = c; next} /icmp_seq=/ {c = 0} END {print m + 0}' "$journal")"
duree="$(awk -v s="$suite" -v i="$intervalle" 'BEGIN {printf "%.1f", s * i}')"

printf 'Réponses reçues ou attendues : %s\n' "$envoyes"
printf 'Paquets sans réponse          : %s\n' "$perdus"
printf 'Plus longue coupure           : %s paquets ≈ %s s\n' "$suite" "$duree"
