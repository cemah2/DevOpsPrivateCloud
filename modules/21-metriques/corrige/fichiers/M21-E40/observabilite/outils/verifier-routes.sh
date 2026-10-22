#!/bin/sh
# outils/verifier-routes.sh — plateforme/observabilite (M21-E40, INC-4840).
# Valeurs de référence de la politique d'alerte (M21-E32) contrôlées sur la configuration extraite
# d'Alertmanager (build/alertmanager.yml, outils/extraire-regles.sh) :
#   - repeat_interval ≥ 1 h et group_interval ≥ 1 min sur toutes les routes ;
#   - aucun group_by qui contient pod, instance, file ou « ... » (un courriel par série).
# POSIX sh + yq v4 (mikefarah). Usage : sh outils/verifier-routes.sh build/alertmanager.yml
set -eu
config=${1:-build/alertmanager.yml}
erreurs=0
secondes() { # durée Prometheus (1h30m, 45s…) → secondes entières
  echo "$1" | sed -E 's/([0-9]+)(ms|s|m|h|d|w|y)/\1 \2\n/g' | awk '
    { u = $2; n = $1 } u == "s" { t += n } u == "m" { t += n * 60 } u == "h" { t += n * 3600 }
    u == "d" { t += n * 86400 } u == "w" { t += n * 604800 } u == "y" { t += n * 31536000 }
    END { print t + 0 }'
}
for champ in repeat_interval:3600 group_interval:60; do
  nom=${champ%%:*} min=${champ#*:}
  for v in $(yq "[.route | .. | select(tag == \"!!map\" and has(\"$nom\")) | .$nom] | .[]" "$config"); do
    if [ "$(secondes "$v")" -lt "$min" ]; then
      echo "KO  $nom: $v (minimum : $min s, politique d'alerte M21-E32)" >&2
      erreurs=$((erreurs + 1))
    fi
  done
done
for g in $(yq '[.route | .. | select(tag == "!!map" and has("group_by")) | .group_by[]] | .[]' "$config"); do
  case "$g" in
    pod | instance | file | ...)
      echo "KO  group_by contient « $g » : un courriel par série (INC-4840)" >&2
      erreurs=$((erreurs + 1)) ;;
  esac
done
[ "$erreurs" -eq 0 ] && echo "routes : valeurs conformes à la politique d'alerte"
[ "$erreurs" -eq 0 ]
