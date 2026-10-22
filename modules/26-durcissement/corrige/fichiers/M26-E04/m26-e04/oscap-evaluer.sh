#!/usr/bin/env bash
# oscap-evaluer.sh — M26-E04 (SEC-2704) : évalue une VM d'essai contre un profil ComplianceAsCode et
# rapatrie le rapport. Préfigure le script hebdomadaire d'E24 (conformite-analyse), sans l'envoi S3.
#
# Usage : oscap-evaluer.sh <hôte> <profil court> [datastream]
#   ex. : ./oscap-evaluer.sh durci-deb cis_level1_server
#         ./oscap-evaluer.sh durci-rocky anssi_bp28_intermediary
# Datastream par défaut selon la famille de l'hôte :
#   Debian 13 : /usr/local/share/scap/ssg-0.1.82/ssg-debian13-ds.xml (archive amont 0.1.82)
#   Rocky 10  : /usr/share/xml/scap/ssg/content/ssg-rl10-ds.xml (paquet scap-security-guide)
# Résultats sur la VM : /var/lib/conformite/essais/<profil>-<AAAAMMJJ>.arf.xml et .html ;
# copie du HTML et d'un résumé dans ~/m26/e04/.
set -euo pipefail

[[ $# -ge 2 ]] || { echo "Usage : $0 <hôte> <profil court> [datastream]" >&2; exit 2; }
hote="$1"
profil="$2"
ds="${3:-}"
jour="$(date +%Y%m%d)"
dossier=/var/lib/conformite/essais
sortie="${HOME}/m26/e04"
mkdir -p "$sortie"

if [[ -z "$ds" ]]; then
  if ssh -o BatchMode=yes "admin@$hote" 'test -f /etc/debian_version'; then
    ds=/usr/local/share/scap/ssg-0.1.82/ssg-debian13-ds.xml
  else
    ds=/usr/share/xml/scap/ssg/content/ssg-rl10-ds.xml
  fi
fi

base="$dossier/$profil-$jour"
echo "== $hote : profil $profil, contenu $ds"
debut=$(date +%s)
# oscap renvoie 0 (aucune règle en échec), 2 (au moins une règle en échec) ou 1 (erreur).
code=0
ssh -o BatchMode=yes "admin@$hote" \
  "sudo install -d -m 0750 $dossier && sudo oscap xccdf eval --profile $profil \
     --results-arf $base.arf.xml --report $base.html $ds >/dev/null 2>&1" || code=$?
fin=$(date +%s)
case "$code" in
  0) etat="aucune règle en échec" ;;
  2) etat="au moins une règle en échec (attendu avant durcissement)" ;;
  *) echo "Erreur d'oscap (code $code) : relance à la main pour lire le message." >&2; exit 1 ;;
esac
echo "Évaluation : $((fin - debut)) s, code $code ($etat)"

# Rapatriement du rapport HTML (lisible par root seulement sur la VM).
ssh -o BatchMode=yes "admin@$hote" "sudo cat $base.html" > "$sortie/$hote-$profil-$jour.html"

# Résumé : score et décompte des résultats, lus dans l'ARF (sans le rapatrier : il est gros).
# shellcheck disable=SC2029  # $base est développé ici, volontairement
ssh -o BatchMode=yes "admin@$hote" "sudo grep -o '<score system=\"urn:xccdf:scoring:default\"[^>]*>[0-9.]*' $base.arf.xml | sed 's/.*>//';
  sudo grep -o '<result>[a-z]*</result>' $base.arf.xml | sort | uniq -c" \
  | tee "$sortie/$hote-$profil-$jour.resume.txt"
echo "Rapport : $sortie/$hote-$profil-$jour.html"
