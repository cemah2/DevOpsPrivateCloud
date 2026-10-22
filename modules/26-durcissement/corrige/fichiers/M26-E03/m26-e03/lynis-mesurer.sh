#!/usr/bin/env bash
# lynis-mesurer.sh — M26-E03 (SEC-2703) : audit Lynis d'une liste de VMs, SANS installation.
#
# Pour chaque hôte : l'archive vérifiée est envoyée par SSH sur l'entrée standard, dépliée en root
# dans un dossier temporaire de /root (fichiers appartenant à root, comme Lynis l'exige), Lynis
# audite depuis ce dossier (rapport /var/log/lynis-report.dat, journal /var/log/lynis.log), le
# dossier est supprimé, le rapport est rapatrié dans ~/m26/e03/<hôte>/. Rien d'autre ne change sur
# la VM : pas de paquet, pas de dépôt, aucun réglage (Lynis ne corrige jamais rien).
#
# Usage : lynis-mesurer.sh <archive lynis-3.1.7.tar.gz> <SHA-256 attendue> hôte...
#   ex. : ./lynis-mesurer.sh lynis-3.1.7.tar.gz <SHA256-PAGE-CISOFY> gw01 git01 mon01 ipa01
# L'empreinte attendue est celle de https://cisofy.com/downloads/lynis/ (relevée à la main).
set -euo pipefail

usage() { echo "Usage : $0 <archive.tar.gz> <sha256> hôte..." >&2; exit 2; }
[[ $# -ge 3 ]] || usage
archive="$1"
attendue="$2"
shift 2
auditeur="${WB_MOI:-$(id -un)}"
sortie="${HOME}/m26/e03"

[[ -r "$archive" ]] || { echo "Archive illisible : $archive" >&2; exit 1; }
calculee="$(sha256sum "$archive" | cut -d' ' -f1)"
if [[ "$calculee" != "$attendue" ]]; then
  echo "Empreinte NON conforme : $calculee (attendue : $attendue). Arrêt." >&2
  exit 1
fi
echo "Archive vérifiée : $archive"

# Script exécuté sur la VM par « bash -c » ; $1 = nom de l'auditeur. Variables développées là-bas.
# shellcheck disable=SC2016
distant='set -eu
d="$(sudo mktemp -d /root/lynis.XXXXXX)"
trap '\''sudo rm -rf "$d"'\'' EXIT
sudo tar -xzf - -C "$d"
sudo sh -c "cd \"$d/lynis\" && ./lynis audit system --quick --no-colors --auditor \"$1\"" >/dev/null 2>&1 || true
sudo test -s /var/log/lynis-report.dat
sudo cat /var/log/lynis-report.dat'

for hote in "$@"; do
  echo "== $hote"
  mkdir -p "$sortie/$hote"
  ssh -o BatchMode=yes "admin@$hote" "bash -c $(printf '%q' "$distant") lynis $(printf '%q' "$auditeur")" \
    < "$archive" > "$sortie/$hote/lynis-report.dat"
  rapport="$sortie/$hote/lynis-report.dat"
  indice="$(sed -n 's/^hardening_index=//p' "$rapport")"
  version="$(sed -n 's/^lynis_version=//p' "$rapport")"
  avert="$(grep -c '^warning\[\]=' "$rapport" || true)"
  sugg="$(grep -c '^suggestion\[\]=' "$rapport" || true)"
  printf '%-8s Lynis %-6s indice %-4s avertissements %-3s suggestions %s\n' \
    "$hote" "$version" "$indice" "$avert" "$sugg"
done
echo "Rapports rapatriés dans $sortie/<hôte>/ : à relire avant toute copie dans un dépôt."
