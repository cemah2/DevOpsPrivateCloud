#!/usr/bin/env bash
# /usr/local/sbin/correctifs-etat — rôle correctifs (M26-E30, CHG-2730).
# Publie pour le collecteur textfile de node_exporter (fichier correctifs.prom, écriture atomique) :
#   medisphere_redemarrage_requis                    1 si un redémarrage est attendu (noyau, libc…)
#   medisphere_correctifs_securite_en_attente        mises à jour de sécurité disponibles, non installées
#   medisphere_correctifs_derniere_verification_secondes   horodatage de la vérification
# Lecture seule : ne télécharge ni n'installe rien (Debian : listes déjà mises à jour par apt-daily).
# Usage : correctifs-etat DOSSIER_TEXTFILE
set -Eeuo pipefail
dossier="${1:?dossier du collecteur textfile}"
[[ -d "$dossier" ]] || { echo "dossier absent : $dossier" >&2; exit 1; }

redemarrage=0
attente=0
if [[ -r /etc/debian_version ]]; then
  [[ -e /run/reboot-required ]] && redemarrage=1
  # Paquets à mettre à niveau dont la version candidate vient de l'origine de sécurité.
  attente="$(apt list --upgradable 2>/dev/null | grep -c -- '-security' || true)"
elif command -v dnf >/dev/null; then
  # needs-restarting -r : code 1 = redémarrage nécessaire, 0 = non.
  rc=0
  dnf -q needs-restarting -r >/dev/null 2>&1 || rc=$?
  (( rc == 1 )) && redemarrage=1
  attente="$(dnf -q updateinfo list --security --available 2>/dev/null | grep -c . || true)"
else
  echo "distribution non prise en charge" >&2
  exit 1
fi

tmp="$(mktemp "$dossier/.correctifs.prom.XXXXXX")"
cat >"$tmp" <<PROM
# HELP medisphere_redemarrage_requis 1 si un redémarrage est attendu pour activer des correctifs.
# TYPE medisphere_redemarrage_requis gauge
medisphere_redemarrage_requis $redemarrage
# HELP medisphere_correctifs_securite_en_attente Mises à jour de sécurité disponibles non installées.
# TYPE medisphere_correctifs_securite_en_attente gauge
medisphere_correctifs_securite_en_attente ${attente:-0}
# HELP medisphere_correctifs_derniere_verification_secondes Horodatage de la dernière vérification.
# TYPE medisphere_correctifs_derniere_verification_secondes gauge
medisphere_correctifs_derniere_verification_secondes $(date +%s)
PROM
chmod 0644 "$tmp"
mv -f "$tmp" "$dossier/correctifs.prom"
