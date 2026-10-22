#!/bin/sh
# outils/tester-inhibitions.sh — plateforme/observabilite (M21-E36, INC-4836).
# Les essais de routage (amtool config routes test) ne voient pas les INHIBITIONS. Ce script démarre
# un Alertmanager jetable avec la configuration extraite (build/alertmanager.yml, sans envoi réel :
# les récepteurs sont remplacés par des récepteurs vides), envoie des couples d'alertes et vérifie
# lesquelles sont inhibées.
# Usage (job CI dans l'image prometheus/alertmanager, après outils/extraire-regles.sh) :
#   sh outils/tester-inhibitions.sh build/alertmanager.yml alertmanager/inhibitions-tests.txt
# Format des essais : <inhibée|active> | <étiquettes de la cible> | <étiquettes de la source>
set -eu
config=$1 essais=$2
travail=$(mktemp -d)
trap 'kill "$pid" 2>/dev/null || true; rm -rf "$travail"' EXIT INT TERM

# Récepteurs vidés : aucune notification ne part de la CI. Les routes et inhibitions restent.
awk '
  /^receivers:/ { print "receivers:"; skip = 1; next }
  skip && /^[^ #-]/ { skip = 0 }
  !skip { print }
' "$config" > "$travail/am.yml"
noms=$(grep -o "receiver: *[\"']\{0,1\}[A-Za-z0-9_.-]*" "$config" | sed "s/receiver: *[\"']\{0,1\}//" | sort -u)
for n in $noms; do printf '  - name: "%s"\n' "$n"; done > "$travail/recepteurs"
sed -i "/^receivers:/r $travail/recepteurs" "$travail/am.yml"
# Les gabarits et fichiers de mot de passe ne servent pas ici.
sed -i '/^templates:/,/^[^ -]/{/^templates:/d;/^  *- /d}' "$travail/am.yml"
sed -i '/smtp_auth_password_file/d; /ca_file/d' "$travail/am.yml"

alertmanager --config.file="$travail/am.yml" --storage.path="$travail/donnees" \
  --web.listen-address=127.0.0.1:19093 --cluster.listen-address= >"$travail/journal" 2>&1 &
pid=$!
i=0
until amtool --alertmanager.url=http://127.0.0.1:19093 config show >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -lt 30 ] || { cat "$travail/journal"; exit 1; }; sleep 1
done

erreurs=0
while IFS='|' read -r attendu cible source; do
  attendu=$(echo "$attendu" | tr -d ' ')
  case "$attendu" in ''|\#*) continue ;; esac
  # shellcheck disable=SC2086  # découpage voulu : une étiquette par argument
  amtool --alertmanager.url=http://127.0.0.1:19093 alert add $source --annotation=resume=source >/dev/null
  # shellcheck disable=SC2086
  amtool --alertmanager.url=http://127.0.0.1:19093 alert add $cible --annotation=resume=cible >/dev/null
  sleep 2
  nom=$(echo "$cible" | tr ' ' '\n' | sed -n 's/^alertname=//p')
  # Filtre sur TOUTES les étiquettes de la cible : la source peut porter le même alertname.
  # shellcheck disable=SC2086
  inhibees=$(amtool --alertmanager.url=http://127.0.0.1:19093 alert query --inhibited $cible -o simple | grep -c "$nom" || true)
  # shellcheck disable=SC2086
  actives=$(amtool --alertmanager.url=http://127.0.0.1:19093 alert query $cible -o simple | grep -c "$nom" || true)
  if [ "$inhibees" -ge 1 ] && [ "$actives" -eq 0 ]; then
    obtenu=inhibée
  else
    obtenu=active
  fi
  if [ "$obtenu" = "$attendu" ]; then
    echo "OK  $cible ($obtenu)"
  else
    echo "KO  $cible : $obtenu, attendu $attendu" >&2
    erreurs=$((erreurs + 1))
  fi
done < "$essais"
[ "$erreurs" -eq 0 ]
