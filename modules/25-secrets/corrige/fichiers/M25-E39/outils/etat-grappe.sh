#!/usr/bin/env bash
# outils/etat-grappe.sh — état de la grappe OpenBao, nœud par nœud, SANS jeton et sans rien modifier
# (M25-E39, INC-5239). À lancer depuis adm01. Sert quand la VIP ne répond plus : la CLI « bao » ne
# sait alors plus rien dire d'utile (autopilot est transmis à un actif qui n'existe pas, list-peers ne
# montre que la copie locale, figée, du nœud interrogé).
#
# Pour chaque nœud et pour la VIP : code de sys/health (200 actif, 429 en attente, 503 scellé, 000
# rien), scellé ou non, ce que le nœud croit savoir du leader (sys/leader, lu dans SA copie locale du
# verrou : peut être périmé). Le port de grappe 8201 ne se teste pas d'ici : le pare-feu local des
# nœuds ne l'ouvre qu'aux trois nœuds ; teste-le DEPUIS un nœud vers les autres.
#
# Usage : outils/etat-grappe.sh [nœud…]   (défaut : vault01 vault02 vault03 ; domaine par BAO_DOMAINE)
set -euo pipefail

domaine="${BAO_DOMAINE:-par1.medisphere.internal}"
if (($# == 0)); then set -- vault01 vault02 vault03; fi

printf '%-8s %-5s %-7s %s\n' NŒUD CODE SCELLÉ "LEADER (vu par le nœud)"
for n in "$@" openbao; do
  url="https://$n.$domaine:8200"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url/v1/sys/health" 2>/dev/null || true)"
  scelle="$(curl -s --max-time 5 "$url/v1/sys/seal-status" 2>/dev/null | jq -r 'if .sealed == null then "?" else (.sealed | tostring) end' 2>/dev/null || echo '?')"
  chef="$(curl -s --max-time 5 "$url/v1/sys/leader" 2>/dev/null \
    | jq -r '"\(.leader_address // "-" | sub("^https://"; "") | sub(":8200$"; "")) self=\(.is_self | tostring)"' 2>/dev/null || echo '-')"
  printf '%-8s %-5s %-7s %s\n' "$n" "${code:-000}" "${scelle:-?}" "${chef:--}"
done
