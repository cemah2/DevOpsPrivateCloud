#!/usr/bin/env bash
# mesurer-perf.sh — mesure la durée de playbooks/mesure-perf.yml pour une configuration (M04-E26)
#
# Usage : outils/mesurer-perf.sh [-n N] [-l LIBELLÉ] [-- ARGUMENTS ansible-playbook…]
#   -n N        nombre d'exécutions (défaut 5) ; la première peut être plus lente (connexions)
#   -l LIBELLÉ  nom de la configuration mesurée, repris dans la ligne de résultat
# La configuration mesurée se règle par l'environnement (variables ANSIBLE_…), une à la fois :
#   outils/mesurer-perf.sh -l "projet (référence)"
#   ANSIBLE_FORKS=1 outils/mesurer-perf.sh -l "forks=1"
#   ANSIBLE_PIPELINING=False outils/mesurer-perf.sh -l "sans pipelining"
#   ANSIBLE_SSH_ARGS="-o ControlMaster=no -o ControlPath=none" outils/mesurer-perf.sh -l "sans multiplexage"
#   outils/mesurer-perf.sh -l "faits min" -- -e '{"sous_ensemble": ["min"]}'
#   ANSIBLE_STRATEGY=free outils/mesurer-perf.sh -l "stratégie free"
# Résultat : une ligne de tableau Markdown « | libellé | n | min | médiane | max | » (secondes),
# à coller dans docs/performances.md. Code 1 si une exécution échoue ou change quelque chose.
#
# À lancer depuis la racine du projet. Inventaires : socle + flotte de démonstration (E25),
# modifiables par MESURE_INVENTAIRES.
set -euo pipefail

n=5
libelle="sans libellé"
while getopts ':n:l:h' opt; do
  case "$opt" in
    n) n="$OPTARG" ;;
    l) libelle="$OPTARG" ;;
    h) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Usage : $0 [-n N] [-l LIBELLÉ] [-- ARGUMENTS…]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[[ "$n" =~ ^[1-9][0-9]*$ ]] || { echo "N doit être un entier positif" >&2; exit 2; }
[[ -f playbooks/mesure-perf.yml ]] || { echo "À lancer depuis la racine du projet ansible" >&2; exit 2; }

# Le binaire de l'environnement, sans « uv run » : son temps de démarrage fausserait la mesure.
ansible_playbook="${ANSIBLE_PLAYBOOK:-.venv/bin/ansible-playbook}"
[[ -x "$ansible_playbook" ]] || { echo "Introuvable : $ansible_playbook (uv sync ?)" >&2; exit 2; }
read -r -a inventaires <<<"${MESURE_INVENTAIRES:--i inventories/lab/hosts.yml -i $HOME/m04/e25/flotte-hosts.yml}"

journal="$(mktemp)"
trap 'rm -f "$journal"' EXIT
durees=()
for ((i = 1; i <= n; i++)); do
  debut="$(date +%s.%N)"
  if ! ANSIBLE_NOCOLOR=1 "$ansible_playbook" "${inventaires[@]}" playbooks/mesure-perf.yml "$@" >"$journal" 2>&1; then
    echo "Exécution $i en échec :" >&2
    tail -n 20 "$journal" >&2
    exit 1
  fi
  fin="$(date +%s.%N)"
  # Une mesure qui change quelque chose ne mesure plus la même chose.
  if grep -Eq 'changed=[1-9]' "$journal"; then
    echo "Exécution $i : changed > 0, la charge de mesure n'est plus neutre." >&2
    exit 1
  fi
  durees+=("$(awk -v d="$debut" -v f="$fin" 'BEGIN { printf "%.2f", f - d }')")
  printf '  exécution %d/%d : %s s\n' "$i" "$n" "${durees[-1]}" >&2
done

printf '%s\n' "${durees[@]}" | sort -n | awk -v l="$libelle" '
  { v[NR] = $1 }
  END {
    if (NR % 2) med = v[(NR + 1) / 2]; else med = (v[NR / 2] + v[NR / 2 + 1]) / 2
    printf "| %s | %d | %.1f | %.1f | %.1f |\n", l, NR, v[1], med, v[NR]
  }'
