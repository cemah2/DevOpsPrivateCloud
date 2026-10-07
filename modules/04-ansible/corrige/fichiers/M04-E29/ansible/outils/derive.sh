#!/usr/bin/env bash
# outils/derive.sh — détecte la dérive de configuration du socle (M04-E29)
#
# Usage : outils/derive.sh [-d DOSSIER] [-p PLAYBOOK] [-- ARGUMENTS ansible-playbook…]
#   -d DOSSIER   rapports (défaut rapports/derive) : derive.log, resume.json, junit/*.xml
#   -p PLAYBOOK  défaut playbooks/site.yml
# Lance le playbook en --check --diff, avec des faits FRAIS (pas de cache), et un rapport JUnit
# où chaque tâche « changed » est un cas en échec (JUNIT_FAIL_ON_CHANGE).
# Codes retour :
#   0  conforme  (aucune tâche ne changerait quoi que ce soit)
#   1  dérive    (au moins une tâche changerait quelque chose, aucune erreur)
#   2  erreur    (hôte injoignable, tâche en échec, exécution interrompue, erreur d'Ansible)
#   4  erreur d'usage
# Même outil partout, depuis la racine du projet : CI (job derive), adm01, Semaphore.
# ansible-playbook : $ANSIBLE_PLAYBOOK s'il est défini, sinon « uv run ansible-playbook » si
# le projet uv est présent, sinon celui du PATH (sem01).
set -euo pipefail

ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dossier="rapports/derive"
playbook="playbooks/site.yml"
while getopts ':d:p:h' opt; do
  case "$opt" in
    d) dossier="$OPTARG" ;;
    p) playbook="$OPTARG" ;;
    h) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Usage : $0 [-d DOSSIER] [-p PLAYBOOK] [-- ARGUMENTS…]" >&2; exit 4 ;;
  esac
done
shift $((OPTIND - 1))
[[ -f "$playbook" ]] || { echo "Playbook introuvable : $playbook (lance depuis la racine du projet)" >&2; exit 4; }

if [[ -n "${ANSIBLE_PLAYBOOK:-}" ]]; then
  read -r -a cmd <<<"$ANSIBLE_PLAYBOOK"
elif command -v uv >/dev/null && [[ -f uv.lock ]]; then
  cmd=(uv run ansible-playbook)
else
  cmd=(ansible-playbook)
fi

mkdir -p "$dossier/junit"
rm -f "$dossier"/junit/*.xml "$dossier/derive.log" "$dossier/resume.json"

# Faits frais (le cache de adm01 pourrait masquer une dérive), sortie analysable, JUnit.
export ANSIBLE_CACHE_PLUGIN=memory ANSIBLE_GATHERING=implicit ANSIBLE_NOCOLOR=1
export ANSIBLE_CALLBACKS_ENABLED=ansible.builtin.junit,ansible.posix.timer
export JUNIT_OUTPUT_DIR="$dossier/junit" JUNIT_FAIL_ON_CHANGE=true JUNIT_HIDE_TASK_ARGUMENTS=true

debut="$(date -Iseconds)"
code=0
"${cmd[@]}" "$playbook" --check --diff "$@" >"$dossier/derive.log" 2>&1 || code=$?

rc=0
"$ici/recap-ansible.sh" "$dossier/derive.log" --json "$dossier/resume.json" || rc=$?
case "$rc" in
  0) verdict=conforme; sortie=0 ;;
  1) verdict=derive; sortie=1 ;;
  *) verdict=erreur; sortie=2 ;;
esac
# En --check, ansible-playbook rend 0 même s'il « changerait » des choses. Un code non nul
# avec un récapitulatif propre = erreur d'Ansible lui-même (Vault, syntaxe, inventaire).
if ((code != 0 && sortie < 2)); then verdict=erreur; sortie=2; fi

commit="$(git rev-parse --short HEAD 2>/dev/null || echo inconnu)"
[[ -s "$dossier/resume.json" ]] || echo '{}' >"$dossier/resume.json"
jq --arg verdict "$verdict" --arg debut "$debut" --arg commit "$commit" \
  --arg playbook "$playbook" --argjson code "$code" \
  '. + {verdict: $verdict, debut: $debut, commit: $commit, playbook: $playbook, code_ansible: $code}' \
  "$dossier/resume.json" >"$dossier/resume.json.tmp"
mv "$dossier/resume.json.tmp" "$dossier/resume.json"

echo "Dérive : $verdict (code ansible $code, commit $commit) — rapport dans $dossier/"
exit "$sortie"
