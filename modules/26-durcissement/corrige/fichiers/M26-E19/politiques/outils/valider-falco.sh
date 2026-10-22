#!/bin/sh
# plateforme/politiques — outils/valider-falco.sh (M26-E19)
# Valide les règles Falco de MédiSphère, en deux temps (deux jobs de CI, deux images) :
#   conventions  (yq de mikefarah 4.x) : extrait le bloc customRules."regles-medisphere.yaml" du
#                fichier de valeurs vers regles-extraites/regles-medisphere.yaml, puis vérifie nos
#                conventions : préfixe « MédiSphère — », exactement une étiquette gravite_* par règle,
#                aucune règle désactivée (enabled: false) ni remplacée (override) — une exception passe
#                par une liste ou une macro medisphere_* (RB-261) ;
#   moteur       (binaire falco de la version du cluster) : « falco -V » sur les règles par défaut
#                PUIS les nôtres (elles utilisent leurs macros : spawned_process, container…), avec le
#                greffon container chargé (les règles par défaut l'exigent).
# POSIX sh : le premier job tourne dans l'image Alpine d'E07 (sans bash).
# Usage : outils/valider-falco.sh conventions [falco/regles-medisphere.yaml]
#         outils/valider-falco.sh moteur
# Sur un poste qui a les deux outils : outils/valider-falco.sh conventions && outils/valider-falco.sh moteur
# Variables (moteur) : FALCO (défaut falco), FALCO_CONFIG (/etc/falco/falco.yaml),
#                      FALCO_REGLES_DEFAUT (/etc/falco/falco_rules.yaml).
set -eu

mode="${1:-}"
sortie="regles-extraites/regles-medisphere.yaml"

case "$mode" in
  conventions)
    valeurs="${2:-falco/regles-medisphere.yaml}"
    command -v yq >/dev/null || { echo "outil manquant : yq (mikefarah 4.x)" >&2; exit 2; }
    [ -r "$valeurs" ] || { echo "fichier illisible : $valeurs" >&2; exit 2; }
    mkdir -p "$(dirname "$sortie")"
    yq -r '.customRules."regles-medisphere.yaml" // ""' "$valeurs" >"$sortie"
    [ -s "$sortie" ] || { echo "ÉCHEC : clé customRules.\"regles-medisphere.yaml\" absente ou vide" >&2; exit 1; }
    erreurs=0
    mal_nommees="$(yq -r '.[] | select(has("rule")) | .rule | select(test("^MédiSphère — ") | not)' "$sortie")"
    if [ -n "$mal_nommees" ]; then
      echo "ÉCHEC : règle(s) sans le préfixe « MédiSphère — » :"; echo "$mal_nommees"; erreurs=1
    fi
    sans_gravite="$(yq -r '.[] | select(has("rule")) | select([.tags[] | select(test("^gravite_(critique|avertissement)$"))] | length != 1) | .rule' "$sortie")"
    if [ -n "$sans_gravite" ]; then
      echo "ÉCHEC : règle(s) sans exactement une étiquette gravite_critique|gravite_avertissement :"
      echo "$sans_gravite"; erreurs=1
    fi
    interdits="$(yq -r '.[] | select(has("rule")) | select(.enabled == false or has("override")) | .rule' "$sortie")"
    if [ -n "$interdits" ]; then
      echo "ÉCHEC : règle(s) désactivée(s) ou remplacée(s) — passe par une liste ou une macro medisphere_* :"
      echo "$interdits"; erreurs=1
    fi
    [ "$erreurs" -ne 0 ] || echo "conventions : OK ($(yq -r '[.[] | select(has("rule"))] | length' "$sortie") règles) → $sortie"
    exit "$erreurs"
    ;;
  moteur)
    falco="${FALCO:-falco}"
    command -v "$falco" >/dev/null || { echo "outil manquant : $falco" >&2; exit 2; }
    [ -s "$sortie" ] || { echo "lance d'abord : $0 conventions" >&2; exit 2; }
    "$falco" -c "${FALCO_CONFIG:-/etc/falco/falco.yaml}" -o 'load_plugins[]=container' \
      -V "${FALCO_REGLES_DEFAUT:-/etc/falco/falco_rules.yaml}" -V "$sortie"
    ;;
  *)
    echo "usage : $0 conventions [fichier-de-valeurs] | moteur" >&2
    exit 2
    ;;
esac
