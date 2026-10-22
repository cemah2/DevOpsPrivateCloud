#!/bin/sh
# outils/verifier-tableaux.sh — plateforme/observabilite (M21-E37, INC-4837).
# Contrôles des tableaux que la CI de M21-E17 ne faisait pas, sans joindre la production :
#   1. chaque règle d'enregistrement citée par un tableau (nom de la forme niveau:métrique:opérations)
#      est définie dans regles/ ;
#   2. chaque variable label_values(sélecteur, étiquette) cite une étiquette de la liste tenue dans
#      tableaux/etiquettes.txt (une par ligne : les étiquettes que la plateforme garantit) ;
#   3. aucune source de données n'est citée par un UID en dur dans une cible ou une variable.
# POSIX sh + yq v4 (mikefarah) : tourne dans l'image mikefarah/yq, comme outils/extraire-regles.sh.
# Usage (racine du dépôt) : sh outils/verifier-tableaux.sh
set -eu
erreurs=0
regles=$(mktemp)
trap 'rm -f "$regles"' EXIT
for f in regles/*.yaml; do
  [ -e "$f" ] || continue
  yq eval-all 'select(.kind == "PrometheusRule") | .spec.groups[].rules[].record // ""' "$f" | grep -v '^$' >> "$regles" || true
done
autorisees=tableaux/etiquettes.txt
[ -f "$autorisees" ] || { echo "KO  $autorisees absent" >&2; exit 1; }

for t in tableaux/*.json; do
  [ -e "$t" ] || continue
  # 1. Règles d'enregistrement citées
  for r in $(yq -p=json -o=y '[.. | select(has("expr")) | .expr] | .[]' "$t" 2>/dev/null |
             grep -oE '[a-zA-Z_][a-zA-Z0-9_]*:[a-zA-Z_][a-zA-Z0-9_]*:[a-zA-Z0-9_]+' | sort -u); do
    if ! grep -qx "$r" "$regles"; then
      echo "KO  $t : la règle d'enregistrement $r n'est définie nulle part dans regles/" >&2
      erreurs=$((erreurs + 1))
    fi
  done
  # 2. Étiquettes des variables label_values()
  for l in $(yq -p=json -o=y '.templating.list[] | select(.type == "query") | (.definition // "")' "$t" 2>/dev/null |
             sed -n 's/.*label_values(.*,[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*).*/\1/p' | sort -u); do
    if ! grep -qx "$l" "$autorisees"; then
      echo "KO  $t : la variable cite l'étiquette « $l », absente de $autorisees" >&2
      erreurs=$((erreurs + 1))
    fi
  done
  # 3. Sources citées par UID en dur (autorisé : variable ${…}/$…, ou les sources spéciales de Grafana)
  durs=$(yq -p=json -o=y '[.. | select(has("datasource")) | .datasource | select(tag == "!!map") | .uid // ""] | .[]' "$t" 2>/dev/null |
         grep -vE '^(\$.*|-- (Grafana|Mixed|Dashboard) --|grafana|)$' | sort -u | tr '\n' ' ')
  if [ -n "$durs" ]; then
    echo "KO  $t : source(s) citée(s) en dur : $durs" >&2
    erreurs=$((erreurs + 1))
  fi
done
[ "$erreurs" -eq 0 ] && echo "tableaux : contrôles 1 à 3 réussis"
[ "$erreurs" -eq 0 ]
