#!/usr/bin/env bash
# fabriquer-donnees.sh — jeu de données JETABLE pour M02-E37 (purge des rapports).
#
# Usage : fabriquer-donnees.sh ZONE
#   Crée dans ZONE (qui ne doit pas exister, ou être vide) :
#     ZONE/rapports/           racine à purger (marquée par .zone-de-test)
#     ZONE/hors-zone/          témoin qui ne doit JAMAIS être touché
#     ZONE/attendu.tsv         état attendu après une purge conforme à la politique :
#                              « CONSERVER<TAB>chemin<TAB>sha256 » ou « PURGER<TAB>chemin »
#   Les dates de modification sont posées dans le passé (touch -d) : 2 à 20 jours pour ce
#   qui doit rester, 45 jours et plus pour ce qui doit partir. Le seuil de la politique
#   étant de 30 jours, le jeu reste valable une dizaine de jours après sa fabrication.
#
# Sert à l'injection de la panne, au contrôle (lab/bin/check 02 37) et à tes propres tests :
# ne lance jamais un script de purge en cours de mise au point ailleurs que sur une copie.
set -euo pipefail

if (($# != 1)); then
  echo "Usage : $0 ZONE" >&2
  exit 2
fi
zone="$1"
if [[ -e "$zone" ]] && [[ -n "$(ls -A "$zone" 2>/dev/null)" ]]; then
  echo "$zone existe et n'est pas vide : refus." >&2
  exit 3
fi
mkdir -p "$zone/rapports" "$zone/hors-zone"
zone="$(cd "$zone" && pwd)"
racine="$zone/rapports"
maintenant="$(date +%s)"
manifeste="$zone/attendu.tsv"
: >"$manifeste"

# fichier CHEMIN_RELATIF ÂGE_EN_JOURS CONSERVER|PURGER
fichier() {
  local rel="$1" age="$2" sort="$3" chemin
  chemin="$zone/$rel"
  mkdir -p "$(dirname "$chemin")"
  case "$chemin" in
    *.pdf) printf '%%PDF-1.4\n%% MédiSphère — %s\n%%%%EOF\n' "$rel" >"$chemin" ;;
    *.json) printf '{"source": "MédiSphère", "fichier": "%s"}\n' "$rel" >"$chemin" ;;
    *) printf 'MédiSphère — %s\n' "$rel" >"$chemin" ;;
  esac
  touch -d "@$((maintenant - age * 86400))" "$chemin"
  if [[ "$sort" == CONSERVER ]]; then
    printf 'CONSERVER\t%s\t%s\n' "$rel" "$(sha256sum "$chemin" | cut -d' ' -f1)" >>"$manifeste"
  else
    printf 'PURGER\t%s\n' "$rel" >>"$manifeste"
  fi
}

# date_jours ÂGE FORMAT — date d'il y a ÂGE jours (nom des rapports)
date_jours() { date -d "@$((maintenant - $1 * 86400))" +"$2"; }

for app in medi-agenda medi-doc medi-notif; do
  for age in 2 9 20; do
    fichier "rapports/$app/rapport-$(date_jours "$age" %F).json" "$age" CONSERVER
    fichier "rapports/$app/rapport-$(date_jours "$age" %F).pdf" "$age" CONSERVER
  done
  for age in 45 90 200; do
    fichier "rapports/$app/rapport-$(date_jours "$age" %F).json" "$age" PURGER
    fichier "rapports/$app/rapport-$(date_jours "$age" %F).pdf" "$age" PURGER
  done
  fichier "rapports/$app/Rapport mensuel $(date_jours 15 %Y-%m).pdf" 15 CONSERVER
  fichier "rapports/$app/Rapport mensuel $(date_jours 120 %Y-%m).pdf" 120 PURGER
  fichier "rapports/$app/LISEZMOI.txt" 300 CONSERVER
  fichier "rapports/$app/a-conserver/contentieux $(date_jours 400 %F).pdf" 400 CONSERVER
  fichier "rapports/$app/a-conserver/audit-hds-$(date_jours 380 %Y).json" 380 CONSERVER
  fichier "rapports/$app/a-conserver/audit-hds-$(date_jours 10 %Y).json" 10 CONSERVER
done
# Fichiers temporaires : seules medi-agenda et medi-doc ont un dossier tmp/
for app in medi-agenda medi-doc; do
  fichier "rapports/$app/tmp/export-1.tmp" 0 PURGER
  fichier "rapports/$app/tmp/export-2.tmp" 50 PURGER
  fichier "rapports/$app/tmp/verrou.lock" 1 PURGER
done
# Application retirée : tout son dossier part
fichier "rapports/legacy-rdv/rapport-$(date_jours 3 %F).json" 3 PURGER
fichier "rapports/legacy-rdv/rapport-$(date_jours 100 %F).json" 100 PURGER
fichier "rapports/legacy-rdv/a-conserver/export-final.pdf" 500 PURGER
# Hors de la racine : ne doit jamais être touché
fichier "hors-zone/temoin.pdf" 400 CONSERVER
fichier "hors-zone/temoin.json" 400 CONSERVER

printf 'Zone de test du workbook (M02-E37) : données fictives, purgeables.\n' >"$racine/.zone-de-test"
echo "Jeu de données créé dans $zone ($(grep -c . "$manifeste") fichiers, état attendu dans $manifeste)."
