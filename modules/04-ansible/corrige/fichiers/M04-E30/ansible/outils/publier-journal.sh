#!/usr/bin/env bash
# outils/publier-journal.sh — n'affiche un journal Ansible qu'après avoir vérifié qu'il ne contient
# aucun secret Vault du projet (M04-E30)
#
# Usage (jobs CI, depuis la racine du projet) : outils/publier-journal.sh JOURNAL...
# Vérifie les journaux donnés ET les rapports JUnit de rapports/ (ils contiennent les résultats
# des tâches en échec ou « changed ») avec outils/secrets-dans-journal.py.
# Code 0 : tout est propre, les journaux sont affichés. Code 1 : secret trouvé ; seuls les NOMS
# des variables en cause sont affichés, et les fichiers vérifiés sont vidés pour qu'aucun
# artefact ne conserve le secret. Le job échoue.
set -euo pipefail

(($# > 0)) || { echo "Usage : $0 JOURNAL..." >&2; exit 2; }
fichiers=("$@")
if [[ -d rapports ]]; then
  mapfile -t -O "${#fichiers[@]}" fichiers < <(find rapports -type f -name '*.xml' | sort)
fi

if uv run python outils/secrets-dans-journal.py "${fichiers[@]}"; then
  for j in "$@"; do
    echo "===== $j"
    cat "$j"
  done
  exit 0
fi
for f in "${fichiers[@]}"; do
  : >"$f"
  echo "Vidé (secret détecté) : $f" >&2
done
echo "Corrige la tâche en cause (no_log, diff: false), voir RB-041 et M04-E30." >&2
exit 1
